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
| Ipse native helper | `native/ipse-runner.rs`, compiled as `priv/ipse-runner` | Runtime process groups and advisory locks; used by tests | MIT (project source) |

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
| Standard filesystem/text utilities | Scripts use `dirname`, `mkdir`, `cp`, `chmod`, `rm`, `uname`, and `tr`; setup examples use `mktemp`; helper verification uses `sleep`, and tests use `head`/`tr` | Existing host utility implementation/licenses vary, commonly GNU coreutils on Linux |
| `tar`, gzip support, `getconf` | Packaging archive and Linux libc identification | Host distribution; `getconf` is a libc utility. `getconf` failure falls back to `system-libc` naming |
| Hex bootstrap | Documented `mix local.hex --force` setup step | [Hex](https://github.com/hexpm/hex), Apache-2.0; Jason itself is fetched through Git, not a Hex package |

Bundled releases include ERTS, Elixir code, Jason, and the helper; they still need
compatible OS libraries and `/bin/sh`. Toolchain license notices and
`IPSE_NOTICES_DIR` handling are described in the
[release check](testing.md#release-check). Record actual versions and tested
platforms in [verification results](testing.md#current-evidence-and-next-checks).

## Existing CI dependencies

The [checks workflow](../../.github/workflows/ci.yml) uses GitHub Actions on
`ubuntu-latest`, [actions/checkout@v4](https://github.com/actions/checkout),
[erlef/setup-beam@v1](https://github.com/erlef/setup-beam) (Elixir 1.18 / OTP 27),
and [dtolnay/rust-toolchain@stable](https://github.com/dtolnay/rust-toolchain).
These are CI-only hosted services/actions,
not Ipse runtime packages. Their sources are the named GitHub repositories;
checkout, setup-beam, and the rust-toolchain action use MIT. The Rust compiler
and standard library have separate MIT OR Apache-2.0 licensing.
The runner image and action tags are rolling inputs; record changes and obtain
developer approval before introducing additional actions or external CI tools.

## Optional integrations

ChatGPT/OpenAI, Ollama, and Anthropic are selected providers, not automatically
installed dependencies. The scripted demo needs none of them. Remote providers
require network access and account authorization; Ollama requires a separately
installed local service and model. Provider selection never authorizes an
installation or a switch in billing. See [usage](../operator/usage.md).

A browser is needed for subscription sign-in. Codex CLI is optional development
tooling, with its own account and terms; it is not an Ipse dependency. Optional
tools must not silently become prerequisites for builds, tests, or operation.
