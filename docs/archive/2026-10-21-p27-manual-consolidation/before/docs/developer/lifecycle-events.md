Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../developer/lifecycle-events.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Reading and extending lifecycle events

Lifecycle events describe occurrences at specific host boundaries. A proposal, an
admitted intent, and a recorded outcome are different facts. A hook may await a
typed decision; a subscription receives selected facts; an action proposal still
needs host admission. Receiving an event grants no permission to execute a tool,
read another view, or infer.

Start with `lib/ipse/lifecycle/source.ex`, `event.ex`, and `metadata.ex`.
`runtime.ex`, `answer.ex`, `tool.ex`, and `child.ex` validate particular saved
boundaries. Session remains the owner of work and the journal remains recovery
authority. This vocabulary does not replace the turn loop with an event framework.

## Give an occurrence identity before delivering it

`Lifecycle.Source` binds a record to session ID and actual byte offset. Version-1
`event_id` is the first 128 bits of SHA-256 over the domain-separated
`ipse:journal:v1:<session>:<offset>` identity. A separate canonical record digest
binds content and stays private. Two identical prompts appended at different
offsets are two occurrences. Metadata/private views of one record keep its ID;
subscriber delivery and action IDs identify different consumption attempts.

The first fixture in `test/lifecycle_test.exs` makes this concrete:

```elixir
record = %{"type" => "message", "message" => %{"role" => "user", "content" => "same text"}}
{:ok, first} = Ipse.Journal.append_with_source(root, id, record)
{:ok, second} = Ipse.Journal.append_with_source(root, id, record)
false = first["event_id"] == second["event_id"]
true = Ipse.Lifecycle.Source.matches?(first, record)
```

Here `root` and `id` are an inactive temporary fixture journal under its required
ownership policy. Active Session code uses its owned writer. A source is identity
and content binding, not authentication against a hostile same-user editor or a
permission token.

`Journal.append_with_source/3` returns only after sync. Optional
`append_observed/3` can commit mandatory evidence even when source limits refuse
an observation. Required-source refusal writes no event. Never let an optional
observer duplicate or suppress the recovery append.

`Journal.source_page/4` reads complete records without tail repair or callbacks.
Default page count is 32, maximum 64, with at most 1 MiB raw JSON per page and per
record. Reads reject duplicate keys, nonobjects, oversized/incomplete lines, and
nonboundary cursors. A non-nil cursor can require a final empty read for EOF.
`source_page/5` adds an exclusive validated byte boundary; it does not parse later
records and returns nil at that fixed end. Open-tail paging is not a transactional
snapshot. Raw pages are private journal data and must not be forwarded wholesale.
The [history action](extension-history.md) adds view grants, fixed ranges, and gaps.

## Project the smallest required view

`Event.project/3` checks source/content binding and returns a closed envelope with
`version`, `data_version`, `event_id`, `type`, `source`, `origin`, `view`,
`correlations`, and `data`. Both versions are 1 and host events use `origin: host`.
Metadata excludes private text and content hashes. Private views expose only the
selected content and private source, never a complete record or native history.
SDK objects fit 16 KiB and private strings fit 8 KiB; overflow refuses without
truncation.

| Saved boundary | Event | Private view |
| --- | --- | --- |
| Original input marker | `prompt.received` | `prompt.original` |
| Expanded user message | `prompt.expanded_committed` | `prompt.expanded` |
| Prompt transform result | `prompt.projection_committed` | `prompt.projection` |
| Final effective input marker | `prompt.effective_committed` | `prompt.effective` |
| Completed answer marker | `answer.committed` | `answer.original`, `answer.presented` |
| Admitted tool input/outcome | `tool.intent_committed`, `tool.outcome_recorded` | `tool.input`, `tool.result` |

Expanded text precedes transforms; an intermediate projection may precede another
transform. Neither is final-effective input. Selected subscriptions create the
final marker after transforms, with actual received-source and turn binding.
Legacy records without those links retain their absence.

`Lifecycle.Answer` binds original assistant digest, final presented text,
turn/request, and effective-prompt source after native completion and presentation.
Recovery resolves those against preceding messages and physical source positions.
Each answer view fits 8 KiB independently; an oversized original need not prevent
a bounded presented view. Metadata retains counts even when private text is
unavailable. An answer-only grant exposes no private prompt through its causal ID.

## Understand committed metadata coverage

`Lifecycle.Metadata` copies fixed fields from validated host facts. Unknown source
types, malformed identifiers, numeric values, or enum dimensions refuse.
Worker-returned business assertions never set a host outcome.

| Family | Event vocabulary and retained facts |
| --- | --- |
| Session | `session.created`, `session.started`, `session.resumed`, `session.close_committed`, `session.recording_stopped`; epoch/closure facts |
| Waits | `wait.started`, `wait.finished`; exact wait/domain and available causal IDs, outcome/duration |
| Model | `model.admitted`, `model.usage_observed`, `model.finished`, `model.measured`; request/attempt/parent, kind/sequence/outcome/duration |
| Messages/tools | `assistant.committed`, `tool.result_recorded`, `tool.started`; text counts, saved request or approval category |
| Admitted tools | `tool.intent_committed`, `tool.outcome_recorded`, `tool.recording_stopped`; host IDs, counts/status/approval and actual sources |
| Context | `context.workspace_committed`, `context.catalog_committed`, `context.extensions_committed`, `context.compaction_committed`, `context.compaction_failed`; counts and saved correlations |
| Questions | `question.waiting`, `question.answered`, `question.closed`; no question or answer text |
| Children | `child.started`, `child.finished`; host child, actual parent/start links, status/reason/duration/cleanup |
| Extensions | Invocation/action/delivery admitted or recorded; question waiting; continuation admitted; text admitted/ready/closed, with their actual host IDs/outcomes |
| Turn | `turn.settling`, `turn.finished`, `turn.cancelled`; available turn and status |

