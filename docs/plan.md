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

P23 is the active implementation milestone. P24 remains authorized. The operator's
2026-10-17 input proposes making P25 a larger comparative research and supervised
self-development evaluation, with security reviews before and after its changes.
Production knowledge features move to later P26/P27 work. The protocol and split
below are proposals for review; recording them does not launch scans, authorize
new dependencies or start production engine implementation.

| Milestone or gate | Current state | Next result |
| --- | --- | --- |
| [P23: accounting and budgets](#p23-usage-cost-reporting-and-budget-controls) | In progress; configured own-session/child reports and supported request output caps | Atomic host reservations/reconciliation and accounted extension model operations |
| [P24: voice and media](#p24-voice-and-realtime-media) | Authorized; unimplemented | Chained STT/text/TTS, then explicit realtime/media capability |
| [P25: comparative self-development](#p25-comparative-research-and-supervised-self-development) | Proposed revised scope; unstarted | Independent Codex/Ipse research, measured discrepancies, Ipse-authored repairs and fresh acceptance runs |
| P25 security gates | Proposed; no service access or scan verified | Baseline audit before broad self-development and final-candidate review/rescan afterward |
| [P26: memory baseline](#p26-optional-working-and-long-term-memory) | Deferred; proposed scope subject to P25 decisions | Independently selectable working/long-term memory tools and optional lifecycle policies |
| [P27: research, graph and RAG](#p27-optional-research-graph-and-rag) | Deferred; proposed scope subject to P25 decisions | Configurable research/retrieval packages, graph augmentation and RAG |
| [Apache-2.0 transition](#license-transition) | Requested; unimplemented | Separate verified license/package/documentation change after the agreed delivery scope |

The P23D baseline at `84597b4` passed
[hosted Linux/macOS verification](https://github.com/lexlapax/ipse/actions/runs/39046213259),
including both packages, the installed extension lab and applicable Mac enforcement.
The preceding `03d4187` run failed one Mac MCP fixture; eleven focused Linux
catalog tests passed and the new hosted run did not reproduce it. No transport
repair or deadline change was made; its original cause remains unconfirmed.
Later runtime increments need their own verification.

Recommended order: finish P23; deliver P24 as
already requested; freeze the P25 candidate and run its baseline security audit;
then execute the comparative research/repair/rerun cycle and final security review.
P25's text/research trial has no technical dependency on audio devices or a live
voice account. If those need operator action, independent P25 preparation can
proceed without representing P24 as complete. P26/P27 wait for the research outcome
and a selected implementation scope. A material new defect is addressed when
found rather than deferred merely to preserve milestone numbering.

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

**In progress.** The [usage contract](developer/usage-accounting.md) supplies durable
request/attempt/provider/billing/model facts separately from diagnostics. The
[configured cost implementation](developer/costs.md) and
[operator guide](operator/usage-accounting.md) define the available reports:

| Increment | Implemented scope |
| --- | --- |
| P23A | Pure versioned rate-card estimator with exact configured identities, fixed-point arithmetic, cache partitions, provenance and explicit unknown/partial values |
| P23B | Separately granted own-session `usage.read`, fixed prefixes, source-bound cached recovery and default-off `builtin:cost-report:1` pages |
| P23C | Finite separately granted full own-session enumeration and default-off `builtin:cost-summary:1`, cumulative request replacement and overflow/legacy handling |
| P23D | Explicit registered-child discovery/reads and default-off `builtin:cost-tree:1`, frozen accounting prefixes, exact origins and visible missing/busy/invalid/legacy/cleanup gaps |
| P23E1 | Explicit supported provider output ceilings, narrowed child/summary caps and saved-policy resume |

[Provider output ceilings](developer/provider-limits.md) apply only to supported
API/Ollama requests. ChatGPT subscription refuses the unsupported setting; no
output-token ceiling is invented for that public interface. Local source/package
and 41-assertion installed-lab checks passed; this runtime increment needs its own
hosted result. See [actual evidence](developer/testing.md#current-evidence-and-next-checks).
Atomic shared reservations and accounted extension model operations remain open.

These reports do not enforce budgets, produce a globally atomic tree balance or
promise an invoice ceiling. Rates are configured; subscription equivalents,
API estimates and local inference resource costs remain distinct. Missing usage
or failed-child cleanup cannot be converted to zero liability.

Remaining acceptance:

1. Add optional host-owned admission and durable atomic reservation/reconciliation
   for covered main, summary, parallel-child and extension requests. Reserve before
   dispatch, account for actual/partial/unknown results and retain uncertain
   liability through cancellation, owner death and resume. A callback or report
   cannot enforce admission; durable recovery must not reset quotas or replay work.
2. Add generic versioned accounted model operations for extension extraction and
   other selected supported request types. Explicit profiles, private data grants,
   provider limits, cancellation and canonical usage apply; no unaccounted model
   calls inside hooks. Refuse unsupported operations, including embeddings until
   their separate public provider/accounting contract is implemented.
3. Document configurable limits, coverage and provider-enforceable output bounds.
   Keep cost/token estimates honest where input or in-flight liability cannot be
   bounded exactly. No mandatory pricing service or hardcoded price/model choice.
4. Prove parallel contention, refusal-before-dispatch, reconciliation, missing or
   corrupt durable policy/state, partial failures and inert recovery with fixtures.
   Verify reports and the independent installed extension lab on the new candidate;
   close source/package and supported-platform checks with actual evidence.

## P24: voice and realtime media

**Authorized; unimplemented.** Build on the owned text/provider and P23 accounting
foundation. Start with a chained STT → admitted text agent → TTS extension/client;
then add a versioned realtime provider/session capability for bidirectional
transport, interruption, turn control, playback acknowledgment and reconciliation
of generated versus played history.

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

## P25: comparative research and supervised self-development

**Proposed revised milestone; unstarted.** Replace P25's production-engine delivery
with a large supervised evaluation using those engines as a research/planning
problem. Track A uses Codex; Track B uses stable installed Ipse. Both research
working/long-term memory, configurable research providers, graph and RAG, including
Zero-Mem and alternatives, then propose implementable P26/P27 designs. Each works
independently before comparison, with common requirements and recorded resource,
provider/model, retrieval and assistance differences.

The [evaluation protocol](developer/self-hosting-evaluation.md) owns the proposed
rubric, artifact manifest, round limits, held-out cases and security process.
The [knowledge design](developer/knowledge-extensions.md) owns domain questions and
selection gates. Existing P14 tools/skills/ledger and P22 SDK are available; engine
installation or production implementation is not required by this milestone.

| Phase | Deliverable and gate |
| --- | --- |
| A — freeze and baseline audit | Pin task/rubric, source packet, runner/candidate, profiles, tools and resource limits; run and triage OpenAI security audit before broad self-development |
| B — independent research | Frozen A/B reports, primary-source/claim ledgers, alternatives, architecture, dependency/license review and implementation proposals; common-packet and live-research comparisons |
| C — evidence-based comparison | Codex reviews both reports against the sources and common rubric; record material discrepancies, root-cause hypotheses, uncertainty and supervisor assistance |
| D — Ipse-authored repairs | Stable Ipse develops meaningful harness/extension/skill fixes with regressions and documentation in a separate candidate; Codex independently reviews and verifies |
| E — fresh reruns | Clean same-input and held-out evaluations after fixes; real behavior change, context pressure, operator question, interruption/resume and independent review, plus source/native/package/platform checks |
| F — final security and acceptance | Review/rescan the exact final candidate, disposition findings, publish sanitized evidence and the researched P26/P27 proposal |

Research acceptance means source-supported correctness, required coverage and a
useful implementation plan at comparable declared limits. Codex's report is a
reviewed reference, not unquestionable truth or a wording template. Both tracks
must satisfy minimum criteria; justified alternative decisions can pass. Proposed
bounds are three repair rounds and two independent final Ipse runs, with no material
factual/citation errors or unresolved critical/high security issues. Pin actual
limits before execution; exhausted limits produce a residual-gap report, not an
unbounded attempt to force agreement.

Self-development acceptance additionally requires at least one meaningful
Ipse-authored behavior change and independently verified regression tests. Record
supervisor-authored repairs and manual interventions honestly. A report comparison
alone, copied Codex conclusions or a synthetic extension lab cannot close this gate.
Promote a new frozen runner only after independent review and checks; preserve old
reports/runtimes and validate held-out cases rather than tuning a single answer.

Use OpenAI Codex Security for baseline and final reviews. The hosted route is
preferred to adding local tooling, subject to actual account/repository access
and revision coverage. Scan status and coverage are separate; findings need
triage and fixes need regression evidence. Raw findings stay private. No scan has
run, no recurring monitoring is enabled and no new dependency is approved by this
plan. See [security execution constraints](developer/self-hosting-evaluation.md#security-review-before-and-after-the-trial).

## P26: optional working and long-term memory

**Deferred; proposed scope after P25 selection.** Deliver useful independently
selectable session/task working-memory and cross-session memory capabilities,
initially explicit recall/remember/forget/export tools or existing MCP where that
meets the need. Add optional lifecycle recall/capture adapters only when justified.
Choose a configurable local baseline through the research gate; Zero-Mem is
inspiration, not a selected package or reproduced benchmark result.

Acceptance: default-off parity; explicit namespace/project/operator scopes;
provenance, retention/TTL and conflicts; approved bounded writes; concurrent
forget without resurrection; derivative deletion/export and clear journal/backup
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

## License transition

The operator requested MIT → Apache-2.0 after the extension work. That request
remains open. With production knowledge implementation now deferred, the proposed
placement is after the agreed P23/P24/P25 delivery and audit gates, before a later
P26/P27 implementation campaign. Confirm that revised placement with the operator
when finalizing the revised delivery scope; do not silently reinterpret “after
all this” or change the license during this planning edit.

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
results and cancellation. Serial remains default; atomic shared token/cost
reservations remain P23 work. See
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
