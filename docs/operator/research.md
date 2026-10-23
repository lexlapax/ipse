# Research a question and inspect its evidence

Choose the route that matches your task. Ipse provides no default search service.
Select sources/services explicitly and inspect quotations before relying on claims.
Attribution identifies the bytes used; it cannot establish truth, freshness,
authenticity, or semantic support.

| Task | Route and retained product |
| --- | --- |
| Ask the main agent to investigate and synthesize | Native `$research` workflow, recorded source/claim ledger |
| Rank supplied text without a model or service | Offline Research extension, structured result |
| Investigate through selected search/fetch tools | MCP Research extension, structured result and call receipts |
| Keep sources for later questions or traverse retained relationships | [Corpus](corpus.md) or [Graph](graph.md) |

The extension's caller-provided ledger and saved results are separate from the
native evidence ledger. `ipse research` exports only the native ledger. Neither
route automatically saves sources into Corpus or extracts Graph facts.

## Ask the main agent for bounded research

Choose/review a retrieval service's tools, credentials, schemas, terms, and data
transfer. Save an MCP file outside the workspace. This complete-shaped example
uses a nonworking placeholder URL; replace it with the selected service's values:

```json
{"servers":[{"id":"research","transport":"http","url":"https://search.example.invalid/mcp","tools":["search","fetch"],"timeout_ms":30000}]}
```

For static bearer authentication, add `bearer_env` naming your private environment
variable. Never place tokens in the URL/committed configuration. Ipse does not
load `.env` automatically. [MCP setup](mcp.md) owns transport/schema details;
project configuration and skills cannot enable MCP.

Start a real subscription session, or explicitly choose another provider:

```sh
ipse chat --provider chatgpt --mcp-config /private/path/research-mcp.json \
  --cwd /path/to/research-workspace --max-steps 30
```

Enter a bounded task:

```text
Use $research to compare SQLite WAL concurrency constraints using official
sources. Use at most two searches and three fetched sources. Record sources
and claims in the evidence ledger. Distinguish supported facts, inference,
conflicts, and unanswered questions. Do not write a report file until I ask.
```

This uses real model requests and approved external retrieval. For a local-only
assessment, supply local sources and say so. Review each MCP query/URL, full
arguments, and server identity. Native shell networking policy and configured
HTTP MCP are separate boundaries. Headless `--yes` broadly authorizes configured
calls. Prompt source counts guide the model; host request/context/ledger bounds
remain authoritative. No silent service, model, or billing fallback occurs.

## Inspect and export the native ledger

Ask to show `research_ledger` and explain source IDs and attached claims. This
reads recorded evidence without retrieval. `research_source` captures an exact
URL/literal excerpt from one successful recorded MCP result, retaining call/result
identity, hashes, completion time, and any reported metadata. Titles/authors/dates
remain unverified. One fetched source per call usually makes correspondence easier
to inspect. Ambiguous old call IDs are omitted rather than incorrectly paired.

`research_claim` links source IDs with supported, inference, conflict, or open
labels. These are model assessments for you to check. The host validates recorded
provenance and references, not the source's truth or completeness.

| Native ledger item | Bound |
| --- | --- |
| Sources / claims / total JSON | 16 / 32 / 64 KiB |
| Source excerpt | 4000 UTF8 bytes |
| Claim statement / unique references | 1000 bytes / eight |
| Recent successful external calls | 16, with reviewed arguments and untrusted previews |

At a bound, stop or deliberately scope a new session and identify the gap. Export
with the original session/state directory after obtaining its ID from `/session`
or `ipse sessions`:

```sh
umask 077
ipse research --resume SESSION_ID --state-dir /private/path/sessions > /private/path/evidence.json
```

Omit state-dir for the default store. This local export starts no tool, model,
retrieval, or report write. It includes private excerpts; inspect it before sharing.
For a narrative report, ask for a specific workspace-relative path/format and
approve the proposed write separately. Keep source/claim IDs alongside citations.

## Rank a supplied source without external services

The offline Research extension needs a compatible artifact and source toolchain
for this build exercise. From the checkout, run `./dev/build.sh`, then:

