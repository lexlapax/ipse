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
approval. No new dependency was introduced by the documentation restructure.
See [agent rules](../../AGENTS.md), [setup](../operator/arch-linux.md), and
[third-party notices](../../THIRD_PARTY_NOTICES.md).

## Language and runtime inventory

| Dependency | Version/source | Scope and purpose | License |
| --- | --- | --- | --- |
| Elixir and Mix | Elixir 1.18+; `mix.exs` requires `~> 1.18` | Core implementation, build, release, ExUnit tests, scripts | Apache-2.0 |
| Erlang/OTP and ERTS | OTP 27+; system toolchain or bundled release | VM, OTP supervision, crypto, public-key/TLS, HTTP, filesystem and process APIs | Apache-2.0 with component notices |
| Jason | Git tag `v1.4.4`, commit `926d2ac6cc0271b9a7079b2ec16ae0cf802f7963` in `mix.lock` | Sole external Elixir package; JSON for HTTP, native protocol, and journals | MIT |
| Rust toolchain and standard library | Rust 1.85+; `native/build.sh` invokes `rustc --edition=2021` | Build the OS helper; no third-party Cargo packages | MIT OR Apache-2.0 |
| Ipse native helper | `native/ipse-runner.rs`, `native/ipse-linux-sandbox.rs`, compiled as `priv/ipse-runner` | Runtime process groups, advisory locks, optional Linux namespace/Landlock/seccomp policy; used by tests | MIT (project source) |

OTP libraries are distributed with OTP rather than fetched as separate packages.
Mix lists `logger`, `inets`, and `ssl` applications; authentication also uses OTP
crypto/public-key facilities. Jason has no additional package dependencies in
the current lockfile. No Node, JavaScript, or Python runtime is required.

## Existing host and build requirements

| Dependency | Scope and reason | Source/license notes |
| --- | --- | --- |
| Unix OS and C library | Runtime process groups, advisory locks, filesystem, native runtime ABI | Host distribution; libc varies by platform. Match release OS/architecture/libc |
| OpenSSL and system CA trust | OTP TLS and verified HTTPS provider/auth connections | Host/toolchain distribution; preserve its version-specific notices |
| `/bin/sh` | Runtime shell tool and source/release launchers | Host shell implementation and license vary; POSIX shell syntax is used |
| C linker/toolchain | Link the Rust helper during source builds | Arch `base-devel`; versions/licenses supplied by distribution |
| Git | Fetch the pinned Jason dependency and repository work | Host Git package, GPL-2.0 |
| Standard filesystem/text utilities | Scripts use `dirname`, `mkdir`, `cp`, `chmod`, `rm`, `uname`, and `tr`; setup examples use `mktemp`; helper verification uses `sleep`, and tests use `head`/`tr`. Existing bundled OTP launchers/fresh-release checks also need `basename`, `cut`, `sed`, `cat`, `grep`, `readlink`, `expr`, `awk`, and `id`; the package verifier makes that utility-only PATH explicit | Existing host utility implementation/licenses vary, commonly GNU coreutils plus GNU sed/grep and awk on Linux; OS-supplied equivalents on macOS |
| `tar`, gzip support, `getconf` | Packaging archive and Linux libc identification | Host distribution; `getconf` is a libc utility. `getconf` failure falls back to `system-libc` naming |
| Hex bootstrap | Documented `mix local.hex --force` setup step | [Hex](https://github.com/hexpm/hex), Apache-2.0; Jason itself is fetched through Git, not a Hex package |

Bundled releases include ERTS, Elixir code, Jason, and the helper; they still need
compatible OS libraries and `/bin/sh`. Toolchain license notices and
`IPSE_NOTICES_DIR` handling are described in the
[release check](testing.md#release-check). Record actual versions and tested
platforms in [verification results](testing.md#current-evidence-and-next-checks).

The optional Linux native sandbox uses kernel APIs through the existing Rust
helper, without bubblewrap, containers, new packages, or a separate daemon.
It requires enabled Landlock ABI 6+ (Linux 6.12+) and permitted unprivileged
user/mount/network namespaces and modern mount APIs. These are host capabilities,
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
selected by the developer on 2026-10-15; the separately approved built-in
`codesign` is used only for the experimental App Sandbox probe. No container,
VM runtime, new CI action, or downloaded testing utility is introduced.

The optional macOS process diagnostic compiles
`scripts/support/macos_process_probe.rs` with the existing Rust standard library
and orchestrates it from Elixir. Its `setsid`, `setpgid`, `getpgrp`, and
`kill(pid, 0)` checks use the existing host C library. It adds no package,
external command dependency, or runtime service. The extra process check is
opt-in and fails on the currently observed group escapes; it is separate from
CI's passing file/network probe.

## Optional integrations

The developer approved macOS's built-in `/usr/bin/codesign` on 2026-10-15
in response to the sandbox dependency question ("Approve built-in codesign").
Its approved scope is ad-hoc signing of Ipse's generated helper application
and sealing its App Sandbox entitlements, including macOS CI enforcement
checks. It needs no signing certificate or personal signing key. The utility
is supplied and licensed with macOS; supported macOS versions and enforcement
results must be recorded before claiming a working backend. Elixir and Rust
can generate the bundle and entitlement files but do not replace Apple's
platform code-signing facility. Deprecated `sandbox-exec` and a Linux VM were
considered alternatives; native platform tooling was selected by the developer.
This approval does not establish that the prototype enforces the intended policy.

ChatGPT/OpenAI, Ollama, and Anthropic are selected providers, not automatically
installed dependencies. The scripted demo needs none of them. Remote providers
require network access and account authorization; Ollama requires a separately
installed local service and model. Provider selection never authorizes an
installation or a switch in billing. See [usage](../operator/usage.md).

A browser is needed for subscription sign-in. Codex CLI is optional development
tooling, with its own account and terms; it is not an Ipse dependency. Optional
tools must not silently become prerequisites for builds, tests, or operation.
