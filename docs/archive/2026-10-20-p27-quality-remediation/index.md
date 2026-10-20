# P27 quality remediation

Historical investigation record, 2026-10-20. This work follows the verified
[external-review repair](../2026-10-20-p27-external-review-r1/index.md) at
`e703f885d92273a1e694b0d4bb2328a84d38199f`. P27 remains open. Current procedures
belong to the [evaluation training manual](../../developer/knowledge-evaluation.md),
and acceptance belongs to the [plan](../../plan.md#p27-optional-research-graph-and-rag).

## Preserve failure diagnostics

Saved incomplete extraction and rerank invocations clustered near 120 seconds.
The Session's complete-result clock starts at invocation entry; a selected model's
120-second timeout starts later. That is consistent with deadline preemption,
but the old journals and evaluation receipts do not establish the exact cause.
The evaluator discarded Session error notifications while waiting for completion.

The driver now retains distinct `failure_codes` without copying error strings.
It recognizes the current complete-result deadline notification as
`complete_result_deadline` and classifies other error notifications as
`session_error`. There are at most two distinct codes. Existing outcome,
completion, uncertainty and cleanup semantics remain separate. This adds no
retry, effect, model request or host deadline change.

The regression fails before the change because `failure_codes` is absent. After
the change, nine Session-driver tests and 24 adjacent seven-variant runner tests
pass. The deadline control delivers the actual timer message to a held fixture
and checks the real Session notification and resulting receipt. It does not wait
120 seconds or prove the historical cause. A real failing callback also confirms
that private callback error detail is absent from the diagnostic receipt.
Formatting, strict compilation and the documentation checker pass. The sandbox
initially blocked Mix's loopback lock; compilation passed with the required
loopback access. The [receipt](diagnostics.json) retains log hashes and scope.
These are credential-free fixtures, with no real model or memory comparison.

## Remaining quality work

Model extraction still asks for absolute UTF8 offsets and canonical chunk hashes;
reranking asks for long canonical span identifiers. Dense retrieval uses a
200-character prefix, and answer preparation crops passages again. Compact model
contracts and complete evidence windows are under design. Their quality and
latency benefits remain hypotheses until measured on exposed tuning inputs.
The current comparison's one-fact-per-chunk preparation is another explicit limit.
No engine is selected.

The earlier workload stays exposed tuning material. Final validation requires a
new independently authored private 50-question workload with answers sealed until
first predictions are frozen, followed by matched exact charged-memory/resource
comparison and independent semantic review. Whole-codebase and documentation
consolidation remains a separate required readiness phase before P27 completion.
