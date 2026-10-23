# Develop Ipse

Build a checkout, follow one completed turn, then choose the owner of your change.
These chapters assume basic Elixir/OTP knowledge and teach Ipse through processes,
messages, source, and focused exercises. To operate Ipse, use the
[user manual](../operator/index.md).

## Build and follow your first Session

You need Elixir 1.18+, OTP 27+, Rust 1.85+, Git, and a C linker on Linux or macOS.
[Dependencies](dependencies.md) records scope/licenses; [Arch setup](../operator/arch-linux.md)
provides installation commands. An extracted release includes its runtime, not
the developer toolchain.

From the checkout root:

```sh
mix local.hex --force
mix local.rebar --force
./dev/build.sh
mix run examples/session.exs
mix test test/ipse/session_test.exs
```

The build fetches locked packages and compiles the helper/application. The example
uses a fixed provider and temporary files. Expect a journaled answer and an idle
resume with zero new model calls. Tests exercise approval/lifecycle through
synthetic providers; no paid account is required. Mix needs loopback. Resolve
`:eperm` through the environment's permission flow, keeping TLS verification enabled.

Read [Architecture](architecture.md) to follow prompt through completion, then
[Persistence](persistence.md) for intent-before-effect and interrupted outcomes.
Use [Testing](testing.md) to review the complete path and verify a changed artifact.

## Navigate the consolidated tree

| Location | Ownership |
| --- | --- |
| lib/ipse/ | Host runtime and public Session/provider/CLI boundaries |
| lib/ipse/session/ | Same-process turn/invocation/context logic plus explicit resource, lock, and delivery owners |
| lib/ipse/extension.ex and lib/ipse/extension/ | Generic public SDK and host contracts, with no domain algorithms |
| extensions/bundled/ | Shipped Memory, reports, transforms, and trace features |
| extensions/knowledge/ | Independently built Corpus, Graph, and Research artifacts |
| test/ipse/, test/extensions/, test/dev/ | Matching host, feature-package, and developer-tool tests |
| dev/ | Separate build/check commands; evaluation, verification, fixtures, and platform helpers |
| examples/ | Small extension sources and Session example; compatibility-lab workers share one lab folder |
| priv/ | Runtime resources, shipped skills/demo, and built native helper |
| native/ | Rust OS implementation and protocol documentation |

Keep cohesive helpers with their owner instead of adding one-caller wrappers.
Retain separate files/processes for real lifetime or public-contract boundaries.
Session owns one conversation. Turn/Invocation are synchronous implementation
modules in that same process; IO runs in explicitly owned tasks. A folder split
does not create another conversation owner. See [AGENTS](../../AGENTS.md) for the
source map and [CONTRIBUTING](../../CONTRIBUTING.md) for submissions.

## Change host behavior

| Learning task | Chapter |
| --- | --- |
| Follow turns, questions, child conversations, and approvals | [Architecture](architecture.md) |
| Resolve settings, profiles, endpoints, context/output/deadline policy | [Configuration](configuration.md) |
| Snapshot instructions/skills and compact active context | [Workspace and context](workspace-context.md) |
| Change journals, recovery, locks, or saved-result capacity | [Persistence](persistence.md) |
| Restore canonical usage and reserve shared budget liability | [Accounting](accounting.md) |
| Launch local work, enforce supported OS policy, and confirm cleanup | [Sandbox](sandbox.md) |
| Bind selected external tools through bounded transports | [MCP](mcp.md) |
| Project durable/ephemeral sources into text or diagnostic delivery | [Lifecycle events](lifecycle-events.md) |

Supervision, approval, and OS confinement have separate contracts. Process death
cannot prove an effect completed or revoke a remote request. Follow each chapter's
failure exercise before adding asynchronous work.

## Implement domain behavior through extensions

Start with [Extension authoring](extensions.md): build an artifact, inspect/import
it, select explicit trust, run conformance, and complete a workflow. Then choose
the host contract your feature needs:

| Learning task | Chapter |
| --- | --- |
| Export typed tools/commands/services and publish complete output | [Invocations](extension-invocations.md) |
| Use CAS, stale-write deadlines, services, questions, and explicit Memory | [State and continuations](extension-state.md) |
| Request approved tools, MCP, text inference, or native embeddings | [Effects](extension-effects.md) |
| Choose notifications, finite jobs, live feeds, or historical catch-up | [Events](extension-events.md) |
| Change citations, retrieval, attributed facts, or native Research | [Knowledge algorithms](knowledge-extensions.md) |
| Publish immutable pages/root CAS, suppress/migrate, or implement a remote store/gateway | [Knowledge storage](knowledge-storage.md) |

New domain features should use documented extension APIs where they fit. Core
changes address host correctness/invariants or a reviewed generic API gap. Import
and skill loading grant no execution or effect authority.

## Run a defensible comparison

Follow these reader tasks in order:

1. [Evaluation runbook](knowledge-evaluation.md): independently commit a workload,
   review the complete policy, build artifacts, declare/seal, measure, and audit.
2. [Execution](knowledge-execution.md): trace public Sessions, complete results,
   evidence packing, canonical requests, and storage coverage.
3. [Measurement](measurement.md): understand captured code, exact charged-RAM
   populations, native authority, service ownership, and failure/loss controls.
4. [Scoring](knowledge-scoring.md): release references after the audit gate,
   obtain independent blinded judgments, recompute literal support, and qualify
   each strategy before choosing one.

Synthetic protocol checks establish no model quality. Failed first outcomes stay
in the declared grid. Historical/exposed data is suitable for tuning, not fresh
held-out acceptance.

## Finish a reviewable change

Choose observable acceptance and meaningful regressions. Review affected manuals
as whole chapters, verify their examples, then run the relevant
[handoff checks](testing.md). Consult [dependency policy](dependencies.md) before
adding a package, executable, or service. Keep priorities/acceptance in the
[plan](../plan.md), and dated measurements/reviews/receipts in the
[archive](../archive/index.md). Current manuals teach behavior rather than recount
milestone history.
