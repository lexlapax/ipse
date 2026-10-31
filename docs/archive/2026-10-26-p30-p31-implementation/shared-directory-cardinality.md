# Shared directory cardinality correction — 2026-10-29

This additive correction follows the [directory receipt](shared-generation-directory.md)
and independent review. Current scope belongs to the [plan](../../plan.md).
The original frozen source and artifact remain unchanged.

The reviewer constructed ten valid captured sources grouped as three plus seven
at cursors zero and eight. Packing accepted two summaries, but lookup correctly
required the canonical eight-plus-two grouping and refused the producer's result.
Packing now requires each group's source count to equal the lesser of eight and
the remaining catalog count. It refuses the noncanonical split before producing
a directory; source/chunk/fact identities and canonical outputs are unchanged.

Focused pure controls `46922` and `46923` passed in 2.1 s each. The exact three-plus-
seven case refuses, canonical eight-plus-two packs and looks up successfully, and
the existing seventeen-group cross-manifest/entity/corruption controls still pass.
`46923` additionally retains the exact compiled feature BEAMs under `_build`.
No native operation, model inference or publication occurred. Strict publication
gates and the existing qualification limits remain unchanged.

The [manifest](shared-directory-cardinality/manifest.json) pins the three changed
source files, two logs, compiled feature hashes and original directory manifest.
The test compiler's optional evidence destination is restricted to `_build`.
Generated BEAMs are not archived. This repairs canonical grouping; controller,
public hydration, GC, migration and populated/peak qualification remain separate.
