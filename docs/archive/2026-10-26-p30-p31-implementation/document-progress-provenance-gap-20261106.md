# Document progress provenance gap — 2026-11-06

Historical source-review finding against `6fc75341`. This qualifies the earlier
[Source/Index checkpoint](document-continuation-epoch-20261106.md), preserving its
actual focused results. Current limits belong to the [storage chapter](../../developer/knowledge-storage.md#fence-document-stages-before-metadata-maintenance)
and [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance).
No native experiment, model call or original-notebook access ran for this review.

## Counterexample

A Source put at epoch zero can finish its first immutable unit and return a
version-three continuation with unit one, no live stages, no active write and
the unchanged catalog stamp. After maintenance opens/closes to epoch one, a
caller can copy it, select version four/epoch one and recompute the public
`epoch_binding_sha256` from the same source hash and new counter.

Source's closed token and snapshot checks then accept those rewritten fields.
Catalog, source head and page checks can remain unchanged. The next immutable
unit can reach a mutation under epoch one. Its bytes may be valid, but neither
the public hash nor an earlier byte check authenticates the continuation's
original epoch/progress. Old native stage headers do not help when no stage
reference remains in that token. This is a source trace, not an executed attack.

The proposed hash-only Projection adaptation has the same problem and was
restored before testing or acceptance. Generic Job and lexical Index instead
join their token to a native stored job's identity, physical revision and epoch;
that separate anchor blocks this token-only relabelling.

## Disposition

The earlier unchanged-token/counter-only tests and Source/workspace integration
passes remain valid within their stated scope. They do not qualify hostile
counter-plus-digest recomputation. The earlier Source review did not cover that
case and is unqualified for this stronger continuation contract. Ordinary
document approval, namespace/source/current-use checks and native stage/CAS
fences were not bypassed by this finding; no wider authority is inferred.

Source and Projection need native progress provenance before general maintenance
or GC can open. The design under review uses bounded native owner/plan/epoch/unit
heads, couples progress to the actual successful unit CAS, verifies immutable
reuse under the lock and consumes progress atomically at terminal publication.
It must also account for transport reservations, known-operation/manifest bounds,
unknown outcomes and explicit reducing cleanup. No such repair or full capacity
result is implemented or accepted by this record.
