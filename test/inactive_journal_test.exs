defmodule Ipse.InactiveJournalTest do
  use ExUnit.Case, async: false
  alias Ipse.Journal
  alias Ipse.Journal.Limits

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-inactive-journal-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Code.ensure_loaded!(Limits)
    previous_priority = Process.flag(:priority, :high)
    :erlang.trace_pattern({Limits, :encode, 2}, true, [:local])

    on_exit(fn ->
      :erlang.trace_pattern({Limits, :encode, 2}, false, [:local])
      File.rm_rf!(root)
    end)

    %{root: root, previous_priority: previous_priority}
  end

  test "inactive append cannot release its real lock ahead of a delayed mutation", c do
    try do
      for mode <- [:append, :append_observed, :append_with_source] do
        {:ok, id} = Journal.create(c.root, %{})
        path = Path.join(c.root, id <> ".jsonl")
        lock = Path.join(c.root, id <> ".lock")
        before = File.read!(path)
        parent = self()
        event = %{"type" => "inactive_gate", "items" => List.duplicate(%{"a" => 1}, 60_000)}

        caller =
          spawn(fn ->
            {:ok, port} = Ipse.Runner.lock(lock)
            send(parent, {:lock_ready, self()})
            receive do: (:go -> :ok)
            result = apply(Journal, mode, [c.root, id, event])
            :ok = Ipse.Runner.unlock(port)
            send(parent, {:append_returned, self(), result})
            receive do: (:finish -> :ok)
          end)

        assert_receive {:lock_ready, ^caller}, 5_000
        encoder = gate(caller)

        try do
          assert File.read!(path) == before
          assert {:error, _} = Ipse.Runner.lock(lock)
          refute_receive {:append_returned, ^caller, _}, 10_500
          assert File.read!(path) == before
          assert {:error, _} = Ipse.Runner.lock(lock)
          true = :erlang.resume_process(encoder)
          assert_receive {:append_returned, ^caller, result}, 5_000
          if mode == :append, do: assert(result == :ok), else: assert(match?({:ok, %{}}, result))
          assert {:ok, [_, ^event]} = Journal.load(c.root, id)
          assert {:ok, next} = Ipse.Runner.lock(lock)
          assert :ok = Ipse.Runner.unlock(next)
        after
          resume(encoder)
          send(caller, :finish)
          if Process.alive?(caller), do: Process.exit(caller, :kill)
        end
      end
    after
      Process.flag(:priority, c.previous_priority)
    end
  end

  test "a tracked inactive append retains its lock after its caller dies", c do
    {:ok, id} = Journal.create(c.root, %{})
    path = Path.join(c.root, id <> ".jsonl")
    lock = Path.join(c.root, id <> ".lock")
    before = File.read!(path)
    parent = self()
    event = %{"type" => "inactive_gate", "items" => List.duplicate(%{"a" => 1}, 60_000)}

    caller =
      spawn(fn ->
        {:ok, _} = Ipse.Session.Lock.acquire(lock)
        send(parent, {:lock_ready, self(), Ipse.Session.Lock.current()})
        receive do: (:go -> :ok)
        Journal.append(c.root, id, event)
      end)

    assert_receive {:lock_ready, ^caller, guard}, 5_000
    encoder = gate(caller)
    guard_monitor = Process.monitor(guard)

    try do
      caller_monitor = Process.monitor(caller)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}, 5_000
      assert Process.alive?(encoder)
      assert File.read!(path) == before
      assert {:error, _} = Ipse.Runner.lock(lock)
      refute_receive {:DOWN, ^guard_monitor, :process, ^guard, _}, 100
      true = :erlang.resume_process(encoder)
      assert_receive {:DOWN, ^guard_monitor, :process, ^guard, :normal}, 5_000
      assert {:ok, [_, ^event]} = Journal.load(c.root, id)
      assert {:ok, next} = Ipse.Runner.lock(lock)
      assert :ok = Ipse.Runner.unlock(next)
    after
      resume(encoder)
      if Process.alive?(caller), do: Process.exit(caller, :kill)
      Process.flag(:priority, c.previous_priority)
    end
  end

  defp gate(caller) do
    :erlang.trace(caller, true, [:call, :set_on_spawn, {:tracer, self()}])
    send(caller, :go)

    receive do
      {:trace, encoder, :call, {Limits, :encode, [%{"type" => "inactive_gate"}, _]}} ->
        true = :erlang.suspend_process(encoder)
        encoder
    after
      5_000 -> flunk("Inactive append did not reach the controlled encoding gate")
    end
  end

  defp resume(pid) do
    :erlang.resume_process(pid)
  catch
    :error, :badarg -> :ok
  end
end
