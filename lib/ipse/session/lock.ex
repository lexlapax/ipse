defmodule Ipse.Session.Lock do
  @moduledoc "Retains the session lock through owner death until tracked workers and writer exit."
  use GenServer
  @key {__MODULE__, :guard}

  def acquire(path) do
    case GenServer.start(__MODULE__, {path, self()}) do
      {:ok, guard} ->
        port = GenServer.call(guard, :port)
        Process.put(@key, guard)
        {:ok, port}

      error ->
        error
    end
  end

  def current, do: Process.get(@key)

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

  def track_session(child) do
    guard = for_owner(child)
    if is_nil(guard), do: exit(:child_lock_unavailable)
    :ok = track(guard, :peer)
    track(child, :worker)
  end

  def release(guard), do: GenServer.call(guard, :release, :infinity)

  @impl true
  def init({path, owner}) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)

    case Ipse.Runner.lock(path) do
      {:ok, port} ->
        {:ok, _} = Registry.register(Ipse.Registry, {__MODULE__, owner}, nil)
        {:ok, %{owner: owner, owner_ref: monitor, port: port, dependents: %{}, lost: false}}

      error ->
        {:stop, elem(error, 1)}
    end
  end

  @impl true
  def handle_call(:port, {owner, _}, %{owner: owner} = s), do: {:reply, s.port, s}

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

  def handle_call(:release, {owner, _}, %{owner: owner} = s) do
    quiesce(s.dependents)
    result = Ipse.Runner.unlock(s.port)
    {:stop, :normal, result, %{s | dependents: %{}}}
  end

  def handle_call(_, _, s), do: {:reply, {:error, :session_lock_refused}, s}

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = s) do
    quiesce(s.dependents)
    Ipse.Runner.unlock(s.port)
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
