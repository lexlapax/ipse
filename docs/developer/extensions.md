# Extension architecture and coverage

This guide records P22's design rationale, framework comparison and SDK/core
coverage gates. The research was reviewed on 2026-10-16 against `3ad33b3`;
implementation was subsequently authorized and its P22 gates passed at `de073ba`.
Proposed
callbacks and examples below are design targets unless an implemented contract
is linked here. This is not a frozen complete SDK or proof that every future
feature can avoid core changes.

Current contracts are organized by responsibility:

| Responsibility | Implemented contract |
| --- | --- |
| Package identity, import and worker execution | [Artifacts and worker SDK](extension-artifacts.md) |
| Scoped selection and trust | [Operator configuration](../operator/extensions.md#configure-selections) |
| Ordered prompt/completed-answer projections | [Session hooks](extension-hooks.md) |
| Tools, commands, services and finite host operations | [Invocations](extension-invocations.md), [host calls](extension-host-calls.md) |
| Explicit continuation and approved effects | [Questions](extension-questions.md), [workflow tools](extension-tool-actions.md) |
| Typed dependency composition and contextual evidence | [Services](extension-services.md), [context](extension-context.md) |
| Durable request facts and embedded/worker private delivery | [Usage accounting](usage-accounting.md), [text channel](text-streams.md) |
| Journal identity and typed recorded views | [Lifecycle adapter](lifecycle-events.md#internal-journal-source-and-prompt-views); raw pages stay host-only, while [history reads](extension-history.md) expose scoped projections |
| Declared read-only prompt/answer delivery | [Event subscriptions](extension-events.md), with separate metadata/private authority and required/optional receipts |
| Live committed views | [Feeds](extension-feeds.md), with scoped metadata/admitted-tool views, explicit enrollment, bounded consumers and visible incomplete closure |
| Source-bound prompt/answer actions and recall | [Event jobs](extension-event-jobs.md), with finite approved actions, before-request contributions and after-turn maintenance |
| Optional diagnostic capture | [Observability](observability.md), with operator policy, bounded owned sinks, aggregate local ring retention and immediate stop |
| Author conformance inputs | [Synthetic checks](extension-conformance.md), with normal trust/approval, scratch Sessions, explicit answers and content-free assertions |
| Independent domain package | [Extension lab](extension-proof.md), with separately compiled artifacts, candidate core freeze and unchanged installed-runtime verification |

The [lifecycle coverage audit](lifecycle-events.md#supported-lifecycle-coverage)
records supported private/causal seams, and the independent lab includes a
supervised extension-only authoring/review trial. Hosted Linux/macOS verification
of the current lab passed. The proof covers exercised domain seams, not the entire
SDK. Synthetic dispatcher tracing and source-debugging
boundaries are documented under observability. The
[plan](../plan.md#p22-extension-scaffold-and-lifecycle-hooks) owns current status;
[testing](testing.md#current-evidence-and-next-checks) owns actual results.
[Adoption scenarios](extension-scenarios.md) explain bundled, installed and
generated features. Inert local import and new-session activation are available;
remote acquisition, builders and hot activation remain future capabilities.

## Recommendation


Use a small versioned Elixir behaviour and OTP-owned workers around a shared
lifecycle event vocabulary. A hook is a selected handler at a documented boundary;
its delivery contract determines whether it observes, returns an ordered
projection or proposes separately admitted work. Separate private content access
from sanitized metadata, and event delivery from action permission. The
[event/subscription design](lifecycle-events.md) owns those distinctions and the
prompt-to-knowledge-graph acceptance proof.
Keep approvals, provider selection, journaling, compaction validation and process
ownership in the host. Reuse skills for instructions and MCP for explicitly
configured external capabilities. An extension may compose those facilities;
it should not replace the session loop with a mandatory workflow engine.

This recommendation is an architectural inference from the primary sources
below and the current implementation, rather than a claim that one upstream
plugin API can be adopted unchanged.

## What other harnesses do

| Harness | Observed mechanism | Lesson for Ipse |
| --- | --- | --- |
| OpenCode | Its main documentation describes local JS/TS modules or configured npm plugins, ordered hooks, tool before/after events and experimental compaction customization. Packages can install during startup. | Use explicit composition order and distinct lifecycle stages; keep executable loading/install an operator action. [Main docs](https://opencode.ai/docs/plugins/) |
| OpenCode V2 documentation | Domain-owned registrations distinguish prompt admission, model context and auxiliary requests; setup can return cleanup. V1 plugins require migration. | Version the API and separate prompt admission from each model call. Treat this as a separately documented V2 contract, not proof that every installed V1 supports it. [V2 API](https://opencode.ai/v2/docs/build/plugins/), [migration](https://dev.opencode.ai/v2/docs/build/plugins/migrate-v1) |
| Codex | Official hooks cover prompt, session, tools, permissions, compaction, children and stop/interrupt. Non-managed definitions require hash-based trust review. Matching command hooks can start concurrently. | Bind enablement to reviewed code/configuration identity; define which callbacks are ordered rather than inheriting parallel execution semantics. [Hooks](https://learn.chatgpt.com/docs/hooks) |
| Codex packaging | Plugins group skills, MCP and hooks. Hook scripts must exist on the execution host; enabling a plugin does not itself trust its hooks. Distribution/surface restrictions differ. | Separate packaging, installation, enablement and execution authorization. [Packaging](https://developers.openai.com/plugins/build/plugins), [supported surfaces](https://learn.chatgpt.com/docs/plugins) |
| Pi | TypeScript extensions provide lifecycle handlers, tools, commands, session entries and UI. Handlers distinguish observations from transformations; session data and cross-session storage are separate. Extensions share process OS permissions. | Explicit return contracts, durable non-context state and honest trust boundaries. [Extension guide](https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/extensions.md) |
| Pi typed events | Input returns continue/transform/handled; tool-call results can block. | Use typed results only at stages where the host supports the requested effect. [Public declarations](https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/core/extensions/types.ts) |
| Claude Code | Command/HTTP/MCP and model-backed hooks have event-specific inputs and decisions across session, turn and tool stages. | Document event schemas and cancellation/failure semantics individually. [Hooks reference](https://code.claude.com/docs/en/hooks) |

These are documentation/source comparisons, not installed interoperability tests.
Upstream main-branch documents are moving references, reviewed on the date above.
No upstream JavaScript runtime, plugin package or hook script was installed.

## Minimal scaffold and loading

The implemented scaffold separates `Ipse.Extension` (behaviour),
`Ipse.Extensions.Registry` (inert activation), `Host` (owned dispatch) and `Worker`
(independent VM/protocol ownership). Session retains admission and journal state.
Callback contexts are purpose-built JSON values, never the entire Session struct,
credential configuration, environment or provider-native data. Generic lifecycle
envelopes provide source identity, versions and distinct metadata/private views
under the supported [event contracts](lifecycle-events.md). Unsupported types or
delivery modes refuse; the coverage audit explicitly identifies unsupported stages.
Elixir [behaviours](https://elixir.hexdocs.pm/Module.html#module-behaviour) supply
callback contracts; [Task.Supervisor](https://elixir.hexdocs.pm/Task.Supervisor.html)
supplies owned work. Runtime return values still require host validation.

Compile bundled Elixir adapters into the release, including two opt-in examples.
Their data-only metadata is available without invoking code. Disabled adapters
must not introduce `on_load`, automatically started OTP applications or registration
callbacks that execute during boot/discovery; prove this in the release fixture.
Separate the adapter ID/manifest from its execution backend: a reviewed builtin
may execute in-VM; an independently installed artifact uses an owned external
worker. Both implement the same versioned, serializable invocation/result
contracts. Operator configuration selects installed string IDs or instance aliases,
order, enabled hooks, validated options and timeout/error policy. Unknown IDs
fail without download; flags/configuration never become module names or shell
strings. Do not create host atoms from arbitrary IDs or evaluate project `.exs`.

The [independent lab](extension-proof.md) proves local separately built Elixir
worker artifacts can be imported, configured and used without rebuilding Ipse.
Its synthetic memory/workflow proof leaves production algorithms to P25 and
unsupported SDK capabilities to explicit enhancements. A downloaded package manager,
marketplace, signing infrastructure and automatic builder can follow later using
the same artifact/activation contracts. A reviewed custom release remains an
optional distribution route, rather than the only way to add an extension.

Reuse P15 configuration precedence and provenance, but require explicit
operator enablement of executable extensions. Generic project-config trust alone
does not authorize new code, hooks or endpoints. A project may configure only
operator-enabled IDs within their declared scope; show the effective chain and
source. Pin API/module/build/config identity in the session manifest. Changed
identity refuses resume or requires an explicit new session; do not silently
reload code midway through work. Children receive a separately validated subset,
not the parent's whole extension state, context or external-service capabilities.

An in-VM extension is **trusted executable code**, with the VM user's access.
Allowlisted callback values and timeouts constrain the API, not arbitrary BEAM
code: a module could call File, spawn processes or inspect VM state directly.
Supervision does not sandbox it. Operator review is therefore essential. A
worker adapter therefore needs an explicit ownership/effect protocol. A separate
process provides code/heap/dependency separation, not OS confinement by itself;
trusted local workers retain the user's OS access unless a supported explicit
policy is selected. Existing MCP remains useful for external tools but is not a
generic lifecycle-hook standard or automatic authorization for external effects.

### Worker boundary

OTP code replacement operates on modules, and a VM's current exported code is
shared across its processes. Loading code can also run `on_load` functions.
Consequently, installing an arbitrary BEAM package into the host cannot be treated
as passive discovery or per-session version isolation. This motivates separate
workers for independently installed/generated packages. It is a design inference
from [OTP code loading](https://www.erlang.org/doc/system/code_loading.html) and
the [code server contract](https://www.erlang.org/doc/apps/kernel/code.html).

Keep the SDK/worker bootstrap usable without starting Ipse's Session/provider/auth
application tree inside the worker. Package authors depend on the SDK contract,
not private host modules or its dependency versions. Both backends must pass the
same invocation/result conformance fixtures before the SDK is considered stable.

The SDK must avoid PIDs, refs, functions, structs and arbitrary Erlang terms in
public values. A builtin facade translates those same JSON-shaped values to
local calls. A worker bridge negotiates protocol/SDK versions, required/optional
capabilities, artifact/runtime identity, schemas and limits before activation.
Use bounded framed local stdio, request IDs, deadlines, explicit cancellation,
late/duplicate-reply rejection, stdout protocol separation and bounded stderr.
No distributed BEAM node, shared cookie, implicit network transport or host state
access is needed. [OTP ports](https://www.erlang.org/doc/system/ports.html) supply
byte-oriented owned communication; cleanup of descendants still needs Ipse's
OS helper and verification, not an assumption that closing a port kills a tree.

Evaluate existing OTP, the current stdio owner/helper, Jason/JSONSchex and
maintained protocol packages before implementing framing/validation. Reuse
suitable pieces behind an Ipse adapter; document any missing lifecycle semantics
that require a small custom bridge. MCP transport ownership can inform reuse,
but do not pretend MCP already defines prompt/settlement callbacks. Each worker
receives purpose-specific context and explicit credential references only when
its approved capability requires them; no inherited host credential/environment
dump. This is API/data minimization, not a sandbox against trusted executable code.

The first standalone worker targets Elixir/OTP and existing declared tooling.
Later other-language workers can use the same wire contract, with explicit runtime
requirements and dependency approval/inventory; no new language runtime becomes
a silent Ipse dependency. Shared-worker reuse is deferred. Current callbacks use
fresh owned VMs for transforms/invocations; question continuations reconstruct
state from bounded JSON. Text consumers own a VM for their private resource
lifetime. An activation instance alone does not imply persistent VM state.
Preserve cross-process locking for intentionally shared durable stores.

## Lifecycle map

Design an event taxonomy for every meaningful lifecycle boundary, but implement
and stabilize only exercised seams. Events describe occurrences; hooks subscribe
to boundaries under explicit delivery contracts. Diagnostic notifications,
private feeds, ordered hooks and event-triggered jobs share correlation while
retaining different permissions, ordering and recovery. The
[lifecycle contract](lifecycle-events.md) defines source identity, original versus
effective prompt and original versus presented answer views, bounded delivery,
causal loops and no-replay semantics.
Neither private access nor metadata includes hidden reasoning or auth.

| Stage | Useful observations | Proposed transformation/effect boundary |
| --- | --- | --- |
| Configuration and session | Resolution, validation, start, resume, explicit close | Inspect selected extension manifest; executable activation remains operator-owned |
| Prompt admission | Original received, effective projection committed or failed | Bounded transforms, selected private notifications and separately admitted prompt jobs |
| Context assembly | Instruction/skill sources and sizes, retrieval contributions | Bounded publications and before-request recall jobs with frozen main-request snapshots |
| Model request | Start, first visible token, completion, error, cancellation, usage | P22 observes metadata; provider/model/billing and native continuation stay host-owned |
| Stream and completed answer | Visible output counts, final response saved, presentation ready | Initial postprocessor affects completed display only, not individual stream chunks |
| Tool lifecycle | Proposed, validated, approval requested/answered, intent synced, started, recorded/unknown/denied | P22 observes; future veto can restrict, never grant approval or rewrite a reviewed call |
| Operator questions | Waiting, invalid/stale answer, accepted, closed | Observation; answers cannot become effect approvals |
| Delegation | Proposed, child start/finish/failure/unknown, approval wait | Observation; preserve separate child ownership, limits and approvals |
| Compaction/checkpoint | Prepare, summary request/result, validate, synced commit, refusal | P22 observes; later contributions cannot bypass host validation or delete original evidence |
| Turn/session settlement | Done, failure, cancellation, owner death, close | Bounded best-effort notification; mandatory cleanup remains in supervisors/guardians |

Source integration seams are `Session.prompt/2` and prompt admission,
`system_message/1`, `launch_model/2`, normalized progress, `dispatch_tool/4`,
`launch_tool/4`, `tool_result/5`, question/delegation handling, compaction commit,
`finish/2` and cancellation. These are internal references, not public extension
callbacks. Avoid one giant callback with arbitrary access at every seam.

## Ordering, persistence and failure

Transforms run sequentially in explicit configuration order. Later transforms
see earlier validated projections. Diagnostic observers receive sanitized immutable
views; private subscribers need separate content authority. Read-only feeds cannot
return host actions. Effectful subscriptions admit owned jobs through the ordinary
approval/intent/outcome path. Background completion cannot alter an admitted model
request; same-turn recall uses an awaited boundary hook. Diagnostic sink completion
order has no effect on model or tool execution.
All slow work stays outside the Session GenServer in owned cancellable workers.
Reject synchronous reentry into the same Session while it waits for a callback.

Implemented contracts bound activation to eight instances, SDK objects to 16 KiB
and host actions to sixteen per invocation. Worker initialization/callback
deadlines are five seconds; workflow tools have their separately bounded tool
deadline. Hook input/output and global contextual evidence have distinct limits
in their authoritative guides. These replace the research draft's provisional
200–2000 ms transform timing. A transformer cannot raise the context ceiling.
Subscriber/job admission, queue bounds, diagnostic file quotas and visible
drop/gap counts still need implementation.
Validate encoded bytes, JSON shape and UTF-8; owned task shutdown is not hard
memory/OS containment. Unexercised observer contracts remain provisional.

Persist original user input, exact derived prompt/presentation, transformation
identity/order and source/config digests in bounded private events before use.
Keep original provider messages and tool results unchanged. Restore the committed
projection without calling extensions again; never replay effects on resume or
compaction. Compaction must account for extension contributions while preserving
operator intent and source references. An interrupted transform stays explicitly
incomplete, with no automatic model request. Do not promise exactly-once execution
of arbitrary extension code.

A required prompt transform that crashes, times out or returns invalid data stops
before inference; no silent untransformed fallback. A failed optional diagnostic
sink is disabled/reported without failing an otherwise successful tool. Prompt
notifications use their separate per-delivery required/optional policy; a fresh
explicit input may make a new delivery attempt. A failed
display formatter visibly falls back to the saved original answer, since the
model/effects may already have completed. Callbacks cannot relabel failed/unknown
effects successful. Journal failures retain the existing host failure boundary.

Postprocessing cannot erase streaming text already shown. P22 therefore retains
the existing visible stream and labels a separate completed formatted view.
Buffering/replacing the stream is a later explicit presentation mode. Neither
mode alters hidden/native continuation or rewrites the model's saved response.

## First two extensions

1. **Prompt context template:** append a bounded operator-configured task/style
   annotation as a separately attributed context contribution. Keep the exact
   original prompt, show the active template, journal the effective projection
   and apply it once per admitted user turn. No files, network, nested inference
   or changes to tools/provider/approval policy.
2. **Completed-answer formatter:** apply a configured plain-text wrapper to the
   completed visible answer and retain both original and labelled presentation.
   No changes to tool calls/results, citation source records or future provider
   continuation. Verify ordering, crash fallback and resumed presentation.

These deliberately exercise the two requested pre/post seams without introducing
storage or service dependencies. Custom transformations use the same behaviour
and validated contracts; the examples are not a fixed mandatory workflow.

## Long-term memory and customized workflows

The [independent lab](extension-proof.md) exercises synthetic memory/workflow
adapters through the generic SDK; production knowledge adapters belong to P25's
separate research/selection gates.
The two hook examples do not implement those systems. Session journals, research
ledgers and compaction checkpoints are not cross-session long-term memory.

A memory adapter needs scoped operator/project/namespace ownership, explicit
recall and remember/forget/export operations, retrieval budgets and attributable
source IDs/dates. Recalled text is untrusted data, never a new permission grant.
Persist which version/snippet influenced a turn, so later memory edits cannot
silently change resume. Remember/forget and external retrieval use host-approved,
journaled effects, with explicit endpoints/credential references and no hidden
provider calls. Define conflicts, stale data, deletion, secret exclusion, locks,
bounded records and cancellation before storing real material. Start evaluation
with local files/existing OTP facilities versus maintained SQLite packages;
choose a store from demonstrated needs. No mandatory database, embedding service
or vector engine is selected by this proposal.

Workflows should initially be skills plus optional Elixir adapters proposing
ordinary host operations: clarify, plan, delegate, review, test and report.
Each action keeps its own budgets, approvals and journal. Any automatic
continuation must be explicit and bounded, stopping for operator questions,
cancellation and unknown outcomes. Avoid recursive hooks or an unconditional
turn-complete handler that starts another turn forever. Do not add a workflow
framework simply to express a few module/process transitions.

## P22 completion evidence

### Core boundary and SDK coverage

The goal is that a new domain feature adds an extension package, configuration,
documentation and extension tests, without edits under `lib/ipse/` or `native/`.
Core owns the generic interfaces and safety invariants. Extensions own feature
policy and implementation. This is a measurable acceptance rule, not a guarantee
that future core defects or genuinely new host capabilities never need fixes.
An API gap needs a reviewed, general host capability with its own invariants;
do not add a feature-name conditional to Session or the CLI to work around it.

| Feature | Required generic SDK surface | Host retains |
| --- | --- | --- |
| Prompt preprocessing | Ordered prompt annotation/projection | Original intent, bounds, source identity, admission and durable projection |
| Output postprocessing | Completed presentation projection | Original model message/native continuation and streaming semantics |
| Custom tools | Activation-pinned descriptor/schema registration and owned invocation | Catalog collision checks, argument validation, full approval, intent and outcomes |
| Operator commands/forms | Namespaced command registration and existing structured-question API | Parsing, terminal lifecycle, stale-answer checks and permission separation |
| Long-term memory | Bounded context contributions, namespaced storage and approved effect proposals | Scope/locks, snapshot provenance, context budget and no replay |
| Customized workflows | Bounded host-action proposals at admission or before settlement | Cancellation, step/time budgets, child ownership, approvals and unknown-effect stop |
| Research integrations | Custom tools plus attributable context/source contributions | Research ledger validation, citations/provenance and effect policy |
| Optional provider integration | Registered provider-adapter contract with capability declaration | Explicit profile/model/billing selection, credential resolution and wire continuation integrity |
| Debugging/tracing | Shared lifecycle metadata, snapshots, diagnostic sinks and bounded synthetic dispatcher samples | Private journal integrity, argument exclusion, VM-side trace admission, quotas and owner cleanup |
| Usage/cost reporting | Canonical request/attempt usage facts and generic command/context registration | Durable identity/normalization; future budget admission/reservations |
| Streaming presentation | Typed private visible-content subscription | Sequence/flow control, cancellation and original provider history |
| Voice and realtime clients | Versioned owned-resource/media/provider capabilities | Turn/transport lifetime, approvals, playback reconciliation and explicit billing |

These surfaces belong in one small SDK with independently versioned contracts,
not one arbitrary callback that receives a Session PID and private state. Publish
behaviours, closed request/result schemas, fixtures and conformance helpers.
Registration rejects duplicate IDs, builtin shadowing, unsupported required
capabilities and unbounded descriptors before a session starts. Use namespaced
tool/command IDs; route through generic host dispatch, rather than new CLI cases
per extension. A provider registration is a later SDK capability: it must reuse
the existing public-interface and explicit billing rules, and cannot redirect a
configured request as a fallback. P22 need not rewrite existing provider adapters
merely to demonstrate the first examples.

The [runtime capability review](runtime-capabilities.md) assigns observability
controls/local developer diagnosis to P22, cost extensions/budget enforcement to
P23 and voice/realtime to P24. P22 establishes canonical usage facts and a bounded
read-only visible-text channel. Diagnostic samples, durable accounting and product
media have different delivery/privacy contracts; do not force them through one
Telemetry handler or JSON event queue. Media/realtime are negotiated boundaries
with explicit unsupported-operation errors until P24.

The requested shipped [knowledge extension family](knowledge-extensions.md)
belongs in P25: working/long-term memory, pluggable research, graph augmentation
and RAG, all default-off and independently selected. P22's generic service
composition, evidence, context/store and owned-job contracts must support these
without making any database, embedding provider or graph engine mandatory.

### Context, state and effects

Each public operation has a closed schema; arbitrary returned maps cannot be
interpreted as effects. Current interfaces and remaining proposals are distinct:

| Interface | Current contract or design target | Commit/use boundary |
| --- | --- | --- |
| Registration | Implemented inert manifest IDs, capabilities, schemas and options | Validate before activation; discovery executes no callback |
| Prompt/presentation | Implemented `append` or `prefix`/`suffix` objects | Journal source-bound derived projection; preserve originals/native data |
| Context contribution | Implemented `context.publish` sets with provenance | Accept/refuse within budgets, then pin exact main-request snapshots |
| Tool/command/service | Implemented declared result schemas or explicit `host_call` proposals | Owned invocation; full tool approval and finite separately admitted actions |
| Lifecycle subscriptions | Stable journal/tool sources, prompt/answer barriers and bounded live scoped feeds | Exact acknowledgment; separate private-view authority, barrier outcomes or incomplete feed closure, with no automatic replay |
| Triggered work and ordered recall | Implemented prompt jobs with before-request/after-turn schedules; broader lifecycle jobs remain pending | Separate action admission; committed source/provenance and deterministic request snapshots |
| Before-settlement scheduling | Future explicitly negotiated capability | Must validate remaining budgets/phase; no arbitrary auto-continuation exists |

The linked operation guides own exact implemented envelope fields and bounds.
Invocations and durable actions carry host-issued correlation IDs and source
identities; transform projections pin input/output/context digests. The planned
[lifecycle envelope](lifecycle-events.md#event-identity-and-views) adds durable
source identity, causal links, versions and explicit views. Tool/context text is
private capability data, not diagnostic payload. A hook result remains a typed
projection or proposal rather than an editable broadcast event.
Unknown result keys/kinds fail validation;
no returned command string is implicitly executed. Any policy veto may reduce
capabilities only. It cannot grant approval, rewrite already reviewed arguments,
change credential/provider selection or erase unknown outcomes.

Serialize stateful invocations per adapter/session, keeping slow work in an owned
worker and versioning the state snapshot committed with a derived projection.
Diagnostic observers use a separate bounded channel and cannot mutate that
durable state. A private subscriber requesting writes must enter the negotiated
event-triggered job/action contract; acknowledgment alone grants no effect.
Do not promise exactly-once callback invocation across a crash: only committed
results restore, while uncommitted transforms stop for explicit recovery and
effect intents retain unknown-outcome semantics. Specify init/shutdown failures
and owner cleanup independently of optional notification delivery.

Separate mandatory operator/repository instructions, original admitted intent and
provider continuation from optional reference documents, memory and extension
annotations. Each optional contribution declares origin, stable ID/version,
UTF-8 text, encoded-byte cost, priority and maximum budget. Current v1 publication
accepts or refuses a set atomically, preserving previous sets on refusal. A future
per-item selection policy must report what was omitted; it must never silently
remove mandatory instructions or native continuation. Retrieval does not get
unlimited space
just because it is useful. The supervised P21 trial's large instruction and
retained-context measurements motivate this distinction; they do not establish
that any mandatory instruction was safe to discard.

For version 1, the prompt example appends an attributed annotation. Arbitrary
rewrites require an explicit separate capability and operator-visible policy.
The host can validate structure, budgets and provenance, but cannot prove that
a rewrite preserved the semantic meaning of every original instruction. Keep
raw and derived values in the private journal, with a defined provider projection.
A privacy-redaction transform must not claim that data was removed from inference
if a pinned-intent ledger or compaction projection can reinsert it. Test that
case before offering such a transform. Admission runs once per new operator
prompt; context retrieval runs only at documented request boundaries. Restore
committed snapshots on resume and compaction without reexecuting either callback.

Storage is scoped by extension ID, operator/project identity and namespace, with
bounded record sizes, cross-process locks and explicit export/deletion semantics.
Start by evaluating existing OTP/files and maintained Mix packages against the
actual access pattern; choose no mandatory database or embedding backend now.
Separate private durable extension state from model-visible text. Remember,
forget, network retrieval and other effects are proposals that enter the same
host approval/intent/outcome path as builtin tools. Journal a stable operation ID,
adapter identity and outcome; interrupted effects remain unknown and are never
replayed automatically. State migrations are explicit offline operations with
their own review and recovery procedure, not resume callbacks with side effects.

Workflows can propose a structured question, ordinary tool request, child review,
or bounded continuation before a turn settles. The final `settled` event is
notification only. Host action validation applies the remaining step/time budget,
deduplicates operation IDs, and stops on cancellation, questions or unknown
effects. No observer may recursively start turns. Callback workers cannot make
synchronous reentrant calls into the waiting session. Generic proposals support
custom sequences without adopting a workflow framework or making self-development
a mandatory pipeline.

### Installation and compatibility

Separate immutable package artifacts, installed/trusted records and activation
instances. Builtin precompiled examples and standalone packages use the same
metadata/options/capability contract. P22 includes a minimal local artifact import
and registry, plus worker execution without a core rebuild. Managed network
download/build/install UX is a follow-on. No implicit project evaluation, startup
dependency download, host code-path injection or hot reload. Record licenses and
dependencies for every distributed artifact; disabled callbacks/init never run.
Project `.ipse/` configures only an operator-approved subset; flags override
invocation configuration within that ceiling, not executable trust or revocation.
Children get a validated subset with separate storage/approval/effect identities.

The implemented [artifact contract](extension-artifacts.md) owns manifest identity,
import staging, compatibility and installation transactions. The
[operator guide](../operator/extensions.md) owns selection, leases, promotion,
expiry and recovery procedures. [Adoption scenarios](extension-scenarios.md#configuration-lifetime-and-activation)
exercise those boundaries and future acquisition/activation designs without
claiming implementation. A session pins its exact active set/generation. Initial P22 activation
uses new sessions; live activation is a foreseen idle host transaction with a
versioned capability, rather than arbitrary code reload. The
[scenario matrix](extension-scenarios.md#scenario-tests) distinguishes foundation
fixtures from deferred conversational installers/builders and remote catalogs.

Pin SDK/protocol requirements, required capabilities, artifact/runtime digest,
instance/lease/generation, ordered configuration digest and projection version.
Configuration changes affect new sessions. Resume refuses unknown mandatory
versions, changed
identity, corrupt projections or missing required adapters before any callback,
tail repair or inference. Optional diagnostic sinks may be absent only under a
documented policy that cannot change context or effects. Provide compatibility
fixtures and a deliberate migration/new-session path, preserving old evidence.
Do not claim that an older binary can recognize future journal formats: document
the minimum reader version and forbid unsupported downgrade of such sessions.

In-VM modules remain fully trusted code, even when SDK capabilities are narrow.
Timeouts and owned tasks do not prevent arbitrary file access, memory exhaustion
or an extension deliberately spawning unowned processes. Extension conformance
is not OS sandbox certification. External execution must use a separately
reviewed process/protocol/isolation boundary; no automatic switch to an external
service is permitted.

### Delivery sequence and extension-only proof

1. **P22A — contracts and host kernel:** finalize schemas, capability/trust and
   version policy; separate package/installed/activation identities, then implement
   the registry, local immutable import, generic owned dispatch, worker bridge,
   durable projections and lifecycle events required by exercised capabilities.
   Keep SDK values serializable and backend-independent; define scoped instance
   configuration, session leases and a versioned activation-generation boundary.
   Include canonical request/attempt/parent identity and durable normalized usage
   facts with explicit unknowns. Separate droppable diagnostics, durable facts and
   private content subscriptions. Add durable source/causal identity, explicitly
   selected original/effective prompt views, event-triggered owned jobs and an
   ordered pre-request recall seam. Keep read authority separate from action/model
   authority; test gaps, duplicate delivery, self-trigger loops and stale writes
   after forget. Stabilize bounded read-only text delivery and
   version future media/resource capabilities without implementing voice.
   Define versioned service `provides`/`requires`, host-mediated typed invocation,
   scope/provenance and bounded jobs; reject unsupported dependencies, cycles and
   reentrant calls. Use P14 evidence identities for retrieval/memory snapshots.
   Include generic tool/command/context/state/effect seams rather than merely
   hardwiring the two examples. Keep unexercised callbacks provisional.
2. **P22B — two packaged examples:** opt-in prompt annotation and completed-answer
   formatter, with original/derived integrity, ordering and disabled parity.
   Prove compiled-in availability with zero disabled execution, generic config/
   flag overrides, distinct instances and operator inspect/enable/disable/recovery.
   Exercise a private read-only stream consumer; completed-answer formatting does
   not rewrite already delivered chunks. The default-off local trace sink in P22D
   uses the same extension configuration surface with a host capture/egress gate.
3. **P22C — coverage gate:** build a separate local memory/workflow demonstration
   package using only the documented SDK. Exercise scoped remember/recall/forget,
   a namespaced command/tool, a structured question and one bounded approved
   workflow action. Use synthetic local records, no model service or new store
   dependency. Freeze core before adding this package; the resulting diff must
   contain no core/native edits or feature-specific host branches. A failed gate
   sends the general SDK gap back to P22A before compatibility is declared stable.
   Run it as an independently built local worker artifact imported without
   rebuilding Ipse, with temporary-session use and explicit persistent configuration.
   Production memory stores, elaborate workflows, assisted download/build UI and
   live activation remain follow-ons against these same versioned contracts.
   Add a small synthetic retrieval service to prove declared composition and
   source-attributed context without building P25's production engines. Exercise
   the [prompt-event graph scenario](lifecycle-events.md#knowledge-graph-acceptance-proof)
   through a synthetic subscriber using only the frozen SDK, including background
   indexing versus awaited recall and no-replay recovery.
   The [current lab evidence](extension-proof.md) records the candidate freeze,
   41 source/installed assertions, supervised trial and passed platform gates; it does
   not certify unexercised contracts or production algorithms.
4. **P22D — observability and compatibility:** bounded local lifecycle sink,
   transform/event timing and drop counters; documented opt-in local BEAM tracing;
   conformance fixtures, package checks and a supervised extension-only trial.
   Include side-by-side pinned versions, install interruption, lease expiry,
   revocation, missing artifacts and clear unsupported-capability refusals from
   the [scenario matrix](extension-scenarios.md#scenario-tests).
   Remote OpenTelemetry is optional follow-on work with an explicit configurable
   endpoint and separate data-transfer authorization, not a completion dependency.
   Verify off/local/export configuration and immediate sink-stop, synthetic
   extension debugging, usage facts independent of tracing, and slow/cancelled
   stream consumers. Cost reports/budgets and audio delivery remain
   [P23/P24](runtime-capabilities.md#verification-and-milestone-scope).

For every phase, test crash/timeout/owner death, full queues, malformed/oversized
returns, unsupported identity, conflicting registration, cancelled/partial
projections, corrupt journals, child policy, no approval bypass and unknown-effect
no replay. Prove original/native data and admitted intent survive compaction.
Run credential-free source and extracted-package checks on Linux and hosted Mac;
report local live-provider and OS verification separately. Review SDK/operator
documentation, notices and links before committing/pushing each completed phase.

### Evidence requirements

Require disabled-by-default behavior parity; config/trust/version/ordering tests;
both adapters end to end; invalid output, timeout, crash and owner-death cleanup;
slow/full observer queue behavior; original/derived text and provider continuation
integrity; no approval bypass or new effects; separate child policy; cancelled
and resumed transforms; corruption refusal; and credential-free package examples.
Run Linux source/native and hosted Mac/package checks, plus an independently
reviewed supervised trial. Record real limitations and dependencies, review both
operator/developer guidance and links, then commit/push completed increments.

Use the proposed event requirements in [observability](observability.md) when
implementing the remaining observer contract. Current API/status is mapped at
the start of this guide. See
[P22](../plan.md#p22-extension-scaffold-and-lifecycle-hooks),
[configuration](configuration.md) and [recovery](context-compaction.md).
