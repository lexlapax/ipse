# Observe boundaries, run jobs, and catch up from history

Choose the delivery contract before writing a callback. A notification acknowledges
one selected prompt/answer occurrence. A job performs finite admitted work before
a request or after a turn. A feed observes committed live facts while Session work
continues. History is a separate explicit read of a fixed recorded prefix.
None of those selections grants another's private views or effects.

Read [metadata.ex](../../examples/extension-lab/src/metadata.ex),
[observer.ex](../../examples/extension-lab/src/observer.ex), and the recall/capture/
catch-up handlers in [memory.ex](../../examples/extension-lab/src/memory.ex).
Their [spec](../../examples/extension-lab/spec.exs) declares different grants.
The synthetic lab needs a built checkout and no account/model service.

## Select the occurrence and its private view

Declarations are inert manifest data matching executable descriptions. Version is
one; IDs are lowercase ASCII up to 32 characters. Unknown stages/versions/views/
modes, wildcards, or executable filters refuse. Notifications/jobs/feeds share
four subscriptions per artifact and eight active total. Activation pins normalized
subscriptions and digest.

| Occurrence/view | Required authority |
| --- | --- |
| Prompt received, original | Notification/job plus `event.prompt.original` for text |
| Effective prompt committed | Notification/job plus `event.prompt.effective` for text |
| Answer committed, original/presented | Notification/job plus exact `event.answer.original` / `.presented` |
| Supported live metadata | Declared `event.feed`; tool/wait facts also need source-recording grants |
| Live tool input/result | `lifecycle.record`, `lifecycle.tools`, exact `event.tool.input` / `.result` |
| Historical metadata | `host.actions`, `host.history` |
| Historical private prompt/answer/tool | History plus exact `host.history.*` view and a recorded source |

Metadata carries no private content. Children see only their own permitted facts.
Live grants imply no history. Installation or diagnostic selection grants no
private view. `Feeds.types/0` owns supported live types; prompt/answer boundaries
use notifications/jobs. Creation/start/resume/final-close lie outside live enrollment,
so use authorized history for recorded metadata.

## Write an acknowledgment-only notification

This fragment selects presented-answer delivery:

```json
{"capabilities":["event.notify","event.answer.presented"],"subscriptions":[{"id":"observe_answer","event":"answer.committed","event_version":1,"view":"answer.presented","mode":"notify","schedule":"after_turn","required":true}]}
```

`event.notify` exists exactly when notifications do. Answer notifications require
`after_turn`; prompt declarations omit schedule and retain their six-field shape.
Session syncs delivery intent binding identity/declaration/source/turn/payload digest
before startup. Echo actual IDs from the closed payload:

```elixir
def handle("event.notify", payload, state) do
  {:ok,
   %{"api_version" => 1, "kind" => "ack",
     "delivery_id" => payload["delivery_id"],
     "event_id" => payload["event"]["event_id"]}, state}
end
```

Wrong IDs or host calls refuse, even if this artifact has other grants. Every
notification gets a fresh worker; private state does not survive it. Initialization
and callback have separate five-second bounds and ordinary SDK limits. Overflow
records not-started with null payload digest before startup, without truncation.
A live lease, validated acknowledgment, and confirmed cleanup precede committed
`extension_event_result`. Timeout/malformed/interrupted work is not retried.

## Declare a job with an exported handler

A job names an `exports.jobs` descriptor in its own artifact. This complete-shaped
fragment declares awaited recall; it is not a full manifest:

```json
{"capabilities":["event.job","event.prompt.effective","host.actions","host.state.read","host.context"],"subscriptions":[{"id":"recall","event":"prompt.effective_committed","event_version":1,"view":"prompt.effective","mode":"job","handler":"recall","schedule":"before_request","required":true}],"exports":{"version":1,"tools":[],"commands":[],"services":[],"jobs":[{"id":"recall","description":"Recall selected scoped evidence","arguments_schema":{"type":"object","additionalProperties":false,"required":["event"],"properties":{"event":{"type":"object"}}},"result_schema":{"type":"object","additionalProperties":false,"required":["status"],"properties":{"status":{"type":"string","enum":["ok"]}}}}]}}
```

Job descriptors share eight-per-group/32-total limits. Empty/missing jobs normalize
to none. Jobs are not model tools, `/ext` commands, or callable through the public
export route. Only before-request/after-turn schedules exist; answer jobs are after-
turn. Selection permits the handler, not its later effects. State/services/context/
model calls retain separate grants and approvals.

