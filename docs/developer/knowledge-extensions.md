# Build source-bound knowledge behavior

Follow a retained source into a current citation, then change retrieval without
bypassing source identity, approved inference, or recovery. Corpus, Graph, and
Research are independent worker packages. The native Knowledge capture package
uses the protected collection SDK. These workers use the public SDK; they do not
load domain code into the host or open their own files/sockets/executables.
Start with the [operator procedures](../operator/corpus.md) and
[artifact builder](../../extensions/knowledge/README.md).

## Find the owners and compiled authority

| Source under `extensions/knowledge/src/` | Responsibility |
| --- | --- |
| `knowledge.ex`, `knowledge/records.ex`, `notes.ex` | Protected capture continuation, stable evidence and note retention |
| `knowledge/contracts.ex` | Inert operator-sidecar publication schemas and managed recipes; no authority or executable setup |
| `corpus.ex` | Source/query/index commands and final revalidation |
| `graph.ex`, `research.ex` | Attributed extraction/traversal and captured-source investigations |
| `profiles.ex` | Closed named algorithms and preset compatibility |
| `store.ex`, `store/` | Root/page transactions and State/MCP adapters |
| `evidence.ex` | Safe identities, chunks/citations, ranking/fusion/facts/traversal |
| `adapters.ex` | Complete selected retrieval/embedding/text-helper interactions |
| `documents.ex`, `documents/` | Bounded extraction of acquired bytes, DOCX package checks, and optional protected PDF parser staging |

Entrypoints implement SDK callbacks directly. A compiled preset fixes capabilities;
options cannot promote lexical State code into semantic or MCP authority. All
Knowledge presets declare SDK 2 and complete-result permission. Builder/generator
check exact declarations before grants. Import, trust, and activation remain separate.
Corpus uses store/retrieval/embedding/rerank families; Graph uses stores/extraction,
with empty retrieval registry; Research uses search/fetch/BM25/optional rerank.
Reject unused/incompatible profiles before generating permissions. A syntactically
valid dense/graph/hybrid/remote-query profile is still invalid for Research.

## Follow protected capture from a Session source

The `knowledge/native` preset exports `capture` as a tool and command. It accepts
one text/category/reason/event-time tuple and an exact quote with an opaque Session
source handle. All seven profile registries must be empty. This path uses the
selected main model's tool calls; it performs no secondary inference.

Follow `Knowledge.handle/3` through source read, exact quote, public SDK proof,
saved lineage override, existing-record lookup and explicit managed collection commit. The host
reconstructs the proof independently at publication and checks the current
protected permission. The artifact declares `host.collection.managed` separately
from read access and carries the exact sidecar recipe digest. Its original commit
explicitly advances the import floor. Read/write grants do not imply this capability.
A worker's origin label or JSON proof grants no permission.
The [collection SDK](collection-sdk.md) owns that admission boundary.

`Knowledge.Records.capture/4` constructs a note only when its text equals the
entire quoted span and the origin is native operator input, a native answer, or
a literal typed tool outcome. Typed outcomes cannot become preferences. Other
claims become attributed pending proposals, including an expanded interpretation
of a short operator answer. Exact support still proves no entailment or truth.
Ordinary notes expire after 90 days; current/preference notes retain their category.
Pins require a separate explicit operator workflow.

Lineage derives from source identity and span, independently of a model's text
or category. The pure Records retention model can apply a saved session-only
override to every classification and paraphrase of that evidence; it cannot renew
an anchored expired override. The current managed host refuses legacy override
adoption until a typed operator workflow supplies that authority. An existing
public record returns its revision without replacement or TTL
renewal. New proposals have a seven-day deadline and a retained queue ceiling of
64 records/256 KiB. The capture path counts retained proposals, including expired
ones; it neither silently deletes them nor renews them to make room.

Saved override values wrap the pure retention policy with separate native operator
evidence under `evidence.sources`, so they can satisfy constrained publication.
`Records.saved_override/2` checks the complete wrapper and matching lineage before
applying it. Bare policies, foreign lineages and weak-origin wrappers refuse.
This format check does not establish operator acceptance; that remains the trusted
management workflow's responsibility.

