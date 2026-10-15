# Arch Linux: run and develop Ipse

Ipse is developed with Elixir/OTP and a small Rust helper. Codex CLI is a
development tool you can use in the checkout; it is not a Ipse dependency.
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
and Rust 1.85.1 on Linux. Arch's rolling versions still need local validation.
See [Arch's Elixir guide](https://wiki.archlinux.org/title/Elixir) and the
[Elixir](https://archlinux.org/packages/extra/any/elixir/) and
[Erlang](https://archlinux.org/packages/extra/x86_64/erlang/) packages.

```sh
git clone https://github.com/lexlapax/ipse.git
cd ipse
mix local.hex --force
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
```

Hex bootstraps Mix dependency handling; the sole direct dependency, Jason,
is fetched from its pinned Git revision. Rust uses only the standard library.
Do not run Mix or Ipse with sudo. The demo is scripted, requires no account,
and prints a session ID and temporary workspace. It writes `ipse-demo.txt`,
reads it back, and runs a short shell command.

## Continue development with Codex CLI

From this checkout, start your installed Codex CLI:

```sh
codex
```

Codex reads the root `AGENTS.md`. A useful first prompt is:

```text
Read AGENTS.md, docs/plan.md, docs/architecture.md, and docs/testing.md.
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

## Use your ChatGPT subscription first

```sh
./bin/ipse login
./bin/ipse status
```

Open the printed URL in a browser on this same machine and complete consent.
The callback binds to `127.0.0.1` on an ephemeral port. Live account eligibility,
model access, refresh, and inference need your validation; fixture tests alone
cannot establish them. There is no silent fallback to API billing.

Try a real turn in a scratch workspace, reviewing proposed mutations:

```sh
IPSE_TRY_DIR=$(mktemp -d)
./bin/ipse chat --cwd "$IPSE_TRY_DIR"
```

Ask: `Create hello.exs that prints hello, run it, and summarize the result.`
Approve the file and shell calls if they match your request. The default model
is `gpt-6.1-sol`; use `--model NAME` for one available to your account. Shell
execution has your OS permissions; it is not sandboxed. `/cancel` stops active
work and `/exit` leaves. Use `./bin/ipse logout` to clear the saved login.

## Other providers and state

Use `--provider openai` with `OPENAI_API_KEY`, `--provider ollama` with a running
local Ollama service, or `--provider anthropic` with `ANTHROPIC_API_KEY`.
See the [README](../README.md) for commands. Supply secrets through your normal
secret manager; never put them in tracked files or a Codex prompt.

Data defaults to `~/.ipse`. `IPSE_HOME` changes the whole application
home; `--state-dir` changes journals only. Keep the same home when resuming:

```sh
./bin/ipse sessions
./bin/ipse chat --resume SESSION_ID
./bin/ipse skills --cwd /path/to/project
```

For an isolated smoke test that cannot touch your account's saved login:

```sh
IPSE_HOME=$(mktemp -d) ./bin/ipse demo
```

## Troubleshooting and packaging

- `mix` or `rustc` missing: check the installed packages and your `PATH`.
- Helper missing/incompatible: run `./scripts/build.sh` on this machine.
- `:eperm` while Mix starts or tests bind sockets: check sandbox permissions.
- Provider rejects a model: select an available model explicitly; check your
  account's plan and limits. Do not change to API billing unintentionally.
- Session already open: close its other Ipse process. Do not delete the
  lock file; OS locks release when their process exits.
- Inspect errors locally; redact credentials and transcript content before
  sharing logs. Never share `~/.ipse/auth/`.

`./scripts/package.sh` builds a release for the current machine. Extract its
archive elsewhere and run `./ipse demo`. The bundled runtime still depends
on compatible OS libraries; an archive built on another Linux distribution is
not universally portable. Building from source is the first Arch validation path.
When distributing a release, set `IPSE_NOTICES_DIR` to a directory containing
the bundled toolchain's license notices; the packager copies these into `licenses/`.
