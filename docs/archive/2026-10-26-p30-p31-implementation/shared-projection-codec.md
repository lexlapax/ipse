# Shared projection packing — 2026-10-29

This historical component receipt follows the [fused transport](fused-document-writes.md)
and [strict deadline gate](strict-deadline-interposition.md). Current scope belongs
to the [plan](../../plan.md) and [Corpus manual](../../operator/corpus.md).
It establishes a lossless codec and read-only preparation path, not a selected
global generation, protected publication, populated capacity, or model quality.
The subsequent [independent review](shared-projection-codec-independent-review.md)
found that noncanonical fact version `1.0` can silently hydrate as integer `1`;
the exact round-trip claim requires the focused boundary repair in progress.

`Store.Collection.Generation` packs up to eight captured sources together. Source
pages bind their complete immutable source heads, original source identities,
observation/expiry/history metadata, document status, and complete warning digest.
Vector pages preserve every ordered chunk identity, exact input digest, model
selection, canonical float32 bytes and vector digest. Fact pages use bounded
entity dictionaries and source-local span coordinates; hydration regenerates the
original fact IDs and exact typed citations from the full captured sources.
No source text, Word locator, warning or assertion is truncated.

Each leaf is at most 48 KiB. Page references bind complete ordered bytes, hashes
and sizes. Group headers bind the source set, cursor, model/extraction recipes,
counts, identity digests and all page references. Hydration checks the caller's
expected cursor and selections, authenticates every page, and canonically repacks
the entire group. A changed page hash alone cannot authorize changed content.
This is ordinary Elixir data transformation using existing Evidence, Projection,
JSON and hash functions; it introduces no dependency or generic protocol change.

The Collection client's private `source_bundles` read supplies complete hydrated
sources and their authenticated heads. Its coverage explicitly says
`source_bundle_preparation` and `evidence_readable: false`; it is not a public
query result or later-use authority. The fixture uses existing SDK host calls and
bounded result publication. It never transmits a whole namespace snapshot.

## Focused controls

- `46886` first passed the actual read-only Session with eight ordinary sources.
- `46889` passed strengthened corruption controls alongside the separate typed
  deadline diagnostic. It performed 76 reads and zero effects.
- `46909` passed the partial-Word variant in 11.4 s. Seven ordinary sources and
  one actual parsed synthetic DOCX supplied 94 vectors, 160 facts and 40 entities.
  The partial source retained its warning and 20 typed Word citations. Fourteen
  leaf values plus a 3,956-byte header sufficed; the largest leaf was 45,073 bytes.
  The Session performed 74 reads and zero effects, with native status unchanged.
- `46910` retained the exact compiled artifact and repeated that changed Word
  control together with the corrected current inline-deadline control: two passed
  in 9.3 s. Future strict deadlines now expect the closed Core refusal, an absent
  target and unchanged native generation; a later ordinary untimed call remains
  independent. Historical positive receipt validation was not rewritten.

The codec controls refuse missing/reversed pages, a changed expected model,
rehashed wrong vector input, rehashed shifted citation span, rehashed warning
metadata, captured-head revision substitution and reversed source order. The
first `46908` harness run omitted application startup and failed before Session
creation; its log is retained beside the corrected run.

Native fixture setup uses ordinary untimed Core writes solely to seed synthetic
records on actual `/tmp` tmpfs. Those writes are not document acquisition,
Consent authority, strict stage expiry, or a currently supported ingestion path.
The actual Session continuation performs only `snapshot`, `value.stat` and
`value.read`. The tested host graph contains the strict Collection gate; no
protected publication or qualifying workload was attempted.

## Full-profile dry planning

The finite development planner verifies a local artifact's declared bytes, then
uses the implemented Source 3 recipe, lexical grouping, projection codecs and
actual bounded SDK frame grammar. It performs no native storage, inference or
acquisition. The geometry remains 1,000 sources, exactly 20 MiB extracted text,
10,000 chunks and 1,024-dimensional vectors, 5,000 distinct entities and 20,000
assertions. It does not reduce the accepted profile.

The existing per-source implementation needs at least 20,504 initial mutations
and 8,316 live keys, so it still refuses the 8,192-key ceiling. The shared codec
forms 125 groups and 1,625 immutable group values. Planned manifest and entity
directories add eight and 79 pages. Including current raw-source and lexical
keys plus planned root/job gives 5,030 initial keys, or 6,414 while replacing
vectors with unchanged sources/facts. These directory/controller operations are
plans, not an implemented atomic generation protocol. The full peak including
staging, source changes, retained generations, migration and GC is not qualified.

Fresh shared values require 5,587 mutations in the fused transport calculation;
the largest actual emitted frame is 13,341 bytes. No 16 KiB SDK, 8,192-key,
32,768-operation, 192 MiB document backend, or 256 MiB total-profile ceiling was
changed. The current gate reports publication unavailable. The retained planner
output separates packed bytes from unmeasured native metadata and journal peaks.
It measures 61,328,250 bytes of packed group values and 643,268 bytes of planned
directory values; staged vector replacement adds 57,114,610 bytes of vector/group
headers. These figures exclude raw sources, lexical values, native metadata,
journals, GC and migration. They are not a whole-profile peak measurement.

The [manifest](shared-projection-codec/manifest.json) pins exact sources, failed
and passing logs, the tested fixture and Corpus artifacts, host BEAM inventory,
helper, current gate provenance and dry planner output. Generated artifacts stay
under `_build`; only source, logs and provenance are archived.

Still required are an authenticated global manifest/entity directory, bounded
generation controller and selective public query, atomic old-plus-staged
selection, safe explicit GC, migration/floor behavior, complete operation and
peak-byte accounting, and the actual populated/rebuild workload. Current strict
publication remains refused; these codec results provide no fallback around it.
