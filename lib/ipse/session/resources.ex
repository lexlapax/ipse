defmodule Ipse.Session.Resources do
  @moduledoc "Private task cleanup scope; process death never substitutes for an OS-helper receipt."
  use GenServer
  @key {__MODULE__, :scope}

  def start(owner), do: GenServer.start(__MODULE__, owner)

  def start_child(root, peer, reporter, token),
    do: GenServer.start(__MODULE__, {:child, root, peer, reporter, token})

  def bind(scope), do: Process.put(@key, scope)
  def current, do: Process.get(@key)

  @doc false
  def active?(timeout \\ 5_000)

  def active?(timeout) when is_integer(timeout) and timeout in 1..5_000 do
    case current() do
      nil -> true
      scope when is_pid(scope) -> GenServer.call(scope, :active, timeout) === true
      _ -> false
    end
  catch
    :exit, _ -> false
  end

  def active?(_), do: false

  @doc false
  def await_ready(scope, owner) do
    owner_ref = Process.monitor(owner)
    scope_ref = Process.monitor(scope)

    try do
      receive do
        {:cleanup_scope_ready, ^scope} -> :ok
        {:DOWN, ref, :process, _, _} when ref in [owner_ref, scope_ref] -> exit(:normal)
      end
    after
      Process.demonitor(owner_ref, [:flush])
      Process.demonitor(scope_ref, [:flush])
    end
  end

  def async(fun) when is_function(fun, 0) do
    scope = current()
    owner = self()

    task =
      Task.async(fn ->
        if is_pid(scope), do: await_ready(scope, owner)
        bind(scope)
        fun.()
      end)

    if is_pid(scope) do
      :ok = GenServer.call(scope, {:track_task, task.pid})
      send(task.pid, {:cleanup_scope_ready, scope})
    end

    task
  end

  def attach(scope, worker), do: GenServer.call(scope, {:attach, worker})

  def register(kind, scope \\ current()) do
    if is_pid(scope) do
      GenServer.call(scope, {:register, kind, self()})
    else
      {:ok, nil}
    end
  catch
    :exit, _ -> {:error, :cleanup_scope_closed}
  end

  def closed(nil, _), do: :ok

  def closed(%{scope: scope, id: id}, result) do
    send(scope, {:resource_closed, id, self(), result})
    :ok
  end

  def close_task(worker) do
    case Registry.lookup(Ipse.Registry, {__MODULE__, worker}) do
      [{scope, _}] -> close(scope)
      [] -> {:error, :cleanup_unconfirmed}
    end
  end

  @doc false
  def authorized_effect?(worker, caller) when is_pid(worker) and is_pid(caller) do
    case Registry.lookup(Ipse.Registry, {__MODULE__, worker}) do
      [{scope, _}] -> GenServer.call(scope, {:authorized_effect, worker, caller})
      _ -> false
    end
  catch
    :exit, _ -> false
  end

  def authorized_effect?(_, _), do: false

  def close(scope) do
    GenServer.call(scope, :close, 5_000)
  catch
    :exit, _ -> {:error, :cleanup_unconfirmed}
  end

  def finish(scope) do
    GenServer.call(scope, :finish, 5_000)
  catch
    :exit, _ -> {:error, :cleanup_unconfirmed}
  end

  @doc false
  def stop_async(scope), do: GenServer.cast(scope, :stop)

  @impl true
  def handle_cast({:abandon_child, token, peer, reporter}, state) do
    case state.child_tokens[token] do
      %{peer: ^peer, reporter: ^reporter, child: nil} = entry ->
        tokens =
          if Process.alive?(peer),
            do: Map.put(state.child_tokens, token, %{entry | cancelled: true}),
            else: Map.delete(state.child_tokens, token)

        {:noreply, %{state | child_tokens: tokens}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast(:stop, state) do
    state = if state.child_report != nil, do: stop_child_owner(state), else: state
    state = close_resources(state)
    if is_pid(state.worker), do: Process.exit(state.worker, :kill)
    report_child(state, if(state.failed, do: {:error, :cleanup_unconfirmed}, else: :ok))
    {:stop, :normal, state}
  end

  @impl true
  def init({:child, root, peer, reporter, token}) do
    Process.flag(:trap_exit, true)

    with {:ok, ticket, guard} <- GenServer.call(root, {:register_child, peer, reporter, token}) do
      {:ok,
       %{
         owner: peer,
         owner_ref: Process.monitor(peer),
         worker: nil,
         worker_ref: nil,
         tasks: %{},
         effects: %{},
         lock_guard: guard,
         resources: %{},
         failed: false,
         closed: false,
         child_tokens: %{},
         child_report: {ticket, reporter, token},
         finish_permitted: false
       }}
    else
      _ -> {:stop, :cleanup_scope_closed}
    end
  end

  def init(owner) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       owner: owner,
       owner_ref: Process.monitor(owner),
       worker: nil,
       worker_ref: nil,
       tasks: %{},
       effects: %{},
       lock_guard: Ipse.Session.Lock.for_owner(owner),
       resources: %{},
       failed: false,
       closed: false,
       child_tokens: %{},
       child_report: nil
     }}
  end

  @impl true
  def handle_call({:attach, worker}, _, %{worker: nil} = state) do
    {:ok, _} = Registry.register(Ipse.Registry, {__MODULE__, worker}, nil)
    Process.link(worker)
    {:reply, :ok, %{state | worker: worker, worker_ref: Process.monitor(worker)}}
  end

  def handle_call({:register, kind, pid}, {pid, _}, %{closed: false} = state)
      when kind in [:shell, :lock, :extension, :mcp, :http] and map_size(state.resources) < 32 do
    :ok = Ipse.Session.Lock.track_in(state.lock_guard, pid, :peer)
    id = make_ref()
    resource = %{pid: pid, kind: kind, monitor: Process.monitor(pid)}
    ticket = %{scope: self(), id: id}
    {:reply, {:ok, ticket}, %{state | resources: Map.put(state.resources, id, resource)}}
  end

  def handle_call({:track_task, pid}, {caller, _}, %{closed: false} = state) when is_pid(pid) do
    if caller in [state.owner, state.worker] or Map.has_key?(state.tasks, caller) do
      :ok = Ipse.Session.Lock.track_in(state.lock_guard, pid, :worker)
      {:reply, :ok, %{state | tasks: Map.put(state.tasks, pid, Process.monitor(pid))}}
    else
      {:reply, {:error, :cleanup_scope_closed}, state}
    end
  end

  def handle_call({:track_effect, pid}, {caller, _}, %{closed: false} = state)
      when is_pid(pid) and map_size(state.effects) < 32 do
    if caller in [state.owner, state.worker] or Map.has_key?(state.tasks, caller) do
      :ok = Ipse.Session.Lock.track_in(state.lock_guard, pid, :peer)
      {:reply, :ok, %{state | effects: Map.put(state.effects, pid, Process.monitor(pid))}}
    else
      {:reply, {:error, :cleanup_scope_closed}, state}
    end
  end

  def handle_call({:track_child_effect, pid, token}, {caller, _}, %{closed: false} = state)
      when is_pid(pid) and is_reference(token) and map_size(state.effects) < 32 and
             map_size(state.child_tokens) < 32 do
    if (caller == state.worker or Map.has_key?(state.tasks, caller)) and
         not Map.has_key?(state.child_tokens, token) and
         Process.alive?(pid) and Process.alive?(caller) and Process.alive?(state.owner) do
      :ok = Ipse.Session.Lock.track_in(state.lock_guard, pid, :peer)
      entry = %{peer: pid, reporter: caller, child: nil, guard: nil, cancelled: false}

      {:reply, {:ok, state.owner},
       %{
         state
         | effects: Map.put(state.effects, pid, Process.monitor(pid)),
           child_tokens: Map.put(state.child_tokens, token, entry)
       }}
    else
      {:reply, {:error, :cleanup_scope_closed}, state}
    end
  end

  def handle_call({:register_child, peer, reporter, token}, {child, _}, %{closed: false} = state) do
    case state.child_tokens[token] do
      %{peer: ^peer, reporter: ^reporter, child: nil, cancelled: false} = entry ->
        if Process.alive?(peer) and Process.alive?(reporter) and Process.alive?(state.owner) do
          :ok = Ipse.Session.Lock.track_child_scope(state.lock_guard, child)
          id = make_ref()
          resource = %{pid: child, kind: :child, monitor: Process.monitor(child)}
          ticket = %{scope: self(), id: id}

          {:reply, {:ok, ticket, state.lock_guard},
           %{
             state
             | resources: Map.put(state.resources, id, resource),
               child_tokens: Map.put(state.child_tokens, token, %{entry | child: child})
           }}
        else
          {:reply, {:error, :cleanup_scope_closed}, state}
        end

      _ ->
        {:reply, {:error, :cleanup_scope_closed}, state}
    end
  end

  def handle_call({:track_child_guard, guard, token}, {peer, _}, %{closed: false} = state)
      when is_pid(guard) do
    case state.child_tokens[token] do
      %{peer: ^peer, guard: nil, cancelled: false} = entry when is_pid(state.owner) ->
        if Process.alive?(state.owner) do
          :ok = Ipse.Session.Lock.track_in(state.lock_guard, guard, :peer)

          {:reply, :ok,
           %{
             state
             | effects: Map.put(state.effects, guard, Process.monitor(guard)),
               child_tokens: Map.put(state.child_tokens, token, %{entry | guard: guard})
           }}
        else
          {:reply, {:error, :cleanup_scope_closed}, state}
        end

      _ ->
        {:reply, {:error, :cleanup_scope_closed}, state}
    end
  end

  def handle_call({:child_cancelled, token, peer}, {reporter, _}, state) do
    case state.child_tokens[token] do
      %{peer: ^peer, reporter: ^reporter} = entry ->
        {:reply, {entry.child, entry.guard},
         %{state | child_tokens: Map.put(state.child_tokens, token, %{entry | cancelled: true})}}

      _ ->
        {:reply, :unconfirmed, state}
    end
  end

  def handle_call({:forget_child, token, peer}, {reporter, _}, state) do
    case state.child_tokens[token] do
      %{peer: ^peer, reporter: ^reporter, cancelled: true} ->
        {:reply, :ok, %{state | child_tokens: Map.delete(state.child_tokens, token)}}

      _ ->
        {:reply, {:error, :cleanup_scope_closed}, state}
    end
  end

  def handle_call(
        {:prepare_child_finish, token},
        {owner, _},
        %{owner: owner, child_report: {_, _, token}, finish_permitted: false, closed: false} =
          state
      ) do
    {:reply, :ok, %{state | finish_permitted: true}}
  end

  def handle_call(
        {:authorized_effect, worker, caller},
        {owner, _},
        %{owner: owner, worker: worker, closed: false} = state
      ) do
    {:reply,
     Process.alive?(owner) and Process.alive?(worker) and Process.alive?(caller) and
       (caller == worker or Map.has_key?(state.effects, caller)), state}
  end

  def handle_call({:authorized_effect, _, _}, _, state), do: {:reply, false, state}

  def handle_call(:active, {caller, _}, %{closed: false} = state) do
    admitted =
      caller in [state.owner, state.worker] or Map.has_key?(state.tasks, caller) or
        Map.has_key?(state.effects, caller)

    {:reply, admitted and Process.alive?(state.owner), state}
  end

  def handle_call(:active, _, state), do: {:reply, false, state}

  def handle_call(action, {caller, _}, state) when action in [:close, :finish] do
    state =
      if state.child_report != nil and
           (caller != state.owner or not state.finish_permitted),
         do: stop_child_owner(state),
         else: state

    state = close_resources(state)
    result = if state.failed, do: {:error, :cleanup_unconfirmed}, else: :ok

    if action == :close or state.child_report != nil, do: report_child(state, result)

    if action == :close or state.child_report != nil,
      do: {:stop, :normal, result, state},
      else: {:reply, result, %{state | closed: true}}
  end

  def handle_call(_, _, state), do: {:reply, {:error, :cleanup_scope_closed}, state}

  @impl true
  def handle_info({:resource_closed, id, pid, result}, state) do
    case state.resources[id] do
      %{pid: ^pid, monitor: monitor} ->
        Process.demonitor(monitor, [:flush])

        {:noreply,
         %{
           state
           | resources: Map.delete(state.resources, id),
             failed: state.failed or result != :ok
         }}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state) do
    if is_pid(state.worker), do: Process.exit(state.worker, :kill)
    state = close_resources(state)
    report_child(state, if(state.failed, do: {:error, :cleanup_unconfirmed}, else: :ok))
    {:stop, :normal, state}
  end

  def handle_info({:ipse_cancel_resource, id}, %{child_report: {%{id: id}, _, _}} = state) do
    state = stop_child_owner(state)
    state = close_resources(state)
    report_child(state, if(state.failed, do: {:error, :cleanup_unconfirmed}, else: :ok))
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{worker_ref: ref, closed: true} = state),
    do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _, _}, %{worker_ref: ref} = state) do
    state = close_resources(state)
    if state.failed, do: send(state.owner, {:owned_task_cleanup_failed, state.worker})
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    case Enum.find(state.resources, fn {_, resource} -> resource.monitor == ref end) do
      {id, _} ->
        send(state.owner, {:owned_task_cleanup_failed, state.worker})
        {:noreply, %{state | resources: Map.delete(state.resources, id), failed: true}}

      nil ->
        tasks = Map.reject(state.tasks, fn {_, monitor} -> monitor == ref end)
        dead = Enum.find_value(state.effects, fn {pid, monitor} -> if monitor == ref, do: pid end)
        effects = Map.reject(state.effects, fn {_, monitor} -> monitor == ref end)

        tokens =
          Map.reject(state.child_tokens, fn {_, entry} ->
            entry.peer == dead and entry.cancelled and is_nil(entry.child)
          end)

        {:noreply, %{state | tasks: tasks, effects: effects, child_tokens: tokens}}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{resources: map_size(state.resources), failed: state.failed}}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp close_resources(state) do
    deadline = System.monotonic_time(:millisecond) + 4_000

    state =
      Enum.reduce(state.resources, state, fn {id, resource}, state ->
        result = close_resource(id, resource, deadline)
        Process.demonitor(resource.monitor, [:flush])

        %{
          state
          | resources: Map.delete(state.resources, id),
            failed: state.failed or result != :ok
        }
      end)

    Enum.each(state.tasks, fn {pid, _} -> Process.exit(pid, :kill) end)

    failed =
      Enum.reduce(state.tasks, state.failed, fn {pid, ref}, failed ->
        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> failed
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> true
        end
      end)

    failed =
      Enum.reduce(state.effects, failed, fn {pid, ref}, failed ->
        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> failed
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> true
        end
      end)

    %{state | tasks: %{}, effects: %{}, failed: failed}
  end

  defp close_resource(id, resource, deadline) do
    case receipt(id, resource.pid, 0) do
      nil ->
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        result =
          cond do
            remaining == 0 ->
              {:error, :cleanup_unconfirmed}

            resource.kind == :extension ->
              Ipse.Extension.Worker.close(resource.pid, min(remaining, 3_000))

            resource.kind == :mcp ->
              Ipse.MCP.StdioTransport.close(resource.pid, min(remaining, 3_000))

            true ->
              send(resource.pid, {:ipse_cancel_resource, id})
              receipt(id, resource.pid, min(remaining, 2_500)) || {:error, :cleanup_unconfirmed}
          end

        result =
          if result == :ok,
            do: :ok,
            else:
              receipt(
                id,
                resource.pid,
                min(max(deadline - System.monotonic_time(:millisecond), 0), 100)
              ) ||
                result

        if result != :ok and resource.kind in [:extension, :mcp],
          do: Process.exit(resource.pid, :kill)

        result

      result ->
        result
    end
  end

  defp receipt(id, pid, timeout) do
    receive do
      {:resource_closed, ^id, ^pid, result} -> result
    after
      timeout -> nil
    end
  end

  defp report_child(%{child_report: {ticket, reporter, token}}, result) do
    closed(ticket, result)
    send(reporter, {:child_scope_finished, token, self(), result})
  end

  defp report_child(_, _), do: :ok

  defp stop_child_owner(state) do
    Process.exit(state.owner, :kill)

    receive do
      {:DOWN, ref, :process, owner, _} when ref == state.owner_ref and owner == state.owner ->
        state
    after
      4_000 -> %{state | failed: true}
    end
  end

  @effect_key {__MODULE__, :active}
  @effect_owner_key {__MODULE__, :effect_owner}

  @doc false
  # Use only for a reviewed native-controller or owned-transport operation whose
  # complete effects and cleanup are fenced by this scope. Unlike file_effect/2,
  # timeout kills the peer. Never wrap arbitrary file-server or other IO that may
  # continue after that peer dies. The caller must stop on cleanup uncertainty.
  def controlled_owned_effect(fun, timeout) when is_function(fun, 0) and timeout in 1..120_000 do
    if Process.get(@effect_key),
      do: {:error, :nested_controlled_effect},
      else: controlled_owned_effect_start(fun, timeout)
  end

  defp controlled_owned_effect_start(fun, timeout) do
    root = current()
    reporter = self()
    upstream = file_effect_owner()
    token = make_ref()
    deadline = System.monotonic_time(:millisecond) + timeout

    if is_pid(root) and active?(min(timeout, 5_000)) do
      {peer, monitor} =
        spawn_monitor(fn ->
          peer_ref = Process.monitor(reporter)
          root_ref = Process.monitor(root)

          receive do
            {:begin_controlled, ^reporter, session_owner} ->
              Process.demonitor(peer_ref, [:flush])
              Process.demonitor(root_ref, [:flush])
              controlled_peer(root, reporter, session_owner, upstream, token, fun)

            {:DOWN, ^peer_ref, :process, _, _} ->
              :ok

            {:DOWN, ^root_ref, :process, _, _} ->
              :ok
          end
        end)

      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      tracked =
        if remaining > 0 do
          try do
            GenServer.call(root, {:track_child_effect, peer, token}, min(remaining, 5_000))
          catch
            :exit, _ -> :unconfirmed
          end
        else
          :unconfirmed
        end

      case tracked do
        {:ok, session_owner} ->
          send(peer, {:begin_controlled, reporter, session_owner})

          controlled_wait(
            root,
            peer,
            monitor,
            token,
            max(deadline - System.monotonic_time(:millisecond), 0)
          )

        _ ->
          Process.exit(peer, :kill)
          GenServer.cast(root, {:abandon_child, token, peer, reporter})

          receive do
            {:DOWN, ^monitor, :process, ^peer, _} -> :ok
          after
            4_000 -> :ok
          end

          {:unknown, :cleanup_unconfirmed}
      end
    else
      {:error, :cleanup_scope_closed}
    end
  catch
    :exit, _ -> {:unknown, :cleanup_unconfirmed}
  end

  defp controlled_peer(root, reporter, session_owner, upstream, token, fun) do
    peer = self()

    guard =
      spawn_link(fn ->
        parent_ref = Process.monitor(reporter)
        session_ref = Process.monitor(session_owner)
        root_ref = Process.monitor(root)
        peer_ref = Process.monitor(peer)
        send(peer, {:guard_ready, self()})
        controlled_guard(peer, parent_ref, session_ref, root_ref, peer_ref, nil, nil)
      end)

    receive do
      {:guard_ready, ^guard} -> :ok
    end

    :ok = GenServer.call(root, {:track_child_guard, guard, token})

    case start_child(root, peer, reporter, token) do
      {:ok, child} ->
        Process.link(child)
        send(guard, {:watch_child, peer, child})

        receive do
          {:child_watched, ^guard} -> :ok
        end

        bind(child)
        Process.put(@effect_key, true)
        Process.put(@effect_owner_key, upstream)

        result =
          try do
            {:returned, fun.()}
          catch
            _, _ -> {:failed, :effect_failed}
          end

        :ok = GenServer.call(child, {:prepare_child_finish, token})
        send(guard, {:finish_child, peer})

        receive do
          {:child_unwatched, ^guard} -> :ok
        end

        _ = close(child)
        send(reporter, {:controlled_result, token, peer, result})

      _ ->
        send(reporter, {:controlled_result, token, peer, {:failed, :child_unavailable}})
    end
  end

  defp controlled_guard(peer, parent_ref, session_ref, root_ref, peer_ref, child, child_ref) do
    receive do
      {:watch_child, ^peer, pid} when is_nil(child_ref) and is_pid(pid) ->
        ref = Process.monitor(pid)
        send(peer, {:child_watched, self()})
        controlled_guard(peer, parent_ref, session_ref, root_ref, peer_ref, pid, ref)

      {:finish_child, ^peer} when is_reference(child_ref) ->
        if Process.alive?(child) do
          Process.demonitor(child_ref, [:flush])
          send(peer, {:child_unwatched, self()})
          controlled_guard(peer, parent_ref, session_ref, root_ref, peer_ref, nil, nil)
        else
          Process.exit(peer, :kill)
        end

      {:DOWN, ^parent_ref, :process, _, _} ->
        Process.exit(peer, :kill)

      {:DOWN, ^session_ref, :process, _, _} ->
        Process.exit(peer, :kill)

      {:DOWN, ^root_ref, :process, _, _} ->
        Process.exit(peer, :kill)

      {:DOWN, ^peer_ref, :process, _, _} ->
        :ok

      {:DOWN, ref, :process, _, _} when ref == child_ref ->
        Process.exit(peer, :kill)
    end
  end

  defp controlled_wait(root, peer, monitor, token, timeout) do
    result =
      receive do
        {:controlled_result, ^token, ^peer, value} -> value
        {:DOWN, ^monitor, :process, ^peer, _} -> :down
      after
        timeout ->
          Process.exit(peer, :kill)
          :timeout
      end

    cleanup_deadline = System.monotonic_time(:millisecond) + 4_000

    down =
      if result == :down do
        true
      else
        receive do
          {:DOWN, ^monitor, :process, ^peer, _} -> true
        after
          cleanup_remaining(cleanup_deadline) -> false
        end
      end

    remaining = cleanup_remaining(cleanup_deadline)
    if remaining == 0, do: exit(:cleanup_unconfirmed)
    status = GenServer.call(root, {:child_cancelled, token, peer}, remaining)

    {_child, guard} = if match?({_, _}, status), do: status, else: {nil, nil}

    guard_down =
      if is_pid(guard) do
        guard_ref = Process.monitor(guard)

        receive do
          {:DOWN, ^guard_ref, :process, ^guard, _} -> true
        after
          cleanup_remaining(cleanup_deadline) ->
            Process.demonitor(guard_ref, [:flush])
            false
        end
      else
        false
      end

    cleanup =
      case status do
        {nil, guard} when is_pid(guard) ->
          :ok

        {child, guard} when is_pid(child) and is_pid(guard) ->
          receive do
            {:child_scope_finished, ^token, ^child, result} -> result
          after
            cleanup_remaining(cleanup_deadline) -> {:error, :cleanup_unconfirmed}
          end

        _ ->
          {:error, :cleanup_unconfirmed}
      end

    remaining = cleanup_remaining(cleanup_deadline)
    if remaining == 0, do: exit(:cleanup_unconfirmed)
    :ok = GenServer.call(root, {:forget_child, token, peer}, remaining)

    cond do
      not down or not guard_down or cleanup != :ok -> {:unknown, :cleanup_unconfirmed}
      match?({:returned, _}, result) -> {:ok, elem(result, 1)}
      true -> {:unknown, :effect_interrupted}
    end
  catch
    :exit, _ -> {:unknown, :cleanup_unconfirmed}
  end

  defp cleanup_remaining(deadline),
    do: max(deadline - System.monotonic_time(:millisecond), 0)

  @doc false
  def file_effect_owner, do: Process.get(@effect_owner_key, self())

  @doc false
  def bind_effect_owner(owner) when is_pid(owner) and node(owner) == node() do
    case Process.get(@effect_owner_key) do
      nil ->
        Process.put(@effect_owner_key, owner)
        :ok

      ^owner ->
        :ok

      _ ->
        {:error, :effect_owner_already_bound}
    end
  end

  def bind_effect_owner(_), do: {:error, :invalid_effect_owner}

  def file_effect(fun, guard \\ Ipse.Session.Lock.current()) when is_function(fun, 0) do
    if Process.get(@effect_key) do
      fun.()
    else
      perform_file_effect(fun, guard)
    end
  end

  defp perform_file_effect(fun, guard) do
    owner = self()
    scope = current()
    {pid, ref} = spawn_monitor(fn -> execute_file_effect(owner, scope, fun) end)

    try do
      case scope do
        nil -> :ok = Ipse.Session.Lock.track_in(guard, pid, :peer)
        scope -> :ok = GenServer.call(scope, {:track_effect, pid})
      end
    catch
      kind, reason ->
        Process.exit(pid, :kill)
        Process.demonitor(ref, [:flush])
        :erlang.raise(kind, reason, __STACKTRACE__)
    end

    send(pid, {:begin_file_effect, owner})

    receive do
      {^pid, {:returned, value}} ->
        Process.demonitor(ref, [:flush])
        value

      {^pid, {:raised, kind, reason, stack}} ->
        Process.demonitor(ref, [:flush])
        :erlang.raise(kind, reason, stack)

      {:DOWN, ^ref, :process, ^pid, _} ->
        exit(:file_effect_unconfirmed)
    end
  end

  defp execute_file_effect(owner, scope, fun) do
    ref = Process.monitor(owner)

    receive do
      {:begin_file_effect, ^owner} ->
        bind(scope)
        Process.put(@effect_key, true)
        Process.put(@effect_owner_key, owner)

        result =
          try do
            {:returned, fun.()}
          catch
            kind, reason -> {:raised, kind, reason, __STACKTRACE__}
          end

        send(owner, {self(), result})

      {:DOWN, ^ref, :process, ^owner, _} ->
        :ok
    end
  end
end
