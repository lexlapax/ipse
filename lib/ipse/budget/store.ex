defmodule Ipse.Budget.Store do
  @moduledoc "Owner-only bounded JSONL reservations under the existing cross-process native lock."
  alias Ipse.Budget.{Ledger, Policy}
  @bytes 33_554_432
  @record_bytes 65_536

  def attach(config, dir, id, fresh, mode \\ :session) do
    with :ok <- Policy.runtime(config) do
      if config[:budget] == nil do
        {:ok, config}
      else
        with {:ok, dir} <- Ipse.WorkspaceContext.canonical_path(dir),
             {:ok, root} <- root(config, dir, id),
             :ok <- ensure_directory(root, fresh and config[:budget_root] == nil),
             {:ok, checkpoint} <- checkpoint(config, root, mode),
             {:ok, _} <-
               transaction(
                 root,
                 config.budget,
                 fn state -> {:read, state} end,
                 fresh and config[:budget_root] == nil,
                 checkpoint
               ) do
          {:ok, config |> Map.put(:budget_root, root) |> Map.put(:budget_checkpoint, checkpoint)}
        end
      end
    end
  rescue
    _ -> {:error, :budget_store_unavailable}
  end

  def transaction(root, policy, fun, create \\ false, checkpoint \\ nil) do
    with :ok <- Policy.validate(policy),
         true <- root?(root),
         :ok <- ensure_directory(root, false),
         :ok <- safe_lock(root, create),
         {:ok, lock} <-
           acquire_lock(path(root, ".lock"), System.monotonic_time(:millisecond) + 1_000) do
      try do
        with :ok <- if(create, do: create(root, policy), else: :ok),
             {:ok, raw} <- read(root),
             bytes = byte_size(raw),
             :ok <- check_prefix(checkpoint, root, policy, raw),
             {:ok, state} <- restore(checkpoint, root, policy, raw) do
          case fun.(state) do
            {:read, result} ->
              with :ok <- pin(checkpoint, raw, bytes, state), do: {:ok, result}

            {:append, event, result} ->
              encoded = Jason.encode!(event) <> "\n"

              with {:ok, next} <- Ledger.apply_event(state, event),
                   true <-
                     byte_size(encoded) <= @record_bytes and bytes + byte_size(encoded) <= @bytes,
                   :ok <- append(root, encoded),
                   :ok <- pin(checkpoint, [raw, encoded], bytes + byte_size(encoded), next) do
                {:ok, result}
              else
                _ -> {:error, :budget_write_refused}
              end

            {:error, _} = error ->
              error
          end
        end
      after
        Ipse.Runner.unlock(lock)
      end
    else
      _ -> {:error, :budget_store_unavailable}
    end
  rescue
    _ -> {:error, :budget_store_unavailable}
  catch
    :exit, _ -> {:error, :budget_store_unavailable}
  end

  def identity(root),
    do: %{
      "session_id" => root["session_id"],
      "state_dir_sha256" => Ipse.Compaction.digest([root["state_dir"]])
    }

  defp checkpoint(_config, _root, :inspect), do: {:ok, nil}

  defp checkpoint(config, root, :session) do
    expected = Ipse.Compaction.digest([identity(root), config.budget])

    if config[:budget_root] == nil do
      table = :ets.new(:ipse_budget_checkpoint, [:set, :public])
      true = :ets.insert(table, {:identity, expected})
      {:ok, table}
    else
      table = config[:budget_checkpoint]

      if is_reference(table) and :ets.lookup(table, :identity) == [{:identity, expected}],
        do: {:ok, table},
        else: {:error, :budget_checkpoint_unavailable}
    end
  end

  defp check_prefix(nil, _, _, _), do: :ok

  defp check_prefix(table, root, policy, raw) do
    with [{:identity, expected}] <- :ets.lookup(table, :identity),
         true <- expected == Ipse.Compaction.digest([identity(root), policy]) do
      case :ets.lookup(table, :prefix) do
        [] ->
          :ok

        [{:prefix, bytes, hash}] when bytes <= byte_size(raw) ->
          if :crypto.hash(:sha256, binary_part(raw, 0, bytes)) == hash,
            do: :ok,
            else: {:error, :budget_prefix_changed}

        _ ->
          {:error, :budget_prefix_changed}
      end
    else
      _ -> {:error, :budget_checkpoint_unavailable}
    end
  end

  defp restore(nil, root, policy, raw) do
    with {:ok, events} <- decode(raw), do: Ledger.restore(events, identity(root), policy)
  end

  defp restore(table, root, policy, raw) do
    case {:ets.lookup(table, :prefix), :ets.lookup(table, :ledger_state)} do
      {[{:prefix, bytes, _}], [{:ledger_state, bytes, state}]} ->
        with {:ok, events} <- decode(binary_part(raw, bytes, byte_size(raw) - bytes)) do
          Enum.reduce_while(events, {:ok, state}, fn event, {:ok, current} ->
            case Ledger.apply_event(current, event) do
              {:ok, next} -> {:cont, {:ok, next}}
              _ -> {:halt, {:error, :invalid_budget_ledger}}
            end
          end)
        end

      _ ->
        restore(nil, root, policy, raw)
    end
  end

  defp pin(nil, _, _, _), do: :ok

  defp pin(table, raw, bytes, state) do
    true =
      :ets.insert(table, [
        {:prefix, bytes, :crypto.hash(:sha256, raw)},
        {:ledger_state, bytes, state}
      ])

    :ok
  end

  defp root(config, dir, id) do
    case config[:budget_root] do
      nil ->
        {:ok, %{"state_dir" => dir, "session_id" => id}}

      value ->
        origin = config[:delegation_origin] || %{}
        expected = Path.join([value["state_dir"] || "", "subagents", value["session_id"] || ""])

        if root?(value) and dir == expected and origin["parent_session_id"] == value["session_id"] do
          {:ok, value}
        else
          {:error, :budget_scope_mismatch}
        end
    end
  end

  defp root?(root) do
    is_map(root) and Enum.sort(Map.keys(root)) == ~w(session_id state_dir) and
      is_binary(root["state_dir"]) and Path.type(root["state_dir"]) == :absolute and
      byte_size(root["state_dir"]) <= 4096 and not String.contains?(root["state_dir"], <<0>>) and
      is_binary(root["session_id"]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, root["session_id"])
  end

  defp directory(root), do: Path.join(root["state_dir"], "budgets")
  defp path(root, suffix), do: Path.join(directory(root), root["session_id"] <> suffix)

  defp ensure_directory(root, create) do
    directory = directory(root)

    if create do
      case File.mkdir(directory) do
        :ok -> File.chmod!(directory, 0o700)
        {:error, :eexist} -> :ok
      end
    end

    with {:ok, stat} <- File.lstat(directory),
         true <- stat.type == :directory,
         true <- Bitwise.band(stat.mode, 0o077) == 0,
         {:ok, canonical} <- Ipse.WorkspaceContext.canonical_path(directory),
         true <- canonical == directory do
      :ok
    else
      _ -> {:error, :unsafe_budget_directory}
    end
  end

  defp acquire_lock(path, deadline) do
    case Ipse.Runner.lock(path) do
      {:ok, lock} ->
        {:ok, lock}

      error ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          acquire_lock(path, deadline)
        else
          error
        end
    end
  end

  defp safe_lock(root, create) do
    case File.lstat(path(root, ".lock")) do
      {:error, :enoent} when create -> :ok
      {:ok, stat} -> if safe_file?(stat), do: :ok, else: {:error, :unsafe_budget_lock}
      _ -> {:error, :unsafe_budget_lock}
    end
  end

  defp safe_file?(stat),
    do: stat.type == :regular and stat.links == 1 and Bitwise.band(stat.mode, 0o077) == 0

  defp create(root, policy) do
    data = Jason.encode!(Ledger.header(identity(root), policy)) <> "\n"

    with true <- byte_size(data) <= @record_bytes,
         {:ok, file} <-
           :file.open(String.to_charlist(path(root, ".jsonl")), [
             :write,
             :exclusive,
             :binary,
             :raw
           ]) do
      try do
        with :ok <- File.chmod(path(root, ".jsonl"), 0o600),
             :ok <- :file.write(file, data),
             do: :file.sync(file)
      after
        :file.close(file)
      end
    else
      _ -> {:error, :budget_create_refused}
    end
  end

  defp read(root) do
    with {:ok, stat} <- File.lstat(path(root, ".jsonl")),
         true <- safe_file?(stat),
         {:ok, file} <-
           :file.open(String.to_charlist(path(root, ".jsonl")), [:read, :binary, :raw]) do
      try do
        with {:ok, raw} <- :file.read(file, @bytes + 1),
             true <- byte_size(raw) <= @bytes and String.ends_with?(raw, "\n") do
          {:ok, raw}
        else
          _ -> {:error, :invalid_budget_ledger}
        end
      after
        :file.close(file)
      end
    else
      _ -> {:error, :budget_store_unavailable}
    end
  end

  defp decode(raw) do
    deadline = System.monotonic_time(:millisecond) + 5_000

    raw
    |> String.split("\n")
    |> Enum.drop(-1)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, events} ->
      with true <- System.monotonic_time(:millisecond) <= deadline,
           {:ok, event} <- Ipse.Extensions.Manifest.decode_json(line, @record_bytes),
           true <- is_map(event) do
        {:cont, {:ok, [event | events]}}
      else
        _ -> {:halt, {:error, :invalid_budget_ledger}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      error -> error
    end
  end

  defp append(root, data) do
    with {:ok, stat} <- File.lstat(path(root, ".jsonl")),
         true <- safe_file?(stat),
         {:ok, file} <-
           :file.open(String.to_charlist(path(root, ".jsonl")), [:append, :binary, :raw]) do
      try do
        with :ok <- :file.write(file, data), do: :file.sync(file)
      after
        :file.close(file)
      end
    else
      _ -> {:error, :budget_write_refused}
    end
  end
end
