# Packed vector projection component — 2026-10-29

This historical receipt follows [bounded inline publication](inline-document-publication.md)
and the [namespace lexical index](namespace-lexical-index.md). The
[plan](../../plan.md), [Corpus manual](../../operator/corpus.md) and
[developer manual](../../developer/knowledge-extensions.md) remain authoritative.
This is a storage/hydration prerequisite, not full P31C1b/F, populated capacity,
namespace vector search, model quality or managed later-use acceptance.

`Store.Collection` now exposes internal `vector_store` and `vector_selected`
operations through its `Projection` adapter. Extension callers supply vectors;
there is no new model service, public Corpus export, provider selection, authority
grant or saved-consent reuse. Existing Evidence validation checks canonical finite
nonzero float32 values, dimensions, complete chunk order and each chunk's exact
input digest. The manifest retains exact profile/model/dimensions/encoding and
selection hash, the storage recipe, source generation/content/full-bundle digest,
and captured catalog hash/generation/floor. Source and chunk identities are not
rewritten. Source versions one, two and three use their existing chunk recipes.

Pages retain original little-endian float32 bytes as canonical base64 pieces of
at most 4,096 raw/5,464 encoded bytes. A 1,024-dimensional vector uses one piece;
4,096 dimensions use four. Pages are at most 48 KiB and carry complete ordered
rows, source-bundle binding and ordinal. References bind complete raw page counts
and hashes. This avoids large JSON float arrays crossing one SDK result and adds
no generic protocol ceiling. Complete source and vector-page assembly is private
inside the extension; a public consumer must return a bounded projection.

One explicit continuation writes one immutable value, with existing bounded
append continuation when required. Tokens carry the complete recomputed manifest
hash, catalog/root physical revisions, unit, prepared refs and active write.
Skipped pages require exact existing-value witnesses; prepared metadata requires
the owned session/epoch/target/revision/hash/count and sealed completion proof.
One existing two-ref CAS consumes the projection root and unchanged captured
source catalog. The old selected projection remains readable during preparation.
The catalog's physical revision is checked inside the final CAS, including a
same-body catalog publication after the last stage inspections. Unknown effects
produce no new ready continuation and never replay on resume.

Selected hydration authenticates the complete ordered pages and regenerates the
canonical packed representation after checking every source/chunk/input/model
binding. It rechecks the catalog after hydration. Missing, reordered, rehashed
wrong-chunk pages, changed model selection, stale catalogs and floor regression
refuse. Complete document metadata and partial-extraction warnings remain in the
returned private source; this adapter does not manufacture a complete-document
claim. Its coverage explicitly declines population, quality and namespace claims.

The implementation reuses OTP binary/base64 operations, existing Evidence
validation and the Collection read/stage/CAS adapter. No dependency or common
workflow framework was added. The per-source packed representation is necessary
to retain exact float32 identity within existing SDK strings. Global projection
generation selection, graph population, migration, collection and peak/operation
preflight remain separate required work.

## Focused evidence

- `46843` retained the first failed attempt: the synthetic producer supplied a
  derived `encoding` field to the existing `Evidence.vector` constructor, whose
  closed input excludes that field. The producer was corrected; numeric
  validation was unchanged. The test's dynamic module load/JSON encoder spelling
  were corrected before the passing run.
- `46844`: two controls passed in 63.5 s. Thirty-two complete chunks round-trip at
  1,024 and 4,096 dimensions; missing/reversed pages, wrong order, bad numeric input
  and forged vector hashes refuse. An actual Session stored eleven vectors in two
  pages, returned a source-local exact citation, retained old hashes during every
  replacement step, selected the new revision atomically, and refused another
  model selection. Selected hydration stayed below 64 host reads.
- `46845`: the actual queued final-publication catalog race passed. Two fixture
  failures were retained: a proposed floor rollback was initially a no-op because
  the seed floor was already zero, and a third identical main-VM module load hit
  the BEAM two-version limit. The fixture now establishes floor one and reuses its
  already loaded exact artifact.
- `46846`: both corrected controls passed in 42.6 s. Actual Session hydration
  refused a missing page, reversed manifest pages and a rehashed wrong-chunk page;
  restored data read correctly; catalog floor rollback refused read and rebuild.
  Killing the actual owner after final native root CAS but before its receipt
  preserved the intent. Inert resume changed neither journal nor native status.
- The current `corpus/collection-documents` artifact built without diagnostics.
  Its public exports/capabilities remain unchanged by this internal adapter.

The eleven-vector fixture observed forty native mutations for two complete
projection generations plus one direct native source-seed operation: 41 total,
10 live records and 204,800 allocated bytes afterward. These are fixture counts,
not populated-profile or peak measurements. Old immutable pages remain retained;
this is not garbage-collection or all-profile atomic-rebuild qualification.

The [manifest](packed-vector-projections/manifest.json) pins source snapshots,
logs, exact tested worker artifacts and unchanged host/helper evidence. Native
fixtures run in isolated actual `/tmp` tmpfs homes; build artifacts remain in
repository `_build` on Btrfs. Linux 7.2.11 private diagnostic helper admission is
not production profile admission. No embeddings, paid/live inference, installed
Word, semantic quality or real document corpus was exercised.
