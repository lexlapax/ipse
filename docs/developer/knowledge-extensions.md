# Optional memory, research, graph and RAG extensions

This guide proposes P26/P27 delivery from the P25 research; it does not select or
install a production engine. All optional capabilities remain independently
**disabled by default**. P14 already supplies a research skill,
configured MCP retrieval and a durable evidence ledger. P22's
[synthetic installed memory/workflow lab](extension-proof.md) proves exercised SDK
seams, including prompt-driven graph capture and explicit catch-up. Those are
foundations, not production memory, graph, RAG or a pluggable research engine.

P24's scoped architecture/security readiness gate passed at `375e607`. P25's
live and corrected-packet reports are frozen; its
[execution record](p25-evaluation.md) owns source checks, failed criteria,
supervisor interventions and the authored diagnostic repair. Two fresh reports,
assisted held-out cases and corrected live controls pass; final security review
and acceptance remain open. This guide owns proposed domain decisions;
the [plan](../plan.md#p25-comparative-research-and-supervised-self-development)
owns scheduling and the [protocol](self-hosting-evaluation.md) owns acceptance.
Production memory, research, graph and RAG remain deferred to P26/P27. P23 reports
and shared main/summary/child budgets are available, within their covered operations.
[Accounted one-shot text calls](extension-model-calls.md) now supply the optional
model seam verified in P23F; embeddings and production engines remain separate.

## Research before implementation selection

The operator selected **Zero-Mem as inspiration**, not an adoption decision.
Yilin Xiao and colleagues' 2026
[paper, version 1](https://arxiv.org/abs/2607.29377v1) preserves interaction evidence and
combines relational and temporal access with deterministic retrieval/calibration,
without intermediate LLM memory-operation calls; it accounts for encoder work
separately. Evaluate that method against a simple scoped lexical/raw-turn baseline.
Do not equate no maintenance LLM calls with free embeddings, storage, computation
or final-answer tokens. Report local measurements, not the paper's benchmark
claims as Ipse results.

The [paper-linked repository](https://github.com/Zero-Mem/Zero-mem), pinned at
`8c34fdb…` during P25, is a release placeholder. The independent
[Rust zeromem implementation](https://github.com/ptaranat/zeromem), pinned at
`eda2126…`, describes a clean-room implementation and different encoder/entity
extraction choices. Its workspace declares 0.3.0/MIT; its separate crate manifest
defaults to `fastembed`. The documented first-use encoder download and shared
cross-project store are adoption decisions, not Ipse defaults. Its live-session
forget/resurrection warning is a required test case. A
[third independent implementation](https://github.com/skorotkiewicz/zero-mem)
disclaims benchmark reproduction; route-dependent fallback statements do not
establish universal availability. None is interchangeable with the authors' code.

The [40-entry packet](p25-evidence-packet.json) retains locators, pins, capture
times, excerpt hashes and evidence limits; entries P05/P15/P27/P29/P37/P38 own
these distinctions. A pin proves identity, not benchmark reproduction, semantic
support, current maintenance or complete license clearance. The packet is a
compressed candidate screen, not a substitute for full implementation/dependency
inspection before adoption. No code was copied and no engine was installed.

The researched baseline is explicit bounded task notes and approved project facts,
with deterministic lexical recall. Keep extraction, embeddings and global sharing
optional. Compare this baseline with Zero-Mem-inspired retrieval before adopting
an engine; no intermediate LLM calls does not remove encoder or storage costs.
Alternative framework lessons below inform interface design, not runtime adoption.

Every adoption decision must complete the source screen with:

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

| Capability | Minimal delivery and optional hooks | Alternatives and adoption risks | Required configuration |
| --- | --- | --- | --- |
| Working memory | Explicit bounded task cards in session state; optional awaited context publication and proposed post-turn updates | MemGPT's virtual-context concept (P02); LangGraph's scope distinction below. Letta V1 blocks are legacy, not a current integration contract (P09/P10/P20) | Capacity, lifetime and update policy; optional approved extraction profile; no long-term store |
| Long-term memory | Approved project facts, deterministic lexical recall and explicit remember/forget/selected-note export | Zero-Mem variants; [Mem0](https://github.com/mem0ai/mem0) and [Letta](https://docs.letta.com/concepts/shared-memory/). Managed Mem0 benchmark claims include proprietary optimizations; example API defaults are not Ipse defaults (P22/P23). Letta cloud sharing and local MemFS differ (P08/P21) | Operator/project namespace, store, retention, promotion policy and optional extraction profile |
| Research | Inert research skill plus configured search/fetch and existing source/claim ledger; optional owned orchestration only after host gaps are resolved | [Open Deep Research](https://github.com/langchain-ai/open_deep_research) has multiple model roles; [STORM](https://github.com/stanford-oval/storm) uses DSPy (P19/P31/P35). Neither justifies a mandatory framework or hidden helper inference | Named search/fetch/retrieval/rerank services, profiles, call/time limits; memory remains optional |
| Graph | Explicit attributable entities/edges and bounded deterministic traversal; approved indexing and optional recall | [Graphiti](https://github.com/getzep/graphiti) invalidation retains history (P17); [GraphRAG](https://github.com/microsoft/graphrag) warns about indexing cost (P24); [LightRAG](https://github.com/HKUDS/LightRAG) deletion/recovery needs proof (P12/P13). No deletion guarantee follows from a README | Schema, store, source generations, traversal budget; extraction and graph service separately optional |
| RAG | Selected documents, bounded chunks, lexical retrieval and exact source citations; approved ingestion and optional context publication | SQLite FTS5, pgvector exact search or Qdrant hybrid fusion (P25/P33/P40). An exact-neighbor claim is not semantic answer recall. Ollama/TEI encoders and reranking need truncation/resource policies (P07/P11/P18) | Roots/corpus, chunker, store, top-k/byte limits; embedding/reranker/profile only when selected |

Each package may ship metadata/code with Ipse, yet disabled instances must create
no domain store, worker, indexing job, endpoint connection or model call. Graph and RAG
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
| Composition | Operator-bound typed value services, pinned dependencies, acyclic routing and installed synthetic lookup proof | Production retrievers and an approved MCP bridge if workflows need it; nested effectful services remain a negotiated enhancement |
| Evidence/context | Bounded attributed publications, receipt-backed awaited recall and frozen snapshots, exercised by the installed lab | Domain records mapped to P14 source/claim identity and production retrieval quality |
| Research ledger | Literal capture tied to successful recorded MCP results, at most 16 sources/32 claims/64 KiB per session; semantic support remains a model assessment | Explicit bounded study partitioning or reviewed pagination/cross-session evidence authority; not an unlimited corpus store |
| State/deletion | Scoped CAS records, locks/tombstones and installed rejection of delayed prompt writes after concurrent forget | TTL, persistent source-generation suppression, derivative deletion/export and production concurrency coverage |
| Owned work | Explicit invocations, prompt/answer jobs, fixed-range history, cancellation, receipts/questions and installed domain deduplication/catch-up | Production ingestion/reindex policy; fully concurrent effectful jobs remain a negotiated enhancement |
| Event source/views | Stable journal references, scoped history, prompt/answer delivery and selected live metadata/private-tool feeds, with separate ephemeral text sources | Unsupported view families and causal links listed in the lifecycle audit; cross-session history authorization |
| Optional model work | Explicit profile-bound `host.model` one-shot text calls, canonical usage/shared budget and private input grants; P23F source/package/platform checks passed | Embeddings need a separate public provider/accounting contract; callbacks cannot silently call a model |

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

Existing `tool.call` refuses MCP IDs, and value services cannot return effects or
nested host calls. Start research with the main model's configured MCP tools and
inert skill. Autonomous extension-driven external search needs a reviewed generic
bridge with approval, ownership, receipts and accounting boundaries; do not hide
it in worker networking. Likewise, `host.model` is one-shot text, not embeddings.
Embedding destinations, vector bounds, downloads and known/unknown costs need a
separate versioned contract. Current tree budgets do not cover MCP or embedding
charges. See [tool actions](extension-tool-actions.md),
[services](extension-services.md), [model calls](extension-model-calls.md) and
[budget coverage](budgets.md).

Retrieved chunks and memory records need stable identity, namespace/scope,
source/version/digest, timestamps, excerpt/reference and provenance. Optional
scores indicate ranking, not truth. Keep entities/index IDs linked to original
evidence, and extension content below the instruction/permission boundary.
Record source event and extractor version; reject stale writes after forget so
queued extraction/reindex cannot resurrect deleted facts. Current SDK state is
namespaced by artifact and configuration-source identity. P25 must distinguish
that execution identity from stable logical memory identity and propose explicit
export, migration and collection across upgraded artifacts and moved configs.
Never silently reassign old state to new code. Forget/no-resurrection and retention
must cover retained namespace versions and derivative graph/RAG indexes.
CAS alone is not a forgetting policy: an explicit write using the current
tombstone revision can recreate a key. Capture a logical source generation before
extraction and persist suppression across reingestion, migrations and late work;
do not simply read the newest revision and write forgotten content back.

Deleting a derived store does not erase journals, backups or prior remote/provider
transfers. Separately specify retrieval tombstones, history-access/redaction
projections, raw journal retention and secure erasure. The present private history
grant can expose original prompts/tool inputs/results; it does not implement
redacted history or true forgetting. A requirement to hide/redact retained host
evidence needs a reviewed generic core contract, not an extension's deletion claim.
Saved recall publications also restore without querying a backend: a backend
tombstone alone cannot exclude that text from a future resumed prompt. Broad
revocation needs a reviewed projection/invalidation contract or an explicit
affected-session handoff policy, distinct from erasing past provider transfers.
P25 should propose the boundary and assess its cost without implementing speculative
erasure or weakening mandatory recovery records.

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

The proposed order is small explicit capabilities, lifecycle integrity, then
optional automation and backends. The reference's checked packet proposal supports
this direction; Ipse's first proposals remain provisional where source inspection
failed. A shared recommendation is not proof, and final reruns do not retroactively
repair earlier reports. The [trial record](p25-evaluation.md) owns acceptance.

| Proposed increment | Delivery and measurable gate |
| --- | --- |
| P26A — explicit notes | Independent default-off working/project-memory tools, bounded state/context and selected-note export; deterministic scope, permission, quota and disabled-side-effect cases all pass |
| P26B — lifecycle integrity | Source-generation suppression, TTL/conflicts, derivative inventory and explicit migration/collection design; zero forbidden resurrection across delayed work, reingestion, restart and import fixtures |
| P27A — research and lexical RAG | Pluggable configured tools, cited sources/claims and bounded lexical retrieval; useful without memory, graphs or embeddings; explicit partial results on unavailable services |
| P27B — optional comparisons | Independently test extraction, embeddings/hybrid retrieval and graph adapters after generic host gaps/dependency approvals; publish matched baseline quality/resource deltas before selection |

No stage requires voice, a cost UI, a mandatory database or a workflow framework.
Required host authority/accounting gaps must close before operations that need
them. Current state is a small bounded store, not a scalable corpus engine.
Evaluate maintained Elixir/OTP facilities and packages before writing or selecting
storage/index machinery; a SQLite binding or native service is not approved by
its appearance in this table.

For future quality evaluation, propose a seeded 100-record/100-question corpus
across two projects and three sessions per project, with exact evidence spans,
unanswerable questions, updates, temporal conflicts and deletion races. Freeze
it and reference hardware/model/resource allocations before measurement. Initial
proposed quality gates are at least 90% supported answers/abstentions and 95%
semantic citation precision; every citation must resolve to its exact source/span.
Report recall@5, nDCG@10, p50/p95 latency, peak memory/storage, encoder work,
model calls and separately known/unknown costs. These are proposed criteria,
not measured scores or portable latency promises. Deterministic authority,
cross-project isolation, no-replay and no-resurrection cases require zero failures.

Sharing scope, retention periods, remote disclosure, hardware/resource ceilings,
profiles/billing and backup-erasure obligations remain material operator choices.
Keep affected features unavailable until configured; a research recommendation
or suggested answer does not supply consent. Full candidate/license/dependency,
weight, dataset and hosted-terms review remains necessary before adoption.

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
