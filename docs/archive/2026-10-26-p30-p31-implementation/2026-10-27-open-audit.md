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
source and preliminary probe provenance.
