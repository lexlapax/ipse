# Lifecycle events, hooks and subscribers

P22 lifecycle design with implemented journal-source, runtime-wait and prompt/answer adapters and
[bounded read-only subscriptions](extension-events.md) plus separate
[event jobs](extension-event-jobs.md) for approved actions, awaited recall and
after-turn maintenance. Prompt/answer barriers and
[live scoped feeds](extension-feeds.md) are implemented, including
[admitted-tool input/results](tool-events.md). The
[coverage audit](#supported-lifecycle-coverage) distinguishes stable seams from
unsupported stages and incomplete legacy correlations.
Existing [transforms](extension-hooks.md),
[invocations/actions](extension-host-calls.md), [context](extension-context.md)
and [visible-text delivery](text-streams.md) retain their current wire contracts.
The [plan](../plan.md#p22-extension-scaffold-and-lifecycle-hooks) owns delivery
status. Observability is one consumer of this foundation, not its definition.

## Model and current coverage

An event describes a lifecycle occurrence. A hook is a selected handler attached
to a documented boundary. A subscription declares which occurrences a handler
receives and how the host delivers them. A returned action proposal asks the
host to do something; it is not an event saying that the action already happened.
For example, a tool proposal, synced tool intent and recorded tool outcome are
three distinct facts. Receiving any of them grants no tool permission.

A before-hook event means the host reached a boundary and is awaiting a typed
decision; it does not mean the proposed operation completed. The host validates
the result and emits a separate committed/refused occurrence. After-hooks consume
that outcome. Neither can change an earlier event or grant new authority by
returning a modified copy of it.

Use one versioned lifecycle vocabulary and host-issued correlation model, with
separate delivery and data-access contracts. Do not turn every callback into an
unordered broadcast, or make diagnostics the only way to receive lifecycle data.
Existing journals remain the recovery authority; this does not require replacing
Session with a new event-sourcing or workflow framework.

The internal adapter provides stable source references, typed prompt/answer views and
allowlisted metadata for other saved boundaries without changing the journal
format or initializing any subscriber. The
[implemented source API](#internal-journal-source-and-prompt-views) below is the
building block for selected notifications and the remaining delivery contracts.

| Needed by a prompt-driven knowledge graph | Current support | Remaining foundation |
| --- | --- | --- |
| Read prompt text | Selected transforms, read-only original/final-effective subscriptions and source-bound jobs with explicit capabilities | Broader private lifecycle views and continuous private feeds |
| Observe host activity | Exact live metadata and separately granted admitted-tool views, bounded queues and explicit incomplete closure; installed consumers verified | Other private views require the explicit enhancements identified by the coverage audit |
| Extract entities | Owned prompt jobs can run deterministic extraction | Model work needs a separately admitted, accounted request capability |
| Store derived facts | Prompt jobs use normal approved state actions with source-bound invocation receipts | Production storage adapters and complete forgetting policies |
| Add recalled evidence to an answer | Before-request jobs publish bounded attributed context into a frozen request snapshot; installed lab exercises explicit history catch-up | Broader context seams and production recall quality |
| Consume generated text | Selected workers receive acknowledged visible-text frames or completed original/presented answer events | Keep these explicit content channels separate from sampled diagnostics |
| Recover without duplicate effects | Source-bound receipts, question checkpoints, no automatic replay and installed lab deduplication/tombstone checks | Production reindex policy and externally committed effects |

The current prompt transform cannot return `host_call` to store entities. A text
consumer acknowledgment also cannot request effects. Implementing a graph by
performing untracked I/O inside either callback would bypass the intended host
contract. Worker isolation alone does not prevent reviewed executable code from
using ordinary OS permissions; capability checks govern supported host APIs and
do not constitute a new OS sandbox.

## Supported lifecycle coverage

This audit describes candidate core `3b0ef78`, exercised by the independent lab
at `2874da0`. It checks the actual `Lifecycle.Event`/`Metadata` projectors,
`Subscriptions` and `Feeds` declaration allowlists, history grants, runtime/tool/
child source validators and Session's synced record/delivery boundaries. The
table is the supported surface, not a promise that every internal function emits
a callback. An unavailable stage/view is refused rather than synthesized from a
nearby fact. A source ID identifies an occurrence; delivery, invocation and action
IDs identify separate attempts to consume or act on it.

| Boundary | Implemented observation or hook | Causal/private limits |
| --- | --- | --- |
| Configuration/session | Inert registry/configuration inspection; `session.created` in recorded history; opt-in epoch start/resume/logical close | Initialization/close facts are outside live-feed enrollment. No callback can rewrite configuration, trust or auth. Prior unrecorded epochs stay absent |
| Prompt admission | Ordered `transform.prompt`; original/effective `notify` or `job`; recorded expanded/intermediate projections | Selected prompt markers bind actual turns; each committed projection is its own occurrence. No unrestricted prompt wildcard, implicit private grant or synthetic prompt-refusal event |
| Context assembly | Bounded caller-owned `context.publish`, awaited before-request recall, frozen request snapshot; workspace/catalog/extension metadata | Extension snapshot binds the request. Older workspace/catalog facts expose counts without invented request/turn links. No complete private system-message subscription |
| Model execution | Admitted/usage/finished/measured metadata, actual request/attempt/parent identities and independent durable accounting | Generic feeds do not expose counters/pricing. P23 adds a separate own-session `usage.read` grant; accounted extension model requests and budgets remain host work, with no hidden callback inference |
| Visible output/answer | Negotiated ephemeral text frames; ordered `transform.presentation`; committed original/presented answer notifications/jobs | Text ranges have broker/stream identity, not journal offsets. The completed answer binds the effective prompt and native request. No hidden reasoning, provider-native payload or audio access |
| Tools/approvals | Opt-in admitted-tool intent/outcome metadata and separately granted private input/result feed/history; operator wait start/finish | Host tool IDs bind actual admitted request/turn/call and source facts. Denied/invalid/unstarted calls have no fabricated execution event. No proposal/validation veto callback or approval-granting hook |
| Operator questions | Waiting/answered/closed metadata; actual wait/source identity; explicit extension question continuation | Generic question metadata omits text, answer and raw call ID. Only the admitted question continuation receives its validated answer. Invalid/stale replies do not become accepted events or approvals |
| Children | Recorded start/result metadata and live feed/history; authenticated parent-side result and cleanup acknowledgment | Completion binds its actual start source and available parent request/turn. Child subscriptions require independent permitted selection; parent private grants do not transfer |
| Compaction | Committed/refused metadata and separately accounted compaction requests; cached checkpoint validation | No hook may replace native continuation or delete evidence. Legacy commits without request/turn links remain unlinked; prepare/veto/private-summary subscriptions are unsupported |
| Turn settlement | Settling/finished/cancelled metadata and host-owned after-turn jobs | Settlement retains its actual turn ID; older generic finish/cancel facts have no invented link. A final notification cannot be required for cleanup or effect completion |
| Owner death/close | Owned resource cancellation, recorded logical closure where ownership still permits it, incomplete open epochs after abrupt loss | No reliable last callback can run after untrappable death or loss of journal ownership. Cleanup confirmation and VM exit are separate facts; incomplete work is not replayed |
| Custom/external events | No worker-origin host facts or arbitrary publication; local envelopes provide a future bridge boundary | Namespaced domain publication, remote subscription transport, media and concurrent effectful scheduling need explicit versioned contracts, not new strings in existing declarations |

Durable observation uses exact supported versions/views. Notify/job declarations
select only original/effective prompt or completed-answer boundaries. Live feeds
select the separate metadata allowlist plus admitted-tool private views; historical
reads have separate view grants. Source recording, diagnostic capture, subscription
delivery and action permission are independent switches. There is no global
cross-session ordering or exactly-once guarantee for arbitrary external effects.

The existing fixtures exercise unknown versions/modes/views refusing before
initialization, private/metadata separation, physical source/causal validation,
bounded queues and incomplete closure, disabled parity and inert resume. The
[installed lab](extension-proof.md) proves the prompt-to-graph, catch-up, workflow
and private tool/text paths without feature-specific host dispatch. This audit
finds no additional core seam required by those exercised P22 scenarios. Consumers
needing a row's unsupported capability require an explicit SDK enhancement;
P23/P24 own their remaining runtime features; proposed P25 research informs deferred
P26/P27 production knowledge work.

## Internal journal source and prompt views

`Ipse.Lifecycle.Source` binds a journal record to its session ID and byte offset.
Its version-1 event ID is the first 128 bits of SHA-256 over the domain-separated
session/offset identity; the canonical record digest separately binds content.
The digest stays private. Distinct records with identical text get distinct IDs;
all supported views of one record retain its source ID. This relies on append-only
journals: edits/replacement require corruption review, not silent reuse of an old
reference with changed content. The reference is identity, not authentication or
a permission token.

`Journal.append_with_source/3` returns a reference only after the append is synced;
the caller must hold the session lock. The existing `append/3` and `load/2` retain
their behavior. `Journal.source_page/4` reads complete records from a byte cursor
without rewriting old journals, repairing tails or invoking callbacks. Pages
contain at most 64 records and 1 MiB of raw JSON record bytes, plus bounded source
references; individual records are capped at 1 MiB. The default count is 32.
Reads use bounded chunks, validate record boundaries and reject duplicate JSON
keys, non-object records and oversized/incomplete lines. A non-nil next cursor
may need one final empty read to establish EOF. Concurrent append/tail repair
needs the caller's ordinary session ownership policy; this API does not create a
transactional catch-up snapshot or retry a changing tail automatically.
Page reads validate the selected records, not the entire journal or its session
metadata. Full Session recovery validation and scope checks remain prerequisites
for admitting any work from those facts.

The optional fifth `source_page/5` argument is an exclusive, validated byte
boundary. Bounded line reads do not parse later records, and reaching that fixed
boundary returns `next: nil`. The four-argument API retains its existing open-tail
semantics. The [history operation](extension-history.md) adds the missing SDK
admission: own-session anchor/view validation, separate private grants, bounded
pages and explicit skipped/gap rows. It does not forward raw journal pages.

Pages are **private journal data**, including records unsupported by the event
adapter. Do not forward them wholesale to workers or diagnostics. A source
reference's canonical digest detects a changed record supplied with that
reference. Legacy records are readable within these bounds; unsupported large
records refuse rather than being skipped or truncated.

### Prompt and answer views

`Ipse.Lifecycle.Event.project/3` checks source/content binding and creates a closed
version-1 envelope. Prompt facts have explicit metadata and private views:

| Existing journal source | Event type | Private view |
| --- | --- | --- |
| `extension_prompt_received` | `prompt.received` | `prompt.original` |
| User `message` | `prompt.expanded_committed` | `prompt.expanded` |
| Validated `transform.prompt` result | `prompt.projection_committed` | `prompt.projection` |
| Selected subscription's `lifecycle_prompt_received` | `prompt.received` | `prompt.original` |
| Selected subscription's `lifecycle_prompt_committed` | `prompt.effective_committed` | `prompt.effective` |
| Selected subscription's `lifecycle_answer_committed` | `answer.committed` | `answer.original` or `answer.presented` |

Every type also supports a `metadata` view containing only byte counts, stable
source correlation and applicable host operation/request/turn/artifact correlation. Metadata
excludes prompt text and content digests. The private view contains only its
selected text and private source binding, never the full journal record or native
continuation. Both use the existing 16 KiB SDK-object bound; private strings retain
the 8 KiB limit and overflow refuses without truncation. Larger future private
feeds need negotiated resource handles/flow control.

The answer marker is a distinct boundary after native completion and all
presentation transforms. `Lifecycle.Answer` binds the original assistant message
digest, final presented text, turn/request IDs and effective-prompt source. Session
recovery checks those against actual preceding messages/projections; source
validation also resolves the prompt reference physically. It is not the earlier
`assistant.committed` message metadata or a chunk/playback acknowledgment.
Original/presented views share one answer source ID. Each retains at most 8 KiB;
larger text is unavailable, with byte count and private digest retained rather
than truncation. Metadata remains available, and a bounded presented view can be
selected independently of an oversized original. Native history is unchanged.
An answer-only subscriber gets no private prompt data from its causal reference.

These stages describe the actual saved facts: `expanded_committed` precedes
transforms, and a projection may precede another configured transform. Neither is
advertised as the final request prompt. Selected subscriptions add a distinct
final-effective user-text marker after all prompt transforms, with received-source
and turn bindings. Original input is recorded when transforms or prompt subscriptions
are selected. Legacy bare prompt records do not carry a turn ID, so the adapter
does not invent one. Full causal links and broader
lifecycle delivery remain pending. The [subscription contract](extension-events.md)
grants selected views through the host; projecting a view in host code alone grants
no authority.

### Committed metadata

Other committed facts have allowlisted metadata projections through
`Ipse.Lifecycle.Metadata`, using the same source ID, envelope and bounds.
Admitted-tool sources additionally have separately granted private views under
the [tool event contract](tool-events.md). The table describes metadata only.

| Source family | Event vocabulary | Selected metadata |
| --- | --- | --- |
| Session header | `session.created` | No configuration, credentials or paths |
| Recorded process epoch | `session.started`, `session.resumed`, `session.close_committed`, `session.recording_stopped` | Host epoch/previous-epoch IDs, previous closure state, logical closure/cleanup confirmation or source-limit notice |
| Operator wait | `wait.started`, `wait.finished` | Host wait/epoch IDs, approval/question domain, actual available turn/request/invocation/operation/child links, selected question's causing-event ID; finish adds outcome and process-local elapsed milliseconds |
| Admitted-tool input/outcome | `tool.intent_committed`, `tool.outcome_recorded`, `tool.recording_stopped` | Host tool/epoch/turn/request IDs, actual causing sources, encoded view byte counts, approval/status and available process-local duration; no names, arguments, result text or private hashes |
| Request admission, usage observation, completion and measurement | `model.admitted`, `model.usage_observed`, `model.finished`, `model.measured` | Existing request/attempt/turn/parent IDs, kind, sequence, duration, outcome and finality where saved |
| Saved assistant/tool text and tool start | `assistant.committed`, `tool.result_recorded`, `tool.started` | Text byte count, existing assistant request ID or approval category; no arguments, result text or raw provider call IDs |
| Workspace/catalog/extension context and compaction | `context.workspace_committed`, `context.catalog_committed`, `context.extensions_committed`, `context.compaction_committed`, `context.compaction_failed` | Source/tool counts or existing request ID; no paths, contributions, summaries or error strings |
| Native questions | `question.waiting`, `question.answered`, `question.closed` | No question/answer or arbitrary call ID |
| Delegated child start/result | `child.started`, `child.finished` | Host child ID; result adds actual parent turn/request/start-event links, status, fixed reason, duration and cleanup acknowledgment; no task/result text or raw call ID |
| Extension receipts | `extension.invocation_admitted/recorded`, `extension.action_admitted/recorded`, `extension.question_waiting`, `extension.continuation_admitted`, `extension.delivery_admitted/recorded`, `extension.text_admitted/ready/closed` (each slash denotes separate types) | Existing invocation/operation/continuation/delivery/resource IDs, action count and host action/delivery outcomes where saved |
| Turn settlement, completion and cancellation | `turn.settling`, `turn.finished`, `turn.cancelled` | Existing settlement turn ID or bounded status category |

The projector selects fixed fields and rejects invalid selected identifiers,
numeric values and enum dimensions instead of coercing them. Other private fields
are never copied. An invocation result is **recorded**, not necessarily a successful
business operation; its arbitrary returned value cannot set the metadata outcome.
Event-job invocation metadata includes its delivery ID and `causing_event_id`
from the validated private trigger, excluding trigger digests and source hashes.
Request admission retains actual parent request/session links. Missing legacy
links remain absent: the projector does not guess a turn, hash arbitrary call IDs
into public identifiers or invent a cause from adjacent records.

This is a display projection, not a complete journal validator, authentication,
subscriber admission or an exporter. Owned Session recovery validation and physical
source resolution remain prerequisites for actions. Unknown source types refuse.
Negotiated [visible-text events](stream-events.md) have a separate ephemeral
source contract and never enter journal history or these committed-type feeds.
The session header describes creation; the optional runtime
facts below distinguish subsequent process epochs. A saved tool
message proves that a result was recorded, not the success of its underlying effect.
The host API digest pins these lifecycle, subscription and history adapters
alongside existing extension contracts. Neither `Source.valid?/1` nor
`Event.project/3` authenticates a worker-supplied record/reference pair. Host
admission resolves saved references against its owned validated journal;
workers cannot manufacture authoritative host facts.

### Runtime epochs and operator waits

`Lifecycle.Runtime` records these metadata sources when capture starts in `local`
or `export` mode, or a selected reviewed artifact declares `lifecycle.record`.
The capability enables source recording independently of diagnostics; it grants
no callback, content read, host action or export permission. With both absent,
no runtime facts are appended, including on an idle resume. Current subscriptions
retain prompt/answer boundaries. Live metadata feeds can select waits and the
recording-limit notice with `lifecycle.record`; initialization/final-close facts
remain outside live enrollment. Authorized metadata history reads expose those
recorded facts without starting a feed.

At the final initialization boundary, each recorded process gets a fresh `epoch_id`.
A resume identifies the prior recorded epoch and whether it was closed or
unclosed; legacy/unrecorded history has no invented prior epoch. `session.close_committed`
means the logical close result was synced before process exit, not that the PID
is already dead. Explicit close includes the existing cleanup result. Owner loss
records its observed cause but leaves `cleanup_confirmed: false`, since that path
does not confirm orderly diagnostic-resource cleanup. Unexpected termination,
untrappable kill or lock-helper loss may leave the epoch open. Termination does
not append a speculative finish or write after journal ownership is lost.

Interactive native tool, extension-action and delegated-child approvals start
distinct waits before operator publication. Accepted decisions close only that
wait; stale references do nothing. Policy allow/deny without an operator wait is
not given a synthetic waiting span. Native and extension questions start after
their question checkpoint, preserving existing checkpoint adjacency. Their
private source references resolve the actual preceding question occurrence;
public metadata carries only its event ID, never raw question/provider IDs,
text, arguments, answers or BEAM references. Extension waits bind their real
parent invocation/operation; standalone extensions do not borrow an earlier
model request ID.

Only validated answers finish a question wait. Cancellation records `cancelled`;
observed owner/worker interruption records `interrupted`; extension lease loss
at approval records `expired`. None authorizes later effects. An explicitly
resumed question gets a new wait/epoch and monotonic start time, retaining its
actual saved question source when available. A prior unclosed wait stays
incomplete; downtime is not added to a fabricated duration. Legacy questions
without a recorded reference retain that absence. Recording/schema restoration
and physical source validation run before tail repair or further work.

The durable session admits at most 10,000 runtime facts plus one
`session.recording_stopped` limit marker. Starts reserve room for their matching
end/close facts. Exhaustion disables further runtime recording for that session,
leaving any unclosed span explicitly incomplete; it does not deny ordinary agent
work or cleanup. Diagnostic filtering, sampling, stop and sink acknowledgments do
not control these already-enrolled sources. In particular, `/observability off`
stops sample delivery; runtime metadata recording ends with this epoch or its
source limit. A new invocation uses its reviewed configuration again.

### Validation and verification

Nine source fixtures in `test/lifecycle_test.exs` exercise stable identities,
repeated prompts, legacy/noncanonical JSON byte positions, paging/record limits,
tail/duplicate-key/scalar refusal, forged bindings, private-view bounds and secret
exclusion. Four `test/lifecycle_metadata_test.exs` fixtures cover the wider closed
vocabulary, request/parent correlation, malformed dimensions and exclusion of
business assertions. A real selected prompt-transform session verifies prompt and
model boundaries plus byte-identical idle resume; the job fixture checks actual
source-to-delivery-to-invocation causation. The bundled `priv/extension-demo.exs`
checks shared prompt/model source IDs and request correlation in source and
extracted-runtime verification. See [actual verification scope](testing.md#current-evidence-and-next-checks).
Projection fixtures alone do not establish broader subscriber delivery or production graph behavior.

`test/lifecycle_runtime_test.exs` checks strict restoration, bounded recording,
native decisions, questions/restart, cancellation, owner loss, physical-reference
refusal before repair and disabled parity. Independent event-job fixtures exercise
`lifecycle.record` with capture off, separate mutation approval and extension-question
restart; delegated fixtures check child correlation and lost-child wait closure.
The bundled runtime fixture exercises idle start/close/resume and metadata
projection. The [independent domain package](extension-proof.md) separately tests
these seams against an unchanged installed runtime.

### Delegated child outcomes

Opt-in delegation always saves its existing start record. Its parent-side
`delegation_finished` receipt binds the real start source and parent request/turn
to a host child ID. The registered worker reports after the bounded result and
child close; unrelated callers and stale jobs refuse. `child.finished` projects
only status, fixed reason, process-local duration and cleanup acknowledgment.
It is available through ordinary metadata feeds/history independently of
diagnostic capture and requires no private child-text grant.

`result_recorded` requires a bounded result and the owned child's actual logical
cleanup acknowledgment before exit. It does not establish business success or
detached-descendant containment. `unknown` covers timeout, unavailable results,
child/worker failure or parent cancellation; the reason is a closed enum, never
an arbitrary error. A monitor exit cannot promote unknown work to success.
Abrupt parent death may leave no outcome at all. Old starts stay readable without
invented completions, and idle resume appends or replays none. Strict reduction
and physical start-source resolution run before tail repair. See
[delegation ownership and bounds](delegation.md#lifetime-and-recovery).

`lifecycle_child_test.exs` covers projection privacy, malformed/duplicate receipts,
parent/source bindings and the absence of cleanup acknowledgment from a dead PID.
Real delegation tests cover authorized reports, cancellation, timeout, parallel
child loss, inert resume and source refusal before repair. The live-feed fixture
checks shared start/completion identity through independently compiled consumers;
the serial bundled demo checks real receipts in source/extracted runtimes.

### Ephemeral visible-text occurrences

The opt-in v2 private text channel carries broker epochs, fresh stream IDs and
accepted byte ranges. Metadata/private projections share range identity while
consumer-local delivery sequences and coalescing remain separate. Subscription
closure has no invented request position. The [stream event contract](stream-events.md)
owns negotiation, schemas and limits. Durability, history, diagnostics and live
metadata feeds do not automatically acquire this private channel. Other progress
and media variants require their own negotiated contracts; no audio, exporter or
playback semantics are implied.

## Delivery contracts

Data access and scheduling are declared separately. A subscriber requesting
private content must not acquire it by subscribing to a metadata topic.

| Contract | Ordering and overload | Permitted response |
| --- | --- | --- |
| Implemented prompt/answer notification | Finite ordered boundary plan, one active callback, explicit required/optional outcomes | Exact acknowledgment only; metadata or separately granted private view |
| Diagnostic notification | Independent bounded queues; sampling/drop counts are visible; sink failures do not fail the turn | Acknowledge metadata only; no host actions or context changes |
| Implemented live scoped feed | Selected committed facts after explicit enrollment; bounded serial queue, durable intents/acknowledgments, visible incomplete closure on pressure/failure | Exact acknowledgment only; metadata or separately granted tool input/result, with no implicit history/actions |
| Private content feed | Per-subscription sequence, bounded bytes/in-flight delivery, acknowledgment and explicit gaps/incomplete closure | Acknowledge the selected content view; effects require separate job admission |
| Ordered boundary hook | Host awaits handlers in configured order at a named seam; deadline or invalid required result stops that transition | Schema-checked projection, context contribution or restrictive decision permitted at that seam |
| Implemented prompt/answer job | Host admits a bounded owned job against a committed source event; action proposals use the ordinary approval/intent/outcome path | Finite negotiated host actions; no recursive turn launch or implicit provider call |

An acknowledgment means the delivery was accepted, not that a graph write or
model request succeeded. Job admission, action completion and job completion
have separate receipts. Subscriber failure cannot turn an unknown action into a
successful one. Mandatory cleanup and recovery facts never depend on optional
subscriber delivery, including a final close/owner-death notification.

The implemented event-job plan is finite and uses one effectful
extension action lane per session, admitted at documented safe boundaries.
Slow computation runs outside Session. A callback cannot synchronously reenter
the Session waiting for it. Work needing interactive approval or clarification
must enter that lane explicitly; a background notification cannot create a
second, competing operator conversation. Queue-full admission has a visible
refusal or gap, never an unbounded mailbox or a silently lost committed job.
Fully concurrent effectful jobs are a separately negotiated host enhancement.

A background index update does not promise to affect the current answer. Context
is frozen at request admission. A same-turn recall requirement uses an awaited
context hook; a background publication is eligible only at a later documented
request boundary. Completion timing must not change an already admitted request.

## Event identity and views

Specify a closed envelope and a schema per event type before exposing it to
workers. The envelope needs:

- Envelope and payload-schema versions, event type and host-issued event ID.
- Session, turn and relevant request/tool/job identity; parent and causing-event
  links where present. Independent subscribers get distinct delivery/job IDs.
- A source position for committed events, and an explicitly ephemeral epoch and
  sequence for progress/content frames. There is no global order across sessions.
- Host origin versus extension origin, including the pinned originating instance
  and activation generation for extension-produced facts.
- A declared data view and bounded payload or opaque scoped resource reference.
  Relative monotonic timing belongs to its process epoch; wall-clock timestamps
  cannot establish causal order across restart.

Assign durable source identity before delivery and retain it on explicit
redelivery. Do not mint a new occurrence ID for each sink or derive identity only
from prompt text: identical prompts submitted twice are two occurrences. Existing
journal events need an additive source-position/identity adapter; do not reinterpret
old recovery records or reexecute them to manufacture notifications. Diagnostic
projections retain permitted correlation to their source but exclude private data.

The initial prompt stages distinguish operator input received, effective prompt
committed after skill expansion/transforms, and request context committed. A
subscriber explicitly selects its source view. Generated annotations and memory
recall must not masquerade as new operator input. Prefer effective committed text
for a graph intended to mirror model input; original operator text is a separate
grant for applications that need it. Original text and earlier journal entries
may remain private even when a later projection is redacted.

Metadata contains only host-allowlisted categories, measurements and correlation
IDs. Private prompt/tool/output views need separate read capabilities and scope;
neither raw content nor content hashes are automatically safe diagnostic labels.
Provider-native continuation, hidden reasoning, credentials and complete Session
state are excluded. Large content uses bounded opaque handles with instance,
generation, lifetime and read limits; handles are not paths, URLs or authority
to arbitrary storage. Media keeps its negotiated data plane rather than encoding
audio into lifecycle events.

The taxonomy covers session, prompt, context, model, visible output, tools,
approvals, questions, children, compaction, extensions/jobs and turn settlement.
Only implemented seams and schemas may be advertised as available. Unknown
required types, versions, views or delivery modes refuse before executable
activation; existing SDK v1 callbacks must not silently gain new semantics.

## Subscription, permission and ownership

Declarations belong in inert, schema-checked manifest data: exact event types and
versions, content view, delivery mode, ordering/required policy, bounded options
and requested capabilities. Bind the effective selection to artifact/options,
operator trust, project/session/child scope, activation generation and expiry.
No executable filter, arbitrary topic wildcard or worker-selected scope runs in
Session. Unknown declarations fail validation. The implemented
[notification schema](extension-events.md#inert-declaration-and-authority)
supports read-only `notify`; [job declarations](extension-event-jobs.md#declarations-and-handlers)
add a typed handler and before-request/after-turn schedule. The separate
[feed schema](extension-feeds.md#declare-a-feed) selects supported metadata or
separately granted tool input/results during live work. Other private views and
delivery modes remain negotiated design targets.

Prompt access, persistent writes, external transfer and model inference are
separate grants. Installing or enabling a graph extension does not imply all
four. Deterministic extraction can use the owned worker without inference;
model-based extraction needs an explicit profile, usage/budget admission and
provider/billing authority. Current host actions do not yet expose that generic
model-request capability. Storage/network proposals still require their normal
approval policy even when prompted by an authorized subscription.

Every delivery/job owns its worker/resource lifetimes and bounded cancellation.
Expiry, unsubscribe, explicit stop and owner death revoke future deliveries and
close dependent resources. Already committed effects/history remain. Child
subscriptions require their own permitted subset and cannot inherit the parent's
private feed implicitly. Idle resume validates receipts without initializing
subscribers or replaying jobs; a fresh explicit operation uses a new admission.

Extensions cannot publish forged host events. Future custom domain events use a
declared namespaced schema and host-mediated publication, retaining origin,
causation, depth and budgets. P22 can reserve that extension point while refusing
unsupported publication. Initially jobs do not trigger themselves from their own
result events; any later cross-extension chain needs explicit routing and bounded
depth/fan-out. Graph updates, diagnostics and context publication must not form an
automatic extraction loop.

## Recovery, replay and external systems

Sync source facts and job intent before executable initialization. Record pinned
subscriber identity, input view/snapshot, source event, operation IDs and validated
outcomes. An interrupted job/effect remains incomplete or unknown; subscription
startup/resume does not retry it. Deduplication uses source event, subscriber
identity and operation identity. External stores need their own idempotency/CAS
contract; an event ID alone cannot make arbitrary writes exactly once.

Diagnostic gaps may be accepted; missed knowledge ingestion must be visible.
Explicit catch-up/reindex is a separate approved bounded job over an authorized
source range, preserving original source IDs and its own new job identity. It
does not replay tools or assume old data-access/model authority. Retention limits,
partial history and unavailable private content produce an explicit gap/refusal.
The implemented [own-session history primitive](extension-history.md) supplies
that recorded-view range to selected SDK code; source fixtures exercise an
explicit catch-up command, question continuation and separate write approval.
The [independent lab](extension-proof.md) exercises domain deduplication, bounded
catch-up and stale-write rejection after forget. Production reindex policy remains
separate. Reaching the range end does not establish complete original/effective
coverage in legacy history.
Cached history receipts also resolve physical anchors/projections and contiguous
source spans during recovery, diagnostics and handoff validation. These checks do
not rerun history operations or replace their cached pages.
Tombstones/revisions must prevent a delayed extraction or reindex job from
resurrecting forgotten facts; deletion of derived stores does not erase original
journals or prior provider transfers.

The shared envelope is the integration boundary; local SDK consumers need no
global event bus. Other systems would use a reviewed bridge extension over the
same typed event/view contract, with explicit endpoint, authentication, private
read and egress grants. Its delivery/job contract must distinguish local receipt,
remote acknowledgment and committed remote effects, and specify bounded buffering,
disconnect recovery and explicit catch-up. Publishing or writing cannot be hidden
in a read-only acknowledgment. No network subscription endpoint or background
effectful bridge is currently implemented; an MCP connection alone supplies neither.
No distributed BEAM node or mandatory broker is needed. A future CloudEvents
transport mapping can preserve source/ID/type and causal extensions without
changing internal delivery semantics; no conformance or transport is claimed here.

## Knowledge-graph acceptance proof

The P22 coverage gate requires the following cases. The
[independent extension lab](extension-proof.md) exercises deterministic graph
capture, recall and recovery against candidate core `3b0ef78`; primitive fixtures
cover additional bounds and failure paths. These are distinct evidence layers:

1. Select a private prompt subscription explicitly; with it disabled, no graph
   worker, store or model request starts. Metadata-only subscribers never see the
   synthetic prompt secret. Verify original/effective stages are distinct.
2. Commit a prompt event, admit one owned extraction job and extract synthetic
   entities deterministically. Propose a scoped write through existing approved
   actions. A subscription acknowledgment alone cannot write or infer.
3. Store source-event identity, original evidence reference, extractor/artifact
   version and revision with the entities/edges. Verify duplicate delivery does
   not duplicate committed records, while identical new prompts remain distinct.
4. Compare background indexing with awaited recall. Prove background completion
   cannot alter an admitted request, and a required recall failure stops inference
   rather than silently omitting the promised contribution.
5. Exercise queue saturation, invalid/oversized data, approval refusal, cancellation,
   owner death, expiry and idle resume. Verify no automatic effect replay, visible
   gaps/unknown outcomes and no recursive event loop.
6. Delay a job across forget/delete; reject stale writes. Exercise explicit bounded
   catch-up, scoped child refusal and a synthetic external adapter without an
   actual network service or new core feature-name dispatch.

Source fixtures now cover prompt-job admission, deterministic extraction, approved
CAS writes, required recall, after-turn request isolation, question recovery and a
delayed write rejected after concurrent forget. Additional SDK fixtures cover
fixed-range history pagination, private grants, gaps and inert catch-up resume.
The installed lab adds domain deduplication, bounded catch-up, scopes, versions,
question/workflow continuation, private tool/text consumers and pressure closure,
without core changes or a release rebuild. A supervised extension-only trial also
ran with separate read-only review. The [coverage audit](#supported-lifecycle-coverage)
defines the stable seams; hosted Linux/macOS verification passed at `de073ba`. These checks
do not establish production graph quality. Proposed P25 researches extraction,
storage/retrieval and evaluation choices; P26/P27 defer production implementation
and its quality measurements until those choices are reviewed.

## Reuse decisions and sources

[Telemetry](https://telemetry.hexdocs.pm/telemetry.html) invokes handlers in the
calling process, provides no handler ordering guarantee and detaches failing
handlers. It can feed trusted metadata instrumentation; it does not supply the
ordered projection, private capability, owned job or durable effect contract.
[Phoenix.PubSub](https://phoenix-pubsub.hexdocs.pm/Phoenix.PubSub.html) supplies
topic subscription/broadcast and pluggable distribution. Ipse initially needs
local bounded owner-managed delivery, not distributed fan-out; PubSub alone
would still need host admission, privacy, queue and recovery adapters.

[CloudEvents 1.0.2](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md)
separates event context from data and defines source/ID duplicate identity. Use
those interoperability ideas without claiming that an envelope supplies
transactional delivery or permissions. Existing OTP processes/monitors, the
worker bridge, Jason/schema adapter and journals are the initial implementation
building blocks. No package or outside runtime is added by this decision.
