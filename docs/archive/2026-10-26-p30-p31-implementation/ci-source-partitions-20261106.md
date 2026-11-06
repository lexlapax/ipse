# Complete source tests in separate CI jobs

This engineering record is dated 2026-11-06. The [current plan](../../plan.md)
owns acceptance; [testing guidance](../../developer/testing.md#run-the-complete-source-baseline)
owns contributor procedures. This change is not a hosted baseline pass or a
release authorization.

The Linux job in [run 42171506872](https://github.com/lexlapax/ipse/actions/runs/42171506872)
completed its build, parser, formatter, compiler, native and documentation checks,
then reached the existing 60-minute job limit during the default test suite.
It had no completed suite summary or installed-proof result. The macOS job
separately failed two native terminal input controls before its default suite.
Neither job is reclassified as passing.

CI now runs four Mix file partitions per OS in separate jobs. Each builds the
candidate and runs its complete assigned default test set without additional
filters. The installed Mix 1.18 implementation sorts all test files and assigns
them round-robin. The current 497-file census divides into 125, 124, 124 and 124
files, with an exact union and no duplicates. Nested fixture commands have no
partition flag and retain their complete explicit control sets. The local
single-VM default command remains available.

Platform/native/package/installed checks retain their separate job. Every source
partition and platform job retains a 60-minute limit. The draft-release workflow
uses the same two matrices, and draft creation waits for both complete matrices
and tag admission. No tag, draft, asset upload or publication was performed.

Fifteen focused release controls pass, including exact named-job step parity,
both operating systems, all four partitions, and refusal of omitted checks,
filtered or optional source jobs, weakened publication dependencies and premature
release mutations. The first run passed 13 of 15: its new test parser had
mistakenly treated trigger names as jobs. Restricting that parser to the actual
jobs section and checking the valid baseline before negative cases corrected
the test. The failed output remains retained.

Canonical Elixir 1.18 formatting and the existing action-pin policy check pass.
The full contributor testing chapter was reviewed and its overlapping hosted
budgets and release instructions reconciled. Source/runtime checks for the
focused run passed. Hosted partition execution and the broader installed and
P30/P31 acceptance remain open.
