# Selection critical recall with unmeasured rows, 2026-11-07

This is historical synthetic source evidence. The [plan](../../plan.md#p30-advisory-decision-engines) owns milestone status; the [decision guide](../../developer/decisions.md#freeze-a-selection-study) explains the current evaluation contract.

The selection report previously counted a critical case as recalled whenever
its stored membership contained the critical set, even if that arm's prediction
was refused or failed. The separate paired observation already marked that row
unverified, so the two fields could disagree. The revised aggregate uses null
when any critical prediction in the arm is not `ok`. A noncritical refusal does
not erase a known critical count. A null count withholds the aggregate threshold
comparison; it is neither zero nor a pass. Semantic support and citation
measurement keep their separate completeness field. The overall disposition
remains `unverified`, with no qualified production strategy.

In an isolated checkout based on `dbea54e73c9e4d34f1585bc5aa945fc3a6e909b3`,
the final pure run passed 31 tests, with zero failures, skips or exclusions.
It used Elixir 1.20.4/OTP 29 with one scheduler and SDK/dependencies from the
separate `8d29aec6` build. Controls include version-1 and version-2 refused
critical rows, failed and timed-out baselines, noncritical refusal, and complete
synthetic semantic reviews with a withheld critical comparison. The source and
test hashes matched before and after that run:

- `dev/evaluation/selection_experiment.exs`: `de77ce30fba708f12ec234f24f8aae1977099e4e99e6e5ff76881e28c1c7a395`
- `test/dev/evaluation/selection_critical_pairs_test.exs`: `a6fa856039fbb589fb01f46e686eadf7e7f26eb1b3d42eff3e8c99d3e458cbd9`
- The retained output log SHA-256 is `d078ed2957b4156bebf5717dad46dc3241e3ac50896dda734515a376e283c81f`.

The Elixir 1.18 formatter was applied directly through `Code.format_string!/1`;
the final test ran afterward. No Mix, native helper, PTY, service, retained
notebook, paid inference or real labels were used. This checks report arithmetic
and compatibility of the version-1 `score/6` and version-2 `score/7` inputs;
it does not establish independent labels, quality, latency/cost, installed use,
the current integrated suite or P30 acceptance.
