# Whole-codebase consolidation review, 2026-10-22

Historical implementation/review record. The subject was the uncommitted candidate
against `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb`; this is not an exact final-SHA
acceptance verdict. Use the [user manual](../../operator/index.md),
[developer training](../../developer/index.md), and [plan](../../plan.md) for current
instructions and open gates. The captured `817ab84` comparison remained untouched.
No reviewer accessed private workload inputs, references, predictions, journals,
remote processes, accounts, or credentials.

## Intent and panel

Consolidate host runtime, features, tests, developer commands, examples, resources,
and current manuals while preserving public contracts and real process ownership.
Session remains one conversation process; Turn/Invocation run synchronously within
it. Preserve individual historical files. File count alone is insufficient evidence
of reduced complexity.

The interrogate review used the same standalone brief and rubric for three
independent read-only reviewers. No project panel was configured, so three available
distinct models were selected. Their reports and explicit coverage limits remain:

- [gpt-6.1-sol](review-sol.md): one warning, missing schema test commands.
- [gpt-6-astra](review-astra.md): one warning, overstated batch validation.
- [gpt-6-sol](review-six.md): two warnings, captured entrypoint and missing tests.

[Provenance](review-provenance.json) binds original and bannered report hashes.
The parent independently traced every accepted finding before repairing it.
No finding was dismissed or left as an optional consideration. Agreement about
missing paths is independent consensus; the two other findings were each raised
by one reviewer and confirmed by the parent.

## Accepted findings and repairs

| Finding | Reviewers | Judgment and resulting behavior |
| --- | --- | --- |
| Reopening an older captured evaluator called Runner.main, absent from that capture | gpt-6-sol | Act on. Select the fixed historical CLI module only when it is a hash-verified capture member; bind/load it with the rest of that closure. New captures continue to use Runner. Never recompile/patch old evidence. |
| Architecture claimed all argument/workspace/guidance validation preceded every batch effect | gpt-6-astra | Act on. Teach whole-response identity/count/byte admission followed by sequential per-call checks/approval/intent. Earlier effects can precede a later refusal; runtime behavior remains unchanged. |
| Three schema exercises named a merged-away test file | gpt-6.1-sol, gpt-6-sol | Act on. Point the two dependency exercises and MCP exercise to test/ipse/json_test.exs. Extend the docs checker to reject absent focused-test paths in current manuals. |

## Causal evidence

The captured-entrypoint fixture builds two clean synthetic source repositories:
current Runner entry and the earlier separate CLI layout. Both seal an actual
precompiled evaluator, then reopen through the current public CLI. They use inert
artifacts and absent input paths; no model service or dataset is accessed.
The first red attempt was fixture setup failure because it omitted new untracked
entry files. It is not causal evidence. Corrected red r2 reached the unchanged
separate capture and failed with undefined Runner.main. The loader repair then
passed both cases in 50.4 seconds, including missing/extra capture-file refusals,
relative paths, unchanged runtime inventory, and zero created prediction/data/
report paths. The test copier now includes cached and nonignored new candidate
files instead of silently omitting the uncommitted source layout.

The documentation-path control used an isolated two-page Git fixture. Before the
new guard, a nonexistent test path passed. Afterward it produced two explicit
missing-target errors; creating the named file restored zero errors. Current
manuals passed the same checker with zero errors. These controls verify file
presence, not that every documented test succeeds or every chapter is usable.

Raw local receipts are retained in the ignored continuation capsule. The real
Research CLI separately passed investigation, ledger inspection, and assertion
with completion barriers, an isolated home, and zero model/external calls. An
initial piped driver raced busy commands and sent invalid /quit; its retained
output is not passing evidence. The corrected driver waits for Finished and uses
/exit. Public plan conversion/builder and pure version-three answer preparation
also pass with absent dataset files and no model calls.

## Supported-toolchain loading correction

The final broad default suite passed with 1,459 tests, one skipped and 36 excluded
in 1,176.4 seconds. A separate Elixir 1.18.5 / OTP 27.3.4 check then exposed a
verification-tool loading cycle. Scenarios listed Runtime as an explicit measured
compiler input while also requiring it at file scope. The strict compiler refused
the resulting redefinition. Removing that require exposed a forward reference
from Scenarios' command execution into the not-yet-loaded Runtime.

