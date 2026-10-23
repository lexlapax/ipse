> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/extensions.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Build, exercise and upgrade an extension

Start with a prompt hook, turn its behavior into a conformance scenario, then
trial an independent package. Use extensions for domain behavior that fits the
existing contracts. Keep permission decisions, durable host receipts, provider
routing and process ownership in the host.

You need the repository's Elixir/OTP and Rust toolchain. Run commands from the
repository root with synthetic data and dedicated scratch state. The exercises
below need no provider credentials or model service.

## Run a prompt and presentation hook

```sh
./scripts/build.sh
mix run -e 'Code.require_file("priv/extension-demo.exs"); Ipse.ExtensionDemo.run()'
```

Read `priv/extension-demo.exs` beside the output. It starts a real Session with
a synthetic provider and checks the original prompt, derived model input,
completed presentation, saved native assistant message and idle resume.
Those values deliberately differ. Display text must not replace provider-native
continuation.

The bundled annotation implements these callbacks in
`lib/ipse/builtins/prompt_annotation.ex`:

```elixir
@behaviour Ipse.Extension

def describe, do: %{"sdk" => 1, "capabilities" => ["transform.prompt"]}
def init(options), do: {:ok, options}
def handle("transform.prompt", _payload, options),
  do: {:ok, %{"append" => options["text"]}, options}
```

This is a callback fragment, not a complete independent artifact. `describe/0`
declares the executable contract, `init/1` receives schema-checked options and
`handle/3` returns a public stage result plus private worker state. The host
validates public output even from bundled code.

Trace the `text` option through `Registry.builtins/0`, `Registry.prepare/4`,
`Host.run/4` and `Projection`. Find the options schema, intent append, reply
validation and derived user message. Then trace the adjacent answer formatter:

| Stage | Payload | Closed reply | Projection |
| --- | --- | --- | --- |
| `transform.prompt` | Visible `text` | `{"append":"fragment"}` | Attributed reference appended to the effective user message |
| `transform.presentation` | Visible `text` | `{"prefix":"before","suffix":"after"}` | Completed visible answer only |

Prompt annotations retain original operator input in the journal and grant no
instruction or approval authority. Presentation updates `Session.info.final`
and sends a separate presentation event. It changes neither saved assistant
data nor previously streamed text. Change the demo's annotation option and
predict all five observed values before running it again.

## Follow selection, execution and recovery

Keep these identities separate:

| Identity | Contents and purpose |
| --- | --- |
| Artifact | Immutable manifest, license and declared file bytes; import alone grants nothing |
| Operator trust | Reviewed capability, scope, child, route and binding ceilings for those exact bytes |
| Activation | Artifact plus alias/options, order, scope, configuration source, lease and host/runtime identity pinned to one session |

`Registry.builtins/0` returns inert descriptors such as
`builtin:prompt-annotation:1` and `builtin:answer-format:1`. Disabled discovery
does not open installed artifacts or initialize workers. Imported artifacts
cannot claim the builtin backend or shadow its IDs. `Registry.prepare/4`
checks selected identities, schema, options, ceilings and expiry outside Session.
`Session.start_link/1` revalidates code/schema in a monitored task with a
five-second preflight bound before opening its journal.

The activation pins SDK/protocol, normalized exports/requirements/subscriptions,
options and configuration digests, earliest expiry, child ceiling, generation 1,
host implementation digest, Elixir, OTP major, ERTS and architecture. An embedded
caller must prepare current entries. Reusing a stale private entry or replacing
code behind a saved identity refuses.

For each transform, Session launches a monitored host job in configuration order.
The job obtains a synced `extension_transform_intent` before executable startup,
including `on_load`, `describe` or `init`. `Host` performs slow work outside the
GenServer. `Worker` owns an independent VM and native process group; it starts
a clean ERTS instance without the parent's application tree or credentials.
Initialization and callback each have five-second deadlines.

