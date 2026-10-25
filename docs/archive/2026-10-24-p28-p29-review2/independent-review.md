# Independent review of P28/P29 audit repairs at c2a19cb

Date: 2026-10-24.

- **Subject:** `c2a19cb`, which is `origin/main`, compared with the audited commit `1084f9a`.
- **Requirement sources:** the accepted P28 and P29 briefs, the plan, the approval, machine-label and xAI records, and the `AGENTS.md` invariants.
- **Receipts:** I treated them as claims to check, not as proof.

## Verdict

**Not yet acceptable as a complete repair.** Thirteen of the fourteen findings are resolved or substantially resolved. The automated gates pass locally and on the hosted runs.

However, the F1 fix introduced a **P2 regression in operator diagnostics**:
- `Ipse.CLI.Errors.message/1` now replaces any message containing a space-preceded `/` with a generic error.
- That generic text says "Unexpected error (unexpected_diagnostic). An effect may have happened; inspect saved receipts…", which is false for these cases.
- It hides causes the operator needs: configuration refusals that name a file, the changed-skill refusal, every Grok/xAI error, and the ChatGPT endpoint hint.
- This contradicts WP2's purpose: say what failed, whether an effect may have happened, and the next command.

Two smaller gaps remain:
- F7 is only partly addressed.
- F11 has one sibling help line still stale.

The other new findings are P3. Nothing found is P1.

## Checks actually run

All checks ran in a clean clone of `c2a19cb` in the scratchpad, with `ERL_CRASH_DUMP=/dev/null` exported. The original checkout is unchanged: HEAD is `c2a19cb`, the `docs/operator/usage.md` edit is still there, and `.claude/` was not read.

| Check | Result |
| --- | --- |
| `./dev/build.sh` | pass |
| `mix format --check-formatted` | pass |
| `mix compile --warnings-as-errors` | pass |
| `elixir dev/check-docs.exs` | pass |
| `IPSE_HOME=<fresh> ./bin/ipse demo` | pass |
| `rustc --edition=2021 --test -D warnings` for `ipse-sequence`, `ipse-listener` and `ipse-secrets` | pass (15+1, 7 and 0 tests; `ipse-secrets` compiles warning-free) |
| `mix test --include native_sandbox` (Linux, Elixir 1.20.4 / OTP 29) | **1772 passed, 0 failed, 19 excluded**, seed 629531, 1060.0 s |
| `./dev/package.sh` | `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` plus `.sha256` |
| `elixir dev/verify.exs installed package --archive <exact path> --input examples/memory-corpus.json` | pass (all 12 PASS lines, including setup→doctor→demo, Grok setup refusal, grants 4→2, upgrade/resume, symlink) |
| CLI comparison of the `1084f9a` and `c2a19cb` builds | regressions reproduced; see R1 |
| GitHub (`gh run view`, `gh api`, `git ls-remote`) | see Hosted evidence |
| Throwaway `elixir -e` running the exact `errors.ex:69` regex | used to confirm R2 |

Reviewer work, read-only:
- Three read-only reviewers inspected the per-finding code paths.
- The Rust drift probe was compiled and run, and a missing key panicked with status 101.

## Source equivalence

- `dc70463..aee0ad8`: under `lib native mix.exs mix.lock config priv extensions rel .github dev`, the only change is `test/ipse/extension/mcp_call_session_test.exs`. The rest of the diff is archive records.
- `aee0ad8..c2a19cb`: documentation and receipts only.
- So the hosted evidence at `dc70463` (release workflow) and `aee0ad8` (CI) covers the runtime and workflow at `c2a19cb`. My local runs cover `c2a19cb` directly.

## Hosted evidence (checked against GitHub, not run locally)

