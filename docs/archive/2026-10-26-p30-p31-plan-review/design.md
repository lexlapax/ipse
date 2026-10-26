# Revised knowledge and decision delivery design

Design record, **2026-10-26**, replacing the [first design](../2026-10-26-p30-p31-plan/index.md)
after the [audit and developer choices](index.md). Source baseline: `eccf7c7`.
This is a proposal, not implemented behavior. The [current plan](../../plan.md)
alone owns status, package dependencies and acceptance disposition; this document
specifies contracts and user journeys. Current commands remain in the
[operator manual](../../operator/index.md). Planning authorizes no runtime work,
provider spending, dependency installation or publication.

## A usable first release

Start with project notes on the model the person already uses. After one explicit
enablement, useful eligible facts and decisions are saved through a normal model
tool call, shown in a compact changes receipt, and recalled in later sessions.
Corrections and forgetting are ordinary operations. A separate extraction model,
embedding service, graph server and decision engine are not prerequisites.

The first release checkpoint is a bounded notes preview after P31E, not completion
of the entire milestone. It can use existing State storage and bundled Memory
with a new source-bound record version. Proposed preview limits are 32 active
notes, 64 retained source identities including suppression, 512 KiB namespace
bytes and 6 KiB per note/evidence value. Reserve metadata space and verify the
envelope before publishing it. Existing State has a 1-MiB/256-key ceiling and
retains deleted-key revisions; this preview cannot promise indefinite turnover.
Show remaining capacity, refuse before exhaustion, export completely and provide
a forward migration path. Early delivery does not waive provenance, protected
consent, concurrent revocation, correction, forgetting or cancellation.

