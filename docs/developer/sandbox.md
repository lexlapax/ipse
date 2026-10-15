# Native shell sandbox

`--sandbox off` is the default trusted local mode. `--sandbox native` explicitly
requests the fixed native OS backend. Approval and sandboxing are independent:
`--yes` changes approval policy, never disables sandbox enforcement. Failure to
create the requested sandbox stops that shell call; it never retries unsandboxed.
Sessions retain the requested mode in metadata and reject a different mode on
resume. Provider inference runs in Elixir outside the shell sandbox.

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
socket pairs remain available for compiler/VM internals.

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

The developer selected native backends rather than Linux containers on every OS.
macOS core/runtime checks and an experimental signed App Sandbox helper probe
are separate from a supported production sandbox backend. Built-in `codesign`
was explicitly approved; see [dependency approval](dependencies.md#optional-integrations).
The experimental file/network and child-inheritance probe passed on macOS 14
arm64 CI; see [actual evidence](testing.md#p4-release-verification-and-protocol-proposal-2026-10-15).
Those checks do not prove resource/process containment or a production CLI backend.
Deprecated `sandbox-exec` is not used.

Local checks on macOS 26.7.2 arm64 reproduced file/network enforcement but found
a process-containment failure. Both `setsid` and `setpgid` descendants survived
normal command exit, timeout, explicit Port closure, and Port-owner death.
They retained App Sandbox's outside-file denial and still wrote inside the
workspace after the helper process exited. Ordinary descendants in the original
group were terminated in all four cases. The CLI remains fail closed on macOS.
See [the reproducible diagnostic and evidence](testing.md#macos-process-boundary-2026-10-15).

### Public interfaces and remaining limits

Apple documents [App Sandbox entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
and [absolute-path file exceptions](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html).
They provide the probe's file/network boundary. The experiment does not establish
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

Apple's [`setrlimit` contract](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getrlimit.2.html)
provides inherited process limits. The proposed ceilings are core files disabled,
256 open descriptors, 64 MiB regular files, and CPU seconds derived from the
command deadline. CPU limits do not constrain a sleeping escaped process.
`RLIMIT_NPROC` applies to a real UID, not a private job. Memory-limit behavior
needs verification on each supported macOS version before claiming a hard
ceiling. These macOS ceilings are design requirements, not implemented limits.
Tests must prove actual denial, inheritance, and inability to raise a hard limit.

### Signing and integration gates

A production cache needs an owner-only location outside the writable workspace,
cross-process locking, atomic publication of a strictly verified signature,
and rejection of replaced or symlinked inputs. Cache identity must include the
helper contents, policy version, and exact canonical granted roots. No reused
bundle may silently retain a broader workspace or temporary-directory grant.
Concurrent commands and interrupted signing need explicit recovery checks.

The current diagnostic removes its scratch bundle and workspace files. macOS
also creates `~/Library/Containers/org.ipse.sandbox.<random-id>` for the signed
application. Those OS-managed containers persist after the probe; three were
observed after three local invocations. Container retention and cleanup must be
part of the production signing lifecycle. The probe does not remove them or
change unrelated application containers.

Integration remains gated on a verified process boundary, resource enforcement,
signing/cache recovery, cancellation and owner-death cleanup, and a fresh bundled
native-mode check. Signal isolation from the supervisor and unrelated host
processes also remains unverified. Polling or cooperative child self-termination
cannot replace adversarial containment. No private API, deprecated sandbox
utility, privileged service, or VM dependency has been introduced. Changing
the required boundary or adopting another platform dependency needs a developer
decision before enabling a production backend.

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

Included enforcement tests fail if unavailable; they never convert an unsupported
host into an enforcement pass. Record actual OS/toolchain and fixtures separately
from provider connectivity and release checks in [testing](testing.md).
