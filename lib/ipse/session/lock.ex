defmodule Ipse.Session.Lock do
  @moduledoc "Retains the session lock through owner death until tracked workers and writer exit."
  use GenServer
  @key {__MODULE__, :guard}

  def acquire(path), do: start(path, :legacy)

  @doc false
  def acquire_header(path), do: start(path, :header_v1)

  @doc false
  def acquire_resume(path), do: start(path, :resume_v1)

  @doc false
  def acquire_share_header(path), do: start(path, :header_share_v2)

  @doc false
  def acquire_share_resume(path), do: start(path, :resume_share_v2)

  @doc false
  # Inactive internal candidate: current Session startup still uses acquire/1.
  def acquire_export_candidate(path), do: start(path, :export_v1)

  defp start(path, mode) do
    case GenServer.start(__MODULE__, {path, self(), mode}) do
      {:ok, guard} ->
        port = GenServer.call(guard, :port)
        Process.put(@key, guard)
        {:ok, port}

      error ->
        error
    end
  end

  def current, do: Process.get(@key)

  @doc false
  def mode(guard), do: GenServer.call(guard, :mode)

  def track(pid, kind) do
    case current() do
      nil -> :ok
      guard -> GenServer.call(guard, {:track, pid, kind})
    end
  end

  def for_owner(owner) do
    case Registry.lookup(Ipse.Registry, {__MODULE__, owner}) do
      [{guard, _}] -> guard
      [] -> nil
    end
  end

  def track_in(nil, _, _), do: :ok
  def track_in(guard, pid, kind), do: GenServer.call(guard, {:track, pid, kind})

  def track_child_scope(nil, _), do: :ok
  def track_child_scope(guard, pid), do: GenServer.call(guard, {:track_child_scope, pid})

  def track_session(child) do
    guard = for_owner(child)
    if is_nil(guard), do: exit(:child_lock_unavailable)
    :ok = track(guard, :peer)
    track(child, :worker)
  end

  def release(guard), do: GenServer.call(guard, :release, :infinity)

  @doc false
  def begin_header(guard, deadline), do: header_call(guard, {:begin_header, deadline}, deadline)

  @doc false
  def write_header(guard, bytes, deadline),
    do: header_call(guard, {:write_header, bytes, deadline}, deadline)

  @doc false
  def header_identity(guard, deadline),
    do: header_call(guard, {:header_identity, deadline}, deadline)

  @doc false
  def journal_append(guard, identity, offset, line) do
    deadline = System.monotonic_time(:millisecond) + 4_000
    header_call(guard, {:journal_append, identity, offset, line, deadline}, deadline)
  end

  @doc false
  def journal_repair(guard, identity, offset, target, action) do
    deadline = System.monotonic_time(:millisecond) + 4_000
    header_call(guard, {:journal_repair, identity, offset, target, action, deadline}, deadline)
  end

  @doc false
  def request_share_arm(guard, writer, token, operation),
    do: :gen_server.send_request(guard, {:share_arm, writer, token, operation})

  @doc false
  def request_share_identity(guard, token, operation, deadline),
    do: :gen_server.send_request(guard, {:share_identity, token, operation, deadline})

  @doc false
  def request_share_export(guard, token, operation, request, deadline),
    do: :gen_server.send_request(guard, {:share_export, token, operation, request, deadline})

  @doc false
  def request_share_settle(guard, token, operation, deadline),
    do: :gen_server.send_request(guard, {:share_settle, token, operation, deadline})

  @doc false
  def request_share_cancel(guard, token, operation),
    do: :gen_server.send_request(guard, {:share_cancel, token, operation})

  @doc false
  def request_confirm_share_thaw(guard, token, operation),
    do: :gen_server.send_request(guard, {:share_confirm_thaw, token, operation})

  defp header_call(guard, request, deadline) when is_integer(deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0) + 1_000
    GenServer.call(guard, request, timeout)
  catch
    :exit, _ -> {:error, :header_unconfirmed}
  end

  defp header_call(_, _, _), do: {:error, :header_unconfirmed}

  @impl true
  def init({path, owner, mode}) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)

    result =
      case mode do
        :legacy -> Ipse.Runner.protected_lock(path)
        :export_v1 -> Ipse.Runner.protected_export_lock(path)
        :header_v1 -> Ipse.Runner.protected_header_lock(path)
        :resume_v1 -> Ipse.Runner.protected_resume_lock(path)
        :header_share_v2 -> Ipse.Runner.protected_share_header_lock(path)
        :resume_share_v2 -> Ipse.Runner.protected_share_resume_lock(path)
      end

    case result do
      {:ok, port} ->
        {:ok, _} = Registry.register(Ipse.Registry, {__MODULE__, owner}, nil)

        {:ok,
         %{
           owner: owner,
           owner_ref: monitor,
           port: port,
           mode: mode,
           dependents: %{},
           lost: false,
           header_phase: :ready,
           header_deadline: nil,
           share: nil,
           share_ordinal: 0,
           share_sequence: 0,
           share_epoch:
             if(mode in [:header_share_v2, :resume_share_v2], do: :crypto.strong_rand_bytes(16))
         }}

      error ->
        {:stop, elem(error, 1)}
    end
  end

  @impl true
  def handle_call(:port, {owner, _}, %{owner: owner} = s), do: {:reply, s.port, s}
  def handle_call(:mode, {owner, _}, %{owner: owner} = s), do: {:reply, s.mode, s}

  def handle_call(
        {:begin_header, deadline},
        {owner, _},
        %{owner: owner, mode: mode, header_phase: :ready, share: nil} = s
      )
      when is_integer(deadline) and mode in [:header_v1, :header_share_v2] do
    result = Ipse.Runner.session_header_begin(s.port, deadline)
    phase = if match?({:ok, _}, result), do: :prepared, else: :failed
    {:reply, result, %{s | header_phase: phase, header_deadline: deadline}}
  end

  def handle_call(
        {:write_header, bytes, deadline},
        {owner, _},
        %{
          owner: owner,
          mode: mode,
          header_phase: :prepared,
          header_deadline: deadline,
          share: nil
        } = s
      )
      when mode in [:header_v1, :header_share_v2] do
    result = Ipse.Runner.session_header_write(s.port, bytes, owner, deadline)
    phase = if result == :ok, do: :complete, else: :failed
    sequence = if result == :ok, do: 3 + div(byte_size(bytes) + 16_383, 16_384), else: 0
    {:reply, result, %{s | header_phase: phase, share_sequence: sequence}}
  end

  def handle_call(
        {:header_identity, deadline},
        {owner, _},
        %{owner: owner, mode: mode, header_phase: phase, share: nil} = s
      )
      when mode in [:header_v1, :header_share_v2] and phase in [:ready, :complete] do
    {:reply, Ipse.Runner.session_header_lock_identity(s.port, deadline), s}
  end

  def handle_call(
        {:journal_append, identity, offset, line, deadline},
        {caller, _},
        %{mode: mode, lost: false} = s
      )
      when mode in [:header_v1, :resume_v1, :header_share_v2, :resume_share_v2] do
    authorized = Enum.any?(s.dependents, fn {_, pair} -> pair == {caller, :writer} end)

    ready =
      s.share == nil and
        ((mode in [:header_v1, :header_share_v2] and s.header_phase == :complete) or
           (mode in [:resume_v1, :resume_share_v2] and s.header_phase == :ready))

    result =
      if authorized and ready,
        do: Ipse.Runner.session_journal_append(s.port, identity, offset, line, deadline),
        else: {:error, :journal_write_unconfirmed}

    {:reply, result, s}
  end

  def handle_call(
        {:journal_repair, identity, offset, target, action, deadline},
        {owner, _},
        %{owner: owner, mode: mode, lost: false} = s
      )
      when mode in [:header_v1, :resume_v1, :header_share_v2, :resume_share_v2] do
    ready =
      s.share == nil and
        ((mode in [:header_v1, :header_share_v2] and s.header_phase == :complete) or
           (mode in [:resume_v1, :resume_share_v2] and s.header_phase == :ready))

    result =
      if ready,
        do:
          Ipse.Runner.session_journal_repair(s.port, identity, offset, target, action, deadline),
        else: {:error, :journal_write_unconfirmed}

    {:reply, result, s}
  end

  def handle_call(
        {:header_identity, deadline},
        {owner, _},
        %{owner: owner, mode: mode, header_phase: :ready, share: nil} = s
      )
      when mode in [:resume_v1, :resume_share_v2] do
    {:reply, Ipse.Runner.session_header_lock_identity(s.port, deadline), s}
  end

  def handle_call(
        {:share_arm, writer, token, operation},
        {owner, _},
        %{owner: owner, mode: mode, lost: false, share: nil} = s
      )
      when mode in [:header_share_v2, :resume_share_v2] and is_pid(writer) and
             is_reference(token) and is_binary(operation) and byte_size(operation) == 16 do
    tracked = Enum.any?(s.dependents, fn {_, pair} -> pair == {writer, :writer} end)

    ready =
      (mode == :header_share_v2 and s.header_phase == :complete) or
        (mode == :resume_share_v2 and s.header_phase == :ready)

    if tracked and ready and operation != <<0::128>> and Process.alive?(owner) and
         Ipse.Journal.Writer.check_share_barrier(writer, token, operation) == :ok and
         s.share_ordinal < 18_446_744_073_709_551_615 do
      ordinal = s.share_ordinal + 1

      transport =
        :crypto.hash(:sha256, <<s.share_epoch::binary, ordinal::64, operation::binary>>)
        |> binary_part(0, 16)

      share = %{
        writer: writer,
        token: token,
        operation: operation,
        transport: transport,
        phase: :armed,
        ordinal: ordinal
      }

      {:reply, {:ok, transport}, %{s | share: share}}
    else
      {:reply, {:error, :session_share_unconfirmed}, s}
    end
  end

  def handle_call(
        {:share_identity, token, operation, deadline},
        {owner, _},
        %{owner: owner, lost: false, share: %{token: token, operation: operation, phase: :armed}} =
          s
      )
      when is_integer(deadline) do
    result =
      with true <- System.monotonic_time(:millisecond) < deadline,
           {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(s.port, :os_pid),
           {:ok, identity} <- Ipse.Runner.session_header_lock_identity(s.port, deadline),
           true <- Process.alive?(owner) and System.monotonic_time(:millisecond) < deadline do
        {:ok, Map.put(identity, :pid, pid)}
      else
        _ -> {:error, :session_share_unconfirmed}
      end

    {:reply, result, s}
  end

  def handle_call(
        {:share_export, token, operation, request, deadline},
        {owner, _},
        %{
          owner: owner,
          share: %{token: token, operation: operation, phase: :armed} = share,
          lost: false
        } = s
      ) do
    seq = s.share_sequence + 1

    result =
      Ipse.Runner.session_share_export(
        s.port,
        seq,
        share.ordinal,
        share.transport,
        request,
        deadline
      )

    phase = if result == :ok and Process.alive?(owner), do: :shared, else: :poisoned

    {:reply, if(phase == :shared, do: :ok, else: {:error, :session_share_unconfirmed}),
     %{s | share: %{share | phase: phase}, share_sequence: seq, share_ordinal: share.ordinal}}
  end

  def handle_call(
        {:share_settle, token, operation, deadline},
        {owner, _},
        %{
          owner: owner,
          share: %{token: token, operation: operation, phase: :shared} = share,
          lost: false
        } = s
      ) do
    seq = s.share_sequence + 1

    result =
      Ipse.Runner.session_share_settle(s.port, seq, share.ordinal, share.transport, deadline)

    phase = if result == :ok and Process.alive?(owner), do: :settled, else: :poisoned

    {:reply, if(phase == :settled, do: :ok, else: {:error, :session_share_unconfirmed}),
     %{s | share: %{share | phase: phase}, share_sequence: seq}}
  end

  def handle_call(
        {:share_confirm_thaw, token, operation},
        {writer, _},
        %{share: %{writer: writer, token: token, operation: operation, phase: phase}, lost: false} =
          s
      )
      when phase in [:settled, :cancelled],
      do: {:reply, :ok, %{s | share: nil}}

  def handle_call(
        {:share_cancel, token, operation},
        {owner, _},
        %{owner: owner, share: %{token: token, operation: operation} = share} = s
      ) do
    if share.phase == :armed do
      {:reply, :ok, %{s | share: %{share | phase: :cancelled}}}
    else
      {:reply, {:error, :session_share_unconfirmed}, %{s | share: %{share | phase: :poisoned}}}
    end
  end

  def handle_call({:track, _, _}, _, %{share: share} = s) when not is_nil(share),
    do: {:reply, {:error, :session_share_frozen}, s}

  def handle_call({:track_child_scope, _}, _, %{share: share} = s) when not is_nil(share),
    do: {:reply, {:error, :session_share_frozen}, s}

  def handle_call({:track, pid, kind}, {caller, _}, s)
      when is_pid(pid) and kind in [:worker, :writer, :scope, :peer] do
    scoped =
      kind in [:worker, :peer] and
        Enum.any?(s.dependents, fn {_, pair} -> pair == {caller, :scope} end)

    writer =
      kind == :peer and Enum.any?(s.dependents, fn {_, pair} -> pair == {caller, :writer} end)

    if caller == s.owner or scoped or writer do
      ref = Process.monitor(pid)
      {:reply, :ok, %{s | dependents: Map.put(s.dependents, ref, {pid, kind})}}
    else
      {:reply, {:error, :session_lock_refused}, s}
    end
  end

  def handle_call({:track_child_scope, pid}, {caller, _}, s) when is_pid(pid) do
    parent_scope? = Enum.any?(s.dependents, fn {_, pair} -> pair == {caller, :scope} end)

    if parent_scope? and Process.alive?(caller) and Process.alive?(pid) do
      ref = Process.monitor(pid)
      {:reply, :ok, %{s | dependents: Map.put(s.dependents, ref, {pid, :scope})}}
    else
      {:reply, {:error, :session_lock_refused}, s}
    end
  end

  def handle_call(:release, {owner, _}, %{owner: owner} = s) do
    quiesce(s.dependents)
    unlocked = unlock(s)
    result = if s.share == nil, do: unlocked, else: {:error, :session_share_unconfirmed}
    {:stop, :normal, result, %{s | dependents: %{}}}
  end

  def handle_call(_, _, s), do: {:reply, {:error, :session_lock_refused}, s}

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = s) do
    quiesce(s.dependents)
    unlock(s)
    {:stop, :normal, %{s | dependents: %{}}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, s),
    do: {:noreply, %{s | dependents: Map.delete(s.dependents, ref)}}

  def handle_info({port, {:exit_status, _}}, %{port: port} = s), do: lost(s)
  def handle_info({:EXIT, port, _}, %{port: port} = s), do: lost(s)
  def handle_info(_, s), do: {:noreply, s}

  defp lost(%{lost: false} = s) do
    send(s.owner, {s.port, {:exit_status, :lock_lost}})
    {:noreply, %{s | lost: true}}
  end

  defp lost(s), do: {:noreply, s}

  defp unlock(%{mode: :export_v1, port: port}), do: Ipse.Runner.unlock_export_candidate(port)
  defp unlock(%{mode: :header_v1, port: port}), do: Ipse.Runner.unlock_export_candidate(port)
  defp unlock(%{mode: :resume_v1, port: port}), do: Ipse.Runner.unlock_export_candidate(port)

  defp unlock(%{mode: :header_share_v2, port: port}),
    do: Ipse.Runner.unlock_export_candidate(port)

  defp unlock(%{mode: :resume_share_v2, port: port}),
    do: Ipse.Runner.unlock_export_candidate(port)

  defp unlock(%{port: port}), do: Ipse.Runner.unlock(port)

  defp quiesce(dependents) do
    Enum.each(dependents, fn {_, {pid, kind}} ->
      case kind do
        :scope -> Ipse.Session.Resources.stop_async(pid)
        :peer -> :ok
        _ -> Process.exit(pid, :kill)
      end
    end)

    Enum.each(dependents, fn {ref, {pid, _}} ->
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      end
    end)
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {key, _} when key in [:state, :message, :reason, :log] -> {key, :session_lock_guard}
      pair -> pair
    end)
  end
end
