# Complete logical values under retained document ownership

Scoped additive implementation, 2026-10-29, after the
[fixed document reader](document-held-reader-independent-review.md). The
[plan](../../plan.md) owns acceptance. This is transport decoding for the future
source-admission caller, not source eligibility, inference permission or a public
worker endpoint.

`DocumentStage.read_value/2` receives the actual trusted held-reader closure and
selected key. It reuses `packed?/1` to validate the existing physical wrapper,
full original parts, byte count and body hash, then `ResultDocument.decode/2`
for the complete logical object, including duplicate-key and existing structural
bounds. It preserves the native record revision and actual committing operation
ID. Its returned hash/size describe the logical JSON body; they are deliberately
distinct from the physical packed record hash. Absent records return nil;
malformed/corrupt/escaped reads refuse. The supplied closure's actual ownership
and the caller's source-policy checks remain necessary; a shaped callback is
not authority.

The [manifest](document-held-value/manifest.json), SHA-256
`86342fa9c06e719ef8c062d65cbfce419c575515033c90306d613f990f35679a`,
pins two source/test snapshots, five launcher/log/freezer files, both 699-entry
runtime/private-asset inventories and the original reader manifest. The new tree
copies the frozen complete-host-plus-reader base and recompiles only DocumentStage;
the helper remains `40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
Compiled binaries stay in the recorded `_build` trees. This predates the separate
public Management/current-bundle integration; inherited source hashes describe
their original pre-overlay checkpoint, not every later source overlay.

`47164` compiles with empty diagnostics. `47165` passes two new native tests in
0.1 seconds. A real ordinary inline document publication is read completely
under the retained document owner, with exact committing ID/revision, original
body hash/size and an explicitly different physical hash; the escaped reader
refuses. A roughly 40-KiB logical value is reconstructed in full, while actual
stored bad-hash, duplicate-JSON and extra-wrapper-field fixtures refuse. These
are trusted synthetic storage/protocol controls, not genuine external source
provenance. The eleven predecessor reader tests were not rerun for this additive
helper. No SDK/quota/packing change, model call, aggregate suite, producer dispatch
or complete package qualification is claimed. Independent review remains.
