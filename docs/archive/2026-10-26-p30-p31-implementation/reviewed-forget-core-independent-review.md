# Independent review of the forget-only Core fence

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the Core receipt](reviewed-forget-core.md), manifest SHA-256
`47ec7ccfc5cd45581b5d21679eeed4f0533afe536d992072070af770ae477544`,
against the [accepted effect direction](reviewed-forget-effect-restoration-independent-review.md)
and [private input review](management-review-input-independent-review.md).
No runtime edits, tests, native/model effects, network calls or gate changes
were made by this review.

## Disposition

Accepted as the narrow Core fence change. The owner-source diff is one line:
`native_literal_forget` leaves the refused-kind list;
`native_literal_retention` and `native_literal_supersession` remain refused.
The normalized-request/Core binding, exact generation/revision CAS, operation
ledger, signed retirement/suppression, advanced import floor and native owner
path are unchanged. This does not create a worker-supplied permit constructor
or make a normalization kind a source of authority: the trusted management
normalizer still revalidates and consumes the actual same-owner Review permit.

This follows the specific original one-use semantic admission contract. Bounded
post-consumption work can become unknown after expiry/loss; the change does not
promise physical completion before a deadline. Strict deadline APIs and other
normalizers remain unchanged. Public Management entry gates remain closed.
Actual journaled genuine-input forgetting belongs to the separate composed
effect cohort and is not qualified here.

## Evidence verified

The [verification script](reviewed-forget-core-review/review-manifest.exs) and
[result](reviewed-forget-core-review/review-manifest.log) check six source
snapshots, eight launch/log files, both freeze helpers and three complete graph
inventories. Each contains 698 physical regular files and one recorded telemetry
directory symlink; the verifier checks its target without traversal. Only
Collection changes from accepted input graph to Core graph. Only CLI.Knowledge
and CLI.Errors additionally change in the corrected diagnostic graph. Helper,
Review, normalizer, Consent, Journal and Writer remain unchanged.

I inspected strict compile 47145, the ten passing selected 47146 controls, the
two retained failures, corrected diagnostic compile 47147 and the two targeted
47148 passes. The new storage-fence control proves retention/supersession do not
advance generation/floor/root or add their operation IDs. Its synthetic trusted
callbacks do not prove native input, signed forget normalization or an actual
Review effect. Existing managed-CAS/read-lifetime/owner-loss, strict deadline and
direct retention refusal controls retain their scope.

Both initial CLI failures compare newer expected text against an older inherited
CLI executable; their actual outcomes already refuse before review/mutation.
The corrected graph overlays current diagnostic owners and reruns only those
two cases. Product source and expectations were not weakened. The initial
freeze helper's directory-symlink read failure is retained; the corrected freeze
records symlink type/target and does not repeat runtime controls.

No passing aggregate was rerun. Same-journal intent/result ordering, actual Core
suppression, Consent settlement, changed facts/epoch, expiry/owner loss and
no-replay remain requirements of the independently reviewed effect journey,
not consequences of this one-line restoration.
