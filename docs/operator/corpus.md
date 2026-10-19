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
and final revalidation. A complete search with no usable match returns `abstain`.

`as_of_ms` is a Unix time in milliseconds. Use `null` to choose current time and
record it in coverage. Expired sources and sources observed after the selected
time do not become current evidence. Exact quotation establishes recorded bytes;
check whether they support your question before relying on an answer.

Read `status` together with `coverage.complete`. Deliberately forgotten, expired,
future-dated and historical sources stay excluded. Their diagnostics remain in
`gaps` and `coverage.exclusions`; they do not make an otherwise complete search
partial. A search can therefore return `ok` evidence while reporting exclusions.
Graph retrieval also excludes facts outside their validity interval, reporting
`excluded_fact`. A fact with missing or replaced source provenance remains a
`stale_fact` failure and leaves the query partial.

An unpublished source, missing vectors under an explicit fallback policy, or a
cut-off graph traversal leaves `coverage.complete: false` and `status: "partial"`.
That also applies when no passage is returned: an incomplete search cannot claim
that no usable evidence exists. Inspect the gap before publishing an answer or
deciding on further work. Combined retrieval exposes each algorithm's coverage
under `coverage.components`; fusion does not remove a component's limits.

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

## Publish a larger source

Small `put` accepts at most 8192 text bytes when the work fits its invocation
allowance. Larger sources use explicit `open`, contiguous `append` calls and
`publish`, up to 64 KiB. Retain the returned draft ID, revision and next offset.
Publish verifies the declared byte count and hash. An incomplete draft is not
searchable. Inspect an interrupted draft before explicitly appending, publishing
or aborting it. Resume never completes it automatically.

## Add explicit embeddings and reranking

This example needs an already running local Ollama service with
`embeddinggemma:latest` and `qwen3.5:9b` already available. It installs or downloads
nothing. Select your actual models and native embedding dimensions explicitly if
they differ. The [embedding manual](embeddings.md) explains host profile fields.
Keep the lexical route when you do not want model calls.

Exit the earlier chat with `/exit`. Keep the artifact parent and application home
from the first example. Create a fresh workspace and these two files in your shell:

```sh
IPSE_CORPUS_SEMANTIC_WORKSPACE=$(mktemp -d)
cat > "$IPSE_CORPUS_ARTIFACTS/semantic-options.json" <<'JSON'
{
  "version": 1,
  "stores": {"notes": {"kind": "state", "scope": "project", "partition": "manual"}},
  "search": {}, "fetch": {},
  "retrieval": {
    "words": {"kind": "bm25", "version": 1},
    "similar": {"kind": "dense", "version": 1, "embedding": "vectors"},
    "blend": {
      "kind": "hybrid", "version": 1, "lexical": "words", "embedding": "vectors",
      "graph": null, "rrf_k": 60, "missing_embedding": "refuse"
    }
  },
  "embedding": {"vectors": {"kind": "embedding", "profile": "encoder"}},
  "rerank": {"ordered": {"kind": "model_complete", "profile": "ranker", "max_candidates": 16, "quote_bytes": 128}},
  "extraction": {}
}
JSON
cat > "$IPSE_CORPUS_ARTIFACTS/semantic-inference.json" <<'JSON'
{
  "embedding_profiles": {
    "encoder": {
      "operation": "embedding", "provider": "ollama", "model": "embeddinggemma:latest",
      "credential": "none", "base_url": "http://127.0.0.1:11434",
      "dimensions": 768, "dimension_mode": "native", "timeout_ms": 120000
    }
  },
  "profiles": {
    "ranker": {
      "provider": "ollama", "model": "qwen3.5:9b", "credential": "none",
      "base_url": "http://127.0.0.1:11434", "max_output_tokens": 4096,
      "reasoning_effort": "none", "timeout_ms": 120000
    }
  },
  "budget": {"version": 1, "max_requests": 6}
}
JSON
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus-semantic" \
  --package corpus --preset state-semantic
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-semantic" \
  --package corpus --preset state-semantic --instance corpus \
  --options "$IPSE_CORPUS_ARTIFACTS/semantic-options.json" \
  --inference-config "$IPSE_CORPUS_ARTIFACTS/semantic-inference.json" \
  --state-binding knowledge \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-semantic.json"
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus-semantic"
```

Inspect the actual printed digest as before. Review the generated trust, both
inference routes and the six-request shared budget. Validate, then start a fresh chat:

```sh
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-semantic.json" --no-project-config \
  --extension corpus
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-semantic.json" --no-project-config \
  --extension corpus --cwd "$IPSE_CORPUS_SEMANTIC_WORKSPACE"
```

The main provider stays scripted. Explicit index and query commands below can
call the selected local models after their separate approvals. Importing or
selecting the extension starts no indexing.

Store and inspect one source in this fresh workspace:

```text
/ext ext__corpus__source {"store":"notes","action":"put","args":{"source_id":"manual:locks","generation":1,"expected_revision":0,"title":"Session locks","text":"Lock files remain on disk. Releasing the OS lock preserves inode identity.","uri":"local:manual-locks","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}}
/ext ext__corpus__source {"store":"notes","action":"inspect","args":{"source_id":"manual:locks"}}
```

Copy the chunk ID from the inspection result. Replace `CHUNK_ID` below with that
exact ID, then run one explicit indexing operation:

```text
/ext ext__corpus__index {"store":"notes","embedding":"vectors","source_id":"manual:locks","generation":1,"action":"next","chunks":["CHUNK_ID"]}
```

Approve only the inspected source text, the selected `encoder` route and the
shown State writes. A completed index publishes vectors for that source
generation. Each indexing invocation selects one or two chunk IDs; a larger
source needs separate explicit batches. Changing a source does not automatically
reindex it. An interrupted projection needs inspection before new work.

Compare the three retrieval choices on the same source:

```text
/ext ext__corpus__query {"store":"notes","retrieval":"similar","rerank":null,"query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
/ext ext__corpus__query {"store":"notes","retrieval":"blend","rerank":null,"query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
/ext ext__corpus__query {"store":"notes","retrieval":"blend","rerank":"ordered","query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
```

Dense retrieval uses cosine similarity. Hybrid retrieval combines lexical and
dense rankings with reciprocal rank fusion. Both send the query to `encoder`.
The last command also sends candidate IDs and excerpts to `ranker`; its output
must list every supplied ID exactly once. Inspect each egress approval, citation,
coverage and revalidation result. The example expects the retained locks passage,
not a synthesized answer. A valid model response does not prove better relevance.

The selected `missing_embedding: "refuse"` policy refuses missing/incompatible
projections. An explicit `lexical_with_gap` policy can return lexical evidence
with a reported gap; it does not mean indexing succeeded. Providers and models
never switch automatically. Budget exhaustion requires a reviewed new decision,
not an automatic retry in a fresh Session. For attributed graph augmentation,
follow the independent [Graph procedure](graph.md).

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
