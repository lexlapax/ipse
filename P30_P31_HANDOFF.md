# P30/P31 work in progress

Updated 2026-11-09. This is a handoff of unfinished work, not milestone
acceptance. Read `AGENTS.md` and `docs/plan.md` before continuing. The objective
still includes the full P30 decision-engine and P31 knowledge/prompt-assistance
milestones, their required tests, an adversarial audit and a reviewer handoff.
`P30_P31_RESUME_HANDOFF.md` is the older chronological working log (to
2026-11-08); its entries describe their own time, not current status.

## Resume here (2026-11-12)

Branch tip before this note: `e23a77ee`, equal on the local checkout, `origin`
and serenity (`~/projects/lexlapax/ipse`). Serenity's checkout is in use by a
run; do not change its working tree until that run ends.

Working agreement (operator, 2026-11-11): no open-ended investigation agents;
land what exists; record known limits instead of diagnosing them; the operator
starts long serenity runs and reports when they end; results are read once.
`main` moves by fast-forward when the full Linux suite passes on serenity with
`IPSE_TEST_NATIVE_STORAGE=1`, the macOS baseline passes locally, hosted Linux
jobs are green, and any hosted macOS failure is on the flake list below and
passes one re-run.

Landed since `675e34fe`:

- `5f4ac89a` awaits the staging helper's exit after refused output. This was
  the `RunnerStorageTest` `cleanup_unconfirmed` failure (a cancel written into
  an exiting helper closed the Port with `:epipe`). Reproduced on macOS 21/360
  under load, 0/1,800 after. No regression test; other cancel paths keep the
  same race.
- `932b4504`, `9c7d1dcf`, `bfd8fd28`, `e23a77ee`: an unbindable reference is
  refused before journaling; Notes recall stops within one message's dependency
  byte allowance (74 literal notes or 50 accepted decisions, partial coverage
  reported). Linux pass on serenity: four files, native storage,
  `IPSE_TEST_RECALL_MANY=1`.
- `09552840` halts the document peaks harness without flushing ports (the
  64-source process lingered after writing results). Unverified until the
  250-source run ends.

Running or finished on serenity:

- Documents ladder, 250 sources: the first run stopped after 31 minutes at the
  65th fact publication (a Session admits 64 extension result sources; the
  refusal surfaced as "outcome unknown"); partial evidence
  `_build/document-peaks-250`. `3432be27` hands the publish and assemble roles
  to a new Session every 64. Rerun started by the operator 2026-11-13: log
  `~/ipse-tmp/docs-peaks-250b.log`, evidence `_build/document-peaks-250b`. Earlier rungs: `~/ipse-tmp/docs-peaks/_build/document-peaks-8`
  and `-64` (64 sources: 7,047.7 s, 97,609 host actions, 72.2 ms/action, journal
  peak 42,969,402 bytes, allocated peak 11,657,216 bytes, 0 journal refusals).
- Notes cohort at `e23a77ee`: FAILED after 5,165 s. Log
  `~/ipse-tmp/notes-cohort-e23a77ee.log`; the integrated child failed, see
  `/tmp/ipse-native-seed-integrated-full-3547f82b380e3a5ec5084284e0bf505c/integrated-full/turns-1.log`.
  The retained root is evidence: never resume, replay or modify it.
  Read once (2026-11-13): all 57 effects completed; turn 1 recall completed
  (82 actions) and its reference was admitted, but the model-phase projection
  (`managed_reference_projected` in Session
  `bedb653412dcb1c794be79720fe107a4`) returned `unavailable` for all 79
  dependencies, so the request was dispatched without any note and the
  fixture stopped. Which bound made the whole check unavailable (128 distinct
  verifications or the 5 s lease) is not determined.

Next steps, in order:

1. Read `turns-1.log` once and record why the cohort child failed.
2. When the 250-source run ends, copy its evidence into a dated
   `docs/archive/` record and update the Documents rows in `docs/plan.md` with
   the 8/64/250 numbers. Full size (1,000) stays unqualified; the operator
   decides on it with these numbers.
3. Record known limits here and in `docs/plan.md`: recall cap (74/50 by
   bytes); 42-record base ceiling per pass before deduplication, 63-record
   guarantee at 2,000 notes derived only; 5 s lease on one-literal paths;
   tool-result messages inherit the proposing message's dependency union and
   can exceed the occurrence bound after the result is journaled, leaving a
   Session that cannot be restored (not reproduced live; fix options: refuse
   the tool call before the effect, release the result as withdrawn, or bound
   tool-result occurrences like assistant messages).
