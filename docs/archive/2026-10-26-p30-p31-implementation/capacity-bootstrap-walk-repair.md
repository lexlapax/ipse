# Capacity bootstrap walk repair

Historical preparation evidence, 2026-10-27. The capacity driver remains an
uncommitted candidate and has not performed a native publication or capacity
qualification. The earlier [static review](managed-v3-capacity-static-review/REVIEW.md)
and its open lifecycle and source-authority limits still apply.

The source-control suite initially reported 15 of 16 passing: its isolated
bootstrap child exited 137 without output. A standalone bootstrap reproduced
exit 137 after entering bootstrap; starting the application alone succeeded.
Inspection found that `Macro.prewalk` instrumented a matching call by wrapping
the original call in a new AST node. The pre-order walk then visited that same
call inside its replacement and could repeatedly wrap it. Replacing it with
`Macro.postwalk` instruments the original node after its children are visited,
without revisiting the replacement.

The focused bootstrap control then passed (seed 20261104). The entire
source-control suite passed 16 tests (seed 20261105) using the source-only
`ebin-third` graph from the private preparation record, with the checked-out
driver and test loaded as source. Both files passed `mix format
--check-formatted`. The checked driver SHA-256 is
`18087e961796247bb94d2f22668d701b0908e373c503892e66c9f030fec5e493`; the test
SHA-256 is `3f15768dfc19f8720c2495a72181cbe437bcca3e2b725ad9c2f84ec69baf8d06`.
The checked [driver](capacity-bootstrap-walk-candidate/managed_v3_capacity.exs)
and [test](capacity-bootstrap-walk-candidate/managed_v3_capacity_test.exs)
are preserved alongside this record.
These results derive from the command transcript, not an archived raw log.

The inferred AST expansion explains the reproduced failure and is supported by
the corrected bootstrap control; the operating system did not provide an OOM
receipt, so exit 137 alone does not prove an OOM kill. Native helper selection,
store admission, clean continuation and source bindings still require an
independent adversarial review of this exact candidate. The 2,000/4,000-record
capacity run, real Session source/consent, turnover and full baseline remain
unverified. No production or milestone acceptance follows from these tests.

One transport question remains for that review: the candidate stops its own
frame collector after a terminal frame, while `Runner.close_stdio(port,
:completed)` drains subsequent port data while waiting for exit. Its unit test
rejects data supplied to the decoder after a terminal frame, but does not prove
that later separately delivered data is rejected by the integrated collector.
Assess whether this weakens the required process-result evidence before any
capacity run; no native transport was exercised here.
