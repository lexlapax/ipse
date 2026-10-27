defmodule Ipse.Session.Resources do
  @moduledoc "Private task cleanup scope; process death never substitutes for an OS-helper receipt."
  use GenServer
  @key {__MODULE__, :scope}

  def start(owner), do: GenServer.start(__MODULE__, owner)
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
  def handle_cast(:stop, state) do
    state = close_resources(state)
    if is_pid(state.worker), do: Process.exit(state.worker, :kill)
    {:stop, :normal, state}
  end

  @impl true
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
       closed: false
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

  def handle_call(action, _, state) when action in [:close, :finish] do
    state = close_resources(state)
    result = if state.failed, do: {:error, :cleanup_unconfirmed}, else: :ok

    if action == :close,
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
        effects = Map.reject(state.effects, fn {_, monitor} -> monitor == ref end)
        {:noreply, %{state | tasks: tasks, effects: effects}}
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

  @effect_key {__MODULE__, :active}
  @effect_owner_key {__MODULE__, :effect_owner}

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
