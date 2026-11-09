# Exact kernel 7.2.14 tmpfs storage profile

Historical qualification record, 2026-11-09. The operator explicitly authorized
reviewing and admitting the available host's new kernel, as for the
[7.2.11 profile](../2026-10-28-native-profile/index.md). Current behavior and
status belong to [the plan](../../plan.md) and the
[operator native-policy manual](../../operator/arch-linux.md#check-protected-storage-admission).

| Provenance | Value |
| --- | --- |
| Source | `codex/p30-p31` at `7833160d` plus the uncommitted selector, test-gate and manual changes committed with this record |
| Selector source SHA-256 | `e560c0a461eddd6fe8afc57b167247365f2bae221f090d9d852a950117693c98` (`native/ipse-storage-profile.rs`) |
| Host | Arch Linux `7.2.14-arch1-1`, x86_64, 20 CPUs, 46 GB memory |
| Toolchain | Elixir 1.20.4 on Erlang/OTP 29; Rust helpers from `./dev/build.sh` |
| Replacement | [Current plan](../../plan.md#execution-order-for-p30-and-p31) |

## Admitted scope

The tmpfs profile previously admitting only `7.2.11-arch1-1` now admits exactly
`7.2.11-arch1-1` or `7.2.14-arch1-1` on x86_64, with the unchanged feature checks:
4096-byte page, block and fragment units, selected global shmem policy `advise`,
and a uniquely resolved actual-directory tmpfs mount carrying exactly one
`huge=advise` option. Btrfs stays refused on both kernels. Other releases
(including `7.2.12-arch1-1` and `7.2.13-arch1-1`), other suffixes of `7.2.14`
and other architectures refuse. The `7.2.10` profile is unchanged. No limit,
reserve or environment switch changed.

## Host observation

Read-only observation on the host: kernel `7.2.14-arch1-1`, x86_64, page size
4096; `/tmp` is tmpfs with 4096-byte block and fragment sizes, mount options
`rw,nosuid,nodev,size=24524376k,nr_inodes=1048576,inode64,huge=advise,usrquota`,
and global shmem selection `always within_size [advise] never deny force`. The
7.2.11 record's mount options also carried `usrquota`; apart from the kernel
release and a 8 KiB difference in tmpfs size, the observed features match. The
checkout is Btrfs. No device, mount or kernel setting was changed.

## Checks actually run

| Check | Result |
| --- | --- |
| `./dev/build.sh` | Pass |
| `rustc --edition=2021 -D warnings --test native/ipse-runner.rs` | Pass; 88 passed, 2 ignored, including the 3 profile tests (new positive `7.2.14-arch1-1` and the refused neighbouring releases) |
| `mix test test/ipse/runner/storage_profile_test.exs test/ipse/session/ollama_model_pin_test.exs` | 11 passed; includes actual tmpfs Collection publication and the declared-Btrfs refusal on the checkout |
| `IPSE_TEST_NATIVE_STORAGE=1 mix test` | **4,399 passed, 0 failures, 136 skipped, 132 excluded**; 9,900.4 s; exit 0. `:native_storage` tests ran (the variable makes an unqualified host fatal) |

The full run is a single-VM local run on OTP 29, not the CI-parity OTP 27
toolchain of the [2026-11-08 baseline](../2026-11-08-whole-source-baseline/index.md).
Its total of 4,667 tests is that baseline's 4,665 plus two tests added since.
Opt-in workloads, including the 2,000-note integrated cohort, were excluded.

## Boundaries

As before, this qualifies protected storage transactions on the specified
tmpfs profile only. It does not qualify Btrfs or other filesystems on this
host, reboot or power-loss durability (tmpfs is volatile), installed user
journeys, performance or a whole-host filesystem claim. A kernel release
string is not an attestation of every machine that reports it.
