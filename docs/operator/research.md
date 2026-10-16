# Bounded research

Use `$research` to clarify scope, plan a small search, evaluate primary sources,
retain evidence, distinguish inference/conflicts and produce a cited report.
The skill is inert instruction. It enables no service and grants no permissions.
Search and retrieval are **operator-configured MCP capabilities**. Ipse embeds
no search provider, endpoint, account or automatic fallback. Choose any server
compatible with the [MCP contract](mcp.md); keep credentials explicit.

A generic configuration template is:

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

Replace the example endpoint and exact tool names with your selected server.
Review its schemas, terms, network/data-transfer behavior and output limits.
Authenticated servers can reference an operator environment variable with
`bearer_env`; never put a token in a URL or committed configuration. Project
`.ipse/config.json` cannot silently enable MCP. Select its configuration explicitly:

```sh
./bin/ipse chat --mcp-config /path/to/research-mcp.json --max-steps 30
```

Then ask, for example: “Use $research to compare SQLite WAL concurrency constraints
from official documentation; at most two searches and three fetched sources.”
Interactive external calls require their full usual approval. Headless `--yes`
authorizes configured tools broadly; use interactive review when that is preferable.
A native shell policy denies network access through shell, while explicitly
configured HTTP MCP operates remotely under its separate visible boundary.
Unknown calls must not be automatically replayed. Failure/rate limits do not
switch to another service, model or billing mode.

## Optional service example

One independently exercised option is the hosted
[Exa MCP service](https://exa.ai/docs/get-started/exa-mcp), which documents anonymous
rate-limited search/fetch without an API key. It is optional, changeable and not
installed or bundled with Ipse. An example uses URL `https://mcp.exa.ai/mcp`, server
ID `exa`, and the explicit tool allowlist `web_search_exa`, `web_fetch_exa`.
Ipse's query-free endpoint policy uses that default URL. No paid `agent_run`, OAuth
or automatic service selection is enabled. Different credentials/limits require
separate explicit configuration. Service availability and schemas can change;
discovery changes fail closed rather than silently altering a reviewed call.

## Evidence ledger

Successful external tool results expose a host-recorded call ID. `research_source`
captures an exact URL and literal excerpt from one successful recorded MCP result.
It records source/result SHA-256, tool identity, retrieval time and any reported
title/author/publication date. Metadata is marked unverified. New retrieval times
come from host result completion; old results lacking that field use source-capture
time, without claiming the server fetched fresh content at that moment.

`research_claim` links a statement to captured source IDs, with kind `supported`,
`inference`, `conflict` or `open`. Non-open claims need references; unknown IDs
are rejected. The kind is the model's assessment: the host checks provenance and
references, **not semantic truth, authenticity, freshness or whole-page coverage**.
Read the actual passages and primary sources before trusting the conclusion.
Fetching one page per call makes source/excerpt correspondence easier to audit.

`research_ledger` reads durable evidence independently of compacted context and
lists up to 16 recent successful external results with call IDs, reviewed request arguments and explicitly
untrusted previews. It retrieves nothing. A ledger holds at most 16 sources,
32 claims and 64 KiB JSON; excerpts are at most 4000 UTF-8 bytes, statements 1000
bytes and claim references eight unique IDs. The native display, including bounded
recovery references, is at most 64 KiB + 512 bytes. Capture repeats are idempotent.
When a limit is reached, stop or start a separately scoped session; do not pretend
missing evidence was captured. The skill's search/source count is guidance;
Session step/context budgets and tool/ledger sizes are host-enforced bounds.

Ledger entries live in the **private original session journal**, outside transient
model context. Resume validates committed entries against recorded evidence,
without replaying retrieval, inference or report writes. Export a saved ledger
locally, without authentication or model calls:

```sh
./bin/ipse research --resume SESSION_ID --state-dir /path/to/sessions > evidence.json
```

The exported ledger contains selected excerpts and may be private. Share it only
intentionally. A requested report uses ordinary reviewed workspace writes. Keep
source/claim IDs alongside citations, and label incomplete or conflicting evidence.
Historical open notes remain immutable; later claims can explain their resolution.
Children cannot retrieve via MCP or record the parent's ledger. Optional child
analysis receives only selected collected evidence; the parent verifies synthesis.
See [verification and limits](../developer/research.md).
