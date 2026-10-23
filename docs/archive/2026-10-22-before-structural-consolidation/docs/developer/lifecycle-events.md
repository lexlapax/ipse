> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/lifecycle-events.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Bind lifecycle observations to recorded work

A proposal, an admitted intent and a recorded outcome are different facts.
Lifecycle code gives each supported occurrence a source identity and projects
only an authorized view. Session owns work and the journal owns recovery truth.
An event grants no permission to read another view, execute effects or infer.

Start with `lib/ipse/lifecycle/source.ex`, `event.ex` and `metadata.ex`, then read
`runtime.ex`, `answer.ex`, `tool.ex` and `child.ex` for saved boundaries. This
chapter teaches how to add or change a source without inventing completion,
private coverage or replay. Run the exercises in a built checkout using synthetic
journals and providers; no account is required.

## Give a durable occurrence its own identity

`Lifecycle.Source` binds a record to session ID and physical byte offset.
Version-one `event_id` is the first 128 bits of SHA-256 over
`ipse:journal:v1:<session>:<offset>`. A separate canonical record digest binds
content and stays private. Identical prompts at different offsets are distinct
occurrences. Metadata/private views share that occurrence ID; deliveries and
actions identify consumption attempts.

The first fixture in `test/lifecycle_test.exs` demonstrates the distinction:

```elixir
record = %{"type" => "message", "message" => %{"role" => "user", "content" => "same text"}}
{:ok, first} = Ipse.Journal.append_with_source(root, id, record)
{:ok, second} = Ipse.Journal.append_with_source(root, id, record)
false = first["event_id"] == second["event_id"]
true = Ipse.Lifecycle.Source.matches?(first, record)
```

Here `root`/`id` belong to an inactive temporary fixture journal under its
ownership policy. Active Session uses its owned writer. A source binds identity
and content; it is neither permission nor authentication against same-user edits.

`append_with_source/3` returns after sync. Optional `append_observed/3` can retain
mandatory evidence when observation bounds refuse a source. Required-source
refusal writes no event. An optional observer must never duplicate or suppress
the recovery append.

`Journal.source_page/4` reads complete records without callbacks or tail repair.
Default count is 32, maximum 64; raw page and record bounds are 1 MiB. It rejects
duplicate keys, nonobjects, oversized/incomplete lines and nonboundary cursors.
A non-null cursor may need a final empty read to establish EOF. `source_page/5`
adds an exclusive validated byte boundary, parses nothing later and returns null
at that fixed end. Open-tail paging is not a transactional snapshot. Raw pages
are private; [history reads](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-feeds.md) add selected grants and gaps.

## Project a closed view

`Event.project/3` verifies source/content binding and returns exactly `version`,
`data_version`, `event_id`, `type`, `source`, `origin`, `view`, `correlations` and
`data`. Both versions are 1, with host origin. Metadata excludes private text and
content hashes. Private views expose selected content/source, never an entire
record or native history. SDK objects fit 16 KiB and private strings 8 KiB;
overflow refuses without truncation.

| Saved boundary | Event | Private view |
| --- | --- | --- |
| Original input marker | `prompt.received` | `prompt.original` |
| Expanded user message | `prompt.expanded_committed` | `prompt.expanded` |
| Transform result | `prompt.projection_committed` | `prompt.projection` |
| Final effective input | `prompt.effective_committed` | `prompt.effective` |
| Completed answer marker | `answer.committed` | `answer.original`, `answer.presented` |
| Admitted tool input/outcome | `tool.intent_committed`, `tool.outcome_recorded` | `tool.input`, `tool.result` |

Expanded text precedes transforms; intermediate projection can precede another
transform. Neither is final effective input. Selected subscriptions create that
final marker with received-source/turn links. Legacy records lacking those links
retain their absence. `Lifecycle.Answer` binds original assistant digest, final
presentation, request/turn and effective-prompt source after native completion
and presentation. Recovery resolves physical preceding evidence. Each answer
view fits 8 KiB independently; a large original need not hide a small presentation.
Metadata retains counts without revealing a prompt through its causal ID.

## Preserve the meaning of committed metadata

`Lifecycle.Metadata` copies fixed fields from validated host facts. Unknown
types, malformed IDs, numeric values and enum dimensions refuse. Worker business
assertions never decide host outcomes.

| Family | Coverage |
| --- | --- |
| Session | Created, started, resumed, logical close, recording stopped; epoch/closure |
| Waits | Started/finished; wait/domain, actual causal IDs, outcome/duration |
| Model | Admitted, usage observed, finished, measured; request/attempt/parent/kind/sequence/outcome/duration |
| Messages/tools | Assistant committed, tool result recorded, tool started; text counts, saved request/approval category |
| Admitted tools | Intent, recorded outcome, recording stopped; host IDs, counts/status/approval and physical sources |
| Context | Workspace, catalog, extensions and compaction committed; compaction failed; counts/correlations |
| Questions | Waiting, answered, closed; no question/answer text |
| Children | Started/finished; actual parent/start links, status/reason/duration/cleanup |
| Extensions | Invocation/action/delivery, questions, continuation and text-resource admission/readiness/closure |
| Turn | Settling, finished, cancelled; actual turn/status |

The concrete event strings and schemas live in the projector modules. Metadata
omits paths, arguments, raw provider call IDs, error prose, prompts, answers,
native payloads, private digests, credentials and counter/pricing content. Use
[accounting reads](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/usage-accounting.md) for counters. Do not infer causal links
from adjacency or reinterpret an old completion as a newer boundary.

## Record epochs and waits independently of delivery

`Lifecycle.Runtime` enrolls when capture is local/export or an artifact selects
`lifecycle.record`. The capability records sources; it grants no worker, private
read, action or export. With neither enrollment condition, idle resume appends no
runtime facts. Turning observability delivery off does not end an enrolled epoch.

