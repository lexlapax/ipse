# Optional memory, research, graph and RAG extensions

Operator-requested planning on 2026-10-16. These are proposed shipped extensions,
**all disabled by default**, not new implementations or services. P14 already
provides a research skill, configured MCP retrieval and a durable evidence ledger;
P22's synthetic memory/workflow example will prove SDK coverage. Neither is a
production memory, graph, RAG or pluggable research engine. Plan delivery as the
independently selectable P25 capability family using P22 foundations. P23 reporting/
budgets can integrate when available; local memory need not wait for voice or cost UI.

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

Every P25 candidate needs a research/decision record before implementation:

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
4. A bounded synthetic prototype and failure/concurrency/recovery tests, then
   opt-in live evaluation when necessary. Require scoped data/retention and no
   hidden model calls. Research completion alone does not authorize installation
   or mark a production feature implemented.

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

## P22 foundational additions

1. **Service composition:** manifests declare namespaced versioned `provides`/
   `requires` capabilities and selected instance aliases, separate from package
   build dependencies. Host-mediated typed service calls validate declared schemas,
   caller scope, budgets, ownership and correlation. No direct worker-to-worker
   PIDs or unbounded callback recursion. Reject unsupported interfaces, missing
   services, circular dependencies and reentrant call chains before dispatch.
   The first proof can use a small local fake retriever; no general service graph
   framework is required.
2. **Common evidence contract:** retrieved chunks/memory records carry stable IDs,
   namespace/scope, source/version/digest, timestamps, excerpt/reference, provenance
   and optional score/uncertainty. Scores are ranking signals, not truth. Context
   contributions name their exact snapshot and fit the host budget; untrusted
   source content never becomes an instruction/permission level. Reuse P14 source/
   claim identity and validation instead of inventing an incompatible citation
   ledger. Keep any internal entities/index IDs mapped to original evidence.
3. **Owned work and effects:** approved store/index writes and network/model
   requests use ordinary host proposals, journals, cancellation and usage facts.
   Slow ingestion/extraction runs as owned bounded jobs outside Session, with
   progress, operation IDs and explicit unknown outcomes. Optional inference uses
   explicit existing profiles/delegation or a negotiated host request capability;
   no hidden model HTTP call or private provider interface. Unsupported operations
   refuse, rather than spawning an unaccounted workflow inside a hook.
4. **Snapshot/state lifecycle:** session scratch, durable memory and derived indexes
   have separate namespaces and retention. Recall is committed before inference;
   resume restores that projection without a new retrieval or automatic write.
   Define stale/conflicting records, export, TTL, tombstones and indexing version
   before storage. Forget/delete propagates to owned graph/vector derivatives,
   with job status and scope; it does not promise erasure from private journals,
   backups or remote services outside the stated deletion operation.
5. **Provider/configuration independence:** typed options select store/search/fetch/
   embedding/rerank/graph instances and profiles. Validate capabilities and runtime
   compatibility without hardcoded endpoints or feature-specific Session branches.
   Project scopes can narrow operator grants; they cannot activate data egress or
   widen memory access. Durable store locking remains cross-process.

These are generic SDK/store/retrieval/job contracts and fixture requirements.
P22 does not need production graph queries, embeddings, a database installer or
full automated research. Exercise composition, provenance and scoped memory through
the coverage gate before freezing core; later adapters implement the feature logic.

## P25 delivery and acceptance

Treat these as independent packages with shared contracts, not one mandatory
pipeline. Deliver short-term/long-term memory first, then the research engine and
RAG adapters as useful; graph storage/traversal remains independently selectable.
This feature-family work can proceed independently of voice or cost UI once its
required P22 capabilities exist. Each implementation choice follows the research
gate above. No implementation goal is started by this plan entry; the operator
requested the plain-English sequence for approval before runtime changes begin.

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
