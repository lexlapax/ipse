# Verify native execution and process ownership

Approval permits an effect. Confinement limits its OS access. Supervision owns
its lifetime. Test those claims separately. Default `--sandbox off` is trusted
user execution; explicit native mode fails closed without unsandboxed retry.
`--yes` changes approval, not confinement. Session pins mode on resume. Inference
runs outside the shell sandbox, and local MCP chooses its own launch policy.

Read [`Tools.Sandbox`](../../lib/ipse/tools/sandbox.ex),
[`Tools.MacOSSandbox`](../../lib/ipse/tools/macos_sandbox.ex),
[`Runner`](../../lib/ipse/runner.ex), then the [native protocol](../../native/README.md).
Elixir owns policy/lifecycle; Rust implements narrow OS facilities. The exercised
backend and host capabilities determine the guarantee, not a successful config parse.

## Protect the executable before launching work

Resolution rejects overlap between writable workspace and active application,
selected helper, or protected cache before locking and each launch. Helpers must
be bounded executable regular files, singly linked and not group/other writable.
Native execution never builds a missing helper from writable target source.
Build/install outside the workspace being changed; Linux repeats overlap checks
in the helper. These protect target mutation, without defending against arbitrary
same-user replacement outside confinement.

Shell environment uses fixed PATH/locale and private HOME/TMPDIR, excluding provider
credentials. MCP direct exec can install explicitly selected values only through
bounded private launch framing after confinement. Do not broaden the supervisor's
environment to make a toolchain/server work.

## Understand the Linux workspace profile

`linux-workspace-v1` supports x86_64 or little-endian aarch64 with Landlock ABI 6+,
permitted unprivileged user/mount/network/PID namespaces, and modern mount APIs.
Root/privileged capabilities refuse. A containing policy may still deny setup.
A private namespace has empty read-only root, pinned read-only system tool/library
binds, selected devices/runtime files, writable workspace, and private temporary
storage. Recursive read-only mounts protect external metadata; Landlock confines
files/signals. Seccomp denies external network, host IPC, namespace creation,
group escape, and other unsupported operations. Connected Unix stream/seqpacket
pairs remain for VM/compiler internals; datagram pairs remain denied.

Root, `/tmp` itself, protected system roots, home/ancestors, known credentials,
and Ipse-home overlap refuse. Ordinary projects below home or private temporary
subdirectories are allowed. Workspace secrets remain readable. No dependency-root
expansion, network access, or tool installation is inferred from a task.

Descriptor paths use `/dev/fd` and stdio links through fresh read-only `subset=pid`
procfs at `/dev/.ipse-proc` inside the private PID namespace. Host `/proc` remains
absent. Landlock denies proc enumeration/ordinary reads while descriptors reach
only confined files or anonymous pipes. Do not expose host procfs to repair Bash
substitution or compiler access.

A pre-exec waiter anchors process-group identity before release. Escaped descendants
still cannot escape the PID namespace; terminating its init ends the group.
Preserve registration/start barriers and native cleanup evidence when changing
Runner. Killing a BEAM task alone is not the same proof.

## Understand the macOS workspace profile

`macos-workspace-v1` uses a signed App Sandbox worker and public `/usr/bin/codesign`.
An unsigned supervisor verifies signature/policy before execution. Workspace and
stable per-workspace data root are writable; Homebrew locations are readable.
Baseline container/bundle access means this is not a strict two-directory read
allowlist. Descendants inherit file/network restrictions.

Ordinary groups stop on completion/cancellation/timeout/owner loss. Deliberate
`setsid`/`setpgid` descendants can survive and keep permitted writes. Restrictions
persist but lifetime containment is best effort. Same-generation commands share
sandbox data/container. Cleanup acknowledgment does not prove all detached work
died. Output draining ends within 500 ms of direct-child exit; retained pipes still
cause stdio failure.

Before exec, core files are disabled, descriptors capped at 256, regular files at
64 MiB, and CPU seconds at `ceil(timeout_ms/1000)+1`, narrowed by existing limits.
Sleeping detached work remains outside CPU cleanup. No private-process, aggregate
memory, or aggregate disk quota exists.