Scenarios now owns the pure catalog and argument grammar. Runtime owns command
execution, and callers explicitly load both. Compiler diagnostics and exact
26/27-module closures remain strict. The mutation-refusal test now requires a
unique callback-entry marker, so an earlier unrelated MatchError cannot satisfy
its intended post-callback assertion. The first two failing floor subsets remain
historical failures. The corrected isolated subset passed all 77 tests.

The [Astra](loading-review-astra.md) and [Six](loading-review-six.md) correction
reviews found no further actionable defect after the execution-body move. Astra's
addendum acknowledges the initially missed forward-reference warning. Six's
follow-up initially repeated the already-repaired capture defect and subsequently
withdrew that warning. The parent dismisses that stale follow-up claim based on
the actual fixed source and two-layout regression. This does not invalidate the
original pre-repair defect: the parent's causal red and green reproduced it.

## Final local verification

After integration, all fourteen changed caller suites passed, 161 tests in 681.3
seconds. Host runtime code was unchanged after the broad default suite. A fresh,
clean source snapshot passed build, formatting, strict compilation and all 77
focused checks on Elixir 1.18.5 / OTP 27.3.4. Its package build, installed package
verification, installed model-service ownership proof and demo passed. All fifteen
Knowledge presets built; all ten source and ten installed Knowledge routes passed
with synthetic services and no actual model calls. The snapshot's tracked source
remained clean and the original source inventory stayed unchanged.

macOS native checks passed 30 tests with six excluded. Rust bound-authority controls
passed three tests, regular-file copying passed seven with one ignored, and macOS
policy parsing passed four. The latter compilation retained the existing unused
run_anchor warning. These are macOS checks, not Linux enforcement evidence.

The code census excludes historical documents and counts Elixir, Rust and shell
sources under runtime, tooling, examples/resources and tests. Files decreased from
426 to 351. Nonblank lines increased from 125,131 to 125,630, including new regression
coverage. Host and bundled sources alone decreased from 131 files to 74, with 132
additional nonblank lines. No line-count or measured-complexity reduction is claimed.
The [provenance](review-provenance.json) retains the census and raw receipt hashes;
the full logs and source inventory remain in the ignored continuation capsule.

## Final macOS verifier repair

[Hosted run 39895104182](https://github.com/lexlapax/ipse/actions/runs/39895104182)
tested exact consolidation commit 6960ee2f7e1389c64ae0fe8a82d679c676ee0d76. Ubuntu
passed its whole job. macOS passed its full suite, native checks, packaging and all
source/installed Knowledge routes, then failed the final experimental App Sandbox
verifier at compilation. The merged process-boundary function still captured the
removed quote_shell name instead of the existing shell_quote function. This run
remains failed; successful earlier steps do not upgrade its verdict.

The repair changes that function capture to the retained helper. A default-suite
regression compiles the complete verifier module in an isolated Elixir child
without invoking its platform entrypoint. It first reproduced the exact undefined
function failure, then passed after the repair. The same complete module compiles
on Elixir 1.18.5 / OTP 27.3.4. The real default verifier also passed locally with
workspace spaces and an apostrophe: signed policy denied outside reads, symlink
reads, writes, chmod and loopback networking while permitting workspace/private
temporary writes and nested-shell inheritance. Strict signing/entitlement checks
passed. The optional detached-process boundary was not tested by this command;
its documented containment limits remain.

The [testing manual](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
now distinguishes cross-platform verifier compilation from actual OS enforcement.
Final exact-source hosted verification remains required for the correction.

## Remaining acceptance

The final exact-SHA hosted matrix, final-source Linux native-inclusive checks,
independent candidate review and commit/push remain. None is supplied by the
read-only reports or AST comparisons. Heavy Serenity verification waits for the
measured comparison to close.

P27 remains open for the complete private comparison/audit, independent semantic
review/adjudication, individual strategy qualification, all-results publication,
and an evidence-based engine choice. References remained sealed during this work.
The developer explicitly accepted the running comparison at
817ab84944c347f76e297efaad313b1ec841ee91 as versioned evidence alongside final-code
checks. Consolidation alone does not require another 350-answer run. Quality,
resource-audit and strategy-qualification gates remain mandatory.