The callback sees visible text and options, not a Session PID, auth, full context,
hidden reasoning or native continuation. SDK objects allow 16 KiB; input strings
allow 8 KiB. Hook fragments also have a 4096-character bound. Derived text allows
16 KiB and a complete projection record 64 KiB. Later hooks receive earlier
output; an over-budget next input fails explicitly. Reserved extension-context
framing markers in prompt fragments refuse. Nothing silently truncates.

After schema, identity, source, lease and cleanup checks, Session commits the
result with exact input, reply, derived output and hashes. `Projection` restores
the derivation without invoking a callback. It checks versions, ordering,
uniqueness and matching intent/result/source/context bindings before permitted
tail repair. Idle resume stays idle. An unmatched intent is interrupted work,
not a request to run it again.

Timeout, crash, expiry, invalid reply or unconfirmed cleanup stops the job without
retry. Worker stderr/private callback reasons do not become user diagnostics.
Prompt failure prevents that attempt's inference; presentation failure retains
the already completed assistant answer. Expiry is checked at admission and
commit, not through continuous wall-clock preemption. Hashes detect inconsistent
records, not a malicious coherent replacement of the whole private journal.

Independent VMs separate dependencies and resource lifetimes. They do not
sandbox executable worker code: trusted workers retain the user's OS permissions.
Supervision, approvals and OS confinement remain distinct. Children inherit only
operator-permitted instances, with fresh private workers and no parent transcript,
MCP or recursive-delegation authority.

## Turn the hook into a repeatable scenario

Read `priv/conformance-operator.json` and `priv/conformance-demo.json`, then run:

```sh
./bin/ipse extension check --config priv/conformance-operator.json --fixture priv/conformance-demo.json --extension annotation --no-project-config
```

The operator file trusts the known builtin but leaves its instance disabled.
The flag selects it only for this run. The fixture grants no trust or capability:

```json
{
  "version": 1,
  "cases": [{
    "id": "annotate", "kind": "prompt", "text": "Synthetic question",
    "expect": {
      "status": "ok", "requests": 1, "user_contains": "Synthetic note",
      "final": "Conformance fixture completed.",
      "records": {"extension_transform_result": 1}
    }
  }]
}
```

The report contains assertion results, counts, fixture digest and exact artifact,
runtime and API identities. It omits input text, options, answers, values and
journal bodies. A nonzero exit means invalid setup, unexpected behavior or an
incomplete suite. A matching negative case is useful evidence of refusal, not
platform-containment certification.

`Conformance.schema/0` owns the closed v1 fixture, at most 16 KiB with no duplicate
keys or unknown fields. Use these fields to describe the author's actual task:

| Field | Contract |
| --- | --- |
| `files` | Up to sixteen safe relative seed paths, each at most 256 bytes, with contents at most 4096 bytes |
| `options` | Instance option objects for already selected IDs; per-case objects replace common objects |
| `cases` | One to sixteen ordered cases with unique lowercase ASCII IDs up to 32 characters |
| `kind` | `prompt`, `tool`, `command` or `service` |
| `text` | Required prompt text; optional synthetic prompt for a tool |
| `name`, `arguments` | Qualified export and schema-valid tool/command/service arguments |
| `script` | Prompt-only, up to eight exact assistant-text or tool-call replies |
| `answers` | Up to eight explicit answers through the real validator |
| `timeout_ms` | 100..60000, default 15000; expiry cancels owned work |
| `cancel_after_ms` | Optional 1..60000 cancellation delay |
| `expect` | Required status and selected observable assertions |

Tool cases request one synthetic call then finish. Exhausted prompt scripts
return `Conformance fixture completed.` Commands/services invoke their exports
explicitly. Model-selected tools and later mutations remain denied without
`--yes`. Answers grant no action permission; missing answers stop at `question`
instead of selecting a recommendation.

