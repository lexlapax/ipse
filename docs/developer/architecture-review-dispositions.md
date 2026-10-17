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

The operator returned a second report for source
`b570ef8422d83f70ebd13386a0e0bf5630d9c3d6`, with documentation evidence at
`d14d6acc4c9f6ec003f94006a9bf4a0d9b395d9a`. The same reviewer used the same
session, retaining the first critique. It is a same-reviewer follow-up, not the
requested fresh independent assessment. Reported settings were Opus 5.5,
subscription, effort auto, no subagents or billing change; inspection lasted about
six minutes plus writing. No code or tests were executed. The reviewer accepted
the scoped F/S repairs and explicit D policies, while identifying adjacent gaps
and explicitly withholding architectural acceptance because of omissions.

New inspection covered the repair diff, terminal renderer, writer, retained native
group owner, event jobs and HTTP profile. Session extension/question paths,
subscriptions, MCP HTTP and test bodies received partial coverage. Invocation,
actions, projection, services, contributions, text resources/consumers, feed channel,
most usage readers, compaction, workspace context, skills, auth, MCP client/schema/
config, lifecycle/observability and OS sandbox implementations still need substantive
independent inspection with their test bodies. A fresh reviewer should prioritize
these surfaces rather than repeat only the repair delta.

## Findings and verified repairs

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
| S1 | Controlled suspended Sessions reproduced uncaught 5-second approval and 10-second cancellation exits. A separate killed-client fixture reproduced the unowned root Session. Repair at `fe54206` registers ownership, catches request exits without printing private reasons/retrying, stops the reader and attempts bounded cleanup. Source/native/demo/package/both installed proofs and hosted Ubuntu/macOS passed | Closed within exercised caller/owner scope. Sequential cleanup or slow storage may still exceed a caller deadline; unconfirmed cleanup remains explicit rather than extending deadlines or asserting effects failed |
| S2 | Source confirms numeric group IDs remained usable after leader reaping in shell, stdio and native Mac signature-check cleanup; no PID-reuse incident is reproduced. Repair at `b570ef8` pins identity with a retained inert group owner, default child-status handling and mutex-bound signals. Process/native, 771 full native-inclusive tests, demo/package/both installed proofs and hosted Ubuntu/macOS passed, including native Mac signature checks and sandbox enforcement | Closed within exercised group-identity scope. Covers ignored-SIGCHLD ownership, late signal refusal and EOF-confirmed ordinary-child exit after abrupt owner death. One extra owned process per invocation; no new dependency or detached-descendant containment claim |
| S3 | A gated 138 KB valid Unicode delta reproduced `invalid_chunk` closure after start acknowledgment. Repair at `fe54206` reuses UTF-8 boundaries and sequential bounded pushes; fixtures verify exact text, one original UI delta, contiguous v2 ranges and unchanged private native response. Direct oversize pushes still refuse. Source/native/demo/package/both installed proofs and hosted Ubuntu/macOS passed, including the extracted-runtime large-delta probe | Closed within exercised visible-text scope. Buffer/deadline bounds and failure under genuine backpressure remain unchanged; this is fragmentation, not media support |

Supervisor verification also found a recurring Mac CI concern outside the critique:
documentation-only `3dd7110` failed two MCP catalog stdio discoveries before tool
dispatch. The later F1 matrix passed both hosts without an MCP runtime change.
The cause remains unconfirmed; a green replacement run is not a root-cause repair.
Exact failed/passing runs are retained in the testing record.

## Design choices and future contracts

| ID | Current assessment | Follow-up |
| --- | --- | --- |
| D1 | Host/runtime identity pins intentionally refuse incompatible extension resume. “Any rebuild” is too broad: unchanged bytes are not a changed digest. Repeated preparation against the same code/options produces identical identities; existing changed-host/artifact/options regressions refuse activation/resume | Accepted compatibility policy; retain frozen-runner or explicit handoff guidance. This verifies identical current bytes, not every toolchain's rebuild reproducibility; do not weaken recovery identity as a convenience fix |
| D2 | State namespaces include artifact and source identity; upgrades/moves can select a different namespace | P25/P26 proposals must address stable logical identity, explicit export/migration/collection and deletion across retained versions; no silent state reassignment |
| D3 | Expired/revoked extension authority can refuse session activation, including idle resume. A real-expiry fixture confirms existing saved diagnosis and operator-written handoff succeed with unchanged journal bytes and no provider/callback activation | Accepted activation boundary with an existing read-only recovery path; no new API or execution of expired code is needed |
| D4 | Fixed reservations are estimates and can understate in-flight input | Accepted documented limitation; preserve observed peaks and overdraw refusal, and evaluate stronger estimators separately from an invoice guarantee |
| D5 | A controlled interleaved two-request fixture confirms shared overdraw refuses an otherwise completed response within its own reservation; both provider completions and actual usage remain in the budget ledger. Refused assistant/native content has no durable quarantine; Session admission and provider completion are different boundaries | Retain the current fail-closed whole-tree policy and document content loss. No new authority to expose/execute paid work. Future private quarantine/export needs a reviewed main/summary/helper contract; this fixture is not a full parallel-child scheduling or live-provider test |
| D6 | Torn budget records fail closed without automatic ledger repair | Accepted documented limitation; any future recovery must preserve the original ledger and unknown liability |
| D7 | Journal retention and retrieval deletion have different meanings | P25/P26/P27 must distinguish retrieval tombstones, no-resurrection, namespace migration/collection, journal redaction/access policy and secure erasure. A memory extension alone cannot promise removal of immutable host evidence |
| D8 | Text pressure can fail the main request by the selected contract | Accepted bounded-pressure policy; S3's separate avoidable fragmentation failure is repaired without expanding buffers/deadlines |
| D9 | Trusted executable code and explicit native execution have different OS boundaries | Preserve the documented trust model and macOS best-effort detached cleanup; no blanket confinement claim |

