# Choose and maintain dependencies

Use this chapter when a change needs a package, executable, service or build tool.
You will decide whether an existing adapter is sufficient, document the complete
dependency cost, and verify the result from both source and an installed runtime.
The inventories below are the authoritative current package and host requirements.

## Start with the existing boundary

Find the owner of the requirement in [the architecture](architecture.md). For
example, a new note-ranking function belongs in a memory extension. It can use the
existing bounded state/CAS host calls without installing a database. A provider
stream change should reuse `Ipse.Provider.Transport` and `Ipse.HTTP`, which own
bounded responses, TLS and request-specific client lifetime.

Before adding common validation, transport or persistence machinery, inspect the
existing Ipse adapter and maintained Elixir/OTP packages. Reuse a suitable
implementation behind a small adapter. Explain a concrete shortcoming when custom
code is necessary; "we need more control" is not enough.

Work through this example before writing a new schema checker:

```sh
rg 'validate_arguments|validate_object' lib/ipse/json.ex
mix test test/ipse/json_test.exs
```

`Ipse.JSON` reuses JSONSchex for admitted JSON Schema validation. Ipse still
owns closed keyword/byte/depth bounds and disables remote loading. A second
validator would need to preserve the same boundary and keep two definitions in
sync. Extend the small adapter only after checking its existing supported subset.

## Make the adoption decision explicit

For each dependency, record its purpose, runtime/build/test/CI scope, version or
exact source, transitive requirements and license. Review distribution notices,
platform support, endpoint/credential requirements and installed-runtime behavior.
Update this inventory alongside declarations and lockfiles.

Use Elixir for repository scripts where possible, then Bash/portable shell or
Ipse's existing Rust helper for the OS facilities it owns. New dependencies outside
Elixir or Rust packages require explicit developer approval before adoption. This
includes external commands, services and CI actions, even when used only during
development or tests. Record the approval and why existing supported options were
insufficient. Elixir/Rust packages still require focused justification and checks.

A target project may use another stack. That project's dependencies are not
Ipse's implementation graph. Likewise, importing an extension artifact does not
install its build toolchain; the author must package compatible executable code
and its own license/dependency inventory.

## Runtime and toolchain inventory

| Dependency | Version/source | Scope and purpose | License |
| --- | --- | --- | --- |
| Elixir and Mix | Elixir 1.18+; `mix.exs` requires `~> 1.18` | Core implementation, build, release, ExUnit tests, scripts; knowledge workers use standard-library `JSON` for binary encoding and Elixir null handling | Apache-2.0 |
| Erlang/OTP and ERTS | OTP 27+; system toolchain or bundled release | VM, OTP supervision, crypto, public-key/TLS, filesystem and process APIs | Apache-2.0 with component notices |
| Jason | Git tag `v1.4.4`, commit `926d2ac6cc0271b9a7079b2ec16ae0cf802f7963` in `mix.lock`; direct override for shared package requirements | JSON for HTTP, native protocol, journals and bounded SDK validation; read-only evaluation audit children include its existing runtime path | Apache-2.0 |
| MCP Elixir SDK | Hex `mcp_elixir_sdk` 1.1.0, pinned in `mix.exs` and `mix.lock` | MCP 2025-11-25 client handshake, request matching, and protocol types; Ipse supplies bounded stdio/HTTP transports and reuses the SDK's SSE parser | MIT |
| elixir_uuid | Hex 1.2.1, transitive SDK dependency, locked in `mix.lock` | SDK UUID utilities | Apache-2.0 |
| JSONSchex | Hex `jsonschex` 0.10.0, pinned in `mix.exs` and `mix.lock` | JSON Schema Draft 2020-12 validation behind Ipse's bounded keyword allowlist; no remote loader | MIT |
| ex_json_pointer | Hex 0.8.0, transitive JSONSchex dependency, locked in `mix.lock` | JSON Pointer handling inside schema compilation | MIT |
| Req and Plug | Hex `req` 0.7.5, `plug` 1.20.3, pinned in `mix.exs` and `mix.lock` | The SDK 1.1.0 advertises optional HTTP dependencies but unconditionally references their modules; required for successful compilation on Elixir 1.20. Ipse also reuses Req for bounded opt-in HTTP MCP; no HTTP server is enabled | Apache-2.0 |
| Finch | Hex 0.24.0, locked | All-status bounded inference/authentication streaming and Req/MCP HTTP pools; private HTTP/1 request pools with owned teardown | MIT |
| Mint | Hex 1.11.0, locked | Finch transport with default certificate/hostname verification and a header bound | Apache-2.0 |
| HPAX | Hex 1.1.0, locked | Mint HTTP/2 compression support | Apache-2.0 |
| MIME | Hex 2.0.7, locked | Req/Plug MIME utilities | Apache-2.0 |
| NimbleOptions | Hex 1.1.1, locked | Finch option validation | Apache-2.0 |
| NimblePool | Hex 1.1.0, locked | Finch process pooling | Apache-2.0 |
| PlugCrypto | Hex 2.2.1, locked | Plug cryptographic helpers; fixes CVE-2026-105963 | Apache-2.0 |
| Telemetry | Hex 1.4.2, locked; developer approved on 2026-10-15 | Erlang/BEAM events used by Finch/Plug; adds no outside runtime service | Apache-2.0 with upstream NOTICE |
| Rust toolchain and standard library | Rust 1.85+; `dev/build-native.sh` invokes `rustc --edition=2021` | Build the OS helper; no third-party Cargo packages | MIT OR Apache-2.0 |
| Ipse native helper | `native/ipse-runner.rs`, `native/ipse-process-group.rs`, `native/ipse-stdio.rs`, `native/ipse-linux-sandbox.rs`, `native/ipse-macos-sandbox.rs`, `native/ipse-measure.rs`, `native/ipse-sequence.rs`, `native/ipse-bound.rs`, `native/ipse-listener.rs`, `native/ipse-file-copy.rs`, `native/ipse-environment.rs`, compiled as `priv/ipse-runner` | Runtime anchored process groups, advisory locks, bidirectional OS pipes, optional Linux user/mount/network/PID namespaces, private descriptor procfs, Landlock/seccomp and macOS signed App Sandbox worker policies; optional owned cgroup measurement, execution-bound serial stages, direct-child loopback-listener observations, retained-descriptor regular-file copies and selected child-environment forwarding; used by tests | Apache-2.0 (project source) |

