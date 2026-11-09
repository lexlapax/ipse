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

## macOS fixes in this commit (not yet run on macOS)

Checked only on Linux: format, warnings-as-errors compile, compilation of all
4,665 tests, each changed test file with `--max-cases 2`, and the subagents and
extensions demos. None of the macOS branches has executed. First job on the Mac:
run the changed test files below and the installed package verification, then
push and watch hosted CI.

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

Not resolved:
- `test/ipse/runner/terminal_input_test.exs` (2 tests): the PTY child VM exits
  non-zero right after the first typed line on macOS, in claimed and unclaimed
  modes. Unclassified; needs a Mac to diagnose.
- Why macOS partition 1 exceeded 60 minutes is unknown; the gated 30-minute
  evaluation children may account for it.

## Decisions waiting for the user

These are product regressions on macOS since `fbb207d5` (from `86c990c6`
onward). The commit gates or adapts their tests; it does not restore behavior.

1. Extension `mcp.call` over stdio no longer works on macOS: managed stdio
   startup is refused before launch. Either implement and verify native start
   deadlines on macOS or document the limit in `docs/operator/mcp.md`.
2. Extension workflow shell (`tool.call` with managed admission) is refused on
   macOS and reported as an unknown outcome rather than a clear refusal.
3. Extension state refuses any `IPSE_HOME` with a symlinked ancestor (such as
   macOS `/tmp` or `/var`) and reports unknown. Options: canonicalize the root at
   config admission, or map pre-effect acquire refusals to a failed outcome with
   `extension_state_unavailable`.

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
- OTP 27 dropped-keystroke fix (`6e41801b`): whether released v0.1.0 is exposed
  is unverified, so `docs/releases/v0.1.0.md` is unchanged. Ask the user.
- The local baseline has not been rerun since these test changes. Rerun it, and
  hosted CI on both platforms, before claiming the branch green.
- Commits `7841ceb5..308ef051` carry an AI co-author trailer contrary to
  `AGENTS.md`; they are pushed and must not be rewritten.

## Reproducing the hosted Linux exclusion locally

On the reviewed Arch host, Btrfs is unqualified on kernel 7.2.11, so a temporary
directory under `/var/tmp` reproduces hosted CI:

```sh
IPSE_UNQUALIFIED_TMP=$(mktemp -d -p /var/tmp)
TMPDIR="$IPSE_UNQUALIFIED_TMP" mix test
```
