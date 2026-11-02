# Signed-note decision source withdrawal — 2026-11-02

This author-run P30C follow-up uses the current runtime after `e68566d` plus
the test source in the [receipt](p30-signed-withdrawal-20261102.json). The
[plan](../../plan.md) owns acceptance and [testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
owns the runnable control. It uses synthetic local provider responses and
automated native terminal input; it establishes neither live-engine access nor
human/consumer quality. No paid model request occurred.

A fresh native fixture produces eight reviewed literal notes from two original
Session journals. The positive over-budget shadow selection passed **one test**
in 36.5 seconds, seed `791839`, with 191 excluded. It checks the actual context
allocation, all eight source dependencies and the synthetic decision request;
it publishes no notes or State changes.

The withdrawal control first failed after the positive fixture was reused. A
second failure on a separate fresh fixture reproduced the same listener timeout.
Both original logs are preserved in the receipt. The second run's Session
journal shows the intended source loss reached the actual decision preflight:
one main dispatch occurred, the decision dispatch did not, the helper request
finished failed/partial, its next Worker input became unknown, and the turn
ended with an error. The old test instead waited for successful completion and
a second main request. The linked synthetic listener timed out while that
expectation waited; this was not evidence of decision egress.

The failed fresh run retained the first source under the fixture's temporary
held name. After the test VM exited, it was restored to its original path with
the same inode and matching original SHA-256; the second source also retained
its original bytes. No uncertain effect or request was replayed.

The repaired control requires the error, exactly one main dispatch and no
decision dispatch, final main accounting and failed/partial helper accounting.
It binds the unknown Worker input to the failed action and complete observed
dependency union, checks strict Saved reconstruction and unavailable managed
lineage, restores both original journals, and checks an idle resume without
replay. A separate cleanup callback protects source restoration if the test
process exits during the hold. It does not replace a missing source with a copy.

The repaired control passed **one test**, seed `791842`, then passed again with
the added accounting assertions on a new fixture: **one test** in 28.2 seconds,
seed `791844`, 191 excluded. The adjacent generic current/stale decision
controls passed **two tests**, seed `791843`, 190 excluded. Formatting and the
current test-graph strict compile passed. The preliminary `791842` test source
was superseded by the added assertions and was not separately snapshotted; the
receipt binds the final source used by `791844`. Its source/helper inventory is
selected, not a complete pre/post build-graph inventory. The whole testing and
operator knowledge guidance was reviewed for this control. Documentation checks
covered 1,057 Markdown files and 8,735 links with zero errors; retained private
ledger-directory permission warnings remain in the log. These focused controls
are not a new complete-suite, installed, platform, final adversarial-audit or
quality result.
