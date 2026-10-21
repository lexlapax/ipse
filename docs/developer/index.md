# Develop Ipse

Build a checkout, follow one completed turn and then choose the owner of your
change. You need basic Elixir and OTP knowledge; these chapters teach Ipse's
processes, messages, persistence and authority through source and fixtures. For
using the application, start with the [user manual](../operator/index.md).

## Build and follow your first session

You need Elixir 1.18+, Erlang/OTP 27+, Rust 1.85+, Git and a C linker on Linux or
macOS. [Dependencies](dependencies.md) explains package/host scope and licenses;
[Arch setup](../operator/arch-linux.md) gives installation commands. Use your
host's supported toolchain procedure elsewhere. A bundled Ipse release contains
its runtime, not the development toolchain.

From a checkout:

```sh
mix local.hex --force
mix local.rebar --force
./scripts/build.sh
mix run examples/session/hello.exs
mix test test/session_test.exs
```

The build fetches locked packages and compiles Rust helpers/application. The
example uses a fixed provider and temporary files; expect its confirmation that
the answer was journaled and idle resume made no model call. Session tests then
exercise approval and lifecycle paths with synthetic providers. No paid account
is needed. Mix's lock service needs loopback; use your environment's permission
flow or a suitable terminal on `:eperm`, keeping TLS verification enabled.

Read these chapters in order:

1. [Architecture](architecture.md): follow `prompt/2` to completion and identify
   Session, owned task, provider and journal responsibilities.
2. [Persistence](persistence.md): trace intent, effect and result, including what
   remains unknown after interruption.
3. [Reviewing changes](reviewing-changes.md): check a complete allowed/refused
   source path instead of trusting one helper or return value.
4. [Testing](testing.md): choose a focused fixture and prove source/installed
   behavior, then run applicable OS/package checks.

`Ipse.CLI`, `Ipse.Session` and `Ipse.Extension` are public entry points.
[`Ipse.Application`](../../lib/ipse/application.ex) starts shared services.
Session owns each conversation; slow IO uses owned tasks and Rust implements
narrow OS facilities. [AGENTS](../../AGENTS.md) defines repository conventions;
[CONTRIBUTING](../../CONTRIBUTING.md) explains submissions.

## Change conversation behavior

| Learning task | Authoritative chapter |
| --- | --- |
| Resolve bounded settings, provenance, profiles and child routes | [Configuration](configuration.md) |
| Snapshot instructions/skills and reduce active context without losing history | [Workspace context and compaction](workspace-context.md) |
| Ask and restore explicit structured user questions | [Operator questions](operator-questions.md) |
| Bound provider requests and response assembly | [Provider limits](provider-limits.md) |
| Preserve canonical counters, coverage and configured cost estimates | [Usage accounting](usage-accounting.md) |
| Reserve shared request liabilities conservatively | [Budgets](budgets.md) |
| Retain native research source/claim provenance | [Research](research.md) |

## Work across process boundaries

| Learning task | Authoritative chapter |
| --- | --- |
| Launch/confine local OS work and confirm cleanup | [Sandbox](sandbox.md) |
| Integrate external tools through bounded transport | [MCP](mcp.md) |
| Own child conversations and separate approvals | [Delegation](delegation.md) |
| Deliver visible text with pressure, exact acknowledgment and ephemeral identity | [Text streams](text-streams.md) |
| Bind durable metadata, epochs, waits and private tool views to physical sources | [Lifecycle sources](lifecycle-events.md) |
| Capture optional sanitized diagnostics | [Observability](observability.md) |

Supervision, approval and OS confinement are distinct boundaries. Process exit
cannot prove completion of an OS effect or revoke remote work. Follow each
chapter's failure exercises before adding another asynchronous lane.

## Build domain behavior through extensions

[Extension authoring](extensions.md) takes a small hook through description,
packaging, trust, selection, conformance and a complete workflow. Then choose
the generic contract your behavior needs:

| Learning task | Authoritative chapter |
| --- | --- |
| Import inert artifacts and launch an owned VM | [Artifacts and workers](extension-artifacts.md) |
| Export typed tools, commands and services | [Invocations](extension-invocations.md) |
| Use scoped CAS, stale-write deadlines and durable questions | [State and continuations](extension-state.md) |
| Request approved file/shell, MCP, text-model or embedding work and read retained results | [Effects](extension-effects.md) |
| Bind typed services and publish literal receipt-backed context | [Composition](extension-composition.md) |
| Observe prompt/answer boundaries or run before/after-turn jobs | [Notifications and jobs](extension-events.md) |
| Consume bounded live feeds and fixed-prefix history | [Feeds and catch-up](extension-feeds.md) |
| Prove unchanged artifacts against an installed runtime | [Testing and compatibility lab](testing.md) |

[Explicit memory](memory.md) is a domain implementation over generic state and
actions. [Knowledge packages](knowledge-extensions.md) traces independent Corpus,
Graph and Research workers, source-root publication, citations and retrieval
changes. [Knowledge evaluation](knowledge-evaluation.md) teaches independent data
commitments, prediction/label separation, captured execution, cold audit, exact
charged-memory measurement and semantic review. [Capability placement](runtime-capabilities.md)
helps decide when a generic host gap warrants a core change.

## Finish with a reviewable result

Keep changes focused on observable behavior. Add meaningful state/protocol
regressions, update affected chapters coherently and run their
[handoff checks](testing.md). Consult [dependency policy](dependencies.md) before
adding packages, executables or services. Comparative/supervised self-development
uses [evaluation design](self-hosting-evaluation.md).

Current priorities and acceptance belong to [the plan](../plan.md). Dated
measurements, investigations, reviews and verification receipts belong to
[the archive](../archive/index.md). Manuals explain the current implementation
and its use; they do not serve as milestone reports.
