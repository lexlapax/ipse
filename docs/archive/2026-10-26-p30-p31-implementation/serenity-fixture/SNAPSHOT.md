# Serenity disposable fixture: incomplete research snapshot

Historical evidence captured 2026-10-27. This is an incomplete, experimental
fixture retained for independent review and recovery of development work. It is
not an operator procedure, a safe live backend, or evidence that Linux 7.2.11
is qualified. The controller entry point remains disabled. Do not enable the
backend or execute host-device operations without independently reviewing the
remaining identity, containment, crash recovery, and cleanup gaps described in
`BARRIER-DIAGNOSTIC.md` and `CGROUP-SLICE-PROTOCOL.md`.

The source files and tests here are a snapshot; several use private absolute
`/tmp` paths from the original investigation and are not portable run commands.
`SHA256SUMS` records this snapshot's file hashes. It excludes binaries, archived
upstream kernel sources, and the instrumented private helper itself; the helper
generator and recorded helper hashes are retained. The workspace ledger tests
used a temporary owner-only directory and removed it afterward. No loop device,
device-mapper fault, or Btrfs mount was created by these artifacts.

This historical snapshot supplements the current milestone status in
[the plan](../../../plan.md) and the implementation records in its parent
archive. Later changes may supersede the snapshot.

A later snapshot addition includes a read-only pidfd observer prototype. A
separately running synthetic observer reported an interrupted private test's
pending ledger entry as unknown. The observer does not recover devices and has
not received independent review. The current controller mock/synthetic suite
passed 45 tests; no live-device test is implied.

The review-only controller now also models recovery from an exactly recorded
active error or linear table, after verified quiescence and a separate recovery
budget. Its real backend refuses these prerequisites: the live quiescence
proof, recovery budget and exact-resource guardian are not implemented. Two
additional mock tests pass; the current total is 47.

A subsequent source review added a final loop-index removal prototype and mock
negative tests. The kernel may reject nondeferred mapper removal on openers and
loop-index removal on openers or a bound backing file, but this observation has
not been validated against the running Arch kernel. The real backend refuses to
claim the loop index belongs to this fixture; it cannot safely reach removal.
The private suite now has 49 passing tests, none involving a host block device.

The latest draft includes an exclusive, fsynced loop-identity record tied to
the run nonce, tested using synthetic values. It is not wired to live creation,
does not prove post-crash ownership or authorize removal, and requires review.
The private test suite passed 50 tests at this snapshot.

Newer private checkpoint: the draft records the boot ID and retained sysfs
identity with loop provenance, and includes a read-only retained cgroup-parent
witness. Neither is independently reviewed or exercised on a created loop,
mapper, cgroup slice or device. The cgroup draft does not establish workload
migration restrictions, privilege drop, namespace equivalence or complete
cleanup. The current private controller suite passed 53 tests. All live entry
points and real backend quiescence checks remain disabled.

Latest checkpoint adds a two-step diagnostic socket gate: after verifying the
private helper and pending file, the listener waits for explicit release and
rechecks identities, then parses complete W/S results. Temporary-file success
and malformed-release refusal ran; no injected error or device test ran. The
review-only orchestration also rechecks a bounded pause before fault and release.
These components are not yet a reviewed privileged live backend. The independent
cgroup migration and crash recovery requirements remain open; 54 private tests
passed at this checkpoint.

The next checkpoint includes an experimental bounded child-process adapter for
that gate, with a fresh supervised temporary-file integration run and report
parser tests. The adapter and listener remain tied to private `/tmp` paths;
they cannot safely orchestrate the `/work` device fixture. They do not prove
privileged process-tree or device cleanup. The private suite passed 55 tests.

A subsequent private checkpoint includes a generated container-path listener
source. It compiled and refused an invalid temporary-path invocation, but has
not run in Docker or against a device. Its generator modifies a source-derived
diagnostic; neither source nor binary qualifies the production helper. The
private adapter also rejected a mismatched Port PID and reported the staged
operation unknown. Runtime pinning, privileged container isolation and recovery
remain open.

A later private checkpoint adds disabled container-path channel/stage sources
and a read-only Btrfs mount probe. Serenity's existing workspace demonstrated
that a Btrfs mount's anonymous device number need not equal its backing block
device. The draft now relates a held mount ID and Btrfs filesystem UUID to its
single underlying device through sysfs; the read-only workspace probe matched
the actual underlying device. This logic is unreviewed and has not been tested
on the disposable mapper. The private suite passed 56 tests. No device or mount
creation was performed.

