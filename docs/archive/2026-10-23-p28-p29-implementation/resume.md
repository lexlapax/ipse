# Pause and resume handoff

Saved 2026-10-23 at the user's explicit request to pause and resume from the
ChatGPT desktop app. This is an incomplete implementation checkpoint. The goal
remains planning, implementing and testing all of P28 and P29, then preparing an
external auditor to assess implementation completeness. Backward compatibility
is not required; correctness regressions are unacceptable.

## Repository state

- Repository: `/home/lexlapax/projects/lexlapax/ipse`.
- Branch: `main`; keep it as the only branch, as previously requested.
- Starting commit: `229439597ee33029a4ce7497782ce55e78dca058`.
- `.claude/` and `erl_crash.dump` were already untracked; preserve them and do
  not stage, read, delete or treat them as this task's changes.
- Read root `AGENTS.md`, the current plan and both accepted design briefs before
  continuing. No subagents have been used. No dependency was added.

## Implemented checkpoint

P28 WP1 adds `lib/ipse.ex` with application version and compiled commit identity,
`--version` and `version --json`, runtime help version, one archive version source,
and installed archive/application/CLI agreement assertions. Build/package scripts
force compilation with `IPSE_BUILD_COMMIT` to avoid stale embedded provenance.
The package dispatcher threads the supplied archive path to the existing package
proof. Operator recovery and contributor testing instructions explain the identity
and its limits. The plan and archive index link the implementation record.

P29 WP0 has an [official wire-facts record](wire-facts.md). OpenRouter reports
`model` and `provider` in streaming metadata and may repeat the finish reason in
the final usage frame. Gemini's stateless GenerateContent route remains supported;
original parts, including empty signed text parts, must round-trip. Both adapters
still need implementation and fixtures. Recheck documentation if resuming much
later; do not infer any live account behavior from this research.

## Checks actually run

- `./dev/build.sh`: passed after restoring the already locked PlugCrypto 2.2.1
  dependency and correcting a new module-attribute syntax error.
- `mix test test/ipse/cli/version_test.exs`: 2 passed, seed 935465.
- `mix format --check-formatted`: passed.
- `mix compile --warnings-as-errors`: passed.
- `elixir dev/check-ci-policy.exs`: passed.
- `elixir dev/check-docs.exs`: passed before this handoff was added, 406 Markdown
  files and 3699 links, zero errors; check the checkpoint's final result separately.
- `git diff --check`: passed before this handoff.
- Full `mix test`, seed 1587: interrupted by explicit user request, exit 130;
  **no final result**. Partial log: `/tmp/ipse-p28-wp1-tests.log`. It contains
  deliberate fixture failure logs, which are not a suite verdict. No assertion
  failure had been reported, but this is insufficient to claim a pass.
- Chained demo and package commands never started. No new installed archive or
  exact-source hosted result is established by this checkpoint.

The test shell/session (82249) is terminal. A host process-name check found no
remaining BEAM VM, Ipse helper, Erlang child setup or epmd after interruption.
There is no live operation to resume or poll. Start a new check only after
inspecting current source and state.

## Next actions

1. Inspect Git status/history and this checkpoint; preserve unrelated files.
2. Review the WP1 diff, rerun the full source baseline, and run the demo with an
   isolated `IPSE_HOME` from `mktemp -d`. Keep source/build outputs fixed during
   checks. Mix and fixture loopback require execution outside the sandbox through
   the normal permission flow; keep TLS and assertions intact.
3. Build `./dev/package.sh`, record its exact archive path, then run
   `elixir dev/verify.exs installed package --archive EXACT_ARCHIVE --input examples/memory-corpus.json`.
   Verify archive/application/version agreement, inspect failures, and obtain
   hosted Ubuntu/macOS results for the pushed revision. Do not call WP1 complete
   before its required checks pass.
4. Continue P28 WP2 errors, WP3 doctor, WP4 private setup, WP5 release lifecycle,
   and WP6 whole-manual review. Continue P29 registry equivalence, shared fixture
   conformance, pinned OpenRouter/local-compatible, native Gemini, and registry
   integration into doctor/setup. The implementation record keeps the full matrix.
5. Preserve distinction between auditor readiness, a fresh-account unassisted
   walkthrough, opt-in live provider checks and actual release publication. None
   of those has occurred. Prepare the concrete implementation and evidence before
   requesting any final external action or missing operator participation.

Commit verified packages and push without force. A checkpoint commit is a save,
not completion of WP1, P28, P29 or the external audit.
