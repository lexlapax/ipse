# Development plan

Ipse is an Apache-2.0-licensed general-purpose local AI harness. Its core stays in
Elixir/OTP, with Rust for small OS helpers; target projects may use any suitable
stack. Prefer extensions, tools and inert skills for domain features, ordinary
OTP for ownership, and reviewed generic core changes for missing host invariants.
No mandatory workflow framework, external service or database. Integrations use
explicit provider/service selections and their documented endpoint policy.

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

The requested whole-repository
[semantic documentation remediation](archive/2026-10-25-prepublication-docs/index.md)
is complete, with local example/archive/installed checks and the full hosted
Linux/macOS matrix at `5daf5d0`. On explicit developer authorization, the stable
tag and unpublished draft were replaced with the audited candidate `341e458`.
Its complete Linux/macOS release workflow and exact re-downloaded assets pass
[verification](archive/2026-10-25-prepublication-docs/release-reconciliation.json).
The developer then explicitly authorized publication. [v0.1.0](https://github.com/lexlapax/ipse/releases/tag/v0.1.0)
was published as the latest release on 2026-10-25, with the same four inspected
assets ([publication receipt](archive/2026-10-25-prepublication-docs/publication.json)).
Qualified readiness retains its recorded human/live limits.

| Milestone or gate | Current state | Next result |
| --- | --- | --- |
| P0–P22 | Complete within [the scopes below](#completed-milestones-p0p22) | Preserve their invariants when extending the host |
| [P23: accounting and budgets](#p23-usage-cost-reporting-and-budget-controls) | Complete within one-shot text/accounting scope | Keep later embedding and provider coverage separately identified |
| [P24: architecture/security readiness](#p24-independent-architecture-validation-and-baseline-security) | Accepted for supervised P25 at `375e607` | Preserve the scoped verdicts and accepted same-user storage limit |
| [P25: comparative self-development](#p25-comparative-research-and-supervised-self-development) | Accepted within declared supervision/assistance at `3307563` | Preserve frozen inputs, failures and bounded comparison claims |
| [P26: memory baseline](#p26-optional-working-and-long-term-memory) | Explicit-note scope accepted at `25f1d8e` | Productize automatic memory under P31 without changing this historical acceptance |
| [P27: research, graph and RAG](#p27-optional-research-graph-and-rag) | Optional-package scope complete; hybrid qualified and selected | Evaluate new workloads independently; retain all seven strategies' original results |
| [P28: operator usability and release](#p28-operator-usability-and-release-readiness) | v0.1.0 published at `341e458` under qualified acceptance after semantic documentation remediation and exact asset inspection | Retain human/live qualifications; evaluate subsequent changes against their own scope |
| [P29: provider registry, OpenRouter and Gemini](#p29-provider-registry-openrouter-and-gemini) | Original scope and repairs accepted for qualified readiness; added Grok routes pass automated checks | Preserve unverified Grok API/OAuth eligibility and Gemini foreign-history live acceptance |
| [P31: usable knowledge and prompt assistance](#p31-usable-knowledge-and-prompt-assistance) | Implementation authorized; local host, permission and capture components in progress | Sustainable metadata, current recall, lifecycle and integrated qualification remain open |
| [P30: decision engines](#p30-advisory-decision-engines) | P30A/B typed/protocol and admitted-operation increments in progress; no qualified consumer | Verify full B baseline; C–E integrate with P31B/E, without waiting for PDF/graph |
| [P32: voice and media](#p32-voice-and-realtime-media) | Deferred; unimplemented; formerly P31 | Select media contracts and device/service validation in a later increment |
| [Apache-2.0 transition](#license-transition) | Complete at `7bb642b` | Preserve runtime, dependency and extension license boundaries |

Acceptance is bounded by the evidence for each milestone. Internal source review,
external critique, static scanning, fixture execution, hosted platform checks and
live accounts establish different claims. P24/P25 acceptance is supervised use in
a trusted, cooperative workspace; partial security scans and withheld independent
verdicts remain partial. P27's versioned held-out comparison is not a universal
engine ranking. No unattended operation or security certification is claimed.
No further broad architecture-review loop or security scan is scheduled.

The [architecture dispositions](archive/2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md),
[P25 acceptance](archive/2026-10-18-before-manual-rewrite/docs/developer/p25-evaluation.md#scoped-acceptance-decision),
[P26 remediation](archive/2026-10-19-p26-remediation/index.md),
[P27 comparison](archive/2026-10-23-p27-heldout-comparison/index.md) and
[P28/P29 qualified acceptance](archive/2026-10-24-p28-p29-review2/acceptance.md)
preserve the decisions and original limitations. On 2026-10-26 the developer
inserted knowledge and prompt assistance as P31 and moved voice/media to P32.
Historical media proposals retain their contemporary P24, P28 or P31 numbering;
the [previous scopes](archive/2026-10-26-p30-p31-plan/prior-milestones.md) are preserved.
The [current design](knowledge-design.md) and
[latest audit disposition](archive/2026-10-26-p30-p31-final-handoff/index.md) link source
research, settled user choices and concrete contracts. P31A is the next implementation
entry point; P30A/B is independent parallel work.
The [implementation handoff](archive/2026-10-26-p30-p31-final-handoff/implementation.md)
specifies P31A's bounded first work and required evidence.
The developer authorized full P30/P31 implementation on 2026-10-26, with full tests,
an adversarial audit and review handoff. The [implementation record](archive/2026-10-26-p30-p31-implementation/index.md)
preserves the frozen amended baseline, finite live allowance and open evidence.
Publication remains separately authorized.
The developer-selected Grok follow-up extends P29 and keeps API billing separate
from registered-client subscription OAuth.

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

[Provider output ceilings](developer/configuration.md) follow the selected route's
capability contract. ChatGPT subscription refuses the unsupported setting; no
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
are recorded in testing. P23 delivered one-shot text; P27 subsequently added the
separate native embedding contract. Audio remains unsupported pending separate
contracts. In-flight input/money estimation
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
checks can proceed earlier. Live audio (now P32) is not a prerequisite. Scope the trial
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
Automatic recall/capture is now scoped under [P31](#p31-usable-knowledge-and-prompt-assistance);
it is not enabled by this baseline. Zero-Mem is inspiration, not a selected package or
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
records the independent findings and their causal checks. At that consolidation,
the manuals had 14 operator and 22 developer chapters. Corrected-source hosted Ubuntu/macOS,
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
checks were separate gates at that stage, with later acceptance recorded above.

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
They do not verify the later corrective increment. Its
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
upgrading this historical result or replaying consumed seals. P31 adds a separately
qualified ordinary-user knowledge experience; voice/media remains deferred as P32.

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
procedures. The acceptance rule requires the complete frozen audit, independent
semantic judgments, all-strategy publication, an individual qualifying strategy,
the engine decision and whole-document editorial integration.

## P28: operator usability and release readiness

**v0.1.0 published on explicit developer authorization on 2026-10-25 at `341e458`, under the qualified readiness accepted on 2026-10-24. Semantic documentation remediation, full platform verification and exact asset inspection pass; the recorded human/live qualifications remain.**
P0–P27 established correctness, recovery and evidence for a
supervised developer. This milestone makes the same harness usable by an operator
who did not build it, without weakening approvals, explicit provider selection or
fail-closed behavior. It adds no provider, model service or dependency by default.
The [P28 implementation brief](archive/2026-10-23-p28-p29-design/p28.md) breaks
this scope into ordered work packages with files, tests and decisions.
The developer accepted its recommended decisions on 2026-10-23. A missing
configuration keeps the built-in `chatgpt` default, and interactive starts print
a notice that names it and points to `ipse setup`. The first stable version is `v0.1.0`. The
release workflow drafts releases with the runner-provided `gh` CLI and the default
token, as recorded in the dependency inventory.
The [implementation record](archive/2026-10-23-p28-p29-implementation/index.md)
tracks the ordered work packages, actual checks and auditor handoff requirements.
Version/build identity is complete at `b4788b4`, with local source and
installed-archive checks and exact-source hosted Ubuntu/macOS verification.
Actionable errors pass full local and hosted checks at `6818000`. Offline doctor passes
the native-inclusive suite at `a89fce7`. Private setup passes focused and installed
first-run checks. Release checksums, symlink handling, draft workflow and lifecycle
manuals are implemented; the local installed upgrade proof passes. Whole-manual
review and installed examples pass. The original `9c5eb6a` native-inclusive baseline,
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
agents and proposes modes plus reusable consent. The developer explicitly selected
implementing this follow-up before external audit, extending the brief's original
approval-semantics exclusion. Native workspace edit consent and exact shell-call
session grants are implemented in the
[new candidate](archive/2026-10-24-approval-implementation/index.md), with inspect/revoke,
fresh proposal binding and no inherited/resumed grants. The combined `622a2c8`
runtime passes full local native, installed and hosted Ubuntu/macOS checks;
the older baseline retains its narrower scope.
The developer also requested [machine identification during sign-in](archive/2026-10-24-sign-in-host-label/index.md).
New registrations now use a short `ipse@HOST` display-name hint to prefill the
browser's editable name. Returning authorization preserves registration identity
and omits that hint. The earlier terminal-only guidance is superseded; combined
verification includes browser-prefill request construction, without claiming a
new real browser authorization.
The inspected RC draft was deleted on explicit developer authorization after all
four exact assets and inspection metadata were retained locally; its RC tag remains.
The developer subsequently [accepted the repaired candidate with its documented
qualifications](archive/2026-10-24-p28-p29-review2/acceptance.md), including the
assisted walkthrough and missing human macOS/upgrade checks. This is a qualified
readiness decision, not an unassisted pass or a fresh independent verdict.
The developer subsequently authorized stable tagging and draft preparation.
The initial tag/draft used `1617657`; its
[workflow](https://github.com/lexlapax/ipse/actions/runs/40169083307) completed
successfully before the documentation remediation. After that remediation, the
developer explicitly authorized replacing the tag/draft with `341e458`, retaining
the original tag object and four assets locally. Tag `v0.1.0` now points to
`341e458`; its [release workflow](https://github.com/lexlapax/ipse/actions/runs/40202117315)
passes both platforms, every installed proof, complete asset admission and draft
re-download. Independent inspection verifies all four hosted digests/checksums,
both compiled identities, bundled manuals and runtime notices in the
[reconciliation receipt](archive/2026-10-25-prepublication-docs/release-reconciliation.json).
The final main check's first macOS attempt failed one cleanup fixture; its
unchanged retry and the fresh release checks pass. The failure remains recorded
with its cause unestablished. After inspecting those results, the developer
explicitly authorized publication on 2026-10-25. The
[published release](https://github.com/lexlapax/ipse/releases/tag/v0.1.0) is latest;
its [publication receipt](archive/2026-10-25-prepublication-docs/publication.json)
verifies the same four pre-inspected asset IDs, sizes and digests, unchanged notes
and the approved tag/source. This closes publication under the existing qualified
acceptance without claiming new human walkthroughs or live inference checks.

Scope:

1. A guided first-run path that writes an owner-only operator configuration after
   showing it: provider and billing choice, credential source, workspace defaults
   and optional extensions. It never selects a provider or paid mode implicitly and
   never prints or copies credentials.
2. An `ipse doctor` diagnosis of toolchain, runtime identity, configuration
   resolution, credential presence (not values), provider reachability on explicit
   request, native policy availability, MCP and extension selection, and session
   store permissions/bounded headers without acquiring locks. Every finding names
   the documented recovery step.
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
unassisted walkthrough by a fresh operator account. The developer's recorded
readiness decision accepts the walkthrough qualifications for v0.1.0 without
claiming that original human criterion was met. Signing, notarization and
distribution channels such as package managers need separate approval as release
dependencies.

## P29: provider registry, OpenRouter and Gemini

**Original P29 scope completed at `9c5eb6a`; repaired candidate accepted for v0.1.0 readiness with documented qualifications on 2026-10-24. Live xAI access and registration remain unverified.** The central
[`provider registry`](../lib/ipse/provider/registry.ex) supplies configuration,
profiles, credentials, billing, accounting, capabilities, setup and diagnosis.
Independent pre-refactor fixtures from `dd510a7` retain existing manifests,
destinations, usage, costs and saved-session behavior. Shared conformance covers
the existing adapters, pinned OpenRouter, explicit loopback-compatible servers
and native Gemini. Session/child/SDK, compaction, privacy, budgets and recovery
controls pass. Guided setup saves explicit route profiles while preserving
existing configuration. Native embeddings remain limited to OpenAI/Ollama.

Original-scope verification at `9c5eb6a` passes the Linux native-inclusive suite (1713 passed,
19 excluded), isolated demo, complete installed proof and the exact-source
[Ubuntu/macOS matrix](archive/2026-10-23-p28-p29-implementation/final-hosted.json),
including all independent proofs. Whole-manual review and installed examples pass.
Separate [live Gemini and pinned OpenRouter text/tool checks](archive/2026-10-23-p28-p29-implementation/p29-live-final.json)
pass at `492d091`. Later error, endpoint and Gemini history-conversion repairs
have fixture coverage; those live checks do not verify the new paths. Live
Gemini foreign-history acceptance remains unverified. Missing Gemini counters
remain partial. The
[combined receipt](archive/2026-10-23-p28-p29-implementation/combined-verification.json)
preserves exact revisions, exclusions and earlier failures. The developer supplied
an [independent completeness audit](archive/2026-10-24-p28-p29-audit-repair/index.md).
Its findings are repaired and verified at `aee0ad8`; the approved artifact handoff
passes at `dc70463`, which has the same runtime source. The follow-up record retains
earlier failed/canceled runs and the separate hosted scopes. Independent re-review
remains distinct from implementation checks. Earlier receipts cover their exact
source; P28's human walkthrough qualifications and publication status remain distinct.
The [second independent review and corrections](archive/2026-10-24-p28-p29-review2/index.md)
supersede acceptance of the first repair: its slash filter masked legitimate
configuration, skill and provider causes despite green automated checks. Those
causes now survive actual CLI rendering. Strict setup diagnosis, exact release
admission and numeric stream diagnostics pass local and hosted checks at
`5d9650e`. The requested author adversarial review also repairs a cross-toolchain
verifier compiler defect; 33 verifier tests, installed checks for both toolchains
and the complete hosted rehearsal pass at `45cae30`. Host code, native helpers and
the release workflow are unchanged in that follow-up. The record retains failed iterations and
superseded/canceled runs. The pre-existing short private MCP-value collision
remains documented, without weakening privacy. The
[release-readiness handoff](archive/2026-10-24-p28-p29-review2/release-readiness.md)
prepares v0.1.0. The developer's [qualified acceptance](archive/2026-10-24-p28-p29-review2/acceptance.md)
closes the readiness decision without a fresh independent verdict or new live
provider checks. Documentation remediation and the authorized tag/draft rebuild
are complete, including exact asset inspection. The developer subsequently
authorized v0.1.0 publication; the existing human/live qualifications remain open.
The [P29 implementation brief](archive/2026-10-23-p28-p29-design/p29.md) breaks
this scope into ordered work packages with files, tests and decisions.
The developer accepted its recommended decisions on 2026-10-23. Gemini, then
OpenRouter, follow the existing four providers in the implemented priority order
recorded in [AGENTS.md](../AGENTS.md#product-and-scope).
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
   provider continuation data. This increment supports AI Studio API keys;
   Vertex credentials and OAuth are unsupported. Billing is recorded as API,
   without inferring the account's free/paid tier. Gemini embeddings may
   follow under the existing versioned embedding contract with its own evaluation.

Acceptance: registry equivalence tests over existing fixtures and saved sessions;
loopback fixture servers for streaming, tool calls, truncation, errors, usage and
continuation round trips for each new adapter; budget and cost reporting with
unknown prices kept unpriced; destination and egress facts; and separately
recorded opt-in live account checks. The accepted implementation includes
OpenRouter and Gemini in the provider priority order in [AGENTS.md](../AGENTS.md).

### P29 follow-up: Grok API and subscription OAuth

**Implemented and automatically verified before external audit, 2026-10-24;
live API/subscription eligibility remains unverified.**
The [primary-source research and work packages](archive/2026-10-24-xai-provider-research/index.md)
cover xAI/SpaceXAI's Grok API, its officially supported Hermes subscription
integration, device authorization, native Responses, continuation, billing and
retention. This extends the accepted P29 scope; the earlier registry/Gemini/
OpenRouter verification does not prove Grok compatibility.

Add separate explicit `xai` API-key and `xai_oauth` subscription routes, with no
automatic credential/billing fallback and an explicit model. Prefer native
Responses with local history and `store: false`; preserve opaque continuation in
an xAI-specific namespace, and retain Ipse approval/journal authority over tools.
Use existing bounded Elixir transport, private storage and OS locks, with no new
language runtime or mandatory service. Integrate profiles, roles, accounting,
setup, offline doctor, SDK/children, compaction and resume. Keep xAI hosted search,
execution, MCP, media and multi-agent features outside this text/tool increment.

The developer has no Ipse OAuth registration yet. Public discovery supports
device authorization but advertises no registration endpoint; the official
Hermes announcement does not grant Ipse its client identity. Require an approved
Ipse client ID, and refuse missing registration before network access. Do not
borrow another app's ID or saved tokens. Document registration and entitlement
as open external gates; fixture success cannot establish subscriber eligibility.

The working implementation adds both routes, provider-bound Responses, minimal
registered-client device authorization with locked rotating credentials, private
setup/doctor, explicit billing and native-replay isolation. xAI's public OpenAPI
schema clarifies that the output cap excludes reasoning and function calls; total-
output reservations therefore refuse. Reported legacy totals disambiguate whether
completion includes reasoning, counting it once; missing evidence stays partial
and mixed dialects/contradictions are invalid.
Reported USD ticks remain separate from aggregate rate-card estimates. Focused
source/integration checks and the `622a2c8` installed proof pass. Its full Linux
native-inclusive suite passes 1760 tests, 19 excluded, followed by an isolated demo;
its complete Ubuntu/macOS matrix passes, including all independent proofs and
experimental macOS checks. The later live-driver candidate exposed two macOS
fixture assumptions: cancellation before command-handler startup and an undersized
eight-client listener queue. Controlled reproductions and 26 focused checks support
test-only repairs. Repaired candidate `288a6a2` passes its complete Ubuntu/macOS
matrix, including all independent and experimental macOS proofs; the
[final receipt](archive/2026-10-24-xai-provider-research/final-hosted.json) preserves
the exact run. Product deadlines and frozen evaluator implementation are unchanged.
The authorized live API check found a project key
but received HTTP 403 on its first `grok-4.7` request and stopped without retry.
API inference remains unverified pending team billing/model permissions; no OAuth
account check has run. The [receipt](archive/2026-10-24-xai-provider-research/verification.json)
keeps these scopes and candidates separate.

Acceptance: unchanged existing-provider golden fixtures; Grok Responses
conformance and native replay/privacy; device/refresh/expiry/denial/rotation and
unsafe-file tests; explicit billing and accurate partial usage/costs; real Session
integration; whole-manual review; full source/native/demo and installed checks;
hosted Linux/macOS. Record API-key and OAuth live checks separately when their
credentials/registration are available. The external-auditor handoff must name
any remaining registration or live-account limits explicitly.

## P30: advisory decision engines

**Authorized; typed/protocol and admitted-operation increments in progress.** P31 is the active delivery
path. P30A/B can proceed independently; later
P30 work consumes the first usable notes journey, not the entire P31 milestone.
The [current design](knowledge-design.md#p30-interfaces-and-useful-consumers)
owns detailed contracts. The [final audit disposition](archive/2026-10-26-p30-p31-final-handoff/index.md)
records repairs; the [former plan](archive/2026-10-26-p30-p31-final-handoff/prior-plan.md)
preserves the replaced scope.

Target OpenAI Decisions, TypeSafe's hosted System One API for **Jev**, and a
separately configured loopback SystemOne-compatible endpoint. The developer
confirmed that “Zev” meant Jev; the unrelated `zev-rs` project is not selected.
No local engine, SDK, new dependency or live account eligibility is established.

| Package | Output and prerequisites |
| --- | --- |
| P30A | Versioned neutral text contract and pure OpenAI/System One wire subsets implemented; synthetic fixtures and finite experiment/benefit criteria prepared; fixed foundation baseline and incremental audit pass. [Developer contract](developer/decisions.md) |
| P30B | In progress: operator-only profiles, bounded owned HTTP, `host.decision`, Session/replay bindings, v3 usage/prices and shared budgets implemented; focused synthetic controls cover zero-egress refusal, hosted/compatible wire, tampering, owner loss, inert resume and child approvals. Full fixed-source/package baseline remains pending; live account access unverified. No qualified consumer is implied |
| P30C | In progress: [pure Knowledge planners and zero-call controls](archive/2026-10-26-p30-p31-implementation/p30c-pure-policy.md) have an [independent pure-scope audit and reporting correction](archive/2026-10-26-p30-p31-implementation/p30c-pure-policy-audit.md); protected helper integration and qualified consumer selection remain open after B and P31B |
| P30D | Implement bounded experiments: notes selection beyond the context budget and candidate assessment in replay/shadow mode on real main-tool inputs; after C and P31E |
| P30E | Evaluate frozen experiments against engine-free baselines and installed workflows; record useful, rejected/no-benefit and unverified dispositions plus separate live/model access; after D; document/graph routing is a later independently qualified addition |

Acceptance requires exact result count/type/range/distribution validation, valid
per-question refusal handling, uncertainty and malformed-output distinctions,
permission/reservation/journal admission before egress, cancellation during actual
work and zero dispatch on denial. Decisions choose within saved authority; they
never create evidence, establish truth, grant permission or silently switch a
model provider/paid service. Consent displays operation-specific pricing, endpoint,
processing/storage region, cache retention and verified/unknown account controls.
Freeze per-consumer quality, abstention, latency and cost bars before evaluation.
Hard protocol/integration gates must pass; completed negative experiments can close
D/E and P30 with **no qualified default consumer**. Missing access/incomplete evidence
stays unverified/open unless explicitly accepted as a qualification. Only useful,
qualified strategies become selectable; fitting note sets bypass retrieval decisions
without an extra call. Protocol success is not model quality.

## P31: usable knowledge and prompt assistance

**Active implementation track; P31A qualification and P31B host primitives in progress.**
Standalone native permission review and literal capture have component controls;
automatic capture, current recall and lifecycle management remain open. P30 numbering does not imply it
must finish first. P26/P27 retain
their completed original scopes, P20 remains completed and voice/media stays P32.
Implementation is authorized; release publication is not.

The selected outcome is automatic useful-fact/decision capture with visible changes,
permission remembered across sessions, retrieval before material clarification,
automatic routing only among enabled knowledge sources, and PDF/Word ingestion.
The audit follow-up adds these explicit choices: enablement takes effect in the
next new session; saved knowledge consent also applies to headless `run` without
`--yes`; graph/PDF may remain experimental/off under qualified completion; a narrow
Rust PDF-parser exception is allowed when maintained Elixir/Erlang options are
unsuitable. Workspace/shell/MCP/delegation authority remains separate.

The [current design](knowledge-design.md) is the single
detailed contract specification: proposed command vocabulary, main-model capture,
source intake, retention, worktree sharing, headless admission, process coordination,
document extraction, prompt editing and release qualification. This ledger owns
delivery status/dependencies and gates; do not duplicate its lifecycle prose here.
The developer's subsequent [local Ollama request](archive/2026-10-26-ollama-local-rag/index.md)
adds an optional embedding/RAG route: Qwen3-Embedding 0.6B and Qwen3.5 4B are the
primary qualification targets, with a smaller EmbeddingGemma 2 text challenger
and an available Qwen3.5 9B comparison. Model details and contracts live in the
[design](knowledge-design.md#optional-local-embeddings-and-rag), not this ledger.

| Package | Output and prerequisites |
| --- | --- |
| P31A | In progress: amended baseline archived; host ownership/contracts, nonpublishing interaction/pilot probes, storage/parser evaluation and human journeys prepared. Main-route pilot and frozen evidence checks in progress; independent intake labels/workload ratification and human/platform evidence remain open. See [record](archive/2026-10-26-p30-p31-implementation/index.md) |
| P31B | In progress: native input, actual-owner transactions, protected identity/control, managed Collection SDK and registered inference dispatch have local component controls and scoped independent audits. [Owned allocation inventory recovery](archive/2026-10-26-p30-p31-implementation/sol-recovery.md) now settles retained stages before counting and refuses sync errors; kernel admission is unchanged. Credential refresh is separated from the inference completion witness, with local controls. An unused [controlled owned-effect foundation](archive/2026-10-26-p30-p31-implementation/owned-effect-component.md) has scoped controls and independent review; its full baseline and inference integration remain open. Standalone full native permission review, next-session readiness, headless save and revocation have automated PTY controls. Actual publication and inert replay use synthetic workers. Endpoint recovery, integrated freshness and platform acceptance remain open. The verification host later moved to an unadmitted kernel; [the resulting native test refusals](archive/2026-10-26-p30-p31-implementation/kernel-profile-recovery.md) remain open. Allocation supports only explicitly reviewed local filesystems. See the [SDK record](archive/2026-10-26-p30-p31-implementation/managed-sdk-component.md) |
| P31C0 | In progress: authenticated SourceIndex list/read/quote, stable SDK proofs and host-normalized publication/source clocks have local Session/replay controls. Pure root dependencies and a same-view get/snapshot/visible-scan observation foundation have scoped controls, but are not wired into Session or current eligibility. Current managed eligibility/withdrawal, lineage and replay enforcement, exclusions, typed retention/suppression/export remain; after A/B; internal only. [Observation evidence and limits](archive/2026-10-26-p30-p31-implementation/same-view-observation-component.md); [normalization record](archive/2026-10-26-p30-p31-implementation/managed-normalizer-component.md) |
| P31C1a | In progress: versioned collection storage, reciprocal worktree admission, pure note/temporal policy, reclamation/import and measured full-import headroom have component controls. An actual managed capacity run stopped at 3,724 publications on a full metadata shard; its [failed 4,000-record target](archive/2026-10-26-p30-p31-implementation/managed-storage-continuation.md) remains open. Sustainable domain metadata and actual 30/90-day/annual-turnover qualification remain; after C0, **required before E release** |
| P31D0 | In progress: native capture artifact/build catalog, standalone permission review/status/revocation and next-new-session activation have local source controls. Retention management, separate local embedding/answer choices and installed notes acceptance remain; installed packaging depends on C1a. Optional local preset follows D1/F |
| P31E | Main-model capture with explicit proposal acceptance/input origin, stable-prefix turn-local recall/source paging and quality remediation, category receipts, correction/forget and reuse; after B/C1a/D0; **interim notes release checkpoint**, with integrated intake/cache/latency checks |
| P31C1b | Extend storage for document/graph collections, source versions/indexes, model/recipe-bound vectors and atomic rebuild capacity, durable work references where needed and safe P26/P27/released-notes migration; after C1a, prototype alongside E |
| P31D1 | Remaining knowledge/parser artifacts, catalog composition, optional local-model provisioning/identity/context checks and endpoint inference slots, installed upgrades; follows applicable B/C1b/F/G contracts; weights remain unbundled |
| P31F | In progress: DOCX extraction now reports partial coverage for external or unexamined relationships, with a format-specific v3 recipe and synthetic controls. Text/PDF/DOCX acquisition, change tracking, cited retrieval, no-extra-service quality remediation and a qualified optional Ollama hybrid/local-answer route remain; after C1b and required D1 packaging; Word can qualify independently of PDF |
| P31G | Source-bound automatic relationships, alias/conflict/time handling and correction; after E, with C1b for graph collections; qualifies separately from F |
| P31H | Research evidence transfer and cross-store lineage/invalidation; integrates each available E/F/G store without requiring unqualified optional backends |
| P31I | In progress: static ceilings deny durable research writes. The [main-Session enhancement integration](archive/2026-10-26-p30-p31-implementation/enhance-integration.md) adds experimental `/enhance`, native witnessed editing/acceptance, cancellation/source isolation, bounded questions and MCP catalog revalidation from the independently reviewed private prototype. Whole-source/platform qualification and live carryover remain open, alongside planning MCP reads and deferred decisions. Integrated knowledge/document clarification still needs E/F; this is not P31I completion |
| P31J | Integrated safety, quality, resource, installed-user, migration and whole-manual acceptance; records supported, experimental and unverified slices explicitly |

F and D1 develop together: parser/acquisition code can run in source fixtures
before packaging; F's installed acceptance requires D1's relevant artifacts.
Do not turn this integration relationship into a sequential implementation deadlock.
The early notes release waits for C1a's sustainable capacity, but not C1b, parsers,
automatic graph or P30. Safe exhaustion of the old State store is not release
acceptance. Publication still requires separate authorization. Core notes/recall
quality cannot borrow P27's result or the optional graph/PDF experimental allowance.

Acceptance gates:

- Ordinary installed users enable knowledge without manual builds/JSON/MCP, see
  accurate next-session status, use normal conversations and later recall, correct,
  forget and disable. Covered effects cause zero repeat permission prompts in chat
  or `run`; prove an eligible headless save while generated prose remains attributed
  or pending review and shell/workspace edits remain denied.
- Default capture uses host-validated tools on the selected main route, with all
  adapter protocols covered and live/model quality distinguished. No mandatory
  secondary extractor or new embedding account. Qualify small notes and larger
  document retrieval separately, including paraphrases and citation support. Decision
  cards require explicit `accept CODE`; bare yes never accepts them in the first
  release. Models supply exact quotes, not offsets. Standalone review preserves origin.
- The optional local route qualifies at least one explicit embedding/answer pair
  on frozen quality/resource gates, with guided setup, versioned preprocessing,
  unchanged-tag/weight-change handling, bounded atomic reindex, endpoint-wide
  contention and offline inference evidence. Distinguish local retrieval with a
  remote main model from fully local answers. No automatic model substitution,
  hidden downloads or mandatory embedding dependency. E does not wait for this F
  slice; failure leaves the local slice open pending repair or explicit scope
  acceptance, not covered by graph/PDF's experimental allowance.
- Preserve authority, evidence and lifecycle under secret/poisoned inputs, concurrent
  processes, revocation, cancellation, queued work, forged worktree membership, divergence, stale context,
  disabled-store forgetting and old-backup migration. Experimental labels waive
  none of these gates. Unknown effects never replay.
- Freeze and measure pilot-derived capture intake, history/compaction overhead,
  serialized prefix stability, cache partitions and TTFT, shared budgets, visible
  retention/category corrections, temporal history, multi-day use, turnover, parser
  fidelity and storage capacity. Verify enhancement on the default main ChatGPT route
  with dispatch-enforced draft effects, stable tools, cancelled-intent tests and
  preserved history. Complete Linux/macOS source/package/installed
  checks and independent user journeys; absent human-platform evidence stays open
  and needs explicit qualified acceptance at release, never an invented pass.
- PDF/Word and graph remain in delivery scope. The developer permits qualified
  P31 completion with graph/PDF quality failures retained as experimental/off,
  precisely documented with follow-up work. Core notes/recall, Word and safety gates
  remain required. Rewrite manuals for the actual shipped scope at each checkpoint.

Deferred: voice/media, universal historical-chat mining, unattended daemons,
team/cloud synchronization, unrestricted provider routing, live in-session artifact
activation, lossless context erasure and a general workflow framework.

## P32: voice and realtime media

**Deferred; unimplemented. Previously P31; older archives call it P28 or P24.**
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
campaign, before the separately deferred P26–P27 features and voice (now P32).
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
Instructions and skills cannot enable executable extensions, change billing or
grant effects. Explicitly trusted project configuration may select a provider and
billing route under the configuration rules; that trust grants no effect approval.
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
