# Public Corpus document Collection routes — 2026-10-28

This component connects the [packed selected-source adapter](document-store-adapter.md)
to ordinary public Corpus commands. It does not qualify P31C1b/F. Namespace lexical
selection, the accepted 1,000-source / 20 MiB / 10,000-chunk / 5,000-entity /
20,000-assertion / 256 MiB profile, rebuild/migration and representative ordinary
Word packages remain required. The [plan](../../plan.md) owns milestone acceptance.

## Public selection and authority

The separately selected `corpus/collection-documents` preset grants the existing
`host.actions`, `host.actions.mixed`, `host.collection.store` and `host.tools`
capabilities. Existing presets retain their existing capability lists and exports.
The new [options example](../../../extensions/knowledge/options/corpus-collection.json)
selects a project Collection store and BM25 retrieval. Operator configuration
requires the explicit `documents` / `document_graph_v1` Collection binding; the
operator generator emits it and refuses a State binding for this preset. Existing
project identity admission, full normal approval arguments and sandbox/file
identity checks remain in force. No inference, shell or saved-consent grant is
added.

Public `source` supports `put`, `put_document` and approved workspace
`read_document` through this backend. Ready results contain an explicit next
command: provided input is resupplied by `continue_collection_source`; a workspace
file is reacquired by `continue_collection_document` with its complete original
hash pinned. The initial host acquisition receipt remains bound into the complete
source plan and final citation across later reacquisition. Acquisition checks the
complete original bytes, paged identity and final complete hash before storage.

`query_selected` accepts one to eight explicit source IDs. It authenticates each
complete source closure, runs existing Evidence ranking/query-scope validation,
returns typed segment-local citations and preserves partial-extraction warnings.
Coverage says `namespace_complete: false`. Ordinary `query` refuses
`collection_namespace_index_unavailable`; this selected command is not a full
namespace search implementation. Unsupported lifecycle/index operations refuse
explicitly rather than falling through to a State snapshot.

## Bounded continuation changes

Checkpoint version two can pause inside an active native stage. Its active ref
records exact slot, epoch, target, physical revision, body hash/count, known
appended offset and state. The extension derives the next offset only after a
known successful append. It re-inspects the exact owned stage before continuation;
forged or stale offsets cannot skip or overwrite a native prefix. Workspace reads
and storage mutations share the existing 16-effect invocation budget. Read-only
slot allocation chooses an unoccupied one of the existing 16 slots; it does not
silently reclaim expired foreign work.

New source-data objects are version two and bind the complete ordered bundle
hash and block ordinal, including the original acquisition receipt. This makes a
returned active stage or already published data prefix an authenticated witness
of the opening plan. The reader still accepts stored version-one data objects.
Pending version-one adapter checkpoints refuse rather than silently changing their
meaning. Existing Evidence Source version-one text compatibility and Source
two typed metadata validation remain intact.

Selection still occurs only at the final atomic source/catalog CAS. Unknown or
interrupted effects produce no new ready command and never replay automatically.
The complete source and typed metadata are privately reconstructed across bounded
host replies; no SDK object, string, depth or generic result limit is widened.
Current original-package acquisition remains 32 KiB, extracted text 64 KiB,
32 chunks and typed metadata 16 KiB. These are intermediate component limits,
not the accepted full storage or ordinary Word profile.

## Focused actual Session evidence

All controls build the ordinary public artifact, use independent workers, actual
Session transport and native Collection on isolated `/tmp` tmpfs homes. Build
artifacts stay under repository `_build` on Btrfs. The unchanged frozen helper
admits exact available-host Linux 7.2.11 tmpfs; production admission and repository
Btrfs support are not widened.

- [46816](corpus-collection-documents/public-46816.log): two passed. A 32-paragraph
  DOCX larger than one native reply pauses within the shared effect budget, resumes
  and yields exact paragraph-32 evidence with original hash, opening acquisition
  and partial warning. Provided-source continuation and citation also pass; old
  document preset capabilities/exports remain unchanged.
- [46817](corpus-collection-documents/public-refusal-46817.log): two passed.
  Enhanced Word control refuses an active-offset forgery, changed workspace file
  and forged opening acquisition receipt without further storage mutations. It
  still completes the original ready command after explicit fixture restoration.
  The generated operator grant control passes. An avoidable compile warning from
  statically referencing the dynamically loaded build helper is retained here;
  the test uses explicit dynamic dispatch in the final source.
- [46818](corpus-collection-documents/public-unknown-46818.log): two passed without
  diagnostics. The final generator control validates the exact fixed Collection
  binding and rejects a State binding. Actual public continuation is killed after
  native append but before action-result commit. Its last durable record remains
  intent; inert Session reopening leaves both journal and retained files unchanged.
  It produces no replayed read, append or ready command.

The [manifest](corpus-collection-documents/manifest.json) binds 13 source files,
three logs, helper and all 207 tested host BEAMs. Those host BEAMs are unchanged
from the adapter evidence. Source snapshots are frozen separately under
`_build/corpus-collection-documents-20261028/sources`. No BEAM is archived here.

The synthetic DOCX fixtures do not establish installed Word quality or ordinary
package-size support. These NoModel controls contain no inherited managed inputs;
`collection.store` integration with the generic managed-derived input actual-use
gate remains separately required. Full namespace lexical indexing/global
statistics, graph/vector selection, lifecycle collection, logical counter audit,
rebuild/migration/floor transfer and populated capacity/peak-allocation measurements
remain open.
