defmodule Ipse.Journal.Writer do
  @moduledoc "Session-owned durable appends; validates before linking and monitors normal owner exit."
  use GenServer
  alias Ipse.Journal

  def start(directory, id, owner, policy \\ nil, lock_mode \\ :legacy)

  def start(directory, id, owner, policy, lock_mode)
      when is_binary(directory) and is_binary(id) and owner == self() and
             lock_mode in [:legacy, :header_v1, :resume_v1, :header_share_v2, :resume_share_v2] do
    case GenServer.start(__MODULE__, {directory, id, owner, policy, lock_mode}) do
      {:ok, writer} ->
        Process.link(writer)
        {:ok, writer}

      error ->
        error
    end
  end

  def start(_, _, _, _, _), do: {:error, :journal_unavailable}

  def append(writer, event), do: call(writer, {:append, :plain, event})
  def append_observed(writer, event), do: call(writer, {:append, :observed, event})
  def append_with_source(writer, event), do: call(writer, {:append, :source, event})

  @doc false
  def install_source_window(writer, window), do: call(writer, {:source_window_install, window})
  @doc false
  def source_query(writer, request), do: call(writer, {:source_query, request})
  @doc false
  def ensure_source_window(writer), do: call(writer, :source_window_ensure)

  @doc "Reserves JSONL bytes, including newlines, and events while retaining quota-marker headroom."
  def reserve(writer, capacity), do: call(writer, {:reserve, capacity})

  @doc "Appends one plain record against an owner-only, writer-local reservation token."
  def append_reserved(writer, token, event),
    do: call(writer, {:append_reserved, token, :plain, event})

  def append_reserved_observed(writer, token, event),
    do: call(writer, {:append_reserved, token, :observed, event})

  @doc "Releases unused reserved capacity; already appended bytes and events remain charged."
  def release(writer, token), do: call(writer, {:release, token})

  def close(writer), do: call(writer, :close)

  @doc false
  def request_share_barrier(writer, operation, job_ref, owner_generation)
      when is_pid(writer) and is_binary(operation) and byte_size(operation) == 16 and
             is_reference(job_ref) and is_reference(owner_generation) do
    :gen_server.send_request(writer, {:share_barrier, operation, job_ref, owner_generation})
  end

  @doc false
  def request_share_barrier_sources(writer, operation, job_ref, owner_generation, proofs)
      when is_pid(writer) and is_binary(operation) and byte_size(operation) == 16 and
             is_reference(job_ref) and is_reference(owner_generation) and is_list(proofs),
      do:
        :gen_server.send_request(
          writer,
          {:share_barrier_sources, operation, job_ref, owner_generation, proofs}
        )

  @doc false
  def request_share_barrier_display_sources(
        writer,
        operation,
        job_ref,
        owner_generation,
        proofs,
        inactive_ids
      )
      when is_pid(writer) and is_binary(operation) and byte_size(operation) == 16 and
             is_reference(job_ref) and is_reference(owner_generation) and is_list(proofs) and
             is_list(inactive_ids),
      do:
        :gen_server.send_request(
          writer,
          {:share_barrier_display_sources, operation, job_ref, owner_generation, proofs,
           inactive_ids}
        )

  @doc false
  def request_share_barrier_display_sources(
        writer,
        operation,
        job_ref,
        owner_generation,
        proofs,
        inactive_ids,
        %{directory: directory, ids: journal_ids} = journals
      )
      when is_pid(writer) and is_binary(operation) and byte_size(operation) == 16 and
             is_reference(job_ref) and is_reference(owner_generation) and is_list(proofs) and
             is_list(inactive_ids) and is_binary(directory) and is_list(journal_ids),
      do:
        :gen_server.send_request(
          writer,
          {:share_barrier_approval_sources, operation, job_ref, owner_generation, proofs,
           inactive_ids, journals}
        )

  @doc false
  def thaw_share_barrier(writer, token, operation),
    do: call(writer, {:share_thaw, token, operation})

  @doc false
  def check_share_barrier(writer, token, operation),
    do: call(writer, {:share_check, token, operation})

  @doc false
  def request_share_control_open(writer, token, operation, deadline),
    do: :gen_server.send_request(writer, {:share_control_open, token, operation, deadline})

  @doc false
  def request_share_control_transfer(writer, token, operation, recipient, name, secret, deadline),
    do:
      :gen_server.send_request(
        writer,
        {:share_control_transfer, token, operation, recipient, name, secret, deadline}
      )

  @doc false
  def request_share_control_close(writer, token, operation),
    do: :gen_server.send_request(writer, {:share_control_close, token, operation})

  @doc false
  def request_share_control_prepare_close(writer, token, operation),
    do: :gen_server.send_request(writer, {:share_control_prepare_close, token, operation})

  @doc false
  def append_inactive(directory, id, event, mode)
      when is_map(event) and mode in [:plain, :observed, :source] do
    Ipse.Session.Resources.file_effect(fn ->
      with {:ok, state} <- open(directory, id, self(), nil, :legacy) do
        try do
          case append_record(state, mode, event) do
            {:reply, result, _} -> result
            {:stop, :normal, result, _} -> result
          end
        after
          :file.close(state.file)
        end
      end
    end)
  end

  defp call(writer, request) do
    GenServer.call(writer, request, 5_000)
  catch
    :exit, _ -> {:error, :journal_write_unconfirmed}
  end

  @impl true
  def init({directory, id, owner, policy, lock_mode}) do
    case open(directory, id, owner, policy, lock_mode) do
      {:ok, state} -> {:ok, Map.put(state, :monitor, Process.monitor(owner))}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp open(directory, id, owner, policy, lock_mode) do
    with {:ok, limits} <- Journal.normalize_limits(policy),
         true <- is_pid(owner) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id),
         path = Path.join(directory, id <> ".jsonl"),
         {:ok, stat} <- File.lstat(path),
         true <- protected?(stat),
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :append, :binary, :raw]) do
      state = %{
        file: file,
        path: path,
        id: id,
        owner: owner,
        lock_guard: Ipse.Session.Lock.for_owner(owner),
        lock_mode: lock_mode,
        offset: stat.size,
        count: 0,
        limits: limits,
        sealed: false,
        reservations: %{},
        reserved_bytes: 0,
        reserved_events: 0,
        identity: identity(stat),
        source_origin: nil,
        source_window: nil,
        share_barrier: nil,
        recent_acceptance: [],
        recent_lifecycle_intent: nil
      }

      case validate_open(state) do
        {:ok, count, origin} ->
          {:ok, %{state | count: count, source_origin: origin}}

        {:error, :journal_limit_reached} ->
          :file.close(file)
          {:error, :journal_limit_reached}

        _ ->
          :file.close(file)
          {:error, :journal_unavailable}
      end
    else
      _ -> {:error, :journal_unavailable}
    end
  end

  @impl true
  def handle_call(
        {:share_barrier, operation, job_ref, generation},
        {owner, _},
        %{owner: owner, share_barrier: nil, lock_mode: mode} = state
      )
      when mode in [:header_share_v2, :resume_share_v2] and is_binary(operation) and
             byte_size(operation) == 16 and is_reference(job_ref) and is_reference(generation) do
    share_barrier(state, operation, job_ref, generation, nil)
  end

  def handle_call(
        {:share_barrier_sources, operation, job_ref, generation, proofs},
        {owner, _},
        %{owner: owner, share_barrier: nil, lock_mode: mode} = state
      )
      when mode in [:header_share_v2, :resume_share_v2] and is_binary(operation) and
             byte_size(operation) == 16 and is_reference(job_ref) and is_reference(generation) do
    with {:ok, sources} <- verified_barrier_sources(state, proofs) do
      share_barrier(state, operation, job_ref, generation, sources)
    else
      _ -> {:reply, {:error, :source_index_refused}, state}
    end
  end

  def handle_call(
        {:share_barrier_display_sources, operation, job_ref, generation, proofs, inactive_ids},
        {owner, _},
        %{owner: owner, share_barrier: nil, lock_mode: mode} = state
      )
      when mode in [:header_share_v2, :resume_share_v2] and is_binary(operation) and
             byte_size(operation) == 16 and is_reference(job_ref) and is_reference(generation) do
    with {:ok, sources} <- verified_barrier_sources(state, proofs, 0..128),
         {:ok, locks} <- inactive_lock_identities(state, inactive_ids) do
      share_barrier(state, operation, job_ref, generation, sources, locks)
    else
      _ -> {:reply, {:error, :source_index_refused}, state}
    end
  end

  def handle_call(
        {:share_barrier_approval_sources, operation, job_ref, generation, proofs, inactive_ids,
         journals},
        {owner, _},
        %{owner: owner, share_barrier: nil, lock_mode: mode} = state
      )
      when mode in [:header_share_v2, :resume_share_v2] and is_binary(operation) and
             byte_size(operation) == 16 and is_reference(job_ref) and is_reference(generation) do
    with {:ok, sources} <- verified_barrier_sources(state, proofs, 0..128),
         {:ok, locks} <- inactive_lock_identities(state, inactive_ids),
         {:ok, journal_locks} <- approval_journal_locks(state, journals),
         true <- length(locks) + length(journal_locks) <= 128 do
      share_barrier(state, operation, job_ref, generation, sources, locks ++ journal_locks)
    else
      _ -> {:reply, {:error, :source_index_refused}, state}
    end
  end

  def handle_call(
        {:share_check, token, operation},
        {guard, _},
        %{lock_guard: guard, share_barrier: %{token: token, operation: operation}} = state
      ),
      do: {:reply, :ok, state}

  def handle_call(
        {:share_control_open, token, operation, deadline},
        {owner, _},
        %{owner: owner, share_barrier: %{token: token, operation: operation} = barrier} = state
      ) do
    with false <- Map.has_key?(barrier, :writer_control),
         {:ok, port} <- Ipse.Runner.open_owner_control(),
         {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
         :ok <- control_frames(port, <<?R, 16::32, "owner-control-v1">>, deadline, <<>>),
         {:ok, stat} <- File.stat("/proc/#{pid}/fd/0"),
         true <- Bitwise.band(stat.mode, 0xF000) == 0x1000 and stat.inode > 0 do
      control = %{
        port: port,
        pid: pid,
        device: stat.major_device,
        inode: stat.inode,
        phase: :ready
      }

      {:reply, {:ok, Map.take(control, [:pid, :device, :inode])},
       put_in(state, [:share_barrier, :writer_control], control)}
    else
      _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
    end
  end

  def handle_call(
        {:share_control_transfer, token, operation, recipient, name, secret, deadline},
        {owner, _},
        %{
          owner: owner,
          share_barrier: %{
            token: token,
            operation: operation,
            writer_control: %{port: port, phase: :ready}
          }
        } = state
      ) do
    expected = <<?H, 17::32, operation::binary, 2, ?T, 17::32, operation::binary, 2>>

    with :ok <-
           Ipse.Runner.send_owner_control(
             port,
             operation,
             :management_journal,
             recipient,
             name,
             secret
           ),
         :ok <- control_frames(port, expected, deadline, <<>>) do
      {:reply, :ok, put_in(state, [:share_barrier, :writer_control, :phase], :transferred)}
    else
      _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
    end
  end

  def handle_call(
        {:share_control_prepare_close, token, operation},
        {owner, _},
        %{
          owner: owner,
          share_barrier: %{
            token: token,
            operation: operation,
            writer_control: %{phase: :transferred}
          }
        } = state
      ) do
    {:reply, :ok, put_in(state, [:share_barrier, :writer_control, :phase], :closing)}
  end

  def handle_call(
        {:share_control_close, token, operation},
        {owner, _} = from,
        %{
          owner: owner,
          share_barrier: %{
            token: token,
            operation: operation,
            writer_control: %{phase: :closing} = control
          }
        } = state
      ) do
    if Map.has_key?(control, :close_from),
      do: {:reply, {:error, :journal_share_frozen}, state},
      else: {:noreply, put_in(state, [:share_barrier, :writer_control, :close_from], from)}
  end

  def handle_call(
        {:share_control_close, token, operation},
        {owner, _},
        %{
          owner: owner,
          share_barrier: %{token: token, operation: operation, writer_control: %{phase: :closed}}
        } = state
      ),
      do: {:reply, :ok, update_in(state, [:share_barrier], &Map.delete(&1, :writer_control))}

  def handle_call(
        {:share_control_close, token, operation},
        {owner, _},
        %{
          owner: owner,
          share_barrier: %{
            token: token,
            operation: operation,
            writer_control: %{port: port, phase: :transferred}
          }
        } = state
      ) do
    case Ipse.Runner.close_owner_control(port) do
      :ok -> {:reply, :ok, update_in(state, [:share_barrier], &Map.delete(&1, :writer_control))}
      _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
    end
  end

  def handle_call(
        {:share_thaw, token, operation},
        {owner, _} = from,
        %{owner: owner, share_barrier: %{token: token, operation: operation} = barrier} = state
      ) do
    if Map.has_key?(barrier, :thaw_request) or Map.has_key?(barrier, :writer_control) do
      {:reply, {:error, :journal_share_frozen}, state}
    else
      request = Ipse.Session.Lock.request_confirm_share_thaw(state.lock_guard, token, operation)

      {:noreply,
       %{state | share_barrier: Map.merge(barrier, %{thaw_request: request, thaw_from: from})}}
    end
  end

  def handle_call(:close, {owner, _}, %{owner: owner, share_barrier: barrier} = state)
      when not is_nil(barrier),
      do: {:stop, :normal, {:error, :journal_write_unconfirmed}, state}

  def handle_call(_, _, %{share_barrier: barrier} = state) when not is_nil(barrier),
    do: {:reply, {:error, :journal_share_frozen}, state}

  def handle_call(
        {:source_window_install, %Ipse.Session.SourceWindow{} = window},
        {owner, _},
        %{owner: owner, source_window: nil, id: id} = state
      ) do
    origin = if state.source_origin, do: Ipse.JSON.digest([state.source_origin])

    if window.index.session_id == id and window.index.origin_sha256 == origin,
      do: {:reply, :ok, %{state | source_window: window}},
      else: {:reply, {:error, :source_index_refused}, state}
  end

  def handle_call(
        {:source_query, query},
        {owner, _},
        %{owner: owner, source_window: window} = state
      )
      when not is_nil(window) do
    result =
      case query do
        :snapshot ->
          {:ok, Ipse.Session.SourceWindow.snapshot(window)}

        :index_scope ->
          {:ok,
           %{
             secret: window.index.secret,
             window: window.index.window_id,
             generation: window.index.generation
           }}

        :origin ->
          {:ok, state.source_origin}

        :effective_source ->
          {:ok, window.effective_source}

        {:legacy_workspace_acquisition, parent, identity, path, sha} ->
          Ipse.Session.SourceWindow.legacy_workspace_acquisition(
            window,
            parent,
            identity,
            path,
            sha
          )

        {:workspace_acquisition, operation, identity} ->
          Ipse.Session.SourceWindow.workspace_acquisition(window, operation, identity)

        {:proof, request} ->
          Ipse.Session.SourceIndex.resolve_proof(window.index, request)

        {:stored_proof, proof} ->
          Ipse.Session.SourceIndex.revalidate_stored(window.index, proof)

        {:answer_request, turn, request, quote} ->
          Ipse.Session.SourceIndex.answer_request(window.index, turn, request, quote)

        {:planning_answer_request, entry, turn, request, quote} ->
          Ipse.Session.SourceWindow.planning_answer_request(window, entry, turn, request, quote)

        {:planning_answer_current, entry_sha, turn, request, proof} ->
          {:ok,
           Ipse.Session.SourceWindow.planning_answer_current?(
             window,
             entry_sha,
             turn,
             request,
             proof
           )}

        {:assertion_request, id} ->
          Ipse.Session.SourceIndex.assertion_request(window.index, id)

        {:tool_result_provenances, call_id, message} ->
          Ipse.Session.SourceWindow.tool_result_provenances(window, call_id, message)

        {:tool_query_provenances, call_id, operation, args} ->
          Ipse.Session.SourceWindow.tool_query_provenances(
            window,
            call_id,
            operation,
            args,
            :live
          )

        {operation, request} ->
          Ipse.Session.SourceWindow.execute(window, operation, request)

        _ ->
          {:error, :source_index_refused}
      end

    case unchanged(state) do
      :ok -> {:reply, result, state}
      _ -> {:stop, :normal, {:error, :source_index_refused}, state}
    end
  end

  def handle_call(
        :source_window_ensure,
        {owner, _},
        %{owner: owner, source_window: window} = state
      )
      when not is_nil(window) do
    if window.historical_window == window.index.window_id,
      do: {:reply, :ok, state},
      else: append_record(state, :plain, Ipse.Session.SourceWindow.opened(window))
  end

  def handle_call({:append, _, _}, {owner, _}, %{owner: owner, sealed: true} = state),
    do: {:reply, {:error, :journal_limit_reached}, state}

  def handle_call({:append, mode, event}, {owner, _}, %{owner: owner} = state)
      when mode in [:plain, :observed, :source] and is_map(event) do
    append_record(state, mode, event)
  end

  def handle_call({:reserve, _}, {owner, _}, %{owner: owner, sealed: true} = state),
    do: {:reply, {:error, :journal_limit_reached}, state}

  def handle_call({:reserve, capacity}, {owner, _}, %{owner: owner} = state) do
    case capacity do
      %{bytes: bytes, events: events}
      when map_size(capacity) == 2 and
             is_integer(bytes) and is_integer(events) and
             events > 0 and bytes >= events * 3 ->
        if available?(state, bytes, events) do
          case unchanged(state) do
            :ok ->
              token = make_ref()

              {:reply, {:ok, token},
               %{
                 state
                 | reservations: Map.put(state.reservations, token, capacity),
                   reserved_bytes: state.reserved_bytes + bytes,
                   reserved_events: state.reserved_events + events
               }}

            _ ->
              {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
          end
        else
          {:reply, {:error, :journal_reservation_unavailable}, state}
        end

      _ ->
        {:reply, {:error, :journal_reservation_invalid}, state}
    end
  end

  def handle_call({:append_reserved, token, mode, event}, {owner, _}, %{owner: owner} = state)
      when is_map(event) and mode in [:plain, :observed] do
    case Map.fetch(state.reservations, token) do
      {:ok, capacity} -> append_reserved_record(state, token, capacity, mode, event)
      :error -> {:reply, {:error, :journal_reservation_invalid}, state}
    end
  end

  def handle_call({:release, token}, {owner, _}, %{owner: owner} = state) do
    case Map.pop(state.reservations, token) do
      {nil, _} ->
        {:reply, {:error, :journal_reservation_invalid}, state}

      {capacity, reservations} ->
        {:reply, :ok,
         %{
           state
           | reservations: reservations,
             reserved_bytes: state.reserved_bytes - capacity.bytes,
             reserved_events: state.reserved_events - capacity.events
         }}
    end
  end

  def handle_call(:close, {owner, _}, %{owner: owner} = state),
    do: {:stop, :normal, :ok, state}

  def handle_call(_, _, state), do: {:reply, {:error, :journal_owner_or_record_invalid}, state}

  defp append_record(state, mode, event) do
    case encode(state, mode, event) do
      {:ok, line, result} ->
        with :ok <- unchanged(state),
             :ok <- append_line(state, line) do
          {:reply, result,
           %{
             state
             | offset: state.offset + byte_size(line),
               count: state.count + 1,
               recent_acceptance: recent_acceptance(state, event),
               recent_lifecycle_intent: recent_lifecycle_intent(event),
               source_window: source_advance(state, event)
           }}
        else
          _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
        end

      {:limit, reason} ->
        if map_size(state.reservations) == 0,
          do: seal(state, reason),
          else: {:reply, {:error, :journal_reservation_unavailable}, state}

      _ ->
        {:reply, {:error, :journal_record_refused}, state}
    end
  end

  defp append_reserved_record(state, token, capacity, mode, event) do
    case encode(%{state | reserved_bytes: 0, reserved_events: 0}, mode, event) do
      {:ok, line, result} ->
        if capacity.events > 0 and byte_size(line) <= capacity.bytes do
          with :ok <- unchanged(state),
               :ok <- append_line(state, line) do
            remaining = %{bytes: capacity.bytes - byte_size(line), events: capacity.events - 1}

            {:reply, result,
             %{
               state
               | offset: state.offset + byte_size(line),
                 count: state.count + 1,
                 recent_acceptance: recent_acceptance(state, event),
                 recent_lifecycle_intent: recent_lifecycle_intent(event),
                 reservations: Map.put(state.reservations, token, remaining),
                 reserved_bytes: state.reserved_bytes - byte_size(line),
                 reserved_events: state.reserved_events - 1,
                 source_window: source_advance(state, event)
             }}
          else
            _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
          end
        else
          {:reply, {:error, :journal_reservation_exhausted}, state}
        end

      {:limit, _} ->
        {:reply, {:error, :journal_record_refused}, state}

      _ ->
        {:reply, {:error, :journal_record_refused}, state}
    end
  end

  defp control_frames(port, expected, deadline, buffer) do
    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        :error

      buffer == expected ->
        :ok

      byte_size(buffer) >= byte_size(expected) or
          binary_part(expected, 0, byte_size(buffer)) != buffer ->
        :error

      true ->
        receive do
          {^port, {:data, bytes}} -> control_frames(port, expected, deadline, buffer <> bytes)
          {^port, _} -> :error
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> :error
        end
    end
  end

  defp recent_acceptance(state, event) do
    digest =
      if is_map(event) and
           event["type"] in ~w(pending_proposal_accepted pending_acceptance_intent) do
        case Ipse.JSON.checked_digest([event]) do
          {:ok, value} -> value
          _ -> nil
        end
      end

    Enum.take(state.recent_acceptance ++ [digest], -2)
  end

  defp recent_lifecycle_intent(%{"type" => "managed_lifecycle_intent"} = event) do
    case Ipse.JSON.checked_digest([event]) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp recent_lifecycle_intent(_), do: nil

  defp verified_barrier_sources(state, proofs, bounds \\ 1..8) do
    with true <-
           is_list(proofs) and length(proofs) in bounds and
             length(Enum.uniq(proofs)) == length(proofs),
         %{index: index} <- state.source_window,
         {:ok, sources} <-
           Enum.reduce_while(proofs, {:ok, []}, fn proof, {:ok, acc} ->
             case Ipse.Session.SourceIndex.revalidate_stored(index, proof) do
               {:ok, source} -> {:cont, {:ok, [source | acc]}}
               _ -> {:halt, {:error, :source_index_refused}}
             end
           end),
         do: {:ok, Enum.reverse(sources)},
         else: (_ -> {:error, :source_index_refused})
  end

  defp inactive_lock_identities(state, ids) do
    with true <- is_list(ids) and length(ids) <= 128 and ids == Enum.sort(Enum.uniq(ids)),
         true <-
           Enum.all?(
             ids,
             &(is_binary(&1) and &1 != state.id and Regex.match?(~r/\A[0-9a-f]{32}\z/, &1))
           ) do
      lock_identities(state, Path.dirname(state.path), ids)
    else
      _ -> {:error, :source_index_refused}
    end
  rescue
    _ -> {:error, :source_index_refused}
  end

  defp approval_journal_locks(state, %{directory: directory, ids: ids}) do
    with true <-
           is_binary(directory) and Path.type(directory) == :absolute and
             Path.basename(directory) == "knowledge-management",
         true <- is_list(ids) and length(ids) <= 128 and ids == Enum.sort(Enum.uniq(ids)),
         true <- Enum.all?(ids, &(is_binary(&1) and Regex.match?(~r/\A[0-9a-f]{32}\z/, &1))) do
      lock_identities(state, directory, ids)
    else
      _ -> {:error, :source_index_refused}
    end
  rescue
    _ -> {:error, :source_index_refused}
  end

  defp approval_journal_locks(_, _), do: {:error, :source_index_refused}

  defp lock_identities(state, directory, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case File.lstat(Path.join(directory, id <> ".lock")) do
        {:ok, stat} when stat.uid == elem(state.identity, 3) ->
          if protected?(stat) and stat.inode > 0,
            do:
              {:cont,
               {:ok, [%{session_id: id, device: stat.major_device, inode: stat.inode} | acc]}},
            else: {:halt, {:error, :source_index_refused}}

        _ ->
          {:halt, {:error, :source_index_refused}}
      end
    end)
    |> case do
      {:ok, locks} -> {:ok, Enum.reverse(locks)}
      error -> error
    end
  end

  defp share_barrier(state, operation, job_ref, generation, sources, locks \\ nil) do
    if operation != <<0::128>> and unchanged(state) == :ok do
      token = make_ref()
      window = if state.source_window, do: Ipse.Session.SourceWindow.snapshot(state.source_window)

      snapshot = %{
        session_id: state.id,
        identity: state.identity,
        offset: state.offset,
        count: state.count,
        source_window: window,
        job_ref: job_ref,
        owner_generation: generation,
        recent_acceptance: state.recent_acceptance,
        recent_lifecycle_intent: state.recent_lifecycle_intent
      }

      snapshot =
        if is_list(sources), do: Map.put(snapshot, :verified_sources, sources), else: snapshot

      snapshot =
        if is_list(locks), do: Map.put(snapshot, :inactive_source_locks, locks), else: snapshot

      barrier = %{token: token, operation: operation, snapshot: snapshot}
      {:reply, {:ok, token, snapshot}, %{state | share_barrier: barrier}}
    else
      {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
    end
  end

  defp available?(state, bytes, events) do
    state.offset + state.reserved_bytes + bytes + Journal.reserve_bytes() <=
      state.limits["max_bytes"] and
      state.count + state.reserved_events + events + 1 <= state.limits["max_events"]
  end

  defp source_advance(%{source_window: nil}, _), do: nil

  defp source_advance(state, event) do
    source =
      case Journal.source(state.id, state.offset, event) do
        {:ok, source} -> source
        _ -> nil
      end

    Ipse.Session.SourceWindow.advance(state.source_window, event, source)
  end

  @impl true
  def handle_info(
        {port, {:exit_status, 0}},
        %{share_barrier: %{writer_control: %{port: port, phase: :closing} = control}} = state
      ) do
    if from = control[:close_from] do
      GenServer.reply(from, :ok)
      {:noreply, update_in(state, [:share_barrier], &Map.delete(&1, :writer_control))}
    else
      {:noreply, put_in(state, [:share_barrier, :writer_control, :phase], :closed)}
    end
  end

  def handle_info(
        {port, {:exit_status, _}},
        %{share_barrier: %{writer_control: %{port: port} = control}} = state
      ) do
    if from = control[:close_from],
      do: GenServer.reply(from, {:error, :journal_write_unconfirmed})

    {:stop, :normal, state}
  end

  def handle_info(message, %{share_barrier: %{thaw_request: request, thaw_from: from}} = state) do
    case :gen_server.check_response(message, request) do
      {:reply, :ok} ->
        if Process.alive?(state.owner) do
          GenServer.reply(from, :ok)
          {:noreply, %{state | share_barrier: nil}}
        else
          {:stop, :normal, state}
        end

      {:reply, _} ->
        GenServer.reply(from, {:error, :journal_write_unconfirmed})

        {:noreply,
         %{state | share_barrier: Map.drop(state.share_barrier, [:thaw_request, :thaw_from])}}

      {:error, _} ->
        GenServer.reply(from, {:error, :journal_write_unconfirmed})

        {:noreply,
         %{state | share_barrier: Map.drop(state.share_barrier, [:thaw_request, :thaw_from])}}

      :no_reply ->
        case message do
          {:DOWN, ref, :process, owner, _} when ref == state.monitor and owner == state.owner ->
            {:stop, :normal, state}

          _ ->
            {:noreply, state}
        end
    end
  end

  def handle_info({:DOWN, ref, :process, owner, _}, %{monitor: ref, owner: owner} = state),
    do: {:stop, :normal, state}

  @impl true
  def terminate(_, state), do: :file.close(state.file)

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:id, :offset])}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp validate_open(state) do
    with :ok <- unchanged(state),
         {:ok, %{header: header}} <- Journal.scan_file(state.file, state.limits, :header),
         true <-
           state.lock_mode != :legacy or
             not Journal.native_owner_required?(header["metadata"]),
         :ok <-
           Ipse.Journal.SourceOrigin.check(state.file, state.path, state.id, header["metadata"]),
         {:ok, origin} <- Ipse.Journal.SourceOrigin.recorded(header["metadata"], state.id),
         {:ok, stats} <- Journal.scan_file(state.file, state.limits),
         true <- stats.tail == :none and stats.count > 0,
         :ok <- unchanged(%{state | source_origin: origin}) do
      if stats.last_quota != nil or
           stats.bytes + Journal.reserve_bytes() > state.limits["max_bytes"] or
           stats.count + 1 > state.limits["max_events"],
         do: {:error, :journal_limit_reached},
         else: {:ok, stats.count, origin}
    else
      {:error, :journal_limit_reached} = error -> error
      _ -> {:error, :journal_unavailable}
    end
  end

  defp append_line(state, line) do
    if state.lock_mode in [:header_v1, :resume_v1, :header_share_v2, :resume_share_v2] do
      {device, _minor, inode, _uid} = state.identity

      Ipse.Session.Lock.journal_append(
        state.lock_guard,
        %{device: device, inode: inode},
        state.offset,
        line
      )
    else
      append_legacy_line(state, line)
    end
  end

  defp append_legacy_line(state, line) do
    Ipse.Session.Resources.file_effect(
      fn ->
        with {:ok, file} <- :file.open(String.to_charlist(state.path), [:append, :binary, :raw]) do
          try do
            with :ok <- unchanged(state, file),
                 :ok <- :file.write(file, line),
                 :ok <- :file.sync(file),
                 do: unchanged(%{state | offset: state.offset + byte_size(line)}, file)
          after
            :file.close(file)
          end
        end
      end,
      state.lock_guard
    )
  end

  defp unchanged(state, file \\ nil) do
    with {:ok, path_stat} <- File.lstat(state.path),
         {:ok, info} <- :file.read_file_info(file || state.file),
         file_stat = File.Stat.from_record(info),
         true <- protected?(path_stat) and protected?(file_stat),
         true <- identity(path_stat) == state.identity and identity(file_stat) == state.identity,
         true <- path_stat.size == state.offset and file_stat.size == state.offset,
         :ok <-
           if(state.source_origin,
             do:
               Ipse.Journal.SourceOrigin.check(file || state.file, state.path, state.id, %{
                 "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
                 "source_origin" => state.source_origin
               }),
             else: :ok
           ) do
      :ok
    else
      _ -> {:error, :journal_changed}
    end
  end

  defp identity(stat), do: {stat.major_device, stat.minor_device, stat.inode, stat.uid}

  defp protected?(stat),
    do: stat.type == :regular and stat.links == 1 and Bitwise.band(stat.mode, 0o077) == 0

  defp encode(_state, _mode, %{"type" => "journal_limit_reached"}),
    do: {:error, :journal_record_refused}

  defp encode(state, mode, event) do
    with {:ok, encoded} <- Journal.encode_event(event, state.limits),
         {:ok, result} <- source(state, mode, event, encoded) do
      case Journal.admit(
             state.limits,
             state.offset + state.reserved_bytes,
             state.count + state.reserved_events,
             byte_size(encoded)
           ) do
        :ok -> {:ok, encoded <> "\n", result}
        {:error, reason} -> {:limit, reason}
      end
    else
      {:error, :journal_limit_reached} -> {:limit, "record_bytes"}
      error -> error
    end
  rescue
    _ -> {:error, :journal_record_refused}
  end

  defp seal(state, reason) do
    event = Journal.limit_receipt(state.limits, state.offset, state.count, reason)
    line = Jason.encode!(event) <> "\n"

    with true <- byte_size(line) <= Journal.reserve_bytes(),
         :ok <- unchanged(state),
         :ok <- append_line(state, line) do
      {:reply, {:error, :journal_limit_reached},
       %{
         state
         | sealed: true,
           offset: state.offset + byte_size(line),
           count: state.count + 1,
           recent_acceptance: [],
           recent_lifecycle_intent: nil
       }}
    else
      _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
    end
  end

  defp source(_, :plain, _, _), do: {:ok, :ok}

  defp source(state, :observed, event, _) do
    reference =
      case Journal.source(state.id, state.offset, event) do
        {:ok, reference} -> reference
        _ -> nil
      end

    {:ok, {:ok, reference}}
  end

  defp source(state, :source, _, encoded) do
    with {:ok, decoded} <- Ipse.JSON.decode_bounded(encoded, Journal.source_record_bytes()),
         {:ok, reference} <- Journal.source(state.id, state.offset, decoded) do
      {:ok, {:ok, reference}}
    end
  end
end