The private `IPSE_HOME/sandbox/macos` cache uses a stable advisory lock, atomic
staged signing, exact entitlements/manifest/helper hashes, and owner/type/mode/
hardlink checks. Signing/verification each allow ten seconds and bounded output.
Identity binds helper/policy/canonical workspace/cache root. Capacity is 32
generations and matching data roots, without automatic eviction while detached
processes may live. Each command gets random temporary home; cleanup is best effort
and OS containers can outlive cache removal. Existing Ipse home must be owned by
the user with `0700`; root and missing prebuilt helper refuse. A source checkout
cannot sandbox itself. There is no private process API, privileged service, VM,
or `sandbox-exec` fallback.

## Observe a directly owned Linux listener

An HTTP response cannot prove a newly launched process owns its address; a previous
server could answer after bind failure. Runner's optional owned-listener mode
provides one native ownership observation, without implying confinement or model
correctness. On Linux `open_stdio/6` accepts `owned_listener: {:ipv4_loopback, port}`,
sandbox off, and an absolute executable.

Before launch, bounded `/proc/self/status` inspection requires a sole `NStgid`
equal to the helper's PID. This establishes that numeric proc paths use its PID
namespace. Inherited ancestor procfs refuses; a fresh PID namespace with its own
procfs can work. Ordinary stdio does not require the optional capability.
The `P` fact associates exact caller-visible `127.0.0.1` listener with descriptors
held by the retained direct child. IPv4 wildcard, same-port IPv6 wildcard, and
only-delegated listeners refuse. Both caller TCP tables share a 1-MiB bound.
A forged child stdout line remains opaque data; missing listener times out.
Other platforms refuse before launching the selected executable.

From a Linux checkout:

```sh
mix run dev/verify-owned-listener.exs
mix run dev/verify-owned-listener-regressions.exs
mix test test/ipse/runner/listener_test.exs test/ipse/runner/stdio_test.exs
```

The ordinary exercise makes two metadata requests and zero inference calls.
Inspect its retained private evidence: positive observation precedes metadata;
occupied-port refusal makes no request before a positive query of the untouched
existing fixture. Ordinary stdio emits no proof.

The regression command compiles temporary diagnostic native copies, reverting
one repair at a time without changing production source. A private-network-
namespace listener must remain unproven in the caller namespace. Closing output
during inspection must retain the same unreaped child until teardown. Additional
controls cover inherited ancestor procfs refusal before marker creation, ordinary
stdio in that setup, and fresh-private-procfs positive admission. Missing user/
network/PID/mount capability yields incomplete/exit two, not coverage.

Trace `native/ipse-stdio.rs` and `native/ipse-listener.rs`. The sole wait owner keeps
the child unreaped while background inspection uses numeric proc paths. Socket
tables describe the HTTP caller's namespace, not the child's private namespace.
Retain identity across output loss. After `P`, continue draining/monitoring the
Port through bounded metadata requests; terminal/transport loss ends admission.
PID/inode are diagnostic, not signaling handles. Cleanup still uses ordinary
`close_stdio/2` and group ownership. The [native fields](../../native/README.md#observe-an-owned-loopback-listener)
are authoritative. Exact charged-RAM collection is a separate
[measurement contract](measurement.md), not a listener or shell guarantee.

## Prove allowed and forbidden operations

First follow Bash substitution/host-pipe fixtures in `test/ipse/tools/sandbox_test.exs`.
They establish usable confined descriptors while external process descriptors
stay unreachable. Compare macOS lifetime cases, which deliberately demonstrate
weaker cleanup. Run only the backend matching the host. On Linux:

```sh
./dev/build.sh
mix test --include native_sandbox
```

On macOS use its explicit native sets:

```sh
mix test test/ipse/tools/macos_sandbox_test.exs --include macos_sandbox
mix test test/ipse/tools/macos_filesystem_test.exs --include macos_filesystem
```

Included enforcement tests fail when unavailable; exclusions/skips establish no
enforcement. Cache admission has its own `macos_sandbox_cache_test.exs`. Each
allowlist change needs intended success plus a nearby forbidden operation. Source,
installed helper lookup, signatures, and actual OS policy are separate checks.
[Testing](testing.md) covers their final handoff sequence.

Windows has no runtime, package, or native backend. A future backend needs public
file/network confinement and a preassigned no-breakaway job lifetime contract;
Unix-group tests cannot establish it.
