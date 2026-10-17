# Architecture review: dispositions and repair gates

P24's first independent critique targets
`21e59fefea90faa028bc752899d776a09da357af`. The operator returned the report in
the private working conversation on 2026-10-17. This document is its sanitized
finding register and supervisor verification record; the full report and any
exploit details remain outside Git. The [plan](../plan.md) owns scheduling and the
[evaluation protocol](self-hosting-evaluation.md) owns review/scan acceptance.

## Provenance and coverage

The reviewer reported Claude Code with Opus 5.5 (`claude-opus-5-5`), default
reasoning, one subscription-selected session and no subagents or operator help
beyond the brief. Billing mode was not independently observable to the reviewer.
The reported inspection lasted about nine minutes plus report writing, below the
two-hour bound. It used committed Git objects, preserved the worktree and honored
the excluded reports/designs. These are reviewer-reported session facts.

The report is a partial static review, with no executed code, tests or runtime
reproductions. It inspected journal/budget/worker/native-supervisor/delegation
paths substantially and portions of Session, CLI, configuration, profiles, feeds,
history and text delivery. It did not inspect tests or most subscription/job/
invocation/service/accounting-read validators, context/compaction/auth plumbing,
MCP HTTP, OS sandbox implementations, observability or the independent examples.
Those omissions remain explicit coverage work; this report does not close P24.

## Findings requiring verification and repair

“Accepted source defect” means the supervisor checked the described path against
current code. It is not a claim of a reproduced impact. Severity and reachability
must follow evidence; the review's labels are initial assessments.

| ID | Surface | Disposition and evidence | Remaining gate |
| --- | --- | --- | --- |
| F1 | Terminal rendering and approval visibility | Reproduced, repaired and verified at `0420e7a`: source/native/demo/package, both installed proofs and hosted Linux/macOS gates passed. CLI display escaping preserves original messages/provider continuation; the installed locale probe also drove an IO-encoding correction | Closed within exercised display scope; this does not close other findings or architectural coverage |
| F2 | Project profile and credential-bearing egress authority | Reproduced before repair: a project-selected loopback endpoint received the synthetic API credential. Candidate now refuses project endpoints/operator-ID replacement before session creation, preserves operator customization and project default-endpoint routing, and discloses helper origin/full-target digest. Source/native/demo/package/installed checks passed, including 78 focused checks and the strengthened independent artifact proof | Hosted Linux/macOS validation remains open. Separately, the operator's choice on documented project sandbox precedence is pending; no floor change has been made |
| F3 | Budget observation durability versus canonical journal | Accepted ordering hazard: provider usage is emitted before the ledger observation transaction, while resume requires ledger liability to cover journaled observations | Exercise persistence refusal and crash boundaries with real store/lock fixtures. Repair must retain reported usage, conservative liability and forged-source refusal; merely omitting usage or relaxing validation is insufficient |
| F4 | Journal/ledger growth and Session responsiveness | Accepted source concern: appends reread/decode the existing journal synchronously; ledger transactions replay their bounded file. Restore also scans prior admissions | Measure scaling and responsiveness; design owned append/validation state and meaningful regression bounds. Source complexity alone does not establish the report's latency numbers |
| F5 | Indeterminate tool failure classification | Accepted source defect in the shell/task failure paths: post-dispatch uncertainty can reach a definite-error receipt | Reproduce helper/task loss after dispatch; preserve known pre-dispatch errors and unknown outcomes through tool lifecycle, extension receipts and resume |
| F6 | Tool-call identity and interrupted recovery | Accepted source defect: admission does not reject duplicate IDs and recovery maps results by ID; compaction already rejects duplicate call identifiers | Add live admission and historical interrupted-result regressions; preserve original/native evidence without assigning one result to multiple effects |
| F7 | Filesystem aliases and mutation/conflict guards | Accepted platform-conditional source gap: the metadata-path guard and child target claims use case-sensitive lexical paths | Exercise case-insensitive filesystem behavior on a real Mac/hosted Mac. Cover metadata paths and parallel alias claims; Linux fixture success cannot prove APFS behavior |

