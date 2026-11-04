# Frozen bounded support checks — 2026-11-04

Frozen before any v17 result is read. The original v16 first outcomes remain
immutable. This reevaluation uses the same twelve input IDs and bytes and the
separately frozen v17 artifact. It is remediation, not the original first run.

Select every private document-gold support entry whose source_id is exactly one
of the twelve IDs in the pinned public input manifest. Do not filter by expected
answer, outcome, parser status, stratum, quote length or apparent difficulty.
Question rows with no support for these inputs are outside this source cohort;
empty-support questions supply no extraction quotation check. Count selected
questions and support entries separately before extraction. Invalid/empty or
non-UTF8 selected quote/schema entries are recorded as invalid, not as passes or
silently excluded. Preserve the complete private per-support first result.

For every selected nonempty UTF8 quote, require exact literal byte presence in at
least one extracted original document segment. Separately check exact literal
presence in the Collection source-payload text. No whitespace/case/Unicode
normalization, concatenation across omitted segments, paraphrase or answer
comparison is permitted. Refused extraction/payload is a failed presence check,
not an exclusion. These are support retention checks, not semantic correctness.

For quote-bearing segments compare only explicit compatible structural fields:
part, table, row and cell compare literally to the same locator keys;
footnote_id/comment_id compare literally to annotation_id and require the
corresponding word/footnotes.xml or word/comments.xml part. A quote passes this
bounded structural check only when at least one quote-bearing segment agrees
with every mapped field. Record applicable mapped-field coverage and any fields
that cannot be mapped. An empty mapped set supplies no structural pass.

Gold body_paragraph/cell_paragraph and paragraph conventions do not have an
established exact mapping to the parser's global paragraph ordinal. Revision and
revision_id have no corresponding parser locator field. Those fields, and any
other unknown Gold locator keys, stay unverified. They are not ignored as fully
compatible and are never counted as an exact full-locator pass. No complete
rendered-text, style/visibility, revision identity, semantic-answer, installed
citation or full parser-fidelity score follows from this protocol.

Freeze Gold bytes/schema, input bytes, loader/adapter, artifact and this protocol
before candidate execution. Read only the Gold fields needed for selecting and
checking support, without exposing answer, quote, locator values or private
per-support results to the implementation author or Git. Public evidence contains
aggregate counts, typed outcomes, field coverage/unsupported categories and hashes
only. Do not tune or change criteria after results; any later change is a new
explicitly versioned experiment.
