# Actual primitive turnover and bounded continuation controls

Dated investigation, **2026-10-26**. This is development-authored synthetic
Collection/Notes fixture evidence, following the [v4 block checkpoint](storage-v4-blocks.md).
It does **not** complete P31C1a, E, default enablement, domain capture, or release
acceptance. The [current plan](../../plan.md) and [qualification protocol](qualification.md)
remain authoritative. The annual run was pending at the original checkpoint.
The later [segment-1 outcome](storage-annual-s1-incomplete.md) is **incomplete,
with termination cause unknown** and no eligible continuation. The original
30/90-day results and continuation-control evidence below retain their scope;
they do not establish annual acceptance.

## Separate the storage fixture from a conversation

The driver creates 2,000 eligible notes through 16 actual publications: 1,800
ordinary notes distributed over the previous 90 days, 100 pins, 50 preferences
and 50 current temporal assertions. These are actual payload writes, without
seeded operation receipts. Each ordinary workday performs 20 additions, four
ordinary corrections, two explicit forgets, four temporal supersessions and an
expiry-maintenance publication. Day 90 doubles intake and corrections/forgets/
supersessions. Each action is published separately, subject to the existing
128-change bound for a maintenance batch.

Ordinary correction history keeps its original deadline; temporal history keeps
365 days from supersession. A selected initial temporal assertion remains
untouched until day 100. Pins/preferences/current values stay persistent. Pure
policy checks exercise its delayed history and exact maximum payloads. New
payload padding varies deterministically with SHA-256-derived evidence.
Replacement or deletion advances the destructive floor; a pure addition does not.

The seven-day offline interval queues exactly 217 known-unstarted actions. It
issues no operation IDs while offline. Resumption publishes every queued action
individually and compares the result with the pure model. The 10,000-cycle phase
is explicitly generic one-key update/delete/recreate receipt churn, rather than
a claim of 10,000 authenticated domain forgets.

The evidence maps are synthetic JSON, not authenticated Sources artifacts. No
Session, inference, actual capture pipeline, paid account, model download or
qualification/gold corpus is involved. Forty turns per day is a **nominal**
workload label, not forty reads or actual turns. Explicit-forget overrides are
retained as actual rows. Expiry currently removes the note without a durable
expiry-lineage override, so recapture TTL protection and sustainable domain
suppression metadata remain unverified. Those flags are false in every report.

Native allocated-file telemetry runs on every publication, including the root
reservation. Diagnostic status and a selected exact value/revision read run
daily and every 100 cycles. Each read checks the expected generation and record
count; every 30 days a fresh OS VM reads the snapshot. Serialized-disk maxima
are daily samples: the v1 JSON field `peak_accounted_disk_bytes` must be read
with that sampling qualification. It is not the every-publication allocated peak.

## Observe 30 and 90 days

The complete private source graph strictly compiled 117 application files.
Its [source/application-BEAM manifest](storage-workload-runtime-v1.json) and exact
[original driver](storage-workload-v1.exs) preserve the tested input. The helper
is the actual protected binary
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
All files and stores are synthetic. The selected workspace Btrfs mount is the
same mount as the earlier physical probe: 4,096-byte units, zstd:3, ssd,
discard=async and space_cache=v2, kernel 7.2.10.

| Actual result | 30-day representative | 90-day maximum values |
| --- | ---: | ---: |
| Commit calls | 946 | 2,836 |
| Migration writes | 0 | 89 |
| Read calls | 63 | 274 |
| Retained operation IDs / final generation | 946 | 2,925 |
| Final records, including history/overrides | 2,242 | 2,750 |
| Elapsed driver wall | 305.246 s | 1,090.666 s |
| Observed publication p50 / p95 | 281.709 / 392.019 ms | 335.444 / 489.821 ms |
| Every-publication managed allocated peak | 33,083,392 B | 46,727,168 B |
| Maximum post-publication BEAM memory sample | 98,315,672 B | 163,165,712 B |

The [30-day receipt](storage-workload-30.json) and [90-day receipt](storage-workload-90.json)
contain exact counters, source hashes, filesystem details, retained stores and
false qualification flags. Managed peaks include the unchanged 22-MiB control
reservation; Collection retains its 42-MiB budget, 24-MiB logical envelope and
6-KiB complete-value ceiling. Memory samples are BEAM memory, not peak process
RSS or whole-machine memory.

The day-90 burst, complete 32-record paged same-store import, atomic commit,
checkpoint drop and fresh-VM inspection passed. The import took 71.097 seconds.
Another component's individual control-ledger stress overlapped both runs:
these latency observations are **not** reference-hardware performance
qualification. They do not demonstrate two concurrent Collection writers.

