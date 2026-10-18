# Development plan

Ipse is an MIT-licensed general-purpose local AI harness. Its core stays in
Elixir/OTP, with Rust for small OS helpers; target projects may use any suitable
stack. Prefer extensions, tools and inert skills for domain features, ordinary
OTP for ownership, and reviewed generic core changes for missing host invariants.
No mandatory workflow framework, service, database or hardcoded external endpoint.

This document owns priorities, scope and acceptance. The
[documentation map](index.md) owns navigation; developer contracts own API details;
[testing and evidence](developer/testing.md#current-evidence-and-next-checks) owns
actual verification. Historical test counts and execution narratives belong there,
not in competing current-status sections. The
[previous plan and knowledge design](archive/2026-10-17-before-self-hosting-review/index.md)
are preserved with provenance.

## Current priorities and status

P0–P22 are complete within the scopes summarized under
[completed milestones](#completed-milestones-p0p22). This does not establish all
provider/account combinations, unattended self-development or production knowledge
quality. Subscription, API and installed Ollama checks have separate
[provider verification](developer/testing.md#provider-verification-status).

P23 is complete within its one-shot text/accounting scope. P24 is the active gate.
The consolidated independent assessment of `a5912ab`/evidence `a21469e` has
returned without acceptance. It confirms the earlier repairs but identifies
required-extension cancellation leaving delivery blocked and abnormal Session
death freeing the lock before dependent work stops. It also requests a decision
on HTTP-pool loss and retains material independent SDK/sandbox coverage gaps.

The implemented repairs distinguish explicit host cancellation from unexpected
consumer loss and retain the session lock through an independent quiescence
guard. Separate completion owners fence admitted filesystem operations because
BEAM caller death alone does not prove IO completion. Pool loss remains fail
closed with explicit idle resume, and the HTTP guardian waits for supervised
children before releasing its slot.

The repaired runtime passed frozen source/native/package/installed checks; the
final source and tests passed hosted Linux/macOS verification at `e8f7ad5`.
Failed intermediate runs and their unconfirmed causes remain in the evidence
record. The 2026-10-18 focused subscription pass inspected the Git-exported
`86d4d69` snapshot and repair delta, but its safeguard interrupted the write-up.
The incomplete return supplies neither the requested finding detail nor a final
coverage matrix and does not close architectural acceptance. The operator then
explicitly approved running the baseline scan before closing that gate, targeting
remaining concerns without another architecture-review round. A private Ipse
cloud environment is published; Security Cloud requires a separate setup flow.
Its automatic environment was created and the one-time high-reasoning scan is
running against exact revision `8b4f706`; terminal results and triage are pending. The used
consolidated brief is archived, and no R/S/C/O sequence is scheduled. The
[register](developer/architecture-review-dispositions.md) owns dispositions and
remaining independent omissions; the [internal audit](developer/architecture-self-audit.md)
records implementation-side counterexamples and limits.
The operator's 2026-10-17 direction
puts independent architectural challenge, security review and a large supervised
self-development trial ahead of media. P24 now owns architecture/security
readiness; the former P24 voice/media scope moves to deferred P28. P25 compares
independent Codex and Ipse research, then uses Ipse to repair demonstrated gaps.
Production knowledge packages remain deferred P26/P27 work selected from those
findings. Recording these reviews does not launch external analysis, approve a
new source transfer or dependency, or select a production engine.

| Milestone or gate | Current state | Next result |
| --- | --- | --- |
| [P23: accounting and budgets](#p23-usage-cost-reporting-and-budget-controls) | Complete within selected scope; source/native/package/installed and hosted Linux/macOS passed | Retain accounting invariants through P24/P25 review and repairs |
| [P24: architecture and security readiness](#p24-independent-architecture-validation-and-baseline-security) | Repairs verified; focused report incomplete; baseline scan running at `8b4f706` under approved scan-first order | Read terminal results and triage, assess remaining architectural coverage and resolve applicable findings |
| [P25: comparative self-development](#p25-comparative-research-and-supervised-self-development) | Planned revised scope; unstarted | Independent Codex/Ipse research, Ipse-authored repairs, fresh acceptance runs and final architecture/security review |
| [P26: memory baseline](#p26-optional-working-and-long-term-memory) | Deferred; proposed scope subject to P25 decisions | Independently selectable working/long-term memory tools and optional lifecycle policies |
| [P27: research, graph and RAG](#p27-optional-research-graph-and-rag) | Deferred; proposed scope subject to P25 decisions | Configurable research/retrieval packages, graph augmentation and RAG |
| [P28: voice and media](#p28-voice-and-realtime-media) | Deferred; former P24 scope, unimplemented | Chained STT/text/TTS, then explicit realtime/media capability; no prerequisite for P24/P25 |
| [Apache-2.0 transition](#license-transition) | Requested; unimplemented | Separate verified license/package/documentation change after the agreed delivery scope |

Feature status, verified runtime behavior and independent architectural acceptance
are separate. The latest internal audit records its actual inspected boundaries,
counterexamples and omissions; it does not replace external coverage or freeze
P25's runner. Historical repair revisions, platform results and investigations belong in
[testing](developer/testing.md#current-evidence-and-next-checks).

Execution order:

1. Retain the verified consolidated repairs and disposition checks in the
   [internal audit](developer/architecture-self-audit.md) and
   [register](developer/architecture-review-dispositions.md). Resolve the recorded
   material independent coverage before accepting architecture. Following the
   interrupted focused report, the operator explicitly authorized the baseline
   scan first, retaining architectural acceptance as an open gate. Triage the
   remaining concerns and actual scan coverage before P25 execution.
2. Execute P25's independent research, discrepancy comparison, Ipse-authored
   repairs and fresh same-input/held-out reruns. Finish with an external
   architecture delta review and security review/rescan of the final candidate.
3. Select later P26/P27 production increments from the evidence. Keep P28 media
   deferred until explicitly scheduled; neither audio devices nor voice accounts
   block P24/P25. Resolve the separate license-transition placement before that
   change rather than allowing deferred features to hide its outstanding status.

Brief preparation and review-service access checks may precede scored execution.
Architecture review normally precedes the baseline scan to sharpen its threat
model; a recorded reason may reverse that order. Material repairs require review
of affected surfaces on the new revision. Address a new defect when found rather
than postponing it to preserve numbering. Earlier dated records retain their
original milestone names; current scheduling follows this plan.

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
[actual evidence](developer/testing.md#current-evidence-and-next-checks).
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

**In progress; focused report incomplete; scan-first order approved; architectural acceptance and baseline scan open.**
The external assessment of source `a5912ab` and evidence `a21469e` confirms the
previous ownership/egress/context repairs within its inspected scope. It found
no High/Critical defect there, but B-1's required-consumer cancellation and A1's
abnormal-death lock race were confirmed gaps. Before/after tests reproduce the old
behavior and verify the repairs.
Explicit host cancellation now releases confirmed extension-owned enrollments
while fresh input must reinitialize the same required selection. A separate
lock guardian survives Session death and fences replacement work until tracked
writer/tasks/scopes/resource and child guards exit. A real blocked-write probe
then showed that caller death does not prove filesystem IO completion, even in
raw mode. Admitted core writes, journal appends/repair and state/budget critical
sections now have separately tracked completion owners that core cancellation
does not kill. Their actual completion precedes unlock. Dispatch tracking covers
nested helpers and delegated children; uncertainty never authorizes replay.

Pool loss remains an explicit conservative Session stop with inert manual resume.
A rejected cooperative alternative left Finch's caller blocked. A controlled
probe also found the old HTTP guardian releasing its name while a supervised
child remained alive; it now waits for those children. Normal cancellation must
retain native-helper receipts before terminating nested task processes. The
repaired runtime passed the frozen local baseline and installed-artifact proofs.
The final source/test matrix at `e8f7ad5` passed on hosted Linux/macOS.
[Testing](developer/testing.md#current-evidence-and-next-checks) records exact
source, receipts and platform scope; none supplies independent acceptance.

Independent SDK authority and sandbox coverage remains materially incomplete.
Internal inspection and passing fixtures cannot close those external omissions.
The operator authorized a bounded completion on 2026-10-18, using a fresh
read-only Claude subscription session and a Git-exported `86d4d69` snapshot,
without prior critiques or implementation-side verdicts. Its safeguard stopped
the report during the first finding; the returned detail and coverage matrix are
incomplete despite the CLI's successful exit. Retained source reads and the
conditional opening judgment do not establish acceptance. The operator explicitly
authorized proceeding to the baseline scan, with architectural acceptance still
open and no further architecture-review round. The
[disposition register](developer/architecture-review-dispositions.md) retains the
cumulative checkpoint and current policy decisions; the
[operator review page](operator/architecture-review.md) owns execution details.
P25 remains gated on assessed architecture and triaged baseline results.

Torn-ledger continuation preserves the damaged tree and its liability; automatic
ledger repair remains unavailable. Synthetic startup still takes about 20 seconds
for 64 MiB with 200 answered questions; reducer changes did not materially reduce
that latency. These measured/accepted limits remain explicit in readiness decisions.
The [disposition register](developer/architecture-review-dispositions.md) owns
F1–F7, S1–S3, D1–D9, A1–A7 and PA-1–PA-15; [testing](developer/testing.md#current-evidence-and-next-checks)
owns exact revisions, counts and platform receipts.

The reports through `7810925` and the returned consolidated assessment of
`a5912ab` are static reviews with unrun proposals and explicit omissions. Preserve
their cumulative independent checkpoint and identify which later evidence closes
each material gap. The operator requested a full internal audit and one
consolidated handoff, which has now returned; no further separate external
R/S/C/O rounds are scheduled. The
[evaluation protocol](developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
keeps independent source assessment before dispositions and distinguishes
implementation-side coverage from external acceptance. No fixed number of reviews
can guarantee acceptance or absence of defects.

Retain explicit limits: journal growth/startup cost and same-size rewrite checks,
linear ledger reads/hashes, unknown liability, fail-closed shared overdraw and
unquarantined paid-response loss, pinned extension compatibility, and macOS
detached-descendant cleanup. Future memory migration/deletion proposals must
distinguish retrieval state from retained host evidence. Then run the triaged
baseline scan on the resulting exact revision. P25 execution remains gated;
repaired findings do not certify omitted surfaces.
Read-only Security Cloud checks on 2026-10-18 confirmed repository access and
available credits, with no matching environment. The operator then separately
approved creating and publishing a private environment and selected high reasoning
for the offered scan model. The environment is published, but Security Cloud's
environment discovery still returns no Ipse target. The scan UI instead provides
automatic environment creation, which the operator explicitly approved for the
one-time GPT-5.6 Sol/high repository scan, with monitoring off and no secrets.
The one-time scan started at `8b4f706` on 2026-10-18; its
[run record](operator/architecture-review.md#baseline-scan) identifies the exact
target and status. No terminal result, triage or billing-mode change is claimed.
Setup's ordinary suite had two container cleanup failures; the two
affected modules passed all 63 tests under a retained Rust subreaper, with no
source/assertion changes. A full suite under that launcher remains unrun and the
cloud host lacks required native enforcement. The root
[security context](../SECURITY.md) supplies the non-secret threat model and private
reporting policy. Setup does not close either review gate.

Challenge the foundation before the large self-development
trial. An external agent, such as Claude, reviews a pinned repository/design
packet independently of the implementation author and the Codex/Ipse research
tracks. The first pass does not receive our preferred verdict or either track's
report. This is an adversarial design review, distinct from a vulnerability scan
and from the later knowledge-design comparison.

Require concrete counterexamples and failure sequences against core/extension
boundaries; lifecycle ordering, subscriptions and backpressure; trust, private
grants and project/operator scope; ownership, cancellation, locking and no-replay
recovery; persistence/SDK evolution; accounting and unknown liability; and the
foreseen memory, research, graph/RAG and media seams. Test whether realistic
features fit existing extension APIs, need a justified generic enhancement, or
reveal a foundational defect. Do not add speculative core abstractions merely to
make every hypothetical feature possible without a future versioned enhancement.

Pin the brief, revision, packet manifest, model/provider, access and resource
limits. Select an available public interface and obtain any required source-share,
credential, billing or dependency approval before execution. Exclude secrets,
private journals and unrelated workspaces. An unavailable reviewer/service keeps
the gate open; another provider is an explicit choice, never a silent fallback.

Acceptance requires a retained critique and assumption/counterexample register,
independently checked findings, accepted/rejected-with-evidence/deferred
dispositions, regression or evaluation cases for applicable repairs, and a
triaged baseline OpenAI security audit on the resulting exact revision. Applicable
critical/high findings and foundational correctness gaps block affected execution
until repaired. Escalate unresolved material design choices to the operator.
Record residual risks and coverage limits; an agent's verdict is evidence to
evaluate, not authority to rewrite core or declare the design safe.

The [review and trial protocol](developer/self-hosting-evaluation.md) owns the
architecture-review procedure and security execution constraints. Prefer external
architecture review before scanning, then repair/refreeze as needed. P25 closes
the loop with a final architecture delta review and security review/rescan; P24's
baseline cannot certify later changes. The first external static review has run;
the baseline scan is running, with no completed scan or architectural acceptance
claimed.

## P25: comparative research and supervised self-development

**Planned revised milestone; unstarted.** Replace P25's production-engine delivery
with a large supervised evaluation using those engines as a research/planning
problem. Track A uses Codex; Track B uses stable installed Ipse. Both research
working/long-term memory, configurable research providers, graph and RAG, including
Zero-Mem and alternatives, then propose implementable P26/P27 designs. Each works
independently before comparison, with common requirements and recorded resource,
provider/model, retrieval and assistance differences.

The [evaluation protocol](developer/self-hosting-evaluation.md) owns the rubric,
artifact manifest, proposed round limits, held-out cases and review process.
The [knowledge design](developer/knowledge-extensions.md) owns domain questions and
selection gates. Existing P14 tools/skills/ledger and P22 SDK are available; engine
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
| F — final architecture, security and acceptance | External architecture delta review and OpenAI security review/rescan of the exact final candidate; disposition findings, verify repairs, publish sanitized evidence and the researched P26/P27 proposal |

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
scan is running; it is not P25 execution or completed security review. No recurring
monitoring is enabled and no new dependency is approved by this plan. See
[architecture validation](developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
and [security execution constraints](developer/self-hosting-evaluation.md#security-review-before-and-after-the-trial).

## P26: optional working and long-term memory

**Deferred; proposed scope after P25 selection.** Deliver useful independently
selectable session/task working-memory and cross-session memory capabilities,
initially explicit recall/remember/forget/export tools or existing MCP where that
meets the need. Add optional lifecycle recall/capture adapters only when justified.
Choose a configurable local baseline through the research gate; Zero-Mem is
inspiration, not a selected package or reproduced benchmark result.

Acceptance: default-off parity; explicit namespace/project/operator scopes;
stable logical identity with explicit export/migration/collection across artifact
and configuration-source versions; provenance, retention/TTL and conflicts;
approved bounded writes; concurrent forget without resurrection; derivative
deletion/export and distinct history-access/redaction, journal/backup and erasure
limits; cancellation and unchanged resumed recall. No mandatory store, embedding
model, remote service or silent promotion. Keep core conversation/recovery intact
when optional memory is off. Measure quality and resources separately from
protocol correctness; document actual dependency, configuration and recovery.

P25's research may change this split. No production backend is selected or started
by this proposal. See the authoritative [knowledge design](developer/knowledge-extensions.md).

## P27: optional research, graph and RAG

**Deferred; proposed scope after P25 selection.** Build independently useful
research orchestration, graph augmentation and corpus retrieval packages on
P14/P22/P23 and selected shared knowledge contracts. Prefer explicit tools and
existing MCP adapters before hooks or services. Memory, research, graph and RAG
must remain independently configurable; enabling one does not enable the rest.

Acceptance: named pluggable search/fetch/store/retrieval/embedding/rerank profiles;
source/chunk/version/citation identity; bounded ingestion/traversal/retrieval;
lexical operation without mandatory embeddings; deletion propagation and stale
index policy; contradictory/stale/weak evidence; partial failures, cancellation,
budgets and no automatic replay. Evaluate algorithm quality on held-out workloads,
then separate opt-in live evidence from credential-free source/package fixtures.
No framework, database or provider is mandated. P25's findings determine delivery
order and any justified generic host enhancement before implementation selection.

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
See [media boundaries](developer/runtime-capabilities.md#text-and-media-are-distinct-from-diagnostics).

## License transition

The operator requested MIT → Apache-2.0 after the extension work. That request
remains open. Production knowledge implementation and former-P24 media are now
deferred, so the exact transition point needs to be settled against that changed
scope. The proposed placement is after P23 and the P24/P25 review/trial gates,
before a later optional-feature campaign. Confirm that placement with the operator
before changing the license; do not silently interpret “after all this” as either
including or excluding deferred P26–P28 work. This planning edit changes no license.

The eventual separate change must replace Ipse's license and bundled copies,
reconcile current README/contribution/operator/developer guidance and packaging
notices, verify artifact identity/package checks and preserve third-party licenses
and historical provenance. Commit and push the verified transition separately.

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
[P0 closure](developer/testing.md#p0-closure-on-serenity-2026-10-15).

## P1: make everyday use clearer

Complete: line-oriented running/waiting/cancelled/finished states, EOF/queued-input
and unknown-effect recovery checks. Skills remain explicit, bounded and inert.
See [verification](developer/testing.md) and [operator usage](operator/usage.md).

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
[P2 evidence](developer/testing.md#p2-context-compaction-2026-10-15).

## P2b: define an OS sandbox boundary

Complete for the optional Linux native profile's tested filesystem/network/process/
resource boundary. Trusted execution remains the default; requested native policy
fails closed. Mac enforcement and best-effort descendant lifetime have distinct
limits. See [sandbox contract](developer/sandbox.md),
[Linux evidence](developer/testing.md#p2-native-linux-sandbox-2026-10-15) and
[Mac boundary](developer/sandbox.md#macos-production-boundary).

## P3: workspace context from any directory

Complete: launch/explicit working directory, bounded scoped instruction snapshots,
provenance and deterministic resume/refresh, with coding and non-coding trials.
Shell target scope can remain unknown; instruction path checks are not an OS
sandbox. See [contract](developer/workspace-context.md) and
[evidence](developer/testing.md#p3-workspace-context-2026-10-15).

## P4: packaging and protocols

Complete within Linux/macOS source/archive verification and separate MCP/delegation
protocol design scope. Packages identify OS/architecture/libc and include notices;
fresh extraction checks do not establish all architectures or signing/notarization.
Windows and adversarial detached-descendant termination on Mac remain outside scope.
See [evidence](developer/testing.md#p4-release-verification-and-protocol-proposal-2026-10-15).

## P5: local MCP tools

Complete: explicit stdio tools, bounded descriptors/allowlists, schema validation,
full approvals, durable intent and owned transport/no-replay recovery using reused
MCP/schema packages. Source, extracted and scoped live checks are recorded in
[P5 evidence](developer/testing.md#p5-local-mcp-2026-10-15); arbitrary servers are
not certified by the demo. See [MCP contract](developer/mcp.md).

## P6: local subagent delegation

Complete: opt-in serial local children, separate journals/approvals, bounded
context/results, parent ownership and no recursive delegation/child MCP. See
[delegation contract](developer/delegation.md) and
[P6 evidence](developer/testing.md#p6-local-delegation-2026-10-15).

## P7: expanded MCP capability

Complete within bounded local resources/prompts and pinned independent-server
interoperability. Ordinary stdio cleanup repairs do not remove the documented Mac
detached-child limit. See [P7 evidence](developer/testing.md#p7-expanded-local-mcp-2026-10-15)
and [second-server coverage](developer/testing.md#second-independent-local-mcp-server-2026-10-15).

## P8: bounded skill resources

Complete: explicit source-bound `load_skill_resource`, bounds, provenance and
inert resume; loading does not run scripts or install dependencies. See
[P8 evidence](developer/testing.md#p8-skill-resources-2026-10-15).

## P9: parallel local subagents

Complete: opt-in two-child groups, separate approval routing, bounded scheduling,
results and cancellation. Serial remains default; P23 separately adds atomic shared
token/cost reservations. See
[P9 evidence](developer/testing.md#p9-parallel-local-delegation-2026-10-15).

## P10: network MCP

Complete: explicitly configured MCP Streamable HTTP POST with JSON/finite SSE,
verified TLS, server-specific credentials, limits, exact approvals and no replay.
Redirects/retries, OAuth negotiation, GET subscriptions and reconnection are not
implemented. Remote cancellation is best effort. See
[contract](developer/mcp.md#streamable-http-boundary) and
[P10 evidence](developer/testing.md#p10-streamable-http-mcp-2026-10-15).

## P11: live dotsetup trial

Complete within read-only project/next-step assessment and selected Ipse follow-ups:
Bash descriptor compatibility, sandbox visibility facts and project-orientation/Git
skill guidance. Existing dotsetup edits were preserved; no dotsetup coding/deployment
or GitHub adapter trial was performed. Multi-repository read roots remain separate.
See [comparison](developer/testing.md#p11-live-project-assessment-2026-10-15) and
[repairs](developer/testing.md#native-bash-and-visibility-repair-2026-10-15).

## P12: task tracker coding trial

Complete in a separate app workspace: forms/SQLite CRUD, validation, persistence,
independent review and layout checks. Elixir was imposed by the test operator, so
this did not prove neutral stack selection. Long-turn limitations led to P13.
See [P12 evidence](developer/testing.md#p12-task-tracker-coding-trial-2026-10-15).

## P13: long-turn compaction and general-purpose trials

Complete: safe long-turn checkpoints/diagnostics, a neutral-stack task tracker
(Ipse chose Python/Flask) and a source-backed non-coding task. Ipse's implementation
language does not constrain target workloads. These are bounded trials, not
unrestricted task coverage. See [compaction](developer/testing.md#p13-long-turn-compaction-2026-10-16),
[coding](developer/testing.md#p13-neutral-stack-coding-trial-2026-10-16) and
[non-coding](developer/testing.md#p13-non-coding-document-trial-2026-10-16) evidence.

### First supervised self-development trial

Complete: frozen installed Ipse authored shared operator skill discovery in a
separate candidate, with independent checks, approved effects and idle resume.
The trial exposed and repaired bundled launcher environment contamination of
system Mix. See [integration evidence](developer/testing.md#shared-skills-questions-configuration-and-profiles-integration-2026-10-16).
Later P18/P21/P22 trials broadened this supervised evidence; P25 proposes a larger
comparative evaluation without claiming unattended self-development.

## P14: bounded deep research

Complete: inert research skill, configured provider-agnostic MCP retrieval and
bounded durable source/claim ledger/export, plus an independently checked live
primary-source trial. No mandatory search service, recursive research engine or
production knowledge backend. See [research contract](developer/research.md) and
[five-stage evidence](developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P15: scoped configuration and shared operator skills

Complete: bounded versioned JSON/provenance and trusted scoped selections;
project > Ipse user > shared operator `~/.agents/skills` > bundled precedence.
Project text cannot enable executable extensions, change billing or grant effects.
See [operator configuration](operator/configuration.md),
[developer contract](developer/configuration.md) and
[integrated evidence](developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P16: explicit model profiles and task routing

Complete: named profiles and main/routine/review roles, supported provider settings,
explicit child selection and credential/native-payload isolation. A stronger
subscription main/local Ollama child trial passed; no hidden billing/provider
fallback or automatic summary routing is claimed. See
[profiles](operator/model-profiles.md) and
[integrated evidence](developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P17: structured operator questions

Complete: validated single-choice, multiple-choice and text answers, explicit
submission, durable waiting/resume, cancellation/EOF/headless behavior and separate
approval authority. Child questions and MCP elicitation remain unsupported.
See [contract](developer/operator-questions.md) and
[integrated evidence](developer/testing.md#five-stage-integrated-verification-2026-10-16).

## P18: supervised self-development on the operator's Mac

Complete: frozen-runner `sessions --json` change, structured clarification,
independent local Mac/native/package checks, bounded review and hosted Linux/Mac
verification before PR #1 merged. Review budget exhaustion, supervisor assistance
and safe context refusal remain recorded. See the
[Mac runbook](operator/self-development.md) and
[local evidence](developer/testing.md#p18-macos-supervised-self-development-evidence).

## P19: long-session diagnosis and recovery

Complete: content-free context/timing diagnostics and explicit reviewed handoff
without silently trimming native continuation or intent. Synthetic fixtures
reproduce the failure shape, not a private original Mac transcript. See
[observability contract](developer/observability.md),
[operator recovery](operator/recovery.md) and
[P19 evidence](developer/testing.md#p19-diagnosis-and-explicit-recovery).

## P20: repeatable supervised self-development

Complete: inert bundled self-development skill/resources, credential-free real
Session fixture and supervised live use. Existing approvals, profiles and journals
supply the boundaries; there is no mandatory workflow engine. See
[P20 evidence](developer/testing.md#p20-reusable-self-development-skill).

## P21: larger self-development trial on Serenity

Complete: Ipse-authored fresh-chat handoff import from a frozen P20 runner,
independent Linux/package checks, separate bounded live review and hosted Linux/Mac
checks. Repeated orientation needed supervisor narrowing; a reviewed manual handoff
and unchanged idle resume were exercised. See
[P21 evidence](developer/testing.md#p21-supervised-serenity-trial-and-independent-checks).

## P22: extension scaffold and lifecycle hooks

Complete within the SDK contract at `de073ba`: immutable artifacts, explicit scoped
trust/selection, independent workers, typed hooks/invocations/host calls, state,
context/evidence, services, questions, approved actions, owned jobs, source-bound
history/events/feeds and private visible-text channels. Diagnostics have independent
off/local/export controls, bounded retention and synthetic developer tracing.
Two shipped prompt/presentation examples are default-off.

The [architecture/comparison](developer/extensions.md),
[adoption scenarios](developer/extension-scenarios.md) and
[lifecycle coverage audit](developer/lifecycle-events.md#supported-lifecycle-coverage)
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
[completion evidence](developer/testing.md#supervised-extension-only-trial-2026-10-17).
