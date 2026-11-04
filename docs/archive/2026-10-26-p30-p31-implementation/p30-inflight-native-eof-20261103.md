# In-flight decision allowance through native review — 2026-11-03

This synthetic control passes one previously open P30 evidence gate: a second
OS process obtains native approval and attempts the shared one-call experiment
while the first call remains admitted and its provider response is withheld.
It does not test simultaneous entry into reservation, live engine quality,
installed packages or whole-milestone acceptance. The [plan](../../plan.md)
owns current scope.

## Correct the fixture lifecycle

The [earlier attempt](p30-inflight-allowance-20261103.md) stopped before the
contender's review. Its first CLI could rearm an idle native prompt and retain
the per-user input lock. This test changes only that fixture: after the first
decision reaches the synthetic provider, its PTY sends normal Ctrl-D to the
new prompt. The actual native reader reports EOF; the normal CLI waits for
accepted work to finish and releases input. The fixture waits for the EOF-sent
marker and removal of that Session's input entries before launching the second
PTY. It does not call an approval handler directly, replace a witness or change
a product timeout. `/exit` would cancel the work and is not used for the winner.

## Exact execution and result

The borrowed compiled runtime is the larger-Word candidate from the
[preceding checkpoint](word-collection-larger-20261103.md). Its tracked product
source matches `6fbbd90f`; the candidate's knowledge README differs and is
excluded from the product-source inventory. The pre-existing complete runtime
inventory and current product-source inventory matched before and after the
run. This control did not rebuild that runtime. The test additions were
formatted before execution; the PTY driver compiled with Rust warnings denied.
The archived [launcher](p30-inflight-native-eof-20261103/once.sh) records exact
volatile paths and isolation. HOME remained inherited; IPSE_HOME, TMPDIR,
operator-home paths and project state were fresh synthetic locations. Neither
paid credentials nor external inference services were used.

The [run log](p30-inflight-native-eof-20261103/run.log) reports **1 passed in
23.2 seconds**, seed 439851. The [completion record](p30-inflight-native-eof-20261103/status)
has `test_exit=0` and `postcheck_exit=0`. This is one fresh attempt, not a replay
of the earlier uncertain fixture.

The winner's request remained unanswered while the contender independently
checked the same project, policy digest and epoch, acquired its own native
approval and reached one experiment reservation. The bounded test-only trace
correlates that operation with one nested `fits?/3` call inside its monotonic
reservation interval. Its locked state contained one admitted model call,
zero settled calls and a limit of one; every other resource dimension fit.
The fit returned false and reservation returned `consent_reservation_refused`.
The contender acquired no reservation and sent no decision-provider request.
The [summary](p30-inflight-native-eof-20261103/summary.json) contains these bounded
assertion results; it does not preserve raw trace events for independent
recomputation.

After the contender completed, the provider released the winner's response.
The winner settled its original operation successfully. Both actual Sessions
validated saved reconstruction, closed, reopened idle and closed again without
additional action intent. The parent observed exactly one decision-provider
dispatch and an unchanged Collection snapshot. The test does not establish
that every terminal application or OS supports this input lifecycle.

## Retained evidence and remaining checks

The [evidence manifest](p30-inflight-native-eof-20261103/evidence.sha256), SHA-256
`048bf5677bd905d10d4d94c4f0ee77d9899fbdf75e8b20c5205ea30735c20118`,
covers the exact fixtures, entry point, launcher, logs, summary and inventories.
All entries verify. Full synthetic terminal transcripts remain in volatile
storage; their hashes are [retained](p30-inflight-native-eof-20261103/volatile-transcripts.sha256),
with a [bounded projection](p30-inflight-native-eof-20261103/synthetic-projection.txt).
The projection cannot reconstruct those transcripts after their removal.

Independent review checked the fixture, evidence and whole operator permission
and developer decision/testing manuals. The integrated worked example in the
decision training chapter explains the input lifecycle. The [documentation check](p30-inflight-native-eof-20261103/docs-check.log)
reports 1,137 Markdown files, 9,445 local links and zero errors in a tracked-only
mirror; it is not an execution of every documented command.

Simultaneous reservation races, the complete final-source suite, consumer
experiments and final P30/P31 audit remain open. No production behavior changed.
