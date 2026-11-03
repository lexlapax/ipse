# Align simulated workdays with the actual consent quota

Dated **2026-11-02**, based on `5f20b5a` plus the source and output hashes in
the [receipt](native-calendar-quota-clock-20261102.json). The [plan](../../plan.md)
owns acceptance and the [storage chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns the procedure. This is a development-fixture correction, not annual
qualification or a runtime policy change.

The [first compensated clock plan](native-calendar-clock-anchor-20261102.md)
allowed 24 hours after the seed-relative day start. The actual saved-consent
quota instead uses UTC-aligned 24-hour periods. If a simulated workday crossed
midnight, its later actions could consume the same quota period as the next
simulated workday. A calendar that reported no daily excess would then not be
sufficient evidence that the host would admit the sequence.

The clock plan now ends each simulated workday at the next UTC midnight, while
retaining its seed-relative start and the same offset across restarts that day.
It refuses an action at or beyond that exclusive boundary. The existing
compensated-clock example now ends at `1801872000000`; its start and offset are
unchanged. A workday can therefore be shorter than 24 real hours. The caller
must check before and after each effect and leave an unconfirmed effect for
inspection if it crosses the boundary; this arithmetic does not itself perform
or fence an effect.

A synthetic protected-consent control with a one-operation daily quota reserved,
admitted and settled one operation immediately before midnight. A second
reservation at that time was refused, and a reservation at the reset succeeded;
the clock planner refused that reset instant for the previous day. The complete
selected seed/calendar/clock/quota tests then exited 0 with **18 passed**, seed
`791866`. The command-line boundary example exited 2 as expected. Formatting and
warnings-as-errors compilation passed for the affected source.

Two earlier test runs failed because the fixture first used an already-created
control-root path and then attempted settlement before admission. Their logs are
retained in the receipt; those intermediate test-file versions were not
separately snapshotted. The quota store was synthetic and separate from the
closed seed. No Collection publication or model request occurred.

The real 2,000-note seed's saved control still needs the running signed audit
and an explicit first-period check before continuation. Long-running clock
jumps, active-effect loss, full annual workload and semantic quality remain
open. No production quota, provider, permission or storage ceiling changed.
