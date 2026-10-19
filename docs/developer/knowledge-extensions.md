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
Conflicting assertions remain separate. Lexical results without assessed facts
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
truncation cannot erase provenance or produce a dangling reference. The conversion avoids duplicating
every quotation for the synthetic open claim while preserving source identity.
It does not raise the 12000-byte public result ceiling. Research accepts up to
ten sources, but a legal source count can still produce `result_too_large`.

Run `mix test test/knowledge_packages_test.exs` before changing these bounds.
Its ten-source control checks every returned source and index. The eleventh
source refuses, and ten longer quotations still refuse at the original output
ceiling. The suite runs domain modules in a separate VM.

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
complete bounded text and vectors. Public results remain closed JSON objects of
at most 12,000 encoded bytes.

Unknown effects terminate the chain. They cannot become empty successful search,
a retry or permission to switch profiles. Session owns journaling, approvals,
accounting, cancellation and cleanup. Domain code preserves those outcomes.

## Plan projections before inference

Indexing and extraction first claim a source-bound projection draft. Store
returns selected chunks, an opaque token and a capacity plan. The entrypoint
checks the remaining effect/read allowance before inference and passes validated
results back with that token. Store owns page packing and final publication.

The extraction adapter sends `max_facts` alongside the selected chunks. Its fixed
instruction specifies the closed fact fields and absolute half-open UTF8 byte
offsets. The decoder separately enforces the requested fact count, selected
profile, chunk identity and exact spans. A prompt is not a substitute for those
checks. Follow the valid and over-limit response controls in
`test/knowledge_packages_test.exs` before changing the request or decoder.

The reranker requires a complete candidate-ID permutation inside exactly one
`order` object. A bare array, omitted candidate, duplicate or foreign ID refuses;
none becomes an implicit successful lexical fallback. Its named quote ceiling
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
Base64, float32 encoding and vector SHA256. Never shorten a vector to fit a text
response.

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

Collection removes unreachable bodies while retaining State tombstones. It does
not recover the 256-record allowance. The 1 MiB ceiling includes old generations,
drafts, orphan pages and tombstones. Selected exports are paged. Foreign copies
become historical assertions and need explicit reindexing or extraction.
Suppression cannot erase journals, backups, prior transfers or independent stores.

An explicitly aborted draft also invalidates delayed publication. `Store.abort`
requires the inspected root revision and exact draft ID for source, fact or vector
work. `source_draft_current/1` adds the source-kind restriction for append/publish;
clearing a fact draft cannot turn it into publishable source content. Work through
`test/knowledge_store_test.exs` for State and MCP controls: wrong ID/revision,
source publication against a projection, stale completion, a newer draft and
permanent suppression.

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

The MCP store relies on the server's partition access and atomic CAS. Exact
receipts establish what that selected server asserted. They do not verify its
internal transactions or enforce a remote ACL.

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
