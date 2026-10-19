# Evaluation clocks and budget reconciliation, 2026-10-19

Historical implementation and verification record after `48bb176`. The commit
containing this record owns the measurement changes. Use the current
[evaluation training chapter](../../developer/knowledge-evaluation.md#reconcile-model-work-with-durable-accounting)
for execution flow and exercises. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
retains the complete P27 acceptance requirements. This increment opens no
held-out member, runs no model weights and selects no retrieval engine.

## Measurement boundary

The runner records monotonic clocks for executable preflight, source authoring,
Session opening, ingestion, projection, each query, each public invocation,
cleanup and overall execution. Invocation clocks retain whether completion was
confirmed. Failure observations remain present, and missing query clocks make
coverage incomplete. Nearest-rank p50/p95, sample counts, unknown counts and
per-query outcome counts describe the observations. Canonical request durations
remain separate and can be unknown.

Every durable request is exported before budget inspection, so a reconciliation
failure cannot erase its canonical accounting. A second export associates each
request with its invocation journal interval, project, variant and source/query
context. It reports budget admission or refusal, dispatch intent and settlement
separately. Request groups distinguish index embedding, query embedding,
extraction, reranking and common answer generation. Unknown tokens stay unknown;
embedding output is not applicable. Unpriced work has no invented currency amount.

The read-only reconciliation runs under the saved budget's ordinary lock. It
requires exact admission identities and covers every earlier canonical usage
observation with retained liability. It accepts only one root session, matching
this evaluator's prohibition on delegation. The snapshot preserves all booked
token and money dimensions, partial outcomes and unknown reservations. Neither
a dispatch intent nor confirmed local invocation completion proves remote
provider acceptance or an invoice.

An initial implementation called the live `Budget.validate_sources/3` on an
inspection configuration. Inspection intentionally has no live checkpoint. Seven
of thirteen tests failed before accounting export, and a selected quota test
failed again during diagnosis. The evaluator now compares its single-root
admissions and conservative liability through public ledger/usage functions.
No live checkpoint, budget policy or core host invariant was changed.

The summary explicitly limits its `complete` field to clocks and accounting.
`resource_evaluation_complete` remains false. Storage reachability, OS process
peak memory and model process memory remain unmeasured. The existing file
counter and sampled harness BEAM memory do not close those gates.

## Focused controls

Four resource tests and ten runner tests passed together in 119.1 seconds,
seed 813202. They include the existing seven-variant public-Session fixtures
and real CLI phase controls. The seventeen-request case verifies full export,
query attribution, dispatch intent, settlement and canonical duration coverage.
The one-request quota case retains two query rows and two canonical attempts,
with one admission, one refusal and one actual scripted HTTP call.

The pure reconciliation control retains a sixty-token historical peak followed
by seven tokens. A budget replay without that earlier peak fails reconciliation.
Removing a refusal, changing the root identity or concealing canonical usage
behind a refusal also fails. Clock controls preserve return, exception and throw
behavior without retaining private failure reasons. Missing observations and
duplicate query clocks cannot pass coverage. All providers are owned loopback
fixtures; no actual model inference occurs.

The final export-order adjustment is covered by the full source suite: 1136
passed, 17 Linux-only exclusions, 571.2 seconds, seed 177058. Strict stdio tracing
and both actual macOS enforcement tags were enabled. Build, formatting,
warnings-as-errors compilation, CI policy and an isolated credential-free demo
passed. Documentation verification checked 229 Markdown files and 2562 local
links without errors. These local checks use macOS arm64, Elixir 1.20.3 and OTP 29.
The older hosted preflight/format run checks `48bb176`, not this increment.

The standalone source driver passed five checks with seven durable invocation
receipts and zero model requests. An initial installed recovery check selected
an explicit-only Graph artifact while its proof configured model extraction.
The worker refused ingestion before inference, as required for that incompatible
selection. That failed setup remains separate from verification with the
required model-capable Graph preset.

With that preset, the installed Graph recovery proof passed eight checks with
confirmed cleanup and zero model requests. The wrapper hid system development
tools and verified unchanged extracted host files and archive bytes. The archive
SHA256 remained `d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
No package was rebuilt or published.
Held-out quality, storage lifecycle measurement, independent semantic review
and the remaining full P27 acceptance audit stay open.

## Retained hosted failure

The [accounting revision matrix](https://github.com/lexlapax/ipse/actions/runs/39246740065)
at `f5b91b0` failed its macOS source step. The `bad_append` evaluator-driver
fixture expected a completed malformed continuation, but its second invocation
reached the configured one-second deadline. The first open completed in 345 ms.
The append receipt records 1054 ms, no confirmed invocation result, and
`{:timeout, :ok, {:done, :cancelled}}`. No inference request was involved.
This establishes the timeout boundary, not the component that consumed the time.
The cause remains open pending diagnostic evidence. Passing local runs do not
repair or explain it. macOS reported 1153 tests, one failure and 32 exclusions,
seed 461915, with later verification steps skipped. Linux completed successfully
with 1153 tests, zero failures and 32 exclusions, including its package and
independent installed proofs. All 24 steps in each terminal job were inspected;
only Linux's two macOS-specific steps were skipped there. The matrix's overall
result remains failure.
