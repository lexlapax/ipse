# Frozen source regression groups — 2026-11-04

This dated record preserves execution against one source candidate. The
[plan](../../plan.md) owns milestone acceptance and
[testing](../../developer/testing.md) owns procedures. The earlier
[failed combined run](combined-source-regression-20261104.md) remains failed.

The exact 473 test files formed disjoint explicit groups of 245, 77, 76 and 75
files. Their source was parent `d3dab913c96fcf4455120470b6a157bebe4547e8` plus
the reviewed worktree overlay. Each received complete private source/Git/index,
runtime/dependency/Hex, HOME and temporary state. Verified CoW copies used no
hardlinks or silent fallback. Ordinary explicit Mix file lists were used without
a second partition filter; the serial group alone owned native operator input.

## Terminal results

| Group | Files | Passed / executed | Skipped | Excluded | Seconds |
| --- | --- | --- | --- | --- | --- |
| Serial, corrected UTF-8 environment | 245 | 2,173 / 2,174 | 121 | 122 | 5,815.3 |
| Parallel 1, corrected UTF-8 environment | 77 | 609 / 609 | 2 | 0 | 1,156.0 |
| Parallel 2 | 76 | 648 / 648 | 4 | 0 | 266.4 |
| Parallel 3 | 75 | 588 / 588 | 1 | 1 | 1,211.2 |

The outer Mix aggregate is **4,018 / 4,019 passed, one failed, 128 skipped and
123 excluded**, with no invalid cases reported. Nested subprocess summaries are
not added again. Each group's eleven integrity postchecks passed: source,
runtime and dependency bytes; runtime/source pathsets and links; Git identity;
Mix metadata type; private Hex; and unchanged original top-level entries with
bounded new outputs. The status files have twelve fields including test_exit;
the serial test_exit was 2. The exact mutable Mix failure metadata was recorded
separately; compiled runtime and artifact bytes were unchanged. The serial
launcher/BEAM were gone and the shared operator-input lock had no holder.

The [file assignment](source-regression-groups-20261104/common/unified-testfile-manifest.json),
[nonoperator receipts](source-regression-groups-20261104/evidence.sha256) and
[terminal aggregate](source-regression-groups-20261104/terminal/aggregate.json)
retain the exact inputs and outcomes. The terminal
[evidence manifest](source-regression-groups-20261104/terminal/evidence.sha256)
has SHA-256 `e94dc2c359d1257c3bc879f78ebdf0855b2e9a850c8ee4c727dececdd6fb2244`.
Its common inventories are retained once in the sibling `common/` directory;
historical private packet names in JSON remain provenance, not new runtime pins.

## Preserved owner-loss failure and fresh causal control

The failed original-A owner-loss fixture closed the shared Erlang Port after
staging. Collection generation/floor advanced from 1/1 to 2/2 and the intended
B record published without a completed capture result. Later liability and
Saved assertions were not reached. The old callback did not establish that the
OS exporter had exited before the native switch; absent delivery did not imply
no effect. The [original safe failure](source-regression-groups-20261104/terminal/serial/failure-01-safe.json)
and all original state remain preserved.

A [separate causal correction](source-owner-loss-causal-20261104.md) matches the
native PID and uses the existing bounded exit waiter inside the staged callback,
then requires an independent confirmed-exit message. One fresh two-case cohort
passed **2 tests, 237 excluded, 17.2 seconds**, including the unchanged native
StoredSources owner-loss guard. Original no-publication, full-liability, strict
Saved and idle/no-replay assertions all ran. Product/native code, deadlines and
permission boundaries were unchanged. This does not retroactively pass the
original serial run or establish its historical OS-exit ordering.

A separate [Port-close component](source-regression-groups-20261104/source-port-close/README.md)
observed the same native executable alive immediately after 50 of 55 closes,
then confirmed all 55 exits. Its earlier setup failures and unavailable first
nine observations remain recorded. This supports the witness distinction; it
is not original-case causal evidence or an additional publication qualification.

## Preserved launcher failures and limits

The first serial invocation stopped during fixture compilation after an isolated
environment omitted a UTF-8 locale. The first parallel group ended 599/609 passed
with ten failures: nine decoded an Elixir warning prefix as JSON, and one failed
removing Unicode names under Latin-1 filename encoding. Integrity checks passed.
Separate setup-only RED/GREEN controls reproduced both without App, native-input
or model effects. Explicit installed `LC_ALL=C.utf8` fixed both; corrected runs
used fresh copies/state, leaving old failures intact. The terminal packet keeps
those statuses, exact classifications, proof sources and versioned launchers.

This is a terminal full-file regression record plus a separately passing causal
test correction, not a flat all-green aggregate or P30/P31 completion. Installed,
retained-cohort recall, complete-day, annual workload and broader consumer/quality
gates remain separate. The later [P30 current-use test additions](p30-advice-output-revocation-20261104.md) have separate focused results and were not part of this frozen 473-file assignment. No old unknown Session or effect was replayed.
