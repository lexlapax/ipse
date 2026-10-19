# Knowledge integration platform checks, 2026-10-19

Historical verification record for exact runtime candidate
`fb980a0abee17bf9dcdf0d197ff261fcad12035b`. This closes the complete-result
integration's platform gate, not P27. The
[plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance.
Current procedures belong in the [user manuals](../../operator/index.md) and
[contributor evaluation manual](../../developer/knowledge-evaluation.md).
The [domain review](complete-domain-results.md) and
[generic review](result-transport-review.md) retain earlier findings, repairs
and negative runs rather than replacing them with this passing result.

## Exact-source hosted matrix

[Run 39336257891](https://github.com/lexlapax/ipse/actions/runs/39336257891)
completed successfully on Ubuntu and macOS at the full commit above. Both jobs
use Elixir 1.18 and OTP 27. Each source suite reports 1,280 tests, zero failures
and 32 exclusions, or 1,248 executed passing tests.

Both jobs pass build, formatting, strict compilation, CI policy, documentation,
demo, fresh packaging, the extracted-package verifier and independent installed
extension/model-call proofs. Source and installed MCP, embedding, saved-result
and knowledge proofs pass, as does admission of all fifteen knowledge presets.
The macOS job also passes four native Rust policy tests, thirty native integration
tests with six exclusions, and the experimental App Sandbox verifier. Ubuntu
skips those macOS-only steps; its hosted job does not claim Linux native sandbox
enforcement.

The knowledge block includes complete-value, base, independence, MCP, Research,
recovery and Graph/Corpus lifecycle checks. The exact 4-MiB saved-result proof
retains all 1,024 fragments and verifies one callback, confirmed cleanup, exact
historical reads, unchanged journals and zero model requests. These are real
worker and local protocol fixtures, not live model quality measurements.

## Native-enabled Serenity run

A separate owned detached worktree on Serenity verifies the same full SHA.
Its source suite with native sandbox tests enabled completes in 660.1 seconds
with 1,265 executed passes, fifteen exclusions and no failures. Build, formatting,
strict compilation, policy, documentation, demo, fresh packaging and the base
extracted-package verifier pass. The main checkout remains clean at `5e2d85e`.

All fifteen presets pass admission. Source and installed executions each pass
sixteen base protocol groups and five complete-result cases. Graph and Corpus
each pass their seven-case lifecycle exercise in source and installed modes.
The owner-loss case explicitly retains unconfirmed cleanup; a passing exercise
does not convert that unknown into confirmation. Malformed/unavailable Corpus
indexing aborts the retained draft without another provider request.

The fresh Linux archive SHA-256 is
`02e9d4ffc7d849a0001dae898fc0ff252e23a3c080e508fec5a7f651dc3fba4d`.
Private receipts preserve the source identity, full logs, package identity and
eight independently parsed source/installed proof results. That archive is
distinct from the earlier generic-host archive recorded in its own review.

## Local checks and remaining work

The local macOS source baseline passes 1,248 tests with 32 exclusions in 724.9
seconds under the strict stdio probe and unchanged 60-second test deadline.
Build, both supported formatter versions, strict compilation, policy and demo
pass. Fresh source/installed domain proofs and all three manuals' configuration
and import examples pass. The domain review records their exact result sizes,
artifact boundaries and independent whole-milestone review coverage.

P27H4's bounded transport and complete-domain integration gate is complete for
this candidate. The earlier red `11d067f` hosted run remains a failed historical
gate; this later exact-source matrix verifies the repaired fixture and integrated
candidate. Neither result authorizes replay of the interrupted comparison.

P27 still needs exact peak-memory instrumentation, a clean comparison freeze,
the complete seven-strategy held-out workload, independent semantic judgments
and resource-based engine selection. The [memory investigation](resource-memory-grounding.md)
reproduces missing Port-child coverage in an outer-only kernel receipt. Its
metric-scope question remains pending. No new model comparison, model-service
restart or budget renewal occurred during these checks.
