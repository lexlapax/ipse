# P30 and P31 delivery design

Superseded after review by the [revised design](../2026-10-26-p30-p31-plan-review/design.md)
and [audit disposition](../2026-10-26-p30-p31-plan-review/index.md). The original
body below is retained as historical design, including its unresolved gaps.

Planning record dated **2026-10-26**, based on `caf7221` and the
[knowledge product assessment](../2026-10-26-knowledge-productization/index.md).
Historical design record; use the [current plan](../../plan.md) for active scope
and acceptance, and the [operator manual](../../operator/index.md) for implemented
commands. This request authorizes planning and roadmap changes, not implementation,
provider spending or a release. Proposed additions are not implemented commands.
The [previous P30/P31 bodies](prior-milestones.md) preserve the superseded scopes.

## Selected product outcome

P31 makes project knowledge useful from a release archive. A person enables notes,
documents or relationships, then works normally. Ipse recalls relevant evidence,
automatically saves useful facts and decisions within the approved scope, reports
what changed, and supports inspection, correction, forgetting and disablement.
It checks available information before asking about a material missing choice.
An explicit prompt-enhancement interaction lets the person review changes before
submitting a task; it never silently replaces their intent.

The developer selected these behaviors in plain-English questions:

| Decision | Selected behavior |
| --- | --- |
| Conversation capture | Automatically save useful facts and decisions and show changes |
| Permission lifetime | Keep the approved project choice across future sessions; re-ask for changed scope, services or limits |
| Incomplete requests | Look for the answer first, then ask only about choices that materially affect the task |
| Routing freedom | Automatically choose among enabled knowledge sources; ask before changing model providers or paid services |
| Document coverage | Include PDFs and Word documents in P31 |

Implement document support for text/Markdown/code, text-bearing PDF and Word
`.docx`. Define those formats precisely in setup and acceptance; legacy binary
`.doc`, scanned/image-only PDF, OCR and embedded objects need separately evaluated
extractors and are not silently claimed as supported. Unsupported/encrypted inputs
must receive an actionable per-file result. The format boundary is an implementation
proposal, not evidence of tested coverage. PDF and Word cannot be deferred out of
P31 merely because plain-text ingestion is the first development slice.

P30 remains the typed decision operation and its measured consumers. P31 owns
the knowledge and prompt-assistance experience. Voice/realtime media moves to
P32 without losing its existing scope. P20 remains completed self-development.
Automatic knowledge must work with no decision service configured. A configured
decision engine adds a measured optional strategy; its failure does not authorize
switching to another model, provider, service or billing mode.

## User journeys that define completion

| Journey | Required result |
| --- | --- |
| Enable project knowledge | Guided scope/model/storage/budget choices; no source checkout, Elixir helper, handwritten JSON, hashes or MCP for local use |
| Work normally and start another session | Useful eligible facts/decisions are saved and recalled automatically; covered work does not ask for another permission grant |
| Inspect or correct a memory | Show source, speaker/evidence class, time, scope and dependencies; corrections do not silently erase historical assertions |
| Use selected documents | Preview included/excluded files, ingest with progress, answer with inspectable quotations, detect changes/deletions and show unsupported files |
| Track entities and relationships | Capture typed, attributed relationships from eligible conversation/source evidence; resolve known aliases, expose conflicts and support time-qualified questions |
| Forget and disable | Stop future use/publication at the defined boundary; show dependent records and explain retained journal/backup/external copies |
| Ask an incomplete question | Retrieve available facts first, ask a short material question only when needed, and use the answer in the actual executing model request |
| Improve or plan a task | Review an optional rewrite; accept/edit/cancel; planning-only mode enforces its advertised effect ceiling before explicit execution |
| Recover an interruption | Show saved, pending, partial, failed and unknown work; do not repeat an effect that might already have happened |

