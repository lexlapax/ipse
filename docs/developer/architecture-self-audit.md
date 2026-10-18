# Supervisor adversarial architecture audit

This is the implementation author's internal review, not independent acceptance,
a security scan or a proof that defects are absent. The operator requested a full
adversarial architecture review and repairs before one consolidated final external
handoff, replacing further separate R/S/C/O rounds. The earlier private reports
remain outside Git. [Testing](testing.md#current-evidence-and-next-checks) owns
actual verification; [dispositions](architecture-review-dispositions.md) retains
the historical external findings and independent coverage checkpoint.

## Scope and method

The consolidated independent report at `a5912ab`/evidence `a21469e` has returned
without acceptance. It confirms the earlier repairs in its inspected scope, but
exposes cancellation and abnormal-death gaps missed by this implementation-side
pass. The current repairs and their limits are described below. Internal coverage
does not fill the reviewer's remaining material SDK/sandbox omissions.

The later baseline security scan found helper integrity and aggregate call
admission gaps missed by this internal pass, plus JWT/CI hardening. Its
[dispositions](architecture-review-dispositions.md#baseline-security-scan-at-8b4f706)
separate source claims, reproduced behavior, repairs and accepted limits. Internal
coverage is not a claim that those earlier designs were correct.

The review followed ownership, permission, source identity, durability, egress and
resource bounds across complete execution/recovery paths, rather than treating
passing modules as sufficient. It inspected the complete current Session state
machine, including initialization, task results, asynchronous peers, approvals,
questions, cancellation, cleanup, compaction and restore. All architectural areas
below were inspected internally; historical external omissions remain external
omissions. No subagents, live account, operator transcript or credential was used.

| Boundary | Implementation and actual test-body inspection |
| --- | --- |
| SDK authority and composition | Manifest/config/identity/bootstrap/catalog/registry/conformance, invocation/actions/operations, host/worker/lease, services/contributions/projection, state/store, tool/model calls and cost helpers. Actual state/store/model-call/model-jobs/child-usage/invocation bodies, conformance and service cases were read, including fixture helpers and corruption/approval/expiry/crash paths |
| Durable and ephemeral delivery | Feeds/channel, subscriptions/event jobs, history/usage/child reads, text resources/consumer/broker and lifecycle source/projectors. Actual feed/event-job/subscription/history/usage/text test bodies, mixed peers, source corruption, question resume, ack order, pressure and cancellation were read |
| Lifecycle and optional diagnostics | Runtime/tool/child/answer/metadata/event/ephemeral/source, diagnostic resources/channel/config/event, developer trace and saved diagnosis. Lifecycle/metadata/answer/runtime/tool/child, observability, developer-trace, diagnostics and conformance bodies were read; task death with feeds and lifecycle enabled is now a real regression |
| Context and recovery | Context/workspace/skills, compaction, handoff, questions, research and CLI. Workspace-session, handoff, tool-result compaction, skill-resource and CLI admission/approval/cancellation bodies were read, with selected compaction/skill/workspace tests. Challenges included lower-role references, drift, native continuation, compacted uncertainty and ambiguous historical calls |
| Auth and egress | Auth/store/JWT/HTTP, provider selection/OpenAI/Ollama/Anthropic/SSE/error/limits/request/HTTP, profiles/config, HTTP ownership/proxy and MCP client/config/schema/catalog/stdio/HTTP. Auth/pending-refresh, egress, HTTP/profile, MCP client/config/session/HTTP and config/profile-session cases were read; exact locked SDK link/exit and Finch/Mint streaming behavior were inspected |
| Persistence and accounting | Journal/writer, budget/policy/store/ledger, usage/normalizer and their Session integrations. Actual writer, usage/normalizer and budget bodies were read, including contention, corruption, child admission, partial usage, overdraw and torn-ledger continuation |
| OS and delegation | Runner/task resources, tools, delegation/worker/group, sandbox/Mac cache, and all Rust runner/stdio/process-group/environment/Linux/macOS helper implementations. Actual runner/stdio/task-resource/delegation/parallel/Linux/macOS/cache bodies were read. Static Mac reading is separate from hosted Mac execution |

This is full architectural-boundary coverage with selected existing tests and all
new regression bodies, not a claim to read every older test, script, demo or
vendored dependency. Exact public locked dependency reads support their relevant
client/link boundary only. Tests do not establish semantic truth of retrieved
content or resistance to every prompt injection. Rebuild identities, trusted-code
execution and retained host evidence are explicit contracts, not extension sandboxes.

## External R findings and repaired interactions

| Item | Counterexample and resulting behavior | Evidence scope |
| --- | --- | --- |
| R-1 / R-5 | A cleanup ticket survived known pre-spawn refusal despite no OS helper. Shared launch settles known refusal; post-spawn failures still require a receipt | Scoped negative MCP/extension/shell/lock launches and a real capture-on Session refusal/retry; forced helper loss still refuses confirmation |
| R-1 SDK link interaction | Failed SDK `start_link` killed the caller; trapping exits in that caller then masked scope death during blocked IO | Real Session and killed-scope fixtures rejected the broad trap. Only a nested scoped SDK task traps SDK exits, with a caller guardian; the outer worker retains its scope link |
| R-2 / IA2 | OTP httpc only streamed 200/206, invalidating the claimed universal ceiling | Existing locked Finch streams all statuses before accumulation. Ten length/chunked cases across 200/201/302/429/500, TLS trust/hostname/root and proxy/error/helper cases pass; eight nonstreamed cases failed before repair |
| R-3 and compaction | Idle required-peer/broker loss disappeared; a summary could also overwrite main delivery policy | Lost enrollments persist until explicit release. Consumer/broker death, forged policy update, release/replacement and actual compaction fixtures pin refusal before new main dispatch |
| R-4 | A broadened test accepted confirmed or unconfirmed cleanup and could not distinguish them | Separate clean native exit-zero/usable Session, immediate clean exit and forced helper-loss fixtures require distinct strict outcomes. No deadline or alternate-outcome relaxation |
| R-6 / HTTP ownership | Guardian lookup raced borrower startup; scope close could confirm with a live borrower/pool/socket | Guardian lease precedes borrower start. Cancellation awaits the exact guardian and its borrower/pool shutdown; controlled pre-borrow, stalled teardown and real held-socket scope probes cover both paths |
| OS input | NUL truncated a shell command and actually performed the scratch effect intended to be refused | Invalid UTF-8/NUL command, cwd and lock paths refuse before helper launch; the no-effect test failed before repair |

An isolated 64 MiB chunked-500 comparison measured the old adapter consuming the
whole body and the candidate stopping at its ceiling with lower sampled global
binary memory. This is not a process/OS peak-memory guarantee. No dependency was
added; [the inventory](dependencies.md) explains reuse of existing Finch/Mint.

## Additional findings from the full internal pass

| ID | Confirmed failure and repair | Regression |
| --- | --- | --- |
| FA-1 | Cancellation written after a stdio terminal frame could hit closed stdin and lose actual cleanup confirmation. MCP/extension terminal closure now passively awaits the native helper's real exit within the original deadline | A controlled helper closes stdin, sends terminal output and exits later: old closure lost confirmation. Positive exit zero, negative forced exit and missing-receipt cases pin receipt semantics. The precise historical Mac failure remains an inference |
| FA-2 | Invalid UTF-8 killed Session during journaling; explicit skill expansion could exceed the intended input bound | Valid UTF-8 and 1 MiB admission before and after expansion, with no journal/provider mutation on refusal. CLI handles synchronous refusal and bounds accepted queued tasks to 16/1 MiB; real headless, interactive and held-provider overflow fixtures cover usability/cancellation |
| FA-3 | TextConsumer automatically unsubscribed during callback failure, clearing a required enrollment and admitting inference | Unexpected worker termination now reaches the broker as real consumer loss. A failing required callback refuses the answer and the following request without new inference; explicit operator unsubscribe remains distinct |
| FA-4 | Auth bounded parsing only after the entire HTTP body; a 127-prefixed hostname bypassed proxy selection | Existing Finch bounded callbacks cap every auth status at 1 MiB before accumulation. Ten held-open status/length/chunked fixtures abort before EOF. Only parsed 127/8 IP addresses get implicit bypass; similarly prefixed names use the configured proxy |
| FA-5 | Handoff and saved diagnosis omitted unknown effects retained inside a validated summary checkpoint | A shared projection helper includes checkpoint actions and ordinary unknown tool messages, preserving occurrences. Real compaction/export/diagnosis reproduces the former zero count and verifies the retained call ID |
| FA-6 | Historical duplicate IDs could pair a research result preview with another invocation's arguments | Available results omit ambiguous intent/result identities, matching source-capture refusal. Duplicate-source regression asserts no misleading preview |
| FA-7 | Task death with lifecycle and feeds active used `cleanup_failure`, absent from the feed enum; cleanup itself raised and crashed Session | Append the typed reason without renumbering existing reason codes. A real held-model task kill requires normal Session stop, cleanup-failure epoch/feed receipts, validated sources and inert resume |
| FA-8 | Direct `--base-url` was not pinned in Session metadata; idle resume could silently change/drop the destination | Pin actual non-secret origin/target digest before first dispatch; validate before journal creation. Legacy recorded main/summary endpoint hashes must match. Idle legacy direct routes are unknowable, so unverifiable custom routing refuses. Idle/current and legacy request fixtures require unchanged journals on refusal and matching idle resume |
| Fixture integrity | Non-atomic PID files exposed empty readiness values and shared temporary names could collide | Independent worker fixtures publish completed PIDs via per-worker staging and rename. Liveness, effect and cleanup assertions remain intact |

These fixes address generic host invariants, not memory/research-specific Session
branches. The auth client uses the same established HTTP ownership adapter and
proxy policy. Prompt bounds do not turn trusted stdin read-ahead into a hard
process-memory quota.

## Earlier repairs and retained decisions

N-A1 uses the existing lifecycle `cleanup_failure` enum; N-A2 allows independently
validated diagnostic receipts beside pending extension questions. IA1 allows
validated adjacent prompt-source checkpoints; IA3 propagates nested cleanup scope;
IA5 binds owner/scope before dispatch. Their regression scope remains valid, but
the R and FA interactions demonstrate why those earlier passing tests were
insufficient as architectural evidence. The original IA2 universal httpc-cap claim
and claim that widening the MCP test did not weaken evidence were incorrect.

Optional text `end/complete` describes delivery, not successful Session admission;
a required peer can still cause the final answer to be refused. Durable
`answer.committed` is separate. Idle resume does not restore process-local required
clients. Saved skill/workspace snapshots and lower-role reference messages remain
instructions/data, never permission grants. Replaced login grants have unspecified
remote revocation semantics; logout revokes the newest known grant and reports
unconfirmed revocation. Blindly revoking a related old token family is not assumed
safe for the new grant.

## Consolidated assessment follow-through

The earlier required-delivery tests covered unexpected callback loss, but missed
host-directed cancellation. The lock guarantee also relied on `terminate/2`,
which untrappable Session death skips. Those omissions made the earlier broad
ownership claim too strong. The full private report, including frozen phase A,
was read; only sanitized dispositions and synthetic verification are committed.

| Item | Result and contract | Probe |
| --- | --- | --- |
| Consolidated B-1 / A2 | Confirmed host cancellation now releases only extension-owned enrollments after cleanup. The next task must initialize the same required selection. Unexpected loss alone stays sticky; embedding handles are separate | Five successive required-worker cancellations followed by successful required delivery; the old code refused subsequent inference. Existing unexpected-callback and unconfirmed-worker refusal checks remain |
| Consolidated A1 / A7 | A separate lock guardian retains the native Port across Session death. Writer, root/nested tasks, scopes, resource actors and delegated guards are tracked before dispatch; actual exits precede unlock | A suspended cleanup scope reproduced successful unsafe resume before repair. Root/nested and delegated-child stalls now retain the real lock. Guardian loss stops without appending; a subsequent real FIFO probe exposed that worker/writer exit alone does not fence dirty IO. FileEffect completion owners now survive caller death through synchronous IO completion; budget/state locks belong to those owners |
| Consolidated A3 | Pool-supervisor loss remains a conservative Session stop and requires explicit idle resume, without automatic retry | Actual Finch-supervisor kill pins normal Session stop, borrower/socket termination and unchanged idle resume. The fixture initially selected the registry child incorrectly; only the corrected supervisor probe establishes this behavior. A cooperative alternative left the caller blocked and was rejected |
| Internal filesystem completion | Ordinary and raw filesystem IO can outlive a killed BEAM caller. Admitted workspace writes, active appends/tail repair and budget/state critical sections now have separately tracked completion owners; cancellation never kills those owners | A gated real FIFO write rejects resume until drained. The previous tool implementation allowed resume. A separate real budget-lock probe retains the lock after caller death. These are controlled blocking probes, not power-loss certification |
| Internal HTTP child cleanup | The private HTTP lease waits for monitored supervised children before releasing its client slot | Suspending a named registry child and killing the top supervisor reproduced premature guardian exit. The repaired guardian retains its slot until that child exits |
| Cancellation composition | Normal scope close collects native-helper receipts before terminating nested task processes; abrupt owner death stops workers immediately and retains uncertainty | The existing workflow-shell cancellation regression rejected the initial nested-drain ordering. Its strict confirmed cleanup assertion passes after reordering; no alternate cleanup outcome or deadline relaxation |
| MCP readiness composition | Ready-file timing now starts at the tool-start event, after discovery/model selection. The three-second poll and configured ten-second protocol deadline are unchanged; cleanup remains strict | The first final Mac matrix failed before its kill precondition. A controlled 3.2-second model gate fails the old helper and passes the corrected helper; all 12 MCP session cases pass locally. The original occurrence's exact runtime phase remains unconfirmed |
| MCP loss precondition | Direct Client disconnect now occurs only after observed dispatch and verified file effect. Atomic PID-marker publication prevents empty-ready-file observations; failure diagnostics report fixture phases only | A second Mac matrix returned a pre-dispatch error from the old immediate-disconnect Client case; its actual effect phase is unconfirmed. The strict immediate-exit Session case remains, and the controlled direct Client case still requires unknown and exactly one effect. All 23 Client/Session cases pass locally; no runtime or protocol deadline change |
| Trace-owner setup | The owner-death fixture now initializes its owner and tracer synchronously, then performs the same untrappable kill and cleanup assertions | The next Mac run passed MCP but missed the old default 100 ms startup message; revocation was never exercised. All 49 affected tracing/lifecycle/diagnostics/MCP cases pass with constructor readiness; no capture or cleanup deadline change |
| Consolidated A6 | Request-free legacy endpoint provenance is unknowable. Compatibility still permits implicit-default legacy resume and cannot detect an old custom-to-default change | Guidance now states that exact gap. New-session pinning and recorded legacy request hashes remain strict; no migration or historical route reconstruction is claimed |

The guardian uses ordinary OTP monitors, Registry and the existing native lock;
it is a host ownership fix, not a domain feature or new workflow/dependency.
Tracking barriers cover tasks created during teardown. Normal cancellation keeps
OS receipts distinct from process death. A stalled tracked actor can retain the
lock past caller deadlines. Same-user interference, lock-helper/guardian failure,
unknown OS effects, remote refresh rotation and detached descendants are not
turned into stronger containment guarantees.

## Verification and remaining limits

The security-repair composition was checked across Session initialization,
ancillary locks and shell/stdio launches: native helper/application overlap must
be refused before any workspace mutation or lock helper can run, not only inside
the command supervisor. Repeated checks use the selected canonical helper and
reject hardlink aliases. The native Linux helper supplies a second overlap guard.
Default trusted execution retains its existing authority; same-user replacement
outside native writable roots remains outside that confinement boundary.

The macOS shared-data concern required a separate correction: selected server
credentials now use an exact bounded private stdin prefix, not a shared-root
file. An unbuffered descriptor preserves protocol bytes across exec; the existing
watchdog/owner lease covers blocked reads/writes. Pure framing/policy tests pass
on Linux, while actual Mac execution remains a hosted check. Large-prefix testing
also exposed immediate Port backpressure after launch; the host now waits for a
bounded nonblocking flush, handling the exact owned cancellation ticket. This
proves pipe readiness only, not server startup or native enforcement.

A real optional-worker pressure sequence reproduced next-turn rejection while
the old consumer was still closing. A ready, live optional instance now retires
without vetoing that turn; visible status explains missing delivery. Its slot is
not reused and no replacement starts until cleanup completes. Initial readiness,
required delivery and unconfirmed-OS-cleanup refusal keep their existing policy.
The regression covers the failed composition, continued inference and later
fresh enrollment. Host file-tool checks still accept the documented concurrent
writer limit; even a native peer can change workspace paths, so this is not
race-proof host IO or per-command shared-container isolation.

Tool-call admission charges complete response batches before any dispatch and
restores current-turn usage from effective conversation. Invalid-argument loops
exercise the actual Session until 128 calls are consumed; an over-limit batch
starts no effect. JWT tests include a valid traced signature as a positive
control, then confirm pathological components never reach cryptographic verify.
CI pins were resolved from official upstream references and the local policy
check rejects mutable selectors. Package review also caught the missing root
security-policy file; it is now bundled and checked. Exact receipts remain in
[testing](testing.md#current-evidence-and-next-checks). SC1–SC4 passed the hosted
Linux/macOS matrix at `bfce156`. Pipe/pressure/startup follow-ups subsequently
passed their own exact-source matrix at `375e607`, including actual Mac private
environment/raw-stdin handling, signed enforcement and both installed proofs.

The `a5912ab` and `99bbbdf` matrices remain evidence for their exact sources and
exercised scopes. The additional filesystem-completion repair passed a frozen
local baseline, package and both installed-artifact proofs at `74686f1`.
Three later Mac matrices failed cases whose startup or effect conditions had not
been established. Their negative evidence and unconfirmed actual causes remain
recorded. Phase-staged readiness has a controlled regression, and direct loss now
follows verified dispatch/effect with strict unknown and one-effect assertions.
Trace-owner setup is synchronous, with
unchanged capture/revocation deadlines. The complete source/test matrix passed
on Linux/macOS at `e8f7ad5`, including native Mac enforcement and both installed
proofs per host. That historical runtime source was unchanged from `74686f1`.

[Testing](testing.md#current-evidence-and-next-checks) owns exact revisions and
receipts. Earlier passes do not certify later code. The used review brief is
archived. The operator subsequently authorized a focused independent completion
on 2026-10-18. Its safeguard interrupted the report, so the operator approved
baseline scanning first while keeping architectural acceptance open. The
[current checkpoint](../operator/architecture-review.md) owns execution status;
the [register](architecture-review-dispositions.md#focused-completion-at-86d4d69)
separates partial reads and unverified concerns from actual findings. This does
not change this internal audit's provenance. The supervisor's
[scoped readiness decision](architecture-review-dispositions.md#p24-scoped-readiness-decision)
now assesses the completed baseline, verified repairs and accepted limits for
supervised P25. It is not a new independent verdict. P25 preparation may proceed;
scored runs need frozen inputs/limits, and final trial acceptance retains its
separate delta/security gate. The later P25 scan and current repairs are covered
below; they do not retroactively validate this earlier audit.

## P25 final-scan repair review

The `b5ddd02` scan exposed two boundaries missed by the earlier internal review:
stdin read-ahead could become a later approval, and journals had no finite durable
growth limit. Both findings remain open for final validation; the scan predates
the current changes and its coverage is explicitly partial.

The changed-path review follows actual CLI input through pending approvals and
each question in a bundle, then follows journal admission through writer failure,
Session termination, recovery reducers, diagnosis and handoff. It checks operator
configuration and child routing, source offsets and host identity pins. This is
implementation-side review, not independent architectural acceptance.

Real buffered-input regressions cover both stale approval and stale structured
answers. Fresh host-generated confirmation codes bind each display to its input;
old codes cannot authorize another proposal or answer the next question. Full
arguments, denial, EOF and programmatic approval/answer semantics remain intact.

Journal admission reserves a terminal receipt before accepting each normal
record. Incremental readers enforce finite bytes, events and encoded record
length before whole-history allocation. Recovery accepts the independently
validated terminal record beside pending questions, and never reopens a sealed
journal. Actual pending native/extension questions and a shell effect whose result
crosses the bound exercise inert diagnosis/handoff and unknown outcomes.

Internal review also caught a tight header read-ahead boundary and an inactive
append compatibility failure in the first full suite. The bounded-header check
now succeeds without loading a sparse oversized tail. Inactive append restores
the previous owner-only permission normalization after validation, while refusing
hardlinks before changing permissions or contents. The failed suite is retained;
focused corrections pass. The frozen full rerun passes 893 native-inclusive
tests with 15 platform exclusions. Package verification and all 41 legacy/nine
model-call assertions also pass using existing compiled artifacts. Six retained
live-trial journals restore unchanged under the new reader, and five multibyte/
escaped-JSON chunk-boundary probes preserve values and source offsets. These are
local checks; hosted platforms and refreshed affected security review remain open.
The first hosted matrix passes Linux but Mac observes the expected backpressure
closure after the test's six-second receive deadline. The real-timer fixture now
runs serially; neither the production five-second timer nor assertion deadline
changes. The actual scheduling cause remains unconfirmed, and the failed matrix
is retained rather than being treated as a successful Mac check.

Residuals are explicit: journal startup/decoded-memory and per-question prefix
projection cost within the new per-file bounds, no whole-directory storage quota
or same-size rewrite authentication at every append, linear bounded-ledger prefix
hashing, fixed token reservations and unknown
liability, whole-tree overdraw and unquarantined paid-response loss, torn-ledger
refusal with fresh-session continuation rather than repair, exact artifact/runtime
resume pins and no state migration/erasure contract, trusted extension/user-shell
permissions, sequential cleanup deadlines, and remote MCP effects/session
persistence. macOS detached descendants remain best effort. Deliberate
service-crash cleanup remains unconfirmed and unsafe to continue; tests/proofs
must retain that result. The older discovery flake, original normal-exit MCP
failure and diagnostic/question close failure retain unconfirmed root causes;
controlled repairs and later green runs do not retrospectively prove them.
