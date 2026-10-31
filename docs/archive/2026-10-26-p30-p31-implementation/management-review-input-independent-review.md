# Independent review of private management Review input

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
the [input candidate](management-review-input.md), manifest SHA-256
`6c4fdd20275c02399413d340c89bddaa8ee5e54a6c146ed5289f26688d21cee7`,
against the [original Review contract](native-review-component.md),
[management purpose](management-display-scope.md),
[display/deadline review](management-full-facts-display-independent-review.md)
and [forget-only effect direction](reviewed-forget-effect-restoration-independent-review.md).
No runtime/native edits, model/network calls, gate changes or test reruns were
made by this review.

## Disposition and evidence

Accepted within its private, no-mutation scope. No new blocking defect was
found. The candidate observes genuine native input for its displayed challenge,
then freshly revalidates a signed target and consumes one actual same-owner
permit. It does not implement journaled forget, public management admission or
an effect-completion receipt.

The [verification script](management-review-input-review/review-manifest.exs)
and [result](management-review-input-review/review-manifest.log) check all
33 entries, 39 frozen sources, the complete 698-physical-file runtime inventory,
five retained feature BEAMs and exact final helper
`0fa53f914f711f1f8de3682335e510e15a28acd2db07870d1a869209d6276416`.
Only Management, ManagementTerminal, Review, Runner, Resources and the helper
differ from the accepted deadline-repair graph. Other owners and the selected
bundle retain their preceding bytes. The production helper contains no test
markers. Final handle instrumentation and the retained elapsed-deadline source
substitution match the frozen source exactly; instrumented BEAMs are separately
pinned.

The final-helper native queued-input and owner-loss controls and actual
signed-target handle/consume control are distinct from the preceding
`bc9bf274ba6fba5e7933e13fda4d645dcea240969a9764965eca654a0c32720f`
helper's positive, cancellation, epoch-race and substituted-expired-deadline
controls. I inspected the retained logs and fixture code without repeating
them. Earlier failures, missing assets, sandbox refusal and Boolean cleanup
defect remain historical diagnostics; their missing whole-source/fixture states
are not reconstructed by the final tar. The full-runner test build deliberately
excludes this non-test terminal-lease module and suppresses existing dead-code
diagnostics; its two affected operator tests are not whole-native qualification.

## Display, release and one-use handle

The same native guardian retains the matched tty, terminal-channel lock and
actual CLI/journal controls. Native C still follows protected reader reap,
guardian lease drop and all four exporter settlements. For input mode, the
owner controls remain live; Writer thaws and the Collection, Consent and
Identity callbacks unwind before U. The new input child inherits no transferred
target lease copies. At the actual input prompt, the preceding cohort's race
control acquires each original target/control lock and changes the epoch.

The volatile process-local handle binds reference, exact Port/operation, full
facts, rendered-display hash, random challenge, resource ticket and original
clocks. It is not serialized authority. Foreign-process use has no matching
process-local slot. Actual-owner completion deletes the slot; mismatched facts
close it, and reuse refuses. A different command cannot create a permit. The
final actual control tests foreign/different-command calls and subsequent
same-owner replay around one genuine successful consumption.

U admits only the fixed non-sensitive input prompt. The native reader flushes
queued input, uses the literal `approval> ` redraw prefix, returns bounded text,
and is reaped before the guardian restores and flushes terminal state and emits
operation-bound i/z. No protected facts are rendered again by Review or input
editing. Native loss or malformed/partial/out-of-order/extra transcript refuses
observation; BEAM checks the original owner and clocks while parsing at most
298 buffered bytes. Clean native/control exits precede returning the input
observation. Already admitted writes remain subject to unknown rather than
instantaneous cancellation.

## Exact timing interpretation

Original Review creates its 30-second monotonic permit after `review_input`
returns to BEAM, with subsequent activity/liveness checks before admission.
It does not carry an independently sampled native keystroke timestamp. This
candidate starts that clock when BEAM parses the complete native i/z transcript,
before remaining native/control cleanup, and passes that original deadline to
Review. It is conservative relative to the original host-return boundary.
Cleanup and later revalidation/consumption do not refresh it; an expired
deadline cannot enter or succeed through the existing live-permit wrapper.

An arbitrary scheduling delay before BEAM receives the transcript is not a
30-second keystroke-age guarantee. It remains bounded by the original
120-second wall/monotonic operation clocks, captured before setup and
conservatively mapped into the native guardian's absolute clock. Setup retains
its narrower five-second budget; input/cleanup use the original overall budget,
not a new 120 seconds. BEAM checks those clocks on receipt and after cleanup,
and the outer final classifier checks them after composed cleanup. Late/queued
transcript receipt cannot restart an expired operation. These are discrete
checks, not clock-atomic cancellation.

The expired-permit fixture substitutes an already elapsed deadline after actual
input; it does not wait a real 30 seconds or measure native keystroke age.
Neither that fixture nor this source review qualifies a stronger timestamp
contract. The accepted original contract supplies no such stronger requirement.

## Revalidation and remaining work

After input, the candidate reacquires actual Identity → exact management
Consent → Collection ownership and rereads the signed target with the selected
recipe. It compares the entire prepared request and all original facts except
the second preparation's fresh operation ID and its derived action digest.
Original operation/facts remain the permit binding; no rebase is admitted.
The existing owner/scope/liveness, exact-input, first-use and final-success
checks remain in Review. The target's expired signed deadline and revoked
capture are historical management state, not renewed inference authority.

No Core mutation, durable intent/result/Consent effect settlement or public gate
is proved here. Actual changed-target/root and partial-frame schedules and
composed owner-loss/cancellation at all new phases remain future qualification;
earlier cohorts must stay attributed precisely. The minor stale top comment in
ManagementTerminal still describes a display-only module and should be updated
with the next source freeze. The independently accepted forget-effect direction
remains contingent on the real journaled, bounded and freshly revalidated caller
composition, followed by focused effect/unknown/no-replay controls.
