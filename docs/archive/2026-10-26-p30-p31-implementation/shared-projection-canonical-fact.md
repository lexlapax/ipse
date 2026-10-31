# Shared fact version correction — 2026-10-29

This additive correction follows the [shared codec receipt](shared-projection-codec.md)
and its independent audit. Current scope belongs to the [plan](../../plan.md).
The original frozen receipt and source snapshots remain unchanged.

The reviewer supplied a concrete lossless-roundtrip counterexample: legacy
Evidence validation accepts fact version `1.0` because it compares numerically
with `1`. The shared codec omitted that version and regenerated integer `1` on
hydration, retaining the same fact ID/citations while changing the exact input.

Shared packing now requires canonical integer fact version `1` before accepting
a group. Existing Evidence and legacy per-source Projection readers remain
unchanged. This narrows the new shared codec boundary without reinterpreting
historical stored data or changing canonical fact identities.

Actual read-only Session control `46912` passed in 9.7 s. It proves the `1.0`
counterexample keeps its original fact ID and citations, remains accepted and
exactly round-trippable through the legacy per-source codec, and is refused by
shared packing. Canonical integer facts still round-trip exactly with partial
Word warnings, typed citations and the existing corruption controls. The Session
performed 74 reads, zero effects, and left native status unchanged.

The [manifest](shared-projection-canonical-fact/manifest.json) pins three changed
sources, the passing log, the exact retained fixture artifact and previous frozen
manifest. Generated BEAMs remain under `_build`. This is a codec repair; it does
not qualify protected publication, model provenance, global selection, capacity,
GC, migration, or complete peak storage. The strict publication gate remains.

The [independent repair review](shared-projection-canonical-independent-review.md)
verified the retained manifest and exact-roundtrip assertions and found no
additional concrete defect in this scoped change.
