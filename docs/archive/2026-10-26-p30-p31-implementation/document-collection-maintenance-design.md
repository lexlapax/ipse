# Proposed document Collection reclamation and migration — 2026-10-29

Status: bounded design for parent review, not implementation or new authority.
No runtime code, gate, test cohort, model service or sealed quality input changed.
The [plan](../../plan.md) owns acceptance. This follows the reviewed ordinary
[document decision path](document-decision-restoration-implementation-review.md)
and [directory-v2 direction](shared-directory-v2-design-independent-review.md).

## Required result and current boundaries

The frozen [baseline, lines 711–722](baseline.md) requires the full document
profile and old-plus-staged rebuild together within the total envelope including
notes. Lines 636–659 require preserving TTLs, dependent evidence and suppression
identity; lines 732–740 require complete export, fencing, checkpoints, validation,
atomic root switch and rollback that cannot resurrect forgotten facts. Safe
refusal alone does not qualify usable capacity. The [commit contract, lines
103–119](contracts.md) requires immutable complete staging, atomic selection and
unknown inspection without replay.

The design supplies bounded maintenance for the **ordinary, fixed project
document namespace**. It does not grant access to notes, SemanticAdmission
namespaces, arbitrary State bindings, Session journals, other projects, arbitrary
paths or a caller-selected quota/profile. Importing P26/P27 or released-notes data
still requires its separately admitted source binding, domain conversion and
suppression checks. The document primitives below are necessary infrastructure
for that journey, not acceptance of those conversions.

| Existing owner/API | Reuse | Exact gap |
| --- | --- | --- |
| `CollectionStore.prepare/execute`, fixed `document_graph_v1` binding | Existing project lookup, identity/artifact/Session binding, ordinary approvals, intent/receipt validation, resource scope | Public `DocumentStage` currently exposes no published-value index, deletion, operation inspection or export/import |
| `Collection.ReadView` and `Directory.visible_index` | Native-root-checked metadata selection with zero value-object reads | Current visible filtering hides only `host.validity.*`; a document index must hide **all** `host.*`, especially `host.stage.*` |
| Core `commit` with nil values | Exact native generation and per-record revision CAS; destructive floor advance; existing atomic publication | No public document deletion operation or safe reachability controller |
| Core physical `collect` | Same-lock retention of active, migration and checkpoint objects; at most 512 orphan files per directory/pass | This does not discover unreachable **logical records**; it runs after publication, not as a worker directory walker |
| `Migration`/`Planning`/`Encoding` | Durable writer fence, known IDs, record/operation digests, lineage checks, pending records, atomic switch, checkpoint/rollback | Document profile rejects migration at `execute_selected`; descriptor is notes-limited to 24 MiB, values/plans to 6 KiB, and pages contain 32 whole values. These cannot cross the unchanged SDK with large packed documents |
| `DocumentStage` | Exact body/hash, bounded parts, owned reusable slots, stage consumption, native CAS and deadline/unknown rules | Consuming a sealed value into **migration pending records**, rather than live records, needs a trusted adapter |

Core deletion removes a logical record-map entry and can free a live record
slot. It does **not** erase successful operation IDs or replenish the 32,768
operation ledger. Neither GC nor migration may silently reset that ledger.
Document native allocation remains 192 MiB, logical document data 160 MiB,
8,192 records and the existing fixed reservations; all new maintenance metadata,
operations and old/staged/checkpoint overlap count.

## Authority and proposed host surface

Use a separate closed `collection.maintain` host action with project scope,
`host.actions` and explicit `host.collection.maintain` operator trust for the
fixed `documents`/`document_graph_v1` binding. The proposed binding lists the
admitted maintenance operations (`index`, `delete`, `export`, `import`); existing
`host.collection.store` bindings retain their current meaning. This is a
proposal requiring the parent's design decision, not an existing configuration
field or runnable command. Do not silently add it to existing presets/trust.

