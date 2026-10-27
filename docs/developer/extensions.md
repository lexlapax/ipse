# Build and verify an extension

Build one optional behavior, import its inert artifact, then follow activation,
execution, and recovery through a real Session. The host owns approval, provider
routing, durable receipts, and resource lifetime. Feature code owns its domain
algorithm. Run these exercises from a built checkout using temporary state.
No account or model service is needed.

## Choose the smallest existing contract

| Required result | Use |
| --- | --- |
| Prompt reference or completed presentation | Transform |
| Typed model tool or explicit local command | Invocation |
| Typed value supplied to another selected extension | Bound service |
| Approved state/file/MCP/text/embedding/decision work | Host action continuation |
| Finite work before a request or after a turn | Event job |
| Selected notifications or acknowledged live events | Notification/feed |
| Visible provider text | Text consumer |
| Canonical counters or configured estimates | Accounting reads |
| Optional diagnostic metadata | Observability sink |

A read-only consumer cannot return an action request. An observer cannot enforce
a budget after dispatch. Stream completion does not establish answer admission.
For example, a word-count consumer can acknowledge visible frames in private
worker state. Persisting the result needs an explicit invocation or admitted job.
Use `answer.committed` for a workflow requiring an admitted answer, rather than
transport end. [Lifecycle delivery](lifecycle-events.md) teaches those distinctions.

Generic SDK code is in `lib/ipse/extension.ex`, with host contracts in
`lib/ipse/extension/`. Feature implementations share `extensions/`: shipped
Memory/reports/transforms are in `bundled/`, independently built Knowledge packages
in `knowledge/`. Bundled entrypoint names and artifact IDs remain stable; source
location alone grants no special authority.

## Follow a prompt hook through a real Session

```sh
./dev/build.sh
mix run -e 'Code.require_file("priv/demo/extensions.exs"); Ipse.ExtensionDemo.run()'
```

Read the [driver](../../priv/demo/extensions.exs) alongside the
[bundled transforms](../../extensions/bundled/transforms.ex). It checks five
separate values: original prompt, effective provider input, streamed raw text,
completed presentation, and retained native assistant data. Predict which values
change before editing the annotation option.

This callback fragment is the core of the prompt annotation:

```elixir
@behaviour Ipse.Extension

def describe, do: %{"sdk" => 1, "capabilities" => ["transform.prompt"]}
def init(options), do: {:ok, options}
def handle("transform.prompt", _payload, options),
  do: {:ok, %{"append" => options["text"]}, options}
```

It is not a complete artifact. `describe/0` declares the executable contract;
`init/1` receives schema-checked options; `handle/3` returns public JSON plus
private state. The host validates output even from bundled code. Trace the
option through `Registry.prepare/4`, `Host.run/4`, and `Projection`.

| Stage | Payload | Closed output | Effect |
| --- | --- | --- | --- |
| `transform.prompt` | Visible `text` | `{"append":"fragment"}` | Attributed reference added to effective user input |
| `transform.presentation` | Visible `text` | `{"prefix":"before","suffix":"after"}` | Completed display only |

Original operator input and assistant continuation remain durable. An annotation
grants no instructions or permissions. Presentation can change `Session.info.final`
and its presentation event, without changing previously streamed text or saved
native data. Private worker state is not durable memory.

## Build an independent artifact

Choose a fresh output path and compile the reviewed lab sources separately:

```sh
IPSE_ARTIFACT_ROOT=$(mktemp -d)
elixir dev/build-artifact.exs extension-lab \
  --sdk _build/dev/lib/ipse/ebin --output "$IPSE_ARTIFACT_ROOT/lab"
```

Inspect `lookup/extension.json` in that output and
[lookup.ex](../../examples/extension-lab/src/lookup.ex). The builder records actual
BEAM/license lengths and hashes plus current runtime compatibility. It executes
trusted compilation, not extension installation or selection.

| Trusted recipe | Output | SDK |
| --- | --- | --- |
| `extension-lab` | Seven artifacts, including two Memory versions | 1 |
| `model-calls` | Accounted text helper | 1 |
| `embedding-actions` | Native vector helper | 1 |
| `decision-calls` | Explicit typed advisory helper | 1 |
| `mcp-actions` | Bound MCP helper | 1 |
| `saved-results` | Complete document command | 2 |

