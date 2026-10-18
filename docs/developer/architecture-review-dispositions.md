# Architecture review: dispositions and repair gates

P24's first independent critique targets
`21e59fefea90faa028bc752899d776a09da357af`. The operator returned the report in
the private working conversation on 2026-10-17. This document is its sanitized
finding register and supervisor verification record; the full report and any
exploit details remain outside Git. The [plan](../plan.md) owns scheduling and the
[evaluation protocol](self-hosting-evaluation.md) owns review/scan acceptance.

## P25 final security triage

The separately approved GPT-5.6 Sol/high scan completed on 2026-10-18 against
`b5ddd0205a57b14afdc3038bd73c04ec7fdfb9c2`, run
`wfr_3b03c34c933a9aebe79f0641425405058caa5dd0bac7f68555a421c31e32c8c9`.
The supervisor read every report page plus the findings, manifest and coverage,
verified all four service digests and checked the pinned revision. It reports two
Medium findings, no High/Critical findings, and **partial** static coverage.
The initial repository-filtered findings query returned no entries; the unfiltered
query returned both canonical findings. This is not evidence of zero findings or
an ingestion failure.
Raw artifacts and reproduction details remain private.

| ID | Surface | Current disposition | Required gate |
| --- | --- | --- | --- |
| FSC-1 (`csf_d8fb991afccccf6790b8e749`) | Proposal-bound terminal confirmations | Reproduced with a real CLI/loopback fixture. Fresh per-proposal codes prevent buffered/replayed input. Internal review also reproduced buffered structured answers; per-question codes fix that adjacent case. All 30 CLI tests, full local handoff and hosted `f467de9` checks pass | Closed within the tested scope and refreshed static approval review at `f467de9`; no whole-design certification |
| FSC-2 (`csf_07c9aa59e131a3393e3639f5`) | Durable journal growth and bounded recovery/listing | Finite operator-narrowable limits, a reserved terminal receipt, incremental decoding and header-only listing pass quota/question/unknown-effect fixtures, full local handoff, old compiled proofs and hosted `f467de9` checks. Independent delta findings below are also reproduced and repaired | Closed within bounded per-file policy and refreshed static persistence review at `f467de9`; total-directory storage and other stated limits remain |
| FSC-3 (`csf_3bd48e9866059c02fcc3e7b7`), Medium | Provider stream assembly and intermediate work | A retained-line probe reproduces disproportionate work. Three new admission regressions fail on the scanned source. The candidate uses reverse fragments, new-byte line scanning, finite event/item/call limits and in-parser deadline checks; all 62 provider cases pass | Local full native/package checks pass; hosted verification and affected independent review remain open |

The scan prioritizes major runtime boundaries but defers full file-level review
of parts of Session, budget/accounting, compaction, lifecycle, text delivery,
subscription/job helpers and supporting tests/docs/examples/scripts. Its lack of
runtime provider, sandbox or package execution is distinct from the inspected
hosted source/native/installed receipts. The earlier baseline's coverage and
independent architecture omissions retain their own identities; they are not
silently expanded by this report. P25 remains open through repair and affected
coverage refresh. After both hosted jobs passed, the operator-approved one-time
verification scan ran from 18:16:25 to 18:32:42 UTC against
`f467de9d9424d1f77d59bcff036a2e7cfec9e1e4`, run
`wfr_abc3fbbecf49982d820b6c798513b78ed65eadd153d8b10a785c8ef15d242d20`.
It explicitly selected GPT-5.6 Sol/high and the existing private environment;
continuous monitoring remains off. All four original artifact digests, the exact
revision and the single unfiltered canonical finding match. The complete report
was read. It records one new Medium finding, no High/Critical findings, and partial
coverage of 417 tracked paths: implementation/automation surfaces were reviewed,
while historical docs and remaining test bodies were not individually audited.
No code, tests or OS enforcement ran in the scan. Reported usage is $30.07,
fully covered by allowance; $405.2560288 remains. No further Cloud run is launched.