Resolve the namespace from the already admitted ProjectIdentity exactly as
CollectionStore does. Worker JSON never supplies a namespace, filesystem root,
profile, Session ID, owner, quota or a source-store credential. Bind each action
to the exact request, selected identity, actual Session/job and operation ID.
Journal intent before mutation; display full arguments; headless mutation still
requires ordinary explicit authorization. Managed-input mutation remains denied
at both current admission and execution boundaries. Maintenance grants no saved
capture consent, review permission or protected output permission.

All operations below are proposed inner requests, not existing accepted APIs:

| Request | Closed arguments and result |
| --- | --- |
| `records.index` | `generation`, `after` (null or exact public key), `limit` 1..16; returns ordered physical descriptors, `next`, generation/floor and an explicit `public_document_records` coverage tag |
| `records.delete` | `maintenance_id`, expected `generation`, 1..8 exact `{key, revision, record_sha256, record_bytes}` candidates; returns a bound destructive receipt or conflict |
| `operation.inspect` | Exact operation ID; returns the existing known receipt or absent at a checked generation, never executes it |
| `maintenance.open/checkpoint/close` | Purpose `gc` or `export`, expected generation, exact observed root/job/catalog anchors, owner-bound maintenance ID; checkpoint accepts only closed bounded maintenance progress; close uses the current exact fence/revision |
| `migration.open/plan/accept/operations/commit/abort/checkpoint.drop/rollback` | Fixed-profile, owner-bound streamed forms described below; each mutation carries expected generation and exact migration/checkpoint ID |

An index descriptor is `{key, revision, record_sha256, record_bytes}` for the
**physical packed record**, taken from validated Collection metadata without
opening its body. It is distinct from `value.stat`'s logical original-body hash
and byte count. Keep these names distinct in the protocol, validators and
receipts. Exclude all `host.*` keys before pagination/counting; refuse a private
cursor. Never return host stage headers, parts, ready values, owner identities or
foreign Session data. A cursor is ordering state, not a completeness proof:
require exact generation on every page, start at null for a complete scan, and
verify exact monotone progress. Shrink by complete descriptors to a fixed
4-KiB result budget; never drop fields or truncate keys. Reuse ordered-tree
selection and root rechecking, not filesystem enumeration or a second index.
The worst 8,192-record walk can require 512 sixteen-row pages **plus** startup
reads; it must use explicit continuation rather than pretend one invocation
fits the 512-read allowance.

## Publication barrier and pending work

GC cannot infer reachability from the current selected root alone. As confirmed
with the shared-generation owner, an append/reduction publishes one immutable
value per explicit continuation **before** advancing its durable job. New
summary/group/run/manifest values may therefore exist without a job reference,
including after unknown without a recoverable caller token. Raw-source and
lexical builders have analogous pre-selection windows. Stage TTL is not a TTL
for those already-published immutable values.

Use one document-only durable maintenance fence, created by a generation-CAS
under the actual Collection native lock. A small host-private control record
can reuse ordinary Collection persistence; it need not introduce a second
database or native protocol. It binds purpose, fixed namespace/profile,
maintenance ID, actual owner identity, opening generation and a bounded lease
deadline. Its existence must be checked by **every** production ordinary document
mutation, including inline writes, staged writes and stage consumption, before
the same expected-generation CAS. Checking outside that CAS without generation
binding is insufficient. Opening drains the current native operation; all later
ordinary mutations refuse until a known close/abort. Read operations remain
generation checked. The fence is never worker-visible through `records.index`.

Opening and closing advance the existing Collection floor. Versioned extension
continuations must capture and check that floor/barrier before resuming paused
publication work. Current Job/Source/Index tokens do **not** supply this guarantee;
it is an unavoidable integration gap. A continuation from before maintenance
must not silently resume at its old unit after GC. An operator may explicitly
inspect a preserved durable job and obtain a new token after revalidating every
prerequisite; unknown in-flight effects are not replayed. Unrecorded source-build
plans require an explicit restart with their complete original input.

