# Independent P28/P29 implementation audit at 1084f9a

Date: 2026-10-24. Subject: `1084f9a` (`origin/main`). Its runtime source is identical
to the final candidate `288a6a2` and to `622a2c8`; I checked this with
`git diff --stat` over `lib native mix.exs mix.lock config priv extensions`, which
was empty. Requirement sources: the accepted P28 and P29 briefs
(`docs/archive/2026-10-23-p28-p29-design/`), the plan's P28/P29 sections, the
approval, machine-label and xAI design records, and `AGENTS.md` invariants.
I used the auditor handoff only as a map.

## Verdict

**Implemented and verified locally, with no P1 findings.** I found one P2: WP2's
Done condition, "no CLI path prints `inspect(reason)`", is not met. Its
consequence is limited to local paths and POSIX atoms; no credentials are
exposed. Everything else is P3. That covers brief-literal deviations, drift
risks and stale record wording. The open gates are still open and unverified
here. They are the `v0.1.0` tag and publication, the WP6 walkthrough
qualifications (assisted navigation, no macOS or human-upgrade walkthrough),
Grok live inference and registered-client subscription access. None of the
records claims them closed, and P28 must not be declared complete until they are.

## Verification actually run

Everything ran in a clean clone of `1084f9a` in a scratch directory. The original
checkout was not built or modified, and `.claude/` was not read.

| Check | Result |
| --- | --- |
| `./dev/build.sh` (deps, native, forced warnings-as-errors compile) | pass |
| `mix format --check-formatted` | pass |
| `mix compile --warnings-as-errors` | pass |
| `elixir dev/check-docs.exs` | pass |
| `mix test --include native_sandbox` (Linux, Elixir 1.20.4 / OTP 29) | **1762 passed, 0 failed, 19 excluded**, 1060.6 s |
| `./bin/ipse demo` with isolated `IPSE_HOME` | pass. My first attempt with an empty `HOME` failed only because Mix could not find Hex, which is a harness mistake on my side and not a product failure. |
| `ipse --version` | `0.1.0` |
| `rustc --test -D warnings` on `native/ipse-sequence.rs` and `native/ipse-listener.rs` | pass (15/1 and 7) |
| `./dev/package.sh` | built `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` plus `.sha256` |
| `elixir dev/verify.exs installed package --archive <that path> --input examples/memory-corpus.json` | pass. Covers sidecar, setup/doctor/demo, cwd with spaces, standalone operation and unchanged inventories. My first attempt passed a wrong archive path from my own script; I reran it with the exact path. |

Not run:
- macOS, the hosted matrix and the supported Elixir-floor build (I checked the
  hosted receipts against GitHub instead; see below);
- live Gemini, OpenRouter or xAI inference, or any paid request;
- browser sign-in;
- release creation or publication;
- a fresh-account walkthrough.

## Requirement matrix (summary)

✔ means implemented, with code and a test that would fail without it.
Partial means part is implemented and a gap remains. Unverified means a human or
external gate I could not check. Each row lists only the exceptions.

