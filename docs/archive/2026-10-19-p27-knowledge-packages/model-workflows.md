# Recover drafts and complete bounded model workflows, 2026-10-19

Historical investigation after `075d56e`. The commit containing this record owns
the recovery, continuation, prompt and explicit Ollama thinking-selection changes.
Use the current [Graph user manual](../../operator/graph.md),
[knowledge development manual](../../developer/knowledge-extensions.md) and
[model-call training](../../developer/extension-effects.md#request-bounded-text-inference) for procedures.
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance.
These tuning results do not complete P27 or establish held-out quality.

## Causal repairs

Graph could leave a facts draft after denied or failed extraction, but its public
source-abort command accepted only source-ingestion drafts. The repaired abort
accepts the exact current draft ID and root revision for source, facts and vector
drafts. Append and source publication remain restricted to source drafts.
Controlled State and independent MCP cases cover foreign IDs, changed revisions,
stale aborts, newer drafts, delayed publication and permanent suppression.
The real Graph-only Session proof failed at the exact abort against the old
artifact, then passed eight groups against the repaired artifact. Denied model
egress dispatched zero requests. Independent source and installed runs confirmed
cleanup, unchanged host/archive bytes and no domain modules loaded into the host.

Extraction now supplies `max_facts`, a closed JSON schema and absolute half-open
UTF8 byte-coordinate rules. Its decoder still independently checks fact count,
selected chunk identity and spans. Reranking requires a complete object containing
every candidate ID exactly once. Partial, duplicate and foreign orders refuse;
they do not become successful lexical fallbacks. A combining-character regression
showed that a 32-grapheme excerpt could contain 601 bytes. Excerpts now use a valid
UTF8 prefix of at most 128 bytes, matching the advertised request bound.

An actual completed rerank exposed a separate continuation defect. Nested
`put_in(state.ctx.rank[...], ...)` returned the outer state, which was then stored
as `ctx`. Corpus failed with a missing `snapshot`; Research had the analogous
missing `ranked` failure. Independent controlled cases reproduce both old paths.
The repaired continuations update the rank map inside the existing context,
retaining source coverage and the final root-revalidation step.

## Explicit model control

The already available `qwen3.5:9b` model advertises thinking enabled by default
and accepts `false`. Its recorded digest remains
`6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7`.
Ollama's [public thinking API](https://docs.ollama.com/capabilities/thinking)
documents native `think: false`. Ipse now accepts the explicit Ollama profile
value `reasoning_effort: "none"` and emits that native control. An omitted
selection leaves the wire field absent. Other provider/model allowlists remain
unchanged. This is a supported profile-control gap, rather than domain-specific
logic in the host. The existing execution field retains selection in approval,
journal and recovery validation; the SDK request and grants do not change.

The actual Session loopback case checks full approval, native `false`, canonical
usage and idle recovery. The independent model proof runs both default and
explicit `none` profiles. Both retain wire/text/native-receipt, token, deadline
and budget bounds. A native control requests backend behavior; it does not prove
the model's internal computation or imply free inference.

## Retained tuning outcomes

All inference used the normal Session boundary, the existing local Ollama service,
explicit egress decisions and fixed allocations. No held-out files, paid service,
model downloads, direct provider calls, retries or fallback were used. The two
permitted tuning sources were unchanged. Failed runs remain retained.

| Declared run | Observed outcome | Canonical reported input/output tokens |
| --- | --- | --- |
| Second bounded-text driver | Wrong caller State-namespace assumption refused ingestion before inference; driver policy corrected against the logical binding | Zero model requests |
| Default thinking, 4096-token text caps, four requests | Both extractions reached generation limits; rerank and answer provider calls completed; bare-array rerank output refused | 1549 / 14166 |
| Explicit `none`, four requests | Two extractions persisted valid attributed facts; answer completed; provider rerank completed but Corpus hit the context defect | 1647 / 420 |
| Context-repaired rerank, one request | Provider returned one of two IDs; strict decoder refused the incomplete order | 351 / 61 |
| Explicit count/no-filter rerank instruction, one request | Both IDs returned; query completed with final source revalidation | 386 / 117 |

The default-thinking four-request run retained conservative budget bookings of
9025 input and 14166 output tokens. The explicit-`none` run booked its measured
1647/420 tokens. The two single-request rerank runs each retained a 4096-token
input/output ceiling and one request slot. Every owned Session confirmed cleanup.
Offline journal restoration and canonical usage/budget audits verified all four
inference runs without repeating model work. Their costs remain unpriced and
semantic support remains unmeasured. Empty returned native thinking fields in
the explicit-`none` run are an observed response property, not internal proof.

The final rerank instruction supplies `required_count` and explicitly places
irrelevant candidates last. It does not relax complete-permutation validation.
The successful two-source trial verifies that path on tuning inputs, without
claiming general extraction, ranking or answer quality.
The [workflow artifact inventory](workflow-builds.json) preserves the fifteen
independently built preset identities used for this implementation.

## Platform evidence and remaining gates

The corrected source passed 1094 tests with actual macOS sandbox/filesystem
cases included, 17 Linux-only exclusions and the strict stdio cleanup probe
enabled. The run took 402.5 seconds on macOS arm64, Elixir 1.20.3 and OTP 29.
All 294 recorded runtime/native/domain/example/test source hashes remained
unchanged during verification. Build, formatter and documentation checks pass;
the documentation checker reports 222 files and 2529 local links without errors.

The new local verification archive has SHA256
`d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
The previous archive was preserved with its original hash. This is a local
verification package, not a published release. It was built before this final
receipt paragraph was added; runtime sources did not change afterward.

| Current source/package check | Result |
| --- | --- |
| Standard extracted-package verifier | Passed with development tools hidden |
| Independent installed model proof | Nine groups passed for each default and explicit `none` selection |
| Independent base knowledge proof | Eleven groups passed in both source and installed runtime |
| Paged evaluation driver | Five source groups passed, seven durable receipts, zero model requests |
| Corpus MCP selected-page proof | Nine groups passed in source and installed runtime |
| Research MCP search/fetch proof | Fifteen groups passed in source and installed runtime |
| Graph-only draft recovery | Eight groups passed in source and installed runtime; zero model requests, denied dispatches and stale-abort writes |
| Credential-free demo | Passed in an isolated home |
| Complete profile manual example | Actual CLI selected local Ollama and retained `none` in execution facts; no inference |

All installed wrappers confirmed unchanged archive and extracted host files.
Domain modules remained absent from the host VM. The twelve sequential source
and package verification jobs all exited zero. Their fixture service/model
responses do not establish live model quality. The manual-check script initially
misparsed its Markdown fence before reaching the CLI; after correcting that
script, the complete example passed. Its first offline assertion also used
`selected_profile` instead of the CLI's actual execution `id`; inspecting the
saved output corrected the assertion without repeating CLI work or inference.

The earlier wire-limit source `075d56e` passed every applicable step on both
[hosted platforms](https://github.com/lexlapax/ipse/actions/runs/39207812134),
including source/native/package and independent installed proofs. Only the
Linux job's macOS-only steps were skipped. That exact-source receipt does not
cover the later changes recorded here.

Full held-out evaluation, remaining lifecycle/authority controls, evaluator
failure-path coverage, resource comparisons and engine selection remain open.
The implementation, profiles, prompts, evaluator and clean-source identity must
be frozen before exposing held-out inputs. Final first predictions must be
hashed before labels or semantic review are opened. Keep the declared 0.90
support/correct-abstention and 0.95 semantic-citation thresholds unchanged.
