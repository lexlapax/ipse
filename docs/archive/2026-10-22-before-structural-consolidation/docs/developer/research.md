> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/knowledge-extensions.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Binding research claims to recorded evidence

Ipse's research tools preserve where an excerpt came from. They do not search by
themselves or prove a claim true. Retrieval uses explicitly configured MCP servers;
`Ipse.Research` adds a bounded private evidence ledger over already recorded
results. A skill can guide the work but cannot enable endpoints or authorize calls.

Read `lib/ipse/research.ex` from `definitions/0` through `call/4`, then follow
`source/3` and `claim/2`. Keep the original events available while doing this.
Context summaries and displayed excerpts are not the ledger's recovery source.

## Capture an existing result

`research_source` accepts a successful MCP tool call ID, literal URL/excerpt, and
optional title, author, and publication metadata. The host finds exactly one
recorded external intent and one result with `result_recorded` outcome. It checks
UTF-8/bounds and literal presence of both URL and excerpt in the result. It stores
a stable source ID, source/result digests, and explicitly unverified metadata.

The source fixture in `test/research_test.exs` is a useful reading exercise:

1. Find the synthetic successful MCP result and its host outcome metadata.
2. Follow the capture call to the matching journal event.
3. Change the requested excerpt mentally to text absent from the result. Identify
   the check that refuses it before any source is added.
4. Read the ambiguous-call fixture. Reused IDs cannot select evidence by guesswork.

Literal presence proves text provenance only. A multi-page result may contain a
URL and an unrelated excerpt, so single-page retrieval and human review matter.
No host check promotes model-supplied title or publication time into verified fact.

Successful MCP messages include `ipse_external_result` metadata and a bounded
visible call-ID/tool/time header. A new source uses recorded result completion
with `retrieval_time_basis: tool_result_recorded`. Legacy results without that
time retain source-capture time. Neither establishes server freshness.
`research_ledger` includes bounded recent successful references with reviewed
arguments and untrusted previews so older/compacted results remain addressable.
It never repeats retrieval.

## Record a claim with honest support

`research_claim` accepts statement, kind, and unique captured source IDs.
Kinds `supported`, `inference`, and `conflict` require at least one source; `open`
may have none. Host validation checks shape and references, not semantic entailment.
A later immutable claim may explain how an older open question was resolved.
Exact repeated source/claim capture returns the existing record.

| Ledger boundary | Limit |
| --- | --- |
| Sources / claims | 16 / 32 |
| Ledger JSON | 65,536 bytes |
| Excerpt / statement | 4,000 / 1,000 UTF-8 bytes |
| References per claim | 8 |
| URL / source call ID | 2,048 bytes / 256 characters |
| Tool arguments | 16 KiB |
| Result body with host header / ledger with recovery references | 66,048 bytes |

Reaching a bound refuses a new record without trimming evidence into a successful
capture. Research ledger tools are unavailable to children; forged child requests
refuse explicitly. Report file writes keep ordinary approval requirements.

## Preserve the record/result boundary

The owned tool worker reads original journal events and prepares a source/claim
outside Session. Session syncs version-1 `research_source` or `research_claim`
before publishing the normal tool result. A crash between those two writes leaves
a durable ledger entry and uncertain call outcome. Resume revalidates each entry
against preceding evidence and never replays capture, retrieval, or file effects.
CLI export uses that same reconstruction without credentials or inference.

MCP schemas sometimes identify Draft-07. The schema adapter accepts only its
explicit identical-keyword subset and adapts it for the existing validator.
It does not enable refs, combinators, remote loaders, formats, or full Draft-07.
See [MCP schema boundaries](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/mcp.md#schema-subset) before changing compatibility.

```sh
mix test test/research_test.exs test/research_session_test.exs
```

These tests check literal/ambiguous evidence, failed retrievals, timestamp basis,
claim references, ledger bounds, changed committed excerpts, and inert recovery.
For a new evidence type, first define exactly what the host can verify. A source
identifier is not a substitute for support or permission.
