# Catalog-bound namespace lexical index — 2026-10-29

This component extends the [public Corpus routes](corpus-collection-documents.md)
and [lossless source runs](source-lexical-runs.md) with ordinary namespace queries.
It is not P31C1b/F acceptance. The [plan](../../plan.md) remains authoritative.
Populated capacity, rebuild peaks/retention, graph/vector population, migration,
source lifecycle collection, later actual-use admission, representative Word and
performance qualification remain required.

## Namespace producer and publication

The Collection preset adds the public `lexical_index` command/tool with explicit
`begin`, `next`, `inspect` and `abort` actions. Existing presets keep their grants
and exports. A build captures the complete current source catalog hash, logical
generation and floor, plus the expected current index revision. Its protected
job has one exact revision; every ready continuation binds that job and revision.
It does not silently join or replace another active job. Inspection returns
status and progress, not a fabricated ready command. Abort leaves the selected
index and sources intact.

A bounded group contains at most eight catalog-selected sources. The builder
hydrates those complete sources and their committed lexical runs, verifies source
bundle hashes and recomputes every run before deriving lossless term-frequency
postings. It preserves exact chunk token lengths and source time-selection data.
It sorts terms, splits postings into bounded semantic JSON pages, and packs
several pages into existing immutable values no larger than 48 KiB. Run headers
carry ordered page ordinals, term bounds, offsets, raw byte counts/hashes and
complete physical-object hashes. No term, posting, warning metadata or source is
silently dropped to fit an envelope.

Index checkpoint version two advances immutable units with exact existing-value
witnesses. A forged skipped unit must already exist with the recomputed complete
body hash/count; missing units refuse. Durable job progress advances once a whole
source group is prepared. This avoids rewriting the growing job after every
packed object and preserves the existing operation ledger. Active append offsets
still advance only after known success. Unknown effects produce no new ready
command and never replay automatically.

Final publication seals the index root and an unchanged copy of the captured
source catalog. One existing two-ref Collection commit consumes both stages and
selects them atomically. The catalog's physical revision is therefore checked
inside publication even when its logical body is unchanged. Root/catalog stage
ownership, targets, revisions, complete raw hashes/counts and completion offsets
are checked before selection. A changed catalog or index refuses; an older
selected index remains in place. The no-op catalog CAS leaves its logical
hash/generation/floor unchanged, but can make a concurrently prepared source put
conflict on its old physical base. The caller must inspect that refusal; there is
no automatic rebase or replay. Builds also refuse a catalog generation/floor
regression rather than treating a rolled-back source store as a fresh index.

## Ordinary queries and bounded transport

Ordinary Corpus `query` now uses this index for the separately selected Collection
preset. `query_selected` remains available. A namespace query checks the selected
index's exact current catalog hash/floor, reads authenticated run directories,
then reads only matching posting pages through existing `value.read`. A page ref
binds its raw offset/count/hash and the complete host-read object's hash. This
allows bounded partial reads without decoding or sending a whole packed value.
The worker verifies page ordinals, term ranges, local source/chunk bounds and
unique postings before using their statistics.

The query computes eligible global chunk count, average token length and exact
term document frequencies from committed metadata and postings. It selects the
highest scoring chunks, hydrates only those sources and verifies their complete
bundles, generations and content hashes. Evidence independently recomputes final
chunk frequencies/lengths and BM25 scores before producing exact citations. A
final current catalog check rejects intervening source selection changes.
Expired, future and historical sources are excluded explicitly. Selected partial
Word sources retain their full warnings; other eligible partial sources retain
an explicit source warning count/digest gap. The complete extraction metadata
remains stored and available through selected-source retrieval.

Coverage distinguishes indexed, eligible and hydrated populations. A successful
logical namespace search may say `namespace_complete: true`, while
`population_qualified: false` remains explicit. Partial extraction still produces
partial status. This is not a full-capacity or semantic-quality assertion.

Every SDK object, string, array and depth limit remains unchanged, as do 512 reads,
16 effects, the 8,192 live-record bound and 32,768 operation ledger. The small
internal adapter operations reuse the existing closed host read/stage/commit
protocol; they add no host fields, path/profile/quota knobs or workspace authority.
The worker uses ordinary Elixir maps/lists and existing JSON primitives. OTP and
Mix provide the required sorting, processes and bounded encoding; no dependency
or workflow framework was introduced. The domain-specific byte-offset container
is necessary because JSON encoders do not return authenticated inner-page offsets.