4. `docs/operator/configuration.md` describes `max_steps` as 30 calls per
   turn; extension-command steps accumulate Session-wide. Correct it.
5. P30D: rebuild the Linux package on the final tip, rerun both installed
   checks, update `docs/archive/2026-11-09-p30-qualified-completion/index.md`
   items 3 and 5, then ask the operator for sign-off.
6. Research: installed end-to-end journey and P31H acceptance rows.
7. Final baselines on both hosts, whole-manual review, hosted CI, fast-forward
   `main`.

Hosted macOS flake list (undiagnosed, assumed load-related): `ExtensionLabTest`,
`HeaderDeadlineTest`, `KnowledgeEvaluationSessionTest`,
`Runner.TransactionTest`, `Extension.TextTest`,
`KnowledgeEvaluationRunnerIsolationTest` (and its nested
`KnowledgeEvaluationRunnerTest` cases), `Extension.FeedsTest`,
`Session.DraftResponseLimitsTest`, `Extension.ContributionsTest`. Run
42972305666 on `5f4ac89a` had all Linux jobs green and macOS 1/4 red in the
last two.

## Where things stand

- Branch `codex/p30-p31`. `main` was fast-forwarded to `751e3724` (no
  force-push). This handoff commit is on the branch only; it has not been merged
  to `main`.
- Since the previous handoff (`29cb7ac9`):
  - `6e41801b` removed operator-terminal input contention (per-terminal lock
    with bounded wait; `Ipse.Runner.TerminalInput` pauses the OTP 27 VM stdin
    reader).
  - `b6df1b11` restored fail-closed expectations in three native-loss collection
    tests and fixed a replay-cache receive timeout. Runtime unchanged.
  - `b520dde5` recorded the first passing local whole-source baseline at
    `b6df1b11`: 4,665 tests, 0 failures on Arch Linux kernel 7.2.11, tmpfs
    `/tmp` ([record](docs/archive/2026-11-08-whole-source-baseline/index.md)).
  - `751e3724` excludes tests tagged `:native_storage` when the test temporary
    directory is not a reviewed native storage profile
    (`native/ipse-storage-profile.rs` admits only kernel 7.2.10 Btrfs/tmpfs and
    exactly `7.2.11-arch1-1` x86_64 tmpfs). `test/test_helper.exs` probes the
    pinned helper; `IPSE_TEST_NATIVE_STORAGE=1` makes an unreviewed host fatal.
    Hosted Ubuntu CI then passed all four source partitions and the platform job
    (run 42566465912). Native storage is covered only on a reviewed host.
- Hosted macOS CI is still red at `751e3724`: about 60 failures in partitions
  2-4, partition 1 hit the 60-minute job limit, and the platform job failed in
  `dev/verify.exs installed package` (memory `state.get` outcome unknown).
  `main` was green on macOS at `fbb207d5`, so these came in with this branch.

## macOS fixes (`eabff5e7` and its follow-up)

Checked locally on macOS (Darwin 25.6.0, arm64) with Elixir 1.20.5 on OTP 29;
hosted CI uses OTP 27. All 24 test files changed in `eabff5e7` pass (315 tests,
47 skipped, 49 excluded) apart from the terminal-input pair fixed below. Every
other `operator_pty` user passes (43 run; most are Linux-only or
`:native_storage`). Replaying the CI platform job after the build step, 56 of
62 commands pass, including `./bin/ipse demo` and the installed package,
model-service, extension, model-call, embedding, saved-result, document and
non-MCP knowledge verifiers. The six failures are the source and installed
`mcp`, `knowledge-mcp` and `knowledge-research` verifiers, all from decision 1
below: `Ipse.MCP.StdioTransport` exits during `initialize`, surfacing as a
GenServer crash rather than a clear refusal. The full source suite has not run
on the Mac.

Follow-up fixes found on the Mac:

- `test/support/operator_pty.rs` now makes the PTY the controlling terminal of
  the child's session (`setsid` + `TIOCSCTTY`). Without one, macOS gives the
  slave to the first new session leader the VM spawns (erts port children call
  `setsid`) and revokes it when that child exits, so the VM's next write fails
  with `EIO`. This was the `terminal_input_test` "child exits after the first
  line" failure; a real login terminal is not affected.
