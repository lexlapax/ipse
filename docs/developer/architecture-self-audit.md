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

The passing `a5912ab` matrix remains evidence for that source and its exercised
scope. The first follow-through passed its own Linux/macOS matrix at `99bbbdf`.
The additional filesystem-completion repair passed a new frozen local baseline,
package and both installed-artifact proofs. Its first hosted Linux job passed;
macOS stopped at an MCP readiness precondition. The fixture-stage correction has
a controlled regression and a passing focused suite. The repeated Mac matrix then
failed a separate direct-Client precondition; that case now verifies its dispatch
and effect before triggering loss, with phase diagnostics. The next full matrix
will verify this fixture-only follow-up; the earlier causes remain unconfirmed.
[Testing](testing.md#current-evidence-and-next-checks) owns exact revisions and
receipts. Earlier passes do not certify later code. The used review brief is archived; no new external assignment
or scan was launched. Baseline security and P25 remain gated on applicable repairs
and adequate independent coverage.

Residuals are explicit: full journal startup/memory and per-question prefix
projection cost, no journal size cap or same-size rewrite authentication at every
append, linear bounded-ledger prefix hashing, fixed token reservations and unknown
liability, whole-tree overdraw and unquarantined paid-response loss, torn-ledger
refusal with fresh-session continuation rather than repair, exact artifact/runtime
resume pins and no state migration/erasure contract, trusted extension/user-shell
permissions, sequential cleanup deadlines, and remote MCP effects/session
persistence. macOS detached descendants remain best effort. Deliberate
service-crash cleanup remains unconfirmed and unsafe to continue; tests/proofs
must retain that result. The older discovery flake, original normal-exit MCP
failure and diagnostic/question close failure retain unconfirmed root causes;
controlled repairs and later green runs do not retrospectively prove them.
