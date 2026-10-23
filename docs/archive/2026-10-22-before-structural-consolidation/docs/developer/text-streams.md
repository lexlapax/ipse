> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/lifecycle-events.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Consume visible text with bounded delivery

`Ipse.TextStream` brokers visible provider text with ordering, per-consumer
acknowledgments and pressure. Saved assistant/native messages remain authoritative.
Terminal progress is a separate channel; private thinking and summary deltas never
enter this stream. A completed transport frame is not durable answer admission.

Read `lib/ipse/text_stream.ex` beside `test/text_stream_test.exs`. Session owns
the broker, registers the actual provider task as producer and retains required
delivery policy. `Ipse.Extensions.TextResources` manages independent worker
consumers through the same broker. These exercises use synthetic providers and
require a built checkout, not an account or paid inference.

## Enroll before inference and negotiate the frame version

While idle, `Session.subscribe_text(session)` returns
`{:ok, %{server: pid, subscription_id: id}}`. Version two is explicit through
`Session.subscribe_text(session, 2)`. Existing callers keep version one and peers
can use different versions on one broker. Unsupported versions refuse before
broker initialization. Busy enrollment refuses. No embedded/selected consumer
means no broker.

`required:true` makes terminal delivery part of main-response admission. Embedded
requirements belong to this process and are not recreated on resume. Selected
workers declare `stream.text` under ordinary trust, identity and expiry. Version
two also needs `stream.text.events`. Only operator artifact trust can set
`text_required:true`; project options and artifact code cannot grant it.
Four embedded/selected consumers share one capacity. Insufficient capacity
refuses startup before worker initialization or inference, even for optional
delivery.

Session syncs `extension_text_intent`, owns/registers the consumer, waits for real
broker readiness and syncs ready before main dispatch. A live PID is not an
enrollment check. Workers may remain across turns. Failed workers do not restart
within a turn; new input can create a new optional resource only after confirmed
cleanup. A detached still-closing worker remains reported and is not replaced
concurrently. Lost required enrollment needs explicit release.

## Consume and acknowledge frames

Embedded clients receive `{:ipse_text, server, frame}`. Consume and acknowledge
each normal frame before waiting for the next:

```elixir
receive do
  {:ipse_text, server, %{"sequence" => sequence} = frame} when server == handle.server ->
    :ok = Ipse.TextStream.ack(handle, sequence)
    frame
end
```

The handle belongs to the enrolled consumer PID. A complete client repeats this
receive until end/closure and monitors the broker. Wrong callers, stale/duplicate
sequence and stale producers refuse. Keep handles private; workers get opaque
serialized handles, never host PIDs.

| Kind | Meaning |
| --- | --- |
| `start` | Main request begins; request ID matches canonical accounting |
| `text` | Valid UTF-8, at most 2048 bytes |
| `end` | Provider outcome completed/failed/cancelled/unknown and this delivery's complete flag |
| `closed` | Unsequenced incomplete closure with fixed reason and queued/pending/unacknowledged counts |

Normal frames include version, session, generation 1, request/stream/subscription
IDs and consecutive delivery sequence. Embedded clients do not ack `closed`.
Broker `DOWN` without completed end is incomplete; an untrappable kill cannot
send a final notice. `TextStream.unsubscribe/1` releases a live enrollment.
While idle, its Session owner can call `Session.unsubscribe_text/2`, including
for a lost broker.

## Distinguish occurrence identity from delivery order

V1 stream ID equals request ID. V2 gives every broker a fresh random `epoch_id`
and every begin a fresh `stream_id`, even when an owner reuses a request ID.
The broker epoch is independent of runtime/diagnostic epochs; generation 1 is
not a restart counter. Every v2 frame adds a closed source:

| Field | Stream start/text/end | Subscription closed |
| --- | --- | --- |
| Common | Version 1, kind `ephemeral`, session/epoch/event IDs | Same |
| Scope | `stream`, stream/request IDs | `subscription`, subscription ID |
| Position | `start_byte`, `end_byte` | None |

Ranges are half-open accepted UTF-8 byte positions. Start is `[0,0)`; end is a
point at the accepted count. Pending text counts only after admission; cancelled
pending text has no accepted range. Overflow closes with `position_limit`.
The event ID is the first 128 bits of a domain-separated canonical source/frame
kind digest and contains no text hash.

Consumers can coalesce the same accepted bytes differently:

```text
consumer A: text [0,2), text [2,6), end [6,6)
consumer B: text [0,6),             end [6,6)
```

The text IDs differ because the ranges differ; the final point ID is shared even
when delivery sequences differ. Sequence orders one consumer's delivery, not
global occurrences. Splitting respects UTF-8, while offsets count bytes rather
than characters/graphemes. Closed is subscription-scoped because queued work can
span requests and closure can happen while idle. It invents no request/position;
different subscriptions have different closure identities.

