# Partial-write diagnostic on Linux 7.2.11

Recorded 2026-10-27. This is one bounded diagnostic, not qualification of a
kernel, filesystem, native transaction, or protected write path. It used no Ipse
native helper and did not change the admission profile. The test directories
were newly created, owner-only, and removed after the test, one on tmpfs and
one on the project's Btrfs filesystem; it touched only its own synthetic files.

The standalone [Rust source](partial-probe.rs), compiled with Rust 1.99.1
using `rustc --edition=2024 -D warnings -O`, ran on `7.2.11-arch1-1`. It
launched one child for each case, retained a read-only FD in the parent, and
sampled length and `st_blocks * 512` before killing that child, immediately
after it exited, at approximately 10, 110 and 1,110 ms, and after the parent's
`fsync`. Each child had completed or failed its `write_all` call and was
blocked on stdin before it was killed. Thus this does **not** test a kill during
a write system call. All files remained named during observation, then were
closed and removed. The parent-held FD is a diagnostic observation device, not
a reconstruction of Ipse's actual-owner protocol.

There were six successful dense writes: deterministic pseudorandom data at 1,
4,095, 6,144, 65,537 and 1,048,577 bytes, and zeros at 1,048,577 bytes. A
seventh attempted 65,537 random bytes with `RLIMIT_FSIZE` set to 8,192 bytes and
`SIGXFSZ` ignored. It returned Linux `EFBIG` after an 8,192-byte partial file.
The limitation-induced error is not a Btrfs writeback or block-device error.
Each sample's charged count remained unchanged at every observation; the
partial file measured 8,192 bytes and 8,192 charged bytes. All seven subsequent
`fsync` calls succeeded on each filesystem. The complete [tmpfs output](partial-tmpfs.tsv)
and [Btrfs output](partial-btrfs.tsv) are retained; they are byte-identical.

The tested tmpfs mount reported `huge=advise`; the project mount reported
`compress=zstd:3`. The source SHA-256 is
`5d8142ffac370286aa8aa8b03e1608af1d08c863c8795a941690772728802109`;
each TSV SHA-256 is
`feae273932e0db4e6d003a3a7d23c3cfa7959317e1776ebed04860a186ebbfeb`.
The relative sampling intervals are nominal sleeps, not measured deadlines.

This does not establish dirty-page state, delayed writeback or compression
state, in-flight syscall interruption, concurrency, unlinked-file behavior,
actual transaction-owner fencing, filesystem recovery, `ENOSPC`, or I/O
failure behavior. Those properties require their own tests and source argument;
an isolated Btrfs fault-injection environment was not available. Source review
also observes error cleanup clearing a delayed-allocation charge before freeing
a reserved extent, but Ipse's declared budget is named-file `st_blocks`, not
the filesystem-wide physical allocator reservation. The ordering alone is not
evidence that the declared metric was violated; possible later changes to the
named-file count and all recovery paths remain open.
