# Private visible-text delivery

`Ipse.TextStream` owns bounded private visible-text delivery independently of
optional diagnostics. Embedded clients enroll through Session; installed workers
enroll through an explicitly trusted/selected `stream.text` capability. Both use
the same acknowledged frame channel. There is no audio transport or separate
stream CLI flag.

Only main-request visible `{:text, delta}` output enters the channel. Summary
text, native reasoning/signatures, tool payloads, auth and completed presentation
output do not. Saved assistant/native responses remain authoritative. Selecting
a consumer grants no effect, provider, project or export permission.

## Subscribe and acknowledge

While idle, call `Ipse.Session.subscribe_text(session)` to receive
`{:ok, %{server: pid, subscription_id: id}}`. Keep that handle private and monitor
the server. Subscription fails while the Session is busy. Without an embedded
enrollment or selected worker consumer, ordinary CLI/model operation creates no
broker.

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

This PID/handle belongs to local embedding. Workers use the serializable interface
below and never receive a host PID. Frame values satisfy bounded plain-JSON DTOs,
including worst-case escaping at the 2 KiB text limit. Raw media needs a separate
data plane.

## Worker clients

An artifact declares `stream.text` and the operator trust ceiling permits it.
Selection uses the same generic configuration/flags as other extensions. No
export descriptors or `host.actions` are needed solely for this read-only stage.
At most four selected worker consumers are admitted; they share the four-consumer
broker capacity with embedded clients. Insufficient capacity refuses startup
before worker initialization or provider dispatch rather than dropping a peer.

On model preparation after fresh operator input, Session syncs an
`extension_text_intent`, registers an owned consumer, then allows its independent
VM to initialize. All selected consumers must become ready before the first main
request of that turn. Readiness/reuse checks actual broker enrollment, not merely
a live consumer PID. Live consumers may remain enrolled across turns; a failed
consumer is not restarted for another model call in the same turn. Fresh explicit
operator input may start a new resource with new correlation. Summary requests
receive no private text frames.

The worker's `handle("stream.text", payload, state)` receives:

```json
{
  "api_version": 1,
  "handle": "00000000000000000000000000000000",
  "frame": {"version": 1, "kind": "text", "text": "visible delta"}
}
```

This abbreviated frame illustrates the wrapper; actual frames include the
session/subscription/request/stream IDs, generation and sequence listed above.
The opaque handle is host-issued and bound to that consumer/resource. It is not
a Session PID or a permission grant. Return exactly:

```json
{"api_version":1,"kind":"ack","handle":"00000000000000000000000000000000","sequence":1}
```

Echo the actual handle and sequence; an unsequenced `closed` frame uses zero.
Only a valid reply admits the host-side acknowledgment. Extra keys, stale/wrong
handles/sequences, ordinary result objects and `host_call` proposals refuse the
read-only contract. Stream callbacks cannot rewrite output, start a model or
acquire host tools/state/actions. They have the normal five-second callback
deadline, 64 MiB cumulative native output-traffic cap and existing 24-hour helper
lifetime ceiling. Reaching a bound ends that resource without automatic restart.
This worker owns private VM state for
the resource lifetime; ordinary transforms/invocations still use fresh workers.

Expiry is checked before initialization and every frame/reply acknowledgment.
Callback/protocol failure or broker loss closes the subscription incomplete and
reports a fixed status; it does not rewrite provider history or retry a frame.
The original request may continue after a consumer leaves, or fail if the broker's
pressure deadline fires first. Cancellation explicitly closes registered workers.
An independent owner guardian also stops a blocked consumer after untrappable
Session death; Worker/native ownership then closes its VM/process group. This
does not strengthen the documented detached-descendant OS limits.

## Resource receipts and recovery

Intent/ready/closed lifecycle records pin resource ID, activation identity,
session/turn and intent digest. Closed receipts contain fixed reasons, nullable
acknowledged frame/byte counts and explicit cleanup confirmation. Missing/changed
readiness or provenance refuses validation before tail repair. Resource receipts
are mandatory private recovery facts; frame text and live subscriptions are
ephemeral and are not journaled. These are separate from optional diagnostics.

Idle resume initializes no consumer and replays no frames. Only fresh operator
input may enroll a new resource; old committed lifecycle records stay intact.
Terminal callback delivery is best effort and cannot be promised after `:kill`.
Unconfirmed worker cleanup remains explicit and causes subsequent close/cancel
to report failure. `Session.diagnostics/1` reports active consumer count and the
unconfirmed-cleanup flag without raw text/options.

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

`text_stream_test.exs`, `text_stream_session_test.exs`, `extensions_text_test.exs`
and compaction fixtures
cover Unicode concatenation, bounds, caller/sequence checks, pressure deadlines,
cancellation, consumer/owner death, control overload, inert resume and summary/
native exclusion. The source/package hook fixture consumes the raw private stream
alongside completed formatting and durable accounting. See [verification](testing.md).
