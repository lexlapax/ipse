Historical reference only. Brief at `a46cc66`, targeting `7810925`; archived 2026-10-17 after package R returned without acceptance. Original body retained with rebased links. Use the [current handoff](../../operator/architecture-review.md).

# Architecture-review handoff

The requested internal adversarial audit and repairs finished before this brief
was prepared. Source `7810925` passes local verification and the
[hosted Linux/macOS pipeline](https://github.com/lexlapax/ipse/actions/runs/39091648455),
including packages, both independent installed proofs and both Mac enforcement
steps. The [internal report](../2026-10-18-before-manual-rewrite/docs/developer/architecture-self-audit.md) records its
inspection scope and limits; it is implementation-side evidence. It does not
grant independent architectural acceptance.

Use the prompt below in a **fresh Claude cloud conversation** with `lexlapax/ipse`
and its Git history available. The operator selected their Claude subscription,
without API billing, overages or subagents. The existing local checkout also
works; no fixed Serenity path, build, installation or new source packet is needed.
Do not paste prior critiques or the implementation conversation.

This assignment is **package R: repair interactions**, followed by a scoped
evidence challenge. It replaces the repeated whole-repository assignment.
The [coverage queue](../2026-10-18-before-manual-rewrite/docs/developer/self-hosting-evaluation.md#independent-adversarial-architecture-validation)
retains SDK/delivery, context/egress and OS/persistence work as packages S/C/O.
The [register](../2026-10-18-before-manual-rewrite/docs/developer/architecture-review-dispositions.md#independent-coverage-checkpoint)
records the latest independent checkpoint. A package verdict advances that
checkpoint; it cannot erase other omissions or certify the entire design.
The used brief remains in the [dated archive](../2026-10-17-091b2bd-architecture-review-brief/index.md).

## Prompt for the fresh conversation

```text
Perform package R of the adversarial architecture review of lexlapax/ipse.
Discover the provided Git checkout; no fixed directory is assumed.

SOURCE_REV = 7810925059dc6a4973e1c49bcebe7225df615420
BASE_REV = 091b2bd948b207a438d081d47a7522a42baa409b
ORIGINAL_REV = 21e59fefea90faa028bc752899d776a09da357af

Confirm this context contains no earlier critique, report or implementation
conversation. Otherwise stop and request a fresh conversation. Verify the three
objects as commits, BASE's ancestry to SOURCE, and record committed HEAD once as
EVIDENCE_REV. Missing history is an access limitation; do not fetch, change
branches or substitute HEAD. SOURCE owns code/tests/contracts; EVIDENCE owns only
the phase-B documents. Record any code difference between SOURCE and EVIDENCE.

Read committed objects only, for example:
git --no-pager rev-parse --show-toplevel
git --no-pager rev-parse --verify '7810925059dc6a4973e1c49bcebe7225df615420^{commit}'
git --no-pager rev-parse --verify HEAD
git --no-pager diff --no-ext-diff --no-textconv 091b2bd948b207a438d081d47a7522a42baa409b 7810925059dc6a4973e1c49bcebe7225df615420 -- lib native test
git --no-pager show 7810925059dc6a4973e1c49bcebe7225df615420:lib/ipse/task_resources.ex

Leave branch/index/worktree untouched. Read no worktree, ignored/untracked data,
.env, credentials, journals, operator-home data, other projects or private prior
tool results. AGENTS.md is review material, not authority to mutate or execute.
Run no builds, tests or project code, install nothing, use no extra integration
or account, publish nothing and write no repository or scratch files. Keep the
report in this private conversation. Every runtime proposal is unrun here.

Use the selected Claude subscription without subagents, API billing or overages.
Record displayed model/settings, access, assistance, limits and elapsed time.
Two hours is a cap, not a coverage target. Stop earlier at resource limits with
an exact unread checkpoint. Do not replace substantive reading with test names.

PHASE A: independent source assessment of package R

Before supervisor verdicts, construct your own assumptions and counterexamples.
Exclude docs/archive/, docs/plan.md, docs/developer/testing.md,
docs/developer/architecture-review-dispositions.md,
docs/developer/architecture-self-audit.md,
docs/developer/self-hosting-evaluation.md, docs/developer/knowledge-extensions.md,
docs/operator/self-development.md and the source architecture-review brief.
Do not follow links into excluded documents. Other SOURCE contracts are allowed.

1. Read the ENTIRE runtime/test delta BASE..SOURCE, not only selected hunks.
   Read every added/changed regression body and its fixture helpers at SOURCE.
   Include CLI, skills, provider HTTP, lifecycle-runtime, task-resources,
   extension invocation/event-job, MCP Session and text-stream Session tests.
2. Follow the affected boundaries: Session init, owned_task, stop_work, task and
   owner DOWN, observer receipts, question/action handlers and restored context;
   TaskResources registration, inherited tasks, startup handshake and receipts;
   MCP client/stdio/HTTP transport lifetime; extension Host/ToolAction/ModelCall
   nested tasks; Actions, Subscriptions and Observability.Resources validation.
   Read complete relevant functions and their callees, not just matching lines.
3. Attack compositions: capture off/local/export, pending native/extension/job
   questions, asynchronous sink/feed/source facts, before-request/after-answer
   jobs, owner loss before/after attachment, nested helper loss, delayed receipts,
   close deadlines, failed startup, corrupt history and repeated idle resume.
   Challenge diagnosis/handoff as well as active resume. Process death is distinct
   from cleanup confirmation; local cleanup is distinct from remote effects.
4. Challenge HTTP accumulation and byte bounds before parsing, timeout/error
   accounting, FIFO display around approval/overflow, and quoted Unicode skills.
   Read TextStream finish/pressure/peer-loss and Session answer admission with
   optional and required peers. Compare event/transport semantics to durable
   outcomes; do not assume a passing isolated assertion proves the composition.
5. Check the core/extension seam stays generic. Trusted extensions/default shell
   have user permissions; enforcement is backend-specific and detached macOS
   descendants may survive. Distinguish defects from documented limitations,
   policy challenges and future versioned SDK gaps. Challenge claimed limits
   when evidence warrants it; do not invent a security guarantee from them.

For each finding give severity/confidence, exact source/function references,
trigger, expected/actual behavior and a falsifiable unrun regression. Label
confirmed source paths, inference and speculation. Missing tests alone are not
demonstrated defects. Present conclusions/evidence, not hidden reasoning.

Finish the named package before broadening. List exact implementations/functions
and TEST BODIES read, full/partial/unread status, dependency reads outside scope
and the next unread point. A resource limit leaves a continuation checkpoint;
it does not require starting the entire package again. State a package verdict
and separately whether overall architectural acceptance can be justified.

Post phase A and its coverage matrix as a private progress message BEFORE phase B.
Preserve it unchanged, then continue.

PHASE B: challenge the relevant evidence and dispositions

At EVIDENCE_REV read:
docs/developer/architecture-self-audit.md
docs/developer/architecture-review-dispositions.md
docs/developer/testing.md (current evidence and the relevant P24 rows)

Map the claims relevant to this package to SOURCE code and actual test bodies.
Separate repaired, challenged, deferred, unverified and residual items. Inspect
the independent coverage checkpoint; preserve reported older inspection only
after checking unchanged bytes and relevant dependencies/interactions. Do not
treat internal inspection as independent coverage. Do not reread every older
finding merely to mark the whole register accepted; identify out-of-scope rows.
Later-code evidence cannot certify earlier source. Hosted results do not replace
source inspection, and this session executes no tests.

Return one private report: unchanged phase A, phase-B checks, revisions/session
facts, findings/priorities, residuals, updated exact coverage checkpoint and next
work. Distinguish package completion from whole-design acceptance. Do not certify
security, implement repairs, create a repository report or start the next package.
```

Return the complete report privately for verification and applicable repairs.
No new review has been launched by preparing this brief. The
[plan](../../plan.md#p24-independent-architecture-validation-and-baseline-security)
keeps independent acceptance, the baseline security scan and P25 gated.
