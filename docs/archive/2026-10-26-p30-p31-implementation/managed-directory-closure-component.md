# Managed publication directory closure

Historical component record, **2026-10-27**. Current contributor guidance is
[protected persistence](../../developer/persistence.md#serialize-protected-consent-before-publication);
the [plan](../../plan.md) retains milestone acceptance. This prerequisite does
not complete managed metadata version 3, current recall or either milestone.

## Contract and reviewed scope

`Collection.execute_managed/6` now gives its trusted normalizer an additive
version-2 callback witness with actual native root bytes/hash and explicit
absent/present state. The existing summary, manifest, original-request, recipe
and operation bindings retain their meanings. Raw root bytes are callback data;
the host does not add them to SDK responses or durable receipts.

The existing binary-key read remains available. The only additional closed form
is `%{"op" => "neighbors", "request" => descriptor}`. It reuses
`Collection.Directory` selection and costs against the already validated current
record index, under the same retained native lock. No read view, nested
Collection lock, value scan, scan operation or batch operation is introduced.
Neighbor replies match read-view metadata/witness semantics, including actual
record revision and operation identity. Values need separately charged reads.
Legacy roots 2/3 retain binary reads but refuse neighbor adoption; neighbor roots
4/5 and actual native absence are explicit.

Binary reads cost one and neighbor lookups cost four, including missing keys and
nil positions. One owner-bound allowance contains 32 units, debited before lookup
or native IO. Malformed requests spend no units; another process cannot spend the
owner's allowance. An authorized over-budget attempt now latches refusal and
prevents publication even if the callback ignores it. This is an explicit
contract tightening: the preserved original test performed 32 successful reads,
ignored the 33rd refusal, and successfully published. Its six original controls
passed unchanged before implementation. It is not evidence that the earlier
contract already prevented that publication.

The normalized-request extras/deletion rules, SDK, native source, reservations
and Normalizer v2 remain unchanged. Final native check/release still withhold
results after loss. The original owner/scope/native boundary is cooperative
trusted Core; this is no hostile-BEAM or arbitrary same-user filesystem sandbox.

## Exact verification

Private working graphs are `/tmp/ipse-managed-directory-20261027-01`, `-02` and
`-03`. Graph01 matches all 2,312 qualified neighbor-owner inputs, with only an
additional private ExUnit failure-cache file after its six passing controls.
Graph02 retains the first 29/30 run: my new empty-root fixture requested deletion
without advancing its floor, and unchanged validation correctly refused it.
Only that fixture was corrected to explicitly advance the floor. Its original
source and log remain preserved. The subsequent focused 30/30 run preceded final
whitespace cleanup; the sealed final broad run includes all 30 controls.

Graph03 final source/runtime manifests have **2,314** regular inputs, identical
before/after, SHA-256
`1bb8790f9f0ba690db9f5470ebb7a5e1b523992427ffdbbccbad80af7dfc78c7`.
All 17 Collection suites passed **169/169**, seed `20261114`, `max_cases: 2`,
356.8 seconds. This includes managed 7, new native directory 11, unchanged
Normalizer 12, SDK/session, migration, storage and read-view controls.

Full private compilation produced 167 modules from 130 sources with diagnostics
`[]`. Actual Elixir **1.18.4 / OTP 29** formatted all three changed Elixir files
and compiled Collection with diagnostics `[]`. The exact current read-view manual
exercise passed. Its code SHA is
`54704fd43d8cca330387039bfa13cbc4e2d7edf4e2324b339221a7f0c2906e81`.
The whole persistence chapter, collection SDK chapter and operator knowledge
permission manual were reviewed. The document checker passed, with its final
archive-inclusive output retained in the evidence.

| Final input | SHA-256 |
| --- | --- |
| Collection source | `54ebfc8258c16aa131e7d36df608dc45654dc906de815c48f6004d3bcf394fdc` |
| Existing managed tests | `5693e4728d761ce161bbcc444bea6fb216ebc1a98c37450718509d3d920be045` |
| New native directory tests | `065bd3d3def84457a479852e8e538dc6dc15bcf3854c3b49d1c9c91f09eecc5c` |
| Persistence chapter | `a512596172897f30156c34d9192df096a3d644279f04fea189d503cf039f8db3` |
| Executed Collection BEAM | `cccbcec0b4c1585b6f18e57463e1447db720bee27163e5f5d4393cb48b4f50c6` |
| Executed private native helper | `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b` |

The shared old helper `108c762e…` was hashed read-only and never executed,
rebuilt or modified. All compilation/testing used private sources, builds,
helpers and fixture paths. No model, network inference, credential or independent
qualification-answer inspection was involved.

## Evidence and limits

Owner-only durable evidence is under
`p31-verification/managed-directory-closure` in the task visualization root.
It contains `REPORT.md`, `provenance.json`, `files.sha256`,
`preservation-receipt.json`, the three complete source/runtime graphs, raw logs,
drivers and replay instructions. Executable images are retained as data; replay
uses a writable copy. Original compiler harness failures (target redefinition,
missing Mix initialization and omitted bundled sources), the invalid fixture,
the no-Git private document-check failure, and corrected final checks are retained
with their actual outcomes. They are not relabeled as successful checks.

This evidence comes from the implementation author. Root read all changed code,
tests and documentation and reported no actionable static finding; that is not
an independent executed audit. Whole-implementation adversarial audit remains
pending. No current managed eligibility, authenticated inherited metadata,
metadata-v3 activation, Session withdrawal or SDK reader integration is claimed.
