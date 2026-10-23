Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../2026-10-22-before-structural-consolidation/docs/developer/text-streams.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Owning a private visible-text stream

`Ipse.TextStream` is a bounded broker for visible provider text. It preserves order
and concatenation while applying per-consumer acknowledgments and pressure.
The terminal progress stream remains separate. Saved assistant/native messages
remain authoritative and unchanged; private thinking and summary deltas never
enter this channel.

Read `lib/ipse/text_stream.ex` with `test/text_stream_test.exs`. Session owns the
broker, registers the actual provider task as producer, and retains any required
delivery policy. Independent worker resources are managed by
`Ipse.Extensions.TextResources` through the same broker.

## Subscribe, consume, and release

While idle, `Session.subscribe_text(session)` returns
`{:ok, %{server: pid, subscription_id: id}}`. Version 2 adds explicit ephemeral
source identity through `Session.subscribe_text(session, 2)`.
`required: true` makes successful terminal delivery part of main-response admission.
Busy Session enrollment refuses. No embedded/selected consumers means no broker.

Normal messages are `{:ipse_text, server, frame}`. Consume and acknowledge each
normal frame before waiting for the next. The broker fixture's drain loop uses
this pattern:

```elixir
receive do
  {:ipse_text, server, %{"sequence" => sequence} = frame} when server == handle.server ->
    :ok = Ipse.TextStream.ack(handle, sequence)
    frame
end
```

`handle` belongs to the enrolled consumer PID. A real client repeats this receive
until end/closure and monitors `handle.server`; the one-frame example illustrates
the exact acknowledgment call. Wrong callers, stale/duplicate sequence, and stale
producers refuse. Keep handles private; workers receive opaque serialized handles,
never host PIDs. `TextStream.unsubscribe/1` releases a live enrollment; the Session
owner can use `Session.unsubscribe_text/2` while idle, including for a lost broker.

| Kind | Meaning |
| --- | --- |
| `start` | Main request begins; request ID matches canonical accounting |
| `text` | Valid UTF-8 text, at most 2,048 bytes |
| `end` | Completed/failed/cancelled/unknown provider outcome; `complete` describes this delivery |
| `closed` | Unsequenced incomplete closure with fixed reason and queued/pending/unacknowledged counts |

Normal frames carry version, session, generation 1, request/stream/subscription IDs,
and consecutive delivery sequence. V1 stream ID equals request ID. V2 uses fresh
stream identity plus a typed source; see [stream events](stream-events.md).
`closed` is not acknowledged by embedded clients. A broker `DOWN` without completed
end also means incomplete; an untrappable kill cannot send a final notice.

## Apply pressure outside Session

The broker permits four consumers. Each has one outstanding frame, at most 64
queued entries, and 64 KiB queued text. Adjacent text for one request coalesces
without changing concatenation. Delivery splits at UTF-8 boundaries. Direct
`push/3` accepts at most 64 KiB; Session's `push_delta/3` fragments a larger valid
provider delta sequentially without widening buffers or queuing all pieces.

One producer call of at most 64 KiB may wait outside queues. If a consumer cannot
admit it, the provider task waits while Session remains responsive. A five-second
pressure deadline closes blocking subscriptions explicitly, leaving healthy peers.
Optional consumers detach and inference proceeds; required loss fails delivery.
Start/end controls obey the same 64-entry limit. Cancellation releases blocked
pushes and marks accepted text incomplete. Consumer death frees its buffer;
Session death stops broker and producer.

Session syncs request admission, registers the owned task before its dispatch
barrier, and allows only that producer to begin/push/finish. After provider outcome
accounting commits, the producer queues end. Optional consumers do not delay answer
admission for terminal acknowledgment; required consumers do, within five seconds.
Paid usage remains recorded even when required delivery prevents answer admission.

`end` reports provider transport and this consumer's coverage, not a durable answer
commit. A healthy optional peer can see completed/complete before a required peer
times out and the Session refuses the answer. No corrective frame rewrites that
transport fact. Use Session's result for turn success or `answer.committed` for an
admitted-answer workflow.

## Keep required policy after unexpected loss

Unexpected callback/consumer/broker loss does not implicitly unsubscribe a required
enrollment. Main inference stays refused until an explicit release. A replacement
consumer alone cannot erase the lost requirement. Summary requests have no visible
frames and cannot clear it. Releasing during an active required stream still
fails that request. Embedded requirements are process-local; resume recreates none.

Selected workers declare `stream.text` under normal trust/expiry/identity. At most
four selected plus embedded consumers fit the same capacity. Insufficient capacity
refuses startup before initialization or inference. Optional delivery describes
post-enrollment failures, not permission to skip startup validation.
Operator artifact trust may set `text_required: true`; project options and artifact
code cannot grant required status.

Session syncs `extension_text_intent`, owns/registers the consumer, waits for actual
broker readiness, and syncs ready before main dispatch. A live PID alone is not an
enrollment check. Workers can remain across turns. Failed workers do not restart
within the same turn. Fresh operator input can create a new optional resource only
after confirmed cleanup. A detached still-closing optional worker is reported and
not replaced concurrently. Lost required enrollment must be explicitly released.

## Implement the worker callback

`handle("stream.text", payload, state)` receives outer API version 1, an opaque
32-hex `handle`, and the complete negotiated `frame`. Return exactly an ack echoing
the actual values:

```elixir
%{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
  "sequence" => payload["frame"]["sequence"]}
```

For an unsequenced `closed`, the worker contract uses sequence zero. Extra keys,
wrong handles/sequences, ordinary results, or `host_call` refuse. This is a read-only
resource, not a transform or action lane. Callbacks have five-second deadlines,
64 MiB cumulative native output-traffic cap, and 24-hour helper lifetime ceiling.
Expiry is checked before initialization and each frame/reply acknowledgment.

Intent/ready/closed receipts bind activation, resource/session/turn, and intent
digest. Closed retains fixed reason, nullable acknowledged counts, and actual
cleanup acknowledgment. Frame text remains ephemeral and is never journaled.
Recovery validates receipts before tail repair but initializes/replays nothing.
Host cancellation closes workers and, after confirmed cleanup, releases extension
enrollments so fresh input can initialize them under the unchanged trust policy.
Embedded enrollments are independent. Missing cleanup remains fail closed; native
receipt, VM exit, and successful inference are different facts.

An owner guardian stops blocked consumers after Session death. Broker status
formatting redacts private payload/state. Raw `:sys.get_state` remains privileged
inspection and must use synthetic data.

## Practice a delivery change

Read "full buffers backpressure the producer" and "slow consumer gets explicit
bounded shutdown" in `test/text_stream_test.exs`. Identify what remains responsive
while push waits. Then inspect the mixed optional/required peer case in
`test/text_stream_session_test.exs` and compare accounting to admitted history.

```sh
mix test test/text_stream_test.exs test/text_stream_session_test.exs test/extensions_text_test.exs
```

These suites establish pressure, Unicode concatenation, exact caller/sequence
binding, large provider deltas, cancellation/owner death, required failure,
independent-worker callbacks, and inert recovery. For a queue change, test both
text and control saturation. A fast consumer success case cannot establish bounded
behavior under pressure.