```sh
IPSE_RESEARCH_ARTIFACTS=$(mktemp -d)
IPSE_RESEARCH_HOME=$(mktemp -d)
IPSE_RESEARCH_WORKSPACE=$(mktemp -d)
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_RESEARCH_ARTIFACTS/research" \
  --package research --preset offline
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_RESEARCH_ARTIFACTS/research" \
  --package research --preset offline --instance research \
  --options extensions/knowledge/options/research-offline.json \
  --output "$IPSE_RESEARCH_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse extension import "$IPSE_RESEARCH_ARTIFACTS/research"
```

If you already have a reviewed compatible artifact, import it instead of building.
Import/inspection are inert. Inspect the actual printed digest with the same home:

```sh
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse extension inspect DIGEST
```

Review source, manifest, and generated trust/routes. The generated instance is
disabled until explicitly selected. Offline Research has no host-effect grant or
logical State binding. SDK 2 and `invoke.result.pages` support complete larger
results. The options file contains all seven registries, including empty ones:

```json
{
  "version": 1,
  "stores": {},
  "search": {"given": {"kind": "provided", "version": 1}},
  "fetch": {"given": {"kind": "provided", "version": 1}},
  "retrieval": {"words": {"kind": "bm25", "version": 1}},
  "embedding": {},
  "rerank": {},
  "extraction": {}
}
```

Search/fetch kinds must match. Every Research retrieval profile must be BM25.
Corpus's dense/hybrid/graph/`mcp_query` profiles are not Research algorithms.
Unknown/unused families and missing selected profiles refuse configuration.

Validate configuration and start a credential-free scripted main session:

```sh
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse config \
  --config "$IPSE_RESEARCH_ARTIFACTS/operator.json" --no-project-config \
  --extension research
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_RESEARCH_ARTIFACTS/operator.json" --no-project-config \
  --extension research --cwd "$IPSE_RESEARCH_WORKSPACE"
```

Use `/ext` directly, rather than sending an ordinary conversational task.
Run one command at a time and wait for `Finished.` before the next:

```text
/ext ext__research__investigate {"search":"given","fetch":"given","retrieval":"words","rerank":null,"query":"quiescence","as_of_ms":1700000000000,"limits":{"max_sources":1,"max_body_bytes":1024,"timeout_ms":5000},"sources":[{"source_id":"manual:release","generation":1,"title":"Release policy","text":"Release requires quiescence.","uri":"local:release-policy","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}]}
```

Expect ok, the exact quotation, source/generation/content/chunk identity, byte
coordinates, and quote hash. Coverage reports provided sources, captured bytes,
as-of time, and `native_ledger: false`. This command makes no host call, model
request, or retained-store write.

The supplied source ID/URI are provenance, not destinations this route fetches.
Observation equal to selected time is eligible; expiry equal to it is excluded.
Future observations, expired text, and historical imports do not become current.
Optional as-of time fixes eligibility/ranking/citations; omitting it uses current
time after capture. Backdating proves no historical existence or trustworthiness.

A lexical match is not semantic support. Without attributed graph facts the claim
stays open with `semantic_support_unassessed`. `evidence_indexes` are zero-based
positions in this result's evidence array. One passage normally gives `[0]`.
No usable match returns abstain. Case-insensitive matching retains original UTF8
quote coordinates. Nearby conditions may fit; distant qualifications may lie
outside chunk/quote bounds. Inspect full source when needed.

## Bound an investigation and read the complete result

Every invocation supplies search, fetch, retrieval, rerank, query, limits, and
sources. Rerank is null unless explicitly selected. Optional as-of time is an
integer 0..9007199254740991, never null/string/negative. Supplied sources have
exactly the eight fields in the example.

| Input/output | Bound |
| --- | --- |
| Query | 1..1024 UTF8 bytes |
| max_sources | 1..10 |
| max_body_bytes | 1..49152 accumulated text bytes |
| timeout_ms | 1000..30000 ms requested investigation allowance |
| Supplied sources | At most ten within count/body allowances |
| Source ID / title / URI / text | 256 / 128 / 512 / 65536 bytes |
| Returned quote | At most 1024 UTF8 bytes |
| Complete result | At most 4 MiB encoded JSON, subject to journal capacity |

