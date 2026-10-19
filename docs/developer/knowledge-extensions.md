# Designing a knowledge capability as an extension

A knowledge feature combines evidence, retrieval, storage, and sometimes inference.
Choose each part explicitly. Ipse currently supplies explicit note extensions,
configured MCP retrieval, a research evidence ledger, and generic extension
contracts. It does not supply a production graph, embedding index, RAG engine,
or automatic cross-session memory policy.

Use this chapter to place a new feature in the existing architecture. The
[extension SDK](extensions.md) owns protocol details;
[memory](memory.md) teaches the implemented note domain, and
[research](research.md) teaches evidence provenance. Historical candidate studies
belong in the archive, not in the current runtime contract.

## Start with the user operation

Suppose a user wants to recall project facts. First implement an explicit bounded
query over a selected store. A model tool or operator command is sufficient if
recall happens on request. Automatic recall adds a different requirement: a
selected before-request job must finish and publish attributed context before
request admission. Background indexing cannot change an already frozen request.

| Requirement | Existing mechanism to inspect |
| --- | --- |
| Explicit remember/recall/forget/export | Memory invocation and generic state actions |
| Retrieval from an external service | Explicit MCP tool/resource selection |
| Source-supported claims | Research source/claim ledger |
| Read earlier recorded views | Granted fixed-range history action |
| Run deterministic extraction at a prompt boundary | Source-bound event job |
| Add same-request recalled evidence | Awaited before-request job and context publication |
| Optional one-shot model extraction | Separately approved/accounted `host.model` operation |

Read `lib/ipse/extensions/memory.ex` and its state continuation alongside
`test/extensions_memory_session_test.exs`. Observe that the extension returns
host proposals instead of directly writing files. This pattern preserves intent,
approval, CAS, cancellation, and saved receipts without adding domain branches to
Session.

A skill can teach a method using existing tools. It cannot silently install a
backend, enable an endpoint, create a background job, or grant private history.
Use a core change only for a missing generic invariant or reviewed API gap.

## Define identity before ranking

A useful retrieval record needs an exact source identity, source version, extractor
or index version, scope, and provenance. Derived chunks need stable chunk/span
mapping back to source text. A URL or filename alone does not identify which
version was indexed. Keep original evidence separate from a model-written summary
and distinguish a retrieval score from support for an answer.

Work through an update/forget race before choosing an algorithm:

```text
read source generation 4 → prepare extraction
forget source generation 4 → commit suppression
resume delayed extraction → refuse stale CAS or suppressed source
```

`test/extensions_memory_test.exs` exercises this race, including reread, import,
and transitive derivatives. An implementation that checks suppression only once
before a long computation can resurrect forgotten content at commit. Preserve
both source-domain suppression and host storage revisions.

Define session/project/operator sharing as an operator ceiling. Persistent memory's
logical binding deliberately separates storage identity from exact code identity;
it does not transfer arbitrary scope or permit changed-code session resume.
A new backend needs equivalent ownership, finite records/bytes, stale-write
handling, and explicit migration/export behavior. Evaluate existing Elixir/OTP
facilities and maintained packages before adding custom protocol/storage machinery;
record any dependency in the inventory and obtain required approvals.

## Specify the retrieval boundary

For a lexical query, document tokenization, tie-breaking, top-k, excerpt bytes, and
no-match behavior. For a graph, also bound traversal depth, visited nodes, edges,
and cycles. For an index, bind source/index versions and decide whether stale
indexes refuse or require explicit rebuilding. Do not silently add embeddings,
download weights, contact a model, or switch providers when local retrieval fails.

Embeddings have no supported model-call/accounting operation today. The one-shot
text helper is not an embedding API. A service exposed through MCP still needs
explicit endpoint, credential, selection, egress, and unknown-remote-effect policy.
Executable code making out-of-band calls is not automatically budgeted by Ipse.

When inference is needed, select a permitted helper profile and use its approved
accounted action. Keep extraction input, generated candidates, and accepted facts
separate. A returned action proposal is not proof the write ran; an acknowledgment
is not a commit receipt. See [runtime capabilities](runtime-capabilities.md).

## Make gaps and retention visible

Catch-up reads use authorized fixed source ranges and original event identity.
Missing history, oversized private views, interrupted jobs, and denied writes must
remain gaps or unknown outcomes. Explicit catch-up is new bounded work, never
replay of old tools. Deduplicate by source, consumer identity, and operation,
while retaining distinct identical prompts as separate occurrences.

Deleting a retrieval entry does not erase original journal evidence, cached
context, backups, or earlier provider transfers. The implemented note policy
requires fresh affected sessions after forget. Automatic invalidation needs a
generic host contract; a domain package must not promise it on its own.

## Build a contributor proof

Choose a small synthetic corpus containing an update, contradiction, expired
record, forgotten ancestor, unanswerable query, and cross-project secret. Write
expected source/span and abstention results before running retrieval. Measure
recall quality separately from deterministic authority/isolation tests. If a
candidate uses encoders or models, include their requests, resources, and known or
unknown costs under matched budgets. A corpus score cannot prove production
semantic quality or absence of leakage.

```sh
mix test test/extensions_memory_test.exs test/extensions_memory_session_test.exs
mix test test/research_test.exs test/research_session_test.exs
```

Use these existing implementations as source-reading exercises, then add focused
fixtures for the new package. Prove default-off empty effects, explicit scope,
approval refusal, stale commit rejection, bounded output, cancellation, and inert
resume before adding automatic lifecycle behavior. The [installed extension
example](extension-proof.md) illustrates independent packaging; its synthetic graph
is a teaching example, not a production engine selected by configuration.