| Item | Status | Notes |
| --- | --- | --- |
| P28 D1–D3 | ✔ | Default notice prints before `Auth.token` (`cli.ex:492-508`, test `setup_test.exs:200`); `v0.1.0`; `gh` recorded in `dependencies.md:139` |
| P28 WP1 version source | ✔ | Only `mix.exs` holds the version; compile-time commit; `--version`, `version --json`, help |
| P28 WP2 errors / status JSON | **Partial** | See F1 |
| P28 WP3 doctor | ✔ | No network without `--probe-provider`, no locks, no `Auth.token`; P3 notes F5, F6 |
| P28 WP3b kernel probe | Deferred as allowed | Doctor says enforcement was not probed |
| P28 WP4 setup / PrivateFile | ✔ | Atomic, owner-only, no-clobber backup, read-unchanged check; P3 notes F7 |
| P28 WP5 release | ✔ with deviations | OTP crypto replaces `sha256sum` (disclosed); draft-order deviation F3; notes F4 |
| P28 WP5 RC rehearsal | Verified by receipt and GitHub | Workflow run 40054387769 succeeded; release now absent, tag retained |
| P28 WP6 manual and walkthrough | **Unverified / qualified** | Assisted Linux walkthrough only; no macOS walkthrough; human upgrade skipped; uninstall order F8 |
| P28 `v0.1.0` publication | **Open** | Human gate |
| P29 WP0 wire facts | ✔ | Committed `b4788b4`, before adapter commits `8160f0d` and `62d3ad7`; official sources cited |
| P29 WP1 registry and goldens | ✔ | All 17 Spec fields. Goldens added once in `cd74f91`, never modified, and each source hash matches `dd510a7`. `dev/evaluation` changed by one disclosed comment only. Exceptions under-documented (F9) |
| P29 WP2 conformance | ✔ | Eight routes use the shared fragmented fixture; ChatGPT keeps its dedicated controls |
| P29 WP3 OpenRouter / compatible | ✔ | Identity checked before text on first and later chunks; usage emitted before refusal; only the `openai`/`OpenAI` alias; credit cost ignored; loopback literal-only (127.x, mapped IPv6, DNS names and userinfo all refused); F2 |
| P29 WP4 Gemini | ✔ | Header-only key; fixed `alt=sse` only from the Spec; Vertex refused; signatures verbatim and never invented; every finishReason other than STOP or MAX_TOKENS refused; partial usage preserved; F10 |
| P29 WP5 menus, priority, D2/D3 | ✔ | `AGENTS.md:37-38` order matches the registry; `data_collection` deny by default; help text F11 |
| P29 live | Verified by receipt | `492d091` receipt holds no secrets; Gemini usage partial as documented |
| Approval follow-up | ✔ | Exact `{cwd, sandbox, full args}` key; bounded; edit mode covers root native write/edit only; children and SDK use separate approval tuples that skip grants; fresh per-prompt code defeats stale input; grants journaled but never rehydrated; F12, F13 |
| ChatGPT machine label | ✔ | Strict ASCII label, URL-encoded, no hint on returning registration |
| Grok X0–X4 | ✔ at fixture level | Separate `xai` and `xai_oauth` identities with no fallback; foreign ciphertext refused both ways; finite device polling; validated URI; pending refresh never replayed; scope preserved; visible-only cap; `XAI_API_KEY` scrubbed in Rust and Elixir. With no `IPSE_XAI_CLIENT_ID`, login refuses before any IO. **Live API and subscription access unverified**; the `live-api.json` attempt got HTTP 403 |

## Findings

### P2

**F1. Raw `inspect` output still reaches the CLI, so WP2's Done condition fails.**
- The brief says: "Never print `inspect/1` of arbitrary terms… Done: no CLI path
  prints `inspect(reason)`."
- `Ipse.CLI.Errors.message/1` passes any binary reason through unchanged
  (`lib/ipse/cli/errors.ex:61-63`).
- Several inner modules still embed `inspect`:
  - `lib/ipse/tools/sandbox.ex:179` and `:206`, reachable through
    `--sandbox native` and setup;
  - `lib/ipse/workspace.ex:524`;
  - `lib/ipse/session/turn.ex:1207`, reachable through `/context refresh`.
- Consequence: absolute paths and Erlang term syntax are printed. No credential
  path was found.
- No test enforces the Done condition, so future binary reasons will also
  bypass the mapping.

### P3

- **F2. Mid-stream error text is not `safe/2`-filtered** (`chat_completions.ex:265-272`).
  The brief requires `error.message` "after `safe/2` redaction". The code embeds
  the raw provider message and only removes the API key, so arbitrary upstream
  text, including control bytes, can reach terminal and journal error text.
- **F3. The release workflow creates the draft before the matrix runs**
  (`.github/workflows/release.yml`: `prepare` job). The brief orders it as
  verify, then create the draft. With `fail-fast: false`, a failing platform
  leaves a partial draft that is still publishable by a human. The `inspect` job
  does fail in that case.
- **F4. The release notes can't be used as-is as the GitHub release body.**
  `docs/releases/v0.1.0.md:3-5` says the notes are "not evidence of a published
  release", and its relative `../operator/...` links won't resolve on a release
  page. The file needs editing before the `v0.1.0` tag.
- **F5. Doctor's default-provider warning points to `--provider`, not `ipse setup`**
  (`doctor.ex:168-170`). This differs from the D1 startup notice.
- **F6. Doctor's `config.files` hard-codes `trusted`/`parsed` as true**
  (`doctor.ex:138-145`). An untrusted project config is never listed, while the
  brief asks for each source's trust and parse status.
- **F7. Setup and package tests are weaker than the brief:**
  - setup's "no key in file" check covers only dry-run output (`setup_test.exs:39-56`);
  - the installed setup→doctor check accepts warnings (`package.exs:138`);
  - the anchor test checks that the file exists, not that the anchor exists
    (`errors_test.exs:16-18`);
  - the Ollama probe host `localhost` differs from the inference host `127.0.0.1`
    (`registry.ex:107-108`).
- **F8. The uninstall order is reversed** (`docs/operator/install.md:120-130`).
  The `rm` commands come before "Before removing the last executable, revoke…
  with `ipse logout`".