`dev/build-artifact.exs` accepts this finite recipe set, not arbitrary source.
Only `mcp-actions` accepts `--omit` with a unique comma-separated subset of its
capabilities for denial fixtures. Unknown/duplicate options and existing output
paths, including dangling links, refuse. The builder loads the SDK's existing
JSON/schema dependencies, compiles in a private staging working directory,
rejects diagnostics/warnings, verifies declarations/inventory, and renames only
a complete output. Failure removes its owned stage. Load callbacks can execute
during trusted compilation, so this is not a sandbox for arbitrary code.

Stable source locations and deterministic compilation keep temporary paths and
map order out of rebuild identity. The lab's spec supplies exact descriptions and
entrypoints; the builder checks each compiled module against it. Different versions
compile separately. See `test/dev/artifact_builder_test.exs` for collisions,
warning/refusal, declaration drift, marker containment, and stable rebuilds.
A package-owned builder, such as Knowledge's, must bind final bytes and every
runtime dependency without claiming untested platforms.

## Bind the manifest to immutable bytes

[`Artifact.decode/1`](../../lib/ipse/extension/artifact.ex) reads duplicate-free
UTF-8 `extension.json` within 16 KiB. Required fields are:

| Fields | Meaning |
| --- | --- |
| `format`, `protocol` | Integer 1 |
| `sdk` | 1, or 2 with `invoke.result.pages` |
| `id`, `version`, `backend`, `entrypoint` | Identity/display version; imported backend `elixir_worker`; worker-only module name |
| `license_file`, `files` | Declared license and exact relative file inventory |
| `capabilities`, `options_schema` | Declared operations and bounded options |
| `runtime` | Elixir requirement, OTP majors, exact platform strings |

Optional `exports`, `requires`, and `subscriptions` declare inert invocation,
service, and delivery contracts. Declarations are requirements, not operator grants.
Unknown shapes/operations refuse. Artifact identity is SHA-256 of original manifest
bytes. Whitespace changes identity too. Versions do not select mutable code.

