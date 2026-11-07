# Rejection follow-up diagnostic setup — 2026-11-06

Historical synthetic verification. The [plan](../../plan.md) owns current
acceptance status; [recovery guidance](../../operator/recovery.md) describes
operator handling of unknown effects.

A separate instrumented test was intended to identify the preflight branch
that refused a follow-up turn after a known rejection. The fresh synthetic
fixture built its Knowledge artifact but stopped during setup with
`extension_bundle_unavailable`: its isolated runtime did not have the bundle
catalog and the launch omitted the fixture's fresh-bundle setting. The test
reported zero of one selected tests passed and 21 excluded. It did not reach
native rejection, the follow-up turn, or the model. It supplies no diagnosis of
the earlier refusal and no recapture-suppression result.

The failed log SHA-256 is
`c063a86d14866ffd25c74f1fadcaa614727a76ea705cefaf862ba024526765db`.
The fresh synthetic root and log are retained; the owned process group was
empty, and independent host checks found the Input lock and TCP 39657 free.
The explicitly declined retained-notebook check was not run, and its records
and unknown outcomes were not used or replayed.
