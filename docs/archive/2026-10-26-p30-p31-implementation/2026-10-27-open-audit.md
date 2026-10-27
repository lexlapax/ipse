# Open independent review findings, 2026-10-27

Historical working record; the [plan](../../plan.md) owns current status. These
reviews are partial and do not constitute the requested final adversarial audit.
They inspected the uncommitted SDK-v3 and egress prototypes alongside the
committed source, without executing native publication tests.

## Managed first publication

The first-root witness records a verified historical publication, not continued
root freshness. The reviewed contract activates Identity after child locks are
released. Ordinary authorized SDK writes acquire the outer Identity lock, so
the review did not establish an exposed concurrent-writer bypass. Direct trusted
Core calls to Collection have different authority and are not evidence that a
worker can bypass that lock. A deterministic competing-Session test must still
pause after postproof, verify that a second authorized writer waits for Identity
activation, and verify the historical first-root binding after a later write.

The postproof opens the format MAC and compares changed records' operation,
revision and value hashes to the captured host normalizer output. It does not
independently reopen each changed-page MAC. The developer manual was corrected
to make that distinction. Corruption and substitution of changed pages, native
owner loss after postproof and during activation, and failure of final Consent
settlement remain to be exercised at those exact boundaries.

## Inference egress prototype

The uncommitted gate executes before `Finch.stream_while`, which can subsequently
wait for connection checkout, DNS, connection, TLS or proxy setup. A policy or
source change during that wait can therefore precede sending request bytes. The
existing local transport tests establish only their named direct controls, not a
final current-authority barrier. The gate also reports a wire-body digest to its
verifier without independently binding it to a host-derived expected body, and
the existing Session source snapshot is not an authoritative managed-root read.
Registered and unregistered paths both need coverage. No Session integration or
claim of protected inference egress follows from the prototype.

A subsequent local diagnostic reproduced the connection-wait gap with a
loopback TLS server: the gate accepted while a synthetic policy was enabled,
the server paused before its TLS handshake, the test disabled that policy, and
the server then received the previously admitted fixture body. The focused
private-graph run reported **7 passed**, including this deliberate reproduction
of the defect, using seed 20261225; its [output](kernel-7.2.11/egress-gate-tests.log)
does not establish a security pass. It used Elixir 1.20.4/OTP 29 and the
uncommitted prototype: gate source SHA-256
`8f3db327dadc7fc9fdf4109c3048db89f3cd95d14a23bb5ce6e28bcf6a7a0d1d`,
transport source `3e408c926489e059dd6e5e9f754be63a18a738c63506c997620d4ff14faca38f`,
and test source `8197559debc553d788a8dd81254537c7effe2bf62946a61f3c41cccaa7053e1c`.
The output SHA-256 is
`1577310c04ec059519dea5533b82cf43fd117ac1f20ee449d5e3fe0386eff01b`.

One possible maintained seam is Mint's public connect followed by a final check
and request, but direct Mint use would need a declared dependency, bounded
response and lifetime handling, equivalent TLS and proxy behavior, and failure,
cancellation and connection-wait tests. Connection setup itself can expose
destination metadata. A concurrent-revocation linearization rule and current
root validation are required regardless of transport; a narrow timing interval
alone is not a proof. This is a design lead, not an approved or implemented fix.

## Linux 7.2.11 qualification

Independent static review compared the downloaded upstream v7.2.10 and v7.2.11
`fs/btrfs/file.c`, `fs/btrfs/extent_io.c`, `fs/btrfs/ordered-data.c`,
`mm/shmem.c`, `mm/filemap.c`, and `fs/stat.c` copies and found each pair
byte-identical. The reviewed Btrfs successful buffered-write path moves new
delayed-allocation accounting to inode accounting under the same inode lock used
by `getattr`; the reviewed tmpfs non-VMA buffered-write path under the tested
mount and global policy does not select huge orders. These observations do not
authenticate the running Arch kernel or establish the complete allocation bound.

In particular, Btrfs error cleanup can clear `EXTENT_DELALLOC_NEW` without the
successful transfer to inode bytes. The timing of page and extent reclamation
relative to that clear needs a complete trace and isolated writeback and
allocation failure tests. This is an unresolved proof gap, not a demonstrated
defect. The earlier successful-write kill probe cannot establish that property.
The user authorized continuing qualification on 7.2.11; the profile remains
unchanged and fail-closed. A private user/mount namespace can mount a disposable
tmpfs here, but `/dev/loop-control` and `/dev/mapper/control` were absent in the
checked environment. No Btrfs fault injection was attempted on the user's
filesystem. See the [recovery record](kernel-profile-recovery.md) for the
source and preliminary probe provenance. A later
[partial-write diagnostic](kernel-7.2.11/partial-probe.md) observed stable counts
after a completed or size-limit-failed write, but did not inject Btrfs I/O
failure or interrupt a write system call.
