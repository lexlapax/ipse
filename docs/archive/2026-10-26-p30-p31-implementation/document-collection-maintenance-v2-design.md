# Corrected document maintenance design, version two — 2026-10-29

Status: proposal, not destructive API authorization or implementation acceptance.
This replaces the unimplemented fence/migration direction in the [original
proposal](document-collection-maintenance-design.md), preserving it and its
[independent review](document-collection-maintenance-design-independent-review.md).
The original floor-advancing barrier and logical-only faithful export are
withdrawn. Current scope/acceptance remains in the [plan](../../plan.md).

## Implemented read slice and permission decision

The separate [descriptor inventory receipt](document-descriptor-inventory.md)
covers only `collection.store` / `value.index`. Parent direction explicitly
narrows the review's suggested separate maintenance capability: existing
operator-bound document read authority already reads any non-host key in the
same fixed namespace, so enumerating only that metadata needs no additional
trust selector. It supplies no deletion, fence, migration or arbitrary host-key
authority. Missing/foreign-instance document trust still refuses. No mutating
maintenance permission has been added to presets or configuration.

Destructive operations below still require a separately reviewed explicit
ordinary document maintenance grant, exact arguments, ordinary approvals,
current Session/artifact/project binding and durable intent. They cannot borrow
saved note consent or managed review/output authority. Project identity supplies
the fixed `document_graph_v1` namespace; requests never select filesystem roots,
foreign projects/Sessions, notes profiles, arbitrary State bindings or quotas.

## Independent durable barrier epoch

Give document maintenance a separate monotone safe-integer epoch, independent
of Collection's destructive floor. Store its closed typed state in the
hash-bound document manifest metadata, with explicit version compatibility:
epoch, status (`idle`, `active`, `recovering`), maintenance ID/purpose, actual
owner identity, opening descriptor/anchor commitment, lease deadline, bounded
progress and resource reservation. Preserve the current epoch in idle state.
Do not implement close by deleting a control record through destructive `commit`.
Do not put barrier state in the domain record map that import/rollback replaces.

Open/adopt/close update this metadata with existing native generation CAS and
`advance_floor:false`. They spend their real operation IDs, but neither change
suppression lineage nor erase a retained checkpoint. A domain-record deletion
still advances the actual floor and invalidates incompatible rollback. Notes
formats remain unchanged; old document roots start at epoch zero only through
an explicit compatible reader rule. Epoch overflow refuses; it never resets.

The actual native owner serializes the barrier change with every ordinary
document mutation: inline publish/prepare, stage open/append/seal/write-parts,
consumption, abort/reclaim and each migration mutation. No precheck separated
from the expected-generation CAS can authorize a write across a barrier. Native
lock ownership and existing final decision/release receipts remain mandatory;
the barrier does not promise physical completion before a clock millisecond.

Version Source/Index/Job/Projection publication continuations to bind this epoch
and their admitted owner/recipe. Check it from current stored metadata, not just
from the caller token, on every resume including edited direct-finish positions.
A worker's own stage writes may advance generation without changing its epoch;
do not reject those by confusing generation with the maintenance epoch. Current
tokens lack this guarantee. Until all publication paths implement it, the fence
and destructive GC remain unavailable. A fresh inspected token may continue a
known preserved job only after reconstructing its semantic plan/prerequisites;
unknown effects remain inspection cases, not automatic retries.

## Explicit recovery, adoption and abort

Proposed closed maintenance actions are open, inspect, checkpoint, close,
recover/adopt and abort. Cross-Session recovery is separately authorized and
fully proposed; ordinary possession of a maintenance ID or expired lease is not
ownership. Bind each transition to exact current generation, old maintenance
ID/epoch, protected anchor commitment and expected owner identity.

Before adoption/abort, stop the prior admitted owner and obtain authenticated
quiescence of its actual native effects and all transferred/inherited leases.
Use production Session resource cancellation and the actual retained native
Collection/Identity/source owners. BEAM DOWN, elapsed wall time, loss of the
request socket or a successful unrelated lock probe is insufficient. Acquiring
the same real Collection lock establishes that its earlier lock-held mutation
has ended, but is not proof that another dependent owner cannot later submit
work. Its stale epoch and Session admission must also be fenced. An unconfirmed
closure, stopped holder or missing release ACK leaves recovery busy/unknown;
there is no success acknowledgment or takeover based on timeout alone.

Once quiescence is established, inspect the old owner's durable operation IDs
and pending state. Adoption atomically advances the barrier epoch, binds the new
owner and preserves all unresolved effect identities/liabilities. It cannot
turn unknown into not-executed. Explicit abort removes pending eligibility and
releases the barrier through one known terminal transition; it does not replay
or roll back an admitted effect. Recovery is incomplete until the namespace and
resource state are inspected after that transition. The current native closure
integration must qualify this path before recovery is implemented/enabled.

## GC semantics and host guarantees

