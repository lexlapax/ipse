# Ordinary document-stage decision restoration — 2026-10-29

Scoped implementation evidence following the [accepted design](document-decision-restoration-design.md)
and its [independent scope review](document-decision-restoration-independent-review.md).
This restores ordinary fixed-profile document staging, not P31 completion or
managed-source publication. The [plan](../../plan.md) owns acceptance.

## Behavior and scope

`Collection.execute_profile_before/6` now admits only the fixed
`document_graph_v1` profile and a bounded positive host deadline. It preserves
the inherited minimum and uses the existing actual native lock owner's
`switch_before` for the final synced-pointer decision. The native owner retains
the locks through rename, directory sync and release. Expired decisions refuse
selection; a pre-expiry decision can finish physically later. The native error
reply is not a persisted decision timestamp, and a failure after staging remains
the existing conservative unknown result. No rollback or replay is inferred.

Notes-profile timed publication, the blanket `with_publication_deadline` callback,
saved-consent capture, native-reviewed management and managed output remain gated.
`publication_support/0` still reports unavailable for knowledge capture.

The scope review found that `collection.store` could otherwise bypass those
managed-effect gates under ordinary allow/`--yes`. Invocation now refuses its
managed mutations before intent, approval or dispatch. CollectionStore separately
refuses a mutation whenever `with_effect` supplies a non-null managed deadline,
before entering DocumentStage. Host lineage, never a worker flag, selects that
classification. Read-only operations keep their existing rules.

A new classifier control exposed a corrupt-dictionary exception: a missing
dependency digest could raise instead of returning a nonempty/unavailable union.
`managed_invocation?/1` now treats exceptions and caught exits as managed. This
cannot make unavailable lineage ordinary. It grants no operation or disclosure.

## Focused evidence

The [manifest](document-decision-restoration/manifest.sha256) pins fourteen source
files, all retained logs, the queued-action fixture and final runtime inventories.
No provider or external model request ran.

| Control | Actual result |
| --- | --- |
| Current document components,47048 | Four pass: prepared inline consumption/owner fencing, full multipart append/seal/consume/slot reuse, expired-slot refusal/reclaim and trusted live/elapsed deadline scope cleanup. |
| Inherited minimum and restoration,47046 | One pass: inherited deadline cannot be cleared or extended; earlier deadline wins; invalid/expired scopes refuse; exact scope is restored. |
| Synced pointer delayed past deadline,47047 | One pass: actual native staging completes while retained owner waits; after expiry, result is unknown, root bytes and old selected value are unchanged. |
| Public ordinary Session and notes gate,47049 | Both pass: >32 KiB complete value with ten full-argument approvals, seven append actions and valid replay; notes timed entry/callback still refuse before staging. |
| Lineage and actual managed Session gates,47051 | Three pass: inherited-only, newly read, unavailable and missing-dictionary dependencies classify as managed; allow and interactive document mutations both refuse before intent, effect admission or namespace creation. |
| Queued-action execution backstop,47052 | One actual Session passes using an explicitly older Invocation overlay: managed action intent/admission occurs, but current CollectionStore returns typed failure before DocumentStage and no document namespace exists. This tests the second boundary, not current public admission. |

Strict compilation passed for State, Collection, CollectionStore and Invocation
in47040, current DocumentStage in47044, and the repaired classifier in47050.
Formatting and scoped whitespace checks passed. Existing native-owner and
pre-/post-decision evidence supplies the unchanged native transaction foundation;
this section adds no native code or claimed physical expiry primitive.

## Failed cohorts and executable identity

The graph was copied from the frozen State-native v6 cohort, then compiled with
the four changed modules. Initial47041 passed four components but failed the
inherited trace: it still loaded an earlier DocumentStage that ignored the
inherited minimum. Its old BEAM is retained under `_build` and hashed. After
compiling current DocumentStage,47045 reached the correct refusal but its test
tried to prepare a new snapshot inside an expired scope. Preparing that request
before entering the expired scope corrected the fixture;47046 passed. Neither
failure is presented as a successful minimum-deadline control.

47049 passed its actual Session and notes cases but failed the new missing-digest
classifier assertion with an exception.47050 repaired that public classification
boundary, and47051 passed the new classifier plus both actual managed gates.
The final inventories were captured after these controls, not before the first
run. [Cohort metadata](document-decision-restoration/cohorts.json) names every
overlay and this provenance limit. The final helper is the already frozen State
v6 helper; the queued graph differs intentionally by its earlier Invocation.
The complete original runtime inventory was not captured before overlay edits;
do not label all intermediate executions as one final-source cohort.

The queued fixture and [launcher](document-decision-restoration/queued-backstop.exs)
are retained. It deliberately uses the earlier State-restoration Invocation BEAM,
which lacks the new document pre-intent gate, while retaining current document
execution and classifier modules. It proves refusal of a previously admitted
managed action at execution, not permission to bypass the current public gate.

## Remaining qualification

Independent implementation review, whole operator/developer document
reconciliation and the batched documentation check follow this freeze. The
coherent full-source/package baseline remains pending. No installed bundle,
arbitrary platform, complete fault schedule, human workflow or final P31 audit
is claimed. The new read-only shared generation/controller and streamed
finalization need separate actual protected-write, capacity, cleanup and migration
qualification; a working staged store alone does not establish them. Other
source/output/consent/review boundaries retain their own gates and requirements.
