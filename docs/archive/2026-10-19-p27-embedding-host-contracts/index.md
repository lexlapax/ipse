# P27 embedding host-contract verification, 2026-10-19

Historical verification record only. This records the generic embedding increment
after `b55f39c`, not completion of P27 or a model-quality evaluation. Current
procedures are the [embedding user manual](../../operator/embeddings.md) and
[extension training chapter](../../developer/extension-effects.md#generate-and-reconstruct-embeddings).
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns current status.
The source commit containing this record owns the runtime, fixtures and manuals.

## Selected contract and corrections

The increment adds separately granted `embedding.create`, selected operator-only
profiles, actual OpenAI/Ollama native response adapters, exact egress approval,
private typed float32 sources and bounded coordinate pages. It extracts existing
text inference lifetime handling into `Extensions.Inference`, preserving v1 text
request/response/accounting semantics. Session retains sole admission, usage and
journal ownership. Existing HTTP/JSON/OS facilities are reused without new
dependencies or unaccounted worker inference.

Embedding admission/usage/completion v2 identifies its operation. Output tokens
remain null and explicitly inapplicable; shared output liability is semantic
zero before dispatch. Applicable unknown input and money retain reservations.
Version-1 rate cards remain text-only. Version-2 rows require operation identity
and embedding rows price flat input plus optional reported duration. Report
consumers preserve operation instead of dropping it during projection.

The first combined run passed 38 of 83 tests and failed 45. Its principal defect
was a new `oneOf` schema outside Ipse's deliberately bounded schema subset. That
invalidated legacy cards and nested configuration even without an active budget.
The correction uses one admitted closed schema with versions 1/2, plus strict
per-version row rules. The schema validator and SDK limits were not expanded.
The corrected combined run passed all 96 cases. A further 51 compatibility cases,
24 pricing/recovery cases and 21 real embedding Session/result cases passed.
The final mixed report/pricing run passed 22 cases after the report consumers
were updated.

Independent static review found an overly broad unknown-action predicate.
It now permits a saved vector source only with its exact admitted request and
either missing completion or completed/final equal usage and reported model.
The ordered usage reducer independently enforces the same source/completion
rule. Direct unknown-prefix and contradictory-completion regressions passed.
Later integrated review found no additional concrete runtime defect. Its stale
manual findings were corrected, including a separate unsupported-capability
statement found in the final whole-manual search.

## Direct verification

| Check | Result |
| --- | --- |
| Build, format and warnings-as-errors source compile | Passed |
| Full source including actual macOS sandbox/filesystem cases | 1,032 passed; 17 Linux-only exclusions |
| Actual SDK worker Session/result cases | 21 passed |
| Independent embedding artifact, source host | 12 checks passed; two synthetic native provider calls, zero actual model calls |
| Native Rust macOS policy | 4 passed |
| Signed macOS enforcement probe | Passed file/network denial, allowed workspace/private-temp operations, inheritance and strict signature/entitlement checks |
| Credential-free demo | Passed |
| Standard extracted-package baseline | Passed under the native process-group owner with a 120,000 ms bound |
| Independent embedding artifact, extracted runtime | 12 checks passed; archive/host unchanged and development tools hidden |
| Independent MCP artifact, same extracted runtime | 12 checks passed; archive/host unchanged and development tools hidden |
| Unchanged text model-call artifact, source and extracted runtime | 9 checks passed in each; archive/host unchanged and development tools hidden for installed execution |
| Operator embedding configuration example | Actual CLI inspection passed without inference |
| Hosted Linux/macOS embedding gates | Passed at `3e32051`, run `39198125930`; source, package and independent source/installed proofs |

The local archive SHA-256 is
`96ca1aaebab676d87cff09f31f138aa37d942960582335b26d222c30e8c5817f`.
It is a local verification archive, not a published release. Later evidence-only
documentation edits do not assert a rebuilt archive. Existing Mix support-file
and fixture type warnings, the Rust unused-helper warning and the optional macOS
probe module warning remain distinguished from failing checks.

The [rerunnable SDK artifact](../../../examples/embedding-actions/README.md)
drives real loopback Ollama/OpenAI native wire formats. It validates reversed
OpenAI indices, widths 768/4096, eight vectors reconstructed through 48 bounded
reads, whole-vector hashes, full approval, denied/exhausted zero dispatch,
source-before-completion/result, operation-aware usage, a shared output-zero
budget and inert resume. The artifact module remains absent from the host VM.
The installed wrapper hides system Elixir/Erlang/Mix/Rust and verifies the same
archive and extracted files remain unchanged.

The Session cases additionally exercise actual timeout/cancellation/owner loss,
separate approved child inference sharing the parent quota, receipt/source/page
tampering before tail repair, overdrawn publication refusal and a real budget-lock
barrier after provider dispatch. Unconfirmed observation/settlement preserves
genuine final metering while exposing no vectors, retaining reservation and
refusing unproven resume coverage. Strict cleanup and production deadlines were
not relaxed.

## Hosted verification and remaining acceptance

The first [hosted run](https://github.com/lexlapax/ipse/actions/runs/39197237697)
at `2c77907` stopped at formatting on both platforms. Elixir 1.18 wraps one guarded
binding differently from local Elixir 1.20. Naming that local binding
`embedding_vector` makes its multiline layout consistent. A syntax-tree comparison
after removing call metadata and this single local rename confirms alpha
equivalence; 24 text/vector result regressions and warnings-as-errors compile
pass. The initial comparison helper had omitted remote-call line metadata; the
corrected comparison removes all call metadata. No runtime deadline, assertion,
SDK bound or behavior was changed. The earlier package hash above still identifies
the pre-correction local verification archive.

The corrected-source [hosted run](https://github.com/lexlapax/ipse/actions/runs/39198125930)
at `3e320513fc0c8de30a77ad476aacff73888bcbf1` completed successfully on both
`ubuntu-latest` and `macos-14`. Each job passed formatting, compilation, the full
source suite, packaging, package verification and the independent source and
installed embedding proof. The existing MCP and text-model artifact proofs also
passed. These hosted packages are separate from the earlier local archive.

No actual embedding or text model was called for these proofs. They establish
transport, authority, typed storage, accounting and recovery, not retrieval,
semantic support or model selection. Research/corpus/graph packages, source
suppression and stale-index lifecycle, matched held-out comparisons and actual
selected-model quality remain open in the full P27 plan. The generic H3 host
contract has passed its scoped local and hosted gates.

The [quality preregistration](quality-preregistration.md) records thresholds before
held-out exposure; it is not a measured result. The [decision trail](decisions.tsv)
preserves failures and corrections. Its initial placeholder timestamp and short
integration rows remain historical entries with explicit later corrections.
Temporary paths identify local working receipts; committed fixtures and verifiers
provide rerunnable checks. No credentials, private transcript or generated release
is preserved here.
