# Native permission renewal across the original expiry

Dated **2026-11-02**, based on `0af4081` plus the selected source and helper
hashes in the [receipt](native-consent-renewal-20261102.json). The [plan](../../plan.md)
owns remaining acceptance; the [storage chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
explains why a year-long test needs this step. This is an author-run component
control, not annual qualification or a live account test.

The initial native population spans 21 simulated dates before the following
365-day workload. The CLI's initial saved grant expires 365 days after review,
so it cannot by itself authorize capture on the final annual dates. A fresh
explicit native review is required; time passing does not renew permission.

Two fresh isolated process-clock and PTY journeys passed together. One retained
the original policy through simulated day 386: the actual protected consent
read refused it, its callback did not execute, and the control snapshot remained
unchanged. This is a policy-boundary control, not a complete attempted-capture
test. The second reviewed `knowledge enable` again on day 364, advanced beyond
the original expiry to day 386, and captured an exact new ordinary statement
through an actual native Session. Its control operation settled with one
publication and zero model calls. The original signed stored current note and
its saved Session source remained byte-identical and inspectable. The renewal
incremented the policy epoch and extended its expiry. A synthetic provider
would fail if invoked; no model request was made.

The final combined command exited 0 with **2 passed, 2 excluded**, seed
`791850`. Two earlier positive controls passed at seeds `791848` and `791849`;
the latter also checked the new text and operation accounting. All used the
test-only process clock and retained native stdio helper. The receipt binds
selected source and helper bytes collected after execution, test logs and the
reported timestamps. The complete clock-lifecycle test file also passed all
**4 tests** at seed `791851`; formatting, warnings-as-errors compilation and
documentation/link checks passed. This is not a complete pre/post runtime inventory.

The stored-note read authenticates the signed Collection record; it does not
check its current source eligibility or deliver it to a model. Recall after
renewal, old Session behavior, later owner-loss cases, periodic renewal during
the complete workload and independent quality remain open. No runtime code,
permission scope, budget or storage limit changed.

The subsequent [recall and source-loss control](native-renewal-recall-20261102.md)
tests a fresh Session's synthetic loopback request after renewal; the other
limitations above remain.

## Incomplete full-source run

Before the focused controls, a clean independently built clone of `3b14048`
began `mix test --max-cases 1 --seed 791845`. The run was stopped deliberately
with SIGTERM so the prerequisite native check could use the fixtures serially.
Its parent process reported exit 0, but the log ends in a SIGTERM notice and has
no complete parent ExUnit summary: **the run is incomplete, not a pass**. The
partial log and SHA-256 are retained in the receipt. The earlier complete
`9f1707c` baseline remains historical; a complete later-source run is still
required after the remaining changes.
