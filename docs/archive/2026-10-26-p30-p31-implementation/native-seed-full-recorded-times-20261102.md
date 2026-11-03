# Full signed seed audit with recorded journal times

Dated **2026-11-02**, using the closed population published by `5331e60` and
the audit caller from `4e43b81`. The [receipt](native-seed-full-recorded-times-20261102.json)
binds the caller, exact report, per-record rows and parent log. The
[plan](../../plan.md) owns current acceptance; the
[storage chapter](../../developer/knowledge-storage.md#audit-the-complete-retained-population)
owns the procedure.

The read-only audit exited 0 after checking **2,000** signed records: 1,800
ordinary, 100 pinned, 50 preferences and 50 current statements. It rechecked
all **373** original source files, the root and control without changing them.
The per-record rows are byte-identical to the preceding full audit. The updated
caller also read **53,938** journal events: the latest selected recorded
`checked_at_ms` was `1795389015486`, matching the earlier separate source scan.
This is 78,342,310 milliseconds before the seed-relative start of simulated
day 21. It is a maximum of selected recorded field names, not an upper bound on
physical completion or proof that the host clock was monotonic.

The final measured component sum remained **134,131,712 bytes**, including
122,515,456 bytes of original Session files and 9,773,056 bytes of Collection
allocation. These are post-audit component allocations, not a full disk or
process-tree peak. No source, control, model, provider or publication changed.

The actual continuation must still verify the current root/control and a
defensible initial clock bound, confirm the first UTC quota period is clear,
and retain its own intent and recovery evidence. Maximum-value tests, the
30/90/365-day workload with 10,000 additional changes, independent semantic
quality, installed qualification and final review remain open.