The resource probe uses identical fragmented partial-line input on Linux: 1/2/4 MiB
took approximately 0.63/3.33/12.97 seconds before repair and 2.75/2.59/4.86
milliseconds afterward, retaining exact bytes. This is a local controlled probe,
not a portable latency guarantee. OTP can optimize some binary appends; the
observed rescan and list/field accumulation justify the repair without asserting
that every concatenation copies. A first expanded provider run passed 59/60: its
new rejection fixture continued byte writes after the intended client abort.
Sending that fixture's bounded body before awaiting closure corrects staging;
existing split-byte fixtures and assertions remain. Corrected provider runs pass
60, then 62 cases after adding success/error chunk-exhaustion coverage.

### Independent repair-delta review

A fresh read-only installed-Ipse session reviewed `641dcae` → `81b67f5` using
the already approved own ChatGPT subscription, explicit GPT-6.1 Sol/high, and a
477-file frozen base/candidate packet. Prior findings, verdicts, results and private
data were excluded. It read every changed runtime module and meaningful changed
test body, including the complete Session implementation and supporting reducers.
Two of six supplied contract documents were not located; conformance coverage is
partial. This is a separate model context, not different-vendor or whole-design
acceptance.

The report completed within its original limits: 451.4 seconds, 28 requests,
86 proposals and 78 started calls. Only reads/inert skill loads occurred; cleanup
was confirmed. Two supervisor allowlist mistakes interrupted legitimate skill
reads; both explicit continuations and cumulative limits are retained. The
13,825-character private report is SHA-256
`06d4965ea3df36eb6cdbe60ef25b4618ca9966de62724f7af65284aedb055aa9`.

| ID | Finding and evidence | Candidate correction and gate |
| --- | --- | --- |
| P25-DA1, Medium | Inactive append could return after two writer-call timeouts while its temporary writer retained a queued mutation. A controlled real-lock probe reproduced a late append under the next owner's acquired lock; the regression fails before repair | Reuse admission/fsync synchronously inside a tracked filesystem completion owner, with no temporary GenServer or hidden cleanup timeout. All three append modes retain the real lock across a delayed mutation; a caller-death fixture verifies guardian retention. Closed within the tested scope: full local native/package, exact `f467de9` hosted checks and refreshed static persistence review pass |
| P25-DA2, Medium | CLI resume called whole-history load before resolving lowered operator journal limits. Tracing the real CLI reproduces the default-policy full load; the regression fails before repair | Discover only a bounded header, then resolve operator policy before full Session loading. Byte, event and record-bound cases pass with unchanged history. Closed within the tested scope: full local native/package, exact `f467de9` hosted checks and refreshed static persistence review pass |