The native builder also declares `operator.json` in the artifact's hashed file
inventory. `Knowledge.Contracts.operator/0` supplies closed structural constraints
for notes, pending proposals and each of the four retention choices, plus reviewed
literal/proposal recipe data referencing the exact constraint digests. The builder
uses the public `Ipse.Extension.canonical_digest/1` helper rather than a private
host encoder. A capture
schema excludes pin/history categories. Separate retention schemas prevent an
ordinary choice from carrying a duration or silently becoming a pin. These use
the existing supported JSON Schema subset and introduce no schema evaluator.
They do not authenticate origin or establish operator acceptance. The managed
publication adapter authenticates the source and the host Normalizer independently
checks lineage, category and source clocks under the Collection lock. Its version-2
packed anchor/live pages preserve deadlines after public-record pruning and reject
experimental version-1 metadata. Managed recall must still apply these witnesses
at every dispatch before standalone activation is ready.

An operator adapter can inspect this data with
`Artifact.read_declared(store, digest, "operator.json", 65_536)`. This revalidates
the installed artifact and then rechecks the selected file's declared size and
digest. It loads no extension code and grants no permission. The sidecar is data
from a selected artifact, not an instruction to execute code or enable a feature.

To trace the actual boundary, run:

```sh
mix test test/extensions/knowledge/knowledge_records_test.exs
mix test test/extensions/knowledge/knowledge_contracts_test.exs
mix test test/extensions/knowledge/knowledge_capture_test.exs
mix test test/extensions/knowledge/knowledge_session_test.exs
```

The first two exercise pure records and declarative contracts with synthetic
proof inputs. The third checks worker continuations in a separate VM. The fourth
builds/imports a separate SDK artifact, runs a synthetic main
model through native `source_list` and capture, checks an actual protected pending
publication and accounting, then validates saved context. It requires the reviewed
native allocation profile. It performs no real model calls. Conflict, denied and
unknown outcomes terminate rather than automatically retrying a mutation.

This capture component does not provide standalone setup, proposal acceptance,
automatic turn hooks, managed recall, correction or collection of expired data.
Keep it in developer integration until those workflows and their qualification
are complete. The explicit Memory procedures retain their existing scope.

## Verify independent selection before algorithm work

From a built checkout:

```sh
IPSE_SELECTION_ARTIFACTS=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/corpus" --package corpus --preset state-lexical
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/graph" --package graph --preset state-explicit
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/research" --package research --preset offline
elixir dev/verify.exs source knowledge-independence \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_SELECTION_ARTIFACTS"
```

Expect nine memory/package/scope cases plus catalog refusal, with zero model
requests. [The proof](../../dev/verification/knowledge.exs) pairs session WorkingMemory
and project/operator persistent Memory with each package, in distinct logical
bindings. Disabled/enabled idle/resume counters remain zero for workers, State,
MCP, embedding, and text work. Actual commands provide positive controls.
Same source IDs do not turn notes into retained evidence or vice versa. Forgetting
one store preserves the other's content. Research owns no retained knowledge store.

Inspect actual namespace-relative filenames/hashes: Research+Memory has one State
file; Corpus/Graph+Memory have two. Empty inventory proves no inert-resume claim.
Counters use arity-only OTP trace instrumentation, without arguments/payloads, and
require every target to be instrumented. Confinement needs separate OS evidence.
All three packages plus Memory exceed the existing 16-KiB catalog and must refuse
before Session/worker/store work. Pairwise compatibility grants no larger catalog.
Repeat the same artifacts in installed mode for runtime compatibility, not new quality evidence.

## Trace one source and a revalidated query

Follow Corpus source validation into Store draft claim, immutable content/chunk
writes, and final root CAS. Storage revision advances on every root mutation;
source generation identifies one complete text version. Pages/projections/citations
bind generation and content hash. Source ID alone identifies no current bytes.
[Storage training](knowledge-storage.md) owns capacity, CAS, suppression, and migration.

Evidence's safe integers stop at 9007199254740991. Generations are positive;
observation/event/expiry/fact/query times are nonnegative, nullable only when optional.
Commands validate before storage reads where applicable; imports validate captured
fields after destination snapshot and before publication. Remote capture rejects
unsafe timestamps before typed results.

