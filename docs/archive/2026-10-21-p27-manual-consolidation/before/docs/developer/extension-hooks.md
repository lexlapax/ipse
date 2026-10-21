Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../developer/extensions.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Implement prompt and presentation hooks

A transform returns a narrow projection at a host-owned boundary. Use
`transform.prompt` to append attributed reference context, and
`transform.presentation` to wrap the completed visible answer. Neither callback
can propose host actions or change provider-native continuation. This chapter
traces the bundled examples so you can modify a hook without confusing display,
model context, and durable history.

## Trace a prompt annotation

Open `lib/ipse/builtins/prompt_annotation.ex` and its inert descriptor
in `Registry.builtins/0`. The callback returns the option `text` as `append`:

```elixir
def handle("transform.prompt", _payload, options),
  do: {:ok, %{"append" => options["text"]}, options}
```

The host supplies only `%{"text" => current_visible_text}`. It appends the returned
fragment inside an attributed extension-context frame, saves the exact derivation,
and uses that effective user message for inference. The original operator input
remains in the private journal. An annotation is untrusted reference text and
cannot approve tools or replace system rules.

Now open `answer_format.ex`. It returns exactly `prefix` and `suffix`. The host
wraps completed presentation, sets `Session.info.final`, and publishes a separate
`{:presentation, text}` client event. Original assistant content, native provider
data, and already streamed text remain unchanged. The CLI prints the completed
presentation separately.

Run both paths with a synthetic provider:

```sh
mix run -e 'Code.require_file("priv/extension-demo.exs"); Ipse.ExtensionDemo.run()'
```

Read the fixture assertions before changing either module. They show which value
must change and which original values must survive.

## Registry and admission

`Registry.builtins/0` returns static metadata without invoking extension code.
The two transform examples use `builtin:prompt-annotation:1` and
`builtin:answer-format:1`. Other builtin descriptors provide explicit notes,
accounting reports, and local tracing under their own capabilities.
Their descriptors bind actual BEAM and license bytes. Disabled discovery does not
look up installed artifacts or run initialization. Imported artifacts cannot
claim the builtin backend or shadow these IDs.

`Registry.prepare/4` resolves ordered enabled instances outside Session. It checks
operator capability/scope ceilings, project and child policy, code, runtime,
options, and expiry. `Session.start_link/1` then revalidates required code/schema
in a monitored task with a five-second preflight bound before opening its journal.
Embedded callers must prepare current selections, not reuse stale private entries.

The activation identity pins instance/reference/artifact, options digest,
SDK/protocol, export/requirement/subscription digests, scope, hashed configuration
source, order, lifetime, earliest expiry, child ceiling, host API digest, runtime
components, and generation 1. Runtime components include Elixir, OTP major, ERTS,
and architecture. Registry's private `host_digest/0` computes the implementation-code pin;
`Identity.valid?/1` validates its saved shape. Resume
requires the same identities; a host or option change needs an explicit fresh
session or reviewed handoff, not hot replacement.

Children inherit only instances allowed by the operator's `allow_children`
ceiling. Each callback still owns a separate VM. They do not share private worker
state or acquire parent conversation/MCP/recursive-delegation authority.

## Ordered jobs and wire values

For each stage, Session launches a monitored host job that calls selected
instances in configuration order. A fresh worker VM handles each transform.
The job requests a synced `extension_transform_intent` before startup, including
before executable `on_load`, `describe`, or `init`. Slow IO stays outside the
Session GenServer, which remains responsive to cancellation.

Initialization and callback each have a five-second deadline. Worker startup uses
a clean ERTS boot rather than the parent's application tree or credentials.
The callback gets schema-valid options and visible text, without Session PID,
auth, full context, hidden reasoning, or native continuation. Worker stderr and
private callback reasons do not become user diagnostics.

| Stage | Closed result | Applied to |
| --- | --- | --- |
| `transform.prompt` | `{"append": "fragment"}` | Current effective user text |
| `transform.presentation` | `{"prefix": "before", "suffix": "after"}` | Completed visible presentation |

SDK objects are at most 16 KiB and input strings at most 8 KiB. Each fragment has
a 4,096-character limit in addition to encoded byte bounds. Derived text is at most
16 KiB and a complete projection record at most 64 KiB. Later transforms receive
prior output; if that output exceeds their input budget, the stage fails explicitly.
Nothing silently truncates. Reserved opening or closing extension-context markers
in prompt fragments refuse before commit.

A timeout, crash, invalid reply, expiry, or cleanup failure stops the job without
retry. The resource scope closes registered workers and requires native cleanup
acknowledgments. Missing receipts leave cleanup unconfirmed. Worker leases retain
receipts that were already obtained even when callback completion fails.
These ownership checks are separate from the documented OS containment limits.

## Persistence and recovery

An intent binds a unique 32-hex request ID, exact identity, stage, input hash,
effective-context hash, and source-message hash. The result repeats that binding
and saves exact input, result, derived output, and output hash only after validation
and normal cleanup. Native data is referenced by a hash, never sent to the worker.

`Projection` reconstructs saved derivations without running callbacks. It checks
closed schemas, versions, source/context/identity hashes, ordering, uniqueness,
and matching intent/result pairs. Required artifact and saved-context validation
happen before partial-tail repair. Prompt projections restore onto unchanged
original messages; presentation bindings restore without altering assistant data.

An unmatched intent represents interrupted work. Idle resume restores committed
projections and stays idle. It does not initialize a worker, replay a transform,
or start inference. Fresh input may create a new intent. Prompt-transform failure
prevents that attempt's model call; presentation failure retains the already
completed assistant answer. Expiry is checked at admission and commit, with no
wall-clock preemption or live revocation command. Hashes detect inconsistency,
not a malicious writer who replaces the whole private journal coherently.

## Change a transform safely

As an exercise, change the annotation option in the demo and predict the original,
effective, and presented strings before running it. Then find the tests that
reject a fragment containing reserved framing markers and a projection whose
saved context hash changed. Those checks belong to the host, regardless of worker
backend.

```sh
mix test test/extensions_registry_test.exs test/extensions_session_test.exs
```

These fixtures check disabled parity, independent workers, original/native data,
cancellation/owner death, byte-identical idle resume, corrupt projections, missing
code before repair, and inability to grant mutation approval through annotations.
To add actions, use [typed invocations](../../../../../developer/extension-invocations.md). To contribute
retrieved evidence before a request, use [event jobs](extension-event-jobs.md)
and [context publications](extension-context.md).
