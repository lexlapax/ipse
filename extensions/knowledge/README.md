# Build the knowledge extensions

Build Corpus for retained source retrieval, Research for an explicit investigation,
or Graph for attributed facts and bounded traversal. Each package is a separate
SDK-2 artifact. Importing one does not enable another. The existing working and
persistent memory extensions keep their own selections.

Follow the complete user procedures for [Corpus](../../docs/operator/corpus.md),
[Graph](../../docs/operator/graph.md) and
[Research](../../docs/operator/research-extensions.md). The native main-agent
[research ledger](../../docs/operator/research.md) remains a separate workflow.

The builders require Elixir 1.18 or later, OTP 27 or later, and Ipse's public SDK
BEAM directory. Run these commands from the repository root after
`./scripts/build.sh`. They use no additional packages.

## Build a lexical corpus

Use a fresh output directory for each artifact. The builder refuses an existing
output path and publishes the artifact only after compilation succeeds.

```sh
IPSE_KNOWLEDGE_ARTIFACTS=$(mktemp -d)
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_KNOWLEDGE_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical --instance corpus \
  --options extensions/knowledge/options/corpus-lexical.json \
  --state-binding knowledge \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/corpus.json"
```

The configuration contains a disabled instance and its exact capability ceiling.
Review the source, manifest, options and trust selection before using it. Import
the artifact with `ipse extension import PATH`. Use `--extension corpus` with the
generated operator configuration to select the disabled instance explicitly.
Follow the [extension user manual](../../docs/operator/extensions.md) for import,
inspection and activation.

The `notes` store in this example has project scope and partition `manual`.
Ipse supplies the actual workspace namespace. Sharing with another artifact
requires both the same operator State binding and the same partition. A profile
name alone does not share data. Session scope expires with that session's storage
identity; operator scope deliberately shares across workspaces.

## Choose the required capabilities

The preset is compiled into the entrypoint. Configuration cannot change it.
Build only the authority needed by the selected algorithms.
All presets declare `invoke.result.pages` alongside their tool and command
capabilities. The builder and configuration generator require matching SDK-2
declarations; an SDK-1 artifact needs a new build rather than an options change.

| Package | Presets | Additional work |
| --- | --- | --- |
| Corpus | `state-lexical`, `mcp-lexical` | BM25 retrieval without model calls |
| Corpus | `state-dense`, `mcp-dense` | Explicit embeddings and cosine retrieval |
| Corpus | `state-rerank`, `mcp-rerank` | Lexical retrieval with a selected text reranker |
| Corpus | `state-semantic`, `mcp-semantic` | Embeddings and optional text reranking |
| Research | `offline` | Caller-provided source investigation, no host effects |
| Research | `mcp`, `mcp-model` | Selected search/fetch bindings, optional text reranking |
| Graph | `state-explicit`, `mcp-explicit` | Explicit attributed facts |
| Graph | `state-model`, `mcp-model` | Optional selected text extraction |

Every options file contains version 1 and all seven registries, including empty
registries. The supplied files cover lexical Corpus, offline Research and
explicit Graph. Profile validation rejects unused authority, unknown variants,
missing references and cycles before any host action. No profile accepts a
module, executable, endpoint override or arbitrary host request in command input.

