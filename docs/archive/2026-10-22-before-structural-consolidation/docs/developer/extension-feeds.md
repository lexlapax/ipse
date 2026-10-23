> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/extension-events.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Observe live facts and catch up from history

A feed observes supported committed lifecycle facts while explicit Session work
proceeds. A history read scans a fixed recorded prefix as new explicit work.
Neither grants effects, publishes context or replays a journal. The extension
owns deduplication, extraction and any later separately approved writes.

Read `examples/extension-lab/src/observer.ex` and `src/tool_observer.ex` for live
observation, then the `catchup` export in `src/memory.ex` for a domain history
scan. `spec.exs` shows their distinct grants. You need a built checkout and
Elixir toolchain; the synthetic lab needs no account or model service.

## Choose live and historical authority separately

Live declarations need `event.feed` in artifact and operator trust. Private tool
views need their exact event capability and prior source recording. History needs
`host.actions`, `host.history` and each selected private historical capability.
Live grants never imply history. Children see only their own independently
permitted sessions, and metadata selection grants no private content.

| View | Live prerequisite | Historical prerequisite |
| --- | --- | --- |
| Metadata | Declared supported feed; tool facts also need recording grants | `host.history` |
| Tool input/result | `lifecycle.record`, `lifecycle.tools`, `event.tool.input` or `event.tool.result` | `host.history.tool.input` or `host.history.tool.result`, plus recorded source |
| Original/expanded/effective prompt | Separate boundary notification/job contract | `host.history.prompt.original`, `.expanded` or `.effective` |
| Original/presented answer | Separate boundary notification/job contract | `host.history.answer.original` or `.presented` |

`Feeds.types/0` is the authoritative live list. It includes committed model,
assistant/tool, context/compaction, question, child, extension, wait and settlement
facts. `wait.started`, `wait.finished` and `session.recording_stopped` also require
`lifecycle.record`. Prompt/answer boundaries use [notifications or jobs](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-events.md).
Session creation/start/resume/final close lie outside live enrollment; use
authorized history for their recorded metadata. See
[lifecycle sources](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/lifecycle-events.md) for coverage and recording prerequisites.

## Declare a bounded live feed

Add this fragment to a complete reviewed manifest:

```json
{"capabilities":["event.feed"],"subscriptions":[{"id":"requests","event":"model.admitted","event_version":1,"view":"metadata","mode":"feed","queue_events":8}]}
```

The declaration has exactly six fields. `queue_events` is 1..32 and includes the
active callback, queued callbacks and an acknowledgment awaiting durable commit.
Feeds share four-per-artifact and eight-total subscriptions with notifications
and jobs. `event.feed` is present exactly when feeds exist; `describe/0` must
match. Required policies, schedules, handlers, filters, wildcards and arbitrary
topics refuse.

Selection alone starts no worker. Accepted explicit input, a valid question
answer, an admitted command/service or explicit context refresh can enroll once
for that process. Invalid input and idle resume enroll none. Session syncs
`extension_feed_intent` before startup and `extension_feed_ready` before draining.
The enrollment intent is the lease's lower source boundary; earlier facts lie
outside coverage. One worker retains private state for that lease.

`handle("event.feed", payload, state)` receives `api_version:1`, host `handle`,
subscription ID, consecutive lease-local sequence starting at 1, `after` pointing
to the enrollment intent, and the selected version-one event envelope. Echo its
actual identifiers:

```elixir
def handle("event.feed", payload, state) do
  {:ok,
   %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
     "sequence" => payload["sequence"],
     "event_id" => payload["event"]["event_id"]}, state}
end
```

Metadata excludes arguments, question/answer text, credentials, raw native data,
arbitrary errors and private content hashes. A tool view adds only its selected
input/result and normal source binding. A feed may observe metadata about other
selected instances in the same owned session, never another session.

Initialization and each callback have separate five-second deadlines. Payloads
and replies retain SDK 16 KiB object and 8 KiB string limits. An acknowledgment
cannot execute actions even when that worker separately has effect grants.
Diagnostic sampling settings do not enable this path. The trusted worker retains
ordinary OS permissions; queue bounds are not a heap quota or sandbox.

## Account for pressure and incomplete coverage

After syncing a source, Session reserves capacity before sending mailbox work
and records `extension_feed_delivery_intent` before enqueueing. Only a synced
valid `extension_feed_delivery_result` releases capacity for the next callback.
Each worker has one serial lane. Feed-control receipts have no feed projection,
which prevents acknowledgment loops.

A session permits 10000 deliveries and 10000 lease intents. A full queue, delivery
ceiling or oversized payload closes with the first rejected source. Oversized
unreferenceable sources use `source_unavailable`. An unavailable private view
closes that feed with `view_unavailable` and a source gap while metadata may
continue. Invalid replies, timeout, expiry and resource loss also end coverage.
Ordinary agent work continues. There is no silent drop, retry or implicit catch-up.

`/events off`, cancellation and close revoke admission and interrupt owned work.
The closed receipt retains first cause, admitted/acknowledged counts, available
rejection reference and actual cleanup confirmation. A callback finished without
a committed acknowledgment is still unacknowledged. Close need not drain queues
or deliver subsequent cancellation/final-close facts. Enrollment stays stopped
for that Session process; additional input does not restart it. A new Session
process, including compatible resume followed by explicit input, can enroll a
fresh lease. Idle resume alone still enrolls nothing.

