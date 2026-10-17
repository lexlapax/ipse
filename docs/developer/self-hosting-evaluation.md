# Comparative research and supervised self-development

Proposed P25 protocol, revised 2026-10-17. This guide defines the experiment;
the [plan](../plan.md#p25-comparative-research-and-supervised-self-development)
owns scheduling and acceptance status. No comparative run or security scan is
claimed here. Use the [operator runbook](../operator/self-development.md) for
runner/candidate separation and the [knowledge design](knowledge-extensions.md)
for the research questions. Production knowledge packages are deferred to P26/P27.

The experiment asks two separate questions: can Ipse produce a reliable,
implementable research proposal, and can it develop and verify improvements to
its own harness under supervision? A good report alone answers only the first.
Prior P18/P21/P22 trials establish narrower capabilities and remain useful evidence;
they do not establish this larger trial's result or unattended self-development.

## Freeze the task and comparison

Before either track starts, commit a common brief, rubric and public/synthetic
input manifest. Record the repository revision, installed runner archive digest,
toolchain/OS, skills, extension artifacts and supported capabilities. Keep private
run state outside the candidate and out of Git. Freeze a baseline runner and a
separate candidate worktree; the author never replaces its running executable.

Require a passing runner baseline before scored execution, including resolution
of applicable failures recorded in [current verification](testing.md#current-evidence-and-next-checks).
Preparing the brief, checking service access and choosing resources can proceed
while a prerequisite is open. Audio/device acceptance is not a prerequisite for
this text/research trial. Separate an unavailable capability from a failed trial;
neither can be recorded as a pass.

The brief covers working and long-term memory, configurable research providers,
graph augmentation and RAG. Each track must inspect current Ipse contracts,
research primary sources and alternatives, then produce a recommended architecture,
tool/skill/MCP/extension/core allocation, dependency/license decisions, evaluation
design, failure/security analysis and staged P26/P27 proposal. Include Zero-Mem
as inspiration and distinguish the paper, authors' code and independent projects.
An explicit decision to reject a candidate is a valid result when supported.

Organize the work into reviewable packages: current-harness/API assessment;
candidate/source discovery; comparative architecture and evaluation design;
and the discrepancy-driven authoring, verification and rerun cycle. Retain an
intermediate artifact and resource/intervention record for each package. Pin the
size and resource limits in the brief rather than expanding them after results
arrive. This makes the larger test measurable across sessions and checkpoints.

Use two complementary comparisons:

| Comparison | Purpose | Controls |
| --- | --- | --- |
| Common evidence packet | Compare analysis and planning without search-access differences | Identical captured sources/digests and task inputs; no access to the other report |
| Independent live research | Exercise search, fetching, evidence capture and synthesis end to end | Same question, cutoff, permitted public sources and comparable declared resource limits; record tool/provider differences and unavailable access |

Run independent live discovery before releasing the curated packet, or use
isolated cohorts with no packet/report access. Build the common packet against
the brief's coverage criteria and record its selection method; do not choose only
sources that support Track A's preferred design. Fresh sessions must not inherit
the other track's reports through files, memory, skills or handoff artifacts.

Configure provider, model, supported reasoning effort, billing identity, retrieval
endpoints and credential references explicitly for each track. Prefer the same
main model/settings where both interfaces support them. Record requested and
reported identities and unavoidable differences; an alias cannot establish an
identical backend. Never change profiles, billing or endpoints to rescue a run
silently. Ipse uses its own auth, not Codex's credential files.

Pin maximum wall time, requests, context/output limits, retrieval calls, money
where estimable and allowed supervisor interventions before execution. Unknown
usage remains unknown; subscription equivalents, API estimates and local resources
remain separate. Include compaction, review, retries and helper/model work in the
resource record. If P23 lacks a required hard limit for the selected operation,
close that prerequisite or document a supervisor-enforced limit before starting.
Do not describe a report estimate as an invoice ceiling.

## Independent tracks and review

Track A uses Codex. Track B uses the installed stable Ipse with normal skills,
tools and explicitly enabled extensions. Both may ask structured questions;
record each answer and provide task-relevant clarifications to both tracks.
Record environment repairs, extra instructions and supervisor edits as assistance.
Keep outputs separate until the initial reports and source ledgers are frozen.
Parallel execution is optional; independent inputs and outputs matter more than
simultaneous timing. Ipse subagents remain explicitly opt-in, with existing
approval, child-MCP and recursion restrictions.

Codex compares the reports criterion by criterion against captured sources and
the task, writing a discrepancy register. Review Codex's own claims with the same
checks. A shared error in both reports still fails; a justified Ipse alternative
can pass even when Codex chose differently. Have the operator adjudicate unresolved
material design choices or disputed evidence rather than declaring Codex infallible.
Do not collect or export hidden model reasoning as evaluation evidence.

Use the following proposed scoring scheme, fixed before the first scored run:
0 = missing/incorrect, 1 = material gaps, 2 = meets the brief with supported
evidence, 3 = exceeds it with useful independently verified analysis.

| Criterion | Evidence needed for a score of at least 2 |
| --- | --- |
| Coverage and decisions | Every requested family has alternatives, rationale, scope and an implementation form; optional components remain independently selectable |
| Source fidelity | Decision-driving claims map to inspected primary sources/revisions and relevant excerpts; dates, conflicts, uncertainty and unsupported claims are explicit |
| Ipse fit | Implemented APIs are distinguished from missing capabilities; core invariants remain host-owned and domain logic uses available SDK/tools |
| Privacy and security | Scope, egress, prompt injection, permissions, retention, provenance and concurrent deletion/no-resurrection are addressed |
| Reproducibility and dependencies | Exact candidates, licenses, runtime constraints, configurable endpoints and a reproducible evaluation are provided |
| Resource and failure behavior | Quality, latency, usage and operational tradeoffs; unknown costs, cancellation, partial effects and no-replay recovery are represented |
| Delivery usefulness | An implementable P26/P27 sequence with measurable acceptance, operator configuration/recovery guidance and explicit unresolved choices |

Proposed research acceptance: every criterion scores at least 2, no unresolved
material factual/citation error, permission violation or critical/high security
defect, and Ipse's total is no more than two points below the independently checked Codex
reference under comparable limits. Codex must also meet the minimum; otherwise
repair or replace the reference instead of lowering the bar. This small evaluation
supports a bounded capability claim, not statistical equivalence across all tasks.

## Turn discrepancies into Ipse-authored improvements

For each discrepancy record the requirement, report location, source evidence,
severity, likely cause, reproduction and proposed repair. Distinguish harness
defects, missing tools/SDK operations, workflow/skill problems, model/provider
limitations and unresolved causes. Reproduce suspected harness defects with
synthetic fixtures before assigning them to core. An extension or skill is often
enough; missing host invariants require a reviewed generic core change.

Ipse authors selected repairs in the candidate, including meaningful regression
tests and coherent operator/developer documentation. Codex reviews the diff and
checks evidence independently. If Codex must author a repair, record that intervention
and give the improved installed Ipse a fresh authoring task; do not relabel the
supervisor's change as self-development. Promote only a reviewed, verified commit
to the next frozen runner and retain every prior runner/artifact identity.

The larger trial must include at least one meaningful Ipse-authored behavior
change, either an extension/workflow capability or a justified generic core repair,
with independently verified tests. Research-only editorial improvements cannot
close the self-development gate. If no research discrepancy yields a useful
behavior change, select a separately scoped harness acceptance task without
building a production P26/P27 engine merely to manufacture work.

Exercise a multi-stage task across an idle stop/resume and deliberate context
pressure, plus cancellation or an interrupted proposed effect. Verify original
journals, explicit unknown-effect inspection and no automatic inference/effect
replay. A safe context refusal is an observed boundary, not automatically a defect.
Use reviewed handoff when needed and measure the intervention. Include one
independent review session with a realistic declared budget and an explicit
operator question. Existing process/OS limitations remain applicable.

## Reruns and stopping rules

Keep the original reports immutable. Rerun in fresh sessions against the same
inputs after each repair, and add fresh held-out questions/cases hidden from the
author during fixes. Examples include conflicting temporal memory, concurrent
forget/indexing, a misleading fetched instruction, an unavailable provider and
an incomplete citation. Release a held-out case after scoring; use another fresh
case in a later round. These cases test the proposed designs and source reasoning;
they do not require a production knowledge engine. Keep research-quality scoring,
deterministic harness regressions and actual self-development behavior distinct.
Production algorithm benchmarks remain P26/P27 work.

Proposed initial limit: three repair rounds, with two independent final fresh
Ipse runs, including held-out cases, meeting the rubric within the declared limits.
Record score variability and assistance. An exhausted round/time/resource budget
produces an incomplete trial and a residual-gap report; it never implies parity
or authorizes automatic expansion. The operator may explicitly extend a trial.
Do not train the report toward particular wording or weaken the rubric after
seeing results. If model or retrieval access changes materially, start a new
comparison cohort with a new pinned reference.

Independently verify actual build/format/compile/tests, native checks on supported
hosts, demo, extracted package and installed-extension compatibility for the final
candidate. Linux checks run on Linux; macOS evidence comes from a real Mac/hosted
Mac run, with local operator checks distinguished from hosted results. Report
failures, exclusions and untested integrations. A changed core needs a new
compatibility run; P22's historical frozen proof cannot certify later commits.

## Security review before and after the trial

Use OpenAI's Codex Security for a baseline repository audit before broad
self-development, then review the final changes and rescan the final candidate.
Prefer [Codex Security Cloud](https://learn.chatgpt.com/docs/security/setup): it
scans connected GitHub repositories in a cloud environment. Workspace entitlement,
the caller's GitHub connection and repository access must be verified at execution;
their availability has not been tested here. Confirm the actual scanned revision,
terminal status, validation evidence and coverage before accepting results.

The local [Security scan guidance](https://learn.chatgpt.com/docs/security/plugin/scans)
describes repository/folder scans, security context and coverage review; its
[change review](https://learn.chatgpt.com/docs/security/plugin/code-changes) is a
separate diff-focused option. These local modes are alternatives if hosted
coverage cannot target the required revision, not assumed Cloud features.
The [standalone CLI](https://learn.chatgpt.com/docs/security/cli) requires Node and
Python. Installing it for this repository would require the explicit external
dependency approval and inventory entry; this proposal adds neither dependency.
No silent fallback to API billing, local installation or recurring monitoring.

Prepare reviewed, non-secret threat-model context before scanning. A root
`SECURITY.md` can hold persistent security context/reporting guidance when that
work begins; reconcile it with existing policies rather than creating duplicate
instructions. Prioritize these Ipse-specific surfaces:

- Repository/config/skill/model text crossing instruction, extension trust and
  permission boundaries; installed artifact/runtime pins and private grants.
- Approval argument binding, durable intent/outcome validation, unknown effects,
  resume/catch-up, forged records and interrupted imports.
- Credential/TLS/redirect handling, scoped filesystem/native helper boundaries,
  cross-process locks and owned process/stream/worker shutdown.
- Resource exhaustion, parallel accounting/reservations, private prompt/tool/text
  views, tracing egress and source-bound recall/storage/deletion.

Scan only the selected repository snapshot in a disposable, least-credential
environment. Exclude ignored `.env`, auth/session files, private journals and
unrelated workspaces; do not upload a copy of the operator home. Review cloud
setup scripts, network access and source-transfer scope. Keep raw findings and
exploit details private outside Git; commit only reviewed sanitized evidence and
fixes. No automatic public issue, report, dependency installation or publication.

Triage each finding against actual reachability, existing trust assumptions and
validation evidence. Track accepted, rejected-with-reason and unresolved findings
with the affected and repaired revisions. Critical/high applicable issues block
the trial's broader execution or final acceptance until repaired; other findings
need an explicit disposition and residual-risk record. Fixes get focused
regressions and independent review. A failed/incomplete scan or inaccessible
service remains an open gate, and no-findings does not establish security.

After the final fix, rerun applicable validation and security review against the
exact final candidate. Any later runtime/security change invalidates that final
review for the changed surfaces. Keep before/after scan IDs, revision identities,
coverage limitations and dispositions alongside the experiment evidence.

## Evidence and completion record

Retain a versioned manifest tying together the common brief/rubric, source packet,
private artifact references, actual provider/tool settings, immutable A/B reports,
claim ledgers, scores, discrepancy register, operator interventions, Ipse-authored
commits, runner upgrades, tests/packages/CI, held-out reruns and both security
reviews. Public evidence must be sanitized; artifact existence is not a claim
that its private contents were reviewed.

P25 completes only after both research and self-development gates, security
dispositions and relevant platform/package checks pass, the operator has reviewed
material choices, and documentation/links are reconciled. Publish a conclusion
that states supported capabilities, remaining gaps and assistance. The resulting
P26/P27 design is a deliverable; production engine implementation remains deferred.
