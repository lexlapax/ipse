# Include initial native pin reviews in the workload budget

Dated **2026-11-02**, based on `5331e60` plus the source hashes in the
[structured receipt](native-pin-budget-20261102.json). This is a pure developer
preflight, with zero native operations, turns or model requests. It qualifies no
annual workload or storage capacity. The [plan](../../plan.md) owns acceptance;
the [storage training chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns current commands.

The [actual native population plan](native-notes-seed-20261102.md) requires
2,000 captures and 100 separate pin publications. Capture cannot directly
assign the pin category. The earlier [operation floor](native-workload-budget-20261102.md)
counted only those captures, omitting the pin reviews. The revised floor includes
`initial_pin_promotions: 100` and preserves all other daily/burst counts.

The developer-selected **10,000 mixed changes total**, additional to normal annual
work, therefore has a minimum of **23,080 operations**. The unchanged retained-ID
limit is 32,768. Expiry, imports, compaction, recovery and control management
remain outside this lower bound; pilot-derived intake remains unratified. The
unselected complete three-action comparison now has a 43,080 minimum and exceeds
the same limit by at least 10,312. No limit, authority or workload requirement
changes here. The earlier receipt geometry remains a measurement of its original
22,980/42,980 scenarios; it has not been relabeled as the revised workload.

Five pure tests passed in a plain Elixir VM, seed `791833`, including equality
between the budget's 2,100 initial effects and the native runner's complete
initial plan. The CLI emitted both revised arithmetic rows without starting
Ipse or opening native storage. The first test invocation passed three tests
but omitted the Notes source from its isolated VM, producing module warnings;
the final invocation loads that source and emits no warnings. Original logs are
retained separately in the receipt. The native population cohort continues
against its frozen `5331e60` source; this arithmetic repair changes none of its
private files or effects. Strict isolated compilation and source formatting
passed. Whole-chapter review reconciled the developer storage manual's current
floor with its historical geometry, and checked the operator's statement, pin
and recovery procedures against their separate effects. Manual/link validation
checked 1,051 Markdown files and 8,697 local links with zero errors.
