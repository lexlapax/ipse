# Knowledge and decision delivery design

Current **proposal**, revised **2026-10-26** against source baseline `a812369`,
with the [local Ollama research amendment](archive/2026-10-26-ollama-local-rag/index.md)
added after `bd556fa` at the developer's request.
The [plan](plan.md) owns status, package dependencies and acceptance disposition;
this document owns the proposed contracts and user journeys. The
[final repair record](archive/2026-10-26-p30-p31-final-handoff/index.md) explains
the repairs and preserves earlier designs. The
[implementation handoff](archive/2026-10-26-p30-p31-final-handoff/implementation.md)
defines the P31A starting work and checks. Settled developer choices remain in
the [first audit record](archive/2026-10-26-p30-p31-plan-review/index.md#decisions-after-the-audit).
Current implemented commands remain in the [operator manual](operator/index.md).
Planning authorizes no runtime work, provider spending, dependency installation
or publication. Numerical targets below are unmeasured acceptance proposals.

At the first authorized implementation commit, archive this complete final proposal
unchanged as the dated implementation baseline, rebase links mechanically, and
replace this live-proposal page with a short pointer. Link that baseline from the
plan and contributor training; update current manuals only as behavior is implemented.
Keep subsequent design decisions in dated records and status in the plan. Do not
leave a second, drifting live specification beside the implementation.

## A usable first release

Start with project notes on the model the person already uses. After one explicit
enablement, useful eligible facts and decisions are saved through a normal model
tool call, shown in a compact changes receipt, and recalled in later sessions.
Corrections and forgetting are ordinary operations. A separate extraction model,
embedding service, graph server and decision engine are not prerequisites.

The first release checkpoint is a usable notes release after P31E, not completion
of the entire milestone. It requires P31C1a's sustainable notes storage first.
Existing State has a 1-MiB/256-key ceiling and retains deleted-key revisions;
P31C0 may use it for internal interaction/evidence prototypes only. A 64-identity
store that permanently fills after a few sessions is not a public preview.
Evaluate maintained Elixir/OTP storage and a bounded State evolution before
choosing an adapter; do not build a second temporary database merely to ship
sooner. The first released store must reclaim eligible space safely, preserve
suppression and pass the multi-day and turnover workloads below on its own.
Future migration is not its recovery from ordinary use.

Ship this notes release through the usual verified archive/release process, with an
upgrade rehearsal from v0.1.0. Select its version at release preparation; this
plan does not publish or reserve a version. Documents, larger indexes, automatic
relationships and optional decision consumers can arrive in later increments.
The earlier delivery goal remains, but minimum sustainable storage moves ahead
of it. Early delivery does not waive provenance, consent, concurrent revocation,
correction, forgetting or cancellation.
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

The first-use journey starts in the project with the proposed standalone
`ipse knowledge setup`, followed by `ipse chat`. Setup explains scope, retention,
source eligibility and limits before that first knowledge-enabled conversation.
The in-chat enable command serves existing conversations; test it separately
with next-new-session activation. Resuming the old conversation is not activation.

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
| Accept a proposed decision | Explicit `accept CODE` shown by the decision card; no bare-yes acceptance in the first release |
| Review pending items without chat | `ipse knowledge review` opens a bounded interactive review; read-only list/JSON mode supports unattended inspection |
| Change an assigned retention category | One receipt action or `ipse knowledge retention ID --policy automatic --days 90`; proposed syntax, frozen in A |
| Stop use or manage parked work | `/knowledge disable`, `/knowledge work`, `/knowledge continue ID`, `/knowledge discard ID` |
| Exclude this conversation or run | `/knowledge pause` and `--no-knowledge`; explicit read-only mode also forbids publication |
| Enhance a request | `/enhance TEXT`, `/enhance show`, `/enhance replace TEXT`, `/enhance accept ID`, `/enhance cancel` |

For Git projects, setup recommends one knowledge identity for the repository and
its worktrees, showing that scope before saving consent; offer “only this folder.”
Store an opaque project ID with the explicitly admitted canonical primary root
and Git common directory in protected operator state. A newly encountered folder's
`.git`/`commondir` files are candidate metadata, never authority to receive notes.

A primary root must match the admitted root. A linked worktree can join the chosen
scope automatically only through reciprocal registration: its bounded regular
`.git` file resolves to an admin entry under the already admitted common directory's
`worktrees/`; that entry's `commondir` resolves back to the admitted common directory;
and its `gitdir` backlink identifies this exact canonical worktree's `.git` file.
Check ownership, safe paths and metadata identity, reject symlink substitution,
and fence metadata changes while admitting the binding. Revalidate at new-session
admission and before a changed binding supplies any recall, not just before writes.
Use a reviewed bounded metadata adapter; do not execute repository hooks or commands
from workspace configuration to establish trust. Unsupported layouts fail to an
explicit join, with no inherited recall before that choice.

Non-Git projects use the chosen canonical root. Never join by repository name,
remote URL, caller-supplied project ID or outward `.git` pointers alone. Separate
clones, moves, replaced common directories and old per-folder stores need an
explicit previewed join/migration preserving suppression and conflicts. A crafted
archive pointing at another project's metadata must receive no shared notes.
This protects against untrusted workspace contents, not arbitrary code already
able to alter protected operator state or the admitted repository's metadata.

Shared notes/decisions do not share filesystem authority. File evidence and code
indexes retain worktree ID, relative path, content/commit version and branch
provenance. Current-code questions cannot silently answer from another worktree's
different file. Joining a new worktree does not authorize reading all its files.
Current State still hashes cwd; `state_binding` alone does not implement this
sharing. C0 prototypes the admitted project-identity contract; C1a must implement
and qualify it with safe per-folder import before the notes release.

## Capture with the selected main model

The baseline exposes one compact source-bound capture tool to the current main
model only when knowledge is enabled. The model may propose a small useful batch
during normal task execution; there is no mandatory extraction call after each
turn. The model supplies host-issued source occurrence/version IDs, a bounded exact
supporting quote and, when needed, a host-issued chunk ID. The host matches the
quote uniquely against the immutable admitted/redacted source and computes UTF-8
byte spans. Missing or ambiguous matches need more context/narrower chunks or a
visible rejection; never choose the first match, normalize punctuation/Unicode
or ask a model to calculate byte offsets. Resolve ownership/evidence class in the
host; caller-written provenance is not proof. Validate exclusions and consent,
then commit eligible records and show saved/updated/skipped/conflicted counts.
No per-fact approval within the saved scope and no invisible repair-model loop.

C0 must specify, and E must integrate, a host-issued source index for each turn:
occurrence/version ID, origin class and an admitted excerpt/read handle for eligible
user events, native answers, proposals and typed tool receipts. Current provider
messages do not expose this index. Put only a bounded handle, count and coverage
summary in the turn-local reference envelope defined below. The full index is a
host-owned paged read tool, not a context contribution containing every receipt.
Pages carry opaque source IDs, origin and version with explicit next-page/coverage
status. Missing a context page does not make its admitted receipt uncapturable.

The index and evidence reads resolve only authorized occurrences in the current
Session or explicitly selected knowledge, never arbitrary journal paths or another
session's transcript. Revalidate generation, mode and scope at each read. Keep native
messages/authors unchanged and expose no hidden reasoning. Mark partial/unavailable
sources; do not regenerate missing bytes with a model. Count index/read operations
in context, step and overhead budgets. Typed receipt fields attest only their
host-verifiable meaning; arbitrary output quotes do not.

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
A user later accepting a conclusion can make it eligible through the visible
proposal contract below; the confirming word alone is not evidence for the claim.
Capture calls and results also enter native history and the journal. Keep results
compact (target <=1 KiB, hard bound 2 KiB): IDs, status and counts, with detailed
evidence available by read. Count later replay and compaction overhead, not only
the immediate tool tokens. Do not delete native tool pairs or unknown-effect
records to meet a size target; use validated compaction and no-replay recovery.
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

### Confirming a proposed decision

Reuse native question IDs and exact selected answers when a material choice already
uses that UI; do not ask again just to save it. For an ordinary assistant suggestion,
the capture interaction has a pending-proposal operation. New recommendations can
start as assistant-authored, unverified claim text without prior supporting facts.
Validate shape, exclusions and any supplied references, without inventing evidence
or requiring a previous decision. The host assigns an immutable ID/version/text
hash, journals it, and displays that exact text as a concise decision card after
the completed reply.
The UI identifies its current decision focus. A model assertion that text was shown
is not a render acknowledgment. Pending proposals are neither confirmed facts nor
active recall; creating one does not grant any effect permission.

The first release accepts cards only through an explicit displayed `accept CODE`
interaction, bound to that exact proposal/version; the code is a host-issued,
project/client-bound capability to select a decision, not permission for an effect.
Chat codes also bind their Session; standalone review has its own host-issued
review-client identity and does not create a conversation just to obtain one.
Persist ID/version/hash, render revision and the actual interactive acceptance event.
Reject stale, reused-for-another-version, cross-session and unknown codes. A bare
“yes”, even with one card visible, never confirms it: the assistant may have asked
a competing question in prose that the host cannot reliably distinguish. Native
question selections retain their existing explicit identity. Restating a choice
in full can still supply a new direct assertion; do not retroactively assign it
to an unseen card. Accepted proposals establish the user's decision, not objective
truth of the assistant's premises, and grant no workspace/service permissions.

Edit, supersession, interruption and expiry invalidate outstanding acceptance codes.
Resume must re-display the still-pending proposal with a fresh code; duplicate receipt
delivery cannot publish twice. Source quotes, tool/child text and headless input cannot
accept a card. P31A's trial measures intended versus inferred targets for bare
affirmatives, including prose questions and multiple pending decisions, in observation
mode only. Any later enabling of bare-yes acceptance needs a separate reviewed change
with frozen false-acceptance criteria; it is not necessary for P31 completion.
A pending batch has at most eight items/8 KiB;
keep at most 64 pending proposal/review items and 256 KiB per project for seven days,
then visibly expire or refuse new items. Never promote on expiry or silently evict
a pending decision to make room. Direct assertions and verified outcomes still save
under consent without this proposal interaction or a per-fact approval.

The proposed standalone `ipse knowledge review` displays pending candidates with
their exact text, source class, provenance and proposed retention. It uses a real
controlling terminal for both display and response, with freshly rendered acceptance
codes; an `interactive` command flag or piped `IO.gets` input alone is insufficient.
This is an operator-interface boundary, not proof against same-user PTY automation.
Argv/stdin content, `--yes`, copied codes and generated text cannot supply human attestation.
Without that channel it can list/export bounded metadata as JSON but cannot promote
items. Offer reject/correct/defer and explicit selection of at most eight fully
displayed items/8 KiB per batch with an immutable manifest hash; never an unseen
“accept all.” Recheck source versions,
exclusions and current consent before publication. This supports operators who run
tasks headlessly but perform occasional human review outside chat; wholly unattended
promotion remains out of the first release. No model request is needed to review.
Human review adds an acceptance event linked to the original source and candidate
version; it never rewrites `run_input` provenance as an interactive original assertion.
Listing, rejecting, forgetting and reducing retention remain available while knowledge
is paused, disabled or revoked. Accepting/publishing requires currently active valid
publication consent; a retained but disabled grant is insufficient. Review cannot
silently re-enable knowledge or widen scope. Listing alone does not renew a candidate's
expiry, start a worker or incur inference.

### Intake and poisoning resistance

Default automatic capture includes direct interactive user assertions, corrections
and accepted decisions, plus narrowly typed host-verified outcome facts. A successful shell exit
proves execution status, not arbitrary stdout. A pasted quotation remains third-party
material even inside a user message. Web/MCP/file prose and unaccepted assistant proposals
require separately selected ingestion as attributed reference evidence; they do
not automatically become user preferences or confirmed facts.

The host records input origin independently of provider `role: user`: interactive
operator input, native operator answer and unattended `run_input` are distinct.
All human-attestation paths, including ordinary chat assertions, card acceptance
and native answers reused for capture, require the verified operator channel above.
The terminal implementation must establish the display/input channel rather than
trust `interactive: true`, `TERM` or the command name. Redirected/piped `ipse chat`
input is unattended data unless a separately verified controlling terminal supplies
the actual operator event. Legacy records lacking origin proof remain unverified
for new automatic attestation; stored role labels cannot upgrade them.
Scripts can construct argv/stdin from issues, emails or logs. Their prose is task
input, not a human attestation. Default headless preference/decision candidates
remain bounded pending review and are excluded from active recall. A later human
can accept one exact candidate version. Apply exclusions even before pending storage.

Saved headless consent still automatically admits eligible typed host-verified
outcomes, and can admit selected source content as attributed reference evidence
when that category was included in setup. It never turns embedded directives into
preferences or permission. Show saved/pending/skipped counts in human output and
machine-readable results; surface pending counts at the next interactive startup.
A human-typed `run "remember X"` cannot be distinguished from generated argv: it
uses this same conservative classification. A future protected structured-producer
contract may add attested automation, but it is not required for P31. Text that says
`origin=interactive`, a copied receipt or a child response cannot confer that status.

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

For notes that fit, include complete eligible note text within the granted recall
allocation below, with evidence IDs. When it does not fit, include a compact
selection/coverage summary and provide paged metadata, read-by-ID and search tools.
Do not insert the whole note index into context or assume all eight KiB is always
available. Each page states remaining coverage; never silently truncate a note and
claim full inclusion. Complete byte inclusion does not prove model attention.

### Turn-local context and cache preservation

Today's `Session.Context.header/1` renders extension context before all conversation
history. Using it for changing seed recall/source indexes would invalidate a reusable
prefix. P31 therefore needs a reviewed host context-placement contract, frozen in A
and implemented through C0/E. Keep the admitted header and ordered tool declarations
stable within a context epoch. Never add per-turn timestamps, IDs, recall or source
indexes to that prefix. An explicit refresh, real catalog/model change, revocation
or compaction can establish a new epoch; record its reason and measure it separately.
The versioned contract must cover changing contributions from every selected
publisher in a P31 session, not move knowledge alone while another per-turn
`context.publish` still rewrites the header. Preserve existing receipt validation
and legacy-session replay under their recorded version; qualify the new projection
only for sessions admitted to it. Ordinary contribution updates use the tail and
cannot be relabeled intentional epoch resets to evade the cache gate.
Move mutable reported-model facts to the tail or explicitly change the epoch when
identity changes; never retain a false old identity just to keep the prefix stable.
Declare admitted read capabilities from catalog/session start, even while their
stores are empty. Today `saved_result_read` is added only after the first result;
remove that conditional catalog churn for the selected capability and validate
handle existence at dispatch. Do not enumerate changing source IDs in tool schemas.

Render changing knowledge as a labelled, untrusted **user-role turn-local reference envelope
after the already-admitted conversation history**, adjacent to the current user
turn, or as a genuine result of an admitted read tool call. Do not fabricate an
unpaired tool response. Journal envelope identity, source/policy generations,
position and content hash so saved reconstruction reproduces the same request.
Previously sent envelopes stay in their original positions in effective history;
normal turns append instead of replacing old reference text or rewriting native
assistant/tool items. Stage later tool/answer source updates at the active tail,
without inserting messages inside a native tool-call/result group. Test each adapter's
actual serialized body; Anthropic/Gemini hoist system/developer messages, so this
data envelope cannot use those roles. A provider's role folding must not move the tail
reference back into its system/header or change historical prefix bytes.

The current host accepts at most eight contribution items **per extension instance**,
2,048 text bytes/item and 16,384 rendered bytes across all contributions including
JSON/provenance. Keep this aggregate ceiling; the new placement does not create a
second free 16-KiB allowance. Within it, allocate at most 8 KiB rendered bytes to
the knowledge service: at most 6 KiB for recall (at most four items), 1 KiB for
source-index/read handles (one item), and 1 KiB for framing/coverage (one item).
Leave the other 8 KiB for existing extension context; enforce limits on final
rendered bytes, not just excerpt text. The two remaining item slots are not extra
byte capacity. Existing contributions exceeding the reserved slice do not get
silently evicted: shrink optional recall to the remaining allocation, retain a
small index handle if it fits, otherwise emit visible coverage status and use the
fixed index-read tool with an implicit current-Session scope. Required-context
failure stops the dependent request. No tool needs a dynamic schema or header
parameter to address that scope.
This limit applies to the current automatic context selection; historical envelopes
also count toward the ordinary conversation bound. Refusal to replace a contribution
must invalidate its stale selection rather than silently keep yesterday's recall.

The index read defaults to 32 entries/4 KiB rendered per page, returning fewer
entries when needed to fit. Cursors bind Session, immutable source-window/version
and policy; refreshing after new receipts creates a new index generation.
Evidence reads are bounded by the remaining turn/request budget, with a proposed
8-KiB page maximum.
Tool results count toward the ordinary conversation/context and step limits; moving
the index to tools is not an unbounded side channel. Page/read references remain
available even if optional seed recall has no room. Freeze packing and arbitration
in A, qualify a tool-heavy turn with multiple extensions and many receipt pages in E.

Before each dispatch revalidate managed reference envelopes, managed read/search
tool-result projections and their compaction-derived excerpts, including prior
history occurrences, against suppression/expiry/permission generations. A forgotten
or revoked managed excerpt must be withdrawn from the effective request even when
that breaks the prefix: correctness takes priority over cache reuse. Journal a
deterministic safe projection/retraction, preserve native continuation/tool pairing
and show the existing original-transcript limit. If an adapter cannot safely project
it, stop and offer explicit recovery rather than send the stale contribution.
Preserve tool call IDs, result pairing and original journal bytes; do not treat a
managed read response as exempt merely because it entered history through a tool.
The original user/assistant native-transcript limitation remains disclosed, separate
from the retractable managed retrieval surfaces.
Compaction must preserve origin, validity and accepted/cancelled intent semantics;
it cannot turn a reference envelope into a fresh user assertion.

Prefix stability is a request-layout property, not proof of a provider cache hit.
Per-route qualification records cache eligibility, TTL/settings and actual cached,
uncached and cache-write partitions when exposed; unavailable values stay unknown.
The performance gate below includes TTFT (first visible text token), so subscription
routes still have observable latency evidence without pretending to know their cost.
[OpenAI's cache guide](https://developers.openai.com/api/docs/guides/prompt-caching)
describes exact-prefix reuse; it does not establish every control for subscription
accounts. [Anthropic's guide](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
requires cache controls/breakpoints; the current Ipse adapter sends none, so layout
repair alone cannot claim Anthropic cache hits. Any new control needs separate
adapter/retention qualification. [Gemini's caching guide](https://ai.google.dev/gemini-api/docs/caching)
describes model/route-dependent eligibility; qualify Ipse's actual `generateContent`
route. These sources were checked on 2026-10-26; reverify controls before use.

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
evaluation. Measure candidate recall separately from final answers. Notes-release
success does not qualify large-document retrieval. Failing automatic recall
remains unqualified; fix it or keep that product slice open. The graph/PDF
experimental allowance is not a waiver for the core notes/recall journey.

P31E includes notes-retrieval remediation before its release if its baseline misses
these bars; this must not wait for document/graph storage. P31F separately includes
a document-retrieval improvement increment if that baseline misses its bars:
repair source selection/citations and evaluate main-model query expansion.
The separately selected optional Ollama path below is required P31F work even if
the no-extra-service baseline passes; it does not replace that baseline. Additional
Gemini or compatible embedding routes remain candidates, not selected delivery.
No new mandatory service or silently downloaded model follows from a benchmark
failure. If no no-extra-service strategy qualifies, present the evidence and seek
an explicit scope decision; do not advertise it as solved.

Automatic seed recall executes once per accepted turn using that turn-local envelope;
subsequent read/search tools remain available. Before every actual model dispatch,
revalidate selected evidence against source, expiry and consent generations,
including later tool/question continuations. Clear stale contributions after
forget/change/failure; required-source failure stops dependent answering, optional
failure is visible. Do not treat an old context replacement as a valid new recall.

### Optional local embeddings and RAG

Provide two explicit setup choices: **local search with the current main model**,
or **local search and local answers**. The first still sends selected source
excerpts to a remote main model when one is selected. The second selects Ollama
as the main answer/capture route for the next new session; it must not silently
replace ChatGPT or introduce a hidden answering model. Embeddings produce search
vectors, not answers, verified facts or graph relationships. No embedding service
is required for the initial notes journey.
Local-only preflight inventories every enabled inference stage, including
extraction, reranking, decisions, compaction and delegation. Show any remote stage
in the setup preview and require an admitted local selection or disable/refuse it
under this choice; a previously saved remote helper cannot silently remain active.
Include knowledge stores and source-processing services in that route inventory;
remote graph/MCP storage cannot inherit a local-only label from the model pair.

Qualify `qwen3-embedding:0.6b-q8_0` at native **1,024 dimensions** as the primary
local embedding preset. Compare the smaller text-only
`embeddinggemma-2:270m-q8_0-text` at **768 dimensions**, with separate platform
qualification. For fully local answers, qualify `qwen3.5:4b`; compare `qwen3.5:9b`
when hardware permits. These are Apache-2.0-weight candidates, not benchmark
winners or already supported presets. The [research record](archive/2026-10-26-ollama-local-rag/index.md)
owns dated model/size/license sources, alternatives and unverified runtime floors.
Never substitute candidates automatically or inherit P27's old quality result.

Use the native Ollama HTTP adapters and existing extension ownership. The pipeline
is admitted source text → bounded citation-preserving chunks → lexical and dense
indexes → RRF(k=60) → bounded cited passages → selected main model. No new vector
server, mandatory reranker, Python/JavaScript framework, graph service or P30
engine is required. P30 can later choose among qualified enabled stores; it cannot
change the embedding or answering model without the applicable operator choice.

P31A freezes model-specific query/document templates and the actual dispatched
bytes. Qwen retrieval queries carry its task instruction; document chunks do not.
Google's candidate uses its own distinct query/document prefixes. Count wrappers
inside host input limits, retain original source spans for citations, reject
double-prefixing and keep `truncate:false`. Start with native dimensions; validate
count, width, finite coordinates, a nonzero vector norm and normalization within
a frozen tolerance. Dimension reduction requires separate qualification.
Large publisher context limits do not enlarge Ipse's
existing 4,096-byte/input, eight-input, 12-KiB aggregate embedding bounds.

Bind an index generation to full installed model digest, quantization/backend,
runtime/version, dimensions, normalization, chunker and task-template versions.
Treat moving tags as discovery labels, not immutable identity. P31A must choose
an enforceable artifact-pinning contract: prefer owned immutable model closure;
shared-daemon checks alone cannot prove per-request weights under concurrent tag
replacement. A shared route must explicitly declare its cooperative local-service
trust boundary, recheck identity around jobs and refuse changed/unverifiable
results; it cannot claim immutable attestation. Changed identity requires a
separate bounded rebuild and atomic index publication, never mixed vector spaces.
Rebuilds preserve exclusions, suppression, citations and revocation; failure leaves
the previous still-valid generation usable without restoring forgotten material.

P31D0 designs connection/provisioning choices; D1/F deliver the installed local
preset. Show model license, download/cache space, actual endpoint and both data
routes before selection. Reuse resident models when suitable. Optional downloads
require explicit consent; installation of Ollama follows the dependency policy.
Acquisition has separate model-count/download/disk/deadline/progress bounds and an
owned, journaled receipt; embedding-request limits are not download limits. Serialize
Ipse pulls per service/model, coordinate with inference admission, inspect partial
or unknown completion after cancellation/owner death, and never restart a pull on
resume automatically. Disconnecting the client may not stop the daemon's download;
qualify stop behavior and disclose unresolved work. Only verified complete model
identity can activate a selection. Cleanup cannot remove another client's assets.
Models stay outside Ipse archives. Do not alter, stop or replace a shared daemon.
Qualify a local-only choice with resident local models, cloud features disabled on
an operator-managed service, and knowledge-pipeline egress blocked after provisioning;
loopback alone is insufficient. External research remains a separate data route.

P31A freezes finite matched trials and resource ceilings; F must qualify at least
one embedding/answer pair before advertising this optional local route. Measure
candidate recall, answer/citation support, abstention, poisoned-source resistance,
tool/capture quality, cold/warm latency, TTFT, RAM/VRAM and index/rebuild disk peak.
Record effective context and full request budgets; current Ipse profiles do not
set Ollama's `num_ctx`. Add protected operator-scoped endpoint admission across
projects/processes for main/child generation and embeddings, separately from
project budgets. Bind slots to one protected service ID with canonical origin and
explicitly admitted address aliases, independent of model/profile or `/api/chat`
versus `/api/embed` paths. Start with one inference slot, foreground priority and
bounded visible/cancellable waits. Release the slot between a settled model response
and tool execution so a subsequent embedding tool cannot deadlock. On timeout or
owner death persist unknown reservation state; a released OS lock does not prove
the daemon stopped. Clear it after confirmed owned-service quiescence or explicit
shared-service reconciliation/recovery, never by automatic replay or timeout alone.
This schedules Ipse dispatches, not other daemon clients or actual shared-server
concurrency; expose that limit during recovery. No model-card size proves a
machine will fit. Keep E independent of this later document option;
any earlier notes use needs its own qualified profile. Failure leaves the local
slice open or requires an explicit scope decision; graph/PDF's experimental
allowance does not waive it.

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

Permission answers which knowledge effects are allowed; input origin answers what
claims the evidence supports. Reusing permission never upgrades `run_input` into
human testimony. Verify both a real automatic headless save of a host-verified
outcome and quarantine of injected prose under the same consent, without `--yes`.

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

Proposed defaults, disclosed in setup and frozen in P31A:

- An explicit interactive “remember X” pins the admitted claim and support until
  deletion unless the user specifies a duration. The receipt says which policy
  applies. All provenance, secret and scope checks still apply.
- Directly stated enduring preferences are persistent until corrected/forgotten;
  a task-local instruction or inferred preference is not automatically enduring.
  Record why the persistent category was selected and make correction easy.
- Other ordinary automatically captured facts expire after 90 days unless pinned, explicitly
  reconfirmed or corrected with new evidence. Model retrieval never renews expiry:
  that would let repeated recall perpetuate poisoned or obsolete material. A daily
  enduring preference survives through its persistent category, not its read count.
- Current temporal assertions, such as Acme's owner, retain their support until
  explicitly corrected, superseded or forgotten, subject to quota. Keep observed
  date and uncertainty visible: retention does not prove they are still true.
  Temporal history retains superseded assertions and support for at least 365 days
  after supersession under the selected quota; offer a longer/project-lifetime
  policy explicitly. Support for
  a pinned historical assertion stays pinned. A change arriving after day 90 must
  still find the previous version and its evidence. A 30-day cleanup may remove
  obsolete display/index revisions only; it must not delete the domain history needed for
  this promise. Questions outside the retained window return a visible gap.
- Uncommitted review/proposal candidates and parked unstarted work expire after
  seven days. Expiry never confirms a candidate or retries an unknown effect.

Show each note's policy, reason and upcoming expiry; support an explicit project
policy adjustment. Preserve existing Memory TTLs during import unless the operator
selects a previewed migration policy; pins and categories require new record support.
Keep evidence at least as long as all current or retained historical dependents;
expired/missing support invalidates their use. Persistent items cannot be silently
evicted to admit newer observations. At 80% capacity show a notice; collect eligible
expiry, then pause new capture visibly at the cap. Safe refusal remains necessary,
but is insufficient evidence of usable capacity.

Every save/update receipt shows the assigned category and expiration/persistence,
including whether the model inferred an enduring preference. Offer a one-step
change to ordinary 90-day retention, a user-selected duration, session-only/no durable
capture, or pin. Persist the operator override against the claim/evidence lineage;
repeated capture or paraphrase with the same support cannot silently promote it
back to persistent. Session-only downgrades suppress the selected durable derivative
and retain its minimal override/suppression metadata. Shared source evidence remains
while needed by unrelated authorized current/historical dependents; the receipt must
not claim all bytes were erased. An explicit reduction of the selected claim's
temporal retention is a user policy override: show the resulting historical coverage
gap instead of claiming the old 365-day coverage still holds. Do not shorten other
claims' support or relabel all claims from a shared source event.

Keep journal, original binaries, extracted evidence, indexes, revisions and backups
separate in status/quotas. Minimal suppression identity may outlive normal evidence;
bound it with version floors/compaction that reject incompatible old imports.
Do not simply delete tombstones and permit resurrection. Test a year of new-source
turnover, pins, expiry, offline gaps and imports as well as repeated updates to
one fixed set. The notes release must meet the sustained workloads below with
proposed capacity of at least 2,000 active notes, including 200 persistent notes,
6-KiB maximum note-plus-evidence values, 24 MiB for records/evidence/history and
64 MiB total including indexes/suppression/control metadata. These are provisional
minimum capacity and maximum resource envelopes to evaluate, not measured facts.
Adjust the envelope after prototype measurements and freeze it before held-out
qualification; do not reduce the workload to disguise failure. Count journal growth
separately; the store quota is not a promise to bound the original conversation log.
The tested persistent population includes pins, enduring preferences and current
temporal assertions together; 200 is the workload mix, not a separate hard pin cap.
The total quota still bounds an operator who keeps adding persistent records.

### Pilot intake before freezing capacity

Twenty ordinary items/day is an initial floor for a declared 40-turn workload,
not a measured typical rate. P31A runs a finite nonpublishing capture pilot after
fixing the provisional tool/source contract: up to three representative, explicitly
authorized routes (default ChatGPT, a small local tool-capable model where available,
and an already selected API route), three 20-turn sessions each, on frozen mixed
tasks with independently labelled useful decisions/facts and few/no-memory turns.
A lightweight Elixir probe may exercise normal main-provider tool continuations
with fake storage receipts; it must publish no project notes or execute task effects.
Fixtures alone do not establish model propensity. Do not add a service or spend
without an approved finite request/token/cost envelope; unavailable routes remain
unverified, with the missing pilot evidence an explicit open readiness item.

Measure proposed and admitted items/turn, independent usefulness/critical-fact
coverage, duplicate/correction/consolidation rates, payload sizes, retention-class
mix, read/continuation counts and cache/latency metrics. A model that rarely calls
capture but misses useful decisions does not qualify as efficient. For each piloted
route, derive intake as the greater of 20 and the ceiling of 40 times the highest
observed session-average useful-unique rate per turn. This conservative pilot
bound is not a population estimate. Freeze the workload at the largest qualified
route's result, with the measured persistent/temporal mix and declared burst margin;
preserve the initial floor and the 2,000-note minimum. Reconcile storage/history
envelopes before the held-out tests. E repeats intake checks on real integrated
sessions so a dummy pilot cannot qualify the final capture behavior by itself.

If measurements exceed the initial envelope, increase sustainable capacity or
qualify lossless dedup/consolidation with provenance/critical-fact checks, then
refreeze before evaluation. Do not silently reduce useful capture, forget durable
facts or call capacity refusal normal success. Exercise a separate worst-case
320-proposal/day burst at the eight-item/40-turn ceiling: validate/deduplicate,
report what saved/skipped/pended, warn at 80%, and visibly pause at a finite cap
without evicting pins or replaying rejected candidates. Status reports observed
intake, capacity and projected days remaining with uncertainty. Report pause counts
and time-to-cap in pilots/endurance; exceeding the frozen normal-use envelope in
the integrated pilot requires remediation or explicit qualified acceptance, not
an unqualified claim that ordinary use lasts months.

P31C1b's additional document/graph profile targets 1,000 active document sources,
20 MiB extracted document evidence, 10,000 chunks, 5,000 entities and 20,000 graph
assertions. Its 256-MiB total store envelope includes the notes allocation; source
and evidence counts for documents do not replace the notes capacity. Ratify these
targets with temporal history and resource accounting rather than treating them
as an unlimited all-history promise. Local vectors and index metadata count here,
including both old and staged generations during rebuild. Ten thousand float32
vectors at 1,024 dimensions alone require 39.1 MiB before metadata/index overhead.
Preflight peak space and refuse visibly without deleting protected data; qualify
the target workload and rebuild together. Model downloads/cache use a separately
disclosed disk allowance outside this store. Any earlier local-notes preset must
also fit C1a's complete capacity and migration gates.

Forgetting suppresses managed lineage and declared aliases across notes, graph,
chunks, vectors and context. Disabled stores revalidate before re-enable/import.
Queued or stale writers cannot resurrect it. Do not promise detection of every
independently restated paraphrase. Already sent conversation text/native provider
continuation cannot be withdrawn: users may keep the current conversation with
that limitation or explicitly start fresh with a reviewed bounded note. Starting
fresh loses full native history; neither option erases the original journal.

P31C0 supplies source-bound records on existing State for internal prototypes.
P31C1a evaluates and supplies sustainable notes storage before E; C1b extends it
for documents/graph without a second unnecessary database. Domain storage/query
policy stays in extensions, host admission and lifecycle remain mandatory. P26/P27
and prototype imports need capacity preflight, complete export, writer fencing,
checkpoints, validation, atomic root switch and rollback that cannot restore
forgotten facts. Later migrations preserve the released notes contract. Historical
questions need retained versions; current `as_of_ms` cannot reconstruct replaced
generations. Show retention gaps and unknown dates honestly.

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

`/enhance TEXT` creates a host-enforced draft turn in the **current Session**, using
its ordinary main provider/model/billing route and native conversation history.
The person is asking that assistant to draft a clearer request, not to execute TEXT.
This baseline does not call the extension `model.complete` helper or require an
auxiliary subscription capability. P31A freezes this intent/request contract before
the naming trial; P31I implements and qualifies it on the default ChatGPT route as
well as the other selected main routes. Optional independent helpers remain a
separate opt-in capability requiring their own route/account qualification.

Mark the request and answer as draft material in native history and the journal.
Keep the selected ordered tool declarations byte-stable across draft, cancellation
and ordinary turns. Enforce the ceiling at dispatch/admission, not by removing
tools or trusting a model instruction: reject prohibited calls, workspace writes,
shell, MCP effects, delegation, capture publication and effectful extension callbacks before/after the
turn. Already admitted context, bounded questions and explicitly allowed reads
remain subject to source/egress permission. Neither saved consent nor `--yes` can
override the ceiling. Cancelled drafts are non-authoritative history, not facts
or execution intent; future capture cannot launder them into accepted decisions.

Persist cancellation against the exact draft/version before returning to ordinary
input; fence queued work and late callbacks. Append a concise, labelled user-role
host intent-status notice at the active tail, distinct from untrusted source data. The
notice says the draft was abandoned and may not supply requirements for later
work; it does not repeat its contents or alter the stable header. The next ordinary
turn is bound to its own user intent, not the cancelled draft. Preserve cancellation
in resume, source eligibility and compaction: neither raw draft requests nor their
summaries may become pinned active user intents. Keep original native records
inspectable; do not delete provider-native history to conceal the issue.

The host deterministically blocks effects during drafting and blocks cancelled
draft acceptance/capture. It cannot prove that a model will never be influenced
by text it has seen. Qualify cancelled-draft carryover explicitly: conflicting
requirements, filenames and instructions from the cancelled draft must not affect
the next unrelated task's answer or effects, including under existing session
grants, resume and compaction. A failure keeps enhancement unqualified for that
route until repaired; disclose the retained-history limitation and offer an
explicit fresh-session recovery, never a silent history reset or provider switch.
Settle prohibited draft tool calls as denied results without execution, preserving
call/result pairing and step bounds. Do not rely on provider `tool_choice` changes
to enforce the mode. A later user may explicitly reintroduce a cancelled idea as
new intent; tests must distinguish that from accidental carryover.

Show the ordinary route and budget. Bound request count, deadline and accepted
output bytes. The current ChatGPT adapter refuses an output-token cap; do not set
an unsupported cap, silently use API billing or claim server-enforced token limits.
Record measured usage and unknown remote liability on cancellation. These local
bounds do not promise that remote inference has stopped.

The line-oriented minimum is show/replace/accept/cancel, including a bounded
multiline replacement mode. It requires no editor dependency. An optional editor
round-trip uses a configured executable/argv, private bounded UTF-8 draft and an
input-loop suspension handshake; do not shell-evaluate `$EDITOR`. Handle abnormal
exit and cancellation, review changes and clean up. Never assume `IO.gets` can
prefill/edit a live buffer. Bind original/proposed/accepted text, evidence/question
IDs and draft revision to a host intent record; pending can become accepted or
cancelled, only accepted can become consumed once. Stale acceptance refuses.
Acceptance submits the exact accepted text as a new ordinary turn under current
permissions and the pre-existing enclosing mode. It exits only the temporary draft
ceiling; planning/read-only remains active until independently changed by the user.
It does not edit old native history or execute the original unaccepted request.
Resume restores pending/accepted/consumed/cancelled state and
never auto-accepts or replays. A provider failure leaves a visible incomplete draft.

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

P30 delivers an admitted typed decision operation and a **finite evaluation**, not
a requirement that a classifier improve the product. Freeze the experiment list,
engine/model/rubric identities, candidate policies, tuning allowance, held-out
workload and benefit criteria at A. The initial experiments after P31E are:

- Notes selection when the eligible set exceeds the shared context allocation:
  compare bounded selection/reranking with deterministic recall plus ordinary
  model read/search, matching source/token limits. Include critical-decision recall,
  citations, latency and total cost. Sets that fit completely are a bypass stratum,
  not a manufactured multiclass problem.
- Note-candidate assessment on the same host-validated main-tool candidates:
  compare ordinary admission/main-model judgment with optional advice on durability,
  ambiguity or conflicts. Start in offline replay/shadow mode; never publish twice.
  Measure missed useful decisions, false durable claims, abstention and total cost.
  Advice cannot repair false evidence, change source class or grant consent.

In production, fitting notes bypass retrieval selection; no candidate bypasses
candidate assessment; no useful alternative or selected qualified strategy means
no request for that consumer. Candidate assessment is not a required second opinion
on every turn. Evaluation may call an unqualified candidate under a separately
explicit finite experiment grant and budget, in replay/shadow mode with no effect
publication; ordinary saved knowledge consent does not authorize that experiment.
A production strategy becomes selectable only if it passes the frozen benefit and
safety criteria; there is no default-on extra classifier.
Later routing among notes, documents, graph and combined retrieval has real source
alternatives and compares with query-all/fusion, but waits for F/G and does not
block the initial finite P30 scope.

A/B/C protocol, permission, accounting, cancellation and integration gates must
pass. D/E records each selected experiment as **qualified/useful**, **evaluated and
rejected/no benefit**, or **unverified**. A completed negative evaluation closes its
experiment; P30 may finish with no qualified default consumer and must say so.
Missing access or incomplete live evidence is not a negative result or passed
gate: leave it open or obtain explicit qualified acceptance with the limitation.
Do not keep trying new workloads indefinitely until something wins.

Filter alternatives by enabled sources, eligibility and limits before sending any
decision. A deterministic policy maps valid output into an ordinary journaled
effect, with fresh authority, source-version and budget checks.
Permission/reservation/journaling also precede
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
apply. Unknown account ZDR/residency properties stay unknown. An endpoint is not proof of an account's
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

Cache/performance qualification has two comparisons: product overhead with knowledge
on/off on matched tasks, and a cache-isolation replay matching the eligible prefix
length and changed-suffix budget on the same route/model. Separate cold from warmed
requests and record warm-up, TTL, controls and intentional resets. Freeze the replay,
sample count and numerical tolerances in A; mocks qualify serialization only.
Reuse Usage's existing nullable cache counters: total input, cache reads, cache
writes and uncached input. `input - cache_read` is non-read input **including** writes;
subtract writes only for the separate uncached partition when all components are
known and consistent. Report missing counters as unavailable, never zero or success.

Add monotonic request-dispatch-to-first-visible-text and user-input-to-first-visible-
text timing, the latter including local recall. Tool-only replies get first usable
tool-event/completion timing, not zero TTFT; never expose hidden reasoning. Report
raw sample counts and p50/p95, known cost and cache-read ratio on long sessions.
Proposed warmed cache-isolation tolerances are <=5 percentage-point cache-read-ratio
regression and <=10% non-read input increase, with matched suffix budgets; proposed
product TTFT tolerances are <=20% regression at p50 and p95 on the frozen long-session
workload. Ratify feasible targets from the pilot before held-out tests, recording
any change and why; no after-the-fact relaxation to erase a failed result.
If counters or authorized live access are unavailable, retain that cache metric as
unverified and qualify only measured layout/latency. A release cannot call the full
cache/performance gate passed on unchanged token totals or mocks alone; missing
required route evidence needs an explicit qualification decision.

| Area | Proposed target or required evidence |
| --- | --- |
| Notes recall | Separate frozen strata: 100 prompts across independent <=32-note sets and 100 across independent collections at the frozen active capacity (at least 2,000 notes) exceeding context/index inclusion. Include answers absent from the initial context/index page and constrained/zero optional recall allocations. Apply semantic bars separately to each stratum; fitting fixtures require 100% eligible-byte coverage within their granted allocation |
| Larger quality | At least 200 capture cases, 100 document prompts and 100 entity/relation cases; separate negatives, temporal contradictions, absent evidence and PDF/DOCX fidelity |
| Capture work | At most one ordinary batch per turn, <=8 items/8 KiB proposal; zero mandatory extractor calls on turns with no candidates; no hidden repair loop |
| Capture overhead | Local admission/publication p95 <250 ms on reference hardware; target median <=10% additional measured input/output tokens over matched 100/500-turn sessions, including history replay and compaction, and <=1 capture-only continuation per turn. Report billed cost where known, tool argument/result bytes, request/history/journal growth, time to compaction, compaction count/cost and end-to-end p50/p95 latency by model; include dedup/no-op and near-context-limit cases |
| Cache and first response | Actual serialized prefix stability before the changing tail, stable tools across first-result/draft/ordinary transitions, nullable cache/non-read partitions and both TTFT measures under the frozen paired protocol above. Test real adapter role folding and native grouping. Subscription billing absence does not waive latency/cache evidence |
| Context/source discovery | Multiple publishers, >=64 typed receipts with enough explicitly bounded steps or valid parallel calls, UTF-8/escaped labels and near-limit history; capture from first/last receipt and a native answer using paged reads, including zero optional inline allocation. Test cursor changes/revocation, stale-replacement refusal, unread coverage and actual wire bounds |
| Optional extraction | Default <=1 request per eligible batch, finite input/output bounds and 30 s deadline; target p95 save lag <=15 s on the qualified reference profile, with foreground priority |
| Cost setup | No silently chosen paid daily allowance; helper calls remain disabled until an operator chooses a finite cap. Main capture shares the selected main route; unknown/subscription prices show call/token bounds and measured usage |
| Local retrieval | Target p95 <500 ms warm / <2 s cold on documented four-core/8-GiB/local-SSD hardware, excluding remote inference |
| Notes endurance before E | C1a: pilot-derived frozen intake/mix, with the initial minimum of 30 simulated workdays at 40 turns/day, 20 ordinary 90-day items/day, four corrections/two forgets per day and 200 persistent records (100 pins/50 preferences/50 current temporal assertions); increase envelope for measured rates/mix. Two overlapping OS processes, continuation to day 90, offline week/restarts/imports, representative plus maximum-value payloads. No ordinary-use pause under the frozen workload |
| Turnover before E | C1a: 10,000 update/correct/forget cycles plus continuation to 365 days under frozen intake/class/payload counts. At least four temporal supersessions/day with retained prior support; ordinary correction/expiry/forget cases separately. Account for live/history bytes and suppression reclamation; refuse imports below supported version floors. Report high-intake burst pauses separately from the supported ordinary envelope |
| Platforms | Full source/native/demo/package/installed checks for changed runtime paths on Linux and macOS; parser/model/account/human scopes recorded separately |

Use deterministic tests for forged sources, secrets on every intake, hostile
instructions, cross-worktree version confusion, headless knowledge save with denied
shell, concurrent budget/revocation races, every queue/owner-exit state, disabled
store forgetting, stale context before later same-turn dispatch, migration rollback,
planning MCP impostors and stale prompt acceptance. Observe actual model requests,
receipts and persisted state, not only callback results. Unknown effects never replay.

Required boundary cases include issue/email-generated headless input attempting to
save a preference, a legitimate automatic verified headless save, copied provenance,
explicit versus bare-yes decision acceptance with competing assistant prose questions,
multiple/stale/unshown/cross-client codes, and native question selection without
a second prompt. Standalone review must work without a model/chat, reject generated
confirmation input and keep batch versions/scope fixed under concurrent changes.
Test repeated exact quotes, UTF-8/normalization differences,
redaction and unavailable source versions. A real registered worktree can join; an
outward-pointing archive, wrong backlink, stale registration, separate clone and
metadata/symlink swap cannot recall another project's notes before any model request.
Forget after a paged note/search read, then continue, resume and compact: no managed
result or derived excerpt may reintroduce it, and tool-pair/native replay validation
must still pass or visibly stop for recovery.

Retention tests cover explicit remember/duration, enduring versus task-local
preferences, no TTL renewal from model reads, first temporal supersession after
day 90, historical questions beyond 30 days and at the 365-day boundary, pins,
quota accounting and honest expired-evidence gaps.
Also test visible false-persistence classification, one-step downgrade, duplicate
recapture respecting the override, required historical dependents and worktree reuse.
P31A's draft contract and P31I acceptance must inspect the actual default ChatGPT
request route, ordinary native history and ceiling, including no unsupported output
cap; edit/accept/cancel/stale acceptance, acceptance while planning/read-only,
callback effects, failures and resume all need coverage. Any authorized live
default-route journey is separate from fixtures;
neither this design nor a passing mock claims live verification.
Cancel a draft containing a distinctive conflicting requirement/canary path; the
next unrelated task's response and tool arguments must not adopt it, under existing
grants as well as ordinary approvals. Repeat through compaction, resume and late
callbacks; inspect persisted cancellation and request layout, not only capture output.

Recruit usability participants at P31A. Require at least one independent fresh-user
notes journey for the interim release: standalone setup then first chat, capture/later recall,
correction/forget, limits, headless scope and disable. Final P31 acceptance adds
documents, graph status and the complete upgrade/migration journey; the interim release
still rehearses installation/upgrade automatically. Separately test enabling inside
an existing conversation, unchanged resume and next-new-session activation. Record
assistance, setup-to-first-use time and actual approval counts. Seek macOS human
coverage early. If unavailable, retain automated macOS
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
