# Retrieve sources with the knowledge extensions

Use Corpus to retain source text and retrieve cited passages. Use [Graph](graph.md) for
explicit attributed facts and bounded traversal. Use [Research](research-extensions.md) to investigate
provided sources or selected search/fetch services for one invocation. Select
each package independently. The [memory extensions](memory.md) keep their own
working and persistent note stores.

Start with a lexical Corpus in a scratch workspace. This example needs no model
service, embedding model or MCP server. It builds from the source checkout. If
you already have a reviewed compatible artifact, start at import instead.

## Build and select a corpus

Install the [source toolchain](arch-linux.md) or use your existing supported
Elixir/OTP installation. Run `./scripts/build.sh` from the repository root, then:

```sh
IPSE_CORPUS_ARTIFACTS=$(mktemp -d)
IPSE_CORPUS_HOME=$(mktemp -d)
IPSE_CORPUS_WORKSPACE=$(mktemp -d)
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical --instance corpus \
  --options extensions/knowledge/options/corpus-lexical.json \
  --state-binding knowledge \
  --output "$IPSE_CORPUS_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus"
```

Expect import to print an artifact digest. Review the source, manifest and
generated configuration. Inspect that actual digest with the same home:

```sh
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse extension inspect DIGEST
```

Replace `DIGEST` with the import result. Import and inspection do not run the
worker. The generated instance starts disabled with an exact trust ceiling.
Validate and explicitly select it:

```sh
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator.json" --no-project-config \
  --extension corpus
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator.json" --no-project-config \
  --extension corpus --cwd "$IPSE_CORPUS_WORKSPACE"
```

The demo provider avoids model credentials. The following commands invoke the
extension directly; they do not ask a conversation model to choose tools.

## Store text and retrieve its citation

In chat, enter:

```text
/ext ext__corpus__source {"store":"notes","action":"put","args":{"source_id":"manual:locks","generation":1,"expected_revision":0,"title":"Session locks","text":"Lock files remain on disk. Releasing the OS lock preserves inode identity.","uri":"local:manual-locks","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}}
/ext ext__corpus__query {"store":"notes","retrieval":"words","rerank":null,"query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
```

Review each proposed State write before approving it. A `put` may propose several
writes because it publishes the source after its immutable pages exist. Expect
a final `ok` result. The query returns a real passage with source identity,
generation, content hash and byte offsets. Coverage reports the selected time
and final revalidation. No usable match returns `abstain`.

`as_of_ms` is a Unix time in milliseconds. Use `null` to choose current time and
record it in coverage. Expired sources and sources observed after the selected
time do not become current evidence. Exact quotation establishes recorded bytes;
check whether they support your question before relying on an answer.

## Inspect, replace and forget a source

Inspect before changing the source:

```text
/ext ext__corpus__source {"store":"notes","action":"inspect","args":{"source_id":"manual:locks"}}
```

Coverage includes the current root revision and all chunk IDs and byte spans.
It omits the full source body. To replace the source, issue another `put` with
the next source generation and the inspected `expected_revision`. To forget it,
use `action:"forget"` with `source_id` and that exact revision. A concurrent
change produces a conflict. Inspect again before deciding on new work.

Forget publishes permanent suppression. Future queries exclude the source and
its projections. Delayed indexing or old imports cannot restore it. Earlier
journals, exports, backups and provider transfers remain. Follow
[session recovery](recovery.md) for conversations that already contain the source.

## Use larger sources and optional algorithms

Small `put` accepts at most 8192 text bytes when the work fits its invocation
allowance. Larger sources use explicit `open`, contiguous `append` calls and
`publish`, up to 64 KiB. Retain the returned draft ID, revision and next offset.
Publish verifies the declared byte count and hash. An incomplete draft is not
searchable. Inspect an interrupted draft before explicitly appending, publishing
or aborting it. Resume never completes it automatically.

Embedding indexing and graph extraction are explicit. They do not start when
you query, import or enable another package. Build a preset with the required
grants, define named profiles, select source generations and chunk IDs, and
review the separate model or egress approval. The [embedding manual](embeddings.md)
explains host profiles. The [package build guide](../../extensions/knowledge/README.md#choose-the-required-capabilities)
lists closed presets and complete configuration inputs.

Lexical retrieval uses BM25. Optional profiles select dense cosine retrieval,
hybrid fusion, bounded graph augmentation or reranking. A profile never silently
switches providers. Missing projections either refuse or follow an explicitly
configured lexical-with-gap policy. Coverage identifies the gap; it does not
mean indexing succeeded.

## Keep stores bounded and recover from refusal

State allows 256 retained record slots and 1 MiB per namespace, including drafts,
old pages and tombstones. Collection removes unreachable bodies but does not
recover record slots. Plan exports and a reviewed migration before filling the
store. Selected exports are paged. An incomplete export cannot be imported as a
complete source. Foreign copies retain historical provenance and require explicit
reindexing or extraction.

The example uses project scope and partition `manual`. Ipse supplies the actual
workspace namespace. Sharing with Graph requires the same operator State binding
and partition. A shared profile name alone does not share data. Operator scope
deliberately shares across workspaces; session scope uses that session's identity.

A named MCP store uses a fixed operator partition and selected binding. The server
must enforce partition access and atomic CAS. Approvals show the selected route
and arguments; they do not enforce a remote namespace. Configure the service
using the [MCP manual](mcp.md).

For a denied, unavailable or unknown action, read the result and coverage. Unknown
work may already have happened. Inspect the source and draft before issuing new
work; resume does not replay it. An effect or capacity refusal needs a smaller
explicit batch or reviewed store change. Grants, providers and source/vector
contents do not change automatically to make a refusal disappear.
