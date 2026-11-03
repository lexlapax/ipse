Code.require_file("../../support/worker_handoff_trace.exs", __DIR__)

defmodule Ipse.Test.WorkerHandoffTraceTest do
  use ExUnit.Case, async: false
  alias Ipse.Test.WorkerHandoffTrace

  test "collector records bounded timing and status without return payloads" do
    tracer = WorkerHandoffTrace.start(self())
    pid = self()
    target = {Ipse.Extension.Worker, :bind_stdin, 3}
    started = System.monotonic_time()
    finished = started + System.convert_time_unit(2_000, :microsecond, :native)
    send(tracer, {:trace_ts, pid, :call, target, started})

    send(
      tracer,
      {:trace_ts, pid, :return_from, target, {:ok, "SYNTHETIC_PRIVATE_PAYLOAD"}, finished}
    )

    reference = make_ref()
    send(tracer, {:finish, self(), reference})
    assert_receive {:worker_handoff_trace, ^reference, captured}, 1_000
    assert captured["dropped"] == 0
    report = WorkerHandoffTrace.spans(captured)
    assert [%{"elapsed_us" => 2_000, "outcome" => "ok"}] = report["spans"]
    assert report["unmatched_calls"] == 0
    refute Jason.encode!(report) =~ "SYNTHETIC_PRIVATE_PAYLOAD"
  end
end
