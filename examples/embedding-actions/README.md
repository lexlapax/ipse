# Native embeddings and bounded coordinate pages

This independently compiled SDK artifact exposes the explicit
`ext__embeddings__embed` command. It requests an operator-selected embedding
profile, reconstructs all returned float32 bytes from bounded coordinate pages
inside its private worker, checks their whole-vector SHA256 values, and returns
small metadata and hash summaries. It does not call a conversation model or
parse text as vectors.

Build from the repository root after building Ipse:

```sh
IPSE_EMBEDDING_ARTIFACT=$(mktemp -d)/artifact
elixir scripts/build-artifact.exs embedding-actions --sdk _build/dev/lib/ipse/ebin --output "$IPSE_EMBEDDING_ARTIFACT"
elixir scripts/verify.exs source embedding \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_EMBEDDING_ARTIFACT"
```

The manifest ID is `ipse-example/embedding-actions`. The verifier imports into a
temporary home and selects instance `embeddings` with explicit grants for
`invoke.command`, `host.actions`, `host.actions.mixed`, `host.embedding` and
`host.results`. Command arguments have exactly three required keys:

```json
{
  "profile": "local768",
  "inputs": ["Synthetic public source"],
  "timeout_ms": 10000
}
```

The profile names an operator embedding profile. There are one to eight inputs;
each input is nonempty and at most 4096 bytes, with the host enforcing the
12288-byte aggregate and unchanged SDK bounds. Timeout is an integer from 1000
to 120000 milliseconds, narrowed by the selected profile and owner. The command
cannot supply a provider, endpoint, credential, dimension or output-token cap.
Every embedding call still requires its own complete egress approval.

The result has `status`, `request_id`, `reported_model`, `usage` and `vectors`.
Each vector summary contains `index`, `bytes`, `sha256`, `input_sha256` and
`pages`. Full vectors remain private. Coordinate pages carry at most 768
float32 values encoded as Base64; ordinary public arrays retain their existing
size limit.

The twelve proof checks exercise exact approval and denied dispatch, real
loopback Ollama/OpenAI HTTP wire formats, widths 768 and 4096, all eight vectors
through 48 pages, private source ordering, canonical operation-aware metering,
a shared request/input/output budget, exhaustion without dispatch, inert resume
and absence of the artifact module from the host VM. The OpenAI loopback fixture
uses a temporary synthetic key; it never reads an account or sends credentials
to an external service. These fixtures establish transport, storage and
accounting behavior. They establish no embedding quality or live model result.

After packaging, run the same proof against the archive for the actual host:

```sh
elixir scripts/verify.exs installed embedding \
  --archive /path/to/ipse-archive-for-your-host.tar.gz --input "$IPSE_EMBEDDING_ARTIFACT"
```

The wrapper extracts a disposable release, hides system Elixir/Erlang/Mix/Rust
executables, runs the proof through the bundled runtime, and compares archive
and host files before and after. A source run alone does not establish an
installed result. Temporary sessions, fixture listeners and synthetic credential
environment changes are cleaned up.

The [shared verification guide](../../docs/developer/testing.md#run-one-proof-against-source-and-an-installed-runtime)
explains pre-launch compilation, input inventories and isolated runtime ownership.
