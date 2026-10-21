# Prove an extension against source and an installed runtime

The independent lab teaches you to test an extension package without rebuilding
Ipse around its domain behavior. Compile worker artifacts separately, exercise
them through real host APIs, and run the same proof against an unchanged extracted
release. The useful result is an inspectable compatibility experiment, including
its failure cases and limits.

The lab uses deterministic synthetic data and a synthetic provider. You need no
model service, credentials, database, or external endpoint. Its memory/graph
logic is a teaching fixture, not a production retrieval engine.

## Build and execution boundary

Build Ipse with the repository toolchain, then build the artifacts in a separate
compiler VM:

```sh
./scripts/build.sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)/artifacts
elixir scripts/build-artifact.exs extension-lab --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LAB_ARTIFACTS"
mix run --no-compile examples/extension-lab/verify.exs "$IPSE_LAB_ARTIFACTS"
```

Keep the shell variable for the installed check below. The builder compiles
reviewed source against the existing `Ipse.Extension` behavior, copies the
repository license, inventories every file, and pins current runtime targets.
It creates memory versions 0.1.0 and 0.2.0 as separate immutable artifacts plus
lookup and observer workers. It does not import, trust, or enable them.

Read these files in order:

1. `examples/extension-lab/spec.exs` defines descriptors, schemas, capabilities,
   service routes, and disabled operator selections.
2. `scripts/build-artifact.exs` compiles the finite `extension-lab` recipe in its
   own VM and emits data-only manifests. Follow the shared construction flow in
   [the artifact chapter](extension-artifacts.md#build-and-inspect-a-package).
3. `src/memory.ex` and `src/lookup.ex` implement domain behavior through public
   callbacks and finite host calls.
4. `proof.exs` drives installation, Sessions, approvals, questions, and assertions
   from the host side.
5. `verify.exs` prints the report; `verify-package.exs` repeats it inside an
   extracted release with a restricted development-tool PATH.

Workers use `describe`, `init`, and `handle` JSON values. They receive no private
Session state or host PID. The text observer also uses public pure ephemeral-frame
helpers. The host-side verifier can inspect journals and, for its synthetic text
case, `:sys.get_state/1` acknowledgment counters. That privileged test
instrumentation is not an extension API or permission grant.

## Choose a contract exercise

| Artifact | Reader exercise | Host contracts exercised |
| --- | --- | --- |
| Memory, two versions | Store a synthetic fact, recall it, forget it, and compare versions | Jobs, typed tools/commands, CAS, context, questions, file tools, history |
| Lookup | Return a configured corpus value and then force required recall to fail | Typed routed service, schema equality, failure before inference |
| Metadata | Acknowledge prompt counts without receiving private text | Inert notification and exact acknowledgment |
| Observer | Hang a consumer and inspect the first coverage gap | Feed enrollment, bounded capacity, closure, no idle reenrollment |
| Tool observer | Compare private input/result and metadata for one occurrence | Separate tool-view grants and exact feed acknowledgments |
| Text observer | Check visible text and metadata projection | Versioned text resources and exact frame acknowledgment |

These are trusted local programs with ordinary OS permissions. The proof checks
host mediation and ownership of the exercised code; it cannot certify arbitrary
third-party workers or OS containment.

## Capture, recall and deletion

Follow the before-request recall branch. It reads scoped memory, calls the
explicitly routed lookup service, then publishes literal receipt-backed context.
The host freezes the set in the main-request snapshot. After-turn capture reads
the selected original prompt, extracts bounded labels/relations, and proposes a
new approved CAS write. It cannot change the already admitted answer.

The fixture recognizes text such as `entity: Ada` and `link: Ada -> OTP`.
Facts retain source event/view identity, extractor version, and package version.
A new identical prompt has a new source ID. Catch-up of the same recorded
occurrence deduplicates without rewriting state. Its fixed-range
`prompt.original` scan allows at most eight pages per invocation, each scanning
at most eight records, and reports gaps and continuation explicitly.

Domain limits are deliberately below host limits: eight sources, sixteen entities,
and a 7,000-byte stored value. Capacity refusal is visible. Stored labels,
relations, and source bindings do not duplicate whole prompts.

Forgetting an entity removes all source facts containing it and retains blocking
identities. This conservative rule can remove other facts from those sources.
Forget-all uses a host tombstone and blocks recreation in that namespace. It also
clears this instance's future context. A delayed write with its pre-forget
revision conflicts. Old journals, request snapshots, and provider transfers
remain; use this case to understand why deleting derived records does not erase
source history or establish a production retention policy.

## Test the unchanged installed runtime

Build a runtime archive through the repository's
[packaging procedure](testing.md#verify-the-extracted-package).
Choose the actual archive for your current platform and use artifacts compiled
for that runtime's compatible SDK/OTP/platform:

```sh
elixir examples/extension-lab/verify-package.exs /absolute/path/to/ipse-runtime.tar.gz "$IPSE_LAB_ARTIFACTS"
```

The archive path is a placeholder. The verifier extracts a disposable release,
creates an isolated home, imports selected artifacts through the CLI, and checks
actual temporary selection with caller and lookup target enabled. It then runs
the broader host proof inside the extracted runtime.

Inside the release, PATH contains declared host utilities and permits the bundled
Erlang runtime. System Elixir, Erlang, Mix, and Rust development executables are
refused. Canonical path comparison accounts for filesystem aliases. The archive
hash and host application BEAM bytes must remain unchanged; domain modules must
not be loaded into the host. These checks catch accidental reliance on checkout
code paths or rebuilding Ipse to make a package work.

Run this on each platform you claim to support. One host's compatible `.beam`
files and passing source run do not establish another runtime or architecture.
The stored `FROZEN_CORE` file records the lab's original baseline for historical
comparison; use the candidate runtime you actually built for a new experiment.

## Interpret the report before adding cases

Inspect each boolean in `checks` alongside its assertion in `proof.exs`.
The proof checks real graph/provenance, original/effective separation, awaited
recall, frozen context, writes/denials, question continuation, inert resume,
source deduplication, scoped persistence, concurrent versions, forget/CAS,
feed pressure, installed private-tool/text delivery, and saved receipt validation.
The `stats` case checks counts and revision/deleted metadata with one state read,
no inference, and no tombstone rewrite.

The final case deliberately crashes a required service. It must prevent inference
and must not invent cleanup confirmation. A matched report therefore ends with
`safe_to_continue: false` and `expected_terminal_cleanup: unconfirmed`; no later
domain case runs. Exit zero means the declared positive and negative assertions
matched. It does not mean every cleanup was confirmed.

To extend the proof, add one extension-owned export and a host assertion that
observes its effect independently of its returned status. Keep package creation
outside activation and check unchanged host bytes. If the operation needs a new
host capability, document and test that generic boundary before presenting the
feature as extension-only.

```sh
mix test test/extension_lab_test.exs
```

This integration builds and runs the source proof in separate VMs. The package
command above establishes installed execution separately. For helper inference,
use the additional [model-call artifact proof](../../examples/model-calls/README.md),
which uses a local HTTP fixture. Neither proof establishes paid billing, model
quality, external retrieval quality, or unsupported SDK contracts.
