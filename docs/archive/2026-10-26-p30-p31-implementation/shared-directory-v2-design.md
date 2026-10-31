# Proposed bounded shared-directory version two — 2026-10-29

Status: scoped design for independent review; not implemented or admitted.
The [measured metadata geometry](shared-metadata-geometry.md) shows both an
earlier native packed-wrapper refusal and704read replies for legal5,000-label
metadata. Existing limits remain16KiB encoded SDK frames,8KiB decoded strings,
ten native parts,64KiB native packed values,512reads/16effects per invocation,
48KiB extension values,8,192 lifetime keys and32,768native operations. The
accepted1,000source/20MiB/10,000chunk/5,000entity/20,000assertion target is not
reduced. No Core/native or dependency addition is proposed here.

## Explicit format selection and compatibility

Add a distinct public `generation_job` action, `finalize_paged`. It may start
only from a complete version-one captured job in `manifests`, before any
version-one directory reduction, or continue its own version-three job. The
existing `finalize` action and Job version two retain their exact version-one
directory behavior. There is no automatic conversion or fallback when a
version-one job reaches a budget refusal. An operator can explicitly abort and
rebuild using the new action. A mismatched action/job recipe refuses.

Keep Source/chunk/citation, vector, fact, shared group and captured-summary
formats and identities unchanged. Existing version-one roots/pages retain
exact byte and canonical-regeneration compatibility. New readers accept both
root versions; old readers explicitly refuse version two. The selected root
continues to switch at the same `generation.<partition>` key, only in the final
root/job/catalog CAS. A current version-one selection remains readable until
that switch.

Version-two roots use `version:2` and recipe
`ipse.evidence.shared_directory.v2`. Existing source-head and model/catalog
bindings remain. Remove the version-one `entity_rows_sha256` field: do not
reinterpret or falsely preserve its flat canonical-row digest. Add
`entity_page_rows:32` and `entity_pages_sha256`. Define that digest with the
existing canonical SHA adapter over the exact closed object:

```elixir
%{"version" => 2, "kind" => "ordered_entity_pages",
  "recipe" => "ipse.evidence.shared_directory.v2",
  "entities" => total_entities, "groups" => total_groups,
  "page_rows" => 32, "pages" => exact_ordered_page_references}
```

Each reference binds exact content key, SHA256 and byte count. The external
expected root digest still authenticates the entire closed root and its exact
catalog hash/generation/floor, generation number and vector/fact selection.
The commitment is a page-set commitment, not a flat row hash, inference receipt
or later-use authority seal.

## Bounded production and semantic verification

Manifest batches remain at most16captured summaries, authenticated against
their exact ordered captured catalog pages and source heads. Their source-head
digest remains the existing flat canonical digest: eight small manifest pages
fit its bounded read pass. Manifest pages remain version one; version-two root
validation explicitly requires that page recipe.

Entity occurrence runs and merged entity pages use explicit version-two
page/run recipes with at most32rows. A run directory contains at most157refs;
at most eight run directories are held by a merge checkpoint. Each merge reads
only the needed head pages, validates exact hashes/ordinals/cardinality, merges
identities once, requires equal labels for duplicate identities, unions exact
sorted memberships, and emits one32-row page. No label, membership or warning
is truncated. Input position cursors are durable private job fields, never
caller continuation fields.

After merge, verify entity pages one per durable job step. Each step loads the
exact next page at the invocation's fixed native generation and validates:

- Exact version/recipe/kind, ordinal and32rows except the exact final remainder.
- Complete ordered unique entity identities, legal labels and canonical ID
  regeneration, nonempty sorted unique memberships in0..groups-1.
- The first identity is strictly greater than the previous verified page's last
  identity, and the cumulative row count cannot exceed the declared total.
- Exact page reference key/hash/size and binding to the ordered page commitment,
  selected job, captured catalog/floor and common model/extraction selectors.

The durable version-three job adds a closed reduction recipe discriminator,
`digest_cursor`, `verified_entities` and `last_entity_id`. The initial values are
zero/zero/nil. Each known atomic job/catalog update advances by exactly one
semantically validated page. Only the exact final cursor and entity count may
enter selection. No OTP NIF hash context is serialized and no custom SHA
implementation is introduced.

## Checkpoints, interruption and final selection

The untrusted continuation remains only the existing closed job ID, physical
job/root revisions, captured catalog hash, plan hash, bounded unit index,
current write checkpoint and sealed-stage refs. It never supplies reduction
cursors, validation counts, page lists or a claimed semantic verdict. Every
resume reconstructs the phase from the current stored job and reloads/rechecks
its semantic input before preparing or verifying metadata, including edited
tokens at the first metadata unit, later metadata units and direct finish.
The plan digest binds the exact resulting job, catalog and immutable units.

This distinction is required: a final `value.stat` showing a hash exists is not
semantic page validation. Each page must pass the code path above before a
known durable cursor advance. An edited private unit index must not skip it.
Stored job rows have the existing cooperative operator-approved Collection
trust boundary; they are not new host attestations of worker behavior. This
design adds no fake cryptographic authority to arbitrary stored JSON.

Unknown or inconsistent outcomes stop without a continuation or retry. Resume
can inspect durable state, but does not replay an interrupted write. A staged
metadata value must match its exact expected job phase, input-derived body,
target/revision, complete hash/size and owned slot/epoch. Check current
catalog/root/job bindings at startup and preserve their expected revisions.
Final selection retains the existing exact sealed-stage verification and
native-generation-pinned `value_commit_at` path for three metadata values.
It verifies existence/full hashes of all selected manifest/entity pages at
the final stage epoch without presenting those stats as semantic proof. Old
selection persists until that single CAS. Concurrent catalog/floor/root/job
change refuses; owner loss retains unknown/no replay.

## Size, work and required controls

At5,000entities,157entity pages plus eight manifests produce165references.
Thirty-two worst-label rows with all125memberships measured31,181body bytes
and47,547packed native bytes, below48KiB/64KiB. Root/job sizing must be checked
with the maximum16-byte partition, full63-page catalog, all165selected refs,
eight active run refs and all checkpoint fields before implementation is
accepted. No complete root/job object is sent through one SDK host-call
envelope: existing value byte staging and SDK2 result publication handle their
bounded private assembly and public projection.

Required focused controls before actual publication qualification:

- Exact v1 canonical/reader roundtrip remains unchanged; old reader rejectsv2.
- Maximum labels/125memberships,157pages and maximum partition/root/job/native
  wrappers stay bounded; count actual escaped replies and every emitted frame.
- Missing/reordered/duplicate/forged pages and memberships, cross-page duplicate
  IDs, skipped or altered cursor, stale catalog/floor/selection, and edited
  first/later/direct-finish metadata unit all refuse before a proposed effect.
- Resuming a known partial write retains exact semantic input; unknown never
  replays. Actual native/public final CAS preserves old selection and refuses
  stale generations, as the version-one control does.
- Exact extra durable-step operations, run/proof/staged keys and retained
  old/new bytes must join the full build/rebuild/GC/migration ledger. A bounded
  per-step pass is not populated-capacity or full-peak acceptance.

The collection SDK/native backend is reused unchanged. Elixir/OTP `:crypto`
and existing JSON/SHA adapters supply hashing; new code belongs to extension
directory/reduction policy, not common protocol machinery or a workflow
framework. Safe run/job reclamation, selected-root floors, lifetime-key reuse,
migration and the populated workload remain required subsequent sections.
