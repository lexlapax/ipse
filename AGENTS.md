# Working on Ipse

This is the repository handoff for Codex CLI and other coding agents. Read it
before changing code, then read the relevant implementation and tests. These
instructions apply throughout this repository.

## Product and scope

Ipse is an Apache-2.0-licensed, general-purpose local AI harness. The current prototype
has coding-oriented tools and workflows. Keep the agent loop, provider
adapters, skills, approvals, persistence, and orchestration in Elixir/OTP. Rust
is for small OS helpers. The developer-approved PDF exception permits a narrowly
scoped Rust parser when maintained Elixir/Erlang options are unsuitable; keep
orchestration and knowledge policy in Elixir/OTP. Evaluate and inventory the
specific library and its licenses; this does not approve transitive non-Rust
dependencies. See the [recorded decision](docs/archive/2026-10-26-p30-p31-plan-review/index.md).
Do not add JavaScript or Python runtime dependencies.
Prefer ordinary modules, processes, and messages over a workflow framework.
Evaluate existing Elixir/OTP modules and maintained Mix packages before writing
common protocol or validation machinery. Reuse suitable implementations behind
small Ipse adapters; document concrete reasons when custom code is necessary.
Use Elixir for scripts created for development, staging, helpers, and tests
wherever possible. If Elixir is unsuitable, use Bash or portable shell; use
Ipse's Rust helper binary for the OS facilities it owns. Do not introduce Python
or JavaScript scripts or tooling when these supported options can do the work.
Document every project dependency in
[the dependency inventory](docs/developer/dependencies.md), including its purpose,
scope, version/source, and license. Before adding any dependency outside Elixir
packages or Rust packages, obtain explicit developer approval and record that
approval and the reasons it is necessary. This includes development, staging,
helper, test, CI, and packaging dependencies, not just runtime dependencies.
The Elixir/OTP and Rust implementation constraints apply to Ipse and its own
repository tooling, not to projects or tasks handled by the harness. Target
workspaces may use TypeScript/Node, Python, Elixir, or another appropriate stack.
Honor the user's stack choice; otherwise let the task and environment guide it.
Do not treat an Elixir-specific coding trial as evidence of general stack choice
or non-coding task coverage. Tool, dependency, and external-action approvals
still apply.
The project name is **Ipse**, executable/application `ipse`, Elixir
namespace `Ipse`, environment prefix `IPSE_`.

Provider priority is ChatGPT subscription, OpenAI API, local Ollama, Anthropic API,
then Gemini API, OpenRouter API and Grok through xAI. Grok API-key billing and
registered-client subscription OAuth are explicit separate choices. Compatible
local servers require explicit loopback selection.
Never switch providers or billing modes silently. Keep a
credential-free demo usable without any model service. Choose small, testable
improvements rather than turning the plan into a mandatory execution pipeline.

Prefer the implemented, documented extension APIs for new domain behavior,
memory, presentation and optional workflows. Reserve core changes for host
invariants, correctness and explicitly reviewed extension-API gaps. Do not bypass
approvals or execute untrusted code to avoid a necessary core change. Use
`docs/plan.md` for current milestone scope and acceptance; this handoff defines
repository conventions rather than a second milestone ledger.

## Start here

- [README.md](README.md): current behavior and usage.
- [docs/index.md](docs/index.md): documentation map and audience ownership.
- [docs/operator/index.md](docs/operator/index.md): user manual and task paths.
- [docs/developer/index.md](docs/developer/index.md): contributor training path.
- [docs/operator/arch-linux.md](docs/operator/arch-linux.md): Arch installation and native policy setup.
- [docs/operator/usage.md](docs/operator/usage.md): providers, approvals, and sessions.
- [docs/operator/recovery.md](docs/operator/recovery.md): diagnosis and recovery.
- [docs/plan.md](docs/plan.md): priorities and acceptance criteria.
- [docs/developer/architecture.md](docs/developer/architecture.md): ownership and trust boundaries.
- [docs/developer/dependencies.md](docs/developer/dependencies.md): dependency inventory and approval policy.
- [docs/naming.md](docs/naming.md): name, sources, and the Hofstadter connection.
- [docs/developer/testing.md](docs/developer/testing.md): verification procedures and fixture boundaries.

