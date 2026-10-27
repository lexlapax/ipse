# Build the knowledge extensions

Build Corpus for retained source retrieval, Research for an explicit investigation,
or Graph for attributed facts and bounded traversal. Each package is a separate
SDK-2 artifact. Importing one does not enable another. The existing working and
persistent memory extensions keep their own selections.

The `knowledge/native` preset is a protected-capture integration component. It
builds independently with empty profile registries and uses Session source proofs
and saved collection consent. Use the [standalone permission review](../../docs/operator/knowledge-permissions.md)
to select it for a new session; importing its artifact alone grants no saved
permission. Automatic capture, managed recall and lifecycle management remain
under implementation. Follow the [capture training path](../../docs/developer/knowledge-extensions.md#follow-protected-capture-from-a-session-source)
for its actual SDK Session test and current limits.

Follow the complete user procedures for [Corpus](../../docs/operator/corpus.md),
[Graph](../../docs/operator/graph.md) and
[Research](../../docs/operator/research.md). The native main-agent
[research ledger](../../docs/operator/research.md) remains a separate workflow.

The builders require Elixir 1.18 or later, OTP 27 or later, and Ipse's public SDK
BEAM directory. Run these commands from the repository root after
`./dev/build.sh`. They use no additional packages.

Source and package builds also compile an inert `knowledge/native` artifact into
`priv/extension-bundles/` with a digest-bound catalog. The runtime can inspect that
catalog and explicitly import a selected artifact through `Extension.Bundles`;
neither step starts a worker, grants capabilities or changes configuration.
The native artifact includes a manifest-declared `operator.json` with structural
publication schemas and exact managed recipes. Capture requests the separate
`host.collection.managed` operation and explicitly advances the import floor.
A host can read the reverified sidecar bytes without loading worker code. The
schemas grant no source authority or operator acceptance; publication authenticates
proofs and normalizes source clocks independently. Current-read eligibility
remains a separate host check.
Installed users do not need a compiler for those packaged bytes. The artifact
also includes a pure development decision planner; it enables no production
strategy or automatic engine call. The [decision exercise](../../docs/developer/decisions.md#exercise-a-consumer-without-contacting-an-engine)
teaches its zero-call controls, public SDK closure and current integration limits.

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
Select `contract: "ipse-cas-v3"` for record-adding writes. Its owner must enforce
the 88 retained-record ceiling atomically across every accepted writer version. The
[remote-store procedure](../../docs/operator/corpus.md#select-a-remote-store)
includes complete options and binding examples. V1 and V2 selections retain
reads and recovery operations; adding records refuses before CAS. Switching
contracts requires an explicitly compatible service and fresh configuration.
Drain older writers and reconcile over-capacity partitions before relying on V3
admission. A draft reserves no slots for later appends: competing writes can make
an append refuse, while inspection and abort remain available within the ceiling.

For inference presets, supply `--inference-config FILE`. The file accepts only
`profiles`, `embedding_profiles` and an optional shared `budget`. It must contain
every host profile referenced by the package's embedding, extraction and rerank
registries, with an explicit provider and model. The generator preserves those
registries in its output. It never reads the ordinary home configuration or
chooses a provider. Follow the [embedding manual](../../docs/operator/extensions.md)
and [profile manual](../../docs/operator/configuration.md#reuse-a-named-model-profile) to define those routes.
Run `ipse config --config FILE --no-project-config --extension INSTANCE` to
validate the complete generated configuration before starting a session.

## Verify independent artifacts

Build Graph and Research beside the lexical Corpus built above, then run the
base proof with the common verification command:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/graph" \
  --package graph --preset state-explicit
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/research" \
  --package research --preset offline
elixir dev/verify.exs source knowledge \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_KNOWLEDGE_ARTIFACTS"
```

The verifier compiles the trusted host-side proof in a separate compiler VM
before starting the selected host. The proof imports the prebuilt worker artifacts
into private temporary homes and invokes public Sessions. Production knowledge
modules must remain absent from the host VM. Neither artifacts nor harness source
are compiled inside the running proof.

The base case checks exact citations, lexical retrieval, suppression, inert
recovery, explicit graph support and provided-source investigation. It uses
synthetic text and no model service. To inspect a narrower boundary, select its
explicit scenario with the same three artifacts:

```sh
elixir dev/verify.exs source knowledge-complete \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_KNOWLEDGE_ARTIFACTS"
elixir dev/verify.exs source knowledge-independence \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_KNOWLEDGE_ARTIFACTS"
```

`knowledge-complete` runs five checks. Research and Corpus retain ten full quotes,
including a Research citation larger than one 4096-byte fragment. Graph preserves
eight claim bases while returning one passage, and opposing assertions retain
both polarities and citation bases. The proof checks complete byte counts/hashes,
historical reads, inert restart, unchanged journals and confirmed cleanup.

`knowledge-independence` pairs each package with session-, project- and
operator-scoped explicit memory. It checks idle/resume dispatch counters,
note/evidence isolation and the combined catalog ceiling. Follow
[the selection exercise](../../docs/developer/knowledge-extensions.md#verify-independent-selection-before-algorithm-work)
for its expected observations.

Small results return inline JSON. Larger results use a `saved.result` descriptor
for a complete document of at most 4 MiB, subject to aggregate and journal limits.
Read the complete document before consuming its fields; do not remove quotes or
provenance to fit an inline reply. Follow
[contributor training](../../docs/developer/knowledge-extensions.md#publish-and-materialize-the-complete-domain-value)
for SDK ownership and [the user procedure](../../docs/operator/extensions.md#invoke-a-command-and-inspect-its-complete-result)
for `ipse result` and `/result` examples.

For the Session evaluation driver, pass the lexical Corpus artifact itself:

```sh
elixir dev/verify.exs source knowledge-evaluation \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_KNOWLEDGE_ARTIFACTS/corpus"
```

It checks synthetic paged ingestion, named profiles and durable invocation
receipts, with no model calls. It does not run a frozen quality comparison.

To exercise optional remote routes, build their separate artifacts first:

```sh
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/corpus-mcp" --package corpus --preset mcp-lexical
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_KNOWLEDGE_ARTIFACTS/research-mcp" --package research --preset mcp
elixir dev/verify.exs source knowledge-mcp \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_KNOWLEDGE_ARTIFACTS/corpus-mcp"
elixir dev/verify.exs source knowledge-research \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_KNOWLEDGE_ARTIFACTS/research-mcp"
```

The owned loopback MCP fixtures need local sockets. Corpus checks selected-only
reads, forged responses, denial and unknown recovery. Research checks selected
search/fetch tools, paged captured bodies, exact citations, completion-time
observations and inert recovery. Server scores and source text are synthetic.

## Repeat the same proofs against an installed runtime

Package for the actual host, then set `IPSE_ARCHIVE` to the exact compatible file
printed by the packager:

```sh
./dev/package.sh
IPSE_ARCHIVE=/absolute/path/to/the-compatible-archive.tar.gz
elixir dev/verify.exs installed knowledge \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_KNOWLEDGE_ARTIFACTS"
elixir dev/verify.exs installed knowledge-independence \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_KNOWLEDGE_ARTIFACTS"
elixir dev/verify.exs installed knowledge-complete \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_KNOWLEDGE_ARTIFACTS"
elixir dev/verify.exs installed knowledge-evaluation \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_KNOWLEDGE_ARTIFACTS/corpus"
elixir dev/verify.exs installed knowledge-mcp \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_KNOWLEDGE_ARTIFACTS/corpus-mcp"
elixir dev/verify.exs installed knowledge-research \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_KNOWLEDGE_ARTIFACTS/research-mcp"
```

The common verifier compiles the same trusted proof against the extracted SDK
before launch. Its runtime PATH has declared utilities and bundled `erl`, with no
system development commands. It checks unchanged archive, artifacts, host and
harness inventories. The archive and artifacts must match the platform and OTP
release. Ordinary proof runtimes and temporary homes are removed afterward.

Use [the verification guide](../../docs/developer/testing.md#prove-an-independent-artifact-without-rebuilding-the-host)
to change shared setup, and [the knowledge training manual](../../docs/developer/knowledge-extensions.md)
for recovery, interrupted inference and durable embedding selection exercises.
These fixtures establish exercised protocol behavior. They do not measure
held-out answer support, retrieval quality, web coverage or model quality.
