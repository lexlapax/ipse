# Private visible-text subscriptions

`Ipse.TextStream` implements P22's private text-delivery foundation independently
of optional diagnostics. This is an explicit embedded API, not a CLI flag,
audio transport or installed-worker SDK operation. Only main-request visible
`{:text, delta}` output enters it. Summary text, native reasoning/signatures,
tool payloads, auth and presentation-transform output do not. Saved assistant/
native responses remain authoritative and unchanged.

## Subscribe and acknowledge

While idle, call `Ipse.Session.subscribe_text(session)` to receive
`{:ok, %{server: pid, subscription_id: id}}`. Keep that handle private and monitor
the server. Subscription fails while the Session is busy. Ordinary CLI/model
operation creates no broker. Subscription grants no approvals, model access,
effects, project trust or remote export.

Messages are `{:ipse_text, server, payload}`. Normal frames carry version 1,
session ID, generation 1, request/stream ID, subscription ID, consecutive sequence
number and `kind`:

| Kind | Meaning |
| --- | --- |
| `start` | Main request beginning; request ID matches durable accounting. |
| `text` | Valid UTF-8 `text`, at most 2048 bytes. Chunks are not individual tokens. |
| `end` | Completed/failed/cancelled/unknown `outcome`; `complete` only for completed provider transport with preceding accepted text acknowledged. |
| `closed` | Explicit incomplete shutdown with fixed reason, unsent frame/byte, pending-byte and unacknowledged-byte counts. Unsequenced and not acknowledged. |

Call `Ipse.TextStream.ack(handle, sequence)` after consuming each normal frame.
Only the enrolled consumer PID can acknowledge its current outstanding sequence.
Wrong callers, stale/duplicate acknowledgments and stale request producers are
refused. `Ipse.TextStream.unsubscribe(handle)` removes that consumer and releases
pending flow. A server `DOWN` without completed `end` also means incomplete:
an untrappable broker kill cannot send a notification.

```elixir
{:ok, handle} = Ipse.Session.subscribe_text(session)
monitor = Process.monitor(handle.server)
:ok = Ipse.Session.prompt(session, "Explain the project")

receive do
  {:ipse_text, server, %{"sequence" => sequence} = frame} when server == handle.server ->
    # Consume frame, then continue receiving and acknowledging subsequent frames.
    :ok = Ipse.TextStream.ack(handle, sequence)
    frame
  {:DOWN, ^monitor, :process, _, _} ->
    :incomplete
end
```

This PID/handle belongs to local embedding. Future worker SDK access must wrap
it in host-issued serializable scoped handles; workers do not receive host PIDs.
Frame values satisfy bounded plain-JSON DTOs, including worst-case escaping at
the 2 KiB text limit. Raw media needs a separate data plane.

## Flow control and ownership

Four consumers are permitted. Each has one outstanding frame, at most 64 queued
entries and 64 KiB queued text. Adjacent text for the same request coalesces
without changing concatenation. Delivery splits only at UTF-8 boundaries. One
producer call of at most 64 KiB can wait outside those buffers. If any consumer
cannot admit it, the provider task waits while Session remains responsive.
A 5-second pressure deadline closes subscriptions with explicit incomplete notices
and returns an error to the producer, causing request failure without retry.
Stalled start/end controls also have the 64-entry cap: overflow explicitly closes
the affected consumer. Diagnostic drop/sampling queues are not used for text.

Session journals admission, creates the owned task, registers that exact producer
and releases a dispatch barrier. Consumer calls cannot become producers. After
provider outcome accounting commits, Session queues the terminal frame. Cancel
releases a blocked push, marks accepted content incomplete and stops the task.
Consumer death removes its buffer and releases flow for remaining peers. Session
death stops the broker and dependent task. Live subscriptions/chunks are ephemeral
and never replayed on resume. A broker with no consumers stops validating/delivering
text. This is ownership and flow control, not an OS sandbox.

The primary terminal client's existing progress stream remains separate.
Presentation hooks wrap only completed display; private consumers receive raw
visible provider text. No audio synthesis or hidden reasoning enters this channel.
`format_status/1` redacts payload/state, messages, reasons and logs. Raw
`:sys.get_state`/developer tracing remains privileged private inspection.
Ordinary OTP GenServer calls, monitors, timers and maps add no dependency.

`text_stream_test.exs`, `text_stream_session_test.exs` and compaction fixtures
cover Unicode concatenation, bounds, caller/sequence checks, pressure deadlines,
cancellation, consumer/owner death, control overload, inert resume and summary/
native exclusion. The source/package hook fixture consumes the raw private stream
alongside completed formatting and durable accounting. See [verification](testing.md).
