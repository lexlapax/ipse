# Restore the accepted State deadline contract — 2026-10-29

This concrete design has a [technical review](state-deadline-restoration-review.md)
and the required amendments below are accepted for implementation. It does not
remove a runtime gate. The [requirements audit](expiry-requirements-audit.md) recovered
the original [accepted design](../2026-10-19-p26-remediation/expiry-write-design.md).
The [plan](../../plan.md) still records the current refusal. The full P30/P31
goal requires usable positive journeys as well as safety; refusing all timed
writes is not completion.

## Preserve the original decision point

The original generic `write_before_ms` contract checks CAS first, then expiry
under the namespace lock, and checks expiry again after synced temporary output
immediately before publication. That final locked publication decision is the
linearization point. The original design explicitly disclaims physical rename
completion within the same wall-clock millisecond. A trace stopped after that
decision and resumed after expiry demonstrates this limitation, rather than
contradicting that contract.

The final decision is not the initial reservation, approval or start of staging.
A staging delay that crosses expiry must refuse the mutation. An accepted
decision binds the already fixed request, observed namespace/CAS state, complete
replacement bytes and deadline; no caller can change the body afterward or reuse
it for another mutation. A later acknowledgment describes that decision's actual
outcome, not that the old note is still eligible at response time. Subsequent
note use retains its own expiry and current-source checks.

The current State gate arose from a stronger physical-completion interpretation.
Correcting that interpretation alone is insufficient: current State performs
its final rename through the Erlang file server while a different process owns
the namespace flock. The separately confirmed Session journal race shows why a
BEAM liveness precheck is not an ownership fence. The proposed restoration must
also keep State mutation in the actual native lock owner.

## Own the namespace and opaque mutation together

Evaluate the existing retained native transaction and file-owner protocols for
reuse before introducing another parser or process. The selected shape must
provide these behaviors; the exact private command names are implementation
details, not a new SDK or capability:

1. Acquire the persistent namespace lock from the outset. Retain its exact
   descriptor and identity; never release/reacquire to upgrade it. Restrict the
   target to the namespace's fixed `state.json`, with safe private directory,
   owner, no-symlink, regular-file and identity checks. The lock file stays in
   place. An older helper that lacks the protocol must refuse, without falling
   back to an unfenced timed mutation.
2. Read bounded current bytes while that native owner retains the lock. Elixir
   validates the existing JSON layout, CAS/revision, optional expected generation,
   quotas and exact request/operation binding. Rust owns only the OS operations
   and bounded opaque transport; it does not interpret notes or policy JSON.
   Bind that exact initial target identity or verified absence to a one-use
   read/finish sequence. Known read, conflict and failure results also require
   confirmed native release; lost ownership cannot return a trusted result.
3. Transfer one complete immutable replacement of at most the existing 1 MiB
   State bound. Keep the existing 256-record and safe revision limits in Elixir.
   Stage, set private permissions and sync in the same native process that holds
   the namespace flock. Preserve CAS/revision/generation conflict, then initial
   elapsed-deadline, then quota precedence. Deadline zero remains valid and must
   not be confused with an absent deadline. An elapsed native response must carry
   its actual bounded `checked_at_ms`, rather than just an error number.
4. Immediately before the irreversible replacement, that native process verifies
   its actual retained lock/target identities and samples its own wall clock.
   At or after the supplied deadline, refuse before replacing active state and
   return the observed check time. Before the deadline, admit only that fixed
   replacement, perform atomic rename and sync the directory while retaining
   the lock. No post-check extension callback or changed body is allowed.
5. A successful response must bind the admitted private command and actual
   completion. A known deadline non-effect retains the original closed
   `write_deadline_elapsed` value: checked time, unchanged generation and record
   summary without its value. Preserve the existing successful/conflict shapes.
   Native loss, partial response or uncertain cleanup must not manufacture a
   known non-effect or successful write; return the host's existing unknown path.
6. Close with an actual native acknowledgment rather than treating process exit
   as confirmation. Owner loss during an in-flight native write may leave an
   effect unknown, but the namespace flock must remain held until that native
   mutation stops. A contender must not acquire while an earlier detached
   file-server operation can still replace its state.

Read-only and unconditioned compatibility must be assessed explicitly. All
ordinary State put/delete replacements must use the same native owner; retaining
a second file-server mutation route leaves the same ownership race. Do not
silently raise limits, weaken file checks or
claim a new platform without running its relevant controls. Partial staging
cleanup and operation-ID inspection must remain bounded and truthful. Keep
cleanup restricted to provably owned staging; inspection cannot silently delete
unknown operator files. Old running unfenced writers must be stopped before the
new backend is treated as a qualified owner; do not claim mixed-version fencing.
Reuse of transaction transport must not silently impose Collection's separate
filesystem/quota profile on the existing generic State contract.

## Keep authorization and recovery unchanged

This design grants no authority. The outer and inner host checks, full proposed
approval arguments, durable intent before effects and separate managed-source
gates remain. Removing an indiscriminate `write_before_ms` refusal must not enable
tainted State/service use that still lacks its own current-use boundary.

Retain validation of the historical `state_deadline_fence_unavailable` receipt
for saved reconstruction. Current supported execution should instead produce
the original success, CAS conflict or elapsed-deadline receipt at its actual
decision point. Restore does not compare historical receipts with today's clock,
and interrupted effects never replay automatically. A stored operation ID can
help inspect whether an unknown effect happened; it is not permission to retry.

Memory still derives the deadline from the existing target for remember/active
import. Fresh import of an expired backup retains its historical expiry and
separate migration policy. The model cannot omit or extend that domain-derived
condition. Existing note/category/suppression rules and new-knowledge consent
are not changed by this generic storage repair.

## Evidence required before restoring execution

- Closed request bounds and historical receipt compatibility, exact CAS conflict
  precedence, elapsed refusal without target change, and live timed success.
- Actual Memory remember and active-import approval crossing the existing note's
  expiry, plus before-expiry live controls and fresh expired-backup behavior.
- Staging held before the final clock decision until expiry: known elapsed
  non-effect, unchanged active file and bounded cleanup.
- Controlled stop after the valid final decision: a later physical rename is an
  allowed in-flight completion under the documented contract, not evidence of a
  physical deadline guarantee. Never relabel a lost response as confirmed.
- Real native-helper loss with an independent contender, and owner death during
  native IO: no later file-server write under the contender, unknown interrupted
  result and no replay.
- Malformed/partial frames, one-use/body/target substitution, symlink/identity
  changes, old-helper refusal, quotas and unconditioned compatibility.

Use focused tests during implementation; run the full runtime/package baseline
only after the related implementation is coherent. Before declaring the section
complete, reconcile operator/developer chapters with the actual supported
decision contract and preserve all earlier gated and partial evidence.

This State design does not itself restore Collection, document-stage, retention,
Review or managed display paths. Each needs its own final-decision and ownership
review against its original contract. No physical no-late-IO promise is added,
and no current gate is removed by this document.