| Run | Event / SHA | Result |
| --- | --- | --- |
| 40137711178 Checks | push, `aee0ad8` | success. Only expected platform-specific skips. Ubuntu 1791/0 failed/36 excluded; macOS 1756/0/36/1 skipped; native 36/0/6, per the logs read by the reviewer |
| 40136316520 Draft release | workflow_dispatch, `dc70463` | success: `prepare`, both `test` legs and `draft`. Artifacts `verified-ubuntu-latest` (48,111,549 B) and `verified-macos-14` (34,424,829 B) present. Collection and complete-set admission succeeded. **"Create or recover … draft" and "Re-download and inspect" both skipped** |
| Superseded or failed runs | 6a2d861 cancelled; 2a9d950 failed (2 failures per platform); dd16c46 and dc70463 Checks cancelled | Recorded as such in `verification.json` |
| Releases and tags | API returns 0 releases, drafts included; only tag `v0.1.0-rc.1` (→ `e944fcf`) | No `v0.1.0` tag or release |

Not verified:
- The `c2a19cb` CI run was in progress during the review and is not referenced by the receipts.
- The tag-push create, upload and re-download path of the reordered workflow has never run.

## Disposition of the original findings

| # | Disposition | Evidence |
| --- | --- | --- |
| F1 | **Partly resolved; regression R1/R2** | The `inspect(reason)` producers are gone (`sandbox.ex:177-206`, `macos_sandbox.ex:596`, `workspace.ex:4-46` fixed map, `turn.ex:1186,1207`). A lint test plus binary-filter tests were added to `errors_test.exs`. `skill_catalog_changed` and the preflight causes are kept. The filter itself over-refuses; see R1 and R2 |
| F2 | Resolved | `chat_completions.ex:265-272` uses `Transport.safe/2` (`transport.ex:245-263`). Usage is still emitted before refusal (`chat_completions.ex:205-214`). Tested at `chat_completions_test.exs:417` plus the new filter test |
| F3 | Resolved | `release.yml`: the `draft` job `needs: [prepare, test]` and admits with `verify_assets!` (`:183`) before create or upload (`:193,:199`). Both mutation steps are `if: github.event_name == 'push'` (`:185,:202`). Create is only `--draft --verify-tag`; the reuse path asserts `isDraft`. Workflow default is `contents: read`. Upload and download actions are pinned to SHAs and recorded with approval (`dependencies.md:139-140`). Confirmed on run 40136316520 |
| F4 | Resolved | `docs/releases/v0.1.0.md` is standalone, with absolute `blob/v0.1.0/` links whose anchors exist at this source. The old notes are kept in `release-notes-before.md` |
| F5 | Resolved | `doctor.ex:184-190` points to `ipse setup` (`doctor_test.exs:79`) |
| F6 | Resolved | `Config.inspect_sources/4` (`config.ex:35-63`) reuses the bounded, boundary-checked `read_source`. Validation is pure; `trusted` mirrors trust and nothing is merged. Covered by the untrusted-project doctor test. In some cases the cause shown is masked by R1 |
| F7 | **Partly resolved** | Fixed: Ollama probe and inference both use `127.0.0.1` (`registry.ex:107-108`); anchors are checked against real headings; a saved-config secret test was added. **The cited gap remains**: installed setup→doctor still only rejects `fail` and accepts any warning (`dev/verification/package.exs:148`; the Grok case at `:184`). The tight macOS allowlist (`:85-91`) was added to the bare doctor check instead |
| F8 | Resolved | `install.md:118-130` puts logout and revoke before the `rm` commands |
| F9 | Resolved (minor residue) | One shared `native/ipse-secrets.rs` used by the runner and measure (`ipse-runner.rs:2-3,187-191`; `ipse-measure.rs:274`). Registry-driven drift probe (`runner_test.exs:193-213`, fails if a key is missing) and a real-shell test (`:172-191`). Rate-card completeness and uniqueness covered (`registry_test.exs:28-29`). Exception reasons recorded; see P3-5 |
| F10 | Resolved | Foreign call IDs omitted; native Gemini parts kept verbatim with their IDs (`gemini.ex:155-192`; `gemini_test.exs:291-299`). Vertex `.mtls` variants refused after lowercasing and trimming the trailing dot (`gemini.ex:17-25`). Reasoning guidance carried through profile validation (`profiles.ex:73-85`, `registry.ex:423`; `gemini_test.exs:177-186`). **Live foreign-history acceptance unverified** |
| F11 | **Partly resolved** | `terminal.ex:94` fixed. `terminal.ex:104` (`--max-output-tokens`) still says "API/Ollama only", but `xai_oauth` and `openai_compatible` accept it (`registry.ex:233,255`) |
| F12 | Resolved | `usage.md:119-122` matches `permissions.ex:17,55` and `terminal.ex:401-423` |
| F13 | Resolved (claim slightly overstated) | Real child delegation with an active parent edit grant still requires a forwarded approval (`delegation_integration_test.exs:140-150`). A real SDK write still asks and refuses `:session_edits` (`invocation_test.exs:2491-2498`). Both would fail if grants were inherited. The cancel test (`permissions_test.exs:180-196`) cancels during a pending approval, not during an executing effect; see P3-7 |
| F14 | Resolved | RC status and runtime-notice snapshot corrected. Walkthrough link and wording updated. Hosted receipts now carry run ID, `headSha` and steps that match GitHub. The 4000 ms disclosure added. Plan wording distinguishes original-scope verification |