For an MCP preset, supply `--mcp-bindings FILE` to the configuration generator.
The JSON object maps every selected alias to one configured tool ID, for example
`{"reviewed":"mcp__local__cas"}`. It cannot add unused aliases. Configure the
server separately through Ipse's [MCP user manual](../../docs/operator/mcp.md).
The store's partition is an operator selection that appears in approvals. The
server must enforce its own partition access and atomic CAS contract. Ipse
does not enforce a remote namespace or verify the server's internal transactions.
Select `contract: "ipse-cas-v2"` for new source creation. The
[remote-store procedure](../../docs/operator/corpus.md#select-a-remote-store)
includes complete options and binding examples. V1 selections retain reads and
existing-source updates, but missing-root creation refuses before CAS. Switching
contracts requires an explicitly compatible service and fresh configuration.
Drain older writers sharing the store before relying on atomic source admission.

For inference presets, supply `--inference-config FILE`. The file accepts only
`profiles`, `embedding_profiles` and an optional shared `budget`. It must contain
every host profile referenced by the package's embedding, extraction and rerank
registries, with an explicit provider and model. The generator preserves those
registries in its output. It never reads the ordinary home configuration or
chooses a provider. Follow the [embedding manual](../../docs/operator/embeddings.md)
and [profile manual](../../docs/operator/model-profiles.md) to define those routes.
Run `ipse config --config FILE --no-project-config --extension INSTANCE` to
validate the complete generated configuration before starting a session.

## Verify independent artifacts

Build Graph and Research into the same artifact parent used above:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/graph" \
  --package graph --preset state-explicit
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/research" \
  --package research --preset offline
mix run examples/knowledge/verify.exs "$IPSE_KNOWLEDGE_ARTIFACTS"
```

The verifier imports the artifacts into isolated temporary homes and invokes real
Session workers. It checks exact citations, lexical retrieval, suppression,
inert recovery, explicit graph support and provided-source investigation. It
requires domain modules to remain absent from the host VM. It uses synthetic
source text and no model service. These checks establish protocol behavior;
they do not measure semantic answer quality or choose an embedding model.

Use the same three SDK-2 artifacts to exercise complete results beyond the inline
reply size:

```sh
mix run examples/knowledge/verify-complete-results.exs "$IPSE_KNOWLEDGE_ARTIFACTS"
```

Expect five checks. Research and Corpus each retain ten full 1024-byte quotes.
Another Research case retains one escaped citation larger than a 4096-byte
fragment. Graph retains eight complete claim bases while returning one evidence
passage. A separate pair of opposing assertions keeps both polarities and citation
bases through Graph and Corpus graph retrieval. The exercise validates complete
byte counts and hashes, exact historical reads, inert restart, unchanged journal
bytes and confirmed cleanup. No model
service is used, and domain modules remain absent from the host.

Small results still return inline JSON. Larger results use a `saved.result`
descriptor for a complete document of at most 4 MiB, subject to aggregate and
journal limits. Per-quote and request bounds remain unchanged. Read the retained
document before consuming its domain fields; never remove quotes or provenance
to fit a reply. Follow [contributor training](../../docs/developer/knowledge-extensions.md#publish-and-read-the-complete-domain-value)
for SDK ownership and [the user procedure](../../docs/operator/extensions.md#read-a-saved-result)
for `ipse result` and `/result` examples.

Run `mix run examples/knowledge/verify-independence.exs "$IPSE_KNOWLEDGE_ARTIFACTS"`
to pair each package with session-, project- and operator-scoped memory. It checks
idle/resume dispatch counters, explicit note/evidence isolation and the combined
catalog ceiling. Follow the [selection exercise](../../docs/developer/knowledge-extensions.md#verify-independent-memory-and-knowledge-selections)
for its scope and expected output.

Run `mix run examples/knowledge/verify-evaluation.exs CORPUS_ARTIFACT` to check
the evaluation Session driver with synthetic paged ingestion, named profiles and
durable invocation receipts. It makes no model calls and is separate from a
frozen quality evaluation.

Build `corpus-mcp` with package `corpus` and preset `mcp-lexical`, then run
`mix run examples/knowledge/verify-mcp.exs ARTIFACT` to exercise a real approved
CAS/query server. The verifier starts and stops its own loopback fixture, checks
selected-only source reads, forged responses, denial and unknown recovery, and
uses no model service. Its server-side scores are synthetic assertions.

Build `research-mcp` with package `research` and preset `mcp`, then run
`mix run examples/knowledge/verify-research.exs ARTIFACT` for selected search/fetch
tools. It checks a paged captured body, exact citations, completion-time source
observations, denial, malformed responses and inert recovery. It uses a local
fixture and does not measure web coverage or model quality.

For an extracted runtime, run:

```sh
elixir examples/knowledge/verify-package.exs dist/ipse-*.tar.gz "$IPSE_KNOWLEDGE_ARTIFACTS"
elixir examples/knowledge/verify-package.exs dist/ipse-*.tar.gz "$IPSE_KNOWLEDGE_ARTIFACTS" independence
elixir examples/knowledge/verify-package.exs dist/ipse-*.tar.gz "$IPSE_KNOWLEDGE_ARTIFACTS" complete
elixir examples/knowledge/verify-mcp-package.exs dist/ipse-*.tar.gz /path/to/corpus-mcp
elixir examples/knowledge/verify-mcp-package.exs dist/ipse-*.tar.gz /path/to/research-mcp research
```

The verifiers hide development tools from the runtime PATH and check that the
archive and extracted host files remain unchanged. The MCP fixture needs loopback
sockets. Keep one matching archive in `dist/` or supply its exact path.
The `complete` mode compiles its trusted proof harness in the outer development
VM, then runs its prebuilt BEAMs and the selected artifact BEAMs inside the
extracted runtime. Its PATH contains declared host utilities and bundled `erl`,
with no system development toolchain. It also checks unchanged artifact and
proof-harness files. The archive and artifacts must match the platform and OTP
release used to build them.
