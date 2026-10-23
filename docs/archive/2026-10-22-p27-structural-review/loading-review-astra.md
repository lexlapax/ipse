> Historical correction review, captured 2026-10-22. The body and dated addendum below are unchanged. Use the [review disposition](index.md#supported-toolchain-loading-correction) for the final assessment and the [developer manual](../../developer/index.md) for current instructions. Intermediate warnings are superseded only where the report or disposition explicitly says so.

# Explicit Runtime loading correction review

Verdict: no substantive actionable defect found in the proposed correction. The source change addresses the duplicate compilation path, preserves strict compiler diagnostics, and migrates the public callers found in the permitted scope. The strengthened test distinguishes successful callback admission from the earlier pre-callback failure.

## Scope and evidence

Reviewed the difference between `/Users/spuri/projects/lexlapax/ipse` and `/tmp/ipse-p27-structure-floor-20261022-c2/source` for all 16 files listed in `/tmp/ipse-p27-explicit-loads-isolated.patch-receipt.json`. Also read unchanged public verification Runtime and entrypoint code and searched public `dev/` and `test/` loading references, as separately authorized. Applied the shared interrogate rubric.

No source files were edited. No tests, builds, captured launches, private workloads, private evidence, or remote operations were run or read. Only this report was written. The reported Elixir 1.18.5 / OTP 27.3.4 failure and successful 14.5-second focused rerun are parent-supplied observations, not independently executed verification. The earlier `verification_test.exs:96` invocation selected the preceding case after the line shift and is not evidence for this test. I make no claim about the pending full suite or floor subset.

## Root cause and correction

`dev/verification/scenarios.exs:185-210` already declares both `dev/verification/scenarios.exs` and `dev/verification/runtime.exs` as measured compiler inputs and includes Runtime in the expected module closure. Before this correction, Scenarios also required Runtime at file scope. That gives the same module a direct compiler input and an implicit require path during the measured parallel compilation. This source structure supports the reported Runtime redefinition failure.

Removing the trailing require leaves Runtime explicitly declared in the measured closure. It also puts ordinary source loading in the entrypoint or test that owns execution. The correction leaves `Runtime.compile!/6` strict: only warning-free compiler results are accepted (`dev/verification/runtime.exs:991-996`), returned module identities must match the declaration (`:997`), and harness filenames must match the expected BEAM files (`:1008-1009`). There is no diagnostic suppression or relaxation of the closure check.

## Caller coverage

All Scenarios-loading callers found in the permitted public source scan load Runtime explicitly before using it:

- `dev/verify.exs` adds the explicit require; `dev/evaluate-knowledge.exs` already had it.
- Evaluation, verification, MCP-session, and model-fixture tests add the adjacent explicit require.
- Embedded suites in `packages_test.exs` and `graph_population_test.exs` load both files before loading fixtures.
- Subprocess launch arguments in `store_test.exs` and `index_abort_test.exs` add Runtime to their `-r` sequence before the fixture-loading `-e` expression.
- `store_contract_test.exs` adds Runtime to its source list before flattening that list into `-r` arguments.
- The existing embedded subprocess in `verification_test.exs` already requires both files.
- `dev/verification/package.exs` is loaded by Scenarios' package branch after the source entrypoint has loaded Runtime. The measured verification source uses Runtime through the declared compiled closure.

No missing public load caller was found. This is a bounded source scan, not proof about untracked external consumers or undocumented scripts outside `dev/` and `test/`.

## Captured runtime consequences

The measured source closure continues to include Runtime, so removing the file-level require does not remove it from newly compiled measured harnesses. Ordinary source entrypoints now supply their dependency explicitly.

The inspected captured evaluation path in `Runtime.reopen_evaluation!/3` verifies captured runtime identities and loads verified BEAM bytes through `:code.load_binary/3`; its child program does not require Scenarios or Runtime source files. The proposed load correction therefore introduces no source recompilation into that captured launch path and requires no rewrite of a retained artifact. Existing manifest identity and captured-file checks remain intact. This is a source-level consequence assessment; no retained runtime was opened or launched, and captured compatibility was not independently exercised.

## Callback-entry marker

The exact test now begins at `test/dev/verification_test.exs:97`. For each 26/27-module closure, it creates a unique reference, enters `Runtime.with_runtime/3`, successfully evaluates `MeasuredExecution.Environment.bound?()` in the prepared child, and only then sends the reference (`:116-127`). After the expected `MatchError`, the test requires that reference (`:132`).

A compiler or preparation `MatchError` can no longer satisfy the test: no callback marker would have been sent. The callback runs synchronously, so requiring the message after `with_runtime/3` does not depend on asynchronous callback scheduling. The mutation occurs after the marker; the unchanged post-callback verifier compares the input inventories, and the successful file write supplies the intended mismatch. `File.write!/2` failure would raise a different exception and fail the assertion.

This proves that preparation and the bound-environment child evaluation were reached before the expected refusal. The 26/27 counts alone are not the closure proof; the unchanged strict compiler and harness checks provide that during preparation. The test deliberately uses `native_environment: :base`, so it does not prove Linux native manager enforcement or a real measured evaluation workload.

## Integration note

The isolated diff drops final newlines from 15 edited files. The parent identified this as a patch-generation formatting artifact and committed to restoring final newlines and formatting before applying. It is not a substantive review blocker, but the final applied diff should retain those newlines. Formatting of that final revision was not verified here.

## Addendum — 2026-10-22: move verification dispatch into Runtime

The initial correction was incomplete: my first review missed the sequential source-load warnings from `Scenarios.main/1` referring to Runtime before the entrypoint loaded Runtime. The parent-reported floor subset exposed that failure. This addendum reviews the subsequent correction and supersedes the original conclusion that the explicit requires alone were sufficient.

No substantive actionable defect found in the extended correction. Compared the current isolated Scenarios, Runtime, `dev/verify.exs`, and declaration CLI test against main, and searched the allowed public developer/test sources for the old and new entrypoints. The old execution body is preserved in `Runtime.verification_main/1` (`dev/verification/runtime.exs:12-29`), with `Scenarios.parse!/1` supplying parsing and local `run` calls supplying execution. The sole discovered caller is updated at `dev/verify.exs:3`. No `Scenarios.main` caller remains in the searched scope. Scenarios retains a Runtime module atom in its measured catalog; it no longer calls or requires Runtime.

Package behavior is preserved. `verification_main/1` parses and validates the invocation before selecting the package branch, requires `package.exs` only in that branch, and invokes Package through `apply/3` after loading it. Both source files are in the same directory, so moving the `__DIR__`-relative require preserves its target. The entrypoint has already loaded Scenarios and Runtime when Package is compiled; Package's calls to those modules therefore have their providers available. Non-package source loading and measured compilation do not require or compile Package. The alias plus dynamic `apply/3` does not add Package to the measured compiler closure. The installed-package restriction remains in `Scenarios.parse!/1`.

The synthetic captured evaluator construction remains compatible with this move. `declaration_cli_test.exs:13-151` copies public source into an isolated repository, constructs both current and separate-CLI layouts, captures the selected evaluator, and checks that reopening reaches the measured-entry refusal before data inputs. Its `separate_cli_layout!/1` helper (`:432-481`) still rewrites Runner's `main/1`, the evaluator source/module declarations, and Runtime's evaluator entry call. None of those matched source fragments is removed or changed by the verification-dispatch move. The copied evaluator entrypoint explicitly loads both Scenarios and Runtime. The source fixture handoff subprocess in `verification_test.exs:218-233` likewise explicitly loads both before calling Runtime. This inspection establishes that the fixture construction still addresses the intended layouts; it is not an independent captured-launch result.

The callback-entry marker and strict compiler/closure checks are unchanged by this extension. Moving dispatch removes the forward-reference source warning path without suppressing warnings or weakening admission. Runtime's added dispatch function does not add a module to the expected 26/27-module closures.

The inspected extension diff now has final newlines. The parent reports that all earlier affected files have been restored; I did not run formatting or independently verify every restored file in this addendum.

Verification limit: read-only source and diff review only. No tests, package build, captured launch, private input, remote access, or source writes were performed. The 77-case floor rerun was live when this review was requested; its result is not claimed here. The full isolated floor result, final formatting, and integration checks remain the parent's verification responsibilities.