## Follow-up findings and verification

These A identifiers belong to the `b570ef8` follow-up, separate from F1–F7.
Local regressions use synthetic content and isolated homes; no live model service
or operator credentials are involved. Completion still requires the candidate's
full handoff and hosted platform checks recorded in [testing](testing.md).

| ID | Assessment and repair | Verification and remaining limits |
| --- | --- | --- |
| A1 | Reproduced: a relayed newline-delimited fake prompt remained below the actual pending approval. CLI now retains its reference, full proposal and MCP target context and redraws them after interleaved output or local commands, without buffering returned text | Controlled subscriber regression passes; an actual two-child CLI/HTTP fixture also exercises the read-result versus shell-approval ordering. Terminal control escaping remains active; returned prose remains untrusted |
| A2 | Reproduced with a suspended writer: the default call timeout escaped with its private request term. Explicit five-second writer calls now return an unconfirmed-write error; every mandatory append path deliberately stops Session as `journal_unavailable`. Termination stops owned work and confirms writer exit before releasing the lock | Controlled callback-stall regressions verify provider cleanup, canceled queued append, and a real completed shell effect whose unrecorded result resumes unknown without replay. This is not a kernel fsync/power-loss test. Kernel IO can still delay writer termination and client cleanup confirmation; no append retry or deadline relaxation |
| A3 | Reproduced live admission of oversized question IDs. `Ipse.ToolCall` now defines opaque valid UTF-8 IDs of 1–256 bytes for live batches, question restore, extension parent/source and question-source validation. Handoff retains a stricter display encoding and hashes unsafe historical IDs | Boundary ASCII/multibyte/punctuation question IDs survive abrupt interruption, resume and answer; 257/300-byte and oversized multibyte IDs are refused before questions or effects and leave resumable idle history. Existing oversized checkpoints are not silently rekeyed; use inert diagnosis/handoff if required. Host identity includes the shared validator |
| A4 | Missing/non-directory parents now fail a read-only preflight before `File.write` is attempted | Real filesystem refusals pass. A later write failure remains unknown even after successful preflight; the check is not a path lock or proof against races. Other ambiguous write failures stay conservative |
| A5 | Corrected stdio retry commentary and native guidance: the unreaped anchor can keep group signaling successful after ordinary children exit | Documentation matches bounded drain/disconnect behavior; no native behavior change or stronger detached-child claim |
| A6 | Accepted residual: no cumulative journal quota, full-history startup/resume validation and no live same-size rewrite authentication | Existing persistence limits remain explicit; same-user file tampering is not a security boundary. Future retention/redaction requires a reviewed generic contract |
| A7 | Accepted residual: ledger reads/prefix hashing remain linear and contention may abort paid in-flight work, retaining unknown liability | No weakening of durable accounting, source validation, shared-overdraw refusal or billing claims |

## Execution order and completion

The scoped F1–F7 and S1–S3 repairs have passed their own source/native/package/
installed and hosted gates through `b570ef8`. The
[testing record](testing.md#current-evidence-and-next-checks) owns exact results,
revisions and remaining verification limits. Future repairs still need a
regression or measured counterexample, coherent operator/developer guidance and
their own checks before commit/push; an earlier green baseline does not cover them.

The `b570ef8` follow-up does not supply the required fresh-session coverage.
After verifying these new repairs, refresh the
[review brief](../operator/architecture-review.md) to pin the resulting source and
prioritize the omissions above. The next reviewer must start without prior review
context, preserve its own source assessment before reading this register and
record inspected test bodies and specific uncovered paths. Preserve both earlier
critiques and challenge every disposition. Baseline security and P25 remain gated
by adequate independent coverage and applicable repairs. No scan has run; P24 is open.