## Keep annual continuation honest

The observed 90-day inclusive wall per write projects beyond the original
two-hour guard before accounting for later receipt growth. The revised
[entry point](../../../dev/knowledge/storage_workload.exs), shared
[workload implementation](../../../dev/knowledge/storage_workload.ex),
[segmented runner](../../../dev/knowledge/storage_annual.exs) and
[oracle](../../../dev/knowledge/storage_continuation.exs) therefore permit at most
four explicit segments. Each process keeps the original two-hour deadline,
512-MiB sampled BEAM guard and 16-million-word driver heap bound. A soft boundary
after 6,000 publications or 90 minutes stops only after a confirmed day or
100-cycle unit; it does not retry an uncertain operation.

The [final annual-runtime manifest](storage-workload-runtime-v2.json) binds 125
source files and 550 dependency/application/consolidated BEAM files, the same
117-file application source graph, and the protected 108c helper. ERTS system
version includes its two-scheduler configuration; continuation commands retain
`ERL_FLAGS='+S 2:2'`. A first manifest check with default schedulers detected that
configuration mismatch before writing a manifest or calling Collection; the
matching two-scheduler check passed. The source/BEAM graph remains immutable.

Segments use the **same** actual persistent store. A protected benchmark-only
oracle creates a durable pending marker before Collection work and releases its
short native transaction before any Collection call. At a confirmed boundary,
the driver exports every actual record and complete receipt ledger, checks all
values/revisions, then atomically writes a payload-free checkpoint and hashed
report and removes the marker. The oracle transaction is short and never spans
a workload loop, Collection operation or model call.

Resume requires the exact source, dependency/application/consolidated BEAM and
helper binding, the expected checkpoint hash, a clean marker state and an exact
descriptor. It scans all records, checks the saved revision/value digest,
reconstructs the pure model at its original timestamps, and validates each
earlier receipt prefix and ordered applied lineage. No seed, copied backup,
synthetic receipt, retention renewal or store reset is used for continuation.
Pending/unknown work, source drift, changed roots or existing future segments
refuse. Earlier reports/checkpoints are chained by their hashes.

Each segment oracle has a separate 8-MiB ceiling, at most four directories;
checkpoint plus report must fit 2 MiB. This is out-of-band benchmark overhead,
explicitly excluded from product managed usage and measured separately. Reports
separate startup-validation reads and oracle commit time. Chronological wall
includes oracle writes and restart gaps; the active endpoint metric explicitly
ends before each final oracle commit.

The first control [refused before any Collection call](storage-continuation-first-failure.json)
because helper fingerprinting selected the private application directory as a
workspace. Selecting the protected external fixture directory repaired that
driver-only error. A later copy command used the private working directory and
repeated the changed-root control; it was not counted as a source-binding pass.
No store or receipt was reset to conceal either attempt.

The [three-segment control](storage-continuation-three-segments.json) progressed
47→78→81 real writes with full receipt-prefix verification. The final
[maximum-value control](storage-continuation-max-control.json) progressed 47→48
on one persistent store after expanding the fingerprint to consolidated BEAMs.
The [refusal controls](storage-continuation-refusals.json) preserve an unchanged
47-ID Collection for pending marker, extra segment, checksum, binding and segment
limit checks. A known fixture-injected marker was removed only by the test
fixture, never by automatic driver repair. A separate
[changed-root refusal](storage-continuation-root-refusal.json) observed generation
48 after one explicit foreign test write and performed no further write.
[Source drift](storage-continuation-source-refusal.json) refused before any
Collection call. [Checkpoint corruption](storage-continuation-corruption.json)
left the completed 81-ID Collection unchanged. The
[three pure checks](storage-continuation-pure.log) cover closed/tampered progress,
runtime binding, revision/value digests and offline reconstruction.

The native preflight still accepts at most 256 planned files. A later annual
same-store import may exceed that metadata-plan bound; any refusal must remain a
failed required migration gate with source generation/floor/fence inspection.
Ordinary write completion cannot turn that failure into overall acceptance.
The reviewed filesystem profile remains limited to the explicitly supported
Linux kernel/Btrfs/tmpfs combinations; other kernels and APFS remain open.

These frozen runs exercise ordinary v4 roots on the comparable 117-module graph.
Concurrent managed-root/managed-reference work, its additional receipts and
packed source anchors, is not picked up mid-run. That graph needs its own actual
domain annual qualification. No result here closes the Source/expiry-override,
turn-pipeline, managed-root, platform or default-release gates.
