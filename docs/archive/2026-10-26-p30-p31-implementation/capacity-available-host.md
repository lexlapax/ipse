# Available-host managed V3 capacity continuation

Dated **2026-10-28**. This is a bounded synthetic capacity investigation, not
production kernel admission, turnover, current-source authority or release
qualification. The [plan](../../plan.md) owns delivery status and the
[earlier failed population](managed-storage-continuation.md) remains preserved.

The historical 3,724-publication refusal used fixed V2 shards. Current
`ManagedPages`, its repair planner and `NormalizerV3` already use ordered,
authenticated IMB2 pages; no new production geometry rewrite was necessary.
The unused capacity controller could not yet exercise that implementation:

- Its candidates and shared normalizer fixture still treated plain interactive
  input as literal authority. Trusted-function fixtures now use explicit
  category-specific `native_operator_assertion` members. This simulates an
  already authenticated review; it supplies no terminal or human evidence.
- The added proof fields made the former escaped control exceed the unchanged
  2,048-byte proof limit. Controls now use 248 escaped bytes, yielding a 2,045-byte
  proof and a 5,567-byte ordinary note. Exact values and hashes are frozen before
  effects. Other values are 3,334 bytes for 200 preferences and 3,339 bytes for
  3,796 ordinary notes. This is a declared workload, not an exact maximum proof.
- Test subprocesses now inherit the actual runtime beam paths and use unique
  temporary directories. They no longer assume `_build/test` or collide across
  separate VMs.
- The source-derived publication loader now accepts public or private
  `publish/4`, then requires that function plus `verify_publication/5` and
  `snapshot/2` before bootstrap can finish. The actual fixture had made
  `publish/4` public; the old loader silently omitted it.

Plan version 4 explicitly selects `available_host_diagnostic`, the private
test-only Linux 7.2.11 profile and helper SHA-256
`86d6226c868b7095c6ba7460cc0b42832e98fb70feea0779fb3473ac7bb28a6a`.
It requires `production_admitted: false`; old unlabeled plans refuse. Product
kernel admission is unchanged. No `IPSE_RUNNER_PATH` override is accepted.

## Focused controls and retained failure

The private graph compiled 159 modules with warnings treated as errors. The
first selected run (46720) passed 49/56; it exposed the stale proof/control and
subprocess assumptions above, plus two obsolete historical-source expectations.
The repaired [46721 selection](capacity-available-host/focused-46721.log) passed
55/56 in 19.4 seconds; its remaining historical fixture used mismatched recipe
digests. The corrected historical interpreter/recipe fixture then
[passed its sole selected case](capacity-available-host/historical-46722.log)
(46722, 3.2 seconds, 34 excluded, exit 0). It creates signed legacy native-answer
and fragment literals under a deliberately permissive interpreter, then proves
the current host refuses them. The journal-owned plain-input test now checks
an authenticated never-current proposal and refuses a literal dependency.

An actual pinned-helper [directory-sync control](capacity-available-host/native-sync-control.log)
passed before the first workload. That proves the observed native sync path,
not persistence after power loss. The first graph/store pair,
`_build/capacity-sol-20261028` and
`_build/storage-workloads/ipse-managed-v3-capacity-sol-20261028`, stopped before
publication 1 because the old source loader had omitted public `publish/4`.
Its oracle remains pending, no clean receipt exists, and no Collection root was
created. The controller refused the unsuccessful child. Nothing was replayed.
The original frozen driver was restored and matched its recorded plan digest
`4847389cca6d40fc84d15735cc58ecb64dd2a6efbca6bbb4709998ffb9c6bd4e`.

After repairing the loader, the strengthened non-native
[bootstrap control](capacity-available-host/bootstrap-46723.log) passed one
selected case (46723, 1.3 seconds, 20 excluded, exit 0). A new graph/store pair
with suffix `-02` was then compiled and frozen; the first failed pair is not a
continuation source.

## Current bounded run

The corrected graph is `_build/capacity-sol-20261028-02`; its store is
`_build/storage-workloads/ipse-managed-v3-capacity-sol-20261028-02`.
Plan file SHA-256 is
`546471ff93133a026f25bac1ac528add2b22399e5e9deed31c2d66e90611acfc`;
runtime binding file SHA-256 is
`9abf0874c1d753188d8febf85426dae11245ccdaf609848c24895af11a3ab303`.
Each admitted segment performs at most 500 actual managed publications and
checked readbacks. There are eight possible segments, with no automatic retry.
Each has a 360-second soft bound, 480-second hard bound, sampled 512-MiB total
BEAM guard and 16-million-word main heap bound. Continuation requires matching
plan/runtime/source bytes, a complete checked oracle/root, matching call records
and terminal report, an observed zero process exit and the immutable clean
controller receipt. Unknown or refused work stops without replay.

