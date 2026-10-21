# Publish a complete saved result

This example builds a command-only SDK-2 extension and publishes exactly 4 MiB
through 1,024 bounded fragments. It uses synthetic data and requires no model
service, credentials or network access. Run the commands from the repository root.

Build Ipse first, then compile the artifact in a separate development process.
Choose an output directory that does not already exist:

```sh
./scripts/build.sh
IPSE_SAVED_ARTIFACT=$(mktemp -d)/artifact
elixir scripts/build-artifact.exs saved-results \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_SAVED_ARTIFACT"
elixir scripts/verify.exs source saved-results \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_SAVED_ARTIFACT"
```

The builder uses the SDK and its existing JSON/schema dependencies. It creates a
manifest, one worker BEAM and an Apache-2.0 license file. Building an artifact does
not activate it. The proof imports it without executing it, configures operator
trust for `invoke.command` and `invoke.result.pages`, and invokes
`ext__saved__publish` through an ordinary Session.

Read [worker.ex](worker.ex) to see `ResultPublication.prepare/1` return the private
output value. The worker computes 511 strings of 8,192 bytes and pads the complete
JSON document to exactly 4 MiB. Bootstrap owns byte transport after that return;
the domain callback runs once. Small values would retain the inline callback
contract. Services and recovered question continuations cannot publish outputs.

Read [proof.exs](proof.exs) for complete API calls. It checks every fragment, the
full byte count and digest, the unchanged logical schema, a bounded human view,
confirmed Session cleanup, offline materialization and exact reads after restart.
Worker load/callback markers and the journal remain unchanged during recovery.
The trusted worker writes its load and callback markers inside the isolated proof
home using ordinary OS access.
The final JSON report must contain `fragment_count: 1024`, `byte_count: 4194304`,
`model_requests: 0`, `resume_inert: true` and `cleanup: "confirmed"`.

To verify an actual package archive, build the artifact first as above, then run:

```sh
./scripts/package.sh
elixir scripts/verify.exs installed saved-results \
  --archive dist/ipse-0.1.0-darwin-arm64.tar.gz --input "$IPSE_SAVED_ARTIFACT"
```

Replace the archive name with the file produced for your platform. The outer
verifier needs the development Elixir toolchain and `tar`. Before starting the
release, it compiles the trusted proof harness. The release uses that harness and
the prebuilt artifact; it performs no artifact or harness build. Its runtime
`PATH` contains declared shell utilities and a link to bundled `erl` only, excluding
system Elixir, Erlang, Mix and Rust tools. Verification compares the archive,
artifact, extracted release, harness and utility hashes before and after.

Run verifiers under a bounded CI/job timeout. `System.cmd/3` has no individual
process timeout. The command proof itself has a 60-second wait and retains
production callback, aggregate deadline and resource bounds. Temporary proof
homes and extracted releases are removed. The prebuilt artifact remains for
inspection; remove it when finished. These checks prove generic local publication
and recovery, not native sandbox enforcement or knowledge-package quality.

The [shared verification guide](../../docs/developer/testing.md#prove-an-independent-artifact-without-rebuilding-the-host)
explains pre-launch compilation, input inventories and isolated runtime ownership.
