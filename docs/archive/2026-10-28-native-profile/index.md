# Exact available-host tmpfs storage profile

Historical qualification and implementation record, 2026-10-28. The user
explicitly authorized changing the gates to use the available host. This record
supports a narrowly scoped production selector change; current behavior and
status belong to [the plan](../../plan.md) and
[operator native-policy manual](../../operator/arch-linux.md). It supplements,
rather than relabels, the earlier
[kernel recovery investigation](../2026-10-26-p30-p31-implementation/kernel-profile-recovery.md)
and [private capacity diagnostic](../2026-10-26-p30-p31-implementation/capacity-available-host.md).

## Admitted scope

The new storage-allocation profile accepts only `7.2.11-arch1-1`, compiled for
64-bit Linux x86_64, on tmpfs with all of these actual-FD checks:

- Filesystem block and fragment sizes agree and are exactly 4096 bytes.
- The runtime page size is exactly 4096 bytes.
- The global selected shmem huge-page policy is exactly `advise`.
- The actual retained directory's mount ID resolves uniquely to tmpfs with
  exactly one `huge=advise` option.
- Existing protected ownership, file/directory identity, single-link,
  retained writer leases and zero directory-allocation checks all succeed.

Other `7.2.11` releases and suffixes, other architectures, other filesystems,
page/block deviations and other huge-page selections refuse. In particular,
Btrfs is **not admitted on the new kernel**. The old `7.2.10`/`7.2.10-*` profile
and its previous Btrfs/tmpfs behavior are preserved; they were not requalified
here. No general environment switch or caller-selected quota can widen these
gates. General shell helper selection remains separate from the compile-pinned
protected helper.

Dense staged files still use twice their per-file allocation-unit rounding as
the pre-publication reserve, with the existing per-file, batch and total bounds.
Allocated usage is still actual `st_blocks` accounting; unsupported conditions
do not become an estimate. Existing native accounting synchronizes retained
pending files while holding all writer leases before allowing a fresh inventory.
An unconfirmed sync refuses inventory/preflight/publication. The 24-MiB domain,
64-MiB total, 22-MiB control reserve and all host consent/source boundaries are
unchanged.

## Actual host and build

The escalated read-only observation found kernel `7.2.11-arch1-1`, x86_64,
page size 4096. `/tmp` is tmpfs with 4096-byte units and `huge=advise`; global
shmem selection is `[advise]`. The checkout is Btrfs with 4096-byte units and
`compress=zstd:3`. The exact recorded features and source hashes are in
`provenance.json`. No device, existing mount or global kernel setting was changed.

Only a new private graph was built:
`_build/native-profile-sol-20261028`. Current native sources were copied into
its `project/native/`; its helper was compiled with production optimization,
stripping and abort settings plus warnings denied. Only Runner was recompiled
in the copied application graph to bind that helper's checksum and private
application path. The shared `priv/ipse-runner` and earlier diagnostic graphs
were not changed by this section.

| Artifact | SHA-256 |
| --- | --- |
| New selector source | `6a96b7ecb7005b4d65a9f47864a6cd72169b99c4e707b325c9c1eae9a40843ad` |
| Actual production-profile helper used here | `6407e40e96498029ff7e13d96215a263812732aad1979b4c3e5f4b867b5a4d56` |
| Earlier private diagnostic helper, not reclassified | `86d6226c868b7095c6ba7460cc0b42832e98fb70feea0779fb3473ac7bb28a6a` |

The exact helper hash identifies this build, including its build path/toolchain.
A later normal source/package build must bind its own newly built helper and
retain its own receipt. Kernel release and feature observations are not source
or secure-boot attestation of every machine bearing the same release string.

## Focused qualification actually run

The helper and its Rust test binary compiled with warnings denied. The
compile-bound Runner rebuilt with warnings as errors. Three Rust profile tests
passed, with 67 other native tests filtered out. They verify checked rounding
and arithmetic, the finite kernel selector, mount-ID uniqueness, filesystem type,
page/block deviations, all unqualified huge-page choices and preservation of
the older profile's choices. See [the profile controls](profile-unit.log).