## Focused evidence and retained failures

All native controls use actual Sessions and workers, normal approvals and isolated
`/tmp` tmpfs homes. Build artifacts stay under repository `_build` on Btrfs. The
same frozen helper admits exact available-host Linux 7.2.11 tmpfs; production
kernel admission, repository Btrfs, the latest other-agent core cohort and later
managed-input/output reuse are not qualified here.

- [46828](namespace-lexical-index/namespace-public-46828.log): the ordinary public
  artifact acquired a 32-paragraph Word document, continued staged storage,
  built the namespace index through ready commands and queried it through normal
  `query`. Exact paragraph-32 citation, original acquisition and partial warnings
  passed. This case took 22.3 seconds including build/setup and ingestion.
- [46830](namespace-lexical-index/namespace-groups-46830.log): a nine-source native
  fixture crosses two index groups. Actual Session build/query returns exactly
  the full-source reference BM25 citations and scores, excludes the expired
  source, and hydrates three sources in 35 host reads. Index construction added
  35 native operations and six live records; allocation changed 143,360 to
  167,936 bytes. Fixture seeding is explicitly direct native setup, not public
  bulk-ingestion evidence. Before/after allocation is not peak measurement.
- [46831](namespace-lexical-index/namespace-negative-46831.log): two passed.
  Multiple semantic pages use actual nonzero host offsets. Missing physical data,
  rehashed reordered directory refs and forged offsets refuse; selected-source
  evidence remains available independently of a missing index object. A lower
  source floor refuses rebuilding. A separate actual Session control changes the
  catalog's physical revision, with identical logical bytes, just before final
  publication's fresh snapshot. The new index refuses; the old root stays byte
  identical and its namespace query remains current. This isolates the catalog
  revision guard from merely rejecting an old native snapshot generation.
- [46832](namespace-lexical-index/namespace-unknown-46832.log): actual native final
  publication completed, then the owner was killed before its action-result
  receipt. The last durable record stays intent. Inert Session reopening leaves
  files/journal byte identical and performs no replay or fabricated continuation.
  The possibly completed store effect is observed explicitly, not denied.
- [46825](namespace-lexical-index/namespace-smoke-46825.log) and the component case
  in [46827](namespace-lexical-index/namespace-public-46827.log) cover initial
  global ranking, as-of eligibility, stale catalog refusal and explicit rebuild.
  Checkpoint batching reduced the two-source first-index cost from 27 to 23
  native operations, with four added live records.

First failures remain visible. The initial compile command typo and ungrouped
function warning are in the compile logs. [46826](namespace-lexical-index/namespace-public-46826.log)
failed compiling a misplaced test variable. The public setup case in 46827 found
an undefined ready helper in the new route; the route now uses the existing ready
map contract. [46829](namespace-lexical-index/namespace-groups-46829.log) failed
fixture identity lookup because prepending an `ipse-*` artifact directory shadowed
`Application.app_dir(:ipse)`; the fixture now loads its exact Evidence BEAM without
changing application code paths. None of these failures lowered acceptance targets.

The [manifest](namespace-lexical-index/manifest.json) freezes eight sources, eleven
logs, the helper and unchanged 207 host BEAM hashes. Exact source snapshots and
ten actually tested fixture BEAMs remain under `_build/namespace-lexical-20261028`;
the retained artifact manifest hash is recorded. No BEAM is archived here.

## Required capacity and compatibility increments

The current 2,048-byte chunk recipe cannot simultaneously populate 20 MiB and
10,000 chunks: those chunks cover at most 20,480,000 bytes, 491,520 bytes below
20,971,520. Small ordinary paragraph separators do not bridge that gap. A separately
versioned Collection chunk recipe is the next required implementation; old source
and chunk identities must remain unchanged. The target must not be reduced.

The subsequent populated workload must measure the entire notes-inclusive envelope,
old and staged index/vector/graph generations, operation retention, logical counters
and allocation peaks. These small controls do not establish those results. Legacy
sources without lexical metadata refuse indexing; explicit migration and floor
transfer remain required. Immutable object collection and expired-stage cleanup
need their public lifecycle path; no idle/disabled background IO is introduced.
Original Word acquisition above 32 KiB and representative package quality remain
open. Exact current-source query checks here do not qualify later provider use
or the separately reviewed managed-derived input gate for `collection.store`.
