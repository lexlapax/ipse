# Store sources and retrieve cited passages

Use Corpus to retain source text and retrieve cited passages. Use [Graph](graph.md) for
explicit attributed facts and bounded traversal. Use [Research](research.md) to investigate
provided sources or selected search/fetch services for one invocation. Select
each package independently. The [memory extensions](memory.md) keep their own
working and persistent note stores.

Start with packaged lexical document support in a scratch workspace. It needs
no embedding model, MCP server or secondary model service. The conversation
keeps your chosen provider; direct extension commands can use the credential-free
demo provider. Source-build procedures below cover other independently selected
Corpus configurations.

## Set up packaged Word support

Use an installed `ipse` or `./ipse` in an extracted release. In a built source
checkout, substitute `./bin/ipse`. Preview a small project-scoped State store:

```sh
ipse documents setup --profile state --cwd /path/to/workspace
ipse documents setup --profile state --cwd /path/to/workspace --write
ipse config --no-project-config --cwd /path/to/workspace
ipse chat --provider demo --no-project-config --cwd /path/to/workspace
```

Replace the workspace path with an existing directory. The preview creates no
home, artifact or identity. `--write` requires a native terminal and a fresh
`enable CODE` review of the exact artifact, options and trust grant. Piped input,
bare `yes` and `--yes` cannot authorize it. Saving imports the selected shipped
artifact without executing it and adds the `documents` instance to your private
operator configuration. No source toolchain, manual artifact build or JSON edit
is needed. The instance starts in the next new session using that configuration;
its store is separately scoped to each workspace. Running sessions keep their
pinned selection; ordinary resume requires the original configuration bytes.
Setup neither changes the conversation route nor enrolls notes
capture. Retrieved excerpts can reach the selected conversation provider.

Put a supported small `.docx` named `source.docx` in the workspace. In chat, issue
one command at a time, finish each approval and wait for `Finished.`:

```text
/ext ext__documents__source {"store":"notes","action":"read_document","args":{"source_id":"workspace:source","generation":1,"expected_revision":0,"title":"Workspace Word document","path":"source.docx","expected_sha256":null,"uri":"workspace:source.docx","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}}
/ext ext__documents__query {"store":"notes","retrieval":"words","rerank":null,"query":"words from your document","top_k":5,"as_of_ms":null}
```

