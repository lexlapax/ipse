# Shell supervisor

Build with `native/build.sh` (Rust standard library only; Linux/macOS). Runner
can also build it on demand for trusted execution in a source checkout when
`rustc` is available; native mode requires a prebuilt helper outside the workspace. Package
`priv/ipse-runner` with releases/escripts, or set `IPSE_RUNNER_PATH`.

Arguments are `CWD TIMEOUT_MS COMMAND`. Stdout is a binary frame stream: one type
byte, a four-byte unsigned big-endian payload length, then that many payload
bytes. `O` carries stdout/stderr bytes (interleaving follows arrival order), `X`
carries JSON `{ "exit_code": integer, "timed_out": boolean }`, `E` carries a
known pre-dispatch setup refusal, and `U` carries an uncertain post-dispatch
failure. Output can split UTF-8 characters between frames. This shell `U` frame
is separate from the lock subprotocol's unlock acknowledgment below.

Runner returns `{:unknown, reason}` for a lost/timed-out supervisor, malformed or
incomplete frames/results, post-dispatch failure or an output-consumer exception.
A refusal following output/result evidence cannot downgrade uncertainty to a
known error. A valid final result retains the ordinary exit-code/timeout facts.
Pure validation, helper setup and explicit pre-dispatch refusals remain known
errors. Keep helper and Elixir Runner from the same installed build; an uncertain
effect must be inspected rather than replayed.

The caller keeps the helper's stdin pipe open. EOF kills the owned process group.
An explicit cancellation byte `C` also requests cleanup while retaining the Port
to observe helper exit. A private Port owner traps close-time exit races without
changing the caller's exit handling. Shell cleanup is confirmed only after a
normal helper exit after stack cleanup (status 0 or a returned error at status 1).
Forced stdio watchdog termination uses status 2; that, a timeout or abrupt helper
loss remains unconfirmed.
The helper starts `/bin/sh -c COMMAND` as a member of that fresh group and kills
it on timeout, parent-pipe EOF, failed output delivery, and shell exit.
The timeout includes the shell and its ordinary descendants. A deliberately
adversarial process can escape by creating a new session; this is **not a
sandbox**. Shell runs with the user's local filesystem and network access.
Provider credentials OPENAI_API_KEY, ANTHROPIC_API_KEY, and
IPSE_CHATGPT_ACCESS_TOKEN are removed from the shell environment. Other
inherited environment values remain available.

## Process-group identity and lifetime

`ipse-process-group.rs` owns one extra inert copy of the helper per shell/stdio
invocation or native macOS signature-check command. This anchor leads the group;
the actual command joins before sandbox setup/exec. The anchor's PID is kept
unreaped through command completion, output draining and final group cleanup.
It cannot be reused for an unrelated group while signals still reference it.
All signaling threads lock the shared slot through the signal; release kills
the anchored group, clears that slot, and reaps the anchor under the same mutex.
Late input/watchdog/owner events therefore find no signaling target after release.

The supervisor restores default child-status handling before launch, including
when its launcher ignored `SIGCHLD`; automatic reaping would invalidate the guard.
The anchor has a cleared environment, null output and a private stdin lease held
by the supervisor. A child joins the group before closing its inherited copy of
that lease, before any lengthy sandbox setup. Abrupt supervisor death closes the
lease and the anchor kills its own group, including itself. `--group-anchor` is
an internal role of this same helper, not an external executable dependency or
a configurable command. Failure to create the owner refuses command launch.
The OS helper's existing trust, sandbox and detached-descendant limits still apply.

