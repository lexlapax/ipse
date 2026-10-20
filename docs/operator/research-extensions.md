# Investigate supplied sources or a selected retrieval service

Use the Research extension to rank a bounded set of source passages and inspect
its evidence, claims, and gaps. Start with caller-supplied text. That route needs
no search service, model, embedding, or retained Corpus store. Optional search,
fetch, and model reranking require separate compiled presets and operator
selections.

Research returns structured evidence, not an automatically verified report.
Source attribution proves which bytes were used. It does not establish that a
quotation supports a conclusion or that the source is authentic, current, or
complete. [Corpus](corpus.md) retains sources for later queries;
[Graph](graph.md) retains explicit attributed relationships. Select them
independently when those are the tasks you need.

## Build an offline Research artifact

You need the source checkout and its [supported toolchain](arch-linux.md).
Run `./scripts/build.sh` from the repository root first. Then run:

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

Use a fresh artifact output path. The builder compiles the preset into a separate
compatible artifact; options cannot grant a different preset's authority. If you
already have a reviewed compatible artifact, import it rather than rebuilding.
These commands do not invoke a model or retrieval service.

Review the source, manifest, and generated configuration. Inspect the actual
printed digest with the same application home:

```sh
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse extension inspect DIGEST
```

Replace `DIGEST` with the import result. Import and inspection do not initialize
the worker or activate it. The generated instance is disabled and grants only
its compiled invocation capabilities. Offline Research has no host-effect grant
or logical State binding. It declares SDK 2 and `invoke.result.pages` so a larger
investigation can retain its complete result.

The supplied options file contains this complete closed selection:

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

