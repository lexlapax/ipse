# Proposed directory-v2 metadata sizing — 2026-10-29

Additive sizing for the frozen [version-two design](shared-directory-v2-design.md)
and [maximum-label measurements](shared-metadata-geometry.md). This does not
implement or admit the proposed directory format. The design hash remains
`22dff7b5d85f020daab29dec271a574c2420e85b545c7acc7efbd2b86798014b`.

The pure sizing script constructs the proposed root, catalog and a conservative
job containing all165selected page references plus eight active run references,
63catalog pages, a maximum16-byte partition, maximum safe integer revisions,
and maximum128-byte selector strings filled with JSON-escaped control bytes.
It uses the existing client and SDK frame validator to model complete value
preparation, authenticates reconstruction, checks the existing ResultDocument
decoder, and computes the exact native-format packed wrapper. No native effect
or model call runs; modeled success receipts are not host publication evidence.

47065 completed without diagnostics:

| Proposed record | Body bytes | Native packed bytes | Parts | Write frames | Maximum frame bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Catalog | 7,371 | 8,048 | 2 | 1 | 8,259 |
| Selected root | 35,192 | 37,470 | 6 | 3 | 13,318 |
| Active job | 44,451 | 47,375 | 8 | 4 | 13,576 |

All fit the unchanged48KiB client value,64KiB packed native value, ten-part and
16KiB frame limits. Eight modeled metadata preparation writes plus one eventual
three-stage selection are below sixteen effects; actual complete controller
accounting still needs implementation and focused testing. The separately
measured conservative32-row/all125-membership page is31,181body/47,547packed
bytes. Per-page semantic verification and resumed-stage checks remain required;
these numbers do not certify semantic completeness, native publication, full
capacity, GC/migration or whole-profile peak.

47064 retained a sizing-fixture failure because the reused write model omitted
the small catalog's `value.prepare_inline` case. The sizing script adds that
modeled receipt branch only; runtime code is unchanged. The
[manifest](shared-directory-v2-sizing/manifest.json) pins both logs, the exact
script, its reused geometry fixture, the prior runtime/design manifests and the
current client digest. Compiled artifacts remain in their existing `_build`
cohorts.