Coding and non-coding scenarios are mandatory: project conventions, product/spec
documents, client/account ownership changes and an ordinary research question.
“Knowledge” is the family name; Memory, Corpus and Graph remain independently
selectable. A single enable flow must not silently turn on all representations.

## Architecture and ownership

Keep extraction, ranking, retrieval, entity resolution and clarification policy
in feature packages/skills. Keep authority, canonical evidence references,
accepted operator intent, accounting, cancellation and recovery in reviewed host
contracts. Use ordinary Elixir modules and OTP ownership. Do not introduce a
workflow framework, a graph-of-agents runtime, or a mandatory remote database.

| Area | Owner and contract |
| --- | --- |
| Setup/status/management | Terminal/client: translate ordinary choices into reviewed configuration and explicit permission; no hidden grants in project files |
| Persistent permission | Generic host: protected consent records, admission checks, revocation generations and aggregate budgets |
| Durable evidence and indexes | Selected knowledge storage adapter with a host-admitted access contract; extension algorithms cannot bypass host effects by opening arbitrary stores |
| Capture and recall | Memory/Corpus/Graph jobs and tools; source-bound candidates and projections; bounded context contribution |
| Cross-package use | Explicit evidence transfer/typed contract or shared pure domain implementation; no shell recursion into Ipse and no assumed nested effectful services |
| Decision operations | P30 host effect, profiles and adapters; P31 consumer rubrics and deterministic mappings |
| Prompt editing and planning | Skill/extension analysis; client/host owns explicit accepted input and mode ceilings |
| Work lifetime | Session-owned bounded work first; durable checkpoints and explicit recovery; no detached extension task or always-on daemon |

Activation must reconcile today's exact session artifact pins. Guided enablement
prepares the chosen packages and policy, then performs a reviewed versioned
transition or a safe session handoff that retains the conversation, unfinished
intent and explicit unknown outcomes. Prefer the simpler honest handoff if hot
activation cannot preserve those invariants. Show when the feature becomes active;
no manual prompt copying, fingerprint repair or implied hotload from a config edit.
Disabling stops effects immediately under policy even if removing the selected
artifact from the catalog requires that same safe transition.

The current SDK already supports in-package read-only recall jobs. A friendly
Graph capture tool can reuse its existing dispatcher and quote-based citation
construction. Neither needs a new general composition API. Review new contracts
only where the integrated journey requires them: complete event evidence,
cross-store invalidation/transfer, durable scoped effect consent, sustainable
storage, accepted intent and planning enforcement.

### Persistent consent without repeated prompts

Setup creates a protected operator consent record, separate from ordinary
configuration. It binds project identity/root rules; selected features and data
categories; excluded paths/data; storage and sharing scope; allowed effect types;
service/profile/endpoint/model and billing identities; retention; and finite
limits with units and reset periods. A profile name alone is insufficient if its
endpoint or billing destination changes. Never store secrets in the policy.

Fresh and resumed sessions validate the current consent, then authorize covered
**new** effects without asking again. Both outer extension-tool dispatch and inner
State/model/embedding/decision/MCP operations must consult the policy; covering
only internal writes would leave read-tool approval fatigue. Arbitrary native
edits, shell execution, unrelated MCP, source-file deletion, child delegation and
cross-project access remain outside the knowledge grant.

Compatible reviewed package upgrades can retain semantic consent when scope,
service, limits and behavior contract are unchanged. Executable artifact trust
remains separate: an arbitrary replacement with the same display name must not
inherit trust. Define explicit old/new artifact admission and schema compatibility
checks during upgrade. Expanded authority requires a concise change review.
Reducing limits, pausing or disabling takes effect without a confirmation loop.

Use a monotonic revocation/policy revision visible to concurrent sessions.
Define atomic ordering between revocation/suppression and local publication,
including concurrent processes: separate pre-commit generation checks alone are
insufficient. Acknowledgment means no new dispatch or later local publication
under the revoked authority; identify already committed work and outstanding
remote effects. A stale prepared write cannot commit after that boundary.
An already dispatched remote effect may have
completed and retains uncertainty. Revocation never promises rollback. Retained
journal receipts document prior authority; they cannot create or restore it.

