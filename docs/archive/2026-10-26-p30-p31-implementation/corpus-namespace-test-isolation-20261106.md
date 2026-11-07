# Corpus namespace test isolation — 2026-11-06

Historical test evidence. The [plan](../../plan.md) owns current P31 status.

The running full regression against `0cdc36fa` reported an outer failure in
`Ipse.KnowledgeCorpusNamespaceFenceTest`. Its child completed all 16 controls,
but the wrapper rejected warnings that two fixture modules had been redefined.
The parent had passed an unrelated temporary fixture-harness directory to the
child through its complete code path. The original result remains in the active
run's `_build/verification/p31-final-regression-0cdc36fa-20261106-01/run-01/raw-private.log`;
the full run was still active when this record was written.

Commit `90f545c2` changes only the wrapper: the child receives the SDK and its
required dependency paths instead of the parent's entire code path. It still
rejects warnings, and the nested control marker requires exactly 16 cases with
no failures, skips or exclusions.

The focused test passed with both fixture modules deliberately loaded from a
synthetic harness in the parent process. The outer test reported one pass and
exit 0; the required nested marker establishes the 16-case result. The retained
packet is `_build/verification/corpus-namespace-isolation-20261106-01/`.
Its `focused.log` SHA-256 is
`79e6042940dc303dd0eec86bb1bb94d756e39a942a78d21ae9ac22ed90556e53`,
and its `status.txt` SHA-256 is
`931935425fedfe47b826857541e46859418a3c751a13f6afcd132ace14ea5f9f`.
The recorded inputs matched their post-run hashes. The run used one scheduler
and began with 2,814,736 KiB available; it did not use the shared native Input
or TCP test resources.

This isolated pass does not change the earlier full-run failure or establish a
passing current full regression. No model service or retained notes were used.
