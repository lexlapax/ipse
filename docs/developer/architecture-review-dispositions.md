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
| F2 | Project profile and credential-bearing egress authority | Endpoint/profile/disclosure repair at `e7a5458` passed source/native/demo/package/installed and hosted Linux/macOS checks after the real synthetic-key reproduction. The operator subsequently selected project-only sandbox tightening. Repair at `324bff1` preserves native mode/provenance with explicit operator environment/CLI authority; source/native/demo/package/installed and hosted Linux/macOS passed | Closed within exercised endpoint, profile, disclosure and sandbox-authority scope |
| F3 | Budget observation durability versus canonical journal | Reproduced with a real lock: canonical input 60 exceeded ledger booking 40, and idle resume refused before tail repair. Repair at `3bd99af` commits observations before publication, preserves committed overdraw and withholds uncovered final-only usage when settlement fails. Source/native/demo/package, both installed proofs and hosted Linux/macOS passed | Closed within exercised scope. A failed durable write leaves unavailable measurements and unknown reservations, explicitly documented rather than an exact count. Historical peak/forged-source checks remain strict; no validator relaxation or ledger repair is introduced |
| F4 | Journal/ledger growth and Session responsiveness | Repair at `200640e` passed source/native/demo/package, both installed proofs and hosted Linux/macOS. The owned writer reduced Btrfs 64 MiB median append from 164.2 ms to 1.5 ms, with actual approval at 3.4 ms. Validated ledger-state caching removes repeated decoding/folding while retaining full prefix verification; indexed attempt/order accumulation removes quadratic admission work | Closed within the exercised persistence scope. Writer/source/fsync and budget rewrite/refusal regressions pass. The journal still has startup/growth costs and no cumulative quota; live journal guards do not authenticate same-size rewrites. Ledger reads/hashes remain linear and bounded. The independent follow-up must assess these explicit residual limits; see the persistence contract and measured evidence |
| F5 | Indeterminate tool failure classification | Reproduced with an owned shell helper killed after a real scratch-file effect and with a failing output consumer. Repair at `324bff1` preserves known validation/setup refusals, classifies uncertain helper/worker/write failures as unknown and keeps idle resume inert. Source/native/demo/package/installed and hosted Linux/macOS passed, including the extracted real-helper-loss probe | Closed within exercised tool-failure scope; related lifecycle/extension/MCP checks and incomplete/oversized/invalid/contradictory frame regressions retain unknown outcomes |
| F6 | Tool-call identity and interrupted recovery | Reproduced live duplicate-ID approval/effects and, with a corrected valid historical fixture, result reuse at the old reducer. Repair at `324bff1` rejects the whole malformed response before tool admission and retains original/native evidence separately from effective context. Historical recovery consumes each result once. Source/native/demo/package/installed and hosted Linux/macOS passed | Closed within exercised identity/recovery scope; malformed collections and idle resume remain safe without rewriting original evidence, and the extracted runtime checks one-use historical results |
| F7 | Filesystem aliases and mutation/conflict guards | Repair at `be11890` passed portable regressions, build/format/compile, 763 native-inclusive tests, demo/package/both installed proofs and hosted Ubuntu/macOS. The dedicated Mac fixture established actual case/normalization alias inode identity before verifying metadata denial; portable child fixtures cover case/normalization/format-control claim conflicts | Closed within exercised alias scope. Original approval/execution paths remain intact; the policy intentionally denies some physically distinct names and does not promise arbitrary filesystem equivalence or race protection |

## Additional concerns

| ID | Assessment | Required disposition |
| --- | --- | --- |
| S1 | Controlled suspended Sessions reproduced uncaught 5-second approval and 10-second cancellation exits. A separate killed-client fixture reproduced the unowned root Session. The CLI now registers ownership, catches request exits without printing private reasons/retrying, stops its reader and attempts bounded cleanup. Build/format/compile, 50 focused and 768 native-inclusive tests, demo/package/both installed proofs passed | Hosted platform gate pending. Sequential cleanup or slow storage may still exceed a caller deadline; unconfirmed cleanup remains explicit rather than extending deadlines or asserting effects failed |
| S2 | Process-group identity reuse after leader reaping is a proposed race, not a reproduced incident | Inspect guard/reaping ordering and platform semantics before accepting or rejecting; avoid claiming a PID-reuse exploit without evidence |
| S3 | A gated 138 KB valid Unicode delta reproduced `invalid_chunk` closure after start acknowledgment. Provider-to-broker fragmentation now reuses UTF-8 boundaries and sequential bounded pushes; fixtures verify exact text, one original UI delta, contiguous v2 ranges and unchanged private native response. Direct oversize pushes still refuse. Source/native/demo/package and both installed proofs passed, including the new extracted-runtime large-delta probe | Hosted platform gate pending. Buffer/deadline bounds and failure under genuine backpressure remain unchanged; this is visible-text fragmentation, not media support |

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
