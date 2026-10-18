# Supervisor adversarial architecture audit

This is the implementation author's internal audit, not independent review,
architectural acceptance or a security scan. The private external reports remain
outside Git. This record names actual counterexamples, inspected boundaries,
repairs and limits; [testing](testing.md#current-evidence-and-next-checks) owns
verification receipts and [the disposition register](architecture-review-dispositions.md)
owns the cumulative external coverage checkpoint.

## Current gate

The package R review of `7810925` reopened cleanup and HTTP-bound claims from the
previous internal audit. That audit missed composition failures, and its passing
matrix did not establish those claims. The used brief is
[archived](../archive/2026-10-17-package-r-review-brief/index.md); its replacement
remains withheld until final hosted verification passes. This repair batch and
internal continuation pass their local source/package gates. R is unaccepted; S/C/O, baseline
security and P25 remain gated. Internal inspection cannot supply independent
coverage or certify the whole architecture.

## Package R repairs and additional counterexamples

| Item | Counterexample and resulting behavior | Actual probe |
| --- | --- | --- |
| R-1 / R-5 | Registering a cleanup ticket before a launch refusal left a nonexistent helper unconfirmed. Known pre-spawn errors now settle their tickets; post-spawn launch-frame failure awaits a real helper receipt | Scoped invalid-cwd MCP, nonexecutable shell/lock helper, extension artifact startup and real captured Session refusal/retry. The corrected pre-spawn fixtures failed before repair; actual forced helper loss still refuses confirmation |
| R-1 SDK composition | The pinned SDK's failed `start_link` can kill the owned caller despite the transport's settled ticket. Trapping exits in that caller fixed startup but masked scope death during blocked IO | Both a real launch-refusal Session and a killed-scope blocked-MCP fixture were exercised. Only a nested scoped SDK task traps those exits; its caller guardian kills it on caller loss, while the outer task retains its normal scope link. Both regressions now pass |
| R-2 / IA2 correction | OTP `httpc` streams only 200/206, leaving error and other success bodies outside the old consumption cap. Inference now uses the existing locked Finch streaming callbacks for every status | Ten length/chunked fixtures across 200/201/302/429/500 hold the oversized connection open and require refusal before EOF. The eight nonstreamed cases failed before repair. Positive TLS trust and negative hostname/untrusted-root fixtures, proxy fixtures, provider errors and helper-model tests pass |
| R-3 | Required delivery disappeared when its consumer died while idle. A dead broker could also be silently replaced. Lost required enrollments now block main inference until explicit idle release | Consumer death, broker death, forged policy update, explicit release and replacement fixtures pass. Policy messages are bound to the broker and a Session-issued private reference. Live enrollments remain process-local, not resumed subscriptions |
| R-3 compaction interaction | A summary request overwrote the main delivery flag after required broker loss, allowing the next main request through | A real compaction fixture reproduced main dispatch and successful completion before repair. Summary preparation now preserves the main requirement; the same fixture refuses main dispatch until explicit release |
| R-4 | The previous MCP recovery regression accepted both confirmed and unconfirmed closure and therefore could not pin cleanup | Controlled disconnect observes the actual native-helper exit zero and requires confirmed receipt, live idle Session and inert unknown-result recovery. Immediate server exit separately requires confirmed close; forced helper loss separately requires unconfirmed close. The precise older Mac unconfirmed path remains unexplained |
| R-6 | Looking up a guardian after killing its borrower can miss an unregistered request pool | MCP retains a guardian lease before spawning the borrower and waits for that exact guardian through cancellation and DELETE. Pre-borrow cancellation and deliberately stalled teardown are controlled probes; the narrow old scheduler race was not reproduced live |
| Internal HTTP ownership | Scope close could report success while a provider HTTP borrower, pool and socket were still alive | A real held-open socket reproduced this. HTTP guardians now register in the task scope and acknowledge only after stopping the borrower and pool. The same fixture requires all three to stop before successful scope close |
| Internal OS text admission | An embedded NUL truncated a shell command at the OS boundary; the intended invalid-input fixture actually performed a scratch-file effect | Commands/cwd and lock paths now reject invalid UTF-8 and NUL before helper launch. The no-effect fixture failed before repair and passes afterward |

The 64 MiB chunked-500 memory comparison used separate isolated VMs with the old
and candidate HTTP module. The old adapter consumed the full response; the
candidate stopped at its transport ceiling. Sampled global binary memory was
substantially lower. This measures that fixture, not process/OS peak memory or a
hard memory cap. No credential, real model service or operator journal was used.

## Continuation inspection

This pass read the complete current provider HTTP, HTTP profile ownership, MCP
client/stdio/HTTP transports, task-resource and text-stream paths and the pinned
MCP SDK's startup, link/exit and close behavior. It read Finch's streaming/pool
and Mint header-bound implementation rather than assuming `httpc` semantics
carried over. No dependency was added; the reuse rationale is in
[dependencies](dependencies.md).

The internal continuation also read the task-result branch and the remaining
Session model/tool/question/extension helpers named in the package checkpoint;
Runner launch, close, receive/output and frame paths; native stdio and process-group
ownership; EventJob question restoration; TextConsumer; and the observability
channel's close path. Actual fixture setup/helpers for invocation, event jobs and
text delivery were checked. Full lifecycle top-level/metadata/answer,
developer-trace, diagnostics and extension-conformance test bodies were read,
in addition to all new or changed regression bodies. Local execution is recorded
separately from reading those bodies.

Cross-boundary review specifically challenged failed startup versus dispatched
work, SDK links versus scope links, nested HTTP ownership, idle required loss
through compaction, and helper exit versus server exit. It exposed the additional
counterexamples above before this handoff. These implementation-side reads do
not close the external omissions. The next independent pass must carry forward
only unchanged reads and inspect this entire delta and its interactions.

## Earlier audit and retained corrections

The previous internal repairs were implemented at `c774557`; the test-only
candidate `7810925` passed its recorded local and hosted matrix. That evidence
remains valid for its actual fixtures, with the following qualifications.

| Item | Previous result and present limit |
| --- | --- |
| N-A1 | Lifecycle-on model/tool task death now uses the existing `cleanup_failure` closure, stops normally and resumes inertly. R-1 challenged when cleanup failure should be diagnosed, not that durable enum repair |
| N-A2 | Diagnostic intent/ready/closed facts no longer poison pending extension questions after full receipt validation. Repeated resume/answer, diagnosis/handoff and corrupt-record refusal were exercised |
| IA1 | Independently validated prompt-source checkpoints are permitted beside native extension-tool questions; subscription validation and checkpoint adjacency remain strict |
| IA2 | The original 200-response cap test proved only streamed success consumption. Its universal wording was incorrect; R-2 supplies the all-status repair and regressions |
| IA3 | Tool/model/history nested tasks inherit the cleanup scope. R-1 and the HTTP scope probe required inspecting the resources actually enrolled inside those tasks |
| IA4 | MCP transports retain real cleanup results after forced helper death. R-1 showed that enrollment without startup settlement wrongly classified no-process refusal |
| IA5 | The dispatch barrier monitors owner and scope before attachment. The probe tests the extracted handshake rather than claiming a timed Session reproduction |
| N-A3 | Optional transport `end/complete` can precede required-peer failure and refusal of answer admission. The contract distinguishes delivery from Session success and durable `answer.committed`; no corrective terminal frame is promised |
| N-A4 / N-A6 | CLI display drains its bounded deferred queue before newer mailbox events; quoted Unicode skill metadata removes ASCII delimiter bytes correctly |
| N-A5 / PA-13 | Remote revocation of replaced login grants remains unspecified. Historical questions skip repeated validators but still rebuild/hash prefixes; no cached-projection or material startup-latency claim is made |

The prior assertion that the `7810925` test-only correction did not weaken the
MCP test was too broad: accepting either cleanup result widened its evidence.
R-4 now splits strict cases rather than treating both outcomes as equivalent.
The older failure's cause is not established by subsequent green runs.

## Verification and limits

Repairs and counterexamples pass locally. Final build, both actual formatter
floors, strict compilation, native-inclusive suite, isolated demo, package and
both independently precompiled installed proofs pass on frozen runtime bytes.
All installed assertions were parsed with unchanged archive/host bytes and no
system development toolchain on the runtime path. Actual hosted Ubuntu/macOS logs
and enforcement results are the remaining repair handoff gate; see the verification
record for receipts. No replacement prompt is ready yet.

The review is bounded. It does not read every Session line, adapter, example or
older test body, prove absence of defects, or replace package S/C/O. Detached Mac
descendants, remote MCP persistence, sequential close deadlines, startup/journal
growth, linear ledger prefix hashing and deliberate service-crash unconfirmed
cleanup remain explicit limits. The earlier Mac discovery flake and the older
MCP normal-exit unconfirmed path retain separate unconfirmed causes.

After verification, prepare a package R continuation from its saved checkpoint
and this delta. Do not restart all architecture areas or turn internal inspection
into independent acceptance. Keep [the plan](../plan.md#p24-independent-architecture-validation-and-baseline-security),
[dispositions](architecture-review-dispositions.md) and operator brief consistent.
