# Word block packing and exact citation maps

2026-10-31, after `1b516ad`. Implementation evidence for the reproduced
[ingestion gap](word-ingestion-gap-20261031.md), not full P31F acceptance.
Current user procedures and format teaching belong to
[Corpus](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
and the [Knowledge guide](../../developer/knowledge-extensions.md#follow-acquired-document-bytes-into-cited-storage).

## Resolve the actual failing geometry

Inspection of the original public SDK fixture found **17 paragraphs and 312
table-cell segments**, rather than 329 plain paragraphs. A paragraph-only
implementation passed a synthetic native journey but still refused this original
file. That intermediate limitation is preserved in the local
`/tmp/ipse-paragraph-packing-public-word-20261031.log`. The implementation was
extended to preserve both kinds, without editing the input or raising a limit.

Recipe **v14** packs adjacent simple blocks from one document part only when an
extraction exceeds 32 blocks. Each group has at most 64 original blocks and fits
the selected 2,048/4,096-byte chunk bound. Compact rows retain original paragraph
number, exact UTF-8 byte length and, for cells, table/row/cell coordinates.
Gaps in paragraph numbering remain; annotation/region/other richer locators act
as grouping barriers. The full text and newline joins remain byte-exact.
Unsupported geometry still refuses before metadata assembly.

The original immutable 16,079-byte file now produces **six groups**, **6,509 text
bytes** and **6,325 metadata bytes** in both payload profiles. The existing
32-chunk, 16-KiB manifest, 64-KiB staged text and action/storage limits are unchanged.
Older extraction recipes retain their prior boundaries. At most 32 original
blocks keep their ordinary representation; no saved source is repacked on read.
The format's parser recipe changes to v14; unrelated text/Markdown/PDF stay v2.

## Preserve evidence across packed boundaries

Single-block quotations retain the ordinary locator and local byte range.
Cross-block quotations use `document.version: 2`, a shared part and ordered
compact span rows with explicit `span_fields` column labels. The public citation's
outer version remains 2 or 3 for its existing source family. Rows preserve local
block offsets, quotation offsets, implicit newline gaps and original table
coordinates. Evidence reconstructs the exact expected map from the hydrated
source; changed coordinates, shifted boundaries, reordered IDs or labels refuse.
The stored group map separately validates row shapes, sums, UTF-8 splits,
separators, increasing IDs and complete group hashes.

No new library, native protocol, service, permission or core output gate is added.
The existing paged manifest, draft/CAS and source-reacquisition paths are reused.
The current operator and developer chapters integrate groups and both citation
forms into their acquisition/inspection workflow. Their earlier whole-document
editorial review is retained, with overlapping chunk/locator explanations
reconciled and the runnable verification path updated.

## Verification

The [machine record](word-block-packing-20261031.json) freezes owning code/test
hashes, independent artifact identity, public input identity and reports/log hashes.
The upstream provenance and MIT license hash remain in the earlier investigation.

- Pure mixed-block control checks 329 Unicode blocks, numbering gaps, cell
  coordinates, cross-block spans, forged rows, shifted byte maps and old-recipe
  refusal. It passes without loading domain modules into the parent test VM.
- Both actual native State and Collection journeys pass: mixed paragraphs/cells,
  explicit approvals, stale-file refusal before further writes, completion through
  bounded stages, last-cell coordinates, Saved reconstruction, confirmed close
  and identical cited retrieval after resume. The initial two-profile control
  passed in 21.0 seconds; stronger coordinate controls passed in 20.2 seconds.
- The **original public file** passed actual native acquisition, staged publication,
  exact source-offset quotation, original binary hash, partial-coverage reporting,
  Saved and confirmed close: 1 passed/18 excluded in 10.8 seconds. This fixture
  requires `IPSE_PUBLIC_WORD_FIXTURE` and verifies the exact original SHA256.
  Its expected text uses Ipse's independent parser process, so it is a round-trip
  integrity control, not an independent Word-rendering oracle.
- Final acquisition/ingestion/packing/chunking selection: **27 passed**, 103.1
  seconds, with the public original enabled. Earlier extraction/fidelity/ingestion
  controls passed **44**, 59.1 seconds, before the self-describing span labels;
  the final selection and independent proofs cover those later label changes.
- Independent final Corpus artifact: **8 source and 8 installed checks passed**,
  including table packing, cross-block citations and forged-label refusal.
  Inventories remained unchanged, private homes and a precompiled harness were
  used, and runtime PATH excluded the system development toolchain. The host is
  the exact previously verified `25afe99` archive; these checks do not claim that
  its older bundled catalog contains v14.
- The verification gate now requires all eight named checks, beyond their total
  count. A new control passed for each missing, false and substituted check and
  for forbidden live-inference claims. Both actual reports also passed this
  stronger validator without repeating their runtime executions.
- Root build, strict compile, format and credential-free demo passed. The native
  helper is unchanged at `c6768890455697de64284463092806fa2e30305a7ea7b8e6ee60c625f3f0ccff`.

Logs use `/tmp/ipse-block-packing-*20261031.log`; earlier intermediate paragraph
controls use `/tmp/ipse-paragraph-packing-*20261031.log`. No model inference or
release publication occurred. Full Word fidelity, richer locator geometries,
large-scale capacity, quality/installed-user journeys and the failed whole-source
baseline remain open under the original goal.
