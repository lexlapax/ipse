# Annual storage segment 1: incomplete, termination cause unknown

Historical investigation, **2026-10-26 Pacific time** (inspection continued on
2026-10-27 UTC). This supersedes the pending annual status in the
[30/90-day turnover checkpoint](storage-workload-endurance.md). The annual
365-day plus 10,000-cycle workload did **not** finish its first segment. There
is no eligible continuation, and no annual acceptance passed. The
[current plan](../../plan.md) and [qualification protocol](qualification.md)
remain authoritative.

## Retain the outcome without replay

The tool-managed process was launched as session `14201` from the immutable
private source graph `/tmp/ipse-storage-endurance-20261026-02`, using its own
`/tmp/ipse-storage-endurance-20261026-02-build` BEAM graph and private helper.
The original command used `mix run --no-compile --no-deps-check`,
`ERL_FLAGS='+S 2:2'`, `--segmented --days 365 --cycles 10000 --payload maximum
--granularity individual --segment-publications 6000`. It retained the original
two-hour, 512-MiB sampled BEAM and 16-million-word main-process heap guards.
No guard was raised. The [runtime manifest](storage-workload-runtime-v2.json)
binds the comparable 117-file application graph, all source/BEAM hashes and helper;
the runtime fingerprint is
`1ae1497bec81dd1a4c225d45d0fd810671f9a7c59a74d4d0d7671f678792fe2d`.

A later poll returned `Unknown process id 14201`. The selected log contains
the store location and day-30 progress only. The last partial report records
day 55, cycle 0, generation 1,721 and 2,442 records. It sampled a managed
allocated peak of 43,565,056 bytes, including the existing 22-MiB control
reservation, and post-publication BEAM memory of 107,383,576 bytes. These are
partial observations, not final maxima or completed annual results.

The oracle marker was last modified at 21:03:22 Pacific; the retained Collection
root was last modified at 21:13:17. Neither a complete final JSON report nor a
driver failure/resource-failure JSON was present. No exit code, termination
signal or reliable host-process observation survives. The execution namespace's
process list does not establish host-wide process absence. The termination
cause therefore remains **unknown**. The timestamps do not establish an external
session timeout, resource-guard stop, heap-limit stop or capacity failure.

The oracle still contains its original pending marker and retained lock files,
with no `root.json` checkpoint or hashed report. The completed-boundary protocol
has not run. There was **no resume, marker removal, repair, operation retry or
store reset**. This store must not be passed to the continuation command.

## Inspect the retained state read-only

The [inspection receipt](storage-annual-s1-inspection.json) and exact
[diagnostic source](storage-annual-s1-inspect.exs) preserve a bounded inspection
using the frozen modules. It made no product API or native transaction calls;
it read selected synthetic files and regenerated the deterministic pure model.
The root bytes were equal before and after the read. This establishes a stable
diagnostic snapshot, not successful owner shutdown or permission to continue.

| Retained state | Observed result |
| --- | --- |
| Root version / generation / floor | 4 / 1,752 / 1,732 |
| Root SHA-256 | `e278cf80e52f04c47cd2e49ae4eef196e8eada5fd538858f14ce8d4182535944` |
| Canonical referenced metadata block decode | 41 blocks passed |
| Valid retained receipts | 1,752 |
| Current objects with matching byte length and SHA-256 | 2,450 |
| Actual values compared with pure model | Exact day-56, cycle-0 match |
| Active migration / retained checkpoint | Neither present |
| Object / manifest directory entries | 2,451 / 43 |
| Pending Collection object/manifest files | None observed |

Generation 1,752 shows later durable publications than the day-55 partial report;
the exact record values match the end of day 56. It does not prove that the
driver observed every final return, performed its day-56 diagnostic reads, or
confirmed a clean boundary. Receipt IDs and the destructive lineage remain
protected in the retained store. The inspection did not copy note values into
the archive or manufacture an oracle checkpoint.

## Evidence and remaining gates

The [artifact manifest](storage-annual-s1-artifacts.json) records original
selected paths, byte counts, modification times and SHA-256 hashes for the
unchanged [partial report](storage-annual-s1-partial.json),
[location/provenance](storage-annual-s1-location.json), and
[log](storage-annual-s1.log), plus hashes for this diagnostic and receipt.
These files contain synthetic fixture identifiers and selected paths only;
there are no credentials, environment dumps, host process arguments or private
transcripts. The store and oracle remain outside Git at the selected path in
the location artifact.

The successful 30/90-day evidence remains separate. This interrupted attempt
provides partial individual-write durability and physical-capacity observations
only. It does not exercise day-90 migration in this store, the offline week,
365 days, or any of the 10,000 later cycles. The known 256-file final import-plan
limit remains an open required gate. Another component's control-ledger stress
overlapped execution, so there is no reference performance claim.

The frozen graph uses ordinary v4 roots and synthetic Notes policy records.
Authenticated Sources, durable expiry-lineage overrides, domain recapture
admission, Session turns, models and the concurrent managed-root format are
outside its coverage. The separate control-ledger attempt has its own owner
and provenance; neither attempt grants acceptance. Current operator/developer
manuals and plan remain unchanged because this record changes no runtime
behavior and closes no milestone gate. Any future launcher or rerun needs a
separate authorized design; this record starts none.
