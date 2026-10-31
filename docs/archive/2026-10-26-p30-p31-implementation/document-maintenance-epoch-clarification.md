# Required maintenance epoch and ID rules — 2026-10-29

This parent disposition adopts the remaining conditions from the
[independent inventory/v2 review](document-inventory-v2-independent-review.md).
It supplements the unchanged [v2 proposal](document-collection-maintenance-v2-design.md),
whose reviewed SHA-256 is
`62f5cca802d37156719b1b48f17b7cf72a4a98b97e1d34f01d41bbaa9d18d56a`.
It implements no fence, deletion or migration. The [plan](../../plan.md) owns
acceptance; the complete workload ledger remains a prerequisite.

The opening transition must invalidate previously admitted ordinary work even
after maintenance closes. Merely checking `active` while a fence exists is
insufficient. Use these explicit transitions under the same native generation
CAS as the hash-bound barrier metadata:

| Transition | Epoch rule | Required binding |
| --- | --- | --- |
| Open from idle epoch `e` | Select strictly new `e + 1` atomically with the active fence | New maintenance ID, exact current generation/anchors and admitted owner |
| Checkpoint in active epoch `e` | Preserve `e` | Exact maintenance ID, owner, ordered progress and current generation |
| Adopt an interrupted active epoch `e` | Select strictly new `e + 1` atomically with the new owner | Explicit recovery authorization, exact prior fence, actual old-owner quiescence and unresolved operation inspection |
| Known close or abort in active epoch `e` | Return to idle retaining `e` | Exact current fence/owner and confirmed terminal result |

Never restore the pre-open epoch, infer an epoch from a caller token, reset on
idle, or silently wrap an exhausted counter. Opening/adoption must refuse an
unrepresentable transition before publication, preserve existing state and
honor the preflight's terminal/recovery headroom. This counter is independent
of the destructive floor; read-only export must preserve existing rollback
checkpoints. Actual deletions retain their separate floor-advancement rule.

Every relevant Source/Index/Job/Projection publication continuation must
authenticate the stored epoch and semantic prerequisites at resume. A pre-open
token from `e` must still refuse after close has retained `e + 1`. Reading the
new epoch and editing an old caller token is not fresh admission. Test this
exact post-close schedule, adoption, abort, edited direct-finish tokens and
overflow. Existing unversioned work requires explicit inspection/revalidation;
the new field cannot be assumed from a legacy token or defaulted across a fence.

Migration reservations must also protect identity, not just arithmetic. Before
body staging, authenticate the complete planned incoming operation-ID set and
its receipts. Every newly allocated local stage/checkpoint/terminal ID must be
absent from that reserved incoming set as well as already-known and allocated
local IDs. Randomness is not proof of disjointness. An incoming already-known
ID is usable only under the existing exact matching-receipt/binding rules;
count the actual set union without erasing either history. Reserve all future
local staging/plan/progress and terminal IDs together with still-new incoming
IDs before copying bodies. A count that fits while its IDs collide does not fit
the protocol. Include adversarial chosen collisions and unchanged legacy notes
behavior in the focused implementation controls.

These requirements close ambiguities in the proposal. They do not establish
an implemented barrier, a usable full-profile migration or safe native takeover.
The actual producer/storage/journal ledger, owner-control integration and exact
packed-layout streaming still need their implementation and verification.
