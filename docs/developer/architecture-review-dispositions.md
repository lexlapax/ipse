# Architecture review: dispositions and repair gates

P24's first independent critique targets
`21e59fefea90faa028bc752899d776a09da357af`. The operator returned the report in
the private working conversation on 2026-10-17. This document is its sanitized
finding register and supervisor verification record; the full report and any
exploit details remain outside Git. The [plan](../plan.md) owns scheduling and the
[evaluation protocol](self-hosting-evaluation.md) owns review/scan acceptance.

## Provenance and coverage

**Current gate:** the fresh report for source `091b2bd` (evidence `20b377c`)
withheld acceptance and found two applicable defects despite the prior green
handoff. The requested [supervisor adversarial audit](architecture-self-audit.md)
reproduced and repaired them and five additional interaction defects. Candidate
`7810925` passes local and hosted Linux/macOS checks. The
[replacement brief](../operator/architecture-review.md) assigns independent
repair-interaction coverage first, then the explicit remaining checkpoint below.
Historical closed rows describe exercised scope; neither those rows nor this
internal audit grant architectural acceptance. The scan and P25 remain gated.

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
six minutes plus writing. The one reported operator decision retained that existing
session. No code or tests were executed. The reviewer accepted
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
| D6 | Torn budget records fail closed without automatic ledger repair | Challenged in fresh-review PA-2. Keep refusal while evaluating explicit evidence-preserving recovery; no automatic truncation or refund of unknown liability |
| D7 | Journal retention and retrieval deletion have different meanings | P25/P26/P27 must distinguish retrieval tombstones, no-resurrection, namespace migration/collection, journal redaction/access policy and secure erasure. A memory extension alone cannot promise removal of immutable host evidence |
| D8 | Earlier text pressure could fail the main request | Superseded by the operator's PA-1 choice: optional delivery detaches; explicitly required delivery can refuse admission. S3's bounded fragmentation remains intact |
| D9 | Trusted executable code and explicit native execution have different OS boundaries | Preserve the documented trust model and macOS best-effort detached cleanup; no blanket confinement claim |

## Follow-up findings and verification

