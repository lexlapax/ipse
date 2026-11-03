# Synthetic source-owner phase comparison, 2026-11-03

This diagnostic compares one and eight inactive original Session owners during
actual managed model egress. It does not qualify the 33-note or 2,000-note
journeys and does not establish the cause of either earlier unknown outcome.
The exact redacted evidence is in the sibling `source-owner-phase-20261103/`
directory; `evidence.sha256` covers the files listed there. The disposable
instrumentation is not production code.

Both cases used fresh, separate synthetic roots, native-reviewed Knowledge
grants, and a new consuming Session with the existing five-second provider and
Worker limits. Each seeded the same eight five-byte synthetic notes. In the
first case all eight originals belonged to one Session; in the second they
belonged to eight Sessions. The actual provider request contained the full
notes in a decoded user-role Knowledge reference. Each emitted key, revision,
full text and operation ID was checked against its committed successful read.
Within each case, a digest of those eight key/revision pairs matched the actual
egress dependencies; the digests were not compared across different runs.
Both egress unions had ten dependencies (two v3 and eight v4), eight distinct
v4 records and eight source proofs. Source identities necessarily differed.

| Instrumented stage | One source | Eight sources |
| --- | ---: | ---: |
| Complete egress callback | 1,068.295 ms | 1,382.059 ms |
| First protected observation | 215.961 ms | 278.698 ms |
| Second protected observation | 219.779 ms | 256.443 ms |
| Source index/cache calls, total | 567.792 ms | 735.915 ms |
| Source-lock acquisition, total | 1.833 ms | 14.636 ms |
| Source journal scanning, total | 2.881 ms | 4.328 ms |
| Source proof resolution, total | 0.125 ms | 0.181 ms |
| Source unlocking, total | 0.146 ms | 1.667 ms |

Times are differences between monotonic timestamps emitted around the named
calls in a temporary instrumented host. The egress span contains the nested
stages, so the rows must not be added as independent totals. Lock times measure
acquisition calls, not time for which locks are retained. The index/cache span
includes access to the scoped replay cache and its restore call. It can include
size checks, hashing, a cache lookup, copying, or reconstruction. **The markers
record cache availability, not hits or misses**, and cannot attribute that span
to a particular operation inside the cache.

The one-source journal contained 214 events and 367,227 bytes; the eight-source
journals contained 32 events apiece and 546,149 bytes in total. Both cases
reported scoped cache availability, but their source histories and cache state
were not controlled to equivalence. This single pair is directional: source
index/cache calls were a larger measured component than native lock acquisition
in these synthetic runs, but instrumented overhead, different journal content,
startup and scheduling can affect the comparison. It does not measure the
unmodified host, prove linear scaling, identify a cache hit or miss, or justify a
production optimization by itself.

The one-shot launcher retained distinct fresh roots and stopped on an unsuccessful
case. It reported `run_exit=0 postcheck_exit=0`; the analyzer required one
same-process/token egress interval, complete ordered stages, zero dropped
markers, one producer barrier, matched per-case record digests and equal
version/proof/count shapes. The Session/root/job relationship is supported by
the independently reviewed controlled-peer call path and real fixture; the
markers alone do not attest it. Per-case source journal hashes and journal/lock
identities were checked against their pre-consumer snapshots on successful
closure. Missing markers, unconfirmed closure or shape mismatches would have
made the comparison inconclusive. No previous Session or unknown turn was
resumed or replayed. The redacted case logs retain only fixture-root lines;
provider requests and post-use source inventories are not archived. The
request/read, source-preservation and exact single-test assertions are supported
by the archived fixture and entry code together with the zero-exit launcher
status and completion marker, not independently reproducible raw request or
post-use inventory evidence.

The source baseline was commit `f44f2506de2de47a31c84f2b1b7617236c4d340f`,
which predates the subsequent installed-verifier checkpoint. The complete
source inventory was compared with a fresh archive of that commit; the only
changes were five documented runtime/fixture files and the temporary timing
module. Source and compiled-runtime inventories were checked before and after
the two cases. Elixir and Rust versions are separately recorded; runtime hashes
do not pin those toolchains.

The offline build used task-owned copies of dependencies and Mix/Hex caches
from a previous synthetic installed-package fixture with the same lockfile;
this is not independent dependency attestation. Compilation and bundle
production finished, but the original build exited nonzero at its strict
post-build dependency check because the telemetry Rebar-generated `source.dag`
changed. The failing comparison is preserved. The resulting dependency cache
and compiled runtime were separately fingerprinted without rebuilding. Source
and runtime remained unchanged across the cases; the dependency cache was not
rechecked across them. No product deadline, authority or policy was changed.
