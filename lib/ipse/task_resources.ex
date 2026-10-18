defmodule Ipse.TaskResources do
  @moduledoc "Private task cleanup scope; process death never substitutes for an OS-helper receipt."
  use GenServer
  @key {__MODULE__, :scope}

  def start(owner), do: GenServer.start(__MODULE__, owner)
  def bind(scope), do: Process.put(@key, scope)
  def current, do: Process.get(@key)

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

    Task.async(fn ->
      bind(scope)
      fun.()
    end)
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

  @impl true
  def init(owner) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       owner: owner,
       owner_ref: Process.monitor(owner),
       worker: nil,
       worker_ref: nil,
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
    id = make_ref()
    resource = %{pid: pid, kind: kind, monitor: Process.monitor(pid)}
    ticket = %{scope: self(), id: id}
    {:reply, {:ok, ticket}, %{state | resources: Map.put(state.resources, id, resource)}}
  end

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
    state = close_resources(state)
    if is_pid(state.worker), do: Process.exit(state.worker, :kill)
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
        {:noreply, state}
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

    Enum.reduce(state.resources, state, fn {id, resource}, state ->
      result = close_resource(id, resource, deadline)
      Process.demonitor(resource.monitor, [:flush])
      %{state | resources: Map.delete(state.resources, id), failed: state.failed or result != :ok}
    end)
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
              Ipse.Extensions.Worker.close(resource.pid, min(remaining, 3_000))

            resource.kind == :mcp ->
              Ipse.MCP.Transport.close(resource.pid, min(remaining, 3_000))

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
end