## Additional concerns

| ID | Assessment | Required disposition |
| --- | --- | --- |
| S1 | Cleanup deadlines can exceed a synchronous caller's timeout; observed caller crash is unverified | Check aggregate cleanup and CLI exit handling with controlled workers; distinguish conservative unconfirmed cleanup from an actual lost owner |
| S2 | Process-group identity reuse after leader reaping is a proposed race, not a reproduced incident | Inspect guard/reaping ordering and platform semantics before accepting or rejecting; avoid claiming a PID-reuse exploit without evidence |
| S3 | A large provider delta can exceed the text-channel chunk bound; the reported path is untested | Check actual adapter/chunk paths, documented pressure behavior and output preservation; classify bounds versus avoidable fragmentation failure |

Supervisor verification also found a recurring Mac CI concern outside the critique:
documentation-only `3dd7110` failed two MCP catalog stdio discoveries before tool
dispatch. The later F1 matrix passed both hosts without an MCP runtime change.
The cause remains unconfirmed; a green replacement run is not a root-cause repair.
Exact failed/passing runs are retained in the testing record.

## Design choices and future contracts

| ID | Current assessment | Follow-up |
| --- | --- | --- |
| D1 | Host/runtime identity pins intentionally refuse incompatible extension resume. “Any rebuild” is too broad: unchanged bytes are not a changed digest | Verify unchanged versus changed builds and retain explicit handoff/upgrade guidance; do not weaken recovery identity as a convenience fix |
| D2 | State namespaces include artifact and source identity; upgrades/moves can select a different namespace | P25/P26 proposals must address stable logical identity, explicit export/migration/collection and deletion across retained versions; no silent state reassignment |
| D3 | Expired/revoked extension authority can refuse session activation, including idle resume | Assess a separately authorized read-only inspection/export path without executing expired code or admitting effects |
| D4 | Fixed reservations are estimates and can understate in-flight input | Accepted documented limitation; preserve observed peaks and overdraw refusal, and evaluate stronger estimators separately from an invoice guarantee |
| D5 | A shared overdraw can refuse an otherwise completed provider result | Verify actual canonical/native retention and sibling behavior before deciding whether already-completed work may be exposed. Material semantics may require an operator decision |
| D6 | Torn budget records fail closed without automatic ledger repair | Accepted documented limitation; any future recovery must preserve the original ledger and unknown liability |
| D7 | Journal retention and retrieval deletion have different meanings | P25/P26/P27 must distinguish retrieval tombstones, no-resurrection, namespace migration/collection, journal redaction/access policy and secure erasure. A memory extension alone cannot promise removal of immutable host evidence |
| D8 | Text pressure can fail the main request by the selected contract | Accepted boundary pending S3's separate oversized-chunk assessment |
| D9 | Trusted executable code and explicit native execution have different OS boundaries | Preserve the documented trust model and macOS best-effort detached cleanup; no blanket confinement claim |

## Execution order and completion

Repair the demonstrated display and configuration-authority defects first, then
durability, performance and recovery/alias issues in focused increments. Each
increment needs a regression or measured counterexample, coherent operator/developer
guidance and its own required checks before commit/push. Passing old baselines
does not verify repairs. The [testing record](testing.md#current-evidence-and-next-checks)
owns actual full-suite/package/platform results and revisions.

After repairs, request an independent delta/coverage pass covering the original
omissions, particularly Session extension begin/commit/question restore,
subscriptions/jobs, compaction/workspace context and MCP HTTP. Retain original
findings and check each disposition; no automatic approval follows from agreement
between agents. The baseline security audit and P25 remain gated by the initial
critique's triage, applicable repairs and adequate architecture coverage. No
security scan has run and P24 remains incomplete.
