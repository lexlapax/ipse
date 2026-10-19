# Identifying ephemeral visible-text occurrences

Version-2 text frames give consumers a shared identity for accepted byte ranges.
`Ipse.Lifecycle.Ephemeral` projects them into lifecycle envelopes. They are not
journal positions, provider tokens, hidden reasoning, answer admission, or playback
receipts. Learn this identity model before building a stream-derived index.

## Negotiate a format before inference

Embedded clients call `Session.subscribe_text(session, 2)` while idle; existing
calls keep v1. A selected worker declares and receives operator trust for both
`stream.text` and `stream.text.events`. Its `handle("stream.text", payload, state)`
and outer `api_version: 1` stay unchanged; only `frame.version` becomes 2.
Peers may use different versions on one broker. Unsupported versions refuse before
broker initialization. Negotiation adds no write/model/export permission.

The ordinary [text channel](text-streams.md) retains four consumers, 2 KiB UTF-8
chunks, bounded buffers, exact acknowledgments, and required/optional delivery.

## Read a source independently of its delivery

Each broker creates a random `epoch_id`, independent of runtime/diagnostic epochs.
Each begin creates a fresh `stream_id`, even when an embedded owner reuses the
request ID. V1 retains `stream_id == request_id`; v2 separates those identities.
`generation: 1` is not a restart counter.

Every v2 frame adds one closed `source`:

| Field | Stream start/text/end | Subscription closed |
| --- | --- | --- |
| Common | `version: 1`, `kind: ephemeral`, `session_id`, `epoch_id`, `event_id` | Same |
| Scope | `scope: stream`, `stream_id`, `request_id` | `scope: subscription`, `subscription_id` |
| Position | `start_byte`, `end_byte` | Absent |

Text ranges are half-open accepted UTF-8 bytes. Start is `[0,0)` and end is a point
at the accepted count. Pending text counts only once admitted; cancelled pending
text has no accepted range. Position overflow closes with `position_limit`.
IDs are the first 128 bits of a domain-separated canonical source/frame-kind
digest. They contain no text hash.

For example, two consumers may coalesce the same six accepted bytes differently:

```text
consumer A: text [0,2), text [2,6), end [6,6)
consumer B: text [0,6),             end [6,6)
```

Their text occurrence IDs differ because ranges differ. Their final point ID is
shared even if delivery sequences differ. Sequence orders one consumer's frames;
it is not global occurrence order. Splitting preserves UTF-8 boundaries, while
offsets count bytes rather than characters or graphemes.

`closed` is unsequenced and subscription-scoped. Queued work can span requests or
closure can happen while idle, so it has no invented request or byte position.
Different subscriptions have different closure identities. Existing incomplete
reason/count fields remain available.

## Project only an authorized view

`Ephemeral.valid_frame?/1` checks closed schemas, computed ID, scope bindings,
numeric bounds, Unicode, and exact range length. `project/2` produces a version-1
common envelope with host origin and selected metadata/private data:

| Frame | Event | Data |
| --- | --- | --- |
| Start | `text.started` | Empty metadata |
| Text | `text.delta` | Metadata byte count or `text.visible` text |
| End | `text.finished` | Transport outcome and complete flag |
| Closed | `text.subscription_closed` | Incomplete flag, reason, counts |

Metadata/private projections retain the same source ID. Subscription and sequence
stay in the outer frame. Projection authenticates no worker-supplied frame and
grants no read access. Session binds request IDs to admitted accounting; a
standalone broker cannot prove an arbitrary owner-provided request ID is inference.

Durable `Event.project/3`, history, and live metadata feeds reject these ephemeral
sources. No text frame is journaled or replayed, and idle resume enrolls no
consumer. Acknowledgment confirms receipt, not display, business success, or audio
playback. Another required consumer can fail after this consumer receives a
completed end; use Session's result or `answer.committed` for admitted answers.

## Practice a range change

Read the unequal-consumer-boundary and request-reuse fixtures in
`test/text_stream_test.exs`. Follow `lib/ipse/lifecycle/ephemeral.ex` to see which
fields enter the event ID. Then read negotiated Session cases in
`test/text_stream_session_test.exs`. Compare malformed range refusal with valid
split Unicode text.

```sh
mix test test/text_stream_test.exs test/text_stream_session_test.exs
```

These suites establish byte concatenation/ranges, identity reuse/restart,
cancellation of pending text, idle closure, negotiation, and no effectful replies.
When changing a source field, test both consumers with different coalescing and a
broker restart. A stable ID for one delivery shape does not establish shared
occurrence identity across consumers.
