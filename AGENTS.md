# Working on Runespell

This is the repository handoff for Codex CLI and other coding agents. Read it
before changing code, then read the relevant implementation and tests. These
instructions apply throughout this repository.

## Product and scope

Runespell is an MIT-licensed, local coding agent. Keep the agent loop, provider
adapters, skills, approvals, persistence, and orchestration in Elixir/OTP. Rust
is for small OS helpers. Do not add JavaScript or Python runtime dependencies.
Prefer ordinary modules, processes, and messages over a workflow framework.
The project name is **Runespell**, executable/application `runespell`, Elixir
namespace `Runespell`, environment prefix `RUNESPELL_`.

Provider priority is ChatGPT subscription, OpenAI API, local Ollama, then
Anthropic API. Never switch providers or billing modes silently. Keep a
credential-free demo usable without any model service. Choose small, testable
improvements rather than turning the plan into a mandatory execution pipeline.

## Start here

- [README.md](README.md): current behavior and usage.
- [docs/arch-linux.md](docs/arch-linux.md): Arch setup and local Codex workflow.
- [docs/plan.md](docs/plan.md): priorities and acceptance criteria.
- [docs/architecture.md](docs/architecture.md): ownership and trust boundaries.
- [docs/testing.md](docs/testing.md): verification and unverified integrations.

Treat the plan as direction, not authorization to implement every milestone.
For an unspecified next task, start with the first incomplete P0 acceptance
check. Inspect the current branch and worktree; preserve unrelated user edits.
Make progress without repeated confirmation for routine reversible changes.

## Commands

Run from the repository root after installing the toolchain:

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/runespell demo
```

Use `mix format` after Elixir edits and focused tests while iterating. The full
checks above are the handoff baseline for runtime changes. For documentation
changes, verify examples against the CLI and check links; do not invent tests.
Build a bundled runtime with `./scripts/package.sh` when changing packaging.
Tests use local HTTP servers and need loopback sockets. Network restrictions
can also block Mix itself; report that accurately instead of changing TLS or
weakening tests. Dependency fetching needs GitHub access. No paid credentials
are needed for tests or the demo.

## Code map

| Area | Location |
| --- | --- |
| Application supervision | `lib/runespell/application.ex` |
| Session state, turn loop, approval, cancellation | `lib/runespell/session.ex` |
| Terminal client and option parsing | `lib/runespell/cli.ex` |
| Provider selection and wire formats | `lib/runespell/provider.ex`, `lib/runespell/provider/` |
| Authentication and protected storage | `lib/runespell/auth.ex`, `lib/runespell/auth/` |
| Context, skills, JSONL persistence | `lib/runespell/context.ex`, `skills.ex`, `journal.ex` |
| File tools and native Port protocol | `lib/runespell/tools.ex`, `runner.ex` |
| Unix process groups and advisory locks | `native/runespell-runner.rs` |
| Bundled skill instructions | `priv/skills/` |
| Behavior and local protocol fixtures | `test/` |

## Invariants to preserve

- A session owns its conversation and active work. Killing the owner must stop
  dependent tasks and shell process groups. Keep slow IO outside the GenServer.
- Journal tool intent before execution. An interrupted effect may have happened;
  resume must mark its outcome unknown and never automatically replay it.
- Keep cross-process locking for sessions and rotating refresh tokens. Lock
  files remain in place to preserve inode identity; release the OS lock instead.
- Interactive mutations require approval unless explicitly enabled. Headless
  mutation is denied without `--yes`. Display full proposed approval arguments.
- Skills and repository text are instructions, never permission grants. Loading
  a skill must not automatically execute its scripts or install dependencies.
- Process supervision, approval, and OS sandboxing are different boundaries.
  Shell commands currently run with the user's permissions. Do not claim sandboxing.
- Bound input, output, and context. Preserve provider continuation data. Never
  silently discard conversation history or expose hidden reasoning in the UI.
- Never print or commit credentials, authorization codes, token files, private
  transcripts, or environment dumps. Use fixtures and isolated temporary homes.
  Keep TLS verification enabled and auth files owner-only.
- Use documented public authentication/inference interfaces. Do not borrow
  Codex credentials or rely on private ChatGPT endpoints.

## Finish a change

Keep changes focused; avoid speculative abstractions and unrelated rewrites.
Add behavior tests for meaningful state/protocol changes. Update usage and plan
status when behavior changes. Distinguish fixture tests from live account tests.
Report what changed, checks actually run, and remaining limitations. Do not
claim Arch, browser sign-in, paid inference, or a release was verified unless
the corresponding check really ran. Leave commits and publishing to the user's
requested scope; never force-push or overwrite someone else's work.