Keep all seven registries, including empty ones. Search and fetch must use the
same kind for an investigation. Every Research retrieval profile must be BM25.
Corpus's dense, hybrid, graph and `mcp_query` profiles are not Research algorithms;
configuration rejects them before generating grants. For server-ranked passages
already retained in a store, follow [Corpus remote retrieval](corpus.md#retrieve-server-selected-passages).
Unknown options, unused profile families and missing selected profiles also refuse.

## Select it and investigate one supplied source

Inspect configuration before selection:

```sh
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse config \
  --config "$IPSE_RESEARCH_ARTIFACTS/operator.json" --no-project-config \
  --extension research
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_RESEARCH_ARTIFACTS/operator.json" --no-project-config \
  --extension research --cwd "$IPSE_RESEARCH_WORKSPACE"
```

The scripted main provider needs no model credentials. Use `/ext` directly rather
than submitting an ordinary conversational task. In chat, enter this complete
invocation and wait for it to finish:

```text
/ext ext__research__investigate {"search":"given","fetch":"given","retrieval":"words","rerank":null,"query":"quiescence","as_of_ms":1700000000000,"limits":{"max_sources":1,"max_body_bytes":1024,"timeout_ms":5000},"sources":[{"source_id":"manual:release","generation":1,"title":"Release policy","text":"Release requires quiescence.","uri":"local:release-policy","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}]}
```

Expect `status: "ok"`, a passage quoting `Release requires quiescence.`, and
source ID, generation, content hash, chunk ID, byte offsets, and quotation hash.
Coverage identifies `kind: "provided"`, source count, captured bytes, the selected
`as_of_ms`, and `native_ledger: false`. This command makes no host call, model
request, or retained-store write.

`source_id` and `uri` are supplied provenance, not URLs that this route fetches.
`observed_at_ms` is Unix milliseconds. Sources observed after the investigation's
selected time, expired sources, and historical imports do not become current
evidence. Supply an observation time you can justify; backdating text does not
make it trustworthy. The example supplies `as_of_ms` to select a fixed time for
ranking, citations, and coverage. Omit that optional field to use the current
time after source capture. A fixed time changes eligibility; it does not fetch an
older page or prove that the captured text existed at that time. Observation
equal to the selected time is eligible; expiry equal to it is excluded.

A word match does not establish semantic support. With no attributed graph facts,
the extension leaves the question's claim open with
`semantic_support_unassessed`. Its `evidence_indexes` are zero-based positions
in the same result's `evidence` array. For one returned passage, expect
`"evidence_indexes": [0]`; inspect that passage's complete citation. These
references avoid repeating quotation text and do not assess semantic support.
No usable match returns `status: "abstain"`. Inspect source text and gaps before
asking a model or writing a conclusion.

Word matching ignores case, while quotations retain the original UTF-8 bytes.
Case conversion during matching does not move the citation into a different
part of the source. The byte offsets always address the supplied or captured text.
Returned passages use the same [query-aware excerpts as Corpus](corpus.md#store-text-and-retrieve-its-citation).
Nearby actors and conditions can fit in the quote; distant qualifications can
remain outside its byte or chunk boundary. Inspect the source when
the selected passage leaves an important condition unclear.

## Bound an investigation

Every investigation names `search`, `fetch`, `retrieval`, `rerank`, `query`,
`limits`, and `sources`. Optional `as_of_ms` is an integer from zero through
9007199254740991 Unix milliseconds. Null, strings, and negative times refuse.
`rerank` is null unless you explicitly select a configured profile. A supplied source has
exactly the eight fields in the example; do not add arbitrary metadata.

| Input | Bound |
| --- | --- |
| Query | 1..1024 UTF-8 bytes |
| `max_sources` | 1..10 |
| `max_body_bytes` | 1..49152 accumulated source-text bytes |
| `timeout_ms` | 1000..30000 ms requested investigation allowance |
| Supplied sources | At most ten, within `max_sources` and the body allowance |
| Each source | ID 256 bytes, title 128 bytes, URI 512 bytes, text at most 65536 bytes |
| Each returned quotation | At most 1024 UTF-8 bytes |
| Complete returned result | At most 4 MiB of encoded JSON, subject to journal capacity |

The complete SDK input still has its 16 KiB object bound; these field maxima
are not additive. Smaller source batches can be needed for escaped text.
Ten sources are a count ceiling. A larger valid result uses a saved document
with every selected quote and its provenance intact. An invalid or over-limit
aggregate returns `result_too_large`; journal capacity can also refuse publication.
No partial document becomes a successful investigation. Retain the refusal
before deciding whether to issue a smaller explicit investigation.

Before each later fetch or model rerank, Research checks its remaining allowance
once. A value below 1000 ms returns `time_limit` without proposing that action.
At or above 1000 ms, that same duration becomes the host request's timeout.
When the capture queue is empty and no rerank is selected, Research ranks and
returns the completed capture without requiring time for another fetch.
Individual host requests and cleanup retain their own deadlines. A larger body
limit does not grant longer execution or wider authority.

## Read a larger investigation

A small investigation displays its JSON value directly. A larger one returns a
`saved.result` descriptor with `output_id`, `byte_count`, `sha256` and
`historical_receipt: true`. That descriptor identifies the complete document;
read the document before assessing its evidence, claims or gaps.

In the original chat, replace the example ID with the returned output ID:

```text
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":[]}
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":["evidence",0,"citation","quote"]}
```

The first request gives a bounded root view. The second reads the first quote.
Follow returned references and `next` cursors to inspect other children. To print
the complete JSON after closing chat, use the original session ID and state
directory:

```sh
IPSE_RESEARCH_OUTPUT_ID='COPY_THE_64_CHARACTER_OUTPUT_ID'
IPSE_RESEARCH_SESSION_ID='COPY_THE_SESSION_ID'
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse result "$IPSE_RESEARCH_OUTPUT_ID" \
  --resume "$IPSE_RESEARCH_SESSION_ID" --state-dir "$IPSE_RESEARCH_HOME/sessions"
```

These reads start no investigation, search, fetch, worker or model call. They
return the committed historical result; source expiry or later changes do not
turn it into current evidence. A model's `saved_result_read` tool can access
only output already disclosed by an original tool invocation in that session.
Direct `/ext` output and your `/result` reads do not disclose it to the model.
Follow [saved-result reading](extensions.md#read-a-saved-result) for cursor rules,
read errors and exact retained-byte identity.

## Inspect caller-provided claims

The `ledger` command inspects, appends supplied assertions to, or exports a
ledger you pass in its arguments. It does not retrieve the previous result or
own a persistent claim database. For example:

```text
/ext ext__research__ledger {"action":"inspect","args":{"ledger":[{"claim":"Release requires quiescence.","basis":["manual:release, generation 1, quotation: Release requires quiescence."],"label":"supported"}]}}
/ext ext__research__ledger {"action":"assert","args":{"ledger":[],"claims":[{"claim":"The release process may need an explicit quiet period.","basis":["Operator interpretation of manual:release"]}]}}
```

Expect returned rows labeled `open`, `origin: "provided"`, and
`native_receipt: false`. A supplied `supported` label is retained only as
`provided_label`; it cannot promote a caller assertion into host-verified evidence.
Ledger entries have exactly `claim`, `basis`, and `label`; new assertions have
exactly `claim` and `basis`. Supported input labels are `supported`, `inference`,
`conflict`, and `open`. Claims are at most 1024 bytes, with up to eight basis
strings of at most 1024 bytes each. Input ledgers hold at most 32 rows, assertions
at most eight, and the combined result at most 32 rows. Encoded arguments must
also fit 12000 bytes.

For an export, invoke `action: "export"` with the full caller-supplied `ledger`
array and no `claims` field. The JSON value or saved-result descriptor displays
locally; it does not write an export file.
Ask for an ordinary reviewed workspace write if you want to retain a narrative
report. Keep source identity, quotations, claim labels, and gaps alongside it.
The private session journal retains command results, but that does not create a
native research-ledger entry or a separate durable Research store.

## Add an explicit search/fetch gateway

The optional MCP route calls only operator-bound tools implementing the exact
`search-v1` and `fetch-v1` contracts below. An arbitrary search tool with a similar
name is not compatible. Obtain/review a gateway implementing those contracts,
including its credentials, limits, and remote effects. Ipse does not install one
or select a search provider for you.

Create a new options file with this complete selection:

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

Save it as `$IPSE_RESEARCH_ARTIFACTS/mcp-options.json`. Create
`$IPSE_RESEARCH_ARTIFACTS/mcp-bindings.json` containing exactly the selected
aliases mapped to your actual configured tool IDs:

```json
{
  "selected_search": "mcp__research_gateway__search",
  "selected_fetch": "mcp__research_gateway__fetch"
}
```

These example IDs refer to a server ID `research_gateway` and tools `search` and
`fetch`. Use the real IDs from your reviewed MCP configuration. Configure that
server separately using [MCP servers](mcp.md). It must allowlist both exact tools.
Keep credentials out of options and binding files. The gateway can be local or
HTTP; its transport/configuration is a separate operator choice.

Build a fresh artifact and configuration, keeping the offline one unchanged:

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

Inspect the printed digest, review the generated trust/routes, and validate the
new configuration with `--extension research` as before. Then start a fresh chat,
replacing `/private/path/research-mcp.json` with your reviewed server file:

```sh
IPSE_HOME="$IPSE_RESEARCH_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_RESEARCH_ARTIFACTS/operator-mcp.json" --no-project-config \
  --extension research --mcp-config /private/path/research-mcp.json \
  --cwd "$IPSE_RESEARCH_WORKSPACE"
```

A direct investigation uses no main conversation model. It does use your selected
MCP service when you approve the separate calls:

```text
/ext ext__research__investigate {"search":"web","fetch":"web","retrieval":"words","rerank":null,"query":"release quiescence","limits":{"max_sources":2,"max_body_bytes":8192,"timeout_ms":30000},"sources":[]}
```

MCP investigations require `sources: []`. Check every approval's binding, resolved
server/tool, query/URI, descriptor, and full arguments. Invoking the extension does
not approve search or fetch. A search result does not authorize a different
service, additional endpoint, or silent provider fallback.

## Check the gateway contract

The search tool receives this closed argument object, with your query and limit:

```json
{"version":1,"contract":"search-v1","query":"release quiescence","limit":2}
```

It must return MCP text containing one JSON object with exactly these fields:

```json
{
  "version": 1,
  "contract": "search-v1",
  "status": "ok",
  "hits": [{
    "source_id": "manual:release",
    "uri": "local:release-policy",
    "title": "Release policy",
    "snippet": "Release requires quiescence."
  }],
  "coverage": {"complete": true},
  "next": null
}
```

Each hit has exactly `source_id`, `uri`, `title`, and `snippet`, bounded to
256, 512, 128, and 1024 bytes respectively. Hit count cannot exceed the requested
limit. Incomplete/paginated results do not silently become complete coverage.

The fetch tool receives `version`, `contract: "fetch-v1"`, and the exact selected
hit URI. For the example hit, the complete request is:

```json
{"version":1,"contract":"fetch-v1","uri":"local:release-policy"}
```

A compatible response contains exactly these fields:

```json
{
  "version": 1,
  "contract": "fetch-v1",
  "status": "ok",
  "requested_uri": "local:release-policy",
  "observed_uri": "local:release-policy",
  "media_type": "text/plain",
  "observed_at_ms": 1700000000000,
  "text": "Release requires quiescence.",
  "body_sha256": "abbba53d88fbef3ff61fa825de40691302cb2837fefec6b4701c41ec69ff5010",
  "complete": true,
  "start_byte": 0,
  "end_byte": 28
}
```

This is a synthetic response with an actual matching text hash and byte count.
A real gateway must report its actual requested/observed URI, captured text,
observation time, media type, byte end, and SHA-256. It cannot substitute a partial
body while claiming completeness. `requested_uri` must equal the selected URI.
Coordinates refer to captured UTF-8 text, not original HTML bytes. A changed
observed URI remains explicit provenance, not proof that Ipse approved another
remote destination independently of the gateway.

Each captured MCP JSON result is at most 65536 bytes and is read through bounded
same-invocation result pages. Investigation body and final-result limits still
apply. Invalid JSON, field shape, hashes, spans, incomplete results, or receipts
refuse. The host binds replies to recorded calls; it does not certify the
service's claims or enforce the gateway's internal source access.

## Add optional reranking through a named model

MCP retrieval does not require inference. To add a text reranker, build another
artifact with preset `mcp-model`. In a new complete options file, retain the MCP
registries above and set `rerank` to:

```json
{"ordered":{"kind":"model_complete","profile":"reranker","max_candidates":16,"quote_bytes":128,"output_contract":"json_schema_v2"}}
```

This object is the `rerank` registry, not a standalone options file. Supply a
separate inference file containing the referenced host profile. For example:

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

Save the inference file as `$IPSE_RESEARCH_ARTIFACTS/rerank-inference.json` and the
complete model-enabled options as
`$IPSE_RESEARCH_ARTIFACTS/mcp-model-options.json`. The options must still contain
`version` and all seven registries, not just the rerank fragment above.

Structured output requires a host supporting `model.complete` version 2 and a
compatible native Ollama service. The host constrains the JSON order shape and
candidate IDs; Research independently checks complete, duplicate-free coverage.
Invalid output fails without a repair call and retains completed usage. To use
the original text contract with another provider, omit `output_contract`.
Unsupported structured profiles refuse before model approval or dispatch.

This expects an already available local model. Select your actual provider/model
explicitly using [model profiles](model-profiles.md); no model is downloaded and
no service/billing route is substituted on failure. Build and generate:

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

Inspect the actual digest. Validate `operator-mcp-model.json` with
`--extension research`, then use that configuration in a fresh chat with the same
reviewed `--mcp-config` file. The generator accepts only explicit `profiles`,
`embedding_profiles`, and optional shared `budget` in its inference input; it
does not read your ordinary home configuration for a missing profile.

Invoke `investigate` with `rerank: "ordered"`. Reranking sends the query and up to
16 short candidate IDs, canonical source-span references and excerpts of at most
128 UTF-8 bytes to that named model. A separate full model-egress approval is required. Its JSON
must return one `order` object naming every supplied ID exactly once. Missing,
duplicate or invented IDs and malformed output refuse. Put irrelevant candidates
last rather than dropping them. The call consumes ordinary accounting
and applicable shared [budget reservations](budgets.md).
Rendered rerank input must fit 4096 bytes and model output 8192 bytes. A long
query/candidate combination can refuse despite individually legal fields; it is
not silently truncated to make the request fit.

Live optional model-reranking quality has not been measured. Valid output and
recorded usage do not prove a better ranking or a correct answer. Inspect quoted
evidence and compare results for your task before relying on this optional step.

## Recover without replaying retrieval

A refused result names the actual failing operation or limit. It does not change
services, profiles, limits or algorithms. A `time_limit` refusal needs a new
explicit investigation with a reviewed allowance, not an automatic retry.
An unknown search, fetch, or model call may have
run remotely. Inspect its receipts and available service records before deciding
whether to issue a new investigation. Local cancellation cannot prove remote work
stopped.

Idle resume starts no search, fetch, reranker, worker, or result-page scan. Saved
results remain exactly as committed. Changed artifact/options/bindings/profiles
can refuse resume; restore the original selection or create a reviewed
[handoff](recovery.md). No invocation automatically saves sources into Corpus or
extracts Graph facts. Choose those writes separately with their own approvals.

The [native `$research` workflow](research.md) and `research_source`/`research_claim` tools remain
a separate main-agent route for a durable native evidence ledger. Their saved
ledger exports with `ipse research --resume SESSION_ID`. That command does not
export this extension's caller-provided ledger or convert its result into native
records. If you use both routes, keep their provenance and completeness claims
separate. Preserve private journals and review all exports before sharing them.
