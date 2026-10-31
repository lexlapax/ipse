# Independent shared-directory review — 2026-10-29

This review covers the frozen [directory increment](shared-generation-directory.md),
its [manifest](shared-generation-directory/manifest.json), `Directory`, its
canonical `Generation` boundary, catalog validators and focused fixture controls.
It does not qualify a generation controller, publication, public projection
query, model provenance, migration, GC or populated capacity.

The retained manifest verified **19 source files, nine logs, four artifact
inventories and 209 host BEAM hashes**, together with the pinned helper and both
referenced predecessor manifests. The [verification script](shared-generation-directory/review-manifest.exs)
is retained. Passing Session and geometry checks were inspected rather than
rerun. Their reported 58 reads/zero effects and 136-source geometry remain
component evidence; neither establishes the full profile's key, operation,
peak-byte, replacement-overlap or installed-user acceptance.

One concrete consistency defect was reproduced against the frozen official
Corpus artifact. Ten genuine fixture sources were canonically packed and captured
as groups of **three and seven**, at cursors zero and eight. `Directory.pack/5`
returned success. Looking up its exact output, with matching root digest,
catalog, floor and selectors, returned `generation_directory_corrupt`.

Packing checks the number of summaries, each group's one-to-eight source bound,
and the full flattened catalog/head sequence. It does not require each group's
source count to equal `min(8, catalog_sources - cursor)`. Lookup does require
that exact per-group count. The result is a producer/consumer mismatch, not a
demonstrated authority bypass or published corrupt generation. Packing should
refuse the three-plus-seven input, and a regression should cover a nonmultiple
of eight with both accepted canonical grouping and rejected noncanonical
grouping. The [counterexample script](shared-generation-directory/review-partial-groups.exs)
uses the retained frozen fixture sources and performs no native operations:

```text
DIRECTORY_PARTIAL_GROUP_COUNTEREXAMPLE: %{
  lookup: {:error, :generation_directory_corrupt},
  sources: 10,
  pack: :ok,
  captured_group_sources: [3, 7]
}
```

The remaining inspected bindings are appropriately scoped. Capture hydrates and
canonically repacks a complete group before producing its private summary.
Packing checks every captured catalog page's hash, ordinal and shape; it binds
the complete ordered source/head list, text/chunk totals, catalog digest, floor
and common selectors. The trusted expected root digest anchors later lookup;
all manifest pages are authenticated before selected headers are returned.
Selected headers bind exact source-key order and selectors. Entity hydration
checks the entire entity-page chain and row digest, canonical IDs/labels,
ordering, uniqueness and bounded group indices. It does not independently
hydrate every group's facts to prove entity membership, and lookup does not
read projection payloads. These remain separate later hydration requirements,
consistent with the explicit false evidence-readability flags.

Summaries are trusted extension-private derived data, not host authority seals;
an expected root must come from the eventual trusted generation selection.
The current read-only fixtures establish no current-use source authority or
actual inference provenance. The scoped defect has been sent to the component
owner. Repair verification is still required; this review changed no
implementation or runtime gate. The parent batches documentation validation.

## Cardinality repair verification

The later [cardinality correction](shared-directory-cardinality.md) repairs the
scoped producer/consumer mismatch above. Its manifest digest
`223c621005fa500c6f3159dce3296d4ac651ce044319d9e9d17f24d7eb85d1c0`
verified, including three frozen sources, two logs, twelve exact compiled feature
BEAMs and the original directory manifest. Source comparison shows the directory
change only adds the required `min(8, remaining sources)` check while validating
each summary.

The reviewer ran the original three-plus-seven counterexample against those
retained repaired BEAMs; packing now returns `invalid_generation_directory`
before producing a directory. The
[repair probe](shared-generation-directory/review-cardinality-repair.exs)
is retained. Its first diagnostic attempt failed at compilation because the
wrapper removed a variable binding used by unreachable code; the corrected
wrapper reached the codec and confirmed refusal. This was a probe-construction
error, not a failed repair control.

The frozen regression was inspected: it requires the original noncanonical split
to refuse and canonical eight-plus-two grouping to pack and successfully look up
the final source. The recorded focused `46922`/`46923` controls also retain the
existing seventeen-group checks. Those passing suites were not rerun. No further
defect was found in this narrow repair. Controller, publication, hydration,
authority and complete capacity qualifications remain open; no source or runtime
gate was changed by this review. The parent batches documentation validation.
