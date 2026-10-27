# Sustainable collection storage component

Dated implementation investigation, **2026-10-26**. This is historical evidence,
not a declaration that P31C1a or C1b is complete. Use the [current plan](../../plan.md),
[frozen contracts](contracts.md), [qualification protocol](qualification.md#storage-and-performance)
and [implementation index](index.md) for scope and outstanding gates. Native OS
facilities are committed as `91acd09`; Collection, migration and pure Notes remain
under active verification at this checkpoint.

## Ownership and bounded format

`Ipse.Extension.Collection.execute(root, project_sha256, request, operation_id)`
is an internal host boundary. The host supplies a protected operator root and
admitted project identity; extension workers receive neither arbitrary paths nor
new filesystem authority. Knowledge policy belongs in the package's pure Notes
module. The generic collection never chooses retention or infers content.

The version-2 root selects a hashed immutable manifest. Values are canonical JSON
maps in immutable SHA-256-named files. Each manifest bounds active records,
successful operation receipts, imported receipts, one staged import and one
rollback checkpoint. Logical limits are 6 KiB per complete value, 24 MiB active
record/evidence/history bytes, 8 MiB per manifest, 8,192 active records and 32,768
operation IDs. Exhaustion visibly refuses publication; IDs are never silently
reset. The total envelope is 64 MiB including staged values, both manifests,
pending root pointer, directories, retained locks and an 18 MiB control allowance.
The control owner must independently enforce that allowance and reclaim its
orphans. This component does not assert that absent integration.

`status` reports logical and allocated bytes separately. The dependency-free OS
primitive uses checked `MetadataExt.blocks() * 512`, including directory blocks;
unknown allocation fails closed. It does not estimate universal 4-KiB blocks.
The fully staged root pointer exists before the final allocation measurement.
Value writes are bounded native batches; each value is synced, then renamed to
its content hash. A manifest and root pointer are separately synced before the
root rename and parent-directory sync. Bounded GC preserves every active, staged
or checkpoint reference and removes at most 512 orphans per directory per pass.

Private staging uses exclusive 0600 creation. Each native writer acquires a
retained per-parent `.writer.lock` before readiness, receives at most one
acknowledged 16-KiB frame at a time, and creates no pending file before positive
payload. Collection GC, status and final allocation acquire the writer leases
under the logical collection lock. They release those leases before launching a
writer and reacquire after confirmed exit. Thus a stopped old writer cannot have
its still-open allocation hidden by reclamation after its owner dies. File
content never travels in argv or diagnostics. Native interfaces and bounds are
documented in the [native protocol reference](../../../native/README.md#write-protected-staging-files).

The existing external native logical-lock owner can itself die mid-I/O. Before
and after publication observations refuse a known lost helper and return an
unknown result, but these observations are not atomic fencing. Delegating the
final conditional switch to the actual retained flock owner remains an explicit
integration gate. No claim below closes revocation/CAS concurrency under that
fault. Operation intent and inspected unknown outcomes remain host-control duties;
Collection receipts prevent automatic replay of an already published operation.

## Internal operation shapes

Every request is an exact-key map; unknown fields refuse. `snapshot`, `status`,
`get` with `key`, `inspect` with `operation_id`, and generation-bound `scan` with
`after` and `limit` (1–32) are reads. `commit` carries `expected_generation`,
`advance_floor` and at most 128 `changes` containing `key`, `expected_revision`
and a JSON-map `value` or null deletion. Deletion requires floor advancement.
CAS conflicts do not publish. A previously successful operation ID returns its
original receipt even when the submitted request differs.

`export` pages at most 32 records under a fixed generation and returns a typed
descriptor containing project, generation, floor, counts, byte total and record
and receipt digests. `export.operations` pages at most 128 original receipts.
`import.open` takes `expected_generation` and `descriptor`; its operation ID is
the opaque migration ID. It fences ordinary writers. `import.page` takes that
ID, `expected_generation`, `after` and exactly the next 32 `records` (except the
last page). `import.operations` analogously accepts 128 sorted receipts per page.
`import.commit` validates every declared count and digest before atomic active
selection. Imported IDs survive a fresh-root import and rollback; a conflicting
receipt for the same ID refuses. `import.abort` clears staging. All migration
steps are themselves immutable operations and CAS-bound.

Import cannot go below the current suppression floor. Same-floor replacement
can retain one rollback checkpoint; `rollback` requires its `checkpoint_id` and
current generation. Destructive publication invalidates that checkpoint.
`checkpoint.drop` explicitly releases it. These operations accept no external
untrusted paths. The older bounded `import` merge exists only as a <=128-change
operation and is not the complete migration path.

Pure Notes constructors count all metadata and evidence within 6 KiB. A counted
64-byte metadata reservation lets an exactly maximal current assertion become
dated historical support without truncating evidence. Ordinary notes expire
after 90 days; reading never renews them. Pins, preferences and current temporal
assertions persist. Temporal supersession retains old support for at least 365
days. Operator overrides are explicit minimal lineage records, so session-only
policy, forgets and changed retention cannot be reversed by recapture or an old
backup. Shared evidence is not globally deleted. Session/Consent routing and
semantic qualification are separately owned and are not established by these
pure tests.

## Measurements and failed attempts retained

The independent development workload uses no qualification corpus, gold labels,
model downloads or live inference. It seeds 2,000 active notes including 200
persistent, then simulates 40 turns, 20 ordinary notes, four corrections, two
forgets and four temporal supersessions per day. It includes a seven-day offline
interval, explicit catch-up batches and fresh-VM reads every 30 days. Annual
maintenance is batched by day; 377 annual publications do not qualify the control
ledger for individual per-turn admissions. A separate requested 10,000-cycle
stratum performs one durable CAS operation per cycle.

An early driver used an infinite cyclic stream with eager enumeration. It grew
to approximately 17 GiB RSS and was terminated after approximately 52 seconds.
This was a driver construction failure, not a Collection capacity result. The
driver now constructs finite lists, validates days 1–365 and cycles 0–10,000,
limits its heap to 16 million words and has a linked 100-ms monitor for total VM
memory (512 MiB) and a 30-minute deadline; binary memory is measured separately.
Partial reports are written every 30 days or 100 cycles. These bounds limit a
failed measurement rather than relying on eventual OOM. The failed eager driver
never produced a qualified store result.

An earlier annual representative/10,000-cycle attempt reached at least cycle
1,000 before `status` became unavailable while an ordinary shared helper rebuild
overlapped. That attempt has no complete report and is not an annual pass. The
observed overlap does not establish its cause. Subsequent runs must pin a helper
matching the exact protocol and preserve that provenance.

| Earlier stratum | Publications | Reported result | Provenance limit |
| --- | ---: | --- | --- |
| [30-day representative](storage-early-30-representative.json) | 46 | p95 78.338 ms; 1,230,264 logical bytes | Serialized accounting; old 8-MiB control assumption; not current quota qualification |
| [365-day maximum](storage-early-365-maximum.json) | 377 | p95 141.297 ms; 4,372 records; 22,426,708 data bytes | 6,112-byte current-note fixtures, serialized accounting, old control reservation |
| [365-day maximum before protected writer repair](storage-pre-writer-365-maximum.json) | 377 | p95 175.329 ms; exact 6,144-byte initial current notes; 22,427,604 data bytes; peak allocated plus control 54,755,328 bytes | Exact allocated accounting and 18-MiB control reservation; predates writer lifecycle repair and final native fencing |

The last measurement's final allocated collection usage was 34,222,080 bytes;
with the control reservation it was 53,096,448 bytes. Peak VM memory was
114,261,928 bytes. Hardware was an Intel i7-12700K with 48 GB RAM, Linux,
Elixir 1.20.4 / OTP 29, four schedulers. These are development-machine results,
not reference-hardware latency acceptance.

Subsequent filesystem inventory established that all three earlier runs used
`System.tmp_dir!/0` on **tmpfs**, with `huge=advise`; their allocated-byte
observations are tmpfs results and their latency is not NVMe evidence. The
workspace resides on NVMe-backed Btrfs with `compress=zstd:3`; both filesystems
report 4096-byte units. A reported unit alone establishes no universal allocation
upper bound. Current reruns must record the actual selected filesystem/options
and use varied synthetic maximum-size payloads so compressible padding does not
hide storage growth. Same-owner staging and a preflight bound for old plus staged
allocation remain required before claiming the 64-MiB envelope.

Crash injection found a prior OTP staging open/chmod interval that could leave
an unsafe 0644 pending file after SIGKILL. GC correctly refused it rather than
repairing unsafe metadata. Native exclusive 0600 staging replaces that path.
The first stopped-reader implementation could saturate the generic stdio input
queue and sometimes report `cleanup_unconfirmed`; those failed fault tests were
not discarded as passes. Acknowledged 16-KiB frames now prevent queue saturation.
The pinned v5 native helper passed five Rust units and seven Runner tests; the
three backpressure/cancellation/stopped-owner-loss controls also passed three
consecutive reruns with the prior failing seed. Tests verify actual same-inode
kernel lease release as well as ordinary child exit, rather than using a PID as
signaling authority. Native Linux checks do not establish macOS or actual power
loss coverage.

Current-source Collection/migration tests, final pinned-helper endurance,
individual annual control receipt growth, whole-system quota enforcement,
atomic lock-owner publication and independent semantic quality remain open.