Delivery coverage and cleanup are independent. A failed delivery may still have
a genuine native cleanup receipt. Process absence alone proves no descendant
cleanup. Stopping tool recording closes affected feeds with incomplete coverage
while ordinary tools can continue.

Saved validation checks identity, declaration, sequence, ready/close order,
payloads and actual source positions before tail repair. Source/intent resolution
uses at most ten records, allowing eight feed intents and an adjacent question
checkpoint. It stops at the intent; later torn tails remain for normal recovery.
Raw records remain at most 1 MiB, without a full journal scan for each frame.
Open/interrupted leases stay historical incomplete work. Idle resume starts no
worker and recreates no queue.

## Capture a fixed historical prefix

An admitted invocation or job returns this five-field request inside an outer
host-call reply:

```json
{"op":"history.read","view":"prompt.effective","cursor":0,"snapshot":null,"limit":8}
```

`cursor` is an inclusive JSONL byte boundary. Limit is 1..8 source records scanned,
not matching events. Paths, another session and project/operator scope are not
accepted. Trusted reads need no new mutation approval; later writes, tools and
model transfers keep their own rules.

With null snapshot, this action intent's starting byte offset becomes the
exclusive upper boundary. The returned version-one snapshot contains session ID,
byte offset, event ID, operation ID and view, without a path or private digest.
Continue by passing the exact snapshot and returned `next`. Each call still needs
current grants and lease admission. Host resolves the capture intent and checks
caller identity, session, operation and view; changed/missing anchors refuse.
A worker-supplied reference is not permission or authenticated provenance.

The range `[0, byte_offset)` excludes its capture intent and later appends, so
catch-up cannot chase its own receipts. It can continue across explicit
invocations or answered questions in the same pinned session. A cursor is page
position, not a narrower grant or a persisted progress promise. The bound relies
on the owned append-only journal, not immutable storage against same-user edits.

## Consume pages, skips and gaps

An `ok` page has exactly `version`, `coverage`, `snapshot`, `cursor`, `next`,
`scanned` and `records`. Coverage is `recorded_views_only`. Each consumed source
produces one row:

| Kind | Fields |
| --- | --- |
| `event` | Selected versioned event retaining its occurrence ID |
| `skipped` | Content-free source and `reason:other_view` |
| `gap` | Content-free source and `unsupported_record`, `view_unavailable` or `page_budget` reason |

Null `next` means the captured range was examined, not complete conversational
coverage. Skips/gaps expose neither raw record type nor body. Private rows contain
only the selected content/binding. Tool views expose closed name/arguments JSON
or result text from recorded markers; old native messages are not relabelled.
Missing prompt/answer boundaries are not invented from nearby records. Expanded
prompt remains a distinct saved-user-message view.

Each call scans up to eight records and 1 MiB raw JSON, plus bounded anchor
resolution. Page values are at most 12288 encoded bytes; the whole callback must
fit SDK 16 KiB, string and depth limits. An overflowing next event remains
unconsumed when the page already has rows. One event too large for an empty page
becomes a `page_budget` gap without truncation. Cursor, syntax, raw-source and IO
failures return known `history_snapshot`, `history_cursor`, `history_source` or
`history_timeout`, without paths, error prose or unchecked partial pages.

History IO uses a linked task outside Session and a five-second wait before
brutal task shutdown. Reads consume their invocation allowance; there is no host
pagination loop or automatic reindexing.

## Keep extraction and forgetting consistent

Receipts bind page, snapshot, operation, caller and session namespace. To publish
an excerpt, cite the page action's operation ID with a path such as
`["records",0,"event","data","text"]` under
[context publication](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-composition.md). The page action can differ from
the original capture action. Provenance establishes recorded text, not truth or
instruction priority.

Record gaps/skips before claiming complete ingestion and deduplicate by original
occurrence. Source IDs cannot make remote writes exactly once. Capture revision/
tombstone before delayed extraction and use it in later CAS. Forgetting derived
notes does not erase journals or revoke independent history access. The extension
owns suppression and explicit reindex commands.

Recovery checks cached anchors, actual projections, contiguous spans and budget
gaps without rerunning scans or updating pages. Missing, altered or coherently
omitted spans refuse before repair. Interrupted operations remain incomplete or
unknown. Idle resume runs no catch-up callback.

## Verify pressure and fixed-range catch-up

Run the observer's deliberate hang through the capacity fixture. Identify the
first rejected source and compare admitted/acknowledged counts; idle resume must
start no worker. Then capture history, append more facts and continue the saved
snapshot. Later facts must remain outside it, and zero matching events may still
advance the cursor. Question continuation must be explicit new work.

```sh
mix test test/extensions_feeds_test.exs test/extensions_history_test.exs
```

The suites cover metadata privacy, private views, bounded pressure, stop/cancel/
owner loss, page splitting, gaps, torn later tails, source tampering and cached
recovery. The [installed lab](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/testing.md) combines them with domain deduplication
and stale-write rejection after forget against an unchanged runtime.