- **F9. WP1's documented exceptions are only category names** in
  `p29-wp1-verification.json`. Several literal provider dispatches are left
  without stated reasons:
  - `cli.ex:522-523`;
  - `setup.ex:198,220,249`;
  - `config.ex:199`;
  - the auth namespaces.

  Two hand-kept lists have no drift test against the registry:
  - Rust secret lists in `native/ipse-runner.rs:186` and `ipse-measure.rs:274`,
    and `runner_test.exs:172` also checks a literal list rather than
    `Registry.secret_env()`. A new key added only to the registry would reach
    native shells with no test failing.
  - `rate_card_ids` (`registry.ex:301`).
- **F10. Small Gemini mismatches:**
  - the config-time refusal of xhigh/max loses the brief's wording
    (`profiles.ex:73-82`);
  - rebuilt foreign history sends non-Gemini call IDs (`gemini.ex:174-194`), and
    live acceptance is unverified;
  - Vertex mTLS hosts (`*aiplatform.mtls.googleapis.com`) are not refused. This
    is beyond the brief's list.
- **F11. Help text is stale.** `terminal.ex:94` says `--base-url` is
  "(API/Ollama only)", but `usage.md` uses it for `openai_compatible`.
- **F12. The operator manual doesn't spell out what combined grants allow**
  (`docs/operator/usage.md:113-118`). An `edits` grant plus an exact-command
  grant lets the model rewrite a granted script and re-run it without a prompt.
  This is consistent with the trusted-shell model, but should be stated.
- **F13. Some non-inheritance guarantees are tested only at unit level.**
  Child and SDK non-inheritance of grants is tested on constructed maps or names
  (`permissions_test.exs:180-203`), not through real delegation or SDK effects.
  No test covers keeping grants across `/cancel`. Code inspection supports all
  three claims.
- **F14. Stale or incomplete record wording:**
  - in `combined-verification.json`, `rc_rehearsal.status` ("deletion pending")
    contradicts `draft_cleanup` in the same object;
  - `runtime-notice-package.json` `rc_status` is an in-progress snapshot;
  - the walkthrough record (`2026-10-24-p28-walkthrough/index.md:14-15,117-126`)
    links the deleted draft and says approval policy is unchanged;
  - `p29-wp2-hosted.json` and `xai/format-hosted-failure.json` lack
    `headSha`/run ID;
  - `approval/final-hosted-failure.json` has empty `steps`;
  - the handoff's fixture summary (`auditor-handoff.md:160-163`) omits that the
    after-effect test's local timeout went from 1000 to 4000 ms. That change is
    disclosed in `fixture-coordination.json` and is a fixture parameter, not a
    product deadline;
  - `plan.md:698`/`:708` "Complete" and "Final verification" for P29 refer to
    the original scope at `9c5eb6a`. This sits awkwardly with the handoff's
    "overall goal remains open".

## Evidence and provenance assessment

- **Hosted runs:** every recorded run ID, head SHA, conclusion and job list
  matches GitHub, checked with `gh run view`. The 288a6a2 matrix counts were
  confirmed from the run logs:
  - Ubuntu: 1781 tests, 0 failures, 36 excluded;
  - macOS: 1746 tests, 0 failures, 36 excluded, 1 skipped;
  - macOS native: 36 tests, 6 excluded.
- **Retained failures:** these are preserved and not presented as passes:
  - WP3 macOS 8160f0d;
  - formatting failures;
  - the b52c32e driver failure;
  - superseded and cancelled runs.
- **Fixture commits `288a6a2` and `521dd87`:** no assertions were removed (13
  were added), no product timeouts changed and no exclusions were added. The
  only timing change is a test-local 4000 ms setting. CI has no
  `continue-on-error` or `|| true`.
- **Secrets:** a `git grep` and `git log -p -G` sweep over the P28/P29 range
  found no committed credentials, OAuth codes or auth URLs, and no `.env` or
  crash dump is tracked.
- **RC state:** `v0.1.0-rc.1` release absent, tag retained, no `v0.1.0` tag.

## Unperformed or unverifiable

- Local-only receipt logs under `/tmp` on the implementer's host.
- Retained `dist/rc-rehearsal/` assets.
- macOS execution.
- Whether the recorded live requests happened as described.
- Whether the goldens were produced by an independent `dd510a7` build. Hashes
  and history are consistent with that.
- Test-first ordering of `registry_test.exs`.
- Unknown-outcome non-replay specific to OpenRouter and Gemini tool effects.
  This relies on the generic Session mechanism.
