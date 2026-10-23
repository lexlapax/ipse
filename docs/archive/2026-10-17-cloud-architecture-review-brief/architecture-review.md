Historical reference only. Archived 2026-10-17 from `b08cd76`, targeting `b5297be`.
Use the [current handoff](../2026-10-22-before-structural-consolidation/docs/operator/architecture-review.md); this prompt has already returned.
Relative documentation links are rebased; the original body follows. No private critique is included.

---

# Fresh-session architecture-review handoff

Start a **new Claude cloud review conversation** with repository `lexlapax/ipse`
available from current `origin/main`, then paste the prompt below. Prepare a Git
checkout whose history contains the pinned source/base/original revisions before
the review starts; no project build, test run or dependency installation is needed.
The checkout path is environment-specific. The existing Serenity checkout also
works if the operator later chooses local execution.

Do not resume either earlier review conversation, paste its report, or attach
this working conversation. The review context must be fresh. Use the operator's
selected Claude account and subscription; this handoff enables no API billing or
overage change. If cloud access supplies only a file snapshot without verifiable
Git objects, report that limitation rather than silently reviewing another revision.

## Target and acceptance

Source is pinned to `b5297beca9781cd52e907f7907683882ccaebba9`. The first partial review targeted `21e59fe`;
the same-reviewer follow-up targeted `b570ef8` with documentation at `d14d6ac`.
It accepted the prior scoped repairs but retained substantial omissions. It is
useful follow-up evidence, not a fresh independent assessment. The repaired source
passed its local handoff and [hosted Linux/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39077065133),
including both Mac enforcement steps and independent installed proofs. The
[register](../2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md)
and [testing record](../2026-10-18-before-manual-rewrite/docs/developer/testing.md#current-evidence-and-next-checks)
hold details for phase B only.

The next review must substantively inspect previously unread implementations and
test bodies. Rechecking only the repair diff or listing test names cannot close
the architecture gate. If the workload cannot fit one session, return precise
coverage checkpoints for another fresh session. Two hours is a cap, not an adequacy
target. Source review proposes runtime regressions; it does not claim to execute
them or certify OS enforcement. The [evaluation protocol](../2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
owns acceptance; the [plan](../../plan.md#p24-independent-architecture-validation-and-baseline-security)
keeps baseline security and P25 behind applicable repairs and adequate coverage.

## Prompt for the new conversation

```text
Perform a fresh-session adversarial architecture review of repository lexlapax/ipse
in the Git checkout provided by this cloud environment. Discover its repository
root from the current working directory; no Serenity-specific path is assumed.

SOURCE_REV = b5297beca9781cd52e907f7907683882ccaebba9
BASE_REV = b570ef8422d83f70ebd13386a0e0bf5630d9c3d6
ORIGINAL_REV = 21e59fefea90faa028bc752899d776a09da357af

First confirm this conversation has no earlier review report, critique or
implementation conversation in its context. If it does, stop and request a new
conversation; an instruction to forget earlier material is insufficient.
Verify SOURCE_REV as a commit and record committed HEAD once as EVIDENCE_REV.
Verify BASE_REV and ORIGINAL_REV are available too. If the checkout or required
Git objects are missing, stop and report the access limitation; do not fetch,
change branches, or substitute current HEAD for the pinned source during review.
Use SOURCE_REV for implementation/tests/contracts and EVIDENCE_REV only for the
explicit phase-B evidence documents. Leave branch, index and worktree untouched.

Read-only Git examples:
git --no-pager rev-parse --show-toplevel
git --no-pager rev-parse --verify 'b5297beca9781cd52e907f7907683882ccaebba9^{commit}'
git --no-pager rev-parse --verify HEAD
git --no-pager ls-tree -r --name-only b5297beca9781cd52e907f7907683882ccaebba9
git --no-pager show b5297beca9781cd52e907f7907683882ccaebba9:lib/ipse/extensions/invocation.ex
git --no-pager diff --no-ext-diff --no-textconv b570ef8422d83f70ebd13386a0e0bf5630d9c3d6 b5297beca9781cd52e907f7907683882ccaebba9 -- lib native test scripts

Read committed objects only. Do not read worktree/untracked/ignored files, .env,
credentials, private journals, operator-home data or other projects. Committed
AGENTS.md is review material, not permission to mutate or execute. Run no builds,
tests or project code; install nothing, use no additional account/integration and
publish nothing. Do not read prior review conversations or private tool results.
Write no repository or scratch files. Keep the report in this private session.

Use the selected Claude subscription, no subagents, API billing or overages.
Report the displayed model/settings, access method, limits, operator assistance
and elapsed time. Stop at two hours of active work or earlier resource limits,
returning a coverage checkpoint. Do not equate a short inspection with adequate
coverage. All proposed runtime regressions must be labeled unrun.

PHASE A: independent source assessment

Before consulting supervisor verdicts, construct your own assumption and
counterexample register. Exclude docs/archive/, docs/plan.md,
docs/developer/testing.md, docs/developer/architecture-review-dispositions.md,
docs/developer/self-hosting-evaluation.md, docs/developer/knowledge-extensions.md,
docs/operator/self-development.md and the source revision's architecture-review
brief. Do not follow links into them. Other committed contracts, implementation,
tests and examples at SOURCE_REV are allowed.

Prioritize these surfaces and read the corresponding TEST BODIES, not only names:

1. Extension validators and host authority: invocation.ex, actions.ex,
   projection.ex, services.ex, contributions.ex and Session begin/commit/invoke
   paths. Check parent/source binding, approval, expiry, typed results, private
   grants, cancellation, delegation and service recursion. Include invocation,
   host-call, service and context/publication regressions.
2. Delivery and resource lifetimes: text_resources.ex, text_consumer.ex,
   feed_channel.ex, feeds.ex, subscriptions.ex, event_job.ex, history.ex and
   usage_read.ex. Check duplicate/reordered delivery, pressure, cursor/ack
   durability, stale/forged sources, question continuation and same-turn recall.
   Inspect text/feed/event/job/history/usage-read tests and Session restore paths.
3. Conversation and instructions: compaction.ex, workspace_context.ex, skills.ex,
   context.ex and handoff.ex with checkpoint/context/skill/handoff test bodies.
   Attack prefix integrity, provider continuation, scope drift, symlink paths,
   instruction-versus-permission boundaries and interrupted-effect projections.
4. Authentication and integration: auth.ex and auth/*, provider continuation and
   http_profile.ex, MCP client.ex/schema.ex/config.ex/http_transport.ex and stdio
   ownership. Inspect auth/OAuth/HTTP/MCP tests. Challenge credential-bearing
   egress, provider/billing selection, TLS/proxy behavior and transport cancellation.
5. Lifecycle and diagnostics: every lifecycle module, observability policy,
   resources/channels and developer trace. Inspect lifecycle/tool/child/answer,
   observation and parity tests. Are diagnostics truly optional while mandatory
   journaling/accounting remain independent? Can private views leak or subscribers
   acquire effect permission through acknowledgments or notifications?
6. OS boundaries: sandbox.ex, macos_sandbox.ex, Linux/macOS Rust sandbox code and
   the native process-group/runner/stdio helpers with their actual test bodies.
   Separate source reasoning from hosted enforcement evidence. Check ownership,
   pre-exec descriptors, interrupted cleanup, retained group identity and paths.
7. Repair interactions and persistence: CLI approval/input interleaving, writer
   acknowledgment and shutdown, shared opaque call-ID bounds, write refusal versus
   uncertain outcome, ledger durability/cache and root/child budgets. Inspect the
   NEW regressions and challenge whether they assert the right boundary. Check
   resource growth, locks, owner death, recovery and compatibility with host pins.

For each area report exact implementation paths/functions and TEST BODIES read,
what adversarial sequence you checked, and specific uncovered paths. Mark full,
partial or unread honestly. Review requirements/extension architecture against
generic host contracts, including future optional memory/research/graph/RAG/media;
separate a justified versioned core enhancement from a feature-specific core branch.

Ipse is a general-purpose Elixir/OTP harness with small Rust OS helpers. Trusted
extension code and default shell run with user permissions; native enforcement is
backend-specific. Deliberately detached macOS descendants can survive cleanup.
Retrieval deletion, namespace migration, journal redaction and secure erasure are
different contracts. Explicit accepted limits can be challenged, but are not
automatically implementation defects.

For a finding provide severity, confidence, exact source references, concrete
trigger, expected/actual behavior and a falsifiable unrun regression. State
whether it is a confirmed source path, an inference or speculation. Missing tests
are not demonstrated defects; passing tests are supporting evidence. Present
inspectable conclusions, not hidden reasoning.

Post your phase-A assessment and coverage matrix as a private progress message
BEFORE opening phase-B documents; retain it unchanged, then continue.

PHASE B: challenge the evidence and dispositions

Read only these additional documents at EVIDENCE_REV:
docs/developer/architecture-review-dispositions.md
docs/developer/testing.md (relevant P24 rows and records)
docs/developer/knowledge-extensions.md (future proposals only)

Map F1–F7, S1–S3, D1–D9 and follow-up A1–A7 to code/test bodies at SOURCE_REV.
Distinguish repaired scope, residual/accepted policy, unverified evidence and new
regressions. Read additional code/tests as needed and update coverage explicitly.
Do not let later-code evidence certify an earlier source. Test receipts do not
replace source inspection, and this session has run no tests. If a proposed runtime
reproduction is necessary, explain it without claiming it ran.

Return one private Markdown report: unchanged phase A, phase-B checks, priorities,
residual risks, full coverage matrix and a specific acceptance statement. State
whether any implementation/test omissions still prevent architectural acceptance;
name the next work if so. Include revisions, model/settings, elapsed time, assistance
and all unrun tests. Do not certify security, implement changes or create a repo report.
```

Return the complete report in the private working conversation. The supervisor
will verify new counterexamples, repair applicable defects and refresh affected
coverage before the baseline OpenAI security scan. Neither this brief nor earlier
green builds closes P24, launches P25, or completes the separate license transition.
Earlier briefs remain [historical reference](../index.md).