Source-bound delivery intent, argument validation, and invocation intent precede
startup. `event.job` receives ordinary invocation fields and `arguments.event`.
Top-level trigger is host-made, binding delivery/source event/schedule. Similar
fields in domain arguments grant nothing. The callback returns a valid result or
finite host call under [state/effect protocols](extension-state.md). Jobs have fresh
workers, five-second callback/init bounds, ordinary sixteen calls or explicit mixed
counters, and Session-wide 10000-invocation/10000-delivery ceilings. They introduce
no concurrent background effect lane, recursive turn, or unbounded mailbox.

## Trace the order around inference

Accepted prompt occurrences bind original and effective text to a turn/source.
Both notification stages deliver after skill expansion and all transforms. Received
runs first, then effective, ordered by instance/ID and subscription ID. Received
is an observation of an earlier occurrence, not an interception hook. Views expose
user text, not full provider context/system instructions/native continuation.
Original/effective source records permit 1 MiB. Oversized original input refuses
idle; oversized effective input stops before delivery/inference.

Before-request jobs run after expansion/transforms and before MCP discovery,
compaction, and inference. Recall can read, call a bound service, and publish
context; the request snapshot freezes the resulting contributions. An answer-only
selection still records causal prompt boundaries without exposing that text.

After native answer completion and successful presentation, settling precedes
answer-committed. The source binds original/presented text, native message,
request/turn, and effective prompt. Views share one occurrence ID. Intermediate
tool messages or failed inference/presentation produce no completed-answer event.
After-turn prompt jobs precede answer declarations. Maintenance cannot change the
frozen answer or retract streamed text; it keeps Session busy until settlement.
Private answer views retain 8 KiB; larger views are unavailable with original counts/
digests retained, while metadata or a smaller presented view may remain available.
No payload exposes hidden reasoning, credentials, raw native data, or arbitrary journal bodies.

| Failure | Required policy | Optional policy |
| --- | --- | --- |
| Prompt notification unacknowledged | Stop inference | Retain receipt/notice; later work allowed |
| Answer notification unacknowledged | Stop maintenance; settlement error | Retain receipt/notice; later work allowed |
| Job has known failed action | Stop later declarations; before-request failure prevents inference | May continue with notice |
| Job has unknown action/cleanup | Stop lane | Stop lane |

Job success needs valid final result, confirmed cleanup, and every action ok/answered.
Denied/conflicting/failed/cancelled actions fail it regardless of callback claims.
Pure successful values remain assertions. Known pre-execution refusal may be not-
started; interrupted execution cannot. After-turn failure cannot undo answer/accounting.

## Preserve questions and delayed-write identity

A question closes its worker and retains a bounded checkpoint. Explicit answer
commits result/continuation intent before a fresh worker receives host actions.
Original callbacks/effects do not rerun. Pending recovery retains prompt/answer
sources, schedule/declaration, and immutable remaining plan. Completed declarations
are skipped. Idle resume initializes no subscriber/job or executable queue.
Unfinished intent remains unknown; identical later text has fresh occurrence IDs.

