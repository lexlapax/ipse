defmodule Ipse.Session.StoredSources do
  @moduledoc """
  Read original, inactive Session sources under their retained ownership locks.

  The directory is selected by the consuming Session, never by a worker proof.
  Active sources in other Sessions refuse promptly. Copies, legacy origins,
  partial tails and different project scopes cannot supply current evidence.
  The callback retains ownership; its result is historical after return and
  must be revalidated for later delivery or inference.
  """
  alias Ipse.{Journal, Runner}
  alias Ipse.Journal.SourceOrigin
  alias Ipse.Session.{Saved, SourceIndex, SourceWindow}
  @error {:error, :collection_source_refused}
  @proof_limit 128
  @snapshot_budget {__MODULE__, :snapshot_budget}

  def with_verified(context, intent, proofs, fun) when is_function(fun, 1) do
    with_sources(Map.put(context, :stored_source_resolution, :strict), intent, proofs, fun)
  end

  @doc "Read bounded historical proof statuses once per original Session; grants no live lease."
  def snapshot(context, proofs) do
    with true <- is_list(proofs) and length(proofs) in 1..@proof_limit,
         true <-
           Enum.all?(proofs, &match?({:ok, _}, Ipse.Extension.ManagedRecipe.source_identity(&1))),
         {:ok, limits} <- Journal.normalize_limits(context.config[:journal]) do
      prior = Process.get(@snapshot_budget)
      Process.put(@snapshot_budget, limits["max_bytes"])

      try do
        statuses =
          proofs
          |> Enum.uniq()
          |> Enum.group_by(& &1["session_id"])
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.reduce(%{}, fn {id, group}, acc ->
            rows =
              if id == context.session_id do
                Enum.map(group, fn proof ->
                  case local(context, nil, [proof]) do
                    {:ok, [checked]} -> checked
                    _ -> unavailable(proof)
                  end
                end)
              else
                case with_sources(
                       Map.put(context, :stored_source_resolution, :partial),
                       nil,
                       group,
                       fn checked -> {:ok, checked} end
                     ) do
                  {:ok, checked} -> checked
                  _ -> Enum.map(group, &unavailable/1)
                end
              end

            Enum.reduce(rows, acc, fn row, current ->
              Map.put(current, Ipse.JSON.digest([row["proof"]]), row["unavailable"] != true)
            end)
          end)

        {:ok, statuses}
      after
        if is_nil(prior),
          do: Process.delete(@snapshot_budget),
          else: Process.put(@snapshot_budget, prior)
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp with_sources(context, intent, proofs, fun) do
    with true <- is_list(proofs) and length(proofs) in 1..@proof_limit,
         true <- length(Enum.uniq(proofs)) == length(proofs),
         true <-
           Enum.all?(proofs, &match?({:ok, _}, Ipse.Extension.ManagedRecipe.source_identity(&1))) do
      proofs
      |> Enum.group_by(& &1["session_id"])
      |> Enum.sort_by(&elem(&1, 0))
      |> with_sessions(context, intent, [], fn verified ->
        fun.(Enum.map(proofs, fn proof -> Enum.find(verified, &(&1["proof"] === proof)) end))
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    :exit, _ -> @error
  end

  defp with_sessions([], _, _, verified, fun), do: fun.(verified)

  defp with_sessions([{id, proofs} | rest], %{session_id: id} = c, i, verified, fun) do
    with {:ok, current} <- local(c, i, proofs) do
      result = with_sessions(rest, c, i, current ++ verified, fun)

      case local(c, i, proofs) do
        {:ok, ^current} -> result
        _ -> @error
      end
    end
  end

  defp with_sessions([{id, proofs} | rest], c, i, verified, fun) do
    path = Path.join(c.history_dir, id <> ".jsonl")
    lock_path = Path.join(c.history_dir, id <> ".lock")

    with {:ok, before_lock} <- File.lstat(lock_path),
         true <- protected?(before_lock),
         {:ok, journal} <- File.lstat(path),
         true <- protected?(journal) and journal.uid == before_lock.uid,
         {:ok, lock} <- Runner.lock_source(lock_path) do
      monitor = :erlang.monitor(:port, lock)

      result =
        try do
          with true <- lock_live?(lock, monitor),
               true <- same_lock?(lock_path, before_lock),
               {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
            try do
              with {:ok, info} <- :file.read_file_info(file),
                   {:ok, budgeted} <- budget(c, info),
                   {:ok, stats} <- Journal.scan_file(file, c.config[:journal], :load),
                   true <- stats.tail == :none,
                   metadata = (List.first(stats.events) || %{})["metadata"],
                   {:ok, origin} when is_map(origin) <- SourceOrigin.recorded(metadata, id),
                   :ok <- SourceOrigin.check(file, path, id, metadata),
                   true <- project?(metadata, c),
                   {:ok, saved} <- Saved.restore(stats.events, id),
                   :ok <- SourceWindow.validate_sources(c.history_dir, id, stats.events),
                   {:ok, current} <-
                     resolve(saved.source_window.index, proofs, c[:stored_source_resolution]),
                   true <- lock_live?(lock, monitor) do
                result = with_sessions(rest, budgeted, i, current ++ verified, fun)

                with :ok <- SourceOrigin.check(file, path, id, metadata),
                     true <- unchanged?(file, info),
                     true <- same_lock?(lock_path, before_lock),
                     true <- lock_live?(lock, monitor) do
                  result
                else
                  _ -> @error
                end
              else
                _ -> @error
              end
            after
              :file.close(file)
            end
          else
            _ -> @error
          end
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      try do
        live = lock_live?(lock, monitor)

        case Runner.unlock(lock) do
          :ok when live -> result
          _ -> @error
        end
      after
        Process.demonitor(monitor, [:flush])
      end
    else
      _ -> @error
    end
  end

  defp local(c, i, proofs) do
    request =
      case c[:source_binding] do
        nil -> {:extension_stored_sources, c.job_ref, i, proofs}
        binding -> {:managed_sources, c.job_ref, binding, proofs}
      end

    GenServer.call(c.owner, request, 5000)
  end

  defp budget(c, info) do
    with {:ok, limits} <- Journal.normalize_limits(c.config[:journal]),
         bytes = Map.get(c, :stored_source_bytes, 0) + File.Stat.from_record(info).size,
         true <- bytes <= limits["max_bytes"],
         :ok <- charge_snapshot(File.Stat.from_record(info).size) do
      {:ok, Map.put(c, :stored_source_bytes, bytes)}
    else
      _ -> @error
    end
  end

  defp charge_snapshot(bytes) do
    case Process.get(@snapshot_budget) do
      nil ->
        :ok

      remaining when is_integer(remaining) and remaining >= bytes ->
        Process.put(@snapshot_budget, remaining - bytes)
        :ok

      _ ->
        @error
    end
  end

  defp unavailable(proof), do: %{"proof" => proof, "unavailable" => true}

  defp resolve(index, proofs, :partial) do
    {:ok,
     Enum.map(proofs, fn proof ->
       case SourceIndex.revalidate_stored(index, proof) do
         {:ok, checked} -> checked
         _ -> unavailable(proof)
       end
     end)}
  end

  defp resolve(index, proofs, _) do
    Enum.reduce_while(proofs, {:ok, []}, fn proof, {:ok, acc} ->
      case SourceIndex.revalidate_stored(index, proof) do
        {:ok, checked} -> {:cont, {:ok, acc ++ [checked]}}
        _ -> {:halt, @error}
      end
    end)
  end

  defp project?(metadata, c) do
    source = metadata["semantic_admission"]
    consumer = c.config[:semantic_admission]

    Ipse.Extension.SemanticAdmission.valid?(source, nil) and
      get_in(source, ["pin", "project_id"]) == get_in(consumer, ["pin", "project_id"]) and
      get_in(source, ["pin", "namespace"]) == get_in(consumer, ["pin", "namespace"])
  end

  defp protected?(stat),
    do: stat.type == :regular and stat.links == 1 and Bitwise.band(stat.mode, 0o077) == 0

  defp same_lock?(path, before) do
    case File.lstat(path) do
      {:ok, after_stat} -> protected?(after_stat) and identity(after_stat) == identity(before)
      _ -> false
    end
  end

  defp unchanged?(file, before) do
    case :file.read_file_info(file) do
      {:ok, after_info} ->
        fields = ~w(size mtime ctime mode links major_device minor_device inode uid gid)a

        Map.take(File.Stat.from_record(before), fields) ==
          Map.take(File.Stat.from_record(after_info), fields)

      _ ->
        false
    end
  end

  defp identity(stat), do: {stat.major_device, stat.minor_device, stat.inode, stat.uid}

  defp lock_live?(lock, monitor) do
    receive do
      {:DOWN, ^monitor, :port, ^lock, _} -> false
      {^lock, {:exit_status, _}} -> false
      {:EXIT, ^lock, _} -> false
    after
      0 -> Port.info(lock, :connected) == {:connected, self()}
    end
  rescue
    _ -> false
  end
end
