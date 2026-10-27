# Managed source clocks and publication metadata

Dated **2026-10-26**. Incremental implementation and independent audit after
`5510ddb`, with the Normalizer and mandatory-floor guard still uncommitted at
measurement. This is historical engineering evidence, not whole P30/P31 acceptance.
The [persistence chapter](../../developer/persistence.md) owns current developer
guidance; the [plan](../../plan.md) owns delivery status.

`Collection.Normalizer` checks a reviewed literal/proposal recipe, its exact
constraint digest and host-authenticated proofs under the atomic Collection
callback. One fresh public record gains a permanent source anchor and packed live
metadata. Separate note/proposal clocks cannot renew through paraphrase, category
change, later policy widening or public-record pruning. Narrower policy shortens
the saved baseline. Host time controls admission. Typed operator overrides and
managed current-read integration remain open.

The [independent audit](managed-normalizer-audit.md) reproduced three defects
before owner repairs: optional floor advancement allowed a genuine older backup
to discard permanent anchors and renew source lifetime (P1); retained ordinary or
pending rows could claim infinite expiry (P2); retained pointers accepted invalid
Collection keys (P2). All three closed independently against the repaired hashes.
Managed originals now explicitly require `advance_floor: true` before callback;
the host never rewrites that choice. Domain metadata/normalization format 2 refuses
experimental format-1 pages that lacked this protection. Generic version-5
storage receipts still grant no domain authority.

## Measured graph and checks

The complete private 119-module graph at
`/tmp/ipse-managed-normalizer-20261026-02` uses a private native helper with digest
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
It includes the separate SDK owner's bounded `scan_visible` seam; that seam is
outside this Normalizer acceptance scope and is not part of this component commit.
No shared helper was rebuilt. The audit preserves complete before/after
source/BEAM/helper inventories and unchanged independent control drivers.

- Strict compilation passed with zero diagnostics
  (`/tmp/ipse-managed-normalizer-02-strict.log`).
- Owner focused tests: **18 passed**, **2.4 seconds**, seed **277012**
  (`/tmp/ipse-managed-normalizer-02-tests.log`).
- Independent frozen domain controls: **2/6 before**, **6/6 after**. The explicit
  true-floor native backup/prune/new-occurrence control passed **1/1** on both
  graphs. This isolates the old optional-false defect from the already-correct
  true-floor path. Generic complete version-5 import passed **1/1** on both.
- Independent after owner baseline: **18/18**. All **695** frozen before files
  rehashed unchanged after closure. The audit states its positive fixture protocol
  adaptation explicitly; the old false-floor payload is now a negative control.

Repaired Normalizer source SHA-256:
`4eff99e231e64c0f0f9254abe0c6118126bf5d4781d6b816bf7922e69ecda4b6`;
BEAM `28b948d58de7df378a126769c227b5f28f600d974ac72bb90b671838ba5d4bb3`.
The full measured Collection source (including the unstaged scan seam) is
`d4e6308af1202e5e16b6a21d809f4edd651fa169b145be192030eb897e8ba567`;
BEAM `7196bdd16c8ffaffa2c56dd47f886aff8c0a4cd72b110a083685c51dddfa6843`.

No model calls, human/platform qualification, standalone activation, typed
override adoption, recall freshness or whole-branch acceptance follows from these
checks. The separate SDK and inference audits do not replace the requested final
post-implementation audit.
