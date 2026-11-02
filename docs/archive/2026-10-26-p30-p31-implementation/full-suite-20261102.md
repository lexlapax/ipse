# Complete frozen source baseline — 2026-11-02

Dated **2026-11-02**. Author-run verification of frozen
`39c8043f84d5f9c15ab22acf41afc7dde6adc123` in an independent clean clone.
This is a failed regression baseline, not milestone completion, installed
qualification or an independent audit. [The plan](../../plan.md) owns current
status; [testing](../../developer/testing.md) owns the verification procedure.

## Actual terminal result

```sh
mix test --max-cases 1 --seed 791758
```

The parent command exited **2** after **7,658.9 seconds**: **3,747/3,748 passed,
one failed, 118 skipped and 112 excluded**, with 3,978 declared cases. The
[receipt](full-suite-20261102.json) binds the actual terminal exit, complete final
summary, consecutive parent failure heading and verified pre/post inventories.
Nested subprocess summaries are not added to the parent counts.

The single parent failure is
`test/ipse/extension/managed_collection_call_session_test.exs:8841`,
“interrupted protected outer remains unknown and never replays on resume”.
After the fixture's held marker, `Session.cancel/1` returned
`{:error, :cleanup_unconfirmed}` where the test required `:ok`. The test stopped
there, so its later confirmed-close and inert-resume assertions did not execute
in this run. This observation does not establish a fixture-only cause or justify
accepting uncertain cleanup as confirmed. Reproduction and diagnosis remain open.

A first focused launch in the restricted sandbox failed before executing tests:
Mix's TCP-based filesystem lock returned `:eperm`. The permitted-executor run
of the unchanged original case, seed `791763`, passed one test with 189 excluded
in 11.2 seconds and exited 0. Its raw log is
`/tmp/ipse-protected-outer-cancel-repro-network-20261102.log`; the failed startup
log is `/tmp/ipse-protected-outer-cancel-repro-20261102.log`. This focused pass
does not diagnose the full-run failure, prove it harmless or replace the aggregate.

The earlier complete `f44b63c` result of 3,653 passed and 54 failed remains
[historical evidence](full-suite-20261101.md). This newer result is its own
complete execution; it is not computed by subtracting focused repairs.

## Frozen inputs and observations

The independently built checkout is
`/tmp/ipse-p30-p31-fullsuite-20261102-compatibility`. Its source was cloned without
hard links from the committed branch; private staging directories were not copied.
Dependency sources were supplied separately, then `./dev/build.sh` and
`MIX_ENV=test mix compile --warnings-as-errors` both completed with exit 0 before
the prelaunch freeze. No build or source edit changed that checkout during testing.

Prelaunch and post-terminal verification match:

- 7,877 tracked source paths;
- 633 test-runtime BEAM/application files;
- 83 runtime private assets;
- exact source HEAD, clean tracked status and native helper bytes.

The native helper SHA-256 remains
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
The inventory compares path sets and file bytes; build symlinks also include
followed contents, while source/private symlinks bind link text. It does not
inventory the complete system Elixir/ERTS/library closure, environment, permissions,
inodes, in-memory test code or generated child artifacts. It is not complete
machine isolation or a record of every loaded object.

The raw log is `/tmp/ipse-full-p30-p31-20261102.log`, with SHA-256
`2c5bea09c5f52339ad8cdabdfed0fc35dff0fbc72c97e31f4ed8c255571a142e`.
The receipt retains hashes of the original prelaunch and postcheck JSON files.
Its parser requires the last complete end-of-log summary, matching actual exit,
consecutive exact parent failure headings and verified inventories. Its 3,935-case
minimum only rejects a nested child summary; it is not an independently derived
exact current count.

Native/Mix/terminal cohorts were serialized. Later development in the original
checkout includes the separately verified process-clock fixture and documentation
correction. Its standalone clock checks used private compiler outputs and plain
VM/Rust children without starting Ipse or a native terminal; they changed no frozen
input or process environment. The later native clock-lifecycle draft was only
compiled in memory, without starting Ipse, during this run. None of those later
files is qualified by this frozen aggregate.

## Remaining acceptance

The cancellation failure must be diagnosed while preserving unknown effects,
actual resource exit, journal lineage and nonreplaying recovery. A later focused
pass cannot turn this failed complete baseline into a passing one. Skipped and
excluded cases remain unexecuted here, including unavailable platform/native
profiles and separately selected controls. Live accounts, independent model
quality, Word fidelity, sustainable turnover, installed journeys, final audit and
reviewer handoff retain their separate open gates.