Segment 1 completed 500 actual publications in 111,680 ms. Its final population
was 538 records, 1,779,134 logical data bytes, 2,441,216 allocated Collection
bytes and 25,509,888 accounted bytes including the conservative control
reservation. Its maximum observed accounted publication peak was 25,640,960
bytes. Root SHA-256 was
`58704d9180ca904e71fa26b6c1c9b2c33b58e9e62a998d7784050ab8977c041c`.
Subsequent observed clean boundaries:

| Segment | Actual total publications | Total records | Elapsed | Native Collection allocation | Accounted total | Maximum accounted publication peak |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 1,000 | 1,074 | 187,598 ms | 4,870,144 B | 27,938,816 B | 28,090,368 B |
| 3 | 1,500 | 1,613 | 240,867 ms | 7,294,976 B | 30,363,648 B | 30,511,104 B |
| 4 | 2,000 | 2,140 | 291,003 ms | 9,711,616 B | 32,780,288 B | 32,894,976 B |
| 5 | 2,500 | 2,684 | 348,671 ms | 12,136,448 B | 35,205,120 B | 35,352,576 B |

The diagnostic 2,000-publication target is confirmed by the checked terminal
root, complete record/receipt scan, matching report/oracle/call hashes and
controller zero exit. Segment-4 root SHA-256 is
`17d6f44817e0232509af9ba0655885980fb258d05f29948e08eb86008631c4d4`.
Segment 6 stopped at the unchanged 360-second soft guard after **2,965**
verified publications, before constructing publication 2,966. Its exact frozen
source/stack location identifies that pre-dispatch check. There was no page,
normalization or byte-capacity refusal. The pending oracle remains unchanged;
there is no segment-6 report or clean receipt. The 4,000-note target is not yet
confirmed.
The late segment-3 mean was 489.8 ms per publication and
checked readback; a later segment can hit the unchanged soft deadline even with
remaining byte/page capacity. The existing per-phase commit/readback counters
are nil because their process-dictionary writes occur inside an owned callback
process; total publication/readback timing is measured, and no separate phase
timing claim is made.

## Explicit bounded continuation after the soft boundary

The developer authorized adapting diagnostic gates to the available host while
preserving product safety, byte ceilings and unknown-outcome rules. The additive
[`managed_v3_continuation.exs`](../../../dev/knowledge/managed_v3_continuation.exs)
therefore defines a new manifest/protocol, rather than editing the frozen run.
It uses chunks of at most 250 calls with the same 360/480-second, 512-MiB and
16-million-word bounds, at most eight chunks and **4,000 total publications**.
The original graph/helper/core source remains selected; no old request is
reexecuted, source ID reshuffled or uncertain operation replayed.

The read-only reconciliation verified every preceding clean controller receipt,
the exact pre-dispatch soft-failure location, unchanged source/runtime bindings,
the complete current note/value/revision sequence and every native retained
receipt hash against all 2,965 actual call observations. It confirmed that the
exact next operation ID and note were absent, then rechecked the final native
root. Missing/reordered/duplicate calls, receipt mismatch, root drift,
missing next-absence proof and changed source fail the corresponding checks.
The observed failure was the single exact soft-boundary trace. The frozen
classifier's treatment of appended errors and its later baseline-artifact
rechecks were limited; the independent-review section below records the repairs.
The new controller binds original store/directory identity and is itself frozen
before effects. Three focused [continuation controls](capacity-available-host/continuation-controls-46725.log)
passed with warnings treated as errors (46725, 0.5 seconds, exit 0).

The [reconciliation observation](capacity-available-host/reconcile.log) and
[new manifest](capacity-available-host/continuation-plan.json) retain this scope.
The new directory is `_build/capacity-continuation-sol-20261028`; manifest file
SHA-256 is `babf6fad26994254c840d80e6138de1f7d7e6cf6c855b56c11cbb56aa0c3737b`,
and frozen controller source SHA-256 is
`57996de4f726f7d09b70c69ce80796b914599a571178c581a2c76b63f5718dbc`.
The baseline root is
`39c01390c75d807a301a0b1ac25d6c6e734c33a33de8ed5938160f900f98b98d`,
with 2,965 notes/3,182 total records, 10,553,162 logical data bytes,
14,393,344 native allocated bytes and 37,462,016 accounted bytes. Its original
pending oracle is retained as historical evidence and never promoted to clean.
The first new chunk, 2,966 through 3,215, completed cleanly in 243,951 ms.
The total population was 3,215 notes/3,450 records, native allocation
15,589,376 bytes and accounted allocation 38,658,048 bytes; observed accounted
publication peak was 38,805,504 bytes. Root SHA-256 was
`1e90d4d422bd1a7d05b4c611c1c2a929f848e45ea74714862d30c4ae17698dff`.
A second control attempt for that same chunk refused its existing exclusive
attempt marker before launching another child; the original receipt/log remains
unchanged. Chunk 2 then completed cleanly at 3,465 notes/3,712 records in
261,524 ms, with 16,789,504 native allocated bytes and 39,858,176 accounted
bytes. Chunk 3 completed at 3,715 notes/3,988 records in 281,653 ms; chunk 4 at
3,965 notes/4,255 records in 295,580 ms. The final 35-call chunk completed at
4,000 notes in 89,532 ms. Every controller observed successful child/native
completion and retained its matching clean receipt.

