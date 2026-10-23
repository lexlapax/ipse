> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/examples/README.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Accounted model-call artifact proof

This independently built SDK artifact wraps `model.complete` as an explicit
command. It imports only the public `Ipse.Extension` behaviour, returns plain JSON
host-call requests and receives committed receipts. It has no provider client,
credential lookup, filesystem state or direct network code. It is a synthetic
proof/example, not a shipped memory or extraction engine.

Build from the repository root after `./scripts/build.sh`:

```sh
IPSE_MODEL_ARTIFACT=$(mktemp -d)/artifact
elixir scripts/build-artifact.exs model-calls --sdk _build/dev/lib/ipse/ebin --output "$IPSE_MODEL_ARTIFACT"
elixir scripts/verify.exs source model --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_MODEL_ARTIFACT" --selection default
elixir scripts/verify.exs source model --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_MODEL_ARTIFACT" --selection none
elixir scripts/verify.exs source model --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_MODEL_ARTIFACT" --selection json
elixir scripts/verify.exs source model --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_MODEL_ARTIFACT" --selection json-none
elixir scripts/verify.exs source model --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_MODEL_ARTIFACT" --selection json-long
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

Run all five selections. The first leaves thinking at the backend default and checks
that no `think` field is sent. The second explicitly selects an Ollama profile
with `reasoning_effort: "none"`, checks native `think: false`, and restores the
same execution fact on idle resume. `json` and `json-none` select version-2 structured
output and check the exact native JSON Schema, once with each thinking selection.
`json-long` selects version three, with explicit root/profile/request deadlines
of 480000 milliseconds and the same schema and output ceiling. The fixture
responds promptly; it tests the captured allowance, approval, source-tamper
refusal and inert resume, without claiming an eight-minute live inference.
The response keeps the same text/usage envelope. All five use the synthetic HTTP
fixture, with no repair or retry.

After packaging, set `IPSE_ARCHIVE` to the exact compatible archive printed by
`./scripts/package.sh`, then run the same five selections:

```sh
elixir scripts/verify.exs installed model \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_MODEL_ARTIFACT" --selection default
elixir scripts/verify.exs installed model \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_MODEL_ARTIFACT" --selection none
elixir scripts/verify.exs installed model \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_MODEL_ARTIFACT" --selection json
elixir scripts/verify.exs installed model \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_MODEL_ARTIFACT" --selection json-none
elixir scripts/verify.exs installed model \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_MODEL_ARTIFACT" --selection json-long
```

The outer verifier compiles the trusted proof against the extracted SDK before
starting the installed host. The verifier extracts a
disposable release, restricts `PATH` to the existing declared shell utilities and
the bundled runtime, and refuses system Elixir/Erlang/Mix/Rust tooling. The same
proof runs against the installed host and previously built artifact; archive and
host file bytes must remain unchanged. CI runs it on Linux and macOS separately
from the earlier seven-artifact/41-assertion compatibility lab.

Source tests also build the artifact externally and run this proof. A successful
fixture proves exercised SDK/routing/accounting behavior, not live billing,
arbitrary private-data authority, OS confinement or model quality. For actual
operator selection and the closed request/receipt contract, use
[extensions](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extensions.md) and
[accounted model calls](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/extension-effects.md#request-bounded-text-inference).
