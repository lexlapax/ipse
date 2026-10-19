> Historical reference only. Snapshot of `docs/developer/research.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../developer/research.md).

# Research evidence contract

P14 reuses the existing explicit MCP client and optional skills rather than adding
a retrieval engine, mandatory service or workflow framework. Search/fetch endpoints,
capabilities and credentials remain operator configuration. The runtime knows no
Exa endpoint or Exa-specific tool names. The optional hosted-service example is
operator documentation only; credential-free fixtures and packages make no request.

## Source and claim records

`Ipse.Research` uses existing Jason, bounded JSONSchex, SHA-256, journal and OTP
session tools. `research_source` accepts an exact successful MCP call ID, URL,
literal excerpt and optional title/author/publication metadata. It verifies one
unambiguous recorded intent/result, `result_recorded` status, literal URL/excerpt
presence, UTF-8 and bounds. It saves source/result digests and stable source ID.
It proves text provenance, not URL authenticity or correspondence within a
multi-page response; prefer single-page retrieval and independently review support.
Reported metadata is explicitly unverified.

Successful MCP tool messages carry `ipse_external_result` host metadata and a
visible bounded call-ID/tool/time header so models can select the actual reference.
New source timestamps use recorded result completion and mark
`retrieval_time_basis: tool_result_recorded`. Legacy messages without completion
time use source-capture time, preserving prior entries. Neither is a guarantee of
server freshness. `research_ledger` exposes bounded recent successful references
for older or compacted results, with reviewed request arguments and untrusted previews; it never retrieves again.
A live trial demonstrated why call IDs must be visible; failed capture stayed open
until this host interface was repaired, rather than inventing evidence IDs.

`research_claim` validates unique captured source IDs and statement/kind bounds.
`open` may have no sources; other kinds need at least one. It does not automate
semantic fact checking or upgrade the model's assessment into a host guarantee.
Immutable later claims can explain resolution of older open notes. Exact repeated
source/claim capture returns the existing record without duplicating it.

Limits: 16 sources, 32 claims, aggregate 65536-byte ledger JSON; source excerpt
4000 UTF-8 bytes; statement 1000 bytes; eight references per claim; source URL
2048 bytes and call ID 256 characters. Input uses existing 16-KiB argument bounds.
A recorded MCP body may include the existing 64-KiB result plus a bounded host
header. Native ledger output with up to 16 recovery references stays within
66048 bytes. Reaching a bound refuses the record with an error.

## Ownership and recovery

The owned tool worker reads original journal events and prepares records outside
the GenServer. The session journals `research_source`/`research_claim` version-1
events before publishing the normal tool result. They are private bookkeeping,
not workspace/network effects or permission grants. A crash between record and
tool result leaves the record durable and the call outcome uncertain; startup
never replays it. Resume revalidates each committed entry against its preceding
recorded evidence and stops on corruption. Context checkpoints retain original
journal data; ledger reconstruction does not depend on a summary or tool excerpt.
Local CLI export uses that same reconstruction without credentials or inference.

Children do not expose ledger tools and forged child requests fail explicitly.
Existing parent/child ownership, approvals, cancellation and unknown remote-effect
rules remain unchanged. Reports use ordinary write/edit approvals. A skill or a
retrieved instruction cannot install dependencies, enable network or authorize work.

## MCP compatibility evaluation

The anonymous hosted Exa MCP catalog (observed server version 3.5.0) provides
search and page-fetch tools without local installation. Its initial admission
failed because generated schemas declare Draft-07. Existing JSONSchex implements
2020-12, so Ipse now explicitly adapts **only the already admitted keyword subset**
whose semantics are identical across those drafts. Original descriptor/schema
identity stays bound on the wire. No refs, tuple items, dependencies, combinators,
formats, patterns, arbitrary dialects or remote loader are admitted. Shape, byte,
depth/node and argument bounds remain unchanged. This is not full Draft-07 support.
See the primary [Draft-07 validation specification](https://json-schema.org/draft-07/draft-handrews-json-schema-validation-01)
and [2020-12 vocabulary](https://json-schema.org/draft/2020-12/json-schema-validation).
No custom HTTP/HTML/search machinery or new dependency was needed.

See [operator configuration](../operator/research.md), [MCP contract](mcp.md) and
[actual fixture/live verification](testing.md#p14-bounded-research-2026-10-16).
