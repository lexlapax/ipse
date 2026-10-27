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
