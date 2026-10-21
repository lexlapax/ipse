> Historical reference only: metadata-only feed contract from commit `b8aae70`, archived 2026-10-17. Use the [current feed contract](../../developer/extension-feeds.md). Relative links were rebased for this snapshot.

# Live lifecycle metadata feeds

Selected extensions can consume supported committed metadata while explicit
session work proceeds. A feed uses one owned worker per declaration and preserves
its private VM state for that lease. Its exact acknowledgments grant no actions,
context changes or provider requests. [Prompt/answer notifications](../../developer/extension-events.md)
retain their ordered barriers and fresh-worker contract; [event jobs](../../developer/extension-events.md#declare-a-job-with-an-exported-handler)
retain separate effect admission. Operator selection and stop are described under
[event subscribers](../2026-10-18-before-manual-rewrite/docs/operator/extensions.md#event-subscribers).

## Declare a feed

Include these fields in an otherwise complete reviewed worker manifest:

```json
{
  "capabilities": ["event.feed"],
  "subscriptions": [
    {"id": "requests", "event": "model.admitted", "event_version": 1,
     "view": "metadata", "mode": "feed", "queue_events": 8}
  ]
}
```

Each declaration has exactly those six keys. `queue_events` is 1..32, including
queued callbacks, the in-flight callback and an acknowledgment awaiting durable
host commit. The existing four-per-artifact/eight-total subscription ceilings
include feeds, notifications and jobs together. `event.feed` is present exactly
when a feed declaration exists; `describe/0` must match the inert manifest.
No required/schedule/filter/handler field, wildcard, private view or arbitrary
topic is admitted. Installation, inspection and disabled selection execute no code.

`Feeds.types/0` lists supported metadata types: model, saved assistant/tool,
context/compaction, questions, children, extension activity, waits and turn
settlement. These use the shared [metadata vocabulary](../2026-10-18-before-manual-rewrite/docs/developer/lifecycle-events.md#committed-metadata).
Waits and `session.recording_stopped` additionally require `lifecycle.record` in
that artifact's trust ceiling so their sources exist with diagnostics off.
Prompt/answer stages use their existing boundary subscriptions. Creation,
process start/resume and final logical close are outside this live enrollment;
authorized [history reads](../../developer/extension-feeds.md#capture-a-fixed-historical-prefix) expose recorded metadata for them.
Declaring those types as feeds refuses explicitly.

## Enrollment and callback

A session initially enrolls no feed worker. Accepted explicit input, a validated
question answer, an admitted operator command/service, or explicit context refresh
can enroll the selected declarations once for that process. Invalid input and
idle resume initialize none. Enrollment syncs `extension_feed_intent` with its
session/resource IDs, exact identity and declaration before executable startup.
The source of that intent is the lease's lower boundary. Earlier records are
outside its coverage. Worker startup and all callbacks run outside Session;
`extension_feed_ready` is synced before callbacks drain.

`handle("event.feed", payload, state)` receives exactly:

| Field | Value |
| --- | --- |
| `api_version` | Integer 1 |
| `handle` | Host resource ID |
| `subscription_id` | This declaration's ID |
| `sequence` | Consecutive lease-local admission number, starting at 1 |
| `after` | Public source reference to the enrollment intent |
| `event` | Shared version-1 metadata envelope with the original occurrence ID |

Source references in this payload contain no private content digest. Metadata
excludes arguments, question/answer text, provider continuation, credentials and
arbitrary errors. It is scoped to the owned session, including metadata about
other selected instances there. Children receive only their independently
permitted selection in their own session. Diagnostic mode and sampling do not
gate or sample this path.

The response must exactly echo the real identifiers:

```elixir
def handle("event.feed", payload, state) do
  {:ok,
   %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
     "sequence" => payload["sequence"], "event_id" => payload["event"]["event_id"]},
   state}
end
```

The whole payload/reply retains the 16 KiB SDK-object and 8 KiB string limits.
Initialization and each callback have separate five-second deadlines. The worker's
private heap is ephemeral and has ordinary OS permissions; these protocol bounds
do not establish an OS memory or network sandbox. Even an artifact with separate
host-action grants cannot request effects in a feed acknowledgment. Persistent
writes or extraction model calls need separately admitted jobs/operations.

## Ordering, pressure and stop

After syncing a source fact, Session projects its selected metadata and reserves
capacity before sending any mailbox message. It syncs a source-bound
`extension_feed_delivery_intent` before enqueueing the callback. A valid worker
acknowledgment yields a host `extension_feed_delivery_result`; only after that
sync does the host release capacity and dispatch the next callback. One worker owns
one serial lane. Feed control receipts have no feed projection, preventing a
self-triggering acknowledgment loop.

Across the durable session, at most 10,000 deliveries and 10,000 lease intents
are admitted. Full queues, the delivery ceiling or an oversized payload close
the feed with an explicit first rejected source. An unreferenceable oversized
source closes it with `source_unavailable`. Source journal appends remain intact.
Invalid replies, timeout, expiry or resource loss also end coverage. Ordinary
agent work proceeds. There is no silent drop-and-continue mode, implicit retry,
automatic catch-up or hidden inference. Independent source ordering is preserved
inside each lease; there is no global cross-session order.

`/events off`, cancellation and session close revoke admission and interrupt
in-flight worker calls through a bounded shared cleanup result. They record
`extension_feed_closed` with the first closing cause, admitted/acknowledged counts,
an available rejection reference and actual cleanup confirmation. A callback that
finished without a committed host acknowledgment remains unacknowledged. Close
does not promise to drain callbacks or deliver later cancellation/final close facts.
The feed stays stopped for this process; a new invocation can enroll on new work.
Completed delivery acknowledgment establishes receipt, not business success or
worker cleanup. VM disappearance alone does not confirm descendant cleanup.

## Recovery and verification

Saved validation checks pinned declarations, finite sequences, ready/closure
ordering, source positions and exact payload/receipt links before tail repair.
Anchor references resolve once per lease. Each delivery resolves its selected
source and its actual intent within at most ten records: source, up to eight feed
intents and the existing adjacent question checkpoint. Reads stop at that intent,
preserving a later torn tail for normal recovery. A record is bounded to 1 MiB;
no full-journal scan is run for each frame. These checks retain the existing
append-only ownership assumptions; source identity is not authentication against
hostile same-user filesystem replacement or a complete ingestion audit.

An interrupted/open lease and its unacknowledged intents remain historical
incomplete work. Idle resume neither initializes a worker nor reconstructs its
queue. New explicit work can enroll a fresh lease; earlier facts are outside its
coverage. Explicit bounded history catch-up uses separate read capabilities and
source-event deduplication. Any later write retains approval and tombstone/CAS
requirements. A source ID alone does not make external effects exactly once.

`test/extensions_feeds_test.exs` runs independent compiled workers through real
Sessions: metadata privacy and identity, barriers alongside feeds, source-bound
approval observation, pressure and invalid replies, stop/cancel/owner loss,
question checkpoint recovery, disabled parity, finite receipt bounds and coherent
payload tampering before repair. Source fixtures and primitive extracted-runtime
checks are distinct from the pending frozen-core installed graph-package proof.
Continuous private/media feeds, effectful background lanes, external transport
adapters and broader causal source seams remain separately negotiated work.