These A identifiers belong to the `b570ef8` follow-up, separate from F1–F7.
Local regressions use synthetic content and isolated homes; no live model service
or operator credentials are involved. Candidate `b5297be` passed its full local
handoff and hosted Ubuntu/macOS source/package/installed checks, including both
Mac enforcement steps. A1–A5 are addressed within that exercised scope; A6/A7 remain
explicit limits. Exact evidence belongs in [testing](testing.md#current-evidence-and-next-checks),
and these repairs do not close independent architectural coverage.

| ID | Assessment and repair | Verification and remaining limits |
| --- | --- | --- |
| A1 | Reproduced: a relayed newline-delimited fake prompt remained below the actual pending approval. The initial repair retained and redrew the bound proposal; PA-7 replaces per-chunk redraw with bounded display deferral while retaining local-command redraw | Controlled subscriber and actual two-child CLI/HTTP fixtures exercise read-result versus shell-approval ordering. Terminal control escaping remains active; returned prose remains untrusted |
| A2 | Reproduced with a suspended writer: the default call timeout escaped with its private request term. Explicit five-second writer calls now return an unconfirmed-write error; every mandatory append path deliberately stops Session as `journal_unavailable`. Termination stops owned work and confirms writer exit before releasing the lock | Controlled callback-stall regressions verify provider cleanup, canceled queued append, and a real completed shell effect whose unrecorded result resumes unknown without replay. This is not a kernel fsync/power-loss test. Kernel IO can still delay writer termination and client cleanup confirmation; no append retry or deadline relaxation |
| A3 | Reproduced live admission of oversized question IDs. `Ipse.ToolCall` now defines opaque valid UTF-8 IDs of 1–256 bytes for live batches, question restore, extension parent/source and question-source validation. Handoff retains a stricter display encoding and hashes unsafe historical IDs | Boundary ASCII/multibyte/punctuation question IDs survive abrupt interruption, resume and answer; 257/300-byte and oversized multibyte IDs are refused before questions or effects and leave resumable idle history. Existing oversized checkpoints are not silently rekeyed; use inert diagnosis/handoff if required. Host identity includes the shared validator |
| A4 | Missing/non-directory parents now fail a read-only preflight before `File.write` is attempted | Real filesystem refusals pass. A later write failure remains unknown even after successful preflight; the check is not a path lock or proof against races. Other ambiguous write failures stay conservative |
| A5 | Corrected stdio retry commentary and native guidance: the unreaped anchor can keep group signaling successful after ordinary children exit | Documentation matches bounded drain/disconnect behavior; no native behavior change or stronger detached-child claim |
| A6 | Accepted residual: no cumulative journal quota, full-history startup/resume validation and no live same-size rewrite authentication | Existing persistence limits remain explicit; same-user file tampering is not a security boundary. Future retention/redaction requires a reviewed generic contract |
| A7 | Accepted residual: ledger reads/prefix hashing remain linear and contention may abort paid in-flight work, retaining unknown liability | No weakening of durable accounting, source validation, shared-overdraw refusal or billing claims |

## Fresh cloud review and PA dispositions

The fresh cloud report targets source `b5297be`, base `b570ef8`, original
`21e59fe` and evidence `b08cd76`. It reports a fresh Opus 5.5 subscription session,
medium effort, no subagents/billing change/operator help, about 20.5 minutes plus
writing, and no executed code/tests. A worker restart reportedly lost no work.
It found no Critical/High defect in inspected scope but explicitly withheld
acceptance. This is independent source evidence, not runtime reproduction or a scan.

| ID | Supervisor assessment | Current action and evidence |
| --- | --- | --- |
| PA-1 / D8 | Reproduced optional pressure discarding a completed response | Operator-approved optional detachment and explicit required enrollment are implemented. Session/broker/actual-provider fixtures cover pressure, broker loss, healthy required peers, completion acknowledgment, fixed failure reporting and retained paid usage. Local native-inclusive and hosted Linux/macOS handoffs pass through `091b2bd`, including package/both installed proofs. Startup integrity and OS cleanup receipts remain separate |
| PA-2 / D6 | Torn ledgers still refuse; the reviewer challenges that recovery cost | A real budget fixture verifies refusal preserves both ledger and partial journal, then explicit inert handoff into a fresh quota without replay, refund or transfer of old liability. This is continuation, not tree repair. Any future repair must lock/validate the complete canonical tree and preserve original evidence; blindly dropping a partial record is not adopted |
| PA-3 | Task death alone does not acknowledge exit of task-owned shell groups or extension VMs | Initial scopes passed local/hosted checks at `451f97c`, but N-A1 exposed an invalid lifecycle closure, and internal IA3–IA5 exposed omitted nested/MCP receipts and pre-attachment ownership. Reproductions, repairs, capture-on recovery and local/hosted checks pass through `7810925`. Independent interaction coverage remains required; detached-descendant limits remain separate |
| PA-4 | Reproduced fresh project skill shadowing on resume | Bounded catalog/provenance checkpoints retain selection, report discovery drift and refuse changed bodies/resources until explicit refresh. Corrupt snapshots refuse before tail repair. Legacy sessions checkpoint first observed selection at the next request; idle opening stays inert |
| PA-5 | Auth accepted an unsupported proxy by falling back to direct egress; MCP private pools had no proxy options | Shared OTP/Finch policy at `42d9f1f` passed local and hosted Linux/macOS source/package/installed gates. Real local CONNECT fixtures cover auth, inference and MCP; unsupported schemes refuse and proxy credentials do not become origin headers. No live account or remote origin was used |
| PA-6 | CLI endpoint overrides lacked profile-equivalent validation | Shared provider URI policy now covers profiles, CLI before credential acquisition and actual adapter routing. Remote cleartext, userinfo/query/fragment and malformed routes refuse; explicit loopback fixtures remain usable. Included in the PA-5 checks |
| PA-7 | Reproduced 101 full approval blocks for 100 sibling chunks | Bounded deferral (64 events/64 KiB) retains the complete authoritative proposal; local commands can redraw, overflow is visibly counted after the decision. Real interleaving fixtures preserve approval binding |
| PA-8 | Anthropic assistant-first rejection remains speculative; official Messages docs do not establish it | A validated checkpoint is user-role historical context on Anthropic's wire only. A real adapter fixture preserves canonical bytes and native continuation, and refuses malformed checkpoint markers. No live failure or paid revalidation is claimed |
| PA-9 | Reproduced a native effect and delegated decision mismatch for nonboolean approval | Literal `true` governs native/delegated/extension decisions and receipts. Native no-write, delegated denial and extension tool/host-action regressions pass with local and hosted handoffs at `451f97c` |
| PA-10 | Reproduced acceptance of a forged second invocation for the same parent call | Validator consumes each source request/call occurrence once; the fully bound duplicate intent/result/tool-message fixture refuses before repair or replay. Recovery checks and local/hosted handoffs pass at `451f97c` |
| PA-11 | Reproduced acceptance of an extension's own closing delimiter | Reserved opening/closing markers refuse before committing a transform or dispatching inference. Original records remain intact; projection/recovery and local/hosted handoffs pass at `451f97c` |
| PA-12 | Reproduced browser waiting blocking refresh/logout | Waiting releases the lock; callback reacquires it and compares the complete protected state before code exchange. Authorization epochs also invalidate callbacks after logout with no existing token. Synthetic refresh/logout races pass without real accounts |
| PA-13 / A6 | Prefix replay and append reducers add cost; startup remains unbounded | Ordinary message/action accumulation is linearized. Historical questions skip repeated durable validators but still reconstruct and hash each prefix; no cached projection is reused. One-sample 64 MiB/200-question open remains about 20 seconds: no material latency win. Repeated projection/JSON encoding/hashing and full startup passes remain measured limits, not closed performance claims |
| PA-14 / D9 | Trusted shell inherits environment beyond three stripped keys | Accepted explicit trust limitation; no new confinement or secret-isolation claim |
| PA-15 / A2 | Five-second journal acknowledgment deadline deliberately stops Session | Accepted fail-closed policy and tested callback-stall limitation, not a new reproduced defect |

The operator selected role separation. Core-owned rules remain system text;
workspace/skill/contribution data occupy a labelled user-role reference message.
Extension helper calls likewise use fixed core rules and user-role JSON task data.
Compaction and diagnostics count both header messages; canonical conversation and
native continuation remain intact. Provider/recovery fixtures and both precompiled
installed proofs pass with the local full handoff and hosted Linux/macOS matrix
through `091b2bd`. A passing fixture does not certify prompt-injection resistance.

Remaining coverage now prioritizes lifecycle runtime/child/event/ephemeral and
their tests; invocation workflow/state/question tests and event/job/history/
subscription/usage-read tests; auth and MCP client/HTTP/config tests; handoff,
compaction/workspace-session tests; state/child-usage/store implementations and
tests; macOS cache/signing/sandbox and stdio tests; delegation/parallel/budget
test bodies, usage and normalization. The cloud report's actual coverage replaces
the earlier blanket-unread list; no accepted repair disposition closes those gaps.

## Latest fresh review and supervisor audit

The private fresh-session report for source `091b2bd`, base `b5297be`, original
`21e59fe` and evidence `20b377c` reports Opus 5.5, medium effort, subscription
without overage, read-only committed-object inspection and no execution or edits.
It withholds acceptance, with context-limited coverage in every area. Those are
reviewer-reported facts; its raw critique remains private. Prefix these new A
identifiers with `N-` to distinguish them from the older follow-up's A rows.

| ID | Disposition | Required evidence |
| --- | --- | --- |
| N-A1 | Reproduced invalid lifecycle closure after owned task death; use existing `cleanup_failure`, unconfirmed | Model and tool deaths with capture on, deliberate normal stop, durable closure and inert resume |
| N-A2 | Reproduced diagnostic receipts poisoning a pending extension question; validate the independent receipt stream before allowing it through the action reducer | Real sink/question kill-resume-answer-resume, saved diagnosis/handoff, event jobs before inference and after answer, explicit sink stop and corrupt-receipt refusal |
| N-A3 | Clarified transport completion versus durable answer admission, preserving the existing frame protocol | Healthy optional peer receives completed transport; failing required peer prevents admission, retains failed accounting and returns distinct delivery failure. Use Session outcome or `answer.committed` for admitted answers |
| N-A4 | Reproduced deferred terminal output overtaken by newer queued output; drain saved display directly in FIFO order | Suspended real client, older held output, approval decision then newer output; proposal binding/overflow tests retained |
| N-A5 | No demonstrated revocation defect; local reauthorization does not prove remote invalidation | Public profiles/sessions contract specifies sign-out revocation, not older-grant behavior on replacement. Document uncertainty; do not add speculative account calls or claim live validation |
| N-A6 | Reproduced quoted multibyte skill metadata parsing error; remove matching ASCII delimiter bytes | Real discovery/load with single/double-quoted Unicode names and descriptions |

The requested [supervisor audit](architecture-self-audit.md) additionally records
IA1–IA5: subscription question checkpoints, provider response bounds, nested-task
scope inheritance, MCP cleanup receipts and pre-attachment task ownership. These are source/runtime repairs,
not knowledge-specific extensions. Each has a pre-fix counterexample and new
verification. The internal report names actual inspected boundaries/test bodies
and remaining independent coverage; no internal result grants acceptance.

### Independent coverage checkpoint

This is the latest reviewer's reported static coverage at `091b2bd`, sanitized
from the private report. It is not a passing verdict or a claim that current
dependencies are unchanged. Line ranges refer to that exact revision. The next
review first checks the new delta; carry-forward requires comparing relevant
source and interactions, not merely finding a file in this table. Earlier reports
may add coverage only with their own pinned evidence and the same comparison.

| Package | Latest reported reads | Remaining checkpoint |
| --- | --- | --- |
| R: interactions | Lifecycle modules, diagnostics, observability, developer trace and worker lease; Session init/restore/close/DOWN and extension question/action paths. Full lifecycle-runtime/tool/child and observability tests, task-resource tests; stream and recovery deltas | Reopen changed runtime/test bodies and affected dependencies at the new source. Lifecycle top-level/metadata/answer, developer-trace, diagnostics and parity/conformance test bodies were unread in this external pass |
| S: SDK/delivery | Invocation/actions/operation/host, full event-job/subscriptions/feed/channel; history execute/collect/source validation; state namespace/operations, full store, child-usage restore/source functions. Invocation tests 1085–1800 and event-job tests 200–end | Invocation tests 1–1085, question-session/tool-action/services tests; usage-read, text-resources/consumer and their tests; subscriptions/history/feed/text-event bodies; manifest/conformance/config bodies and state/store/child-usage/model-job tests |
| C: context/egress | Auth/main HTTP/store, HTTP proxy/profile, provider HTTP delta, MCP HTTP/config endpoint parsing/catalog dispatch; full skills/context/handoff, compaction delta. Full pending-refresh, egress and native catalog tests; auth/workspace-session deltas | JWT, MCP client/schema/transport, provider Ollama/error/SSE and MCP HTTP/client/config/schema test bodies; workspace-context and tool-result compaction implementations/tests, handoff and skill-resource tests |
| O: OS/persistence | Full task resources; runner/native shell/stdio deltas, macOS cache/build/validation, delegation run-child; task-resource and tool-recovery deltas. Targeted terminal escaping, path normalization and environment stripping checked in phase B | Native sources beyond deltas, macOS/stdio/Linux policy and filesystem test bodies, delegation/parallel/budget bodies, usage/normalizer, writer and ledger. Recheck F3/F4/F7/S1/S2 substantively; grep or delta inspection did not establish full coverage |

The report also left some Session and extension/CLI test-delta hunks unread.
Package R must read the entire subsequent runtime/test delta, while the other
packages retain these explicit omissions. Each returned report updates this
checkpoint with exact functions and test bodies; partial packages continue from
their next unread point. No ordinal review count closes the gate.

## Execution order and completion

The scoped F1–F7/S1–S3 and A1–A5 repairs passed their own source/native/package/
installed and hosted gates through `b5297be`. The
[testing record](testing.md#current-evidence-and-next-checks) owns exact results,
revisions and remaining verification limits. Future repairs still need a
regression or measured counterexample, coherent operator/developer guidance and
their own checks before commit/push; an earlier green baseline does not cover them.

The fresh cloud reports satisfy fresh-session provenance but do not close
coverage or acceptance. The internal audit and repairs now pass their platform
checks through `7810925`; only then was the [review brief](../operator/architecture-review.md)
replaced. Use the latest omissions and bounded coverage packages from the evaluation
protocol; do not restart an unbounded whole-repository review. Earlier briefs are
preserved in the [archive](../archive/index.md); preserve all private critiques.
The next session must retain its source assessment before checking this register
and identify inspected test bodies and omissions. Baseline security and P25 remain
gated by adequate coverage and applicable repairs. No scan has run; P24 is open.
