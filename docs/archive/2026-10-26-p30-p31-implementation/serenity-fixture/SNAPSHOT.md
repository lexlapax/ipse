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
