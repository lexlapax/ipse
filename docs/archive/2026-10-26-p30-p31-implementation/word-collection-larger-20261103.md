# Larger workspace Word acquisition and installed Collection check

2026-11-03. This synthetic Linux evidence concerns one workspace Word acquisition larger than 32 KiB using the shipped Collection-backed Corpus. It does not complete P30 or P31, establish the maximum practical document size, test other platforms, or attest semantic extraction independently of the operator-trusted Corpus artifact. The workspace file recheck is point-in-time and does not lock the file against later mutation.

## Installed result

The default PDF-enabled archive `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` had SHA-256 `42b084dd2990bc8a2a20de3c40cbd4ea6e92260697d930aae5ed374a408ad918`. Its installed synthetic Collection journey passed with verifier and postcheck exit 0. The retained original was 36,251 bytes, SHA-256 `b81b5b8352fb8f61f718bf0a667c2528dce7bc03e8d4baa0cf85c2d91f5b8ce0`. The fixture acquired and cited the source, asserted the citation's original hash, refused use while the original was absent, and succeeded after restoration. It also checked that the configured artifact matched the installed shipped catalog; that artifact's digest was `8e007c6be9134fa98efeebd1f2042b1aaef72228803d6653604ae58591933480`.

The [installed report](word-larger-installed-20261103/installed-report.json) records zero model calls and an unchanged extracted-release inventory across the verifier. The separately retained [archive member list](word-larger-installed-20261103/final-archive.members) and [post-run extracted file inventory](word-larger-installed-20261103/final-installed-release.sha256) identify their contents; the verifier's before/after comparison is represented by the report, not by an independently retained before-inventory. The installed run used the existing ExUnit fixture pattern, copied ExUnit and a synthetic Rust PTY compiled before launching the packaged runtime. It was not a human-operated test. The fixture's raw terminal log, which contains synthetic approval material, remains only in volatile scratch; the report records its hash.

The package was built from a complete Git export of `f1d84fc280873d6c7630666f545614a45fad2c44` plus the 22-file [reviewed overlay](word-larger-installed-20261103/word-vertical-live.patch). The archive's commit field is that base label, not a claim that the overlaid source was committed at that revision. The [source inventory](word-larger-installed-20261103/final-package-source.sha256) covers 8,765 regular source files; [membership](word-larger-installed-20261103/final-package-source.files) and the tracked [symlink](word-larger-installed-20261103/final-package-source.links) were checked separately. Offline caches were copied from the previously named task-owned synthetic caches with matching lockfiles; this is not independent dependency attestation. The package build and postcheck passed and its documentation check found 52 documents and zero missing local targets.

## Source-tree controls

The exact [source manifest](word-larger-installed-20261103/word-vertical-live.sha256) and [compiled runtime inventory](word-larger-installed-20261103/live-runtime.sha256) were checked around the final isolated runs. The strict project compile and [16 focused controls](word-larger-installed-20261103/live-focused.log) passed. Those controls cover receipt pairing/lifetime, document-guard classification, one-use reader and peer refusal, bounded result/termination waits, owner-scoped task recognition, and an actual queued-start/Worker-death process case. The short synthetic wait checks do not prove an interrupted underlying file operation has already stopped.

Fresh real Sessions on that source passed the [small document](word-larger-installed-20261103/live-small.log), [larger document](word-larger-installed-20261103/live-large.log), [owner-loss/no-replay](word-larger-installed-20261103/live-loss.log), and [small source replacement at publication](word-larger-installed-20261103/live-interpose.log) scenarios. The larger case checked acquisition, citation, refusal on changed or missing original, recovery after restoration and idle reopen without replay. The interposition case directly read the native Collection afterward and found no published source head. These are synthetic source-tree Sessions, not independent installed results.

A fresh [cancellation-at-registration control](word-larger-installed-20261103/live-cancel-v2.log) found the peer dormant at the paused registration point, queued actual Session cancellation, observed peer termination and found no native source head. It returned `cleanup_unconfirmed`; it does not establish clean cancellation or prove the peer never started after the pause was released. The [legacy branch control](word-larger-installed-20261103/live-legacy.log) used the production guard source under a test-only module name, a fake legacy classification and a real file recheck/native commit seam. It does not establish a live Session legacy receipt or reader authority. The [durable test-only patch](word-larger-installed-20261103/word-durable-tests.patch) was prepared separately. Its [exact combined Session test file](word-larger-installed-20261103/combined-session-test.exs) was run against the unchanged fingerprinted runtime: [four opt-in cases passed, 26 were excluded](word-larger-installed-20261103/combined.log), and source/runtime postchecks passed. Cancellation again reported cleanup-unconfirmed. The direct ExUnit entry selected the four cases without loading `test_helper.exs`; the separately copied [integrated test helper](word-larger-installed-20261103/combined-test-helper.exs) records the default opt-in exclusion.

