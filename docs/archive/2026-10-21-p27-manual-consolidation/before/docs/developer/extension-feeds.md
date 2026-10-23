Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../2026-10-22-before-structural-consolidation/docs/developer/extension-feeds.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Consume a bounded live lifecycle feed

A feed observes supported committed facts while explicit session work proceeds.
Each declaration owns one worker VM and a finite queue. Its acknowledgment means
receipt of that fact, not authority for effects. Use a feed for an observer or
monitor; use boundary notifications for prompt/answer views and event jobs for
host actions.

Read `examples/extension-lab/src/observer.ex` and `src/tool_observer.ex`. The first
has a deliberate hang for pressure testing; the second checks selected private
tool views. Their manifests in `spec.exs` show why metadata and tool content need
different grants.

## Declare a feed

Add this fragment to a complete reviewed manifest:

```json
{
  "capabilities": ["event.feed"],
  "subscriptions": [{
    "id": "requests", "event": "model.admitted", "event_version": 1,
    "view": "metadata", "mode": "feed", "queue_events": 8
  }]
}
```

Declarations have exactly those six keys. `queue_events` is 1–32 and includes
queued callbacks, the active callback, and an acknowledgment awaiting durable
commit. Feeds share the four-per-artifact/eight-total subscription limits with
notifications and jobs. `event.feed` is present exactly when feeds exist, and
`describe/0` must match the inert manifest. Required policies, schedules,
handlers, filters, wildcards, and arbitrary topics refuse.

`Feeds.types/0` is the authoritative supported event list. It includes committed
model, assistant/tool, context/compaction, question, child, extension, wait, and
turn-settlement facts from the shared
[lifecycle vocabulary](lifecycle-events.md#understand-committed-metadata-coverage). Prompt/answer
boundary events retain their separate notification/job contracts. Session creation,
start/resume, and final logical close are outside live enrollment; use authorized
history reads for their recorded metadata.

| Selected event | Views | Additional prerequisites |
| --- | --- | --- |
| `tool.intent_committed` | `metadata`, `tool.input` | `lifecycle.tools` and `lifecycle.record`; private input also needs `event.tool.input` |
| `tool.outcome_recorded` | `metadata`, `tool.result` | Same recording grants; private result also needs `event.tool.result` |
| Other admitted-tool facts | `metadata` | `lifecycle.tools` and `lifecycle.record` |
| Waits and `session.recording_stopped` | `metadata` | `lifecycle.record` |
| Other supported types | `metadata` | Declared feed authority |

Private grants must correspond exactly to declared views. Tool recording is a
separate source prerequisite; feed selection cannot manufacture old private facts.
Stopping that recorder closes affected feeds with incomplete coverage while
ordinary tools can continue. See [tool sources](tool-events.md).

## Enrollment and callback

Selection alone enrolls no worker. Accepted explicit input, a valid question
answer, an admitted command/service, or explicit context refresh can enroll feeds
once for that process. Invalid input and idle resume run none. Session syncs
`extension_feed_intent` before startup, then `extension_feed_ready` before draining
callbacks. The enrollment intent's source is the lease's lower boundary; earlier
facts are outside its coverage.

`handle("event.feed", payload, state)` receives a closed object with:

| Field | Meaning |
| --- | --- |
| `api_version` | Integer 1 |
| `handle` | Host resource ID |
| `subscription_id` | Selected declaration ID |
| `sequence` | Consecutive lease-local admission number, starting at 1 |
| `after` | Public source reference to enrollment intent |
| `event` | Selected version-1 envelope retaining the original occurrence ID |

The worker retains private state for this lease. A callback acknowledges exact
host identifiers:

```elixir
def handle("event.feed", payload, state) do
  {:ok,
   %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
     "sequence" => payload["sequence"], "event_id" => payload["event"]["event_id"]},
   state}
end
```

Metadata excludes arguments, question/answer text, credentials, native continuation,
arbitrary errors, and private content hashes. Tool views include only the selected
input/result and normal private source binding. Every view is scoped to the owned
session, including metadata about its other selected instances. Children observe
only their own independently permitted sessions.

The full payload/reply retains 16 KiB SDK-object and 8 KiB string limits.
Initialization and each callback have separate five-second deadlines. Even a
worker with separate action grants cannot return effects through an acknowledgment.
Diagnostic capture settings neither enable nor sample this path. The worker heap
has ordinary OS permissions; queue bounds are not an OS sandbox or memory quota.

## Ordering, pressure and stop

After syncing a source, Session reserves capacity before sending any mailbox
message and commits `extension_feed_delivery_intent` before enqueueing. A valid
acknowledgment yields a synced `extension_feed_delivery_result`. Only then is
capacity released and the next callback dispatched. One worker owns one serial
lane. Feed-control receipts have no feed projection, preventing acknowledgment
loops.

At most 10,000 deliveries and 10,000 lease intents are admitted across a session.
Full queues, the delivery ceiling, or oversized payloads close with the first
rejected source. Unreferenceable oversized sources use `source_unavailable`.
An unavailable private view closes that feed with `view_unavailable` and a source
gap while metadata may continue. Invalid replies, timeout, expiry, or resource
loss also end coverage. Ordinary agent work proceeds. There is no silent drop,
implicit retry, automatic catch-up, or hidden inference.

`/events off`, cancellation, and close revoke admission and interrupt owned work.
`extension_feed_closed` retains the first cause, admitted/acknowledged counts,
rejection reference when available, and actual cleanup confirmation. An uncommitted
acknowledgment remains unacknowledged even if the callback finished. Closing need
not drain the queue or deliver later cancellation/final-close facts. It stays
stopped for that process; a new invocation can enroll on new work.

Delivery coverage and cleanup are independent. A failed delivery can still have
a genuine native cleanup receipt, which the worker lease retains. Process
absence alone is insufficient proof of descendant cleanup.

## Recovery and verification

Saved validation checks identities, declaration, sequence, ready/close order,
payloads, and physical source positions before tail repair. Each delivery resolves
source and intent within at most ten records, allowing up to eight feed intents
and the adjacent question checkpoint. Reads stop at the intent, leaving a later
torn tail for ordinary recovery. Raw records are at most 1 MiB; there is no full
journal scan per frame.

Open/interrupted leases remain historical incomplete work. Idle resume starts no
worker and rebuilds no queue. New explicit work enrolls a fresh lease, excluding
earlier facts. Use separately granted [history reads](extension-history.md) for
explicit catch-up and deduplicate by source occurrence. Source IDs alone cannot
make external writes exactly once.

For an exercise, run the deliberate hang through the capacity fixture. Identify
the first rejected source and compare admitted versus acknowledged counts. Then
resume idle and confirm no worker is enrolled.

```sh
mix test test/extensions_feeds_test.exs
```

These fixtures test pressure, strict replies, metadata privacy, private tool
views, stop/cancel/owner loss, source tampering, and question recovery. The
[installed lab](extension-proof.md) checks those exercised worker contracts against
an unchanged packaged runtime.
