# Narrow source direction for restoring reviewed forget effects

Read-only requirements/source review, 2026-10-29. The [plan](../../plan.md) owns
acceptance. This derives the smallest forget-only direction from the
[original Review contract](native-review-component.md),
[original management journey](managed-forget.md),
[requirements audit](expiry-requirements-audit.md),
[restoration direction](reviewed-forget-restoration-direction.md) and
[management display purpose](management-display-scope.md). The five inspected
owner sources are retained in a [source snapshot](reviewed-forget-effect-source-review/source.tar)
with [hashes](reviewed-forget-effect-source-review/source.sha256).
This is not a runtime build or test cohort. No source/gate edits, runtime tests,
model calls or network operations were made.

## Supported contract

The original Review contract requires genuine exact native input, a volatile
same-owner permit, exact revalidation under effect locks, one live consumption
and withholding of successful completion after observed expiry/loss. The
30-second monotonic permit starts after genuine input. A consumed operation may
reach storage after that deadline and return unknown. It cannot roll back a
completed effect, replenish the permit or authorize another attempt.

The [late-forget evidence](strict-gate-lifetime-followup.md) demonstrates just
that schedule: live consumption, delayed native switch, a committed reducing
effect and an unknown outer Review result. It contradicts a stronger physical
completion promise, not the original live-consumption/unknown-completion rule.
The current blanket gate remains in force until an explicitly reviewed
restoration. It should not be described as a native capability limitation that
requires a new physical-deadline primitive for reducing forget.

The specific original admission point is successful `Review.consume/3` inside
`NormalizerV3.forget/3`, under the retained Identity, management Consent and
Collection owners, after exact semantic revalidation. Existing bounded metadata
planning/sealing and Core staging follow that call. Restoration must name this
as one admitted bounded attempt; it must not claim consumption is a final
instruction after all staging or a clock sample immediately before rename.
The audit's broader suggested post-staging decision protocol would require
additional integration and is not silently supplied by removing this gate.

## Smallest implementation direction

1. **Keep the scope reducing and host-owned.** Once genuine guarded input and
   the complete management journey are reviewed, permit only normalization kind
   `native_literal_forget` in `Collection.managed_mutation/8`, using the existing
   normalized request/binding and `apply_mutation` CAS. Keep retention and
   supersession refused. Do not drop or weaken any existing strict deadline
   field/API, repurpose the document-only `switch_before` route, or derive a
   forget deadline from an expired target's source TTL. A future session-only
   alias is the same effect only if it produces the identical forget facts and
   normalization; no pin/duration/ordinary retention follows from that alias.
2. **Rederive after input.** Complete native display/reader closure and release
   target/policy display owners before waiting for input. After genuine input,
   reacquire actual Identity → Consent → Collection ownership. Recheck existing
   project/binding, installed artifact/recipe, positive exact management epoch
   and fingerprint, no quarantine, current signed format/catalog, literal key,
   full value/hash/revision, live/anchor rows, absence of an override, root and
   generation, and exact proposed operation/facts. Use the same original facts;
   refuse changes instead of silently rebasing. Disabled/expired capture and
   missing original evidence remain allowed for selected-derivative management,
   not inference or source endorsement. Mode, interactive client, explicit deny,
   resource ceilings and no headless/saved-consent admission remain unchanged.
3. **Preserve one-use admission and exact CAS.** Keep the actual same-process
   permit in the tracked management effect owner. `Review.check` can validate
   reservation but cannot authorize mutation. Consent persists one bounded
   `publishing` operation before the Core callback. The trusted normalizer
   authenticates target/root/metadata/facts and consumes once; its existing
   one-shot callback guard prevents another normalization attempt. A serialized
   native-review hash or normalization kind is not authority to recreate that
   permit. Retain exact operation ID, expected generation/revision, signed
   lineage retirement/suppression, literal/live-row removal, bounded metadata
   repairs and advanced import floor in one existing Core commit. No replacement
   target, fresh operation after loss, retry or replay is admitted.
4. **Keep ownership and unknown outcomes through completion.** Retain native
   owners through the fixed attempt, root switch, sync and receipt handling.
   Revocation, target replacement and a successor cannot acknowledge past a
   surviving old native writer. After Core returns, preserve exact accounting,
   normalized-request/normalization/Core-binding checks and
   `Review.consumed_receipt` against the same facts. Identity finalization and
   release precede deferred Consent settlement; keep that whole effect/settlement
   inside Review's live-success wrapper. Do not turn a consumed failure,
   exception, lost/late reply or uncertain cleanup into a known refusal or
   success. Later journal/guard/resource cleanup failure must downgrade the
   result. Respect the separately bound overall operation budget at final
   composed return; cleanup is still attempted after expiry. No clock check
   promises physical rollback or instantaneous owner-death cancellation.
5. **Use the real management journal.** Keep original native-owned header,
   append and Writer ownership, reserve terminal result capacity, and sync the
   immutable intent before Consent/Core admission. Record the terminal result
   without inventing success from a stored capsule. The input observation time
   and normalization's metadata time are not physical commit timestamps. Exact
   operation/root inspection remains read-only; an interrupted `publishing`
   liability cannot be reset or automatically replayed by reopening a Session.

This needs a narrow Collection gate change and the reviewed actual caller
composition, not a new workflow or generalized authorization framework. The
private display receipt is not an input observation or permit, and the source
snapshot does not qualify a restored public route.

## Focused acceptance still required

Use a fresh matching cohort after genuine input integration. Prove one actual
signed forget with complete facts and normal approvals, including revoked
capture/expired selected target and unavailable original support. Separately
prove changed target/root/epoch/recipe after input, wrong-client/foreign/reused
permit, pre-consumption expiry and ordinary/headless denial leave no admitted
root effect. Keep retention/supersession fence controls.

Reuse the original delayed-consumption schedule as an admitted/unknown control:
consume while live, delay beyond the actual permit lifetime, inspect any actual
suppression and exact operation after unknown, and prove no replay. Add owner,
receipt, sync/settlement and journal-cleanup loss controls around the fixed
attempt; do not count the present blanket refusal as restored-effect acceptance.
The native input/closure implementation and final coherent source/package
qualification remain separate pending work.
