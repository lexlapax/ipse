# Hosted checks job budget

Historical verification record, 2026-10-20. Source is
`914bc0ad7fd1794e0c9855a20d4548b961c309f4`. Current contributor procedures are in
[testing](../../developer/testing.md#measure-and-report-honestly), and milestone
acceptance remains in [the plan](../../plan.md#p27-optional-research-graph-and-rag).

The exact-source [run 39392520309](https://github.com/lexlapax/ipse/actions/runs/39392520309)
finished with Ubuntu success and macOS cancellation. GitHub's macOS check
annotation states: "The job has exceeded the maximum execution time of 30m0s".
The workflow configured that limit for each complete platform job.

macOS started at 08:19:13 UTC. Its source suite passed at 08:40:48, native checks
at 08:41:18, package verification at 08:43:12 and saved-result proofs at 08:45:22.
The final source and installed knowledge step was still running when cancellation
arrived at 08:49:26. Its completed subcommands retained successful reports. The
whole step and the later App Sandbox check did not finish. Ubuntu completed all
applicable steps at 08:46:57. These observations do not establish a macOS pass.

The correction changes only the outer job budget to 45 minutes. It retains every
command and assertion, the two-platform matrix and all individual operation/test
deadlines. The complete knowledge proof alone took 6 minutes 38 seconds on
Ubuntu. Starting that step with under four minutes left was insufficient on this
macOS run. Fifteen additional finite minutes provide room for the existing proof
sequence without using another inference attempt or changing runtime behavior.

The complete contributor testing chapter and manual entry points were reviewed.
The operator workflow is unchanged. Local CI-policy and documentation checks
validate the edit; the correction still needs its own complete hosted result.
It establishes no real-comparison quality, exact peak or P27 completion.
