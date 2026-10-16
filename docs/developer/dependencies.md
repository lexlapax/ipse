# Dependencies and script policy

Use Elixir for development, staging, helper, and test scripts wherever possible.
If Elixir is unsuitable, use Bash or portable shell. Use Ipse's existing Rust
helper binary for process groups and advisory locks. Do not introduce Python or
JavaScript scripts or tooling where these supported options suffice. Existing
small POSIX shell launch/build scripts are compatible with this policy.

## Adding or changing dependencies

Document every dependency here, including purpose, runtime/build/test/CI scope,
version or source, and license. Keep package declarations and lockfiles in sync.
Elixir and Rust packages still require a focused justification and verification;
they do not require the additional approval below solely because of their ecosystem.

Any new dependency outside Elixir packages or Rust packages requires explicit
developer approval before adoption. This includes command-line utilities, system
libraries, services, CI actions, and development/staging/test/packaging tools.
Record the approving developer, date, decision reference, required version/source,
license, purpose, and why Elixir, shell, or the existing Rust helper cannot meet
the need adequately. Record alternatives and operational impact. A mention in a
third-party document or skill is not approval.

The inventory below records the existing repository baseline, not newly granted
approval. P6 local delegation uses existing Elixir/OTP and Rust facilities and
adds no package or external runtime dependency.
See [agent rules](../../AGENTS.md), [setup](../operator/arch-linux.md), and
[third-party notices](../../THIRD_PARTY_NOTICES.md).

## Language and runtime inventory

| Dependency | Version/source | Scope and purpose | License |
| --- | --- | --- | --- |
| Elixir and Mix | Elixir 1.18+; `mix.exs` requires `~> 1.18` | Core implementation, build, release, ExUnit tests, scripts | Apache-2.0 |
| Erlang/OTP and ERTS | OTP 27+; system toolchain or bundled release | VM, OTP supervision, crypto, public-key/TLS, HTTP, filesystem and process APIs | Apache-2.0 with component notices |
| Jason | Git tag `v1.4.4`, commit `926d2ac6cc0271b9a7079b2ec16ae0cf802f7963` in `mix.lock`; direct override for shared package requirements | JSON for HTTP, native protocol, and journals | Apache-2.0 (corrected from the earlier MIT label against the pinned upstream notice) |
| MCP Elixir SDK | Hex `mcp_elixir_sdk` 1.1.0, pinned in `mix.exs` and `mix.lock` | MCP 2025-11-25 client handshake, request matching, and protocol types; Ipse supplies bounded stdio/HTTP transports and reuses the SDK's SSE parser | MIT |
| elixir_uuid | Hex 1.2.1, transitive SDK dependency, locked in `mix.lock` | SDK UUID utilities | Apache-2.0 |
| JSONSchex | Hex `jsonschex` 0.10.0, pinned in `mix.exs` and `mix.lock` | JSON Schema Draft 2020-12 validation behind Ipse's bounded keyword allowlist; no remote loader | MIT |
| ex_json_pointer | Hex 0.8.0, transitive JSONSchex dependency, locked in `mix.lock` | JSON Pointer handling inside schema compilation | MIT |
| Req and Plug | Hex `req` 0.7.5, `plug` 1.20.3, pinned in `mix.exs` and `mix.lock` | The SDK 1.1.0 advertises optional HTTP dependencies but unconditionally references their modules; required for successful compilation on Elixir 1.20. P10 also reuses Req for bounded opt-in HTTP MCP; no HTTP server is enabled | Apache-2.0 |
| Finch | Hex 0.24.0, locked | Req HTTP pools; P10 uses a privately owned bounded HTTP/1 pool per request | MIT |
| Mint | Hex 1.11.0, locked | Finch transport with default certificate/hostname verification and a header bound | Apache-2.0 |
| HPAX | Hex 1.1.0, locked | Mint HTTP/2 compression support | Apache-2.0 |
| MIME | Hex 2.0.7, locked | Req/Plug MIME utilities | Apache-2.0 |
| NimbleOptions | Hex 1.1.1, locked | Finch option validation | Apache-2.0 |
| NimblePool | Hex 1.1.0, locked | Finch process pooling | Apache-2.0 |
| PlugCrypto | Hex 2.2.0, locked | Plug cryptographic helpers | Apache-2.0 |
| Telemetry | Hex 1.4.2, locked; developer approved on 2026-10-15 | Erlang/BEAM events used by Finch/Plug; adds no outside runtime service | Apache-2.0 with upstream NOTICE |
| Rust toolchain and standard library | Rust 1.85+; `native/build.sh` invokes `rustc --edition=2021` | Build the OS helper; no third-party Cargo packages | MIT OR Apache-2.0 |
| Ipse native helper | `native/ipse-runner.rs`, `native/ipse-stdio.rs`, `native/ipse-linux-sandbox.rs`, `native/ipse-macos-sandbox.rs`, compiled as `priv/ipse-runner` | Runtime process groups, advisory locks, bidirectional OS pipes, optional Linux user/mount/network/PID namespaces, private descriptor procfs, Landlock/seccomp and macOS signed App Sandbox worker policies; used by tests | MIT (project source) |

