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

## Other native platforms

The developer selected native backends rather than Linux containers on every OS.
macOS core/runtime checks and an experimental signed App Sandbox helper probe
are separate from a supported production sandbox backend. Built-in `codesign`
was explicitly approved; see [dependency approval](dependencies.md#optional-integrations).
The experimental file/network and child-inheritance probe passed on macOS 14
arm64 CI; see [actual evidence](testing.md#p4-release-verification-and-protocol-proposal-2026-10-15).
Those checks do not prove resource/process containment or a production CLI backend.
Deprecated `sandbox-exec` is not used.

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
