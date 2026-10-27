# Device-mapper semantics reviewed for the proposed fixture

This is source review only; no device, mapper, mount or failure injection was executed. The fixture remains disabled. Official Linux [dm-linear documentation](https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/linear.html) describes the table's backing device as a path or major:minor and offset as sectors. The [dmsetup manual](https://man7.org/linux/man-pages/man8/dmsetup.8.html) documents 512-byte table sectors, `reload NAME --table TABLE` as a load to the inactive slot, `--inactive` table inspection and `resume` promoting an inactive table. It distinguishes `--nolockfs` from `--noflush`: suppressing filesystem synchronization does not establish that already mapped I/O was not flushed. It describes `--noflush` as target-dependent. None of this establishes actual timing on mounted Btrfs or safe interruption.

Linux 7.2.11 upstream `drivers/md/dm-target.c` was fetched from `https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable/+/refs/tags/v7.2.11/drivers/md/dm-target.c?format=TEXT`, base64-decoded without modifying the host. Its local SHA-256 was `8c9abd7eb9740099f5bf28620e94a0463f6e79de30c3f6c9a42d5b042b01efc5`, Git blob SHA-1 `3d294365e3ba74e36cae1df946b44f1ad74e1724`. The observed error-target mapper returns `DM_MAPIO_KILL` for both bio and request mapping. This is upstream source, not authenticated proof of the running Arch build, nor a guarantee that a particular file write receives a particular errno. Test the error sentinel and observe actual responses independently.

The kernel's [dm-flakey documentation](https://www.kernel.org/doc/html/latest/admin-guide/device-mapper/dm-flakey.html) says that `error_writes` fails writes during periodic down intervals while reads work, whereas a table-wide `error` target fails all I/O. The current prototype models the latter; switching to flakey for read-availability requires a separately reviewed target, timing/oracle design and revised exact table checks. Never equate elapsed time or target installation with proof of EIO.

`dmsetup --help`, `losetup --help` and source/pure mock tests ran without accessing a device. The real subprocess backend, absolute command ordering and output fields, Docker device cgroup rules, inactive-table behavior with no inactive table, Btrfs mount/suspend interaction, loop-node allocation, major/minor preselection, and safe cleanup still need validation on a fully isolated test graph. The program's main and native-owner live entry stay disabled until those facts and all approvals are resolved.

The 7.2.11 upstream `drivers/md/dm.c` source (local SHA-256 `42a3930036bbfdfd131cb2e75d45085a47f559b9abbedde2f5300d9a9a0f45db`, Git blob SHA-1 `eb9e32995b79c95a38816f0df8242e1c95ec15d2`) handles `DM_MAPIO_KILL` by completing the pending bio with `BLK_STS_IOERR`. This is a block-layer source observation, not proof that the actual native owner's particular syscall returned EIO.

Upstream 7.2.11 `drivers/block/loop.c` (local SHA-256 `05b749e12a0f839a109c71965148f2100b8bd469b73d4e627d8bd08da944d1de`, Git blob SHA-1 `1faecef330092b199dcc81066e9164b0f76b15de`) implements `LOOP_CTL_ADD` using a specific requested loop index and returns an existence error if occupied; `LOOP_CTL_REMOVE` refuses bound devices or devices with open disk openers. `LOOP_CTL_GET_FREE` may itself allocate a new loop, so it is not read-only. The code also notes that a nonzero `max_part` changes main-device minor numbering. The draft loop adapter checks `max_part=0` before and after add; opening loop-control can itself autoload a host-global module, and any failure after add leaves an uncertain created device requiring guarded recovery. None of this proves safe host-global ownership or absence of unrelated actors.

A later 7.2.11 source inspection identified a possible kernel-backed cleanup
check that does not assume unrelated file descriptors are absent. `dm.c`
`dm_lock_for_deletion` checks `dm_open_count` and refuses non-deferred removal
when nonzero. `loop.c` `loop_control_remove` hides the exact loop index under
`loop_ctl_mutex`, then checks `Lo_unbound` and `disk_openers == 0` under the
loop mutex before removing it. By contrast `loop_clr_fd` sets autoclear and
can return while another opener retains the device; detach/list absence is not
itself proof of index removal. A successful nondeferred exact mapper removal,
followed by successful `LOOP_CTL_REMOVE` on the exact independently recorded
newly-created loop index, may supply stronger evidence against foreign open
FDs. This is source reasoning, not yet independently reviewed, not proof of
running Arch binary parity, and not a verified live procedure. It still requires
trusted host administrator and Docker daemon noninterference, exact allocated
index provenance, maintained private mount/cgroup lifetime and fail-closed
handling of any interrupted/EBUSY operation.

The intended operational trust assumption is that Serenity's administrator,
root-equivalent actors and Docker daemon are trusted and do not intentionally
interfere with the uniquely owned fixture. This is not an assumption that
unrelated processes hold no device file descriptors. The fixture must prove
quiescence with host-visible cgroup/process evidence and use the kernel's
nondeferred removal/open-count checks. Any inability to prove the state remains
unknown and cannot authorize another actor's resource cleanup.

## Borrowed loop release and close observations

A later source trace suggests that an already-existing loop index can be
atomically configured against a held backing FD without calling GET_FREE, ADD or
REMOVE; the 7.2.11 loop configuration checks `Lo_unbound` under its internal
lock. This does not prove no other opener and does not authorize deleting an
existing index. `LOOP_CLR_FD` can merely mark autoclear; `GET_STATUS64` ENXIO
means the state is not `Lo_bound` and alone does not prove final backing fput.
The block layer decrements its opener count before invoking `lo_release`, and
`__loop_clr_fd` sets `Lo_unbound` before its backing `fput` call. Thus a zero
opener count, observed ENXIO or sysfs attribute absence is not by itself a
completion barrier.

Linux 7.2.11 `fs/open.c` calls `fput_close_sync` from the ordinary close syscall.
The 7.2 base `fs/file_table.c` implements that path synchronously when it gets
the last file-description reference. That does not establish 7.2.11 source or
running Arch build parity, nor does disk-openers==1 exclude duplicated,
inherited or in-flight references to one block file description. The draft
reports only `CloseAttempted`, not a backing-release receipt. Sources:
[7.2.11 block release](https://raw.githubusercontent.com/gregkh/linux/v7.2.11/block/bdev.c),
[7.2.11 close syscall](https://raw.githubusercontent.com/gregkh/linux/v7.2.11/fs/open.c),
[7.2 base fput implementation](https://raw.githubusercontent.com/torvalds/linux/v7.2/fs/file_table.c).

A harmless regular-file inotify experiment found that dup'ed FDs produce no
`IN_CLOSE_WRITE` until their shared description is finally closed, but a second
independently opened writer can emit the same inode event while the first stays
open. The parser rejects overflow/watch invalidation; coalescing and unrelated
write opens remain ambiguity. The 7.2 base `__fput` emits the close event before
other release work. Therefore this is not a complete final-release witness.
No loop device or Btrfs fixture was used in that experiment.
