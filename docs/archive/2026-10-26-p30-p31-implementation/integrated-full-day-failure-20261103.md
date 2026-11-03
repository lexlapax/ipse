# Full-cohort integrated-day failure, 2026-11-02–03

This historical result is an incomplete synthetic checkpoint. The
[plan](../../plan.md) owns current requirements and status. The separate
[seven-note smoke](integrated-final-smoke-20261102.md) remains distinct.

The isolated snapshot was commit `b10df4a556c097b686eecba1267e3d6425f0f8bc`
plus the three files in the earlier [runner fingerprint manifest](integrated-full-day-preflight-20261102.sha256).
The snapshot excluded `docs/archive` and used separate dependencies, build and
home. Targeted formatting, native/bundled build, forced compilation with warnings
as errors, and focused tests passed; the focused tests reported 2 passed and 1
skipped using seed 791956. The opted-in full test used seed 791957 and failed
after 8,957.1 seconds. Its [exact test log](integrated-full-day-failure-20261103-run.log)
and [first-turn log](integrated-full-day-failure-20261103-turns-1.log) are retained.

The fresh seed closed 273 segments, producing 2,000 public notes and 100 pin
publications. Its read-only audit verified 1,800 ordinary, 100 pinned, 50
preference and 50 current records, 373 unchanged original sources, and unchanged
collection root and control. The audit measured 134,172,672 allocated bytes for
its listed collection/control/identity/management/session components; that is a
sample of selected components, not a whole-root or peak measurement. The first
closed-segment marker has a recorded filesystem time of 2026-11-02 22:34:40
Pacific; the final seed marker is 2026-11-03 00:49:59, and the parent-written
audit log is 01:01:12. These are filesystem timestamps, not direct measurements
of physical completion boundaries. Audit output files created under the fixture
clock have simulated timestamps and must not be treated as real times.

The first 14 of 57 planned day effects closed, all ordinary-addition captures.
The first new Session turn recorded its intent and an in-flight marker but no
result. Its retained journal has one `input_received`, one
`extension_invocation_intent`, 11 `extension_action_intent` events and 10
`extension_action_result` events; the last unmatched action requests
`collection.call` / `get`. It contains no `inference_dispatch_intent` or
`turn_finished`. The loopback fixture's listener timed out after 30 seconds
without accepting a connection, and its linked task terminated the turn
process. This is distinct from the configured 15-second provider inference
timeout; the retained evidence does not show that inference was dispatched.
The first turn is retained as unresolved and is not automatically replayed.

The original synthetic root remains at
`/tmp/ipse-native-seed-integrated-full-520e8f45f283205ed1d526e3669abdde`.
The [fingerprint manifest](integrated-full-day-failure-20261103.sha256) binds
the archived logs and selected retained audit, fixture, closure, turn marker and
journal files. Paths under `/tmp` depend on that retained environment; hashes do
not replace the underlying evidence. The [contention note](integrated-full-day-failure-20261103-contention.txt)
records concurrent pure-Elixir and filesystem activity, so timing samples are
not uncontended performance results.

A separate byte-for-byte forensic backup is retained at
`/tmp/ipse-retained-forensic-backup-b10df4a5`. Its
[97-file hash manifest](integrated-full-day-failure-20261103-backup.sha256)
was verified against both the backup and the original files. It includes the
failed turn journal and markers, all 14 effect intents/results/closures and
their referenced inputs/reports/logs, and seed-audit artifacts. The copied
files have different paths and inodes and cannot provide the original source
authority; no automatic restoration or replay is permitted.

The 20-addition intake and balanced additional-change mix are provisional
synthetic choices, not pilot-derived or accepted as representative. No 40-turn
day, full 57-effect day, quality evaluation or annual qualification passed. A
future diagnostic must use a distinct Session and prompt, preserve the failed
turn and effect evidence, and verify the original source-owner and read-only
boundaries; it must not restart this run or replay its unresolved turn.
