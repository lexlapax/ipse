# Explicit Collection chunking recipe — 2026-10-29

This component follows the [namespace lexical index](namespace-lexical-index.md).
It fixes a capacity geometry conflict without reducing the accepted target. The
[plan](../../plan.md) remains authoritative; this is not populated P31C1b/F,
migration, performance or representative Word qualification.

## Versioned data and unchanged history

New Collection source puts use Source version three with the fixed descriptor
`{"version":2,"max_bytes":4096}`. It is selected by the separately admitted
Collection backend, not by an arbitrary caller chunk-size field. Ordinary legacy
source creation and stored Source versions one/two keep their 2,048-byte recipe.
Reading an existing source never upgrades it. Replacing a source still requires
its exact logical revision and a later source generation.

New chunks use identity recipe two; new citations use version three and carry
the descriptor explicitly. Exact source/text/generation hashes, byte offsets,
quote hashes and original Word/extraction bindings remain intact. Word chunks
remain inside one paragraph/table segment. Full source/citation validation binds
the source's chunking descriptor; a legacy citation cannot be reinterpreted as a
new-recipe citation. Lexical-run version two includes the descriptor and recomputes
chunk IDs accordingly. Run version one remains valid for legacy sources.

DOCX source projection has an explicit recipe selector. State/MCP and ordinary
legacy calls keep recipe one and their existing limits. Collection projection
selects recipe two. UTF-8 chunk counts use actual valid prefix boundaries, rather
than a byte-division approximation. Text, segments, original file hash, extraction
recipe and warnings are unchanged. Source text remains bounded to 64 KiB, source
chunks/segments to 32 and typed metadata to 16 KiB. Original workspace acquisition
remains 32 KiB. Those limits are still intermediate and do not establish full
ordinary Word support.

A complete 4,096-byte normalized token plus posting metadata can exceed a 4-KiB
semantic page. The private index page bound is therefore 6,144 bytes, matching the
existing native read stride. New and old index-page readers remain bounded; the
host SDK stays 16 KiB with 8,192-byte strings and depth twelve. No host/native
protocol, project authority, profile allocation or generic SDK limit is widened.

## Exact capacity arithmetic

The legacy upper bound is `10000 × 2048 = 20,480,000` covered bytes, which is
491,520 bytes short of 20 MiB (`20,971,520`). Ordinary paragraph separators do not
bridge that difference. The accepted byte/chunk target was not reduced.

The focused geometry test parses two actual synthetic DOCX packages containing
ten paragraphs of 2,097 or 2,096 bytes. Their complete extracted text sizes,
including nine separators, are 20,979 and 20,969 bytes. Thus
`252 × 20979 + 748 × 20969 = 20,971,520` bytes. Recipe two produces ten chunks per
source, totaling 10,000; the same paragraphs need twenty legacy chunks per source.
This proves representation arithmetic, not a populated 1,000-source store.

## Focused runtime evidence

- [46833](collection-chunking/chunk-geometry-46833.log): geometry, exact retained
  legacy chunk IDs, legacy citations, new segment-local citations, run versions,
  malformed descriptor refusal and UTF-8 completeness passed. A 65,535-byte
  three-byte-Unicode paragraph remains complete in seventeen new chunks; the
  legacy 32-chunk source envelope refuses it.
- [46834](collection-chunking/chunk-session-46834.log): two actual Session controls
  passed in 42.2 seconds. Retained Source one/Run one and new Source three/Run two
  share a namespace. Legacy evidence stays byte/identity identical. A complete
  4,096-byte token crosses a larger semantic page, still matches the full-source
  BM25 reference, and yields Citation three with exact offsets. The public Word
  route acquires a ten-paragraph DOCX, stages it, builds the namespace index and
  returns ordinary-query evidence with exactly ten indexed chunks, paragraph ten
  and original-byte binding.
- [46837](collection-chunking/chunk-portable-46837.log): the prior consumer is
  compiled from [frozen source fixtures](collection-chunking/legacy-source/README.md)
  whose hashes are checked first. A separate explicit operator grant permits that
  consumer to read retained Source one. It refuses Source three without schema
  reinterpretation. Generated BEAMs remain under `_build`. Earlier passing
  [46836](collection-chunking/chunk-legacy-46836.log) is retained; first failure
  [46835](collection-chunking/chunk-legacy-46835.log) used an invalid atom instead
  of the required operator-scope string in fixture configuration and never opened
  the old reader. That fixture error did not alter the representation design.

The [manifest](collection-chunking/manifest.json) freezes nine current source/test
files, five logs, nine portable historical source fixtures and ten actually tested
current fixture BEAM hashes. The 207 host BEAMs and available-host helper are the
same frozen runtime as the namespace component. Native homes use actual `/tmp`
tmpfs; builds use repository Btrfs. Production kernel/filesystem admission, current
other-agent core changes and later actual-use admission are not qualified here.

## Remaining profile work

The full workload still requires populated document, graph and vector adapters,
operation/index retention and old-plus-staged allocation/peak accounting, explicit
source lifecycle collection and migration/floor transfer. Existing graph counters
remain zero. Bounded inline metadata preparation/publication is the next backend
increment to reduce operation-ledger cost without raising limits. None of the
geometry or compatibility checks replaces the required populated workload.
