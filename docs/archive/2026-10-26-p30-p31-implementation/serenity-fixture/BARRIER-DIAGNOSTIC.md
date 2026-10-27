# Private source-derived stage boundary diagnostic

This is an experimental diagnostic, not the production binary or evidence that
Linux 7.2.11 is qualified. No host block device or mapper was used. Both helper
sources add a private test-only 7.2.11 kernel acceptance and a final-chunk
socket handshake for one synthetic pending name; all other native .rs copies
were byte-for-byte identical to the checkout when built. The helper compiled
with `rustc --edition=2021 -D warnings -C opt-level=z -C strip=symbols -C panic=abort`.

The /work/control variant helper hash is
`4def0d0a3e3bffbdd705d73beb91218154c8bbe9f8f708632a1b2065c245a596`;
transaction source hash `a8c75103d8ab653aed8ed320cc2bfb3ca7217f41d30958acaebadd9a2c971987`,
profile source hash `f73050d9705217e728bb2f8a625acff8610b81c4aadd0faafeec6ee0d174be7c`.
The /tmp socket variant helper hash is
`2876c31518bb279293dda3c2842dd9c726931cc355ddcaabb6f5562f28c4b7d0`.
The latter was wired to an independently compiled private Mix graph and the
actual `Resources.file_effect` and `Runner.Transaction` controller.

On Serenity tmpfs, the benign test received R, confirmed stage had not returned,
sent G, received W/0 then S/0, observed stage/check/release success and a 65536
byte file. Disconnecting at R returned `{:unknown, :transaction_lost}` and
invalidated the capability. Killing the supervised caller at R closed this
helper's socket. Scripts are `barrier_benign_test.exs`,
`barrier_disconnect_test.exs`, `barrier_owner_loss_test.exs`. They use fixed
private root names and require new paths to repeat; the named preexisting
directories must never be recursively deleted blindly.

W and S report the instrumented Rust `write_all` and `sync_all` return errno;
W does not imply a single kernel write syscall or prior page state. Successful
socket closure does not prove full process/cgroup cleanup. The test has not
shown EIO, mounted Btrfs behavior, or production source behavior. Host device
lifecycle and cleanup need independent review and proof before any device use.
The 10 second barrier timeout is a bound, not authorization to recover an
unknown device state. The fixed socket path needs private-directory, peer, and
lifetime ownership verified in a future container design.

Independent audit correction: the three tests above do not bind a
`Resources.start/attach` scope and therefore do not establish Session-owned
resource-scope registration or a cleanup receipt. They exercise a real
Transaction controller reached inside `Resources.file_effect`. The owner-loss
socket observation alone does not prove controller death, lock release, or
pending-file cleanup. No observation proves earlier bytes remained dirty or
kernel writeback was in flight. A complete five-byte W or S frame is required
before attributing its result to the private helper operation; a broken report
is only generic unknown IO.

A fourth separate `barrier_scope_test.exs` started and bound a resource scope in
an owner process, then reached the actual Transaction controller through
`file_effect`. At R, `Resources.finish(scope)` returned `:ok`, the monitored
controller went DOWN, its socket closed, stage returned unknown, the pending
file retained its observed device/inode/size, and a fresh lock could be acquired
and released. This is a scoped cancellation test, not a Session-process test,
not proof of native OS PID death or all cgroup/device cleanup. The script still
requires independent review and uses a fixed temporary path.
Independent review requested a nonempty partial-file assertion; the test was
updated to require `0 < size < 65536` and repeated successfully using
`barrier_scope_repeat_test.exs` at a new path. The first observed file size was
49152. The scoped test does not attach to a Session-owned task with a retained
Session lock.

The disabled `barrier_orchestration.rs` and `barrier_framing.rs` integrate
synthetic barrier events with the existing mock fault/restore/teardown state
machine. The combined controller test suite passed 38 tests. These are mocks,
not a live harness. The parser rejects premature reports, wrong order, truncated
frames and extra data; negative/no-errno reports remain unknown. Review found
that effects require durable pre-effect intent, so setup, stage, fault, release,
restore and cleanup have explicit pending phases and tests that a failed intent
blocks the corresponding operation. A pending record means effect unknown after
crash. Correlation with the exact native peer and pending inode, cgroup cleanup,
immutable tool lifetime, and an independently supervised exact-resource crash
recovery with operator-visible ledger are unimplemented. No host-device action
is authorized by these mock results.

Peer-binding work: `peer_listener.rs` is a temporary-file-only executable; it
accepts the private socket peer credentials, pins the peer and reported Port OS
parent with pidfds, compares proc start-times and process parent, checks the
helper executable's dev/inode, holds a no-follow pending file under a no-follow
root directory FD, and compares the peer's open file and mount ID. It refuses
mismatched parent PID. An Elixir driver observed the live scope owner and lock
ticket, controller and Port PID just before authorizing G. A separate agent
independently built and reran the benign diagnostic successfully. These are
same-namespace observations, not atomic binding across G or proof of immutable
privileged tool closure, cgroup or device cleanup. The listener and scripts
remain experimental; they are not wired to device effects.

`recovery_ledger.rs` is a bounded intent-record prototype, not recovery: a
fresh nonce directory is created relative to a held parent FD and parent is
synced; ledger creation uses openat(O_EXCL|O_NOFOLLOW) and syncs file and
containing directory. It rechecks named/held identity before each ordered record
and rejects incomplete, mismatched-nonce or out-of-order parsing. Its four tests
passed within a newly created private workspace Btrfs directory and that test
directory was removed. The workspace and eventual loop backing share the host
physical Btrfs device, although the diagnostic dm error table targets the loop
mapper, not the workspace path. No actual reboot or storage-power-failure test
has occurred, and exact per-resource identity records, independently supervised
crash recovery, and safe mapper/loop teardown are unimplemented. The full
review-only controller test suite has 43 passing tests; main remains disabled.
