defmodule Ipse.FileEffect do
  @moduledoc "Private completion owner for admitted filesystem critical sections."
  @key {__MODULE__, :active}

  def run(fun, guard \\ Ipse.Session.Lock.current()) when is_function(fun, 0) do
    if Process.get(@key) do
      fun.()
    else
      perform(fun, guard)
    end
  end

  defp perform(fun, guard) do
    owner = self()
    {pid, ref} = spawn_monitor(fn -> execute(owner, fun) end)

    try do
      case Ipse.TaskResources.current() do
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

  defp execute(owner, fun) do
    ref = Process.monitor(owner)

    receive do
      {:begin_file_effect, ^owner} ->
        Process.put(@key, true)

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
