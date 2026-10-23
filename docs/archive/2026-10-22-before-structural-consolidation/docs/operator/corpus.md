> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/operator/corpus.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Retrieve sources with the knowledge extensions

Use Corpus to retain source text and retrieve cited passages. Use [Graph](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/graph.md) for
explicit attributed facts and bounded traversal. Use [Research](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/research-extensions.md) to investigate
provided sources or selected search/fetch services for one invocation. Select
each package independently. The [memory extensions](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/memory.md) keep their own
working and persistent note stores.

Start with a lexical Corpus in a scratch workspace. This example needs no model
service, embedding model or MCP server. It builds from the source checkout. If
you already have a reviewed compatible artifact, start at import instead.

## Build and select a corpus

Install the [source toolchain](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/arch-linux.md) or use your existing supported
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
The generated trust includes `invoke.result.pages` for complete SDK-2 results.
Review that grant with the artifact's other capabilities.

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
Lexical, dense and server-selected retrieval use the same query-aware excerpts.
Ipse keeps a complete chunk when it fits the existing 1024-byte citation limit.
For longer chunks, it selects a cluster of query terms and includes nearby
sentence or line context within that limit. Source offsets refer to the original UTF-8 bytes,
including when Unicode downcasing changes a search term's spelling.

To inspect a condition alongside its actor, store and query another source:

```text
/ext ext__corpus__source {"store":"notes","action":"put","args":{"source_id":"manual:migration","generation":1,"expected_revision":0,"title":"Migration conditions","text":"Ada owns the migration. It proceeds only after audit.","uri":"local:manual-migration","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}}
/ext ext__corpus__query {"store":"notes","retrieval":"words","rerank":null,"query":"migration","top_k":5,"as_of_ms":1700000020000}
```

Expect the quotation to include both sentences, preserving Ada's role and the
audit condition. Longer chunks can lose distant actors or qualifications.
Context before the selected passage gets priority; a long sentence can require
a shorter byte window. Inspect the original
source when the quote leaves a condition unclear. A complete retrieval result
does not certify that its bounded quotes contain every relevant statement.

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
Graph and hybrid retrieval choose the longest complete entity name among facts
eligible at `as_of_ms`. Their graph component reports `seed`; an ineligible fact
or a substring such as `Lease` inside `Release` cannot choose that seed.
Unrelated stored facts do not consume the graph's 256-fact claim-context bound.
If the reached supporting assertions and negative context together exceed that
bound, graph and hybrid retrieval refuse with `graph_context_limit` and return
no claims. They do not omit counterassertions or silently return the lexical
component. Use a more specific query or reduce the configured graph depth or
edge limit, then inspect coverage again.

## Read a complete retrieval result

Small queries return their JSON value directly. A larger query can return a
`saved.result` descriptor containing an `output_id`, byte count and SHA256.
That descriptor identifies the complete retained result. It does not replace
the result's evidence, claims, gaps or coverage.

In the same chat, replace the example output ID with the returned one and read
the first passage's quote:

```text
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":["evidence",0,"citation","quote"]}
```

To print the complete JSON value after closing chat, keep the original session
ID and state directory. For the scratch home above, run:

```sh
IPSE_CORPUS_OUTPUT_ID='COPY_THE_64_CHARACTER_OUTPUT_ID'
IPSE_CORPUS_SESSION_ID='COPY_THE_SESSION_ID'
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse result "$IPSE_CORPUS_OUTPUT_ID" \
  --resume "$IPSE_CORPUS_SESSION_ID" --state-dir "$IPSE_CORPUS_HOME/sessions"
```

