# Stored document input authentication — scoped source review

Read-only review, 2026-10-29, of the frozen
[DocumentSourceUse candidate](document-source-use.md), following the
[source-admission requirements](document-producer-source-egress-independent-review.md).
The [plan](../../plan.md) owns acceptance.

Disposition: accept the bounded stored-byte/time relation as an unwired
implementation prerequisite. No concrete blocking defect was found within that
scope. This is not acceptance of live invocation authority, operator permission,
provider dispatch, public page production, complete domain Source validity or
Word fidelity.

## Reviewer scope and exact evidence

The reviewer authored the extension-private v3 range claim and the synthetic
producer seeds used by these tests. That authorship is disclosed: this is a
separate review of the parent's production Host authenticator and test/evidence
interpretation, not externally independent authorship or quality assessment of
the Word data. No production module, fixture, manual or frozen payload was
changed during this review. No test, effect, model request or workload was rerun.

Verified candidate manifest SHA-256
`77ec4fd5cfb91e1d7be513f3c2aea0eb2d2a5a5841312f189d153b17d2f0371b`,
all 26 direct rows, both current source/test bytes, 19 retained files, both
699/700-entry runtime/private-asset inventories and 33 rows bound by its three
ancestor manifests. The parent inventory exactly equals the corresponding
[complete-value reader](document-held-value.md) inventory. After rebasing graph
paths, every inherited runtime entry is identical; the only addition is
`Elixir.Ipse.Extension.Collection.DocumentSourceUse.beam`. The inventories contain
697/698 regular files and two symlinks each. Both helpers equal
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
The [verifier](document-source-use-review/verify.exs) and
[result](document-source-use-review/verify.log) preserve the read-only checks.
Its first syntax-only verifier failure and source are retained separately as
`verify-initial.log`/`verify-initial.exs`; correcting the missing `end` did not run
any runtime control.

## Relation and earlier findings

The trusted retained-read closure supplies one actual document view.
`DocumentStage.read_value/2` preserves native revision/committing operation and
validates complete logical packing. The authenticator binds the v3 pending claim
to its exact revision/hash, captured catalog/floor, Job, selected domain root
including absence, page and ordered source bindings. Each selected head and
ordered source block is authenticated by its logical hash and exact complete
bundle bytes. `data.<partition>.<logical-block-sha256>` matches the actual
extension producer; it is not a physical record digest or arbitrary path.

The earlier insertion-order incompatibility is repaired. Catalog rows sort by
source key while head ordinals retain insertion identity. The helper now checks
the head's catalog-page family and unique bounded ordinal rather than equating
it to the sorted row position. The actual reverse-insertion seed covers `[1, 0]`.

The earlier document incompatibility is also repaired. The helper does not
re-split the whole text across paragraph separators. It requires the exact first
eight authenticated source/chunk positions, integer byte bounds, per-source
nonoverlap, UTF-8 slices, range-bound chunk IDs and raw/canonical hashes for every
reference. It then matches the exact prepared next batch, including a short final
batch. This establishes byte authority without a Host DOCX/chunking interpreter;
it does not independently certify that a claimed range is the domain extractor's
semantic chunk. The actual extracted-DOCX seed preserves three short paragraph
ranges and gaps. No stronger chunk-splitting requirement is needed for this
reviewed source-byte admission primitive.

Legacy attributes receive the same derived version/key/content hash as the
extension's Source constructor; already complete Source1/2/3 bytes are preserved.
Source-set hashes use ordinary `JSON.encode!` over those complete values, not
canonical SDK digest substitution. Temporary `historical`, `chunks` and
`head_ordinal` fields are removed before hashing. Common byte/version/origin/time
shapes are checked, while extraction receipt meaning, locator fidelity and full
domain Source validity remain explicitly extension-owned. The final production
documentation clarification makes that limitation visible; its retained freezer
recompiles with empty diagnostics and does not rerun tests.

The assembly overshoot finding is repaired: each block's summed piece bytes must
fit the declared source total, one-MiB source maximum and eight-MiB aggregate
before concatenation. Logical read accounting remains 269 maximum:
five anchor/page reads, eight heads and at most 256 source blocks. The 18-MiB
cumulative logical-body allowance and actual packed-value bounds are input/IO
limits, not a total process-memory bound. Decoded blocks, assembled JSON, maps,
and normal runtime overhead still exist; no peak RSS or maximum-population
qualification follows from this arithmetic.

`current?/2` separately checks all returned original source times against a
trusted final host UTC sample: future observation, historical input and equality
at expiry refuse. The eventual caller must retain these facts from the actual
authenticated callback and perform that time check after blocking validation.
Arbitrary shaped facts or a saved pending claim supply no authority.

## Executed cases and remaining integration

Inspected the retained eight scoped cases across their actual executions:
three initial negative/time/guard passes; the repaired four-batch positive in
47181; the corrected referenced-anchor case in 47182; two compatibility passes
in 47184; and the native owned-read/escaped-reader pass in 47185. This is not one
final eight-case aggregate pass. Initial incorrect fixture expectations, the
unreferenced lexical-record assumption, test JSON alias error and wrong native
witness location remain preserved. The model's uppercase claim operation IDs are
explicitly adapted only in the two synthetic compatibility reads. The native case
uses an actual separate claim commit and checks its real operation/revision;
its temporary stores were removed by teardown, so no raw native receipt file is
invented. Native seeding is trusted construction, not genuine acquisition or
operator-source provenance.

The module is still unwired. Its returned operation ID must be matched to an
original successful claim CAS in the same live invocation. A future owner must
authenticate operator/artifact/project/Registry scope, require the reviewed
source-use binding without an omitted-guard fallback, spend batches once, poison
unknown/mismatched results, sample UTC under short final retained ownership and
use the existing one-use exact-wire EgressGate. Restored journals cannot recreate
that volatile admission. No socket-lifetime lock or byte-recall promise is added.
Public page production, approval-wait/source races, live transport, later pages,
facts/group completion, full storage/journal/peak/GC/migration and ordinary Word
quality remain open.
