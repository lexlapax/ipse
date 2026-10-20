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
embeddings remain partial or refused. In `Evidence.validate_facts/3`, inspect
the citation's generation, hash and span before applying source or fact time
policy. A valid expired fact is excluded, while missing or replaced provenance
remains `stale_fact` even if the fact has also expired. An invalid span still
refuses validation.

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
The hybrid case allows a lexical
fallback for missing vectors; one accounted synthetic query embedding does not
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

An exact quote proves which bytes were recorded. It does not prove that a claim
follows from them. Facts retain every support citation and extraction identity.
Conflicting assertions remain separate, with explicit polarity. Traversal still
follows positive edges only. Before classification, `claim_context/2` adds each
current validated assertion that contradicts a reached fact, without traversing
its edge. The shared `conflicts?/2` predicate owns both selection and labels.
Evidence comes from that bounded context before `top_k`; every attributed claim
keeps its own exact citation basis even when its passage falls outside the rank.
Coverage separates traversal edges from context facts and counterassertions.
The conflict predicate compares object identifiers with the same case-insensitive
matching used for traversal nodes. It preserves the original fields, fact IDs
and citation bytes. A conflict requires the same subject, predicate and object
with opposite polarities. Two positive requirements can coexist because arbitrary
predicates do not declare a single-value constraint. Case variants of one
relationship use the same identity rule. The Evidence regressions exercise both
input orders, compatible requirements and explicit opposites. Under a one-edge
bound, an unvisited compatible requirement leaves coverage partial and stays
outside conflict context.
Lexical results without assessed facts
remain open for semantic support. Research's provided ledger normalizes supplied
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

By default, Research chooses its ranking time after capturing the bounded source set. A
gateway can stamp a fetch at completion, so using the invocation's earlier time
would wrongly exclude that newly captured source. Follow `Research.rank/1` and
`publish/1`: the selected time drives ranking and coverage, while each citation
retains its own observation time. An explicit integer `as_of_ms` selects a fixed
time instead, allowing Research and Corpus to share an evaluation snapshot.
Research accepts omission for current time; explicit null refuses. Provided and
fetched routes both report the accumulated raw text bytes. Observations after
the selected time and expiry at or before it remain excluded.

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

The extraction adapter sends `max_facts` alongside the selected chunks. Its fixed
instruction specifies the closed fact fields and absolute half-open UTF8 byte
offsets. The decoder separately enforces the requested fact count, selected
profile, chunk identity and exact spans. A prompt is not a substitute for those
checks. Publication uses `Adapters.attributable_facts?/2` to validate shape and
source spans, then Store validates the selected chunks and live draft again.
`Evidence.validate_facts/3` owns query-time eligibility. Calling it during
publication would silently discard future or past facts before a caller could
query their validity interval.

Run `mix test test/knowledge_packages_test.exs` and follow its public Graph
exercise. Extract a future-valid fact, query before its interval and expect
complete abstention with `excluded_fact`. Query inside the interval and expect
the retained fact and its original basis. The same exercise covers a past
interval, a future-observed source and refused attribution to another generation.
The model adapter control retains future-observed attribution without making a
model request. Existing controls still refuse over-limit model proposals.

The reranker requires a complete candidate-ID permutation inside exactly one
`order` object. A bare array, omitted candidate, duplicate or foreign ID refuses;
none becomes an implicit successful lexical fallback. A candidate ID is the
chunk digest followed by its absolute `start_byte` and `end_byte`, separated by
colons. Chunk identity already binds source, generation and content; offsets
distinguish lexical, dense or graph excerpts from that same chunk. Fusion keeps
those distinct spans. Reranking changes their order without dropping either
quote or its provenance.

For example, reverse two candidates with `Evidence.apply_rerank([a, b],
[Evidence.candidate_id(b), Evidence.candidate_id(a)])`. Read the same-chunk
regression in `test/knowledge_evidence_test.exs`, then the real Session rerank
fixture in `test/knowledge_evaluation_runner_test.exs`. The evaluation approval
validator independently parses canonical IDs, checks the exact current chunk and
span bounds, and recomputes the shown prefix. It loads no production domain
module into the host. A quote occurring elsewhere in the chunk is insufficient.

The named quote ceiling
counts UTF8 bytes. Prefix selection preserves a code-point boundary, including
for a single grapheme with many combining characters. Exercise that byte-bound
case before replacing it with a character-slicing function.

Two 4096-coordinate vectors require 12 coordinate pages, one manifest and one
final CAS. With one draft claim and one embedding call, that is 16 effects.
Result reads use their separate allowance. MCP counts every call as an effect,
including reads. It may require one chunk or a refusal. Metadata-heavy facts may
also need smaller explicit batches. Do not dispatch inference if its result
cannot fit the preflight plan.

