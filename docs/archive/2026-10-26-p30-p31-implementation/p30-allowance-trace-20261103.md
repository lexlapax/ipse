# Synthetic third-call allowance trace — 2026-11-03

This is a controlled-host, synthetic follow-up to the [earlier cross-Session
experiment](p30-cross-session-allowance-20261103.md). That earlier test recorded
two settled calls and a third generic `decision_request_failed`; it did not
establish the reason for that refusal. This fresh fixture strongly correlates
a ledger decision, but did not bind that check to the reservation's call/return
interval. The separate [timestamped follow-up](p30-allowance-interval-20261103.md)
adds that control. Neither changes the earlier result or qualifies a live
engine, an installed workflow, model quality, a monetary cap, or a general
cross-process experiment.

## Source and execution

The isolated `.p30-allowance-trace-7c51.QiSrClJD` snapshot was extracted with
`git archive` from commit `7c51f9ae8e1f5a95b89ab6f5050e140880f67730`. Local
dependencies were copied separately, without an independent inventory. The
three added fixture files and the committed PTY driver are retained under
[the evidence directory](p30-allowance-trace-20261103/); their
[manifest](p30-allowance-trace-20261103/trace-fixture.sha256), SHA-256
`34ee8db30afd4fc7bfa18525586071915d41980a2e9208736eca9039b021ae10`, matched
after the run. No production source was altered in the snapshot.

With `IPSE_BUILD_COMMIT` set to that commit, `MIX_ENV=test`, `HEX_OFFLINE=1`
and `ERL_FLAGS='+S 2:2 +A 2'`, the offline build ran with local socket access:

```sh
./dev/build.sh
IPSE_KEEP_SHADOW_FIXTURES=1 mix test test/extensions/knowledge/shadow_allowance_trace_session_test.exs --seed 0
```

The test had a 200-second outer bound. Its [log](p30-allowance-trace-20261103/trace-first-run.log)
SHA-256 `7ecd29d8d1e69538c072b88760cc9198c81f482e31cc203a9ca69a1698bac696`
reports **1 passed**, seed 0, 26.3 seconds. The build log remains in the
snapshot as `trace-build.log`, SHA-256
`917b46235ec287414364171fda903bcbdd9f7545baa0bfc64debb9273e32f115`;
its `priv/ipse-runner` SHA-256 was
`ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b`.
The main and decision services used synthetic numeric-loopback responses; no
paid call, live account or external inference service was used. This is not
a full-source suite.

## What the trace observed

One closed source Session supplied an eligible saved note. Two separately
started, natively approved synthetic assessment Sessions consumed and settled
two one-call reservations. The third Session requested a new assessment under
the same project and two-call policy. Test-only BEAM local tracing, enabled
before that Session, observed the actual `Consent.reserve_experiment/4` call
and the actual descendant file-effect process's private `fits?/3` call. The
fixture matched the reservation's operation ID to the third journaled action,
verified the expected control root, project and policy, and required one
unambiguous process-lineage match and both actual return values. A missing or
ambiguous trace causes the test to fail.

At that locked check, the test required two settled, in-period one-call
charges, a limit of two, a request for one further model call, zero compacted
rows and no overrun quarantine. It independently checked that all other
resource dimensions still fit. `fits?/3` returned false and the observed
reservation returned `consent_reservation_refused`. The third action failed
without a third reservation or decision-service dispatch; all three journals
reconstructed and the Collection snapshot stayed unchanged. Process ancestry
and matching inputs strongly correlate these observations, but this fixture
did not establish that the check occurred within that exact reservation call.
It therefore did not independently prove the specific refusal reason.

The retained [sanitized summary](p30-allowance-trace-20261103/allowance-trace-summary.json)
SHA-256 `a2d8fa3c68b702204831a54bc0cfee8bc7427ed98e1bc1f3bcb1a6672020c750`
contains counters and outcomes, not source text or credentials. The test's
synthetic home, journals and terminal transcript were retained under `/tmp`
for inspection; temporary-directory cleanup can remove them. The trace
instrumentation sees the synthetic ledger in memory but does not print it.
The earlier unknown-reservation quarantine remains a separate result and was
not replayed or exercised by this test.