This uses Rust's stable process/pipe facilities plus the existing narrow POSIX
boundary. `Child::try_wait` [reaps an exited Unix child](https://doc.rust-lang.org/std/process/struct.Child.html#method.try_wait),
so retaining only that child's numeric ID through later cleanup was insufficient.
A retained anchor avoids a new package, platform-specific `waitid` layouts or
reliance on unstable/Linux-only process-handle APIs. Regression probes establish
unreaped ownership after command exit, refused late signals and EOF-confirmed
ordinary-child exit after abrupt owner death. They do not force PID wraparound
or certify stronger descendant containment.

## Session locks

`ipse-runner --lock PATH` opens a persistent file with mode 0600 and takes a
nonblocking exclusive advisory `flock`. Linux and macOS reject symlink lock
files with `O_NOFOLLOW`. A successful lock emits an `L` frame. Sending any stdin
byte releases the lock and emits a `U` frame; stdin EOF also releases it.
Ownership follows the helper process, so an Elixir Port owner's death releases
the lock automatically. Lock files must **never be deleted**: preserving the
inode prevents concurrent owners from locking different files at the same path.

## Optional native macOS workspace sandbox

`ipse-runner --sandbox macos-workspace-v1 WORKER DATA CWD TIMEOUT_MS COMMAND`
uses an immutable, ad-hoc signed App Sandbox
worker generated and validated with the built-in `/usr/bin/codesign`. The worker
entitlements grant read/write access to the canonical workspace and stable
per-workspace data directory, read-only access to `/opt/homebrew` and
`/usr/local`, and the platform's normal baseline/container access. Network
entitlements are absent. The worker clears inherited environment values and
sets `HOME` and `TMPDIR` to a random temporary directory under shared workspace data.

The signed worker and its metadata are cached under
`IPSE_HOME/sandbox/macos` (default `~/.ipse/sandbox/macos`). The cache rejects
unsafe ownership, permissions, symlinks, and unexpected entries; it validates
the helper digest, manifest, signature, and exact entitlements, and retains at
most 32 generations. The workspace cannot overlap the active helper, application,
or cache. Run from an installed bundle outside the workspace; a source checkout
inside the selected workspace is refused.

The worker applies per-process ceilings: CPU time `ceil(timeout)+1` seconds,
64 MiB regular-file size, 256 open descriptors, and zero core-file size. There
is no aggregate memory or disk quota. Shell and ordinary descendants inherit
the App Sandbox filesystem and network limits. A descendant that calls
`setsid` or `setpgid` may survive cancellation or timeout and retain workspace
write access; process cleanup is best effort, not an OS sandbox boundary.
Sandbox data and the app container are shared by commands for the same
workspace, so this is not per-command data isolation.

`--uid`, `--macos-entitlements CWD DATA`, and `--codesign ARGS...` are internal
cache-preparation operations. `--macos-worker CWD TEMP TIMEOUT_MS COMMAND` is the
signed worker's execution role; calling this role directly on an unsigned binary
does not activate App Sandbox. The public native Runner path always validates
the signed app and its fixed policy first. Setup commands have bounded output
and a 10-second deadline. Initial-child exit ends output draining within 500 ms
even if a detached child retains a pipe.

Actual native macOS enforcement tests passed on macOS 26.7.2 arm64. See
[verification and limits](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#macos-native-backend-2026-10-15).

## Optional native Linux workspace sandbox

`ipse-runner --sandbox linux-workspace-v1 CWD TIMEOUT_MS COMMAND` selects a
fixed, fail-closed OS policy. The three-argument form above retains its trusted
behavior. The sandbox form never falls back to trusted execution. Unsupported
platforms/profiles, privileged callers, or failed kernel setup emit an `E` frame
without starting the requested shell. Policy is applied in the child after the
supervisor creates its process group and before `/bin/sh` executes.

The backend requires native little-endian Linux x86_64 or aarch64, enabled
Landlock ABI 6 or later (Linux 6.12+), permitted unprivileged user namespaces and
UID/GID mappings, mount/network/PID namespaces, and the `open_tree`, `move_mount`,
`mount_setattr`, `statx`, and `close_range` interfaces. Distribution security
policy can disable these facilities even on a recent kernel. Effective UID zero
and effective/permitted/ambient capabilities are rejected. `/proc` is needed by
the supervisor for bounded capability/thread inspection and namespace mapping;
it is absent from the child filesystem. Kernel setup is the capability probe:
a successful sandboxed harmless command establishes support for that invocation.

The child receives separate user, mount, network, and PID namespaces and a private
read-only filesystem root. Canonical `/usr`, `/bin`, `/lib`, and `/lib64` trees
are recursively mounted read-only when present. `/etc/ld.so.cache` and
`/etc/localtime` are optional exact read-only files. Exact devices are
`/dev/null` read/write and `/dev/zero`, `/dev/urandom`, `/dev/random` read-only.
The canonical workspace and a per-command mode-0700 data directory are writable;
the latter appears as private `/tmp` and at its original absolute path. The
read-only root is a sibling of that writable data, never inside it. Mount sources
are pinned and their inode/device identities checked after namespace creation;
replacing a source before spawn fails closed. Mounts are `nosuid`; directory
mounts are `nodev`. Capabilities and their bounding set are dropped before exec.

Bash descriptor paths use a fresh `subset=pid` procfs mounted at `/dev/.ipse-proc`
inside the private PID namespace, with `/dev/fd` and standard descriptor symlinks.
The host's procfs is never mounted. Regular procfs reads/enumeration receive no
Landlock grant. The original pre-exec child and namespace PID 1 are trusted
close-all-descriptors waiters; user code runs as an ordinary child. They forward
exit status and preserve the final command's spawn-error pipe until actual exec.
PID 1 reaps orphaned children; default command signals remain ordinary. Existing
supervisor cancellation kills the owned group and namespace. See
[descriptor design and evidence](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/sandbox.md#observed-bash-and-dependency-visibility-limits).

Landlock additionally confines file access
 and signal recipients to the new
sandbox domain and descendants. Seccomp rejects external socket creation,
connection, binding, listening and accepting; namespace/mount changes; tracing,
process-memory and pidfd access; SysV IPC; io_uring; privilege/module changes;
and process-group/session escape. Private connected AF_UNIX **stream** and
**sequence-packet** pairs are permitted for BEAM/Rust child-spawn internals;
datagram pairs remain denied. Cross-PID resource-limit changes,
scheduling/priority changes, page migration, and process-memory advice/release
are denied; `prlimit64` accepts only current-process PID zero. Private pairs
do not allow connecting to host socket names. Ordinary forks and threads remain
available; `clone3` reports `ENOSYS` for libc's legacy-clone fallback. Inherited
nonstandard descriptors close at exec. The child environment contains only
`PATH=/usr/bin:/bin`, `LANG=C.UTF-8`, and private `HOME`/`TMPDIR` values.

Resource ceilings are: no core dumps, CPU seconds `ceil(timeout)+1`, address
space 16 GiB, 256 open descriptors, and regular file size 64 MiB. NPROC is the
observed real-UID thread count plus 1024, clamped to the caller's existing hard
limit; exhausted hard limits or failed bounded `/proc` scans fail setup. These
are OS resource ceilings, not an aggregate per-command memory, disk, or process
quota; NPROC is shared by the real UID and its count is a snapshot. The existing
supervisor timeout and anchored group cleanup still bound command lifetime. The guard
kills the group before releasing the private-directory owner.

The helper rejects `/`, `/tmp`, overlap with protected system roots, the real
UID's home or its ancestors, and overlap with that home's `.ipse`, `.ssh`,
`.aws`, `.codex`, or a configured `IPSE_HOME`. The caller must still validate
the selected workspace before authorizing this mode: choosing a workspace
authorizes its contents, including unknown custom credential files or other
secrets within it. System tools outside the allowlist and builds requiring
network, host home configuration, `/proc`, or other system paths can fail.

Verified on the development Linux x86_64 host: actual namespace setup, shell
forks, Rust threads, network/signal/pidfd/SysV denials, writable workspace chmod,
absent outside sentinels, read-only system chmod, Elixir version startup and
Elixir compilation, and replaced-workspace rejection. Aarch64 constants were
reviewed against kernel headers; aarch64 execution and other hosts remain
unverified. Authoritative layouts: [Landlock](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/landlock.h),
[mount APIs](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/mount.h),
[statx](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/stat.h),
[x86_64 syscalls](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/syscalls/syscall_64.tbl),
and [aarch64/generic syscalls](https://github.com/torvalds/linux/blob/v6.12/include/uapi/asm-generic/unistd.h).

### Native enforcement tests

The default `mix test` excludes `:native_sandbox`, `:macos_sandbox` and
`:macos_filesystem` tests. Its untagged
capability test distinguishes successful explicit execution from fail-closed
unavailability; that test alone is not evidence that enforcement was exercised.
Run actual adversarial OS tests on a suitable Linux host with:

```sh
mix test test/linux_sandbox_test.exs --include native_sandbox
```

Included enforcement tests fail if the backend is unavailable. They compile a
small Rust standard-library probe using the existing build toolchain, establish
a successful host TCP connection as a positive control, then verify network,
signal, IPC and process-group restrictions through the sandbox. File tests use
fake credentials, and lifecycle tests synchronize on child output before timeout
or owner termination. Loopback access is required for Mix and the TCP fixture.

## Direct stdio server transport

`ipse-runner --stdio CWD TIMEOUT_MS EXECUTABLE ARGS...` directly executes a
configured local server, with no shell construction or interpretation of its
arguments. The application entry point is
`Ipse.Runner.open_stdio(executable, args, cwd, selected_env, timeout_ms, opts)`, which
returns an owned Port. It removes the inherited environment before starting the
helper and supplies only `PATH=/usr/bin:/bin` and `LANG=C.UTF-8` to that supervisor.
A private initial `L` frame delivers the selected environment to the final server;
the helper never loads selected `LD_PRELOAD`/`DYLD_*` values into itself. The native
CLI itself trusts its launcher's environment; applications must use the scrubbed
entry point. Credentials belong
in explicitly selected environment values, never executable arguments or logs.

For MCP, the config's per-server `sandbox` value independently chooses `off`
(the default) or `native`; the CLI shell `--sandbox` option does not set it.
`Ipse.Runner.open_stdio/6` resolves `native` to the fixed Linux or macOS
workspace profile and passes a bounded launch frame so selected environment
values go only to the final server process, not the supervisor. The server gets
`PATH=/usr/bin:/bin`, `LANG=C.UTF-8`, its selected environment, and a fresh
private `HOME`/`TMPDIR` in native mode. Linux native stdio tests verify
workspace writes, outside-workspace denial, network denial, and supervisor
protection. The macOS stdio route uses the signed worker and exact entitlements;
its four native stdio enforcement cases passed on macOS 14 arm64 CI. See
[P7 evidence](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p7-expanded-local-mcp-2026-10-15)
and the subsequent [local cleanup investigation](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#macos-stdio-cleanup-load-2026-10-15).
Native launch or capability failures fail closed and do not retry in trusted
mode. See [the sandbox policy](../docs/developer/sandbox.md) for the common
profiles and their limits.

The helper requires an initial private `L` frame: a big-endian u32 payload size,
then a big-endian u32 entry count and length-prefixed UTF-8 key/value strings.
The payload is at most 134,144 bytes and 130 unique valid environment names;
missing/invalid input fails before launch, with a five-second read deadline.
MCP configuration applies the stricter 16-variable bounds above this helper API.
Selected values are installed only in the final executable environment. On Mac,
the unsigned supervisor writes a bounded length-prefixed environment to the signed
worker's private stdin before relaying server input. The worker reads exactly
that prefix using an unbuffered descriptor and preserves stdin across exec. No
environment file is staged in the shared writable sandbox data. The existing
watchdog and owner lease cover blocked prefix writes and reads. This does not
erase retained data from older generations or establish per-command isolation.
`open_stdio` uses an empty nonblocking write probe to wait at most five seconds
for the initial launch frame to flush, handling owned cancellation while waiting.
It does not claim server readiness or sandbox activation; subsequent writes keep
their ordinary bounded backpressure behavior.

The remaining input is OS transport framing, not MCP framing: `I` followed by an
unsigned big-endian four-byte length and that many raw server bytes forwards
stdin; `C` followed by a zero length cancels the child. Input payloads are at
most one MiB. Use `Ipse.Runner.send_stdio(port, bytes)` to construct input frames
without suspending on a busy Port. `Ipse.Runner.close_stdio(port)` sends cancel,
drains output, and waits at most two seconds for supervisor exit before closing
the Port. It returns `:ok` only after an exit-status confirmation; otherwise it
returns a fixed cleanup-unconfirmed error. Do not reuse a server slot as if
cleanup succeeded after an unconfirmed result. Abrupt owner death still closes
the pipe and independently kills the ordinary process group.

Output uses the existing one-byte kind and unsigned big-endian four-byte length
framing: `O` is server stdout, `S` is server stderr, `X` contains
`{"exit_code": integer, "timed_out": boolean}`, and `E` contains a fixed transport
failure. Output chunks are at most 8192 bytes, and the combined output queue is
32 chunks. Stdout and stderr are separate streams; a chunk need not contain a
complete UTF-8 character or application message. Elixir owns MCP/JSON-RPC parsing;
the native helper interprets neither server messages nor tool schemas.

The lifetime timeout accepts 1–86400000 milliseconds. Owner pipe EOF, timeout,
failed output delivery, input overflow, and initial server exit kill its ordinary
process group. An independent watchdog enforces the deadline even when output
is blocked and allows at most one additional second before forcing supervisor
exit. After server exit, output drains for at most 500 milliseconds. Idle
five-millisecond polls repeat group SIGKILL to catch ordinary children created
during the first signal's delivery, within the original drain deadline or until
pipe disconnect. The unreaped anchor can keep the group present after ordinary
children have exited, so a successful signal does not establish remaining live work.
Retained pipes that exceed the original bound still produce a transport failure
without an `X` completion; this includes detached pipe holders. Input relay buffering
is bounded to one MiB plus the current chunks and OS pipe buffers. Overload fails
closed instead of blocking the owner-death reader. An oversized in-flight Port
write may surface as a linked `:epipe` exit before the final error frame, so the
transport owner must handle Port exits and treat them as failed exchanges.

This mode runs a trusted configured server with the user's OS permissions. Its
process-group cleanup is best effort for ordinary descendants; a deliberately
detached process can escape. It is separate from the native workspace sandbox
and makes no filesystem or network isolation claim. A transport failure never
proves that a server operation had no effects and must not automatically replay
an interrupted request.
