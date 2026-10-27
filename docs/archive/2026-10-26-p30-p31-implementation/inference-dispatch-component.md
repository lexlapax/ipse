# Registered inference dispatch component

Dated **2026-10-26**. This is an author implementation and verification receipt.
The subsequent [independent adversarial audit](inference-dispatch-audit.md) passed
seven fresh local-HTTP/Session probes against this frozen checkpoint and found no
actionable defect within its stated scope. It preserves the exact source/runtime
hashes, first harness failures and limits. The earlier independent
[slot component review](service-slots-component.md) does not certify these new
paths. The [frozen baseline](baseline.md), [coordination contract](contracts.md#consent-commit-order-and-process-coordination)
and [plan](../../plan.md) remain authoritative. This checkpoint does not complete
P30/P31 or qualify a model, platform, operator journey or release.

## Follow one registered request

An operator's `inference_services` registry groups canonical origins under one
service ID. `Ipse.InferenceDispatch.selection/4` derives the actual endpoint,
provider, model and billing mode from the admitted main configuration or named
profile. It checks them against `SemanticRoutes`; a worker cannot select another
endpoint or service by supplying a label. Registered main, compaction, named text,
embedding, decision and named-child requests use the same protected service slot.
An unregistered route keeps its existing direct budget/provider path. Demo has no
service IO and skips service scheduling. Invalid or ambiguous selection refuses.

Named child profile construction now retains the operator service registry and
inherited mode ceilings. It also preserves operator semantic selections for
independent fresh admission, without copying a parent pin/admission, current
input or operator channel. Artifact child eligibility and ordinary child approval
still apply. This retention is not a saved-consent delegation grant.

The actual sequence is:

1. Session writes the existing content-free usage `request_admitted` event. This
   accounts for an attempted request; it is not evidence of provider IO.
2. The Session-owned task queues for the protected service lease. Waiting makes
   no shared usage-budget reservation. Bounded status notifications expose the
   wait. Original queue and dispatch deadlines are retained.
3. Once eligible with the service lease held, a deferred gate relays back to the
   exact active Session task. It has at most five seconds and cannot extend the
   original queue deadline. The native service owner rechecks foreground queue
   eligibility and the unknown marker after the gate before durable admission.
4. Session recomputes the active job, admission, phase, provider route, input,
   ordered tool catalog, source-window snapshot, mode and semantic-admission
   digests. A mismatch refuses. When a semantic pin is active, the task enters
   protected ProjectIdentity then Consent, checks the exact current policy epoch,
   hash and expiry, and appends the final intent from that short callback.
5. The `inference_dispatch_intent` event records these hashes, the exact request
   and attempt IDs, service reservation and a unique local intent ID. It means
   **dispatch intent**, never “HTTP started.” Session accepts this RPC only from
   its exact current inference task or that task's currently registered
   `Resources.file_effect` caller. No general descendant authority is added.
6. All project locks release. The service owner durably admits its reservation,
   then runs the existing shared budget admission and provider IO. No identity,
   Consent or Collection lock is held over queueing or inference.
7. Known terminal completion, or a proven never-entered budget execution, is
   durably recorded by the actual service lock owner. The native lease and scope
   release before the result returns to Session, before assistant publication and
   before any following tool or child execution.

The protected callback is the policy admission linearization point. Revocation
that wins before it refuses the queued call. Revocation after that admission
cannot undo an already admitted call. There is an interval between the journal
intent, service/budget admission and actual HTTP; the intent is not a transport
receipt. A later service refusal may leave a local intent with no HTTP at all.
Foreground reordering may cause another local validation/intent, but does not
replay provider IO.

Replay accepts only closed, versioned intents correlated with an unfinished,
matching usage admission. Duplicate intent IDs, wrong phases/attempts, malformed
hashes, unknown fields, and placement after request completion or a new
input/cancellation/turn/runtime boundary refuse. Neither Usage nor Saved treats
this historical event as present authority or dispatches from it.

## Prove completion without classifying error strings

`Provider.CompletionWitness` keeps an owner/ref-specific observation in the actual
provider caller's process dictionary. No reference/capability enters config,
provider payloads, SDK results or journal records. Completion requires all of:

- The exact selected HTTP target was entered once and its real bounded transport
  reached EOF successfully. Parser/bound/deadline halts are not EOF.
- The actual provider adapter validated its native terminal response, or the
  embedding/decision parser validated its typed complete result for this model
  and operation.
- The isolated HTTP guardian confirmed profile/child cleanup, then actually exited.

A success-shaped custom provider callback supplies none of this proof. Non-2xx,
malformed/incomplete bodies, transport failure, timeout, cancellation, native
owner loss or missing cleanup retain the durable unknown marker. A free local
socket or OS service lock never proves remote quiescence. The original bounded
provider error and observed usage survive; no automatic retry or fallback occurs.
Non-2xx remains conservatively unknown, even after a fully read error body.

The exact wrapper-owned budget execute callback separately records whether it
was entered. Only a callback that was **never entered** may return trusted
`{:unstarted, value}` under the current native lease. The actual native owner
then cancels only that reservation into the ledger's existing `not_started`
receipt, checks/releases and returns the local refusal. This does not call a local
budget error remote-terminal, and does not classify generic errors or strings.
The primitive still trusts its core caller's classification; it is not protection
against arbitrary hostile code in the same BEAM VM.

Conversely, a fully parsed embedding can finish HTTP before final budget
settlement detects an overrun. Its real completion proof settles the service,
while the budget error prevents publication and retains measured liability.
Usage observations flow live even when assistant/result publication is withheld.

## Preserve bounded publication and honest timing

Registered routes hold visible text privately until the service outcome is
settled and the lease actually releases. The buffer holds at most 8 MiB and
8,192 nonempty chunks. Uncertainty discards it; a bound failure returns an explicit
error instead of truncating a response. If the upstream completion proof is
present, an overflow can settle that completed service while still refusing
assistant publication. Otherwise it remains unknown. Actual extension inference
payloads likewise remain private until the slot returns successfully.

This changes registered-main streaming UX: visible text arrives after completion
and service release. A content-free `inference_service_timing` notification
separately reports elapsed upstream first-text time from the actual callback;
that is not visible TTFT. Provider/queue/end-to-end and visible latency must be
measured separately in qualification. No latency acceptance claim is made here.
Unregistered routes retain their existing streaming path.

Selected request timeouts must be at most 100,000 ms. The current ordinary
120,000 ms default therefore visibly refuses for a registered service until the
operator reviews that timeout. The implementation never silently clamps it.
Waits are at most 60 seconds, the gate at most five seconds within that wait, and
the native absolute service lifetime includes bounded callback/cleanup headroom
(up to 120 seconds). The protected filesystem profile remains the limited
Linux/kernel/filesystem profile documented in the slot receipt; unsupported
platforms fail closed with explicit negative evidence, not claimed positive tests.

## Author verification and exact scope

The private `21` snapshot compiled all **124** current host/bundled source files
with zero compile/runtime warnings. It copied source while coordinated with the
other authors, removed stale Ipse beams, and used private dependencies and the
unchanged protected helper. The final `25` source differs only by the stricter
Session dispatch-intent replay-boundary reducer, compiled separately with zero
warnings. The final immutable `26` runtime inherits that exact graph and adds the
last private-buffer ceiling test. It does not include subsequent in-progress
ManagedCollection SDK edits by another author.

`/tmp/ipse-inference-dispatch-26/focused.log`: **120 passed**, seed 214282,
34.8 seconds (3.1 seconds loading, 31.5 seconds tests). These are maintained
synthetic tests with actual local loopback HTTP and independent SDK workers,
not live provider/model qualification. They include:

- Slot/ledger ownership, cross-VM aliases, foreground ordering, deferred gate
  refusal/deadline, callback-only lease checks and revalidation after a foreground
  arrival during a background gate.
- Actual main → native read → next main, compaction, named child and SDK named
  text/embedding/decision dispatch through the registered service.
- Actual cross-project main HTTP holding the slot while SDK embedding waits,
  with no second TCP connection or queued budget reservation.
- Exact active-policy ProjectIdentity/Consent effect-caller admission, and
  revocation while the SDK call waits yielding zero HTTP, zero budget reservation,
  no dispatch intent and no successful inference effect source.
- Source-window change while queued, forged final-gate caller, queued cancellation,
  unknown refusal of the next request, and native service-owner death after
  upstream text with no visible text publication.
- Zero-budget refusal with a proven unentered execute callback and `not_started`
  receipt, followed by a fresh request consuming the fixture's only HTTP call.
- Completed embedding with final budget overrun, incomplete stream withholding,
  the 8,192-chunk bound, release-before-visible-text checks, private completion
  conjunction controls and cleanup.
- Strict replay tampering/duplicate/boundary rejection, all existing Session
  checks, provider checks, profile/ceiling checks, existing embedding/decision SDK
  regressions, and the real credential-free demo completing its tool sequence.

Unsupported-filesystem branches explicitly exercise refusal or print that the
corresponding positive journey did not run. The positive paths above ran on this
host. They do not certify macOS, CI's filesystem/kernel, installed release parity,
a complete source suite, a real shared model daemon or remote concurrency.
Actual Elixir 1.18.5 formatting checked all 25 owned source/test files with zero
differences; current-toolchain formatting also passes for those files.

## Preserve the first failures

The following earlier logs remain private synthetic evidence; later successes do
not erase them:

- `11`: a reserved module-attribute compile error was repaired. The first harness
  then lacked `Mix.start`, and its next strict-result matcher expected the wrong
  diagnostics shape; both harness defects were repaired. Restricted local sockets
  returned `:eperm` before HTTP fixtures, followed by an authorized loopback run.
- `13`: a second reserved module attribute refused compilation; renamed.
  `14`: a full-source harness accidentally loaded old struct beams; it now removes
  stale Ipse beams before a full compilation. These were not passing builds.
- `16/focused.log`: **33/54**. A real implementation mistake hashed the tuple from
  `Mode.capture` instead of its closed map; fixed. New fixture homes incorrectly
  overlapped the target workspace and correctly refused; fixtures separated them.
  A registry cleanup timing assertion was repaired by returning only live HTTP
  guardian PIDs after confirmed exit.
- `17/focused.log`: **51/54**. Usage correctly rejected an unrecognized attempt-ID
  record; the new closed typed intent was integrated into Usage and Saved. Two
  existing Session/demo cases exposed host-reference messages confusing the demo's
  real-user/tool-turn boundary; only valid `Reference.reference?` messages are now
  ignored for that boundary, with malformed/ordinary-user negative controls.
- `22/focused.log`: **116/119**, and `23/targeted.log`: **7/9**. Active-policy test
  exports correctly refused missing exact descriptor/mandatory constraints in
  their reviewed outer mapping. Fixtures were corrected; no production guard was
  bypassed. The compaction fixture's threshold initially failed to account for
  native duplicated message text; its bounded threshold was corrected.
- `24/targeted.log`: **9/9** after those fixture repairs;
  `25/focused.log`: **119/119**; `26/focused.log`: **120/120**.

## Source-bound audit handoff

The linked subsequent independent audit exercises the before-admit/current-check/
unstarted paths, relay, deadline/cancellation intervals, completion witness, actual
HTTP cleanup, live usage, buffered publication and Session replay. Its seven probes
have narrower coverage than the author's maintained suite. Use the frozen private
`26` source/runtime for reproduction; later shared integrations still need review.

The [complete source manifest](inference-dispatch-sources.sha256) binds all 124
host/bundled sources, all eight owned tests and the protected helper from that
exact frozen graph. Paths are repository-relative; no transcript, credential,
environment dump, operator auth file, local protected ledger or private input is
included. The runtime is `/tmp/ipse-inference-dispatch-26/dependencies/ipse/ebin`;
its protected helper is the sibling `priv/ipse-runner`, and its source/tests are
under `/tmp/ipse-inference-dispatch-26/src`. Private fixture homes and local HTTP
fixtures are created afresh by the tests. Auth/provider regression inputs are
synthetic fixtures and isolated homes; this is not a sign-in/account check.
The complete private graph also contains the concurrently authored Collection
normalizer checkpoint. Its manifest entry does not certify that component or
stage its source into this dispatch-only commit; the frozen private graph, not a
claim of an independently releasable mixed checkout, is the reproduction target.

| Bound item | SHA-256 |
| --- | --- |
| `lib/ipse/inference_slots.ex` | `f6fe3e5f5a73ab488543ba8deafefeade1c8679a0ae6a52c8411816123ec5c4a` |
| `lib/ipse/inference_dispatch.ex` | `7efc5f2366a2b372e0b4da54841405631a405fc45694fd405e38b1e534654ddf` |
| `lib/ipse/provider/completion_witness.ex` | `bf76369c3b474235fb0e0b0c53403647a3b3beea25b136d6104637befa31a6d5` |
| `lib/ipse/session/inference_dispatch.ex` | `9542af065c919db65dab479c54cce4be6a1294032b1b3f349b3bd09d0f687b1c` |
| `21/strict.log` | `d724c4d3790412d75f387ec0628f0d896d4275ef876ca5b7c97aaff67ff1061f` |
| `25/strict.log` (empty successful output) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `26/focused.log` | `821a3075b29738166f5f1a5fc01aca30732d039ccdcf50394492935dc61a4cef` |
| private/source native helper | `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29` |

`21/strict.log`, `25/strict.log` and `26/focused.log` above are under
`/tmp/ipse-inference-dispatch-` followed by the indicated snapshot number. No
helper was rebuilt for this component. Existing Task/Resources, Transaction,
SemanticRoutes, Jason/Ipse.JSON, Finch and provider parsers are reused; no new
package, runtime, OS protocol or external service dependency was added.

ManagedReference live record/expiry/lineage revalidation and withdrawal are **not
wired by this component**. The current final gate checks current structural
pin/policy/mode/source-window facts only. The domain recipe/readview validator,
managed occurrence receipts, native selected-service setup/recovery UI, actual
provider/daemon tests, model/corpus qualification, latency/annual/platform evidence,
complete source/installed checks and final independent milestone audit remain
separate work. No text here promotes fixture or component evidence into those
acceptance claims.
