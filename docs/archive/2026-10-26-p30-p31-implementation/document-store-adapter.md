# Packed selected-source Collection adapter — 2026-10-28

This is the first extension adapter increment after the
[document storage boundary](document-store-boundary.md). It is component evidence,
not P31C1b/F completion. The full 1,000-source / 20 MiB / 10,000-chunk /
5,000-entity / 20,000-assertion / 256 MiB profile, namespace lexical index,
graph/vector selection, rebuild, migration and installed Word qualification remain
required. The [plan](../../plan.md) remains authoritative.

## Implemented selection and packing

`IpseKnowledge.Store.Collection` stores complete validated Evidence sources through
the explicit operator-bound `collection.store` API. It serializes each complete
source privately, splits UTF-8 bytes into bounded pieces and packs those pieces
into content-addressed data objects of at most 48 KiB. Every host request/reply
retains the existing SDK object/string/depth limits. Full text and hydrated typed
metadata never pass through one oversized SDK value. Reassembly verifies each
physical object's original byte count/hash and then the complete ordered bundle
count/hash, duplicate-safe JSON, Evidence source/document validity, source key,
partition, generation, text length and chunk count.

The selected representation has a per-source head, catalog pages of 16 sorted
entries, and a catalog head containing ordered page hashes and logical counters.
The declared source/byte/chunk targets remain 1,000 / 20 MiB / 10,000. Entity and
assertion counters are reserved explicitly and remain zero in this increment.
Sources, pages and data use bounded keys beneath the already fixed project
namespace. New physical data is immutable and unselected while prepared.

Each explicit put/continuation prepares one bounded unit. After data is present,
the adapter seals a source head, catalog page and catalog head into three private
stage slots. One final Collection CAS selects all three and consumes their
stages atomically. Until then the previous selected source remains readable.
Logical source revisions and catalog generations are separate from native
staging generations; replacement advances the catalog floor. A continuation
contains only its complete source hash, expected logical revision, catalog base
stamp, unit number and sealed refs. Every resumed unit reconstructs the plan
from the supplied source, rechecks its selected base, and never retries a conflict
or unknown effect. Full data-object stats and all prior stage refs are checked
before metadata preparation and final publication. Interrupted work does not
produce a ready continuation.

The small necessary host additions are read-only `value.stat` and `stage.inspect`.
Stat returns typed absence or exact complete-value byte count/hash/revision.
Inspect reuses the opening stage's project/session/identity checks and deadline;
it cannot reveal another Session's private stage. The extension compares each
sealed target, expected physical revision, raw body hash/count and completion
offset against its reconstructed metadata plan. Neither operation adds a path,
quota, profile, project-admission or saved-consent grant.

`selected` accepts one through eight explicit source IDs. It reads the catalog
head, only each requested source head/catalog page and its complete data closure,
then performs a final pinned-generation catalog stat. It returns private hydrated
sources for the existing Evidence ranking/query-scope functions. Namespace
coverage is explicitly false. The actual Session fixture ranks this selected
set, returns exact Word citations and preserves partial-extraction warnings.
This is not a namespace search substitute.

The ordinary artifact builder now inventories the adapter module. Existing
presets keep their existing grants; an old State document preset still lacks
`host.collection.store`. Public Corpus acquisition/query routing to this new
backend is a subsequent implementation section, as is the full inverted index.

## Focused actual Session controls

The tests use an independently compiled fixture artifact and actual Session,
worker transport, full normal approvals, native Collection publications and saved
reconstruction. They do not wrap a fake State service.

- [46806](document-store-adapter/adapter-46806.log): three passed, one excluded.
  Word text above 8 KiB crosses explicit invocations and yields an exact typed
  citation. Every intermediate replacement still queries generation one; the
  final atomic selection yields generation two. A 24-paragraph document with
  typed metadata above 2 KiB yields paragraph-24 evidence and preserved partial
  warnings. Forged skip continuations refuse. Own-Session stage inspection works;
  a second actual Session receives only a known refusal for the same ref.
- [46805](document-store-adapter/adapter-46805.log): the 17-source catalog page
  crossing and two-ID selective query control passed. It used fewer than 32
  reads for that selection. An independent warning assertion failed because the
  fixture omitted Evidence's existing query-scope function; 46806 repairs that
  fixture omission. The 17-source workload was not repeated after that repair.
- [46807](document-store-adapter/adapter-46807.log): one passed, four excluded.
  A multi-block Word source is selected successfully. Actual queries refuse a
  missing data object, recover after explicit fixture restoration, and refuse
  reordered source blocks even after all outer source/catalog hashes are
  recomputed consistently. Complete original bundle hashing catches the latter.
- [46809](document-store-adapter/adapter-46809.log): one passed, five excluded.
  Actual native port loss during an append becomes a journaled unknown and
  returns no continuation. Saved Session opening performs no callback or write;
  files and journal remain byte-identical. The intentional loss can also report
  cleanup unconfirmed. The fixture records that uncertainty and terminates any
  remaining owner; this is not evidence of confirmed clean native shutdown.
- [Build](document-store-adapter/old-preset-build.log) and
  [inventory](document-store-adapter/old-preset-inventory.log): the ordinary
  `corpus/state-documents` artifact builds without diagnostics, contains the new
  adapter and retains its original capabilities. The new read operations also
  [compile without diagnostics](document-store-adapter/compile-read-ops.log).
  Focused formatting and whitespace checks pass.

Initial setup failure [46803](document-store-adapter/adapter-46803.log) is retained:
the repository is Btrfs, which is unadmitted on this host profile, so a native
ProjectIdentity fixture home there refused. Builds/generated BEAMs remain under
`_build`; explicitly isolated native runtime homes use actual `/tmp` tmpfs. The
same frozen helper admits that exact available-host tmpfs profile. This does not
qualify repository Btrfs or widen production filesystem/kernel admission.

## Frozen provenance and required next sections

The [manifest](document-store-adapter/manifest.json) pins 12 source files, ten
logs, 207 tested host BEAMs and the actual helper hash. Source snapshots and all
generated BEAMs remain under `_build/document-store-adapter-20261028`; no BEAM is
archived here. Its helper matches the first boundary's binary. All 207 first
boundary BEAM hashes were rechecked unchanged before this freeze. Current core
changes in other agents' graphs are not retroactively claimed by this evidence.

The source bundle preserves complete typed extraction metadata, original bytes'
hash and recipe binding. It consumes already supplied/extracted source payloads;
current approved workspace acquisition is still a separate path. Synthetic Word
fixtures do not establish representative Word rendering or an ordinary-file
size profile. Original acquisition above 32 KiB and representative frozen Word
packages remain required next work.

Namespace selection must use a lossless bounded inverted index and global
chunk-length/term-frequency statistics before hydrating final selected sources.
Packing alone does not solve that query. Dense/graph selection needs its own
bounded authenticated index and declared candidate coverage. Physical orphan
collection, ordinary Corpus routing, logical counter audits, explicit staged
rebuild/migration/floor transfer and measured old-plus-staged allocation/operation
ledger retention also remain open. No capacity ceiling, scope label or selected-ID
test changes those acceptance requirements.
