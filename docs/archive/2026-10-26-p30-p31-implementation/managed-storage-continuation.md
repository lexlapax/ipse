# Bounded continuation of actual managed storage writes

Historical synthetic investigation, **2026-10-26 Pacific time**. This extends
the [completed 1,000-publication fixture](managed-storage-capacity.md) through an
explicitly reviewed benchmark oracle. It is capacity evidence for ordinary
literal records and their real managed metadata, not annual domain qualification
or installed-user acceptance. The [plan](../../plan.md) and
[qualification protocol](qualification.md) retain those gates.

## Bind the completed baseline before extending it

The [continuation module](../../../dev/knowledge/managed_storage_continuation.ex)
and [entry point](../../../dev/knowledge/managed_storage_continuation.exs) require
the exact successful baseline report, runtime manifest and native-owner root
receipt, each with its supplied SHA-256. Bootstrap verifies the baseline's
1,000 actual successful calls and 186,636 ms elapsed, checks every original
source/BEAM/helper byte and runtime version, then reads the complete current
Collection state. The root must equal the independently retained closed-root
digest. All canonical metadata blocks, current object byte lengths/hashes and
receipt shapes are checked, with a one-to-one note-generation sequence 1..1,000.

The baseline's historical in-memory normalization map was not saved. Bootstrap
does not invent it: the closed root digest binds the manifest and records that
the original terminal scan already verified. No note payloads or fake receipts
are copied into the new oracle, and no existing receipt is reexecuted.

The exact original wall-start timestamp is unavailable. The original 186,636 ms
stays a separate elapsed observation. Exact chronological timing starts at
bootstrap and includes later gaps/oracle work; no report claims exact
whole-series chronological time. Active segment elapsed excludes final oracle
commit time, which is separately measured.

The same copied **125-module Elixir 1.20.4** source/BEAM graph and actual protected
108c helper remain selected. Added continuation source is frozen under binding
`c2a14ef5edbad10d9e9149e5999be1662fbeba6560dd20323c8c1188589d6547`.
Elixir 1.18.5 formatting success is not execution or BEAM compatibility evidence.
Concurrent product changes are not incorporated between segments.

## Stop at a confirmed bounded boundary

Bootstrap is segment 1 and performs zero Collection publications. At most eight
segments, each with at most 1,000 new calls, may reach 2,000 and then 4,000 total
captures **including the original 1,000**. At most 3,000 new publications are
permitted. Each process keeps an eight-minute hard guard, six-minute soft
boundary, 512-MiB sampled BEAM bound and 16-million-word main-process heap bound.
The first publication refusal, unknown outcome or guard stop ends the run.
Source IDs are never reshuffled to avoid a full shard.

Before any continuation work, the short native oracle transaction writes a
pending marker and releases its lock. No oracle lock spans a Collection call or
workload loop. Resume checks every previous checkpoint/report hash, the complete
current root, value/revision digest, retained receipt ledger and applied lineage.
Every new original request and normalization binding is checked against its
returned receipt. New note rows and updated metadata hashes are accumulated as
an expected state; a final complete native-owner scan must match all rows and
all receipts exactly before the oracle publishes a clean checkpoint.

Each oracle directory has a separate 8-MiB quota, with checkpoint plus report
limited to 2 MiB and eight directories total. This bounded benchmark overhead
is measured separately from product managed-file allocation. Product ceilings
remain 24-MiB logical, 42-MiB Collection and 22-MiB control reservation within
64 MiB. There is no expanded filesystem or payload allowance.

An existing future segment, missing/dirty oracle, source drift, changed root or
checksum mismatch refuses. Unknown outcomes have no automatic retry. A known
capacity refusal also leaves the segment marker pending; it cannot be promoted
to a clean continuation. The separate interrupted ordinary-v4 annual store and
its marker are never touched by this protocol.

## Verify controls before the first bootstrap

Six focused developer tests passed. The first pure compile found a local helper
named `binding/1` conflicting with imported `Kernel.binding/1`; renaming the
helper fixed it before any store effect. The failed log is retained separately.
The [native control driver](../../../dev/knowledge/managed_storage_continuation_check.exs)
then verified clean oracle reading and refusal for pending markers, existing
segments, bad checksums and a corrupt checkpoint. It deliberately changed and
restored a known private source-file fixture to prove fingerprint drift detection.
Only its isolated fault fixture's injected marker was reclaimed. Two complete
read-only Collection inspections confirmed the actual 1,000-publication root
unchanged throughout; no actual capture was added by these controls.

Bootstrap subsequently finished with zero new publications in 1,003 ms plus
29 ms oracle commit time. Native oracle peak/final allocation was
77,824/73,728 bytes; checkpoint plus report serialized to 73,600 bytes. Its clean
checkpoint was read and validated before any extended publication.

## Outcome scope

The first extended segment reached **2,000 notes from 2,000 actual individual
publications**, including the original 1,000. A complete native-owner scan checked
all 2,956 records and retained receipts against the expected state. Later clean
soft boundaries reached 2,817 and then 3,467 notes. **The 4,000-note target
failed:** segment 5 stopped at its first refusal after 3,724 successful actual
publications, with no retry or source-ID reshuffling.

