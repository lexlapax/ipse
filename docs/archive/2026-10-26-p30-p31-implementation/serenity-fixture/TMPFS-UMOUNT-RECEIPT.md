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

A second independently reviewed variant retained an O_PATH descriptor to the
`/tmp` parent and, after closing the busy mount-root FD, called non-lazy
`umount2` via `/proc/self/fd/<parent>/<exact nonce leaf>`. It compiled from
`tmpfs_umount_parentfd_probe.rs` (SHA-256
`7942faa2217240598ce4dbd7c139b81ad8e43389a535ced2dd960d93c82abb85`) and
`tmpfs_umount_parentfd_supervisor.exs` (SHA-256
`6ffdfcce20e46a02e350198178a6866ba93a1bce19ac14cfe760c2f5130ff693`); the
binary SHA-256 was
`22d2b77223c4b87e5f687731c6a14ff205294e1e13e3f0776f4f0e2612260a76`.
`make_parentfd_probe.exs` records the source-only transformation. The command
was `ERL_FLAGS='+S 2:2' elixir
/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_parentfd_supervisor.exs`.
The merged stdout/stderr is `tmpfs-parentfd-run.log` (SHA-256
`18d1774f0af564f631e4ca099673766bf39ea8e274cb67bb7bd8aadb4525effc`). The
supervisor exited 0: mount-root FD unmount returned EBUSY, the retained-parent
path unmount succeeded, and the original temporary directory was removed. A
separate read-only check found the exact target absent and no matching host
mount. No block devices were used.

The parent FD anchors the parent directory, but does not prevent the leaf or
mount from being replaced between verification and `umount2`. The reviewer
explicitly retained that race and the namespace/cleanup limitations. This
single tmpfs result does not qualify the Btrfs fault fixture.

A third independently reviewed variant retained an O_PATH descriptor to `/`,
read its fdinfo mount ID and verified that the private tmpfs mount's observed
parent chain reached it. It used `tmpfs_umount_rootfd_probe.rs` (SHA-256
`b2d08d816c18cbc31b7dad44a0b7e506b4754720ca09641da115e8b1e978c40b`),
`tmpfs_umount_rootfd_supervisor.exs` (SHA-256
`ae8f151a20e90211d8ed9e1e1043ce1bb4acba5184f46e7b5e71d487526efc4d`) and a
binary with SHA-256
`6cc29a1268e7e1f80138793a9b0bfb7414987f184649f19f186507850cd33fb5`.
`make_rootfd_probe.exs` records the source-only transformation. The command
was `ERL_FLAGS='+S 2:2' elixir
/tmp/ipse-serenity-qualification-plan/fixture/tmpfs_umount_rootfd_supervisor.exs`.
The merged log `tmpfs-rootfd-run.log` (SHA-256
`0bb5d36b9fd07c259d0e70e866bee6c70afefc0e51e0626c68f3ddbbe4bce4e1`)
records exit 0, process-root mount ID 383 in temporary mount 460's parent
chain, EBUSY for retained mount-root unmount, successful retained-parent path
cleanup and removal of the original directory. A separate read-only check
found the exact path absent and no matching host mount entry.

This identifies the *process-visible* root in this controlled no-chroot test;
it does not independently prove the true root of an arbitrary mount namespace
after chroot or pivot, propagation state, global absence, or Btrfs cleanup.
The experimental Btrfs guard requires a separately attested namespace-root
boundary and remains disabled.
