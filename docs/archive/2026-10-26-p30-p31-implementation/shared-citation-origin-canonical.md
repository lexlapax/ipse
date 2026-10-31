# Shared citation origin correction — 2026-10-29

This additive integrity correction follows the [fact version repair](shared-projection-canonical-fact.md)
and [directory cardinality repair](shared-directory-cardinality.md). Earlier frozen
source/artifact cohorts remain unchanged. Current scope belongs to the [plan](../../plan.md).

A second exact counterexample used a source with opaque origin receipt
`{"version":1}` and a supplied citation whose otherwise identical receipt used
`{"version":1.0}`. Legacy fact/span validation accepted it, and the fact ID was
unchanged. Shared packing accepted the citation but hydration copied the source's
integer receipt back, so successful output differed strictly from input. The
retained pre-repair probe prints `accepted: {true, true}` and
`exact_roundtrip: false`. Floating citation versions themselves already refused;
the demonstrated gap was nested opaque origin metadata.

Shared packing now regenerates every complete citation from its exact raw source,
chunk and span, requiring strict equality with the supplied citation. This
preserves all source/revision/origin/document metadata and catches numeric aliases
throughout that metadata. Canonical integer fact version remains required. Existing
Evidence and per-source Projection validation/read behavior is unchanged.

Pure focused `46937` passed in 2.5 s: canonical origin round-trips exactly, the
numeric-origin alias remains accepted by legacy validation, and new shared packing
refuses it. Existing job/manifest/corruption controls also passed. Actual public
Corpus Word hydration `46938` passed in 31.5 s after the repair, with 93 SDK reads,
zero effects and a preserved typed Word citation/warning. This does not qualify
model provenance, protected publication, full Word quality or capacity.

The [manifest](shared-citation-origin-canonical/manifest.json) pins the repair
source, exact probe/log, focused test/log and compiled feature hashes. Generated
BEAMs stay under `_build`. The [controller/read receipt](shared-generation-controller-read.md)
records later public fact-window and partial-document behavior separately.