Restoration checks declaration/identity/source/turn/payload/order/receipt and actual
physical source positions before repair. Private job parents additionally bind
delivery intent and prompt/answer sources, without exposing those references in
metadata-only triggers. Missing question-source checkpoints refuse rather than guess.
Cancellation stops owned work, preserving committed state/publications and uncertainty.
In a versioned reference session, an admitted but unfinished replacement context
intent has already invalidated that caller's old selection; it cannot return on
resume. An earlier successful publication followed only by an interrupted callback
remains committed. See [publication](extension-state.md#publish-a-literal-excerpt-with-its-receipt).
For extraction, retain the revision/generation captured before work across the
checkpoint. Rereading after forget must not authorize resurrection. Domain suppression
and cutoffs build on generic CAS, as taught in [state](extension-state.md).

## Declare and acknowledge a bounded live feed

```json
{"capabilities":["event.feed"],"subscriptions":[{"id":"requests","event":"model.admitted","event_version":1,"view":"metadata","mode":"feed","queue_events":8}]}
```

These six fields are exact. Queue size is 1..32 including callback, queued events,
and acknowledgments awaiting durable commit. Required policies/schedules/handlers/
filters/arbitrary topics refuse. Selection alone starts no worker. Accepted input,
question answer, command/service, or context refresh enrolls once per process.
Invalid input and idle resume do not. Intent is the lower coverage boundary;
ready commits before draining. One worker retains private state for that lease.

Feed payloads bind host handle/subscription, consecutive lease-local sequence from
one, enrollment `after` source, and selected event. Echo the actual values:

```elixir
def handle("event.feed", payload, state) do
  {:ok,
   %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
     "sequence" => payload["sequence"],
     "event_id" => payload["event"]["event_id"]}, state}
end
```

Metadata excludes arguments/text/native data/arbitrary errors/private hashes.
Tool views add only selected recorded input/result. Feed views never cross Sessions.
Five-second init/callback bounds and SDK limits remain; an ack never executes an
action even with separate grants. Diagnostic sampling enables no feed.

After source commit, Session reserves capacity before mailbox admission and commits
delivery intent. Only synced valid delivery result releases a slot. Each worker
has one serial lane. Feed-control receipts have no feed projection, preventing
ack loops. A Session permits 10000 deliveries and 10000 leases. Full queues,
capacity/oversized/unavailable private sources, invalid replies, timeout, expiry,
or resource loss close coverage visibly with its first rejected source. Ordinary
agent work continues, without silent drop, retry, or catch-up.

Stop/cancel/close revokes admission and can abandon queued work. The close receipt
retains cause, admitted/acknowledged counts, rejection reference, and actual cleanup.
A callback without committed ack is unacknowledged. Cleanup and coverage remain
separate. Same-process additional input does not restart stopped enrollment; a
compatible resumed process can enroll after explicit work. Idle resume starts none.
Stopping tool recording closes affected feeds while tools may continue.

Saved validation checks identity/declaration/sequence/ready-close/payload/physical
positions before repair. Intent resolution examines at most ten records, including
eight feed intents and adjacent question checkpoint, without scanning the whole
journal per frame. Raw records permit 1 MiB. Later torn tails remain for ordinary
recovery; interrupted leases remain historical incomplete coverage, without queues.

## Capture and page a fixed historical prefix

History is new explicit work through this inner host-call request:

```json
{"op":"history.read","view":"prompt.effective","cursor":0,"snapshot":null,"limit":8}
```

Cursor is an inclusive JSONL byte boundary. Limit 1..8 counts scanned records,
not matching events. No paths/foreign Session/scope selectors are accepted. Reads
need no mutation approval, without approving later writes or model transfers.
The first action intent's starting offset becomes the exclusive upper bound.
Its snapshot binds Session/offset/event/operation/view, without path/private digest.
Continue with exact snapshot and returned `next`, rechecking current grants/lease.
Changed/missing capture anchors refuse. Worker-supplied references grant nothing.

The fixed `[0, boundary)` excludes capture/later receipts, so catch-up cannot chase
itself. It can continue across invocations or answered questions in the same pinned
Session. Cursor is position, not permission or an automatically saved progress promise.
The guarantee relies on owned append-only storage, not hostile same-user replacement.

A page has exactly version/coverage/snapshot/cursor/next/scanned/records, with
`coverage: "recorded_views_only"`. Rows are selected events, content-free other-view
skips, or unsupported/unavailable/page-budget gaps. Null `next` means that range
was examined, not complete conversation coverage. Old missing prompt/answer/tool
boundaries are not invented from adjacent messages. Expanded prompt stays a
distinct saved-user-message view.

Each call scans eight records/1 MiB raw bytes plus bounded anchor resolution.
Page values permit 12288 encoded bytes inside all SDK bounds. An overflowing next
event stays unconsumed if a page has rows; an event too large for an empty page
becomes a page-budget gap, without truncation. Cursor/source/timeout/snapshot
failures return fixed known diagnoses, without paths/prose/unchecked partial pages.
Linked history IO runs outside Session with five-second wait then brutal shutdown.
Every page consumes the invocation allowance. No host paging/reindex loop runs.

Deduplicate by original occurrence and retain skips/gaps before claiming complete
ingestion. A context excerpt cites the PAGE action receipt, for example path
`["records",0,"event","data","text"]`; that can differ from the capture action.
Source IDs establish recorded provenance, not semantic support or exactly-once
remote writes. Forgetting notes erases no journals and revokes no independent
history grant. Recovery validates cached anchors/projections/contiguous spans/gaps
without rerunning reads. Missing/changed/omitted spans refuse before repair.

## Verify observation, recall, maintenance, and catch-up

```sh
mix test test/ipse/extension/subscriptions_test.exs test/ipse/extension/event_job_test.exs
mix test test/ipse/extension/feeds_test.exs test/ipse/extension/history_test.exs
```

Compare metadata/private views of one occurrence, then corrupt an ack ID and require
prompt inference refusal. Trace before-request recall into its frozen model input,
and verify after-turn publication affects only a later request. For pressure,
identify first rejected source and admitted/acked counts, then verify idle resume
starts no worker. Capture history, append more facts, and ensure later facts stay
outside continuation. Zero matches may still advance the cursor. Preserve explicit
question and captured-revision-after-forget controls. [Conformance](extensions.md)
and the [installed lab](testing.md) complete the authoring journey without claiming
unexecuted live-quality or OS guarantees.
