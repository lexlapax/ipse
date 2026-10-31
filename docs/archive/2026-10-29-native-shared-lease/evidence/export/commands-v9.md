# v9 receiver and race controls: recorded commands

These commands were run from the repository root on the host recorded in
`platform-v9.txt`, using `rustc-v9.txt`. The helper binaries used source from
`source-v9.tar`; the v9 fixture was compiled after that helper. The commands
below preserve the original output paths and test selections. They operate on
private synthetic directories and do not activate either user path.

```sh
rustfmt --edition 2021 dev/fixtures/transaction_lease_export.rs
rustc --edition=2021 -D warnings native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-export-v8
rustc --edition=2021 -D warnings --cfg ipse_lease_export_test_hook native/ipse-runner.rs -o _build/shared-lease-sol-20261029/ipse-runner-export-race-v8
rustc --edition=2021 -D warnings dev/fixtures/transaction_lease_export.rs -o _build/shared-lease-sol-20261029/transaction-export-test-v9
task_dir=$(mktemp -d /tmp/ipse-receiver-v9-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-test-v9 --receiver-controls "$task_dir" > _build/shared-lease-sol-20261029/receiver-controls-v9.log 2>&1
valid_dir=$(mktemp -d /tmp/ipse-valid-v9-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-test-v9 "$valid_dir" _build/shared-lease-sol-20261029/ipse-runner-export-v8 0 > _build/shared-lease-sol-20261029/receiver-valid-v9.log 2>&1
race_dir=$(mktemp -d /tmp/ipse-race-v9-XXXXXX)
_build/shared-lease-sol-20261029/transaction-export-test-v9 "$race_dir" _build/shared-lease-sol-20261029/ipse-runner-export-race-v8 12 > _build/shared-lease-sol-20261029/transaction-export-race-v9.log 2>&1
```

The checks were run outside the restricted sandbox after an earlier attempt
failed with EPERM. The recorded v9 fixture binary and both helpers remain in the
build directory identified above; their hashes and the archived logs are in
`review-repairs-v9.sha256`. A fresh build can differ in binary hash due to its
build path or toolchain, so source, compiler details and commands are retained
separately from the observed binaries.

## Reproduce from the saved cohort

The commands above are the historical invocations, not a fresh-checkout recipe:
the repository fixture has since changed. From the repository root, extract the
unignored v9 archive into a new private directory and compile both helpers and
the fixture from that extracted source. The following equivalent sequence was
verified on 2026-10-29 in `/tmp/ipse-v9-independent-repro-46984`:

```sh
cohort=$(mktemp -d /tmp/ipse-export-v9-repro-XXXXXX)
mkdir "$cohort/out" "$cohort/receiver" "$cohort/valid" "$cohort/race"
chmod 700 "$cohort/receiver" "$cohort/valid" "$cohort/race"
tar -xf docs/archive/2026-10-29-native-shared-lease/evidence/export/source-v9.tar -C "$cohort"
rustc --edition=2021 -D warnings "$cohort/native/ipse-runner.rs" -o "$cohort/out/ipse-runner"
rustc --edition=2021 -D warnings --cfg ipse_lease_export_test_hook "$cohort/native/ipse-runner.rs" -o "$cohort/out/ipse-runner-race"
rustc --edition=2021 -D warnings "$cohort/dev/fixtures/transaction_lease_export.rs" -o "$cohort/out/fixture"
"$cohort/out/fixture" --receiver-controls "$cohort/receiver" > "$cohort/out/receiver.log" 2>&1
"$cohort/out/fixture" "$cohort/valid" "$cohort/out/ipse-runner" 0 > "$cohort/out/valid.log" 2>&1
"$cohort/out/fixture" "$cohort/race" "$cohort/out/ipse-runner-race" 12 > "$cohort/out/race.log" 2>&1
```

The receiver, real-helper and deliberate owner-loss-race markers all appeared
in the independent run. This rebuild does not reproduce the recorded binary
hashes and does not enable or qualify a production sink. The archive must be
included in the eventual commit; being unignored alone does not track it.
