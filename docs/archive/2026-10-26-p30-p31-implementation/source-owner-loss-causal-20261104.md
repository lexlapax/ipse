# Confirm native source-owner exit before the publication fault — 2026-11-04

This is a scoped test-witness correction on the unchanged product/native helper.
The original serial run remains failed: its callback closed the BEAM Port before
the native switch, but did not establish that the OS exporter had exited before
the native decision. Retained state proves the B pending row really published;
absent delivery did not mean no effect. That first outcome is preserved.

The corrected callback matches the held share's actual OS PID to Port.info,
initiates close, and uses the existing bounded NativePipeScope exit waiter before
returning the synchronous staged callback. The test requires a separate confirmed
exit message. Read failures or unknown process state cannot count as exit. All
original no-publication, full-liability, Saved and idle/no-replay assertions remain.
No product/native API, timer, grant or capacity changed.

One fresh two-case cohort passed: **2 passed, 237 excluded, 17.2 seconds**. The
second case was the unchanged StoredSources native owner-loss guard. In the
corrected main-route case, the original Collection generation/floor stayed 1/1,
the exact B pending row and operation remained absent, the original A journal
bytes were unchanged, full liability remained reserved with nil actual/receipt,
and full Saved plus inert same-ID reopen passed. Pure retained-state decoding
confirmed those facts without another native call, replay or cleanup.

The complete private runtime had 241 declared modules/744 files and matched the
current product/helper. Runtime, fixture, source and entry hashes plus pathsets
were unchanged afterward. The cohort process/root-marker check and shared
operator-input lock check found no holders before release. The fresh root is
retained privately. One selector-only preflight constructor issue was fixed
before any App/test/native effect; it was not an actual attempt.

This result qualifies the strengthened causal fault witness. It neither proves
the old run's OS-exit ordering nor retroactively passes the old serial aggregate.
The separate Port-close premise component found the same helper still alive
immediately after close in 50/55 observations, followed by 55 confirmed exits;
that supports the distinction but is not original-case causal evidence.

See [safe result](source-owner-loss-causal-20261104/result.json),
[original failure](source-owner-loss-causal-20261104/original-serial-failure-safe.json),
[test-only patch](source-owner-loss-causal-20261104/confirmed-native-exit.patch) and
[evidence scope](source-owner-loss-causal-20261104/scope.md). The
[Collection publication contract](../../developer/collection-sdk.md) retains its
native final-decision and unknown/no-replay rules. No operator procedure changes.

Historical evidence only; current milestone status remains in [the plan](../../plan.md).
