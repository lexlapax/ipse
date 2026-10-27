# Capacity controller terminal handling candidate

Historical preparation evidence, 2026-10-27. This uncommitted candidate follows
the [bootstrap repair](../capacity-bootstrap-walk-repair.md). The controller
now keeps receiving port messages after the native terminal frame, rejects any
subsequent data through its bounded decoder, and requires an observed supervisor
exit before accepting the child result. It limits the post-terminal wait to two
seconds. If completion or cleanup is uncertain, the attempt remains unclean.

The [driver](managed_v3_capacity.exs) has SHA-256
`f3705fa18b8eff7796090b6578e0334b8a8b88142ff88068b4eefc87c5124454`; the
[test](managed_v3_capacity_test.exs) has SHA-256
`62266a48117f3c897c01046f426f626c6d44cf649391e0a4a14fd742767d57db`.
The source-only suite passed 18 tests with seed 20261111, including synthetic
separately delivered post-terminal data, exit without a terminal result and a
real local shell port emitting a terminal frame and exit. Both files were
formatted. The results are from the tool transcript, not an archived raw log.

This does not test the protected native supervisor, process-group cleanup,
owner loss or delayed native frames. It has not been independently reviewed.
The terminal/exit ordering and cleanup semantics must be reviewed against the
actual Runner and native helper before any capacity publication. The source,
consent, current-eligibility, 2,000/4,000-record and annual-turnover gates remain
open; no milestone acceptance is implied.