OTP libraries ship with OTP. The application starts `logger` and `ssl`;
authentication also uses crypto/public-key facilities. HTTP uses owned Finch
pools without starting OTP's `inets` application. Req/Plug satisfy the SDK's
compile-time references; Finch/Mint also serve bounded provider/authentication
transport. Optional Bandit, Decimal and IDNA dependencies are not enabled. No MCP
listener starts automatically. Ipse requires no Node, JavaScript or Python runtime.

The 2026-10-23 [PlugCrypto advisory](https://github.com/elixir-plug/plug/security/advisories/GHSA-ffw9-w85g-f2vh)
affects versions before 2.2.1: wrong-typed cryptographic arguments can expose a
secret key base in stack traces. Ipse has no direct Plug cryptography calls or
enabled Plug server; the dependency arrives through the SDK's compile-time
requirements. The locked patch release removes the vulnerable version from new
builds rather than relying on that current lack of reachability. Recheck this
boundary before adding a Plug server or cryptographic caller.

## Host and build inventory

| Dependency | Scope and reason | Source/license notes |
| --- | --- | --- |
| Unix OS and C library | Runtime process groups, advisory locks, filesystem, native runtime ABI | Host distribution; libc varies by platform. Match release OS/architecture/libc |
| OpenSSL and system CA trust | OTP TLS and verified HTTPS provider/auth connections | Host/toolchain distribution; preserve its version-specific notices |
| `/bin/sh` | Runtime shell tool and source/release launchers; optional native Bash compatibility probes use the already-installed host Bash, required by those project scripts, with no installation or bundled Bash runtime | Host shell implementation/licenses vary; Bash uses GPL-3.0-or-later for the recorded version |
| C linker/toolchain | Link the Rust helper; compile synthetic loader probes for native enforcement tests (`/usr/bin/cc` on Linux, `/usr/bin/clang` on macOS) | Arch `base-devel` or macOS build toolchain; versions/licenses supplied by distribution |
| Git | Existing development tool for pinned Jason fetching and repository work; evaluation seals inspect clean commits/trees and focused tests create synthetic repositories. Sealing/verification uses the declared development runtime | Host Git package, GPL-2.0 |
| Standard Unix utilities | Scripts use `dirname`, `mkdir`, `cp`, `chmod`, `rm`, `uname`, and `tr`; setup examples use `mktemp`; helper verification uses `sleep`, and tests use `head`/`tr` and `kill -0` for process-exit observation. Existing bundled OTP launchers/fresh-release checks also need `basename`, `cut`, `sed`, `cat`, `grep`, `readlink`, `expr`, `awk`, and `id`; the package verifier makes that utility-only PATH explicit | Existing host utility implementation/licenses vary, commonly GNU coreutils plus GNU sed/grep and awk on Linux; OS-supplied equivalents on macOS |
| `tar`, gzip support, `getconf` | Packaging archive and Linux libc identification | Host distribution; `getconf` is a libc utility. `getconf` failure falls back to `system-libc` naming |
| Hex bootstrap | Documented `mix local.hex --force` setup step; fetch and verify locked MCP/schema packages | [Hex](https://github.com/hexpm/hex), Apache-2.0; Jason itself is fetched through Git |
| Rebar3 | Build Telemetry's Erlang code during Mix dependency compilation; developer approved on 2026-10-15 | Standard BEAM build tool, [upstream](https://github.com/erlang/rebar3), Apache-2.0 |
| systemd user-service tools | Optional Linux exact-memory benchmark launch and cleanup only; `systemd-run` starts fresh owned transient services inside the user's delegated hierarchy, and `systemctl --user` inspects or stops only those named services. Developer approved on 2026-10-19. No installation, existing service changes, mandatory runtime or ordinary-test requirement | Host distribution, [systemd](https://github.com/systemd/systemd), LGPL-2.1-or-later; not bundled. Linux cgroup v2 memory-controller capabilities are checked separately. Record the actual host version with each result; the [collector record](../archive/2026-10-19-p27-knowledge-packages/aggregate-memory-native.md#direct-final-source-evidence) retains the tested version |

A bundled release contains ERTS, Elixir code, the locked runtime packages and the
helper. It still needs compatible OS libraries and `/bin/sh`. On Linux, native
mode also needs Landlock ABI 6+ and the permitted namespace/mount facilities. On
macOS, the system `codesign` utility signs and verifies generated App Sandbox
workers; it needs no personal signing certificate. Unavailable enforcement fails
closed. See [sandbox implementation](sandbox.md).

Telemetry/Rebar3 and macOS's built-in `codesign` have existing developer approval.
Their scopes are the BEAM dependency build chain and fixed worker signing and
verification, respectively. The [preserved adoption record](../archive/2026-10-18-before-manual-rewrite/docs/developer/dependencies.md)
contains the original approvals and one-off interoperability investigations.
Those optional investigation tools are not mandatory runtime or CI requirements.

The optional aggregate-memory verification uses an existing systemd user manager
to start a fresh process inside a delegated hierarchy. A writable target directory
alone does not grant cross-delegation migration. The approved user-service launcher
supplies entry without moving existing processes or changing ancestor controllers.
The native counter requires the documented cgroup v2 facilities. It is independent
of hostname and distribution package version. Kernel accounting stays in Ipse's
Rust helper; Elixir owns evaluation semantics. The
[design record](../archive/2026-10-19-p27-knowledge-packages/aggregate-memory-design.md)
preserves the design rationale. [Measurement](measurement.md) defines the current
populations, accounting contract and verification.

## CI inventory

The [checks workflow](../../.github/workflows/ci.yml) uses GitHub Actions with
`ubuntu-latest` and `macos-14` runners. These hosted services are CI-only inputs.

| Action | Pinned source | Purpose and license |
| --- | --- | --- |
| checkout | `actions/checkout@11d5960a326750d5838078e36cf38b85af677262` | Checkout the candidate repository; MIT |
| setup-beam | `erlef/setup-beam@54075bcc5e249e4758d363f27d099f55d843f124` | Supply Elixir 1.18/OTP 27 for floor compatibility; MIT |
| rust-toolchain | `dtolnay/rust-toolchain@b725eda525362e7cf34af9a7243cac1e3f01a7ec` | Select stable Rust; MIT for the action, separate compiler/standard-library notices |
| GitHub CLI (`gh`) | Preinstalled GitHub-hosted runner version, a rolling image input; record the actual version with release evidence | Create/recover drafts, upload/re-download verified assets, and fetch exact-version upstream runtime notices in CI/release jobs with step-scoped `GITHUB_TOKEN`; MIT. Developer approved the release-workflow dependency on 2026-10-23 ([decision D3](../archive/2026-10-23-p28-p29-design/p28.md#decisions)); no additional action or runtime dependency |

Runner images and stable toolchain channels remain rolling inputs. Record their
actual versions with results. Pin any external action to a full commit and review
updates. Introducing another action requires the same outside-language dependency
approval as a local executable.

```sh
elixir dev/check-ci-policy.exs
```

That command rejects mutable action selectors. It does not audit an action's
implementation, license or hosted service terms.

Packaging writes and verifies SHA256 sidecars with the already required OTP
crypto implementation, streaming the archive instead of adding a platform checksum
executable to build/CI requirements. Manual download checks use the platform's
`sha256sum` (Linux/coreutils) or `shasum` (macOS/Perl distribution); these are
operator commands rather than new harness dependencies. The portable release
launcher reuses the already inventoried `readlink` utility.

Before packaging, hosted jobs use that same approved `gh` executable to retain
the running Elixir/OTP versions' upstream license/notice files, including modern
`LICENSES/` layouts. The collector accepts only the two official repositories and
exact release tags, checks Git blob identities and bounded text, and records
source references and SHA256s in `runtime-notices.json`. Downloaded text is not
executed. The token is scoped to the collection step; only the notice-directory
path is carried into later steps. Custom toolchain distributors still provide
their additional notices through `IPSE_NOTICES_DIR`.

The workflow also runs `elixir dev/check-docs.exs` using the existing Elixir/OTP
and Git toolchain. It checks local documentation links, headings, JSON examples,
manual rules and preserved snapshot hashes without executing example commands.

## Verify an update

Review the declaration and lockfile together, then build and exercise the affected
behavior. Check transitive applications and notices, not just the top-level name.

```sh
mix deps
./dev/build.sh
mix compile --warnings-as-errors
mix test test/ipse/json_test.exs
```

The focused command above is an example for a schema-adapter change. Choose the
actual affected fixture for another dependency. Run the [source baseline](testing.md#run-the-complete-source-baseline)
for runtime changes. Keep the source/build output fixed while checks are active.

If the dependency affects worker or runtime paths, also build the package and
run its extracted verifier. Before distribution, provide notices for the exact
bundled Erlang/Elixir toolchain via `IPSE_NOTICES_DIR`. The packager copies locked
package notices and supplied toolchain notices into `licenses/`; inspect that
folder in the extraction. [Third-party notices](../../THIRD_PARTY_NOTICES.md) and
[release verification](testing.md#verify-documentation-and-packaging-at-their-own-boundaries) describe the
remaining distribution obligations.

## Keep optional services optional

Providers, MCP servers, source debuggers and retrieval engines are selected
integrations, not silently installed dependencies. Configuration must make the
service, endpoint, credentials and billing choice explicit. The deterministic demo
and ordinary tests require no model service. A browser is needed for subscription
sign-in; an operator's separate coding assistant is not part of Ipse's graph.

The optional Grok integration was explicitly requested on 2026-10-24 for delivery
before external audit. Its sources are the documented xAI Responses
service at `https://api.x.ai/v1` and registered-client OAuth issuer at
`https://auth.x.ai`. Models/API contracts are externally versioned and change;
record the requested/reported model and dated verification, rather than assigning
the service a package version or open-source license. Access uses the provider's
commercial service terms; no xAI SDK or third-party source is bundled. API-key
team billing and subscription access are separate explicit selections. An approved
Ipse OAuth registration remains an external prerequisite, not a packaged dependency.
The [research and scope](../archive/2026-10-24-xai-provider-research/index.md)
records source links and the approval. Existing Finch/OTP, bounded JSON, private
files and retained native locks supply the implementation; no new package,
executable or language runtime is added. The small provider-owned device polling
state uses RFC 8628 while reusing those existing transport/storage owners.

The optional owned-model evaluation uses an operator-selected Ollama distribution
and local model cache. It copies the declared executable, helper libraries and
selected manifest/blob closure into fresh private files. No installation,
download or service switch occurs. Ollama's source is
[MIT-licensed](https://github.com/ollama/ollama/blob/main/LICENSE); record the exact
runtime version, file hashes and model licenses with the execution. The synthetic
service tests use a repository Rust fixture and need neither Ollama nor weights.
CPU and explicit NVIDIA benchmark selections keep this service optional and
unbundled. A GPU selection uses the operator's existing compatible driver and
the declared Ollama libraries; Ipse installs no driver or CUDA toolkit.

The optional NVIDIA benchmark also uses the existing NVIDIA driver and its
`nvidia-smi` inspection utility to identify a physical GPU. The source is the
operator's installed NVIDIA or distribution driver package. There is no pinned
project-wide driver version: record the exact package version, running driver
version and inspection-tool version with the execution. The binary driver and
utilities use the package's NVIDIA license and third-party notices; retain those
exact notices rather than assigning Ollama's MIT license to them. NVIDIA publishes
its [Linux driver license](https://www.nvidia.com/en-in/drivers/nvidia-license/linux/).
These host components remain outside Ipse's distribution. The user authorized
using the repaired existing GPU for the comparison on 2026-10-21; installing or
adding other external tooling still requires approval.

Report real placement separately from the kernel charged-RAM metric, which
excludes VRAM.

For a new retrieval adapter, start with a synthetic source and the existing SDK.
Measure the requirement before selecting a database, encoder or remote service.
See [knowledge extension development](knowledge-extensions.md). Do not turn an
optional example into a prerequisite for building or operating the harness.