## New findings

### P2

**R1. Configuration refusals that name a file are replaced by a misleading generic error.**
- **Where:** `lib/ipse/cli/errors.ex:64-75`.
- **Cause:** the regex at `:69` refuses any `/` that follows a space. The producers are:
  - `config.ex:409,414,419,445`: invalid, oversized or unsafe; not found; unreadable;
  - `config.ex:482`: a project file attempting endpoint, timeout or profile authority;
  - `workspace.ex:87`.
- **Reproduced against both builds:**
  ```
  IPSE_HOME=$H ipse run --provider demo --config $W/missing.json --cwd $W hi
  1084f9a: Cannot start: Configuration file not found: …/missing.json See …#diagnose-startup-and-service-errors.
  c2a19cb: Cannot start: Unexpected error (unexpected_diagnostic). An effect may have happened; inspect saved receipts before retrying and report the command with secrets removed. See …#report-a-reproducible-problem.
  ```
  - The same happens with a malformed `$IPSE_HOME/config.json` for `ipse run` and `ipse config`.
  - It also happens with a refused project `.ipse/config.json`.
  - Doctor's `config.files` row appends the same text.
- **Consequence:**
  - The operator can't tell which file failed or why.
  - The message falsely suggests an effect happened.
  - It points to bug reporting instead of configuration recovery.
  - For the project-authority refusal, the security-relevant cause is hidden.
- **Coverage:** no test asserts the CLI text for these refusals.

**R2. Runtime errors that mention slash commands, or "Grok / xAI", are masked the same way.**
- **Path:** every session `{:error, text}` goes through `Errors.format` (`terminal.ex:551-552`). I confirmed that the exact regex matches:
  - `turn.ex:65`: "Selected skill changed or is unavailable. Use /context refresh before loading it." This is the only feedback the operator gets, because `terminal.ex:661` swallows the reply atom.
    - Trigger: reference `$skill`, edit that skill's `SKILL.md`, then submit again.
  - Every xAI adapter error, because `openai.ex:41` rewrites the prefix to "Grok / xAI". This includes the missing-credential message at `openai.ex:17` and the terminal-stream refusals.
  - The ChatGPT hint at `registry.ex:50` ("…POST /v1/responses.").
- **Consequence:** the same misleading generic text replaces the recovery instruction. For Grok errors, it also replaces the information that no tools were executed.
- **Fix direction for R1 and R2:** map known refusals to fixed prose, naming the scope (operator or project) rather than the path where that is the concern. Narrow the binary filter so it refuses only real term syntax and control bytes. Add CLI-level text tests for the configuration, skill and xAI paths.

### P3

