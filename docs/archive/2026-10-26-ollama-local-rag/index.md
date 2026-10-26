# Optional Ollama embeddings and local RAG research

Dated research and planning amendment, **2026-10-26**, against `bd556fa`.
The developer requested an open-weight model running on Ollama for RAG and
embeddings. This record supports the [current proposal](../../knowledge-design.md#optional-local-embeddings-and-rag)
and [P31 ledger](../../plan.md#p31-usable-knowledge-and-prompt-assistance);
it is not an installation manual or evidence of model quality. Existing
[embedding procedures](../../operator/extensions.md#generate-vectors-explicitly)
remain unchanged. No models were downloaded, installed or run in this research.

## Selected qualification targets

Separate retrieval from answering. Use **Qwen3-Embedding 0.6B** as the first local
embedding candidate and **Qwen3.5 4B** as the optional local answer candidate.
This is a design selection for evaluation, not a claim they are the best models.
The small embedding artifact, permissive weight license, query instructions and
multilingual/code coverage make Qwen a reasonable first trial. Compare one smaller
embedding challenger, EmbeddingGemma 2's text-only artifact. Neither candidate is
an automatic fallback for the other.

| Role | Exact discovery tag | Native dimensions / advertised input ceiling | Download observed on this date | License and source |
| --- | --- | --- | --- | --- |
| Primary embedding candidate | `qwen3-embedding:0.6b-q8_0` | 1,024 / producer 32K tokens | 639 MB, Q8_0 | Apache-2.0; [Ollama artifact](https://ollama.com/library/qwen3-embedding:0.6b-q8_0), [producer card](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B) |
| Smaller text embedding challenger | `embeddinggemma-2:270m-q8_0-text` | 768 / producer 8,192 tokens | 304 MB, Q8_0 | Apache-2.0; [Ollama artifact](https://ollama.com/library/embeddinggemma-2:270m-q8_0-text), [producer card](https://huggingface.co/google/embeddinggemma-2) |
| Optional local main/answer candidate | `qwen3.5:4b` | Not an embedding model | 3.3 GB llama.cpp Q4_K_M; 4.0 GB MLX | Apache-2.0; [Ollama artifact](https://ollama.com/library/qwen3.5:4b), [producer card](https://huggingface.co/Qwen/Qwen3.5-4B) |
| Larger answer comparison | `qwen3.5:9b` | Not an embedding model | 6.6 GB llama.cpp Q4_K_M; 7.6 GB MLX | Apache-2.0; [Ollama artifact](https://ollama.com/library/qwen3.5:9b), [producer card](https://huggingface.co/Qwen/Qwen3.5-9B) |

Model payload size is not RAM/VRAM required. These tags can change and generator
artifacts differ by backend; record the full resolved manifest/blob identity,
quantization, template and runtime in each trial. Do not pin a short web-page hash
or use a bare family name whose default may select a much larger model.
Qwen3.5 has documented tools and thinking controls; those do not prove accurate
citations, abstention or source-bound capture on the quantized Ollama artifacts.

EmbeddingGemma 2's Ollama metadata currently advertises 256K context, conflicting
with its producer's 8K limit: use the lower bound, not the registry maximum.
Ollama [0.40.0](https://github.com/ollama/ollama/releases/tag/v0.40.0) announces
MLX support and [0.40.4](https://github.com/ollama/ollama/releases/tag/v0.40.4)
adds llama-server embedding work. These are support milestones, not an established
minimum version for every OS/backend/text artifact. Qwen's universal runtime floor
is also unverified. P31 must record tested Linux/macOS versions and effective limits.
Multimodal EmbeddingGemma features do not add audio/video/vision scope to P31.

Other candidates considered:

- [Qwen3-Embedding 4B](https://huggingface.co/Qwen/Qwen3-Embedding-4B) has 2,560
  native dimensions; its [Q4_K_M artifact](https://ollama.com/library/qwen3-embedding:4b-q4_K_M)
  is 2.5 GB. Keep it outside the starter matrix unless the smaller candidates fail
  a diagnosed quality requirement and a finite additional trial is authorized.
- Original [EmbeddingGemma](https://huggingface.co/google/embeddinggemma-300m)
  uses Gemma Terms, not Apache-2.0. Preserve the exact P27 artifact as a historical
  comparator; the new model cannot inherit its result merely by sharing 768 dimensions.
- [Nomic v2-moe](https://huggingface.co/nomic-ai/nomic-embed-text-v2-moe) is
  Apache-2.0 but limited to 512 tokens. Its [958-MB artifact](https://ollama.com/library/nomic-embed-text-v2-moe)
  offers neither the smallest download nor the selected models' input headroom.

## What the user would select

The proposed `ipse knowledge setup` offers local retrieval with the current main
model, or local retrieval plus an explicitly selected local main model. Both are
future P31 workflows. In the first case, retrieved excerpts still leave the
machine when the selected answer model is remote. Fully local answers require
resident local embeddings and generation, explicit next-new-session activation,
and no cloud fallback. Main-model tool capture remains the default; the embedding
model is not a second extractor and cannot establish that a fact is true.
Preflight all enabled inference stages, including extraction/reranking, decisions,
compaction and delegation. The local-only setup preview must resolve or disable
remote helpers explicitly, or refuse activation. A local main model alone cannot
make a previously configured remote helper private.
Inventory knowledge stores and source-processing services too; remote graph/MCP
storage is incompatible with the local-only path unless explicitly disabled or
replaced by an admitted local route.

Setup previews source scope, exclusions, endpoint, both model roles, exact licenses,
download/cache disk needs and resource limits. It reuses suitable resident models;
otherwise provisioning is an explicit optional action with bounded recovery.
Give acquisition its own model-count, download/cache/temporary-disk, deadline and
progress limits, separate from the embedding request ceilings. Journal ownership
and serialize Ipse's pulls per service/model, coordinating with inference slots.
Inspect partial/unknown completion after cancellation or owner death; no automatic
retry on resume. A disconnected HTTP client may leave the daemon downloading, so
qualify server-side stop semantics and report unresolved work. Inspect the complete
identity before enabling; never clean up another client's shared model assets.
Do not bundle weights in Ipse archives, download on ordinary startup, install
Ollama, or reconfigure a shared daemon by implication. Adding an external runtime
dependency still follows [dependency policy](../../developer/dependencies.md).

Ollama documents disabling cloud features with `OLLAMA_NO_CLOUD=1` or its service
configuration. Configure only a service the operator chose to manage. Qualification
must prove the knowledge pipeline with egress blocked after model provisioning; a loopback URL
alone does not establish local execution. Downloads and any enabled external
research remain separately disclosed boundaries. [Ollama FAQ](https://docs.ollama.com/faq).

## Contracts that need implementation

The existing [embedding adapter](../../../lib/ipse/provider/embedding.ex) and native
Ollama transport already bound input/output and reject silent truncation. Inputs
are at most eight strings, each 4,096 bytes, with 12 KiB aggregate; responses have
a 2-MiB ceiling and requests a maximum 120-second timeout. Returned count, declared
width and finite float32 values are checked. These are current constraints to
preserve, not permission to send a whole document at the model's maximum context.
The adapter presently forwards raw inputs and durable selection does not bind
the actual weight digest or task-format version. P31 owns those additional gaps.

1. **Format by task.** Qwen queries use `Instruct: {task}\nQuery:{query}`; documents
   use their text without that query instruction. Freeze the task text and test
   actual request bytes. Google uses distinct query/document wrappers; implement
   only the selected candidate's verified template, with a genuine source title
   or the documented missing-title form. See [Google's formatting guide](https://ai.google.dev/gemma/docs/embeddinggemma/inference-embeddinggemma-with-sentence-transformers).
   Count wrappers inside byte/token ceilings, preserve original citation spans,
   and make formatting single-owner so callers cannot double-prefix inputs.
2. **Use native HTTP.** Keep `POST /api/embed`, `truncate:false`, finite batches and
   exact native dimensions. The public API also exposes load/total duration and
   prompt token counts; measure them without equating them with end-to-end latency.
   Validate nonzero vectors and normalization; shortened vectors need separate
   quality evidence and renormalization. No new Python/JavaScript runtime or vector
   service is needed. [Embedding API](https://docs.ollama.com/api/embed),
   [embedding conventions](https://docs.ollama.com/capabilities/embeddings).
3. **Bind and preserve identity.** Include full model/runtime/backend identity,
   dimensions, normalization, tokenizer/effective context, task templates and
   chunker versions in the encoding/index contract. [Model inventory](https://docs.ollama.com/api/tags)
   exposes digests, [model details](https://docs.ollama.com/api-reference/show-model-details)
   exposes model metadata, and [running models](https://docs.ollama.com/api/ps)
   exposes residency/context. These checks are not cryptographic per-request
   attestation. Reuse/evaluate the existing owned immutable closure mechanism;
   shared-daemon mode needs a declared cooperative trust boundary and checks before
   and after jobs. Reject changed/unverifiable results. Never mix vectors from two
   generations, even if their dimensions match. Reindex into a bounded staging
   generation, recheck source/consent/suppression, then atomically publish.
4. **Budget the complete pipeline.** Preserve BM25 plus dense retrieval and RRF
   k=60 with citation/version filtering; do not introduce an obligatory reranker
   or decision engine. P31C1b's 256-MiB store cap includes notes, vectors, indexes,
   history and staging, not just source text. At 10,000 float32 vectors, 1,024
   dimensions alone consume 39.1 MiB; 768 dimensions consume 29.3 MiB. These are
   arithmetic lower bounds before index/metadata overhead. Preflight old+new
   generations together; stop visibly before exhaustion, and never evict pins or
   revive suppressed evidence to make a rebuild fit. Model cache disk has its own
   explicit bound outside the project store.
5. **Control context and contention.** Existing ordinary profiles do not set
   Ollama `num_ctx`; the [manual](../../operator/configuration.md)
   describes server configuration. P31 must inspect effective context or add a
   reviewed host configuration contract. Add operator-scoped endpoint slots across
   projects/processes, covering main/child generation and embedding calls separately
   from project budgets. One protected service ID covers its canonical origin and
   explicitly admitted aliases, independent of model/profile and chat/embed path.
   Start with one admitted inference, foreground priority and bounded cancellable
   waits. Release the slot after a settled response and before tool execution so
   a model-requested embedding cannot deadlock. Persist unknown reservation state
   on timeout/owner death: lock release does not mean daemon work stopped. Require
   confirmed owned-service quiescence or explicit shared-service reconciliation/
   recovery before clearing; no timeout-based automatic replay. Slots govern Ipse
   dispatches, not actual shared-daemon concurrency or other clients. Include header,
   tools, history, evidence and output/reasoning reserve in generation budgets;
   never truncate history silently. Residency policy must not unload another
   user's/shared service's model. [Ollama context guidance](https://docs.ollama.com/context-length).

## Finite qualification and handoff amendment

P31A freezes fixtures, model/runtime identity and finite local trials. Proposed
test classes are an 8-GiB CPU machine for embeddings and a 16-GiB system/unified
memory machine for the 4B answer model, with an available 8-GiB GPU as an accelerated
comparison. A 9B trial may use an available 24–32-GiB system or 12–16-GiB GPU class.
These are **unmeasured planning targets, not minimum requirements or buying advice**.
Use a bounded 16K generation-context pilot, subject to measured fit, and explicit
finite output/deadline/queue limits. Report CPU offload and memory pressure.

Do not multiply every model, corpus and hardware combination into an unbounded
benchmark. First compare lexical-only versus each embedding candidate with the
same fixed answer route; then compare 4B and an available 9B on the selected
retrieval pipeline. Freeze per-stage samples, cold/warm repetitions, maximum
runtime and stop rules before execution. The existing 120-second embedding bound
is a safety ceiling, not an acceptable interactive latency target. P31A sets
separate warm retrieval, cold startup, ingestion and answer-TTFT thresholds for
each intended hardware tier; missing measurements stay open before F release.

Include synonym-only and exact-ID queries, conflicts, abstention, source injection,
multilingual/cross-language and code cases, plus PDF/DOCX extracted passages and
citations. Record candidate recall separately from supported answers/citations,
capture-tool correctness, per-language results, prompt/history growth, cold/warm
latency, RAM/VRAM, co-residency, rebuild disk peak, refusal/cancellation and
no-egress operation. Keep prior P27 latency/failure evidence: its selected 9B
answer policy used long deadlines, so it does not establish an interactive preset.
See the [P27 held-out comparison](../2026-10-23-p27-heldout-comparison/index.md).

P31D0 designs the setup choices; C1b owns versioned vector storage/rebuilds; D1/F
ship and qualify the installed optional preset. Core notes E remains independent.
At least one local embedding/answer pair must meet the existing P31 quality and
new frozen resource gates to close the local slice. An unavailable challenger does
not block a proven primary; no proven pair leaves this slice open, with a recorded
failure and explicit scope decision needed to qualify completion. Never silently
switch models or claim graph/PDF's experimental waiver applies to this addition.

This is an additive amendment to the [implementation handoff](../2026-10-26-p30-p31-final-handoff/implementation.md).
P31A should archive the amended proposal, include these local-provider contracts
in its matrix, and preserve this dated research alongside its own measured evidence.
The original handoff's runtime/publication authorization limits remain in force.

## Review and verification of this amendment

Read-only reviews compared primary model/API sources, existing provider and
knowledge code, current operator/developer chapters and the amended plan. Repairs
clarified valid zero vector coordinates, all-stage local privacy, common service
identity, unknown request reservations and acquisition cancellation/limits.
Focused rechecks found no remaining issue in those reviewed contracts. This is
design review, not a runtime or model-quality verdict.

`elixir dev/check-docs.exs` checked 443 Markdown files and 4,197 local links plus
manual/archive rules with zero errors. No runtime tests, live inference, model
downloads or hardware measurements were performed; those remain implementation
qualification work.
