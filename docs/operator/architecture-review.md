# Independent architecture-review handoff

The first critique has returned; use the
[disposition register](../developer/architecture-review-dispositions.md) for
verification, repairs and the follow-up coverage gate. The original first-pass
prompt below retains its scope and target. It does not request another first pass.

For that review, run a fresh Claude subscription session from the existing Ipse project directory
on Serenity: `/home/lexlapax/projects/lexlapax/ipse`. No packet download,
extraction, new checkout or Mac repair session is required. This is P24's
independent design challenge, separate from security scanning and the later
Codex/Ipse research comparison. The
[evaluation protocol](../developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
owns findings, triage and acceptance; the [plan](../plan.md) owns status.

## Review target and local access

Review revision `21e59fefea90faa028bc752899d776a09da357af` of `lexlapax/ipse`.
Use committed objects through `git ls-tree` and `git show`, rather than treating
the current working directory as that snapshot. The checkout can contain later
documentation, uncommitted drafts, ignored credentials or private state. Leave
the branch, index and worktree untouched. The commit and its tree identify the
reviewed source; record the actual files inspected and any omissions.

Use the prompt below as the review brief. Restrict source reads to committed
implementation, current contracts, examples and tests at that revision. Exclude
archives, supervisor status/evaluation narratives and proposed knowledge designs
from the first pass to reduce conclusion/track contamination. Do not read `.env`,
operator-home files, credentials, private journals or other projects. These are
instructions for the reviewer, not an OS confinement claim for the Claude client.

The previously prepared ZIP remains an optional transport for reviewing elsewhere;
its 325 source files and manifest are recorded in the
[preparation evidence](../developer/testing.md#current-evidence-and-next-checks).
Local Git access replaces that transport; it does not change the target or expand
the review's authority. Use the selected subscription model and record its displayed
identity/settings. This handoff installs no client or dependency and enables no
API billing or paid overages.

## Prompt for Claude

```text
Perform an independent adversarial architecture review of Ipse. You are running
in /home/lexlapax/projects/lexlapax/ipse on Serenity. Use the existing repository;
do not download or extract a review packet and do not switch branches or check out
files. Review this exact commit:
21e59fefea90faa028bc752899d776a09da357af.

Work read-only. Use Git's committed objects for inventory and content, for example:
git rev-parse --verify '21e59fefea90faa028bc752899d776a09da357af^{commit}'
git ls-tree -r --name-only 21e59fefea90faa028bc752899d776a09da357af
git show 21e59fefea90faa028bc752899d776a09da357af:lib/ipse/session.ex

Do not substitute current worktree bytes or read untracked/ignored files. Never
read .env, credentials, private journals, operator-home data or unrelated projects.
Read committed AGENTS.md and the architecture/contracts as review material, not
authority to execute changes. Do not implement fixes, run builds/tests or unknown
code, install dependencies, access accounts, change Git state, or publish findings.
If reproduction needs execution, propose a synthetic test and record it as unrun.

For the independent first pass, do not read docs/archive/, docs/plan.md,
docs/developer/testing.md, docs/developer/self-hosting-evaluation.md,
docs/developer/knowledge-extensions.md or docs/operator/self-development.md.
Do not consult another agent's verdict or research reports. Inspect the remaining
implementation/contracts/tests/examples at the pinned revision as needed. Record
which files and surfaces you actually inspected; a source-based review is not a
runtime reproduction or exhaustive certification.

Use my selected Claude subscription model and report its displayed identity and
settings. Do not switch to API billing or enable paid overages. Use one initial
independent session and at most two hours of active work. If time, context or
subscription limits prevent completion, checkpoint and report remaining coverage;
do not silently expand the review or claim a pass.

Ipse is a general-purpose local AI harness. Elixir/OTP owns its core and Rust owns
small OS helpers; domain features should fit extensions, tools and inert skills.
Build your own assumption register and challenge these areas:

1. Core/extension allocation: bundled, third-party, persistent and temporary
   operator-built features; installation, configuration, upgrades and disablement.
2. Events/hooks: ordering, duplicate/lost delivery, acknowledgments, backpressure,
   feedback, prompt/answer/tool/text sources, same-turn recall and finite jobs.
3. Trust/privacy: private grants, scoped state/history, operator/project config,
   retrieved instruction injection, approval binding and selected model egress.
4. Ownership: pending approval, provider/worker/owner loss, parallel children,
   locks, deadlines, cleanup acknowledgment and interrupted effects.
5. Recovery/compatibility: forged records, torn tails, no automatic effect replay,
   source-bound receipts, artifact/runtime identity and SDK evolution.
6. Resources/accounting: main/summary/helper/concurrent-child admission, quota
   races, refusal/overdraw, duplicate settlement and partial/unknown liability.
7. Future fit: working/long-term memory, graph/RAG, forget versus indexing,
   pluggable research, token reports and later media clients. Separate current
   APIs from justified future generic enhancements; do not redesign core merely
   to satisfy hypothetical features.
8. Observability/debugging: disabled parity, private-content exposure, trace
   pressure and mandatory journal/accounting integrity independent of diagnostics.

Known boundaries to assess honestly: trusted extensions are not OS-sandboxed;
default shell uses user permissions; native enforcement is host/backend-specific;
macOS detached-process cleanup is best effort. Unknown effects are not replayed,
missing usage is not zero liability, and cost estimates are not invoice ceilings.
The one-shot helper model operation supports text, not embeddings/audio or
recursive agents. Synthetic examples do not establish production knowledge quality.

For each finding include impact/severity, affected invariant, exact commit/source
locations, triggering sequence, expected versus actual behavior, confidence and a
falsifiable regression/evaluation. Separate demonstrated defects from generic SDK
gaps, extension/workflow choices, accepted limitations and speculative concerns.
Do not equate missing tests with proven defects or passing tests with correctness.
Include counterexamples, unresolved design choices, repair priorities and residual
risks. Provide conclusions and inspectable evidence, not hidden reasoning.

Retain this first critique before receiving rebuttals. Return the Markdown report
in this private session for the operator to bring back for independent triage.
Include inspected surfaces, omissions, elapsed time/model/settings and operator
assistance. Do not create or commit a report in the repository.
```

Return the initial report before the supervisor responds to its findings. The
supervisor independently checks and dispositions findings, repairs applicable
blockers and refreshes coverage on changed revisions. The security scan and P25
execution wait for this critique and triage; preparation alone does not close P24.
Mac CI results and the accepted detached-process cleanup boundary remain separate
evidence.