Latest draft anchors Btrfs sysfs traversal using held directory descriptors,
bounds mountinfo while reading, and records the per-run FSID, mount ID and
mount namespace with mapper identity. A generic, disabled gated switch composes
peer verification with the existing mapper transition in mock tests. The real
backend now refuses path-based unmount because the held-mount-to-unmount and
namespace-wide absence guarantees are not established. Read-only workspace
probing still succeeds; 59 private tests passed. Independent re-review and the
live fixture remain pending.

The separately reviewed user/mount-namespace tmpfs diagnostic ran twice without
block devices. Its retained mount-root FD non-lazy unmount returned EBUSY, and
non-lazy cleanup succeeded after closing the FD. See
[TMPFS-UMOUNT-RECEIPT.md](TMPFS-UMOUNT-RECEIPT.md) and the captured merged log;
this is not Btrfs qualification.

A separately reviewed follow-up tested non-lazy cleanup via a retained parent
FD and exact leaf; it succeeded after the busy mount-root FD was closed. Its
receipt, exact merged log and source are preserved. The leaf check-to-use race
remains, and no Btrfs or block device test was performed.

A disabled namespace-local Btrfs unmount prototype now checks a retained parent
FD, recorded FSID/mount ID/mapper/namespace and rejects visible aliases,
nested mounts and shared or slave propagation before non-lazy unmount. There is
no live quiescence-token constructor; namespace exclusion, escaped references,
leaf replacement and global cleanup remain unresolved. It has not been run.
The private suite passed 60 tests, including its mountinfo parser controls.

A reviewed third tmpfs diagnostic observed the retained process-root FD's mount
ID in the temporary mount's parent chain and successfully cleaned up afterward;
its receipt, merged output and sources are preserved. This does not prove an
arbitrary process root is the namespace root. The disabled Btrfs draft now
checks full visible mount-ID ancestry, stacked-root propagation and a separately
attested boundary; its private suite passed 62 tests. No Btrfs device was used.

Following independent review, the disabled unmount draft now holds a typed root
topology object with namespace and root FDs but no live constructor, and its
local unmount receipt explicitly does not claim global mount or device cleanup.
An independently verified namespace-root boundary and quiescence still do not
exist. This draft has not performed a Btrfs unmount; its 62 private tests pass.

A disabled borrowed-loop draft retains a pre-existing index and uses an atomic
LOOP_CONFIGURE attempt; it never removes the index. The host had no loop index
and its loop module was unloaded when inventoried, so none was opened or loaded.
The proposed clear/rundown/close sequence is source investigation only and
returns `CloseAttempted`, not a detach receipt. A separate harmless inotify
regular-file test showed that an unrelated writer can produce an indistinguishable
close event; it is not a backing-release oracle. The private controller and
inotify suites passed 63 and 2 tests respectively. Independent review of the
exact running-kernel release semantics and actual device behavior remains open.

A captured harmless regular-file inotify test and kernel-build-ID note were
added. The running kernel and installed vmlinux reported matching build IDs;
this alone does not establish upstream source parity. The event identifies an
inode, can also result from another writable description, and does not by itself
prove that final file teardown completed. No loop device was opened.

The borrowed-loop draft gained a harmless `/dev/null` negative control:
ENOTTY is refused rather than interpreted as an unbound loop. Its private
controller suite passed 64 tests. No loop or block device was opened.

The latest private borrowed-loop draft adds a local FD-alias/CLOEXEC refusal and
records an exact upstream 7.2.11 close/fput source trace. Its 65 tests passed
serially. The local scan does not exclude foreign or in-flight references, and
the single-owner protocol still lacks a reviewed live implementation and
cleanup proof. No loop device was opened.

An unreviewed Linux/x86-64 seccomp experiment ran only in a synthetic child:
it observed EPERM for dup, F_DUPFD, restore-dumpability, socket, clone3 and
unshare while F_GETFD remained usable. Its source and merged test output are
preserved. It is not wired to a fixture, does not prove all external or kernel
references absent, and must not be treated as a security or cleanup boundary.

The unreviewed single-owner filter draft subsequently added file-backed mmap,
legacy AIO, epoll control and new mount API restrictions. The synthetic child
refused file-backed mmap with EPERM and could still create an anonymous mapping.
Preexisting kernel registrations, other processes, same-UID visibility after
changing dumpability, and complete reference cleanup remain unproved.

A later disabled single-process owner draft checks the inherited FD inventory
before its unreviewed filter and contains bounded command handling plus exact
backing inode checks. Its standalone synthetic tests passed, including an
extra-FD refusal; the disabled executable exited 2 without opening a device.
It has no accepted guardian, authenticated launch, cgroup or final-release
proof and must not be enabled from this historical snapshot.

The latest harmless filter test additionally verified that a loop-status ioctl
reached `/dev/null` and returned ENOTTY after the filter, rather than being
blocked by seccomp. This is syscall-routing evidence only. The standalone owner
entry remains disabled and has not opened a loop device.