The complete SDK input still fits 16 KiB; field maxima are not additive. Escaping
may require smaller explicit batches. An oversized/invalid aggregate refuses
`result_too_large`; journal capacity can also refuse. No partial document becomes
a successful result. Before later fetch/rerank, remaining allowance below 1000 ms
returns time_limit without proposing an action. Otherwise that same remaining
value becomes the request timeout. A completed capture with no later action can
return immediately. Host calls/cleanup retain their own deadlines.

Small results display inline. Larger results return saved.result with output ID,
byte count, SHA-256, and historical receipt. Read the complete document before
judging claims or gaps. Replace the placeholder with the returned ID:

```text
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":[]}
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":["evidence",0,"citation","quote"]}
```

Follow references/next cursors for other children. After chat, print exact retained
JSON using the original session and state directory:

```sh
IPSE_RESEARCH_OUTPUT_ID='COPY_THE_64_CHARACTER_OUTPUT_ID'
IPSE_RESEARCH_SESSION_ID='COPY_THE_SESSION_ID'
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse result "$IPSE_RESEARCH_OUTPUT_ID" \
  --resume "$IPSE_RESEARCH_SESSION_ID" --state-dir "$IPSE_RESEARCH_HOME/sessions"
```

These reads start no worker/retrieval/model. They preserve historical bytes, not
current eligibility. Direct `/ext` and your `/result` reads do not disclose output
to the model; its saved_result_read tool requires original tool disclosure.
[Extensions](extensions.md#invoke-a-command-and-inspect-its-complete-result) explains
cursor and retained-byte rules.

## Inspect caller-provided assertions

The extension ledger command consumes the ledger passed in its arguments. It
never retrieves a previous result or owns a persistent claim database:

```text
/ext ext__research__ledger {"action":"inspect","args":{"ledger":[{"claim":"Release requires quiescence.","basis":["manual:release, generation 1, quotation: Release requires quiescence."],"label":"supported"}]}}
/ext ext__research__ledger {"action":"assert","args":{"ledger":[],"claims":[{"claim":"The release process may need an explicit quiet period.","basis":["Operator interpretation of manual:release"]}]}}
```

Rows return open, provided origin, and native_receipt false. A supplied supported
label survives only as provided_label. Ledger rows have exactly claim/basis/label;
new assertions have claim/basis. Labels are supported/inference/conflict/open.
Claims are at most 1024 bytes; basis has up to eight 1024-byte strings. Input and
combined ledgers allow 32 rows; assertions allow eight; encoded arguments fit
12000 bytes. To export, supply action export with the full ledger and no claims.
It displays locally, without writing a file or creating native ledger records.

## Add a selected search and fetch gateway

The MCP preset requires exact search-v1/fetch-v1 contracts. Similar tool names are
insufficient. Review a compatible gateway's credentials, bounds, and remote effects.
Ipse installs no gateway and selects no search provider. Developer contract
examples live in [Knowledge storage](../developer/knowledge-storage.md#implement-the-research-searchfetch-gateway).

Save this complete file as `$IPSE_RESEARCH_ARTIFACTS/mcp-options.json`:

```json
{
  "version": 1,
  "stores": {},
  "search": {"web": {"kind": "mcp", "binding": "selected_search", "contract": "search-v1"}},
  "fetch": {"web": {"kind": "mcp", "binding": "selected_fetch", "contract": "fetch-v1"}},
  "retrieval": {"words": {"kind": "bm25", "version": 1}},
  "embedding": {}, "rerank": {}, "extraction": {}
}
```

Save bindings separately as `$IPSE_RESEARCH_ARTIFACTS/mcp-bindings.json`:

```json
{
  "selected_search": "mcp__research_gateway__search",
  "selected_fetch": "mcp__research_gateway__fetch"
}
```

Replace IDs with your actual reviewed server/tools. Configure and allowlist both
in [MCP configuration](mcp.md); keep credentials out of these files. Build/select
a fresh artifact:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_RESEARCH_ARTIFACTS/research-mcp" \
  --package research --preset mcp
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_RESEARCH_ARTIFACTS/research-mcp" \
  --package research --preset mcp --instance research \
  --options "$IPSE_RESEARCH_ARTIFACTS/mcp-options.json" \
  --mcp-bindings "$IPSE_RESEARCH_ARTIFACTS/mcp-bindings.json" \
  --output "$IPSE_RESEARCH_ARTIFACTS/operator-mcp.json"
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse extension import "$IPSE_RESEARCH_ARTIFACTS/research-mcp"
```

Inspect its digest and validate the generated configuration as in the offline
procedure. Then start a fresh chat with the reviewed MCP file:

```sh
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_RESEARCH_ARTIFACTS/operator-mcp.json" --no-project-config \
  --extension research --mcp-config /private/path/research-mcp.json \
  --cwd "$IPSE_RESEARCH_WORKSPACE"
```

Investigate with no supplied sources:

```text
/ext ext__research__investigate {"search":"web","fetch":"web","retrieval":"words","rerank":null,"query":"release quiescence","limits":{"max_sources":2,"max_body_bytes":8192,"timeout_ms":30000},"sources":[]}
```

Review every resolved server/tool, descriptor, query/URI, and full argument.
Invoking the extension approves neither search nor fetch. Captured MCP JSON is
bounded to 65536 bytes through same-invocation result pages. Investigation/body/
publication limits still apply. Invalid shapes/hashes/spans/incomplete replies
refuse. Call receipts bind replies, but do not certify the gateway's internal
source access or semantic claims.

## Add an explicitly named reranker

MCP retrieval needs no model. For optional model reranking, use preset mcp-model
and retain the complete MCP options, changing its rerank registry to:

```json
{"ordered":{"kind":"model_complete","profile":"reranker","max_candidates":16,"quote_bytes":128,"output_contract":"json_schema_v2"}}
```

Save the full options as `mcp-model-options.json`. Save this separate inference
file as `rerank-inference.json` in the same artifact root:

```json
{
  "profiles": {
    "reranker": {
      "provider": "ollama", "model": "qwen3:8b", "credential": "none",
      "timeout_ms": 30000, "max_output_tokens": 1024
    }
  }
}
```

Select your actual available model/profile explicitly. The generator accepts only
profiles, embedding_profiles, and optional shared budget in this file; it never
borrows missing profiles from home configuration. Structured output requires a
compatible host/native Ollama service. To use the original text contract with
another provider, omit output_contract. Unsupported structured profiles refuse
before dispatch. Build and generate:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_RESEARCH_ARTIFACTS/research-mcp-model" \
  --package research --preset mcp-model
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_RESEARCH_ARTIFACTS/research-mcp-model" \
  --package research --preset mcp-model --instance research \
  --options "$IPSE_RESEARCH_ARTIFACTS/mcp-model-options.json" \
  --mcp-bindings "$IPSE_RESEARCH_ARTIFACTS/mcp-bindings.json" \
  --inference-config "$IPSE_RESEARCH_ARTIFACTS/rerank-inference.json" \
  --output "$IPSE_RESEARCH_ARTIFACTS/operator-mcp-model.json"
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse extension import "$IPSE_RESEARCH_ARTIFACTS/research-mcp-model"
```

Inspect/validate it and start a fresh chat using operator-mcp-model.json plus the
same MCP file. Invoke investigate with rerank set to ordered. Full model-egress
approval is separate. It sends query and up to sixteen short candidate IDs,
canonical source references, and excerpts of at most 128 bytes. Input must fit
4096 rendered bytes and output 8192 bytes, without silent truncation. The model
must return every candidate ID exactly once; missing/duplicate/invented IDs fail
without repair. Usage and [budget reservations](resources.md) still apply.
Conforming output proves no ranking improvement or factual support.

## Recover before issuing another request

A refusal names the actual operation/limit. It does not change service, profile,
algorithm, or allowance. Unknown retrieval/model work may have run remotely;
inspect receipts/service records before deciding on a new explicit investigation.
Local cancellation cannot prove remote work stopped. A time_limit refusal needs
a new reviewed invocation, never automatic replay.

Idle resume starts no search, fetch, model, worker, or result scan. Saved results
remain committed. Changed selection can refuse resume; restore original settings
or use a reviewed [handoff](recovery.md). Native ledger evidence likewise remains
in the journal through compaction. Resume validates entries without redoing work;
source capture is idempotent and later claims can explain historical open ones.
Corrupt evidence refuses resume/export. Preserve the journal. A child cannot use
parent MCP or write its ledger, though it may analyze selected collected material.
Keep route provenance and private export contents explicit when sharing results.
