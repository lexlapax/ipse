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
findings, failures and scoped acceptance. P27 research, graph and RAG is complete
within its optional-package scope. Whole-milestone review repairs, consolidation,
final-code platform/installed checks, held-out review, publication and acceptance
audit pass. Hybrid is selected as the qualifying reference configuration;
media remains deferred to P31. External services remain configurable; no third-party
engine, database or mandatory backend is selected.

The next sequence turns the verified harness into an operator-facing product:
P28 operator usability and release readiness, P29 a provider registry with
OpenRouter and Gemini, and P30 an advisory decision-engine contract. Voice and
media is renumbered P31 and remains deferred; archived records call it P28.
P28 and P29 are selected for implementation and auditor handoff preparation.
P30 remains proposed. Each milestone keeps its own acceptance evidence.

| Milestone or gate | Current state | Next result |
| --- | --- | --- |
| [P23: accounting and budgets](#p23-usage-cost-reporting-and-budget-controls) | Complete within selected scope | Preserve accounting through the trial |
| [P24: architecture/security readiness](#p24-independent-architecture-validation-and-baseline-security) | Complete for supervised P25 at `375e607`; accepted limits recorded | Refresh affected validation after trial changes |
| [P25: comparative self-development](#p25-comparative-research-and-supervised-self-development) | Complete within declared supervision/assistance at `3307563`; security findings triaged and corrected scopes verified | Preserve frozen evidence; select a later production increment separately |
| [P26: memory baseline](#p26-optional-working-and-long-term-memory) | Complete within explicit-note scope at `25f1d8e`; review repairs and local/hosted gates pass | Preserve lifecycle, authority and documented retention limits |
| [P27: research, graph and RAG](#p27-optional-research-graph-and-rag) | Complete; all acceptance tasks closed within optional-package scope; hybrid qualified and selected | Preserve versioned evidence and explicit configuration; evaluate new workloads independently |
| [P28: operator usability and release](#p28-operator-usability-and-release-readiness) | Selected; implementation in progress | First-run setup, environment diagnosis, actionable errors and a tagged, installable release |
| [P29: provider registry, OpenRouter and Gemini](#p29-provider-registry-openrouter-and-gemini) | Complete at `9c5eb6a`; local/native/installed and hosted Ubuntu/macOS pass | Preserve explicit routing, private continuation and honest accounting; independent completeness audit pending |
| [P30: decision engines](#p30-advisory-decision-engines) | Proposed | Typed closed-answer contract, fixture engines, then OpenAI Decisions and SystemOne-compatible adapters |
| [P31: voice and media](#p31-voice-and-realtime-media) | Deferred; unimplemented; P28 in archived records | Explicit media contracts and later device/service validation |
| [Apache-2.0 transition](#license-transition) | Complete; local and hosted `7bb642b` checks pass | Preserve bundled identity/recovery and third-party license boundaries |

The requested P22–P25 campaign and separate Apache-2.0 transition are complete
within their documented scopes. P26 remediation and P27 are complete, and
P31 remains deferred. Preserve P25's frozen
inputs, runners, source/review/scan identities, scores and failed attempts; newer
documentation does not rescan code or expand an earlier verdict. P27 follows the
researched proposal; further memory automation remains separately scoped. Keep P31
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

**Complete within the selected scope.** The [usage contract](developer/accounting.md) supplies durable
request/attempt/provider/billing/model facts separately from diagnostics. The
[configured cost implementation](developer/accounting.md) and
[operator guide](operator/resources.md) define the available reports:

| Increment | Delivery state and scope |
| --- | --- |
| P23A | Pure versioned rate-card estimator with exact configured identities, fixed-point arithmetic, cache partitions, provenance and explicit unknown/partial values |
| P23B | Separately granted own-session `usage.read`, fixed prefixes, source-bound cached recovery and default-off `builtin:cost-report:1` pages |
| P23C | Finite separately granted full own-session enumeration and default-off `builtin:cost-summary:1`, cumulative request replacement and overflow/legacy handling |
| P23D | Explicit registered-child discovery/reads and default-off `builtin:cost-tree:1`, frozen accounting prefixes, exact origins and visible missing/busy/invalid/legacy/cleanup gaps |
| P23E1 | Explicit supported provider output ceilings, narrowed child/summary caps and saved-policy resume |
| P23E2 | Optional atomic session-tree reservations for main/summary/children, conservative settlement, protected inspection and historical-source validation; local and hosted Linux/macOS source/package/installed checks passed |
| P23F | Explicit one-shot `host.model` text requests, profile-bound approvals/receipts, canonical usage and shared reservations; source/native/package and both independent artifact proofs passed locally and in hosted Linux/macOS checks |

[Provider output ceilings](developer/configuration.md) apply only to supported
API/Ollama requests. ChatGPT subscription refuses the unsupported setting; no
output-token ceiling is invented for that public interface. Verification scope
and limitations are recorded in
[actual evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks).
The [shared budget contract](developer/accounting.md) covers main, summary and local
children and [extension model operations](developer/extension-effects.md#request-bounded-text-inference)
independently of reports. P23F's source and installed proofs passed locally and on
both hosted platforms; the measured coverage remains distinct from live billing.

These reports do not enforce budgets, produce a globally atomic tree balance or
promise an invoice ceiling. Rates are configured; subscription equivalents,
API estimates and local inference resource costs remain distinct. Missing usage
or failed-child cleanup cannot be converted to zero liability.

The [independently built model artifact](../examples/README.md) and
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
the [contributor training](developer/testing.md). Existing P14 tools/skills/ledger and P22 SDK are available; engine
installation or production implementation is not required by this milestone.

Execution readiness requires a passing frozen runner, reviewed task/resource
limits, usable explicit research access for both tracks and P24's architecture
dispositions and triaged baseline audit. Brief preparation and service-access
checks can proceed earlier. Live audio (now P31) is not a prerequisite. Scope the trial
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
the [extension contract](developer/extension-state.md) owns suppression and measurement limits.

## P27: optional research, graph and RAG

**Complete within the optional Research, Graph and Corpus scope.**
The first private GPU comparison at `7bffee0` retained 350 first outcomes but
failed measurement and audit. Its context and streaming corrections passed
verification and hosted CI at `1d40eee`. A fresh comparison at that source then
exhausted its first cell's 100-minute service allowance. It retained 22 outcomes
before the remaining owned work was stopped. Neither attempt qualifies a strategy.
The duration correction at `817ab84` passed local verification and exact-source
hosted CI. Its fresh comparison completed all 350 first outcomes, including six
failures, and passed the joined execution/resource audit before reference release.
Two independent model assessments, separate adjudication and one explicit human
resolution supply complete review of all 350 outcomes and 635 citations. The
owner-resolved rerank case uses a frozen `independent: true` compatibility flag
to close the scorer's global completeness gate. It is not an independent final
judgment and changes neither hybrid nor any strategy's qualification; the
[comparison disclosure](archive/2026-10-23-p27-heldout-comparison/index.md#result-and-remaining-acceptance)
records that accepted method extension. The
original scorer passes the frozen per-strategy qualification policy. Hybrid is
the sole eligible strategy, with 92% answer support and 95.18% citation support,
and is selected as the reference configuration. The
[complete comparison record](archive/2026-10-23-p27-heldout-comparison/index.md)
publishes all outcomes, all seven strategies, original judgments and matched
resources. All four final-code source/installed CPU/GPU synthetic measurement
controls pass, along with platform/package checks and the whole-manual review.
The [requirement-by-requirement audit](archive/2026-10-23-p27-heldout-comparison/acceptance-audit.md)
records the complete acceptance and its limits.
The
[first terminal record](archive/2026-10-22-p27-private-comparison/index.md) and
[duration-repair record](archive/2026-10-22-p27-duration-repair/index.md) preserve
the separate failures and their corrections. The
[previous plan](archive/2026-10-22-p27-private-comparison/previous-plan.md)
preserves earlier increment history.

P27 supplies independently configurable Corpus, Graph and Research extensions.
Memory remains independent. Enabling one package does not enable another or
create an undeclared worker, connection, store, index or model call. Lexical
retrieval works without embeddings. Search, fetch, store, retrieval, embedding
and rerank services use named operator-selected profiles. No framework, database,
provider, external endpoint or measurement backend is mandatory.

### Acceptance criteria

The complete milestone requires all of the following:

- Preserve attributable source, chunk, generation, typed version, hash and citation
  identities through bounded ingestion, extraction, traversal and retrieval.
- Propagate deletion and suppression. Refuse stale projections and honor
  historical and as-of eligibility, including delayed work and import recovery.
- Handle contradictory, stale, negative-only and weak evidence without inventing
  support. Compatible positive requirements remain compatible.
- Preserve approvals, selected profiles, accounting, finite budgets, cancellation,
  owner-loss cleanup, partial failures and inert recovery. Never automatically
  replay an interrupted or unknown effect.
- Require zero authority, isolation, replay and resurrection failures in the
  applicable corrected-source deterministic, native and installed controls.
  Preserve historical failures and declared platform limits; this gate adds no
  unverified sandbox guarantee.
- Deliver generic host contracts before domain consumers. Keep legacy grants and
  SDK bounds unchanged unless the operator explicitly selects a new contract.
- Evaluate seven strategies on fifty independently authored held-out questions
  across two projects. Publish every one of the 350 first outcomes, including
  failures, partial results and unavailable measurements.
- Freeze predictions and verify the full execution and resource audit before
  releasing reference answers. Obtain independent semantic judgments for every
  applicable answer, claim and citation. Recompute literal citation integrity
  against hash-verified corpus bytes through the scorer.
- Select a strategy that individually reaches at least 90% answer support and
  95% citation support. Reject strategies below either target for selection.
  Aggregate results and synthetic fixtures cannot qualify a strategy.
- Compare retrieval quality, classification, latency, request and budget usage,
  retained storage and exact workload-charged RAM. Justify the engine choice with
  those results and their limits.
- Complete whole-codebase consolidation, coherent operator and developer manuals,
  platform and installed-package checks, and independent architecture and
  implementation review. Integrate the final decision into the manuals before
  closing the milestone.

### Implementation and verification

| Increment | Implemented behavior | Acceptance state |
| --- | --- | --- |
| P27H1 | Source-bound result pages, explicit mixed read/effect allowance and pure saved-source validation | Protocol checks complete |
| P27H2 | Approved configured MCP actions, pinned descriptors, child denial, owned cancellation and unknown-outcome recovery | Protocol checks complete |
| P27H3 | Selected-profile native embeddings, exact egress and operation-aware accounting and budgets | Protocol checks complete |
| P27H4 | Opt-in complete results, historical receipt reads and strict source closure within ordinary SDK bounds | Protocol checks complete |
| P27H5 | Explicit schema-bound inference and independently selected extraction and rerank contracts | Compatibility and protocol checks complete; held-out judgments complete |
| P27A | Independent Research and lexical Corpus packages with cited evidence, explicit limits, partial failures and suppression | Implementation/review checks and held-out comparison complete; both strategies rejected for the reference choice |
| P27B | Independent Graph, optional extraction, dense/hybrid retrieval and reranking | Implementation/review checks and matched comparison complete; hybrid selected, weaker strategies rejected |
| Structural readiness | Whole-codebase/manual consolidation reviewed at c9a2d80; its sole Daybreak P2 inventory finding repaired at b81f68f | Complete; local/hosted/native-inclusive suites, package checks and all four source/installed CPU/GPU measured controls pass |
| Comparison audit repair | Stream merged execution against closed cell inventories without materializing the raw aggregate | Reviewed; platform suites and all four source/installed CPU/GPU measured proofs pass |
| Explicit context repair | Bind portable and local context; verify loaded completion context while allowing separate embedding windows | Reviewed; platform/floor checks, 31-case service proofs, all four measured proofs and eight exposed GPU requests pass |
| Duration composition repair | Compose fourteen legal service lifetimes within one finite measured-root ceiling; preserve existing request and service limits | Reviews, platform and supported-toolchain checks, native controls, package checks, all four source/installed CPU/GPU measured proofs and exact-source hosted CI pass at `817ab84` |
| Final acceptance | Frozen outcomes, semantic judgments with the disclosed owner-resolution extension, all-strategy publication, exact resources and hybrid reference choice | Complete within that accepted extension; whole-manual/requirements audit passes; earlier failed attempts retain their verdicts |

The [external whole-P27 review and dispositions](archive/2026-10-20-p27-external-review-r1/index.md)
retain all twelve code and five documentation findings, their repairs and
follow-up coverage. The [readiness repair record](archive/2026-10-21-p27-readiness-repair/index.md)
retains the subsequent whole-milestone and Daybreak review, six further repairs
and their checks. The [structural implementation](archive/2026-10-20-p27-structure-implementation/index.md)
and [whole-manual editorial review](archive/2026-10-21-p27-manual-consolidation/editorial-review.md)
record the earlier changes. Those records do not establish acceptance of the
whole-codebase consolidation.

Structural acceptance is complete. Host runtime follows the standard Elixir layout
with matching feature folders under `lib/ipse/` and `test/ipse/`. Generic extension
host and SDK code is under `lib/ipse/extension/`; bundled and optional feature
implementations share one `extensions/` tree. Small, tightly coupled modules and
one-caller wrappers were merged while justified process/public-contract ownership
remains separate. Developer commands retain separate entry points with shared
implementation grouped under `dev/`. Individual historical files remain intact.

Session retains the conversation process. Its turn and extension-invocation
implementations run synchronously in that process, with caller/reference/phase
admission and resource completion retained by Session. A source split must not
introduce another conversation owner.

The [current consolidation review](archive/2026-10-22-p27-structural-review/index.md)
records the independent findings and their causal checks. Current manuals now have
14 operator and 22 developer chapters. Corrected-source hosted Ubuntu/macOS,
native-inclusive Linux, package and installed-package checks pass at `b81f68f`.
All four source/installed CPU/GPU measured controls pass. Their
[final receipts](archive/2026-10-23-p27-heldout-comparison/final-platforms.json)
retain exact source/archive identities, commands, audit results and exclusions.
File-count reductions alone do not establish
deletion of unnecessary interfaces or lower implementation complexity. The earlier
broad default checkpoint passed with 1,459 passed, one skipped and 36 excluded.
The supported-toolchain loading correction passes 161 integrated caller tests and
77 focused floor tests. The clean floor snapshot also passes packaging, installed
package/model-service checks, all fifteen Knowledge builds and ten source plus ten
installed Knowledge routes. These use synthetic services, not actual model quality
or Linux native enforcement evidence.
Hosted run `39895104182` passed Ubuntu. macOS passed those source/native/package
and Knowledge steps, then failed compilation of the final experimental App Sandbox
verifier. Its stale helper capture is repaired with a causal compile regression,
supported-toolchain compile check and passing real local App Sandbox probe. The
original run remains failed. The correction at `c9a2d80` passed
[run 39899526393](https://github.com/lexlapax/ipse/actions/runs/39899526393) on both
platforms, including all installed proofs and the final experimental macOS
verifier. Its [receipt](archive/2026-10-22-p27-structural-review/hosted-c9a2d80.json)
records exact source and exclusions. The subsequent verification-record update
changes documentation only; actual-model quality and final Linux native-inclusive
checks remain separate gates.

The consolidation covers runtime code, extension packages, tests, developer
tooling, examples, shipped resources and both current manuals. The structural
record distinguishes deletions/merges from moves and records caller, packaging
and documented-usage checks against the resulting structure. The completed
comparison retains its original frozen source and provenance throughout this work.
The developer accepted that comparison at
`817ab84944c347f76e297efaad313b1ec841ee91` as explicitly versioned evidence,
alongside correctness and platform checks on the final consolidated code. A new
350-answer comparison is not required solely because of structural consolidation.
Quality qualification and publication still require the full outcomes, joined
resource audit and independent semantic review.

The [preceding launch-verification record](archive/2026-10-21-p27-gpu-policy/index.md#preserve-the-first-private-preparation-refusal)
binds the canonical command correction, actual fresh-VM regression, macOS and
native-enabled Linux suites, supported toolchain checks, source and installed
synthetic comparisons, packaging and hosted CI to the corrected runtime. Those
checks establish implementation and execution behavior for that earlier source.
They do not verify the current corrective increment. Its
[corrective record](archive/2026-10-22-p27-private-comparison/index.md#verify-the-corrective-increment)
retains passing macOS and native-enabled Linux suites, the supported toolchain,
package/installed checks, source comparisons and exposed context diagnostic.
All four source/installed CPU/GPU measured comparisons and final source-identity
checks pass. Exact hosted run `39737181313` is green on Ubuntu and macOS for
`1d40eee`. That result verifies the context and streaming corrections. The new
duration-composition repair has separate completed verification in its
[record](archive/2026-10-22-p27-duration-repair/index.md#verification-and-remaining-acceptance).
Exact hosted run `39764314254` is green on Ubuntu and macOS for `817ab84`.
All four measured fixture proofs complete 350 outcomes and the joined audits.
These checks verified execution behavior at that increment; the separately
versioned [held-out result](archive/2026-10-23-p27-heldout-comparison/index.md)
now supplies semantic qualification and the reference choice.

### Completion and subsequent work

All P27 acceptance tasks are complete. The selected reference uses existing
State Corpus hybrid retrieval with BM25, native 768-dimensional embeddings,
reciprocal rank fusion at 60, no graph or reranker, and explicit missing-embedding
refusal. This is an operator-selected configuration, not a mandatory service or
automatic provider switch. The answer-quality result applies to the frozen 9B
answer policy and workload; the other strategies remain available but are rejected
for this reference choice.

Preserve the published outcomes, raw assessments, human resolution, final scores,
matched resources and all earlier failures. The released workload is now exposed;
future quality acceptance requires independently authored data. Later engine,
corpus, provider or model changes need their own scoped evaluation rather than
upgrading this historical result or replaying consumed seals. P31 remains deferred.

The [independent review of `a7f4982`](archive/2026-10-23-p27-independent-review/index.md)
confirms acceptance within this scope. The later
[remediation record](archive/2026-10-23-p27-review-remediation/index.md) closes both
P2 findings: dispatched MCP errors now retain a distinct diagnostic outcome,
and non-regular skill files refuse while explicit prompt expansion runs outside
the owner. It also closes deadline-edge accounting and patches PlugCrypto.
The comparison discloses adjudication sensitivity and the owner-resolution method
extension; frozen predictions and scores remain unchanged. Subsequent
[maintenance and fingerprint compatibility](archive/2026-10-23-p27-maintenance/index.md)
consolidates equivalent primitives and pure feature policy, removes the unused
HTTP backend, and versions new MCP sessions while preserving old journal rules.
Verification remains versioned: `4171fb4` had a Linux setup failure followed by
focused correction; `dd0a130` had one harness failure in each initial full suite
and hosted formatting failures; `ca5838b` passed its bounded follow-up checks.
The [final independent review](archive/2026-10-23-p27-final-review/index.md)
then verified `ca5838b` with 1532 native-inclusive Linux tests, its exact package
and installed proof, and green Ubuntu/macOS hosted run 40014715937. It confirms
acceptance and independently recomputes all published evidence. Its remaining P3
MCP corners and documentation/record gaps are addressed in the accompanying
follow-up at `89151b6`, with separate verification in that record. The subsequent
[internal whole-P27 adversarial audit](archive/2026-10-23-p27-final-review/internal-audit.md)
also repairs shared MCP output admission and legacy public-argument/hash agreement.
Its individual reviews, causal probes and final platform/package checks are
recorded separately. Frozen outcomes and scores are unchanged.

### Final comparison policy

The independently authored private workload has fifty questions, two projects
and 22 documents. The earlier exposed workload is tuning material and cannot
establish final acceptance. Preserve every historical attempt and its original
verdict; never upgrade or replay an incomplete comparison.

The [recorded semantic-review method](archive/2026-10-22-p27-semantic-review-policy/index.md)
requires two fresh blinded assessments of every case and citation, followed by
separate adjudication of disagreements. Preserve both raw assessments and the
adjudications. Unresolved judgments leave review completeness open. This method
is recorded before reference release and changes neither qualification target.

The selected inference policy uses the existing `qwen3.5:9b` model with reasoning
for final answers only. Extraction and reranking retain SDK-2's two-minute limit
and disabled reasoning. The explicit SDK-1 version-three answer allowance is
600 seconds and 8192 output tokens. The declared one-NVIDIA-device policy permits
partial CPU/GPU residency. It does not establish physical exclusivity.

The exact memory quantity is `linux_memcg_charged_peak_bytes_v1`, workload-charged
RAM including cache and kernel charges within each declared subject. Report the
whole-lifetime peak, each fresh stage's lifetime peak and the whole population's
peak during each stage separately. RSS samples,
summed process peaks and device memory do not substitute for those measurements.
The optional Linux backend uses the approved existing systemd user-service tools.
Ordinary Ipse operation does not require that backend. Host paths, device UUIDs
and runtime identities belong to execution provenance; Serenity is a verification
host rather than a required product configuration.

The [developer evaluation manual](developer/knowledge-evaluation.md) owns the
runnable declaration, sealing, execution, audit, independent-review and scoring
procedures. Final acceptance still requires the complete frozen audit, independent
semantic judgments, all-strategy publication, an individual qualifying strategy,
the engine decision and whole-document editorial integration.

## P28: operator usability and release readiness

**Selected; implementation in progress.** P0–P27 established correctness, recovery and evidence for a
supervised developer. This milestone makes the same harness usable by an operator
who did not build it, without weakening approvals, explicit provider selection or
fail-closed behavior. It adds no provider, model service or dependency by default.
The [P28 implementation brief](archive/2026-10-23-p28-p29-design/p28.md) breaks
this scope into ordered work packages with files, tests and decisions.
The developer accepted its recommended decisions on 2026-10-23. A missing
configuration keeps the built-in `chatgpt` default, and interactive starts print
a notice that names it and points to `ipse setup`. The first tag is `v0.1.0`. The
release workflow drafts releases with the runner-provided `gh` CLI and the default
token, recorded in the dependency inventory when it is added.
The [implementation record](archive/2026-10-23-p28-p29-implementation/index.md)
tracks the ordered work packages, actual checks and auditor handoff requirements.
Version/build identity is complete at `b4788b4`, with local source and
installed-archive checks and exact-source hosted Ubuntu/macOS verification.
Actionable errors pass full local and hosted checks at `6818000`. Offline doctor passes
the native-inclusive suite at `a89fce7`. Private setup passes focused and installed
first-run checks. Release checksums, symlink handling, draft workflow and lifecycle
manuals are implemented; the local installed upgrade proof passes. Whole-manual
review and installed examples pass. The latest `9c5eb6a` native-inclusive baseline,
isolated demo, installed proof and complete hosted Ubuntu/macOS matrix pass.
RC1's workflow and both platform archives/checksums pass, including re-download
and runtime-notice inspection ([receipts](archive/2026-10-23-p28-p29-implementation/rc-assets.json)).
The developer reports a successful existing-account Linux walkthrough, including
ChatGPT sign-in, doctor/demo and follow-up confirmation of the real task,
individual approvals, output inspection and resume. The
[observation record](archive/2026-10-24-p28-walkthrough/index.md) distinguishes
terminal evidence from operator attestations. A subsequent fresh Linux account
run used Demo and Ollama `qwen3.5:9b`; the developer accepts the run and reports
excessive individual approval prompts. Account setup and product-navigation help
are recorded, so this is not labelled an entirely unassisted manual-only pass.
Human upgrade was skipped because only one version was available; automated
upgrade evidence remains separate. The requested
[approval UX research](archive/2026-10-24-p28-approval-ux/index.md) compares existing
agents and proposes modes plus reusable consent; no policy change is implemented.
RC draft cleanup, final acceptance of these qualifications and stable publication
remain open. The external-auditor handoff includes these findings.

Scope:

1. A guided first-run path that writes an owner-only operator configuration after
   showing it: provider and billing choice, credential source, workspace defaults
   and optional extensions. It never selects a provider or paid mode implicitly and
   never prints or copies credentials.
2. An `ipse doctor` diagnosis of toolchain, runtime identity, configuration
   resolution, credential presence (not values), provider reachability on explicit
   request, native policy availability, MCP and extension selection, session store
   and lock health. Every finding names the documented recovery step.
3. An audit of operator-visible refusals and errors from `ipse chat`, `run`,
   `config`, resume and extension/MCP paths. Each states the cause, what did or
   might have happened and the next command, matching
   [recovery](operator/recovery.md).
4. A versioned release: tagged source, Linux and macOS archives from the existing
   [packaging](developer/testing.md) path, checksums, release notes and
   install/upgrade/uninstall instructions. Upgrades preserve saved sessions or
   refuse them with a documented handoff, as the license transition did.
5. A whole-document review of the operator manual as a new user's path from
   install to a first real task, including accepted limits stated where they apply.

Acceptance: fixture tests for setup output, configuration resolution and each
doctor finding; no network traffic without an explicit request; installed-archive
first-run and upgrade checks on Linux; hosted macOS package checks; and a recorded
unassisted walkthrough by a fresh operator account. Signing, notarization and
distribution channels such as package managers need separate approval as release
dependencies.

## P29: provider registry, OpenRouter and Gemini

**Complete at `9c5eb6a`.** The central
[`provider registry`](../lib/ipse/provider/registry.ex) supplies configuration,
profiles, credentials, billing, accounting, capabilities, setup and diagnosis.
Independent pre-refactor fixtures from `dd510a7` retain existing manifests,
destinations, usage, costs and saved-session behavior. Shared conformance covers
the existing adapters, pinned OpenRouter, explicit loopback-compatible servers
and native Gemini. Session/child/SDK, compaction, privacy, budgets and recovery
controls pass. Guided setup saves explicit route profiles while preserving
existing configuration. Native embeddings remain limited to OpenAI/Ollama.

Final verification passes the Linux native-inclusive suite (1713 passed,
19 excluded), isolated demo, complete installed proof and the exact-source
[Ubuntu/macOS matrix](archive/2026-10-23-p28-p29-implementation/final-hosted.json),
including all independent proofs. Whole-manual review and installed examples pass.
Separate [live Gemini and pinned OpenRouter text/tool checks](archive/2026-10-23-p28-p29-implementation/p29-live-final.json)
pass at `492d091`; the only subsequent runtime changes refine refusal messages.
Missing Gemini counters remain partial. The
[combined receipt](archive/2026-10-23-p28-p29-implementation/combined-verification.json)
preserves exact revisions, exclusions and earlier failures. Independent external
completeness review remains separate; P28's human walkthrough/publication gates
are still open.
The [P29 implementation brief](archive/2026-10-23-p28-p29-design/p29.md) breaks
this scope into ordered work packages with files, tests and decisions.
The developer accepted its recommended decisions on 2026-10-23. Gemini, then
OpenRouter, follow the existing four providers in the documented priority order;
[AGENTS.md](../AGENTS.md#product-and-scope) changes when those providers land.
An `openai_compatible` provider serves loopback servers only, with local billing.
OpenRouter profiles send `data_collection: "deny"` unless they explicitly allow
collection.

1. **Registry, no behavior change.** Each provider declares its adapter, default
   endpoint, credential source, billing mode, reasoning/profile validation, usage
   normalization, pricing source and destination facts in one place. Existing
   journals, profiles, cost reports and destination digests stay identical; old
   sessions resume unchanged.
2. **OpenAI-compatible Chat Completions adapter.** The current OpenAI adapter uses
   the Responses API only. A separate Chat Completions adapter serves OpenRouter as
   a named provider and, with explicit base URLs, local servers that implement the
   same interface. OpenRouter can route to different upstream hosts or fall back to
   other models. Ipse must pin the requested model and upstream order, disable
   fallbacks, record the upstream that actually served each response and refuse a
   mismatch, so no provider or model changes silently.
3. **Native Gemini adapter.** Use the Gemini API rather than its OpenAI-compatible
   endpoint, so thought signatures and function-call state are preserved as
   provider continuation data. AI Studio API keys and Vertex credentials are
   distinct explicit choices, as are free and paid billing. Gemini embeddings may
   follow under the existing versioned embedding contract with its own evaluation.

Acceptance: registry equivalence tests over existing fixtures and saved sessions;
loopback fixture servers for streaming, tool calls, truncation, errors, usage and
continuation round trips for each new adapter; budget and cost reporting with
unknown prices kept unpriced; destination and egress facts; and separately
recorded opt-in live account checks. Whether OpenRouter and Gemini join the
provider priority order in [AGENTS.md](../AGENTS.md) is a developer decision
recorded before release.

## P30: advisory decision engines

**Proposed.** Decision engines answer typed questions from closed answer sets
instead of generating text. Candidates are OpenAI's Decisions API, a beta
`POST /v1/decisions` endpoint, and the SystemOne wire format used by TypeSafe's
hosted Jev service and by Zev, an independent MIT-licensed local engine that serves
both formats on loopback. Public details are recent and partly secondary; verify
current official documentation before adapter work.

This is a separate operation, not a chat provider, following the pattern of the
P27 embedding contract:

1. A versioned request of bounded context plus questions (choice, score and
   yes/no predicate), each with a closed answer set, and a validated response of
   one in-set answer per question, an explicit uncertain/insufficient outcome or
   a refusal. Out-of-set or partial responses refuse the whole decision.
2. Adapters for OpenAI Decisions, hosted SystemOne and loopback SystemOne,
   each with operator-configured endpoint, credential, destination facts,
   usage/cost accounting and budgets. There is no fallback between engines or to
   a language model.
3. Exposure through a new `host.decision` extension grant beside `host.embedding`
   and an optional model tool. Results are advisory data. They never approve an
   effect, grant a capability, choose a provider or profile without operator
   confirmation, or bypass journaling.
4. One measured first use, such as suggesting a profile or route for a task, with a
   small independently labeled workload and published agreement before the
   suggestion appears to operators. Later uses, including memory capture gating,
   skill selection and Research/Graph classification, need their own evaluations.

Acceptance: fixture engines for valid, out-of-set, uncertain, slow, oversized and
disconnected responses; owner death and cancellation; accounting and budget
refusal with zero dispatch; no-fallback checks; and separately recorded opt-in live
checks. Zev or another local engine is an operator-run external service, not a
bundled or required dependency; calling it adds nothing to the dependency
inventory, but the operator manual documents it as an optional endpoint.

## P31: voice and realtime media

**Deferred; unimplemented. Archived records call it P28, and earlier P24.**
Keep the requested scope for a future delivery; it is no longer ahead of
architecture/security review or self-development.
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
campaign, before the separately deferred P26–P27 features and voice (now P31).
Root and bundled extension licenses now carry Apache-2.0 with the original copyright. Current contributor,
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
[runtime facts](../lib/ipse/session/context.ex) and [extension architecture](developer/extensions.md).

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
[Mac boundary](developer/sandbox.md#understand-the-macos-workspace-profile).

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
[delegation contract](developer/architecture.md) and
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
production knowledge backend. See [research contract](developer/knowledge-extensions.md) and
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
See [contract](developer/architecture.md) and
[integrated evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P18: supervised self-development on the operator's Mac

Complete: frozen-runner `sessions --json` change, structured clarification,
independent local Mac/native/package checks, bounded review and hosted Linux/Mac
verification before PR #1 merged. Review budget exhaustion, supervisor assistance
and safe context refusal remain recorded. See the
[Mac runbook](operator/development-workflows.md) and
[local evidence](archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p18-macos-supervised-self-development-evidence).

## P19: long-session diagnosis and recovery

Complete: content-free context/timing diagnostics and explicit reviewed handoff
without silently trimming native continuation or intent. Synthetic fixtures
reproduce the failure shape, not a private original Mac transcript. See
[observability contract](developer/lifecycle-events.md),
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
[adoption scenarios](developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab) and
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