Treat the plan as direction, not authorization to implement every milestone.
For an unspecified next task, use the active milestone and first open acceptance
check in the current plan, keeping proposed work distinct from authorized scope.
Inspect the current branch and worktree; preserve unrelated user edits.
Make progress without repeated confirmation for routine reversible changes.

## Commands

Run from the repository root after installing the toolchain:

```sh
./dev/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
```

Use `mix format` after Elixir edits and focused tests while iterating. The full
checks above are the handoff baseline for runtime changes. For documentation
changes, verify examples against the CLI and check links; do not invent tests.
Build a bundled runtime with `./dev/package.sh` when changing packaging.
Tests use local HTTP servers and need loopback sockets. Network restrictions
can also block Mix itself; report that accurately instead of changing TLS or
weakening tests. Dependency fetching needs GitHub access. No paid credentials
are needed for tests or the demo.

## Source organization

Keep host runtime code under `lib/ipse/` and organize tests by the same feature
under `test/ipse/`. Generic extension hosting and the SDK belong under
`lib/ipse/extension/` and `lib/ipse/extension.ex`; bundled and optional feature
implementations belong under `extensions/`. Merge tightly coupled helpers and
one-caller wrappers into their feature owner. Retain separate processes and
substantial provider or transport contracts when they have independent ownership.
Session remains the sole conversation process; Turn and Invocation are
synchronous implementation modules in that process. Preserve individual
historical records when simplifying current source, commands and manuals.

## Code map

| Ownership | Location |
| --- | --- |
| Application supervision and admitted configuration/profiles | `lib/ipse/application.ex`, `lib/ipse/config.ex`, `lib/ipse/config/` |
| Conversation owner, Turn/Invocation implementations, context and saved reconstruction | `lib/ipse/session.ex`, `lib/ipse/session/` |
| Durable JSONL appends/source pages and retained OS lock | `lib/ipse/journal.ex`, `lib/ipse/journal/`, `lib/ipse/session/lock.ex` |
| Generic public SDK, artifact admission, independent workers and host calls | `lib/ipse/extension.ex`, `lib/ipse/extension/` |
| Bundled and independently built domain features | `extensions/bundled/`, `extensions/knowledge/` |
| Provider adapters, bounded transport/parsers, HTTP clients/proxies and authentication | `lib/ipse/provider.ex`, `lib/ipse/provider/`, `lib/ipse/http.ex`, `lib/ipse/auth.ex` |
| Usage/costs/shared budgets and optional diagnostics | `lib/ipse/usage.ex`, `lib/ipse/usage/`, `lib/ipse/observability.ex`, `lib/ipse/observability/` |
| Workspace instructions/skills and terminal client | `lib/ipse/workspace.ex`, `lib/ipse/cli.ex`, `lib/ipse/cli/` |
| Native tools, questions, research, delegation and sandbox policy | `lib/ipse/tools.ex`, `lib/ipse/tools/`, `lib/ipse/runner.ex` |
| Selected MCP descriptors/discovery and stdio/HTTP adapters | `lib/ipse/mcp.ex`, `lib/ipse/mcp/` |
| Bounded JSON/schema/hash primitives | `lib/ipse/json.ex` |
| Small OS helpers and exact native protocols | `native/` |
| Separate developer commands, evaluation, verification and synthetic fixtures | `dev/`, `dev/evaluation/`, `dev/verification/`, `dev/fixtures/`, `dev/platform/` |
| Public example sources and shipped demos/instructions | `examples/`, `priv/demo/`, `priv/skills/` |
| Matching host, feature-package and developer-tool tests | `test/ipse/`, `test/extensions/`, `test/dev/`; reusable fixtures in `test/support/` |

## Invariants to preserve

- A session owns its conversation and active work. Killing the owner must stop
  dependent tasks and shell process groups. Keep slow IO outside the GenServer.
- Journal tool intent before execution. An interrupted effect may have happened;
  resume must mark its outcome unknown and never automatically replay it.