- OTP 28 and later register `user_drv_reader` but read only on request, so the
  unclaimed control now decides eagerness by OTP release (eager below 28)
  instead of by the registered name. Verified on OTP 27.3.4 (eager branch) and
  OTP 29 locally.
- `dev/verify-release.exs` handoff-resume check reads the journal header's
  `release_receipt_layout`, like the other verifiers, so macOS's legacy layout
  passes the installed package check.

Most failures were Linux-only facilities whose tests lacked a platform gate.
The runtime fails closed off Linux by design:

- Native transaction commands for session acceptance, retained shares, source
  retention and owner-control import compile only on Linux
  (`native/ipse-transaction.rs` ~1107-1530; `native/ipse-runner.rs:42-50`). On
  macOS the helper exits and Elixir reports `{:unknown, :transaction_lost}`.
  `Runner.open_owner_control`, `share_source_lock` and `protected_header_lock`
  refuse off Linux (`lib/ipse/runner.ex`). Gated: `stored_sources_test`,
  `transaction_retained_share_test`, `management_share_candidate_test` (macOS
  now asserts the refusal), `pilot_reservation_test` (one test asserts the macOS
  refusal).
- Rust fixtures in `transaction_test`, `transaction_optional_read_test`,
  `transaction_framing_test` and `project_identity_test` included
  `ipse-lease-transfer.rs` unconditionally; it uses Linux-only socket APIs and
  broke `setup_all` on macOS. Now `#[cfg(target_os="linux")]`, matching
  `native/ipse-runner.rs`.
- Fresh Sessions use the release-receipt journal layout only on Linux
  (`lib/ipse/session.ex` ~8069-8077); macOS uses the legacy layout (no
  `session_release_owner_started`, close confirms cleanup, `release_claim`
  unknown). Expectations made layout-aware rather than skipped: `feeds_test`,
  `budget_test`, `profile_integration_test`, `router_integration_test`,
  `saved_test`, `workspace_resources_test`, `mcp/http_test`, `mcp/session_test`,
  `document_acquisition_session_test`, `source_origin_test`, and the shipped
  demos `priv/demo/usage.exs`, `extensions.exs`, `subagents.exs` (used by
  `dev/verify-release.exs`), plus `dev/verification/knowledge.exs`.
- Managed stdio and managed shell admission are refused on macOS
  (`native/ipse-stdio.rs:420-421`, `native/ipse-runner.rs:118-119`). Gated:
  stdio variants of `mcp_call_session_test`, `stdio_admission_test`, three
  `invocation_test` workflow-shell tests, two `dev/evaluation/runner_test`
  isolation tests (their research row uses managed MCP stdio).
- `dev/verification/runtime.exs` now canonicalizes the verifier's temporary root
  with `pwd -P`. Native transaction acquire refuses symlinked path components,
  and macOS `/var` is a symlink, so extension `state.get` failed and was reported
  unknown in the installed package check.
- Timeouts raised for `storage_continuation_test` (180 s) and
  `collection_directory_test` (300 s); stack traces showed slow work, not hangs.

Hosted run 42640023098 (`eb5f9cf2`, reworded as `ca0a2d03`): Ubuntu all green, including the PTY
driver change. macOS partition 1 now finishes in time; its six failures
(`protected_lease_test` x2, `runtime_lifecycle_test` x2,
`workspace_integration_test`, `decision_session_test`) are fixed in the next
commit and pass locally. The platform job reaches the MCP verifier (decision 1).

Not resolved:
- Five macOS failures seen only on hosted runners; each passes locally in
  isolation and as whole files, on OTP 29 and twice on OTP 27.3.4:
  `test/dev/evaluation/session_test.exs:161` (bad_open/bad_append get
  `{:command_failed, "failed"}` with a 1 s driver timeout),
  `test/ipse/extension/invocation_test.exs:2921` (session gone before
  `Session.info`), `test/ipse/extension/services_test.exs:359` (no `:done`
  within 3 s), `test/ipse/runner_storage_test.exs:43` (got
  `{:cleanup_unconfirmed, :protected_staging_write_unavailable}`; this file's
  partition passed at `eabff5e7`). Likely load or timing on 3-core hosted
  runners; not classified. In run 42657426801 (`8f8753f8`) macOS partitions 3
  and 4 passed `services_test` and `runner_storage_test`; partition 2
  (`session_test`, `invocation_test`) did not run.
