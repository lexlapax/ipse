# Build and exercise an Ipse example

Run these exercises from a built checkout. They use synthetic data, temporary
homes, and scripted or loopback model services. They establish host contracts,
without measuring real model quality. Ordinary users can start with the
[user manual](../docs/operator/index.md).

## Follow one Session

```sh
./dev/build.sh
mix run examples/session.exs
```

The [driver](session.exs) starts a conversation, retains an answer, closes it,
and resumes idle without another provider call. No account or model is needed.
Modify its fixed response to see how provider data becomes journaled state.

## Build an inert extension

Choose a new output path, compile the reviewed source, then verify it through
an ordinary Session. Building does not import, trust, select, or execute it:

```sh
IPSE_EXAMPLE_ARTIFACT=$(mktemp -d)/artifact
elixir dev/build-artifact.exs saved-results \
  --sdk _build/dev/lib/ipse/ebin --output "$IPSE_EXAMPLE_ARTIFACT"
elixir dev/verify.exs source saved-results \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EXAMPLE_ARTIFACT"
```

Expect a complete 4-MiB document, 1,024 fragments, matching size/digest, zero model
requests, inert resume, and confirmed cleanup. Read [saved_results.ex](saved_results.ex)
for the SDK-2 callback and [its verifier](../dev/verification/saved_results.exs)
for the public invocation, bounded view, offline materialization, and restart
checks. The SDK owns transport after the callback returns. Interrupted attempts
consume capacity; services and recovered question continuations cannot publish
saved documents.

Use the same builder/verifier pattern for these separate contracts:

| Builder recipe | Source | Verification scenario | What to inspect |
| --- | --- | --- | --- |
| `model-calls` | [model.ex](model.ex) | `model` | Named-profile inference, full egress approval, retained native receipt, canonical usage, and no replay |
| `embedding-actions` | [embedding.ex](embedding.ex) | `embedding` | Exact width, reconstructed float32 bytes, paged coordinates, operation-aware accounting, and shared budget |
| `mcp-actions` | [mcp.ex](mcp.ex) | `mcp` | Bound stdio/HTTP calls, complete UTF-8 windows, descriptor drift/refusal, and no replay |
| `saved-results` | [saved_results.ex](saved_results.ex) | `saved-results` | One callback producing a complete document through bounded SDK transfer |
| `extension-lab` | [lab sources](extension-lab/src/) | `lab` | Memory/lookup composition, questions, file workflow, and deliberate cleanup uncertainty |

For example, replace `saved-results` in both commands with `embedding-actions`
for the builder and `embedding` for verification. Embedding fixtures cover native
widths 768 and 4096, all eight vectors, approvals/denials, budget exhaustion, and
inert resume. They need no installed model or API account. Synthetic OpenAI wire
fixtures use temporary keys and loopback endpoints only.

The model scenario has five explicit selections. After building `model-calls`,
run each one using the same artifact:

```sh
IPSE_MODEL_ARTIFACT=$(mktemp -d)/artifact
elixir dev/build-artifact.exs model-calls --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_MODEL_ARTIFACT"
for IPSE_SELECTION in default none json json-none json-long; do
  elixir dev/verify.exs source model --sdk _build/dev/lib/ipse/ebin \
    --input "$IPSE_MODEL_ARTIFACT" --selection "$IPSE_SELECTION" || break
done
```

`default` omits the native
thinking selector; `none` checks `think: false`. `json` and `json-none` add native
structured output. `json-long` captures an explicit 480000-ms policy while the
fixture replies promptly. It does not prove an eight-minute live request. Invalid
schema, identity, budget, or result cases refuse without repair calls.

MCP verification uses a reviewed local [fixture](../dev/fixtures/mcp.exs), not a
mandatory retrieval service. It covers full descriptor-bound approval, retained
source ordering, mixed read/effect bounds, and denied dispatch. The separately
configured real service retains its own remote-work and data-transfer limits.

## Try the lab manually

Build `extension-lab` as above, using `IPSE_LAB_ARTIFACTS` for its output. The
builder creates seven separately compiled artifacts. Generate an operator file:

```sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)/artifacts
elixir dev/build-artifact.exs extension-lab --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_LAB_ARTIFACTS"
IPSE_LAB_HOME=$(mktemp -d)
IPSE_LAB_WORKSPACE=$(mktemp -d)
elixir examples/extension-lab/config.exs "$IPSE_LAB_ARTIFACTS" "$IPSE_LAB_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/memory"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/lookup"
```

Review source, manifests, printed digests, and generated trust/routes. All instances
start disabled. Import alone executes nothing. Select only memory and lookup:

```sh
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_LAB_ARTIFACTS/operator.json" --no-project-config \
  --extension memory --extension lookup --cwd "$IPSE_LAB_WORKSPACE"
```

In chat:

```text
/ext ext__memory__remember {"text":"entity: Ada; link: Ada -> OTP"}
/ext ext__memory__recall {"text":"Ada"}
/ext ext__memory__export {}
/ext ext__memory__stats {}
/ext ext__memory__workflow {"path":"lab-note.txt"}
```

Approve each state/file effect with its printed code and answer questions using
their separate codes. Expect recalled labels, complete source data, revision/count
metadata, and an approved note file. `stats` reads metadata without recreating
state, consulting lookup, or publishing context. Both caller and service target
must be selected. No missing dependency is installed automatically.

Then invoke `/ext ext__memory__forget {"entity":"all"}`, approve it, and recall
again. The tombstone suppresses recreation. Earlier journals/results/exports remain.
This project-scoped synthetic memory has its own schema and identity; use
[bundled Memory](../docs/operator/memory.md) for ordinary explicit notes.

The automated lab ends with a deliberate service crash and
`safe_to_continue: false`. Exit zero means its expected positive and negative
assertions matched, not that every callback or cleanup succeeded.

## Verify the same artifact against a release

Package the current source and use the exact archive produced for this host:

```sh
./dev/package.sh
elixir dev/verify.exs installed saved-results \
  --archive /absolute/path/to/the-produced-archive.tar.gz \
  --input "$IPSE_EXAMPLE_ARTIFACT"
```

Substitute the same scenario/artifact used in the source proof. For `model`,
repeat all five selections with installed mode. The outer verifier needs the
development toolchain and `tar`; it compiles the trusted harness before launch.
The extracted release uses its bundled runtime with system Elixir/Erlang/Mix/Rust
hidden, and does not compile artifacts or the harness. Inventories bind the
archive, artifact, release, harness, and declared utilities before/after execution.
A source result alone establishes no installed-runtime result.

Use a bounded CI/job timeout. The wrapper's `System.cmd/3` has no individual process
timeout; scenario callbacks/owners retain their production bounds. Temporary homes,
listeners, and releases are removed, while the built input remains for inspection.
These examples do not establish native sandbox enforcement, browser login, real
model quality, or external-service correctness.

Knowledge packages have a separate [build entry](../extensions/knowledge/README.md)
and [training path](../docs/developer/knowledge-extensions.md). The small
[memory-corpus.json](memory-corpus.json) is a public synthetic input, not held-out
evaluation evidence. Follow [verification training](../docs/developer/testing.md)
for complete acceptance and failure coverage.
