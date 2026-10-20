# Build and change the knowledge extensions

The knowledge packages keep retrieval, investigation and attributed graphs
outside the host agent loop. Follow one source from an explicit command to a
current citation, then change an algorithm without bypassing source identity,
approvals or recovery.

Start with the [user procedure](../operator/corpus.md) and build the
[independent artifacts](../../extensions/knowledge/README.md). Workers use the
[SDK](extensions.md), [MCP actions](extension-mcp-actions.md),
[embedding actions](extension-embedding-actions.md), state actions and accounted
text requests. They do not open files, sockets or executables or load domain
modules into Session.

## Follow the owners

Read these files in order:

| Owner | Source under `extensions/knowledge/src/` | Responsibility |
| --- | --- | --- |
| Corpus | `corpus.ex` | Explicit source, query and indexing journeys |
| Profiles | `profiles.ex` | Closed named algorithms and compiled capability checks |
| Store | `store.ex` | Root CAS, immutable pages, selected generations, suppression and migration |
| State and MCPCAS | `store/` | Approved storage requests and exact response mapping |
| Evidence | `evidence.ex` | Source/chunk/span validation, ranking, facts and traversal |
| Adapters | `adapters.ex` | Complete selected search, fetch, embedding and text-helper interactions |
| Graph and Research | `graph.ex`, `research.ex` | Independent source/extract/query and investigate/ledger journeys |

Each entrypoint implements `Ipse.Extension.describe/0`, `init/1` and `handle/3`
directly. Shared modules own data and transport rules. They do not select another
package for the caller or introduce a workflow interpreter.

A compiled preset fixes authority. `state-lexical` includes State actions and
omits MCP, embeddings and text-model grants. Its options cannot promote it to
`state-semantic`. The builder changes one known `@preset` literal and compiles
against the public SDK. Import, operator trust and activation remain separate.
All knowledge presets declare SDK 2 and `invoke.result.pages`. The builder
requires the selected descriptor to match that SDK and its compiled capability
list. The operator generator rejects an SDK-1 artifact or a missing page grant.
Changing options cannot upgrade an older artifact's protocol declaration.

Trace `Profiles.compatible?/4` before adding a profile family. Corpus consumes
stores, retrieval, embedding and rerank profiles. Graph consumes stores and
extraction profiles, so its retrieval registry must be empty. Research consumes
search, fetch, BM25 retrieval and optional rerank profiles. A well-formed
`mcp_query`, dense, graph or hybrid profile is still invalid for Research.
Reject unusable selections before `BuildSpec.operator/8` generates their grants.

## Verify independent memory and knowledge selections

Build three independent artifacts and exercise each with explicit memory:

```sh
IPSE_SELECTION_ARTIFACTS=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/corpus" --package corpus --preset state-lexical
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/graph" --package graph --preset state-explicit
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/research" --package research --preset offline
mix run examples/knowledge/verify-independence.exs "$IPSE_SELECTION_ARTIFACTS"
```

Expect ten checks: nine package/scope combinations and one catalog-bound refusal.
Working memory uses session scope; persistent memory uses project or explicitly
shared operator scope. Each pairs with Corpus, Graph and provided-source Research.
The proof uses private homes, distinct storage bindings and a conversation
provider that rejects inference. It requires no model service.

Follow `Proof.independence/1`, `memory_entries/4` and `count_calls/1` in
`examples/knowledge/proof.exs`. Each case begins with disabled and enabled idle
selections. Counters for extension-worker starts, State operations, MCP operations,
embedding operations and text-model operations must remain zero. The proof then
writes or investigates a source, remembers a note with the same source ID, and
queries both. Actual worker/State calls provide a positive counter control.
The note never becomes corpus evidence or a graph fact, and retaining source
text never creates a memory note.

Before forgetting, the proof closes and resumes the exact Session. Its journal
and State file bytes stay unchanged, with zero new counted operations. The report
requires one nested State file for Research with memory, and two for Corpus or
Graph with memory. Match namespace-relative filenames as well as their hashes;
an empty file inventory cannot verify this resume check. The proof then
checks forget isolation: suppressing a note preserves the independent evidence;
forgetting retained knowledge preserves a different explicit note. Research has
no retained knowledge store. Earlier recall remains in the private journal, and
no conversational model turn follows forget. Follow the
[memory recovery policy](../operator/memory.md) for affected real conversations.

