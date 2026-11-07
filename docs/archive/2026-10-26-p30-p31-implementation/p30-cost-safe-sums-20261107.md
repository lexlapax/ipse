# P30 bounded cost totals, 2026-11-07

This is dated synthetic source evidence, not P30 qualification. The [plan](../../plan.md#p30-advisory-decision-engines) owns current status and the [decision guide](../../developer/decisions.md#evaluate-the-advice) explains the evaluation contract.

Individual valid cost observations can sum above the supported JSON-safe
integer range. Selection and candidate-assessment reports now retain exact
totals through the limit and return null when any observation is missing or the
sum exceeds it. No total is clipped or wrapped. A measured supported-answer
improvement remains an independent alternative to a cost reduction. Refused
and unknown outcomes keep their existing distinctions. This follow-up builds on
the [unmeasured critical-recall repair](p30-critical-unmeasured-20261107.md).

In an isolated checkout based on `548d3e256bfe2f04e5b76ebc8d89a51e25b52fce`,
the final pure Elixir 1.20.4/OTP 29 run passed 33 tests with no failures, skips or
exclusions. It loaded the three decision-metrics, selection and assessment test
files with an independently built SDK/dependency code path and one scheduler.
The controls cover exact-limit, overflow and missing costs, both selection arms,
fully measured semantic comparison, assessment totals, empty sum identity and
the independent support-improvement alternative. Seven source/test hashes
matched before and after the run, in `pure-05.pre` and `pure-05.post` under
`_build/verification/p30-cost-bounds-20261107-01`. The output log SHA-256 is
`967841fea062dc5bd82827613f605fce26092c6c658d12fb29877db4ed8839a4`.

A separate pure invocation loaded the metrics module without `Ipse.JSON` and
passed the empty/overflow controls. The final changed Elixir files were formatted
with Elixir 1.18.5/OTP 27 before the final run. The first setup attempt failed
before tests because multiple `-pa` paths were passed as one option; its
`pure-01.log` remains separate. Subsequent intermediate runs passed 31 and 32
tests before the final controls were added. No Mix, native helper, PTY, network
port, notebook, paid service or independent labels were used. These checks do
not establish model quality, real cost measurement, installed behavior, the
integrated full-source suite or P30 acceptance.

The unfiltered documentation checker used a separate temporary Git index based
on `548d3e25`, with this archive explicitly included and the isolated worktree.
It checked 1,317 Markdown files and 10,573 local links with no errors. This
establishes documentation structure and link targets only.
