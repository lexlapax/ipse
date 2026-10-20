# Develop Ipse

This is the contributor training manual. Follow the first-session exercise to
build a mental model of the harness, then choose the chapter that owns your
change. You need basic Elixir and OTP knowledge; the manual explains Ipse's
processes, messages, persistence and authority rules through source and fixtures.
For using the application, start with the [user manual](../operator/index.md).

## Build your first checkout

You need Elixir 1.18+, Erlang/OTP 27+, Rust 1.85+, Git and a C linker on Linux or
macOS. The [dependency inventory](dependencies.md) explains package/host scope and
licenses. On Arch, the [setup guide](../operator/arch-linux.md) gives installation
commands. Use your host's supported toolchain installation procedure on another
system; a bundled Ipse runtime does not include the development toolchain.

From a checkout:

```sh
mix local.hex --force
mix local.rebar --force
./scripts/build.sh
mix run examples/session/hello.exs
mix test test/session_test.exs
```

The build fetches locked packages and compiles the Rust helper and application.
The example uses a fixed in-process provider and temporary files. Expect its
message confirming that the answer was journaled and idle resume made no model
call. The Session tests then exercise real approval and lifecycle paths with
synthetic providers. These steps require no paid account.

If Mix reports `:eperm` for a TCP filesystem lock, use the environment's permission
flow or a local terminal with loopback access. Keep TLS verification enabled.
Read [verification](testing.md) before broadening checks or interpreting a
platform exclusion as enforcement evidence.

## Learn the core in order

1. [Follow a turn](architecture.md) from `prompt/2` to a completed answer. Run the
   example, locate each owner and distinguish acceptance from completion.
2. [Follow durable records](persistence.md) through intent, effect, result and
   saved validation. Understand what remains unknown after interruption.
3. [Review authority and ownership](reviewing-changes.md) using a complete source
   path and both allowed/refused controls.
4. [Verify the change](testing.md) with the nearest fixture, then the appropriate
   source, OS and installed-runtime checks.

The public entry points are `Ipse.CLI`, `Ipse.Session` and `Ipse.Extension`.
[`Ipse.Application`](../../lib/ipse/application.ex) starts shared services. Session
owns each conversation; slow IO uses owned tasks, and Rust owns narrow OS helpers.
Read [AGENTS.md](../../AGENTS.md) for repository conventions and
[CONTRIBUTING.md](../../CONTRIBUTING.md) for submitting work.

## Change conversation behavior

| Learn to change | Chapter |
| --- | --- |
| Load bounded scoped settings and retain provenance | [Configuration](configuration.md) |
| Route main, child and helper requests explicitly | [Model profiles](model-profiles.md) |
| Admit instruction/skill snapshots and refresh them | [Workspace context](workspace-context.md) |
| Reduce active context while preserving history | [Compaction](context-compaction.md) |
| Ask and restore explicit user questions | [Operator questions](operator-questions.md) |
| Bound provider requests and response assembly | [Provider limits](provider-limits.md) |
| Retain canonical usage and unknown coverage | [Usage accounting](usage-accounting.md) |
| Calculate configured local cost estimates | [Costs](costs.md) |
| Reserve shared request quotas conservatively | [Budgets](budgets.md) |
| Preserve research source/claim provenance | [Research](research.md) |

## Work across process boundaries

| Learn to change | Chapter |
| --- | --- |
| Launch, confine and confirm local OS work | [Native sandbox](sandbox.md) |
| Integrate external tools through bounded transports | [MCP](mcp.md) |
| Own child conversations and their approvals | [Delegation](delegation.md) |
| Deliver bounded visible text to clients/workers | [Text streams](text-streams.md) |
| Bind text frames to negotiated event identities | [Stream events](stream-events.md) |
| Project durable metadata and runtime epochs | [Lifecycle events](lifecycle-events.md) |
| Bind admitted tool input/results to sources | [Tool events](tool-events.md) |
| Capture optional sanitized diagnostics | [Observability](observability.md) |

Supervision, approval and OS confinement are distinct boundaries. A task exit
cannot confirm a started OS effect or revoke a remote request. Work through the
failure exercises in these chapters before introducing another asynchronous lane.

## Build extensions before adding domain branches

Start with [the extension authoring course](extensions.md). It takes a small
prompt hook through description, packaging, explicit trust, selection and a
synthetic check. Then choose the host interaction you need:

| Goal | Chapter |
| --- | --- |
| Import an inert package and launch its owned VM | [Artifacts and workers](extension-artifacts.md) |
| Transform prompt or presentation projections | [Hooks](extension-hooks.md) |
| Export typed tools, commands and value services | [Invocations](extension-invocations.md) |
| Use scoped CAS storage and durable continuations | [Host calls](extension-host-calls.md) |
| Pause for an explicit structured answer | [Extension questions](extension-questions.md) |
| Request approved file and shell work | [Workflow tools](extension-tool-actions.md) |
| Call a selected MCP item and read complete source windows | [MCP actions](extension-mcp-actions.md) |
| Compose declared value services | [Services](extension-services.md) |
| Publish bounded asserted or receipt-backed context | [Context](extension-context.md) |
| Request a profile-bound accounted text inference | [Model calls](extension-model-calls.md) |
| Create accounted vectors and reconstruct bounded coordinate pages | [Embedding actions](extension-embedding-actions.md) |
| Observe original/effective prompt and completed-answer views | [Notifications](extension-events.md) |
| Run separately admitted before/after-turn jobs | [Event jobs](extension-event-jobs.md) |
| Consume finite, acknowledged live deliveries | [Feeds](extension-feeds.md) |
| Read bounded own-session history for catch-up | [History](extension-history.md) |
| Exercise ordinary host validation with synthetic inputs | [Conformance](extension-conformance.md) |
| Verify unchanged artifacts in an installed runtime | [Compatibility proofs](extension-proof.md) |
| Combine these contracts into a complete feature | [Worked scenarios](extension-scenarios.md) |

[Explicit memory](memory.md) is a worked domain implementation using generic
state/actions. [Knowledge extensions](knowledge-extensions.md) traces the
independent Corpus, Research and Graph workers, source-root publication, exact
citations and projection preflight, with a ranker change exercise.
[Knowledge evaluation](knowledge-evaluation.md) teaches independent dataset commitments,
detached answer custody, prediction/label separation,
complete measured execution through the optional Linux backend, private model
service ownership and separate retrieval, span and semantic measurements.
[Capability placement](runtime-capabilities.md) helps decide when a new generic
host contract is necessary.

## Finish with a reviewable result

Keep a change focused on an observable behavior. Add a meaningful regression when
state/protocol behavior changes, update the affected manual as a coherent chapter,
and run the [handoff checks](testing.md). Use [dependency maintenance](dependencies.md)
before adding packages, executables or services. For a comparative or supervised
self-development task, use [evaluation design](self-hosting-evaluation.md).

Current priority and acceptance decisions live in the [plan](../plan.md). Dated
measurements, investigations, reviews and failed/successful verification records
live in the [archive](../archive/index.md). They provide historical evidence;
these training chapters describe how to understand and change the current code.
