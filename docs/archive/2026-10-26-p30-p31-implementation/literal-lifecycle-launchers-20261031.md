# Reuse the genuine literal-replacement journey for lifecycle checks

Dated **2026-10-31**, following `7b6ccd1`. This is fixture maintenance and
component evidence, not lifecycle or milestone acceptance. The
[receipt](literal-lifecycle-launchers-20261031.json) retains source/log hashes
and completed summaries. Current contributor procedures belong to
[testing](../../developer/testing.md); the [plan](../../plan.md) owns acceptance.

Both existing history-use and interrupted-compaction launchers reached actual
replacement successfully, then failed their stale assertion that close/resume
appended no release-owner records: **0/2 passed in 13.0 seconds**. No production
failure or native authority relaxation was needed. Two small child-only launchers
now reuse `managed_supersession_session.exs`, including its stronger physical
storage checks and exact close/resume suffix validation. This removes 874 lines
of duplicated setup while retaining both distinct follow-up helpers. The old
launchers remain available in revision `7b6ccd1`.

The history follow-up still checks authenticated old attribution, current
successor linkage, successor forgetting, missing original-source refusal and
revocation. Interrupted compaction still pauses after actual staging, kills the
original caller, observes controller exit while the completion worker remains
alive, then requires an unchanged physical root, unconfirmed journal result,
`publishing` control liability and no replay. Its synthetic diagnostic directory
remains retained. Neither check is replaced by a refusal-only expectation.

The first consolidated pair passed **2 cases in 28.0 seconds**. Final serial
verification includes both ordinary shared-setup branches and both follow-ups;
its exact result is in the receipt. Production runtime/helper bytes are unchanged
from the prior commit. No inference, metadata service request or download ran;
allowances remain ChatGPT 238/300 conservatively charged and local 4/1,000.
The earlier whole-source negative result remains unchanged. Legacy Core
supersession/turnover fixtures, full capacity, installed/platform/quality and
independent audit remain open.

The contributor testing chapter was reviewed whole and now teaches reuse of the
actual setup and the distinct lifecycle assertions. The unchanged operator
procedure was reviewed against these checks: two fresh reviews, preserved
history, and no replay after uncertainty. Automated PTYs establish no human or
model-quality qualification.
