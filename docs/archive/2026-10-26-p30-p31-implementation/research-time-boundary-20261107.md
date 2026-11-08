# Research worker time boundaries, 2026-11-07

This is a historical source-worker observation. The [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) owns current acceptance.

Research checks the complete captured source set for eligibility transitions
before proposing rerank and before constructing its result. Permanently
historical and never-eligible sources contribute no transitions. A
current-time investigation refuses with empty evidence and claims when a
transition has occurred or the sampled clock has moved before ranking time.
An explicit as-of time keeps its selected-time semantics. The checks include
sources omitted from the earlier ranking.

During later integration review, a controlled-clock case reproduced an
undetected rollback from 199 to 198 while both samples remained after the
selected time. That first revised run failed. The worker now carries the
pre-rerank sample through its continuation and compares subsequent publication
samples in order. The separate rerun passed the isolated wrapper, including
inline and paged rollback controls and a rollback across the rerank response.
An independent scoped source review found no concrete protocol regression.
A fresh `research/mcp-model` artifact built against the candidate SDK without
diagnostics. These checks do not fence approval-delayed host dispatch or later
delivery; the earlier full regression predates this additional correction.

An isolated extension-VM regression ran twice against the changed Research
source and the SDK/dependencies from the isolated `8d29aec6` build, using
Elixir 1.20.4 and OTP 29.1.1. The final run passed one outer test; its subprocess
requires ten inner tests with no failures, skips or exclusions. Controlled-clock
cases cover observation and expiry equality, sampled rollback, a newly eligible
unselected source, never-eligible and historical sources, historical query time
and the pre-rerank path. The canonical
Elixir 1.18 formatter check passed for both changed files. The test output was
observed in the tool session; no raw log was retained. A separate source review
confirmed the worker-boundary scope.

The tested intermediate Research source SHA-256 was
`ecafe958350f666247868fab0289095c20bbde6d78f5995231dc8da49a3c37c7` and
the regression file SHA-256 was
`201ddd1cd643714d1f3d6352c90c16e25f5706f17696d5090f71da6c069800b4`.
After restart, the later post-preparation check and its inline and paged controls
passed in the isolated extension VM using the same `8d29aec6` SDK and Elixir
1.20.4/OTP 29.1.1. The final run passed one outer test; its subprocess requires
eleven inner tests with no failures, skips or exclusions. Its stable-time control
produces a paged result, while a boundary crossed during preparation returns an
inline refusal with no evidence or claims. The first canonical formatter check
found one unformatted line; the source was formatted, the formatter check then
passed, and the final test ran against the formatted source. The final source
SHA-256 is `5af201e36337977a76fe3c17cbd14041c5232f8d3b589336a0dd67a2f80a4819`;
the test SHA-256 is `72198d5a220bcd68089c9df20fd8c635659a14a8a51ee88d11160b7b29e5f4fa`.
The retained final outer log has SHA-256
`a192df6bce9d253943d68942b316b5c79c7ccf21d303eb2cf4db009a0488eca6`.

A separate isolated checkout of `4f4c1255` with the two Research files above
passed the default PDF-free build, warnings-as-errors compilation, focused
regression, credential-free demo, full canonical formatter and documentation
checker. The focused regression passed one outer test with eleven inner tests.
The first sandboxed build stopped before compilation when Mix could not create
its local lock socket; the separately recorded host build passed. This checkout
also contained the corresponding Research manual and evidence changes, and is
not the final integrated source or package.

This does not fence approval-delayed Host dispatch or later Session delivery,
detect a clock rollback that recovers between samples, or qualify MCP,
installed artifacts or the complete current-source baseline.

The host has committed input and MCP effect records, but the current protocol
does not establish that a declared set includes every candidate and its time
fields. A future Host fence needs a replay-validated complete-set binding, not
only citations or a worker-supplied deadline. It must cover both direct budgeted
model calls and registered inference dispatch, as well as inline and saved
result delivery. These observations do not implement or qualify that fence.