Persistent consent does not override an explicit read-only mode, a deny rule or
the existing headless execution gate. Headless mutation still requires `--yes`;
saved project consent alone must not make a read-only `run` start writing.
Child sessions do not automatically inherit the project automation grant. A
separate explicit child delegation contract would need its own acceptance.

Project allowances must survive process exits and new sessions. Define atomic
reservations across concurrent sessions, per-operation limits and aggregate
period budgets, including unresolved external liability. A new session must not
reset the spend limit. Unknown prices are visible and require an explicit
resource/call-limit policy; they are never reported as zero cost.

### Evidence, time, storage and migration

Maintain stable source occurrence IDs, immutable source versions, speaker/role,
observed time, asserted event/validity time, content hash/span references, origin,
source generation, provenance and consent revision. Separate original evidence
from notes, facts, entity links, embeddings and query indexes. Derived material
retains dependencies on its supporting versions. A citation establishes source
bytes, not truth; retrieval content remains untrusted reference data.

Support user facts/decisions, quoted sources and verified tool outcomes with
distinct classes. Assistant suggestions and inferred conclusions must retain
that status; repeating a previous answer must not turn it into independent
evidence. Capture ordinary outputs when eligible, but do not automatically admit
all generated prose as established fact. Negative, hypothetical, disputed and
uncertain assertions need explicit handling.

The current 1-MiB/256-record State namespace and tombstone accumulation cannot be
the promised everyday collection ceiling. Evaluate maintained Elixir/Rust/OTP
storage choices before selecting a scalable local adapter. Keep admission,
bounded reads, transactional publication, cancellation and recovery inspectable;
do not trade them for arbitrary extension filesystem access. A desktop user must
not need to run a database service. No new dependency is selected in this plan.

Historical questions require retained versions and temporal semantics. Current
`as_of_ms` cannot reconstruct a replaced generation. Define observation time
versus asserted event time, corrections versus retractions, and explicitly
unknown dates. Retention limits may remove historical evidence; queries must
show that gap rather than claim complete history.

Forget creates suppression for managed source lineage and declared aliases,
invalidates dependent projections across managed stores, and blocks stale queued
capture. Disabled stores must revalidate shared suppression before re-enable,
read, import or migration; disabling Graph cannot protect its stale facts from a
later forget. Test reindex, backup import and renamed sources against that lineage.
Do not promise perfect detection of every independent paraphrase. Physical
collection, suppression, expiration and deletion of journals/backups are separate.
Define complete export/import and a migration plan for P26/P27 stores, preserving
suppression first. Preflight, checkpoint, validate and switch atomically; retain
a rollback path that cannot resurrect subsequently forgotten data. Mixed old/new
writers must refuse or be drained before migration.

Project identity is explicit and inspectable. Start with the selected canonical
project root; moving a directory or joining worktrees requires an explicit mapping
or migration, not accidental cross-project merging. User-wide sharing is a
separate opt-in scope. Existing operator-scoped notes remain available through
their existing configuration; P31 does not silently promote project evidence.

### Capture, ingestion and recall lifecycle

Use one visible logical operation for capture/ingestion, with internal effect
intents preserved. Inspect source/class/exclusions before egress, extract bounded
candidates, resolve source versions and aliases, optionally assess candidates,
then publish eligible results under current consent. Uncertain facts can remain
pending or be skipped with a reason. Never relabel a partially published batch as
fully saved. Deduplicate by evidence identity without inventing new aliases after
a forget or conflict.

Files enter through an approved folder/file selection with inclusion preview,
explicit size/type limits, regular-file/symlink/path handling and secret exclusions.
A URI is not automatic fetch permission. Ingestion must identify changes,
renames/deletions, unsupported formats and extraction failures; write generations
and indexes atomically enough to expose incomplete work. A selected semantic
profile defines embedding identity and rebuild behavior. No configured embedding
failure silently changes retrieval strategy or provider.