- macOS partition 1 finished within the limit in runs 42640023098 and
  42657426801; the earlier 60-minute overrun did not recur.
- Also intermittent on hosted macOS only, passing locally and on the next run:
  `test/ipse/session/draft_acceptance_test.exs:250` (operator channel stopped)
  and the installed lab proof (`extension_admission_refused`, possibly the
  5 s `Registry.revalidate` bound in `Ipse.Session.start_link`), both in run
  42651877515.

## macOS regressions: operator decisions (2026-11-09)

These were product regressions on macOS since `fbb207d5` (from `86c990c6`
onward). The operator decided, and the follow-up commit implements:

1. Extension `mcp.call` over stdio: implemented. `native/ipse-stdio.rs` no
   longer refuses `--admitted-stdio` on macOS; the start-deadline check runs in
   `pre_exec` on every Unix (it reports errors without allocating after fork).
2. Extension workflow shell: implemented the same way for `--admitted-shell` in
   `native/ipse-runner.rs`. The Linux-only test gates for managed stdio/shell
   were removed (`stdio_admission_test`, `protected_lease_test`,
   `mcp_call_session_test`, three `invocation_test` and two
   `dev/evaluation/runner_test` tests).
3. Extension state under a symlinked `IPSE_HOME`: both parts implemented.
   `Ipse.Config.home/1` resolves symlinks at `Config.runtime/2` admission and
   at Session start. `Ipse.Extension.State` returns the known `failed` outcome
   `{"code":"extension_state_unavailable"}` for any refusal before the
   namespace lock is held (unsafe directory or lock file, busy lock, symlinked
   ancestor, definite acquire error) and accepts it in outcome validation. The
   verifier's `pwd -P` temp-root workaround is removed, so macOS installed
   checks now run under the symlinked `/var`; the memory and documents
   verifiers use `Ipse.Config.home/1` where they bypass a session.
4. v0.1.0 OTP 27 dropped-keystroke exposure: not exposed; no release note.
   v0.1.0 bundles OTP 27 (eager reader), but its source has no native terminal
   reader (`native/ipse-operator.rs` came later) and no Port inherits the
   terminal (`:nouse_stdio` absent, shell stdin null), so the VM was the only
   terminal reader. Established from source; the Linux v0.1.0 bundle was not run.

