# Independent review of the inactive Session operation seal

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the frozen operation seal](session-operation-barrier.md), manifest SHA-256
`d96e5fdabb6cc67bd74d94fc2ef405941844f1a031bef43084a733fa090efaa2`,
against the prior [Session share review](session-share-candidate-independent-review.md)
and [guarded-terminal design review](guarded-terminal-integration-independent-review.md).
No implementation or runtime edits were made and no passing test cohort was
rerun.

## Disposition

Accepted as an inactive Session infrastructure section. No concrete blocker was
found within its declared scope. This adds the Session-side exclusion that was
missing from the earlier Writer/guard candidate; it does not provide genuine
Host authorization, native descriptor export, Session/Host EOF fences, terminal
writing or protected output activation. All existing protected gates remain
closed.

The admission pattern requires the current job reference and actual task caller,
then matches the active action intent, non-interrupted invocation parent,
selected extension identity and allowed Session phase. It captures the parent,
intent, task, job and phase in the pending operation. The fixture deliberately
injects a synthetic action and an empty identity into the real Session using
`:sys.replace_state`. Its configuration equality and `Registry.live?` check are
not a complete artifact admission proof: an empty identity has no expiry and
passes that predicate. This is accurate only as owner and state plumbing for
an inactive trusted-host candidate. Real selected-identity admission, fresh
validity at the eventual effect boundary and genuine Host/job controls remain
open, as the checkpoint states.

## Seal, replies and failure behavior

The Session queues the Writer barrier asynchronously and returns its new sealed
state before it can dispatch another mailbox message. The Writer may run
concurrently, but no later Session call can pass through an unsealed gap: the
seal handlers precede every ordinary call handler. Source and proof requests,
job/action commits, prompts, subscriptions and other mutation requests therefore
refuse before reaching their normal implementations. No alternate Session cast
or later call clause bypasses this ordering. The only continuation is the
pre-existing question continuation, which runs before the next mailbox call.
The same-VM debug interface and direct file mutation are outside this trusted
host boundary.

After the Writer has drained, Session checks its opaque token and snapshot's
session, job and newly generated operation epoch, then rechecks the captured
caller, parent, action intent and Session phase. It asks the existing guard to
arm asynchronously. That guard verifies the exact tracked Writer barrier,
retained owner and operation binding before producing the transport binding.
The earlier candidate's native operation ordinal and private owner epoch remain
unchanged. No protected bytes or descriptor are sent by this section.

Only the originating task with the exact job and opaque capability can start a
pre-export abort. Session asks the guard to cancel, asks Writer to thaw, and
clears its seal only after Writer's successful asynchronous guard-confirmed
thaw and a live caller check. A foreign abort is refused. Session cannot run
source/proof changes or call direct journal repair between the Writer checkpoint
and arming, because those ordinary handlers remain behind the seal. This does
not authorize an independent future Host path to call Writer or guard as a
second owner.

Unexpected messages, task termination, request failure and the real five-second
timer all lead to permanent quarantine. Both cancellation calls use the same
path and kill the active task without synchronously consulting Writer. They
reply unconfirmed even when Writer is suspended. Poisoned state never resumes
ordinary handling or converts a late successful reply into success. Cancelling
a BEAM task does not prove native IO stopped; this infrastructure makes no such
claim. It does not yet revoke an exported terminal operation because no export
caller exists here.

The timer is a mailbox event measured once for this pending seal; it remains
active through arm and pre-export cancellation. It is not a hard preemption
bound on earlier synchronous Session work, a human-wait deadline, or a completed
end-to-end setup/quarantine bound. Unknown or stale events conservatively poison
a current seal. No successful close or reset is inferred from them.

A sealed or quarantined close explicitly returns `cleanup_unconfirmed` and
stops Session. The observation-drain wrapper now tolerates a refused query so
this close path is reachable. Existing termination kills the actual task and
Writer and releases the guard through its cleanup path; it does not append a
successful release claim through the frozen Writer. If physical cleanup stalls,
the close wrapper still reports uncertainty. Queued journal IO and interrupted
action intent are not declared absent or automatically replayed.

## Evidence and limits

[Manifest verification](evidence/session-operation-review/review-manifest.exs)
and [its result](evidence/session-operation-review/review-manifest.log) verify all
13 manifest entries, the four archived source files, all 697 inventoried runtime
files and the unchanged helper
`a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995`.
Lock and Runner BEAMs exactly match the prior frozen Session share candidate.
The archived Writer differs from that candidate only in its Management native
ownership predicate check. The archived Journal predates the separately reviewed
[metadata alias repair](../2026-10-26-p30-p31-implementation/management-journal-owner-independent-review.md#additive-repair-disposition).
This cohort is not whole-source acceptance and must not replace that repair's
source or runtime qualification.

The final recorded five tests cover: sealing before a suspended Writer drains;
foreign abort refusal and matching pre-export abort/thaw; both cancellation
entry points with Writer suspended; unexpected-event quarantine; and actual
setup-timer expiry. The fixture creates its Task from Session itself, preserving
the real Task owner relationship. Its final run reports five passes with no
termination errors. The earlier close-drain match failure and assertion-passing
runs with Task ownership teardown errors remain retained and do not count as
clean teardown. The final compile receipts report success and include compiler
driver API deprecation warnings; they are not an empty-warning full build.

No additional runtime counterexample was warranted. Actual Host identity and
control tests, task-loss controls, direct adversarial state-binding tests,
authenticated export and all-copy close/thaw, actual Session/Host EOF, bounded
complete setup/quarantine, matched tty writes, forked-reader closure, the fixed
non-sensitive prompt, and final one-use effect admission remain open. This
review supplies no native production or terminal acceptance beyond the frozen
infrastructure controls.
