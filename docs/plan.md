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
RAG, including the operator's Zero-Mem inspiration. P26's explicit-note baseline
is complete at `25f1d8e` after external and whole-milestone internal review,
reproduced repairs and passing local and exact-source hosted checks. The
[remediation record](archive/2026-10-19-p26-remediation/index.md) preserves the
findings, failures and scoped acceptance. P27 research, graph and RAG development
is active. External whole-milestone review repairs have scoped passing checks;
quality evaluation, final integrated review and candidate verification remain open;
media remains deferred to P28. External services remain configurable; no third-party
engine, database or mandatory backend is selected.

| Milestone or gate | Current state | Next result |
| --- | --- | --- |
| [P23: accounting and budgets](#p23-usage-cost-reporting-and-budget-controls) | Complete within selected scope | Preserve accounting through the trial |
| [P24: architecture/security readiness](#p24-independent-architecture-validation-and-baseline-security) | Complete for supervised P25 at `375e607`; accepted limits recorded | Refresh affected validation after trial changes |
| [P25: comparative self-development](#p25-comparative-research-and-supervised-self-development) | Complete within declared supervision/assistance at `3307563`; security findings triaged and corrected scopes verified | Preserve frozen evidence; select a later production increment separately |
| [P26: memory baseline](#p26-optional-working-and-long-term-memory) | Complete within explicit-note scope at `25f1d8e`; review repairs and local/hosted gates pass | Preserve lifecycle, authority and documented retention limits |
| [P27: research, graph and RAG](#p27-optional-research-graph-and-rag) | Active; review repairs verified within their scopes; no engine selected | Finish holistic review and final candidate gates, then frozen held-out quality and matched resources |
| [P28: voice and media](#p28-voice-and-realtime-media) | Deferred; unimplemented | Explicit media contracts and later device/service validation |
| [Apache-2.0 transition](#license-transition) | Complete; local and hosted `7bb642b` checks pass | Preserve bundled identity/recovery and third-party license boundaries |

The requested P22–P25 campaign and separate Apache-2.0 transition are complete
within their documented scopes. P26 remediation is complete; P27 is active and
P28 remains deferred. Preserve P25's frozen
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
[configured cost implementation](developer/usage-accounting.md#calculate-a-synthetic-rate) and
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
children and [extension model operations](developer/extension-effects.md#request-bounded-text-inference)
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

**Complete within the explicit-note scope at `25f1d8e`.** The
[2026-10-19 review](archive/2026-10-19-p26-remediation/index.md) found model
inspection outside expiry/dependency filtering, lossy backup/restore, a missing-source
collection crash and an admission/test gap. These and the internal findings were
reproduced and repaired without weakening suppression or approval. A generic locked
write deadline refuses approvals crossing the existing note's expiry. The
[second external review](archive/2026-10-19-p26-remediation/review-2.md) accepts the
P26 code scope, identifies one low-severity failed-receipt validation gap, and
confirms that the run failed in inherited P27 60-second fixtures. The receipt
correction and all 60 focused tests pass with an explicit 60,000-ms deadline.
After measuring the accumulated work, the independent suppression Session cases
and CLI refusal checks now have separate fixture units; the full seven-variant
current-source integration case remains. A fresh three-reviewer adversarial
review of the entire P26 milestone found no actionable defect. Refreshed full,
native, installed and manual-example checks pass. Exact-source hosted
[run 39309132023](https://github.com/lexlapax/ipse/actions/runs/39309132023)
passes both Ubuntu and macOS with Elixir 1.18.5 / OTP 27, including package and
installed proofs. A forced Linux staging delay also confirms refusal before
publication. The user authorized this internal review and repair followed by P27;
no further external dispatch or CI waiver was required. The remediation record
owns the complete receipts and limits.

Implementation `108aa86` and diagnostic-worker cleanup repair `fb4627e` retain
their applicable source/native/package and exact-source hosted evidence. Local causal reproduction and controlled
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
| P26H3 | Generic optional State write deadline, selected by the extension and enforced under the existing CAS lock without interpreting note schemas | Complete; delayed-approval remember/import, live controls, failed-receipt recovery and forced staging delay pass; hosted source/package gates pass |
| P26A | Separate default-off working and persistent memory, explicit remember/recall/forget/export, provenance, bounded lexical ranking and approvals | Complete; admission, exact backups and real CLI examples pass; external findings repaired and full milestone internally reviewed |
| P26B | Durable source suppression, TTL/conflicts, derivative inventory/collection, schema migration/import, stale-work and cached-context recovery policy | Complete; visibility, legacy migration and delayed-expiry checks pass; fresh-session recovery and retained-history limits remain part of the contract |
| P26 verification | Deterministic authority/concurrency/restart/import cases, measured retrieval/resources, source/native/installed/platform checks and coherent operator/developer guidance | Complete; 60 focused and 1,167 full tests pass locally; exact-source hosted Ubuntu/macOS source and installed gates pass; prior Linux native-enabled evidence retained with its source identity |

Stable logical storage is an explicit operator grant, never a namespace chosen by
project text or extension code. Existing journals and provider-visible history are
retained; memory deletion must state its separate recall/suppression and cached
context limits. See the [knowledge development manual](developer/knowledge-extensions.md)
for current placement and design guidance.
The [operator guide](operator/memory.md) owns configuration/retention/recovery;
the [extension contract](developer/memory.md) owns suppression and measurement limits.

## P27: optional research, graph and RAG

**Active after P26 acceptance; implementation and verification incomplete.** The
[continuation record](archive/2026-10-19-p27-knowledge-packages/continuation.md)
preserves the stopped comparison, evidence identities, protocol defects, CI
failures and remaining tasks. External P26 review and subsequent internal review,
repairs and verification are complete; the user authorized proceeding to P27,
with similar review before P27 completion.
Reconcile affected shared-host verification first; never replay the interrupted
comparison automatically.
The [resumption record](archive/2026-10-19-p27-knowledge-packages/resumption.md)
tracks the repaired inference allowance, failed-answer rows and rerank identity,
plus complete-result transport and the knowledge consumers' verification gates.

Independently built Corpus,
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

The user fixed final quality acceptance on 2026-10-20: select a strategy that
individually meets at least 90% answer support and 95% citation support. Publish
all seven strategies and all 350 first outcomes; strategies below either target
do not qualify for selection. Aggregate results remain diagnostic and cannot
substitute for the selected strategy's scores. This direction does not change
historical scores or waive safety, resource, structural or documentation gates.
The schema-bound evaluator now implements that declared qualification policy,
including complete first-outcome publication and applicable independent review.
Its [source/installed fixture verification](archive/2026-10-20-p27-quality-remediation/index.md#bind-evaluation-outputs-and-individual-qualification)
establishes protocol behavior. Final private-workload validation, matched resources
and the engine decision remain open after structural readiness.

Delivery keeps the complete acceptance above. Generic API work must precede the
domain operations that need it; a successful lexical fixture alone cannot close
the milestone. Preserve current SDK bounds and existing operation authority.

| Increment | Deliverable and direct verification | State |
| --- | --- | --- |
| P27H1 | Source-bound bounded result pages and explicit mixed read/effect allowance where necessary; unchanged legacy grants and pure saved-source validation | Complete for the MCP text contract at `2fe3583`; local source/native/installed and hosted Linux/macOS gates pass at `1f90178` |
| P27H2 | Approved configured MCP actions from extensions; pinned descriptors, child denial, owned cancellation and unknown-outcome recovery | Complete at `2fe3583`; real stdio/HTTP, denial, cancellation and inert recovery pass; source/installed proofs pass on hosted Linux/macOS at `1f90178` |
| P27H3 | Versioned embedding operation with selected profiles, bounded ordinary vectors, exact egress, operation-aware accounting/costs/shared budgets and no text-envelope substitution | Complete at `3e32051`; local source/macOS/installed gates and exact-source hosted Linux/macOS source/package/installed proofs pass with 768/4096-coordinate native fixtures |
| P27H4 | Opt-in bounded complete-result publication for original top-level tools/commands, historical receipt reads, strict source closure and unchanged ordinary SDK bounds | Complete at `fb980a0`; whole-milestone review, local 1,248-test baseline, Serenity 1,265-test native-enabled suite, exact 4 MiB and complete-domain source/installed proofs pass. Exact-source hosted Ubuntu/macOS matrix passes |
| P27H5 | Explicit schema-bound extension inference, native provider admission, approval and saved-result validation, plus independently selected domain output contracts | Host contract and domain selections verified; corrected-source macOS/native-enabled Linux suites, source/package/installed proofs, unchanged precompiled SDK-1 modes and three actual synthetic native requests pass. Plan-three evaluator integration and individual qualification pass both scoped platform checks and complete source/installed synthetic comparisons. Semantic quality remains open |
| P27A | Independent research and lexical corpus packages with named interchangeable profiles, cited evidence, explicit limits, partial failures, stale-index handling and suppression | Review repairs and corrected-source fixture/platform/installed checks pass; held-out quality acceptance remains open |
| P27B | Independent attributable graph, optional extraction, embedding/hybrid and rerank adapters; matched quality/resource comparisons before engine selection | Review defects, compact model contracts and shared original-byte excerpts verified through source/platform/installed checks; corrected-source matched quality/resource comparisons and selection remain open |
| P27 verification | Frozen held-out workload, zero authority/isolation/replay/resurrection failures, measured retrieval/support/citation/resources, source/native/installed checks, coherent user and contributor manuals | Open; scoped repair reviews/checks pass. The fresh exposed diagnostic completes twelve first rows but retains five failed/partial rows and classification defects. Final holistic review, fresh held-out quality, resource/selection and candidate gates remain |
| P27 structural readiness | Holistic consolidation of the entire codebase and all user/developer documentation; migrate callers, builds, tests, packaging and CI together | Selected implementation units and [whole-manual consolidation](archive/2026-10-21-p27-manual-consolidation/editorial-review.md) verified within scope. Final holistic adversarial review and candidate gates remain before the private-evaluation freeze |

The [shared verification change](archive/2026-10-20-p27-shared-verification/index.md)
is verified against unchanged runtime source on macOS and native-enabled Linux,
with fresh packages, the source and installed command matrix, and complete
synthetic native comparisons and authority-loss controls in both modes. It
consolidates verification setup and shared fixtures and repairs the public source
Research CLI and model-service terminal cleanup. This completes that structural
unit; remaining ownership changes, actual-model quality, final private evaluation
and engine selection remain open.

The subsequent [fixed-context answer diagnostic](archive/2026-10-20-p27-quality-remediation/index.md#reject-a-fixed-context-instruction-trial)
retains two fresh eight-request CPU-only runs on exposed material. Structured
output succeeds, but semantic and citation errors persist. A general instruction
revision produced mixed results and was reverted. No quality gain or private
acceptance is claimed; inference-policy investigation and structural work remain.

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

The [complete comparison declaration](developer/knowledge-evaluation.md#declare-the-complete-comparison)
generates all seven strategies and explicit budgets without opening inputs.
Its [initial capacity record](archive/2026-10-19-p27-knowledge-packages/benchmark-declaration.md)
and [whole-run/identity controls](archive/2026-10-19-p27-knowledge-packages/comparison-capacity.md)
retain count, output, approval and source-mapping failures. The controlled gateway
and approval policy now use declared finite bounds. Dataset URIs bind complete
typed source identity; duplicate source generations refuse. Research obeys its
body/time/output bounds. Knowledge packages now preserve complete SDK-2 results
and consumers materialize them before use; invalid aggregates or insufficient
journal capacity still refuse. The [saved-comparison capacity repair](archive/2026-10-19-p27-knowledge-packages/serialized-capacity.md)
aligns bounded prediction/review readers with valid complete synthetic grids;
first attempts and hash-before-reference checks remain unchanged.
The [domain-result record](archive/2026-10-19-p27-knowledge-packages/complete-domain-results.md)
separates these checks from the remaining quality gates.
Its [platform record](archive/2026-10-19-p27-knowledge-packages/platform-verification.md)
binds local, native-enabled Serenity and hosted Ubuntu/macOS checks to `fb980a0`.
The [fourteen-area audit](archive/2026-10-19-p27-knowledge-packages/requirement-audit.md)
maps protocol evidence and remaining acceptance without treating fixtures as
quality measurements.
Declaration and synthetic fixtures do not close the clean freeze, held-out or
selection gates.
The [memory/knowledge selection proof](archive/2026-10-19-p27-knowledge-packages/selection-independence.md)
checks nine real Session combinations, zero idle/resume dispatch, separate note
and evidence stores, independent forget and refusal at the combined catalog
bound. Those protocol checks do not measure semantic quality.
The [storage lifecycle exercise](archive/2026-10-19-p27-knowledge-packages/storage-lifecycle.md)
adds explicit post-prediction suppression/collection, exact page approvals and
per-projection inventories. Its controlled fixtures remain separate from the
required held-out resource comparison.
The [review preparation workflow](developer/knowledge-evaluation.md#prepare-independent-review-from-finalized-predictions)
verifies the complete hashed grid before references, builds blinded review
packets and separates literal integrity from independent semantic verdicts.
Its [controlled verification](archive/2026-10-19-p27-knowledge-packages/review-preparation.md)
also checks aggregate quality gate reporting. Actual held-out judgments and
engine selection remain open.
The [evaluation preparation record](archive/2026-10-19-p27-knowledge-packages/evaluation-preparation.md)
separates synthetic scorer checks from the initial tuning outcomes. The later
[model workflow record](archive/2026-10-19-p27-knowledge-packages/model-workflows.md)
retains the intervening failures, causal repairs and accounted extraction/rerank
trials. The [orchestration record](archive/2026-10-19-p27-knowledge-packages/evaluation-orchestration.md)
adds matched public-Session fixtures, explicit time selection, suppression
controls and separate ranked/answer-context citations. The [domain lifecycle
record](archive/2026-10-19-p27-knowledge-packages/domain-lifecycle.md) covers
State-backed delayed projection/forget races, interrupted provider IO, quota,
malformed/unavailable responses and idle resume in source and installed execution.
The [query completeness record](archive/2026-10-19-p27-knowledge-packages/query-completeness.md)
retains controlled exclusion, unfinished-ingestion and traversal-limit regressions;
these protocol checks do not replace held-out quality evaluation.
The [evaluation preflight record](archive/2026-10-19-p27-knowledge-packages/evaluation-preflight.md)
covers complete selection checks before dataset reads and matching CLI failure
status, plus full canonical usage export. The [resource accounting record](archive/2026-10-19-p27-knowledge-packages/resource-accounting.md)
adds query/phase clocks and request/budget reconciliation. The
[storage inventory record](archive/2026-10-19-p27-knowledge-packages/storage-inventory.md)
adds strict retained-page reachability and draft/orphan/tombstone measurements.
The full resource comparison, exact peak workload-charged RAM measurements and held-out
evaluation remain open. The user requires exact peaks; periodic samples alone
cannot satisfy that gate. The [native accounting investigation](archive/2026-10-19-p27-knowledge-packages/resource-memory-grounding.md)
reproduces a completed Port child's missing high water in an outer Elixir receipt
on macOS and Linux. An outer-only wrapper cannot establish complete coverage.
The initial simultaneous-memory investigation led to the
[aggregate design](archive/2026-10-19-p27-knowledge-packages/aggregate-memory-design.md), which
selects fresh complete cells under a whole-run scope. The first
[native collector](archive/2026-10-19-p27-knowledge-packages/aggregate-memory-native.md)
implements owned admission, birth-before-exec and lifetime/interval counters;
ten synthetic Linux controls and local source/native/installed checks pass.
The [measured sequencer](archive/2026-10-19-p27-knowledge-packages/measured-sequence.md)
adds fresh preparation, cell and finalization stages under the whole counter.
Six live Linux cases and six native protocol tests cover retained attempts,
failed-but-closed stages, collector loss and writerless descriptor FIFOs.
These isolated controls precede the complete integration proof below and do not
establish real comparison coverage.
The [optional listener record](archive/2026-10-19-p27-knowledge-packages/owned-listener.md)
documents direct-child loopback ownership controls and a later reproduced
PID/procfs mismatch. Its repair refuses an inherited ancestor procfs before
server execution; ordinary stdio and a nested namespace with its own procfs
remain supported. This generic capability does not establish complete model
service or benchmark integration.
Charged memory, summed RSS and device memory must not be conflated.
After reconsidering the measurement design, the user selected exact
workload-charged RAM with an optional Linux benchmark backend. This includes
cache and kernel charges under the declared `linux_memcg_charged_peak_bytes_v1`
subject. The fresh comparison uses the approved CPU-only policy. Existing
synthetic native controls establish counter behavior; complete integration is
verified below, while the real comparison remains open. The experiment
specification must remain portable. Resolved paths, runtime identities and observed host configuration
belong to each fresh execution's manifest and provenance; Serenity is a verification
host rather than a requirement for the experiment. Existing systemd user tools
remain an approved optional benchmark-launch dependency. Ordinary Ipse operation
does not require the Linux measurement backend.
The [portable experiment foundation](archive/2026-10-19-p27-knowledge-packages/portable-experiment.md)
separates content-based declarations from fresh local execution seals and derives
the complete fourteen-cell schedule with fixed original allowances. These inert
identity operations do not claim attempts or start measured work. Version-two
seals refuse legacy prediction entry points. The measured entry owns complete
execution; v2 review and scoring additionally require a retained post-exit audit
digest before label access.
The [owned model-service component](archive/2026-10-19-p27-knowledge-packages/owned-model-service.md)
adds fresh private runtime/cache copies, listener admission before HTTP, one
guarded full-work callback and separate service/cleanup outcomes. Its synthetic
Linux source and installed controls pass. The
[complete measured integration](archive/2026-10-19-p27-measured-integration/index.md)
binds that selection, input location, permanent native authority and finite
deadlines into a fresh seal. It runs preparation, fourteen complete cells and
finalization under the whole-population counter, then audits first predictions,
accounting and distinct peak subjects before admitting labels. Complete synthetic
source and installed 350-row exercises and five integrated loss controls pass;
macOS passes 1,294 source and 30 native tests, and Linux passes 1,333 tests with
native sandbox enforcement enabled. Package, installed, demo and manual checks
pass locally. The exact-source
[hosted run at `81a4387`](https://github.com/lexlapax/ipse/actions/runs/39375224043)
passes Ubuntu, including the independent source and installed proofs. macOS fails
a memory test's wall-clock expiry precondition before approval. The
[retained failure and repair](archive/2026-10-19-p27-measured-integration/ci-expiry-wait.md)
preserve the expiry assertions and bound the condition wait. The corrected
`f2bfc8d` [hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39377288100)
passes all Ubuntu and macOS gates. Later whole-P27 review reproduces depth-bound
completeness and durable embedding-selection gaps. The
[corrective increment](archive/2026-10-20-p27-selection-corrections/index.md)
also repairs explicit reindexing after a reported-model change. It passes whole
source suites, native and installed checks on macOS and Linux, with current
manuals and no remaining findings in bounded internal follow-up reviews.
The earlier green matrix does not cover these corrections. Their exact `93f71ad`
[hosted run](https://github.com/lexlapax/ipse/actions/runs/39384645172) fails two
macOS fixture waits and cancels Ubuntu through fail-fast. The separate
[fixture-budget correction](archive/2026-10-20-p27-ci-fixture-waits/index.md)
reproduces a legal callback exceeding the three-second observer and gives the
combined CLI scenario an explicit two-minute test watchdog. Runtime deadlines and
behavior assertions remain intact. All 77 affected tests pass on macOS and Linux;
the two changed paths pass again in the main checkout. The exact `914bc0a`
[hosted run](https://github.com/lexlapax/ipse/actions/runs/39392520309) passes Ubuntu.
macOS passes its source suite, native checks, package and early installed proofs,
then GitHub cancels the final knowledge proof at the outer 30-minute job limit.
The [job-budget correction](archive/2026-10-20-p27-ci-job-budget/index.md) gives
the complete procedure a finite 45-minute budget. Its `1e31e5b` macOS job fails
earlier at native-copy fixture directory creation. The separate
[fixture identity repair](archive/2026-10-20-p27-native-fixture-identity/index.md)
reproduces equal-clock collisions and adds a test-only atomic ordinal. It retains
all native copy assertions. The exact `3605ac1`
[hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39399838296)
passes Ubuntu and macOS. The same test-only naming repair also covers Bound's
Linux fixture constructor at `d97a765`; its exact
[hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39406193501)
passes both platforms, including native, package and independent installed
proofs. These results cover the committed fixture repairs. The later
resource-join, review-binding and product corrections have their own exact-source
receipt below.
The historical fixture slowdown cause remains unproven.
The [subsequent whole-source review](archive/2026-10-20-p27-whole-source-review/index.md)
reproduces source-import capacity, time-qualified fact retention, finite float32
and compatible-positive relationship defects. Its follow-up finds a concurrent
root-admission race. The corrective increment uses a generic conditional State
put and an explicitly selected MCP v2 contract, preserves existing storage formats
and v1 reads/updates, and documents the inherited remote snapshot ceiling. Internal
review findings are repaired. The corrected `b9370fb` increment passes 1,324 macOS
source tests, with one skipped and 36 excluded, and source/installed knowledge,
complete-result and MCP proofs. The exact code inventory remains unchanged
through the full baseline. Its exact
[hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39440053471)
passes Ubuntu and macOS, including native, package and installed proofs. The
[historical admission record](archive/2026-10-20-p27-historical-admission/index.md)
retains the separate original-first audit, strict supplemental checks and native
tamper proof. The earlier frozen comparison completes 350 rows with confirmed
cleanup and passes admission to independent blinded review. Its
[saved-output quality result](archive/2026-10-20-p27-historical-admission/quality.md)
is negative: 28% support accuracy, 423/583 supported measured citation pairs and
four unmeasured pairs. No engine is selected. Corrected-source quality/resource
evidence and untouched held-out requirements remain open. The
[external whole-P27 review](archive/2026-10-20-p27-external-review-r1/index.md)
of `b9370fb` reports no critical or high-severity safety defect, but returns twelve
code findings and five documentation findings. Repairs address hybrid overlap,
atomic remote readable capacity, corpus-grounded scoring, actual fact packing,
encoded export, listener admission and the remaining bounded contract gaps.
Two independent whole-milestone reviews found two further defects in graph query
capacity and completed Research responses. Both are repaired, and both follow-up
reviews report no new actionable finding. Integrated verification passes against
the same frozen 460-file runtime/test inventory: macOS has 1,344 passing tests
plus 30 focused native tests; Linux has 1,383 passing tests with native sandbox
enabled. Both pass source, package and installed domain/host proofs. The repair
record retains source and package hashes, controller recovery and coverage limits.
The older comparison does not establish quality for the new product
corrections; exposed inputs are now diagnostic material.
Final validation uses a new independently authored private 50-question workload,
with answers sealed until predictions are frozen. The earlier questions remain
tuning data.
The [sealed-answer verification record](archive/2026-10-20-p27-sealed-evaluation/index.md)
retains the detached-answer contract, repaired legacy-envelope acceptance and
clear independent follow-ups. The frozen implementation passes macOS's
1,357-test suite, 93 focused Linux integration tests and separate 350-row
synthetic source and installed-package measured proofs. Linux's full suite was
not rerun for that increment. The authoring and audit-access controls establish
no real-model quality result. A new independently authored private workload now
has a [metadata-only commitment](archive/2026-10-20-p27-quality-remediation/private-workload.json):
fifty questions across two projects and 22 documents. A separate independent
semantic review checks all fifty with no findings and unchanged hashes. The
implementer has received no corpus, questions or answers. Release remains gated
on the final code/configuration freeze, and answers stay withheld through the
first-prediction and measured-audit freeze. Tuning, whole-codebase consolidation
and final quality/resource acceptance remain open.
The [quality-remediation record](archive/2026-10-20-p27-quality-remediation/index.md)
tracks subsequent work. Its diagnostic increment retains bounded Session failure
codes without error text; nine Session and 24 runner fixtures pass. It does not
establish the cause of old timeouts or any new model-quality result.
Subsequent changes use exact unique extraction quotes, short model output IDs and
whole admitted answer citations with explicit omission coverage. Both independent
reviews report no new actionable finding. The same frozen runtime/test inventory
passes macOS's 1,349-test suite and 30 focused native tests, and Linux's
1,388-test native-enabled suite. Both source/package/installed proof sets pass;
the quality-remediation record retains hashes and exclusions. These changes
establish no new held-out quality or resource result.
The subsequent [cited-claim answer repair](archive/2026-10-20-p27-quality-remediation/index.md#derive-answer-text-from-cited-claims)
removes independently generated answer prose. The adapter derives material text
from the unchanged ordered claims and preserves the model's classification.
Both independent reviews report no actionable finding. Its frozen 461-file
runtime/test inventory passes macOS's 1,363-test suite and Linux's 1,402-test
native-enabled suite, plus Linux source and installed 350-row synthetic measured
proofs. The record distinguishes matching implementation bytes from later
editorial documents, overlapping focused tests and unchanged historical readers.
The subsequent [shared-excerpt repair](archive/2026-10-20-p27-quality-remediation/index.md#preserve-complete-chunks-and-share-excerpt-selection)
keeps complete chunks within the existing citation limit and applies one
query-aware original-byte policy only to longer chunks. Independent reviews
report no actionable finding. The same frozen 461-file implementation passes
macOS's 1,369-test suite and Linux's 1,408-test native-enabled suite, plus four
source/installed proof pairs and package checks on both platforms. Its exposed
73-of-73 literal span containment is independent of ranking and semantics; it
does not establish model quality. A separately declared
[exposed diagnostic](archive/2026-10-20-p27-quality-remediation/index.md#retain-the-complete-excerpt-diagnostic)
then completes all twelve first rows with confirmed service cleanup: seven `ok`,
four `partial` and one `failed`. Output-shape refusals, extraction deadlines and
classification defects remain. Further quality repair, structural implementation
and final private evaluation remain open.
The subsequent [structured model-call contract](archive/2026-10-20-p27-quality-remediation/index.md#bind-structured-output-to-approved-model-actions)
preserves text version 1 and adds explicitly selected schema-bound version 2.
Knowledge extraction and rerank opt in separately. Both corrective reviews are
clear after a quote-heavy request-bound repair. The same frozen 462-file inventory
passes macOS's 1,383-test suite and Linux's 1,422-test native-enabled suite, five
knowledge source/installed proof pairs and all four model-call modes using an
unchanged precompiled SDK-1 artifact. Three synthetic native first requests pass
with retained usage and confirmed cleanup. These checks establish compatibility,
not semantic quality or a resource comparison. That snapshot's evaluator plans used their original text contract. The later
[plan-three integration](archive/2026-10-20-p27-quality-remediation/index.md#bind-evaluation-outputs-and-individual-qualification)
implements explicit schema and individual qualification; private release still
requires final readiness and a fresh freeze.
The selected-runtime CPU compatibility proof passes two real explicit requests,
with complete accounting and confirmed cleanup. It establishes no quality or
exact memory result. The superseded `f2bfc8d` comparison was intentionally stopped
after 25 completed rows. It has no complete audit and must never be resumed or
replayed. Its first cell's native receipt also reports residual descendants and
incomplete measurement despite domain closure. The
[native population correction](archive/2026-10-20-p27-native-drain/index.md)
retains that result and the separate loaded diagnostic. It permits a fixed
two-second natural tail within the original deadline, keeps authority live
through the terminal decision and binds version-two receipts to the declared
completion policy. Both internal reviewers' reproduced races are corrected.
Final macOS source/native/package checks pass, as do Linux's 1,345-test
native-enabled suite, twelve drain and four terminal controls, complete source
and installed 350-row synthetic proofs and five integrated authority controls.
A fresh corrected CPU comparison, semantic review and resource/quality acceptance
remain open. Historical attempts are never upgraded or replayed.
The inherited combined-fixture timeout is repaired with independent
test units and unchanged deadlines/assertions; the exact-source `25f1d8e`
[hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39309132023)
passes on both platforms. The later exact `21d710c` run passes Ubuntu and fails
macOS in CLI aggregate-deadline and resumed MCP readiness assumptions. The
portable-foundation record retains both failures and their controlled repairs;
the corrected `75b7077` [hosted run](https://github.com/lexlapax/ipse/actions/runs/39362693472)
passes all source and installed steps on Ubuntu and macOS. The older
append-timeout negative remains unexplained.
Successful tuning and scripted provider responses do not establish quality.
Corrected-source held-out predictions, independent semantic review and the complete
resource comparison remain open.

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
handoff capabilities. See [compaction](developer/workspace-context.md#plan-a-reduction-at-the-model-boundary) and
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
[profiles](operator/configuration.md#reuse-a-named-model-profile) and
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
[adoption scenarios](developer/extensions.md#trial-an-independently-built-package) and
[lifecycle coverage audit](archive/2026-10-18-before-manual-rewrite/docs/developer/lifecycle-events.md#supported-lifecycle-coverage)
define supported and unsupported seams. Hooks share lifecycle occurrence identity
with notifications/feeds/jobs while retaining distinct private-view, ordering and
effect authority. Remote event bridges, nested effectful services, automatic
installers/builders and idle hot activation remain explicit future enhancements.

The separate [memory/workflow lab](developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab) passed 41 synthetic
source/installed assertions against frozen core `3b0ef78`, without core edits or
rebuilding the installed archive. A separately reviewed live extension-only change
and hosted Linux/Mac checks closed P22's gates. This proves the exercised SDK
contracts, not production graph/retrieval quality; later core changes require
fresh compatibility evidence. See
[completion evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#supervised-extension-only-trial-2026-10-17).
