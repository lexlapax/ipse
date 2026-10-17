# Optional memory, research, graph and RAG extensions

These are proposed shipped capabilities, **all disabled by default**, with no
production engine or backend selected. P14 already supplies a research skill,
configured MCP retrieval and a durable evidence ledger. P22's
[synthetic installed memory/workflow lab](extension-proof.md) proves exercised SDK
seams, including prompt-driven graph capture and explicit catch-up. Those are
foundations, not production memory, graph, RAG or a pluggable research engine.

The [revised plan](../plan.md#p25-comparative-research-and-supervised-self-development)
proposes P25 as independent Codex/Ipse research, comparison and supervised harness
improvement. This guide owns the domain questions and selection requirements;
the [evaluation protocol](self-hosting-evaluation.md) owns the experiment.
Production packages are deferred to proposed P26 memory and P27 research/graph/RAG,
subject to the research outcome. The earlier implementation authorization does
not override the operator's 2026-10-17 request to reconsider that scope. P23 reports
are available; atomic budgets and accounted extension model requests remain open.

## Research before implementation selection

The operator selected **Zero-Mem as inspiration**, not an adoption decision. The
[paper](https://arxiv.org/html/2607.29377v1) preserves interaction evidence and
combines relational and temporal access with deterministic retrieval/calibration,
without intermediate LLM memory-operation calls; it accounts for encoder work
separately. Evaluate that method against a simple scoped lexical/raw-turn baseline.
Do not equate no maintenance LLM calls with free embeddings, storage, computation
or final-answer tokens. Report local measurements, not the paper's benchmark
claims as Ipse results.

The [paper-linked repository](https://github.com/Zero-Mem/Zero-mem) and independent
[Rust zeromem implementation](https://github.com/ptaranat/zeromem) are distinct
research targets. The latter documents a tool-driven MCP interface plus ingestion
hooks, and warns about current-session recall and deletion resurrection while a
session keeps writing. Those are useful scope/deletion test cases, not proof of
Ipse interoperability or reasons to copy its cross-project defaults. No package
is installed or code copied. Pin the actual sources, inspect current implementation,
runtime dependencies and licenses before any reuse; keep Ipse's own logic in Elixir.

Every candidate needs a research/decision record before implementation selection.
P25's two tracks produce these records independently:

1. Primary papers/docs/source, exact revisions, maintenance/maturity, licensing,
   dependencies and reproducibility. Distinguish authors' code, independent
   implementations, measured behavior and marketing/benchmark claims.
2. A minimal baseline and alternatives, with matched context/model budgets and
   workloads: recall precision/coverage, temporal updates, contradictory evidence,
   multi-hop questions, supported citations, deletion and cross-scope leakage.
   Measure model/encoder/API usage, latency, memory/disk and operational costs.
3. Lifecycle need and implementation form: inert skill, ordinary tool/MCP server,
   host extension, external backend or truly missing generic host capability.
   Reuse existing P14/SDK surfaces; do not create a hook or service merely to call
   one retrieval function. Document rejected alternatives and remaining gaps.
4. A bounded synthetic evaluation/prototype design and failure/concurrency/recovery
   cases, then opt-in live evaluation when necessary. P25 delivers the design and
   evidence-backed decisions; backend prototypes/installations belong to a
   separately selected P26/P27 increment unless explicitly added to the trial.
   Require scoped data/retention and no hidden model calls. Research completion
   alone does not authorize installation or mark a production feature implemented.

## Tool, skill, extension or core

These mechanisms compose; an extension can register tools, but a useful tool
does not require lifecycle callbacks. Packaging and executable enablement remain
separate from an operation's approval.

| Requirement | Prefer initially | Add a hook/host capability only when needed |
| --- | --- | --- |
| Explicit recall/remember/forget/export | Ordinary scoped tool; existing MCP if an external store fits | Context hook for operator-enabled automatic recall; approved write policy for deliberate automatic capture |
| Research on operator request | Existing research skill plus search/fetch/evidence tools | Workflow extension for bounded resumable orchestration, job/progress and provider composition |
| Graph traversal/query | Retrieval tool over a selected store | Context contribution if automatic graph recall is required |
| RAG query over an existing corpus | Retrieval/rerank tool with source IDs | Context hook for automatic augmentation; owned approved ingestion/index jobs for corpus updates |
| Session scratch/task notes | Bounded tool/state service | Admission/context/settlement hooks only for configured automatic policies |
| Approval, journal integrity, scopes, owned cancellation and resource limits | Existing generic core | Reviewed/versioned core enhancement only if a required invariant is missing |

Start tool-first when explicit invocation meets the use case. A selected capability
may ship as a tool pack/skill and optional small lifecycle adapter, without a new
framework or mandatory daemon. Final packaging decisions follow the research gates.

## Package and hook map

IDs below are illustrative; rows are candidate capabilities, not fixed choices
to implement each one as a host extension. Hooks run only for enabled instances and
within their declared capability/scope/budget; a hook notification never grants
permission to write memory, fetch a URL or call a model.

| Extension | Proposed behavior and hooks | Configurable dependencies |
| --- | --- | --- |
| Short-term working memory | Session/task scratch facts and decisions; context contribution at model-context assembly; explicit remember/update/forget commands or proposed post-turn updates. | Session-scoped bounded state, optional approved extraction profile; no long-term store required. |
| Long-term memory | Cross-session scoped recall; explicit remember/forget/export; bounded context recall plus approved durable mutations. | Store adapter, operator/project namespace, retention/TTL, retrieval policy and optional extraction profile. |
| Research engine | Clarify/plan, query decomposition, search/fetch, evidence comparison and cited synthesis; explicit research command/tool and bounded before-settlement workflow actions. | Pluggable named search/fetch/retrieval/rerank providers and explicit model profiles; memory optional. |
| Graph memory | Entity/relation storage and traversal over attributable memory/source records; approved indexing mutations and optional graph-recall contribution. | Compatible graph-store adapter, extraction profile, relation schema and traversal budget; no mandatory graph service. |
| RAG | Approved corpus ingestion/chunk/index jobs; retrieval/rerank and cited context contributions for a task. | Keyword/vector/hybrid/graph retriever, corpus/store, optional embedding and reranker profiles; persistent conversational memory optional. |

Each package may ship metadata/code with Ipse, yet disabled instances must create
no store, worker, indexing job, endpoint connection or model call. Graph and RAG
are not automatically enabled by enabling memory; research does not silently
install either. Missing required providers produce an actionable configuration
error. Operator-declared alternatives may be selected explicitly; no silent
service/provider/billing fallback.

Core conversation ownership, required user intent, validated compaction/native
continuation, questions, approvals and recovery journals remain mandatory host
features. Disabling short-term memory disables optional scratch/recall policy,
not the conversation or crash recovery. Conversely, RAG over an explicitly chosen
document corpus does not authorize permanent personal-memory creation.

## Lessons from other frameworks

[LangGraph memory](https://docs.langchain.com/oss/python/concepts/memory)
distinguishes thread-scoped state/checkpoints from cross-thread namespaced stores.
Ipse should keep optional working/long-term memory scopes explicit while retaining
its existing core recovery contract. This is a design lesson, not a recommendation
to adopt a graph runtime.

[LlamaIndex property graphs](https://developers.llamaindex.ai/python/framework/module_guides/indexing/lpg_index_guide/)
compose graph retrievers, including vector retrieval that expands into connected
paths, and distinguish graph-store/vector-store capabilities. This supports a
separate graph adapter and composable retrieval contract, rather than making all
memory a graph or requiring two databases.

[Haystack retrievers](https://docs.haystack.deepset.ai/docs/retrievers)
separate retriever strategies and document stores; dense retrieval needs embedding
components while keyword and hybrid methods have different requirements. Ipse's
RAG extension should accept capability-declared retrieval adapters and allow a
local keyword baseline without a mandatory embedding service. No Python/JavaScript
framework, vector engine or database is adopted by this research.

## P22 foundation and remaining gaps

Knowledge features use generic host contracts; they do not get a special branch
in Session. Separate implemented primitives from the remaining automatic-policy
seams before choosing a production memory, graph or retrieval engine:

| Responsibility | Implemented foundation | Remaining contract/proof |
| --- | --- | --- |
| Composition | Operator-bound typed value services, pinned dependencies, acyclic routing and installed synthetic lookup proof | Production retrievers; nested effectful services remain a negotiated enhancement |
| Evidence/context | Bounded attributed publications, receipt-backed awaited recall and frozen snapshots, exercised by the installed lab | Domain records mapped to P14 source/claim identity and production retrieval quality |
| State/deletion | Scoped CAS records, locks/tombstones and installed rejection of delayed prompt writes after concurrent forget | Domain TTL, complete derivative deletion/export policy and production concurrency coverage |
| Owned work | Explicit invocations, prompt/answer jobs, fixed-range history, cancellation, receipts/questions and installed domain deduplication/catch-up | Production ingestion/reindex policy; fully concurrent effectful jobs remain a negotiated enhancement |
| Event source/views | Stable journal references, scoped history, prompt/answer delivery and selected live metadata/private-tool feeds, with separate ephemeral text sources | Unsupported view families and causal links listed in the lifecycle audit; cross-session history authorization |
| Optional model work | Existing explicit provider/profile and delegation paths | A negotiated accounted host request capability for extraction/embedding; current callbacks cannot silently call a model |

The [lifecycle event design](lifecycle-events.md) makes prompt-driven graph
ingestion a P22 acceptance scenario. Hooks subscribe to shared boundaries, but
metadata notification, private content delivery, ordered recall and effectful
jobs have distinct contracts. A graph can subscribe to a selected original or
effective prompt view, or a separately authorized completed-answer view, extract
entities deterministically in an owned worker and
propose approved scoped writes. Acknowledgment alone grants no storage or model
authority. Background indexing cannot change an admitted request; same-turn
recall must be awaited and committed before inference. Resume restores committed
snapshots without retrieving or writing again.

Retrieved chunks and memory records need stable identity, namespace/scope,
source/version/digest, timestamps, excerpt/reference and provenance. Optional
scores indicate ranking, not truth. Keep entities/index IDs linked to original
evidence, and extension content below the instruction/permission boundary.
Record source event and extractor version; reject stale writes after forget so
queued extraction/reindex cannot resurrect deleted facts. Deleting a derived
store does not erase journals, backups or prior remote/provider transfers.

Typed options select store/search/fetch/embedding/rerank/graph instances and
profiles; no backend or endpoint is mandatory. Project selections may narrow
operator grants, not authorize egress or widen memory access. Unsupported
operations refuse instead of hiding unaccounted work inside a hook. Use the
independent [installed-package evidence](extension-proof.md) to assess the exercised
contracts alongside the [lifecycle audit](lifecycle-events.md#supported-lifecycle-coverage)
and supervised trial; its P22 hosted checks passed. Production graph queries,
embeddings, database installation and research-engine implementation/measurements
are deferred to P26/P27. P25 evaluates the research and improves the harness used
to do it; it need not implement these engines.

## Research handoff and deferred production acceptance

P25 should deliver source-backed decisions for each family, rejected alternatives,
a baseline and quality/resource evaluation design, dependency/license findings,
an explicit tool/skill/MCP/extension/core map and an implementable P26/P27 proposal.
Compare both tracks against the same requirements and inspected evidence; record
remaining uncertainty and material operator choices. Codex's preferred design is
not automatically correct. No package install, graph store or embedding service is
needed merely to produce this research handoff.

For later implementation, treat the capabilities as independent packages with
shared contracts. Proposed P26 delivers working/long-term memory; proposed P27
delivers research, graph and RAG increments in the order supported by P25. Their
selection can change after the study. These packages have no intrinsic voice or
cost-UI dependency, but required host accounting/admission and other SDK gaps must
be closed before the operations that need them. Request input for material
unresolved choices or actions/dependencies that require approval.

Ship a minimal configurable local baseline and explicit provider interfaces, with
no default remote store, embeddings, search service or model. Evaluate existing
OTP/files and maintained Elixir/Rust packages before selecting store/index/graph
implementations, and record all dependencies/licenses/approvals. Use ordinary
Elixir modules/processes; research orchestration need not become a workflow engine.

Memory fixtures cover scope/TTL/conflict handling, approved writes, no automatic
promotion, concurrent locking, deletion and unchanged resumed recall. Graph/RAG
fixtures cover source/chunk/version identity, stale index refusal or explicit
rebuild, traversal/top-k/byte budgets, lexical operation without embeddings,
deletion propagation and accurate citation mapping. Research fixtures cover
configured provider selection, cancellation/time/request limits, conflicting or
weak evidence, partial failures, stale sources, uncertainty and source-supported
synthesis. Never replace unknown effects or missing evidence with a successful
status. Model-quality benchmarks are separate from deterministic protocol tests.

For every package prove default-off parity and empty side effects, no unauthorized
cross-project retrieval, no hidden model/billing switch, bounded jobs/contexts,
tracing/cost integration and no effect replay on resume. Include credential-free
source/extracted-package fixtures and opt-in live provider checks separately.
Review operator/developer setup/retention/recovery guidance and dependency inventory,
check links, then commit/push each completed package. The P22 extension-only gate
still requires no core/native edits for a conforming feature; truly missing host
capabilities require a separately reviewed versioned enhancement.