The returned interruption/combination test ideas remain coverage limitations,
not additional reproduced defects. No findings are promoted to closed on source
inspection alone. The successful `81b67f5` hosted matrix covers the reviewed code.
The subsequent corrections now pass the complete `f467de9` Linux/macOS matrix,
including native enforcement and 50 installed assertions per host; the
[verification record](testing.md#current-evidence-and-next-checks) retains exact
counts and exclusions. The `f467de9` scan's persistence review reports no further
finding; these two dispositions are closed within that scope. The provider-stream
finding is separate and its repair is not covered by the earlier scanned bytes.

## Provenance and coverage

**Current decision:** P24's scoped supervisor readiness gate is accepted for the
supervised P25 trial at `375e607`; see the [decision](#p24-scoped-readiness-decision).
The focused `86d4d69` pass remains incomplete and earlier independent verdicts are
unchanged. Following the operator's scan-first instruction, the static baseline
completed at `8b4f706`; its checked repairs and composition follow-ups passed
source/native/package/installed and hosted gates. This is not a new independent
post-fix verdict or second scan. The
[current checkpoint](../operator/architecture-review.md) links actual execution;
dated failures/passes remain in [testing](testing.md#current-evidence-and-next-checks).

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

## Review of 091b2bd and supervisor audit

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

## Package R review and current repairs

The private package R report targets source `7810925`, base `091b2bd`, original
`21e59fe` and evidence `a46cc66`. It reports a fresh context, configured Opus 5.5
without verification of the served model, subscription/no overage, no subagents,
read-only committed-object access and no execution or writes. It lasted about
half an hour with an interruption and two short operator prompts. These are
reviewer-reported facts. Package R is partial and unaccepted; S/C/O were not
started, and the raw report remains private.

| ID | Current disposition | Evidence and remaining gate |
| --- | --- | --- |
| R-1 | Reproduced a registered MCP ticket surviving pre-spawn refusal. A captured Session additionally reproduced SDK failed-start link exit killing its worker | Shared owned-stdio launch settles known pre-spawn refusal and preserves post-spawn uncertainty for MCP/extension workers. SDK link exits are isolated in a nested scoped task with a caller guardian; the outer worker retains its scope link. Trapping exits in the outer worker failed the new blocked-MCP scope-death regression and was replaced before handoff. Scoped negative launches, capture-on refusal/retry and prompt scope-death termination pass; final a5912ab platform gates are recorded in testing |
| R-2 / IA2 | Confirmed: the earlier provider cap covered streamed success only; the original broad claim was incorrect | Partial bodies for 201/302/429/500 reproduced timeout rather than limit refusal. Existing Finch now streams all statuses, counts bytes before adapter/error accumulation, bounds error retention and aborts at declared/content or chunked limits. Local provider/error/egress checks pass; no new dependency or live account claim. Final a5912ab source/package/installed and hosted gates pass |
| R-3 | Required delivery remains enrolled across idle consumer/broker loss until explicit release | Broker retains bounded failed enrollments, bound policy updates preserve Session state, and `Session.unsubscribe_text/2` lets the embedding operator release a lost handle. A further compaction regression reproduced the summary clearing that policy; summaries now preserve the main requirement. Main inference refuses until release. Enrollment remains process-local, not a durable resume requirement |
| R-4 | The earlier claim that the widened outcome assertion did not weaken evidence was too broad | Tests now separate controlled clean native exit 0/confirmed cleanup/usable Session, immediate clean exit with confirmed cleanup, and forced helper death with unconfirmed cleanup. Local strict cases pass. The precise cause of the earlier Mac unconfirmed result is not established by changing a test; keep it explicit until stronger evidence exists |
| R-5 | Reproduced shell/lock pre-spawn ticket leakage with a temporary nonexecutable helper | Resolve launch inputs before registration; a refused Port settles its ticket without claiming a launched helper exited. Negative shell/lock paths pass. The pre-spawn fixture uses actual `Port.open` permission refusal rather than assuming a missing interpreter is a pre-launch error |
| R-6 | Removed the startup lookup race by retaining a prepared guardian before spawning the HTTP borrower | Cancellation awaits that exact guardian even before borrower registration. Controlled pre-borrow cancellation, stalled teardown and existing MCP cancellation/TLS checks pass. The reported live race was not reproduced; this is source-order repair plus controlled lifetime evidence |
| Internal HTTP ownership follow-through | Reproduced confirmed task cleanup while a live HTTP borrower, socket and pool remained | HTTP guardians now join the task scope where present, stop the borrower on cancellation, await pool exit and issue a real receipt. The socket-level regression passes. This covers the new provider client as well as direct scoped HTTP use; it does not confirm remote effects |
| Internal OS text admission | A NUL-containing command was actually truncated and executed, rather than refused as the initial negative fixture assumed | Shell command/cwd and lock paths now reject invalid UTF-8 and NUL before launch. The no-effect regression failed before repair and passes afterward |

Inspection of the intervening documentation-only `a46cc66` matrix found two
Ubuntu failures not covered by the earlier recorded green matrix: an empty PID
read during subscription-worker readiness and an unconfirmed diagnostic/question
close. Both exact tests passed 21 unchanged local runs. The PID fixture now
publishes atomically, with all liveness/cleanup assertions intact; the other
failure's cause remains unconfirmed. Its successful Mac job and installed
receipts do not close that cause. Exact results are in testing.

### Package R coverage checkpoint

The reviewer read the complete `091b2bd..7810925` runtime/test delta and the
added/changed regression bodies, but not all fixture helpers. Full implementation
reads include task resources, both MCP transports/client, provider HTTP, text
stream, lifecycle runtime, diagnostic resources and HTTP profile. Targeted
Session, runner, native stdio, action/subscription/worker, host/tool/model/service,
CLI and skill paths remain partial as recorded in the private report. Grep-only
provider-error inspection is not full coverage.

That review's next unread point was **Session task-result handling at source `7810925`
lines 1790–2030**, followed by event-job question restoration, TextConsumer and
Observability.Channel closure; Runner output/frame reducers; invocation/event-job/
text fixture helpers; lifecycle top-level/metadata/answer, developer-trace,
diagnostics and parity/conformance test bodies. Read the relevant remaining
Session functions in lines 2300–4230 and the subsequent repair delta. The SDK's
link/exit behavior is an explicit dependency boundary, not inferred from the
adapter. Updated internal reads do not count as independent coverage.

Earlier lifecycle/observability/developer-trace/diagnostics/worker-lease/handoff
implementations were reported byte-unchanged from `091b2bd` to `7810925` and can
carry forward subject to changed interactions. Their unread test bodies stay
unread by that reviewer. This remains the historical independent checkpoint;
the consolidated assessment should identify which omissions its actual reads
close. The later internal audit is separate evidence and does not rewrite this
reviewer's scope.

## Full internal audit and consolidated handoff

The implementation-side pass inspected all architectural boundaries and the
complete Session state machine, with actual meaningful test bodies rather than
file names alone. The [audit](architecture-self-audit.md) owns the inspected
surfaces, before/after counterexamples and residual limits. It does not claim
every older test or script was read. The historical independent checkpoint above
remains provenance for the single consolidated external handoff, not an instruction
to schedule four more external rounds.

| Internal finding | Disposition and exercised contract |
| --- | --- |
| FA-1 terminal stdio closure | Passive wait after terminal output retains real helper exit confirmation; closed-stdin fixture reproduced the old loss. Forced/missing receipts still refuse |
| FA-2 prompt admission | Invalid UTF-8 and raw/expanded input over 1 MiB refuse before history/inference. CLI admission handling and 16-task/1 MiB accepted queue have real interactive/headless/overflow fixtures |
| FA-3 required worker failure | Callback failure no longer automatically unsubscribes; current and following main requests refuse until explicit release |
| FA-4 auth/proxy | All-status auth reception bounded at 1 MiB using existing Finch; parsed 127/8 bypass excludes maliciously prefixed hostnames. Held-open length/chunked status fixtures abort before EOF |
| FA-5 compacted uncertainty | Handoff and saved diagnosis include unknown checkpoint actions, preserving occurrences alongside ordinary unknown results |
| FA-6 research identity | Ambiguous duplicate historical calls/results are excluded from available previews, consistent with capture refusal |
| FA-7 cleanup enum composition | Real task death with feeds and lifecycle active now closes with typed cleanup_failure, normal Session stop and inert resume; the earlier code raised in cleanup |
| FA-8 endpoint resume | Actual main destination is pinned before first request. Current/legacy routing mismatch refuses unchanged history; idle legacy direct routing cannot be reconstructed |
| Fixture readiness | All independently written worker PIDs publish atomically using per-worker stages; strict liveness/cleanup assertions retained |

## Consolidated assessment of a5912ab

The operator returned the complete private report for source `a5912ab`, base
`7810925`, original `21e59fe` and evidence `a21469e`. The reviewer reports a fresh
Opus 5.5 1M-context subscription session, default settings, no subagents or extra
operator help, committed-object/public dependency reads and no execution or
repository writes. Served model and dependency-tag/tarball equality were not
independently verified. Reading took about 15 minutes plus report writing. Phase A
was preserved before phase B. These are reviewer-reported facts, not supervisor
runtime evidence. Acceptance was withheld; no High/Critical defect was found in
the inspected scope.

| Item | Disposition | Verification and limit |
| --- | --- | --- |
| B-1 / A2 required extension cancellation/release | Reproduced and repaired: confirmed host cancellation releases its owned enrollment, while the next task must reenroll under unchanged required trust | Repeated cancellation/capacity and subsequent successful delivery; unexpected failure alone and uncertain cleanup still refuse. Embedding handles are separate; broker loss is not silently reset |
| A1 abnormal-death ownership / A7 queued writer | Reproduced unsafe resume with a suspended scope. Session.Lock now retains the native lock through actual tracked writer, worker, scope, resource and child-guard exits | Root/nested/delegated tests exercise teardown stalls and actual lock refusal/reacquisition; guardian loss stops without new appends. A later internal FIFO probe found that BEAM exit alone does not fence filesystem writes. Separately tracked FileEffect owners now finish admitted writes/repairs/appends and budget/state critical sections before unlock; the actual gated write and budget lock are regression fixtures. This does not authenticate same-user interference, confirm remote effects or strengthen detached cleanup |
| A3 private pool-supervisor death | Accepted conservative policy, now explicit: kill the borrower, stop Session normally, resume idle only by operator action | Corrected actual-supervisor fixture pins stop/local closure/inert resume. A cooperative alternative stalled the request; it was rejected. A newly reproduced child-exit race is separately repaired: the guardian waits for its supervised children before releasing the HTTP slot |
| A4 remote refresh rotation window | Accepted residual | Server rotation before local persistence cannot be atomically proven; no silent retry or account switch |
| A5 sequential cleanup deadlines | Accepted residual | Close/cancel can outlast the client while multiple resources stop. The lock can remain held until actual local quiescence; timeout is not permission to delete lock files |
| A6 request-free legacy destination | Accepted compatibility gap, wording corrected | Implicit-default resume cannot detect an unrecorded earlier custom route. Use a fresh reviewed Session when that route is unknown. Current metadata and recorded request hashes remain pinned |
| Native E-frame invariant | Retained current contract | No-output E is known pre-spawn failure only because the native runner does not return Err after dispatch. No new protocol or stronger guarantee is claimed |

The reviewer independently read the whole BASE..SOURCE delta and changed test
bodies, Session result/cleanup/restore paths, TextConsumer, observability close,
Runner frames, MCP transports/client change, auth HTTP/login/rotation and provider
HTTP/OpenAI. Fixture helpers outside the hunks remain partial. Prior unchanged
reads carry forward only at their reported scope. The ownership and resource
repairs passed their own frozen local and installed-artifact checks. The final
source/test revision `e8f7ad5` also passed hosted Linux/macOS verification;
[testing](testing.md#current-evidence-and-next-checks) retains exact receipts,
failed intermediate matrices and their unconfirmed causes. This execution
evidence does not close independent source-reading omissions.

Material independent omissions remain: SDK registry/manifest/catalog/grants,
CAS/tombstones, projection/contributions/services, UsageRead/TextResources and
conformance; lifecycle/diagnostics/parity test bodies and event-job restoration;
Anthropic/Ollama/SSE/error, JWT/store, MCP schema/config test bodies; workspace,
skills and compaction core; Linux/macOS sandbox/process-group/cache sources;
budget ledger/policy, normalization and delegation/parallel arbitration, plus
older test bodies. Internal inspection does not close those omissions. Hosted
receipts support execution scope, not independent source reading or acceptance.
The used consolidated brief is archived. The focused follow-through below does
not retroactively certify those omissions. No R/S/C/O sequence is scheduled and
no P25 run has executed.

## Focused completion at 86d4d69

On 2026-10-18 a fresh, nonpersistent Claude subscription process inspected a
credential-free Git export of `86d4d69`, whose runtime/tests match `e8f7ad5`, and
the `a5912ab..86d4d69` repair delta. Prior critiques and implementation-side
verdicts were excluded. Observed CLI metadata reports Opus 5.5, high effort,
Read/Glob/Grep only, no API key source, extra integrations or subagents. The run
lasted about 15 minutes. Raw output, prompt and exact read ranges remain private.

Its safeguard stopped the report during its first finding. The process exited
successfully but the final response explicitly states that the deliverable is
incomplete. Its conditional opening judgment is not acceptance. The requested
detailed counterexamples, complete dispositions and final coverage matrix were
not delivered; they must not be reconstructed as reviewer claims.

The observed 54 Read calls provide partial source evidence for Session/ownership,
selected SDK identity/registry/config/state/store/actions, Linux/macOS native
helpers, ledger/delegation, auth JWT/store, workspace, HTTP/writer/SSE, and three
extension test files. Search-only inspection elsewhere and partial ranges do not
establish whole-module or whole-test coverage.

| Returned concern | Supervisor assessment and remaining work |
| --- | --- |
| File-tool check/use races | Accepted explicit scope limit. Host path checks remain non-atomic against hostile concurrent workspace changes, including changes made by another native command. Native policy confines shell/server processes, not host file tools. Supervised use must trust concurrent writers; descriptor-anchored file operations would be a separate generic core enhancement. This is not a claim that the race is impossible, and same-user assumptions do not excuse a stronger promised boundary |
| macOS shared writable data | Source confirmed transient credential staging inside the shared grant. The follow-up removes that file: a bounded private prefix reaches the signed worker over stdin, with exact unbuffered consumption before exec. Four Rust framing/policy tests and large native environment/raw-input coverage pass on Linux and in actual hosted Mac execution at `375e607`. Shared-container and retained older-generation limits remain |
| Text-delivery policy | Independently reproduced: broker pressure detached a ready optional consumer, whose still-live retirement then refused the next turn. The real-worker regression failed before repair and passes after it. A later turn now continues without delivery to that retiring optional instance, with visible status; no concurrent replacement or same-turn restart is permitted. Required policy, initial readiness and unconfirmed-cleanup refusal remain unchanged |

After the interruption the operator explicitly approved running the baseline
security scan first, keeping architectural acceptance open and avoiding another
architecture-review round. This is an execution-order exception, not a waiver of
P25 readiness or a finding disposition. A private general cloud environment is
published; Security Cloud uses a separate setup flow. The operator explicitly
approved its automatic environment and the one-time GPT-5.6 Sol/high scan, with no
added secrets or continuous monitoring. The run completed against `8b4f706`; see
the [run record](../operator/architecture-review.md#baseline-scan) and dispositions
below. This does not retroactively complete the interrupted report.

## Baseline security scan at 8b4f706

The authorized GPT-5.6 Sol/high one-time repository scan completed on 2026-10-18
at 13:33:24 UTC. It reports five findings and complete static coverage of all 399
committed paths, without exclusions. It ran no application, tests, exploitation,
live account/network integration or native enforcement. Its scope is independent
security evidence, not blanket architectural acceptance or execution coverage.
The report, manifest, findings and coverage artifacts were read completely,
retained privately and SHA-256 checked against the service references. The
[operator record](../operator/architecture-review.md#baseline-scan) links the run.

| Item | Scan severity | Disposition and verification |
| --- | --- | --- |
| SC1 — native helper integrity | High | Repaired at `bfce156`. A synthetic workspace helper created an outside marker before repair. Native resolution now rejects helper/application overlap before Session locking and each shell/stdio launch, refuses extra hardlinks and unsafe modes, and does not build from the target tree. The Rust Linux boundary repeats its own executable-overlap refusal. Full local and hosted Linux/macOS/package/installed checks pass |
| SC2 — aggregate tool admission | Medium | Applicable. Admission now caps a response at 32 calls/2 MiB arguments and an operator turn at 128 calls/8 MiB. All admitted proposals count before execution, including malformed arguments, denials and preflights. Oversized responses start no calls. Real Session fan-out and cross-response malformed-attempt regressions pass; restoration retains the current-turn count |
| SC3 — JWT cryptographic complexity | Low | Applicable hardening. Token/segment/key-count/component bounds precede integer conversion and signature verification. Supported RSA moduli are 2048–8192 bits and positive odd exponents fit in 32 bits. Signed normal-flow fixtures pass; pathological components are traced to prove they never reach the verifier. No compromised endpoint or runtime denial was exercised |
| SC4 — mutable CI action selectors | Low | Applicable hardening. Existing actions are pinned to official full commit SHAs; the annotated setup-beam tag is dereferenced. An Elixir policy check rejects mutable external selectors and runs in CI. Runner images/compiler channels remain rolling; no new action, runtime package or external tool was introduced |
| SC5 — same-user journal rewriting | Low | Accepted documented trust limit, not a demonstrated approval bypass. The report requires same-UID write access to a stopped private journal; it establishes no lower-trust import or unapproved effect. Owner-only storage and locking do not authenticate history against its owner. Adding more editable chain records cannot stop an owner from rewriting the whole chain. Preserve schema/source/identity checks and unknown interruption behavior, but do not claim cryptographic journal authenticity or rewrite the legacy protocol as a P24 repair. Reassess if a lower-trust ingestion path or stronger downstream impact is established |

SC1–SC4 passed the local handoff and exact-source
[hosted Linux/macOS checks](https://github.com/lexlapax/ipse/actions/runs/39133201684)
at `bfce156`, including package/native and both installed proofs. The scan's source
remains `8b4f706`. The table above separately dispositions the interrupted pass's
concerns; a static no-issue surface was not treated as their reproduction or
automatic dismissal. The pipe/pressure follow-up also exposed and repaired a
large-launch-frame readiness gap: `open_stdio` now waits for a bounded nonblocking
flush before returning, while handling owned cancellation. Its focused stdio set
passes all 21 enabled cases. The complete follow-up matrix passed at `375e607`,
including real Mac environment/stdin handling, signed enforcement and installed
proofs. [Testing](testing.md#current-evidence-and-next-checks) owns exact receipts.
No additional scan/review or continuous monitoring has been launched.

## P24 scoped readiness decision

On 2026-10-18 the supervisor accepts source
`375e607d0d3fbedf9ea0454dc74bb69fd73f20f1` for the planned supervised P25 trial.
This decision combines the independent architecture critiques, Security Cloud's
reported whole-tree static baseline at `8b4f706`, the checked repair chain and
exact-source local/hosted execution. The independent reports keep their actual
source identities, partial coverage and withheld verdicts; this is not a new
independent post-fix acceptance, a second scan or a security certification.

SC1–SC4 are repaired and verified. The shared-data/pressure concerns have separate
source checks and meaningful regressions; the launch-flush issue was found and
fixed during that work. No applicable Critical/High finding in this review set
remains unresolved. The service's complete-coverage claim supplies independent
static coverage of previously omitted SDK/OS surfaces, but its receipts do not
prove every older test body was read, nor do static reads establish enforcement.
Actual source/native/package/installed checks support those narrower behaviors.

Acceptance assumes an operator-controlled, cooperative workspace and supervised
effects. Host file checks remain vulnerable to hostile concurrent path changes;
same-user state rewriting and trusted user-permission code are not isolated.
Mac shared-container/detached descendants, unknown remote effects, unconfirmed
cleanup, journal growth/startup, fixed reservations/tree overdraw, torn-ledger
continuation and retained raw evidence remain explicit limits. The deliberate
service-crash proof remains unconfirmed with `safe_to_continue: false`. Earlier
intermittent Mac failures keep their unconfirmed root causes.

P25 must freeze a separate installed runner/candidate and common inputs/limits,
preserve approvals and original evidence, and revalidate changes before promotion.
Its final delta/security review is a separate gate. No production knowledge
engine, new dependency, autonomous deployment or recurring monitoring is approved
by this readiness decision. The operator's existing source-analysis/edit authority
and trial instruction govern execution; this record does not invent broader
data-transfer or billing permission.

## Execution order and completion

The scoped F1–F7/S1–S3 and A1–A5 repairs passed their own source/native/package/
installed and hosted gates through `b5297be`. The
[testing record](testing.md#current-evidence-and-next-checks) owns exact results,
revisions and remaining verification limits. Future repairs still need a
regression or measured counterexample, coherent operator/developer guidance and
their own checks before commit/push; an earlier green baseline does not cover them.

The reports retain their provenance and actual coverage. The used consolidated
brief is archived, the baseline is complete/triaged, and the checked repair chain
passed its local and hosted gates. The scoped supervisor decision above permits
P25 preparation/execution under the recorded controls; it does not rewrite old
independent verdicts. The [current review page](../operator/architecture-review.md)
links the scan and current source. New changes still require affected review and
verification, and P25's final acceptance remains separate.
