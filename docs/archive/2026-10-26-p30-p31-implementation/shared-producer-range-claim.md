# Private producer source ranges — 2026-10-29

This worker-only increment follows the [source-dispatch requirements review](document-producer-source-egress-independent-review.md).
The [public page gate](shared-producer-public-gate.md) remains before claim or
inference; the [plan](../../plan.md) owns acceptance. Exact ranges provide inputs
for a future trusted admission check, not that check itself.

New claims use integer version 3 and recipe
`ipse.evidence.shared_producer.first_page.v3`. The existing five input fields
`[source_index, chunk_index, chunk_id, canonical_sha256, raw_sha256]` retain their
positions, followed by `start_byte, end_byte`. The private producer takes each
input with `binary_part` from the authenticated complete `Source.text`, verifies
equality to the domain chunk text, and sends that exact slice to embeddings.
Canonical SHA remains the existing SDK digest of `[slice]`; raw SHA is over the
unaltered UTF-8 bytes. Text is not trimmed or normalized.

Version 3 validates integer indexes, the actual source-binding index range,
ordered unique source/chunk positions, nonoverlapping ranges within each source,
`0 <= start < end <= 65536` and at most 4096 bytes per slice. These shape checks
do not alone authenticate a stored source or prove a chunking relation. Existing
complete-bundle loading and per-batch anchor/current-policy checks remain.

The exact legacy version 2 recipe and five-field records remain accepted for
read-only inspection. A legacy pending claim still returns `pending_unknown`,
no continuation and no inference/adoption path. Inspection reports its original
recipe instead of labeling an old record as version 3. Version/recipe mismatch
and missing version-3 ranges refuse.

## Focused evidence

The [manifest](shared-producer-range-claim/manifest.json), SHA-256
`c464ec617ef4d403f47582068de49f749185263d0a95361ef6ddb5acd84d5d12`,
pins 27 source/freezer snapshots, two chronological logs, two ancestor manifests,
668 regular Host runtime files, two symlinks and the separately authenticated
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02` helper.
Runtime rows were verified against the preceding selection-adoption cohort;
no Host overlay was made. Domain modules strictly compiled in the fixture's
memory; no emitted domain BEAM cohort or package build is claimed.

- `47174` stopped at a command-line keyword-spacing syntax error, before source
  compilation, fixture work or effects. Its log is preserved.
- `47175` passed three new range controls, with thirteen other cases excluded.
  The multibyte/tab/CRLF source used four modeled embedding receipt flows and
  produced a valid 4,874-byte ready record and the 45,064-byte shared vector
  page. It used 119 reads and 12 effects, and every complete host request was
  validated within the existing 16-KiB envelope. Malformed, foreign, overlapping,
  duplicate/reordered and noninteger ranges refused. Legacy pending inspection
  made zero inference calls and offered no replay.

These are synthetic private-producer/model controls, not actual inference,
native document mutation, current-source Host dispatch, public production or
whole-profile capacity acceptance. No adapter embedding wire field changed.
The tentative compact Host guard and live same-invocation claim/batch admission
remain parent-owned prerequisites. Later pages, facts/group completion,
source acquisition, Session/operation/peak budgets, GC/migration and ordinary
Word quality remain open.

## Additive Host relation fixture

The separate [seed manifest](shared-producer-host-seed/manifest.json), SHA-256
`31fb0ef27e4532ac383575a9ffb3218f95f698d9763c5fdc8d2f2c180facfbd2`,
preserves a [trusted synthetic Elixir literal](shared-producer-host-seed/pending-v3-model.exs)
for Host authentication tests. It comes from the private producer stopped at
its first `embedding.create`, after a known modeled claim CAS. It contains seven
logical records at generation 1014, the exact next two inputs/selection, a
tentative compact guard and the confirmed modeled commit request/outcome.
There are zero inference calls and zero active stages. The claim operation ID
is copied from that model wrapper; other retained record operation IDs are nil,
because this developer model does not retain native operation history. Logical
bytes/hashes are not packed physical native hashes. This is one source with nil
expiry, not an eight-source/native/finite-TTL acceptance fixture.

`47177` passed the seed-only control and wrote the fixture, with sixteen other
cases excluded. `47178` passed its default no-file branch after making seed
serialization optional for ordinary focused test execution. No earlier range,
controller, public Session or capacity cases were rerun. This additive manifest
pins three current source snapshots, the exact first serialization fixture,
the data/logs/freezer and the preceding range manifest. The original range
freeze is unchanged. Host tests may mutate this authentic synthetic relation;
it supplies no source-admission permission or provenance assertion.

## Sorted catalog and segmented DOCX relation seeds

The additive [relation-seed manifest](shared-producer-relation-seeds/manifest.json),
SHA-256 `9a078ffe0fef2a83b3f7631881caeac17d9157c5882c88fd26bf299754c5211a`,
pins nine source/freezer snapshots, two frozen Elixir data fixtures, one log and
two predecessor manifests. Only test setup changed; Producer and document
implementation bytes are unchanged.

`47180` passed exactly two new private seed controls, with seventeen others
excluded. Each stops at its first embedding request with zero inference calls
and zero active stages:

- [Reverse insertion](shared-producer-relation-seeds/pending-v3-reverse-order.exs)
  inserts two sources in descending source-key order. The actual catalog sorts
  them ascending, so authentic head ordinals in claim order are `[1, 0]`.
  The fixture has ten logical records at generation 1017.
- [Segmented document](shared-producer-relation-seeds/pending-v3-segmented-document.exs)
  uses an actual synthetic DOCX package built with OTP ZIP and fixed file times,
  then `Documents.extract`, `source_payload`, `Evidence.collection_source` and
  complete domain Source validation. Its three short Unicode paragraphs produce
  three segment-local chunks, with newline gaps between their byte ranges.
  The exact first two paragraph slices are the pending request inputs. It has
  seven logical records at generation 1011, and includes the original DOCX
  bytes as base64, digest and extracted metadata.

These fixtures preserve actual model action wrappers, including the model's
uppercase hexadecimal operation IDs (`...B2` and `...6B`). They do not invent
native record history. Frozen fixture consumers receive stable exact values;
regenerating a new Job or stage still intentionally uses the ordinary random
IDs/epochs. No previous range/producer/public/native cases or aggregate workload
were rerun, and these synthetic seeds do not enable the public page or qualify
Host source admission.
