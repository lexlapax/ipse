# Integrated synthetic smoke on the formatted overlay, 2026-11-02

This historical receipt records a seven-note synthetic smoke, not the notes
journey or milestone acceptance. The current requirements remain in
[the plan](../../plan.md). It follows the earlier [smoke receipt](integrated-smoke-20261102.md).

The isolated source was commit `36bcdaa85e996e822fea4ee9d782bd5c7e030403`
plus the six formatted overlay files identified by the evidence manifest. The
snapshot used its own dependencies, build and home; it excluded other uncommitted
working-tree changes. The six overlay hashes matched both the snapshot and the
corresponding working-tree files after the test. This run includes the subsequent
`apply/3` seed calls and the opt-in evidence-retention test change.

The isolated native and bundled build and forced test compile with warnings as
errors passed. Focused seed and integrated checks passed with 7 passed and 1
opt-in smoke skipped. The opted-in native smoke then passed with 1 passed and 3
excluded in 616.6 seconds. It used a fresh seven-note cohort, four native effects,
and 40 actual `Session.prompt` turns against a loopback synthetic provider. It
checked the audit and that a second run refused replay. No paid service was used.

The [evidence bundle](integrated-final-smoke-20261102-evidence.json) contains the
completed manifest and all 96 synthetic JSON records, preserved as UTF-8 strings.
The manifest lists each original path, byte count and SHA-256, as well as the six
source-overlay fingerprints. All 96 extracted records were checked against their
original SHA-256 values after bundling. The separate
[bundle checksum](integrated-final-smoke-20261102-evidence.sha256) identifies the
bundle itself. The records contain generated IDs, hashes, sizes, times and local
temporary paths; they do not contain provider request bodies. The test removed
its temporary root after completion. Full session journals and provider requests
are therefore unavailable for later independent reconstruction; the bundle's
journal and request fingerprints cannot by themselves establish their contents.

This result does not establish live-provider or human outcomes, interruption
recovery, quality, the 2,000-note integrated journey, or annual qualification.
Those gates and verification of the final combined source remain open.
