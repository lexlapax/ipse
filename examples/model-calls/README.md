# Accounted model-call artifact proof

This independently built SDK artifact wraps `model.complete` as an explicit
command. It imports only the public `Ipse.Extension` behaviour, returns plain JSON
host-call requests and receives committed receipts. It has no provider client,
credential lookup, filesystem state or direct network code. It is a synthetic
proof/example, not a shipped memory or extraction engine.

Build from the repository root after `./scripts/build.sh`:

```sh
elixir examples/model-calls/build.exs --sdk _build/dev/lib/ipse/ebin --output /tmp/ipse-model-artifact
mix run examples/model-calls/verify.exs /tmp/ipse-model-artifact
```

The build compiles reviewed repository source into an inert artifact; it does not
install or select it. The verifier imports into a temporary home, explicitly grants
`invoke.command`, `host.actions` and `host.model`, selects a loopback Ollama profile
and answers the fixture's full model-egress approvals. A local HTTP fixture sends
synthetic text/native data/counters; no installed model, sign-in or paid service
is needed. It verifies nine assertions: independent artifact, full approval,
explicit profile, private native receipt, bounded text, canonical usage, shared
configured cost aggregation, main/helper refusal and unchanged journal/budget
bytes on idle resume. Temporary state is removed; fixture rates are synthetic.

After packaging, run against a single archive:

```sh
elixir examples/model-calls/verify-package.exs dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz /tmp/ipse-model-artifact
```

Replace the archive path with the actual host's archive. The verifier extracts a
disposable release, restricts `PATH` to the existing declared shell utilities and
the bundled runtime, and refuses system Elixir/Erlang/Mix/Rust tooling. The same
proof runs against the installed host and previously built artifact; archive and
host file bytes must remain unchanged. CI runs it on Linux and macOS separately
from the earlier seven-artifact/41-assertion compatibility lab.

Source tests also build the artifact externally and run this proof. A successful
fixture proves exercised SDK/routing/accounting behavior, not live billing,
arbitrary private-data authority, OS confinement or model quality. For actual
operator selection and the closed request/receipt contract, use
[extensions](../../docs/operator/extensions.md) and
[accounted model calls](../../docs/developer/extension-model-calls.md).
