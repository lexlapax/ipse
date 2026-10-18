# Session extension hooks

This guide owns the ordered `transform.prompt` and `transform.presentation`
contracts. The two compiled examples and independent worker artifacts share the
same JSON SDK. [Lifecycle events](lifecycle-events.md) supply the common occurrence
model; selected notifications, live feeds and event jobs have separate delivery
contracts. Transforms return projections, while [typed invocations](extension-invocations.md)
can propose separately admitted state, question, tool and context operations.
These contracts form part of the completed P22 foundation. New host capabilities
still need explicit review and versioned compatibility; the SDK is not frozen.
See [operator procedures](../operator/extensions.md) and
[artifact/worker SDK](extension-artifacts.md).

## Registry and admission

`Registry.builtins/0` returns static data without invoking extension functions.
Only known compiled IDs can select the built-in backend; imported descriptors
cannot shadow them. The built-ins are `builtin:prompt-annotation:1` and
`builtin:answer-format:1`. Each descriptor binds its actual BEAM and bundled Apache-2.0
license bytes; there is no `on_load`, extension OTP application or startup
initializer. Embedded release code preloading does not activate callbacks.

`Registry.prepare/4` admits enabled instances outside Session: validate operator
trust/capability ceiling, project/child scope, expiry, exact code, compatibility
and options schema. It produces ordered internal entries with private options
and public identities. `Session.start_link/1` revalidates required code/schema
in a monitored task before creating its process or opening its journal, with a
five-second preflight bound. Embedded callers must prepare current selections;
malformed, stale or expired entries are refused. Disabled discovery performs no
artifact lookup, installation or executable initialization.

Identities contain instance/reference/artifact SHA-256, options digest, SDK and
protocol 1, export/requirement/subscription digests, operator/project scope, configuration-source path hash,
ordered capabilities, order/lifetime/earliest expiry, child ceiling,
VM components (Elixir version, OTP major, ERTS version, architecture), host API
digest and generation 1. The host digest binds `Ipse.Extension`, Identity, Catalog,
Invocation, Manifest, Store, Registry, Worker, Bootstrap, Host, Projection,
Actions, Operation, ToolAction, Services, ServiceCall, State, Questions, Tools, Runner, WorkspaceContext,
the shared schema adapter, usage normalizer/
ledger, private text channel, Journal, lifecycle Source/Event, Subscriptions and Session BEAM bytes. It is an exact API
implementation pin, not a signature or full operating-system/toolchain digest.
Startup checks current VM components and code; resume requires identical pinned
identities. No migration or hot activation is implemented.

Children inherit only instances whose operator ceiling sets `allow_children`;
the subset survives explicit model-profile routing. Each callback owns a separate
VM, so parent/child private VM state is not shared. Child MCP/recursive delegation
restrictions remain enforced. Options and native/provider configuration are not
passed through the public identity or callback envelope.

## Ordered jobs and wire values

Session launches one monitored host job per stage. That job invokes selected
instances in configured order, opening a fresh Worker VM per transform. Before
opening executable resources, it requests a Session-journaled intent. Worker
startup itself waits for `initialize` before loading the executable module; the
host's intent therefore precedes `on_load`/initialization and callback execution.
Transform callbacks must be effect-free and cannot return host-action proposals.
The separate invocation contract supports approved effects; it is not yet wired
to generic event subscriptions. Process separation cannot prevent arbitrary
trusted code from using the operator's OS permissions directly.

