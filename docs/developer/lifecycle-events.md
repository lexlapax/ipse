# Lifecycle events, hooks and subscribers

P22 lifecycle design, with an implemented internal journal-source and prompt-view
adapter. Generic subscription admission and event-triggered jobs remain pending;
this is **not an implemented subscription API**. Existing [transforms](extension-hooks.md),
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

The current internal adapter provides stable source references and typed prompt
views without changing the journal format or initializing any subscriber. The
[implemented source API](#internal-journal-source-and-prompt-views) below is the
building block for the remaining delivery contracts, not a new execution path.

| Needed by a prompt-driven knowledge graph | Current support | Remaining foundation |
| --- | --- | --- |
| Read prompt text | Selected prompt transforms receive effective visible user text | Generic subscription with an explicit original/effective view and scope |
| Extract entities | Extension code can compute on its callback input | Event-triggered owned job; optional model work needs a separately admitted request capability |
| Store derived facts | Explicit invocations can propose scoped state writes | Event-to-job admission that can use the same action path |
| Add recalled evidence to an answer | Invocations can publish bounded attributed context | Ordered pre-request retrieval hook with a committed snapshot |
| Consume generated text | Selected workers receive acknowledged visible-text frames | Keep this loss-aware content channel separate from sampled diagnostics |
| Recover without duplicate effects | Invocation/action receipts and cached projections already exist | Bind triggered jobs, outcomes and deduplication to their source event |

The current prompt transform cannot return `host_call` to store entities. A text
consumer acknowledgment also cannot request effects. Implementing a graph by
performing untracked I/O inside either callback would bypass the intended host
contract. Worker isolation alone does not prevent reviewed executable code from
using ordinary OS permissions; capability checks govern supported host APIs and
do not constitute a new OS sandbox.

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

Pages are **private journal data**, including records unsupported by the event
adapter. Do not forward them wholesale to workers or diagnostics. A source
reference's canonical digest detects a changed record supplied with that
reference. Legacy records are readable within these bounds; unsupported large
records refuse rather than being skipped or truncated.

`Ipse.Lifecycle.Event.project/3` checks source/content binding and creates a closed
version-1 envelope for the currently exercised prompt facts:

| Existing journal source | Event type | Private view |
| --- | --- | --- |
| `extension_prompt_received` | `prompt.received` | `prompt.original` |
| User `message` | `prompt.expanded_committed` | `prompt.expanded` |
| Validated `transform.prompt` result | `prompt.projection_committed` | `prompt.projection` |

Every type also supports a `metadata` view containing only byte counts, stable
source correlation and, for a transform, operation/artifact correlation. Metadata
excludes prompt text and content digests. The private view contains only its
selected text and private source binding, never the full journal record or native
continuation. Both use the existing 16 KiB SDK-object bound; private strings retain
the 8 KiB limit and overflow refuses without truncation. Larger future private
feeds need negotiated resource handles/flow control.

These stages describe the actual saved facts: `expanded_committed` precedes
transforms, and a projection may precede another configured transform. Neither is
advertised as the final request prompt. Original input is currently recorded only
when prompt transforms are selected. Legacy bare prompt records do not carry a
turn ID, so the adapter does not invent one. Final effective-prompt seams, full
causal links, ephemeral event identity and other lifecycle types remain pending.
No manifest/configuration capability exposes these internal functions yet;
projecting a view in host code is not subscriber authorization. The host API digest
now pins Journal, Source and Event alongside existing extension contracts.
Neither `Source.valid?/1` nor `Event.project/3` authenticates a worker-supplied
record/reference pair. Future host admission must resolve references against its
owned validated journal; workers cannot manufacture authoritative host facts.

Nine Linux source fixtures in `test/lifecycle_test.exs` exercise stable identities,
repeated prompts, legacy/noncanonical JSON byte positions, paging/record limits,
tail/duplicate-key/scalar refusal, forged bindings, private-view bounds and secret
exclusion. A real selected prompt-transform session verifies the three committed
stages and byte-identical idle resume of the original session ID. The bundled
`priv/extension-demo.exs` additionally checks those views/source IDs in source and
extracted-runtime verification. See [actual verification scope](testing.md#current-evidence-and-next-checks);
these fixtures do not establish subscriber admission or graph-job behavior.

## Delivery contracts

Data access and scheduling are declared separately. A subscriber requesting
private content must not acquire it by subscribing to a metadata topic.

| Contract | Ordering and overload | Permitted response |
| --- | --- | --- |
| Diagnostic notification | Independent bounded queues; sampling/drop counts are visible; sink failures do not fail the turn | Acknowledge metadata only; no host actions or context changes |
| Private content feed | Per-subscription sequence, bounded bytes/in-flight delivery, acknowledgment and explicit gaps/incomplete closure | Acknowledge the selected content view; effects require separate job admission |
| Ordered boundary hook | Host awaits handlers in configured order at a named seam; deadline or invalid required result stops that transition | Schema-checked projection, context contribution or restrictive decision permitted at that seam |
| Event-triggered job | Host admits a bounded owned job against a committed source event; action proposals use the ordinary approval/intent/outcome path | Finite negotiated host actions; no recursive turn launch or implicit provider call |

An acknowledgment means the delivery was accepted, not that a graph write or
model request succeeded. Job admission, action completion and job completion
have separate receipts. Subscriber failure cannot turn an unknown action into a
successful one. Mandatory cleanup and recovery facts never depend on optional
subscriber delivery, including a final close/owner-death notification.

The first triggered-job implementation uses a bounded queue and one effectful
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
Session. Unknown declarations fail validation. These fields are design targets,
not currently accepted manifest/configuration examples.

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
Tombstones/revisions must prevent a delayed extraction or reindex job from
resurrecting forgotten facts; deletion of derived stores does not erase original
journals or prior provider transfers.

Other systems use a reviewed adapter over the same typed event/view contract,
with explicit endpoints, authentication, export authority, flow control and
acknowledgment semantics. An MCP connection alone does not imply support for
event subscriptions. No unauthenticated listener, distributed BEAM node or
mandatory external broker is needed. A future CloudEvents transport mapping can
preserve source/ID/type and causal extensions without changing internal delivery
semantics; no CloudEvents conformance or transport is claimed here.

## Knowledge-graph acceptance proof

Before freezing P22 core, extend the independent installed-package proof:

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

These are pending executable acceptance cases. Passing the design walkthrough
does not complete P22 or establish production graph quality. P25 owns researched
entity extraction, graph storage/retrieval and quality comparisons.

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
