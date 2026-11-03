# Compensate the annual fixture clock for real elapsed time

**Later correction:** The original planner allowed a full 24 hours after the
seed-relative day start. The actual consent quota resets at UTC midnight, so
that window could cross quota periods. Use the [quota-aligned follow-up](native-calendar-quota-clock-20261102.md)
for the current boundary. The original calculations below remain historical.

Dated **2026-11-02**, based on `fb96381` plus the source and output hashes in
the [receipt](native-calendar-clock-anchor-20261102.json). The
[plan](../../plan.md) owns acceptance and the
[storage chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns the procedure. This is development-fixture arithmetic, not a runtime clock
change or an annual execution.

The short [turnover pilot](native-turnover-pilot-20261102.md) used a fixed
`day × 24 hours` offset from the current real clock. That is adequate for its
short scoped run, but a continuation lasting more than one real day would add
that extra real time to every simulated day. It could thereby advance signed
deadlines and consent unexpectedly. The pilot's historical result is unaffected;
the fixed-offset method is not sufficient for a long annual driver.

The new pure clock plan anchors each simulated day to the seed's original wall
timestamp and an unshifted real start time. It subtracts already elapsed real
time when calculating the fixture offset, then retains the same offset for all
batches and restarts within that day. The next day's anchor must begin after the
last recorded virtual time. A backwards real/virtual observation, a batch at or
past the day's end, a changed anchor, or an offset outside the existing fixture's
zero-to-500-day range is refused. The caller must durably retain the anchor and
latest verified time, check before every effect, verify the actual child clock,
and treat an unconfirmed dispatch as unknown. These functions do not grant
permission, run effects, or persist the anchor themselves.

The selected seed, calendar and process-clock tests exited 0 with **16 passed**,
seed `791861`; formatting and warnings-as-errors compilation passed. The new
case simulates 27 hours of elapsed real time before a day-21 start and verifies
the compensated offset in a fresh BEAM and Rust child. It does not wait 27 real
hours or establish long-running drift behavior. Pure tests cover reuse across a
restart, next-day progression and refusal boundaries; the command-line example
also passed, and the one-day-overflow example exited 2 without an effect.

The future driver must use an unshifted real clock to calculate the anchor; it
must not feed the already shifted child clock back as real time. Initializing
from the audited seed also requires a verified last virtual timestamp and root,
not an invented earlier time. OS clock jumps, actual day-boundary interposition,
long execution and crash/restart behavior remain unqualified until exercised in
that driver. No production provider, permission, storage limit or system clock
changed.
