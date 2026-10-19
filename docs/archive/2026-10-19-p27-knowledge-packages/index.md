# Independent knowledge packages, 2026-10-19

Historical implementation and verification record only. This increment follows
`66de1f8` and adds independently built Corpus, Graph and Research SDK artifacts.
The source commit containing this record owns the implementation and verifiers.
It does not complete P27 or select an optional model or retrieval engine.

Use the current [Corpus](../../operator/corpus.md), [Graph](../../operator/graph.md)
and [Research extension](../../operator/research-extensions.md) procedures to run
the packages. The [contributor training chapter](../../developer/knowledge-extensions.md)
teaches their ownership and execution flow. The
[plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance status.

## Implementation and corrections

Domain modules compile against the public SDK into separate worker artifacts.
They remain absent from the host VM. Fifteen presets fix the minimum selected
State, MCP, embedding and text-model capabilities before operator configuration.
The configuration generator emits disabled instances and exact trust/bindings;
it does not choose a provider, install a service or enable another package.

Store uses generation-bound source roots, registered drafts, immutable pages,
CAS publication and permanent suppression. State and an independently authored
MCP CAS fixture exercise the same lifecycle. MCP query references fetch only
their selected source-page closure and receive final root revalidation. Remote
scores are explicitly server assertions. BM25 works without model services;
optional dense, graph, fusion, extraction and rerank implementations require
their own selected profiles and verification.

Integration exposed and repaired real defects before this checkpoint:

- Erlang raw JSON encoding produced iodata and represented Elixir `nil`
  differently from JSON null. The packages now use Elixir's built-in JSON module.
- Missing continuation keys and a profile-name predicate reused for numeric-leading
  operation IDs refused valid result pages. Reader initialization and strict
  operation-ID validation were corrected; a complete two-vector 4096-coordinate
  reconstruction case was added.
- The fixture's generated request IDs became uppercase after the ninth request.
  Its IDs were corrected without weakening production validation.
- Research fixed its ranking time before fetching, which excluded completion-time
  observations. It now selects one ranking time after source capture. Provided
  source coverage also now counts its actual text bytes. Both regressions failed
  before repair and pass afterward; genuinely future sources remain excluded.

## Direct local evidence

| Check | Result and boundary |
| --- | --- |
| Build, format, warnings-as-errors compile, docs and CI policy | Passed before the Research repair; rebuilt artifacts, format, docs and policy also pass after repair |
| Full pre-repair source baseline | 1,062 passed, 32 platform-tagged exclusions; this does not cover the later Research change |
| Repaired full source including actual macOS sandbox/filesystem cases | 1,077 passed; 17 Linux-only exclusions; strict stdio cleanup probe enabled |
| Controlled Research and Store regressions after repair | 17 outer tests passed, including the isolated package suite |
| All independently built presets | 15 admitted; catalogs and file hashes checked, domain modules unloaded in host |
| Independent Corpus/Graph/offline Research Session proof | 11 groups passed; disabled and separate catalogs, exact citations, suppression, inert resume, zero model requests |
| Same base proof in extracted runtime | 11 groups passed; development tools hidden and host/archive unchanged |
| Corpus MCP query source and installed proofs | 9 groups passed in each; selected-only reads, forged/partial/stale refusal, denial and unknown recovery |
| Research MCP source and installed proofs | 15 groups passed in each; paged fetch citations, current/future observations, malformed responses, denial and unknown recovery |
| Evaluation driver positive Session proof | 5 groups passed; public paged UTF8 ingestion, valid dotted profile names, seven durable invocation receipts, zero model calls |
| Graph manual explicit-fact authoring command | Ran successfully against the actual pure evidence helper |
| Graph and offline Research manual configuration | Generated, imported and inspected through the actual CLI in isolated homes, without invocation |
| Credential-free demo and final warnings-as-errors compile | Passed |

The extracted-runtime proofs use the existing local archive with SHA-256
`96ca1aaebab676d87cff09f31f138aa37d942960582335b26d222c30e8c5817f`.
It is a local verification archive, not a published release. Each wrapper checks
that its bytes and extracted host files remain unchanged. These are independent
domain artifacts running against that host, not a claim that the archive contains
the new builder sources. The [build inventory](builds.json) records all fifteen
current artifact manifest hashes.

Local execution used macOS arm64, Elixir 1.20.3 and OTP 29. Hosted Elixir 1.18/OTP27
checks must identify the exact source separately. A Mix filesystem lock failed
with sandbox `:eperm`; the authorized loopback-capable build passed. The first
local model metadata preflight could not access OS CA certificates in the sandbox;
the authorized repeat succeeded without changing TLS verification.

The first [hosted package run](https://github.com/lexlapax/ipse/actions/runs/39203499682)
at `bce86244cd1d8b0d6b3391b886c164ebf83e34ea` stopped at formatting on both
platforms, before tests. Elixir 1.18 lays out several long keyword forms and
guarded bindings differently from local 1.20. Explicit blocks and longer local
binding names remove those ambiguous layouts. A complete syntax-tree comparison,
after removing metadata and normalizing only the declared local renames, confirms
equivalence for all five changed files. The 28 focused evidence/Store/package
tests and the five-group evaluation-driver proof pass after correction. The negative run remains retained;
corrected-source hosted verification is still required.

## Remaining full-milestone gates

The later [HTTP fixture lifetime correction](http-lifetime.md) retains the
corrected-format run's Linux failure and the controlled ordering proof and repair.
The later [evaluation preparation record](evaluation-preparation.md) retains
synthetic helper verification and actual tuning-only embedding/text outcomes.
The later [model wire investigation](model-wire.md) identifies the response-body
limit in a captured diagnostic and separates streaming framing from returned text.
The later [model workflow investigation](model-workflows.md) records exact draft
abort recovery, rerank continuation repairs, explicit Ollama thinking selection
and separately accounted tuning successes and failures.

Exact-source hosted checks still need their final receipts. Actual domain
embedding, extraction, hybrid and rerank
Session comparisons, remaining lifecycle/authority controls, and the complete
held-out quality/resource evaluation remain open. Evaluation-helper negative
failure-path coverage also remains separate from its positive Session proof.

Only metadata for the two already available local models was read. No actual
embedding or text-model inference ran for this checkpoint. Held-out corpus,
qrels and expected answers remain sealed. The preregistered quality thresholds
are decisions, not measurements. Preserve failed rows and do not infer semantic
support from literal quotation or transport success.
