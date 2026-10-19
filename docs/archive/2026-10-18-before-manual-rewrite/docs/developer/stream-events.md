> Historical reference only. Snapshot of `docs/developer/stream-events.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../developer/stream-events.md).

# Ephemeral visible-text events

The opt-in version-2 [private text channel](text-streams.md) attaches live source
identity to actual deliveries. `Lifecycle.Ephemeral` projects frames into the
shared event-envelope shape. These sources describe accepted visible-text ranges
and subscription closure; they are not journal positions, provider tokens,
hidden reasoning or playback receipts.

## Negotiate before delivery

Embedded consumers call `Session.subscribe_text(session, 2)` or
`TextStream.subscribe(broker, consumer, 2)` while idle. Existing calls keep v1.
An independent artifact additionally declares `stream.text.events`, requiring
`stream.text` and explicit operator trust for both. Its existing
`handle("stream.text", payload, state)` and outer `api_version: 1` remain;
only its negotiated `frame.version` changes to 2. Peers on the same broker can
remain v1. Unsupported versions refuse; an unsupported Session request does not
initialize a broker.

Selection retains ordinary configuration, flags and immutable identity pins.
The extra capability selects a format, granting no write, model or export access.
Default-off behavior, four-consumer capacity, 2 KiB UTF-8 chunks, bounded buffers,
acknowledgments and cancellation retain the existing channel contract. Native
worker output/lifetime bounds still apply. No dependency or broker service is added.

## Occurrence identity and delivery position

Each broker has a fresh random `epoch_id`, distinct from diagnostic/runtime epoch
recording. Each `begin` gets a fresh `stream_id`, including if an embedded owner
reuses a request ID. V2 `request_id` retains the owner's host request correlation;
v2 `stream_id` identifies this actual stream. V1 retains `stream_id == request_id`.
`generation: 1` is not an activation/epoch counter.

V2 adds exactly one `source` object to each existing frame kind:

| Fields | Stream-scoped start/text/end | Subscription-scoped closed |
| --- | --- | --- |
| Common | `version: 1`, `kind: "ephemeral"`, `session_id`, `epoch_id`, `event_id` | Same |
| Scope | `scope: "stream"`, `stream_id`, `request_id` | `scope: "subscription"`, `subscription_id` |
| Position | `start_byte`, `end_byte` | Absent |

Actual event IDs are the first 128 bits of the existing canonical digest over a
domain-separated source body and frame kind. They contain no text/content hash.
Text uses the half-open accepted UTF-8 byte range `[start_byte, end_byte)`; start
is `[0,0)` and end is a point at the accepted byte count. Pending text enters the
range only when admitted; cancelled pending text is excluded. Position overflow
closes visibly with `position_limit` instead of wrapping.

Consumers keep separate delivery sequences and may receive different coalesced
ranges. Matching stream/kind/ranges share an occurrence ID across consumers;
different chunk boundaries have different IDs, correlated by their ranges.
Final point identity is shared even when delivery sequence differs. Sequence is
not a global source order, and a frame is not a provider token. Splits stay on
UTF-8 boundaries; offsets count bytes, not characters or graphemes.

Unsequenced `closed` is subscription-scoped, with no invented current request or
stream position: queued work can span requests and closure can happen while idle.
Different subscriptions get different closure identities. Existing incomplete
counts/reasons stay visible.

## Projection and authority

`Ephemeral.valid_frame?/1` checks closed frame/source schemas, computed ID,
request/session/stream binding, numeric bounds, Unicode and exact range length.
`Ephemeral.project(frame, view)` returns a version-1 common envelope with an
ephemeral source and host origin:

| Kind | Event type | Views and data |
| --- | --- | --- |
| `start` | `text.started` | `metadata`: empty data |
| `text` | `text.delta` | `metadata`: output byte count; `text.visible`: selected text |
| `end` | `text.finished` | `metadata`: transport outcome and complete flag |
| `closed` | `text.subscription_closed` | `metadata`: incomplete flag, fixed reason and counts |

Normal events correlate the actual request ID. Closure invents no request link.
Private and metadata views share range identity; subscription/sequence stays in
the outer frame. Projection grants no read authority and authenticates no
worker-supplied frame. Session dispatch binds request IDs to accounting; a
standalone broker cannot prove an owner-provided ID represents admitted inference.

This adapter is separate from durable `Event.project/3` and its metadata validator.
Journal readers, feeds and history do not accept ephemeral sources or gain new
subscription types. No frame is journaled, replayed, automatically indexed or
exported. Native history/accounting stays authoritative. Acknowledgment is receipt,
not presentation, business success or playback. Idle resume starts no consumer;
explicit new work gets new live identity.

`text.finished` reports provider transport completion, including its per-consumer
coverage flag. It does not promise Session admission: another required peer can
fail after this consumer receives its end. Use the Session result or the durable
`answer.committed` subscription for admitted answers; no corrective text event
changes a transport that already completed.

Fixtures cover unequal consumer boundaries, request reuse, broker restart,
Unicode ranges, cancelled pending text, idle closure, malformed bindings and
negotiated Session/worker delivery. Independently compiled workers cover disabled
behavior, no-effect acknowledgments and inert resume. The bundled fixture runs
both versions through a real Session in source/extracted runtimes. The separate
[installed lab](extension-proof.md) verifies v2 worker acknowledgment of start,
visible answer and end, plus public metadata projection. External transport and
voice remain separate capabilities.
