# Research a question and inspect its evidence

Choose the route that matches your task. Ipse provides no default search service.
Select sources/services explicitly and inspect quotations before relying on claims.
Attribution identifies the bytes used; it cannot establish truth, freshness,
authenticity, or semantic support.

| Task | Route and retained product |
| --- | --- |
| Ask the main agent to investigate and synthesize | Native `$research` workflow, recorded source/claim ledger |
| Rank supplied text without a model or service | Offline Research extension, structured result |
| Rerank supplied text with a model and fence it through delivery | [Fenced provided investigation](#fence-a-supplied-source-rerank-through-delivery) |
| Investigate through selected search/fetch tools | MCP Research extension, structured result and call receipts |
| Fetch and retain one selected URI for Corpus questions | [Fetched State retention](#fetch-and-retain-a-selected-source) |
| Explicitly retain supplied text for later Corpus questions | [Provided-only Research transfer](#retain-supplied-evidence-in-a-shared-corpus) |
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

This uses real model requests and approved external retrieval. To restrict the
task to local source material, supply those sources and say so. That instruction
does not confine the selected model or prove network isolation. Review each MCP
query/URL, full arguments, and server identity. Native shell networking policy
and configured HTTP MCP are separate boundaries. Headless `--yes` broadly
authorizes configured calls. Prompt source counts guide the model; host request,
context and ledger bounds remain authoritative. No silent service, model, or
billing fallback occurs.

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
When a Session has a read-only, planning, or draft execution ceiling, it can
read the ledger but cannot add sources or claims, even with `--yes`.

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

Investigation search/fetch kinds must match. Every Research retrieval profile must be BM25.
Corpus's dense/hybrid/graph/`mcp_query` profiles are not Research algorithms.
Invalid profile families and cross-profile references refuse configuration.
An unknown profile name in an `investigate` command refuses that investigation.

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
For current-time investigations, Research samples time before proposing a
rerank and before returning its worker result. If a captured source reaches an
eligibility boundary, or a later sample moves earlier than a preceding check,
Research returns `query_time_changed` without evidence or claims. These worker
checks do not fence an approval-delayed model dispatch or later Session delivery;
the separate [fenced provided investigation](#fence-a-supplied-source-rerank-through-delivery)
has the host check both.

A lexical match is not semantic support. Without attributed graph facts the claim
stays open with `semantic_support_unassessed`. `evidence_indexes` are zero-based
positions in this result's evidence array. One passage normally gives `[0]`.
No usable match returns abstain. Case-insensitive matching retains original UTF8
quote coordinates. Nearby conditions may fit; distant qualifications may lie
outside chunk/quote bounds. Inspect full source when needed.

## Retain supplied evidence in a shared Corpus

Use the optional `state-retained` Research preset when you want to keep supplied
text for later Corpus queries. It accepts provided data, not native research
ledger records or fetch receipts. A URL remains attribution; this route does not
fetch or authenticate it. The offline and MCP presets do not offer `retain`.

This source-build exercise needs the supported Elixir/OTP toolchain and a built
checkout. It uses a fresh private home/workspace, ordinary State approvals and
direct commands with the credential-free demo provider. To use this beside
protected saved-note recall, choose a registered main route with its own reviewed
provider/service configuration; the demo does not deliver protected current notes.
An explicit `/ext` retain remains a user command with ordinary State approval.
A later model-selected Corpus read can return its attributed passage while
preserving the recalled note's source checks; approve the exact proposed tool
arguments when requested. A model-selected Research retain that inherits managed
notes remains refused even with `--yes`. Saved knowledge does not grant State
write permission. The [bounded coexistence control](../archive/2026-10-26-p30-p31-implementation/research-managed-coexistence-20261104.md)
checks that distinction using a registered synthetic local route.

Build the two reviewed artifacts and generate matching options/configurations:

```sh
umask 077
./dev/build.sh
IPSE_RETAIN_ARTIFACTS=$(mktemp -d)
IPSE_RETAIN_HOME=$(mktemp -d)
IPSE_RETAIN_WORKSPACE=$(mktemp -d)
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_RETAIN_ARTIFACTS/research" \
  --package research --preset state-retained
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_RETAIN_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical
elixir -e '[input, output] = System.argv(); options = JSON.decode!(File.read!(input)); options = options |> Map.put("search", %{}) |> Map.put("fetch", %{}); File.write!(output, JSON.encode!(options), [:exclusive])' \
  extensions/knowledge/options/research-state-retained.json \
  "$IPSE_RETAIN_ARTIFACTS/corpus-options.json"
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_RETAIN_ARTIFACTS/research" \
  --package research --preset state-retained --instance research \
  --options extensions/knowledge/options/research-state-retained.json \
  --state-binding research-shared \
  --output "$IPSE_RETAIN_ARTIFACTS/research.json"
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_RETAIN_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical --instance corpus \
  --options "$IPSE_RETAIN_ARTIFACTS/corpus-options.json" \
  --state-binding research-shared \
  --output "$IPSE_RETAIN_ARTIFACTS/corpus.json"
elixir -e '[research, corpus, output] = System.argv(); left = JSON.decode!(File.read!(research)); right = JSON.decode!(File.read!(corpus)); config = %{"version" => 1, "extensions" => left["extensions"] ++ right["extensions"], "extension_trust" => left["extension_trust"] ++ right["extension_trust"]}; File.write!(output, JSON.encode!(config), [:exclusive])' \
  "$IPSE_RETAIN_ARTIFACTS/research.json" \
  "$IPSE_RETAIN_ARTIFACTS/corpus.json" \
  "$IPSE_RETAIN_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_RETAIN_HOME" ./bin/ipse extension import "$IPSE_RETAIN_ARTIFACTS/research"
IPSE_HOME="$IPSE_RETAIN_HOME" ./bin/ipse extension import "$IPSE_RETAIN_ARTIFACTS/corpus"
```

Inspect each printed digest with `IPSE_HOME="$IPSE_RETAIN_HOME" ./bin/ipse
extension inspect DIGEST`. Review the source, complete manifest and generated
operator file before enabling either instance. Import and inspection do not run
the worker. The generated trust covers the artifacts' exact capabilities;
instances remain disabled until selected. This preset adds State access, not
network, model or MCP capability, and does not use saved knowledge consent.

Both instances explicitly select the same logical binding `research-shared`,
project scope and `research-notes` partition. They must also use the same home
and workspace. Matching the `notes` profile alias alone does not share data.

```sh
IPSE_HOME="$IPSE_RETAIN_HOME" ./bin/ipse config \
  --config "$IPSE_RETAIN_ARTIFACTS/operator.json" --no-project-config \
  --extension research --extension corpus
IPSE_HOME="$IPSE_RETAIN_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_RETAIN_ARTIFACTS/operator.json" --no-project-config \
  --extension research --extension corpus --cwd "$IPSE_RETAIN_WORKSPACE"
```

Run these direct commands one at a time, waiting for `Finished.`:

```text
/ext ext__research__retain {"store":"notes","source":{"source_id":"manual:release","title":"Release policy","text":"Release requires quiescence.","uri":"local:release-policy","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null},"quote":"Release requires quiescence."}
/ext ext__corpus__query {"store":"notes","retrieval":"words","rerank":null,"query":"quiescence","top_k":3,"as_of_ms":1700000000000}
```

Review the ordinary `extension:state.put` approvals, including the full proposed
arguments. Denial before the first write leaves this source absent. On success,
Research returns `coverage.source_id` and structured derivation. Corpus returns
the original text with a provided-origin citation, original body hash and exact
selected quote offsets. Supplied ID, URI and observation time remain unverified;
the result proves no native fetch, historical existence or source truth.

The destination ID is derived from the complete body. For this literal example
it is `research.provided:abbba53d88fbef3ff61fa825de40691302cb2837fefec6b4701c41ec69ff5010`.
Inspect it before forgetting:

```text
/ext ext__corpus__source {"store":"notes","action":"inspect","args":{"source_id":"research.provided:abbba53d88fbef3ff61fa825de40691302cb2837fefec6b4701c41ec69ff5010"}}
```

The fresh small-source example publishes root revision 2. Confirm
`coverage.revision`; if it differs, use the returned revision in the next command:

```text
/ext ext__corpus__source {"store":"notes","action":"forget","args":{"source_id":"research.provided:abbba53d88fbef3ff61fa825de40691302cb2837fefec6b4701c41ec69ff5010","expected_revision":2}}
/ext ext__corpus__query {"store":"notes","retrieval":"words","rerank":null,"query":"quiescence","top_k":3,"as_of_ms":1700000000000}
```

Approve the forget mutation. Later queries exclude the body. Retrying its transfer
under a new supplied ID, URI, quote or fresh Session cannot restore it in this
shared namespace. Earlier saved results and provider disclosures remain; forgetting
does not erase history. Changed bodies and fetched-source derivatives are outside
this provided-only suppression rule.

The full original body is limited to 4,096 UTF-8 bytes and the selected quote to
1,024 bytes. The quote must occur exactly once, including overlapping matches.
Aggregate SDK and Store bounds also apply; field maxima are not additive.
Callers cannot choose the destination ID, generation or revision, import a fetch
receipt, or supply a historical origin. A repeated retained body conflicts rather
than silently replacing its attribution. Inspect the existing source before
deciding on new work. If a write is uncertain, preserve the original journal,
home, workspace and configuration and follow [recovery](recovery.md); do not
automatically repeat it or treat an unknown result as a known cancellation.

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

## Fetch and retain a selected source

Choose `state-fetched` when a reviewed MCP gateway should capture one URI and
retain its complete text in a shared State Corpus. This preset does not search,
rank or call a model. It makes a fresh fetch inside each transfer; callers cannot
supply a prior fetch receipt or body as authority. The gateway must implement the
[fetch-v1 contract](../developer/knowledge-storage.md#implement-the-research-searchfetch-gateway).
Choose and allowlist its actual fetch tool using [MCP setup](mcp.md); Ipse installs
no gateway and does not select one for you.

This independent source-build example uses a fresh home/workspace and the same
explicit binding/scope/partition in both instances. It does not restore content
forgotten in an earlier namespace. Build/import/review these artifacts as in the
provided-text procedure. Replace `mcp__research_gateway__fetch` with the actual
reviewed tool ID and supply its MCP configuration at the private path below:

```sh
umask 077
./dev/build.sh
IPSE_FETCH_ARTIFACTS=$(mktemp -d)
IPSE_FETCH_HOME=$(mktemp -d)
IPSE_FETCH_WORKSPACE=$(mktemp -d)
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin --output "$IPSE_FETCH_ARTIFACTS/research" \
  --package research --preset state-fetched
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin --output "$IPSE_FETCH_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical
elixir -e '[input, output] = System.argv(); options = JSON.decode!(File.read!(input)) |> Map.put("fetch", %{}); File.write!(output, JSON.encode!(options), [:exclusive])' \
  extensions/knowledge/options/research-state-fetched.json \
  "$IPSE_FETCH_ARTIFACTS/corpus-options.json"
elixir -e '[output] = System.argv(); File.write!(output, JSON.encode!(%{"fetch-web" => "mcp__research_gateway__fetch"}), [:exclusive])' \
  "$IPSE_FETCH_ARTIFACTS/bindings.json"
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_FETCH_ARTIFACTS/research" \
  --package research --preset state-fetched --instance research \
  --options extensions/knowledge/options/research-state-fetched.json \
  --state-binding research-fetch-shared \
  --mcp-bindings "$IPSE_FETCH_ARTIFACTS/bindings.json" \
  --output "$IPSE_FETCH_ARTIFACTS/research.json"
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_FETCH_ARTIFACTS/corpus" \
  --package corpus --preset state-lexical --instance corpus \
  --options "$IPSE_FETCH_ARTIFACTS/corpus-options.json" \
  --state-binding research-fetch-shared \
  --output "$IPSE_FETCH_ARTIFACTS/corpus.json"
elixir -e '[research, corpus, output] = System.argv(); left = JSON.decode!(File.read!(research)); right = JSON.decode!(File.read!(corpus)); config = %{"version" => 1, "extensions" => left["extensions"] ++ right["extensions"], "extension_trust" => left["extension_trust"] ++ right["extension_trust"]}; File.write!(output, JSON.encode!(config), [:exclusive])' \
  "$IPSE_FETCH_ARTIFACTS/research.json" "$IPSE_FETCH_ARTIFACTS/corpus.json" \
  "$IPSE_FETCH_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_FETCH_HOME" ./bin/ipse extension import "$IPSE_FETCH_ARTIFACTS/research"
IPSE_HOME="$IPSE_FETCH_HOME" ./bin/ipse extension import "$IPSE_FETCH_ARTIFACTS/corpus"
IPSE_HOME="$IPSE_FETCH_HOME" ./bin/ipse config \
  --config "$IPSE_FETCH_ARTIFACTS/operator.json" --no-project-config \
  --extension research --extension corpus
IPSE_HOME="$IPSE_FETCH_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_FETCH_ARTIFACTS/operator.json" --no-project-config \
  --extension research --extension corpus \
  --mcp-config /private/path/research-mcp.json --cwd "$IPSE_FETCH_WORKSPACE"
```

Review the printed artifact digests, manifests and generated trust before
selection. Build and review matching Research and Corpus workers from the same
source revision; update any other Research worker sharing that State partition
as well. New fetched bodies use evidence-root format 2 and capture receipt
version 2. Older workers refuse that root even if selector publication has not
finished. The unchanged artifact semantic-version label does not promise storage
compatibility; use the reviewed content digests and matching storage contract.
Close previously pinned Sessions before writing this format, then start a new
Session with both new artifacts. Resume cannot replace an old pinned catalog in
place. Legacy format-1 captures stay inspectable/exportable without a rewrite,
but their missing selector base cannot establish current selection or recovery.

Unlike `state-retained`, this preset adds selected MCP access as well
as State access. Approve the exact fetch URI and, separately, the proposed State
writes. For a compatible gateway serving the storage chapter's example body,
run each command separately and wait for `Finished.`:

```text
/ext ext__research__fetch_retain {"store":"notes","fetch":"web","uri":"local:release-policy","title":"Release policy","quote":"Release requires quiescence.","timeout_ms":5000}
/ext ext__corpus__query {"store":"notes","retrieval":"words","rerank":null,"query":"quiescence","top_k":3,"as_of_ms":null}
```

Use your selected URI and a unique exact quotation from its captured text. The
result identifies the canonical body key and derivation; the query citation has
`origin.kind: fetch`, requested/observed URI, body hash and UTF-8 quote coordinates.
The existing `research.provided:` key prefix is retained for identity compatibility;
read the origin rather than inferring provenance from that prefix. The descriptor
is attribution to a recorded fetch, not permission or a native current-source
receipt. Later stored metadata alone authenticates no new/current fetch.
Gateway truth, identity and reported timestamps remain unverified.

For each store partition, configured fetch binding and requested URI, a separate
State selector identifies the last approved captured body. A changed body gets a
new immutable canonical record before that selector advances. Earlier bytes and
their original citation receipts remain intact; the ordinary current query treats
those versions as historical. Here, selected means a local State version, not a
live-source check, independent publisher identity or native-note authority.
Gateway timestamps remain attribution and eligibility metadata; State revisions
order selection. The existing 32-source-root bound includes retained older body
versions. Selectors also consume bounded State record space. Older captures
without selection metadata remain untracked and cannot establish a current fetch.

Inspect/forget the returned source ID with the Corpus commands in the previous
procedure. Re-fetching identical body bytes under another URI/quote or fresh
Session cannot restore them in that same namespace. A malformed, partial,
hash-mismatched or missing fetch refuses before State writes. Denying the first
State write leaves storage unchanged. Refusal of a later write can leave earlier
confirmed body publication intact without a confirmed selector. The result then
identifies that known body and requests inspection. An interrupted selector may
already have changed: preserve its journal/configuration and inspect storage;
never resume or automatically retry the uncertain operation.

### Recover a retained body selection

Use the same admitted Research/Corpus artifacts, State scope/partition, configured
fetch binding and requested URI. Obtain the canonical body ID from the known
publication result or its journal. Inspect its revision and current selection,
then export the retained bytes and original attribution before choosing them:

```text
/ext ext__corpus__source {"store":"notes","action":"inspect","args":{"source_id":"research.provided:COPY_THE_64_HEX_BODY_DIGEST"}}
/ext ext__corpus__source {"store":"notes","action":"export","args":{"source_id":"research.provided:COPY_THE_64_HEX_BODY_DIGEST","cursor":null,"limit":2}}
```

Replace the placeholder with the complete returned ID. Follow the export cursor
when another page remains. Inspection reports the source `revision` and, for
tracked fetched bytes, `fetch_version` with its selector revision and selected
source. If the desired body is already selected, a later observation does not
resolve or settle the old unknown operation.

For example, if inspection actually reports source revision 2 and selector
revision 1 for the captured body you want, request this separate explicit command:

```text
/ext ext__research__select_retained {"store":"notes","fetch":"web","uri":"local:release-policy","source_id":"research.provided:COPY_THE_64_HEX_BODY_DIGEST","source_revision":2,"expected_selection_revision":1}
```

Use the actual inspected revisions. This command is not a model tool. Review its
ordinary State write separately. It verifies the unchanged canonical body,
original fetch binding/URI, current metadata and original selector base revision,
then conditionally changes only the selector. It performs no fetch or body
publication and supplies no native permission. A confirmed result says
`selection_status: selected`; `already_selected` is a read-only observation and
makes no State write. Both report `fresh_fetch: false` and `body_republished: false`.

The original base revision prevents replacing a later conflicting selection even
if gateway timestamps run ahead or behind. A changed body/revision, expired or
forgotten source, different binding/URI or legacy capture without a recorded base
refuses. A finite stored expiry remains the write deadline. Preserve and inspect
another unconfirmed result; no old unknown is replayed, refunded or settled by
this command. Do not delete tombstones or change the source ID to force selection.

The body/quote bounds remain 4,096/1,024 UTF-8 bytes with unique quote matching.
Derivative or cross-backend invalidation and model-selected fetched retention
remain unqualified; this State path supplies no managed-note authority. This is not a
promise to suppress every restatement or erase already captured journal text.

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
`profiles`, `embedding_profiles`, `inference_services`, and an optional shared
`budget` in this file; it never
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
same MCP file. Select the configured reranker explicitly:

```text
/ext ext__research__investigate {"search":"web","fetch":"web","retrieval":"words","rerank":"ordered","query":"release quiescence","limits":{"max_sources":2,"max_body_bytes":8192,"timeout_ms":30000},"sources":[]}
```

Full model-egress approval is separate. Research sends the query and at most ten
ranked candidate IDs (the adapter permits up to sixteen),
canonical source references, and excerpts of at most 128 bytes. Input must fit
4096 rendered bytes and output 8192 bytes, without silent truncation. The model
must return every candidate ID exactly once; missing/duplicate/invented IDs fail
without repair. Usage and [budget reservations](resources.md) still apply.
Conforming output proves no ranking improvement or factual support.

## Fence a supplied-source rerank through delivery

Use the `investigate_provided` command when you supply every source yourself,
want a model reranker, and want Ipse rather than the worker to keep that source
set current from approval through the result you see. It is an explicit command;
the main agent cannot call it as a tool.

Start from the mcp-model artifact, options and inference file of the
[reranker setup](#add-an-explicitly-named-reranker). Add this provided profile
entry to both the `search` and `fetch` registries of `mcp-model-options.json`,
keeping any MCP profiles you also use:

```json
{"given": {"kind": "provided", "version": 1}}
```

Register the reranker's actual endpoint as a shared inference service by adding
this top-level key to `rerank-inference.json`, beside its `profiles`:

```json
{"inference_services": {"local": {"version": 1, "origins": ["http://127.0.0.1:11434"]}}}
```

Follow [shared-service setup](configuration.md#serialize-a-shared-inference-service)
for its protected-storage prerequisites, then regenerate
`operator-mcp-model.json` with the same `config.exs` command and start a fresh
chat with it. Run:

```text
/ext ext__research__investigate_provided {"search":"given","fetch":"given","retrieval":"words","rerank":"ordered","query":"release quiescence","limits":{"max_sources":1,"max_body_bytes":1024,"timeout_ms":30000},"sources":[{"source_id":"manual:release","generation":1,"title":"Release policy","text":"Release requires quiescence.","uri":"local:release-policy","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}]}
```

Expect the ordinary `extension:model.complete` approval with its full arguments,
one request to the registered service after you approve, and a result shaped like
`investigate`. With `"rerank":null` the command makes no model request, but its
delivery is still fenced.

Before the worker starts, Ipse journals a content-free source-set intent. Its
digest covers every source's ID, generation, body hash, observation and expiry
time, origin and partition in order, plus the query, as-of time, artifact,
options and parent invocation. The intent also records the earliest time at
which any source becomes eligible or expires. Ipse derives these facts from the
command arguments it admitted, never from the worker. It re-derives the digest
and requires the clock to be at or after its previous check and before that
earliest transition before admitting the model request, before recording the
dispatch intent, immediately before sending the request body, when model output
returns to the worker and before showing the result. An explicit `as_of_ms`
fixes eligibility, so only the digest and clock checks apply.

These cases refuse:

- No registered service matches the reranker's endpoint, or the route changed:
  the action refuses before any approval prompt and sends nothing.
- The worker asks for any search, fetch, State, MCP, embedding or other host call,
  or the invocation would combine with managed notes.
- The sources are empty or a selected search/fetch profile is not provided:
  Research returns `invalid_provided_sources`.
- A source reached its transition, or the clock moved backward, after you
  approved: no request is sent and the result is withheld with an error naming
  that boundary.
- The result is too large to show inline: saved result pages are not used.

The ordinary `investigate` command keeps its existing behavior, including
unregistered rerank routes.

A resumed session shows a fenced result only as
`{"status":"withheld","reason":"provided_sources_historical","historical_receipt":true}`
and never shows its evidence again. An invocation interrupted after its set
intent has no result and is not replayed. An interrupted request to the
registered service leaves an unknown reservation that blocks later requests
until you reconcile it. The fence binds time and the supplied set; it does not
judge ranking quality, truth or freshness, and the model still receives the
query and excerpts.

## Recover before issuing another request

A refusal names the actual operation/limit. It does not change service, profile,
algorithm, or allowance. Unknown retrieval/model work may have run remotely,
and an interrupted retention may have written State. An empty Corpus query does
not prove that no immutable pages were written. Preserve the original journal,
namespace and configuration and inspect the recorded outcomes before new work.
Local cancellation cannot prove remote work stopped. A `time_limit` or
`query_time_changed` refusal needs a new reviewed invocation, never automatic
replay; inspect the recorded rerank outcome first if work was interrupted.

Idle resume starts no search, fetch, model, worker, or result scan. Saved results
remain committed. Changed selection can refuse resume; restore original settings
or use a reviewed [handoff](recovery.md). Native ledger evidence likewise remains
in the journal through compaction. Resume validates entries without redoing work;
source capture is idempotent and later claims can explain historical open ones.
Corrupt evidence refuses resume/export. Preserve the journal. A child cannot use
parent MCP or write its ledger, though it may analyze selected collected material.
Keep route provenance and private export contents explicit when sharing results.