Verified: macOS local (OTP 29) all ungated managed shell/stdio files (115
tests), state/config files, and a full CI platform-job replay with all 62
commands passing (PDF build). Linux on `serenity` (Arch kernel 7.2.14): build,
all 88 native runner tests, and the 15 affected files (191 tests, 0 failures).
Full Linux source suite on `serenity` at `b6351f62`: 3,489 of 3,490 passed;
the one failure (witnessed draft lineage accepting the new failed state
outcome) is fixed in `8f8753f8`. Hosted run 42657426801 at `8f8753f8`: every
Ubuntu job and the macOS platform job passed (all installed proofs, including
MCP, under the symlinked `/var`); macOS partitions 1 and 3 passed; partition 4
failed only `test/ipse/mcp/catalog_session_test.exs:525` on a 5 s `:done`
wait (now 15 s, matching the file's fresh-VM catalog budget); partition 2 was
never acquired by a hosted runner (GitHub macOS capacity), as was partition 1
in run 42651877515. A full macOS source suite has not run anywhere.
Hosted run 42663715255 at `72ee4e63` then passed every Ubuntu and macOS job.

## Verification after the second decisions (2026-11-09)

- Kernel `7.2.14-arch1-1` tmpfs admitted; record in
  `docs/archive/2026-11-09-kernel-7214-tmpfs-profile/`. Full Linux suite on
  serenity with `IPSE_TEST_NATIVE_STORAGE=1`: 4,399 passed, 0 failures.
- First full local macOS suite (OTP 29): 3,327 of 3,329. `ollama_context_test`
  timed out under load and passes alone; `release_test:404` exposed macOS tar
  AppleDouble `._*` entries (every file doubled in a locally built package),
  fixed in `7736b5db` with `COPYFILE_DISABLE=1`.

## Operator decisions (2026-11-09, second round)

- Native storage: admit exact `7.2.14-arch1-1` x86_64 tmpfs (serenity) like
  the 7.2.11 review; Btrfs stays refused.
- P30: independent subagent review of a qualified-completion record, then the
  operator signs off before the plan calls P30 complete.
- Lanes in order: Notes (fresh 2,000-note rerun with populated recall and the
  integrated day), Documents, Research. Fast-forward `main` (no force) once the
  local baselines and hosted CI are green.
- Documents: keep the shared group layout (Root2) at full size, split
  build/finalization across Sessions at points with no pending write (reserve
  each document invocation's worst-case journal space; stop cleanly with the
  existing continuation token), **and** fold source heads into catalog pages
  (Root3/head v3) now. Old version-4/5 roots are refused with
  `document_layout_rebuild_required`; the operator rebuilds from sources (no
  in-place fold, no dual-layout reader). Retain exactly one previous generation; replaced blocks
  stay until explicit cleanup after selection behind the maintenance barrier;
  one initial build plus one rebuild per Collection, documented as the limit.
- P30 record (third round): consent disclosures accepted as a limitation;
  frozen selection abstention and assessment whole-task cost bars added;
  P30D closes with the same scripted journeys on current source (port the
  selection checkpoint to a current verifier, rerun it and
  `pending_shadow_installed.exs` on a current Linux package). Draft record:
  `docs/archive/2026-11-09-p30-qualified-completion/`, awaiting sign-off.
- Documents (fourth round): Root3 head folding is **dropped**. Without the
  separate head record a source cannot be found by key; scanning costs about
  330 MB of journal per 1,000-source build and a key index about 5,000
  operations (more than the ~4,500 left). Keep Root2 with the multi-Session
  split and explicit cleanup; record Root3 as future work. Rebuilding a
  near-capacity Collection uses reviewed retire-then-rebuild with existing
  document retirement; add a test that retirement frees the keys. No cleanup
  operation for replaced blocks exists yet; it must be built.
- Cohort overlap: the fresh 2,000-note run (root
  `/tmp/ipse-native-seed-integrated-full-02a7af4db6f3072e6ce6ab71dd8e14af`,
  started 15:07 PST) overlapped from about 15:20 to 15:47 with selection
  verifier runs in `~/scratch/ipse-p30d-sel` during its seed phase. Seed-phase
  timing is not a clean single-workload measurement.
- Research (P31H): fence registered inference routes for provided-only source
  sets with a host-computed complete-set digest journaled before approval and
  rechecked at send, release and saved restore; ordinary per-call approval keeps
  its documented behavior; saved guarded-result restore stays refused; no extra
  native review of the set.

## Other open items

- Operator decisions given 2026-11-08: cleanup of new synthetic fixtures with
  unexpected unknown outcomes is permitted; `native_literal_lineage_retention` is
  approved as a Collection refusal; the 2,000-note recall check is authorized;
  archive overlays were removed.
- The opt-in 2,000-note integrated cohort run left one native commit outcome
  unknown in segment 55. Its root on the Linux host,
  `/tmp/ipse-native-seed-integrated-full-05d9181e6ee39f52ffcd5c4e84e2b3dc`, is
  preserved and must never be resumed. The cause is undiagnosed.
- Fresh-root reruns on 2026-11-09, alone on serenity: the first (root
  `...-02a7af4db6f3072e6ce6ab71dd8e14af`) started 23:07 UTC and failed the
  turnover precondition (the seed crossed UTC midnight); the test now refuses a
  start within six hours of midnight. The second (root
  `/tmp/ipse-native-seed-integrated-full-b8378dc21c812a5610f502b7198cce94`,
  retained, never resume) seeded 2,000 notes and committed effects 1–14
  (about 9 s each), then turn 1 failed: "synthetic provider request not
  confirmed" after 120 s. Populated seed recall had made 42 serial Collection
  `get` reads by then, each about 2.0 s at the start of the turn and growing
  about 50 ms per prior read (4.2 s by read 42), with constant frame sizes.
  At the ~126-read bound that is roughly 10 minutes of recall per turn. This
  is a recall performance defect, not only a fixture timeout; no unknown
  native outcome was left. The retained copies of the two earlier roots under
  `~/ipse-tmp` on serenity show the same shape (14 effect results, no turn
  result, 8 reads in about 24 s on 2026-11-03): no cohort run has completed
  turn 1.
- Recall read cost, measured on serenity with a 33-source fixture. Each read
  loaded and validated the whole Collection about six times, installed the
  read view about five times, restored each new source journal and ran five
  consent transactions; each worker input also re-verifies every dependency
  accumulated so far, which is the per-read growth. `Ipse.Extension.ValidatedMemo`
  (one validated value per protected owner slot, always after a fresh read and
  hash check of the protected bytes) cut a `get` from about 160 ms to 45 ms, a
  consent transaction from 37 ms to 10 ms, a source restore from 650 ms to
  340 ms and the fixture turn from 31.0 s to 21.8 s; growth fell from about
  25 ms to 16 ms per prior read. Extrapolated to 2,000 notes that is still
  about six minutes for a 126-read turn. On 2026-11-10 the operator chose to
  remove the growth while keeping full recall: when the Collection root
  witness is unchanged since a record was observed, later inputs in the same
  invocation need not re-observe it; expiry and source checks stay. That
  change is not implemented yet, and the cohort has not been rerun.
- P30 needs a reviewed qualified-completion record; remaining P30/P31 gates are
  in `docs/plan.md`.
- Hosted CI run 42761397253 is green on both platforms at `b76d8497` after one
  rerun of two macOS source shards. The preset admission check had failed on
  both platforms because it did not expect `investigate_provided`; `b76d8497`
  fixes that.
- Full local runs: macOS at `b76d8497` passed 3,357 of 3,358 tests and Linux
  with native storage at the recall memo tip passed 4,438 of 4,439. The one
  failure on both was `CollectionCompletedBackupIsolationTest`, caused by
  `projection_capacity_test.exs` loading `Projection` into the test VM at file
  load; hosted partitions happened to separate the two files. The capacity
  test now compiles the module for its own case and removes it afterwards.
  Rerun the full baseline on both hosts before fast-forwarding `main`.
- macOS source shards on hosted CI fail intermittently on timing-sensitive
  tests, a different one each run: `runner_storage_backpressure_test.exs:41`
  (cleanup unconfirmed), `test/dev/verification/lab_test.exs:5` (admission
  refused under stress), `draft_acceptance_test.exs:111` (timeout) and
  `runner/transaction_deadline_test.exs:7` (write deadline elapsed). Each
  passes locally and on rerun. Treat this as a CI reliability defect to fix
  separately; do not widen deadlines without diagnosing the runner load.
- Commits `7841ceb5..308ef051` carry an AI co-author trailer contrary to
  `AGENTS.md`. On 2026-11-09 the operator had only `eb5f9cf2` reworded
  (`ca0a2d03`) with an explicitly authorized force-push; leave the others.
- The Linux host `serenity` (reachable by `ssh serenity`, checkout
  `~/projects/lexlapax/ipse`) runs kernel 7.2.14, admitted as a reviewed tmpfs
  profile on 2026-11-09. At `adfe6773` the provided-set fence session test, both
  inference dispatch tests and the document draft native capacity test pass
  there with `IPSE_TEST_NATIVE_STORAGE=1` (33 tests). At `453d2723`, after the
  second review's fixes, the fence unit and session tests and the inference
  dispatch test pass there (33 tests), including the registered send and the
  send-to-release transition, which report NOT RUN on macOS.
  At `7aa3d615` the built Research package runs `investigate_provided` through
  a Session under the fence there, with and without its model reranker
  (`research_provided_fence_session_test.exs`, 4 tests); the registered rerank
  reports NOT RUN on macOS. An empty or oversized source list is refused by the
  package's argument schema before the host's set capture.
- Documents (2026-11-10): the operator chose a measurement ladder of 8, 64 and
  250 sources before any full-size run. No harness existed that drives a sized
  build through a Session on native storage; one is being built. Full size
  stays unqualified until the ladder's measured per-action cost and peaks
  exist. Decided by the implementing session: the per-source fact route
  (publish, assemble, append), one rebuild with replaced facts, and Session
  handoff only where no write is pending.
- The provided-set fence's last check before a request leaves runs before the
  connection opens. A request can therefore cross a source's transition on the
  wire; its output and result are withheld. Bounding the send itself would
  need a transport change shared with the document path and is not planned.

## Reproducing the hosted Linux exclusion locally

On the reviewed Arch host, Btrfs is unqualified on kernel 7.2.11, so a temporary
directory under `/var/tmp` reproduces hosted CI:

```sh
IPSE_UNQUALIFIED_TMP=$(mktemp -d -p /var/tmp)
TMPDIR="$IPSE_UNQUALIFIED_TMP" mix test
```