Host embedding input hashes are opaque. Bind result indices to their original
inputs and require stable host hashes across pages. Keep raw input hashes
separately. Verify descriptor identity, offsets, full dimensions, canonical
Base64, float32 encoding and vector SHA256. The complete finite float32 range
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

Collection removes unreachable bodies while retaining State tombstones. It does
not recover the 256-record allowance. The 1 MiB ceiling includes old generations,
drafts, orphan pages and tombstones. Selected exports are paged. Foreign copies
become historical assertions. Extraction and indexing preserve that flag, so
`Evidence.current?/2` still excludes them. Current evidence requires an explicit
fresh source replacement with a newer generation and inspected root revision,
without `historical_import`, followed by its required projections. Do not treat
reindexing an imported record as promotion to current evidence.
Suppression cannot erase journals, backups, prior transfers or independent stores.

An explicitly aborted draft also invalidates delayed publication. `Store.abort`
requires the inspected root revision and exact draft ID for source, fact or vector
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

The selected `mcp_cas` profile fixes its contract. `ipse-cas-v2` uses inner envelope
version 2; the surrounding `mcp.call` and result-window transport remain version 1.
Every action echoes contract, version, partition, action and fresh request ID.
Read `MCPCAS.envelope/4` and its write-size preflight together so a batch cannot
be sized under a different contract from the one dispatched.

V2 `cas_root` arguments contain exactly `key`, `expected_revision`,
`expected_generation`, `expected_source_generation`, `expected_content_sha256`,
`draft_id` and `next_root`. Creation requires a non-null safe generation.
Replacement uses null for that condition. The server checks the target revision,
optional store generation and existing source/hash/draft conditions under one
atomic owner. A missing-root request without its generation condition refuses
before mutation. Permanent suppression still refuses replacement.
The v2 owner also refuses a positive-revision tombstone at a root key; it is
neither an available creation slot nor an existing source to replace.

Successful conditioned CAS returns the exact next root at the next target
revision and store generation `G+1`. A v2 conflict carries only a closed record
summary with `key`, `revision`, `deleted`, `source_generation`, `content_sha256`
and `draft_id`. The envelope carries current store generation. A missing record
uses revision zero, deleted true and null source fields. A suppression has its
positive source generation and null hash/draft. A live root reports its hash and
nullable draft ID. The client requires at least one requested CAS condition to
differ; a matching summary cannot claim conflict. No source body is disclosed.
All v2 positive record receipts and conflict summaries require target revision
no greater than store generation, including snapshot metadata and full reads,
immutable writes and collection. A nullable replacement condition does not
permit an intrinsically impossible successful receipt. Collection also requires
the requested snapshot generation plus one, since its atomic owner checks that
condition and advances generation exactly once.
Revision-zero full records must have the canonical missing form, deleted true
with a null value. A revision-zero object cannot claim to be a stored live root.

V1 profiles retain their version-1 wire format for reads and existing-root
updates. New-root creation refuses locally with `atomic_admission_unavailable`,
before dispatching CAS. Operators explicitly select a compatible v2 service and
configuration; the client never falls back or upgrades a profile. Both contracts
read the same persisted root/page format. Drain old v1 writers before relying on
the new admission guarantee.

Follow `test/support/knowledge_mcp_fixture.exs` into its independent atomic owner.
It implements both contracts and supplies the public MCP exercises. Exact
receipts establish what the selected server asserted. They do not verify a real
server's internal transactions or enforce its partition ACL.

Full MCP snapshots use one directory call and at most eleven groups of eight
record reads. At 89 retained records the adapter returns `remote_snapshot_limit`
before Store sees the partition, so even addressed inspect/export/maintenance
cannot proceed. This bound precedes `root_capacity_exceeded`. The Store control
seeds 33 roots and 56 tombstones to check that refusal, then removes one
tombstone to verify the 88-record boundary still permits addressed reads while
the whole snapshot refuses the root count. Recovery beyond that ceiling needs
the selected server's administrative export/migration procedure. Do not widen
the 16-effect allowance or promise that ordinary Ipse exports can bypass it.
Corpus's selected remote-query route reads only bounded returned references; it
does not count all roots or assert a whole-partition snapshot.

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

The optional third argument selects the lifecycle cases. Omitting it preserves
the earlier eight-check Graph abort exercise. Both installed routes hide the
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
mix test test/knowledge_evidence_test.exs test/knowledge_profiles_test.exs
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
