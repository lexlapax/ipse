# Retained receipt geometry — 2026-11-02

Author-run pure development probe from `bd222bf` plus the new probe source.
It supplements the [native operation floor](native-workload-budget-20261102.md)
and changes no runtime, permission, ID limit or byte bound. The
[plan](../../plan.md) owns acceptance and the
[storage training chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns the runnable procedure. The [machine record](native-receipt-geometry-20261102.json)
retains source/SDK/log hashes and all twelve observations.

## Test the next bound before choosing a repair

The current `Blocks` encoder limits retained IDs to 32,768 and also bounds the
complete canonical packed state to 8,388,608 bytes. `Encoding.encode/1` can measure
a synthetic larger state without publishing or claiming that it is decodable.
The probe calls the actual current `Blocks.encode/1` independently to retain its
acceptance/refusal result.

For each count, the probe compares unbound and managed receipts, and zero versus
2,000 selected public-record descriptors. Every receipt has its original
generation, request hash and destructive floor; managed rows also have a binding
hash. Every operation in this scenario advances the floor, with exact retained
lineage IDs. The 2,000 descriptors use native-shaped `note.HASH` keys, revisions,
value hashes, operation IDs and byte counts. No actual value objects or domain
sidecars exist, and there is no authenticated-domain publication.

| Managed receipts | Selected descriptors | Canonical packed bytes | Current block encoder |
| ---: | ---: | ---: | --- |
| 22,980 | 2,000 | 4,899,325 | Encodes synthetic metadata |
| 32,768 | 2,000 | 6,729,681 | Encodes synthetic metadata |
| 42,980 | 0 | 8,026,433 | Refuses the ID count |
| 42,980 | 2,000 | 8,639,325 | Refuses the ID count; packed bytes separately exceed 8 MiB |

The final row exceeds the canonical-state ceiling by **250,717 bytes**, before
sidecars, import/rollback overlap, additional expiry operations or ratified
pilot intake. Merely increasing the ID constant cannot make that scenario fit.
This does not prove that every annual workload has this exact receipt/floor mix;
that requires the actual supported effect ledger and ratified cycle semantics.
It does establish a second concrete constraint for design work. A redesign must
account for both, retain recovery and duplicate-detection semantics, and then
demonstrate actual native allocation and workload behavior.

## Verification and limits

The repository command exited **0**, produced twelve JSON rows and no warnings.
Its output agrees with the prior independent temporary serialization probe for
all twelve row bodies. It starts no Ipse application, Session, native helper or
store and executes zero domain mutations or turns. The temporary first probe
emitted an unused-alias warning; that observation is retained in its own log,
and the unused alias is absent from the repository probe.

The owning developer chapter and operator knowledge-permission manual were
reviewed as whole documents. The new procedure is integrated with workload
budgeting; operator behavior and permission limits remain unchanged. Format,
documentation links and the exact command are checked in the machine record.
The frozen `9f1707c` complete suite was still running independently; this probe
changes none of its source, compiled runtime or helper inputs.

There is no native allocation, migration, peak-resource, latency, semantic-quality
or endurance acceptance here. No receipt is pruned, reset, compacted or converted;
no ID or byte limit is increased. Both annual-cycle interpretations remain
explicit and unratified. The full P30/P31 goal remains open.
