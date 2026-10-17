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

Follow the [operator guide](docs/operator/usage.md) for login, provider selection,
approvals and chat. ChatGPT subscription is the default; API billing requires
explicit provider selection. `/info` reports the running application and
configured provider/model locally. Review full file/shell arguments before
approving them. Structured [operator questions](docs/operator/usage.md#operator-questions)
accept explicit single-choice, multi-select or text answers; answering grants
no action permission.

Shell commands run with trusted local permissions by default.
`--sandbox native` explicitly requests the Linux/macOS workspace profile and
fails closed when unavailable; see [shell policy](docs/operator/usage.md#shell-policy).
Core/package checks have passed on Linux x86_64 and macOS arm64. Native macOS
enforcement passed locally on macOS 26.7.2 and on macOS 14 CI; detached children
can still survive cancellation with workspace access. Windows is future work.
The [verification record](docs/developer/testing.md#current-evidence-and-next-checks)
identifies tested revisions and remaining platform gates.

### Workspace, skills and configuration

Start from the target directory or use `--cwd`. `/context` shows saved scoped
instructions; `/context refresh` reloads them while idle. Operator and trusted
project/directory JSON settings have explicit precedence, local `ipse config`
inspection and pinned resume identity. See [configuration](docs/operator/configuration.md)
and [workspace instructions](docs/operator/usage.md#workspace-instructions).

Use `$project-orientation` to assess a project's purpose, current changes and
available checks before choosing next steps. Skills are discovered in project
`.agents/skills`, Ipse user `IPSE_HOME/skills`, shared operator `~/.agents/skills`,
then bundled definitions. Shared skills are independent of `IPSE_HOME`; see
[skill provenance and limits](docs/operator/usage.md#skills).

### Sessions and recovery

Automatic compaction retains the original journal. Older-turn summaries use
the selected provider; a long-turn fallback excerpts older settled tool output
without a model request. Use `/diagnostics` or local `ipse diagnose` for byte
accounting and [provider usage facts](docs/operator/usage-accounting.md).
When safe compaction cannot continue, export a reviewed handoff and import it
with `chat --handoff PATH` into a fresh idle session. See
[compaction limits](docs/operator/usage.md#context-compaction) and
[context recovery](docs/operator/recovery.md).

### Extensions and external capabilities

[Extensions](docs/operator/extensions.md) use inert local import, separate
operator trust and explicit session selection. The two shipped hooks are
default-off. Reviewed artifacts can expose typed tools/commands/services and
negotiate state, questions, workflow tools, service composition, contextual
evidence and private visible-text consumption. Prompt delivery has separate
[read-only notifications](docs/operator/extensions.md#prompt-event-subscribers) and
[approved jobs](docs/operator/extensions.md#event-jobs) for before-request recall
or after-turn maintenance.
`/ext` inspects the active catalog
and invokes operator commands.
Effects retain normal approval; cached receipts/projections restore without
replay. Default-off [diagnostic capture](docs/operator/observability.md) supports
bounded local sink workers and separate export authority. Synthetic extension
checks offer optional [dispatcher tracing](docs/developer/observability.md#synthetic-dispatcher-tracing).
Broader lifecycle contracts and the independent package proof remain
[P22 work](docs/plan.md#p22-extension-scaffold-and-lifecycle-hooks).

Explicit stdio and Streamable HTTP [MCP tools](docs/operator/mcp.md) use
`--mcp-config`. Local servers have their own trusted/native sandbox setting;
shell policy does not change it. Network MCP needs a configured endpoint,
verified HTTPS and optional server-specific bearer credentials. Literal
loopback HTTP requires an explicit exception.

Opt-in [local subagents](docs/operator/subagents.md) support serial or bounded
parallel work with separate approvals, journals and explicit model routing.
Use `$research` with configured search/fetch MCP tools for a durable
[source/claim ledger](docs/operator/research.md). No search service or automatic
memory backend is required. The terminal is line-oriented; remote agents and
a full-screen TUI remain unsupported. Use the [documentation map](docs/index.md)
for the authoritative operator, developer and verification guides.

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
