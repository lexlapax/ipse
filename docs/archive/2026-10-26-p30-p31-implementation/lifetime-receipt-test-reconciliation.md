# Lifetime-gate test expectations and fresh-header recovery

Historical scoped receipt, 2026-10-29. This follows the
[lifetime containment record](strict-gate-lifetime-followup.md) and its
[independent review](strict-gate-lifetime-independent-review.md). It does not
qualify protected publication or complete P31C0.

The subsequent independent scoped review verified the eleven manifest entries,
209 runtime BEAM hashes and the frozen source/test hashes. It found the stale
State expectations reconciled while historical receipt validation and ordinary
no-deadline CAS remained covered; it did not rerun tests. The DocumentStage
reconciliation is a separate cohort, and no effect-lifetime architecture is
qualified by this review.

Two older State tests still executed deadline-bearing writes expecting successful
writes, conflicts or elapsed-deadline metadata. Current execution refuses all valid
`write_before_ms` writes before storage. The tests now assert that refusal for
elapsed and future deadlines, including stale revision/generation and missing
keys. They check unchanged state and use ordinary no-deadline requests for real
CAS success/conflict controls. Historical elapsed/conflict/success receipts remain
explicit validator inputs; accepting their shape is historical inspection, not
permission to execute a new deadline-bearing write. No State runtime or receipt
validator changed in this follow-up.

The separate Linux fresh-header implementation can return `header_unconfirmed`.
The CLI now maps it to preservation of pending files and any published journal,
inspection before explicit resume after the lock is free, and no automatic
startup retry. Its recovery anchor is `respect-active-ownership`. Recovery guidance
also records matching-helper, no-replace rename and directory-fsync prerequisites,
refusal without unsafe fallback, and the current conservative close lifecycle
record. These are diagnostic and documentation changes; the header protocol and
Session startup implementation were not tested by this cohort.

Focused evidence:

- 46906: the first runner failed copying its graph because its destination parent
  was absent, before compilation/tests. The runner now creates that parent.
- 46907: strict Errors compilation passed; only the two affected State tests and
  two mapped-error/recovery tests ran: **4 passed, 23 excluded**, 0.03 seconds.
- 46908: documentation/link checks passed: 738 Markdown files, 6225 local links,
  zero errors, before this additive record. Permission warnings concern unrelated
  inaccessible fixture ledger directories.
- 46910: final additive-record documentation check passed: 739 Markdown files,
  6228 local links, zero errors.

The [manifest](lifetime-receipt-test-reconciliation/manifest.json) preserves source,
runner, logs and exact runtime hashes from the isolated
`_build/lifetime-receipt-followup-sol-20261029/lib` graph. Its base is the frozen
lifetime cohort with only the Errors BEAM rebuilt. No native helper was rebuilt,
no paid service or PTY was used, and no aggregate suite ran. Word owns the separate
DocumentStage expectation reconciliation.

The literal-v4 two-source A/B publication control and an enforceable final-effect
lifetime architecture remain open. Current protected publication gates stay
closed; these tests do not convert historical positive receipts into acceptance.