For BM25, Store supplies validated sources/heads/revision tokens/coverage. Evidence
ranks at selected time; Corpus revalidates captured roots immediately before return.
A mismatch conflicts instead of publishing stale success. It cannot revoke output
already returned. `as_of_ms` filters the currently retained generations; it does
not reconstruct a past snapshot. For example, after generation two replaces
generation one with `observed_at_ms: 200`, a query with `as_of_ms: 150` excludes it
without recovering generation one. Completeness covers eligible retained generations,
so this can be a complete abstention. Suppressed, expired/future-source, and
time-excluded-fact diagnostics remain explicit exclusions.
Unpublished source work or failed required components stay coverage gaps: an empty
ranking with a draft is partial, not complete abstention.

Graph/hybrid fusion retains each component's claims/gaps/coverage. A completed rank
calculation cannot certify bounded traversal. Only actual missing-embedding policy
can take explicit lexical fallback; graph/transport/malformed-model failures cannot.
The fallback remains partial. `Evidence.query_scope/4` owns direct/combined consistency.
Use `test/extensions/knowledge/query_completeness_test.exs` to compare matches,
no-match, unpublished drafts, forgotten/expired/future sources, and depth-limited graphs.

## Inspect bounded document extraction

`Documents.extract/3` accepts already acquired bytes and a filename; it neither
opens the source path nor authorizes a fetch. The result binds the original binary
hash, an extraction recipe, and bounded text segments with format-specific
locators. Text and Markdown use byte-exact line offsets. The DOCX reader checks
package authority, bounds ZIP expansion and XML parsing, includes insertions, and
excludes deletions and supported hidden runs. Unsupported content stays partial
or refuses rather than claiming complete coverage.

DOCX relationship targets are never fetched. A checked external relationship,
an unexamined internal relationship, or an unexamined relationship part marks
the result partial. Relationship warnings do not repeat targets or arbitrary
unexamined relationship-part names. Malformed target modes and scheme or network-path targets
without explicit external mode refuse. A normal document with relationships the
reader does not interpret can therefore be partial even when its visible body is
readable; inspect the result and original document before using it as evidence.

Recipes are format-specific: `Documents.version("docx")` is
`ipse-documents-v3`, while text, Markdown and PDF use `ipse-documents-v2`.
The legacy `version/0` returns the v2 value; use `version/1` when binding an
extraction to a source version. A prior DOCX v2 result is not automatically
migrated or equivalent. Future indexing must explicitly rebuild or requalify it.
The optional PDF backend requires a separately host-admitted protected parser;
its installation does not activate PDF acquisition. The
[parser contract](../../native/ipse-pdf/README.md) describes its lifetime and
limits. These extraction modules do not by themselves provide an operator file
ingestion workflow, current-source authorization or qualified retrieval.

Exercise synthetic DOCX relationships, bounded XML and Unicode extraction from
the repository root:

```sh
ERL_FLAGS='+S 2:2' elixir -e 'ExUnit.start(seed: 20270116); Code.require_file("test/extensions/knowledge/documents_test.exs"); Code.require_file("test/extensions/knowledge/documents_fidelity_test.exs")'
```

Expect 23 tests to pass; one opens a loopback listener to verify that an external
relationship is not fetched. These fixture controls do not establish real Word
fidelity, PDF quality, migration or end-to-end document retrieval.

## Keep source bytes distinct from semantic support

Raw SHA-256 identifies text/vector bytes; ordered tagged JSON arrays identify domain
objects. Use Elixir `JSON.encode!/decode!`, not raw Erlang encoding: binary sizing
and `nil`→null semantics matter to persisted IDs. Sources allow 64 KiB UTF-8,
with up to 32 contiguous 2048-byte chunks. Citations bind generation/content/chunk,
absolute byte range, literal quote/hash, URI, times, and origin. Quote bounds are
1024 UTF-8 bytes. None proves entailment, authenticity, or freshness.

BM25 uses k1=1.2 and b=0.75. Token offsets retain original half-open byte ranges
through normalization, including case mappings that produce multiple normalized
terms. Never apply downcased-string offsets to original bytes. The Unicode fixture
places a match after byte 1024 and checks the actual quote.

