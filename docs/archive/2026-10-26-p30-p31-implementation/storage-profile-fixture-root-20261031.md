# Select the actual filesystem for storage-profile tests

2026-10-31, test-only increment based on `6156d5b`. The running clean `e86b1b8`
default suite reported a failure because `StorageProfileTest` assumed its
checkout was on Btrfs; the clone is on tmpfs. The first assertion saw `tmpfs`
before the intended unsupported-Btrfs publication was attempted. The original
full-suite failure remains evidence; no replacement aggregate is inferred.
The [plan](../../plan.md) owns completion and the
[testing manual](../../developer/testing.md#require-positive-controls-and-inspect-uncertainty)
owns the current fixture procedure.

The negative test now uses an existing Btrfs checkout or explicit
`IPSE_TEST_BTRFS_ROOT`. Without either, it skips that single mount-dependent case.
An explicitly selected wrong filesystem still fails before publication rather
than skipping. The exact qualified-kernel gate remains in force, including with
an explicit root. The positive tmpfs publication/idempotency/readback test is
unchanged. No native helper, runtime, quota, filesystem allowlist or approval
changed, and a skipped negative case supplies no Btrfs qualification.

Actual controls on the available exact-kernel host:

| Launch | Observed result |
| --- | --- |
| Final direct `mix test test/ipse/runner/storage_profile_test.exs` from the Btrfs checkout | 2 passed, including actual unsupported-Btrfs refusal and qualified tmpfs publication |
| Separate VM started on tmpfs, no explicit root | 1 passed, 1 explicitly skipped |
| Separate VM started on tmpfs, explicit actual Btrfs root | 2 passed |
| Separate VM started on tmpfs, explicit tmpfs root | Exactly 1 failed test, as required by the negative selector control; wrapper passed |

The first version of the conditional test tag lacked parentheses and refused
compilation; its log is retained. Correcting that syntax preceded all three
separate-VM results above. No failed control was counted as a passing product
test. The wrapper uses actual native transactions and Collection operations,
not a mocked filesystem result.

Local logs use `/tmp/ipse-storage-profile-*-20261031.log`; the source-derived
wrapper is `/tmp/ipse-storage-profile-root-control-20261031.exs`. The accompanying
[hash receipt](storage-profile-fixture-root-20261031.json) pins the final test,
wrapper, helper and four observed logs. Developer Testing and operator Arch Linux
were reviewed as whole documents. Testing now explains explicit mount selection,
temporary-directory cleanup and the distinction between skip and qualification.
No real model, service request or new dependency was involved.
