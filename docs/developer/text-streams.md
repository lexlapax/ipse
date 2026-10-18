# Private visible-text delivery

`Ipse.TextStream` owns bounded private visible-text delivery independently of
optional diagnostics. Embedded clients enroll through Session; installed workers
enroll through an explicitly trusted/selected `stream.text` capability. Both use
the same acknowledged frame channel. Consumers are optional by default: losing
their live delivery does not discard successful inference. An operator can
explicitly require delivery. V1 remains the default; explicit v2
negotiation adds [ephemeral event sources](stream-events.md) with stream/range
identity. There is no audio transport or separate stream CLI flag.

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

Use `Session.subscribe_text(session, 2)` for source-bearing v2 frames. Independent
workers additionally declare `stream.text.events` alongside `stream.text`.
Version selection changes no approval or effect authority. See
[v2 fields and identity](stream-events.md#occurrence-identity-and-delivery-position).

Embedding may opt into `Session.subscribe_text(session, 2, required: true)`.
Required consumers must acknowledge the completed stream, including its `end`,
before the response is admitted. Closure, broker loss or the five-second pressure/
completion deadline then fails the request with a distinct required-delivery
diagnosis. This policy is private enrollment state, not a new frame version.
Unexpected worker callback failure is consumer loss, never an automatic explicit
unsubscribe. Unexpected consumer loss between turns retains the requirement: subsequent main
inference is refused until the lost enrollment is explicitly released. Required
broker loss likewise prevents silent replacement with optional delivery. Summary
requests receive no visible frames and cannot clear the main delivery policy.
These enrollments are process-local; idle resume recreates neither clients nor
their delivery requirements.

Messages are `{:ipse_text, server, payload}`. Normal frames carry their negotiated version,
session ID, generation 1, request/stream ID, subscription ID, consecutive sequence
number and `kind`:

| Kind | Meaning |
| --- | --- |
| `start` | Main request beginning; request ID matches durable accounting. |
| `text` | Valid UTF-8 `text`, at most 2048 bytes. Chunks are not individual tokens. |
| `end` | Completed/failed/cancelled/unknown `outcome`; `complete` only for completed provider transport with preceding accepted text acknowledged. |
| `closed` | Explicit incomplete shutdown with fixed reason, unsent frame/byte, pending-byte and unacknowledged-byte counts. Unsequenced and not acknowledged. |

V1 uses its request ID as stream ID. V2 has a fresh stream ID, retains request
correlation and adds a typed `source`; subscription closure has its own scope.
Event identity and delivery sequence are separate because coalescing can differ
between consumers. Every consumer retains the same acknowledgment/flow rules.

Call `Ipse.TextStream.ack(handle, sequence)` after consuming each normal frame.
Only the enrolled consumer PID can acknowledge its current outstanding sequence.
Wrong callers, stale/duplicate acknowledgments and stale request producers are
refused. `Ipse.TextStream.unsubscribe(handle)` lets the enrolled consumer remove
its enrollment and release pending flow. While idle, the Session owner can also
release a live or lost enrollment through `Ipse.Session.unsubscribe_text(session,
handle)`. After broker death, this explicit release clears its lost requirements;
enroll replacement consumers before sending another prompt. Unsubscribing during
an active required stream still fails that request. A server `DOWN` without
completed `end` also means incomplete:
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

The operator's `extension_trust` entry can add `"text_required": true` when its
capability ceiling includes `stream.text`. Omission is optional. This setting is
pinned in activation identity and applies to instances using that artifact;
project options and the artifact cannot grant themselves required status.
Readiness/configuration integrity still gates initial activation for every
selected worker. Optional delivery governs failures after enrollment, not an
exemption from startup validation.

On model preparation after fresh operator input, Session syncs an
`extension_text_intent`, registers an owned consumer, then allows its independent
VM to initialize. All selected consumers must become ready before the first main
request of that turn. Readiness/reuse checks actual broker enrollment, not merely
a live consumer PID. Live consumers may remain enrolled across turns; a failed
consumer is not restarted for another model call in the same turn. Fresh explicit
operator input may start a new optional resource with new correlation. A lost
required enrollment must first be explicitly released; replacement alone cannot
remove that requirement. Summary requests receive no private text frames.

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
An optional consumer detaches without failing inference; loss of a required
consumer fails delivery. Cancellation explicitly closes registered workers.
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
without changing concatenation. Delivery splits only at UTF-8 boundaries. Direct
`push/3` calls retain a 64 KiB bound. Session's provider adapter uses `push_delta/3`
to split a larger valid visible delta into sequential UTF-8 pieces within that
bound, reusing the broker's boundary calculation. It forwards the original UI
delta after delivery succeeds or optional consumers detach; saved assistant/native data remain
unchanged. This avoids an invalid-chunk failure caused solely by provider chunk
size without expanding channel buffers. The provider already owns the original
delta; fragmentation adds no queue of pending pieces. One producer call of at
most 64 KiB can wait outside the buffers. If any consumer cannot admit it, the
provider task waits while Session remains responsive.
A five-second pressure deadline closes only blocking subscriptions with explicit
incomplete notices. Healthy peers stay enrolled. The pending producer continues
when optional consumers detach; required delivery loss fails without retry.
Stalled start/end controls also have the 64-entry cap: overflow explicitly closes
the affected consumer. Diagnostic drop/sampling queues are not used for text.

Session journals admission, creates the owned task, registers that exact producer
and releases a dispatch barrier. Consumer calls cannot become producers. After
provider outcome accounting commits, the producer queues the terminal frame.
Optional consumers do not delay response admission for terminal acknowledgments;
required consumers do, within the same five-second bound. Paid usage remains
recorded even when required delivery prevents admission of the completed answer.
An `end` describes this provider transport and this consumer's delivery coverage;
it is not a durable answer-commit receipt. A healthy optional consumer can receive
`outcome: "completed", complete: true` before another required consumer times out
and the Session refuses the answer. There is no corrective transport frame:
the transport did finish, while admission subsequently failed. The same distinction
applies to a journal failure after streaming. Embedded clients must use the Session
result for turn success. Extensions needing admitted answers subscribe to the
durable `answer.committed` event instead of deriving admission from `text.finished`.
Cancel releases a blocked push, marks accepted content incomplete and stops the task.
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
cover large-delta Unicode concatenation and contiguous v2 source ranges, direct
push bounds, caller/sequence checks, pressure deadlines,
cancellation, consumer/owner death, control overload, inert resume and summary/
native exclusion, optional pressure/broker-loss continuation and explicitly
required completion/failure. An independent worker's unconfirmed OS cleanup still
causes close/cancel to report failure; successful inference is not a cleanup receipt.
The reverse mixed-peer fixture also covers healthy optional delivery followed by
required completion failure, retained failed accounting and no admitted assistant.
The source/package hook fixture consumes the raw private stream
alongside completed formatting and durable accounting. See [verification](testing.md).
