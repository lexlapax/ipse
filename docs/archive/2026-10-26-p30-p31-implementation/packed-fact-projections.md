# Packed cited-fact projections and operation preflight — 2026-10-29

This historical component extends [packed vector projections](packed-vector-projections.md).
The [plan](../../plan.md), [Graph manual](../../operator/graph.md) and
[developer manual](../../developer/knowledge-extensions.md) remain authoritative.
Full P31C1b/F, populated capacity, global graph catalog/traversal, rebuild,
migration/collection, actual-use authority and model quality remain open.

The same Collection Projection adapter now exposes internal `fact_store` and
`fact_selected` operations. It reuses the vector component's source hydration,
manifest-bound explicit continuation, immutable-value witnesses, owned prepared
stages and final root-plus-captured-catalog CAS. The version-one vector root,
selection, recipe and numeric representation remain unchanged. Existing Source,
chunk and citation versions retain their identities. No public Graph or Corpus
export, model inference route, capability or consent grant was added.

Fact packing first applies existing Evidence fact validation and checks every
citation against the complete selected source. Each source-local projection has
up to 32 distinct fact IDs and at most 64 exact subject/object labels. Entity IDs
derive from partition and exact label; there is no alias or semantic-equivalence
claim. Compact ordered pages retain the complete predicate, polarity, inference
flag, time fields, extraction identity and fact ID. Citations retain their exact
chunk ordinal, source byte span and quote digest. Hydration regenerates complete
citations, including typed Word locators, from the authenticated source, and
checks original fact IDs and a complete canonical repack. It does not invent or
truncate quotes or discard partial-extraction warnings.

Pages remain at most 48 KiB and the complete manifest binds source bundle,
generation/content, extraction selection, ordered page counts/hashes, exact local
entity IDs and captured source-catalog hash/generation/floor. One native CAS
selects the root and unchanged source catalog. Old facts remain selected during
preparation; stale/queued writers and unknown effects retain the same refusal
and no-replay behavior as vectors. Private hydration returns the original facts
and complete source to the extension. Global entity counting, traversal/time
filtering and bounded public query projection are later integration work.
Per-source entity/assertion counts do not qualify the global 5,000/20,000 target.

The implementation uses existing Evidence validation, JSON, OTP collection/binary
operations and Collection staging. Its compact citation representation is domain
data, not a new workflow framework or generic validation system. No dependency
or SDK/native ceiling was increased.

## Focused controls

`46847` passed two actual Session controls in 73.3 s. Twenty facts preserved exact
Word paragraph-one citations and full partial-extraction warnings. Old fact IDs
remained readable after every replacement preparation. The selected revision
changed atomically, another extraction selection refused, and a rehashed page
with a changed citation span refused. The control also stored/read a vector
through the generalized adapter and checked the unchanged version-one root field
set and recipe. A separate owner-loss control killed the actual Session after
native fact-root CAS but before its receipt; inert resume changed neither journal
nor native status. Two complete fact generations cost eight native mutations;
the deliberate corruption added one more, for nine between the recorded status
samples. Before/after allocation was 77,824/118,784 bytes, not a peak measurement.

`46848` passed two focused controls in 31.8 s. The actual final fact publication
paused after both owned-stage inspections but before its fresh commit snapshot.
A same-body native catalog publication changed its physical revision. The final
CAS refused, the old fact root remained byte-identical and readable. The other
control rebuilt the portable historical Source consumer from archived source,
explicitly granted its separate artifact identity, read retained legacy data and
refused the newer Source representation. This is compatibility evidence, not
permission to reuse an old live approval or artifact identity.

## Why a populated run still cannot begin

The new finite Elixir development probe
[`collection_profile_operations.exs`](../../../dev/knowledge/collection_profile_operations.exs)
verifies an explicitly supplied locally built fixture artifact's hashes. It
constructs two complete synthetic Word geometries and uses the current Collection
prepared bodies and Projection packers. It validates actual encoded SDK frames
and counts mandatory fresh immutable-value mutations. Metadata is conservatively
counted at its minimum: four mutations per source and three per projection.
The probe performs **zero native storage operations**, inference, acquisition or
publication; it is a dry refusal proof, not a capacity benchmark or Word quality
qualification.

The required weighted geometry is unchanged:
252 × 20,979 + 748 × 20,969 = 20,971,520 extracted bytes, with 1,000 sources,
10,000 chunks, 10,000 1,024-dimensional vectors, 5,000 source-distinct entity labels
and 20,000 assertions. The current recipe requires at least:

| Work per source | Native mutation minimum |
| --- | ---: |
| Source and source lexical run plus selection | 13 |
| Two packed vector values plus selection | 19 |
| One compact twenty-fact value plus selection | 4 |
| Total | 36 |

The **36,000 initial mutation minimum already exceeds 32,768**. It excludes the
namespace lexical index, global graph catalog/index, rebuild, migration,
collection, retention and notes. Its largest checked host frame was 9,070 bytes;
this is an operation-ledger problem even though SDK framing is bounded. Both
source geometries have the same cost. The raw source values are 24,587/24,577
bytes, requiring five bounded append mutations apiece. The vector values are
45,974 and 11,636 bytes, requiring eight and two append mutations.

The output therefore says `preflight: refused` and `profile_qualified: false`.
Do not populate a reduced fixture, seed native objects around these routes or
raise the ledger ceiling and call the complete recipe qualified. A future bounded
transport change must reduce the actual measured initial/rebuild recipe first.

Existing generic migration also remains insufficient: its descriptor still has
a 24-MiB data bound, and migration preserves imported/live operation receipts.
Copying to another store does not automatically reset the 32,768-operation
ledger. Source suppression/floor lineage, old+staged space, complete export,
writer fencing and rollback safety require an explicit document-profile recipe.

The [manifest](packed-fact-projections/manifest.json) pins sources, exact logs,
probe output/source, tested artifact and unchanged host/helper hashes. Generated
BEAMs remain under `_build`; native fixtures use actual isolated `/tmp` tmpfs.
The private Linux 7.2.11 diagnostic helper is not production kernel admission.
