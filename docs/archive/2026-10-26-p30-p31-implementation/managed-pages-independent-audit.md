# Independent ManagedPages / Planner component audit

Recorded 2026-10-27. Historical component evidence; current persistence behavior is
owned by the [developer chapter](../../developer/persistence.md). This audit of
[Storage's component](managed-pages-component.md) is independent of its author
and does not accept its future NormalizerV3 integration or P30/P31.

The unchanged owning ten tests passed. Thirteen fresh controls passed: five pure
codec cases and eight actual native Identity/DomainAuth cases using an independent
flat sorted-list oracle for **trusted fixture Collection observations**. There
were zero actual Collection reads or publications. No actionable codec/local
planner finding was identified. Actual native C provenance, combined publication,
source/lifecycle/current eligibility and real capacity remain separate gates.

The full independently frozen report, all source/runtime inputs, source/BEAM/helper
hashes, original failure probes, corrections, raw logs and replay loader are at:

`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-managed-pages`

| Evidence | SHA-256 |
| --- | --- |
| `REPORT.md` | `33dbc8cad74cdf5db2b5f2ed1a101f93d7aa366fe0d10cca09013fa2880a9b94` |
| `files.sha256` | `1f1c1ccae7db9f889e01ebc64038267d3b1d0606a8a9cc0be3e8220f4dd07a5a` |
| `provenance.json` | `be56124070170975e75651d1970c1c849c9b83ad3596da0030c7b9a43649f2ce` |
| `preservation-receipt.json` | `2a6403ccac8624a7e2f181b39b264b2d49779ed80490308b23ee705367e39098` |

All 4,057 declared source/build/link entries matched owner and copy before/after,
including exact membership, 4,054 regular files and three recorded aliases.
Durable evidence retains 4,152 payloads, owner-only, with admitted private-helper
alias bytes materialized and all files/directories fsynced. Shared108c was never
executed or rebuilt; actual native cases selected the copied d84 helper.

The initial native run was 3/4 because an audit assertion incorrectly expected a
coherently invented sole-leaf directory to authenticate its own native provenance.
The component explicitly requires trusted C observations. The original driver and
diagnostic remain unchanged; a three-leaf fixture makes the omitted successor an
observable structural hole. The first combined 12/12 run emitted two audit-driver
pin warnings. Explicit pins and a separate underfull-buddy case produced the final
warning-free 13/13. No production fix, guard increase or hidden retry occurred.

Author synthetic annual arithmetic was preserved but not rerun or treated as
actual capacity. Current manual hashes and a 548-file/4,804-link/zero-error docs
check are recorded in the full report. The later
[Identity-finalization finding](identity-finalization-finding.md) concerns a
separate existing SDK accounting boundary and does not change this codec result.