The integrated worktree was independently checked against the source manifest: [21 of the 22 original paths match](word-larger-installed-20261103/integrated-21.sha256). The one expected difference is the Session test file after applying the durable test-only patch; its postimage SHA-256 is `ad204c095ad99b827d00cf6eb9efbbf0f7fd8e601d46dafe19d78e199ae45542`. The separately updated test helper's SHA-256 is `ff289233f6c6d16840c6e8653c6dab0750ffd129293614a5b140b4365114f9fb`. Both matched the isolated combined-test copies before execution. This comparison is a path-specific byte check, not a whole-worktree status claim.

A further [fixture-only correction](word-larger-installed-20261103/default-fixture.patch) made the Collection preset select the verified existing shipped catalog by default and give `./dev/build.sh` guidance if that catalog or artifact is unavailable or invalid. The build preceding tests refreshes the catalog; the fixture's integrity check alone does not prove freshness against source. The [final integrated Session test file](word-larger-installed-20261103/final-session-test.exs) has SHA-256 `2d5a33910e95b5a7d96060b1fe68d62fb5683d90040d46370262890da8bdc342`, which was verified against the integrated worktree. With `IPSE_TEST_WORD_SHIPPED` explicitly absent, [two ordinary Collection cases and the four opt-in Word cases passed](word-larger-installed-20261103/default-fixture.log): six passed, 24 excluded, source/runtime postchecks 0. Cancellation again reported cleanup-unconfirmed. These test-only changes do not alter the installed archive or its runtime evidence.


## Preserved failures and interpretation

The earlier [large Session failure](word-larger-installed-20261103/integrated-word.log) ended in an approved guarded commit with an unknown result; that action was not replayed. A separate small instrumented Session's [allowlisted markers](word-larger-installed-20261103/guard-diagnostic-run.log) showed its own fresh-file check raised after catalog selection, source inspection and Session authorization; markers add scheduling and IO overhead, and do not independently prove the earlier large failure's cause. Source review identified that the check attempted to create a tracked task from a file-effect peer, which existing Resources task admission refused. The reviewed repair created the bounded reader from the Worker and bound its exact peer through the Session.

The first cancellation fixture [failed before cancellation](word-larger-installed-20261103/live-cancel.log) because it asserted helper arity 3 after the document-only helper became arity 4. A separate fresh attempt used the corrected assertion; it is the cleanup-unconfirmed result above. An earlier [package-input attempt](word-larger-installed-20261103/initial-package-failure-tail.txt) lacked a required archived documentation target and produced no package. The successful package used the complete tracked export instead.

## Commands and evidence

The source-tree compile and one-shot test commands, their explicit isolated paths, environment clearing and postchecks are retained in the corresponding `live-*-once.sh` files. The [package launcher](word-larger-installed-20261103/final-package-once.sh) ran `./dev/package.sh` with task-owned offline Mix, Hex and Cargo paths; the [installed launcher](word-larger-installed-20261103/final-installed-once.sh) ran the adapted verifier once against the exact archive. HOME was inherited unchanged. The catalog selection, fixture isolation and owner boundaries were source-reviewed; no OS filesystem trace was captured. A test timeout or owner loss remains unknown until cleanup is confirmed; no automatic replay is permitted.

The [evidence manifest](word-larger-installed-20261103/evidence.sha256) is SHA-256 `d419499cb5de44440ac6d03477c056179f7a14e4a8921bd41c3b5f7108f0702e`. Historical launchers contain volatile scratch paths and are evidence of the executed commands, not portable instructions. The current plan and manuals, rather than this dated receipt, own present status and operator guidance.

An independent source review examined the integrated Corpus page and continuation
path, Writer receipt and plan binding, shipped-artifact selection, source-head
guard, current-file check, and reader/effect ownership and cleanup. It found no
additional concrete security or replay blocker in that scope. The reviewer did
not independently rerun the Sessions or establish their results, and the review
does not establish filesystem isolation against arbitrary writers or complete
P31 qualification.

The documentation checker initially reported three missing test targets because
its isolated mirror did not yet contain the new test files. After staging those
files and the reviewed manual corrections, it checked 1,134 Markdown files and
9,419 local links with zero errors. The mirror was a tracked-source copy, not the
user's untracked workspace.

The staged whitespace check reports context-only blank lines in the archived
patch evidence. Those patch bytes remain unchanged for their recorded hashes;
the check passes when those historical patch files are excluded.
