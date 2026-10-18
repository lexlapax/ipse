# Supervisor adversarial architecture audit

This is the implementation author's internal audit, requested after the fresh
external review of source `091b2bd` with evidence at `20b377c`. It is not an
independent review, security scan or architectural acceptance. The private raw
report remains outside Git. This record contains sanitized counterexamples,
actual inspection scope, regressions and remaining work.

## Gate before another external handoff

The used external prompt is withdrawn. Before preparing another, reproduce and
repair applicable findings, inspect the remaining implementations and test bodies,
attack their interactions, and complete the source/native/demo/package/platform
checks on the resulting candidate. A passing test file does not establish its
interactions with optional capture, pending questions, cancellation or recovery.
Do not substitute test names or earlier green runs for reading the boundaries.

## Findings and counterexamples

| ID | Counterexample and disposition | Verification |
| --- | --- | --- |
| N-A1 | Killing an owned model/tool task with lifecycle enabled emits an invalid `worker_failed` epoch closure. Use the existing `cleanup_failure` closure with unconfirmed cleanup; do not broaden the durable enum | Both model/tool regressions reproduced the old MatchError. The repair deliberately stops normally, closes the epoch with unconfirmed cleanup and resumes inertly |
| N-A2 | Diagnostic lease intent/ready/closed records can occur during an extension question and poison its action reducer. Validate the complete diagnostic receipt stream, then allow its independent facts without changing question state | Real sink/question recovery reproduced `invalid_extension_action`. Repeated resume/answer, saved diagnosis/handoff, before-request/after-answer jobs, explicit sink stop and corrupt-receipt refusal pass |
| IA1 | A native extension-tool question with prompt subscriptions records `lifecycle_question_sources` while the action reducer forbids it. This additional interaction was found in the supervisor audit | Real independent notifier + SDK question fixture reproduced refusal. The repair validates subscription history before permitting its source checkpoint; kill/resume/answer and corrupt-checkpoint refusal pass |
| IA2 | Main provider HTTP responses had no default byte ceiling, permitting unbounded parser/adapter accumulation until the time deadline | A synthetic loopback response of 8,388,609 bytes was accepted before repair. The shared HTTP adapter now caps response consumption at 8 MiB and retains smaller caller limits; focused provider checks pass |
| IA3 | Nested workflow tasks did not inherit the cleanup scope, so their native helpers were absent from confirmation | Real approved workflow + SIGSTOP of its exact shell supervisor reproduced `close_confirmed: :ok`. Linked nested tool/model/history tasks now explicitly inherit the outer scope; helper/cancellation, model-job and child-read fixtures pass |
| IA4 | Abrupt MCP stdio-supervisor death discarded its exit status and could later yield confirmed Session cleanup | Killing the exact isolated MCP helper reproduced `close_confirmed: :ok`. MCP transports now join the task scope and preserve actual closure results. Forced helper loss with lifecycle on stops normally with a valid unconfirmed epoch; stdio/HTTP and owner-loss fixtures pass |
| IA5 | An owner dying between task creation and scope attachment leaves the new task waiting forever at the dispatch barrier | Extracted the existing unchanged barrier and reproduced its failure to terminate on pre-attachment owner loss. The barrier now monitors owner and scope before readiness, then hands lifetime control to the attached scope. The fixture covers either process dying without dispatch; this is a controlled handshake probe, not a scheduler-timed Session reproduction |
| N-A4 | Sending deferred CLI display back to the mailbox puts it after newer output already queued behind the approval decision | Deterministic suspended-client fixture reproduced reversed display order. Draining the bounded saved queue directly before newer mailbox events passes, retaining approval and overflow checks |
| N-A6 | Quoted Unicode skill metadata mixes byte length and grapheme slicing, retaining a closing quote | Real discovery/load reproduced the error. Removing matching ASCII delimiter bytes passes single/double-quoted multibyte-name and description fixtures |
| N-A3 | Stream transport completion can precede refusal of assistant admission because another required consumer fails | Reverse-peer Session fixture passes: healthy optional v1 delivery completes, required v2 timeout refuses admission with retained failed accounting. Developer/operator contracts explicitly distinguish transport from Session success and durable `answer.committed`; no corrective transport or new media protocol is introduced |
| N-A5 | Fresh login replaces protected local credentials; remote revocation of the previous grant is speculative and server-dependent | Public profiles/sessions documentation specifies sign-out revocation, not the older-grant effect of replacement. Document that uncertainty; no speculative automatic revocation or live-account claim |
| PA-13 wording | Historical questions skip repeated durable validators but still reconstruct and hash each prefix | Register corrected: no cached projection reuse or material latency improvement; the measured startup limit remains open |

## Inspection and interaction coverage