Metadata omits paths, arguments, raw provider call IDs, error prose, prompts,
answers, native payloads, private digests, credentials, and counter/pricing content.
Use [accounting reads](usage-accounting.md) for counters. Do not invent a causal
link from adjacent records or reinterpret an old completion as a newer boundary.

## Record runtime epochs and operator waits

`Lifecycle.Runtime` enrolls when capture is local/export or a selected artifact
has `lifecycle.record`. That capability records sources only; it grants no worker,
private read, action, or export. With both absent, even idle resume appends no
runtime facts. Stopping observability delivery does not end an enrolled epoch.

Final initialization starts a fresh epoch. Resume identifies the prior recorded
epoch and whether it was closed, without inventing legacy epochs. Logical close
is synced before process exit, not proof that the PID is already dead. Explicit
close includes actual cleanup result. Observed owner loss keeps cleanup false;
untrappable death or lock loss may leave the epoch open. Never append a speculative
finish after ownership is gone.

Interactive approvals start waits before publication. Policy allow/deny creates
no fake wait. Native/extension questions start after their checkpoint and bind the
actual question source; metadata carries event IDs, not private IDs or answers.
Only a validated decision closes its own wait. Stale decisions do nothing.
Cancellation, interruption, and expiry retain distinct outcomes. Resuming a
question creates a new wait/epoch and monotonic start, leaving the prior unclosed
wait incomplete. Downtime cannot be inferred as process-local duration.

A durable session permits 10,000 runtime facts plus one recording-stop notice.
Starts reserve room for closure. Exhaustion stops recording visibly without
stopping ordinary work or cleanup. Tool recording has its separate
[10,000-fact policy](tool-events.md).

## Choose delivery separately from access

| Contract | Scheduling and overload | Accepted response |
| --- | --- | --- |
| [Prompt/answer notify](extension-events.md) | Ordered finite boundary plan, explicit required/optional outcome | Exact acknowledgment |
| [Live feed](extension-feeds.md) | Selected committed facts, bounded serial queue, incomplete closure | Exact acknowledgment |
| [Event job](extension-event-jobs.md) | Owned source-bound before-request/after-turn job in one effectful lane | Negotiated approved host actions |
| [Transforms](extension-hooks.md) | Ordered awaited boundary | Validated projection at that seam |
| [Diagnostics](../../../../2026-10-22-before-structural-consolidation/docs/developer/observability.md) | Independent sampled queues with drop counters | Metadata acknowledgment |
| [Visible text](text-streams.md) | Private ordered flow with acknowledgment and pressure | Text receipt only |

Declarations select exact types, versions, views, and mode under artifact/options,
operator trust, scope, activation, and expiry. Unknown declarations refuse before
executable activation. Live grants do not imply history; private grants do not
transfer to children. A before-hook is a reached decision boundary, not a completed
operation. Notifications cannot quietly start a second operator conversation or
perform effects in an acknowledgment.

Awaited recall must finish before request context freezes. Background publication
can affect only a later boundary. Fully concurrent effectful jobs, arbitrary
worker-origin host events, namespaced domain publication, and network subscription
bridges are unsupported. A new event string alone cannot implement these semantics.

## Preserve interrupted work and visible gaps

Sync the source and invocation/delivery/action intent before executable work.
Retain pinned identity, input view, source, and validated outcome. Interrupted jobs
stay incomplete or unknown; idle resume validates receipts without callbacks or
replay. External stores need their own idempotency/CAS because an event ID cannot
make an arbitrary remote write exactly once.

Explicit catch-up is new approved bounded work over authorized history, retaining
original occurrence IDs. Missing private views or legacy coverage remain gaps.
Tombstones/revisions must block delayed extraction after forget. Deleting an index
does not erase source journals, cached context, or past egress.

Child completion requires an authenticated worker report after bounded result and
actual child cleanup acknowledgment; death alone cannot promote unknown to
`result_recorded`. See [delegation](../../../../2026-10-22-before-structural-consolidation/docs/developer/delegation.md). Ephemeral text sources have
broker epochs/ranges rather than journal offsets and are rejected by durable
history/feed readers; see [stream events](stream-events.md).

## Practice adding a source

Read `test/lifecycle_test.exs` for identical-record identity and source paging,
`test/lifecycle_runtime_test.exs` for wait recovery, and
`test/lifecycle_answer_test.exs` for native-to-presented answer binding.

```sh
mix test test/lifecycle_test.exs test/lifecycle_metadata_test.exs test/lifecycle_runtime_test.exs test/lifecycle_answer_test.exs
```

For a new source, define closed record/envelope views and exact bounds, add strict
reduction and physical source resolution, then wire sync-before-delivery in
Session. Test changed content with a self-consistent digest, stale references,
oversized private views, owner loss, and byte-identical idle resume. A projector
unit test alone does not establish subscriber authorization or delivery.