The worker receives validated options and `{"text": visible_text}` only. No
credentials, complete Session state, provider-native continuation or hidden
reasoning is exposed. Request/response SDK values stay bounded JSON; worker
module-name atoms and executable code paths are confined to that VM. Worker
stderr/error details are not forwarded as callback diagnostics. Plain JSON types
are validated before encoding as well as after decoding, so atom-keyed maps,
PIDs and custom encoders cannot silently change SDK types. Session/worker status
uses the supported [GenServer status callback](https://elixir.hexdocs.pm/GenServer.html#c:format_status/1)
to redact private state, callback messages, reasons and debug logs. Each initialization
and callback has a five-second deadline. Crash, invalid output, expiry or cleanup
failure stops the job without restarting/replaying it. The task resource scope
closes registered Workers and requires native-helper acknowledgments before
confirming cleanup; the Worker also monitors its host job. Missing receipts stop
the Session with cleanup unconfirmed. macOS descendant cleanup retains the
existing documented best-effort boundary.

The launcher selects current ERTS and a profile-free boot (`no_dot_erlang.boot`
from installed OTP, or Mix's release `start_clean.boot`), with explicit
`RELEASE_LIB` and interactive loading inside the worker. It does not use the
parent's full application boot, sys.config, distribution identity or credentials.
The native launch clears inherited environment; only caller PATH/baseline LANG
are selected before ERTS derives its own runtime variables. This works in the
extracted runtime without a system Elixir installation. See the primary
[Mix release structure/clean boot](https://mix.hexdocs.pm/Mix.Tasks.Release.html)
and [OTP boot flags](https://www.erlang.org/doc/apps/erts/erl_cmd.html).

## Transform contracts

| Stage | Input | Required result | Host application |
| --- | --- | --- | --- |
| `transform.prompt` | Current visible effective user text | Closed `{"append": text}` | Append attributed untrusted context; preserve original message in journal |
| `transform.presentation` | Current completed visible presentation | Closed `{"prefix": text, "suffix": text}` | Wrap display only; preserve original assistant/native message |

Inputs use the SDK's 8 KiB string/16 KiB encoded-object bounds. Each returned
fragment has a 4,096-character limit plus SDK byte bounds; derived text is at most
16 KiB and a complete projection event at most 64 KiB encoded. Later transforms
receive the prior projection and can exceed their input budget; failure is
explicit rather than truncation. The prompt example's option is `text`; the
format example requires `prefix` and `suffix`. Other option/result fields fail.
Prompt fragments containing the reserved opening or closing extension-context
markers also fail before committing a projection, so an extension cannot close
its own attributed frame.

Prompt admission saves raw operator input in `extension_prompt_received`, then
the ordinary expanded user message. A committed prompt projection replaces only
that last effective user message's content in model context. Completed presentation
changes `Session.info.final` and emits a separate `{:presentation, text}` client
event; it never changes saved assistant content/provider data. Raw text streaming
continues unchanged. The CLI prints the completed presentation separately.

Prompt-transform failure prevents the model call; presentation failure retains
the already completed original assistant. Previously committed projections remain
available in either case. Initialize/private VM state lasts for the job; it is
not durable session state. [Host-mediated scoped state](extension-host-calls.md)
is available from typed invocations, as are [owned value-service jobs](extension-services.md).
[Context contributions](extension-context.md) and finite prompt/answer
[event jobs](extension-event-jobs.md) are implemented separately. Broader nested
effectful service operations require a negotiated enhancement; static catalogs
and standalone invocations do not imply that capability.

## Persistence and recovery

`extension_transform_intent` contains a unique 32-hex request ID, pinned identity,
stage, input hash, complete effective-context hash and source-message hash. It is
fsynced before execution. A result repeats that intent identity and commits exact
input/result/derived output and output hash after output validation and confirmed
normal worker cleanup. Native continuation is referenced by a hash, never sent
to the extension. These are mandatory recovery records, independent of future
optional observability gates.

`Projection` reconstructs the narrow derivation without invoking callbacks.
It rejects unknown fields/stages/versions, mismatched identity/source/context,
changed hashes/output, duplicate IDs, orphan or duplicate results and invalid
ordering. Deleted projections cannot be silently treated as successful work;
unknown/mistyped transform envelopes fail. The core context restorer preserves
historical unknown tool placeholders before checking callback context hashes,
applies saved prompt projections and validates
presentation bindings against unchanged messages. Required artifact verification
and full saved-context/projection validation happen before tail repair on resume.
The process restores cached final presentation and stays idle; no executable
initializer or transform runs merely because the session resumed.

An unmatched intent is historical interrupted work, not permission to execute.
Fresh input can create a new job/intent; old callbacks are never retried implicitly.
Journal hashes detect inconsistencies, not an adversary who can rewrite the entire
private journal and all hashes. Lease expiry is checked at admission/commit;
there is no wall-clock preemption timer or live revocation command yet. Expiry
does not erase committed context or undo external effects.

## Verification and remaining scope

The source/package fixture is:

```sh
mix run -e 'Code.require_file("priv/extension-demo.exs"); Ipse.ExtensionDemo.run()'
```

It uses a synthetic provider, both built-ins, preserved native fixture data and
byte-identical idle resume. Package verification invokes the same fixture from
an extracted release with a fresh home and utility-only development PATH.
`test/extensions_session_test.exs` additionally compiles an independent artifact
in a separate compiler VM, exercises it without host atom/code loading, checks
actual callback OS-process exit after cancellation/owner death, preserves unfinished
intent on idle resume, refuses missing/tampered code before repair, tests invalid
projections and verifies annotations cannot grant tool mutation approval.
Registry fixtures cover disabled discovery, schema/capability refusal, trust/lease
expiry and child subset routing. See [actual evidence](testing.md#session-extension-hooks-2026-10-16).

Worker [visible-text delivery](text-streams.md) is now implemented. P22 still needs
broader private lifecycle subscriptions, event-triggered owned jobs, an ordered
recall seam, accounting report access, observability/debug controls and the
independent extension-only memory/workflow proof and reviewed supervised trial.
The [event design](lifecycle-events.md) explains why a prompt transform or stream
acknowledgment alone cannot maintain a knowledge graph. Hosted macOS and local Linux
evidence must remain distinguished. This initial capability set does not claim
the complete planned extension family is implemented.