Acquire source bytes through a narrowly admitted bounded reader, including binary
PDF/Word inputs; today's text read tool is not a document-import protocol. Evaluate
maintained Elixir/Rust parsers or bounded adapters before choosing extraction tools.
Any non-Elixir/Rust executable/library dependency needs explicit approval and an
inventory/license entry before adoption; installed users must not assemble a
converter toolchain. Retain original file hash, extractor/version and extracted
text version with stable page/paragraph/table-cell anchors. Citations must identify
both the original document and the exact extracted evidence, with limitations
where layout cannot be mapped faithfully.

PDF fixtures include multi-column order, tables, ligatures, headers/footers and
page boundaries. Word fixtures include headings, lists, tables, footnotes and
tracked changes/comments: define which revision and annotations are admitted and
show that choice. Set input, expanded-container, page, text, CPU/time and memory
limits. Cover malformed/encrypted/empty/image-only documents and ZIP/XML expansion
hazards. Never execute macros, follow external relationships or fetch linked
content during parsing. Partial extraction is visible and cannot stand for a
complete document. Changes/deletion invalidate derived excerpts just as for text.

Before-request recall runs once per accepted user turn, using the original or
explicitly accepted prompt and eligible sources. Rank within a finite context
budget, retain citations and allow explicit tool searches later. Clear invalid
contributions on source change/forget/expiry and on optional recall failure;
existing context replacement failure preserves old content, so this policy must
be implemented deliberately. Required-source failure stops the dependent answer;
optional failure continues with a visible limitation and no stale excerpts.
Before every actual model dispatch, including tool/question continuations, cheaply
revalidate already selected contributions against source/policy/expiry generations;
this does not rerun retrieval at each step. Remove/refuse invalid contributions.
Document that previously transmitted text or provider-native continuation cannot
be recalled by later forgetting; offer an explicit fresh-context handoff when the
user needs to stop carrying that prior context into future work.

Capture uses Session-owned finite work with progress and deadlines. It must not
delay display of an already produced answer or block a new prompt on unrelated
capture. Bound queue references/bytes, per-project concurrency and shared budgets;
prioritize foreground work and show deferred/coalesced/backpressured work. Current
after-turn work keeps the Session busy; any improvement must preserve one
conversation owner and cancellation. A new prompt uses a disclosed settled snapshot;
recent unsaved information remains conversation evidence, not a claimed store commit.
For long work, offer pause/checkpoint/explicit continuation. Cross-session resume
of known unstarted work is distinct from retrying a dispatched unknown effect.
Do not add an unattended daemon or independent persistent scheduler in P31.

Current private event views are single occurrences and omit answer text above
8 KiB. Provide a narrowly granted bounded evidence reference/reader and explicit
prompt/answer/tool joins for capture. Oversized or unavailable evidence is reported;
do not silently capture a prefix and call it the whole turn. Work triggered by
capture itself must not recursively generate further capture.

Define turn settlement beyond the current success-only `after_turn` hook. Accepted
user facts can remain eligible after a model failure, but failed/partial assistant
output is not a completed answer and unaccepted clarification choices are not
decisions. At a question wait, use existing accepted evidence without treating the
wait as a completed turn. Cancellation stops that turn's pending capture/effects;
show retained commits and skipped/unknown work, and require an explicit later
continuation for unstarted work. Never lose or silently recapture such events on
resume; bind checkpoints to exact event identity and settlement status.

### Prompt assistance and accepted intent

Use native `ask_operator` first: answers already return to the main model and
discard pending calls based on its prior assumptions. Inspect authorized context
before asking. Distinguish available facts, material intent, low-impact assumptions
and required unavailable facts. Group related questions, avoid repeated answered
questions, and bound clarification rounds. A question answer is not action consent.
Headless required unknowns produce an actionable incomplete result, not invented
answers or automatic selection of a recommended option.