Cases share one isolated scratch workspace/home but use fresh session IDs, so
remember/recall sequences can share explicit state. Files seed once. Literal
`{{workspace}}` and `{{home}}` expand in option/input/expected values, not keys;
there is no shell or environment interpolation. Options are validated and pinned.
Use these placeholders for IO adapters: real absolute paths are not redirected.
Host inference is synthetic; MCP, delegation and compaction are not activated.
Live-provider/replay flags refuse. Worker code and explicitly approved shell
still have their documented OS permissions.

Choose assertions that prove effects, not merely a callback's success label:

| Assertion | Observable result |
| --- | --- |
| `requests` | Synthetic admitted count, 0..10 |
| `final`, `value` | Exact completed presentation or last invocation object |
| `user_contains`, `context_contains` | Effective model input or labelled reference marker |
| `records` | Exact named journal counts, each 0..1000 |
| `action_statuses` | Exact ordered outcomes, up to 128 |
| `files` | Exact safe relative workspace contents |
| `cleanup` | Close acknowledgment, default true |

After close, the runner validates saved diagnostics, accounting/session links,
physical sources and text resources without repair or replay. Cases run once.
Unexpected assertions or unconfirmed cleanup stop later cases. Inspect
`case_count`, `declared_cases`, `stopped_early` and `safe_to_continue`.
An expected unknown-cleanup case can match while still preventing more work.

Copy the shipped fixture to a scratch file. Change `user_contains` to a marker
that is absent and observe the failed assertion, then restore it and add a record
count. Use `--keep-fixture` to retain private scratch journals for diagnosis.
Normal cleanup removes them without that flag; abrupt termination may leave
them behind. Filesystem deletion is distinct from confirmed process cleanup.