One native batch selected the transaction tests and two new profile tests.
It finished in 4.8 seconds: **22/24 passed**, with two fixture failures. The
unchanged source selector and its actual positive/negative admission ran in
that batch. Existing controls cover multiframe/exact-eight-MiB staging, owner
death during a partial staged write and subsequent accounted reinventory,
injected sync failure refusing new stage, retained locks and identities,
foreign/stale capabilities, cancellation, protocol framing/deadlines, quota
preflight and refusal before file creation. The sync-failure fixture injects an
error after actual sync; it is not physical writeback-error injection.

The first batch also established actual new-kernel Btrfs refusal at quota and
Collection publication, leaving no published root. The new production helper
on tmpfs admitted quota, staging, an actual Collection commit and readback
despite an invalid ambient `IPSE_RUNNER_PATH`. This is the protected production
helper path, not a caller-selected fixture helper.

Two fixture expectations needed repair:

1. The existing separate-VM lock contender inherited code paths in reverse
   priority, so it selected a different Runner and returned unavailable before
   the intended busy boundary. Reversing the argument construction preserves
   the parent's actual code-path priority; no lock refusal was weakened.
2. The new duplicate-publication assertion expected the bare initial receipt;
   Collection's established `existing` result wraps it under `operation`.

Only these two failed cases were rerun: **2 passed, 22 excluded**, in 3.4
seconds. See the retained
[initial batch](native-qualification-first.log) and
[selected repairs](native-qualification-repairs.log). This is not represented
as one clean 24-case run. No aggregate Elixir suite or 4,000-publication workload
was repeated.

An independent root-agent source review found no concrete selector defect. It
covered the exact kernel/architecture branch, filesystem selection before
feature checks, actual-FD mount lookup, page/global/mount gates and absence of
an environment bypass. It did not independently repeat the native batch.

The root agent subsequently ran a separate actual native CLI integration with
this production-profile helper and pinned Runner in a fresh tmpfs graph:
one selected case passed, five excluded, in 12.6 seconds. It exercised native
enable, capture, revocation, forgetting and protected operation inspection.
The initial launcher failed before testing because its code-path wildcard was
not expanded; that failure and the corrected loader are retained with
[the separate management integration record](../2026-10-26-p30-p31-implementation/managed-forget.md).
This does not relabel earlier private-helper journeys or establish an installed
human journey, an aggregate suite or support for Btrfs on the new kernel.

## Boundaries and location implications

This qualification is for protected storage transactions on the specified
tmpfs profile. It does not qualify every filesystem on this host, native shell
sandboxing, inference, paid accounts, annual domain turnover, installed user
journeys, performance, power loss or reboot durability. Tmpfs is volatile;
process-restart tests do not establish persistence after reboot or unmount.

Protected homes, control roots, state stores and collection stores must reside
on an admitted filesystem with the required features. On this host a default
home on Btrfs remains unqualified for these protected writes and fails closed.
Choosing a qualified tmpfs location must be an explicit operator decision with
its volatility disclosed. Do not silently relocate existing state, infer that
`/run/user` has the same features, or describe an ephemeral home as a durable
storage remedy. Ordinary unprotected tools and host paths have their own gates.

The earlier Btrfs capacity/CLI/authority diagnostics remain useful functional
evidence under their recorded private helper. They are not converted into this
tmpfs production-profile pass, and their old sources/helpers/stores stay intact.
The unresolved Btrfs error-cleanup accounting path still requires isolated
writeback-I/O/allocation-failure evidence and its own reviewed admission change.
No loop/device-mapper or existing filesystem fault injection was attempted.

`manifest.json` binds every retained artifact and source snapshot. The root
integration must update whole manuals and rebuild a fresh source/package graph
with this selector; it must not overwrite earlier diagnostic evidence or claim
whole-host filesystem qualification.
