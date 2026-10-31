# Independent review of the pure pending projection

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the parser receipt](pending-projection/receipt.md) and adjacent manifest
SHA-256 `5a8fb333b709ab3e88bc455ab86497cbe7ddb5b352f736eec84a8bf1d7fd5bdd`.
No implementation edits, model/network/native calls, compile or passing test
reruns were made by this review.

Accepted as a pure structural projection of existing pending records. No concrete
scoped blocker was found. This is not proposal acceptance, eligibility, source
authentication, signed-time verification, consent, host revision or a public
SDK/UI route. Those operations and the standalone management journey remain
required and open.

The parser first validates the existing closed proposal schema and SDK bounds,
then enforces literal integer version and safe integer creation/expiry/event
times. Its explicit type checks close the JSON Schema integer-valued float
alias demonstrated during development. The existing proof validator likewise
requires its strict version, bounded integers, exact closed fields, allowed
origin/kind pair, quote byte-span length and quote digest. Complete record,
text, reason and proof byte bounds remain in place; no field is truncated.

The candidate key is rederived with the existing canonical lineage and
text-dependent ID functions. Lineage includes the source identifiers, span and
quote/content digests; candidate ID adds exact text. The supplied lineage,
candidate ID and `pending.` key must all agree. The output preserves exact text,
its SHA-256, assigned category, reason and original proof. It does not recast
assistant or unattended provenance as operator evidence. Source receipt JSON
is still returned as the claimed original proof, not as a verified host source.

Capture, proposal construction, lineage derivation and direct-note classification
do not call the new projection. The existing capture path still produces its
existing record bytes and identities; this addition is a parser using those
algorithms, not a rewrite or conversion of stored proposals. The retained suite
includes the stable candidate key and existing capture/retention/provenance
controls alongside the two new projection tests. No production caller or SDK
export uses the new helper in this section.

Output names distinguish `record_schema_version` from a Collection revision and
mark every returned time as `worker_recorded_*`. No revision, eligible, accepted
or consent verdict is added. The parser deliberately permits a worker-recorded
expiry before its worker-recorded creation time; it neither extends nor derives
a host deadline from those numbers. Future host use must authenticate the exact
current record/revision, original source and signed pending clock, check active
consent and observe the required exact native display/input. Structural success
cannot substitute for any of those boundaries.

The deliberately valid-looking substituted receipt remains accepted as a claim.
Its receipt digest is not part of the existing lineage or candidate ID, so a
pure parser cannot authenticate its truth. The explicit negative test for an
invalid digest and positive test for a different well-shaped digest correctly
separate structure from authority. The same is true of other well-shaped
provenance claims; no implicit promotion follows from this return value.

[Manifest verification](pending-projection-review/review-manifest.exs) and
[its result](pending-projection-review/review-manifest.log) validate all ten
manifest entries: four source/test snapshots, both runner scripts, both final
logs, the receipt and its pinned runtime ancestor. All705 listed runtime files
match the referenced document-descriptor-inventory manifest. These are inherited
host files, not newly compiled parser artifacts or a fresh complete build.

The strict compiler script compiles exactly Notes, Contracts and Records from
the archived source, checks empty compile/runtime diagnostics and removes its
temporary output. Its retained log reports three modules. The test runner loads
the archived test, whose relative requires load those same archived sources,
and its final log reports14passes. These controls were inspected, not repeated.
The initial integer-alias failure is retained only as the receipt's narrative;
there is no separately pinned initial failure log in this cohort. It must not
be described as an independently recoverable failed runtime control.

The current pure parser and final focused checks support this narrow acceptance.
They do not qualify a host acceptance API, native Review, one-use consumption,
current-record CAS, active consent, public user journey, publication or a final
whole-source/standalone-management acceptance. No existing gate changes follow.