Artifacts declare 2..64 files, each at most 8 MiB and 32 MiB together. Portable
ASCII paths allow 256 bytes/eight components. Absolute paths, traversal,
backslashes, manifest replacement, and file/directory prefix collisions refuse.
The inventory includes license and entrypoint BEAM. Options/descriptors use the
[bounded schema subset](mcp.md#schema-subset), without remote schema loading.
`Artifact.compatible?/1` checks Elixir requirements, OTP major, and exact system
architecture. Import may retain incompatible bytes; activation refuses them.
Validation certifies no publisher, license compliance, dependency safety, or
cross-platform execution merely because a file is BEAM.

## Import, grant, and select separately

The generic store is part of Artifact. `Artifact.import/2` captures declared regular
files, verifies lengths/hashes, syncs private staging, and atomically publishes under
a per-digest native advisory lock. Directories use `0700`, files `0600`. Busy
imports fail. Unlock retains the lock inode. Roots/descendants reject symlinks;
selected-root ancestors remain trusted. Inventory inspection has a 1024-entry
cap after ordinary directory listing. Same-user hostile replacement remains
outside those cooperative checks.

`Artifact.lookup/2` revalidates manifest, declared files, and installed inventory.
Missing/changed/extra/symlinked entries refuse. It does not repair or replace an
invalid digest directory. Interrupted staging remains inert. Content addressing
is not author authentication or an OS read-only mount.

| Identity | What it binds |
| --- | --- |
| Artifact | Manifest/license/declared final files |
| Operator trust | Capability/scope/child/route/binding ceilings for exact bytes |
| Activation | Artifact/instance/options/order/source/expiry plus host/runtime identity pinned to a Session |

`Registry.builtins/0` returns inert descriptors. Disabled discovery initializes
nothing. Imported code cannot claim builtin IDs/backend. `Registry.prepare/4`
checks schemas, options, trust, and expiry outside Session; Session revalidates
in monitored preflight before opening the journal. Activation binds normalized
SDK/protocol/exports/requirements/subscriptions, option/source digests, earliest
expiry, child ceiling, generation, host digest, Elixir/OTP/ERTS, and architecture.
Stale embedded entries or substituted code refuse. The host digest validates its
complete compiled application inventory, excluding independently artifact-bound
builtin modules; moving files is not automatically identity-neutral.

Follow [operator selection](../operator/extensions.md) for complete import/trust/
configuration commands. The [example journey](../../examples/README.md) provides
manual lab commands without duplicating that operator procedure here.

## Exercise incompatible bytes before activation

Use the lab output built above in the same terminal:

```sh
IPSE_LAB_LOOKUP="$IPSE_ARTIFACT_ROOT/lab/lookup" iex -S mix
```

Run this complete exercise in that shell. It changes only a scratch copy:

```elixir
alias Ipse.Extension.{Artifact, Worker}
root = Path.join(System.tmp_dir!(), "ipse-incompatible-" <> Ipse.Usage.id())
scratch = Path.join(root, "source")
File.mkdir_p!(root)
File.chmod!(root, 0o700)
{:ok, _} = File.cp_r(System.fetch_env!("IPSE_LAB_LOOKUP"), scratch)
path = Path.join(scratch, "extension.json")
manifest = path |> File.read!() |> Jason.decode!()
manifest = put_in(manifest, ["runtime", "platforms"], ["different-host"])
File.write!(path, Jason.encode!(manifest))
store = Path.join(root, "store")
{:ok, artifact} = Artifact.import(scratch, store)
false = Artifact.compatible?(artifact.manifest)
{:error, :extension_admission_refused} = Worker.start(owner: self(), store: store,
  digest: artifact.digest, trusted: artifact.digest, options: %{})
File.write!(Path.join(artifact.path, "LICENSE"), "changed fixture")
{:error, :invalid_extension_artifact} = Artifact.lookup(store, artifact.digest)
File.rm_rf!(root)
```

Import accepts inert incompatible bytes; Worker refuses activation before code
initialization. Tampering with the stored license then refuses lookup. This
distinguishes storage validity from execution compatibility. Keep all edits in
the disposable store.

## Follow the worker and its public values

The SDK exposes `describe/0`, `init/1`, and `handle/3`. Public objects are string-keyed
JSON maps, bounded to 16 KiB encoded, 8-KiB strings, depth twelve, and 128 members
per map/list. Schemas separately permit 32 KiB, depth eight, and 256 nodes. Count
the complete enclosing callback object, not just the domain value. PIDs/references/
functions/structs/arbitrary Erlang terms remain private worker data. SDK-2's private
`ResultPublication.Output` is consumed inside Bootstrap, without Erlang-term transport.
[Invocations](extension-invocations.md) teaches complete document publication and
its separate aggregate limits.

Worker launches clean ERTS with existing Elixir/Jason/SDK/schema paths and only
the chosen artifact. It starts Elixir, not the host application. Artifact loading
waits for initialization. No artifact module atom or BEAM is introduced into the
host. Native launch clears inherited environment, selecting PATH/baseline LANG;
ERTS derives its own variables. Payload/options cross, not Session state, secrets,
provider continuation, or hidden reasoning. Code still has the user's OS permissions.

Protocol 1 uses 32-bit-length-prefixed JSON, envelopes within 32 KiB, and monotonically
increasing call IDs. Stdout is protocol-only binary IO; `-noinput` is incompatible.
Malformed/duplicate-key/wrong-ID/version replies fail closed. Stderr is discarded;
combined stdout/stderr traffic permits 64 MiB per lifetime. Only one call is active;
contention returns `extension_busy`. Initialize exactly once with selected options;
undeclared stages refuse. Calls default to five seconds, with explicit 1..30000-ms
bounds and narrower host-stage deadlines where applicable.

A raw `Worker.start/1` needs owner, store, digest, `trusted: digest`, and validated
options. This assertion does not grant trust; Session supplies it after admission.
The initialization description must match SDK/capabilities and normalized declarations.
Owner death, timeout, exit, or protocol failure closes the native stdio group.
No call restarts. `close/1` and cleanup leases retain real helper receipts even
on callback failure; process disappearance alone is not descendant cleanup proof.

## Commit the result before depending on it

Session syncs transform intent before executable startup, including load/describe/
init callbacks. Slow Host work runs outside its GenServer. Initialization and
transform callbacks each have five-second deadlines. Payloads expose visible text,
without Session PID, full context, auth, native continuation, or hidden reasoning.
Hook fragments allow 4096 characters, derived text 16 KiB, and full projection
records 64 KiB. Earlier hooks feed later hooks; an oversized next input refuses.
Reserved reference-framing markers refuse, with no silent truncation.

Schema/identity/source/expiry/cleanup checks precede committed input/reply/derived
output hashes. Projection restores exact derivations without callbacks. Version,
order, uniqueness, intent/source/context binding checks precede permitted tail
repair. Unmatched intent remains interrupted work, not instructions to replay it.
Crashes, timeout, expiry, malformed output, or unknown cleanup stop the lane.
Prompt failure prevents inference; presentation failure retains the admitted
assistant answer. Expiry is checked at admission/commit, without continuous
wall-clock preemption. Hashes catch inconsistency, not malicious coherent rewriting
of a private journal.

## Turn the behavior into a conformance scenario

```sh
./bin/ipse extension check --config priv/demo/operator.json \
  --fixture priv/demo/conformance.json --extension annotation --no-project-config
```

Read both files first. Operator configuration trusts the builtin but leaves it
disabled. The flag selects it; the fixture grants no authority. Its prompt case
expects one synthetic request, an annotation marker, completed text, and exact
transform-record count. Change an expected marker in a scratch copy to observe
failure, then restore it and add an effect assertion.

Conformance is a closed duplicate-free v1 object within 16 KiB. It permits sixteen
safe seed files, each path 256 bytes/content 4096 bytes; sixteen ordered uniquely
named prompt/tool/command/service cases; eight scripted assistant replies or explicit
answers; and validated options for selected instances. Cases have 100..60000-ms
timeouts, default 15000, and optional 1..60000-ms cancellation. Missing answers
stop at question, without recommendations submitted on the user's behalf.
Model tools/later mutations remain denied without explicit `--yes`.

Cases share scratch home/workspace, with fresh Session IDs for state sequences.
`{{workspace}}`/`{{home}}` substitute values, not keys, without shell/environment
interpolation. Absolute adapter paths are not redirected. Host inference is
synthetic; MCP/delegation/compaction are not activated. Live/replay flags refuse.
Workers and approved shell retain ordinary OS authority.

Assert actual request counts, final/value, effective input/context, named record
counts, ordered action outcomes, exact safe file contents, and cleanup. After close,
the runner validates saved accounting/session/source/text facts without repair.
Cases run once and unexpected failure/cleanup stops later cases. Inspect declared/
executed counts, `stopped_early`, and `safe_to_continue`. Expected unknown cleanup
can match while still preventing later work. `--keep-fixture` retains private
scratch journals; filesystem removal is separate from process cleanup. Developer
trace flags are described in [testing](testing.md), not permissions embedded in fixtures.

## Upgrade without replay and identify genuine host gaps

The lab builds Memory 0.1.0/0.2.0 side by side. New import does not overwrite old
bytes. Fresh sessions select new code; old ones pin their original selection.
No hot activation, automatic builds/upgrades/catalog fetch, or garbage collection
exists. Keep referenced artifacts. Without an explicit logical state binding,
artifact/instance/source changes isolate namespaces. A reviewed binding permits
sharing but does not migrate schemas or widen operations. Migration is explicit
approved work, never hidden initialization or idle resume.

Pending questions restore JSON checkpoints without worker startup. Only a valid
explicit answer starts a continuation; prior effects do not replay. Feeds restore
coverage/acknowledgment facts without a live queue. Catch-up is new separately
granted work with occurrence deduplication and current revisions. See
[state](extension-state.md) and [events](extension-events.md).

Current contracts do not supply audio IO, STT/TTS, bidirectional realtime inference,
playback acknowledgment, or stateful stream rewriting. Completed formatting cannot
promise live redaction or erase journals/context. Such a capability needs explicit
bounded formats/handles, ownership/interruption/cleanup, retention/consent, and
separate generation-versus-delivery facts. These are design requirements, not flags.

For a shared host gap, specify its exact missing operation, closed schema, numerical
bounds, stale/wrong-owner refusal, and recovery. Change negotiation/admission,
ownership, durable facts, and restoration together. Reuse suitable maintained
Elixir/OTP facilities before adding protocol machinery. Runtime facts, for example,
are an allowlisted `Session.Context.runtime_snapshot` projection, not arbitrary
configuration or process state. A new field needs a concrete reader need and
exclusion tests for nearby private data.

## Verify the complete authoring journey

```sh
mix test test/ipse/extension/registry_test.exs test/ipse/extension/session_test.exs
mix test test/ipse/extension/store_test.exs test/ipse/extension/worker_test.exs
mix test test/ipse/extension/conformance_test.exs test/dev/artifact_builder_test.exs
```

Inspect actual input/native/presentation values, receipts/effects, and cleanup.
Include refusal, owner death, cancellation, expiry, and inert resume for relevant
changes. [Typed invocations](extension-invocations.md), [state](extension-state.md),
[effects](extension-effects.md), [events](extension-events.md), and
[accounting](accounting.md) teach the next contracts. [Testing](testing.md) owns
installed-runtime and final handoff procedures. Synthetic conformance establishes
neither real model quality, billing accuracy, every crash schedule, nor OS confinement.
