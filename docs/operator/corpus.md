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
refusal publishes no partial success. Follow [saved-result reading](extensions.md#read-a-saved-result)
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
Dense citations take at most the first 200 graphemes of a chunk, bounded again
to 1024 UTF-8 bytes. A long combining sequence can end inside that visual cluster
while retaining valid UTF-8 and exact byte coordinates. It does not become a
missing-vector diagnostic.
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

## Select a remote store

Use an MCP store only with a configured server implementing the knowledge CAS
contract and enforcing its partition permissions. To create new sources, select
`ipse-cas-v2` explicitly. The client checks returned receipts; it cannot verify
the server's internal transaction or access controls. No server is installed or
chosen automatically.

For a lexical Corpus, save this complete options file as
`$IPSE_CORPUS_ARTIFACTS/remote-options.json`:

```json
{
  "version": 1,
  "stores": {"notes": {"kind": "mcp_cas", "binding": "reviewed", "partition": "manual", "contract": "ipse-cas-v2"}},
  "search": {}, "fetch": {},
  "retrieval": {"words": {"kind": "bm25", "version": 1}},
  "embedding": {}, "rerank": {}, "extraction": {}
}
```

Save `{"reviewed":"mcp__local__cas"}` as
`$IPSE_CORPUS_ARTIFACTS/remote-bindings.json`, replacing `mcp__local__cas` with
the exact tool ID from your separate [MCP configuration](mcp.md). The alias and
partition appear in approvals. Build and configure a fresh artifact:

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

Inspect the printed digest and validate the generated configuration as in the
first procedure. Start chat with `--config` pointing to `operator-remote.json`
and `--mcp-config` pointing to your reviewed MCP file. Use the earlier `source`
and lexical `query` commands with the selected `notes` store. Expect separate
MCP approvals and the same citation, coverage and revalidation fields.

An existing `ipse-cas-v1` selection can still read and update existing sources.
Creating a missing source refuses with `atomic_admission_unavailable` before
its write. Stop older writers, verify the server's v2 support, then explicitly
select v2 in a fresh reviewed configuration and Session. Changing the contract
does not copy local State data to that server or change stored root/page formats.

## Keep stores bounded and recover from refusal

Each partition permits 32 source roots, including unpublished drafts and
suppression markers. An import for a new source needs an unused source slot.
Use a separate reviewed partition
for new sources when that limit is reached; collection retains existing roots.
State allows 256 retained record slots and 1 MiB per namespace, including drafts,
old pages and tombstones. Collection removes unreachable bodies but does not
recover record slots. Plan exports and a reviewed migration before filling the
store. Selected exports are paged. An incomplete export cannot be imported as a
complete source. Foreign copies retain historical provenance and stay excluded
from current queries after indexing or extraction. For a freshly verified current
capture, inspect the root and repeat the ingestion procedure as an explicit
replacement with a newer generation and current revision. Omit
`historical_import` for that fresh capture, then build its required projections.

Concurrent creation can return `conflict` even when another writer changed a
different source. The first write checks the store generation used to count
available slots. Inspect before deciding on a new command; Ipse does not retry
the failed creation. An unknown result may already have occupied its slot.

When updating artifacts that share a State binding, close older Sessions and
wait for their admitted effects to finish before selecting the new writers.
Retire their old writer configuration. The bound relies on every writer using
the current admission check; older artifacts or direct trusted State writes can
bypass it. Existing valid stores need no data conversion.

If an older partition already exceeds 32 roots, a whole-store query refuses with
`root_capacity_exceeded` once its snapshot completes. A selected remote query
reads only the server-selected sources and does not check total root count.
Keep the data and use `inspect` and paged `export` for each known source ID when
the store fits the read limits below. Existing-source replacement and suppression
remain available within the other store limits. Suppression still occupies its root,
so it does not lower this count. Plan a reviewed migration into separate bounded
partitions instead of deleting markers or editing the State file.

An MCP full-store operation needs at most 12 calls to capture its snapshot.
That permits 88 retained records, including pages and tombstones, in the selected
server partition. At 89 records, `remote_snapshot_limit` refuses before the
root-count check, even for `inspect`, `export` or existing-source maintenance.
Use the configured server's reviewed administrative export/migration procedure
to recover a larger store. Preserve source identities and suppression markers.
Ipse's addressed commands cannot recover it through this bounded contract.

For a denied, unavailable or unknown action, read the result and coverage. Unknown
work may already have happened. Inspect the source and draft before issuing new
work; resume does not replay it. An effect or capacity refusal needs a smaller
explicit batch or reviewed store change. Grants, providers and source/vector
contents do not change automatically to make a refusal disappear.

The example uses project scope and partition `manual`. Ipse supplies the actual
workspace namespace. Sharing with Graph requires the same operator State binding
and partition. A shared profile name alone does not share data. Operator scope
deliberately shares across workspaces; session scope uses that session's identity.
