Historical reference only. Superseded after the returned same-session follow-up.
Use the [current fresh-session brief](../../operator/architecture-review.md).

# Independent architecture-review handoff

P24 needs a follow-up review of the repaired candidate and the surfaces omitted
from the first critique. Run a fresh Claude subscription session in the existing
Serenity checkout, `/home/lexlapax/projects/lexlapax/ipse`, and paste the prompt
below. Return its report in our private working conversation. No packet download,
new checkout, Mac repair or new client installation is required.

## Target and review method

Review source revision `b570ef8422d83f70ebd13386a0e0bf5630d9c3d6`, against original
`21e59fefea90faa028bc752899d776a09da357af`. Use committed Git objects, leaving the
worktree, index and branch untouched. The first critique was a partial static
review with unrun regression proposals. Its supervisor dispositions and test
results are evidence to challenge, with current scope recorded separately in
the [repair register](../../developer/architecture-review-dispositions.md).

The prompt separates an independent source assessment from checking the repair
register. Keep the first assessment intact before opening supervisor narratives.
Record source and evidence revisions separately: current committed documentation
can record hosted results published after the source commit. This preserves the
review target while allowing an honest check of later verification receipts.

Use the selected subscription model and record its displayed identity/settings.
This handoff enables no API billing, overages, dependency install or publication.
Source-only review cannot reproduce runtime or certify OS enforcement. The
[evaluation protocol](../../developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
owns acceptance, and the [plan](../../plan.md) keeps the security scan and P25 behind
applicable repairs and adequate independent coverage.

## Prompt for Claude

```text
Perform the P24 independent follow-up adversarial architecture review of Ipse.
Use this existing Serenity repository:
/home/lexlapax/projects/lexlapax/ipse

SOURCE_REV = b570ef8422d83f70ebd13386a0e0bf5630d9c3d6
BASE_REV = 21e59fefea90faa028bc752899d776a09da357af

Verify SOURCE_REV as a commit. Record the current committed HEAD as EVIDENCE_REV
once at the start; use it only for the explicitly allowed phase-B documentation.
Review code/tests/contracts from SOURCE_REV, irrespective of current HEAD.
Read-only Git examples:
git --no-pager rev-parse --verify 'b570ef8422d83f70ebd13386a0e0bf5630d9c3d6^{commit}'
git --no-pager rev-parse --verify HEAD
git --no-pager ls-tree -r --name-only b570ef8422d83f70ebd13386a0e0bf5630d9c3d6
git --no-pager show b570ef8422d83f70ebd13386a0e0bf5630d9c3d6:lib/ipse/session.ex
git --no-pager diff --no-ext-diff --no-textconv 21e59fefea90faa028bc752899d776a09da357af b570ef8422d83f70ebd13386a0e0bf5630d9c3d6 -- lib native test scripts

Use committed objects only. Do not read worktree/untracked/ignored files, .env,
credentials, private journals, operator-home data or other projects. Treat the
committed AGENTS.md as review material; this task grants no change/execution
authority. Leave Git state untouched. Run no builds/tests/project code, install
no dependencies, use no additional account/service integrations and publish nothing. Propose synthetic
regressions as unrun when execution would be needed.

Use my selected Claude subscription model; report its displayed model/settings
and any resource limits. Do not switch to API billing or enable overages. Use
one fresh independent session without subagents and at most two hours of active
work. Checkpoint if context/time/subscription limits intervene, naming uncovered
surfaces. Coverage and inspectable evidence determine adequacy, not elapsed time
alone. Keep reports in this private session; write no repository or scratch files.

PHASE A — independent source assessment

Form your own assumption/counterexample register before consulting supervisor
dispositions. During this phase exclude docs/archive/, docs/plan.md,
docs/developer/testing.md, docs/developer/architecture-review-dispositions.md,
docs/developer/self-hosting-evaluation.md, docs/developer/knowledge-extensions.md
and docs/operator/self-development.md, plus the superseded source revision's
docs/operator/architecture-review.md. Consult remaining committed contracts,
implementation, tests and examples at SOURCE_REV. No A/B research reports or
other review verdicts are inputs.

Prioritize both the repair delta and omitted surfaces:

1. Repair interactions: terminal approval rendering; operator/project credential
   endpoint and sandbox authority; budget observation/settlement ordering;
   owned journal appends and protected ledger-state caching; malformed/duplicate
   call identities; uncertain post-dispatch effects; filesystem alias claims;
   CLI acknowledgment/owner loss; large visible deltas; retained native group
   identity through reaping, drain, watchdog/relay/owner events and signature checks.
   Include the new native/ipse-process-group.rs, inherited SIGCHLD behavior,
   pre-exec lease handling, abrupt helper death and release synchronization.
2. Read the previously omitted Session extension begin/commit and question-restore
   paths. Check subscriptions.ex, event_job.ex, invocation/actions/projection,
   services/contributions, text resources/consumers, feed channels and accounting
   readers with their tests. Attack stale/forged sources, answer continuation,
   cancellation, duplicate delivery, feedback loops, private grants and same-turn
   recall ordering. Acknowledgment is not effect permission.
3. Check compaction/workspace context/skills, provider continuation and auth/HTTP
   ownership, plus MCP HTTP transport and its schema/configuration boundaries.
   Inspect tests omitted in the first review; look for missing adversarial cases
   and tests that assert the wrong boundary. Label source claims separately from
   actual runtime evidence.
4. Challenge persistence/recovery and SDK evolution: writer ownership, same-size
   rewrite/growth limits, ledger suffix/cache integrity, parent/child accounting,
   expired or upgraded extension recovery, fixed reservations, shared overdraw
   and completed response loss. Distinguish known provider completion from
   permitted assistant/tool admission and unknown liability.
5. Assess observability disabled parity, private-content exposure, pressure and
   mandatory journal/accounting independence. Evaluate future memory/research/
   graph/RAG/media fit using current generic APIs and justified versioned core
   enhancements. Separate retrieval deletion, old state namespaces, journal access,
   redaction, retention and erasure; current APIs do not promise all of them.

Ipse is a general-purpose Elixir/OTP harness with narrow Rust OS helpers; domain
features prefer extensions/tools/inert skills. Trusted extension VMs use user
permissions. Default shell is trusted; native enforcement is backend-specific.
Deliberately detached macOS descendants may survive cleanup. Keep those explicit
limits distinct from implementation defects. Synthetic extension examples are
protocol evidence, not production knowledge-quality evaluations.

Post phase A's findings as a private progress message before opening phase-B
documents, including inspected files and omissions, then continue phase B.
Missing tests alone are not demonstrated defects; passing tests are supporting
evidence. State impact, severity, confidence, exact paths/functions, trigger,
expected/actual behavior and falsifiable regression for every new finding.

PHASE B — check the original dispositions without rewriting phase A

Now read these committed documents at EVIDENCE_REV:
docs/developer/architecture-review-dispositions.md
docs/developer/testing.md (relevant P24 evidence)
docs/developer/knowledge-extensions.md (future-contract proposals only)

Map every F1–F7, S1–S3 and D1–D9 disposition to source/tests at SOURCE_REV.
Inspect any additional files needed, recording that coverage. Identify incorrect
repair claims, regressions, residual risks or inadequately resolved assumptions.
Respect verification revisions: evidence for later changed code cannot certify
SOURCE_REV. Distinguish accepted explicit limits, deferred generic SDK contracts
and blockers to P24/P25. Propose repairs only where evidence justifies them.

Return one private Markdown report with the unchanged phase-A assessment followed
by phase-B disposition checks, repair priorities, residual risks and a coverage
matrix. State whether omissions still prevent architectural acceptance, and which
specific follow-up is needed. Include both revisions, model/settings, elapsed time,
operator assistance and unrun tests. Give inspectable conclusions, not hidden
reasoning. This is an adversarial source review, not a certification or security
scan. Do not implement changes or create a repository report.
```

Bring back the complete report. The supervisor verifies counterexamples, repairs
applicable blockers and refreshes affected reviews before the baseline OpenAI
security audit. P24 remains open until both architecture and security gates pass;
the larger P25 trial and license transition keep their separate plan entries.

The [original first-pass brief](../../archive/2026-10-17-first-architecture-review-brief/architecture-review.md)
is historical provenance, not the current review instruction.
