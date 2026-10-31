# Causal root cache — independent review

Read-only review, 2026-10-29. **Accepted for historical root-only classification
and the retained direct-client headless capture scope.** No blocking defect was
found in the frozen three-owner delta. Automatic model-selected capture and
managed source-tool access remain unqualified; the source-name gate is still
closed. The [plan](../../plan.md) owns overall acceptance.

The [candidate receipt](causal-root-cache.md) and
[manifest](causal-root-cache/manifest.sha256), SHA-256
`8f1274b8270451c71840dd51fa4b4658e333433993be118d444307d274becaf7`,
were checked against the [minimal direction](causal-root-and-source-tools-direction-independent-review.md)
and [accepted publication scope](notes-publication-implementation-independent-review.md).
The independent [verifier](causal-root-cache-independent-review/verify.exs) and
[output](causal-root-cache-independent-review/verify.log) verify all 17 frozen
entries and 668 regular runtime hashes, with exactly ManagedReads,
ManagedLineage and ManagedToolUse changed from the preceding publication
inventory. The retained three BEAMs equal the graph copies. Helper bytes were
independently checked as
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
No tests, effects or model calls were rerun. The runtime hash list is not a new
whole-tree/symlink or packaged-release inventory.

## Authenticated classification and publication

Frozen production source SHA-256 values are:

| Owner | SHA-256 |
| --- | --- |
| ManagedReads | `8ded97c18c5b13ed849a17b98de3d46499fb6329e0ab7b7836bdadc59753ddf4` |
| ManagedLineage | `7d8f68988025a842fd839161d6b9e56067c0a5f34dea6591fcb5493de3b295b4` |
| ManagedToolUse | `733b25a03906203f44801f2a0b33c756429e1c7d6a3b51171b6ef5884020711b` |

An observed receipt first enters a volatile single-operation pending map only
when it matches the active action observation. It creates no classification
then. Cache insertion additionally requires a valid successful Actions result,
exact reconstructed intent equality, a real invocation parent, valid managed
receipt/value binding, selected managed-read mapping and complete recipe
coverage. The receipt binds Session, parent, operation, request/result digests,
dependency digest, pin/project/namespace/epoch and actual root fields. Worker
cache data or a self-consistent shaped root alone does not enter the cache.

Classification accepts only a closed snapshot, explicit nil get, or initial
empty metadata-only index with zero count, no rows and no next page. The v3
label itself is insufficient. Nonempty indexes, later pages, scans and record
values do not receive a positive entry. Cache keys hash the complete dependency;
lookup requires exactly `true`, current binding/pin and expected generation.

Pending state clears on new action, action result, invocation completion and
cancel/turn completion. The cache and pending receipt participate in checked
2048-entry map bounds and the existing 4-MiB encoded state envelope. Capacity
failure marks lineage unavailable; it does not evict evidence and continue with
a partial union. Bounds are source-verified here, not newly exercised capacity
tests. Saved reconstructs the same chronological receipt/result relation; no
serialized cache grants permission, and historical classification does not
restore an effect capability.

Publication still requires `entry.input == []`, the full invocation/read/source
union, identical complete root maps across every dependency, and positive cache
classification for every member. Missing/false classification, stale generation,
foreign pin/namespace, record dependencies or unavailable lineage refuse. A
fresh own nil-get does not replace an earlier dependency. Existing actual source,
Identity/Consent, normalizer witness and native Collection CAS owners remain
the current admission boundary; this delta changes none of those owners or their
deadline/unknown rules.

## Retained evidence and limits

The pinned final replay log records four passing focused cases: classification
absent before the matched result and present afterward; full chronological Saved
reconstruction; forged/missing/reordered/failed-event refusal; strict cache and
pin/generation checks; and self-consistent nonempty/later-index refusal. The
fixture reads an existing retained original headless journal, whose original
Session ID comes from SourceOrigin. This is replay evidence, not a new native
effect. The receipt also reports three selected prior prerequisite controls;
their launcher output and the initial unrelated MCP/header-ID failures have
transcript-only provenance, not separately pinned raw logs. No passing aggregate
was repeated here.

The retained 81-event actual direct-client journal contains one known successful
`collection.managed` result under `approval: saved_consent`; real write and shell
calls were denied. Read-only inspection of the retained native/Consent output
confirms an exact settled matching outcome, one operation, 4801 input bytes,
16384 output bytes, zero model calls for that effect, generation-1 floor anchor
equal to its operation ID, and a typed-host-outcome source proof. The fixture
validates Saved and confirmed close. Its local synthetic model made loopback
requests for the preceding tool journey; zero effect model calls is not a claim
of zero provider activity for the whole fixture.

The authorized Session client explicitly lists/reads the genuine source handle
and invokes capture. The model did not call source tools or select capture.
This does not qualify automatic publication, live account/model quality,
arbitrary input promotion or guarded payload output. The copied journal retains
its original private SourceOrigin; relocation is not a new provenance owner.
The terminal fixture also emits an unused-variable warning; the claimed strict
production-owner compilation is separate from that launcher. The reviewer's
initial verifier mislabeled the approval as `headless`; its
[correction record](causal-root-cache-independent-review/initial-verifier-error.log)
preserves that read-only assertion mistake. Candidate evidence was unchanged.

For the separate source-tool slice, root-only request classification must not
substitute for selected-source result policy. SourceIndex/SourceWindow must
authenticate every selected occurrence and its causal union before observed
result hashing and ManagedUse release, including provenance omitted from list
and quote payloads. Fixed status-only notification can withhold terminal payload;
it does not authorize content-bearing result/model release. That implementation
and its exact freeze require a separate review.
