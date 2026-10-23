Historical review, 2026-10-22. Read-only assessment of the uncommitted candidate
against `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb`, before the recorded repairs.
Reviewer model: `gpt-6-sol`. Original report SHA-256: `7a46d1cbd6f20557bc50d986d61a35d5f9292fb51be386732be3350757d7bbf8`.
The report body below is retained unchanged; line numbers identify that reviewed view.
Use [current training](../../developer/index.md) and [the disposition record](index.md)
for current ownership and acceptance limits.

# Independent structural review of the uncommitted candidate

Baseline: `HEAD 5bffe00364d66f5012e5a0d4cd86c4180c74ebcb`. Reviewed the present tracked diff and untracked source/test/tooling inventory; read the shared rubric and quality reference. Findings below are source-supported. No source edits, remote work, private workload reads, or full test suites were performed.

## Findings

1. **warning — captured evaluator reopening depends on the current module layout.** `/Users/spuri/projects/lexlapax/ipse/dev/verification/runtime.exs:439` takes `Scenarios.evaluator().modules` from the new checkout, then lines 473–480 require those exact modules in the sealed capture. Lines 519–521 always invoke `Ipse.Development.Evaluation.Runner.main/1`. At `HEAD`, `Scenarios.evaluator().modules` included `Ipse.Development.Evaluation.CLI`, and the old `dev/evaluation/cli.exs` defined `CLI.main/1`; the old `Runner` did not define `main/1`. A version-2 pre-consolidation capture can contain a fully valid, unchanged old evaluator yet this loader invokes a function absent from its captured Runner. The ordinary `elixir dev/evaluate-knowledge.exs --phase ... --freeze ... --freeze-sha256 ...` path reaches `reopen_evaluation!/3` via `evaluation_main/1`; it will fail after seal verification rather than execute the captured entrypoint. This is particularly relevant to the retained immutable earlier comparison. Preserve the captured entrypoint contract by selecting the verified CLI module from the capture's declared closure/version, and test reopening a synthetic seal made from the previous module layout. Do not alter the existing private capture to test this. The actual private capture was intentionally not read, so its precise manifest version and whether this path is exercised remain unverified.

2. **warning — the dependency training exercise invokes a deleted test file.** `/Users/spuri/projects/lexlapax/ipse/docs/developer/dependencies.md:25` and `:155` instruct `mix test test/ipse/mcp/schema_test.exs`. The candidate deleted the old schema test and moved its assertions into `/Users/spuri/projects/lexlapax/ipse/test/ipse/json_test.exs`; `test/ipse/mcp/schema_test.exs` does not exist. A reader following either exercise gets a missing-file failure before checking the JSON adapter. Point both commands to `test/ipse/json_test.exs`. A read-only scan of `test/*.exs` paths in current operator/developer manuals, README, CONTRIBUTING, and examples found this as the sole nonexistent test path.

## Checks and limits

- Inspected `git status`, tracked diff names, untracked inventory, consolidation maps, Session/Turn/Invocation, Journal/source validation, extension and provider placement, CLI extraction, build/package scripts, verification/evaluation launch chains, CI path changes, and current manual entrypoints. Compared the captured-evaluator call chain against `HEAD` versions of the relevant files.
- Scanned current manuals for referenced test paths and current non-documentation source for stale moved paths. Confirmed `test/ipse/json_test.exs` contains the schema assertions and the old `test/ipse/mcp/schema_test.exs` is absent.
- No dynamic test was run. The parent already has focused and broad candidate results; final corrected-source full/platform/package/installed checks were pending in the supplied brief. This review does not establish those checks, live provider behavior, frozen private-workload compatibility, or exhaustive equivalence across all moved modules.