The reported blockers affect availability and honest recovery. IA1 is another
availability failure; IA2 bounds provider-driven memory growth; IA3/IA4 affect
the correctness of cleanup confirmation; IA5 affects ownership before dispatch.
These are material correctness gaps, without a demonstrated privilege escalation
or credential disclosure in these reproductions. The display/Unicode issues are
lower-impact correctness defects. Stream completion and remote revocation are
explicit contracts/limits rather than claimed security fixes.

Actual regression bodies live in
[lifecycle runtime](../../test/lifecycle_runtime_test.exs),
[extension invocation](../../test/extensions_invocation_test.exs),
[event jobs](../../test/extensions_event_job_test.exs),
[provider HTTP](../../test/provider/http_test.exs),
[MCP Sessions](../../test/mcp/session_test.exs),
[task resources](../../test/task_resources_test.exs),
[CLI](../../test/cli_test.exs), [skills](../../test/ipse/skills_test.exs) and
[text Sessions](../../test/text_stream_session_test.exs).
All use synthetic inputs and temporary workspaces. The stopped/killed helper
probes target their own known fixture processes. No real model/auth service,
operator journal or credential was used.

The internal pass reviews eight boundaries and their interactions, not every
repository line or every test body. Rows below name actual implementation reads
and selected test-body inspection; executing the full suite is separate evidence.
The final candidate checks still gate the next handoff.

| Area | Current inspection/probes | Status |
| --- | --- | --- |
| Lifecycle and optional capture | Runtime/source/tool/child/event/metadata/answer/ephemeral modules; resource and channel lifetime; Session start/close/DOWN/observer paths. Lifecycle, metadata/answer/tool/child, developer-trace and diagnostics test bodies; actual sink/question recovery | Reviewed boundary; N-A1/N-A2 and cross-capture regressions, final checks pending |
| Extension authority and continuation | Actions, invocation, operation, host, service bindings/calls, tool actions and helper-model admission; projection and subscription/question restoration. Invocation bodies covering approval, corruption, helper IO/accounting, questions and workflow cancellation; services tests | Reviewed boundary; IA1/IA3, independent notifier + native question, strict source corruption and no permission inheritance |
| Delivery and history | Text resources/consumer and stream control paths, feeds/channel, event jobs, history, usage-read and child-read validation. Actual history/usage, selected subscription/feed and stream Session test bodies | Reviewed boundary; explicit transport/admission semantics, pressure, fixed snapshots, private-view grants and inert recovery |
| Auth, provider and MCP | Login/refresh/logout locking, JWT/storage, shared HTTP egress, provider endpoint selection, Ollama/SSE, MCP client/catalog/schema/stdio/HTTP. Actual adapter/error/egress and MCP Session/cancellation test bodies; official revocation contract | Reviewed boundary; IA2/IA4, no account access or billing changes |
| Context and recovery | Skill parser/catalog/digest selection, workspace snapshot/nested/resource validation, historical question prefix projection, lower-role context, compaction/checkpoint and handoff paths. Selected skill/workspace/question/compaction/handoff and diagnostics test bodies | Reviewed boundary; N-A6, no result reuse across assistant groups, preserved unknown effects; startup costs remain open |
| Trust, state and SDK | Identity/config/registry, manifest/import store, scoped CAS/tombstones, contributions, child-accounting physical sources and conformance. Complete state/store test bodies and selected binding/corruption/conformance cases | Reviewed boundary; no executable discovery, no route/grant widening, no state migration/deletion promise |
| OS, delegation and accounting | Native shell/stdio/group owner and Linux policy; Mac native policy/cache/signing (static), task scopes, delegation worker/group, journal writer and budget/ledger/store/normalizer. Actual task-resource/writer/native-policy tests, selected delegation/parallel/budget cases | Reviewed boundary; IA3–IA5, missing helper exit never confirms cleanup; Mac enforcement requires hosted evidence |
| CLI and diagnostics | Complete client event loop and bounded display queue; EOF/cancel/done/next-approval ordering; content-free diagnosis and bounded trace ownership. Deterministic display-order, approval-interleaving, trace and saved-diagnosis test bodies | Reviewed boundary; N-A4, controls retain prompt authority, no deferral through the mailbox |

No further source defect is currently confirmed beyond the findings above. This
is a bounded internal conclusion, not proof of absence. In particular, the review
did not read every example/packaging script, the entire Session module, every
provider adapter or all older test bodies. Independent inspection must still
finish the latest external coverage checkpoint, including state/child/model-job,
provider/MCP/auth, workspace/compaction/handoff, native/delegation/accounting and
SDK tests not substantively read in earlier external passes. Preserve completed
coverage only where code remains byte-identical; inspect new deltas and their
interactions. More green tests do not close that independent gate.

## Completion and limits

No new external prompt is ready. Record subsequent findings and their falsifiable
tests here, reconcile operator/developer guidance, and keep the
[plan](../plan.md#p24-independent-architecture-validation-and-baseline-security),
[dispositions](architecture-review-dispositions.md) and
[verification](testing.md#current-evidence-and-next-checks) consistent. Internal
completion cannot close the remaining independent review or baseline security gate.