The Knowledge extension owns reachability traversal using existing Source,
Index, Directory, Generation, Reduction and Job validators. It must traverse
all partitions, current raw/lexical/shared selections, retained history and
dependent evidence, pending captured catalogs/summaries/runs/pages and exact
known prepared outputs. Preserve both root1 and root2 semantics. Corrupt,
missing or unknown edges refuse or conservatively retain; source expiry is not
permission to delete support still needed by another retained dependent.

Published immutable outputs can precede durable job advancement. If their exact
pending plan is unavailable, retain the entire affected candidate family until
completion or a separately approved exact abort. A barrier does not retroactively
make those values unneeded. Root/job/catalog replacement, unclosed source/output
lease or unsupported paused work blocks the destructive plan. Every operation
excludes `host.*`, host stage state and foreign namespaces from worker discovery
and deletion. No worker walks filesystem object directories.

The host enforces explicit ordinary deletion permission, fixed namespace,
barrier ownership, exact generation/revision/physical-hash/size checks and bounded
CAS. These checks do **not** prove a worker's mark set complete: a worker could
propose an exact current descriptor that remains reachable. Do not call ordinary
deletion host-enforced reachability or invent trusted-worker authority. The
official GC must establish its useful behavior through complete traversal tests.
Managed notes remain under their separate protected source/consent contracts.

For resumable traversal, use bounded typed private progress/frontier metadata
under the same manifest/barrier owner, not arbitrary worker writes to `host.*`.
Bind its ordering, ownership, closed schema and opening descriptor commitment.
The opening commitment is computed once. Exact checkpoint transitions prove
they cannot change the public record map and advance the expected generation;
do not rehash all 8,192 descriptors on every private step. Recompute the complete
commitment on recovery or any path lacking that invariant. Inventory cursors
alone prove neither complete scanning nor complete marking. Preserve the
multi-invocation read budget and reserve progress storage before opening.

## Faithful packed-layout export and import

`value.read` returns the concatenated original logical bytes, resliced for its
read envelope. It loses the stored part boundaries. `Migration.digest` commits
the physical packed-record hash/size, so those logical bytes alone cannot
reconstruct a byte-faithful export.

Define an explicit `document_packed_layout_v1` export recipe. For each public
record, authenticate its exact physical hash/size and closed `document_value`
shape, original logical hash/size and ordered list of original part lengths and
part hashes (at most ten parts of 6,144 bytes). Read the existing logical stream
in bounded fragments, reassemble each original part without changing its bytes,
and validate every part/hash/length plus the complete body. The layout receipt
must itself fit the existing SDK and be bound to the exact checked generation,
key and physical descriptor. Unknown/unpacked formats refuse this recipe; they
are not silently omitted from a claimed complete backup.

On import, preserve those exact original boundaries. Use explicit existing
stage open/append/seal, or fused write-parts grouping that keeps each original
part intact and tests the complete frame. Never let the ordinary adaptive writer
re-split the original body to different boundaries. A proposed trusted pending
`migration.accept` validates the sealed wrapper's exact physical encoding/hash/
size against the source descriptor before adding it to Migration's pending
record map. It consumes the owned slot atomically and does not publish that key
in the active map. Whole original bytes may fit 60 KiB while their packed object
approaches 64 KiB: do not raise the body/part limits to send that wrapper as one
new ordinary value. Existing canonical encoding plus exact part layout must
reproduce the source packed bytes, with an explicit equality check; any encoding
or numeric alias fails rather than changing the committed digest.

A different layout is allowed only under a **named, separately versioned
transformation** with both input and output descriptor commitments, exact key/
reference remapping and before/after semantic validation. It is not called a
faithful export or silently accepted under the old physical record digest.

The document export descriptor covers only its complete public document set,
fixed profile/project, exact counts/bytes, physical record digest and required
operation/floor lineage. Host barrier/progress/stage metadata is not exported as
domain records. Source export is fenced for coherent multi-page reading. A
faithful backup may preserve expired bytes; import does not renew TTLs or grant
current recall/capture authority. P26/P27/released-notes conversion still needs
its separately admitted source and suppression/domain conversion recipe.

Extend existing Migration/Planning behind a document-specific descriptor/plan
version. Stream descriptor pages and operation receipts before bodies, check
complete order/digests/lineage, and preflight the exact plan. Reuse its persistent
pending record map, operation identity checks, atomic switch and same-floor
checkpoint behavior. Preserve barrier metadata across switch/abort/rollback.
Only the exact current owner's import staging/accept/terminal actions may cross
the migration fence. A lower/incompatible floor, ID collision or stale generation
refuses. Keep notes' 24-MiB/6-KiB/page request contracts byte-compatible.

## Whole operation reservation and ledger prerequisite