The shared excerpt selector preserves an entire short chunk. For a longer one,
it finds maximum distinct query-term coverage within 1024 bytes, shortest matching
core, then earliest original start/end. Terms from the same original token retain
one span. Whole original tokens longer than the bound still score, without counting
as complete-token coverage.

Mechanical text units end at LF or ASCII sentence punctuation followed by whitespace/
EOF, retaining trailing whitespace. Decimal punctuation stays within a unit while
abbreviations can split. A fitting whole-unit hull keeps its earliest fitting
preceding unit, then following units; preceding context wins. If too long, center
a codepoint-safe contiguous window around the core, transferring space at chunk
edges. No-match falls back to whole-unit or codepoint-safe prefix. Never concatenate
disjoint text, normalize quotes, or cross chunks. Citation reconstruction validates
that selection independently.

For `migration` in `Ada owns the migration. It proceeds only after audit.`, both
short sentences remain. Distant qualifications can still fall outside a chunk or
byte bound. Source citation integrity is not semantic completeness. Tests include
complete short chunks, omitted context, exhaustive windows, and encoded Answer
packing. Six 480-byte passages can fit where only three of six 900-byte passages
fit; escaping can reduce that number. Do not shorten away conditions to pack more.

## Retain compatible and conflicting attributed facts

Facts keep every support citation and extraction identity. Traverse positive edges
only. Before classification, claim context retains negative assertions on reached
subjects, including the seed, plus explicit opposites of selected positive facts.
A negative object's name does not become a traversal node. Conflict means same
case-insensitive subject/predicate/object with opposite polarity. `Release requires
quiescence` and `Release requires tests` are compatible: arbitrary predicates do
not imply single-valued relationships. Preserve original fields/IDs/quote bytes.
An unvisited compatible edge can still leave traversal partial.

Validate all input provenance before applying time exclusions, including facts not
reached later. Expired valid facts can be excluded; missing/replaced provenance
remains stale even when expired, and forged spans still refuse. Whole query input
is conservatively bounded at 8192 facts from retained-record/manifests limits,
with encoded snapshot constraints. One source/profile has a sole valid head;
predecessors retain profile and cannot repeat keys. Per-head facts allow 256 and
per-extraction 32. Complete claim context separately permits 256. Overflow returns
`graph_context_limit` before classification, without truncated claims.

Seed selection validates facts at as-of time, then matches complete Unicode entity
names, longest subject first with stable spelling ties. `Lease` does not match
inside `Release`. No subject match uses the query itself. Coverage records seed,
traversed edges, context/negative/counterassertion counts. At depth exhaustion,
unselected positive outgoing frontier edges make coverage partial; leaves, empty
frontiers, and fully consumed cycles can be complete.

Top-k bounds returned evidence, not each attributed claim's complete citation basis.
Claims retain support outside the rank. Without assessed facts, classification stays
open with `semantic_support_unassessed`. Publication uses zero-based evidence indexes
only when every internal basis citation appears in final evidence; otherwise retain
full basis. Fusion/truncation must create no dangling or lost provenance. Run
Evidence, graph-population, completeness, and complete-publication controls before
changing either bound.

## Fuse chunks while retaining exact citations