Final initialization starts a fresh epoch. Resume identifies the previous epoch
and whether it was closed, without inventing legacy epochs. Logical close syncs
before exit and cannot prove the PID is dead. Explicit close includes actual
cleanup. Observed owner loss keeps cleanup false; untrappable death or lock loss
may leave an open epoch. Never append a speculative finish after ownership loss.

Interactive approval begins its wait before publication; policy allow/deny
creates no fake wait. Questions start after their checkpoint and bind the actual
source. Metadata carries event IDs rather than private IDs/answers. Only a valid
decision closes its own wait; stale decisions do nothing. Cancellation,
interruption and expiry remain distinct. A resumed question starts a new wait,
epoch and monotonic timer, leaving the old unclosed wait incomplete. Downtime is
not process-local duration.

A session permits 10000 runtime facts plus one stop notice. Starts reserve
closure capacity. Exhaustion visibly stops recording without stopping ordinary
work or cleanup. Tool recording has a separate quota below.

## Bind admitted tool input and result

Default-off `lifecycle.tools` requires `lifecycle.record`. It records bounded
sources without starting a worker or granting private access. Even metadata-only
live tool subscriptions require those recording grants. Private live reads need
`event.tool.input` or `event.tool.result`; history instead uses its separate
`host.history.tool.*` capabilities. Older journals without markers have no
reconstructed private view.

After real approval and synced ordinary `tool_started`, Session syncs
`lifecycle_tool_intent` before starting its task. Its fresh host tool ID binds
session, epoch, turn, request, source assistant call/index, admitted intent and
approval. Reusing a provider call ID later still yields a new occurrence.
A feed callback may run after execution starts and cannot approve or veto it.

The input and result data shapes are:

```json
{"name":"read","arguments_json":"{\"path\":\"notes.txt\"}"}
```

```json
{"text":"the exact recorded tool result"}
```

When the real tool message is recorded, the outcome marker binds its source to
the original host tool ID/source. Status is `result_recorded`, `error` or
`unknown`, never a worker's assessment of domain success. Metadata excludes name,
arguments, text, raw call IDs and private hashes. Both private views are untrusted
data, without complete assistant messages or native payloads.

Each encoded private data object fits 8 KiB, independently of complete SDK limits.
Larger views remain unavailable with counts/private digests, not truncated text.
Counts describe encoded structured objects, not raw text alone. A private feed
closes with `view_unavailable`; metadata/native history may remain available.
History reports its unavailable-view gap.

Tool timing spans admission through recorded outcome, including waits inside that
span. An explicitly resumed extension-tool question keeps its tool ID/source but
uses the new epoch and omits duration. Do not add restart downtime to an old
monotonic timer. Cancellation preserves unknown where the original tool result
says effects may have happened; abrupt exit can leave only intent.
Denied/invalid/unstarted proposals get no fabricated execution events. Native
questions, standalone commands/services and nested host-tool actions retain their
own identities rather than being relabelled model-selected tools.

Tool recording permits 10000 facts plus one stop notice and reserves outcome
capacity for each admitted input. Missing epoch/source/binding or exhaustion
stops recording and affected feeds visibly while tools/approvals continue.
Recovery checks request, turn, epoch, call position, intent, approval, result and
exact view/digest before repair. Physical source-to-marker scans stop within ten
records, allowing eight feed intents before a torn suffix.

## Choose a delivery contract after defining the source

| Consumer | Scheduling and pressure | Reply |
| --- | --- | --- |
| [Boundary notification](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-events.md) | Finite ordered required/optional plan | Exact acknowledgment |
| [Live feed](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-feeds.md) | Bounded serial queue with incomplete closure | Exact acknowledgment |
| [Event job](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-events.md) | Source-bound before-request/after-turn work | Approved finite host calls or final value |
| [Transform](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extensions.md) | Awaited boundary | Validated projection |
| [Diagnostics](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/observability.md) | Independent sampled queue/drop counters | Metadata acknowledgment |
| [Visible text](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/text-streams.md) | Private ephemeral stream with pressure | Text receipt |

Declarations select exact types, versions, views and modes under trust, scope,
activation and expiry. Unknown declarations refuse before startup. A reached
before-hook is a decision boundary, not a completed effect. Awaited recall must
finish before request context freezes; later publication affects a later request.
Arbitrary worker-origin host events, domain publication, concurrent effectful
background jobs and network bridges need explicit contracts beyond a new string.

Sync source and delivery/invocation/action intent before executable work. Preserve
identity, view and unknown outcomes. Idle resume validates without replay.
Catch-up is new bounded authorized work retaining original occurrence IDs and
coverage gaps. External writes still need their own idempotency/CAS. Tombstones
must reject delayed extraction after forget; deleting an index does not erase
sources, snapshots or previous egress.

Child completion requires an authenticated worker report after bounded result
and actual cleanup acknowledgment, not death alone. See [delegation](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/delegation.md).
Text sources use broker epochs/ranges instead of journal offsets and are rejected
by durable history/feeds; see [text streams](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/text-streams.md).

## Practice a source or private-view change

```sh
mix test test/lifecycle_test.exs test/lifecycle_metadata_test.exs test/lifecycle_runtime_test.exs test/lifecycle_answer_test.exs test/lifecycle_tool_test.exs
```

First compare identical-record IDs and source pages. Then inspect a resumed wait
and native-to-presented answer binding. In the tool suite, change private text
and recompute its digest: physical journal evidence must still reject it. Test
reused provider IDs, oversized views, stale references, owner loss and unchanged
idle resume. A projector unit test cannot prove delivery authorization, so run
the relevant feed/history fixtures too. Never execute a tool again merely to
reconstruct its event.
