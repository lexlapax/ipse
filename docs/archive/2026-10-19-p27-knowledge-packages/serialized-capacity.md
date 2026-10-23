# Saved-comparison capacity, 2026-10-19

Historical correctness and verification record after `d04b610`. This closes
serialized prediction/review consumer mismatches. It does not execute the held-out
comparison, establish model quality or complete P27. The
[training manual](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-evaluation.md#trace-an-answers-evidence)
owns current procedures and bounds; the [plan](../../plan.md#p27-optional-research-graph-and-rag)
owns acceptance.

## Follow saved bytes through their consumers

The runner writes one first-prediction JSONL file. It previously could finalize a
file that its own review/scoring reader and pure scorer later refused above
16 MiB, despite an existing cumulative allowance of 64 MiB. A synthetic complete
seven-strategy, fifty-query, two-project grid produced 20,475,387 bytes using
actual lexical/dense/fusion evidence helpers and valid escaped source quotes.
Every row passed independently; the complete file failed `prediction_size_limit`.
This is a valid producer-shape counterexample, not evidence that the private
hash-pinned workload has produced those same bytes.

Both single-file gates now allow the existing 64-MiB cumulative ceiling. The
256-KiB row ceiling, parser/schema/collection limits, complete grid, raw hashes,
first-attempt constraints and reference ordering remain unchanged. The producer's
raw SDK-2 value/base64 receipt duplication belongs in execution history, not in
normalized predictions; it was not the cause of this failure.

The complete downstream review then exposed a second mismatch. The actual packet
builder emitted a valid 2,641,491-byte review template from 350 saved rows, while
the score CLI read and decoded reviews with separate 1-MiB defaults. Its packet
was only 6,133,714 bytes, below the packet's 32-MiB file and 64-MiB total ceilings.
The matched answer helper independently accepted ten shown candidates in 1,156
input bytes and eight claims/eighty citation pairs in an 846-byte response.
This shape fits the actual answer policy, not merely the scorer's broader schema.

The score CLI now bounds review bytes at 32 MiB and uses the existing host
`Ipse.JSON.decode_unique/1`. Duplicate-key rejection and the depth limit remain;
the scorer still validates the complete review shape and references afterward.
The generic manifest and dataset limits remain 1 MiB. The common file reader now
reads at most `limit + 1` bytes and checks the actual result, so a stale stat cannot
silently admit growth above the cap. This is input bounding, not a new same-UID
filesystem-isolation claim.

## Reproduce the meaningful boundaries

From a built checkout, run:

```sh
mix test test/knowledge_evaluation_score_test.exs test/knowledge_evaluation_review_test.exs
elixir docs/archive/2026-10-19-p27-knowledge-packages/probes/review-capacity.exs "$PWD"
```

The permanent scorer regression retains all 350 rows with escaped citation
quotes above 16 MiB, rejects an altered raw hash, and separately refuses a
single file and multiple files above the unchanged 64-MiB total. Neither size
refusal opens a reference loader. The strengthened CLI tests read an above-16-MiB
file far enough to reject its wrong hash before labels, and score an above-1-MiB
valid review copy without upgrading its unmeasured semantic result.

The preserved pure probe reconstructs the actual packet and matched answer-helper
counts above, with no private dataset, model request, native helper or service.
Its SHA-256 is
`532f11f2ce25ff7536b180fea8d2c6f618dbe1e59015e37a7de7b5c34c03bc70`.
Domain helpers run only in this standalone verification VM.

## Verification and review boundary

The corrected scorer regression failed at the original size gate, then passed
after the repair. Its first draft failed earlier because its synthetic baseline
was absent from the declared variant list; that fixture error is retained
separately and is not the causal red result. Seventeen focused scorer/review
tests pass. Both strengthened CLI cases pass independently. The whole capacity
review identified the review-reader gap, then accepted the complete repaired
unit with no remaining findings. Review and lead execution are separate evidence.

The full source baseline passes 1,251 tests with 33 tagged exclusions in 723.8
seconds, with the strict stdio probe and unchanged 60-second deadline. Build,
formatting, warnings-as-errors compilation, CI policy and the scripted demo pass.
The changed Elixir files also match Elixir 1.18 formatting. This unit changes
external evaluation code and tests, with no new host/runtime dependency or native
implementation. Exact-source hosted checks are recorded separately.

The [hosted run for `aae6b1f8683e142e6fd5bdd098df34c265938d69`](https://github.com/lexlapax/ipse/actions/runs/39347154614)
finishes successfully on Ubuntu and macOS. Both source jobs report 1,284 tests,
zero failures and 33 exclusions. Ubuntu takes 654.4 seconds and macOS takes
1,043.7 seconds. The macOS native suite reports 36 tests, zero failures and six
exclusions. The package and installed-runtime gates pass on both platforms.

The explicit caps remain finite. This repair does not promise that every maximum
1,024-query/sixteen-variant declaration fits 64 MiB, or that every admitted
prediction file fits the separate review-packet limits. Size refusal retains
first attempts; dropping rows or rerunning inference is not recovery. Complete
fresh-cell measurement, owned model/cache identity, the actual held-out grid,
independent semantic verdicts and engine selection remain open.