Offer user-invoked enhancement with original/proposed/accepted text and source
references, visible assumptions, edit/accept/cancel and restart recovery. A
versioned host intent record binds text, question/evidence IDs, confirmation and
the consuming request: pending → accepted/cancelled → consumed. Refuse stale or
duplicate acceptance; only the current accepted text becomes the executing request.
Unaccepted drafts are not captured
as user decisions. Preserve provider-native conversation history; never rewrite
old messages to simulate a correction. Append-only extension transforms remain
reference annotations, not authority to replace user intent.

Planning-only mode allows admitted reads, questions, main inference and explicitly
authorized helper/decision calls, but denies workspace and knowledge publication.
Internal journals/accounting still persist; plans can be displayed and retained
as host artifacts. Exporting a file is a separately identified effect. The ceiling
applies to extensions, MCP, children and resumed continuations, including otherwise
authorized automatic capture. Planning advice stays in skills/extensions; the
host enforces the ceiling and explicit transition to execution. Accepting a plan
does not authorize unrelated effects.
Entering planning stops further prohibited dispatch and settles or explicitly
accounts for already in-flight effects before acknowledging its ceiling. Exiting
requires an explicit mode transition; stale queued work cannot use that transition
as permission to execute. Mode changes never promise to undo earlier effects.

Busy input is visibly queued unless the user chooses an explicit interrupt.
Interrupt acknowledges stopped further dispatch and any in-flight uncertainty
before accepting a replacement intent. P31 does not promise unrestricted live
steering or rollback of external effects.

## P30 as a usable decision capability

A typed classifier evaluates supplied candidates/evidence. It does not extract an
arbitrary graph, generate a better prompt, establish a fact's truth or grant
permission. P31 owns extraction and prompt assistance; host policy controls
permission. Attributed evidence remains fallible.

### Verified interfaces and selection limits

