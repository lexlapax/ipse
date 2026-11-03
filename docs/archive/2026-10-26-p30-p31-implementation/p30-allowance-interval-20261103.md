# Timestamped synthetic allowance trace — 2026-11-03

This controlled-host follow-up strengthens, but does not replace, the earlier
[cross-Session test](p30-cross-session-allowance-20261103.md) and
[initial trace](p30-allowance-trace-20261103.md). The earlier test's third
failure was generic; the initial trace matched process ancestry and inputs but
did not establish that its `fits?/3` observation fell inside the particular
reservation call. Both historical results remain unchanged.

## Source and run

The same isolated `.p30-allowance-trace-7c51.QiSrClJD` snapshot, extracted from
commit `7c51f9ae8e1f5a95b89ab6f5050e140880f67730`, used the locally copied
un-inventoried dependencies and the offline build documented in the initial
trace receipt. No production source changed. The revised synthetic fixture and
committed PTY driver are preserved in [the evidence directory](p30-allowance-interval-20261103/).
The [four-file manifest](p30-allowance-interval-20261103/trace-interval-fixture.sha256),
SHA-256 `914445bb1469c5231db05d0d5191f6d921a66c8eb77e7c6fad4c4c3a15ef7fe4`,
matched after the run and against the archived copies.

Using `MIX_ENV=test`, `HEX_OFFLINE=1`, `ERL_FLAGS='+S 2:2 +A 2'`, local socket
and PTY access, and a 200-second outer bound, the fresh scenario ran:

```sh
IPSE_KEEP_SHADOW_FIXTURES=1 mix test test/extensions/knowledge/shadow_allowance_trace_session_test.exs --seed 0
```

The [log](p30-allowance-interval-20261103/trace-interval-run.log), SHA-256
`e0e0f813d878fed06f64e49e0c6721283bc9e2550a6a773aa42328b69dd883d4`, reports
**1 passed**, seed 0, 26.0 seconds. Both inference routes were synthetic
numeric-loopback services; no paid call or external inference service was used.
This is not a full-source or installed test.

## Result and boundary

The fixture created an eligible note in a closed source Session and settled two
separately approved one-call assessments under one two-call project policy. A
third Session attempted assessment. Test-only local BEAM tracing matched exactly
one `Consent.reserve_experiment/4` call to that journaled operation ID and
required exactly one matching `fits?/3` observation. Its BEAM monotonic call and
return timestamps had to fall strictly inside the reservation call/return
interval. The observer also required the check to run in that caller or in its
direct child spawned within the interval before or at the check; missing,
out-of-order or ambiguous required records fail the test. These timestamps are all from the same BEAM runtime and
are used for this ordering check, not as proof of compatibility with a native
clock.

At the observed locked ledger check, two settled in-period model calls had
consumed the two-call allowance and the third requested one more. No ledger
rows were compacted, there was no overrun quarantine, and the other resource
dimensions still fit. The actual `fits?/3` returned false and the reservation
returned `consent_reservation_refused`. The third action failed with no third
reservation or decision dispatch, the three assessment journals reconstructed,
and the Collection snapshot was unchanged. In this instrumented synthetic
journey, the ledger's model-call allowance was the failing resource at that
check; this does not establish a monetary cap, live-engine quality, installed
behavior or a general cross-process budget.

The [sanitized summary](p30-allowance-interval-20261103/allowance-trace-summary.json),
SHA-256 `d79de2288f4af19be9403748687c040a338d1dafaddbe109d8ecec4666bbf0d0`,
records only bounded counters and outcomes. The tracer sees synthetic ledger
arguments in memory but does not print source text or credentials. Synthetic
PID/timestamp events and the full resource vectors are not archived in that
summary. The correlation and other-resource comparisons therefore rely on the
retained fixture assertions and passing test log; the JSON alone cannot
independently recompute them. Synthetic
homes, journals and a terminal transcript remain under `/tmp` subject to
cleanup. The earlier unknown-outcome experiment was not replayed or exercised
in this fresh scenario.