The counters use OTP trace-session `call_count` instrumentation. They retain no
arguments or result payloads and require every target function to be instrumented.
They describe host entrypoints. Run the [OS enforcement checks](testing.md#test-actual-os-enforcement)
separately when changing confinement. The selected logical bindings control store
authority; deliberately sharing a binding changes that authority.

All three knowledge packages plus memory exceed the current 16 KiB catalog
bound. That selection must refuse before Session creation, workers or State
operations. Select the packages needed for the task and preserve the existing
32-entry/16 KiB ceiling. Individual pair compatibility does not grant capacity
for every combined selection.

Run the maintained test or the same proof in a matching extracted runtime:

```sh
mix test test/knowledge_independence_test.exs
elixir examples/knowledge/verify-package.exs /path/to/ipse.tar.gz "$IPSE_SELECTION_ARTIFACTS" independence
```

The installed wrapper hides development tools and checks unchanged host/archive
bytes. Omitting `independence` runs the base knowledge proof. These checks verify
selection, isolation and lifecycle behavior; held-out quality remains a separate
[evaluation task](knowledge-evaluation.md).

## Trace a source and a query

Follow `Corpus.source/2` through a small `put`. The entrypoint selects a named
store and validates one exact lifecycle variant before any host request. Extra
fields cannot inject another binding, provider, partition or host operation.

Store reads a bounded snapshot and validates the selected partition. A root CAS
registers a source draft before immutable content and chunk pages are written.
A final CAS selects those pages. Unselected pages are inert; a conflict or
unknown effect never retries publication.

Follow `Store.cas/4` through `root_admission/2` before changing source creation.
A new root uses the actual missing target at revision zero and the completed
snapshot's namespace generation. Store checks capacity again at this boundary.
The State adapter includes the generic `state.put.expected_generation` condition;
the host compares it under its existing namespace file lock. The first creator
advances generation, so a second creator from that snapshot conflicts even at a
different source key. Pages and existing-root updates omit the condition. They
must survive their own earlier page and draft writes. A positive-revision
tombstone at a root key refuses as corrupt store state, rather than becoming a
free source slot.

Keep the 32-root policy in Store. The host knows only revisions, generations and
opaque values. Read the [conditional State contract](extension-host-calls.md#bind-a-write-to-a-namespace-snapshot)
for precedence and exact receipts. The condition introduces no reservation
record, extra host call or automatic retry. Unrelated namespace writes can
conservatively invalidate admission.

Storage revision and source generation have different meanings. Every root
mutation advances its revision. A source generation identifies one complete
source version. Drafts, pages and citations bind that generation and its raw
content hash. A source ID alone does not identify the indexed bytes.

Now follow `Corpus.query/2` with BM25. Store returns validated selected sources,
projections, revision tokens and coverage. Evidence ranks this captured data at
the selected time. Corpus revalidates the captured roots immediately before
returning. A mismatch produces a conflict instead of stale success. That final
check cannot revoke an answer already returned elsewhere.

Query completeness applies to the eligible sources at that selected time.
`suppressed`, `stale_source` and `excluded_fact` diagnostics describe eligibility
exclusions; they remain visible in `gaps` and `coverage.exclusions`. Other gaps
remain failures of coverage. In particular, an unpublished source must produce
`partial` even when the ranking is empty, rather than a complete abstention.
Trace `Evidence.query_scope/4` from the final `:query_revalidate` branches in both
Corpus and Graph. The shared rule keeps their direct and combined routes consistent.

Follow `fuse_ranks/2` when changing graph or hybrid retrieval. It keeps the
component claims, gaps and coverage alongside the fused order. A completed
reciprocal-rank calculation does not prove that a bounded graph traversal
completed. Every required component must be complete before the final result
can claim complete coverage. Missing or replaced fact provenance and missing
embeddings remain partial or refused. Lexical and graph failures retain their
own error codes. Only an actual missing-embedding condition can take the selected
lexical fallback policy.

Corpus chooses its graph seed through `Evidence.graph_seed/4`. That helper first
validates facts at the query's `as_of_ms`, then matches complete entity names at
Unicode letter/number boundaries. It prefers the longest matching subject, with
stable spelling tie-breaks, and uses the query itself when no subject matches.
`Lease` cannot match inside `Release`. Both graph and hybrid retrieval use this
helper. Graph component coverage records the selected `seed`.

In `Evidence.validate_facts/3`, inspect the citation's generation, hash and span
before applying source or fact time policy. A valid expired fact is excluded, while missing or replaced provenance
remains `stale_fact` even if the fact has also expired. An invalid span still
refuses validation.

Keep query population separate from claim context. A Store snapshot has at most
256 retained records, and each distinct facts manifest decodes at most 32 facts.
Evidence derives its conservative query-input ceiling from that product, 8192;
the existing 1 MiB encoded snapshot bound still applies. A manifest belongs to
one source generation and one profile. Its profile fixes the sole valid head
ID, every predecessor must retain that profile, and the chain rejects repeated
keys. It therefore cannot contribute twice through different valid heads or
roots. Store also keeps its per-head 256-fact and per-extraction 32-fact bounds.

Validate the complete input population before seed selection or traversal,
including facts later excluded by time policy. Then retain every selected
supporting assertion and relevant negative or conflicting assertion. This
complete claim context remains bounded to 256 facts. Overflow returns
`graph_context_limit` before classification, with no truncated claims. Graph,
Corpus graph retrieval and hybrid retrieval preserve that named refusal. Run
`mix test test/knowledge_graph_population_test.exs` for the 261-fact public
lifecycle, unrelated expired sources, retained counterassertions and the
256/257-context boundary. The isolated controls also keep unrelated forged
spans fail-closed and enforce the finite population ceiling.

At depth exhaustion, `Evidence.walk/6` checks whether its frontier still has an
unselected positive outgoing fact. If so, the bounded result remains partial.
An empty frontier, a leaf and a fully consumed cycle stay complete. Follow the
depth-zero and chain controls in `test/knowledge_evidence_test.exs`, then compare
the direct Graph and fused Corpus depth controls in
`test/knowledge_query_completeness_test.exs`. They exercise status and coverage
through the public Session, rather than checking only the returned edge count.

Run the public regression before changing these rules:

```sh
mix test test/knowledge_query_completeness_test.exs
```

The lexical case combines current, forgotten, expired and future-dated sources,
then opens an unpublished draft. Compare a query with a valid current passage
to a no-match query before and after that draft. The graph case extracts two
explicit relationships and permits one edge during retrieval. It must retain
the passage and report partial coverage. Query again at the facts' expiry time
with a wide traversal bound. Expect complete abstention with `excluded_fact`
diagnostics. The pure Evidence suite separately checks that missing or replaced
provenance still fails coverage at that same expiry boundary.
The hybrid case allows a lexical fallback for missing vectors; one accounted
synthetic query embedding does not
turn that fallback into complete retrieval. These exercises measure status and
provenance, not semantic answer quality.

Large inputs use explicit `open`, contiguous `append` and `publish` commands.
Each append binds its draft, expected revision and byte offset. Publish verifies
the declared whole-body length and SHA256. An incomplete draft stays inert, and
resume never completes it automatically.

## Separate byte identity from semantic support

Evidence uses raw SHA256 for source text and vector bytes. Domain IDs hash
ordered JSON arrays with a version and tag. Use Elixir's built-in `JSON.encode!/1`
and `JSON.decode!/1`. They preserve Elixir `nil` as JSON `null` and provide a
binary for byte limits. Erlang's raw `:json.encode/1` returns iodata and encodes
the atom `nil` differently, changing persisted values and IDs.

A source contains at most 64 KiB of UTF8 text. Chunking creates at most 32
contiguous chunks of at most 2048 bytes without splitting UTF8 sequences.
Citation offsets are bytes in the complete source. Validation binds the exact
source generation, content hash, chunk ID, quote, quote hash, URI, times and origin.

BM25 uses `k1 = 1.2` and `b = 0.75`. Scoring and excerpt selection share
`token_offsets/1`: each normalized token retains its original UTF-8 byte start.
Downcasing can split one source token into several normalized terms, as with
`İstanbul`. Those terms still refer to the original token's bytes. Never apply
offsets from a downcased string to the captured source. The Unicode regression
places the match after byte 1024 and requires the selected quotation to contain it.

An exact quote proves which bytes were recorded. It does not prove that a claim
follows from them. Facts retain every support citation and extraction identity.
Conflicting assertions remain separate, with explicit polarity. Traversal follows
positive edges only. Before classification, `claim_context/3` retains eligible
negative assertions whose subjects were reached, including the seed. It also
retains assertions that contradict a selected positive fact. A negative object's
name never enters the frontier through that assertion.
The shared `conflicts?/2` predicate owns conflict selection and labels.
Evidence comes from that bounded context before `top_k`; every attributed claim
keeps its own exact citation basis even when its passage falls outside the rank.
Coverage separates traversal `edges`, `context_facts`, `negative_context` and
`counterassertions`. The last field counts additional assertions that conflict
with a selected positive fact. An unrelated predicate on a reached subject can
remain negative context without becoming a counterassertion. A negative-only
query can return attributed evidence with zero traversed edges and one seed node.
The conflict predicate compares object identifiers with the same case-insensitive
matching used for traversal nodes. It preserves the original fields, fact IDs
and citation bytes. A conflict requires the same subject, predicate and object
with opposite polarities. Two positive requirements can coexist because arbitrary
predicates do not declare a single-value constraint. Case variants of one
relationship use the same identity rule. The Evidence regressions exercise both
input orders, compatible requirements and explicit opposites. Under a one-edge
bound, an unvisited compatible requirement leaves coverage partial and stays
outside conflict context.
Lexical results without assessed facts remain open for semantic support.
Research's provided ledger normalizes supplied
provenance and cannot manufacture the native [research ledger](research.md)'s
receipt authority.

For a result without attributed facts, `Evidence.classify/3` keeps an open
claim with `semantic_support_unassessed` and complete citation basis internally.
At publication, `Evidence.public_claims/2` resolves that basis against the final
rank order. When every citation is present, it emits `evidence_indexes`. Each index is a
zero-based position in that result's complete `evidence` array. Follow the
reference to read its full citation; do not interpret it as assessed support.
Attributed graph claims retain their own citation `basis`. An open claim whose
basis includes an unreturned citation also keeps its full basis, so fusion or
truncation cannot erase provenance or produce a dangling reference. The conversion
avoids duplicating every quotation for the synthetic open claim while preserving
source identity. Graph's `top_k` bounds evidence passages, not the citations
retained in each attributed claim's basis.

Run `mix test test/knowledge_packages_test.exs` before changing these bounds.
Its ten-source controls check every returned source and index. The eleventh
source refuses. Ten full 1024-byte quotes use a complete SDK-2 publication with
their exact spans and provenance. An escaped quote also exercises a citation
larger than one 4096-byte transport fragment without raising the domain quote
limit. The suite runs domain modules in a separate VM.

By default, Research chooses its ranking time after capturing the bounded source
set. A gateway can stamp a fetch at completion, so using the invocation's earlier time
would wrongly exclude that newly captured source. Follow `Research.rank/1` and
`publish/1`: the selected time drives ranking and coverage, while each citation
retains its own observation time. An explicit integer `as_of_ms` selects a fixed
time instead, allowing Research and Corpus to share an evaluation snapshot.
Research accepts omission for current time; explicit null refuses. Provided and
fetched routes both report the accumulated raw text bytes. Observations after
the selected time and expiry at or before it remain excluded.
For each fetch or model-rerank decision, Research samples `remaining_ms/1` once.
It refuses values below 1000 as `time_limit` and passes an admitted value unchanged
to the adapter. Sampling again between the guard and request can turn a valid
1000 ms decision into `invalid_adapter_input` at 999 ms.
`next_fetch/1` sends an empty queue directly to ranking before checking the
allowance for another fetch. A valid empty search or final captured body must
remain publishable when no further fetch is needed. Optional reranking retains
its own admission check.

## Read a continuation at the host boundary

Store and Adapters return these private values:

```elixir
{:done, {:ok, value}}
{:done, {:error, fixed_code, bounded_details}}
{:call, exact_host_request, private_continuation}
{:stop, :unknown_effect}
```

The entrypoint converts `:call` to an SDK host proposal. Its next `host.actions`
callback resumes that exact owner. Initialize every key used by a map update;
`%{state | key: value}` raises if `key` was absent. Private state can contain
complete bounded text and vectors. At completion, each entrypoint passes the
whole public JSON object to `Ipse.Extension.ResultPublication.prepare/1`.

Unknown effects terminate the chain. They cannot become empty successful search,
a retry or permission to switch profiles. Session owns journaling, approvals,
accounting, cancellation and cleanup. Domain code preserves those outcomes.

## Publish and read the complete domain value

Read `finish/2` in Corpus, Graph and Research. Each passes its complete output
to the public SDK helper. A small value becomes the ordinary inline `result`
callback. A larger valid value becomes a private
`Ipse.Extension.ResultPublication.Output` containing immutable JSON bytes, their
length and SHA256. It is a callback return value, not a JSON object to serialize
or a host request to execute. An invalid aggregate becomes the small explicit
`result_too_large` refusal. Keep that refusal path when changing a domain output.

The domain still owns source, citation, claim and coverage rules. For example,
quotes remain limited to 1024 UTF8 bytes. The generic transport allows a complete
document of at most 4 MiB with its own string, depth, collection and node bounds.
It fragments bytes in fixed 4096-byte pieces, so one encoded citation can cross
several fragments. Do not shorten a quote or remove Graph basis merely to align
with a fragment. Follow [invocation training](extension-invocations.md#keep-wire-bounds-separate-from-document-bounds)
for the separate bounds and journal reservations.

Bootstrap handles the private output after the domain callback finishes. Session
owns its invocation lease, deadline, reserved journal capacity and final
publication. Host validates the complete document and declared schema, then
confirms worker cleanup. Only the committed final invocation result makes the
saved descriptor readable. No Corpus, Graph or Research module loads into the
host for this work. Ordinary inline results keep their existing shape.

Consumers must distinguish that descriptor from a domain value. Use
`Ipse.Session.materialize_result/2` with the exact saved delivery before reading
`evidence`, `claims`, `coverage` or `status`. It returns the complete decoded value
and exact retained bytes with `provenance: "historical_receipt"`. A failed read
cannot become an empty ranking, an inline fallback or a repeated query.
The [evaluation driver](knowledge-evaluation.md#materialize-before-interpreting-a-result)
shows that boundary before answer preparation and metrics.

For a worked exercise, build the three artifacts from the selection exercise
above, then run:

```sh
mix run examples/knowledge/verify-complete-results.exs "$IPSE_SELECTION_ARTIFACTS"
elixir examples/knowledge/verify-package.exs /path/to/ipse.tar.gz "$IPSE_SELECTION_ARTIFACTS" complete
```

Read `examples/knowledge/complete-result-proof.exs` alongside its five checks.
Research and Corpus each return ten full quotations. A second Research case
retains an escaped citation larger than a fragment. Graph returns eight full
claims while `top_k: 1` leaves some claim bases outside the evidence list. The
exercise checks every cited span, complete hashes, an exact historical read and
unchanged journal bytes after idle restart. Expect zero model requests, confirmed
cleanup and no production domain modules in the host. The fifth check records
opposite assertions and requires both polarity/citation claims in direct Graph
and Corpus graph retrieval, even with one returned passage. These are protocol
controls, not semantic support judgments.

The installed `complete` wrapper compiles its trusted proof harness in the outer
development VM before starting the extracted runtime. The runtime loads the
prebuilt harness and artifact BEAMs with development tools absent from its PATH.
It rechecks archive, artifact, host and harness identities afterward. Build the
archive and artifacts for the same platform and OTP release.

For dense citation changes, follow `dense_candidates/3` into the shared
`Evidence.utf8_prefix/2` boundary. Preserve the ordinary 200-grapheme excerpt,
then cap its bytes at 1024 before constructing the citation. The package test
uses a single combining grapheme longer than that limit with a valid vector,
and separately removes the vector to keep the real missing-index refusal.

## Plan projections before inference

Indexing and extraction first claim a source-bound projection draft. Store
returns selected chunks, an opaque token and a capacity plan. The entrypoint
checks the remaining effect/read allowance before inference and passes validated
results back with that token. Store owns page packing and final publication.

For embeddings, follow `Adapters.run(:embed, ...)` into an explicit
`embedding.create` v2 request. The successful host value carries
`selection_sha256`, derived from the original approved binding by
`EmbeddingProfiles`. Adapters copies that authenticated identity into each closed
v2 Evidence vector. `Evidence.compatible_vectors?/2` requires two valid current
vectors with equal selection hash, host profile, reported model, dimensions and
encoding. Both direct cosine ranking and Corpus candidate selection use it.
An exact legacy v1 vector remains structurally readable, but is never eligible
for dense comparison. Legacy or changed selections take the existing
missing-embedding refusal or explicitly configured partial lexical fallback.

Store reads version-specific vector records and coordinate parts, requiring
their metadata to agree. It validates selection homogeneity across each complete
projection chain before deduplicating chunk IDs. A newer duplicate must never
hide an incompatible older record. Keep one head for each existing domain
embedding profile. Fully compatible batches append. An explicitly indexed batch
with a different selection, reported model or legacy vector sets `previous` to null under the same root
CAS, without copying old chunks into the new chain. Detached pages remain
collectible through the ordinary explicit collection path. Other heads, source
text, facts and suppression retain their existing ownership.

New vector drafts, capacity plans and private tokens mark `vector_version: 2`.
The registered draft's plan hash includes this requirement. An older draft stays
inspectable and exactly abortable, but cannot be promoted or committed with a new
token. A fresh `next` refuses while that draft is active. Source and fact drafts
keep their existing formats. Follow the State and MCP controls in
`test/knowledge_store_test.exs` through append, selection replacement, legacy
decode, mixed-chain refusal and an attempted old-draft promotion.

For explicit extraction, Graph passes the known facts into the draft preflight.
Store packs their actual encoded pages before claiming the root. A maximum of
32 facts is a count ceiling, not a reservation of 32 worst-case records. For
model extraction, Store derives an affordable page allowance from the remaining
effect and record capacity before approving inference. Commit packs the actual
returned facts and checks that they fit that allowance. Oversized output leaves
the draft available for inspection and exact abort.

The extraction adapter sends `max_facts` alongside selected chunk text, assigning
local IDs `c1` and `c2` in selection order. The model returns only `facts`, whose
items have exactly `subject`, `predicate`, `object`, `polarity`, `chunk` and
`quote`. It copies a short chunk ID and an exact supporting quote of at most
1024 UTF8 bytes. It does not calculate offsets or supply canonical hashes.
`negative` polarity means an explicitly denied relationship, never missing evidence.

Follow `Adapters.proposal_fact/2` and `quote_span/2`. The quote must occur exactly
once inside that selected chunk, counting overlapping matches. Normalized Unicode,
changed whitespace, absent text and ambiguous repeats refuse. A match in another
chunk does not select that chunk. The adapter derives absolute half-open byte
offsets, constructs the existing citation and checks its bytes against the
proposal. The decoder also enforces fact count, profile, closed fields and
duplicate-key rejection. Any invalid proposal refuses the whole response.
Publication uses `Adapters.attributable_facts?/2` to validate shape and
source spans, then Store validates the selected chunks and live draft again.
`Evidence.validate_facts/3` owns query-time eligibility. Calling it during
publication would silently discard future or past facts before a caller could
query their validity interval.

For example, select a chunk beginning at byte 2048 with text
`Éclair does not require β.`. Its model input contains
`{"id":"c1","text":"Éclair does not require β."}`. A valid response is:

```json
{"facts":[{"subject":"Éclair","predicate":"requires","object":"β","polarity":"negative","chunk":"c1","quote":"Éclair does not require β."}]}
```

The decoder finds local offset zero and derives the absolute range from 2048 to
`2048 + byte_size(quote)`. It preserves both multibyte characters. If that quote
occurs twice in the selected chunk, the same response refuses. The model must
select a longer unique supporting quote within the limit or return no fact.
Use the corresponding package regression to follow this example through real
citation validation, including the same quote in two separately selected chunks.

Run `mix test test/knowledge_packages_test.exs` and follow its public Graph
exercise. Extract a future-valid fact, query before its interval and expect
complete abstention with `excluded_fact`. Query inside the interval and expect
the retained fact and its original basis. The same exercise covers a past
interval, a future-observed source and refused attribution to another generation.
The model adapter control retains future-observed attribution without making a
model request. Existing controls still refuse over-limit model proposals.

The reranker assigns short IDs `e1` through `e16` in candidate order. Each model
input entry has `id`, `ref` and a bounded `quote`. The model returns exactly one
`order` object containing every short ID once. A bare array, omitted candidate,
duplicate, extra field or foreign ID refuses; none becomes an implicit successful
lexical fallback. The adapter translates the accepted permutation to canonical
candidate IDs before returning it to Corpus or Research.

The input's `ref` retains the canonical chunk digest and absolute `start_byte`
and `end_byte`, separated by colons. It allows independent approval to check the
exact source span even when two candidates have identical displayed prefixes.
The model copies only `id` in its output. Canonical span IDs remain separate from
fusion identity. The immutable continuation and host's operation/request binding
own response identity; there is no extra model-echo nonce or retry.

`Evidence.fuse/3` uses reciprocal rank fusion with constant 60 over chunk identity.
Its key includes the Store-generated profile/partition namespace, source key,
generation, content hash and chunk ID. Each component contributes once per chunk,
even if graph facts cite several spans in it. A chunk ranked first by lexical
and dense retrieval receives `1/61 + 1/61` and occupies one final rank slot.
The best component rank chooses its exact representative citation. Earlier
components win equal-rank ties. Corpus orders components lexical, dense, graph.
Graph claims retain every original citation basis, including spans outside that
representative or `top_k`. Do not replace persisted chunk IDs or the existing
span/rerank ID format to change this accumulation key.

For example, reverse two candidates with `Evidence.apply_rerank([a, b],
[Evidence.candidate_id(b), Evidence.candidate_id(a)])`. Read the same-chunk
regression in `test/knowledge_evidence_test.exs`, then the real Session rerank
fixture in `test/knowledge_evaluation_runner_test.exs`. The evaluation approval
validator independently parses canonical `ref` values, checks deterministic short
IDs, unique references, the exact current chunk and span bounds, and recomputes
the shown prefix. It loads no production domain
module into the host. A quote occurring elsewhere in the chunk is insufficient.

The named quote ceiling counts UTF8 bytes. Prefix selection preserves a
code-point boundary, including
for a single grapheme with many combining characters. Exercise that byte-bound
case before replacing it with a character-slicing function.

Two 4096-coordinate vectors require 12 coordinate pages, one manifest and one
final CAS. With one draft claim and one embedding call, that is 16 effects.
Result reads use their separate allowance. MCP counts every call as an effect,
including reads. State indexing admits one or two selected chunks. MCP indexing
admits exactly one chunk per invocation and can still refuse its capacity plan.
Metadata-heavy facts may need smaller explicit batches. Do not dispatch inference
if its result cannot fit the preflight plan.

Host embedding input hashes are opaque. Bind result indices to their original
inputs and require stable host hashes across pages. Keep raw input hashes
separately as receipt provenance. The host validates its typed input identity
against the approved input. Comparing a raw hash with a second hash of the same
local text does not authenticate a returned vector. Verify descriptor identity,
offsets, full dimensions, canonical Base64, float32 encoding and vector SHA256.
The complete finite float32 range
is valid, including both signed maxima. The package regression also supplies
infinity and NaN bit patterns and requires refusal. Never shorten a vector to
fit a text response.

## Preserve suppression and migration

Work through this race before changing publication:

```text
claim source generation 4 → start extraction
forget source generation 4 → publish permanent suppression
finish delayed extraction → refuse stale or suppressed commit
```

Suppression roots retain hashes, generation and partition without source text,
title or URI. Old imports and delayed drafts cannot restore them. Graph traversal
validates every supporting source. Queries do not rebuild missing projections.

All root creation, including suppression import, passes `Store.capacity/3`.
Its callers supply the added record count and added root count from the actual
destination record. A suppression export has no original `source_id`, so import
uses its destination key instead of trying to reconstruct that ID. Each partition
permits 32 roots. Snapshot revalidation has the same 32-token bound. The Store
regression fills that capacity through ordinary imports, refuses another root
without a write and still suppresses an existing live source at the ceiling.
Separate State controls fill shared record and byte capacity with another
partition's records and require refusal before a write.

Counting alone does not make concurrent creation safe. The mixed-operation
regression stages put, open, forget, source import and suppression import after
their reads, then releases their first writes one at a time. Each creator gets a
turn as the first writer. Exactly one can consume the last slot, and the resulting
32 tokens must pass public revalidation. A separate control repeats the
distinct-key race through canonical `State.execute/4`, rather than the synthetic
adapter fixture. Run both Store and State suites when changing admission:

```sh
mix test test/knowledge_store_test.exs test/extensions_state_test.exs
```

Older stores can already contain more than 32 roots. Whole-store snapshots refuse
with `root_capacity_exceeded` before emitting oversized token sets. Addressed
inspection, paged export and existing-root maintenance remain available within
the record, byte and invocation limits and the remote snapshot ceiling below.
Adding another root refuses. Suppression
retains a root and therefore cannot repair an overfull partition. Preserve the
data for deliberate migration; do not truncate it or widen query token bounds.

The bound assumes corrected writers. Before selecting new artifacts against a
shared binding, drain older Sessions and their admitted effects, then retire
their writer configuration. Optional generic State conditions cannot constrain
an arbitrary trusted writer that omits them. Valid format-1 stores with at most
32 roots need no data migration.

Collection removes unreachable bodies while retaining tombstones. It does not
recover retained record slots: State allows 256 per namespace, while a qualified
MCP partition allows 88. The 1 MiB ceiling includes old generations, drafts,
orphan pages and tombstones.

Follow `Store.export_source/1` and `export_prefix/5` before changing migration.
An export takes a contiguous UTF-8 prefix bounded by `limit * 4096`, 8192 and
the remaining source bytes. `limit` is 1..4. The packer shrinks the prefix until
the complete envelope fits 12000 encoded bytes and the SDK object limits.
Quotation marks, control bytes and newlines can require smaller parts.
The legacy complete single-part form repeats `source.text` only when that whole
envelope also fits. Otherwise metadata and the top-level `text` remain separate.
Source import reconstructs those bytes, validates their content hash and requires
cursor zero, no continuation, complete content and at most 8192 raw bytes.
A complete final fragment at a nonzero cursor is not a complete import.
Larger migrations use reviewed paged `open`/`append`/`publish` work while retaining
historical import provenance. Projection heads are disclosed as metadata, but
projection contents are omitted and need explicit rebuilding.

Foreign copies become historical assertions. Extraction and indexing preserve that flag, so
`Evidence.current?/2` still excludes them. Current evidence requires an explicit
fresh source replacement with a newer generation and inspected root revision,
without `historical_import`, followed by its required projections. Do not treat
reindexing an imported record as promotion to current evidence.
Suppression cannot erase journals, backups, prior transfers or independent stores.

An explicitly aborted draft also invalidates delayed publication. Store's `:abort`
operation requires the inspected root revision and exact draft ID for source, fact or vector
work. `source_draft_current/1` adds the source-kind restriction for append/publish;
clearing a fact draft cannot turn it into publishable source content. Work through
`test/knowledge_store_test.exs` for State and MCP controls: wrong ID/revision,
source publication against a projection, stale completion, a newer draft and
permanent suppression.

Corpus `index` aborts use the same Store continuation as projection commits.
After a successful abort, the receipt must include the generation actually read
from the committed root as well as its revision. Corpus checks both fields before
reporting success. A cleared draft is not enough if its receipt fails that fence.
Run `mix test test/knowledge_index_abort_test.exs` to exercise real Corpus and
Store callbacks against State and MCP CAS. The controls cover successful abort,
stale profile/generation/chunks, repeated abort, delayed completion and a source
replacement whose generation differs from the abandoned draft's target.

Then run the public Graph-only recovery exercise with a fresh `state-model`
artifact. It denies model egress, inspects the retained draft and approves its
exact abort without selecting Corpus or a model service:

```sh
mix run examples/knowledge/verify-recovery.exs /path/to/graph-state-model
elixir examples/knowledge/verify-recovery-package.exs /path/to/ipse.tar.gz /path/to/graph-state-model
```

Expect eight successful checks, zero model requests and confirmed cleanup. The
installed exercise hides development tools and checks unchanged host/archive
files. Neither exercise measures semantic extraction quality.

## Implement a compatible remote store

Read `store/mcp_cas.ex` with the independent atomic owner in
`test/support/knowledge_mcp_fixture.exs`. The fixture is the executable contract
reference. A service must also enforce the selected partition's access policy.
An exact receipt establishes what that service asserted, not how it implemented
its transaction or authorized access internally.

New record-adding work requires an explicit `ipse-cas-v3` profile. V3 uses inner
envelope version 3 and the same action fields and persisted root/page bodies as
v2. The surrounding `mcp.call` and `mcp.text` result-window transport remain
version 1. Never infer or upgrade a selected contract from a server response.

### Bind requests and replies

Every CAS request contains exactly these fields. This is a complete empty-store
snapshot request:

```json
{
  "version": 3,
  "contract": "ipse-cas-v3",
  "partition": "manual",
  "request_id": "11111111111111111111111111111111",
  "action": "snapshot",
  "args": {}
}
```

A successful empty-store reply contains exactly these fields:

```json
{
  "version": 3,
  "contract": "ipse-cas-v3",
  "partition": "manual",
  "request_id": "11111111111111111111111111111111",
  "action": "snapshot",
  "status": "ok",
  "generation": 0,
  "value": {"records": [], "count": 0, "bytes": 2, "complete": true}
}
```

The response echoes version, contract, partition, action and the fresh 32-digit
lowercase hexadecimal request ID. `status` is `ok`, `conflict` or `refused`.
`generation` is a nonnegative safe integer through 9007199254740991, and `value`
is an object. Unknown fields or mismatched identity refuse as `store_response`.
A failed action must not mutate the partition.

The action-specific argument and success-value objects are also closed:

| Action | Exact `args` fields | Exact successful `value` fields |
| --- | --- | --- |
| `snapshot` | Empty object | `records`, `count`, `bytes`, `complete: true` |
| `get_many` | `keys`: 1..8 record-key hashes | `records` in requested key order, `complete: true` |
| `put_immutable_many` | `pages`: 1..2 objects with `key`, `value`, `expected_revision: 0` | `records` in page order |
| `cas_root` | `key`, `expected_revision`, `expected_generation`, `expected_source_generation`, `expected_content_sha256`, `draft_id`, `next_root` | `record` |
| `collect` | `keys`: 1..12 distinct page keys, `snapshot_generation` | `records` in requested key order |

Full records contain exactly `key`, `revision`, `deleted` and `value`. Keys are
64-digit lowercase hexadecimal hashes. A missing record has revision zero,
`deleted: true` and `value: null`. A live record has a positive revision and an
object value. A tombstone retains its positive revision with `value: null`.
Directory metadata contains exactly `key`, `revision`, `deleted` and `kind`, with
positive revisions and kind `root`, `page` or `tombstone`. Directory keys are
unique. The directory's declared count equals its row count, at most 256, and its
reported encoded storage size is at most 1048576 bytes. Those transport bounds
do not replace v3's stricter 88-record admission rule.

Snapshot record groups must agree with the directory's revisions and deletion
flags, and all replies must retain the captured generation. `get_many` reports
missing keys explicitly rather than omitting rows. Immutable page writes require
unused keys and return exact values at revision one. Collection checks its
snapshot generation and every currently reachable root/draft reference under
the atomic owner. It replaces only unprotected pages with tombstones and advances
their revisions and the store generation once.

Each complete CAS JSON text result is at most 60000 bytes. The adapter reads it
in windows of at most 4096 bytes with exact operation/source identity and offsets.
A request must fit the SDK object bound, 15000 encoded bytes and the adapter's
32768-byte displayed-argument bound. `MCPCAS.write_batches/2` tests the actual
selected contract envelope before choosing one or two immutable pages.

### Enforce root conditions and the retained-record ceiling

For a new root, `expected_revision` is zero and `expected_generation` is the
completed snapshot's store generation. Existing-root updates use null for the
store-generation condition and retain the exact revision, source generation,
content hash and draft conditions. The server checks every supplied condition
under one atomic owner before changing the root. Permanent suppression refuses
replacement. A positive-revision tombstone at a root key is corrupt state, not
a free creation slot.

A successful root CAS returns the exact `next_root` at target revision plus one.
A conditioned creation returns captured store generation plus one. V2 and v3
positive record receipts and conflict summaries require record revision no
greater than store generation. A `cas_root` conflict contains exactly
`value: {"record": SUMMARY}`. The summary contains `key`, `revision`, `deleted`,
`source_generation`, `content_sha256` and `draft_id`. Missing/deleted records use
null source fields. A suppression retains its positive source generation and
null hash/draft. A live root reports its hash and nullable draft ID. At least
one requested condition must differ; an otherwise matching summary cannot claim
conflict. No source body is disclosed.

A qualified v3 owner atomically refuses any write that would exceed 88 retained
keys in the partition, including roots, immutable pages, orphan pages and
tombstones. It applies this ceiling to every accepted writer/version route,
including v1 and v2 requests. A per-client snapshot count is insufficient:
concurrent writers could otherwise both consume the last slot. Store also checks
88 locally, along with 32 roots, encoded bytes and the invocation allowance.
A draft claim does not reserve future slots. Competing writers can still make
publication refuse, leaving an inspectable, exactly abortable draft.

A full snapshot consumes `1 + ceil(records / 8)` MCP effects: one directory call
and groups of at most eight full records. At 88 records it consumes 12 of the
16 effects available to the invocation. Additional writes, rechecks or model
calls must fit the remaining allowance, so `effect_limit` can refuse work before
record capacity is exhausted. Result-window reads use their separate read
allowance; MCP calls themselves are effects even when they read data.

An inherited partition above 88 records returns `remote_snapshot_limit` before
Store can inspect even one addressed source. Use the selected server's reviewed
administrative export/migration procedure. Do not promise that Ipse's ordinary
`inspect`, `export` or abort commands can bypass this full-snapshot ceiling.
The atomic v3 rule prevents qualified writers from creating that unreadable state.

### Cut over without changing stored bodies

V1 and v2 profiles retain their original read envelopes and zero-record
maintenance. Existing-root `open` claims, exact abort, forget and collection can
remain available within the ordinary snapshot, byte and effect limits. A `put`
replacement still creates immutable pages, so it needs v3 even if its root
already exists. Append, publish and projection work that add records also refuse
`atomic_capacity_unavailable` under legacy profiles. A v1 missing-root CAS
additionally lacks atomic root admission and refuses `atomic_admission_unavailable`.

To change a shared service, drain older Sessions and admitted effects, qualify
its partition-wide atomic ceiling across every writer route, then explicitly
select `ipse-cas-v3` in a fresh reviewed configuration and Session. Retire writer
routes that bypass the guarantee. The contract choice neither copies local
State data nor changes the persisted root/page body format. It has no fallback
to v2 or a different service.

## Implement selected remote retrieval

`mcp_query` belongs to Corpus. It returns ranked source/chunk references through
`query-v1`; Research continues to rank its captured source set with BM25. The
selected Corpus store must be `mcp_cas`, and the store and retrieval profiles must
name the same partition. Bind storage and query aliases separately, even when
they resolve to the same reviewed server.

For a runnable operator setup, use
[Corpus remote retrieval](../operator/corpus.md#retrieve-server-selected-passages).
Its complete options and binding examples build with `mcp-lexical` and require
no embeddings or model service. Trace `Corpus.query/2` into
`Adapters.run(:query_refs, ...)` and then `Store.snapshot_selected`.

The query tool receives exactly this object:

```json
{
  "version": 1,
  "contract": "query-v1",
  "partition": "manual",
  "request_id": "22222222222222222222222222222222",
  "query": "release quiescence",
  "top_k": 5,
  "as_of_ms": 1700000020000
}
```

A complete empty result has this closed response shape:

```json
{
  "version": 1,
  "contract": "query-v1",
  "partition": "manual",
  "request_id": "22222222222222222222222222222222",
  "status": "ok",
  "generation": 0,
  "algorithm": "fixture_terms",
  "algorithm_version": 1,
  "scanned_sources": 0,
  "scanned_chunks": 0,
  "complete": true,
  "refs": []
}
```

The response echoes version, contract, partition and request ID. `status` is `ok`
or `refused`, but only `ok` with `complete: true` is accepted. `generation` is the
captured store generation. Algorithm name is 1..64 ASCII letters, digits,
underscores, dots or hyphens, and algorithm version is a positive safe integer.
`scanned_sources` is 0..32 and `scanned_chunks` is 0..1024. Query text is
1..1024 UTF-8 bytes, `top_k` is 1..10, and `as_of_ms` is a nonnegative safe integer.
Each request gets a fresh 32-digit hexadecimal ID. The example IDs are fixed only
to make request/reply correspondence visible.

Each nonempty `refs` item contains exactly `source_id`, `source_key`, `generation`,
`content_sha256`, `chunk_id` and `score`. Source IDs are 1..256 UTF-8 bytes without
control characters, source keys equal raw SHA-256 of their source IDs, source
generation is positive, and both content/chunk hashes are 64-digit lowercase
hexadecimal. Scores are finite numbers. References are unique by source key and
chunk ID, and count cannot exceed requested `top_k`. The result text is at most
65536 bytes and uses the same bounded MCP text-window transport as search/fetch.

Store reads only those selected roots and referenced pages at the reported store
generation. It validates the actual source bytes, generation, chunk identity and
eligibility at `as_of_ms`, then revalidates the roots before returning evidence.
Stale, suppressed, historical, forged or wrong-partition selections refuse the
whole result. Empty references produce complete abstention without Store reads.
No full partition directory is scanned on this route, so coverage does not claim
a whole-store root count check. Scores retain `score_provenance: "server_asserted"`.
They are not local BM25 scores or a verified statement about the server's index.

Run the public protocol control with an independently built MCP Corpus artifact:

```sh
mix run examples/knowledge/verify-mcp.exs /path/to/corpus-mcp-lexical
```

Follow `examples/knowledge/mcp-proof.exs` through selected-only reads, denied
query dispatch, wrong partitions, incomplete results, forged hashes and stale
generation. The empty-result control makes exactly one query call. The interrupted
control resumes idle without replay. These fixture responses establish protocol
behavior, not retrieval quality or a real service's access controls.

## Exercise delayed publication and interrupted inference

Run the domain lifecycle controls before changing projection publication:

```sh
mix test test/knowledge_lifecycle_proof_test.exs
```

Open `examples/knowledge/lifecycle-proof.exs`. Each package runs seven cases through
real public Sessions and its independently built worker. An owned loopback server
returns scripted text or two-coordinate vectors. No model weights or external
service are used, and these responses measure no retrieval quality.

Follow the `forget` case through `interrupted/5`. The first Session registers a
projection draft, obtains egress approval and dispatches its provider request.
The fixture reports that accepted request before returning a response. A second
Session uses the same operator selection, home and workspace, inspects the live
draft and publishes suppression. Only then does the fixture release the first
response. Its delayed publication must refuse. A public inspection still reports
suppression, and a query returns no evidence. Separate Session journals retain
their own operations even though the logical State store is shared.

Compare the other cases:

| Trigger | Required observation |
| --- | --- |
| Cancellation after dispatch | Session cancellation finishes, the provider socket closes, unconfirmed inference retains reservations, and idle resume adds no action intent |
| Session death after dispatch | The socket and Session lock close; no Session cleanup acknowledgment is invented; saved uncertainty remains and idle resume does not replay |
| Selected profile deadline expires | The held request times out, the socket closes, no projection is published and uncertainty remains accounted |
| One-request budget exhausted | The first projection completes; a second attempt is refused before another HTTP request and preserves the selected projection |
| Malformed provider output | No projection is published; the domain retains the failed result and its ordinary accounting |
| Provider unavailable | No successful projection or fallback appears; the actual request remains in canonical accounting |

For Corpus, the malformed and unavailable cases then inspect the retained draft
and explicitly abort it through `index`. The receipt must report the committed
generation and next revision, inspection must show no draft, and the provider
request count must stay unchanged. This exercises recovery through the public
worker protocol as well as the lower-level CAS controls.

Unknown embedding work retains its input reservation and no text-output liability.
Unknown extraction retains both input and output reservations. Read
`uncertainty/2`, `Budget.saved/2` and the canonical journal together; a request
attempt alone does not prove dispatch or settlement. Every case closes or accounts
for its Session and checks an idle resume before asserting zero further requests.

Build the same independent artifacts for a standalone source exercise:

```sh
IPSE_LIFECYCLE_ARTIFACTS=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LIFECYCLE_ARTIFACTS/graph" --package graph --preset state-model
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LIFECYCLE_ARTIFACTS/corpus" --package corpus --preset state-dense
mix run examples/knowledge/verify-lifecycle.exs "$IPSE_LIFECYCLE_ARTIFACTS/graph" graph
mix run examples/knowledge/verify-lifecycle.exs "$IPSE_LIFECYCLE_ARTIFACTS/corpus" corpus
```

Expect seven checks and seven synthetic provider requests per package, with
`actual_model_inference: false`. For installed execution, replace
`/path/to/ipse.tar.gz` with one matching archive built through the
[extracted-package procedure](testing.md#verify-the-extracted-package):

```sh
elixir examples/knowledge/verify-recovery-package.exs /path/to/ipse.tar.gz "$IPSE_LIFECYCLE_ARTIFACTS/graph" graph
elixir examples/knowledge/verify-recovery-package.exs /path/to/ipse.tar.gz "$IPSE_LIFECYCLE_ARTIFACTS/corpus" corpus
```

The optional third argument selects the lifecycle cases. Omitting it selects
the eight-check Graph abort exercise. Both installed routes hide the
development toolchain and check unchanged archive and host bytes.

Exercise durable embedding identity with the same Corpus artifact:

```sh
mix run examples/knowledge/verify-lifecycle.exs "$IPSE_LIFECYCLE_ARTIFACTS/corpus" selection
elixir examples/knowledge/verify-recovery-package.exs /path/to/ipse.tar.gz "$IPSE_LIFECYCLE_ARTIFACTS/corpus" selection
```

Follow `LifecycleProof.selection/1`. It uses two owned loopback endpoints with
the same requested/reported model and two-coordinate width, but different vector
values. Index and query at A, then open a fresh Session at B against the same
durable State binding. Dense retrieval must refuse; an explicit lexical fallback
must remain partial. Reindex at B and require successful dense retrieval. Change
only its timeout and require reuse, then resume an earlier Session without IO.
At that same endpoint, change the fixture's reported model. Querying must refuse
the old vectors, while explicit reindex and the next query succeed under the same
approved selection hash. Expect ten synthetic requests, exact v2 selection receipts, valid accounting
and confirmed cleanup. These responses establish configuration separation and
recovery behavior, not retrieval quality or remote weight identity.

For a change exercise, use an older `expected_revision` in the forget command.
The public command must refuse and the control must fail at its expected-success
assertion. Restore the inspected revision and rerun. This distinguishes a real
suppression race from a fixture that never performed the competing mutation.

## Change the lexical ranker as an exercise

1. Read `Evidence.rank_lexical/4`, tokenization and tie ordering. Record the current
   BM25 parameters and no-match behavior.
2. Add a development case with two sources containing the same terms at different
   frequencies. State the expected order independently of rank output.
3. Run the pure suite. Domain modules load only in isolated VMs.
4. Build a fresh lexical artifact and run the independent Session proof. Check
   exact generations/spans, revalidation and zero model requests. A direct module
   test alone does not prove SDK behavior.

```sh
mix test test/knowledge_evidence_test.exs test/knowledge_profiles_test.exs test/knowledge_domain_regressions_test.exs
mix test test/knowledge_store_test.exs test/knowledge_packages_test.exs
mix test test/knowledge_build_spec_test.exs
```

Use the [artifact procedure](../../extensions/knowledge/README.md#verify-independent-artifacts)
for source execution. Run `examples/knowledge/verify-package.exs` with a bundled
runtime and independently built artifacts for installed execution with development
tools hidden. Both proofs assert that domain modules remain unloaded in the host.
Build a separate Research `mcp` artifact and run
`mix run examples/knowledge/verify-research.exs ARTIFACT` to follow the complete
search, paged fetch and citation path. Inspect the exact approval bindings,
captured-body hash, completion-time observation and the negative-result cases.
The [Research procedure](../operator/research-extensions.md) documents the closed
gateway contract; a tool with a similar name need not implement it.
For measurement work, follow the [knowledge evaluation exercises](knowledge-evaluation.md)
through saved predictions, bounded answer context, independent review and scoring.
Keep protocol checks separate from held-out retrieval, semantic support, citation
and resource measurements. The [plan](../plan.md#p27-optional-research-graph-and-rag)
owns their acceptance status; a passing fixture does not establish model quality.