Do not acknowledge the barrier by merely killing a BEAM worker or timing out a
GenServer. Reuse `Session.Resources.file_effect`, the actual native Collection
lock owner and authenticated check/release receipts. Identity/control ownership
precedes Collection storage ownership; never call back into Session while
holding storage. If a protected-output/source lease holds the same real native
lock, acquisition waits for its actual quiescence; no surrogate lock substitutes.
Missing release/owner response is unknown and the fence remains inspectable.
Closing a Session cancels dependent work; it does not prove a native operation
failed. A lease deadline blocks new maintenance work after expiry, but does not
auto-close a fence or undo an admitted mutation. Recovery requires a fresh
explicit owner-bound inspection/adoption/abort and confirmed old-owner cleanup.

The first implementation should require no live inbound stage slots before
opening GC/export/import, rather than reinterpret their private bodies as
domain records. Same-owner abort and exact expired-epoch reclaim already exist.
Other owners' live slots are not force-aborted; report the bounded busy condition
without disclosing owners/content. A crashed owner's one-hour slots follow the
existing explicit expired-reclaim rule. Reserve enough operation/byte headroom
for fence close or migration abort before opening; expiry never spends that
reserved terminal allowance automatically.

## GC algorithm and conservative reachability

Keep domain traversal in a small knowledge-extension maintenance module, reusing
the actual Source/Index/Directory/Generation/Job/Reduction validators. Host code
owns namespace, fence, quotas and exact deletion CAS, not document semantics.

1. Preview fixed scope, current native generation/floor, all protected anchors,
   pending/busy status, descriptor counts and a bounded work/byte/operation cap.
   Open the approved fence. Reload the anchors and begin the descriptor scan
   under that known maintenance generation. The host fence also binds the exact
   ordered public-descriptor commitment/count, computed with the existing
   canonical metadata digest. Persist a closed, versioned GC job plus bounded
   mark/frontier pages through `maintenance.checkpoint` for explicit continuation.
   These are host-derived private maintenance keys, excluded from the public
   scan; this adapter grants no arbitrary `host.*` write. Own checkpoint writes
   change the native generation, so every next page uses the known new generation
   and rechecks that the public descriptor set/anchors still match the opening
   commitment. Do not add public mark keys mid-scan and falsely claim the old
   cursor covered them. No deletion begins until the complete descriptor set
   authenticates. Charge and preflight every checkpoint key/byte/operation; a
   stored cursor or caller-supplied `marked=true` is not semantic proof.
2. Mark all current raw catalogs/pages/source heads and their data/lexical blocks;
   selected lexical roots/groups/packs; selected shared root1/root2 manifests,
   entity pages, group headers and source/vector/fact pages. Authenticate every
   hash/size/recipe/ordinal and exact reference edge. Preserve full retained
   historical/suppression objects; source expiry alone is not deletion authority.
3. Mark active/pending jobs, captured catalogs/summaries, reduction manifests,
   run directories and all run pages, merge/entity pages and known prepared
   outputs. A run reference cleared from a completed job can become collectible
   only after the selected/new pending roots no longer reference it. Shared
   families are `gengrp/gensrc/genvec/genfact/gensum/genman/genent/genrun/genruns`;
   raw `data` also contains lexical bundles. Discover all partitions in the fixed
   namespace, not only the caller's currently selected partition.
4. **Conservative first version:** if a pending builder's exact durable plan is
   unavailable, retain all candidate immutable families that builder might
   reference. A paused shared job may therefore defer shared GC until completion
   or its separately approved exact abort. Do not guess the unpublished set from
   current job refs, file timestamps, lexical prefixes or stage expiry. Likewise
   retain unknown-format/root records and report incomplete coverage. Missing or
   corrupt protected references refuse deletion rather than become empty edges.
