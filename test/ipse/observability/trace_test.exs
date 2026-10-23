defmodule Ipse.DeveloperTraceTest do
  use ExUnit.Case, async: false
  alias Ipse.Observability.Trace

  setup do
    Code.ensure_loaded!(Ipse.Session)
    target = spawn(fn -> loop() end)
    on_exit(fn -> Process.exit(target, :kill) end)
    %{target: target}
  end

  defp loop do
    receive do
      {:burst, count, owner, ref} ->
        for _ <- 1..count do
          apply(Ipse.Session, :handle_info, [
            :synthetic_private_message,
            %{secret: "private-state"}
          ])
        end

        send(owner, {:burst_done, ref})
        loop()
    end
  end

  defp burst(target, count \\ 1) do
    ref = make_ref()
    send(target, {:burst, count, self(), ref})
    assert_receive {:burst_done, ^ref}, 2000
  end

  defp start(target, opts \\ []) do
    {:ok, policy} = Trace.policy([developer_trace: true] ++ opts)
    {:ok, tracer} = Trace.start(target, policy)
    on_exit(fn -> if Process.alive?(tracer), do: Trace.stop(tracer) end)
    tracer
  end

  defp weak(target) do
    Enum.find(:trace.session_info(target), fn {name, _} -> name == :ipse_conformance end)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(5)
          eventually(fun, attempts - 1)
        )
  end

  test "policy is opt-in, closed and bounded" do
    assert {:ok, :off} = Trace.policy([])
    assert {:ok, nil} = Trace.start(self(), :off)

    for opts <- [
          [trace_ms: 10],
          [trace_events: 2],
          [developer_trace: "yes"],
          [developer_trace: true, trace_ms: 0],
          [developer_trace: true, trace_ms: 5001],
          [developer_trace: true, trace_events: 0],
          [developer_trace: true, trace_events: 129]
        ] do
      assert {:error, :invalid_developer_trace_policy} = Trace.policy(opts)
    end
  end

  test "only selected target and fixed arities reach the bounded report", %{target: target} do
    tracer = start(target, trace_events: 1)
    other = spawn(fn -> loop() end)

    try do
      burst(other)
      burst(target)
      eventually(fn -> weak(target) == nil end)
      assert {:ok, report} = Trace.stop(tracer)
      assert report["reason"] == "event_limit"
      assert report["cleanup_confirmed"]
      assert report["captured"] == 1

      assert [
               %{
                 "module" => "Ipse.Session",
                 "function" => "handle_info",
                 "arity" => 2,
                 "sequence" => 1,
                 "elapsed_us" => elapsed
               }
             ] = report["samples"]

      assert elapsed >= 0
      refute report["complete"]
      refute Jason.encode!(report) =~ "private"
    after
      Process.exit(other, :kill)
    end
  end

  test "VM admission permits only one pending sample while collector is suspended", %{
    target: target
  } do
    tracer = start(target, trace_ms: 5000, trace_events: 1)
    :erlang.suspend_process(tracer)

    try do
      burst(target, 10_000)

      assert {:messages, [{:trace_ts, ^target, :call, {Ipse.Session, :handle_info, 2}, _}]} =
               Process.info(tracer, :messages)

      assert {:flags, flags} = :trace.info(weak(target), target, :flags)
      refute :call in flags
      assert :arity in flags
    after
      :erlang.resume_process(tracer)
    end

    eventually(fn -> weak(target) == nil end)
    assert {:ok, %{"captured" => 1, "cleanup_confirmed" => true}} = Trace.stop(tracer)
  end

  test "independent deadline destroys capture even with a suspended collector", %{target: target} do
    tracer = start(target, trace_ms: 50)
    :erlang.suspend_process(tracer)

    try do
      eventually(fn -> weak(target) == nil end)
      burst(target, 100)
      assert {:messages, messages} = Process.info(tracer, :messages)
      refute Enum.any?(messages, &match?({:trace_ts, _, _, _, _}, &1))
    after
      :erlang.resume_process(tracer)
    end

    assert {:ok, report} = Trace.stop(tracer)
    assert report["reason"] == "duration_limit"
    assert report["cleanup_confirmed"]
    assert report["captured"] == 0
  end

  test "owner death revokes capture and closes its collector", %{target: target} do
    {:ok, owner} =
      Agent.start(fn ->
        {:ok, policy} = Trace.policy(developer_trace: true, trace_ms: 5000)
        {:ok, tracer} = Trace.start(target, policy)
        tracer
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    tracer = Agent.get(owner, & &1)
    assert weak(target) != nil
    Process.exit(owner, :kill)
    eventually(fn -> not Process.alive?(tracer) and weak(target) == nil end)
  end

  test "untrappable collector death leaves no session settings", %{target: target} do
    tracer = start(target, trace_ms: 5000)
    assert weak(target) != nil
    Process.exit(tracer, :kill)
    eventually(fn -> weak(target) == nil end)
    assert {:error, :developer_trace_lost} = Trace.stop(tracer)
  end

  test "watchdog death fails closed", %{target: target} do
    tracer = start(target, trace_ms: 5000)
    {:monitors, monitors} = Process.info(tracer, :monitors)
    {:process, guardian} = Enum.find(monitors, fn {:process, pid} -> pid != self() end)
    Process.exit(guardian, :kill)
    eventually(fn -> weak(target) == nil end)

    assert {:ok, %{"reason" => "watchdog_down", "cleanup_confirmed" => true}} =
             Trace.stop(tracer)
  end

  test "target exit and explicit stop remove settings", %{target: target} do
    tracer = start(target)
    trace = weak(target)
    :erlang.suspend_process(tracer)

    try do
      burst(target)
      Process.exit(target, :kill)
      eventually(fn -> trace not in :trace.session_info(:all) end)
    after
      :erlang.resume_process(tracer)
    end

    assert {:ok, report} = Trace.stop(tracer)
    assert report["cleanup_confirmed"]
    assert report["reason"] == "target_down"
    another = spawn(fn -> loop() end)

    try do
      tracer = start(another)

      assert {:ok, %{"reason" => "stopped", "cleanup_confirmed" => true}} =
               Trace.stop(tracer)

      assert weak(another) == nil
    after
      Process.exit(another, :kill)
    end
  end

  test "cleanup does not change another OTP trace session", %{target: target} do
    other = :trace.session_create(:ipse_trace_test, self(), [])

    try do
      :trace.function(other, {Ipse.Session, :handle_info, 2}, [], [])
      :trace.process(other, target, true, [:call, :arity])
      tracer = start(target, trace_events: 1)
      burst(target)
      assert_receive {:trace, ^target, :call, {Ipse.Session, :handle_info, 2}}
      eventually(fn -> weak(target) == nil end)
      assert {:ok, _} = Trace.stop(tracer)
      burst(target)
      assert_receive {:trace, ^target, :call, {Ipse.Session, :handle_info, 2}}
      assert {:flags, flags} = :trace.info(other, target, :flags)
      assert :call in flags
    after
      :trace.session_destroy(other)
    end
  end
end
