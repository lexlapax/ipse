# Build cited retrieval and graph behavior

Follow a retained source into a current citation, then change retrieval without
bypassing source identity, approved inference, or recovery. Corpus, Graph, and
Research are independent worker packages. They use the public SDK; they do not
load domain code into the host or open their own files/sockets/executables.
Start with the [operator procedures](../operator/corpus.md) and
[artifact builder](../../extensions/knowledge/README.md).

## Find the owners and compiled authority

| Source under `extensions/knowledge/src/` | Responsibility |
| --- | --- |
| `corpus.ex` | Source/query/index commands and final revalidation |
| `graph.ex`, `research.ex` | Attributed extraction/traversal and captured-source investigations |
| `profiles.ex` | Closed named algorithms and preset compatibility |
| `store.ex`, `store/` | Root/page transactions and State/MCP adapters |
| `evidence.ex` | Safe identities, chunks/citations, ranking/fusion/facts/traversal |
| `adapters.ex` | Complete selected retrieval/embedding/text-helper interactions |

Entrypoints implement SDK callbacks directly. A compiled preset fixes capabilities;
options cannot promote lexical State code into semantic or MCP authority. All
Knowledge presets declare SDK 2 and complete-result permission. Builder/generator
check exact declarations before grants. Import, trust, and activation remain separate.
Corpus uses store/retrieval/embedding/rerank families; Graph uses stores/extraction,
with empty retrieval registry; Research uses search/fetch/BM25/optional rerank.
Reject unused/incompatible profiles before generating permissions. A syntactically
valid dense/graph/hybrid/remote-query profile is still invalid for Research.

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
already returned. Completeness applies to eligible sources at that time. Suppressed,
expired/future-source, and time-excluded-fact diagnostics remain explicit exclusions.
Unpublished source work or failed required components stay coverage gaps: an empty
ranking with a draft is partial, not complete abstention.

Graph/hybrid fusion retains each component's claims/gaps/coverage. A completed rank
calculation cannot certify bounded traversal. Only actual missing-embedding policy
can take explicit lexical fallback; graph/transport/malformed-model failures cannot.
The fallback remains partial. `Evidence.query_scope/4` owns direct/combined consistency.
Use `test/extensions/knowledge/query_completeness_test.exs` to compare matches,
no-match, unpublished drafts, forgotten/expired/future sources, and depth-limited graphs.

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
for32 worst-case records. Model extraction derives affordable allowance before
egress. Output exceeding it leaves a draft for inspection/exact abort. Eight heads
per source allow updates to an existing kind/profile at capacity, while a ninth
refuses before draft/model work.

Extraction/rerank profiles can select `output_contract: "json_schema_v2"`; omission
retains v1 text. Recipe version and output contract differ. Structured helpers
use task-specific schema, native Ollama, 12-KiB request within unchanged SDK bounds;
v1 retains8 KiB. Encoded task input separately permits 4096 bytes. No source/input
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

For a chunk at byte2048 containing `Éclair does not require β.`, this proposal
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
Do not shorten vectors. Two 4096-wide vectors require12 coordinate pages, manifest,
final CAS, claim, and embedding call:16 effects. State admits one/two selected chunks;
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
capture is idempotent. Bounds are16 sources/32 claims/64-KiB ledger, excerpts4000 bytes,
statements1000 bytes/eight references, URL2048 bytes, call ID256 characters, arguments
16 KiB, and body/header/recovery result66048 bytes. Bound refusal truncates no evidence.
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
