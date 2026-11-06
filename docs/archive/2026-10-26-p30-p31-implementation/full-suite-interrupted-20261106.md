# Interrupted current-source regression and nested control repair — 2026-11-06

Historical verification record. The [plan](../../plan.md) owns current milestone
status; [testing](../../developer/testing.md) describes the current procedure.

An author-run, isolated default suite used runtime source `e0c2492f` and the
reviewed 508-file census. It was stopped deliberately after approximately one
hour because it had already reported three failures and could not provide a
passing baseline. No complete parent test count or terminal ExUnit result was
obtained. Nested summaries in the retained log do not supply one.

Two native-helper boundary tests failed while creating files under `/tmp` with
`EDQUOT`. The filesystem had free space but its user quota refused the writes.
After a separate inventory established that one abandoned incomplete staging
checkout's documentation tree contained only tracked duplicates, empty files,
and a truncated tracked-file prefix, that tree was removed. Its Git objects,
metadata and other files remain; a fresh 1 MiB synchronized `/tmp` write passed.
This does not establish sufficient quota for a complete subsequent suite.

The third failure was the parent of the selected witnessed draft-inference
control. Its child reported one pass and eight exclusions but the entrypoint
never emitted the completion marker the parent required. The entrypoint now
disables autorun, checks the exact `ExUnit.run/0` counters and emits the marker
only after success. A separate actual native focused run of
`test/ipse/extension/inference_dispatch_session_test.exs:266` exited zero with
one pass and eight excluded (seed 516467). The Elixir 1.18 formatter check and
`git diff --check` passed. The focused result does not change the interrupted
suite's outcome.

The interrupted wrapper recorded `primary=143`; source-copy, launcher and
toolchain post-checks passed. Its process check observed a transient process,
so it did not itself establish complete process cleanup. A later independent
check found that PID gone, no process in the owned group, and no holder of the
shared input lock or test listener. The earlier log and its three failures remain
in the private verification directory. A fresh full baseline and all remaining
P30/P31 acceptance checks are still required.