For argument-free dispatcher samples, add `--developer-trace`; `--trace-ms`
allows 1..5000, default 1000, and `--trace-events` allows 1..128, default 32.
Both require tracing. Capture failure fails the check; a normal sample/time
limit does not. These flags are operator policy, never fixture permissions.
See [diagnostic training](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/observability.md#diagnose-with-synthetic-data).

## Trial an independently built package

The extension lab combines explicit notes with a routed synthetic lookup service:

```sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)/artifacts
IPSE_LAB_HOME=$(mktemp -d)
IPSE_LAB_WORKSPACE=$(mktemp -d)
elixir scripts/build-artifact.exs extension-lab --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LAB_ARTIFACTS"
elixir examples/extension-lab/config.exs "$IPSE_LAB_ARTIFACTS" "$IPSE_LAB_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/memory"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/lookup"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse chat --provider demo --config "$IPSE_LAB_ARTIFACTS/operator.json" --extension memory --extension lookup --no-project-config --cwd "$IPSE_LAB_WORKSPACE"
```

Build Ipse first. Compilation executes trusted build code; import only validates
and copies declared final files. Review source, license, manifest and generated
configuration before activation. The generated file leaves instances disabled.
Memory requires lookup selected and imported; the host neither fetches a missing
package nor silently drops its dependency.

Inside chat, try these explicit commands:

```text
/ext ext__memory__remember {"text":"entity: Ada; link: Ada -> OTP"}
/ext ext__memory__recall {"text":"Ada"}
/ext ext__memory__stats {}
/ext ext__memory__workflow {"path":"lab-note.txt"}
/ext ext__memory__export {}
```

Remember proposes a separately approved write. Recall reads state and the routed
synthetic corpus, then publishes bounded reference evidence. Stats returns counts
and revision/deletion metadata without inference. Workflow asks a question,
closes its VM and continues after an explicit answer; its file write still needs
approval. Inspect the file and receipts. The deterministic label parser teaches
contracts, not general language extraction.

For persistent selection, explicitly set the reviewed instances to
`enabled: true` and `lifetime: "persistent"`, then start a fresh session.
Flags are temporary selections, not configuration writers. Project data can
select only what the operator permits; it creates no trust, routes or bindings.

## Upgrade and recover without replay

The lab builds memory versions 0.1.0 and 0.2.0 side by side. Import publishes a
new digest directory without replacing the first. Fresh sessions can select new
bytes; old sessions retain their original code/options/runtime identity.
Hot activation, remote catalogs, automatic upgrade/build and garbage collection
are unavailable. Keep referenced old bytes for reproducible recovery.

Without an explicit logical binding, artifact/instance/configuration-source
changes isolate state. A reviewed `state_binding` permits selected versions to
share a namespace; it neither migrates schemas nor widens operations. Keep
migration as explicit approved work, never hidden in `init/1` or idle resume.
Trace the two versions and binding assertions in `examples/extension-lab/proof.exs`.

Pending questions restore their bounded JSON checkpoint without worker startup.
Only a valid explicit answer starts a new continuation. Prior callbacks and
writes are not replayed. For an interrupted effect intent, inspect the file or
record and operation ID before requesting new work. Cancellation cannot undo an
already completed rename or remote request. A committed receipt restores its
cached result; an uncommitted outcome remains unknown.

Feeds recover differently: pressure/cancellation closes coverage visibly, retaining
the first rejected source and acknowledgment counts. Idle resume starts no queue
or worker. Explicit historical catch-up is new bounded work with separately
granted reads and ordinary write/CAS approval. Deduplicate occurrence IDs and
retain captured revisions so catch-up cannot resurrect forgotten facts.

## Choose the next host contract

| Learning task | Chapter |
| --- | --- |
| Build/import a package and understand the SDK VM | [Artifacts](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-artifacts.md) |
| Declare a typed tool, command or service and publish results | [Invocations](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-invocations.md) |
| Continue scoped state operations or questions | [State and continuations](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-state.md) |
| Request file, MCP, text-model or embedding effects | [Typed effects](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-effects.md) |
| Compose services and publish attributed context | [Composition](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-composition.md) |
| Observe prompt/answer boundaries or run admitted jobs | [Events](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-events.md) |
| Consume acknowledged live views or catch up on history | [Feeds and history](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-feeds.md) |
| Read canonical counters or estimate configured costs | [Accounting](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/usage-accounting.md) |
| Own visible-text delivery or optional diagnostic capture | [Text streams](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/text-streams.md), [observability](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/observability.md) |
| Implement explicit notes or source/graph/research features | [Memory](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/memory.md), [knowledge packages](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/knowledge-extensions.md) |

The public SDK is `Ipse.Extension` and `lib/ipse/extension/`. Generic host
implementations live under `lib/ipse/extensions/`; bundled behavior lives under
`lib/ipse/builtins/`. Independently built domain packages live under `extensions/`.
Substantive development fixtures and evaluation tools live under `dev/`, while
`examples/` keeps small runnable package journeys. Follow the
[architecture map](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/architecture.md#find-extension-code-by-its-role) for ownership.

If no current contract fits, identify the missing generic operation before
adding a domain conditional to Session. Change schema, capability negotiation,
admission, execution ownership, journal facts and pure recovery together.
Plain JSON public values are bounded; arbitrary Elixir terms remain private
worker state. Action-looking data in an ordinary result executes nothing.
Selection allows eight instances and sixteen operator trust records.

## Verify the author's complete journey

```sh
mix test test/extensions_registry_test.exs test/extensions_session_test.exs test/extensions_conformance_test.exs
mix test test/extensions_config_test.exs test/extensions_state_binding_test.exs test/extensions_invocation_test.exs test/extensions_services_test.exs
mix test test/extensions_event_job_test.exs test/extensions_history_test.exs test/extensions_feeds_test.exs
```

Check actual prompt/native/presentation values, action receipts, effects and
cleanup. For relevant changes include invalid output, owner loss, cancellation,
expiry and interrupted intent. Resume must restore committed facts while idle.
Use [installed verification](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/testing.md) for worker/release compatibility and
the complete handoff checks. Synthetic conformance is not evidence of live model
quality, provider billing, every crash schedule or OS containment.