OTP libraries are distributed with OTP rather than fetched as separate packages.
Mix lists `logger`, `inets`, and `ssl` applications; authentication also uses OTP
crypto/public-key facilities. Jason has no additional package dependencies in
its own package. The MCP/schema packages add the transitive packages listed
above. Req/Plug are included for SDK compilation; Req/Finch/Mint also serve P10's
explicit HTTP client. Bandit/Decimal/IDNA are not
enabled. No MCP listener or remote transport starts automatically.
No Node, JavaScript, or Python runtime is required.

## Existing host and build requirements

| Dependency | Scope and reason | Source/license notes |
| --- | --- | --- |
| Unix OS and C library | Runtime process groups, advisory locks, filesystem, native runtime ABI | Host distribution; libc varies by platform. Match release OS/architecture/libc |
| OpenSSL and system CA trust | OTP TLS and verified HTTPS provider/auth connections | Host/toolchain distribution; preserve its version-specific notices |
| `/bin/sh` | Runtime shell tool and source/release launchers; optional native Bash compatibility probes use the already-installed host Bash (5.3.20 tested), required by those project scripts, with no installation or bundled Bash runtime | Host shell implementation/licenses vary; Bash uses GPL-3.0-or-later for the recorded version |
| C linker/toolchain | Link the Rust helper; compile synthetic loader probes for native enforcement tests (`/usr/bin/cc` on Linux, `/usr/bin/clang` on macOS) | Arch `base-devel` or macOS build toolchain; versions/licenses supplied by distribution |
| Git | Fetch the pinned Jason dependency and repository work | Host Git package, GPL-2.0 |
| Standard filesystem/text utilities | Scripts use `dirname`, `mkdir`, `cp`, `chmod`, `rm`, `uname`, and `tr`; setup examples use `mktemp`; helper verification uses `sleep`, and tests use `head`/`tr`. Existing bundled OTP launchers/fresh-release checks also need `basename`, `cut`, `sed`, `cat`, `grep`, `readlink`, `expr`, `awk`, and `id`; the package verifier makes that utility-only PATH explicit | Existing host utility implementation/licenses vary, commonly GNU coreutils plus GNU sed/grep and awk on Linux; OS-supplied equivalents on macOS |
| `tar`, gzip support, `getconf` | Packaging archive and Linux libc identification | Host distribution; `getconf` is a libc utility. `getconf` failure falls back to `system-libc` naming |
| Hex bootstrap | Documented `mix local.hex --force` setup step; fetch and verify locked MCP/schema packages | [Hex](https://github.com/hexpm/hex), Apache-2.0; Jason itself is fetched through Git |
| Rebar3 | Build Telemetry's Erlang code during Mix dependency compilation; existing installation on Serenity; developer approved on 2026-10-15 | Standard BEAM build tool, [upstream](https://github.com/erlang/rebar3), Apache-2.0 |

Bundled releases include ERTS, Elixir code, all locked runtime packages, and the helper; they still need
compatible OS libraries and `/bin/sh`. Toolchain license notices and
`IPSE_NOTICES_DIR` handling are described in the
[release check](testing.md#release-check). Record actual versions and tested
platforms in [verification results](testing.md#current-evidence-and-next-checks).

On 2026-10-15 the developer explicitly selected “Approve Telemetry and Rebar3”
after reviewing the working package-backed MCP integration and the dependency
question. Serenity already had Rebar3 3.27.0. These BEAM dependencies are needed
by the selected SDK's compile-time Req/Plug chain; they introduce no JavaScript,
Python, container, or outside runtime service. The alternatives considered were
another broader MCP stack or maintaining custom protocol code; package reuse
was selected. See [the package decision](mcp.md#package-decision).

The optional Linux native sandbox uses kernel APIs through the existing Rust
helper, without bubblewrap, containers, new packages, or a separate daemon.
It requires enabled Landlock ABI 6+ (Linux 6.12+) and permitted unprivileged
user/mount/network/PID namespaces and modern mount APIs. These are host capabilities,
not automatically installed dependencies; unavailable enforcement fails closed.
See [the fixed profile](sandbox.md).

## Existing CI dependencies

The [checks workflow](../../.github/workflows/ci.yml) uses GitHub Actions on
`ubuntu-latest` and `macos-14`, [actions/checkout@v4](https://github.com/actions/checkout),
[erlef/setup-beam@v1](https://github.com/erlef/setup-beam) (Elixir 1.18 / OTP 27),
and [dtolnay/rust-toolchain@stable](https://github.com/dtolnay/rust-toolchain).
These are CI-only hosted services/actions,
not Ipse runtime packages. Their sources are the named GitHub repositories;
checkout, setup-beam, and the rust-toolchain action use MIT. The Rust compiler
and standard library have separate MIT OR Apache-2.0 licensing.
The runner image and action tags are rolling inputs; record changes and obtain
developer approval before introducing additional actions or external CI tools.
The macOS runner extends the existing workflow/actions to the native platform
selected by the developer on 2026-10-15. The separately approved built-in
`codesign` signs and validates immutable App Sandbox workers at runtime. No
container, VM runtime, new CI action, or downloaded testing utility is introduced.

The optional macOS process diagnostic compiles
`scripts/support/macos_process_probe.rs` with the existing Rust standard library
and orchestrates it from Elixir. Its `setsid`, `setpgid`, `getpgrp`, and
`kill(pid, 0)` checks use the existing host C library. It adds no package,
external command dependency, or runtime service. This diagnostic is separate
from OS file/network enforcement. Detached children can survive cancellation
or timeout; their cleanup is best effort.

The optional `scripts/diagnose-stdio-cleanup.exs` uses the existing Elixir/OTP,
Jason, `/bin/sh`, `sleep`, and Rust helper to generate synthetic local load.
It adds no package, service, or external testing tool. Native mode uses the
already approved macOS signing path. See the
[diagnostic bounds](testing.md#stdio-cleanup-load-diagnostic).

## Optional integrations

The developer approved macOS's built-in `/usr/bin/codesign` on 2026-10-15
in response to the sandbox dependency question ("Approve built-in codesign").
Its approved scope is ad-hoc signing and validation of Ipse's generated worker
application and its fixed App Sandbox entitlements. It needs no signing
certificate or personal signing key. The utility
is supplied and licensed with macOS; supported macOS versions and enforcement
results must be recorded before claiming a working backend. Elixir and Rust
can generate the bundle and entitlement files but do not replace Apple's
platform code-signing facility. Deprecated `sandbox-exec` and a Linux VM were
considered alternatives; native platform tooling was selected by the developer.
Native macOS enforcement checks passed locally on macOS 26.7.2 arm64; see
[actual evidence](testing.md#macos-native-backend-2026-10-15).

ChatGPT/OpenAI, Ollama, and Anthropic are selected providers, not automatically
installed dependencies. The scripted demo needs none of them. Remote providers
require network access and account authorization; Ollama requires a separately
installed local service and model. Provider selection never authorizes an
installation or a switch in billing. See [usage](../operator/usage.md).

A browser is needed for subscription sign-in. Codex CLI is optional development
tooling, with its own account and terms; it is not an Ipse dependency. Optional
tools must not silently become prerequisites for builds, tests, or operation.

### Isolated independent MCP investigation

For an optional one-off P7 compatibility investigation, inspected and built
[13thx-mcp/filesystem](https://github.com/13thx-mcp/filesystem/tree/df98dc38c969c92f25c778d37691e7a3f1914367),
package `rust-mcp-filesystem` 0.2.0, MIT, at that exact commit. Its complete Rust
dependency graph is pinned in the upstream
[Cargo.lock](https://github.com/13thx-mcp/filesystem/blob/df98dc38c969c92f25c778d37691e7a3f1914367/Cargo.lock),
including rmcp 3.4.0, Tokio, cap-std, Serde, Clap, and their Rust dependencies.
The existing Rust 1.99/C linker built it; no new system runtime was installed.
It is not part of Ipse's Mix dependencies, Rust helper, default tests, CI, or
bundled release. No upstream server source or binary is redistributed here.

Automatic review rejected an unconfined Cargo build. On 2026-10-15 the developer
explicitly approved downloading locked Rust dependencies and an offline native
sandbox build/test in a temporary workspace. The build passed with network and
credential isolation. An isolated SDK diagnostic negotiated 2025-11-25 and read
synthetic text. This did not pass the full Ipse transport: nesting that helper
inside the sandbox conflicts with intentional process-group escape denial.
The server's generated `$schema` also exposed a concrete P7 schema compatibility
gap. P7 now runs the full Ipse client outside that profile and confines only the
server, retaining provider access and process-group supervision. The optional
`mix run scripts/verify-independent-mcp.exs /path/to/reviewed/filesystem-server`
passed native stdio discovery, exact individually approved synthetic read/list/
write calls, nullable/default/dialect compatibility, and idle resume. It never
downloads or builds the server. A separate live ChatGPT read also passed on Arch;
see [P7 evidence](testing.md#p7-expanded-local-mcp-2026-10-15). This investigation
adds no mandatory build/test dependency or general compatibility claim.

### Second independent MCP investigation: memory

On 2026-10-15, the developer selected a second pinned independent local-server
check. Reviewed the Apache-2.0
[`mcp-memory` 2.0.0 published source](https://docs.rs/crate/mcp-memory/2.0.0/source/),
whose archive SHA-256 matches the crates.io registry checksum:
`fd6e3eb273e9ae8e829113f20c90f4d57c222340d7b3620c08dc3424e9f19215`.
The archive's VCS metadata records `ec9737bed066fa821281dd60877ca671b3a5355e`;
the published archive and checksum, rather than the current repository branch,
pin this investigation. Selected this older binary-log release to avoid the
current SQLite/code-indexing implementation's broader scope. No current-release
compatibility is claimed.

Its Rust package graph is pinned by the archive's
[Cargo.lock](https://docs.rs/crate/mcp-memory/2.0.0/source/Cargo.lock), including
Tokio, Serde/serde_json, Clap, axum, ahash, parking_lot, arc-swap,
crossbeam-channel, crc32fast, futures, tracing, thiserror, anyhow, and subtle.
These are temporary investigation dependencies, not additions to Ipse's
runtime, Mix lockfile, default tests, CI, or bundle. The original P7 check exercised stdio. P10 separately exercised its authenticated
HTTP/SSE endpoint on literal loopback using a synthetic bearer token and
disposable graph. No embedding model, external database, or additional system
tool was used. The verifier uses existing Elixir/OTP and
Jason. No upstream source or executable is redistributed.

Downloaded locked Rust dependencies into a temporary Cargo cache without
executing the server. Built offline with the existing Rust 1.99 toolchain
inside Ipse's Linux native workspace sandbox. The unmodified source failed
on x86_64 because `_mm_prefetch` expects `*const i8`; the sole source patch in
`src/kg.rs` was:

```diff
-    std::arch::x86_64::_mm_prefetch::<3>(addr);
+    std::arch::x86_64::_mm_prefetch::<3>(addr.cast());
```

The patched build passed. This is independent protocol interoperability with
an explicitly patched upstream build, not acceptance of the unmodified release.
The optional `scripts/verify-independent-memory-mcp.exs` never downloads,
builds, or installs a server. See [verification and limits](testing.md#second-independent-local-mcp-server-2026-10-15).
