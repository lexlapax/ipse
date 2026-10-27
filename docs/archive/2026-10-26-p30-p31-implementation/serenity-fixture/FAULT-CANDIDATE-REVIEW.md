# Serenity bounded fault candidate, 2026-10-27

This is a pre-run review snapshot, not an operator procedure or a kernel qualification. The later attempt is recorded separately in [the actual outcome](FAULT-ACTUAL-OUTCOME.md).
The [frozen source graph](fault-candidate/SOURCE-SHA256SUMS) hashes to
`65ce6192d2f0f99ee4be21df9a5a3b3d90aaa93567b01d307d84ff8334b95cfb`;
the [bundle manifest](fault-candidate/BUNDLE-SHA256SUMS) hashes to
`f42800edac63b05a9e23997fec8ec1c9a9ec597241b4948074caf9fb217e2031`.
The [candidate harness](fault-candidate/bounded_fault_harness.sh) hashes to
`6ae100f31b3ad8b3dd67ba82f4875244d0e7aa716c8f7d9f19b9d62753bfd612`.
The candidate's binaries are not archived here.

Under the trusted-host/daemon assumption, the invocation targets only recorded
loop index `7:4095`, a newly created mapper at `252:4095` with nonce-derived
name and UUID, and a unique 512 MiB synthetic backing file on `/tmp`. It creates
its loop node only in a checked private container `/dev`. It records pending
operations in the existing persistent ledger before device effects; Docker is
networkless, readonly-root, non-privileged, bounded to the specified device
rules, CPU, memory and process limits. It retains the exact container, stage,
ledger and any uncertain device state; the kernel may nevertheless change the
binding on process death through AUTOCLEAR. Never infer cleanup from a timeout,
missing output, Docker exit, loop status or signal alone.

The coordinating agent authorized and requested independent review before any
backing or mapper effect. The reviewer reported matching manifests and four
reproduced source-executable hashes, 91 passing disabled tests, and no additional
demonstrated wrong-device path under the stated assumption. The review did not
certify cleanup, guardian survival or kernel qualification. A unique Docker
name/label is persisted before create for recovery after an interrupted CLI
response. A bounded PID-1 wrapper was checked in one separate no-device test;
its five-second window cannot guarantee a receipt if PID 1 or the host dies or
filesystem sync stalls.

The backend budget is 120 seconds. The guardian receives the remaining backend
budget plus 35 seconds, the owner's post-configure wait is 160 seconds, and the
outer Docker attach is limited to 180 seconds. Fault preparation requires at
least 45 seconds remaining and GO at least 30 seconds. A source-derived owner
pipe test accepted R after 121.00 seconds without any device, and independent
no-device stage, guardian and wrapper tests passed. Outer timeout can still
occur before or during cleanup: retain exact resources and classify the state
unknown. No actual fault operation had run when this review snapshot was prepared.

A first harness attempt exited 2 before staging or device effects because
udev had created host `/dev/loop4095`. The revised harness checks that exact
host node (block `7:fff`, device:inode `7:1539`) without opening or removing
it; the candidate still creates its own separately checked private node. The
revised version was independently reviewed, with the original concurrency and
unknown-state caveats.
