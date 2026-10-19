# Research a question and retain its evidence

Use `$research` for a bounded question that needs sources, comparison, and a cited
answer. Ipse has no built-in search service. Configure a compatible MCP server
explicitly, or provide local sources and ask for a local-only assessment.

## Prepare a retrieval service

Choose a service and review its exact tools, schemas, credentials, terms, and
data-transfer behavior. Save an MCP configuration outside the workspace. This
complete-shaped example uses placeholder names and a nonworking example URL;
replace them with your chosen server's real values before use:

```json
{
  "servers": [{
    "id": "research",
    "transport": "http",
    "url": "https://search.example.invalid/mcp",
    "tools": ["search", "fetch"],
    "timeout_ms": 30000
  }]
}
```

For static bearer authentication, add `bearer_env` with your server-specific
environment variable name and supply the value privately in the launching
environment. Do not put tokens in the URL or committed config. Ipse does not load
`.env` automatically. [MCP servers](mcp.md) explains supported transports and
schemas. Project configuration and skills cannot enable MCP.

## Ask a question with a source limit

Select your model and retrieval file:

```sh
ipse chat --provider chatgpt --mcp-config /private/path/research-mcp.json \
  --cwd /path/to/research-workspace --max-steps 30
```

This uses real subscription model requests and, when approved, the selected
external retrieval service. Enter a bounded prompt:

```text
Use $research to compare SQLite WAL concurrency constraints using official
sources. Use at most two searches and three fetched sources. Record sources
and claims in the evidence ledger. Distinguish supported facts, inference,
conflicts, and unanswered questions. Do not write a report file until I ask.
```

Review each MCP proposal's full query/URL and server identity before approval.
Native shell mode can deny shell networking while explicitly configured HTTP
MCP still uses its separate remote boundary. Headless `--yes` broadly authorizes
configured calls; interactive mode provides per-call review.

A useful answer states its scope, cites the actual source passages, explains
conflicting evidence, and identifies what it could not establish. Source counts
in the prompt guide the model; request/context/ledger bounds are host-enforced.
If a service fails or rate-limits a call, decide explicitly whether to try later.
Ipse never silently changes search service, model, or billing route.

## Inspect the evidence rather than just the answer

Ask the agent to show the `research_ledger` and explain the claims attached to its
source IDs. This reads already recorded evidence; it retrieves nothing.
`research_source` can capture an exact URL and literal excerpt from one successful
recorded MCP result. The host retains call/result identity, hashes, retrieval
completion time, and any reported title/author/publication metadata. The metadata
remains unverified.

`research_claim` links statements to source IDs as `supported`, `inference`,
`conflict`, or `open`. The host validates recorded provenance and references,
not the truth, freshness, authenticity, or completeness of a page. A model's
`supported` label is an assessment for you to check. Fetching one source per call
usually makes excerpt correspondence easier to inspect.

The ledger holds at most 16 sources, 32 claims, and 64 KiB JSON. Excerpts are at
most 4000 UTF-8 bytes; claim statements 1000 bytes; references eight unique source
IDs per claim. Recent-result discovery lists up to 16 successful external calls
with reviewed arguments and untrusted previews. Ambiguous old call IDs are
omitted instead of paired with the wrong result. When a bound is reached, stop
or start another deliberately scoped session and identify the evidence gap.

## Export a saved ledger

Use the session ID printed by `/session` or `ipse sessions`:

```sh
umask 077
ipse research --resume SESSION_ID --state-dir /private/path/sessions > /private/path/evidence.json
```

Use the original state directory, or omit that flag for the default store.
Export is local: it makes no inference, retrieval, or report-writing call and
does not resume tools. The JSON includes selected source excerpts and can be
private. Review it before sharing.

To create a narrative artifact, ask in chat for a specific workspace-relative
path and format. Inspect the proposed write, then approve it separately. Keep
source/claim IDs alongside citations so a reader can compare the report with the
ledger.

## Resume or recover interrupted research

Evidence stays in the original private journal even if context is compacted.
Resume validates committed entries without retrieving or writing the report
again. Repeated source capture is idempotent. Old open claims remain historical;
a later claim can explain their resolution.

An unknown retrieval may have reached the server. Inspect available service
records before explicitly requesting another call. Corrupt committed evidence
refuses resume/export; preserve the journal and follow [Recovery](recovery.md).
A child cannot use the parent's MCP servers or write its evidence ledger. You
can delegate analysis of selected collected material, then verify the synthesis
in the parent session.
