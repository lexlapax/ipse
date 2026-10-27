# Immutable metadata blocks and physical import checkpoint

Dated investigation, **2026-10-26**. This is an internal, unshipped component
checkpoint with a successful distinct-payload physical import control. It does
not complete P31C1a/C1b. The [v3 checkpoint](storage-correctness-v3.md)
retains the preceding exact source and failed physical same-store import probe.
The [current plan](../../plan.md), [contracts](contracts.md) and
[qualification protocol](qualification.md#storage-and-performance) remain
acceptance authorities. No annual individual workload, reference-hardware p95,
platform qualification or complete allocated-file invariant is claimed here.

## Reconstruct exact records from immutable blocks

The internal Collection request and typed export shapes stay unchanged. A
version-4 generation replaces inline receipt maps, record indexes and ordered
applied proof arrays with flat references to bounded immutable files in the
existing `manifests` namespace. Every reference binds kind, position or binary
prefix, count, serialized size and SHA-256. Its hashed file binds the same kind,
position/prefix and rows, plus block version 1. There are no child references or
recursive file graphs.

Local receipts use fixed chunks of 256 consecutive generations. Only the last
partial chunk changes on append. Imported aliases use deterministic binary-prefix
partitioning of SHA-256 of the full operation ID, with at most 256 rows per leaf.
Record indexes use the same partition rule with at most 128 records per leaf;
active, staged and checkpoint records participate separately. A new alias or
record changes only its leaf, splitting when necessary. Partition depth is at
most 256; clustered input that exhausts a bound refuses without dropping rows.
Applied lineage uses fixed 512-ID chunks, including the proof inside a staged
source descriptor. The original semantic descriptor and receipt shapes are
reconstructed before domain validation and export hashing.

Each block is at most 64 KiB. A generation has at most 1,024 references and at
most 1,024 distinct blocks, with at most 9 MiB of distinct serialized block bytes.
The reconstructed inline version-3 encoding still has its 8-MiB metadata ceiling.
The 32,768 total receipt-ID ceiling and per-index 8,192-record ceiling remain.
Declared aggregate counts and byte sizes refuse before block reads. Decoding
checks every content hash and exact size, lossless receipt reconstruction,
cross-class duplicate IDs, local generation continuity and canonical partition
reconstruction. Unknown fields and noncanonical partitions refuse even when an
attacker recomputes their content hashes. These hashes establish integrity, not
backup provenance or permission.

Publication verifies existing immutable files before reuse. New blocks are
staged, synced and installed through the actual retained transaction owner before
the new generation and root are selected. The old authoritative generation and
all its blocks remain reachable until the root switch is confirmed. Reclamation
marks every active, staged, checkpoint, receipt and applied-proof block from the
validated loaded generation or the exact new encoding. Those marks are reused
only within the same held transaction; no cross-operation content cache weakens
subsequent validation. A post-root reclamation error makes the result unknown.

## Reserve the complete import and an abort

The 64-MiB managed allocated-file envelope remains 22 MiB of control reservation
and 42 MiB for Collection. The 24-MiB logical value-reference envelope and 6-KiB
complete value limit are unchanged. Native admission still reserves twice every
planned file's length rounded to the explicitly supported runtime allocation
unit. No stable-fsync or universal 4-KiB estimate replaces that allowance.

A full planned import preflights all missing values and metadata before opening
the writer fence. Immutable blocks that are reachable at successful open and
unchanged throughout paging need one set: full local receipt chunks, active
record indexes, already-known and admitted source aliases, and applied proofs.
Variable local tails and staged record indexes reserve two sets for a late page's
previous and next metadata. The terminal abort has its own additional new block,
generation and pointer reservation. Abort retains inspected source identities
without adopting source applied lineage. Record pages and final digests remain
mandatory even when all payload files already exist.

The existing native command accepts at most 256 planned sizes. A plan beyond
that bound still refuses; importing thousands of genuinely missing files needs
a separately reviewed bounded accumulator. The larger format does not bypass
that gate. Explicit nonzero legacy state without applied ancestry still refuses;
valid internal inline state may upgrade on a successful write.

## Preserve failures before interpreting results

The first actual-protected v4 focused run passed **48 of 49** checks in 70.1
seconds. Its [sole failure](storage-v4-first.log) was a planner refusal during
inline-to-block migration: counting two copies of every future block exceeded
the native 256-size command bound. The repair reserves one set only for proven
immutable metadata, retaining two sets for variable metadata and the additional
abort allowance. A targeted control observes a bounded plan before the first
staged publication and then runs every import page.

That control admitted open and the bounded-plan assertion, but [timed out at
300 seconds](storage-v4-plan-timeout.log). Direct inspection of the owned synthetic
fixture shortly before timeout showed generation 21,070: 119 of 128 pages had
completed after the initial 20,950-receipt state. This was a finite-progress test
timeout, not a capacity failure or a latency pass. Repeated full encoding for
reclamation and abort comparison was then removed within the held transaction.
The [same guard still timed out](storage-v4-marked-timeout.log) after that narrow
optimization. The closed receipt schema was then shown to admit at most 241 JSON
bytes, including both optional IDs, maximum safe counters and fixed ASCII hashes.
Its redundant per-receipt JSON encoding solely to check 512 bytes was removed;
all closed shape/type/ID/counter checks and actual encoded block ceilings remain.
A maximum-shape unit assertion binds the 241-byte proof and the 512-byte ceiling.
The 300-second test guard was retained. Logs preserve their diagnostic text with
trailing whitespace normalized. The [failed-runtime provenance](storage-v4-failed-runtime-provenance.json)
binds the exact executed BEAM files and archived diagnostic hashes for all three
attempts; no missing historical source snapshot is invented.

Pure block/codec/plan controls passed 16 checks before this narrow optimization.
They include a lossless 20,950-receipt population, block reuse after append and
arbitrary alias insertion, malformed prefixes, aggregate refusal before any read,
missing files and cross-class duplicates. A small actual-protected pair checked
ordinary publication/GC and refusal before reclamation when an authoritative
metadata block becomes unsafe.

The first v4 whole-app strict compilation passed 113 files into the unique
`/tmp/ipse-collection-v4-checkpoint-20261026-01` snapshot. Subsequent narrow repairs
used new private copies of that completed snapshot, with a private copy of the
actual protected helper. Selection still verifies the compiled SHA-256:
`385f42879330838a8635af4689d5c9fd422c6f19beb9de72b710474ac08f216c`.
No production helper override or shared build path was used. A fresh complete
114-file strict compilation then incorporated native-owner reading, followed by
a warning-free four-module component recompile for the closed receipt proof.
The [full current focused run](storage-v4-native-read-focused.log) passed **52 of
52** checks in 325.1 seconds, seed 202131, `--max-cases 1`. Its complete paged
upgrade finished within the unchanged per-test guard. The final stronger receipt
assertion and Notes controls passed [17 of 17 supplementary pure checks](storage-v4-final-pure.log).
Another component's control stress overlapped; these are functional controls,
not comparative IO or latency evidence.

## Measure the complete distinct-payload import

The independent [block probe](../../../dev/knowledge/storage_blocks_probe.exs)
created 4,096 distinct exactly 6,144-byte values using hash-derived varied
synthetic evidence. It seeded 20,950 valid synthetic floor-zero receipts; it did
not perform 20,950 individual transactions or exercise persistent-note policy.
Every fixture file was staged, synced and installed through the same actual
native owner with its unchanged 42-MiB quota. The probe had a finite 20-minute
guard, a 512-MiB sampled VM-memory guard and a 16-million-word driver heap bound.
It retained its store. It made no model calls, downloads or qualification/gold
fixture reads.

After the focused suite passed, the invocation was:

```sh
MIX_BUILD_PATH=/tmp/ipse-collection-v4-closed-receipt-20261026-01 mix run --no-compile dev/knowledge/storage_blocks_probe.exs --parent "$PWD/_build/storage-workloads" --output /tmp/ipse-physical-blocks-probe-20950-v4.json
```

The [exact raw receipt](storage-v4-physical-planning.json) binds seven source
hashes, the retained store and the actual protected helper SHA-256
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
The selected workspace NVMe mount reports Btrfs, 4,096-byte block/fragment units,
`compress=zstd:3`, `ssd`, `discard=async` and `space_cache=v2`. The kernel reports
7.2.10. The other component's annual control stress was active throughout; the
receipt explicitly sets concurrency true and performance/overall qualification
false.

| Counter | Measured value |
| --- | ---: |
| Distinct logical value bytes | 25,165,824 |
| Initial metadata blocks | 128 |
| Initial generation manifest bytes | 17,426 |
| Collection allocated before import | 36,163,584 |
| Collection allocated after rollback | 36,179,968 |
| Maximum observed staged allocation plus 22-MiB control reserve | 60,284,928 |
| Complete record pages | 128 |

Planned open, all record pages, final commit and floor-safe checkpoint rollback
completed. The final generation was 21,081, floor zero, with no import fence or
checkpoint. Re-export confirmed the exact original record digest and every
original full receipt. No failed or unknown operation was retried. The measured
staged total stayed below 67,108,864 bytes. This repairs the preceding physical
same-store import control; it does not qualify an annual individual workload,
persistent domain policy, arbitrary missing-file imports or reference-hardware
latency.

## Keep policy and lifetime gates explicit

The pure Notes review found three actual failing controls before repair: prior
preference support expired at 90 days after supersession, a duration override
applied only to the replacement, and an unrelated new claim's override could be
accepted while its old support belonged to another lineage. The [before output](notes-lineage-before.log)
records 5 of 8 passing. After the narrow repair all 8 passed. Prior current and
preference support now retain 365 days; pinned support remains persistent.
Ordinary corrections keep their existing ordinary deadline. A supplied override
must match both returned derivatives; otherwise the host needs separate lineage
lookups. A same-lineage replacement of a previously overridden note refuses when
the saved override was not supplied. Session-only suppression returns no saved
current/history derivatives. The host still owns admission and authoritative
suppression lookup before storage publication.

Review also found a separate allocated-file lifetime gap: a host-side
ordinary read can retain a file descriptor while the native logical owner dies.
A later owner's reclamation could unlink that still-open inode, hiding its bytes
from inventory until the read finishes. Before/after lease checks reject stale
output but do not establish descriptor closure. Collection now routes every
root, metadata-block and value read through native-owner `Transaction.read/4`.
The selector is derived only from its held protected root and the direct
`objects`/`manifests` namespaces. No ordinary host data-file read FD remains in
Collection. Existing owner/mode/single-link/size and content/schema checks remain.
The 52 focused controls and physical probe use that repaired channel; the
[native contract](../../../native/README.md#publish-protected-state-through-its-lock-owner)
and [training manual](../../developer/persistence.md#serialize-protected-consent-before-publication)
explain the shared facility. Independent adversarial review, complete control
and identity lifetime evidence, other-kernel/APFS support, full missing-file
import planning, host semantic integration and individual annual workload gates
remain open. No endurance run started at this checkpoint.

The current operator [Memory manual](../../operator/memory.md), developer
[State exercise](../../developer/extension-state.md), complete
[persistence chapter](../../developer/persistence.md) and operator
[recovery manual](../../operator/recovery.md) were reviewed as whole documents.
Their shipped legacy State limits and explicit approval/recovery procedures
remain separate from this unshipped Collection API; no existing namespace limit
was raised or sharded. The dated component explanation here preserves current
implementation and verification without adding an unusable operator procedure.
