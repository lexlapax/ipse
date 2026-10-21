Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../developer/extensions.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Develop, trial, and upgrade an extension

An extension workflow crosses package bytes, operator trust, activation identity,
and durable state. This chapter connects those boundaries through complete local
journeys. Use a scratch workspace and dedicated application home while learning.
All examples here use demo or synthetic providers and need no paid service.

## Start with a bundled hook

Run the shipped conformance example after building Ipse:

```sh
./bin/ipse extension check --config priv/conformance-operator.json --fixture priv/conformance-demo.json --extension annotation --no-project-config
```

Read the two JSON files first. The operator configuration permits a known builtin
artifact and defines a disabled instance. The temporary flag selects that instance
for this invocation. The fixture asserts its derived prompt and saved transform
record. The command does not persist enablement.

Trace the same resolution in `Config`, `Registry`, and the CLI tests. This is the
pattern for feature configuration: schema-valid options under an instance alias,
inside an operator capability/scope ceiling. Add domain options to the extension's
schema rather than adding feature-specific host flags. Two aliases can select
the same artifact with different options and deterministic order.

## Build and trial an independent package

The lab provides a complete package pair with explicit service composition:

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

Use the repository toolchain to build Ipse first. The compiler step is executable
build work; import only validates/copies final declared files. Review the source,
license, manifest, and generated operator configuration before activating it.
The generated file leaves all instances disabled, with routes/trust for the
reviewed local bytes. Memory needs lookup selected and imported; the host neither
fetches a missing package nor silently removes its dependency.

Use these explicit commands inside chat:

```text
/ext ext__memory__remember {"text":"entity: Ada; link: Ada -> OTP"}
/ext ext__memory__recall {"text":"Ada"}
/ext ext__memory__stats {}
/ext ext__memory__workflow {"path":"lab-note.txt"}
/ext ext__memory__export {}
```

Remember proposes a separately approved scoped write. Recall reads state and its
routed synthetic corpus, then publishes bounded reference evidence. Stats returns
counts and revision/deleted metadata without model inference. Workflow asks a
question, closes its VM, and continues only after an explicit answer. Its later
file write still needs approval. Inspect the actual file and receipts rather
than trusting a returned success label.

This package's deterministic label parser demonstrates contracts, not general
language extraction. Use the [compatibility lab](extension-proof.md) to run its
assertions automatically against source and an unchanged installed runtime.

## Configuration, lifetime and activation

Keep three identities distinct:

| Identity | What changes it | What it authorizes |
| --- | --- | --- |
| Artifact | Original manifest/file bytes | Nothing by itself; import is inert |
| Operator trust record | Reviewed capabilities, routes, scope/child ceilings, bindings | Executable selection within its exact ceiling |
| Activation instance | Artifact, alias/options, configuration source, runtime/host, order, lease | The exact pinned session selection |

For persistent use, review the successful trial, then explicitly set the intended
instances to `enabled: true` and `lifetime: "persistent"` in the dedicated operator
file. Use a fresh session with that configuration. Flags are temporary selection,
not a configuration writer. Project configuration can select only what the
operator permits and cannot create executable trust, service routes, or logical
state bindings.

A session pins exact code/options/configuration/runtime identity and generation 1.
Importing another artifact or editing defaults does not change that catalog.
Hot activation, current-conversation replacement, managed source building,
remote catalogs/downloads, automatic upgrade, and garbage collection are not
implemented management paths. Use explicit external build, inert local import,
reviewed configuration, and a new session.

Lease expiry refuses future admission/commit. It does not undo writes, erase
history, or provide live wall-clock revocation. Referenced artifact bytes remain
needed for reproducible resume. Missing or changed bytes refuse without rebuilding
or downloading a substitute. Disabled future selection does not alter old saved
sessions.

## Upgrade without losing the storage boundary

The lab builds memory versions 0.1.0 and 0.2.0 side by side. Importing the second
publishes a new digest directory. It never overwrites the first. A fresh session
can select the new artifact while the old session remains pinned to the old one.
Changing an old session's metadata to make resume accept new code would bypass
its recovery contract.

Without a logical binding, artifact/instance/configuration-source changes isolate
state. An explicitly reviewed `state_binding` lets approved versions share one
namespace, but does not migrate record schemas or grant wider operations.
Read [state bindings](extension-host-calls.md#scope-storage-and-recovery) before
designing an upgrade. Keep data migration explicit, with its own reviewed effects
and recovery path. Never hide migration in `init/1` or idle resume.

For a learning exercise, compare the two memory artifact digests and their selected
identity records in `examples/extension-lab/proof.exs`. Find the assertions proving
separate versions run without loading either worker module into the host. Then
trace the binding fixtures to see how explicit storage sharing differs from
execution compatibility.

## Recover an interrupted workflow

When a question is pending, close and resume through the normal session procedure.
The saved question and JSON checkpoint return without worker startup. Only an
explicit valid answer starts a fresh continuation. Original callbacks and prior
writes are not replayed.

When interruption leaves only an effect intent, inspect the target file or scoped
record and its operation ID before deciding on fresh work. Cancellation does not
roll back a completed rename or remote request. A committed result restores its
cached value; an uncommitted outcome remains unknown. Do not edit receipts to
change that classification.

An observer feed has a different recovery rule. Pressure or cancellation closes
coverage visibly, retaining its first rejected source and acknowledged counts.
Idle resume does not restart a worker or rebuild its queue. Explicit history
catch-up is new bounded work with separately granted private reads and normal
write/CAS approval. Deduplicate recorded occurrence IDs and preserve captured
revisions so catch-up cannot resurrect forgotten facts.

## Scenario tests

Run focused tests for the boundary your change crosses:

```sh
mix test test/extensions_config_test.exs test/extensions_registry_test.exs test/extensions_state_binding_test.exs
mix test test/extensions_invocation_test.exs test/extensions_services_test.exs
mix test test/extensions_event_job_test.exs test/extensions_history_test.exs test/extensions_feeds_test.exs
```

The first group checks selection ceilings and exact identities. The second checks
owned invocation, approval, questions, and routed services. The last checks
before/after timing, catch-up, stale writes, and explicit feed gaps. Add a
[conformance scenario](extension-conformance.md) for the author's actual journey,
then use [installed proof](extension-proof.md) for release compatibility.
Do not infer a live provider, OS sandbox, or production-memory guarantee from a
synthetic callback passing.
