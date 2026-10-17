# Ipse

A general-purpose local AI harness built with Elixir/OTP, with local skills,
resumable conversations, and a small Rust process supervisor. MIT licensed. No JavaScript or Python runtime.

**Prototype 0.1:** a terminal application and an embeddable OTP session API,
currently focused on coding and project workflows. The implementation language
does not restrict the languages or runtimes of projects handled by Ipse.
The agent loop, providers, skills, approvals, and journal are Elixir. Rust owns
shell and configured MCP process groups and advisory file locks. This is an independent implementation
informed by lessons from [Loopex](https://github.com/lexlapax/loopex) and
[rs-llmspell](https://github.com/lexlapax/rs-llmspell).

The name comes from Latin *ipse* (the emphatic “self”), inspired by Douglas
Hofstadter's *I Am a Strange Loop*. See [why Ipse](docs/naming.md) for the
sources and the connection to continuity and feedback.

## Build and try it

Source prerequisites: Elixir 1.18+ on Erlang/OTP 27+, Rust 1.85+, a C linker, and
Git. Linux and macOS are targeted; Linux is tested in the development environment.
No Cargo packages are required. Jason is pinned to a Git tag and commit in mix.lock.

```sh
git clone https://github.com/lexlapax/ipse.git
cd ipse
mix local.hex --force
mix local.rebar --force
./scripts/build.sh
./bin/ipse demo
```

If you received a source archive, extract it and start at `./scripts/build.sh`.
The demo needs no credentials. It loads the review skill and its checklist, creates and reads
`ipse-demo.txt` in a new temporary directory, and runs `printf`. It is a
deterministic fixture, **not a model**. The printed session ID can be resumed.

For a bundled platform release, extract the archive and run `./ipse demo`.
It includes Erlang, Elixir application code, and the native helper; no toolchain is
needed. Match the OS/architecture and libc requirements in the release filename.

## Use Ipse

Follow the [operator guide](docs/operator/usage.md) for ChatGPT subscription
sign-in, other providers, approvals, skills, session resume, and logout.
ChatGPT subscription is the default; API billing always requires explicit provider
selection. In chat, `/info` shows the running application version and configured
provider/model without calling a model. Review proposed file and shell calls before approving them.
Interactive chat also supports validated single-choice, multi-select and free-text
[operator questions](docs/operator/usage.md#operator-questions), with explicit
answers and resumable waiting; answers grant no action permission.
Shell commands use trusted local execution by default. `--sandbox native` requests
the opt-in Linux or macOS workspace sandbox and fails closed when unavailable; see
[shell policy](docs/operator/usage.md#shell-policy).
Core and bundled-release checks passed on Linux x86_64 and macOS arm64;
native macOS enforcement also passed on macOS 26.7.2 locally and macOS 14 CI, both arm64. Detached
children may survive cancellation with workspace access. Windows is future work.

Automatic context compaction retains the original journal. Older-turn summaries
use the selected provider; a long-turn fallback excerpts older settled tool output
without a model request; see [operation and limits](docs/operator/usage.md#context-compaction).
Use `/diagnostics` or local `ipse diagnose` for context byte accounting and
[provider usage facts](docs/operator/usage-accounting.md). For an
explicit reviewed recovery into a fresh idle chat, export a bounded handoff note
and import it with `chat --handoff PATH`; see [context recovery](docs/operator/recovery.md).
Run from any working directory or use `--cwd`; `/context` shows applicable saved
instructions and `/context refresh` reloads them while idle. See
[workspace instructions](docs/operator/usage.md#workspace-instructions).
Operator and trusted project/directory JSON settings support explicit precedence,
local `ipse config` inspection and resume checks; see [configuration](docs/operator/configuration.md).
`ipse extension import PATH` and `ipse extension inspect DIGEST` provide inert,
pinned local artifact installation. Scoped trust/selection can enable default-off
prompt annotations and completed-answer formatting in separate Elixir workers.
Reviewed artifacts can also declare schema-checked tools, commands and standalone
services; `/ext` inspects the active catalog and invokes operator commands.
Explicit host-state capabilities support scoped revision-checked storage with
separate write approval; no automatic memory adapter is enabled.
Trusted extensions can ask structured questions and resume from bounded checkpoints
only after explicit answers; idle recovery never starts their callbacks.
An explicit workflow-tool capability reuses bounded file/shell tools, workspace
instruction checks and normal mutation approval.
Typed service requirements use explicit operator bindings and owned value jobs;
unknown routes, schema mismatches and cycles refuse activation.
Resume pins code/configuration and restores committed projections without replay.
See [extensions](docs/operator/extensions.md) for bounds and current SDK scope.
Explicit context publications support bounded assertions or receipt-backed
excerpts, with cached request snapshots and separate mandatory instructions.
Use `$project-orientation` to assess a repository's purpose, current changes,
and available checks before choosing next steps; see
[project assessment](docs/operator/usage.md#working-with-the-agent).
Skills are discovered without copying from project `.agents/skills`, Ipse user
`IPSE_HOME/skills`, shared operator `~/.agents/skills`, then bundled definitions
(in that precedence order). The shared home is independent of `IPSE_HOME`;
see [skill limits and provenance](docs/operator/usage.md#skills).
Explicit stdio and Streamable HTTP MCP tools are available through `--mcp-config`; see
[configuration and trust boundaries](docs/operator/mcp.md).
Local MCP servers default to trusted execution; a per-server `"sandbox": "native"`
requests the fixed native workspace policy independently of shell `--sandbox`.
Network MCP requires an explicit endpoint, verified HTTPS, and optional server-specific
bearer credentials; literal loopback HTTP needs an explicit exception.
The MCP allowlist can include exact tools, resource URIs, and prompt names;
review their metadata and approval requests as untrusted data. See the
[MCP operator guide](docs/operator/mcp.md) for limits and platform evidence.
Opt-in local delegation is available with `--subagents`; it runs serial children
by default or two parallel children with `--subagent-concurrency 2`,
in the same workspace with separate journals and parent-mediated approvals.
[Named profiles and task roles](docs/operator/model-profiles.md) can route bounded
children to an explicitly configured provider/model, including local Ollama. See [local subagents](docs/operator/subagents.md) for limits and
recovery behavior. There is no full-screen TUI, remote-agent, or Windows support.
See [runtime limits](docs/operator/usage.md#runtime-and-limits)
and [architecture](docs/developer/architecture.md) for details.

Use `$research` with explicitly configured search/fetch MCP tools for bounded
research and a durable source/claim ledger; see [research setup](docs/operator/research.md).
No external search service is embedded or required.

Find setup, operation, development, and verification guidance in the
[documentation map](docs/index.md).

## Development

For Arch Linux and a local Codex CLI handoff, start with
[docs/operator/arch-linux.md](docs/operator/arch-linux.md). Coding agents should read
[AGENTS.md](AGENTS.md). The [plan](docs/plan.md),
[architecture](docs/developer/architecture.md), and [verification guide](docs/developer/testing.md)
describe the next work and current limits.

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
./scripts/package.sh
```

The tests exercise local HTTP fixtures, fragmented streaming/tool calls, skill
selection, file edits, approvals, cancellation, journaling/recovery, OAuth checks,
and real Rust process cleanup. No paid model credentials are required.

Keep the core small: ordinary modules and OTP primitives, behavior-driven tests,
and short design notes when a consequential tradeoff needs explanation. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). Dependencies and bundled Erlang/Elixir runtimes retain their own
licenses; packaged releases include third-party notices.
