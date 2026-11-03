# Synthetic cross-process decision allowance — 2026-11-03

This focused controlled-host experiment extends the earlier
[same-process cross-Session check](p30-cross-session-allowance-20261103.md) and
[timestamped allowance trace](p30-allowance-interval-20261103.md). It checks a
shared finite local decision allowance across two OS processes; it is not a
simultaneous reservation race, installed-package check, paid-service test,
monetary cap or P30 milestone acceptance. The [current plan](../../plan.md)
owns status.

## Source and run

An isolated `.p30-cross-process-b6d6.PHYs4ADs` snapshot came from `git archive`
of commit `b6d667a1761793007b3e03b926a71089ac080550`, with local dependencies
copied separately and not independently inventoried. No production runtime or
recall source was changed. The three added fixture files and the existing
committed trace helper and PTY driver are retained under
[the evidence directory](p30-cross-process-allowance-20261103/). The
[five-file manifest](p30-cross-process-allowance-20261103/process-fixture.sha256),
SHA-256 `201776d3cddb82790bbcdce149020829bed4c141a45431b517d5a5d8fec7054e`,
matched before and after the run and against those archived copies. The three
Elixir additions were formatted before hashing and execution.

The offline build used `IPSE_BUILD_COMMIT` set to the commit above,
`MIX_ENV=test`, `HEX_OFFLINE=1`, `ERL_FLAGS='+S 2:2 +A 2'` and local socket
access. Its retained snapshot log `process-build.log` hashes to
`7eb2d6086d8af384d36d64dbc2ede0efa5f5cb94c5c00ee026c8e7e92d04f9ae`;
`priv/ipse-runner` hashes to
`ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b`.
The fresh test used a 200-second outer bound, a local PTY and synthetic numeric
loopback providers:

```sh
IPSE_KEEP_SHADOW_FIXTURES=1 mix test test/extensions/knowledge/shadow_cross_process_session_test.exs --seed 0
```

The [log](p30-cross-process-allowance-20261103/process-first-run.log), SHA-256
`9fbfb885beeef5d41ed44c86585ee2d380a05aac44a3bf641e0929653c279a24`, reports
**1 passed**, seed 0, 27.5 seconds. No paid call or external inference service
was used. This is not a full-source suite.

## Observed boundary

The first OS process captured a real eligible synthetic note in a closed source
Session, reviewed a two-call experiment once, then obtained native approval and
settled one call in each of two distinct subsequent Sessions. While that
process and its synthetic provider remained alive, the fixture's precompiled
PTY driver launched a fresh Elixir OS process. The child checked its OS PID and
Session ID differed from the parent and earlier Sessions, and that the existing
project, policy digest and epoch matched. It obtained a fresh native approval
for the third assessment.

The child used the existing test-only BEAM monotonic trace to match the third
journaled operation to exactly one reservation and one `fits?/3` call within
its reservation call/return interval, running in the caller or its directly
spawned file-effect child. The actual locked state showed two settled in-period
model calls against a limit of two, a request for one more, no compaction or
overrun quarantine, and all other resource dimensions fitting. `fits?/3`
returned false and the reservation returned `consent_reservation_refused`.
The child observed no reservation for that operation and reconstructed its
journal. The parent observed no third decision-provider dispatch, identical
ledger operations and policy before/after the child, and an unchanged Collection
snapshot. All three Sessions completed their own checked close. A later test
would be needed for competing overlapping reservations across OS processes.

The [sanitized summary](p30-cross-process-allowance-20261103/cross-process-summary.json),
SHA-256 `e6c0884a222d3bde5d10aee2870cc895d56704188ff095f565bdef2195f0fcaf`,
contains bounded outcomes, not source text or credentials. It omits raw
PID/timestamp events and full resource vectors: correlation and the
other-resource comparison rely on the retained fixture assertions and passing
log, not independent recomputation from that JSON. Synthetic homes, journals
and terminal transcripts were retained under `/tmp` and are subject to
cleanup. No previous uncertain effect was replayed.
