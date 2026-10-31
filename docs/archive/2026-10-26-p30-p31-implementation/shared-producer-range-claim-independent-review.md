# Private producer source ranges — independent review

Read-only review, 2026-10-29. **Accepted as a private worker claim-format and
exact-byte-range increment.** No new blocker was found in that scope. It supplies
data for the future trusted Host relation; it does not implement that relation
or remove the [public page gate](shared-producer-public-gate.md) or
[source-policy hold](shared-producer-first-page-independent-review.md).
The [plan](../../plan.md) retains overall acceptance ownership.

The original range [receipt](shared-producer-range-claim.md) and
[manifest](shared-producer-range-claim/manifest.json), SHA-256
`c464ec617ef4d403f47582068de49f749185263d0a95361ef6ddb5acd84d5d12`,
were reviewed against the preceding [selection slice](shared-producer-selection-adoption-independent-review.md).
The independent [verifier](producer-adoption-independent-review/verify.exs)
and [output](producer-adoption-independent-review/verify.log) checked all 702
rows: 27 source/freezer snapshots, two logs, two ancestors, 668 regular runtime
files, two nontraversed symlinks and the separately hashed helper. Runtime and
helper rows are exactly identical to the selection cohort. This review ran no
tests/effects/model calls and made no implementation changes.

## Exact bytes and compatibility

The frozen Producer SHA-256 is
`f73bad96ffba74702900f3a8b6a597b47d49c1a04eae98fc3316ee57fc7ccde9`.
The source delta was inspected directly against the selection predecessor.
New claims pair integer version 3 with its exact v3 recipe. Each input preserves
the five preceding positional fields and appends start/end byte offsets.
Construction takes `binary_part` from complete authenticated Source text and
asserts equality to the domain chunk text; that exact value feeds both canonical
SDK hashing and unaltered raw SHA-256, and subsequently embedding inputs. There
is no trim, character-offset conversion or replacement of the original bytes.

The closed v3 validator requires integer source/chunk indices, an existing
source-binding index, unique source bindings, strictly increasing source/chunk
positions and nonoverlapping increasing ranges within a source. Bounds require
`0 <= start < end <= 65536` and slices at most 4096 bytes. Existing record/input/
receipt counts and the 8192-byte claim ceiling remain. These checks prove shape
and internal order, not the truth of a forged source binding or a stored chunk
relation; trusted Host admission must authenticate that relation separately.

Exact legacy version 2 plus its v2 recipe retains the old five-field validation
for inspection. The result now reports the stored recipe. Pending records still
produce `pending_unknown` with no continuation; the page path refuses an existing
pending claim rather than adopting it. A ready old page is not a retry either.
Version/recipe mismatches and absent v3 range fields fail. No embedding wire
field, Core owner, native helper or public page authority changed.

## Evidence boundary

Retained 47175 reports three focused private/model controls and thirteen excluded,
including multibyte/tab/CRLF slices, malformed/order/overlap/index cases and
legacy pending inspection without inference. The modeled successful flow used
119 reads/12 effects, a 4874-byte ready record and 45064-byte vector page, with
complete requests validated against the existing frame envelope. These are
bounded modeled observations, not native mutation, provider inference or a
whole-profile ledger. 47174 preserves the command syntax failure before source
compilation. Domain compilation occurred in fixture memory; no emitted domain
BEAM cohort or package is qualified by this freeze.

The later Host/relation seed appendices have separate additive manifests and are
not silently included in this 702-row review. Their synthetic commit wrappers,
nil native history and fixture origin cannot grant production admission. The
Host must still bind actual claim revision/logical hash/operation, source bundle,
ordered batch and wire bytes at the original short final admission boundary.
Unknown must poison live continuation, and later query filtering cannot repair
egress that lacked permission. Full acquisition, later pages/facts, selection,
capacity, GC/migration and representative document quality remain open.