Research on 2026-10-26 used the official
[OpenAI guide](https://developers.openai.com/api/docs/guides/decisions) and
[create reference](https://developers.openai.com/api/reference/resources/decisions/methods/create).
The documented operation is `POST /v1/decisions`, currently using `gpt-6-luna`;
questions return predicates, choices or fractional ordered-level scores. Valid
per-question refusals can coexist with answers. The reference exposes usage but
no request monetary-budget field, so Ipse must enforce its own admission budgets.
This does not establish live account access or subscription eligibility.

[TypeSafe System One](https://docs.typesafe.ai/api/system-one) uses `state` and a
named question map. Its selected text subset uses Noul/Choice/Score responses;
the API's experimental Box type is outside the initial Ipse contract.
[Choice](https://docs.typesafe.ai/primitives/choice) and
[Score](https://docs.typesafe.ai/primitives/score) preserve distributions and
provider confidence; [model identities](https://docs.typesafe.ai/models) must be
pinned for calibration. These are adapter differences, not reason to coerce one
wire format into another or invent unsupported refusal fields.

[bhubbard/zev-rs](https://github.com/bhubbard/zev-rs) is an identified experimental
Zev candidate with MIT package metadata, not a selected engine. Its
[server](https://github.com/bhubbard/zev-rs/blob/main/src/server.rs) and
[wire conversion](https://github.com/bhubbard/zev-rs/blob/main/src/wire.rs) expose
similarly named endpoints with different native input and lossy structured-input
conversion. A `jev-latest` compatibility alias is not the actual engine identity.
Pin a source/artifact, check all dependencies/model licenses and pass exact subset
conformance before claiming compatibility. No local engine is mandatory.

### Neutral contract and consumer boundary

Start with bounded text/JSON evidence, string question instructions and stable
string choice IDs. Version requests, capability declarations, named question IDs,
rubrics and answer schemas. Preserve finite probabilities, fractional scores,
complete distributions and separately named raw provider confidence. Derive
consumer uncertainty using measured policy; do not equate confidence with truth
or silently compare raw scales across engines.
Validate exact question count/type/IDs and option/level coverage, probabilities
in [0, 1], distribution sums within a declared tolerance, and score range/mean
consistency with the adapter's documented rubric. Finite numbers alone are not
sufficient validation. Unsupported primitive/structured-input forms refuse before
dispatch instead of being silently flattened by a compatibility server.

Missing, duplicate, malformed or out-of-set answers invalidate the structural
result. A valid refusal is an outcome for that question, not corruption of the
whole batch. Independent successful answers may be used only where the consumer
declares them independent; dependent actions require every prerequisite answer.
Distinguish refusal, insufficient evidence, uncertainty, budget denial, timeout,
unavailable service and malformed output.

The dispatch sequence is:

```text
eligible evidence + finite allowed alternatives
  → permission-admitted, journaled decision under selected profile/reserved budget
  → deterministic validation and consumer policy
  → current permission / source-version / budget recheck
  → ordinary journaled effect or explicit no-action result
  → visible reason and outcome
```

| Consumer | Decision evaluates | Permitted consequence |
| --- | --- | --- |
| Retrieval route | Query needs, available indexes and evidence types | Choose an already enabled local/semantic/graph/combined strategy within its approved services and limits |
| Capture assessment | Candidate durability, support, ambiguity and conflict | Admit an eligible attributed candidate under saved capture consent, retain it pending, or skip; never invent evidence or grant consent |
| Clarification usefulness | Remaining material alternatives after retrieval | Recommend a focused question, further permitted retrieval or a disclosed low-impact assumption |
| Provider/profile route | Finite operator-configured profile set | Suggest a change and ask before switching model provider or paid service; source-routing consent cannot authorize the switch |

Filter unavailable or unapproved routes **before** decision dispatch. A decision
cannot enable a disabled package, install an artifact, fetch an unapproved source
or select a new endpoint. Keep routing-engine identity separate from the chosen
answering/extraction provider. Retain request/response identity, rubric/version,
input snapshot references, policy revision, actual selected action, override
reason, usage, cache partitions, latency and cost status; diagnostics must not
dump private source text or credentials.

Provide explicit engine-free and decision-assisted modes. Failure of a configured
engine follows the selected consumer policy: pending capture, a predeclared fixed
local retrieval strategy, or stopping the dependent action. Show the failure;
never silently substitute another engine. One shared-source batch can assess
independent questions; dependent decisions are ordered and bounded. Do not add
mandatory inference on every prompt or a multi-agent debate by default.

No result cache is required initially. If introduced, bind it to project, engine
and resolved model, rubric, full source generations, input and permission scope;
revalidate consent and invalidate on deletion/change. Upstream prompt caching is
distinct and accounted without double-counting cached input as extra tokens.

## Ordered delivery packages

The scope/acceptance ledger in the [plan](../../plan.md) is authoritative. This
table explains dependencies and how to deliver useful increments without a large
up-front framework project. Every package starts unimplemented.

| Package | Output and dependency |
| --- | --- |
| P30A | Freeze neutral contracts, supported engine subsets, fixtures and consumer inputs; verify sources before adapter implementation |
| P30B | Engine profiles/adapters, owned host effect, validation, accounting and budgets; depends on A |
| P30C | Decision-to-policy mapping, observable refusal/uncertainty/failure and finite routing sets; depends on B and P31B consent |
| P30D | Actual retrieval and capture consumers, optional clarification assessment; depends on P30C and P31E/F, adding graph routes after P31G; not just a synthetic classifier demo |
| P30E | Per-consumer labeled qualification against a simple baseline, installed integration and separately recorded live eligibility; depends on D |
| P31A | Freeze user journeys, proposed CLI, source/retention/capacity envelope and acceptance corpus; design generic contract gaps before coding |
| P31B | Persistent consent, revocation, project reservations, mode ceilings and exact effect admission; depends on A; usable knowledge cannot ship without this |
| P31C | Stable evidence/identity, durable local storage, historical versions, suppression/export/migration and complete bounded capture sources; depends on A/B |
| P31D | Ship compatible disabled artifacts; guided setup/status/inspect/disable, catalog composition and safe activation/handoff/upgrades; can overlap B/C |
| P31E | First complete release-user journey: automatic project notes/decisions and recall, friendly corrections/forget, visible changes; depends on B/C/D |
| P31F | Selected-file/folder ingestion for text, PDF and Word, change tracking, indexing, cited retrieval and progress/recovery; depends on C/D and shares E's recall policy |
| P31G | Automatic typed relationship capture, aliases/conflicts/time-qualified retrieval and correction; depends on C/E and shared acquisition from F; conversation capture can develop before every parser is ready |
| P31H | Explicit research-to-knowledge transfer and shared lineage/invalidation; depends on E/F/G; P30D owns optional decision-consumer integration and does not gate the engine-free transfer path |
| P31I | Retrieve-first clarification, editable accepted prompt and enforced planning interaction; can run alongside E–H after A/B and the intent contract |
| P31J | Integrated adversarial, quality, resource, installed-user and documentation acceptance; depends on all selected P31 slices |

The first demonstration is enable → ordinary conversation → visible saved note →
fresh session recall → correct/forget. Deliver that before expanding every backend.
P30's basic operation can be developed alongside P31's host contracts; its product
completion waits for actual consumers. P31's automatic baseline does not depend
on P30 service availability. A decision-assisted strategy that fails qualification
remains experimental/off; its adapter may pass protocol tests without the strategy
being accepted for automatic use.

## Qualification and failure cases

P31A must freeze numerical workload sizes, supported data/model/latency envelopes
and error-cost thresholds **before** evaluating the candidate. No fabricated
benchmark result or inherited P27 score counts as this product's acceptance.
Use a small representative capacity target to compare storage options, then ratify
it from measured prototypes before promising scale in operator documentation.

### Starter workload for storage and interaction prototypes

These are proposed, **unmeasured** design targets, not current limits or release
claims. P31A must publish any revision and its reason before freezing qualification.
They provide something concrete to build and compare without selecting a database
or pretending that today's small State store meets the requirement.

| Area | Initial target to test |
| --- | --- |
| One project, simultaneous counts | 1,000 document/conversation sources; 20 MiB retained extracted evidence; 10,000 chunks; 5,000 entities; 20,000 attributed assertions |
| Storage | 256 MiB bounded knowledge store including indexes, retained versions and metadata; original binary inputs and journals have separate explicit quotas; embeddings are preflighted within the store cap |
| Per-source evidence | Up to 2 MiB extracted text through bounded pages; PDF/Word input/container/page limits determined by parser trials before admission |
| Local retrieval | p95 below 500 ms warm / 2 s cold on a documented four-core, 8-GiB-RAM local-SSD reference machine, excluding remote inference |
| Owned work | One capture and one acquisition/indexing worker per project with shared inference admission; at most 64 immutable queued references / 1 MiB queue metadata; foreground work takes priority |
| Endurance | 10,000 update/correct/forget cycles over a fixed active set of 100 sources, with two writers and retained slots/bytes bounded after collection |
| Quality corpus | At least 200 capture cases, 100 retrieval prompts and 100 entity/relation cases, plus separately labeled clarification and PDF/Word fidelity cases |
| Human journey | At least two independent fresh-account operators, covering Linux and macOS; aim for enable → capture → later-session recall within ten minutes after the executable/provider already works |

Report supported-attribution precision, missed important facts, false entity
merges, citation fidelity, temporal errors and clarification redundancy separately.
Freeze quality thresholds and the treatment of uncertain answers before candidate
evaluation; do not optimize the target against held-out results. Publish machine,
sample sizes, confidence limits where meaningful, disk/RSS and remote costs with
measurements. Local fixtures prove safety/protocol properties; they cannot prove
semantic model quality. No claim of universally correct extraction is acceptable.

### Required qualification cases

- Separate extraction false admissions/missed facts, alias/link accuracy,
  retrieval coverage, answer/citation support, temporal updates and abstention.
  Include user statements, quotations, hypotheticals, negation, assistant proposals,
  ambiguous entities, contradictory sources and revisions.
- Compare notes, lexical/document search, graph plus original evidence and
  explicitly selected semantic modes on matched models/context/budgets. Calibrate
  decision consumers separately; candidate classification success does not prove
  candidate generation. Report false-positive costs, abstention and drift, not
  only aggregate agreement.
- Test fully specified prompts that require no questions, missing facts already
  present in sources, material user choices and harmless defaults. Count avoided
  and unnecessary questions, rounds, completion, latency and spend. Include real
  humans; simulated users alone cannot establish low friction.
- Exercise consent across fresh/resumed/concurrent sessions, revocation during
  extraction, changed endpoints under unchanged profile names, lowered limits,
  exhausted project budget, denied/unknown effects, schema upgrades, malicious
  retrieved instructions and model attempts to widen routes.
- Exercise cancel/owner death at each publication boundary, partial ingestion,
  overflow, long-turn evidence gaps, duplicate capture, stale context, old-backup
  suppression and cross-project isolation. Include disable Graph → forget source
  → re-enable Graph; revalidate context before later same-turn model dispatches.
  Observe the actual main-model request
  and persisted state, not only callback return values.
- Exercise planning ceilings against native writes/shell, extension publication,
  MCP, children and resumed work; preserve allowed reads/questions/inference.
  Test prompt edit/cancel/stale acceptance/restart and interrupted intent changes.
- Exercise text-bearing PDF and `.docx` fidelity and parser resource limits, with
  inspectable original-file/page/paragraph citations. Include malformed/encrypted/
  image-only inputs, expanded containers, external links, embedded objects, tracked
  changes and comments; preserve explicit exclusions and partial extraction status.
- Build/install the whole supported package composition on Linux and macOS.
  Have fresh operators perform the journeys from release assets, recording time,
  approval interruptions, assistance, corrections and recovery. Require zero
  repeat approval prompts for covered automatic operations across sessions;
  changed authority must still be reviewed.
- Rewrite current manuals around the final user tasks and contributor contracts.
  Retain advanced build/protocol exercises in contributor material. Verify all
  real commands/examples/anchors and distinguish fixture, live-model, platform
  and human evidence. Commit/push each completed, verified increment.

Deferred scope: voice/media (P32), team/cloud synchronization, universal historical
chat mining, autonomous external-service installation, unattended daemons, arbitrary
workflow graphs, perfect semantic erasure, arbitrary model-provider switching and
universal extraction quality. PDF and Word ingestion are required P31 work within
the declared format boundary. Routing stays within enabled knowledge sources;
provider or paid-service changes require a new operator choice. Dependency additions
outside Elixir/Rust need the existing explicit approval process after selection.

## Design review and verification

Three read-only internal reviews covered source/architecture constraints, prompt
and authority semantics, and primary-source decision interfaces. Their findings
were integrated: explicit atomic revocation, per-dispatch context validity,
accepted-intent identity, incomplete-turn capture, planning-mode transitions,
disabled-store suppression, strict decision validation and independent P31/P30
delivery. This is design review, not runtime verification or independent product
acceptance.

The author reconciled the roadmap, README, documentation map and archive navigation
with current operator/contributor guidance. Current manuals retain their implemented
explicit-configuration procedures. The former P30/P31 bodies are preserved separately;
historical milestone numbering elsewhere is unchanged. Documentation link/manual
checks pass; no runtime, parser, storage, provider, performance or human checks were
run for this planning-only change. Implementation must perform the gates above.
