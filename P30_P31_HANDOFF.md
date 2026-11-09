# P30/P31 work in progress

Updated 2026-11-09. This is a handoff of unfinished work, not milestone
acceptance. Read `AGENTS.md` and `docs/plan.md` before continuing. The objective
still includes the full P30 decision-engine and P31 knowledge/prompt-assistance
milestones, their required tests, an adversarial audit and a reviewer handoff.
`P30_P31_RESUME_HANDOFF.md` is the older chronological working log (to
2026-11-08); its entries describe their own time, not current status.

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
  runners; not classified.
- Why macOS partition 1 exceeded 60 minutes is unknown; the gated 30-minute
  evaluation children may account for it.

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
Not yet run: full source suites on either OS and hosted CI for this commit.

## Other open items

- Operator decisions given 2026-11-08: cleanup of new synthetic fixtures with
  unexpected unknown outcomes is permitted; `native_literal_lineage_retention` is
  approved as a Collection refusal; the 2,000-note recall check is authorized;
  archive overlays were removed.
- The opt-in 2,000-note integrated cohort run left one native commit outcome
  unknown in segment 55. Its root on the Linux host,
  `/tmp/ipse-native-seed-integrated-full-05d9181e6ee39f52ffcd5c4e84e2b3dc`, is
  preserved and must never be resumed. The cause is undiagnosed; a fresh-root
  rerun alone on the machine is still pending.
- P30 needs a reviewed qualified-completion record; remaining P30/P31 gates are
  in `docs/plan.md`.
- The local baseline has not been rerun since these test changes. Rerun it, and
  hosted CI on both platforms, before claiming the branch green.
- Commits `7841ceb5..308ef051` carry an AI co-author trailer contrary to
  `AGENTS.md`. On 2026-11-09 the operator had only `eb5f9cf2` reworded
  (`ca0a2d03`) with an explicitly authorized force-push; leave the others.
- The Linux host `serenity` (reachable by `ssh serenity`, checkout
  `~/projects/lexlapax/ipse`) now runs kernel 7.2.14, which is not a reviewed
  native storage profile, so `:native_storage` tests are excluded there too.
  No reviewed host currently exercises native storage.

## Reproducing the hosted Linux exclusion locally

On the reviewed Arch host, Btrfs is unqualified on kernel 7.2.11, so a temporary
directory under `/var/tmp` reproduces hosted CI:

```sh
IPSE_UNQUALIFIED_TMP=$(mktemp -d -p /var/tmp)
TMPDIR="$IPSE_UNQUALIFIED_TMP" mix test
```