| Segment | New / total publications | Active elapsed | Managed allocation peak | Sampled BEAM peak |
| --- | ---: | ---: | ---: | ---: |
| Bootstrap | 0 / 1,000 | 1,003 ms | no publication | not a capacity sample |
| 2 | 1,000 / 2,000 | 330,054 ms | 36,278,272 B | 92,193,680 B |
| 3 | 817 / 2,817 | 362,073 ms | 40,873,984 B | 104,890,272 B |
| 4 | 650 / 3,467 | 361,731 ms | 44,724,224 B | 112,857,560 B |
| 5, refused | 257 / 3,724 | no final duration | no final peak retained | no final peak retained |

Completed segments retained actual callback latency arrays. Nearest-rank
p50/p95/maximum were 319.613/403.902/1,190.421 ms for segment 2,
427.454/522.568/679.417 ms for segment 3, and
536.724/641.354/2,493.418 ms for segment 4. These include publication callbacks,
not source construction or complete diagnostics. No isolated reference-performance
window was established; these measurements support no performance pass.

At 2,817, logical data was 12,551,812 bytes: 9,363,708 note bytes, 332,640
anchor bytes and 2,855,464 live-metadata bytes. Segment 3's separately bounded
oracle peaked at 217,088 allocated bytes, ending at 212,992 bytes; its checkpoint
and report serialized to 207,494 bytes. The clean checkpoint was read and checked
against the unchanged runtime binding before the next segment began.

Segment 4 exited zero, and its clean native oracle checkpoint was checked before
the final bounded continuation began. Its complete population contained 3,467
notes, 308 anchor pages and 1,070 live pages. Logical bytes were 11,524,308,
407,708 and 3,512,538 respectively. The separately measured oracle peak/final
allocation was 262,144/258,048 bytes; serialized checkpoint/report bytes were
251,672. No prior receipt was synthesized or replayed between these boundaries.

### Diagnose the first refusal without repair

The [failed request and context](managed-continuation-segment5-failure.json) and
[exit-1 log](managed-continuation-segment5.log) identify attempted publication
3,725 as `{:error, :managed_normalization_refused}`. The last periodic sample was
generation 3,700 at 143,809 ms with a 46,075,904-byte managed allocation peak.
The failure path retains the request and generation but omits its in-memory
latency array, elapsed duration and maximum BEAM sample. Those final-segment
metrics cannot be reconstructed or presented as complete measurements.

A [complete read-only inspection](managed-continuation-refusal-inspection.json)
validated 3,724 note generations, 3,724 retained receipts and all canonical
metadata/value bytes. The attempted operation and note were both absent. The
selected live shard, `189`, had four pages of four entries each: its sixteen
slots were full, and the refused candidate would need a seventeenth. This is a
fixed-shard capacity limit, **not exhaustion of the global byte ceilings**.

| Retained final population | Actual observation |
| --- | ---: |
| Notes / anchor pages / live pages | 3,724 / 333 / 1,133 |
| Total records | 5,190 |
| Note / anchor / live logical bytes | 12,378,576 / 438,067 / 3,771,902 |
| Combined logical data | 16,588,545 B |
| Final native Collection allocated files | 23,044,096 B |
| Final usage plus 22-MiB control reservation | 46,112,768 B |

The [native-owner root receipt](managed-continuation-final-root.json) confirms
wire version 5, generation/floor 3,724 and root SHA-256
`840fa00f9f5f78b278d4622d4ac95a551c3ba8f48c60e6316d7a6d7008b30e41`.
The frozen `c2…6547` runtime binding still matched. The actual pending marker,
`.pending-92286e06f3db0024d10c50fec37c1cff`, remains untouched in segment 5's
oracle directory; its exact fixture bytes are [preserved separately](managed-continuation-segment5-pending-marker.json).
There is no final segment-5 report or clean checkpoint. Oracle reading refuses
the dirty directory, whose native allocation is 4,096 bytes. The confirmed store
is retained for diagnosis and cannot be resumed through this continuation chain.
No ceiling was raised and no new store or replacement candidate was attempted.

The last eligible boundary's cumulative active segment time was 1,054,861 ms;
chronological time from bootstrap through that boundary was 1,286,356 ms. The
original 186,636-ms baseline stays separate. These omit the unfinished segment's
complete elapsed measurement and are not whole-series timing or performance
qualification. Native allocation includes allocated files/directories and the
conservative control reservation; it does not measure filesystem journal/free-space
allocator consumption. BEAM samples are not process RSS.

The [artifact manifest](managed-continuation-artifacts.json) binds all preserved
reports, checkpoint bytes, logs, inspection sources and the runtime freeze.
[Source reconstruction](managed-continuation-source-reconstruction.json) checked
all 126 original source files against commits `b55623d` and `423b69f`; the new
continuation sources are retained with this evidence. Later product source and
native-helper changes were never incorporated into the series.

Every report keeps overall qualification false. The logical clock remains fixed
for this population, so these new-literal
writes do not demonstrate expiry, recapture, correction, forgetting, pinning,
temporal history, pending acceptance or annual turnover. Synthetic host receipts
do not prove a human/native terminal origin. Session/Consent/model paths and
reference performance qualification remain outside this fixture.
