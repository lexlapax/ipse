# Fresh renewal control 03 preparation — 2026-11-04

Historical failed attempts remain intact. The initial typed-expiry product
attempt reached inference and exposed the outer callback error normalization;
the reviewed product repair now propagates only authenticated expiry. Fresh
attempt 02 used the repaired complete host and worker build but stopped after
its day-0 seed: the fixture directory lacked `provider_fixture.ex`. It did not
renew permission or make a model request. Its root is not resumed.

Attempt 03 uses the identical frozen attempt-02 product, rebuilt catalog and
clock Runner adapter. The only execution-fixture changes are a new independent
directory/root/claim, corrected relative references to that directory, inclusion
of the original tracked provider helper, and a mandatory helper hash check
before creating or seeding the native test root. The renewal helper and lifecycle
helper are byte-identical to attempt 02. The provider helper is byte-identical
to this snapshot's tracked `test/support/provider_fixture.ex`.

Pure prevalidation parsed the complete static literal `Code.require_file/2`
closure (19 files, including branches not selected by this control), parsed the
entry and selected test, and strictly compiled all three helper modules with
`elixirc --warnings-as-errors`. No application, Session, native input, provider,
or retained 2,000-note cohort was used. A first sandbox-only prevalidation setup
could not see the real tmpfs dependency symlinks; its missing-Jason warnings and
partial helper beams are preserved under `prevalidation-setup01`. The corrected
prevalidation used the actual frozen dependency paths and produced an empty
strict compilation log.

`required-helpers.sha256` pins 26 explicit paths, including that closure, entry,
selected test, launcher, prevalidation source, clock/PTY binaries and the clock
runtime manifest. `renewal-fixtures.sha256` additionally pins the required-helper
manifest. Runtime and tracked-source inventories remain the frozen attempt-02
inventories. A small own write/sync quota probe and all manifests must pass
before effects. ExUnit selection must resolve to the one renewal-recall case
before its body executes. Product deadlines and authority checks are unchanged.

This control creates only a new small synthetic fixture. It neither accesses nor
mutates the retained 2,000-note cohort or any prior unknown turn. Retained-cohort
native renewal requires a separately reviewed exact allowed-delta intent after
this prerequisite passes.
