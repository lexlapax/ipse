defmodule Ipse.InferenceSlots.Store do
  @moduledoc false
  alias Ipse.{JSON, Runner.Transaction, InferenceSlots.Ledger}
  import Bitwise, only: [band: 2]
  @error {:error, :service_state_unavailable}
  @limit 1_048_576
  @bytes 65_536

  def context(home, cwd, guard \\ nil) do
    with {:ok, uid} <- Ipse.Runner.protected_current_uid(),
         true <- path?(home) and path?(cwd),
         {:ok, ^home} <- Ipse.Workspace.canonical_path(home),
         {:ok, ^cwd} <- Ipse.Workspace.canonical_path(cwd),
         true <- not overlap?(home, cwd),
         :ok <- ancestors(home, uid),
         :ok <- private_directory(home, uid),
         root = Path.join(home, "inference-services"),
         :ok <- create_directory(root, uid),
         :ok <- layout(root, uid, cwd, guard) do
      {:ok, %{root: root, uid: uid, cwd: cwd}}
    else
      {:error, :transaction_filesystem_unsupported} ->
        {:error, :service_filesystem_unsupported}

      {:error, :transaction_capacity} ->
        {:error, :service_capacity}

      {:error, reason}
      when reason in [:service_wait_timeout, :service_cancelled, :service_owner_lost] ->
        {:error, reason}

      {:unknown, _} ->
        {:unknown, :service_state_unconfirmed}

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  # Qualify the finite filesystem before constructing the fixed empty lease tree.
  # A partially constructed tree is visible recovery work, never guessed complete.
  defp layout(root, uid, cwd, guard) do
    if complete_layout?(root, uid) do
      :ok
    else
      with :ok <- safe_lock(Path.join(root, ".lock"), uid),
           {:ok, cap} <-
             acquire(Path.join(root, ".lock"), cwd, guard) do
        result =
          if complete_layout?(root, uid) do
            :ok
          else
            with :ok <- allowed(guard, :effect),
                 {:ok, names} <- File.ls(root),
                 true <- Enum.all?(names, &(&1 in ~w(.lock .writer.lock))),
                 :ok <- Transaction.quota(cap, :flat, @limit),
                 :ok <- create_directory(Path.join(root, "objects"), uid),
                 :ok <- create_directory(Path.join(root, "manifests"), uid),
                 :ok <- create_slots(root, uid) do
              :ok
            else
              {:error, _} = error -> error
              {:unknown, _} = unknown -> unknown
              _ -> {:error, :service_bootstrap_incomplete}
            end
          end

        case {Transaction.check(cap), Transaction.release(cap)} do
          {:ok, :ok} -> result
          _ -> {:unknown, :service_state_unconfirmed}
        end
      end
    end
  end

  defp complete_layout?(root, uid) do
    Enum.all?(["objects", "manifests" | Enum.map(0..7, &"objects/slot-#{&1}")], fn name ->
      private_directory(Path.join(root, name), uid) == :ok
    end)
  end

  def transaction(context, fun, guard \\ nil) do
    with :ok <- namespace(context),
         :ok <- safe_lock(Path.join(context.root, ".lock"), context.uid),
         {:ok, cap} <-
           acquire(Path.join(context.root, ".lock"), context.cwd, guard) do
      result =
        try do
          with {:ok, state} <- read(context, cap),
               :ok <- reclaim(context, cap),
               :ok <- Transaction.quota(cap, :collection, @limit),
               :ok <- allowed(guard, :effect) do
            case fun.(state) do
              {:read, value} ->
                with :ok <- Transaction.check(cap), do: {:ok, value}

              {:ok, next, value} ->
                with :ok <- write(cap, next), do: {:ok, value}

              {:error, _} = error ->
                error

              _ ->
                @error
            end
          end
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      case {Transaction.check(cap), Transaction.release(cap)} do
        {:ok, :ok} -> normalize(result)
        _ -> {:unknown, :service_state_unconfirmed}
      end
    else
      result -> normalize(result)
    end
  end

  # Only the acquire refusal proves that this transaction has not begun any
  # ledger IO. Never retry normalized errors from read, reclaim or publication.
  defp acquire(path, cwd, guard) do
    with :ok <- allowed(guard, :acquire) do
      case Transaction.acquire(path, cwd: cwd, timeout_ms: 5_000) do
        {:error, :transaction_busy} when is_function(guard) ->
          Process.sleep(20)
          acquire(path, cwd, guard)

        result ->
          result
      end
    end
  end

  defp allowed(nil, _), do: :ok
  defp allowed(guard, phase) when is_function(guard, 1), do: guard.(phase)
  defp allowed(guard, _), do: guard.()

  def acquire_service(context, slot, timeout) when is_integer(slot) and slot in 0..7 do
    with :ok <- namespace(context),
         path = Path.join([context.root, "objects", "slot-#{slot}", ".lock"]),
         :ok <- safe_lock(path, context.uid) do
      Transaction.acquire(path, cwd: context.cwd, timeout_ms: timeout)
    end
  end

  defp read(context, cap) do
    case File.lstat(Path.join(context.root, "control.json")) do
      {:error, :enoent} ->
        {:ok, Ledger.empty()}

      {:ok, stat} ->
        with true <- safe_file?(stat, context.uid) and stat.size in 1..@bytes,
             {:ok, bytes} <- Transaction.read(cap, ".", "control.json", @bytes),
             {:ok, state} <- JSON.decode_unique(bytes, 12),
             true <- Ledger.valid?(state),
             do: {:ok, state},
             else: (_ -> @error)

      _ ->
        @error
    end
  end

  defp write(cap, state) do
    with true <- Ledger.valid?(state),
         bytes = Jason.encode!(state),
         {:ok, ^state} <- JSON.decode_unique(bytes, 12),
         :ok <- Transaction.preflight(cap, [byte_size(bytes)]),
         pending = ".pending-" <> Ipse.Usage.id(),
         :ok <- Transaction.stage(cap, ".", [{pending, bytes}]),
         :ok <- Transaction.switch(cap, pending, "control.json"),
         :ok <- Transaction.check(cap) do
      :ok
    else
      {:error, reason}
      when reason in [:transaction_capacity, :transaction_filesystem_unsupported] ->
        {:error, reason}

      _ ->
        {:unknown, :service_state_unconfirmed}
    end
  end

  defp reclaim(context, cap) do
    with {:ok, names} <- File.ls(context.root),
         names = Enum.filter(names, &pending?/1),
         true <- length(names) <= 64 do
      if names == [], do: :ok, else: Transaction.reclaim(cap, ".", names)
    else
      _ -> @error
    end
  end

  defp namespace(context) do
    with :ok <- ancestors(context.root, context.uid),
         :ok <- private_directory(context.root, context.uid),
         {:ok, names} <- File.ls(context.root),
         true <-
           Enum.all?(
             names,
             &(&1 in ~w(.lock .writer.lock control.json objects manifests) or pending?(&1))
           ),
         :ok <- private_directory(Path.join(context.root, "objects"), context.uid),
         :ok <- private_directory(Path.join(context.root, "manifests"), context.uid),
         {:ok, objects} <- File.ls(Path.join(context.root, "objects")),
         true <-
           Enum.all?(
             objects,
             &(&1 == ".writer.lock" or &1 in Enum.map(0..7, fn n -> "slot-#{n}" end))
           ),
         {:ok, manifests} <- File.ls(Path.join(context.root, "manifests")),
         true <- Enum.all?(manifests, &(&1 == ".writer.lock")),
         true <- Enum.all?(0..7, fn n -> slot_safe?(context, n) end) do
      :ok
    else
      _ -> @error
    end
  end

  defp slot_safe?(context, n) do
    path = Path.join([context.root, "objects", "slot-#{n}"])

    with :ok <- private_directory(path, context.uid),
         {:ok, names} <- File.ls(path),
         true <- Enum.all?(names, &(&1 == ".lock")),
         :ok <- safe_lock(Path.join(path, ".lock"), context.uid),
         do: true,
         else: (_ -> false)
  end

  defp create_slots(root, uid) do
    Enum.reduce_while(0..7, :ok, fn n, :ok ->
      case create_directory(Path.join([root, "objects", "slot-#{n}"]), uid) do
        :ok -> {:cont, :ok}
        _ -> {:halt, @error}
      end
    end)
  end

  defp create_directory(path, uid) do
    result =
      case File.mkdir(path) do
        :ok ->
          with :ok <- File.chmod(path, 0o700),
               do: Ipse.Runner.protected_sync_directory(Path.dirname(path))

        {:error, :eexist} ->
          :ok

        _ ->
          @error
      end

    with :ok <- result, do: private_directory(path, uid)
  end

  defp private_directory(path, uid) do
    case File.lstat(path) do
      {:ok, %{type: :directory, uid: ^uid, mode: mode}} ->
        if band(mode, 0o7777) == 0o700, do: :ok, else: @error

      _ ->
        @error
    end
  end

  defp safe_lock(path, uid) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, stat} -> if safe_file?(stat, uid) and stat.size == 0, do: :ok, else: @error
      _ -> @error
    end
  end

  defp safe_file?(stat, uid),
    do:
      stat.type == :regular and stat.uid == uid and stat.links == 1 and
        band(stat.mode, 0o7777) == 0o600

  defp ancestors(path, uid) do
    root_uid = File.lstat!("/").uid

    Enum.reduce_while(Path.split(path), "", fn part, parent ->
      current = if parent == "", do: part, else: Path.join(parent, part)

      case File.lstat(current) do
        {:ok, %{type: :directory, uid: owner, mode: mode}} when owner in [0, root_uid, uid] ->
          if band(mode, 0o022) == 0 or (owner in [0, root_uid] and band(mode, 0o1000) != 0),
            do: {:cont, current},
            else: {:halt, :unsafe}

        _ ->
          {:halt, :unsafe}
      end
    end)
    |> case do
      ^path -> :ok
      _ -> @error
    end
  end

  defp normalize({:error, :transaction_busy}), do: {:error, :service_busy}
  defp normalize({:error, :transaction_capacity}), do: {:error, :service_capacity}

  defp normalize({:error, :transaction_filesystem_unsupported}),
    do: {:error, :service_filesystem_unsupported}

  defp normalize({:ok, _} = result), do: result
  defp normalize({:error, _} = result), do: result
  defp normalize(_), do: {:unknown, :service_state_unconfirmed}

  defp path?(s),
    do:
      is_binary(s) and String.valid?(s) and byte_size(s) in 1..4096 and Path.expand(s) == s and
        not String.contains?(s, <<0>>)

  defp pending?(s), do: Regex.match?(~r/\A\.pending-[0-9a-f]{32}\z/, s)

  defp overlap?(a, b),
    do: a == b or String.starts_with?(a, b <> "/") or String.starts_with?(b, a <> "/")
end