Each continuation child syncs a fresh attempt/start marker before entering the
owned publication path. Its preceding baseline/root must match; every request
still matches the original frozen input row. Native write/readback and final
scan/receipts precede a confirmed oracle. Only matching report/calls/oracle and
observed zero native-supervisor/child completion permit a separate immutable
clean controller receipt. A pending, refused, timed-out or unknown chunk cannot
continue automatically. Benchmark oracles live separately from product state,
with their own native flat quotas; they do not widen the product's 64-MiB bound.

The workload performs initial additions only. It does not implement typed
expiry/forget/correction/pinning, 30/90/365-day turnover, installed user journeys,
Session/Consent/model integration, complete-import admission or performance
qualification. Successful reports retain overall qualification false. The memory
guard enforces sampled refusal but does not retain a passing peak-BEAM series.
Allocated bytes cover native-accounted Collection files/directories; accounted
totals also retain the conservative 22-MiB control reservation and publication
headroom. They do not measure filesystem journal/free-space allocator use or
process RSS. No quiet reference-performance window was established.

## Final observed outcome and independent readback

The additive [read-only final verifier](capacity-available-host/final-check.exs)
passed with marker
`ACTUAL_4000_PUBLICATIONS_AND_NATIVE_RECEIPTS_VERIFIED`. It rechecked the exact
frozen source/runtime/controller manifests, all original clean receipts, every
continuation report/oracle/call/log chain, the original pending oracle and
failure/prefix hashes, all **4,000 actual native retained receipt hashes** and
the full expected note/value/revision population. Operation 4,001 was absent;
no unknown effect was replayed. The final root matched the last confirmed
controller report. The [complete summary](capacity-available-host/summary.json)
and [observed output](capacity-available-host/final-validation.log) keep target
completion separate from overall qualification.

| Final native observation | Value |
| --- | ---: |
| Actual publications / retained operations / notes | 4,000 each |
| Total logical records | 4,291 |
| Managed sidecar records | 291 |
| Public note value bytes | 13,363,912 B |
| Sidecar value bytes | 873,725 B |
| Combined logical data | 14,237,637 B |
| Largest sidecar value | 5,963 B, below 6,144 B |
| Final native Collection allocation | 19,443,712 B |
| Final accounted allocation including control reservation | 42,512,384 B |
| Maximum observed accounted publication peak | 42,651,648 B, below 64 MiB |

Final root SHA-256 is
`fc992d56a59cdf1ff7a12ef12e988f41113574f9ada6cc09dc8d5e0bfe863b9a`.
Summary-file SHA-256 is
`53f7321e72384dd93a62c3b76860e8ad36996292506f01d9a55d51f3761bee1b`.
Nearest-rank total publication/checked-readback p50/p95/maximum were
585.215/974.755/2,656.566 ms. The 4,000 confirmed intervals sum to
2,372,253.712 ms; this excludes preparation, checkpointing, gaps and controller
work and is not complete wall time or a performance pass.

The [artifact manifest](capacity-available-host/manifest.json) inventories
retained evidence. The original input plan, all 4,000 call observations and
controller records are compressed losslessly beside it; runtime bindings and
both controller source revisions are retained. The live stores remain under
the paths above. This demonstrates that current ordered V3 metadata supports
the declared 4,000-addition population beyond the historical V2 fixed-shard
failure. It does not qualify typed turnover, native production admission,
installed users, source authority or quality/performance. Those gates remain
open; no release was published and no full repository suite was rerun.

## Independent controller review and prospective repairs

A separate agent reviewed the continuation read-only while the final chunks
ran. It found two diagnostic-controller gaps, without observing native root
corruption or incorrect publication counts:

- The frozen selector did not re-read the recorded original failure log,
  pending oracle and call-prefix hashes before each later chunk. Initial
  reconciliation bound them and the final independent check proved they stayed
  unchanged in this run; the current entry point now checks them every time and
  refuses an added original report/clean receipt.
- The frozen soft classifier used independent substrings and could accept a
  valid soft trace followed by another exception. The observed log contains
  exactly the one expected pre-dispatch exception. The current classifier
  requires one MatchError and only the known guard/Enum/driver stack frames,
  refusing second exceptions and ambiguous trailing output.

The current controller is retained separately as
[prospectively hardened source](capacity-available-host/current-controller-source.exs),
SHA-256 `c9ce8e9dc2a272da74078f0fbf96805411462400200eca188f396709f3d85e3c`.
Its [four focused tests](capacity-available-host/continuation-controls-46726.log)
passed with warnings treated as errors (46726, 0.5 seconds, exit 0), and its
strict classifier and baseline comparison also
[accepted the actual frozen evidence](capacity-available-host/prospective-real-evidence.log).
The frozen live controller and manifests were never edited or retroactively
represented as the hardened revision. A future run needs a new explicit manifest;
it cannot silently adopt changed controller bytes.