Ship this preview through the usual verified archive/release process, with an
upgrade rehearsal from v0.1.0. Select its version at release preparation; this
plan does not publish or reserve a version. Documents, scalable storage, automatic
relationships and optional decision consumers can arrive in later increments.
PDF and Word remain in P31's delivery scope. The developer permits qualified
completion if graph capture or PDF quality remains experimental/off by default;
the [release gates](#qualification-and-release-gates) define the limits.

## Enablement, commands and project identity

Enabling a feature saves its reviewed configuration and permission for the
**next new session**. Show: “Saved; active in your next new session. This
conversation keeps its current settings.” Do not restart, hand off or replace
the current conversation. Resuming it keeps its existing artifact pins; a new
session activates the selected packages. Setup/status show current and next-session
settings separately and supply the exact new-session command. No source build,
hash calculation, JSON editing or MCP configuration is required for local use.

Disabling/revoking and forgetting take effect at the policy boundary immediately;
they do not wait for activation or require the disabled worker to run. Removing
catalog entries can wait until the next new session. Existing handoff transfers
only a bounded operator note and unknown-effect references into a fresh session,
not native conversation history. Never call it lossless.

The following is **proposed vocabulary for P31A's naming trial**, not runnable
current syntax. Test discoverability with people unfamiliar with the internal
Memory/Corpus/Graph names before freezing aliases and flags.

| Task | Proposed interaction |
| --- | --- |
| Enable/select features | `/knowledge enable`, with notes/documents/relationships choices; equivalent `ipse knowledge setup` |
| Inspect activity and permission | `/knowledge status`, `/knowledge changes`, `/knowledge permissions` |
| Add documents and refresh | `/knowledge add PATH`, `/knowledge refresh` with inclusion/exclusion preview |
| Inspect/correct/forget | `/knowledge show ID`, `/knowledge correct ID`, `/knowledge forget ID`; natural-language tool equivalents |
| Stop use or manage parked work | `/knowledge disable`, `/knowledge work`, `/knowledge continue ID`, `/knowledge discard ID` |
| Exclude this conversation or run | `/knowledge pause` and `--no-knowledge`; explicit read-only mode also forbids publication |
| Enhance a request | `/enhance TEXT`, `/enhance show`, `/enhance replace TEXT`, `/enhance accept ID`, `/enhance cancel` |

For Git projects, setup recommends one knowledge identity for the repository and
its worktrees, showing that scope before saving consent. Use an opaque protected
project ID mapped to the verified canonical Git common directory; offer “only
this folder.” Non-Git projects use the chosen canonical root. Do not merge by
repository name or remote URL; separate clones need an explicit join. A move,
replaced common directory or old per-folder store requires a previewed mapping
or migration, preserving suppression and conflicts.

Shared notes/decisions do not share filesystem authority. File evidence and code
indexes retain worktree ID, relative path, content/commit version and branch
provenance. Current-code questions cannot silently answer from another worktree's
different file. Joining a new worktree does not authorize reading all its files.
Current State still hashes cwd; `state_binding` alone does not implement this
sharing. C0 must add the admitted project-identity binding and previewed per-folder
import while reusing the existing bounded store, not claim an existing sharing knob.

## Capture with the selected main model

The baseline exposes one compact source-bound capture tool to the current main
model only when knowledge is enabled. The model may propose a small useful batch
during normal task execution; there is no mandatory extraction call after each
turn. Use host-issued event/receipt IDs, source spans and evidence classes. Resolve
the actual source bytes and ownership in the host; caller-written provenance is
not proof. Validate the schema, citations, exclusions, suppression and consent,
then commit eligible records and show saved/updated/skipped/conflicted counts.
No per-fact approval within the saved scope and no invisible repair-model loop.

Every existing main adapter sends tool declarations: ChatGPT subscription, OpenAI
API, Ollama, Anthropic, Gemini, OpenRouter, Grok and compatible local servers.
Baseline capture must integrate with those tool protocols and qualify representative
tool-capable models. Protocol fixtures are required for all routes; live and quality
coverage is recorded per selected model. Grok account/OAuth eligibility remains
separately qualified. An unsupported model gets a clear limitation and explicit
note management, never a silent provider switch. Demo uses deterministic fixtures.

A tool call can add an ordinary continuation, tokens and latency. Same-turn capture
is not free and does not capture novel claims written only in a later final answer.
That is deliberate: unconfirmed assistant prose is not an automatic durable fact.
A user later accepting a conclusion makes the confirming statement eligible.
Bind a short confirmation such as “yes” to both its user event and the exact
proposal/version accepted; the confirmation alone is not evidence for the claim.
Edited or unrelated proposals cannot inherit that acceptance.
If execution fails or is cancelled after a note was committed, retain its receipt;
stop undispatched capture and show any unknown effects without replay.

Separate extraction is an opt-in strategy for selected bulk documents/graph work,
not the baseline prerequisite. Today native schema-bound extension output works
only with Ollama. Other routes have a strict text/JSON-and-exact-quote path that
can reject malformed output; it is not native schema enforcement. Compare that
path against tool-based generation before adding provider-specific structured
output. Prioritize adapter additions only where the chosen workload needs them.
Subscription auth does not by itself establish auxiliary-operation eligibility;
verify the exact public route/account terms and show unavailable if unqualified.
Optional helper profile, destination, input scope, billing and limits are explicit.

### Intake and poisoning resistance

Default automatic capture includes direct user assertions, corrections and accepted
decisions, plus narrowly typed host-verified outcome facts. A successful shell exit
proves execution status, not arbitrary stdout. A pasted quotation remains third-party
material even inside a user message. Web/MCP/file prose and assistant proposals
require separately selected ingestion as attributed reference evidence; they do
not automatically become user preferences or confirmed facts.

Apply one exclusion policy before durable copying or additional model egress on
every intake path: chat, tools, files, web/MCP, helpers and queued candidates.
Exclude known credential formats and configured sensitive patterns/paths; retain
minimal admitted excerpts rather than raw transcripts or environment dumps. Bind
citations to the admitted/redacted evidence version, with an explicit redaction
marker; do not retain a hidden unredacted copy in the knowledge store. Detection
is fallible. It cannot undo a secret already sent in the original conversation or
erase its original journal; disclose that boundary and provide no-save controls.

Recall is reference data, never permission or executable instruction. Source IDs
must prevent a model from relabeling an injected page as a user decision. Test
“always approve shell,” quoted instructions, false successful-tool wrappers,
echoed poisoned memories and chat-pasted credentials. An ambiguous candidate may
be skipped visibly; routine harmless capture must not become a questionnaire.

## Recall without another service

P27's lexical Corpus was rejected for its frozen reference workload: supported
answers passed, citation support did not. That result neither qualifies the new
baseline nor proves every lexical/notes workflow unusable. Existing Memory uses
token overlap, not Corpus BM25. Existing embeddings support OpenAI API and Ollama;
ChatGPT subscription does not provide them. Never silently attach paid OpenAI
embeddings to a subscription account.

For the small notes preview, include complete eligible note text up to an 8-KiB
shared-context allocation, paged within host contribution limits, with evidence
IDs. If it does not all fit, expose a complete bounded metadata index and explicit
partial text coverage, then let the current main model read by ID or search.
Bound metadata fields/IDs/framing within the same allocation, packing each
contribution within the host's per-item limit; if the index also exceeds it, page
the index through explicit read tools and report which pages remain unread.
Never silently truncate a note and claim full coverage. Complete byte inclusion
does not prove that the model attends to every note.

For documents and larger stores, freeze a deterministic baseline: query each
enabled eligible store under shared limits, deduplicate by evidence version,
and fuse ranked results using RRF with k=60, fixed tie order and per-store caps.
Exact source/ID constraints bypass broad ranking. Graph is queried only if enabled
and qualified for the selected domain. The main model can reformulate a search
or read a source through ordinary tools, within bounded steps; no separate
query-rewriter is required. Fusion alone cannot recover zero-match synonyms.

Compare plain lexical, main-model-assisted search and explicit opt-in hybrid on
fresh matched source/model/context/spend envelopes. Include synonym-only questions,
must-remember decisions, contradictions, missing evidence and citation selection.
Initial proposed bars are at least 90% supported answers, 95% supported citation
pairs and 95% recall of designated critical decisions; freeze data/rules before
evaluation. Measure candidate recall separately from final answers. Preview
success does not qualify large-document retrieval. Failing automatic recall
remains unqualified; fix it or keep that product slice open. The graph/PDF
experimental allowance is not a waiver for the core notes/recall journey.

P31F includes a retrieval-improvement increment if the baseline misses these bars:
repair source selection/citations, evaluate main-model query expansion, and assess
additional Gemini or compatible embedding routes or an optional local embedding
asset. Select only after API, dependency/model license, resource, privacy and
packaging review. No new mandatory service or silently downloaded model follows
from a benchmark failure. If no no-extra-service strategy qualifies, present the
evidence and seek an explicit scope decision; do not advertise it as solved.

Automatic seed recall executes once per accepted turn; subsequent read/search
tools remain available. Before every actual model dispatch,
revalidate selected evidence against source, expiry and consent generations,
including later tool/question continuations. Clear stale contributions after
forget/change/failure; required-source failure stops dependent answering, optional
failure is visible. Do not treat an old context replacement as a valid new recall.

## Permission, headless operation and coordination

Enabling knowledge creates protected operator consent, separate from project
configuration and executable artifact trust. Bind project/worktree scope, source
categories, exclusions, effect classes, storage/sharing, retention, concrete
provider/profile/model/endpoint/billing, data handling and finite limits/reset
periods. Cover both outer extension tools and inner host effects. Compatible
reviewed artifact upgrades can retain unchanged semantic consent; an arbitrary
same-name package cannot inherit executable trust.

The developer selected reuse of this saved knowledge permission in **both chat
and headless `run`, without `--yes` or a per-run knowledge flag**. Knowledge is
off until explicitly enabled. This is a deliberate new narrow exception to
today's blanket headless-deny behavior and requires admission code plus matching
AGENTS/manual changes at implementation. Separate default headless denial from an
explicit user deny/read-only/planning ceiling: explicit restrictions still win.
Shell, workspace edits, arbitrary MCP, delegation and unselected helpers remain
denied without their own authority. Broad `--yes` neither enables knowledge nor
widens its data scope. Headless missing/revoked permission yields visible skipped
capture and cannot prompt or grant itself permission.

Use a protected per-project control directory under IPSE_HOME and retained native
OS locks, following State/BudgetStore patterns. Maintain a bounded durable policy,
suppression and reservation ledger; use a fixed lock order. Independent VMs must
not rely on ETS or a GenServer alone. The short control lock serializes admission,
revocation and local publication/root-switch authority; do not hold it across
model requests, parsing or other long IO. Exact journal/store commit ordering
and partial-write recovery are required before release.

Reserve resources and capture source/policy generations at admission. Recheck
them under the publication lock. Revocation acknowledgment follows its durable
revision and excludes later admissions/publications; it reports already admitted
in-flight effects, which cancellation may not recall. Do not promise that a
remote request already admitted can never send a byte after acknowledgment.
Unknown remote liability stays reserved. Project period budgets survive exit,
fresh sessions and concurrent processes. Unknown prices are not zero cost.

The main-tool notes path needs no background queue on every turn. Optional
extraction and ingestion use bounded on-disk work references plus separately
retained worker-slot OS locks, owned by active Sessions until resources stop.
An item binds immutable source/version, owner/job/operation IDs, route, permission
revision, resource reservation and state. Keep states unstarted, admitted,
settled, parked/cancelled and unknown distinct. No daemon or detached scheduler.

On close/owner death, stop workers. Known unstarted items can remain parked for
up to seven days, visibly offered at next startup for explicit continue/discard
within existing consent. Nothing runs while Ipse is closed. Revalidate expiry,
forgetting, source versions and policy before continuation. Unknown dispatched
effects are never automatically retried. Bound queue count, bytes and age; show
overflow/coalescing. Default proposals: one capture and one ingestion worker per
project, at most 64 queued references/1 MiB metadata, shared inference admission
and foreground priority. Closing a session must not leave a worker running.

## Evidence, retention, forgetting and migration

Retain short evidence excerpts only for admitted items, not every turn as a new
source document. Identity includes original session/event/role and exact admitted
span, or file/worktree/version/page/paragraph. Deduplicate unchanged evidence.
Store assertions, decisions, preferences and derived indexes separately in
meaning, with stable logical IDs, provenance, confidence where justified, observed
time, stated event time, correction and derivation links. A quotation proves
supporting bytes, not truth. Recall does not create corroboration or renew TTL.

Proposed default retention, disclosed in setup and frozen in P31A: automatic
conversation facts expire after 90 days unless explicitly pinned; pinning retains
until deletion under the same quota. Superseded history has a 30-day retention;
uncommitted candidates/parked unstarted work expire after seven days. Show upcoming
expiry and allow a single policy adjustment. Keep evidence at least as long as
current dependents; expired/missing support invalidates them. Pinned decisions
cannot be silently evicted to admit newer observations. At 80% capacity show a
notice; collect eligible expiry, then pause new capture visibly at the cap.

Keep journal, original binaries, extracted evidence, indexes, revisions and backups
separate in status/quotas. Minimal suppression identity may outlive normal evidence;
bound it with version floors/compaction that reject incompatible old imports.
Do not simply delete tombstones and permit resurrection. Test a year of new-source
turnover, pins, expiry, offline gaps and imports as well as repeated updates to
one fixed set. The proposed larger prototype remains 1,000 active sources/20 MiB
extracted evidence/10,000 chunks/5,000 entities/20,000 assertions within 256 MiB
for the knowledge store, not an all-history promise. Ratify from measurements.

Forgetting suppresses managed lineage and declared aliases across notes, graph,
chunks, vectors and context. Disabled stores revalidate before re-enable/import.
Queued or stale writers cannot resurrect it. Do not promise detection of every
independently restated paraphrase. Already sent conversation text/native provider
continuation cannot be withdrawn: users may keep the current conversation with
that limitation or explicitly start fresh with a reviewed bounded note. Starting
fresh loses full native history; neither option erases the original journal.

P31C0 supplies source-bound records on existing State for the preview. P31C1
evaluates maintained Elixir/OTP storage before selecting a scalable local adapter;
there is no requirement to invent a new database. Domain storage/query policy stays
in extensions, host admission and lifecycle remain mandatory. P26/P27 and preview
migration needs capacity preflight, complete export, writer fencing, checkpoints,
validation, atomic root switch and rollback that cannot restore forgotten facts.
Historical questions need retained versions; current `as_of_ms` cannot reconstruct
replaced generations. Show retention gaps and unknown dates honestly.

## Documents, graph and research

P31 includes text/code/Markdown, text-bearing PDF and Word `.docx`. Unsupported
legacy `.doc`, scanned/OCR, encrypted inputs and embedded objects get explicit
per-file outcomes. Preview inclusion/exclusion and format before bounded source
acquisition. Track changed, renamed and deleted files; partial extraction never
means the whole file was indexed. A URI is not fetch authority.

Evaluate maintained Elixir/Erlang facilities first, including OTP ZIP/XML for
DOCX, with independent expansion/entity safeguards. The developer approved a
narrow Rust PDF-parser exception when maintained Elixir/Erlang options are
unsuitable. Keep orchestration and knowledge behavior in Elixir/OTP; evaluate the
specific parser's maintenance, license, process/resource boundaries and platforms.
This does not approve a particular crate, transitive C library or external utility.
Non-Elixir/Rust dependencies still require concrete approval and inventory.

Bound binary/expanded bytes, ZIP entries, pages, text, CPU/time and memory. Do not
execute macros or fetch external relationships. Cite original hash plus extraction
version and PDF page or DOCX paragraph/table-cell locator. Test columns, tables,
Unicode, headings, notes, comments and tracked revisions with a visible selected
revision policy. Test malformed/encrypted/image-only documents and partial results.
Installed users must not assemble the parser toolchain.

Graph capture uses the same evidence/admission boundary with typed relationships,
polarity, uncertainty, exact support and reversible entity aliases/merges. Do not
merge identities solely by matching names. Conversations can use the main-model
tool path; optional bulk extraction follows its own profile/cost contract. Qualify
unsupported relations, false merges, negation, conflicts and temporal updates
separately from graph traversal or note capture. Source evidence remains inspectable.

Research transfers selected evidence through an explicit host-admitted contract
or shared pure package implementation, not nested effectful extension calls or
shell recursion. Preserve shared suppression/derivation across stores. Stored
external evidence remains attributed data even after an explicit transfer.

## Clarification, editing and planning

Use native questions so answers reach the actual executing model. Check admitted
workspace/current-turn information first; after P31E include project notes, and
after F include selected documents. P31I's terminal/intent work may develop in
parallel, but integrated retrieve-first acceptance depends on those retrieval
paths. Bound question rounds, avoid re-asking answered questions and distinguish
material choices from low-impact assumptions. Headless required unknowns yield
an actionable incomplete result. Question answers do not grant action permission.

`/enhance` uses the current main provider/model/billing route for an explicitly
invoked, bounded draft-only request. Show route and budget; no workspace effects
or automatic capture of drafts. An optional helper profile requires its own
selection, not inherited knowledge consent. Unsupported auxiliary subscription
use is unavailable rather than silently converted to API billing.

The line-oriented minimum is show/replace/accept/cancel, including a bounded
multiline replacement mode. It requires no editor dependency. An optional editor
round-trip uses a configured executable/argv, private bounded UTF-8 draft and an
input-loop suspension handshake; do not shell-evaluate `$EDITOR`. Handle abnormal
exit and cancellation, review changes and clean up. Never assume `IO.gets` can
prefill/edit a live buffer. Bind original/proposed/accepted text, evidence/question
IDs and draft revision to a host intent record; pending can become accepted or
cancelled, only accepted can become consumed once. Stale acceptance refuses.

Planning allows known local reads, questions and authorized inference but forbids
workspace and knowledge publication. Current MCP calls all count as mutating.
Add an operator-owned **per-tool** planning-read declaration bound to exact server,
endpoint/command, tool identity and descriptor/schema hash; server annotations
cannot self-authorize. Changed bindings invalidate it. Egress/cost permission
still applies. Undeclared MCP remains unavailable in planning; a search-like name
does not establish read-only behavior. No server-wide bypass.

Accepted user decisions made while planning remain journaled as deferred candidates,
not published knowledge. An explicit “save these plan decisions” transition may
publish them after leaving the ceiling and revalidating current sources/permission;
ordinary exit from planning does not auto-flush them. Cancelled/unaccepted suggestions
are not decisions. Entering planning stops prohibited dispatch and accounts for
already in-flight effects before acknowledgment. Exiting cannot authorize stale
queued effects. Plan artifacts/journals/accounting are host records, not arbitrary
file export. Apply ceilings to tools, extensions, MCP, children and resume.

## P30 interfaces and useful consumers

The developer confirms **TypeSafe Jev**, not the unrelated `zev-rs` project.
Target OpenAI Decisions, hosted TypeSafe System One and a separately configured
loopback SystemOne-compatible endpoint. No local engine is selected or installed,
and protocol compatibility does not mean Jev is publicly self-hostable. Loopback
does not prove the server itself makes no external requests. Bind actual engine
identity separately from advertised model aliases; test exact supported subsets.

The [OpenAI guide](https://developers.openai.com/api/docs/guides/decisions) and
[API reference](https://developers.openai.com/api/reference/resources/decisions/methods/create)
describe `POST /v1/decisions`, currently `gpt-6-luna`, up to 400 questions and a
1,024-token shared-prefix cache threshold. As checked on 2026-10-26, uncached input
is $0.10/M tokens and output is uncharged; cache rates follow the model schedule,
with regional/long-context adjustments. These are decision-operation rates, not
ordinary chat/extraction prices. Reverify before release.

[TypeSafe System One](https://docs.typesafe.ai/api/system-one) uses `state` and named
questions/answers. Initial support is Noul/Choice/Score; experimental Box is
excluded. Pin [resolved model identities](https://docs.typesafe.ai/models) and
rubrics for qualification. Preserve native distributions/raw confidence separately
from calibrated consumer uncertainty. No engine substitution or lossy input coercion.

The neutral contract uses bounded evidence, stable question IDs and string choice
IDs; validate exact counts/types, option coverage, probability range/sums, fractional
score range and rubric consistency. Structural corruption invalidates the result.
Valid per-question refusal is not corruption: independently usable answers can
remain, while dependent actions need all prerequisites. Classifiers never invent
evidence, establish truth or grant consent.

The first mandatory P30 consumers are **notes-retrieval selection and note-candidate
assessment** after P31E, compared with complete-note/deterministic recall and
host-validated main-tool capture. Documents and graph add separately qualified
routes after F/G; they do not block P30 closure. Filter alternatives by enabled
sources, eligibility and limits before sending the decision. A deterministic
policy maps valid output into an ordinary journaled effect, with fresh authority,
source-version and budget checks. Permission/reservation/journaling also precede
the decision request itself. Never switch providers or paid services without
a new explicit choice. Uncertainty/failure follows a selected visible stop,
defer or fixed-local-baseline policy, never an undisclosed model fallback.

### What decision consent must display

Show operation, concrete endpoint, resolved model, input categories, processing
and storage region, cache mode/retention and verified account controls. The
[OpenAI data-control documentation](https://developers.openai.com/api/docs/guides/your-data)
distinguishes regional storage from processing and account eligibility; Decisions
supports regional processing in the US and Europe. Regional storage elsewhere or
a global endpoint does not establish inference locality; caching limitations also
apply. Unknown account
ZDR/residency properties stay unknown. An endpoint is not proof of an account's
contract. Keep local knowledge retention separate from provider retention.

Show dated rate source, input/cache partitions, adjustments, estimated per-call
ceiling and shared project-period cap. Destination/retention expansion or increases
beyond approved limits require review; ordinary use inside approved limits does
not. Unknown prices require explicit finite resource/call bounds, not a zero-dollar
claim. Keep immutable operation/model/rubric/source/policy identity, usage, latency
and selected action without diagnostic text dumps or double-counted cached tokens.

## Qualification and release gates

All numbers below are design targets to freeze before evaluating held-out cases,
not measured capabilities. Use fresh independently authored corpora; retain failed
results and compare matched models, contexts and budgets. A graph traversal score
does not qualify graph extraction; protocol fixtures do not qualify live models.

| Area | Proposed target or required evidence |
| --- | --- |
| Preview recall | 100 prompts across independent <=32-note sets; fixtures fitting the 8-KiB inclusion budget have 100% eligible-byte coverage; larger sets separately qualify the metadata/read path; semantic quality has separate answer/citation/critical-decision bars above |
| Larger quality | At least 200 capture cases, 100 document prompts and 100 entity/relation cases; separate negatives, temporal contradictions, absent evidence and PDF/DOCX fidelity |
| Capture work | At most one ordinary batch per turn, <=8 items/8 KiB proposal; zero mandatory extractor calls on turns with no candidates; no hidden repair loop |
| Capture overhead | Local admission/publication p95 <250 ms on reference hardware; target median <=10% additional billed tokens on matched mixed-turn sessions and <=1 capture-only continuation per turn; report end-to-end p50/p95 latency by model |
| Optional extraction | Default <=1 request per eligible batch, finite input/output bounds and 30 s deadline; target p95 save lag <=15 s on the qualified reference profile, with foreground priority |
| Cost setup | No silently chosen paid daily allowance; helper calls remain disabled until an operator chooses a finite cap. Main capture shares the selected main route; unknown/subscription prices show call/token bounds and measured usage |
| Local retrieval | Target p95 <500 ms warm / <2 s cold on documented four-core/8-GiB/local-SSD hardware, excluding remote inference |
| Endurance | C1: 10,000 update/correct/forget cycles with two processes plus a simulated year of distinct-source turnover/retention/pins/imports; bounded sustainable use. C0 preview: known slot exhaustion causes visible safe refusal, export and migration, not a false year-long capacity claim |
| Platforms | Full source/native/demo/package/installed checks for changed runtime paths on Linux and macOS; parser/model/account/human scopes recorded separately |

Use deterministic tests for forged sources, secrets on every intake, hostile
instructions, cross-worktree version confusion, headless knowledge save with denied
shell, concurrent budget/revocation races, every queue/owner-exit state, disabled
store forgetting, stale context before later same-turn dispatch, migration rollback,
planning MCP impostors and stale prompt acceptance. Observe actual model requests,
receipts and persisted state, not only callback results. Unknown effects never replay.

Recruit usability participants at P31A. Require at least one independent fresh-user
notes journey for the preview: enable/new-session activation, capture/later recall,
correction/forget, limits, headless scope and disable. Final P31 acceptance adds
documents, graph status and the complete upgrade/migration journey; preview release
still rehearses installation/upgrade automatically. Record assistance, elapsed time and actual approval
counts. Seek macOS human coverage early. If unavailable, retain automated macOS
evidence and an explicit open human-coverage item; release requires a recorded
qualified-acceptance decision rather than an indefinite hidden dependency or a
claim that human macOS use passed. Publication remains separately authorized.

The developer permits final P31 **qualified completion** with graph capture or PDF
extraction experimental/off by default if their semantic/fidelity bars fail.
Publish exact failed scope/model/data, known limitations and a tracked improvement
item. Do not mark those quality gates passed. A useful qualified subset may be
supported while harder layouts/domains remain experimental. Missing useful PDF
coverage must be stated explicitly, not relabeled full PDF support. Word and the
core notes/recall/permission journeys retain their own acceptance gates.

Experimental status never waives parser resource bounds, source integrity,
secret/authority controls, correction/forgetting or cancellation. Unsafe features
do not ship. Final acceptance records enumerate supported, experimental and
unverified slices; qualified milestone status is distinct from unqualified success.
Rewrite current manuals around real shipped tasks at each release, keep advanced
contracts in contributor training and preserve fixtures/live/human evidence.
