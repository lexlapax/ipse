# Serenity fault diagnostic attempt, 2026-10-27

This record follows the [pre-run review](FAULT-CANDIDATE-REVIEW.md). The
coordinating agent executed the reviewed harness. The container exited 3 during
provisioning and emitted `DIAGNOSTIC_UNKNOWN: provision pending; inspect
receipt`. No native fault frame was reported. This is not evidence of EIO,
completed fault testing, cleanup or kernel qualification.

The exact retained container is
`073aa9ac40e7f0af2e0d43be1659cf10c2ca1ce32a6cc203bd4c566d4f4dcb46`; its
name is `ipse-fault-63ebcfd6bc5a4167223662f0dae3539d`. The exact root-owned
stage is `/tmp/ipse-fault-stage.hDULn7U2`, device:inode `53:270135`; the
persistent ledger remains under
`/home/lexlapax/projects/lexlapax/ipse/.serenity-module-receipt.6Fow8PKP`.
The retained synthetic backing has device:inode `53:270861`, size 536870912
and zero allocated blocks at the read-only observation. The kernel modules,
loop index and any mapper state must be treated as retained/unknown until a
separately reviewed recovery is executed.

[Captured host files and a read-only ledger/fixture transcript](fault-actual-evidence/SOURCE-SHA256SUMS)
show loop configuration confirmed and mapper creation pending. The recorded
command output identifies the exact nonce mapper, major:minor `252:4095`, open
count 0, and linear table `0 1048576 linear 7:4095 0`. Read-only host sysfs
reported loop `25:601631`, mapper `25:660633`, the exact nonce name/UUID, and
the mapper as the loop holder. The guardian receipt ends at `stop-pending
supervisor-lost`; signalling, final process cleanup and backing release are not
confirmed. The mount directory appeared empty in a separate namespace. None of
these observations establishes global quiescence or authorizes deletion.

The independently reviewed likely cause is that `fixture_mount` treats the
required Docker bind at `/work/mount` as an error before the Btrfs mount because
its filesystem is tmpfs. A separate no-device container reproduced that bind
mount representation. The log stops immediately after the corresponding mapper
observations, but there is no traced error stack: this is a strong inference,
not a proven exact failure site. There is no format, Btrfs mount or injected
fault record. Do not replay pending operations or automatically remove the
retained index, mapper, backing, stage or ledger.