Use words present in your document. If acquisition returns `draft`, copy its
complete continuation command and finish it before querying. Inspect the returned
quotation, original-file hash, locator, status and coverage. The
[acquisition limits](#acquire-a-small-word-document-from-the-workspace) apply to
both packaged profiles. State retains the small-store ceilings described below.

For experimental native Collection storage, explicitly choose project identity
scope in the same home:

```sh
ipse documents setup --profile collection --scope folder --cwd /path/to/workspace
ipse documents setup --profile collection --scope folder --cwd /path/to/workspace --write
```

Use `--scope repository` at a canonical primary Git root to select repository
identity instead. There is no automatic folder fallback. Native review includes
admission/revalidation of that exact root; failed admission leaves configuration
unchanged, although an inert imported artifact can remain. Collection operations
also require a supported protected-storage profile. After ingesting sources,
[build the lexical index](#query-a-document-collection) before an ordinary query.
This explicit profile does not promise full-capacity, migration or Word fidelity
qualification.

If `documents` already exists, preview with `--replace` to review its replacement.
Setup preserves other instances, profiles and trust. It refuses an incompatible
existing trust grant for the same artifact. Both setup and disable support
`--config PATH`; otherwise they use `IPSE_CONFIG`, then `IPSE_HOME/config.json`.
Saving retains a private timestamped backup of an existing file. A concurrent
setup writer or changed file refuses; inspect the configuration and preview again.
Old trust entries and stored data remain after replacement.

Exit chat, then preview and review disabling the instance for new sessions:

```sh
ipse documents disable
ipse documents disable --write
```

Disabling retains stored sources and trust. It does not revoke a running
session's pinned authority or delete earlier results. Re-enabling requires a new
setup review with `--replace`.

## Build and select a corpus

Install the [source toolchain](arch-linux.md) or use your existing supported
Elixir/OTP installation. Run `./dev/build.sh` from the repository root, then:

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

In chat, run one command at a time. Finish the `put` and all its approvals, wait
for `Finished.`, then submit the query. Follow that sequence for later command
blocks too; pasting several `/ext` lines can refuse the later commands as busy:

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

`as_of_ms` filters current retained versions. It does not restore earlier versions
that have been replaced. If the current version has `observed_at_ms: 200` and you
query with `as_of_ms: 150`, that version is excluded and the previous one is
unavailable to the query. The
query can therefore abstain with complete coverage of eligible retained sources.

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

## Acquire a small Word document from the workspace

Use the explicit `state-documents` preset when Corpus should acquire a `.docx`
file through the native workspace read tool. This preset adds `host.tools` to
lexical State authority. Existing `state-lexical` artifacts cannot acquire files.
The current acquisition limit is **32,768 original file bytes**, read in
hash-bound pages of at most 4096 bytes. Larger originals refuse rather than
losing content. Extracted text is bounded separately at 64 KiB and 32 chunks.
Typed locator metadata is bounded at 16 KiB, 32 stored groups and 32 warnings; its
paging and the store's total capacity can refuse earlier. Nothing trims text or
warnings to fit.

Close the preceding chat with `/exit`. Keep its artifact parent and application
home, then build a separate artifact and configuration:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus-documents" \
  --package corpus --preset state-documents
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-documents" \
  --package corpus --preset state-documents --instance corpus \
  --options extensions/knowledge/options/corpus-lexical.json \
  --state-binding knowledge \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-documents.json"
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus-documents"
```

Inspect the printed digest with `ipse extension inspect DIGEST` using the same
`IPSE_HOME`, and review the new native-tool grant. Put your small document at
`$IPSE_CORPUS_WORKSPACE/source.docx`, then validate and start a new chat:

```sh
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-documents.json" --no-project-config \
  --extension corpus
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-documents.json" --no-project-config \
  --extension corpus --cwd "$IPSE_CORPUS_WORKSPACE"
```

Run the source command first and complete its proposed State-write approvals:

```text
/ext ext__corpus__source {"store":"notes","action":"read_document","args":{"source_id":"workspace:source","generation":1,"expected_revision":0,"title":"Workspace Word document","path":"source.docx","expected_sha256":null,"uri":"workspace:source.docx","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}}
```

Text up to 8192 bytes with small locator metadata can publish in that invocation.
Larger text or locator metadata opens an unpublished draft and returns
`continuation` containing `id: "source"` and the
complete next `arguments`. Copy those arguments unchanged into a new
`/ext ext__corpus__source` command. Finish its approvals, then use the next returned
continuation. It stages locator metadata first in slices of at most 1,024 bytes,
then text in parts of at most 4,096 UTF-8 bytes, before publishing the complete draft.
Do not edit returned metadata/text offsets. A replacement keeps the earlier source selected until that
final publication. Do not query the draft as if it were published.

A draft has a finite expiry. State-backed draft writes retain that expiry through
approval and synced staging; if it elapses before the final locked publication
decision, `write_deadline_elapsed` refuses the replacement. A previously admitted
native replacement can finish later. Ordinary document Collection stages use
their own final locked decision, described below; managed-derived mutations
retain separate refusal gates. Do not strip a deadline to continue a draft.
A check never renews it.
Inspect the retained source/draft and explicitly collect expired work before
starting again. An interrupted stage may have written private pages; resume does
not automatically repeat acquisition or publication.

After publication, choose a query matching your document:

```text
/ext ext__corpus__query {"store":"notes","retrieval":"words","rerank":null,"query":"migration audit","top_k":5,"as_of_ms":null}
```

Corpus reconstructs the complete native binary pages, checks their complete-file
hash, extracts the acquired bytes and performs a fresh hash-pinned read before
proposing source writes. Every continuation reacquires the same original.
A changed file refuses before that stage's storage writes.
Symlinks, nonregular files, oversized input, invalid packages and exceeded text
or metadata bounds refuse. No model service is required.

A hit's document citation binds the original binary hash, extraction recipe and
paragraph or table-cell locator alongside the exact text offsets. Inspect
`status`, `coverage.complete` and `gaps`: unsupported relationships or document
features can leave the result partial. A citation records an acquired snapshot;
it does not assert that the workspace file is still unchanged. Ipse does not
watch this file or automatically refresh it.

Short paragraphs and table cells can share a stored chunk while retaining their
original locations. A quotation covering several blocks has an ordered
`document.spans` list, with its columns identified by `span_fields`; a quotation
inside one block keeps the ordinary `document.locator`. Both forms preserve exact
quotation offsets and table coordinates. The same text, metadata and chunk limits
still apply, so complex or larger documents may refuse rather than lose locators.

Word tables may use nonhidden named styles. A table style with hidden-text
properties or an unresolved or ambiguous reference refuses extraction; numbered
list properties also remain unsupported. A document with both `styles.xml` and
`stylesWithEffects.xml` is readable only when their checked style graphs agree.
Different style types, inheritance, defaults or hidden-text settings refuse;
unsupported effect namespaces also refuse. The current DOCX recipe is
`ipse-documents-v14`. Reacquire and explicitly replace an older source when you
need the newer recipe; existing extractions are not silently rebuilt.

For replacement, inspect the source and use its current revision with the next
generation. Supply the new file's concrete SHA-256 as `expected_sha256`; only an
initial generation-one/revision-zero acquisition permits `null`. The native
`read` tool with `encoding: "base64"`, `byte_offset: 0`, `file_max_bytes: 32768`
and `max_bytes: 4096` returns the complete-file hash with its first page.
Do not retry an interrupted write automatically; inspect the stored source and
draft before choosing a new explicit continuation. Forgetting uses the preceding ordinary source
management procedure. The remote equivalent is the explicitly selected
`mcp-documents` preset with the reviewed CAS binding and its separate approvals.

## Query a document Collection

The experimental `collection-documents` preset uses a fixed project document
Collection instead of State. Use the packaged setup above to review its project
identity and selection together, or supply an identity **already admitted in the
selected home** for the manual artifact procedure below. It requires a matching
native helper and available protected-storage profile. Full-profile capacity,
build/rebuild peaks and Word fidelity remain unqualified.

For an existing admitted project, save these options as
`$IPSE_CORPUS_ARTIFACTS/collection-options.json`:

```json
{
  "version": 1,
  "stores": {"notes": {"kind": "collection", "scope": "project", "partition": "manual"}},
  "search": {}, "fetch": {},
  "retrieval": {"words": {"kind": "bm25", "version": 1}},
  "embedding": {}, "rerank": {}, "extraction": {}
}
```

Close the old chat. Build a separate artifact and generate its disabled selection:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus-collection" \
  --package corpus --preset collection-documents
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-collection" \
  --package corpus --preset collection-documents --instance corpus \
  --options "$IPSE_CORPUS_ARTIFACTS/collection-options.json" \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-collection.json"
```

The generator derives the exact `collection_bindings` trust entry with ID
`documents`, project scope and profile `document_graph_v1`. This preset has no
State binding. Review its `host.collection.store` and workspace-tool grants;
neither admits a project nor enables automatic capture or a saved knowledge grant.

Replace the following paths with the existing admitted home and workspace:

```sh
IPSE_CORPUS_COLLECTION_HOME=/path/to/existing/private-home
IPSE_CORPUS_COLLECTION_WORKSPACE=/path/to/already-admitted/project
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus-collection"
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-collection.json" --no-project-config \
  --extension corpus
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-collection.json" --no-project-config \
  --extension corpus --cwd "$IPSE_CORPUS_COLLECTION_WORKSPACE"
```

Import/inspection and this configuration do not perform project admission. A
missing or changed binding refuses; use explicit document setup with the desired
scope rather than granting notes capture to make a document read work.

After acquiring sources, explicitly build the namespace lexical index:

```text
/ext ext__corpus__lexical_index {"store":"notes","action":"begin","continuation":null}
```

For the packaged instance, use `ext__documents__lexical_index`. A `draft` result
returns its complete next command; copy that command unchanged, finish approvals
and continue until `ok`. Then use the ordinary `query` command. A missing index
returns `lexical_namespace_index_unavailable`; a changed catalog makes the index
stale and requires an explicit rebuild. Index construction uses storage writes,
with separate ordinary approvals, and calls no model.

An explicit `query_selected` takes `store`, `retrieval`,
`query`, `top_k`, `as_of_ms` and one to eight exact `source_ids`; it omits `rerank`.
Inspect citations, `status`, `coverage.complete`, `namespace_complete` and gaps.
A changed catalog or stale index refuses instead of answering from a mixed snapshot.
The lexical preset accepts BM25. For selected shared vectors, use the separate
[semantic query procedure](#query-selected-shared-vectors); ordinary namespace
`query` remains lexical.

Each exact ordinary stage mutation checks the earlier of its original one-hour
expiry and any trusted inherited deadline after synced staging, immediately
before the native root replacement. Expiry refuses a new decision; a replacement
already admitted before expiry can finish later. Successful consumption removes
its exact stage references in the same CAS. An unknown result may have changed
storage and returns no safe automatic continuation. Inspect before new work;
do not replay stages or remove protected files. Read-time source expiry remains
separate from transport-stage expiry.

Managed-derived document mutations refuse before approval/intent, with a second
execution check for an already queued action. Its document grant supplies no
protected-note permission. The separately reviewed `/remember` new-v3 capture
and native `knowledge forget` routes use their own authority; session-only
retention uses the same reviewed removal; other retention choices have their
own reviewed management path. Supersession remains closed. See
[protected knowledge procedures](knowledge-permissions.md) for those limits;
full notes readiness and automatic headless capture remain unqualified.
No fallback to State, MCP or a different namespace occurs. Follow
[protected recovery](recovery.md#inspect-unconfirmed-protected-knowledge) for
uncertain effects and unavailable native storage.

## Inspect supplied shared projections

For a Collection that already has a supplied shared generation, Corpus exposes
`projection_selected` and `generation_job`. These are experimental inspection and
explicit build-control APIs; they neither call an embedding/extraction model nor
prove the supplied projections' model provenance. Keep their exact recorded
selectors, rather than guessing a profile from its display name:

| Command | Complete argument fields |
| --- | --- |
| `projection_selected` | `store`, one to eight unique `source_ids`, `vector_selection`, `fact_selection`, `as_of_ms` (integer or null), `top_k` (1..8) |
| `generation_job` | `store`, `action` (`begin`, `inspect`, `abort`, `finalize` or `finalize_paged`), `continuation` (object or null), `vector_selection`, `fact_selection`; optional `response` (`full` or `compact_v1`) and `guard_sources` (boolean for dense finalization) |

The vector selector contains `selection_sha256`, `profile`, `model`, `dimensions`
and `encoding: "float32le"`; copy the exact recorded selection. The fact selector
is the recorded extraction identity; explicit supplied facts use
`{"kind":"explicit","profile":null,"version":1}`. A changed selector, source
head, floor or catalog refuses. `projection_selected` hydrates complete selected
groups and raw source bundles before returning bounded eligible claims in stored
order with exact citations. It reports vector/fact counts, partial-document
warnings and fact-window exclusions; it is not a vector similarity search.
Hydration is limited to 512 reads and can refuse a wide selection without
returning partial evidence. The result grants no authority for a later use.

Start recovery with `generation_job` action `inspect`, using the exact selections
for that retained job. `begin` initializes a job; it does not supply all projection
groups. The dense producer can append a group after its vector pages and explicit
facts are ready, as described below. `finalize` requires those captured groups and advances bounded
manifest, entity-merge and digest phases. Known intermediate progress returns
`status: "draft"` with a complete `continuation` command. Copy its `id` and full
`arguments` unchanged, finish approvals, and wait before issuing the next one.
Only final `selected` status switches the new generation into use. `abort`
requires the exact inspected continuation and does not constitute general garbage
collection. Timeout/unknown means inspect, never automatically repeat or edit a
continuation to skip work.

For repeated `generation_job` steps, add `"response":"compact_v1"` to its arguments. It returns
`coverage.job_progress` with the complete logical Job digest, size and bounded
progress instead of repeating the whole Job. The exact continuation and limits
remain unchanged, and returned commands carry that option. Omit it or select
`"response":"full"` for the complete Job value. A progress digest is not a
backup, read permission or proof that interrupted work did not happen.

For a known committed Job step, a stage-free continuation has `unit: 0`,
`write: null` and `stages: []`. After confirmed closure of that Session, a fresh
Session in the same admitted project with the same explicitly trusted artifact
can inspect the retained job using its exact selectors and a null continuation,
then use the newly returned token. This does not authorize transferring active
stages or automatically continuing an unknown effect. A token's empty fields
alone do not prove that the preceding operation completed.

For a complete captured job still at its `manifests` phase, choose
`finalize_paged` before starting the older `finalize` reduction. It uses smaller
entity pages and durable page verification for wider metadata. Keep the exact
inspected continuation and selections; after choosing this path, follow only
its returned complete commands. A job already reduced by `finalize` cannot
switch paths. Existing selected generations remain readable; no automatic
conversion occurs on a budget refusal.

For a `collection-dense` instance configured with the explicit
`shared_producer_v1` Collection binding, include `"guard_sources":true` on the
first `finalize_paged` or `finalize` command. Returned continuations retain the
choice. At the final switch the host checks the captured manifest groups against
the current catalog and source bytes, requires one unchanged native generation,
and refuses expired, future-observed or historical sources. The binding is
required for this option; an older Collection binding cannot use it. A selected
producer cannot publish its generation by omitting the guard. This check does
not establish that supplied facts are true or that vectors came from a model.

Both finalization paths have focused native Session selection and recovery
controls using small supplied generations. Complete acquisition,
shared-generation build, full capacity/rebuild peaks, GC, job reclamation and
migration remain unqualified. Ordinary document staging
support does not qualify those journeys or turn a fixture-supplied generation
into a complete ingestion workflow. The document namespace retains its fixed
8,192-key/32,768-operation ceilings and 192 MiB native allocation limit; preparing
a large generation also needs room for old, staged and replacement data. These
ceilings are not a measured full-profile capacity promise. Refusal calls for
inspection and an explicit recovery decision, never raising a worker quota.

To inspect an explicitly configured embedding selection, use the separate opt-in
`collection-dense` preset. It adds embedding/result grants; review them when
building/selecting that artifact. In a chat already configured with that preset,
the Collection store `notes` and embedding alias `vectors`, run:

```text
/ext ext__corpus__generation_produce {"store":"notes","version":1,"action":"selection","embedding":"vectors"}
```

This setup needs no Job or source and makes no inference request or Usage charge.
It returns `configured_profile`, `selection_sha256` and `reported_model: null`.
The configured model name is not an observed provider model or proof of weights.
Keep the returned digest when selecting future pinned work; a changed selection
refuses before inference rather than silently switching routes. Existing legacy
unpinned calls retain their separate contract. The
[embedding procedure](#add-explicit-embeddings-and-reranking) explains explicit
host routes and approvals; its State example does not itself select a Collection
preset.

### Produce shared vector pages

Use a separate source-bound `collection-dense` instance for this experimental
page producer. It requires an already admitted project, current stored
sources, an explicit 1,024-dimensional embedding profile and a registered inference
service. A vector-page call prepares the vectors; use the explicit-fact,
group-append and finalization procedures below to assemble and select a
generation. It does not call an extraction model. The existing
`collection-documents` preset keeps its supplied-generation procedures and grants.

For an already installed local embedding model, replace
`REPLACE_WITH_INSTALLED_1024_MODEL` below with its exact model name. This example
explicitly selects the loopback Ollama route; it neither downloads a model nor
switches provider or billing. Create the two input files:

```sh
cat > "$IPSE_CORPUS_ARTIFACTS/producer-options.json" <<'JSON'
{
  "version": 1,
  "stores": {"notes": {"kind": "collection", "scope": "project", "partition": "notes"}},
  "search": {}, "fetch": {},
  "retrieval": {"words": {"kind": "bm25", "version": 1}},
  "embedding": {"vectors": {"kind": "embedding", "profile": "encoder"}},
  "rerank": {}, "extraction": {}
}
JSON
cat > "$IPSE_CORPUS_ARTIFACTS/producer-inference.json" <<'JSON'
{
  "embedding_profiles": {
    "encoder": {
      "operation": "embedding", "provider": "ollama",
      "model": "REPLACE_WITH_INSTALLED_1024_MODEL", "credential": "none",
      "base_url": "http://127.0.0.1:11434", "dimensions": 1024,
      "dimension_mode": "native", "timeout_ms": 100000
    }
  },
  "inference_services": {"local": {"version": 1, "origins": ["http://127.0.0.1:11434"]}},
  "budget": {"version": 1, "max_requests": 4}
}
JSON
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus-producer" \
  --package corpus --preset collection-dense
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-producer" \
  --package corpus --preset collection-dense --instance producer \
  --options "$IPSE_CORPUS_ARTIFACTS/producer-options.json" \
  --inference-config "$IPSE_CORPUS_ARTIFACTS/producer-inference.json" \
  --collection-source-use shared_producer_v1 \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-producer.json"
```

Review the disabled configuration, exact artifact digest, model, destination and
budget. The explicit flag selects collection binding **v2** with
`source_use: "shared_producer_v1"`. Without the flag the generator preserves v1.
Every embedding request from a v2 instance requires an authenticated source guard;
use a separate ordinary v1 instance for query embeddings that have no producer
claim. The host's normal configuration validation checks the supplied service
registry; the generator does not discover or select a service for you.
The registered service also requires each effective request timeout to be at
most 100000 milliseconds. The example selects that limit explicitly; a longer
profile refuses before provider dispatch rather than being silently shortened.

Import and validate with the existing admitted home/workspace:

```sh
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus-producer"
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-producer.json" --no-project-config \
  --extension producer
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-producer.json" --no-project-config \
  --extension producer --cwd "$IPSE_CORPUS_COLLECTION_WORKSPACE"
```

Store sources using the earlier `source` procedure with instance name `producer`.
Run `generation_produce` action `selection` to obtain the configured selection.
For `generation_job begin`, construct the exact `vector_selection` from that
selection result:

| Selector field | Value |
| --- | --- |
| `selection_sha256` | returned `selection_sha256` |
| `profile` | returned `configured_profile.id` |
| `model` | returned `configured_profile.model` |
| `dimensions` | returned `configured_profile.dimensions` (must be 1024) |
| `encoding` | literal `"float32le"` |

Use
`{"kind":"explicit","profile":null,"version":1}` for `fact_selection`.
You can stage explicit facts for a stored source before building the group.
For a source whose first chunk begins with `Source`, this example cites those
six UTF-8 bytes:

```text
/ext ext__producer__generation_produce {"store":"notes","version":2,"action":"facts","source_id":"<source-id>","expected_revision":0,"facts":[{"subject":"Source","predicate":"supports","object":"review","polarity":"positive","inferred":false,"valid_from_ms":null,"valid_to_ms":null,"spans":[[0,0,6]]}],"continuation":null}
```

Each span is `[chunk ordinal, start byte, end byte]`, with an exclusive end;
offsets address the complete stored source. Use its actual chunk and byte
boundaries. Each fact needs one to eight spans, and a source may have up to 32
facts. Use `"facts":[]` for an explicit empty set. Follow each returned
continuation with its exact arguments until the result is `ok`; for a later
replacement, supply the stored projection revision as `expected_revision`.
The encoded arguments with a null continuation must fit 12,000 bytes, leaving
room for the continuation in the Session request. A larger set is refused
before staging; use the multipart procedure below for a wider set.
The host checks the source and expiry after the final approval. This stages
explicit claims; it does not extract facts or complete a shared generation.

For multipart input, create a local plan from the **exact stored source** and
the compact fact rows. For example, first store this source in the producer
instance and follow its continuations until it reports `ok`:

```text
/ext ext__producer__source {"store":"notes","action":"put","args":{"source_id":"provided:example","generation":1,"expected_revision":0,"title":"Example","text":"Source supports review.","uri":"provided:example","observed_at_ms":10,"event_at_ms":null,"expires_at_ms":null}}
```

In a separate shell at the repository root, create matching source attributes
and rows, then run the planner against the artifact built above:

```sh
cat > "$IPSE_CORPUS_ARTIFACTS/fact-source.json" <<'JSON'
{"source_id":"provided:example","partition":"notes","generation":1,"title":"Example","text":"Source supports review.","uri":"provided:example","observed_at_ms":10,"event_at_ms":null,"expires_at_ms":null,"origin":{"kind":"provided","store_profile":"notes","partition_or_scope":"notes","receipt":null,"historical":false}}
JSON
cat > "$IPSE_CORPUS_ARTIFACTS/fact-rows.json" <<'JSON'
[{"subject":"Source","predicate":"supports","object":"review","polarity":"positive","inferred":false,"valid_from_ms":null,"valid_to_ms":null,"spans":[[0,0,6]]}]
JSON
mix run --no-start dev/knowledge/plan_fact_input.exs \
  "$IPSE_CORPUS_ARTIFACTS/corpus-producer" \
  "$IPSE_CORPUS_ARTIFACTS/fact-source.json" \
  "$IPSE_CORPUS_ARTIFACTS/fact-rows.json" > "$IPSE_CORPUS_ARTIFACTS/fact-plan.json"
```

The source attributes, including origin and times, must match the stored
version. For a document source, use its complete canonical source record,
including its document metadata. The plan contains `draft_id`, `manifest` and
an ordered `pages` array; it grants no storage permission. In chat, inspect
the eight reusable slot revisions:

```text
/ext ext__producer__generation_produce {"store":"notes","version":2,"action":"facts_slots"}
```

For each page, substitute the plan's actual JSON objects and the listed revision
for that page's ordinal into the following call. Review and approve its write:

```text
/ext ext__producer__generation_produce {"store":"notes","version":2,"action":"facts_page","source_id":"provided:example","draft_id":"<draft-id>","manifest":<manifest>,"page":<page>,"expected_slot_revision":<slot-revision>}
```

Once every page succeeds, use the same draft ID and manifest to assemble the
projection, following returned continuations until `ok`:

```text
/ext ext__producer__generation_produce {"store":"notes","version":2,"action":"facts_commit","source_id":"provided:example","draft_id":"<draft-id>","manifest":<manifest>,"expected_revision":0,"continuation":null}
```

If another draft replaces a slot, the old draft refuses; inspect revisions and
stage its pages again. A source change, expiry, mismatched manifest or missing
page also refuses. An unknown outcome is not permission to replay an effect.
The slots are reused; staging facts alone does not complete a group or qualify
the full collection workload.

Then call `generation_produce` with exactly `store`, `version: 1`, `action: "page"`,
`embedding`, the returned `job_id` and `job_revision`, and those same two
selectors. Review every storage and embedding approval. Expect `page_ready` in
coverage, a first shared-vector page and `group_complete: false`; the selected
generation stays unchanged.

For the experimental multi-page path, use version 2 and include
`"vector_cursor":0` and `"previous_ready":null` in the first `page` call;
the other fields and selectors are the same. For example, replace the selectors
and Job values with the actual returned values:

```text
/ext ext__producer__generation_produce {"store":"notes","version":2,"action":"page","embedding":"vectors","job_id":"<job-id>","job_revision":<job-revision>,"vector_selection":<vector-selection>,"fact_selection":{"kind":"explicit","profile":null,"version":1},"vector_cursor":0,"previous_ready":null}
```

When the result contains a `continuation`, invoke its `id` with its exact
`arguments` to produce the next page. A null continuation means all vector pages
in that captured group are ready, not that the group or generation is complete.
Do not construct a continuation from an unknown outcome.

Once all vector pages for the captured group are ready, stage explicit facts
for every source in that group, including an explicit empty list for a source
with no facts. Larger groups can exhaust a Session's bounded lineage ledger.
After every page and fact operation has returned a completed result, with no
outstanding staged continuation, close
the Session with confirmed closure, start a fresh Session in the same admitted
project with the same selected artifact, and inspect the Job using its exact
selectors. Check that its ID and revision match the completed vector pages.
A six-source, two-page synthetic journey needed this handoff before append;
a separate nine-source journey used stage-free handoffs between its two group
builds and finalization. Larger workloads are not yet qualified. Do not transfer
active stages or treat an unknown outcome as completed.

Request the guarded group append with the inspected Job identity and selectors.
For example, replace the placeholders with the values used for the group's first page:

```text
/ext ext__producer__generation_produce {"store":"notes","version":2,"action":"append","embedding":"vectors","job_id":"<job-id>","job_revision":<job-revision>,"vector_selection":<vector-selection>,"fact_selection":{"kind":"explicit","profile":null,"version":1},"vector_cursor":0,"previous_ready":null,"continuation":null}
```

Review the proposed writes and follow every returned `generation_produce`
continuation unchanged. A completed append reports its Job state in
`coverage.job_progress` and provides the Job token in `coverage.continuation`.
If it reports `groups`, use the token's `job_revision` to produce the next captured
group. If it reports `manifests`, use that token with guarded `generation_job`
finalization. A missing fact projection or changed source refuses the append;
an unknown outcome requires inspection rather than replay.

The claim commits before inference. After each approval the host authenticates
the current claim, source byte ranges, source times and fixed job/catalog/root,
then makes one final locked admission for that batch. Expired, historical,
future-observed or changed sources refuse. Already admitted bytes may remain
in flight after a later change. Selection pinning separately refuses a changed
configured route; returned model/input/vector checks still apply.

`inspect` is read-only. A pending or unknown claim offers no retry/adoption token,
including across Sessions. An unsupported v1 binding can approve an inert claim
and then refuse guarded inference with no egress; inspect it before deciding on
new work. Do not replay the old intent or switch identity to consume its stage.
The [actual guarded Session controls](../archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session.md)
and [finite-source positive](../archive/2026-10-26-p30-p31-implementation/shared-producer-finite-guard-session.md)
use synthetic loopback models and a private artifact with this same delegation;
they establish neither model quality nor complete producer/capacity acceptance.
The [two-page v2 Session](../archive/2026-10-26-p30-p31-implementation/shared-producer-v4-public-session.md)
also used a synthetic endpoint and an initially empty selected root.
The [public-entry adoption review](../archive/2026-10-26-p30-p31-implementation/shared-producer-public-adoption-independent-review.md)
separately checks the canonical build and exact delegation/configuration; it does
not relabel the private artifact's native execution as a canonical-artifact run.

### Query selected shared vectors

After a shared generation has been selected, a `collection-dense` reader can
rank one to eight explicitly selected source IDs by cosine similarity or combine
that ranking with BM25. It requires the exact selected vector/fact identities,
the same encoder selection and an already available registered inference service.
These experimental queries return cited evidence; they do not search the whole
namespace, extract facts or generate an answer.

Close the producer Session. Use the current `corpus-producer` artifact and
`producer-inference.json` from the preceding procedure, but create a separate
reader configuration with the ordinary v1 Collection binding. Its query text has
no producer claim; the v2 `shared_producer_v1` binding requires that claim for
every embedding request. Keep the same admitted home, workspace and logical
document binding so the reader can inspect the existing store.

Save these complete options as `$IPSE_CORPUS_ARTIFACTS/collection-query-options.json`:

```json
{
  "version": 1,
  "stores": {"notes": {"kind": "collection", "scope": "project", "partition": "notes"}},
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
  "rerank": {}, "extraction": {}
}
```

Generate, inspect and select the reader without changing the existing producer
configuration. Deliberately omit `--collection-source-use` for this reader:

```sh
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-producer" \
  --package corpus --preset collection-dense --instance corpus \
  --options "$IPSE_CORPUS_ARTIFACTS/collection-query-options.json" \
  --inference-config "$IPSE_CORPUS_ARTIFACTS/producer-inference.json" \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-collection-query.json"
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-collection-query.json" --no-project-config \
  --extension corpus
IPSE_HOME="$IPSE_CORPUS_COLLECTION_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-collection-query.json" --no-project-config \
  --extension corpus --cwd "$IPSE_CORPUS_COLLECTION_WORKSPACE"
```

Replace the selectors below with the complete JSON objects used for the selected
generation, and choose IDs that actually belong to it:

```text
/ext ext__corpus__query_selected {"store":"notes","retrieval":"similar","query":"Source supports review","source_ids":["provided:example"],"vector_selection":<vector-selection>,"fact_selection":<fact-selection>,"as_of_ms":null,"top_k":5}
```

Review the exact query-embedding approval and wait for the completed result.
Choose `retrieval: "blend"` in a separate command for lexical/cosine fusion.
An explicit [query prefix](#choose-an-embedding-query-format) also works on these
retrieval profiles; original query bytes still drive excerpts and lexical ranking.
Graph components and reranking are unavailable on this selected Collection path.
Hybrid requires `missing_embedding: "refuse"`; incomplete shared groups cannot
be treated as a successful lexical fallback.

The reader authenticates the complete selected groups and raw sources before
inference, checks the configured encoder digest without inference, and pins that
digest on the approved request. It checks the returned model/dimensions/encoding
and source-vector bindings, then checks the Collection again before returning.
A changed Collection yields `conflict` with no evidence or claims. With
`as_of_ms: null`, expiry during approval/inference also withholds all results.
An explicit time filters the currently retained versions as described above.

Read `selection_complete`, `namespace_complete`, `revalidated`,
`query_embedding_calls`, read/effect counts and partial-document gaps together.
Complete coverage applies only to those selected sources; namespace coverage
remains false. Stored supplied vectors still report
`model_receipt_provenance: false`: successful query inference does not prove how
the stored vectors were produced. Hydration retains its 512-read limit, with
bounded profile/result/final-validation reads afterward. A wide selection can
refuse without partial evidence. No returned result grants later-use authority,
and an uncertain inference is never retried automatically. Full namespace dense
retrieval, real-model quality and full producer/capacity qualification remain open.

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
refusal publishes no partial success. Follow [saved-result reading](extensions.md#invoke-a-command-and-inspect-its-complete-result)
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

Use hybrid `blend` with `rerank: null` as the reference configuration when adding
embeddings. It combines BM25 and dense retrieval with reciprocal rank fusion at
`rrf_k: 60` and `top_k: 10`, requires the selected embedding profile, and refuses
missing vectors instead of silently using another route. The
[dated comparison](../archive/2026-10-23-p27-heldout-comparison/index.md)
records the quality and resource tradeoffs for this choice. Its generated-answer
results used a fixed final-answer model; Corpus query itself only returns evidence.
Keep lexical `words` when you want source search without model calls. Treat the
reranker below as an explicit alternative to evaluate on your own workload.

This example needs an already running local Ollama service with
`embeddinggemma:latest` already available. It installs or downloads
nothing. Select your actual models and native embedding dimensions explicitly if
they differ. The [embedding manual](extensions.md) explains host profile fields.
Keep the lexical route when you do not want model calls.

Exit the earlier chat with `/exit`. Keep the artifact parent and application home
from the first example. Create a fresh workspace and these two files in your shell:

```sh
IPSE_CORPUS_DENSE_WORKSPACE=$(mktemp -d)
cat > "$IPSE_CORPUS_ARTIFACTS/dense-options.json" <<'JSON'
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
  "rerank": {},
  "extraction": {}
}
JSON
cat > "$IPSE_CORPUS_ARTIFACTS/dense-inference.json" <<'JSON'
{
  "embedding_profiles": {
    "encoder": {
      "operation": "embedding", "provider": "ollama", "model": "embeddinggemma:latest",
      "credential": "none", "base_url": "http://127.0.0.1:11434",
      "dimensions": 768, "dimension_mode": "native", "timeout_ms": 120000
    }
  },
  "budget": {"version": 1, "max_requests": 6}
}
JSON
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus-dense" \
  --package corpus --preset state-dense
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-dense" \
  --package corpus --preset state-dense --instance corpus \
  --options "$IPSE_CORPUS_ARTIFACTS/dense-options.json" \
  --inference-config "$IPSE_CORPUS_ARTIFACTS/dense-inference.json" \
  --state-binding knowledge \
  --output "$IPSE_CORPUS_ARTIFACTS/operator-dense.json"
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus-dense"
```

Inspect the actual printed digest as before. Review the generated trust, the embedding
inference route and the six-request shared budget. Validate, then start a fresh chat:

```sh
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse config \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-dense.json" --no-project-config \
  --extension corpus
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-dense.json" --no-project-config \
  --extension corpus --cwd "$IPSE_CORPUS_DENSE_WORKSPACE"
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
same. A vector whose recorded input digest does not match its current source
chunk is treated as missing; inspect the source and reindex that chunk rather
than relying on the mismatched vector.

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

### Choose an embedding query format

Dense and hybrid retrieval entries can include an explicit `query_prefix` of
1..1024 UTF-8 bytes. Set it in the options file before generating configuration
and start a fresh chat with that reviewed configuration. Without this field,
queries use their original bytes. A lexical or remote-query entry does not accept
it. Collection namespace queries still support lexical retrieval only.

For example, when deliberately selecting a Qwen3 embedding profile, its
[model card](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B) describes an instruction
followed by the query. The `similar` entry can use this complete profile object:

```json
{
  "kind": "dense", "version": 1, "embedding": "vectors",
  "query_prefix": "Instruct: Retrieve relevant passages that answer the query.\nQuery:"
}
```

Select the actual model and dimensions in `encoder` separately; this field does
not select or download a model. To use the same format for `blend`, add that
field to its existing hybrid entry as well. Ipse concatenates the prefix and
query exactly once, without adding whitespace or shortening either value. The
embedding approval shows those complete dispatched bytes. Indexing still sends
the original passage; lexical matching, reranking and displayed citations still
use the original query/source. Changing only this query format needs no source
reindex because it does not change document-vector inputs. Freeze the chosen
format with the options/artifact before evaluating retrieval quality. The dated
reference comparison does not qualify a newly selected model or query format.

### Query and optionally rerank

Compare dense and hybrid retrieval on the same source:

```text
/ext ext__corpus__query {"store":"notes","retrieval":"similar","rerank":null,"query":"lock files inode","top_k":10,"as_of_ms":1700000020000}
/ext ext__corpus__query {"store":"notes","retrieval":"blend","rerank":null,"query":"lock files inode","top_k":10,"as_of_ms":1700000020000}
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
To evaluate reranking, exit this chat and build a separate `state-semantic`
artifact. This alternative adds `host.model` authority and needs an already
available `qwen3.5:9b` model. It is not the measured reference artifact. Generate
its options and host profile from the reviewed dense files:

```sh
elixir -e '
[source, inference, output, host] = System.argv()
options = JSON.decode!(File.read!(source))
options = put_in(options, ["rerank"], %{"ordered" => %{
  "kind" => "model_complete", "profile" => "ranker", "max_candidates" => 16,
  "quote_bytes" => 128, "output_contract" => "json_schema_v2"}})
profiles = %{"ranker" => %{"provider" => "ollama", "model" => "qwen3.5:9b",
  "credential" => "none", "base_url" => "http://127.0.0.1:11434",
  "max_output_tokens" => 4096, "reasoning_effort" => "none", "timeout_ms" => 120000}}
File.write!(output, JSON.encode!(options))
File.write!(host, JSON.encode!(Map.put(JSON.decode!(File.read!(inference)), "profiles", profiles)))
' "$IPSE_CORPUS_ARTIFACTS/dense-options.json" \
  "$IPSE_CORPUS_ARTIFACTS/dense-inference.json" \
  "$IPSE_CORPUS_ARTIFACTS/rerank-options.json" \
  "$IPSE_CORPUS_ARTIFACTS/rerank-inference.json"
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_CORPUS_ARTIFACTS/corpus-rerank" --package corpus --preset state-semantic
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_CORPUS_ARTIFACTS/corpus-rerank" \
  --package corpus --preset state-semantic --instance corpus \
  --options "$IPSE_CORPUS_ARTIFACTS/rerank-options.json" \
  --inference-config "$IPSE_CORPUS_ARTIFACTS/rerank-inference.json" \
  --state-binding knowledge --output "$IPSE_CORPUS_ARTIFACTS/operator-rerank.json"
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse extension import "$IPSE_CORPUS_ARTIFACTS/corpus-rerank"
```

Inspect the printed digest and expanded trust before enabling this alternative.
Then start a new chat:

```sh
IPSE_HOME="$IPSE_CORPUS_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_CORPUS_ARTIFACTS/operator-rerank.json" --no-project-config \
  --extension corpus --cwd "$IPSE_CORPUS_DENSE_WORKSPACE"
```

The same home, workspace, State binding and embedding profile retain the indexed
source. The reranker selects structured output through native Ollama. It needs
`model.complete` version 2; another provider must omit `output_contract` to use
the original text contract. The host never changes modes or providers silently.
Run this explicit alternative query:

```text
/ext ext__corpus__query {"store":"notes","retrieval":"blend","rerank":"ordered","query":"lock files inode","top_k":10,"as_of_ms":1700000020000}
```

This reranked query sends short candidate IDs, canonical source-span references and
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
follow the independent [Graph procedure](graph.md).

## Select a remote store

Use an MCP store with a reviewed server implementing the
[knowledge CAS contract](../developer/knowledge-storage.md#implement-a-compatible-remote-cas-owner)
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
the exact tool from your separate [MCP configuration](mcp.md), and allowlist it
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
[Research](research.md) are separate and cannot replace this route.

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
[request/reply contract](../developer/knowledge-storage.md#implement-selected-remote-retrieval)
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

This source-envelope procedure applies to State and MCP stores. Complete
document Collection export/import and faithful packed-record migration remain
unavailable; a descriptor inventory or part layout is not a restorable backup.

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

For the State and MCP stores described above, each partition permits 32 source roots, including unpublished drafts and
suppression markers. An import for a new source needs an unused root slot.
Collection retains roots and suppression. Use separate reviewed partitions for
new sources when the root ceiling is reached.

State permits 256 retained records and 1 MiB per namespace. A qualified MCP v3
partition permits 88 retained records and at most 1 MiB. Records include roots,
pages, drafts' staged pages, old generations, orphan pages and tombstones.
The source `collect` action removes unreachable bodies but retains their slots. Plan exports and
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
