# Arch Linux: run and develop Ipse

Ipse is developed with Elixir/OTP and a small Rust helper. Codex CLI is a
development tool you can use in the checkout; it is not an Ipse dependency.
Ipse's ChatGPT login is separate from your Codex login.

## Install the toolchain

On a current Arch system, update and install official packages:

```sh
sudo pacman -Syu --needed elixir erlang rust base-devel git
elixir --version
rustc --version
```

Arch does not support partial upgrades. The project requires Elixir 1.18+,
OTP 27+, and Rust 1.85+; the prototype was tested with Elixir 1.18.3, OTP 27,
and Rust 1.85.1 on Debian Linux. The Arch source checks passed with Elixir 1.20.4,
OTP 29, and Rust 1.99.0; see [recorded results](../developer/testing.md). Future rolling
toolchain updates still need local validation.
See [Arch's Elixir guide](https://wiki.archlinux.org/title/Elixir) and the
[Elixir](https://archlinux.org/packages/extra/any/elixir/) and
[Erlang](https://archlinux.org/packages/extra/x86_64/erlang/) packages.

```sh
git clone https://github.com/lexlapax/ipse.git
cd ipse
mix local.hex --force
mix local.rebar --force
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
```

Hex fetches the locked MCP/schema packages; Rebar3 builds the approved Telemetry
dependency. Jason is fetched from its pinned Git revision. See the
[dependency inventory](../developer/dependencies.md). Rust uses only the standard library.
Do not run Mix or Ipse with sudo. The demo is scripted, requires no account,
and prints a session ID and temporary workspace. It writes `ipse-demo.txt`,
reads it back, and runs a short shell command.

## Continue development with Codex CLI

The Mac-to-Serenity return checks are recorded in
[testing](../developer/testing.md#p0-closure-on-serenity-2026-10-15).
Use the [native policy](../developer/sandbox.md) for accepted platform limits.

From this checkout, start your installed Codex CLI:

```sh
codex
```

Codex reads the root `AGENTS.md`. A useful first prompt is:

```text
Read AGENTS.md, docs/plan.md, docs/developer/architecture.md, and docs/developer/testing.md.
Run the build, checks, and credential-free demo on this Arch machine.
Fix concrete failures and record the actual toolchain and results.
Then work on the first incomplete P0 item that does not require my account.
Keep Elixir as the core runtime and Rust limited to OS helpers.
Do not print credentials or private transcripts. Ask me to perform browser
sign-in when a live account check is needed; do not claim it passed from fixtures.
```

Codex must be able to fetch the dependency and open local sockets for Mix and
HTTP fixture tests. If its sandbox blocks these, allow the required command
through its normal permission flow or run that check in your local terminal.
Do not disable certificate verification or change global Codex permissions.
No project-specific Codex config is required.

## Run Ipse

Continue with the [operator guide](usage.md) for subscription sign-in, a scratch
coding session, approvals, other providers, and state management. Use
[troubleshooting](troubleshooting.md) for build, login, model, and session errors.
The optional `--sandbox native` profile needs Linux 6.12+/Landlock ABI 6 and
permitted unprivileged namespaces. See [shell policy](usage.md#shell-policy);
an unavailable profile fails closed instead of running with broader permissions.

## Bundled releases

A release includes Erlang, Elixir application code, and the native helper.
Extract the archive and run `./ipse demo`; match its OS, architecture, and libc
requirements. The Arch archive passed help, demo, and bundled helper checks on
the recorded host; this does not establish portability to another Linux ABI.
Developers building
and validating an archive should follow the
[release verification procedure](../developer/testing.md#release-check).