`Lifecycle.Ephemeral.valid_frame?/1` checks closed schemas, computed ID, scope,
numeric bounds, Unicode and range length. `project/2` produces a version-one
host envelope with selected metadata/private data:

| Frame | Event | Data |
| --- | --- | --- |
| Start | `text.started` | Empty metadata |
| Text | `text.delta` | Byte count, or selected `text.visible` text |
| End | `text.finished` | Transport outcome and complete flag |
| Closed | `text.subscription_closed` | Incomplete flag, reason and counts |

Views share source ID; subscription/sequence remain in the outer frame. Projection
authenticates no worker-supplied frame and grants no access. Session binds request
IDs to accounting; a standalone broker cannot prove an arbitrary request ID means
inference. Durable Event projection, history and live metadata feeds reject these
ephemeral sources. Text frames are never journaled/replayed.

## Apply pressure while Session stays responsive

Each consumer has one outstanding frame, at most 64 queued entries and 64 KiB
queued text. Adjacent text coalesces without changing concatenation and splits
only on UTF-8 boundaries. Direct `push/3` accepts at most 64 KiB. Session's
`push_delta/3` fragments a larger valid provider delta sequentially without
widening buffers or queuing every piece at once.

One producer call of up to 64 KiB can wait outside queues. If a consumer cannot
admit it, the provider task waits while Session remains responsive. A five-second
pressure deadline closes blocking subscriptions explicitly and leaves healthy
peers. Optional consumers detach; required loss fails delivery. Start/end controls
share the 64-entry limit. Cancellation releases blocked pushes and marks accepted
text incomplete. Consumer death frees its buffer; Session death stops broker and
producer.

Session syncs request admission and registers the owned producer before its
dispatch barrier. Only that task can begin/push/finish. After provider outcome
accounting commits, it queues end. Optional consumers do not delay answer admission
for terminal acknowledgment; required consumers do, within five seconds. Paid
usage stays recorded even when required delivery prevents answer admission.

An end describes transport and consumer coverage. A healthy optional peer can
receive completed/complete before a required peer times out and Session refuses
the answer. No later frame rewrites that earlier transport fact. Acknowledgment
proves receipt, not display, domain success or audio playback. Use Session's
result for turn success or `answer.committed` for admitted-answer workflows.

Unexpected callback, consumer or broker loss does not release required policy.
Main inference stays refused until explicit release; a replacement consumer
alone cannot erase it. Summary has no visible frames and cannot clear it.
Releasing during an active required stream still fails that request.

## Implement a read-only worker consumer

`handle("stream.text", payload, state)` receives outer `api_version:1`, an opaque
32-hex handle and the complete negotiated frame. The outer callback remains the
same for v2. Return exactly:

```elixir
%{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
  "sequence" => payload["frame"]["sequence"]}
```

For unsequenced closed, the worker contract uses sequence zero. Extra keys,
wrong handles/sequences, ordinary results and `host_call` refuse. This is neither
a transform nor an effect lane. Callbacks have five-second deadlines, a 64 MiB
cumulative native-output traffic cap and a 24-hour helper lifetime ceiling.
Expiry is checked before initialization and each frame/reply acknowledgment.

Intent/ready/closed receipts bind activation, resource/session/turn and intent
digest. Closed retains fixed reason, nullable acknowledged counts and actual
cleanup. Recovery validates before tail repair but initializes/replays nothing.
Host cancellation closes workers and, after confirmed cleanup, releases their
enrollments for fresh input under unchanged trust. Embedded enrollments remain
independent. Missing cleanup stays fail closed. Native receipt, VM exit and
successful inference are different facts.

An owner guardian stops blocked consumers after Session death. Broker status
formatting redacts private payload/state. Raw `:sys.get_state` is privileged
inspection and belongs only in synthetic fixtures.

## Verify both coverage and identity under pressure

```sh
mix test test/text_stream_test.exs test/text_stream_session_test.exs test/extensions_text_test.exs
```

Read the full-buffer and slow-consumer cases first. Identify the responsive owner
while push waits, then compare optional/required peers' transport frames with
accounting and admitted history. Saturate both text and control queues.

For a source change, compare unequal consumer boundaries, reused request IDs,
broker restart, idle closure and cancelled pending text. Malformed ranges must
refuse while valid split Unicode concatenates exactly. These cases cover
negotiation, caller/sequence binding, large provider deltas, cancellation/owner
loss, worker callbacks and inert recovery. A fast consumer or one stable delivery
shape cannot establish bounded pressure or shared occurrence identity.
