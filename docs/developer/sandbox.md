# Native shell sandbox

`--sandbox off` is the default trusted local mode. `--sandbox native` explicitly
requests the fixed native OS backend. Approval and sandboxing are independent:
`--yes` changes approval policy, never disables sandbox enforcement. Failure to
create the requested sandbox stops that shell call; it never retries unsandboxed.
Sessions retain the requested mode in metadata and reject a different mode on
resume. Provider inference runs in Elixir outside the shell sandbox.

Local MCP servers can separately request these same fixed profiles using their
explicit per-server `"sandbox": "native"` configuration. The shell CLI flag does
not set MCP policy. Unlike the shell's minimal environment, the MCP direct-exec
route can install explicitly selected environment values after the OS boundary;
its supervisor and macOS worker startup retain a clean environment. See the
[MCP contract](mcp.md#process-boundary-and-sandbox) for launch framing, private
temporary data, approvals, and independent enforcement evidence.

## Linux workspace profile

The dependency-free Rust helper implements `linux-workspace-v1`. It needs Linux
x86_64 or little-endian aarch64, Landlock ABI 6 or newer (Linux 6.12+), enabled
unprivileged user namespaces, and permitted mount/network namespaces and modern
mount APIs. Distribution policy or a containing sandbox may deny these features.
A supported architecture alone is not evidence that enforcement is available.
Effective root and privileged capabilities are refused.

A private user/mount/network namespace has an empty read-only root, no `/proc`,
read-only system tool/library binds, selected runtime/device files, a writable
workspace, and private writable temporary storage. Workspace mount sources are
pinned and identity-checked before mounting; replacement fails closed. Recursive
read-only mounts prevent metadata changes outside writable roots, covering a gap
that Landlock filesystem permissions alone do not close. Landlock confines file
access and signals; seccomp denies network sockets, host IPC, namespace creation,
process-group escape, and other dangerous calls. Private connected Unix stream
and sequence-packet socket pairs remain available for compiler/VM internals.
Datagram pairs and external sockets remain denied.

The command receives a minimal environment: system `PATH`, locale, and private
`HOME`/`TMPDIR`. Host provider keys and other inherited environment values are
absent. User-installed tools outside the system roots, home caches, package
fetching, and network services may therefore be unavailable. There is no automatic
permission expansion or tool installation to work around this.

Root, `/tmp` itself, protected system directories, a home directory or its
ancestors, and known credential directories/`IPSE_HOME` overlaps are refused.
An ordinary project below home or isolated directory below `/tmp` is allowed.
Secrets already inside an authorized workspace remain accessible: a workspace
write grant is not a mechanism to selectively protect files within that workspace.
File tools continue to use their separate workspace checks in Elixir.

Resource limits cover core dumps, per-process CPU/address space/file size,
file descriptors, and real-UID process headroom. They are not aggregate memory,
disk, or private process quotas. The existing timeout and owner-death process-group
cleanup remains necessary. See [native protocol and exact limits](../../native/README.md).
This profile reduces specified OS capabilities; it is not protection against
kernel vulnerabilities, an administrator, or every resource-exhaustion technique.

## macOS production boundary

On 2026-10-15, after reviewing the descendant escapes below, the developer
selected native macOS execution with best-effort descendant cleanup. The fixed
`macos-workspace-v1` backend uses an ad-hoc signed App Sandbox worker and the
approved built-in `/usr/bin/codesign`. See
[dependency approval](dependencies.md#optional-integrations). Deprecated
`sandbox-exec`, private APIs, privileged services, and VMs are not used.

The unsigned supervisor verifies the signed worker before launching untrusted
code. App Sandbox restricts files and network access and passes those restrictions
to children. The canonical workspace and a stable per-workspace data directory
are writable. `/opt/homebrew/` and `/usr/local/` are readable for installed tools;
macOS also grants its App Sandbox baseline and the application's own container
and bundle access. This is not a strict two-directory read allowlist.
The worker executes `/bin/sh` with a minimal `PATH`, locale, and temporary
`HOME`/`TMPDIR`, without inherited provider credentials or loader injection values.

Process groups stop ordinary children on exit, timeout, cancellation, or owner
death. Detached `setsid`/`setpgid` children can survive and continue workspace
writes. Their file/network restrictions remain active, but their lifetime is
not contained. Commands sharing the same workspace generation also share its
data root and OS container; there is no isolation between those commands.
After the initial child exits, output draining ends within 500 ms even if an
escaped child retains a pipe. See [the diagnostic](testing.md#macos-process-boundary-2026-10-15)
and [native verification](testing.md#macos-native-backend-2026-10-15).

The direct stdio supervisor retries ordinary group cleanup during idle drain
polls without extending that deadline. Detached pipe holders still fail the
stdio transport's drain and do not receive a successful completion record.
See [the local load investigation](testing.md#macos-stdio-cleanup-load-2026-10-15).

### Public interfaces and remaining limits

Apple documents [App Sandbox entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
and [absolute-path file exceptions](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html).
They provide the file/network boundary. The experiment did not establish
a public entitlement that prevents process-group changes or terminates an entire
adversarial process tree. File-policy inheritance and descendant lifetime are
separate acceptance checks.

The public alternatives reviewed so far do not close the observed gap:

- [`setsid`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setsid.2.html)
  creates a new session and group. The actual probe confirms that App Sandbox
  permits this operation and `setpgid` in descendants on this host.
- Apple's [kqueue header](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/event.h)
  marks `NOTE_TRACK`, `NOTE_TRACKERR`, and `NOTE_CHILD` unsupported since macOS
  10.5. `NOTE_FORK` does not return the child's PID. A process-table poll cannot
  prove race-free ownership across forks, reparenting, and PID reuse.
- Apple's [launchd contract](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5)
  documents cleanup of remaining processes with the job's process-group ID.
  That contract does not cover the observed group escapes.
- [Endpoint Security](https://developer.apple.com/documentation/endpointsecurity/es_new_client(_:_:))
  requires a separate entitlement and user approval for Full Disk Access.
  It is outside the approved ad-hoc helper design and has not been adopted or
  evaluated as a complete termination mechanism.

### Additional native controls reviewed

After the developer chose continued public-native research, the follow-up
review compared these contracts with the reproduced escape. These are source
and documentation findings; none is a new runtime dependency or OS test.

| Candidate | Documented behavior or source evidence | Decision for Ipse |
| --- | --- | --- |
| [Foundation `Process.terminate()`](https://developer.apple.com/documentation/foundation/process/terminate()) | Sends `SIGTERM`, which the target may ignore. Has no effect after the receiver finishes. | Cannot establish forced cleanup after the original command exits. |
| [XPC services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html) | `launchd` manages the service and kills idle services. | Useful for a separate helper policy, but no verified contract for escaped descendants. |
| [`posix_spawn` attributes](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_spawnattr_setflags.3.html) | Set the initial group or start the initial child suspended. | Do not establish inherited, immutable membership for later untrusted forks. |
| [`ptrace`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/ptrace.2.html) | Controls an identified traced process. The documented request set has no follow-fork containment operation. | No verified mechanism for arbitrary descendants and owner death. |
| [libproc interfaces](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h) | The header labels its process-information interfaces private and subject to change. The installed SDK has the same warning. | Do not adopt them as a documented public containment contract. |
| [`proc_terminate_all_rsr`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c) | XNU iterates the global process list and filters `P_RSR`, not descendants of a caller-supplied command. | Not a per-command kill-tree operation. Not invoked. |
| [XNU coalition controls](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/coalition.h) | Visible in OS source, but absent from the inspected SDK's `usr/include` tree. No documented app contract was located for private job creation, immutable membership, and forced teardown. | Source visibility does not satisfy the public-interface requirement. Not invoked. |
| [Endpoint Security fork events](https://developer.apple.com/documentation/endpointsecurity/event-types?language=objc) | Forks produce `NOTIFY_FORK`; the installed SDK has no `AUTH_FORK`. [Apple documents dropped messages](https://developer.apple.com/videos/play/wwdc2020/10159/) when the queue fills. | Notifications alone cannot prove complete descendant membership or prevent escape. No entitlement requested or client installed. |

Context7 resolved Apple's Foundation documentation and returned the termination
contract. Direct Apple documentation and XNU source supplied the other findings.
The installed SDK inspected was **27.0**, separate from the **26.7.2** host OS
and earlier macOS 14 CI. SDK inspection is not execution evidence for any of
those candidate APIs or a compatibility claim for older releases.

This review found no verified replacement for process-group cleanup. A stronger
candidate must establish kernel-enforced membership before untrusted code runs,
preserve it across fork/spawn/exec and group changes, protect the supervisor,
and force every member to stop on cancellation, timeout, or owner death.
It must also provide a safe completion check without signaling unrelated host
processes. The developer subsequently accepted best-effort cleanup for native
macOS mode. The current backend does not satisfy this stronger lifetime contract.

### Resource requirements

Apple's [`setrlimit` contract](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrlimit.2.html)
provides inherited process limits. Before shell exec the worker disables core
files, caps open descriptors at 256 and regular files at 64 MiB, and sets CPU
seconds to `ceil(timeout_ms / 1000) + 1`. Limits clamp to existing lower soft/hard
values. Tests verify inherited values, descriptor exhaustion, regular-file write
denial, and rejection of a hard-limit increase. CPU limits do not replace
wall-clock cleanup or constrain sleeping escaped processes.

The backend does not set a private process quota or claim aggregate memory/disk
limits. `RLIMIT_NPROC` applies to a real UID rather than a private job; it is not
used here. Hard memory-limit behavior has not been established.

### Signing and integration gates

`Ipse.MacOSSandbox` prepares an owner-only cache under
`IPSE_HOME/sandbox/macos`, defaulting to `~/.ipse/sandbox/macos`. A persistent
advisory lock serializes preparation. Staged signing publishes by atomic rename;
bounded abandoned stages are inspected and removed on the next preparation.
Unsafe ownership, permissions, symlinks, hard links, unexpected files, or
mismatched signatures, manifests, helper digests, and exact entitlement schemas
fail closed. Each signing/verification call has a 10-second timeout and bounded
output. The Rust supervisor independently verifies the signature and policy.

Cache identity includes helper contents, policy version, canonical workspace,
and cache root. The cache permits 32 generations and 32 matching data roots;
it fails before creating another generation when full. There is no automatic
eviction while detached children could still be running. Reuse does not broaden
the granted workspace. Each command gets a random temporary home below its
generation's shared data root; removal is best effort after completion.

The workspace must not contain the active helper, compiled application, or
protected cache. A source checkout therefore cannot sandbox itself; install a
bundle outside the target workspace. Native macOS mode requires a prebuilt
helper and refuses root. Existing `IPSE_HOME` directories must be owned by the
current user with mode `0700`.

macOS retains OS-managed app containers after cache or test removal. The
production cache uses a stable `org.ipse.runner.<generation>` bundle ID, avoiding
a new app container on every command. The backend and diagnostic do not remove
them or change unrelated application containers. The generation cap bounds
creation within one retained cache, not containers accumulated across deleted
caches. The experimental probe still creates a random bundle ID on each run.

## Windows

Windows needs an eventual native backend based on AppContainer/LPAC, workspace
ACL grants, and a no-breakaway Job Object assigned before the suspended child is
resumed. Windows runtime, packaging, and enforcement are not implemented. Never
advertise Linux enforcement or Unix process groups as a Windows backend.

## Verification

Ordinary fixture tests include explicit capability/fail-closed behavior. Actual
Linux enforcement tests are opt-in because kernel policy differs between hosts:

```sh
./scripts/build.sh
mix test --include native_sandbox
```

On macOS, run the production backend's enforcement suite:

```sh
mix test test/macos_sandbox_test.exs --include macos_sandbox
```

Included enforcement tests fail if unavailable; they never convert an unsupported
host into an enforcement pass. Record actual OS/toolchain and fixtures separately
from provider connectivity and release checks in [testing](testing.md).
