# Serenity isolated tmpfs unmount observation

Recorded 2026-10-27. This is a disposable tmpfs diagnostic, not Btrfs or
block-device qualification. No block device was used. The reviewer checked the
supervisor's gate, target FD inventory, namespace handles, process identity,
unknown handling and code diff, and found no further blocker for this one
experiment under the stated trusted same-user/host and noninterference
assumptions. The reviewer did not execute it.

The reviewed, logging-only revised sources are `tmpfs_umount_probe.rs` (SHA-256
`cf2589b9af8f5b6b1f7a752191272f3cb8f0b346fe17a8ecb24e35df2669c341`) and
`tmpfs_umount_supervisor.exs` (SHA-256
`d28832cf4f7560b8534b90c4fd233fa492b32c902063c51ac1274a3d1ab4a6d6`). The
locally compiled diagnostic binary SHA-256 was
`608754340028c02a2c6cc4927870b1ad4c0c3632053ce96facd5fea199d3267f`; binaries
are not included in this archive. The supervisor launched one `unshare` child,
verified fresh user and mount namespaces and the UID map, checked its retained
O_PATH target FD, and only then sent the child its explicit gate.

The invocation was `ERL_FLAGS='+S 2:2' elixir
/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_supervisor.exs`.
Its supervisor and child output were captured as one merged stdout/stderr log,
`tmpfs-umount-run.log` (SHA-256
`635adc2ebebd1bb9678fb4933b3c71528cc906e6e213bc384eafbb72d05425e3`). It
exited 0. The retained O_PATH mount-root FD path returned `EBUSY` (errno 16)
for a non-lazy `umount2`; after the FD closed, non-lazy cleanup of the exact
private path succeeded. The supervisor reported removal of the original target
directory. A subsequent read-only check in Serenity's host namespace found the
exact target pathname absent and no host mount entry naming it.

Linux documents `umount2` as pathname-based and lazy detach as a delayed
release. The observation applies only to this running kernel, temporary mount,
and supervised namespace. It does not establish safe Btrfs unmount, absence of
mounts in other namespaces, or a crash-safe device recovery procedure.
Sources: [umount(2)](https://man7.org/linux/man-pages/man2/umount.2.html),
[Linux 7.2.11 mount implementation](https://raw.githubusercontent.com/gregkh/linux/v7.2.11/fs/namespace.c),
[fsmount(2)](https://www.man7.org/linux/man-pages/man2/fsmount.2%40%40man-pages.html).
