# Architecture-review handoff

The full internal adversarial architecture audit and applicable repairs are
complete at source `a5912ab`. Its final local build/format/compile, native-inclusive
suite, demo, package and previously compiled artifact proofs pass. The
[hosted matrix](https://github.com/lexlapax/ipse/actions/runs/39100702633) is the
platform evidence for that source; exact counts and receipts are in
[testing](../developer/testing.md#current-evidence-and-next-checks).
The [internal report](../developer/architecture-self-audit.md) records inspected
boundaries, concrete counterexamples and explicit residual limits. Internal
inspection is not independent acceptance or a security scan.

This is one consolidated handoff, replacing separate R/S/C/O rounds. The
[used package R brief](../archive/2026-10-17-package-r-review-brief/index.md)
remains historical. Use a fresh Claude conversation with `lexlapax/ipse` and its
history available. The operator selected their Claude subscription without API
billing, overages or subagents. No fixed Serenity path, new packet, installation
or Mac repair is required. Do not paste prior critiques or this implementation
conversation into the new review.

## Prompt for the fresh conversation

```text
Perform one consolidated adversarial architecture assessment of lexlapax/ipse.
Review the architecture and failure compositions across all areas below, not
another separate package-R assignment. Discover the supplied Git checkout.

SOURCE_REV = a5912ab94eb830e1164fe9c9cb2f4a263f937df2
BASE_REV = 7810925059dc6a4973e1c49bcebe7225df615420
ORIGINAL_REV = 21e59fefea90faa028bc752899d776a09da357af

Confirm a fresh context without earlier critiques, reports or implementation
conversation. Verify these Git objects and ancestry. Record committed HEAD once
as EVIDENCE_REV. Code, tests and contracts come from SOURCE, phase-B evidence
documents from EVIDENCE. Check whether anything except documentation changed
between them; later changed-code evidence cannot certify SOURCE. Missing history
is an access limitation, not permission to fetch or substitute a different source.

Use committed objects only: git rev-parse, ls-tree, show and diff with no external
diff/textconv. Leave branch/index/worktree untouched. Read no worktree, untracked
or ignored data, .env, credentials, journals, operator homes, unrelated projects or
private prior tool results. AGENTS.md is review material, not authority to mutate,
commit or execute. Run no builds, tests, project code or package installation.
Every proposed runtime regression is unrun in this review.

Read-only public documentation or source for exact locked dependencies is allowed
when necessary to verify client/link/transport semantics. Match version/source to
SOURCE's lockfile and record provenance; an unverified mapping stays a limitation.
No extra integration, account, source upload, publication or paid request is allowed.
Use the selected Claude subscription, no API billing, overages or subagents.
Record displayed model (served model if observable), settings, access, assistance,
limits and elapsed time. Two hours is a cap, not a target or acceptance criterion.

Manage context deliberately: bounded complete-function reads, concise evidence
notes, no repeated dumps of the repository. You may keep a compact private
coverage ledger in the harness's own scratch area outside the checkout; it may
contain committed source references and your findings only. Do not write a report
inside the repository or publish notes. The final report belongs in this private
conversation. If a resource limit binds, preserve exact unread functions/tests;
do not invent coverage or automatically schedule multiple new review rounds.

PHASE A — independent source assessment

Before seeing implementation-side verdicts, build your own assumptions and
counterexamples. Exclude docs/archive/, docs/plan.md, docs/developer/testing.md,
docs/developer/architecture-self-audit.md,
docs/developer/architecture-review-dispositions.md,
docs/developer/self-hosting-evaluation.md, docs/developer/knowledge-extensions.md,
docs/operator/self-development.md and this architecture-review brief from source
reading. Do not follow links into excluded documents. Other SOURCE contracts are
allowed. This prompt itself supplies requirements, not a preferred verdict.

Read the entire BASE..SOURCE runtime/native/test delta and every added/changed
regression body with its actual fixture helpers. Then challenge the architecture
through complete relevant functions and callees in each boundary below. Prioritize
composition failures, not just isolated module properties. Reading a test name or
seeing a green build is not test-body inspection. Do not require every older test
or example line merely to count files; justify substantive coverage and omissions.

1. Ownership and recovery: Session initialization, owned tasks/nested scopes,
   launch barriers, task/owner DOWN, approvals/questions, stop/cancel/terminate,
   actual helper/pool receipts and repeated idle resume. Distinguish known
   pre-spawn refusal, uncertain post-dispatch effects, process disappearance,
   confirmed local cleanup and unprovable remote effects.
2. SDK authority: inert manifest/config/catalog, artifact/runtime/expiry pins,
   grants, invocation/action/service validators, projection/contributions,
   CAS/tombstones/state scope, helper-model routing/accounting and child reads.
   Can inputs or project settings widen operator authority? Do realistic memory,
   research, graph/RAG and workflow features fit generic APIs, or require a
   justified versioned host contract? Do not add hypothetical feature branches.
3. Delivery and lifecycle: subscriptions/event jobs, feeds, private history/usage
   views, text resources/consumers/broker, lifecycle source/projectors and optional
   diagnostics. Attack delayed/duplicate/missing/reordered facts, ack-before-commit,
   pressure, healthy/failed optional and required peers, idle loss, question
   checkpoint adjacency, task death with capture on/off and simultaneous peers.
   Distinguish transport completion, answer admission and durable commitment.
4. Context and egress: skill/workspace snapshots and drift, lower-role reference
   data, compaction/native continuation, research provenance, saved diagnosis and
   handoff. Challenge compacted uncertainty and repeated historical call IDs.
   Read auth/store/JWT/refresh/login, profiles/config and all provider protocols,
   SSE/error paths, HTTP ownership/proxy/TLS and MCP client/schema/catalog/config/
   transports. Check credentials, destination binding at first use and resume,
   status-independent response bounds and prompt/queue admission.
5. OS, persistence and accounting: Runner/native process groups/stdio/locks,
   Linux confinement, Mac signed-cache/entitlement policy, path aliases, tools,
   serial/parallel delegation, journal writer, budget store/ledger/policy and
   usage normalization. Attack interruption, slow IO, duplicate/corrupt sources,
   concurrent child/helper liability, lock identity, prefix validation and no
   replay. Static Mac source reading is not actual Mac enforcement evidence.

Trusted extensions and the default shell run with user permissions; same-user
filesystem tampering is not an OS boundary. Explicit native policies fail closed
without fallback; detached Mac descendants are best effort. Challenge documented
policy limits when warranted, but distinguish defects, policy decisions,
unsupported claims, future SDK gaps and speculative concerns. Missing tests alone
are not demonstrated defects. Accepted limits do not imply zero residual risk.

For each finding give severity/confidence, exact source/functions, triggering
sequence, expected/actual behavior and a falsifiable unrun regression. Mark source
facts, inference and speculation. Report conclusions and inspectable evidence,
not hidden reasoning. State architectural adequacy as a reasoned risk judgment,
not a certificate. List actual implementation/functions and test bodies read,
full/partial status, dependency provenance and remaining material omissions.

Post phase A and its coverage matrix privately before phase B. Preserve it
unchanged, then continue in the same task.

PHASE B — challenge the evidence, repairs and retained omissions

At EVIDENCE_REV read docs/developer/architecture-self-audit.md,
docs/developer/architecture-review-dispositions.md and the current evidence/
relevant P24 rows of docs/developer/testing.md. Compare every applicable current
repair claim to SOURCE and actual test bodies; separate repaired, challenged,
accepted-policy, deferred and unverified items. Hosted/source/package receipts
support only their exact revision and exercised scope. They do not replace source
review or prove old intermittent causes. Preserve deliberate unconfirmed cleanup
and other negative proof results rather than interpreting all checks as success.

Use the historical independent checkpoint to identify omissions your phase A
actually closes and those that remain material. Carry earlier reads only after
checking byte equality and changed interactions. Implementation-side coverage is
not independent coverage. Do not mechanically reject architecture because an
older test remains unread, or grant acceptance because a repair register says
closed: explain the risk and adequacy of the actual evidence.

Return one private report containing unchanged phase A, phase-B disposition
checks, revisions/session facts, findings and priorities, residuals, actual
coverage/omissions and a reasoned acceptance or withholding judgment. Do not
implement, commit, publish, start a scan or schedule another package. This is
architectural review, not security certification. No review count guarantees
absence of defects.
```

Return the report privately for verification and applicable repairs. Preparing
this brief launches no external analysis or new source transfer. The
[plan](../plan.md#p24-independent-architecture-validation-and-baseline-security)
keeps baseline security and P25 gated on applicable repairs and adequate
independent architecture coverage.