5. Propose only unmarked, recognized immutable-body keys in the same fixed
   namespace. Root/catalog/source-head/job/control records are not generic GC
   candidates. Each deletion checks current fence, unchanged protected anchors,
   expected native generation and exact candidate revision/hash/size. One native
   `commit` of nil values with `advance_floor:true` performs at most eight
   deletions atomically. No rebasing conflict; any concurrent root/job/catalog
   replacement stops the plan. Advance only after a known receipt. Re-establish
   the current generation and exact invariant anchors after each own batch.
6. Complete only after the ordered scan finishes and anchors/fence still agree.
   Close the fence explicitly, invalidate old work tokens and report logical
   records removed separately from physical orphan bytes actually reclaimed.
   Reuse native post-publication orphan cleanup; additional passes, if necessary,
   need a bounded trusted maintenance entry and measured receipts. Never let a
   worker unlink object/manifests paths. No idle/disabled background GC is added.

A crash can leave a fence, partial mark job, known deletions or unknown deletion.
Prior deletion batches remain committed; selected/pending reachable values
remain intact. Inspect the exact operation ID, durable fence/job and native
generation before proceeding. A missing client receipt is not permission to
repeat it. A new explicit plan may inspect and validate the surviving store;
it cannot claim the interrupted plan completed. Old GC cursors and mark pages
cannot authorize deletion against a changed root/floor or another maintenance ID.

## Fixed-profile streamed migration

Do not expose generic notes `export/import` requests or switch `Profile` limits
globally. Extend its existing typed machinery behind an explicit document recipe:

1. Open a source export fence after stage quiescence. Export only this project's
   public document records, their complete physical descriptors and required
   operation/floor lineage. Bind version, fixed profile, namespace, format
   recipe, exact generation/floor/anchor/lineage, record count/data bytes and
   full record/operation digests. Host-private maintenance/stage records are
   excluded by construction. The descriptor must explicitly describe that public
   set; the existing raw whole-store descriptor cannot be relabelled unchanged.
   A faithful backup may retain expired evidence bytes; that grants no current
   recall or capture eligibility.
2. Stream descriptor/operation pages and logical value bytes using the existing
   bounded readers. Source generation and descriptor stay fixed through export.
   A local export destination is selected by the operator, represented to a
   worker by a fixed opaque project/profile/digest-bound artifact handle, never
   an arbitrary filesystem path or new shell/network grant. Complete export
   verifies counts and existing canonical digests before reporting success.
3. Open a target migration only for the same explicit project/profile (a cross-
   project join is a different approval/design). Reuse `Migration`'s persistent
   writer fence and pending records. Add a document-only planning phase that
   streams exact record descriptors and operation receipts before accepting
   value bodies. Reuse existing canonical record digest, operation hash chain,
   packed receipt encoding and lineage checks. Do not invent a SHA algorithm or
   serialize a hash context. Store bounded planning pages/checkpoints; each page
   authenticates exact order, counts and previous progress. Compute the complete
   bounded metadata digest from authenticated descriptors at the terminal check.
4. After the exact plan is present, preflight the actual old/live/pending/
   checkpoint/manifest/native allocation plus all future terminal operations.
   Refuse before copying bodies if the unchanged profile cannot fit it. Imported
   successful IDs count against the operation ceiling; current/incoming ID
   collision, mismatched receipt, lower/incompatible floor or missing lineage
   anchor refuses. No quota reset or imported-ledger erasure is a migration.
5. Reuse `DocumentStage` to receive each original body through owned bounded
   parts. A trusted `migration.accept` consumes an exact owned sealed slot into
   the **pending migration record map**, matching its planned key/body digest/
   byte count and physical packed representation; it never selects that key in
   the active record map. Whole-value `import.page` over SDK is not the transport.
   During the fence only the exact owner's migration staging/accept/terminal
   operations may mutate; other stage/direct/ordinary commits remain refused.
   This is a fixed trusted adapter to existing publication, not a callback from
   untrusted worker JSON while a native lock is held.
