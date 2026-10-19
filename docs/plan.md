# Development plan

Ipse is an Apache-2.0-licensed general-purpose local AI harness. Its core stays in
Elixir/OTP, with Rust for small OS helpers; target projects may use any suitable
stack. Prefer extensions, tools and inert skills for domain features, ordinary
OTP for ownership, and reviewed generic core changes for missing host invariants.
No mandatory workflow framework, service, database or hardcoded external endpoint.

This document owns priorities, scope and acceptance. The
[documentation map](index.md) owns navigation. The [user manual](operator/index.md)
teaches operation; the [contributor manual](developer/index.md) teaches implementation
and verification. Dated test counts, receipts and investigations live in the
[archive](archive/index.md), including the
[verification record](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks)
preserved before the manual rewrite. The
[previous plan and knowledge design](archive/2026-10-17-before-self-hosting-review/index.md)
are preserved with provenance.

## Current priorities and status

P0–P22 are complete within the scopes summarized under
[completed milestones](#completed-milestones-p0p22). P23 is complete within its
one-shot text/accounting scope. Provider/account combinations have separate
[verification](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#provider-verification-status); these milestones
do not establish production knowledge quality or unattended self-development.

P24 is complete as a scoped readiness gate for the supervised P25 trial at
`375e607`. The external architecture critiques retain their original partial
coverage and withheld verdicts. After the focused report was interrupted, the
operator approved baseline scanning first without another architecture-review
round. Security Cloud then reported complete static coverage of 399 paths at
`8b4f706`: one High, one Medium and three Low findings. Four applicable repairs
passed local and hosted checks at `bfce156`; the private-journal finding retains
the documented same-user storage trust limit.

Supervisor follow-through separately repaired private macOS credential transfer,
optional-consumer retirement and large-launch-frame readiness. The final
`375e607` source passed local native-inclusive checks and the complete hosted
Linux/macOS source/native/package/installed matrix. The
[readiness decision](archive/2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md#p24-scoped-readiness-decision)
combines that evidence and records accepted limits. This is supervisor acceptance
for a trusted, cooperative workspace under supervision, not a new independent
post-fix verdict, a second scan, or a security certification. Raw findings remain
private. No R/S/C/O review sequence or continuous monitoring is scheduled.

P25 is complete as a scoped supervised evaluation at `3307563`. Installed Ipse
authored a meaningful diagnostic repair; two fresh reports meet every criterion
at 14/21, matching the checked reference. Held-out cases and live question/resume,
compaction and cancellation controls pass with declared assistance. The
[acceptance decision](archive/2026-10-18-before-manual-rewrite/docs/developer/p25-evaluation.md#scoped-acceptance-decision)
retains initial failures, interventions, resource differences and unconfirmed
intermittent CI causes. This establishes supervised research/self-development
within those conditions, not unattended operation or statistical parity.

Final Security Cloud scans have partial coverage and findings, not a clean-scan
verdict. All applicable findings and subsequent review gaps are reproduced,
corrected and closed within their documented scopes. The final provider patch
passes affected source review, bounded same-reviewer follow-up, local native and
installed checks, and the complete exact-source Linux/macOS matrix at `3307563`.
Earlier independent architecture omissions and withheld verdicts remain unchanged;
no security certification or further review/scan loop is claimed. The
[verification record](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks)
owns exact source, failed attempts, checks and exclusions. The requested license
transition follows this completed campaign as a separate verified change.

The research subject is optional working/long-term memory, research, graph and
RAG, including the operator's Zero-Mem inspiration. P26A/P26B's explicit-note
baseline is complete: implementation `108aa86`, with the diagnosed worker cleanup
repair and local/hosted gates at `fb4627e`. P27 research, graph and RAG development
is active; media remains deferred to P28. External services remain configurable; no third-party
engine, database or mandatory backend is selected.

| Milestone or gate | Current state | Next result |
| --- | --- | --- |
| [P23: accounting and budgets](#p23-usage-cost-reporting-and-budget-controls) | Complete within selected scope | Preserve accounting through the trial |
| [P24: architecture/security readiness](#p24-independent-architecture-validation-and-baseline-security) | Complete for supervised P25 at `375e607`; accepted limits recorded | Refresh affected validation after trial changes |
| [P25: comparative self-development](#p25-comparative-research-and-supervised-self-development) | Complete within declared supervision/assistance at `3307563`; security findings triaged and corrected scopes verified | Preserve frozen evidence; select a later production increment separately |
| [P26: memory baseline](#p26-optional-working-and-long-term-memory) | Complete within P26A/P26B scope; cleanup repair and platform gates pass at `fb4627e` | Preserve suppression, explicit retention and affected-session recovery |
| [P27: research, graph and RAG](#p27-optional-research-graph-and-rag) | Active; architecture, implementation and validation incomplete | Configurable independent packages, reviewed host contracts and matched held-out evaluation |
| [P28: voice and media](#p28-voice-and-realtime-media) | Deferred; unimplemented | Explicit media contracts and later device/service validation |
| [Apache-2.0 transition](#license-transition) | Complete; local and hosted `7bb642b` checks pass | Preserve bundled identity/recovery and third-party license boundaries |

The requested P22–P25 campaign and separate Apache-2.0 transition are complete
within their documented scopes. P26A/P26B are complete after the cleanup repair;
P27 is active and P28 remains deferred. Preserve P25's frozen
inputs, runners, source/review/scan identities, scores and failed attempts; newer
documentation does not rescan code or expand an earlier verdict. P27 follows the
researched proposal; further memory automation remains separately scoped. Keep P28
deferred. No further broad architecture-review loop or Cloud scan is scheduled.

The [register](archive/2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md) owns dispositions,
the [internal audit](archive/2026-10-18-before-manual-rewrite/docs/developer/architecture-self-audit.md) owns supervisor methods,
and [testing](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks) owns dated
commands, receipts, failures and exclusions. Internal reads, external static
coverage and actual execution support different claims. Earlier records retain
their contemporary numbering and verdicts.

## Completion rules

For each increment define observable acceptance, preserve original/native history,
explicit provider/billing selection, approvals, owned cancellation, bounded data
and no automatic replay of unknown effects. Instructions and configuration are
never permission grants. Disabled extensions create no worker, store, connection,
indexing job or inference. Core owns mandatory journal/accounting integrity even
when tracing, cost UI or optional memory is disabled.

Evaluate maintained Elixir/OTP and Rust facilities before custom machinery;
inventory selected dependencies and licenses. Dependencies outside Elixir/Rust
require explicit developer approval, including development and security tooling.
Use public interfaces and operator-configured endpoints, with no hidden fallback.

Run meaningful focused tests and the required source/native/demo/package checks for
runtime changes. Distinguish fixtures, live provider/account checks, installed
artifacts, hosted macOS and local macOS evidence. Review affected operator/developer
guides as coherent documents, reconcile entry points and check files/anchors before
calling an increment complete. Commit and push verified focused changes; preserve
unrelated work and never force-push. Detailed procedures are in
[AGENTS.md](../AGENTS.md#finish-a-change) and [testing](developer/testing.md).

## P23: usage, cost reporting and budget controls

**Complete within the selected scope.** The [usage contract](developer/usage-accounting.md) supplies durable
request/attempt/provider/billing/model facts separately from diagnostics. The
[configured cost implementation](developer/costs.md) and
[operator guide](operator/usage-accounting.md) define the available reports:

| Increment | Delivery state and scope |
| --- | --- |
| P23A | Pure versioned rate-card estimator with exact configured identities, fixed-point arithmetic, cache partitions, provenance and explicit unknown/partial values |
| P23B | Separately granted own-session `usage.read`, fixed prefixes, source-bound cached recovery and default-off `builtin:cost-report:1` pages |
| P23C | Finite separately granted full own-session enumeration and default-off `builtin:cost-summary:1`, cumulative request replacement and overflow/legacy handling |
| P23D | Explicit registered-child discovery/reads and default-off `builtin:cost-tree:1`, frozen accounting prefixes, exact origins and visible missing/busy/invalid/legacy/cleanup gaps |
| P23E1 | Explicit supported provider output ceilings, narrowed child/summary caps and saved-policy resume |
| P23E2 | Optional atomic session-tree reservations for main/summary/children, conservative settlement, protected inspection and historical-source validation; local and hosted Linux/macOS source/package/installed checks passed |
| P23F | Explicit one-shot `host.model` text requests, profile-bound approvals/receipts, canonical usage and shared reservations; source/native/package and both independent artifact proofs passed locally and in hosted Linux/macOS checks |

[Provider output ceilings](developer/provider-limits.md) apply only to supported
API/Ollama requests. ChatGPT subscription refuses the unsupported setting; no
output-token ceiling is invented for that public interface. Verification scope
and limitations are recorded in
[actual evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks).
The [shared budget contract](developer/budgets.md) covers main, summary and local
children and [extension model operations](developer/extension-model-calls.md)
independently of reports. P23F's source and installed proofs passed locally and on
both hosted platforms; the measured coverage remains distinct from live billing.

These reports do not enforce budgets, produce a globally atomic tree balance or
promise an invoice ceiling. Rates are configured; subscription equivalents,
API estimates and local inference resource costs remain distinct. Missing usage
or failed-child cleanup cannot be converted to zero liability.

The [independently built model artifact](../examples/model-calls/README.md) and
existing seven-artifact compatibility lab passed against unchanged extracted
packages. Acceptance includes real parallel child inference, nested approvals,
owner-loss cancellation, refusal/overdraw, source-bound cached cost recovery and
inert resume. Exact revisions, archive digests and terminal hosted conclusions
are recorded in testing. One-shot text is the selected operation; embeddings/audio
remain unsupported pending separate contracts. In-flight input/money estimation
and arbitrary trusted out-of-band calls cannot establish an invoice ceiling.

## P24: independent architecture validation and baseline security

**Complete for the scoped supervised P25 trial at `375e607`; not a security certification.**

The independent critiques challenged ownership, effects, privacy, recovery,
extension authority, accounting and native confinement. Their reports remain
partial source reviews with the verdicts they actually returned. The interrupted
2026-10-18 focused pass did not provide its requested final report. Following the
operator's scan-first decision, the one-time Security Cloud baseline at `8b4f706`
reported complete whole-tree static coverage, without executing tests or native
enforcement. Its findings and the interrupted pass's concerns were triaged
separately rather than treating either output as automatic acceptance.

Applicable helper-integrity, aggregate-call, JWT and CI-pin findings were repaired
at `bfce156`. Additional controlled probes corrected credential staging under a
shared Mac grant, a retiring optional consumer rejecting the next turn, and a
large launch frame leaving the first protocol write backpressured. Exact-source
local and hosted verification passed at `375e607`, including actual macOS native
environment/stdin handling, signed sandbox enforcement and both installed proofs.
The [readiness decision](archive/2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md#p24-scoped-readiness-decision)
records the evidence chain and selected acceptance scope. Historical failures and
unconfirmed intermittent causes remain in [testing](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks).

Accepted limits remain explicit: trusted user-permission code; non-atomic host
file checks under hostile concurrent workspace changes; same-user journal/storage
rewriting; Mac shared-container and detached-descendant boundaries; unknown remote
effects and unconfirmed cleanup; journal growth/startup cost at that revision
(reopened by P25's final scan and addressed by its verified bounded-journal repair); fixed
reservations, fail-closed tree overdraw and torn-ledger continuation. Immutable
host evidence is not a memory-erasure interface. These limits constrain the
supervised trial and future contracts; they are not claims that attacks or defects
are impossible. There is no unresolved applicable Critical/High finding in this
review set, but no independent post-fix architecture verdict or second security
scan is claimed.

The implementation author's final changed-path review plus actual execution
supports proceeding under supervision; the old independent reviewers' withheld
verdicts are not rewritten. P25 must preserve the frozen runner and approvals,
record interventions and revalidate changed surfaces. Its final architecture
delta/security review remains a separate gate. The
[preserved operator checkpoint](archive/2026-10-18-before-manual-rewrite/docs/operator/architecture-review.md)
links the actual scan; the
[preserved evaluation protocol](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md)
owns that trial's controls.

## P25: comparative research and supervised self-development

**Complete as a scoped supervised evaluation at `3307563`, with recorded assistance and accepted limits.** Replace P25's production-engine delivery
with a large supervised evaluation using those engines as a research/planning
problem. Track A uses Codex; Track B uses stable installed Ipse. Both research
working/long-term memory, configurable research providers, graph and RAG, including
Zero-Mem and alternatives, then propose implementable P26/P27 designs. Each works
independently before comparison, with common requirements and recorded resource,
provider/model, retrieval and assistance differences.

The [preserved evaluation protocol](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md) owns the rubric,
artifact manifest, proposed round limits, held-out cases and review process.
The [frozen common brief](archive/2026-10-18-before-manual-rewrite/docs/developer/p25-common-brief.md) pins the initial research
controls and identical source manifest before scored execution.
The [preserved knowledge design](archive/2026-10-18-before-manual-rewrite/docs/developer/knowledge-extensions.md)
owns that study's domain questions and selection gates. New evaluation work follows
the [contributor training](developer/self-hosting-evaluation.md). Existing P14 tools/skills/ledger and P22 SDK are available; engine
installation or production implementation is not required by this milestone.

Execution readiness requires a passing frozen runner, reviewed task/resource
limits, usable explicit research access for both tracks and P24's architecture
dispositions and triaged baseline audit. Brief preparation and service-access
checks can proceed earlier. P28 live audio is not a prerequisite. Scope the trial
as several reviewable work packages with retained intermediate artifacts, so
research, long-task recovery and actual self-development have separate evidence.

| Phase | Deliverable and gate |
| --- | --- |
| A — freeze and verify readiness | Pin task/rubric, source packet, runner/candidate, profiles, tools and resource limits; confirm P24 architecture/security coverage matches the actual baseline and refresh affected reviews if it changed |
| B — independent research | Frozen A/B reports, primary-source/claim ledgers, alternatives, architecture, dependency/license review and implementation proposals; common-packet and live-research comparisons |
| C — evidence-based comparison | Codex reviews both reports against the sources and common rubric; record material discrepancies, root-cause hypotheses, uncertainty and supervisor assistance |
| D — Ipse-authored repairs | Stable Ipse develops meaningful harness/extension/skill fixes with regressions and documentation in a separate candidate; Codex independently reviews and verifies |
| E — fresh reruns | Clean same-input and held-out evaluations after fixes; real behavior change, context pressure, operator question, interruption/resume and independent review, plus source/native/package/platform checks |
| F — final architecture, security and acceptance | Completed partial OpenAI security scans, affected delta reviews, reproduced repairs and exact corrected-source platform/installed checks; scoped supervisor acceptance, sanitized evidence and researched P26/P27 proposal. Scan revisions and later corrective patches remain distinct |

Research acceptance means source-supported correctness, required coverage and a
useful implementation plan at comparable declared limits. Codex's report is a
reviewed reference, not unquestionable truth or a wording template. Both tracks
must satisfy minimum criteria; justified alternative decisions can pass. Proposed
bounds are three repair rounds and two independent final Ipse runs, with no material
factual/citation errors, unresolved applicable critical/high findings or foundational
correctness gaps. Pin actual limits before execution; exhausted limits produce a
residual-gap report, not an unbounded attempt to force agreement.

Self-development acceptance additionally requires at least one meaningful
Ipse-authored behavior change and independently verified regression tests. Record
supervisor-authored repairs and manual interventions honestly. A report comparison
alone, copied Codex conclusions or a synthetic extension lab cannot close this gate.
Promote a new frozen runner only after independent review and checks; preserve old
reports/runtimes and validate held-out cases rather than tuning a single answer.

Use P24's external architectural challenge and OpenAI Codex Security baseline as
separate inputs; repeat architecture review for material design changes and
security review on the final candidate. The hosted security route is
preferred to adding local tooling, subject to actual account/repository access
and revision coverage. Scan status and coverage are separate; findings need
triage and fixes need regression evidence. Raw findings stay private. P24's baseline
scan completed; all applicable repairs and composition follow-ups passed their
source/platform gates. Preparation is not scored P25 execution. No recurring
monitoring is enabled and no new dependency is approved by this plan. See
[architecture validation](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
and [security execution constraints](archive/2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md#security-review-before-and-after-the-trial).

## P26: optional working and long-term memory

**Complete within the explicit P26A/P26B scope.** Implementation `108aa86` and
diagnostic-worker cleanup repair `fb4627e` pass applicable source/native/package
and exact-source hosted gates. Local causal reproduction and controlled
before/after regressions explain the strict cleanup failure; the original failed
attempts and unchanged rerun remain in the [verification record](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#macos-diagnostic-cleanup-repair-2026-10-18).
Independently selectable default-off session/task and persistent project/operator
memory ship as bundled extensions.
Explicit recall/remember/forget/export tools and commands provide bounded task
cards/facts and lexical recall. Source suppression, TTL/conflicts, derivative
inventory/collection and approved migration/import preserve lifecycle integrity.
Optional automatic recall/capture remains a separately justified adapter; it is
not enabled by this baseline. Zero-Mem is inspiration, not a selected package or
reproduced benchmark result. The [knowledge design](archive/2026-10-18-before-manual-rewrite/docs/developer/knowledge-extensions.md#research-handoff-and-deferred-production-acceptance)
owns the researched selection and deferred engine comparisons.

Acceptance: default-off parity; explicit namespace/project/operator scopes;
stable logical identity with explicit export/migration/collection across artifact
and configuration-source versions; provenance, retention/TTL and conflicts;
approved bounded writes; concurrent forget without resurrection; derivative
deletion/export and distinct history-access/redaction, journal/backup and erasure
limits; cancellation and unchanged resumed recall. No mandatory store, embedding
model, remote service or silent promotion. Keep core conversation/recovery intact
when optional memory is off. Measure quality and resources separately from
protocol correctness; document actual dependency, configuration and recovery.

The implementation follows the researched explicit-notes baseline, with no external
service, embedding model or database dependency. Domain behavior belongs in
independently selectable bundled extensions. Necessary generic host changes must
preserve legacy identities and grants; they are reviewed and tested separately.

| Increment | Deliverable | Status |
| --- | --- | --- |
| P26H1 | Operator-only, versioned logical state bindings across reviewed artifact/configuration versions; legacy namespace compatibility and scope ceilings | Complete; source/native/installed and exact-source hosted gates pass |
| P26H2 | Bounded value scans and explicit read-work allowance for useful lexical recall, with strict receipt/recovery validation | Complete; byte pages, forged/ungranted/over-limit actions and extended real-worker receipt chain pass |
| P26A | Separate default-off working and persistent memory, explicit remember/recall/forget/export, provenance, bounded lexical ranking and approvals | Complete; scope, sharing, approval, denial/cancel, selected export and inert-resume cases pass |
| P26B | Durable source suppression, TTL/conflicts, derivative inventory/collection, schema migration/import, stale-work and cached-context recovery policy | Complete explicit baseline; affected sessions require manual reviewed fresh-session recovery, not automatic history redaction |
| P26 verification | Deterministic authority/concurrency/restart/import cases, measured retrieval/resources, source/native/installed/platform checks and coherent operator/developer guidance | Complete at `fb4627e`: strict failure reproduced, native receipt loss repaired, controlled regressions and repaired-source Linux/macOS gates pass. Original negative evidence remains retained |

Stable logical storage is an explicit operator grant, never a namespace chosen by
project text or extension code. Existing journals and provider-visible history are
retained; memory deletion must state its separate recall/suppression and cached
context limits. See the [knowledge development manual](developer/knowledge-extensions.md)
for current placement and design guidance.
The [operator guide](operator/memory.md) owns configuration/retention/recovery;
the [extension contract](developer/memory.md) owns suppression and measurement limits.

## P27: optional research, graph and RAG

**Active; implementation and verification incomplete.** Independently built Corpus,
Graph and Research packages now have source and extracted-runtime protocol proofs;
the domain inference, lifecycle and held-out quality gates remain open. Build independently useful
research orchestration, graph augmentation and corpus retrieval packages on
P14/P22/P23 and selected shared knowledge contracts. Prefer explicit tools and
existing MCP adapters before hooks or services. Memory, research, graph and RAG
must remain independently configurable; enabling one does not enable the rest.
The researched proposal delivers configured research/lexical RAG before optional
embedding/graph comparisons. Extension-driven MCP effects and embeddings require
their separately reviewed generic host contracts; current value services and
one-shot text calls are not substitutes.

Acceptance: named pluggable search/fetch/store/retrieval/embedding/rerank profiles;
source/chunk/version/citation identity; bounded ingestion/traversal/retrieval;
lexical operation without mandatory embeddings; deletion propagation and stale
index policy; contradictory/stale/weak evidence; partial failures, cancellation,
budgets and no automatic replay. Evaluate algorithm quality on held-out workloads,
then separate opt-in live evidence from credential-free source/package fixtures.
No framework, database or provider is mandated. P25's findings determine delivery
order and any justified generic host enhancement before implementation selection.

Delivery keeps the complete acceptance above. Generic API work must precede the
domain operations that need it; a successful lexical fixture alone cannot close
the milestone. Preserve current SDK bounds and existing operation authority.

| Increment | Deliverable and direct verification | State |
| --- | --- | --- |
| P27H1 | Source-bound bounded result pages and explicit mixed read/effect allowance where necessary; unchanged legacy grants and pure saved-source validation | Complete for the MCP text contract at `2fe3583`; local source/native/installed and hosted Linux/macOS gates pass at `1f90178` |
| P27H2 | Approved configured MCP actions from extensions; pinned descriptors, child denial, owned cancellation and unknown-outcome recovery | Complete at `2fe3583`; real stdio/HTTP, denial, cancellation and inert recovery pass; source/installed proofs pass on hosted Linux/macOS at `1f90178` |
| P27H3 | Versioned embedding operation with selected profiles, bounded ordinary vectors, exact egress, operation-aware accounting/costs/shared budgets and no text-envelope substitution | Complete at `3e32051`; local source/macOS/installed gates and exact-source hosted Linux/macOS source/package/installed proofs pass with 768/4096-coordinate native fixtures |
| P27A | Independent research and lexical corpus packages with named interchangeable profiles, cited evidence, explicit limits, partial failures, stale-index handling and suppression | Implementation present; final lifecycle/authority/platform and quality validation open |
| P27B | Independent attributable graph, optional extraction, embedding/hybrid and rerank adapters; matched quality/resource comparisons before engine selection | Implementation present; tuning embedding integration passes, text extraction/rerank failures and matched comparisons remain open |
| P27 verification | Frozen held-out workload, zero authority/isolation/replay/resurrection failures, measured retrieval/support/citation/resources, source/native/installed checks, coherent user and contributor manuals | Open |

The [first host-contract record](archive/2026-10-19-p27-mcp-host-contracts/index.md)
retains causal regressions, independent review corrections and local verification.
It establishes approved MCP transport and result paging, not research/graph/RAG
quality. The [embedding host-contract record](archive/2026-10-19-p27-embedding-host-contracts/index.md)
retains typed native embeddings, selected profiles and operation-aware usage,
prices and shared budget coverage. Its local protocol proofs do not establish
actual model quality. Hosted H3 checks pass at `3e32051`; the domain and held-out
gates remain open.

The [independent package record](archive/2026-10-19-p27-knowledge-packages/index.md)
retains source/installed protocol evidence and controlled Research repairs. It
does not establish model quality or select an optional engine. The full frozen
held-out evaluation remains required before completion.
The [evaluation preparation record](archive/2026-10-19-p27-knowledge-packages/evaluation-preparation.md)
separates synthetic scorer checks from actual tuning outcomes. Three embedding
requests and one cited-answer request completed; three text helper requests
failed. Those failures and unknown usage remain retained. Held-out predictions
and independent semantic review are still unmeasured.

## P28: voice and realtime media

**Deferred; unimplemented. Formerly P24.** Keep the requested scope for a future
delivery; it is no longer ahead of architecture/security review or self-development.
Build on the owned text/provider and P23 accounting foundation. Start with a
chained STT → admitted text agent → TTS extension/client; then add a versioned
realtime provider/session capability for bidirectional transport, interruption,
turn control, playback acknowledgment and reconciliation of generated versus
played history.

Voice choice, STT/TTS/device adapters and UI belong in extensions/clients. Core
owns resource lifetime, admission, approvals, cancellation, flow control and
provider continuation integrity. Use a separate media data plane, ephemeral raw
audio by default, canonical transcripts/usage and explicit endpoint/device/billing
choices. Text subscription authentication does not establish audio eligibility.

Acceptance: synthetic split/slow/disconnected media, revised interim transcripts,
barge-in, stale/unplayed frames, owner death, approval waits and no-replay recovery;
source/package checks and separately recorded opt-in live account/device checks.
Evaluate maintained Elixir/Rust/OS facilities and approve/inventory external
dependencies before adoption. No codec, frontend runtime or service is selected.
See [media boundaries](archive/2026-10-18-before-manual-rewrite/docs/developer/runtime-capabilities.md#text-and-media-are-distinct-from-diagnostics).

## License transition

The operator-requested MIT → Apache-2.0 transition follows the completed P22–P25
campaign, before separately deferred P26–P28 features. Root and bundled extension
licenses now carry Apache-2.0 with the original copyright. Current contributor,
dependency, operator and developer guidance uses that license; upstream dependency
licenses, prior artifacts and historical evidence retain their own provenance.

The bundled license is part of built-in artifact identity. Older selected sessions
need their preserved runner or reviewed explicit handoff; the transition does not
rewrite saved journals or imported artifacts. The synthetic recovery boundary,
local source/native/package checks, both packaged license copies and old compiled
compatibility proofs pass. Exact `7bb642b` Linux/macOS source/native/package and
installed checks also pass after correcting a proof-fixture preparation timer;
production code and request/assertion deadlines are unchanged. This separate
transition is complete. The [verification record](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks)
owns actual receipts. No new runtime capability, dependency or service is added.

## Completed milestones P0–P22

These entries retain stable references and explain what each completed scope
established. They are historical summaries, not new implementation instructions.
Exact commands, dated failures, counts and live limitations stay in the linked
verification records. P2 originally named two milestones; they are distinguished
below as P2a and P2b without renumbering later milestones.

## P0: verify the current release path

Complete for the tested Arch host/account: source/demo/package validation,
subscription browser sign-in, natural-expiry refresh/token rotation, streamed
inference, approved tools, idle resume and logout. A permission-off error was
observed; allowance exhaustion and ineligible accounts remain unverified. Broader
host/model/account portability is not implied. See the
[P0 closure](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p0-closure-on-serenity-2026-10-15).

## P1: make everyday use clearer

Complete: line-oriented running/waiting/cancelled/finished states, EOF/queued-input
and unknown-effect recovery checks. Skills remain explicit, bounded and inert.
See [verification](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md) and [operator usage](operator/usage.md).

### Runtime identity and extension boundaries

Implemented allowlisted application/configured-provider/requested-model facts for
`/info` and model turns, with reported model identity retained separately. Aliases
and model self-descriptions cannot establish backend revisions. No keyword answer
interception or credential exposure. The historical extension proposal was
subsequently implemented within P22's documented boundaries; see
[runtime facts](../lib/ipse/runtime_info.ex) and [extension architecture](developer/extensions.md).

## P2a: automatic context compaction

Complete: validated durable checkpoints preserve user intent, host approval/action
metadata and native continuation while retaining original journals; unsafe
reduction stops explicitly. P13/P19/P21 added bounded long-turn recovery and
handoff capabilities. See [compaction](developer/context-compaction.md) and
[P2 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p2-context-compaction-2026-10-15).

## P2b: define an OS sandbox boundary

Complete for the optional Linux native profile's tested filesystem/network/process/
resource boundary. Trusted execution remains the default; requested native policy
fails closed. Mac enforcement and best-effort descendant lifetime have distinct
limits. See [sandbox contract](developer/sandbox.md),
[Linux evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p2-native-linux-sandbox-2026-10-15) and
[Mac boundary](developer/sandbox.md#macos-production-boundary).

## P3: workspace context from any directory

Complete: launch/explicit working directory, bounded scoped instruction snapshots,
provenance and deterministic resume/refresh, with coding and non-coding trials.
Shell target scope can remain unknown; instruction path checks are not an OS
sandbox. See [contract](developer/workspace-context.md) and
[evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p3-workspace-context-2026-10-15).

## P4: packaging and protocols

Complete within Linux/macOS source/archive verification and separate MCP/delegation
protocol design scope. Packages identify OS/architecture/libc and include notices;
fresh extraction checks do not establish all architectures or signing/notarization.
Windows and adversarial detached-descendant termination on Mac remain outside scope.
See [evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p4-release-verification-and-protocol-proposal-2026-10-15).

## P5: local MCP tools

Complete: explicit stdio tools, bounded descriptors/allowlists, schema validation,
full approvals, durable intent and owned transport/no-replay recovery using reused
MCP/schema packages. Source, extracted and scoped live checks are recorded in
[P5 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p5-local-mcp-2026-10-15); arbitrary servers are
not certified by the demo. See [MCP contract](developer/mcp.md).

## P6: local subagent delegation

Complete: opt-in serial local children, separate journals/approvals, bounded
context/results, parent ownership and no recursive delegation/child MCP. See
[delegation contract](developer/delegation.md) and
[P6 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p6-local-delegation-2026-10-15).

## P7: expanded MCP capability

Complete within bounded local resources/prompts and pinned independent-server
interoperability. Ordinary stdio cleanup repairs do not remove the documented Mac
detached-child limit. See [P7 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p7-expanded-local-mcp-2026-10-15)
and [second-server coverage](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#second-independent-local-mcp-server-2026-10-15).

## P8: bounded skill resources

Complete: explicit source-bound `load_skill_resource`, bounds, provenance and
inert resume; loading does not run scripts or install dependencies. See
[P8 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p8-skill-resources-2026-10-15).

## P9: parallel local subagents

Complete: opt-in two-child groups, separate approval routing, bounded scheduling,
results and cancellation. Serial remains default; P23 separately adds atomic shared
token/cost reservations. See
[P9 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p9-parallel-local-delegation-2026-10-15).

## P10: network MCP

Complete: explicitly configured MCP Streamable HTTP POST with JSON/finite SSE,
verified TLS, server-specific credentials, limits, exact approvals and no replay.
Redirects/retries, OAuth negotiation, GET subscriptions and reconnection are not
implemented. Remote cancellation is best effort. See
[contract](archive/2026-10-18-before-manual-rewrite/docs/developer/mcp.md#streamable-http-boundary) and
[P10 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p10-streamable-http-mcp-2026-10-15).

## P11: live dotsetup trial

Complete within read-only project/next-step assessment and selected Ipse follow-ups:
Bash descriptor compatibility, sandbox visibility facts and project-orientation/Git
skill guidance. Existing dotsetup edits were preserved; no dotsetup coding/deployment
or GitHub adapter trial was performed. Multi-repository read roots remain separate.
See [comparison](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p11-live-project-assessment-2026-10-15) and
[repairs](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#native-bash-and-visibility-repair-2026-10-15).

## P12: task tracker coding trial

Complete in a separate app workspace: forms/SQLite CRUD, validation, persistence,
independent review and layout checks. Elixir was imposed by the test operator, so
this did not prove neutral stack selection. Long-turn limitations led to P13.
See [P12 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p12-task-tracker-coding-trial-2026-10-15).

## P13: long-turn compaction and general-purpose trials

Complete: safe long-turn checkpoints/diagnostics, a neutral-stack task tracker
(Ipse chose Python/Flask) and a source-backed non-coding task. Ipse's implementation
language does not constrain target workloads. These are bounded trials, not
unrestricted task coverage. See [compaction](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p13-long-turn-compaction-2026-10-16),
[coding](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p13-neutral-stack-coding-trial-2026-10-16) and
[non-coding](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p13-non-coding-document-trial-2026-10-16) evidence.

### First supervised self-development trial

Complete: frozen installed Ipse authored shared operator skill discovery in a
separate candidate, with independent checks, approved effects and idle resume.
The trial exposed and repaired bundled launcher environment contamination of
system Mix. See [integration evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#shared-skills-questions-configuration-and-profiles-integration-2026-10-16).
Later P18/P21/P22 trials broadened this supervised evidence; P25 proposes a larger
comparative evaluation without claiming unattended self-development.

## P14: bounded deep research

Complete: inert research skill, configured provider-agnostic MCP retrieval and
bounded durable source/claim ledger/export, plus an independently checked live
primary-source trial. No mandatory search service, recursive research engine or
production knowledge backend. See [research contract](developer/research.md) and
[five-stage evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P15: scoped configuration and shared operator skills

Complete: bounded versioned JSON/provenance and trusted scoped selections;
project > Ipse user > shared operator `~/.agents/skills` > bundled precedence.
Project text cannot enable executable extensions, change billing or grant effects.
See [operator configuration](operator/configuration.md),
[developer contract](developer/configuration.md) and
[integrated evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P16: explicit model profiles and task routing

Complete: named profiles and main/routine/review roles, supported provider settings,
explicit child selection and credential/native-payload isolation. A stronger
subscription main/local Ollama child trial passed; no hidden billing/provider
fallback or automatic summary routing is claimed. See
[profiles](operator/model-profiles.md) and
[integrated evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P17: structured operator questions

Complete: validated single-choice, multiple-choice and text answers, explicit
submission, durable waiting/resume, cancellation/EOF/headless behavior and separate
approval authority. Child questions and MCP elicitation remain unsupported.
See [contract](developer/operator-questions.md) and
[integrated evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P18: supervised self-development on the operator's Mac

Complete: frozen-runner `sessions --json` change, structured clarification,
independent local Mac/native/package checks, bounded review and hosted Linux/Mac
verification before PR #1 merged. Review budget exhaustion, supervisor assistance
and safe context refusal remain recorded. See the
[Mac runbook](operator/self-development.md) and
[local evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p18-macos-supervised-self-development-evidence).

## P19: long-session diagnosis and recovery

Complete: content-free context/timing diagnostics and explicit reviewed handoff
without silently trimming native continuation or intent. Synthetic fixtures
reproduce the failure shape, not a private original Mac transcript. See
[observability contract](developer/observability.md),
[operator recovery](operator/recovery.md) and
[P19 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p19-diagnosis-and-explicit-recovery).

## P20: repeatable supervised self-development

Complete: inert bundled self-development skill/resources, credential-free real
Session fixture and supervised live use. Existing approvals, profiles and journals
supply the boundaries; there is no mandatory workflow engine. See
[P20 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p20-reusable-self-development-skill).

## P21: larger self-development trial on Serenity

Complete: Ipse-authored fresh-chat handoff import from a frozen P20 runner,
independent Linux/package checks, separate bounded live review and hosted Linux/Mac
checks. Repeated orientation needed supervisor narrowing; a reviewed manual handoff
and unchanged idle resume were exercised. See
[P21 evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p21-supervised-serenity-trial-and-independent-checks).

## P22: extension scaffold and lifecycle hooks

Complete within the SDK contract at `de073ba`: immutable artifacts, explicit scoped
trust/selection, independent workers, typed hooks/invocations/host calls, state,
context/evidence, services, questions, approved actions, owned jobs, source-bound
history/events/feeds and private visible-text channels. Diagnostics have independent
off/local/export controls, bounded retention and synthetic developer tracing.
Two shipped prompt/presentation examples are default-off.

The [architecture/comparison](developer/extensions.md),
[adoption scenarios](developer/extension-scenarios.md) and
[lifecycle coverage audit](archive/2026-10-18-before-manual-rewrite/docs/developer/lifecycle-events.md#supported-lifecycle-coverage)
define supported and unsupported seams. Hooks share lifecycle occurrence identity
with notifications/feeds/jobs while retaining distinct private-view, ordering and
effect authority. Remote event bridges, nested effectful services, automatic
installers/builders and idle hot activation remain explicit future enhancements.

The separate [memory/workflow lab](developer/extension-proof.md) passed 41 synthetic
source/installed assertions against frozen core `3b0ef78`, without core edits or
rebuilding the installed archive. A separately reviewed live extension-only change
and hosted Linux/Mac checks closed P22's gates. This proves the exercised SDK
contracts, not production graph/retrieval quality; later core changes require
fresh compatibility evidence. See
[completion evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#supervised-extension-only-trial-2026-10-17).