Do not use notes' `ceil(records/32)` import reservation for streamed documents.
For each actual planned value, calculate the exact emitted preparation mutation
count `F(value, layout, marker, frame envelope)` with the real client validator.
It includes inline versus fused/legacy transport, preserved layout, escaping and
full metadata widths. A Job immutable costs `F + 1` (prepared value plus consuming
CAS); direct fused immutable publication costs `F`. Import acceptance costs one
additional mutation per newly prepared record. With a faithful legacy stage
path, `P` original parts cost `1 + P + 1 + 1 = P + 3`, not one page mutation.
An explicit byte-authenticated immutable reuse still costs its actual pending-map
acceptance mutation; unknown is never converted to reuse.

The required ledger is the **ordered sequence**, not independent capacity passes:
initial raw/document/lexical/shared build; required old-plus-staged replacement;
GC/retained history; complete export/import into fresh and populated targets;
checkpoint/rollback policy; terminal cleanup and the frozen turnover workload.
For every step record actual value/part/frame count, immutable reuse, job/catalog/
root checkpoint costs, private progress/plan writes, destructive deletion batches,
barrier/recovery changes, incoming unique operation IDs and maximum simultaneous
logical/physical bytes/records. A 16-effect invocation bound is not a lifetime
operation reservation.

Known local evidence constrains, but does not finish, that ledger:

| Evidence/component | Count and precise limit |
| --- | --- |
| Older shared dry plan `full-profile-packed-dry-46911.log` | 125 groups, 1,625 supplied group values, 5,587 direct fused value mutations; its planned 5,030/6,414 keys exclude later summaries/runs/root2/GC/migration |
| Same values through current Job prepare/consume | 5,587 + 1,625 = **7,212** mutations before Job metadata and summaries, assuming the same body/frame geometry; arithmetic, not a populated execution |
| Representative disjoint 5,000-entity root2 reduction | 125 captured summaries; 157 run pages plus eight run directories, eight manifests, 157 entity pages; 157 merge and 157 semantic verification steps. Each durable job/catalog rewrite and immutable write/consume must be counted |
| Retained root2 maximum component controls `47074`/`47077` | Final selection: 377 reads/9 effects; each semantic page: 46 reads/6 effects; these worst metadata shapes are not an actual full recipe total |
| Same maximum semantic-page shape repeated 157 times | **942** verification mutations alone; a conservative shape projection, not a measured full build |
| 8,192 fresh inline imports, no reuse | At least **16,384** prepare/accept mutations before imported IDs, planning/operation pages, barrier/recovery/checkpoint or larger values |

The earlier 31,758 initial-plus-rebuild estimate used a superseded source-local
layout and cannot certify the shared recipe. No complete updated shared ledger
exists in the retained evidence. This is a **blocking prerequisite for mutating
maintenance**, not postponed acceptance after implementation. Do not claim that
the lifetime 32,768 ceiling fits migration or sustained turnover from these rows.

At open, compute `K = Known(target) union Incoming(unique source operation IDs)`
with exact receipt equality for duplicate IDs. Reserve **all remaining planned
successful mutations**, including their real per-value staging, every private
checkpoint/plan mutation, operation-page acceptance, selection and close. Require
`|K| + planned_mutations + terminal_reserve <= 32768`, and maintain/debit that
reservation durably under the same lock. Ordinary writers cannot spend it. An
unknown step retains a slot/liability until inspection settles its operation ID.
For a populated target, incoming duplicates are a union, not double-counted; a
fresh target must budget imported identities as well as local staging effects.

Derive terminal reserve from the actual admitted state, including up to sixteen
owned stage aborts, one adoption transition if needed, migration abort/close,
permitted checkpoint disposition and the measured number of bounded physical
orphan cleanup passes. Do not insert a constant two-operation allowance. Reserve
their exact metadata/native allocation too. If that full sequence cannot fit,
review a bounded receipt/history/floor compaction design **before** admitting
mutating maintenance. Never erase known IDs, reset generations, shrink the
frozen workload or call refusal ordinary useful capacity.

## Implementation conditions and tests

Only read inventory is implemented by this task. Destructive work remains blocked
on the complete ledger, epoch-aware publication paths, actual owner quiescence/
recovery and physical-layout recipe qualification. Reuse existing Collection,
Migration, Blocks, Encoding, native Transaction and OTP JSON/crypto adapters;
no common workflow engine, hash algorithm or native protocol change is approved.

Focused later controls must cover export preserving a retained checkpoint;
barrier open/close with unchanged floor/lineage/checkpoint; destructive delete
invalidating incompatible rollback; every old/new continuation and own stage
write; stopped original native owner and all-holder closure; cross-Session
recovery/adopt/abort, stale owner and unknown no replay; same logical bytes with
different legal part boundaries, Unicode/escaped/ten-part bodies and exact
physical digest equality; fresh/populated target ID unions and near-limit
reservation sufficient for known terminal cleanup. The complete native/public
initial/rebuild/GC/migration/turnover workload and peak allocation still qualify
the frozen product target. No new full workload or model call ran for this design.