The reference configuration combines lexical and native dense retrieval, with
`rrf_k: 60`, `top_k: 10`, no graph component and no reranker. Build `state-dense`
with an empty `rerank` registry and select its hybrid route. The optional
`state-semantic` preset additionally grants `host.model` for reranking and was
not the measured reference artifact. The [operator example](../operator/corpus.md#add-explicit-embeddings-and-reranking)
names that route `blend`. The [comparison record](../archive/2026-10-23-p27-heldout-comparison/index.md)
explains the selection and its limits. Keep this choice in package configuration;
it requires no domain branch in Session or automatic provider selection.

Rerank/span IDs and fusion identity serve different purposes. `Evidence.fuse/3`
uses reciprocal rank with constant 60 over namespace/source-key/generation/content/
chunk identity. Each component contributes once per chunk despite multiple spans.
A lexical-first/dense-first chunk receives 1/61+1/61 and one final slot. Best
component rank selects its representative citation; earlier component wins ties.
Corpus orders lexical, dense, graph. Preserve every graph claim's original basis,
even outside the representative/top-k. Do not change persisted chunk/span IDs merely
to combine scores. Coverage remains the combination of actual component coverage.

Rerank input assigns deterministic e1..e16 IDs with canonical chunk:byte-start:byte-end
references and quote prefixes up to 128 bytes. A model returns one order object
naming every ID exactly once. Missing/duplicate/foreign IDs, extra fields, or bare
arrays refuse without fallback/repair. Accepted order maps to canonical candidate
IDs. The immutable continuation/host request binds identity, without another nonce.
Evaluation independently parses references, exact chunk/range/prefix, and ID order
without loading production domain code into the host.

## Preflight projections before inference

Store first claims a source-bound projection draft with token and capacity plan.
Entrypoints check remaining read/effect allowance before calls, then return validated
results through that token. Store owns packing and final publication. Explicit
fact batches pack actual JSON before claim, up to 32 facts; count is not reservation
for 32 worst-case records. Model extraction derives affordable allowance before
egress. Output exceeding it leaves a draft for inspection/exact abort. Eight heads
per source allow updates to an existing kind/profile at capacity, while a ninth
refuses before draft/model work.

Extraction/rerank profiles can select `output_contract: "json_schema_v2"`; omission
retains v1 text. Recipe version and output contract differ. Structured helpers
use task-specific schema, native Ollama, 12-KiB request within unchanged SDK bounds;
v1 retains 8 KiB. Encoded task input separately permits 4096 bytes. No source/input
is shortened to fit or rerouted to another provider. See
[accounted effects](extension-effects.md#request-bounded-text-inference).

Extraction supplies max-facts plus c1/c2 local chunk IDs. Facts contain exactly
subject/predicate/object/polarity/chunk/quote. Negative means explicit denial,
not absent evidence. The model copies a unique literal quote, without generating
hashes/offsets. Count overlapping matches inside that selected chunk; absence,
ambiguity, whitespace/Unicode normalization, wrong chunk, duplicate keys, or any
invalid proposal refuses the whole response. Derive absolute byte spans and validate
them. Store revalidates chunks/live draft at commit. Do not apply query-time expiry
during publication and silently discard future/past validity intervals.

For a chunk at byte 2048 containing `Éclair does not require β.`, this proposal
preserves both multibyte characters and derives the absolute range:

```json
{"facts":[{"subject":"Éclair","predicate":"requires","object":"β","polarity":"negative","chunk":"c1","quote":"Éclair does not require β."}]}
```

If the quote appears twice in that chunk, refuse; another selected chunk containing
the same quote does not make this one ambiguous. Follow package controls for
future-valid, expired, future-observed, and wrong-generation attribution.

## Authenticate embeddings and their complete vectors

Embedding.create v2 returns `selection_sha256` authenticated by the host's approved
profile binding. Adapters retain it in Evidence v2 vectors. Compatibility requires
valid current vectors with equal selection hash, host profile, reported model,
width, and encoding. Legacy v1 vectors remain readable but never compare densely.
Changed/legacy selection yields missing-embedding refusal or explicitly partial fallback.

Validate entire projection-chain homogeneity before deduplicating chunk IDs: a newer
duplicate cannot hide an incompatible older row. Compatible batches append. Explicit
reindex with a changed selection/model or legacy vector replaces that head's chain
with `previous: null`, preserving other heads, source, facts, and suppression. Detached pages
need explicit collection. New drafts/tokens/plans bind vector_version2. Older drafts
remain inspectable/exactly abortable, without promotion or a fresh next step while active.

Bind result indices to approved inputs and stable opaque host hashes across pages.
Raw local hashes alone authenticate no returned vector. Check descriptor identity,
offsets/dimensions, canonical Base64, float32 encoding, and full vector digest.
All finite float32 values including signed maxima are valid; NaN/infinity refuse.
Do not shorten vectors. Two 4096-wide vectors require 12 coordinate pages, manifest,
final CAS, claim, and embedding call: 16 effects. State admits one/two selected chunks;
MCP admits exactly one and counts reads as effects. Check complete capacity before
dispatch; metadata-heavy facts can need smaller batches.

The selection proof uses two loopback services with equal names/width but different
vectors. Query at B must refuse vectors indexed at A; explicit fallback stays partial.
Reindex at B restores eligibility. Timeout-only changes permit reuse, but a changed
reported model requires reindex. These controlled vectors prove identity separation,
not weights or retrieval quality.

## Publish and materialize the complete domain value

Store/Adapters use private done/call/stop continuations. Entrypoints turn only exact
host calls into SDK proposals and resume the same owner. Initialize every private
map key before update. Unknown effects terminate, without empty success or retry.
Each finish passes the whole public object to `ResultPublication.prepare/1`.
Invalid aggregates become explicit `result_too_large`; quotes/bases are not dropped
to align with 4096-byte transport fragments.

[Invocation training](extension-invocations.md) owns terminal output/leases/closure.
Only committed final receipt makes saved output readable. Consumers materialize the
exact delivery before interpreting status/evidence/claims/coverage; failed reads
are retained errors, not empty rankings, fallback, or repeated queries.

```sh
elixir dev/verify.exs source knowledge-complete \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_SELECTION_ARTIFACTS"
```

The [five-check proof](../../dev/verification/knowledge_complete.exs) preserves ten
full quotes, escaped citations larger than fragments, graph bases beyond top-k,
opposite assertions, hashes, inert restart, no host-loaded domain modules, and zero
model calls. Repeat in installed mode with the same artifacts and compatible archive.

## Distinguish independent Research from the native ledger

Independent Research ranks provided sources or selected search/fetch gateway output
with BM25 and optional rerank. Its provided ledger normalizes supplied labels to open
assertions; it creates no native host receipts or retained Corpus. Default as-of
time is selected after capture so completion-stamped fetches are eligible. Explicit
safe integer fixes time; null refuses. Observations after selected time and expiry
at/before it exclude. Coverage retains raw captured bytes. Before each fetch/rerank,
sample remaining allowance once; below 1000 ms refuses, otherwise pass that same value.
An empty fetch queue ranks without requiring allowance for another fetch.
[Storage contracts](knowledge-storage.md) specify exact gateway envelopes.

Native [`Tools.Research`](../../lib/ipse/tools/research.ex) instead captures literal
URLs/excerpts from uniquely identified successful recorded MCP results. It records
result/call hashes and completion-time basis; legacy results retain capture-time
basis. Titles/authors/publication claims stay unverified. A URL and excerpt can
both occur in a multi-page result without belonging together, so inspect the source.
Its ledger lists bounded recent references without repeating retrieval.

Native claims bind unique source IDs. Supported/inference/conflict need a source;
open may have none. Shape/reference validation proves no entailment. Exact repeated
capture is idempotent. Bounds are 16 sources/32 claims/64-KiB ledger, excerpts 4000 bytes,
statements 1000 bytes/eight references, URL 2048 bytes, call ID 256 characters, arguments
16 KiB, and body/header/recovery result 66048 bytes. Bound refusal truncates no evidence.
Children cannot use these tools.

Owned work reads original events outside Session; durable research source/claim
precedes ordinary tool-result publication. A crash between them leaves a durable
entry with uncertain call outcome. Resume/export validates preceding evidence without
capture/retrieval/file replay. `ipse research --resume ID` exports this ledger only,
not Research's provided assertions. Narrative file writes need ordinary approval.

## Practice an algorithm change and prove its scope

Add two development sources with shared terms/different frequency and independently
specify order. Follow BM25 tokenization/ties, then the tests in isolated VMs:

```sh
mix test test/extensions/knowledge/evidence_test.exs test/extensions/knowledge/profiles_test.exs
mix test test/extensions/knowledge/domain_regressions_test.exs test/extensions/knowledge/graph_population_test.exs
mix test test/extensions/knowledge/packages_test.exs test/extensions/knowledge/query_completeness_test.exs
mix test test/extensions/knowledge/build_spec_test.exs
mix test test/ipse/tools/research_test.exs test/ipse/tools/research_integration_test.exs
```

Build fresh artifacts and run source/installed `knowledge` and `knowledge-complete`
with exact spans/generations/revalidation/no model calls. Storage lifecycle races
have a separate [worked exercise](knowledge-storage.md). Research MCP has its own
`knowledge-research` scenario and reviewed artifact. Protocol controls do not qualify
semantic answers. Follow [evaluation](knowledge-evaluation.md) for held-out predictions,
independent citation judgments, resource measurements, and strategy selection.
