defmodule Ipse.Session.StoredSources do
  @moduledoc """
  Read original, inactive Session sources under their retained ownership locks.

  The directory is selected by the consuming Session, never by a worker proof.
  Active sources in other Sessions refuse promptly. Copies, legacy origins,
  partial tails and different project scopes cannot supply current evidence.
  The callback retains ownership; its result is historical after return and
  must be revalidated for later delivery or inference.
  """
  alias Ipse.{JSON, Journal, Runner}
  alias Ipse.Journal.SourceOrigin
  alias Ipse.Session.{Saved, SourceIndex, SourceWindow}
  @error {:error, :collection_source_refused}
  @proof_limit 128
  @snapshot_budget {__MODULE__, :snapshot_budget}
  @share_slot {__MODULE__, :shareable_source}

  def with_verified(context, intent, proofs, fun) when is_function(fun, 1) do
    with_sources(Map.put(context, :stored_source_resolution, :strict), intent, proofs, fun)
  end

  @doc "Retain one inactive original source with a private, same-owner transferable lease."
  def with_shareable_verified(context, proof, fun) when is_map(context) and is_function(fun, 2) do
    with_shareable_verified_many(context, [proof], fn [source], token -> fun.(source, token) end)
  end

  def with_shareable_verified(_, _, _), do: @error

  @doc "Retain exact proofs from one inactive original Session under one transferable lease."
  def with_shareable_verified_many(context, proofs, fun)
      when is_map(context) and is_list(proofs) and is_function(fun, 2) do
    with [first | _] <- proofs,
         true <- is_map(first) and first["session_id"] != context[:session_id],
         true <- Enum.all?(proofs, &(is_map(&1) and &1["session_id"] === first["session_id"])) do
      with_shareable_groups(context, proofs, fn sources, tokens ->
        case tokens do
          [%{session_id: _, token: token}] -> fun.(sources, token)
          _ -> @error
        end
      end)
    else
      _ -> @error
    end
  end

  def with_shareable_verified_many(_, _, _), do: @error

  @doc "Retain exact proofs from inactive original Sessions under transferable leases."
  def with_shareable_groups(context, proofs, fun)
      when is_map(context) and is_list(proofs) and is_function(fun, 2) do
    with true <- proofs != [],
         true <- Enum.all?(proofs, &(is_map(&1) and &1["session_id"] != context[:session_id])),
         nil <- Process.get(@share_slot) do
      context =
        context |> Map.put(:stored_source_resolution, :strict) |> Map.put(:shareable_source, true)

      Process.put(@share_slot, %{})

      try do
        with_sources(context, nil, proofs, fn sources ->
          shares = Process.get(@share_slot)
          ids = proofs |> Enum.map(& &1["session_id"]) |> Enum.uniq() |> Enum.sort()

          with true <- is_map(shares) and map_size(shares) == length(ids),
               true <- Enum.all?(shares, fn {_, share} -> share.phase == :ready end) do
            tokens =
              Enum.map(ids, fn id ->
                {token, share} = Enum.find(shares, fn {_, share} -> share.session_id == id end)
                bound = Enum.filter(sources, &(&1["proof"]["session_id"] === id))
                put_share(token, Map.put(share, :verified_sources, bound))
                %{session_id: id, token: token}
              end)

            fun.(sources, tokens)
          else
            _ -> @error
          end
        end)
      after
        Process.delete(@share_slot)
      end
    else
      _ -> @error
    end
  end

  def with_shareable_groups(_, _, _), do: @error

  @doc "Verify active proofs and retain inactive originals through one callback."
  def with_shareable_union(context, intent, proofs, fun)
      when is_map(context) and is_list(proofs) and is_function(fun, 3) do
    with true <- length(proofs) in 1..@proof_limit,
         true <- length(Enum.uniq(proofs)) == length(proofs),
         true <-
           Enum.all?(proofs, &match?({:ok, _}, Ipse.Extension.ManagedRecipe.source_identity(&1))) do
      {active, inactive} = Enum.split_with(proofs, &(&1["session_id"] === context[:session_id]))

      combine = fn active_sources, inactive_sources, tokens ->
        index = Map.new(active_sources ++ inactive_sources, &{JSON.digest([&1["proof"]]), &1})
        ordered = Enum.map(proofs, &Map.fetch!(index, JSON.digest([&1])))
        fun.(ordered, tokens, active != [])
      end

      inactive_scope = fn active_sources ->
        if inactive == [] do
          combine.(active_sources, [], [])
        else
          with_shareable_groups(context, inactive, fn sources, tokens ->
            combine.(active_sources, sources, tokens)
          end)
        end
      end

      if active == [] do
        inactive_scope.([])
      else
        with_verified(context, intent, active, inactive_scope)
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    :exit, _ -> @error
  end

  def with_shareable_union(_, _, _, _), do: @error

  @doc false
  def share_identity(token) do
    case share(token) do
      %{owner: owner, port: port, identity: identity, phase: :ready}
      when owner == self() ->
        if Port.info(port, :connected) == {:connected, owner}, do: {:ok, identity}, else: @error

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  @doc false
  # An owner-bound lease only attests the exact proofs resolved under that lock;
  # it is not itself authority to display or publish those proofs.
  def share_verified_identity(token, proofs) when is_list(proofs) do
    with %{owner: owner, session_id: session_id, verified_sources: sources, phase: :ready} <-
           share(token),
         true <- owner == self() and proofs != [],
         true <- Enum.map(sources, & &1["proof"]) === proofs,
         {:ok, identity} <- share_identity(token) do
      {:ok, %{session_id: session_id, identity: identity, proofs_sha256: JSON.digest(proofs)}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def share_verified_identity(_, _), do: @error

  @doc false
  def share_export(token, operation, recipient, deadline) do
    case share(token) do
      %{owner: owner, port: port, phase: :ready} = state when owner == self() ->
        put_share(token, %{state | phase: :poisoned})

        if Runner.session_share_export(port, 1, 1, operation, recipient, deadline) == :ok do
          put_share(token, %{state | phase: :shared, operation: operation})
          :ok
        else
          @error
        end

      _ ->
        @error
    end
  end

  @doc false
  def share_settle(token, operation, deadline) do
    case share(token) do
      %{owner: owner, port: port, phase: :shared, operation: ^operation} = state
      when owner == self() ->
        put_share(token, %{state | phase: :poisoned})

        if Runner.session_share_settle(port, 2, 1, operation, deadline) == :ok do
          put_share(token, %{state | phase: :settled})
          :ok
        else
          @error
        end

      _ ->
        @error
    end
  end

  defp share(token), do: Map.get(Process.get(@share_slot) || %{}, token)

  defp put_share(token, state),
    do: Process.put(@share_slot, Map.put(Process.get(@share_slot), token, state))

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
         {:ok, lock} <- source_lock(c, lock_path) do
      monitor = :erlang.monitor(:port, lock)

      result =
        try do
          with :ok <- prepare_share(c, lock, before_lock, id),
               true <- lock_live?(lock, monitor),
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

        entry = if c[:shareable_source], do: share_by_port(lock), else: nil

        share_ok =
          c[:shareable_source] != true or
            match?({_, %{phase: phase}} when phase in [:ready, :settled], entry)

        if match?({_, _}, entry) do
          {token, _} = entry
          Process.put(@share_slot, Map.delete(Process.get(@share_slot), token))
        end

        unlocked =
          if c[:shareable_source],
            do: Runner.unlock_export_candidate(lock),
            else: Runner.unlock(lock)

        case unlocked do
          :ok when live and share_ok -> result
          _ -> @error
        end
      after
        Process.demonitor(monitor, [:flush])
      end
    else
      _ -> @error
    end
  end

  defp source_lock(%{shareable_source: true}, path), do: Runner.protected_share_resume_lock(path)
  defp source_lock(_, path), do: Runner.lock_source(path)

  defp prepare_share(%{shareable_source: true}, port, before, session_id) do
    deadline = System.monotonic_time(:millisecond) + 5_000

    with shares when is_map(shares) <- Process.get(@share_slot),
         {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
         {:ok, %{device: device, inode: inode}} <-
           Runner.session_header_lock_identity(port, deadline),
         true <- device == before.major_device and inode == before.inode do
      token = make_ref()

      put_share(token, %{
        session_id: session_id,
        owner: self(),
        port: port,
        identity: %{pid: pid, device: device, inode: inode},
        phase: :ready,
        operation: nil
      })

      :ok
    else
      _ -> @error
    end
  end

  defp prepare_share(_, _, _, _), do: :ok

  defp share_by_port(port) do
    Enum.find(Process.get(@share_slot) || %{}, fn {_, state} -> state.port === port end)
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
