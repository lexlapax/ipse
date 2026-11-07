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

## Related Graph and Research controls

A separate synthetic Graph MCP child run reproduced the same two fixture-module
redefinition warnings despite five passing controls. Three wrappers had passed
their parent's entire code path to children that explicitly loaded that fixture.
Commits `84fe509b` and `2eff186b` restrict those child paths to their required
SDK and dependencies. The Graph children also now require exactly five and 34
tests, respectively, with no failures, skips or exclusions.

In separate contaminated-parent runs the Graph MCP outer wrapper passed once;
the Graph capture outer wrapper passed once with its native Session case excluded;
and the Research outer wrapper passed once with two unrelated cases excluded.
Their nested markers require all five, 34 and eight respective cases without
failures, skips or exclusions. These runs do not qualify the excluded native
journey or a current full suite. Wrapper and support-file pins matched before
and after the Graph runs. The Research run did not capture a complete SDK
before/after inventory.

The packet `_build/verification/graph-inherited-fixture-20261106-01/` retains
the reproduced warnings in `before.log` (SHA-256
`3237c773b6ab025f241e391c2ee8c1b4da4decac2bfc65a03a944be4f40dad4a`)
and final outer logs for Graph MCP
(`3410dcff4d3544e2fde7b16c4c45df53f6d2293ee0275a022694bb3927255642`),
Graph capture (`d990008e744332f16600df4662337b2b502480276d0a818d4ff17c233c131d19`)
and Research (`d34be75b04c373ca32cafcd95c6449eb8dcf94d2eb576171028c4bfeb4ba5805`).

## Document row-context control

A contaminated-parent run of the document row-context wrapper reached its
control marker but failed on six fixture-module redefinition warnings. Commit
`d6c03395` restricts the child code paths and leaves the warning check intact.
The same contaminated-parent wrapper then passed once with exit 0; its source
hash matched before and after the run. The before and after logs and status are
retained in `_build/verification/doc-inherited-fixture-20261106-01/`. This
focused control does not qualify the full document or installed journey.

The same inherited-path collision was reproduced for paragraph packing and a
selected fidelity test. Commits `c4bccf6b` and `12ff331e` isolate their child
paths; separate contaminated-parent checks passed with the original warning and
semantic assertions. After the fidelity repair, the entire fidelity file ran
at `12ff331e` with a contaminated parent: 38 passed, zero skipped or excluded.
Listed source, SDK and fixture hashes matched after the run; the postchecks do
not cover added files, links or file modes. No native Input or TCP test ran.

The full-file packet is
`_build/verification/document-fidelity-all-12ff331e-20261106-01/`. Its `run.log`
SHA-256 is `d6fa99549303225175a566a4492a9ea639079148b67940e4cced52eb29a87887`,
and `status.txt` SHA-256 is
`eb6ba8ffbbfae35702e014fd9ab71a536114ca209194503acb5a81c409049faf`.
This synthetic file-level result does not establish independent Word fidelity,
installed behavior or complete P31F acceptance.