1. **F7 residue.** The installed setup→doctor checks at `package.exs:148,184` accept unexpected warnings, while the brief asks for "all ok or explained skip".
2. **F11 residue.** The stale "API/Ollama only" wording remains at `terminal.ex:104`.
3. **Release admission doesn't check the version or exact names** (`dev/release.exs:43-63`).
   - Platforms are matched only by `-linux-` and `-darwin-` substrings.
   - There is no check of the `ipse-` prefix or the `mix.exs` or tag version.
   - This is mitigated today because both archives come from the validated checkout.
4. **The release guard test is weaker than the properties it protects** (`test/dev/release_test.exs:31-36`).
   - It counts the `if: github.event_name == 'push'` lines without tying them to the two mutation steps.
   - It checks that admission comes before `create`, not before `upload`.
   - It doesn't assert `contents: read`.
   - `refute "--draft=false"` misses other publish forms, such as `gh release edit` or `gh api`.
5. **Record and notes gaps:**
   - An RC tag reuses `v0.1.0.md`, whose `blob/v0.1.0` links are dead until the stable tag exists.
   - `v0.1.0.md:30` says the bundles "include … checksum sidecars", but the sidecars are separate assets.
   - `dependencies.md:130-131` introduces the action table as `ci.yml`-only.
   - `dependencies.md:73` doesn't list `native/ipse-secrets.rs`.
   - The WP1 Transport-default exception has no reason recorded.
   - The measure launcher has no end-to-end secret test.
6. **Most provider stream errors are now withheld** (`chat_completions.ex:265-272`).
   - `safe(:message)` keeps only identifier-shaped text, so real provider prose is almost always withheld.
   - `error["code"]` is not retained.
   - No test proves that a safe identifier survives, so a filter that always returned nil would still pass.
   - This meets the brief, but the error loses most of its diagnostic value.
7. **The repair index overstates F13.** It says "cancel real work", but the test cancels only during a pending approval. Grants surviving cancellation of an executing shell or write are shown by code inspection only.
8. **Workspace protected-path refusal is now unspecific** (`sandbox.ex:205`). It no longer names which category overlaps, such as `.ssh` or `.ipse`.
9. **Possible MCP refusal of short env values.** This was there before the repairs; I found it by reading the code and did not run it.
   - `mcp/config.ex:479-505` treats every non-empty env value as private and scans the public manifest for it, including the 64-hex fingerprint.
   - So a value like `"DEBUG":"1"` would almost always be refused with a generic error. This is the mechanism behind the MCP fixture flake.
   - `docs/operator/mcp.md` doesn't mention it.

## Fixture repairs

- **Weakened tests:** none found. The only replaced assertions are stronger:
  - the anchor check now requires anchor ∈ headings;
  - `[redacted]` became "details withheld" plus a new filter test.
- **Workspace assertion:** `workspace_integration_test.exs:355` swaps `:enoent` for its fixed mapped text. Every outcome, journal and non-replay assertion is kept.
- **Tags, timeouts and runtime:** no new tags or exclusions; `test_helper.exs` is unchanged. Product timeouts are unchanged.
- **MCP overlap fix:** it changes only test strings. The explanation is credible: a hex secret can be a substring of the fingerprint, as the control script reproduces. The legacy `x[redacted]` assertion is kept, and no runtime MCP code changed.

## Limitations

- Not run: macOS, the hosted matrix and the Elixir-floor build. These are checked from GitHub only.
- Not run: the tag-push release path, and live Gemini, OpenRouter or xAI. No paid requests, account authorization, tags, releases or pushes were made.
- Not checked: local receipt logs under the implementer's `/tmp` and the archives under `dist/audit-repair/`.
- Not checked: `c2a19cb`'s own CI outcome.

## Remaining gates, distinct from implementation completeness

- Stable `v0.1.0` tag and publication. The reordered tag-push draft path is still unexercised.
- The assisted Linux walkthrough qualification; no human macOS or upgrade walkthrough.
- Grok live inference and approved-client OAuth: unverified (the API attempt returned HTTP 403, and there is no registration).
- Gemini foreign-history live acceptance: unverified.
