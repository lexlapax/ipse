# Hosted expiry precondition failure

Historical verification record, 2026-10-19. Source under review was
`81a4387d187d46a1c559e6738672b705dc76be11`. Use the
[testing chapter](../../developer/testing.md) for current contributor procedures
and the [memory manual](../../operator/memory.md) for expiry behavior.

[Hosted run 39375224043](https://github.com/lexlapax/ipse/actions/runs/39375224043)
finished with Ubuntu passing every gate, including the independent source and
installed knowledge proofs. macOS failed its ordinary source suite with one
failure among 1,329 tests, 34 excluded and one skipped. Later native and installed
steps on macOS were skipped. This is a red gate, not a passing platform result.

The failure was in `remember approved after target expiry cannot renew it`.
The fixture slept once for the difference between the record's expiry and the
current wall time. Its next assertion observed `1792475212547`, two milliseconds
before the expiry `1792475212549`. It failed before approving the pending write.
This run did not demonstrate an accepted expired renewal or a runtime regression.

The repair checks the actual expiry condition again after each sleep, with a
five-second monotonic watchdog. It preserves the live-target precondition,
`source_expired` result, unchanged stored record, durable failed-write receipt
and inert resume checks. It changes no memory implementation, retention policy,
request deadline or product approval behavior.

The complete affected local macOS file passes all 16 tests in 18.7 seconds.
A separate 300-sample local timer probe did not reproduce an early wake, so it is
not evidence of a local reproduction. The hosted assertion values above are the
observed counterexample. A corrected-source hosted matrix remains required.