6. Validate the full record set, counts, bytes, operation digest, lineage,
   document structure/reference graph and preserved domain TTL/suppression
   semantics. Then reuse the existing one native atomic pending-to-active switch.
   Do not alter active roots piecemeal. A same-floor checkpoint can retain the
   old record set as existing Migration permits; an advanced floor cannot
   create rollback that resurrects older facts. Every further destructive floor
   advance invalidates incompatible rollback. Drop checkpoints explicitly only
   after validation/approval; retained checkpoint bytes count toward peak.
7. Abort removes pending selection eligibility and releases the fence only after
   a known terminal receipt. Preserve seen operation identities as existing
   Migration does. Crashes/owner loss leave a resumable inspected pending state
   or unknown; no automatic `accept`, commit, rollback or abort. Exact partial
   known progress can continue only with a freshly validated explicit request.

This requires a document-specific descriptor/plan version and staged acceptance,
not simply adding migration names to `execute_selected`'s allowlist. Existing
notes request shapes, 6-KiB values, 24-MiB descriptor, 32-record page semantics,
digests and tests stay unchanged. A format conversion must explicitly declare
its recipe and revalidate all references before selection; byte-faithful export
alone is not a proof that a new reader can interpret old data.

## Files and focused acceptance before enabling

Proposed host changes belong in `collection_store.ex` or its tightly coupled
maintenance owner; `collection/document_stage.ex`, `collection.ex`,
`collection/migration.ex` and `collection/planning.ex` own the fixed adapters,
same-lock fence and document recipe. Update exact capability/trust/action and
Saved receipt validators in their existing owners. Keep reachability and
streaming orchestration under `extensions/knowledge/src/store/collection/` and
expose explicit Corpus preview/continue/abort commands only after public Session
verification. Reuse native Transaction; no native protocol change is justified
by the identified gaps. If native cleanup ownership cannot be proved, stop that
part and review it separately rather than adding a filesystem bypass.

Required focused controls, not run by this design review:

- Public descriptor scan: exact complete ordering across maximum legal keys and
  metadata pages, zero body reads, empty/final pages, 4-KiB result/16-KiB complete
  SDK frames, stale generation/cursor refusal, all `host.*` excluded, no foreign
  project/Session/notes namespaces and unchanged legacy APIs/trust denial.
- Actual Session deletion: full approval, exact generation/revision/hash/size,
  retained active/root1/root2/lexical/pending/run/shared references, reused
  immutable values, multiple partitions, unknown formats and corrupt/missing
  references. Concurrent root/job/catalog replacement and queued stale approval
  refuse. Live foreign stages refuse maintenance; exact expired reclaim still
  works. A pre-maintenance paused Source/Index/Job token cannot publish afterward.
- Barrier/cleanup: competing native writer/read owner, Session cancellation,
  helper loss, expired maintenance lease and unknown after deletion/before
  result. Observe actual lock release/quiescence and preserved unknown without
  replay; retained GC jobs/mark pages cannot outlive their exact authority.
- Native migration: complete new large/escaped values, all stage ownership and
  part limits, fixed descriptor pages, exact digest/order/coverage; old selected
  store unchanged before final switch; stale/conflicting/imported IDs, lower or
  forged floors and malformed references refuse. Crash/reopen at planning,
  staged accept and final-switch receipt boundaries; explicit abort/checkpoint/
  rollback preserve floors and known IDs. Include fresh target and existing
  populated target, not just direct trusted fixture insertion.
- Whole workload ledger: measure full initial/rebuild/migration/GC peaks,
  logical records versus physical objects, all planning/stage/mark/checkpoint/
  journal metadata, old-plus-staged overlap, exact operation counts, quota
  reservations and bounded terminal cleanup. A small successful GC/import does
  not qualify full capacity or sustained new-source turnover. If retained
  operation history prevents the required useful workload, a separately reviewed
  bounded history/floor compaction design is required; do not discard receipts.

Only local source and previously frozen evidence were read. No runtime probe,
model request, aggregate suite or docs checker ran. The parent reviews this
proposal before assigning implementation and owns plan/navigation/commit work.
