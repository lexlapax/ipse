> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/sandbox.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Working on native execution boundaries

Approval decides whether an effect is permitted. A sandbox restricts what an
executed process can do. Supervision owns its lifetime. These are separate
boundaries in Ipse, and tests must establish each claim independently.

`--sandbox off` is trusted local execution and the default. `native` requests a
fixed OS backend and refuses setup failure without an unsandboxed retry. `--yes`
does not weaken native policy. Session pins the selected mode on resume; inference
runs in Elixir outside the shell sandbox. Local MCP servers select sandbox mode
independently in their configuration.

Read `lib/ipse/sandbox.ex`, `macos_sandbox.ex`, and `native/README.md` before editing
`native/ipse-runner.rs` or `native/ipse-process-group.rs`. Elixir owns policy and
lifecycle; Rust owns small OS facilities.

## Keep the executable outside writable targets

Policy resolution rejects overlap between the workspace and active application,
selected helper, or protected cache before locking and before each launch. The
helper must be a bounded executable regular file, single-link, without group/other
write permission. Native execution never builds a missing helper from target
source. Install/build outside the workspace being modified, including for
self-development. Linux repeats executable-overlap checks in the helper.
These checks protect against target mutation, not hostile same-user replacement
outside the sandbox.

The shell environment contains fixed PATH/locale and private HOME/TMPDIR, without
provider credentials. MCP direct exec may install explicitly selected values only
after the OS boundary through bounded private launch framing. Do not broaden the
supervisor environment to make a server launch easier.

## Linux workspace profile

`linux-workspace-v1` requires Linux x86_64 or little-endian aarch64, Landlock ABI 6
or newer, unprivileged user namespaces, and permitted mount/network/PID namespaces
and modern mount APIs. Root and privileged capabilities refuse. Architecture alone
does not establish availability; containing policy can deny setup.

A private namespace has an empty read-only root, read-only system tool/library
binds, selected devices/runtime files, writable workspace, and private writable
temporary storage. Mount sources are pinned/identity-checked. Recursive read-only
mounts protect metadata outside writable roots. Landlock confines files/signals;
seccomp denies network sockets, host IPC, namespace creation, group escape, and
other dangerous calls. Private connected Unix stream/sequence-packet socket pairs
remain available for VM/compiler internals; datagram pairs and external sockets
remain denied.

Root, `/tmp` itself, protected system roots, home/ancestors, known credentials,
and `IPSE_HOME` overlaps refuse. Ordinary projects below home or isolated `/tmp`
subdirectories are allowed. Secrets already inside the workspace remain readable.
There is no dependency-root expansion or automatic network/tool installation.

Bash descriptor paths use `/dev/fd`, stdin/stdout/stderr links through fresh
read-only `subset=pid` procfs at `/dev/.ipse-proc` in the private PID namespace.
Host `/proc` stays absent. Landlock denies procfs enumeration and ordinary reads;
descriptor links reach only confined files or anonymous pipes. Do not mount host
procfs to repair a compiler's descriptor access.

A pre-exec waiter anchors group identity without running user code. Namespace
PID 1 mounts procfs, closes descriptors, and reaps; the command remains an ordinary
child so signals behave normally. Existing group cancellation stops the namespace.
Resource ceilings are zero core files, CPU `ceil(timeout)+1` seconds, 16 GiB
address space, 256 descriptors, and 64 MiB regular files. NPROC uses the observed
real-UID thread count plus 1,024, clamped to the caller's existing hard limit.
Exhausted hard limits or a failed bounded procfs scan refuse setup. These are
per-process/UID controls, not aggregate memory/disk/job quotas. Consult the native
README for exact setup checks.

## macOS production boundary

`macos-workspace-v1` uses an ad-hoc signed App Sandbox worker and built-in
`/usr/bin/codesign`. The unsigned supervisor verifies its signature/policy before
untrusted execution. Workspace and stable per-workspace data root are writable;
`/opt/homebrew/` and `/usr/local/` are readable. App Sandbox also grants baseline
container/bundle access, so this is not a strict two-directory read allowlist.
Children inherit file/network restrictions.

Ordinary process groups stop on completion, cancellation, timeout, and owner loss.
Detached `setsid`/`setpgid` descendants can survive and continue permitted writes.
Their restrictions persist, but lifetime containment is best effort. Commands in
one generation share its data root and app container. Cleanup acknowledgment must
not be described as proof that every detached descendant died. Output draining
ends within 500 ms after initial child exit; retained pipes still cause stdio
transport failure.

Before shell exec, limits disable core files, cap descriptors at 256 and regular
files at 64 MiB, and set CPU seconds to `ceil(timeout_ms/1000)+1`, clamped by lower
existing soft/hard values. Sleeping detached processes remain outside CPU cleanup.
No private process quota or aggregate memory/disk quota is enforced.

`Ipse.MacOSSandbox` owns a private cache under `IPSE_HOME/sandbox/macos`, protected
by a stable advisory lock. Atomic staged signing, exact entitlement/manifest/helper
digests, ownership, permissions, path types, and hardlinks are checked. Signing and
verification each have a 10-second deadline and bounded output. Cache identity
includes helper, policy, canonical workspace, and cache root. It permits 32
generations and 32 matching data roots, with no automatic eviction while detached
processes might live. Each command gets a random temporary home; cleanup is best
effort. OS-managed containers can outlive cache removal.

Native macOS mode requires a prebuilt helper, refuses root, and requires existing
Ipse home directories to be owned by the user with mode `0700`. A source checkout
cannot sandbox itself. No private process APIs, privileged service, VM, or
`sandbox-exec` fallback is used.

## Exercise enforcement instead of inspecting configuration

First read the Bash substitution and host-pipe cases in
`test/linux_sandbox_test.exs`. The test proves allowed descriptors work while host
process descriptors remain unreachable. Compare that with descendant-lifetime
cases in `test/macos_sandbox_test.exs`; they intentionally establish a weaker
cleanup boundary.

```sh
./scripts/build.sh
mix test --include native_sandbox
mix test test/macos_sandbox_test.exs --include macos_sandbox
```

Run only the enforcement suite matching the host when developing a backend.
Included tests fail if enforcement is unavailable; a skip is not evidence of
confinement. `test/macos_sandbox_cache_test.exs` checks cache admission separately.
A new allowlist entry needs both an intended successful operation and a nearby
forbidden operation. A launch that merely exits successfully proves little.

## Windows

There is no Windows runtime, package, or native backend. A future implementation
needs its own public file/network boundary and a preassigned no-breakaway job
lifetime policy. Unix groups and Linux tests do not establish Windows enforcement.
