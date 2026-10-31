# Lossless source lexical runs — 2026-10-28

This component follows the [public Collection Corpus routes](corpus-collection-documents.md)
and prepares exact inputs for a future namespace index. It does not implement
namespace selection or complete P31C1b/F. The [plan](../../plan.md) remains the
acceptance authority; the complete populated storage profile, global lexical
index, graph/vector selection, rebuild, migration and representative Word
qualification remain required.

## Exact producer and stored binding

Evidence exposes the existing Unicode letter/number and lowercase tokenizer as
recipe `ipse.evidence.word_tokens.v1`. It derives a lossless sorted run containing
all normalized terms, each term's ordered chunk-local frequency, every exact
chunk ID/range/token count, source/content/generation binding and the existing
observed/expiry/historical time-selection metadata. It does not truncate terms,
postings or lengths. Validation rejects a changed recipe, invalid or unordered
terms/postings/chunks, duplicate rows, invalid local references, inconsistent
aggregate frequencies and chunk IDs that do not recompute from the exact source
key, generation, content hash and range. An empty token vocabulary is valid for
an otherwise valid punctuation-only source.

Store.Collection privately serializes this run and uses its existing immutable
48 KiB object packing, fixed native stage slots and bounded append/seal/publication
path. Source-lexical objects bind the complete source bundle hash, complete run
hash and exact block ordinal. A source-head version two binds ordered run object
refs, complete raw run count/hash, content hash and tokenizer recipe. The existing
final three-ref source/catalog CAS selects the new source and its run together;
new run objects remain unselected during preparation. All data and prior metadata
stages are rechecked before that selection. Checkpoint version three distinguishes
these additional immutable units. A pending version-two checkpoint refuses before
storage work rather than silently changing its unit interpretation.

Stored source-head version one and existing source-data versions remain readable
by ordinary selected-source retrieval. An old head without a lexical run refuses
a run request; no index is fabricated and no implicit migration occurs. Replacing
an older source uses the existing explicit source generation/revision CAS.

The private `lexical` adapter operation accepts a bounded explicit source selection,
authenticates the catalog/head and every ordered run object, checks complete raw
hash/count and run validation, then rechecks the pinned catalog generation.
Its coverage marks `evidence_readable: false` and
`cache_scope: source_lexical_preparation`. It does not produce citations, apply an
as-of eligibility decision or claim namespace completeness. A later global index
must evaluate the committed time metadata and hydrate/validate final evidence.

Runs may contain more than 4,096 terms internally. They are assembled from bounded
JSON strings inside the extension; they are not inserted into a generic SDK
object or published as one oversized array. The host SDK/string/depth/collection
limits, 16-effect and 512-read invocation limits, native 8,192 index and 32,768
operation bounds and existing store quotas are unchanged. The finite private run
and block guards are resource refusals, not populated profile qualification.

## Focused controls and retained failures

All native controls use actual independent workers, Session transport, normal
approvals and isolated `/tmp` tmpfs homes with the same frozen available-host
helper. Builds stay under `_build` on repository Btrfs. No production admission,
filesystem authority, external dependency or generic SDK limit changes.

- [46824](source-lexical-runs/lexical-final-46824.log): two passed in 41.4 seconds.
  The exact Unicode recipe control checks frequencies, empty vocabulary and
  malformed bindings/order/counts. The actual Session control writes a source,
  then replaces it with a Word source producing more than 6,000 exact terms and
  multiple native run objects. Every intermediate stage still reads the old run;
  final publication selects revision two. Missing run data refuses. Reordered
  run refs refuse even after outer head/catalog hashes are consistently recomputed.
  Explicit conversion to a retained legacy head still yields ordinary exact
  Word evidence and refuses its absent lexical run. A version-two pending
  checkpoint refuses, and saved reconstruction validates the resulting journal.
- [46822](source-lexical-runs/lexical-public-46822.log): one public Corpus
  regression passed in 13.1 seconds after checkpoint version three and derived
  chunk-ID validation. Approved acquisition, paused storage, changed-file/forged
  continuation refusal and exact typed citation still work. Subsequent selection
  metadata additions are covered by final 46824; no second public workload is
  claimed for those additions.
- [46821](source-lexical-runs/lexical-run-46821.log): the preceding actual Session
  version passed after fixing the fixture's output projection.
- [46819](source-lexical-runs/lexical-run-46819.log) retains the first failure:
  the test fixture attempted to publish the entire run's more-than-4,096-entry
  term array through ResultPublication. Existing complete-result validation refused
  that fixture projection after read-only run assembly. The fixture now returns
  a bounded summary; full runs remain private. No host limit was raised.
- Earlier [46820](source-lexical-runs/lexical-recipe-46820.log) and
  [46823](source-lexical-runs/lexical-recipe-46823.log) retain focused recipe checks.

The [manifest](source-lexical-runs/manifest.json) pins six source files and six logs,
plus the unchanged helper and 207 host BEAM hashes from the public-route boundary.
Exact source snapshots are retained separately under
`_build/source-lexical-20261028/sources`. No BEAM is archived here.

## Required global index and capacity work

A namespace index still needs bounded generation-scoped merge/rebuild of these
sorted runs, packed exact term dictionaries/postings, global eligible chunk-length
and document-frequency statistics, authenticated candidate selection and selective
final-source hydration. Its published root must bind the catalog generation/floor
and recipe, reject stale generations and preserve the old index until complete
new publication. A Bloom-only filter or explicit source-ID query is not that index.

The complete workload must measure native operation/index retention and peak
allocation, including old and staged index/vector generations and graph data.
Packing runs does not prove that 1,000 source puts plus rebuild fit the existing
operation ledger, nor does the 192 MiB document backend ceiling prove the accepted
256 MiB notes-inclusive populated profile. Explicit reclamation/floor transfer,
full logical counter audits, source lifecycle collection and migration remain
open. Workspace acquisition above 32 KiB and installed/representative Word
packages also remain open. Managed-derived input gating of `collection.store`
is a separate host integration requirement; these NoModel controls contain none.
