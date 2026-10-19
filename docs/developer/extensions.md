# Develop extensions for Ipse

Build domain behavior as an extension when it can use Ipse's existing hooks,
tools, state, context, services, or event jobs. Keep permission decisions,
journaling, provider selection, and process ownership in the host. This chapter
starts with a working example, then gives you a path through the SDK and its
implementation.

You need the repository's Elixir/OTP and Rust toolchain for source development.
Run commands from the repository root. The examples below use synthetic model
responses and do not need credentials or a paid service.

## Run your first hook

Build Ipse, then run the existing two-hook demonstration:

```sh
./scripts/build.sh
mix run -e 'Code.require_file("priv/extension-demo.exs"); Ipse.ExtensionDemo.run()'
```

Read `priv/extension-demo.exs` beside its output. It prepares the prompt annotation
and answer-format instances, starts a real Session with a synthetic provider,
and checks the resulting prompt, displayed answer, saved native message, and
idle resume. The example is useful because those values are deliberately different.
An extension's displayed text must not replace the provider's saved continuation.

The annotation worker in
`lib/ipse/extensions/examples/prompt_annotation.ex` implements the complete
callback contract:

```elixir
@behaviour Ipse.Extension

def describe, do: %{"sdk" => 1, "capabilities" => ["transform.prompt"]}
def init(options), do: {:ok, options}
def handle("transform.prompt", _payload, options),
  do: {:ok, %{"append" => options["text"]}, options}
```

`describe/0` declares the executable contract. `init/1` receives schema-checked
options. `handle/3` returns a stage-specific public object and private worker state.
The host validates the public object even for bundled code. Here it appends an
attributed reference fragment to the effective prompt and retains the original
operator input. It does not grant the fragment instruction or approval authority.

For a first source-reading exercise, follow the `text` option through
`Registry.builtins/0`, `Registry.prepare/4`, `Host.run/4`, and `Projection`.
Locate the options schema, the pre-execution intent, the result validation, and
the point where the derived user message becomes model context. Then follow the
answer formatter through the same path. Its `prefix` and `suffix` change only
completed presentation; streamed chunks and saved assistant data retain their
original form.

## Choose the smallest contract that fits

| You need to build | Start with |
| --- | --- |
| An attributed prompt annotation or completed-answer wrapper | [Session hooks](extension-hooks.md) |
| An independently compiled package | [Artifacts and worker SDK](extension-artifacts.md) |
| A model tool, terminal command, or typed service | [Catalogs and invocations](extension-invocations.md) |
| A sequence of host operations and private scoped records | [Host calls and state](extension-host-calls.md) |
| Clarification that can survive process exit | [Questions](extension-questions.md) |
| Approved file or shell work | [Workflow tool actions](extension-tool-actions.md) |
| Approved selected external calls and complete bounded result reads | [MCP actions](extension-mcp-actions.md) |
| Calls between explicitly routed extensions | [Service composition](extension-services.md) |
| Bounded reference text with recorded provenance | [Context and evidence](extension-context.md) |
| Read-only prompt or completed-answer delivery | [Boundary notifications](extension-events.md) |
| Read-only observations during work | [Live feeds](extension-feeds.md) |
| Awaited recall or maintenance after an answer | [Event jobs](extension-event-jobs.md) |
| Explicit catch-up over recorded own-session views | [History reads](extension-history.md) |
| Approved inference through a named operator profile | [Model calls](extension-model-calls.md) |
| Repeatable synthetic scenarios | [Conformance checks](extension-conformance.md) |
| Proof against source and an unchanged installed release | [Compatibility lab](extension-proof.md) |

Read [end-to-end workflows](extension-scenarios.md) after the first hook. It
connects installation, trial, state, upgrade, and recovery. For explicit-note
behavior, continue with [memory](memory.md). Accounting reads, costs, private
visible-text delivery, and diagnostic capture have their own chapters in
[usage accounting](usage-accounting.md), [costs](costs.md),
[text streams](text-streams.md), and [observability](observability.md).

## Follow the ownership chain

An artifact is immutable package bytes plus a bounded manifest. Operator trust
permits capabilities for those exact bytes. An activation instance adds its alias,
options, order, scope, lease, and runtime identity. These are separate identities.
Importing a package neither trusts nor activates it.

`Registry` resolves inert metadata and admitted selections. `Session` owns the
active conversation, approvals, journal, and action lane. `Host` runs slow callback
and host-operation work outside the Session GenServer. `Worker` owns an independent
VM and its native process group. The worker implements only JSON callback values;
it receives no Session PID or complete host configuration.

Before executable startup, Session commits an intent. Host verifies the artifact,
initializes the worker, invokes its callback, validates its reply, and closes its
resources. Session commits the result only after the applicable schema, lease,
source, and cleanup checks. An action continuation receives a committed receipt,
not direct authority to call Session.

Worker private state lasts for that worker's lifetime. Transforms and notifications
use fresh VMs. A question closes its VM and saves a bounded JSON checkpoint.
A feed retains a VM during its explicitly enrolled lease. Use host-scoped state
for durable records; do not rely on process dictionaries, VM globals, or an
activation instance to preserve private memory.

## Change the host without adding domain branches

When a feature cannot fit a documented contract, identify the missing generic
operation first. A new Session conditional named after a memory or research
feature conceals the missing host boundary. Extend the closed request schema,
capability negotiation, admission, execution owner, journal records, and pure
recovery validator together. Test interrupted work before exposing the operation.

Public values are plain JSON with string-keyed maps. SDK objects are at most
16 KiB; strings, depth, and collections have additional shared limits. Selection
allows at most eight instances and sixteen operator trust records. Arbitrary
Elixir terms belong only in private worker state. Invalid fields fail explicitly;
returning an action-looking map inside an ordinary value never executes it.

A trusted worker still has the user's OS permissions. An independent VM separates
code and dependencies; supervision, timeouts, and capability validation do not
sandbox arbitrary executable code. Keep import inert and make executable trust
an operator decision. Children receive an explicitly permitted subset and cannot
use MCP or delegate recursively.

## Prove a change at its boundary

Start with the focused test named in the chapter you changed. For the first hook:

```sh
mix test test/extensions_registry_test.exs test/extensions_session_test.exs
```

Check the actual derived prompt, saved native message, receipts, and process
cleanup. A passing callback alone says nothing about recovery. Add cases for
invalid output, owner death, cancellation, expiry, and interrupted intent when
your change affects those behaviors. Resume must restore committed values
without running callbacks or effects again.

Then use the [conformance runner](extension-conformance.md) for author scenarios
and the [installed compatibility proof](extension-proof.md) for worker/release
changes. The repository's [testing manual](testing.md) defines the complete
handoff checks. Keep fixture behavior distinct from live provider, billing,
platform containment, or production retrieval quality.