Saved documents allow up to 4 MiB of encoded JSON. Each quotation still has its
1024-byte domain limit. Transport does not shorten quotes, remove provenance,
or discard claims to fit an inline reply. An aggregate or journal-capacity
refusal publishes no partial success. Follow [saved-result reading](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extensions.md#read-a-saved-result)
for bounded views, continuation cursors and read errors.

Reading starts no query, worker or model call. The document is a historical
receipt: later replacement, expiry or suppression changes future retrieval,
not that earlier result. A model can read saved output only when an original
tool invocation disclosed it in the same session. A direct `/ext` command and
your `/result` reads do not disclose the document to the model.

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
[session recovery](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/recovery.md) for conversations that already contain the source.

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
they differ. The [embedding manual](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/embeddings.md) explains host profile fields.
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
  "rerank": {"ordered": {"kind": "model_complete", "profile": "ranker", "max_candidates": 16, "quote_bytes": 128, "output_contract": "json_schema_v2"}},
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

The reranker explicitly selects structured output through native Ollama.
The host sends a schema for the supplied short candidate IDs and required count.
Corpus still checks that every candidate appears exactly once. Malformed or
schema-invalid output fails without a repair request and retains completed usage.
Use a host supporting `model.complete` version 2 and a compatible native Ollama
service. For another provider, omit `output_contract` to select the original text
contract; the host never silently changes modes or providers.

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
generation. State indexing selects one or two chunk IDs per invocation, so larger
sources need separate explicit batches. MCP indexing selects exactly one chunk.
Each source retains at most eight projection heads across profiles. At that
ceiling, indexing with a new profile refuses with `projection_bounds` before
embedding inference or a draft claim. Updating an existing profile still uses
its current head. Inspect projection metadata and reuse an existing profile. If
a new profile is required, publish a new source generation and explicitly rebuild
its projections.

Changing a source does not automatically reindex it. An interrupted projection
needs inspection before new work.

Stored vectors also identify the embedding configuration that produced them.
Changing the selected provider, endpoint, model, dimensions, dimension mode or
host profile name makes the previous vectors incompatible, even if the server
still reports the same model name and width. Older vectors without this identity
also need an explicit reindex. Changing only a timeout preserves compatibility.
A changed server-reported model also makes old vectors incompatible. Explicit
reindexing can replace them even when the requested model and endpoint stay the
same.

After a configuration change, start a fresh chat with the reviewed configuration
and the same home and workspace. Inspect the source and run the `index` command
above with its current generation and chunk IDs. The first successful batch
replaces that embedding profile's old vector chain. Previously indexed chunks
outside the new batch need their own explicit batches before dense retrieval can
cover them again. Source text, facts and other selected profiles remain available.
Old vector pages remain until explicit collection and still consume store slots.
If a server changes weights behind an unchanged endpoint and model name, Ipse
cannot detect that change. Select a distinct model or host profile name before
reindexing so the new and old embeddings cannot be combined.

After a failed or interrupted index command, inspect the source again. If its
registered draft matches the same generation, embedding profile and selected
chunks, explicitly discard that draft before restarting work:

```text
/ext ext__corpus__index {"store":"notes","embedding":"vectors","source_id":"manual:locks","generation":1,"action":"abort","chunks":["CHUNK_ID"]}
```

Approve the matching State update. Success reports `status: "ok"` and coverage
with `status: "aborted"`, the committed source generation and its new revision.
It makes no embedding request. A changed generation, profile or chunk selection
refuses; inspect the current draft instead of retrying the old command.
An older-format vector draft can be inspected and aborted with this same command.
It cannot be resumed into a new-format index. Abort it explicitly, then review
a separate `next` command and its new embedding request.

Compare the three retrieval choices on the same source:

```text
/ext ext__corpus__query {"store":"notes","retrieval":"similar","rerank":null,"query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
/ext ext__corpus__query {"store":"notes","retrieval":"blend","rerank":null,"query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
/ext ext__corpus__query {"store":"notes","retrieval":"blend","rerank":"ordered","query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
```

Dense retrieval uses cosine similarity. Hybrid retrieval combines lexical and
dense rankings with reciprocal rank fusion. Both send the query to `encoder`.
The same chunk found by several components occupies one fused rank slot. Each
component contributes once, and the best component rank supplies its displayed
citation. Graph claims retain their own exact bases even when that representative
quotes another span in the chunk. Fusion does not combine different source
generations or Store partitions.
Dense retrieval uses the shared query-aware quotations for indexed chunks.
This changes displayed spans without changing stored chunks or vectors, so it
requires no reindex by itself. A byte boundary can end inside a long visual
combining cluster while retaining valid UTF-8 and exact source coordinates. It
does not become a missing-vector diagnostic.
The last command sends short candidate IDs, canonical source-span references and
at most 128 UTF8 bytes per excerpt to `ranker`. The model returns every short ID
exactly once; Ipse maps the order back to the original citations. Missing,
duplicate or foreign IDs refuse the response without an automatic repair request.
Those prefixes can omit relevant qualifications later in a source. Inspect each
egress approval, original citation, coverage and revalidation result before relying
on the order. Expect the retained locks passage. A valid model response does not
prove better relevance or produce a synthesized answer.

The selected `missing_embedding: "refuse"` policy refuses missing/incompatible
projections. An explicit `lexical_with_gap` policy can return lexical evidence
with a reported gap; it does not mean indexing succeeded. Providers and models
never switch automatically. Lexical and graph failures keep their own error codes;
they do not become a missing-embedding fallback. Budget exhaustion requires a
reviewed new decision, not an automatic retry in a fresh Session. For attributed graph augmentation,
follow the independent [Graph procedure](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/graph.md).

## Select a remote store

Use an MCP store with a reviewed server implementing the
[knowledge CAS contract](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/knowledge-extensions.md#implement-a-compatible-remote-store)
and enforcing its partition permissions. New record-adding work requires an
explicit `ipse-cas-v3` selection. The server must atomically limit the partition
to 88 retained records across every accepted writer route. Client receipt checks
cannot prove the server's internal transaction or access controls. No server is
installed or chosen automatically.

For a lexical Corpus, save this complete options file as
`$IPSE_CORPUS_ARTIFACTS/remote-options.json`:

```json
{
  "version": 1,
  "stores": {"notes": {"kind": "mcp_cas", "binding": "reviewed", "partition": "manual", "contract": "ipse-cas-v3"}},
  "search": {}, "fetch": {},
  "retrieval": {"words": {"kind": "bm25", "version": 1}},
  "embedding": {}, "rerank": {}, "extraction": {}
}
```

Save `{"reviewed":"mcp__local__cas"}` as
`$IPSE_CORPUS_ARTIFACTS/remote-bindings.json`. Replace the example tool ID with
the exact tool from your separate [MCP configuration](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/mcp.md), and allowlist it
there. The selected alias and partition appear in approvals. Build and configure:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus-remote" \
  --package corpus --preset mcp-lexical
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-remote" \
  --package corpus --preset mcp-lexical --instance corpus \
  --options "$IPSE_CORPUS_ARTIFACTS/remote-options.json" \
  --mcp-bindings "$IPSE_CORPUS_ARTIFACTS/remote-bindings.json" \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-remote.json"
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus-remote"
```

Inspect the printed digest and validate the configuration as in the first
procedure. Replace `/private/path/knowledge-mcp.json` below with the reviewed
server configuration:

```sh
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-remote.json" --no-project-config \
  --extension corpus --mcp-config /private/path/knowledge-mcp.json \
  --cwd "$IPSE_CORPUS_WORKSPACE"
```

Use the earlier `source` and lexical `query` commands with `store: "notes"`.
Expect separate MCP approvals and the same citation, coverage and revalidation
fields. BM25 runs on the selected source snapshot; this selection grants no
server-side ranking tool.

For an existing service, close older Sessions and drain their admitted effects
before changing writers. Qualify v3's atomic 88-record ceiling for all writer
routes, including any v1/v2 clients or administrative write API. Retire routes
that bypass it. Then explicitly select v3 in a fresh reviewed configuration and
Session. V3 changes the inner envelope version to 3 but keeps v2's action fields
and stored root/page bodies. It neither copies State data to the server nor
falls back to v2 when a request fails.

Legacy v1/v2 profiles retain reads and zero-record maintenance within their
snapshot limits. Existing-root open claims, exact abort, forget and collection
can still work. A replacement `put` creates immutable pages, as do append,
publish and projection work. Such record additions refuse
`atomic_capacity_unavailable` until v3 is selected. A v1 missing-root CAS also
lacks atomic root admission and can report `atomic_admission_unavailable`.

## Retrieve server-selected passages

Use `mcp_query` when your reviewed service supplies ranked source/chunk
references through `query-v1`. The selected store must be `mcp_cas`, and its
partition must equal the retrieval partition. Search/fetch gateway contracts for
[Research](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/research-extensions.md) are separate and cannot replace this route.

Keep the imported `corpus-remote` artifact from the preceding procedure. Save
these complete options as `$IPSE_CORPUS_ARTIFACTS/query-options.json`:

```json
{
  "version": 1,
  "stores": {"notes": {"kind": "mcp_cas", "binding": "reviewed", "partition": "manual", "contract": "ipse-cas-v3"}},
  "search": {}, "fetch": {},
  "retrieval": {"selected": {"kind": "mcp_query", "binding": "selected_query", "partition": "manual", "contract": "query-v1"}},
  "embedding": {}, "rerank": {}, "extraction": {}
}
```

Save this alias map as `$IPSE_CORPUS_ARTIFACTS/query-bindings.json`, replacing
both tool IDs with the actual reviewed tools:

```json
{"reviewed":"mcp__local__cas","selected_query":"mcp__local__query"}
```

The configured server must allowlist both tools. Generate and inspect a new
selection without rebuilding the compatible artifact:

```sh
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-remote" \
  --package corpus --preset mcp-lexical --instance corpus \
  --options "$IPSE_CORPUS_ARTIFACTS/query-options.json" \
  --mcp-bindings "$IPSE_CORPUS_ARTIFACTS/query-bindings.json" \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-query.json"
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-query.json" --no-project-config \
  --extension corpus
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-query.json" --no-project-config \
  --extension corpus --mcp-config /private/path/knowledge-mcp.json \
  --cwd "$IPSE_CORPUS_WORKSPACE"
```

In chat, query the remote sources already ingested through `notes`:

```text
/ext ext__corpus__query {"store":"notes","retrieval":"selected","rerank":null,"query":"lock files inode","top_k":5,"as_of_ms":1700000020000}
```

Review the query call and subsequent storage reads separately. The query request
contains only version 1, `contract: "query-v1"`, partition, fresh request ID,
query, `top_k` and `as_of_ms`. The complete
[request/reply contract](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/knowledge-extensions.md#implement-selected-remote-retrieval)
specifies every field and bound.

Expect `method: "mcp_query"` candidates with locally validated citations,
`score_provenance: "server_asserted"`, and remote algorithm, version, scan counts
and store generation in coverage. Ipse reads only the returned sources/chunks
at that generation and revalidates their roots. The server's scores remain its
assertions. Wrong partitions, incomplete replies, stale generations or forged
references refuse the whole result. An empty complete reference list returns
`abstain` without reading the Store. No model or embedding is required.

This route does not scan the partition directory or certify its total root count.
It does not replace the server's capacity or access policy. Keep the same
88-record guarantee for all writers even when selected queries read fewer records.

## Export sources before migration

To export the earlier source, run:

```text
/ext ext__corpus__source {"store":"notes","action":"export","args":{"source_id":"manual:locks","cursor":0,"limit":1}}
```

Read the export envelope in `coverage`. It includes source metadata, a contiguous
`text` part, total `byte_count`, `cursor`, `next`, `complete` and projection
coverage. If `next` is non-null, repeat the export with that returned byte cursor.
Retain every part in order. This command returns JSON; it does not create a file.
Use an ordinary approved workspace write to retain an export outside the journal.

`limit` is 1..4. A part contains at most `limit * 4096` raw bytes, capped at 8192
and reduced until the whole envelope fits 12000 encoded bytes. Escaped quotes,
newlines and control bytes can make a part smaller. Byte cursors always retain
valid UTF-8 boundaries. A complete offset-zero envelope may repeat `source.text`
for compatibility when the duplication fits; readers must also accept metadata
with the complete text only at the top level.

Direct `import` requires a complete offset-zero envelope with no continuation,
matching source bytes/hash and at most 8192 raw text bytes. A final fragment at a
nonzero cursor is not a whole source even when `complete` is true. Migrate larger
sources through explicit paged ingestion with the reviewed historical origin,
not by importing one fragment. Projection contents are omitted and require
explicit reindexing or extraction. Foreign source copies remain historical
assertions and do not become current evidence through those operations.

For a fresh current capture, inspect its destination root and explicitly ingest
a newer generation with the actual revision and justified observation time.
Omit `historical_import` for that fresh capture, then build required projections.
Do not present an old export as a newly observed source.

## Keep stores bounded and recover from refusal

Each partition permits 32 source roots, including unpublished drafts and
suppression markers. An import for a new source needs an unused root slot.
Collection retains roots and suppression. Use separate reviewed partitions for
new sources when the root ceiling is reached.

State permits 256 retained records and 1 MiB per namespace. A qualified MCP v3
partition permits 88 retained records and at most 1 MiB. Records include roots,
pages, drafts' staged pages, old generations, orphan pages and tombstones.
Collection removes unreachable bodies but retains their slots. Plan exports and
reviewed migration before filling either store. An open draft does not reserve
all future space, so a competing writer can make append/publication refuse.
Inspect the retained draft before continuing or approving an exact abort.

Concurrent creation can return `conflict` even when another writer changes a
different source. Inspect before deciding on a new command; Ipse does not retry
failed creation. An unknown result may already have occupied its slot.
For shared State bindings, drain older Sessions and their admitted effects and
retire older writer configurations. Arbitrary trusted State writes that omit
admission conditions can bypass the domain policy.

A full MCP snapshot uses `1 + ceil(records / 8)` calls: one directory plus groups
of at most eight records. Every MCP call consumes one of the invocation's 16
effects, including read calls. At 88 records, the snapshot consumes 12 effects,
leaving four for other work. Rechecks, writes and model calls can therefore
produce `effect_limit` before the record ceiling is reached. Increasing a batch
size or grant does not remove the selected contract's limits.

If an inherited partition exceeds 32 roots, a whole-store query returns
`root_capacity_exceeded` after its snapshot. Addressed inspect/export and
zero-record maintenance can remain available within the other limits.
Suppression retains its root and does not repair that count. If an inherited MCP
partition exceeds 88 records, `remote_snapshot_limit` precedes the root check,
even for addressed inspect, export or abort. Recover through the selected
server's reviewed administrative export/migration procedure, preserving source
identity and suppression. Ordinary Ipse addressed commands cannot bypass that
full-snapshot bound.

For a denied, unavailable or unknown action, read its result and coverage.
Unknown work may already have happened. Inspect the source/draft and relevant
service receipts before issuing new work; resume does not replay it. A definite
effect or capacity refusal needs a smaller explicit batch or a reviewed store
change. Providers, grants and stored source/vector bytes do not change
automatically to make the refusal disappear.

The State example uses project scope and partition `manual`. Ipse supplies the
actual workspace namespace. Sharing with Graph requires the same operator State
binding and partition. A shared profile name alone does not share data. Operator
scope shares across workspaces; session scope uses that session's identity.