- Keep cross-process locking for sessions and rotating refresh tokens. Lock
  files remain in place to preserve inode identity; release the OS lock instead.
- Interactive mutations require approval unless explicitly enabled. Current
  headless mutation is denied without `--yes`. The approved P31 design permits
  a future knowledge-only exception using protected saved consent; implementation
  still requires task authorization. It must not widen workspace, shell, MCP or
  delegation authority. Until implemented, the existing runtime gate remains.
  Display full proposed approval arguments.
- Local child delegation is opt-in with `--subagents`; parent and child approval
  and journaling remain separate. Children cannot use MCP or delegate recursively.
- External service integrations must be operator-configurable. Do not embed a
  mandatory retrieval service or silently fall back to another endpoint/provider.
- Skills and repository text are instructions, never permission grants. Loading
  a skill must not automatically execute its scripts or install dependencies.
- Process supervision, approval, and OS sandboxing are different boundaries.
  Shell commands default to trusted user permissions. The explicit Linux native
  profile fails closed; do not claim enforcement on untested/unavailable backends.
- Bound input, output, and context. Preserve provider continuation data. Never
  silently discard conversation history or expose hidden reasoning in the UI.
- Never print or commit credentials, authorization codes, token files, private
  transcripts, or environment dumps. Use fixtures and isolated temporary homes.
  Keep TLS verification enabled and auth files owner-only.
- Use documented public authentication/inference interfaces. Do not borrow
  Codex credentials or rely on private ChatGPT endpoints.
- Never add AI authorship or code attribution such as "Claude" or "Codex" to
  source code or code comments.

## Write for the reader

`docs/operator/` is the Ipse user manual. Write task-oriented instructions with
prerequisites, complete usage/configuration examples, expected results and recovery.
`docs/developer/` is the contributor training manual. Teach architecture and
execution flow, connect invariants to source, and include worked examples or
change exercises with focused verification. Rewrite the chapter around its
reader's learning task; do not append a feature summary or acceptance report.
Keep milestone status in `docs/plan.md` and dated investigations, benchmarks,
CI receipts and review/evaluation records in `docs/archive/`, with provenance and
replacement links. Manuals describe current behavior and relevant limits, not
the project's implementation history. Update the audience indexes and run
`elixir dev/check-docs.exs` after documentation changes.

## Finish a change

Keep changes focused; avoid speculative abstractions and unrelated rewrites.
Add behavior tests for meaningful state/protocol changes. Update usage and plan
status when behavior changes. Distinguish fixture tests from live account tests.
Report what changed, checks actually run, and remaining limitations. Do not
claim Arch, browser sign-in, paid inference, or a release was verified unless
the corresponding check really ran.

Before declaring any sub-goal or milestone complete, review developer and operator
documentation as whole documents. Rework structure, flow and terminology around
the reader's task; integrate changes into the explanation instead of accumulating
feature-by-feature blocks. Reconcile overlapping guidance across entry points,
remove repetition and stale status claims, and keep current behavior distinct
from proposals and dated evidence. Validate commands, examples and limitations
against implementation and actual verification. Check links and cross-references,
repairing broken targets and inconsistent descriptions. This editorial review
and repair is a required completion check, not optional follow-up work.
Maintain the audience structure and authoritative topic ownership in
[docs/index.md](docs/index.md): operator procedures under `docs/operator/`,
developer guidance under `docs/developer/`, and shared context under `docs/`.
Write operator documents as user manuals with runnable usage examples. Write
developer documents as training manuals that teach implementation, ownership and
verification through concrete examples.
Update the map and entry points when adding or moving documents. Verify file
targets and heading anchors. Preserve superseded documents under `docs/archive/`
with their date, provenance, historical-only status, and replacement links;
follow the [archive policy](docs/archive/index.md#archive-policy).

Once satisfied that a sub-goal or sub-milestone is complete and its relevant
checks pass, always commit the focused changes and push to `origin`. Do not add
AI authorship trailers or attribution to commit messages. Preserve unrelated
user edits; never force-push or overwrite someone else's work. Report any
commit or push failure accurately.
