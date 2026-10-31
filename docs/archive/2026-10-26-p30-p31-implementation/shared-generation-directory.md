# Shared generation directory — 2026-10-29

This historical component receipt follows the [shared codec](shared-projection-codec.md)
and its [canonical fact correction](shared-projection-canonical-fact.md). Current
scope belongs to the [plan](../../plan.md) and [Corpus manual](../../operator/corpus.md).
The strict publication gate remains unchanged. This is a pure directory codec
and actual read-only fixture integration, not generation selection or capacity
qualification.

The new isolated `Store.Collection.Directory` first validates a complete shared
group through canonical hydration/repacking, then captures its bounded immutable
header, source-head and entity summary. Packing accepts up to 125 such summaries
and all captured raw catalog pages. It authenticates every catalog page hash and
ordinal, requires the complete ordered source/head sequence, and checks source
text/chunk totals. It binds exact catalog hash, generation, floor and common model
and extraction selectors. The summaries are extension-private derived data;
they are not host authority seals or proof of actual model inference.

Content-addressed manifest pages hold at most 16 group entries. Entity pages hold
at most 64 exact entity IDs/labels and ordered group memberships. A root binds all
ordered page references, complete source-head and entity-row digests, counts and
selectors. Values remain at most 48 KiB. Entity hydration authenticates complete
page order, counts, labels, IDs and group membership bounds. No generic SDK limit,
quota, namespace, capability or consent rule changed.

Selected-group lookup requires an external expected root digest and exact
generation/catalog/floor/selectors. It authenticates the complete manifest chain
and source-head digest, then only the headers for up to eight requested source
keys. Missing keys stay explicit. It does not hydrate namespace text, vectors or
facts, and returns `evidence_readable: false` and `projection_payloads_read: false`.
Later projection hydration and current-use authority remain separate requirements.
The codec itself performs no storage, inference, acquisition or publication.

Focused checks:

- `46918` actual Session passed in 8.7 s. Eight fixture sources supplied one
  group; the worker acquired the actual stored catalog and page through existing
  SDK `value_read` continuations. It produced two directory values, a 1,176-byte
  root and 40 authenticated entity rows. There were 58 actual read calls, zero
  effects, and unchanged native status. Missing manifest, stale floor/catalog,
  changed header and rehashed catalog head substitution refused.
- `46920` pure isolated control passed in 2.1 s with 17 groups/136 sources across
  two manifest pages and five entity pages. It authenticated 272 entities, selected
  only two group headers, and produced a 2,082-byte root. Missing/reversed pages,
  reversed captured summaries, a rehashed/re-rooted reordered manifest, stale
  floor and altered capture metadata refused. Unknown source keys remained explicit.
  This small one-dimensional synthetic fixture is not the populated full profile.
- `46921` built the official Corpus/collection-documents artifact without compiler
  diagnostics, including the new isolated helper. This is an artifact build,
  not an installed operator or publishing journey.

All failed attempts are retained. `46913` exposed a fixture assertion that reversed
a single vector page and expected rejection; the corrected control duplicates a
sole page or reverses multiple pages. `46914` diagnostic compilation warned about
an unchecked stacktrace head; `46915` isolated the unchanged-page assertion.
`46916` passed the first actual directory path before the complete entity digest
was added. `46917`/`46919` completed the pure assertions but failed output parsing
because the test compiler omitted `return_diagnostics: true`; `46920` uses the
existing supported compiler diagnostic contract. Temporary debugging exception
projection was removed. No failed attempt published a document.

The [manifest](shared-generation-directory/manifest.json) pins exact source, all
logs, retained fixture/Corpus artifacts, the earlier canonical correction and
isolated host graph. Sources and generated artifacts stay under `_build`; the
archive retains source/log/provenance only. Native fixture setup used ordinary
untimed Core writes on actual `/tmp` tmpfs. Those are synthetic seeding, not
Consent, strict expiry or protected ingestion qualification.

Still open are the resumable generation controller, atomic old-plus-staged
selection, selected public query with complete projection hydration and current
source authority, interruption/unknown handling for those mutations, safe GC,
migration/floor behavior, complete operation/peak-byte accounting and the actual
populated/rebuild workload. No actual model receipt provenance or quality was
established. The previous full-profile directory arithmetic was a dry plan and
has not been reclassified as measured capacity by this increment.
