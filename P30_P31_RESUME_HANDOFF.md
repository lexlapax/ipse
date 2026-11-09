# P30/P31 restart handoff

Saved 2026-11-07. This is a working handoff, not a milestone acceptance record.
Read `AGENTS.md` and `docs/plan.md` before resuming. The active objective is to
implement the full P30 decision-engine and P31 knowledge/prompt-assistance
milestones, run their required tests, conduct an adversarial post-implementation
audit and prepare a reviewer handoff. The user restarted the goal; it is active,
not complete. The update below supersedes older state details in this handoff.

## Current restart state — 2026-11-08

The entries below this section are a chronological working log. Their statements
that old sessions are active or tests are pending describe their original time;
they are not current status. No execution session is carried over by this file.
Check the host and the named receipts before resuming a test or touching scratch.

- The user paused the goal and requested a handoff commit. `codex/p30-p31` is at
  `29cb7ac9`, pushed to `origin`, containing the P30/P31 project work in progress
  and the previously staged Research archive. The goal is paused, not complete;
  see the committed `P30_P31_HANDOFF.md`. Preserve unrelated local fixtures.
- An earlier current-source offline build, warnings-as-errors compile, Elixir
  1.18/OTP 27 formatter, credential-free demo and scoped docs check passed; that
  build predates the latest retirement integration and is not a final-source
  receipt. The last complete filtered full test run failed one case on an older
  candidate; no passing final integrated baseline exists. The full filtered run
  remains disabled while the user's decision on cleanup after unexpected
  synthetic unknowns is pending.
- The latest focused receipts include nine diagnosis/resume controls, 21 P30
  fence/decision controls, 13 P31 provider projection/Session controls, eight
  Graph worker controls and a fresh P30 synthetic materializer. Their source
  compositions differ and none proves whole-milestone acceptance.
- The fresh retirement abort diagnostic failed with `cleanup_unconfirmed`; its
  synthetic fixture and prior unknowns are retained. The P31H Research review and
  clock work is isolated and disabled; native review, replay, send and delivery
  remain unqualified. The user declined retained-notebook recall and equivalent
  replacement consumers; do not run them.
- A separate retirement candidate based on `d9014d1f` has a production build
  and individually passing native two-lock, identity-refusal, Session success,
  and Session-death-before/after-switch controls. Their test source overlays
  differ; the combined 21-file candidate has not yet passed a combined build or
  tests. Independent review found two corpus manual recovery/diagnostic wording
  omissions; correct them before final verification. The previously failed
  abort remains unconfirmed and is not resolved by these fresh controls.
- An accidental failed snapshot copied hidden historical directories into
  `_build/verification/current-root-build-20261108-01/source`. Its original
  sources were unchanged; the copy contains lock-named entries and remains
  preserved pending safe classification. Never follow its symlinks.
- The latest local work and restart patch are saved under `~/ipse-tmp`; untracked
  files are not included in `restart-unstaged-latest.patch`. In particular the
  new P30 inventory test is saved separately there. Read the final log entries
  for exact paths, checksums, results and qualified limitations.

## Historical rolling entries — superseded by current state

- Registry actual-CLI dry census session 62282 completed exit 0: one selected,
  zero skipped, 61 excluded; no test body ran. The host process/open-file/lock
  checks found no remaining recorded owners at inspection. Automatic approval
  review rejected a combined postflight command because it included listing
  the NEW scratch tmp directory outside the accepted fixture boundary. Do not
  bypass that rejection or inspect the rejected directory; preserve it intact.
  This leaves its contents/effects uninspected. Only the separately audited
  duplicate source/docs was removed. Identity/seal review and space cleanup are
  in progress before any CLI test; preserve all prior unknowns/locks.
- Registry-corrected actual-CLI one-test dry census is active in exec session
  `62282`, launcher
  `_build/verification/diagnose-resume-ninecase-registry-launcher-20261108-01/run-cli-census.enabled.sh`.
  Core 6/6 passed and independent postflight found no matching live groups/open
  files/operator locks/listeners. Its synthetic Git/build were hash/node
  preserved in `_build/verification/diagnose-registry-core-suite-preservation-20261108-01/`;
  only original non-lock copies and audited duplicate source were removed.
  Original compile locks, symlinks, helpers, telemetry, tmp/fixtures, unknowns
  and receipts remain; scratch Git requires archive restoration. Free tmpfs
  before dispatch was 2,150,109,184 bytes. Poll and review exact CLI census;
  no CLI test body has run yet.
- Registry-corrected diagnosis/resume core suite session 77138 completed exit
  0; outer guard records 6 passed, 0 failed/invalid/skipped, 114 excluded and
  no early stop. Independent host/fixture postflight is in progress. The actual
  CLI entry-point one-case and managed-withheld two-case stages remain unrun;
  do not claim full diagnosis/resume increment or goal completion yet.
- Registry-corrected nine-case CORE-six actual suite is active in exec session
  `77138`, enabled launcher
  `_build/verification/diagnose-resume-ninecase-registry-launcher-20261108-01/run-core-suite.enabled.sh`.
  Reviewed census manifest SHA
  `14b20560ef9258e13d8a30388de8b62e57c99dd454834564ddcc0cb1e1700f47`.
  Before dispatch invalid-census Git/build were independently hash/node
  preserved at `_build/verification/diagnose-core-invalid-census-preservation-20261108-01/`;
  only original non-lock copies plus audited duplicate source were removed.
  Original locks, symlinks, helpers, telemetry, fixture roots, unknowns and
  receipts remain. Free tmpfs was 2,159,570,944 bytes before launch. Poll and
  independently audit before any CLI/managed stages; no tests passed yet.
- Registry-corrected nine-case source is
  `_build/verification/diagnose-resume-ninecase-registry-fix-20261108-01/source`,
  source manifest SHA
  `25395f7e675a62d909410d83f3f915b1748637012a804a0957ef24759cc3ef22`.
  It fixes only the previously wrong CLI-test alias with `Elixir.Registry`;
  independent source/launcher review and 1.18 formatting pass, no tests yet.
  Its fresh core-six dry census is ACTIVE in exec session `92048`, launcher
  `_build/verification/diagnose-resume-ninecase-registry-launcher-20261108-01/run-core-census.enabled.sh`.
  The invalid earlier core census Git and build were copied to
  `_build/verification/diagnose-core-invalid-census-preservation-20261108-01/`
  and independently hash/node verified before only copied non-lock and audited
  duplicate files were removed. Original lock inodes, symlinks, helpers,
  telemetry, fixture roots, prior unknowns and receipts remain; its scratch Git
  needs archive restoration to reuse. Free tmpfs was 2,157,662,208 before
  dispatch. Poll, review exact census and host cleanup before actual tests.
- Core-six dry census session 90422 completed (6 selected/0 skipped/114
  excluded), but its dry log exposed a deterministic defect in the separate
  CLI test: `Registry.lookup(Ipse.Registry, ...)` resolves to the aliased
  extension Registry rather than `Elixir.Registry`. Do not run that nine-case
  candidate. A new isolated test-only correction is being prepared; the census
  is evidence only for the invalid candidate. No test bodies ran. Host audit/
  scratch cleanup remains pending; no old fixtures were touched.
- Nine-case quiescence candidate CORE-six dry census is active in exec session
  `90422`, enabled launcher
  `_build/verification/diagnose-resume-ninecase-quiescence-launcher-20261108-01/run-core-census.enabled.sh`.
  It uses fresh offline scratch, not prior fixtures. Before dispatch four
  completed-run synthetic Git trees and one baseline build were copied to
  `_build/verification/diagnose-baseline-completed-preservation-20261108-01/`
  and independently hash/node verified. Only original non-lock copies and
  audited duplicate source were removed; original lock inodes, symlinks,
  helpers, telemetry, tmp/fixtures, old unknowns and receipts remain. Original
  scratch Git trees require archive restoration to be usable. Free tmpfs was
  2,167,279,616 bytes before dispatch. Poll census and independently review
  exact identities/exclusions and host cleanup before any test bodies.
- Finished filtered baseline independent postflight is
  `_build/verification/diagnose-head-formatted-baseline-launcher-20261107-01/suite-04/independent-postflight-20261108.md`.
  Selected/skipped/excluded lists match reviewed 4,338/131/132, and guard PID
  matched a live owner. Host checks found no matching groups/open files/locks/
  listeners at inspection. Fresh tmp has 445 JSONL and 2,358 lock files, 40
  JSONL matching a simple unknown marker; no full effect reconciliation is
  claimed. All fixtures/journals/locks/old unknowns remain. Only audited
  duplicate source/docs was removed; free tmpfs is ~1.74 GB, below the 2 GiB
  next-run threshold. Further synthetic Git/build archival and duplicate cleanup
  are under independent review. The run remains failed, 4,337 pass/1 fail.
- Formatted filtered HEAD diagnosis baseline session 17848 completed with
  test exit 2 and launcher exit 1: guard records 4,337 passed, one failed
  (known `/run` native-helper boundary fixture), zero invalid, 131 skipped,
  132 excluded, no failed modules or early stop. This is a completed FAILING
  filtered run, not a pass. Build, Elixir1.18/OTP27 format and warnings-as-errors
  compile passed; demo was not reached. Launcher cleanup remains unconfirmed
  pending independent host/fixture postflight. The boundary-corrected candidate
  and further pending-question/resume-warning changes still require fresh checks.
- Independently reviewed disabled quiescence-candidate 6/1/2 launchers are at
  `_build/verification/diagnose-resume-ninecase-quiescence-launcher-20261108-01/`.
  Exact source SHA `0eec74955085c3620497ce8daae5b9cb823841495156852cd4682dca91fcaac8`;
  shifted source locations and guard/Rebar/paths match. Each stage still needs
  a fresh reviewed identity/skip census, runtime, host/effect audit; no tests
  have run. The managed tracked-owner/OS-lock proof does not prove detached work
  absent. Do not use earlier unsafe launchers or run concurrently with baseline.
- Nine-case resume candidate now includes independently reviewed test-only
  failure retention and managed journal quiescence at
  `_build/verification/diagnose-resume-ninecase-quiescence-20261108-01/source`,
  source SHA `0eec74955085c3620497ce8daae5b9cb823841495156852cd4682dca91fcaac8`.
  Core/managed failure paths retain synthetic roots and avoid close retries;
  managed cases wait for owner/writer/tracked processes and normal guard exit,
  reacquire the existing OS lock and hold it during the test journal rewrite,
  then require unlock. This is not proof about detached OS effects. Full
  Elixir1.18 format check passed; runtime tests are unrun. Fresh 6/1/2 launchers
  and exact identity review are being prepared; do not use earlier unsafe
  nine-case launchers. Baseline 17848 remains active with one known failure.
- Disabled nine-case diagnosis/resume launchers are in
  `_build/verification/diagnose-resume-ninecase-launcher-20261108-01/` for
  exact formatted CLI-control source `efb7bedb7203533445facba317d084152fb4a28028a2bbb2d3c740392d7e1d52`.
  They separate core six, actual CLI one and managed-withheld two into census
  and suite stages with fresh roots and reviewed identity gates. No stage ran.
  Independent launcher/managed cleanup review is pending; these must not run
  alongside active baseline. Original real CLI compatibility is unverified.
- Real CLI control revision 03 passed independent static review after fixing
  namespace binding, global cleanup ordering and boundary-time stderr snapshots.
  Formatted source is
  `_build/verification/diagnose-unknown-resume-cli-control-formatted-20261108-01/source`,
  manifest SHA-256
  `efb7bedb7203533445facba317d084152fb4a28028a2bbb2d3c740392d7e1d52`.
  Elixir1.18/OTP27 full format check passed; runtime/config behavior remains
  untested. Nine-case plan at sibling `PLAN.md` SHA
  `4984cc1b74403d250a21eeda7997f4d5eaf611201dbdb98d1f1d8b21b225184f`
  includes saved diagnosis, pending question, actual CLI interactive/headless,
  no-replay/privacy and two managed-withheld cases. Need exact fresh census,
  fixture/cleanup review, tests and independent audit after baseline. Root's
  earlier pending-question false positive is not yet fixed in the worktree.
- Independent CLI-control review found the first draft corrupted a namespace
  from a different config path than the real CLI, and could delete synthetic
  evidence after unconfirmed failure. Revised isolated draft is
  `_build/verification/diagnose-unknown-resume-cli-control-20261108-02/source`,
  source SHA `8cc6d6adc892ae7739768b1b6df54975724a3f5db5d927bdef6fb642a0b1af10`.
  It derives identity from the actual seed Session, cross-checks action identity
  and namespace, and retains the synthetic root/artifact on uncertain failure.
  No runtime/format test ran; revised cleanup, actual CLI config compatibility
  and warning ordering remain under independent review.
- An isolated draft real CLI entry-point control is at
  `_build/verification/diagnose-unknown-resume-cli-control-20261108-01/source`,
  source manifest SHA
  `9629a4be8852fdece64c1e71dafb5e63fe6a8a2093e0c420babb599dad912bf3`.
  It changes only an invocation test on resume-warning v02: CLI-created seed,
  real private synthetic config/artifact, interactive and headless resumes,
  warning ordering, privacy, no old action replay and confirmed-close checks.
  It is unformatted/unrun; config compatibility, race and cleanup are under
  independent review. No claim that the CLI entry control passes.
- Resume-warning wording revision 02 is
  `_build/verification/diagnose-unknown-resume-warning-20261108-02/source`,
  manifest SHA `10ea78e3a203f99370d86484286ecdab03f72a65af1e94aba8f1e08273751964`.
  It says unknown extension actions may include an effect and describes a
  withheld question as unable to be safely restored/displayed, without claiming
  managed context is unavailable. It is untested/unformatted. Existing tests
  call the warning helper with real resumed Session.info but do not exercise
  actual CLI startup. A bounded fresh synthetic interactive/headless entry-point
  control is being explored using existing CLI/extension fixtures; stop rather
  than fabricate config or introduce a framework if it becomes substantially
  complex. Full Saved/replay and old unknown preservation remain required.
- Isolated automatic resume-warning candidate is
  `_build/verification/diagnose-unknown-resume-warning-20261108-01/source`,
  based on formatted pending-question fix, manifest SHA-256
  `aa76d6cdf543fbfbed7c15f5b2722b729bc8ab243a9d6ae1ae7c4d9cbcf7cd35`.
  It reuses validated Saved count, exposes a labelled startup snapshot in
  Session.info, prints content-free resume/withheld-question warnings through
  CLI, and adds focused no-replay/question/privacy tests and guidance. No
  journal result is fabricated. Format check passed; no runtime tests ran.
  Independent adversarial review pending. Existing CLI tests call the exact
  helper with Session.info but do not yet drive end-to-end CLI resume.
- Disabled pending-question-focused launchers are in
  `_build/verification/diagnose-unknown-pending-question-focused-20261108-01/`:
  census SHA `5836bad876bc425794c87b25189b46c99ecba54cb9b8e589f366b3547fe82901`,
  suite SHA `8e68500034665002e7f2d5fbbe3912b4cf3b51437d220759567fdc918f7845e0`.
  Four selected cases include prior diagnosis controls plus new valid-pending,
  intent-only, cleared/unknown/malformed/answered checks. Exact formatted source
  manifest `427ecb16a5ad4e9705997f22cc76a6be3fc9506fe5330722649aa6aca293ee82`
  was independently verified as formatting-only vs reviewed fix. Launcher
  review, fresh census, runtime tests, postflight and root reconciliation remain;
  do not run concurrently with active baseline or claim the earlier root count
  handles pending questions correctly.
- Pending-question fix candidate was independently reviewed, then formatted
  on Elixir1.18/OTP27 at
  `_build/verification/diagnose-unknown-pending-question-formatted-20261108-01/source`;
  source manifest SHA-256
  `427ecb16a5ad4e9705997f22cc76a6be3fc9506fe5330722649aa6aca293ee82`.
  Full format check passed; ASTs match before/after formatting. It excludes
  only the exact currently validated pending question, retains explicit and
  historical unknowns, and adds real/synthetic controls. No runtime tests have
  run; formatted revision/launcher review and fresh census remain. The root
  currently has the earlier false-positive diagnostic code, so do not claim it
  complete; apply only a reviewed reconciliation after focused verification.
- A concrete diagnostic edge case was found: the applied count treats a valid
  currently pending `operator.question` as unknown merely because its action
  has no result, although a validated `extension_question` can resume for an
  explicit answer. Do not declare the current diagnosis candidate complete.
  An isolated correction is being prepared: after `Actions.restore`, exclude
  only the exact current unmatched question action with validated current
  question event; keep explicit unknown outcomes and earlier cleared/unmatched
  actions counted, and add valid-pending/intent-only/unknown/cancelled/legacy
  controls. Full Saved.resume has further validators; do not overclaim. The
  current filtered baseline source lacks this correction and already has one
  known boundary fixture failure; it remains running to find other failures.
- Read-only resume review found a separate host-invariant gap: an unmatched
  non-question extension effect is retained by Actions.restore but Session
  startup restores only pending questions and otherwise goes idle without
  automatically surfacing the uncertain effect. Source supports no automatic
  replay, but on-demand `ipse diagnose` alone is not an automatic resume warning.
  A safe direction is a bounded summary from validated action history retained
  in Session, exposed in live diagnostics/info and a content-free startup
  warning; do not fabricate a late action-result event. Account separately for
  recoverable pending operator.question and prior cancelled/finished parents.
  Requires focused valid-history, visibility/privacy, strict Saved and same-ID
  idle/no-replay controls. This is not implemented or tested, and the separate
  retirement explicit-result cause remains unresolved.
- Read-only interrupted-abort diagnostic composition review: its minimal test
  overlay alone does not reproduce retirement on the P30-only candidate; it
  requires retirement host/native/fixture code and the six reply tags. Product
  overlaps with P30 are Session and Invocation, whose three-way source merge
  simulated cleanly, but is not semantic verification. For causal diagnosis,
  keep the prepared one-test overlay on its matching retirement source; any
  eventual fix must be rechecked with diagnosis+P30+retirement integrated. No
  new candidate/test was created by this review.
- A time-boxed P31H alternative-path review found existing ManagedUse,
  ManagedApproval, WorkerInput and ManagedToolUse owners do not by themselves
  bind a complete arbitrary provided-source set and its time/approval authority
  through physical send, replay and delivery. Empty dependencies continue
  immediately and invented managed references are unsafe. Some owners can be
  reused, but a reviewed host-owned binding/provenance and time-observation
  interface remains necessary; it need not be the proposed `provided_set_v1`.
  This is source review, not a completed implementation or test.
- Root `docs/plan.md` now has one status paragraph for the saved-action
  diagnosis: three focused synthetic controls passed, the filtered baseline is
  in progress with one known boundary-fixture failure, and declined recall,
  opt-in and platform gates remain unqualified. `git diff --check` passes.
  This is time-sensitive WIP and must be revised when the run completes; no
  milestone or unfiltered baseline pass is claimed. Its source patch is in the
  restart tracked-work patch, not the current isolated HEAD candidate.
- Disabled boundary-corrected HEAD baseline launchers are at
  `_build/verification/diagnose-head-boundary-baseline-launcher-20261108-01/`.
  Candidate manifest `40015d69480e177e0e4a242038f5d4c061a9aea864e3c2e0aec0cf4a9f9d3669`;
  census SHA `f8f1d1abfe8d047e58f71d53ca8dcfb4d2c00bafb461bd879a4ae25d8aeb641a`;
  suite SHA `298a2fb197809bb0b8915c74a7bd6490da0a17b7d8ef3d128b2932cf2ed47e69`.
  Fresh synthetic tree/head derived from candidate; independent review, new
  census and process audit are required. No tests ran on this exact candidate.
  Do not start alongside failing baseline 17848, which continues to surface
  later failures. No unfiltered test or milestone acceptance is implied.
- Boundary-corrected HEAD diagnosis source is
  `_build/verification/diagnose-unknown-head-fixture-boundary-20261108-01/source`,
  manifest SHA-256
  `40015d69480e177e0e4a242038f5d4c061a9aea864e3c2e0aec0cf4a9f9d3669`.
  Independent review confirms only native_protocol_test.exs differs from the
  running formatted candidate, and its complete file matches the v12-passed
  boundary test. It checks resolve refusal and the exact overlap guard directly;
  no production behavior changed. This exact candidate is not yet tested. The
  current filtered baseline remains failing and continues for later failures.
- Running formatted HEAD filtered baseline 17848 has reported one failure:
  NativeHelperBoundaryTest expects the application-overlap reason from
  Sandbox.resolve, but this `/run` source is refused earlier as a protected
  system path. This matches the earlier v3 failure; v12's corrected test checks
  generic resolve refusal plus the overlap boundary directly and passed in its
  26-test focused suite. The current baseline is failing, not a pass; it remains
  running to discover later failures. A fresh isolated HEAD candidate with just
  that reviewed test hunk is being prepared. No prior fixture is replayed.
- Read-only root/P30 revision-02 comparison found 19 of 25 scoped paths already
  byte-identical. Six differ and must not be overwritten/staged wholesale:
  archive index and plan contain other milestone WIP; Session and Invocation
  contain document-retirement WIP; Saved contains additional provider WIP;
  delegation integration test contains retained-fixture/close WIP. Root already
  has the diagnosis, P30 fence and native-boundary changes. After diagnosis
  commit, use a scoped P30 index patch and reconcile these six carefully; the
  combined root still needs exact integrated tests. Staged Research remains
  separate. This comparison is read-only and no P30 completion is claimed.
- Independently reviewed fixture reconciliation patch
  `_build/verification/diagnose-fixture-root-reconcile-20261108-02/root-fixtures.patch`
  (SHA `277d08ffe115bfbe967d6b7ffb7f0872d3180341a306264461de276eaee3feb8`)
  was applied after a fresh check. It adds exclusive random test roots to four
  files; Session fixture already matched. Native delegation uses `/tmp`, while
  nonnative uses private TMPDIR, preserving existing native retention, P30
  assertions/close WIP and helper-boundary repair. `git diff --check` and
  Elixir1.18/OTP27 targeted format checks pass. Root integrated native behavior
  is not byte-identical to the isolated tested candidate and still needs its own
  focused verification. Staged Research and other WIP were not changed.
- Exact formatted diagnosis+fixture patch is prepared in isolated index
  `_build/verification/diagnose-prepared-index-20261108-01/index`; cached patch
  SHA `05b0b9328b6820bae1562205fe967e2b72998d63b2932f9640396e40cdd80bde`,
  staged tree `f89e7a495061fd079e2b42a18cde01ead04dd44a` matches the
  independently reviewed candidate/census. Exactly 11 paths are staged in this
  private index; unrelated staged Research is absent, and real index hash was
  unchanged. New objects live in its isolated objects directory, with real Git
  objects as read-only alternate; they require a reviewed safe transfer/commit
  procedure before updating project refs. Independent review is pending. No
  commit/push occurred; baseline 17848 and postflight must finish first.
- Read-only P31I carryover integration map: the 10-path scoped Chat/OpenRouter/
  xAI change overlaps pending P30+diagnosis in Saved, plan and archive index;
  three-way checks against its 09309905 base reported no textual conflicts.
  Saved's provider selectors, P30 fence and diagnosis hunks are distinct;
  plan/index need editorial reconciliation. Root already contains most P31I
  WIP; never overwrite it or staged Research. After earlier increments settle,
  freeze exact source and rerun projection, controlled provider Session/Saved/
  idle no-replay, format/build/docs/baseline and process/fixture audits. Earlier
  receipts do not qualify the new merge; declined populated recall stays off.
- After applying the six-file diagnosis reconciliation to the shared worktree,
  the four Elixir code/test paths passed `mix format --check-formatted` under
  Elixir1.18/OTP27 with isolated Mix home (exit 0, no output). This is a format
  check only; combined worktree runtime verification is still pending.
- Applied independently reviewed six-file diagnosis reconciliation patch
  `_build/verification/diagnose-root-reconcile-prepared-20261107-01/root-reconcile.patch`
  (SHA `bdcbdd769482e84cae5c4803aa8c95bdc662c906db3c7eb5176d24eec4225c50`)
  to the shared worktree after a fresh `git apply --check`. It adds Saved
  diagnosis, three focused tests and two manual passages while retaining P30,
  P31I, retirement WIP and the staged Research archive. `git diff --check`
  passes on those six paths. The HEAD-based and earlier combined candidate
  focused tests passed, but the resulting shared worktree is distinct and still
  needs integrated verification. No commit/index change occurred. Filtered
  HEAD baseline remains active in session 17848.
- Disabled P30-on-diagnosis rev02 focused launchers are at
  `_build/verification/p30-diagnose-focused-v02-launcher-20261107-01/`:
  census SHA `f99821a1950a2c07100a48820a9b41b8332ee34ca398e091094d1d22ba977d9f`,
  suite SHA `1e0eaa7ae9f27801670a4091f20c61c60c8bb8912214aff7fc9f658afcb77d14`
  after its author tightened per-stage review gates. README and independent
  static review now agree on this frozen seal; actual per-stage identity and
  exclusion counts still require a fresh census.
  Planned source-bound stages are 36 fence/assessment, 7 Decision owner,
  1 NEW opt-in synthetic materializer and 12 fixture controls. Launcher
  review and exact per-stage census remain; no tests have run. Do not run
  concurrently with active diagnosis baseline or touch old unknowns.
- Exact-source P30 revision-02 verification plan is
  `_build/verification/p30-fence-diagnose-verification-plan-20261107-01/PLAN.md`
  (SHA `22a1131f47d6c81fe62d60f58e9c36abc33f95c70d392473e8d9fd70cbca3a40`).
  It prioritizes full fence/assessment/policy controls, seven tagged Decision
  owner cases, one opt-in NEW synthetic PTY materializer, and 12 fixture-repair
  selectors. A fresh reviewed launcher/census and effect audit are required;
  old source receipts and the current diagnosis baseline do not qualify P30.
- P30-on-diagnosis revision 02 independently verified its two changed files
  against reviewed v12; exact docs check passed in
  `_build/verification/p30-on-diagnosis-docs-check-20261107-01/` with 1,319
  Markdown files, 10,582 links, zero errors and unchanged seals. No runtime
  tests ran. Diagnosis baseline remains the current closure priority.
- Independent P30 review found the initial merge missed the `/run` native
  boundary fixture repair and three reviewed Decision-manual corrections.
  One revised candidate is
  `_build/verification/p30-fence-on-diagnose-head-20261107-02/source`, manifest
  SHA-256 `0856e72a69b79d55bda2e44b2252bc1fa0ef1de0826250b4b488d78b25571499`.
  Only those two files differ from 01; native fix and manual text match v12.
  No runtime tests have run; exact docs check/review are underway. It remains
  based on pending diagnosis, not committed HEAD, and independent quality/full
  P30 acceptance remain open.
- While diagnosis baseline runs, isolated P30-on-pending-diagnosis source was
  prepared at `_build/verification/p30-fence-on-diagnose-head-20261107-01/source`,
  manifest SHA-256
  `337ab67e937d37ba38d785e1bee2f1ac3651705ce8e66362a7d13f00d8d28a75`.
  It merges the reviewed 22-path P30 patch plus three required test files;
  Saved contains both diagnosis and fence. No provider/retirement WIP imported,
  and no test/build ran. This is based on the pending candidate, not a committed
  new HEAD. Independent review, whole-manual reconciliation and fresh exact
  tests remain. If the diagnosis baseline fails or HEAD changes, reassess it.
- Read-only P30 rebase analysis: the 22-path P30 patch and pending formatted
  diagnosis candidate overlap only `lib/ipse/session/saved.ex`; non-mutating
  three-way merge indicates all 17 existing P30 paths merge and five new paths
  are collision-free against that candidate. This does not address live root
  WIP. After diagnosis commit/push, create a fresh actual-HEAD candidate; carry
  the P30 patch plus only necessary Decision nil-tag, delegation/MCP/source-window
  nil-fence and policy-loaded-state fixture repairs. Do not copy v12 wholesale,
  which includes unrelated provider/docs WIP. Review and rerun exact-source
  focused/session/materializer controls and applicable baseline; P30 quality
  remains open.
- While filtered HEAD diagnosis baseline runs, read-only planning identified the
  next scoped P30 increment as the existing exact-action/rubric fence at
  `_build/verification/p30-fence-head-09309905-20261107-02/`, not a new
  framework. After a successful diagnosis increment and push, rebase only its
  reviewed scoped patch onto the new HEAD, merge Saved diagnosis, preserve WIP,
  reconcile nil-fence test fixtures, then run fresh fence/materializer controls,
  whole-manual/docs review and applicable baseline. Previous focused receipts
  do not qualify the post-diagnosis source; independent quality and full P30
  remain open. No candidate or test was started for this next step.
- Minimal no-trace interrupted-abort diagnostic candidate is
  `_build/verification/retirement-abort-error-candidate-20261107-01/source`,
  source manifest SHA
  `c7f94e441daa3c315034efef718ef78066036705698d55fdb9c72c8e9b4062e5`.
  It adds a single tagged test-only error-category probe, keeps the original
  explicit-unknown and no-replay assertions, and refuses inspection on
  unconfirmed closure. Disabled one-test launchers are at
  `_build/verification/retirement-abort-error-focused-20261107-01/`, pending
  independent review and a fresh census. Do not run concurrently with the
  active filtered baseline; preserve old unknown fixtures and lock inodes.
- Formatted filtered HEAD baseline session 17848 has passed build,
  Elixir1.18/OTP27 format-version and format check, and warnings-as-errors
  compile; the guarded selected test suite is running. Exact candidate docs
  check also passed in `_build/verification/docs-diagnose-head-formatted-20261107-01/`
  (1,318 Markdown files, 10,578 links, zero errors). No final suite/demo or
  host cleanup result yet. Preserve 131 skips/132 exclusions and declined
  populated recall as unqualified; never infer full milestone acceptance.
- The reviewed FORMATTED fixture-protected HEAD FILTERED baseline is active in
  exec session `17848`, enabled launcher
  `_build/verification/diagnose-head-formatted-baseline-launcher-20261107-01/run-suite.enabled.sh`.
  Reviewed census manifest SHA
  `d59fdd253eac80d60cbb4154e6b988142d028d90a30e410ce23e93deb35ca94f`;
  4,338 selected, 131 skipped, 132 excluded. The declined populated recall and
  gated native opt-ins remain excluded. Formatter uses its separately isolated
  Elixir1.18/OTP27 environment; other stages use sealed system toolchain.
  Free tmpfs was 2,163,949,568 bytes before launch. Synthetic census Git and
  build were independently archived and hash/node verified at
  `_build/verification/diagnose-formatted-census-preservation-20261107-01/`;
  only original non-lock files and audited duplicate sources were removed.
  Original lock inodes, links, helpers, telemetry, fixture roots, unknowns and
  receipts remain. Poll exact stages and audit before any commit/push.
- Formatted filtered HEAD census independently reviewed: same 4,338 selected,
  131 skipped, 132 excluded as earlier HEAD census, with seven expected test
  line shifts. Declined populated recall remains outside selection; small fresh
  recall controls remain selected with indirect-path limits recorded. Reviewed
  manifest SHA-256
  `d59fdd253eac80d60cbb4154e6b988142d028d90a30e410ce23e93deb35ca94f`.
  Host postflight found no matching groups/open files/locks/listeners at
  inspection; only duplicate census docs removed. Space remains below 2 GiB;
  preserve/archive unique synthetic Git/build evidence before reclaiming any
  originals. No broad test body has run on the formatted candidate.
- Formatted fixture-protected HEAD dry census session 85990 completed exit 0;
  build/dry passed, guard records 4,338 selected, 131 skipped, 132 excluded.
  No test bodies ran. Independent identity/Git/guard review and host postflight
  are underway. Prior 1.18 formatting pass is exact formatted source, but the
  upcoming filtered baseline must separately run its own stages.
- Formatted fixture-protected HEAD diagnosis filtered dry census is active in
  exec session `85990`, enabled launcher
  `_build/verification/diagnose-head-formatted-baseline-launcher-20261107-01/run-census.enabled.sh`.
  Candidate manifest SHA
  `a25938d49d61d35b5e8c0f7713dd6c45258dc97ea0ad3476471a2735804d60ac`.
  Prior stopped-v2 synthetic Git and `_build/test` were copied to persistent
  `_build/verification/diagnose-baseline-v2-{git,build}-preservation-20261107-01/`
  and independently hash/node verified. Only audited duplicate files and
  original copied non-lock files were removed; original locks, symlinks,
  helpers, telemetry, tmp/fixture roots, unknowns and receipts remain. Scratch
  Git must be restored from the archive before reuse. Free space was
  2,157,232,128 bytes before launch. Poll and review identities/host postflight.
- Stopped format-stage postflight is
  `_build/verification/diagnose-head-fixture-baseline-suite-v2-20261107-01/suite-04/independent-postflight-20261107.md`.
  No matching host groups/open files/locks/listeners were observed. Only its
  audited duplicate `source/docs` was removed, preserving all other evidence.
- Formatted fixture-protected HEAD candidate is
  `_build/verification/diagnose-unknown-head-fixture-formatted-20261107-01/source`,
  SHA-256 manifest
  `a25938d49d61d35b5e8c0f7713dd6c45258dc97ea0ad3476471a2735804d60ac`.
  Only 1.18 formatter changes in Saved and Contributions test; ASTs match.
  Full `mix format --check-formatted` passed on Elixir1.18/OTP27 using empty
  private Mix archives, without Hex error. Earlier launcher reused OTP29 Hex
  archives under OTP27; incompatible archives are strongly indicated as the
  extra error cause. New disabled launchers with separate empty 1.18 Mix home
  and fresh exact census are being prepared. Runtime tests remain pending.
- Corrected filtered baseline session 41021 stopped at format: build and
  version stages passed, Elixir1.18/OTP27 `mix format --check-formatted` exited
  1 on `lib/ipse/session/saved.ex` and `test/ipse/extension/contributions_test.exs`.
  Log also emitted a Hex BEAM `corrupt atom table` error. No compile or broad
  test stage ran; do not call this baseline passed. Host postflight underway.
  An isolated exact-formatter revision and format-environment diagnosis are
  being prepared; preserve previous unknown fixtures and stopped-run evidence.
- Corrected fixture-protected HEAD FILTERED baseline is active in exec session
  `41021`, enabled launcher
  `_build/verification/diagnose-head-fixture-baseline-suite-v2-20261107-01/run-suite.enabled.sh`.
  It binds the independently verified synthetic Git head/tree from the reviewed
  census; the earlier v1 stopped preflight remains recorded, with no test run.
  Reviewed census manifest SHA
  `6b8672cc829a2d85926a99ce5039193f3bd6c35b79c89c8a295b96ba2c628e78`.
  User-declined `recall_many` and native opt-ins remain excluded, so this is
  not an unfiltered full baseline. It uses sealed system toolchain except
  formatter uses Elixir1.18/OTP27. Free tmpfs was 2,149,867,520 bytes before
  dispatch. The stopped preflight synthetic Git was copied to persistent
  `_build/verification/diagnose-baseline-preflight-git-preservation-20261107-01/git`,
  independently hash/node verified; only original non-lock files and an audited
  duplicate source/lib were removed. Scratch Git needs restoration from the
  archive; all original locks, fixtures, helpers and receipts remain. Poll the
  new run and require stage/guard/postflight before any commit or push.
- Filtered HEAD baseline session 40988 exited 1 during preflight before build
  or tests: its suite launcher pinned stale synthetic Git head/tree constants
  (`a307...`/`2ba...`), while its generated values matched the reviewed census
  (`da010601...`/`90e9ca6c...`). This is a launcher defect, not a test result.
  Host/scratch audit and a corrected fresh-path launcher are underway. Preserve
  stopped scratch and all fixtures/locks until audited; no baseline was run.
- The broad BEAM trace approach was stopped because descendant coverage could
  not be proved simply. A smaller disabled test-only error-category overlay is
  at `_build/verification/retirement-abort-error-diagnostic-20261107-01/`;
  it keeps original assertions, logs only bounded categories, and refuses journal
  inspection if owner closure is unconfirmed. Independent review is pending;
  it has not run and does not establish cause or no-replay by itself.
- The independently reviewed fixture-protected HEAD diagnosis FILTERED
  baseline is active in exec session `40988`, enabled launcher
  `_build/verification/diagnose-head-fixture-baseline-launcher-20261107-01/run-suite.enabled.sh`.
  Census selected 4,338, skipped 131, excluded 132; reviewed manifest SHA
  `6b8672cc829a2d85926a99ce5039193f3bd6c35b79c89c8a295b96ba2c628e78`.
  The declined populated recall and gated native opt-ins remain excluded; this
  cannot be called an unfiltered `mix test` or P30/P31 acceptance. Only format
  uses Elixir1.18/OTP27; other stages use sealed system toolchain. Poll it;
  require guard, build/format/compile/demo, postflight and clean exact candidate
  before any scoped commit/push. Two completed synthetic census Git trees were
  copied to `_build/verification/diagnose-census-git-preservation-20261107-01/`
  and independently hash/node verified; only original non-lock regular files
  were removed after host open/lock checks. Scratch Git trees need restoration
  from archives to be usable; external head/tree/index/guard receipts remain.
- Fixture-protected HEAD filtered-baseline dry census session 66628 exited 0;
  build and dry succeeded, guard records 4,338 selected, 131 skipped and 132
  excluded. This is not a test pass. Independent comparison of all identities
  versus v3, including the declined populated-recall boundary, and host cleanup
  audit are underway. No actual broad baseline has started.
- Fixture-protected HEAD diagnosis filtered-baseline dry census is active in
  exec session `66628`, enabled launcher
  `_build/verification/diagnose-head-fixture-baseline-launcher-20261107-01/run-census.enabled.sh`.
  The exact candidate docs check passed (1,318 Markdown, 10,578 links); fixture
  protections and launcher were independently reviewed. The launcher is a
  one-line enable of reviewed source. It runs no test bodies. Review selected,
  skipped and excluded identities—including no equivalent declined recall—plus
  host cleanup before actual filtered baseline. Other stages use sealed system
  Elixir/OTP; only formatting is 1.18/OTP27. Do not claim unfiltered mix test.
- Fixture-isolated HEAD diagnosis filtered baseline launchers prepared at
  `_build/verification/diagnose-head-fixture-baseline-launcher-20261107-01/`.
  They are disabled and undergoing independent review. Candidate source SHA
  `858a6063fa2946961a032a077829bae344f7ae9594cc0eb6e1c3e786303da55f`.
  Planned checks: guarded reviewed census, build, Elixir 1.18/OTP27 formatter,
  warnings-as-errors compile, filtered default tests, demo and postflight.
  Explicit declined `recall_many` and native opt-ins remain excluded; never call
  this an unfiltered `mix test` pass or full P30/P31 acceptance.
- Two unique diagnosis `_build/test` trees were copied to
  `_build/verification/diagnose-build-preservation-20261107-01/` and independently
  hash/node verified. After host open-file checks, only original copied non-lock
  files and audited duplicate source files from completed synthetic scratches
  were removed. Original lock inodes, symlinks, helpers, telemetry, tmp/fixtures,
  old unknowns and receipts remain. Free tmpfs was 2,153,062,400 bytes before
  baseline setup, barely above threshold; recheck immediately before dispatch.
- HEAD03 diagnosis focused tests and host postflight passed; no separate live
  BEAM observer was present. The full baseline cannot safely run on HEAD03's
  five predictable `/tmp` fixture setups, which could collide with old retained
  paths. A separate fixture-only composition at
  `_build/verification/diagnose-unknown-head-fixture-isolation-20261107-01/`
  protects six native test roots via random IDs and exclusive `File.mkdir!`;
  no production/assertion changes. Source manifest SHA-256
  `858a6063fa2946961a032a077829bae344f7ae9594cc0eb6e1c3e786303da55f`.
  Independent review is pending. A full baseline on this composition is not
  an exact HEAD03 test-source pass; preserve old fixtures and no-exclusion
  claims must reflect the expressly declined recall gate.
- Clean HEAD03 diagnosis actual suite session 3146 exited 0: guard reports 3
  passed, zero failed/invalid/skipped, 76 excluded, no early stop. Independent
  identity/host/fixture postflight is underway. Exact clean docs check passed
  separately. This is not the AGENTS.md runtime baseline; a full build, 1.18
  format, warnings-as-errors compile, default mix test and demo plan is being
  prepared before a focused commit/push. Preserve root WIP and staged Research.
- Clean HEAD03 diagnosis 3-test actual suite is active in exec session `3146`,
  enabled launcher
  `_build/verification/diagnose-unknown-head03-focused-20261107-01/run-suite.enabled.sh`.
  Its reviewed census manifest SHA-256 is
  `7cd72e097602dcecfd943066c42c43374e8ca6e7743346c3ffa4099d3e3e6d01`.
  After host census postflight, only audited duplicate docs/test/lib and
  non-telemetry dependency files were removed, keeping original lockfiles,
  builds, helpers, fixtures and receipts. Free tmpfs was 2,165,039,104 bytes
  before launch. Poll actual suite; independently audit cleanup before use.
- Clean HEAD-only diagnosis candidate 03 is
  `_build/verification/diagnose-unknown-head-63f6f0fc-20261107-03/source`,
  source manifest SHA-256
  `6e1ef36214964092f160a1aacdcd49e8f42507c20483d52861afc3bfc3348e37`.
  Independent review confirmed exact HEAD inventory with only six intended
  changed files; accidental `.orig` in older 02 is absent. Exact 03 docs check
  passed (1,318 Markdown files, 10,578 links, zero errors). Its reviewed
  3-test dry census is active in exec session `88435`, enabled launcher
  `_build/verification/diagnose-unknown-head03-focused-20261107-01/run-census.enabled.sh`.
  Poll, independently review actual identities/exclusions and host cleanup,
  then run exact focused tests; a full baseline and scoped commit/push remain.
- Clean HEAD-only diagnosis candidate is at
  `_build/verification/diagnose-unknown-head-63f6f0fc-20261107-01/`, based on
  pushed HEAD with six scoped files only; manifest SHA-256
  `92caee6eb83bbff06e435a6f8dd3449f4036f2395b62c1e31f98344700910d3f`.
  The 3-test combined-source pass supports but does not establish its exact
  HEAD-based behavior. A further isolated revision is being prepared for two
  whole-manual corrections: saved diagnosis does not report phase, and the
  handoff unknown count covers tool calls, not extension actions. Root recovery
  manual received those two corrections; root WIP and staged Research record
  must be preserved. Exact HEAD-based tests, full baseline, docs check and
  scoped commit/push remain required before calling this subgoal complete.
- Diagnostic-coverage focused suite session 28526 exited 0; exact guard
  selected/skipped/excluded sets matched the reviewed 3/0/76 census and all
  three tests passed. Host postflight found no matching recorded groups,
  open scratch files, operator lock holders or named listeners at inspection.
  No independent live BEAM observer was present; formatter PID is self-reported.
  Fresh tmp has no JSONL/lock files, but ordinary teardown prevents inferring
  complete effect reconciliation from that alone. This is scoped evidence;
  it does not establish full Saved.resume validity, causal resolution of the
  retirement failure, or goal completion. HEAD-only isolation is being assessed
  to allow a focused commit without unrelated WIP.
- Exact unknown-action diagnosis 3-test suite is active in exec session
  `28526`, enabled launcher
  `_build/verification/diagnose-unknown-focused-launcher-20261107-01/run-suite.enabled.sh`.
  Reviewed census manifest SHA-256
  `06305cde77e8a31d7932929294409ca4fedd882ed2fcc3d2523c2076a97f1e31`.
  Host census postflight found no matching live groups/open files/operator lock
  holders; no separate live formatter PID observer was present. Only audited
  duplicate docs from the new census and an older interrupted run were removed;
  the old run's tmp/fixtures/locks/receipts and unknowns were not accessed.
  Free tmpfs was 2,459,734,016 bytes before launch. Poll and audit effects.
- Exact diagnostic-coverage 3-test dry census is active in exec session
  `65241`, launcher `_build/verification/diagnose-unknown-focused-launcher-20261107-01/run-census.enabled.sh`.
  Before dispatch, two unique stopped-run builds were copied to
  `_build/verification/retirement-build-preservation-20261107-04/` and
  independently hash/node verified. Only those originals' non-lock regular
  build files and audited duplicate source files in stopped synthetic scratch
  were removed; original locks, symlinks, helpers, telemetry, tmp/fixture roots,
  unknowns and receipts remain. Free tmpfs was 2,158,116,864 bytes before
  launch. Poll census and review identities/cleanup; no test bodies run yet.
- Independent trace-overlay review found unproven descendant-process coverage,
  active-call counters not cleared on process exit, a resettable wait timeout,
  and uncertain resumed-owner cleanup. It remains disabled; missing trace events
  cannot locate a cause. Do not weaken or replace the original explicit-result
  retirement test with this overlay. A fresh diagnostic must prove trace coverage,
  bounded waits and confirmed closure or report inconclusive.
- Unresolved-action diagnosis candidate is
  `_build/verification/retirement-v12-diagnose-unknown-coverage-20261107-01/source`,
  latest source manifest SHA-256
  `73ab7a419bdb98d78f2dd50359415d072cc28859a1b1dad5d5bdc98450e2217a`.
  It reports only a validated aggregate `unknown_extension_action_count`,
  counts unmatched/explicit-unknown actions across cancellation and later
  invocations, and adds focused synthetic tests and manual guidance. Static
  review found no definite counting defect; spliced cases validate Actions and
  diagnose, not all Saved.resume validators. It is untested. Disabled focused
  census/suite launchers await independent review at
  `_build/verification/diagnose-unknown-focused-launcher-20261107-01/`.
- An independent test-only trace overlay for the interrupted abort is at
  `_build/verification/retirement-abort-trace-overlay-20261107-01/`. It is a
  syntax-parsed, unrun diagnostic, not a product fix; trace scope and cleanup
  need independent review and no inference from missing traces is permitted.
  The original failed assertion and previous unknown fixtures remain unchanged.
- `/run/user/1000` was down to ~1.04 GB free after the stopped run. Before a
  new native test, audit only fresh duplicate scratch and preserve all unique
  evidence, fixtures, old unknowns and lock inodes; never lower the preflight.
- Static inspection found a concrete diagnostic gap: `ipse diagnose`/
  `Saved.inspect_saved` reports unknown model tool calls but does not surface a
  pending unresolved extension action such as the unmatched `value.abort`.
  This is visibility/unknown marking, not proof of replay. An isolated minimal
  host-invariant correction with focused tests and guidance is being prepared.
  The separate question of why the explicit action result did not commit is
  still under investigation; do not weaken the failing retirement assertion or
  infer the cause. The original unknown remains unresolved and preserved.
- A read-only, pure `Ipse.Session.Saved.restore/2` against the NEW failed
  synthetic journal returned `:ok`, with `extension_state.action` present for
  `value.abort` and `extension_state.unknown == false`. No Session was started,
  no replay occurred and no fixture was mutated. This confirms strict pure
  reconstruction accepts that journal but not user-visible unknown marking,
  confirmed close, idle no-replay, or why no explicit result committed. Source
  review of inspection/visibility is underway. The fresh unknown remains intact.
- Source review of the fresh unmatched abort intent found `Actions.restore`
  retains the pending action but does not synthesize an unknown result or set
  the explicit `unknown` field for it. `Saved.restore` has additional validators,
  so its acceptance of this exact journal remains untested; idle initialization
  appears not to restart the action, but no-replay and user-visible uncertainty
  require verification. The invariant does not require fabricating a result
  event, but do not assume a pending action satisfies unknown marking. A fresh
  controlled diagnostic is being designed for intent/executor/commit/owner
  sequencing, Saved acceptance, visibility and idle no-replay. Do not change
  the failed assertion or touch the retained unknown to make it pass.
- Read-only sanitized inspection of the NEW failed Session test's synthetic
  journal found its final event at line 36 is `extension_action_intent` for
  `value.abort`; no later action result exists. The preceding `progress.inspect`
  result was ok. No old fixture or notebook was accessed. This confirms an
  unmatched intent, not why result commit was absent or whether strict Saved
  recovery/no-replay is correct. The fresh root and journal remain intact;
  source review is checking the actual recovery invariant, without replay.
- Fixture-corrected retirement suite session 97181 exited launcher 1 after
  native/protocol passed 17/17 and normal Session stopped early with 8 passed,
  1 failed, 5 selected unrun; hook stage was not reached. In the intentionally
  interrupted abort/no-replay test at
  `test/extensions/knowledge/collection_adapter_session_test.exs:6282`, the
  test observed unknown/native loss but found zero persisted unknown
  `extension_action_result` entries where it expected one. Cause is not yet
  established; this may be a test assumption or a real journal ordering issue.
  Preserve the fresh unknown fixture and all prior fixtures/locks; do not replay.
  Two independent source/log investigations and host postflight are underway.
- The fixture-corrected retirement actual suite is active in exec session
  `97181`, enabled launcher
  `_build/verification/retirement-integrated-v12-fixture-offline-launcher-20261107-01/run-suite.enabled.sh`.
  The 33-case census, 164 exclusions, source/helper/Rebar seals and host
  postflight were independently reviewed first. Two unique census build trees
  were copied to `_build/verification/retirement-build-preservation-20261107-03/`
  and independently hash/node verified; only duplicate files and copied
  non-lock regular build files were then removed. All original lock inodes,
  symlinks, helpers, telemetry, tmp/fixtures, previous unknowns and receipts
  remain. Free tmpfs was 2,154,078,208 bytes just before launch. Poll, require
  all three guarded stages, and audit effects/processes independently.
- Fixture-corrected offline census independently reviewed all 33 identities
  and 164 exclusions, zero skips; source/helper/Rebar/host seals match. Reviewed
  manifest SHA-256
  `47a82f252591460d8ef478da266bfad9cef87752a8ee166fcd1f1f967eda92c4`.
  Independent host postflight is
  `_build/verification/retirement-integrated-v12-fixture-offline-launcher-20261107-01/census-01/independent-postflight-20261107.md`.
  At inspection no matching groups, open scratch files, operator lock holders
  or named listeners remained. Two verified duplicate docs trees were removed;
  fixtures, locks, builds, helpers, telemetry, old unknowns and receipts remain.
  Free tmpfs after that cleanup was 2,020,573,184 bytes, below the 2 GiB
  actual-suite preflight. Further exact-duplicate/evidence-preserving cleanup
  is under review; do not remove original locks, links, helpers or unknowns.
- Fixture-corrected offline dry census session 2527 completed launcher exit 0;
  both builds/helper checks passed. Receipts list 17/14/2 selected, zero skips,
  and 0/75/89 excluded. Session dry `--only` exit 1 has the reviewed expected
  Mix behavior; no test bodies ran. Independent identity/seal review and host
  process/fixture audit are underway before any test or scratch cleanup.
- Fixture-corrected retirement candidate dry census is active in exec session
  `2527`, enabled launcher
  `_build/verification/retirement-integrated-v12-fixture-offline-launcher-20261107-01/run-census.enabled.sh`.
  Before launch, four more completed-run unique `_build` trees were copied to
  `_build/verification/retirement-build-preservation-20261107-02/`; independent
  hashes/node/link review matched originals. Only their copied non-lock files
  and audited duplicate stopped-suite source were removed. Original compile
  locks, symlinks, helpers, telemetry, tmp/fixture roots, unknowns and receipts
  remain. Free tmpfs was 2,173,333,504 bytes before launch. Poll census, then
  require exact identity/skip/helper and host cleanup review before tests.
- The fixture-only correction passed independent static review, including the
  14 selected Session setup/teardown paths. Disabled, independently reviewed
  fresh offline census/suite launchers are in
  `_build/verification/retirement-integrated-v12-fixture-offline-launcher-20261107-01/`.
  They require a new reviewed census and have not run. Space is below their
  threshold; four additional unique completed-run `_build` trees were copied
  with symlinks to `_build/verification/retirement-build-preservation-20261107-02/`.
  File/node verification is pending. Preserve original compile locks, links,
  helpers, tmp, fixtures and unknowns; do not remove copied non-lock build files
  until independently verified and host cleanup checked.
- Session fixture fix candidate is
  `_build/verification/retirement-integrated-v12-reply-tags-fixture-20261107-01/source`,
  source manifest SHA-256
  `6d729c5e1025b29a22b224ff55b512f1446ff3e044441c82d85fcc044f465f94`.
  Only two strict `or` operators in matching root/artifact retention guards are
  changed to truthy `||`; no production bytes, assertions or test identities
  changed. The candidate is untested and independently reviewed setup/teardown
  is pending. Stopped run postflight is
  `_build/verification/retirement-integrated-v12-reply-tags-offline-launcher-20261107-01/suite-01/independent-postflight-20261107.md`.
  Host checks found no matching live process/lock/listener/open-file rows at
  inspection; its fresh normal tmp has 16 roots, three JSONL and 38 lock files.
  Preserve all fresh and prior fixtures/locks; no complete effect reconciliation
  is claimed. The earlier unknown arm remains unresolved.
- Offline six-tag actual retirement suite session 4666 ended launcher exit 1.
  Both builds/helper checks and all 17 native/protocol controls passed in NEW
  synthetic fixtures. Normal Session stage recorded 3 passed, 1 failed,
  `early_stop=true`, with 10 selected cases not run; hook stage did not run.
  The failure occurred before its test body: Session fixture setup uses strict
  `or` with an absent nil tag, raising `BadBooleanError`. A narrow test-only
  correction is being prepared. This fresh partial run does not resolve the
  earlier unknown arm, which remains preserved; do not replay old fixtures.
  Host/process/effect postflight is pending.
- The independently reviewed offline six-tag 33-control actual suite is active
  in exec session `4666`, using enabled launcher
  `_build/verification/retirement-integrated-v12-reply-tags-offline-launcher-20261107-01/run-suite.enabled.sh`.
  It uses new scratch and never replays the earlier unknown arm. Four unique
  build trees were copied to persistent
  `_build/verification/retirement-build-preservation-20261107-01/`; independent
  hashes/node/link checks matched before removing only original non-lock regular
  build files. All original compile locks, symlinks, priv helpers, telemetry,
  tmp/fixture roots and unknowns remain. Audited duplicate offline-census
  sources were also removed while retaining all Cargo/Mix lockfiles and parent
  paths. Free tmpfs was 2,165,661,696 bytes just before launch. Poll all stages,
  audit any unknown independently, and do not equate a subset with goal closure.
- Offline six-tag census independently reviewed: all 33 selected identities and
  164 exclusions match, helper/Rebar/source/host seals match, no test bodies.
  Reviewed manifest SHA-256
  `bb335b237f3112a9e704c263c5ed8726e3091a1c8bbdf6274eb4b7f755800a4a`.
  Host postflight found no recorded groups, open scratch files or operator-lock
  holders. Only two audited duplicate `source/docs` trees were removed.
  Free tmpfs remains below the next run's 2 GiB preflight. Four unique `_build`
  evidence trees from the offline census and earlier failed suite have been
  copied with symlinks preserved to
  `_build/verification/retirement-build-preservation-20261107-01/`; their
  independent file-hash/node/link review is pending. Never remove their original
  lock inodes, symlinks, priv helpers, fixtures or unknowns. No build files
  should be reclaimed until copies and host open-file state are verified.
- Offline six-tag dry census session 79927 completed launcher exit 0; both
  builds/helper checks passed. Formatter receipts record 17/14/2 selected,
  0 skips and 0/75/89 exclusions. The Session dry stages' exit 1 with Mix's
  expected `--dry-run --only` message is checked by the launcher. No test
  bodies ran. Independent identity/exclusion/seal review and host postflight
  are in progress; do not claim a test pass.
- The independently reviewed offline six-tag dry census is active in exec
  session `79927`, using fresh enabled launcher
  `_build/verification/retirement-integrated-v12-reply-tags-offline-launcher-20261107-01/run-census.enabled.sh`.
  It seeds two isolated Mix homes from the retained approved Rebar3, verified
  hash/mode identical to all four previous census/suite build copies; no
  upstream authenticity claim. A narrowly audited cleanup removed duplicate
  files from the stopped census while retaining all Cargo/Mix lockfiles and
  ancestors, telemetry, tmp, compiled evidence, helpers, unknown fixtures and
  receipts. Free space was 2,148,757,504 bytes before launch, barely above the
  preflight. Poll; no test bodies run in census. Review its exact 33 identities,
  exclusions, helpers and host cleanup before any fresh actual suite.
- The stopped fresh census's independent host postflight is recorded at
  `_build/verification/retirement-integrated-v12-reply-tags-launcher-20261107-01/census-01/independent-postflight-20261107.md`.
  No test body ran; no matching live groups/open files/operator locks/listeners
  were observed. Only audited duplicate docs and source/dependency files were
  removed afterward, preserving Cargo/Mix lockfiles and ancestors, telemetry,
  tmp, compiled builds, helpers, fixtures and receipts. Current tmpfs free was
  2,148,757,504 bytes, barely above the 2 GiB preflight; recheck immediately.
- Prior successful normal/hook builds used the same approved Rebar3 SHA-256
  `4df37f2f7570e0b5af15b5dcbad6b7a864202575d94e1d8663166c7643ee3a09`.
  A hash-identical copy is retained at
  `_build/verification/rebar3-offline-retirement-20261107-01/rebar3`.
  Revised disabled offline launchers are in
  `_build/verification/retirement-integrated-v12-reply-tags-offline-launcher-20261107-01/`;
  they seed separate fresh Mix homes and retain offline/host/guard controls.
  They are unrun and await independent review before a fresh census.
- Six-tag fresh dry census session 80727 exited 1 during normal build: Mix
  tried to fetch rebar3 and timed out after 60 seconds. No hook build, census
  selections or test bodies ran; this is a toolchain availability failure,
  not evidence for or against the six-tag fix. Launcher cleanup is unconfirmed
  pending host audit; preserve its scratch until audited. Investigate an
  existing approved local rebar3 source; do not weaken network/TLS policy.
- Six-reply-tag candidate dry census is active in exec session `80727`, using
  `_build/verification/retirement-integrated-v12-reply-tags-launcher-20261107-01/run-census.enabled.sh`.
  Both disabled launchers were independently reviewed and use fresh scratch;
  no previous unknown is replayed. Before dispatch, audited exact duplicate
  source/test/lib/dev/native/extensions and non-telemetry dependencies were
  removed from completed synthetic scratch copies only; all tmp fixture roots,
  locks, builds, priv helpers, telemetry and receipts remain. Free space was
  2,153,152,512 bytes (just above the 2 GiB preflight). Poll the census and
  independently review identities, helper seals and cleanup before test bodies.
- Isolated retirement reply-framing fix is at
  `_build/verification/retirement-integrated-v12-reply-tags-20261107-01/source`.
  Only six successful native reply tags were added to the bounded framing
  allowlist; source manifest SHA-256
  `4cb720f5fa1c3f6e67f69df39c33a7c4c05791fb406e0791a1ceef1a3dbbc529`.
  Independent review mapped all six to native success frames and confirmed
  sequence/depth/payload/deadline checks and the 64-byte limit remain. It is
  untested. Never replay the earlier unknown arm; verification needs NEW
  synthetic roots. Failed-run duplicate docs were removed after independent
  audit; its fixtures, locks, helpers, builds and logs remain.
- Retirement failure static diagnosis found a concrete defect: the Elixir
  Transaction.Owner bounded inner reply allowlist omits six successful native
  retirement tags `g`, `m`, `b`, `e`, `k`, `l`. A valid native arm response
  `g` is therefore rejected as unknown; other retirement replies are likewise
  affected. The particular failure log does not prove which reply occurred, so
  its observed outcome stays unknown. A narrowly fixed isolated candidate is
  being prepared and independently reviewed. Never replay the failed fixture;
  any verification must use NEW synthetic roots.
- Retirement postflight found no remaining recorded groups, named runtimes,
  scratch open files, operator lock holder or named listeners at inspection.
  Three new `normal/tmp/ipse-retirement-control-*` roots with six `.lock` files
  remain; preserve all, especially the failing unknown arm. No Session test
  stages ran; 13 passed, one failed, three native selected tests did not run.
- Retirement suite session 65603 exited launcher 1 after native/protocol test
  exit 2. The guard reports 13 passed, 1 failed and `early_stop=true` out of
  17 selected. The exact-two-locks arm expected `:ok` but returned
  `{:unknown, :transaction_lost}`. Treat this as a genuine unknown: preserve
  its new fixture, journals, locks and processes/evidence until independently
  audited, never replay it. The normal/hook builds, helper identity checks and
  native dry stage passed, but the 33-case suite did not complete or pass.
  Independent diagnosis and host cleanup audit are underway.
- The reviewed 33-case retirement-v12-docs actual suite is active in exec
  session `65603`, using enabled launcher
  `_build/verification/retirement-integrated-v12-docs-launcher-20261107-01/run-suite.enabled.sh`.
  It started after the reviewed 17/14/2 census, host cleanup audit, and removal
  of audited duplicate test/lib/non-telemetry dependency subtrees from the two
  fresh census copies and finished focused-v12 copy. Preserved all `_build`,
  priv helpers, telemetry, tmp, locks, fixtures and receipts. Free space was
  2,159,243,264 bytes just before launch. Poll this session; require all three
  guarded stages and independently audit processes/unknown effects afterward.
  This is a narrow lifecycle control, not P31F or full-goal acceptance.
- Retirement-v12-docs census independent review completed: all 17/14/2
  selected identities and 164 exclusions reviewed, zero skips; helper digests
  and source/host/guard seals match. Reviewed manifest SHA-256
  `7565f72fda88c7d33823baa7a354feb011227e5ff8128132dfeb8b045cd30498`.
  The launcher creates no Git index; none is claimed. Host postflight is
  `_build/verification/retirement-integrated-v12-docs-launcher-20261107-01/census-01/independent-postflight-20261107.md`.
  Both ~448 MiB census `source/docs` duplicates were removed only after audit;
  locks, helpers, tmp and fixtures remain. Free tmpfs is still ~109 MB below
  the execution threshold. Additional exact duplicates are being audited; do
  not remove non-duplicate telemetry/build artifacts or old unknowns.
- Retirement-v12-docs dry census session 55713 completed launcher exit 0 with
  17 native/schema, 14 normal Session and 2 hook selected identities. The two
  `--dry-run --only` Session commands exited 1 with Mix's expected "All tests
  have been excluded" dry-run message; the reviewed launcher explicitly checks
  this behavior and separately compares formatter selected identities. No test
  bodies ran. Independent identity, skips/exclusions, helper and host cleanup
  reviews are in progress. Do not call the actual controls passed or enable
  their suite until those reviews and scratch-space gates are complete.
- The reviewed retirement-v12-docs dry census is running in exec session
  `55713`, enabled only after the focused-suite postflight and narrowly scoped
  scratch cleanup. Launcher
  `_build/verification/retirement-integrated-v12-docs-launcher-20261107-01/run-census.enabled.sh`
  differs from the reviewed disabled version only by replacing `exit 77`.
  It builds separate normal/hook helpers and performs dry selection; it does
  not run test bodies. Independently review 17/14/2 selected identities,
  skips/exclusions, helper identities and cleanup before the actual controls.
- Independent focused-suite postflight is recorded at
  `_build/verification/focused-regression-v12-launcher-20261107-01/suite-v12-01/independent-postflight-20261107.md`.
  At inspection, no recorded process groups, relevant named runtimes/listeners,
  open scratch files or operator lock holders remained. No independent live
  observer confirmed the formatter's BEAM PID; do not claim one. Only the
  audited duplicate scratch `source/docs` was then removed to free space;
  fixture roots, locks, original docs, receipts and old unknowns remain.
- V12 focused suite session 63275 completed launcher exit 0. Its outer guard
  records 26 passed, 0 failed, 0 invalid, 0 skipped, 39 excluded and no early
  stop; status is `focused-suite-passed, cleanup=requires-independent-audit`.
  The independent host process/lock/listener and synthetic-effect audit is in
  progress. This focused scope does not establish the previously-loaded parent
  policy branch, full regression, or skipped acceptance gates.
- The independently reviewed exact-v12 26-test focused suite is active in
  exec session `63275`, started after census review, host process/open-file/lock
  checks and deletion of only the fresh dry-census scratch. Enabled launcher:
  `_build/verification/focused-regression-v12-launcher-20261107-01/run-suite.enabled.sh`,
  a one-line enable of the reviewed disabled launcher. Poll it; require exact
  guard receipt and independently audit cleanup/effects before claiming a
  pass or starting a conflicting native run. This scope does not prove the
  already-loaded policy condition or any skipped/full acceptance gate.
- The v12 26-case dry census was independently reviewed: all selected names
  match the 25 failed v3 cases plus the false-positive SourceWindow repair;
  zero skips and all 39 exclusions were reviewed individually. The corrected
  reviewed manifest SHA-256 is
  `7f182cb1b0008ac80b7b9544ab893f265b1189e9844e4d3735ff6328a6cc4c51`.
  Host-escalated process-group, `lsof +D` and lock observations found no
  matching holders immediately before removal; then only the newly created
  dry-census scratch was deleted. Reviewed lists, receipts, logs and seals
  remain in the repository. The previously loaded parent-policy condition is
  not proven by this census and needs its own evidence.
- V12 focused dry census session 4894 exited 0; its status remains
  `census-recorded-not-reviewed, cleanup=requires-independent-audit`. The
  receipt records 26 selected, 0 skipped and 39 excluded; no test bodies ran.
  An independent identity/seal/process/fixture audit and reviewed census lists
  are underway. Current `/run/user/1000` free space is ~1.7 GiB, below the
  2 GiB execution preflight, until eligible fresh census scratch is audited
  and safely reclaimed. Do not enable the suite before those gates pass.
- Finished-suite independent postflight is recorded at
  `_build/verification/p30-p31-guarded-suite-20261107-04/suite-04/independent-postflight-20261107.md`.
  Point-in-time host checks found no recorded suite group, relevant named
  processes/listeners, scratch open-file rows or operator-lock holders. Its
  fresh scratch retains 476 JSONL, 2,405 lock files and 40 JSONL matching a
  simple unknown pattern; no complete effect reconciliation is claimed.
  Only its audited duplicate `source/docs` was removed, freeing tmpfs space;
  original documents, fixture roots, journals and locks remain. User explicitly
  authorized normal fresh synthetic cleanup, not touching prior unknowns.
- The reviewed v12 focused **dry census**, not test bodies, was started in
  exec session `4894` after the above audit and scratch-space check. Enabled
  launcher is `_build/verification/focused-regression-v12-launcher-20261107-01/run-census.enabled.sh`,
  differing from reviewed disabled source only by replacing its `exit 77`.
  Poll it; review all selected/skipped/excluded identities and process/fixture
  cleanup before any focused test run. The original declined recall remains off.
- Session 7702 ended with launcher exit 1 after the outer test process exited 2.
  Its guard receipt records 4,348 passed, 25 failed, 0 invalid, 131 skipped,
  132 excluded, 0 failed modules and `early_stop=false`. This is a completed
  failing selected run, not a pass. Launcher status remains
  `outcome=unknown, cleanup=unconfirmed` because the test stage failed; host
  process/group/listener/open-file/lock and fixture-effect audits are still
  underway. Do not reuse shared resources or delete scratch until audited.
  All 25 failures correspond to the already prepared fixture/assertion repairs;
  they have not been rerun on the fixed source.
- Disabled retirement-v12-docs launchers are at
  `_build/verification/retirement-integrated-v12-docs-launcher-20261107-01/`.
  Census SHA `98e51f4ffe0d0637f0977c42e9089af253692ab4d102bb2477759d8af0f6d11a`;
  suite SHA `0b41adaec85b31dfbd2b6d5d246651965c052b9b094ca6f301ec9feeef11fa6a`.
  They target 17 native/schema, 14 Session and 2 hook cases, with separate
  reviewed census and normal/hook helper gates. They are unrun and need
  independent launcher review, final active-suite failure reconciliation,
  fresh resources and postflight; old v8 evidence is not exact-candidate proof.
- Exact retirement-v12-docs documentation check passed in
  `_build/verification/docs-check-retirement-v12-20261107-01`: exit 0,
  1,322 Markdown files, 10,594 links, zero errors and matching pre/post
  source/index seals. It does not verify retirement runtime behavior.
- Retirement-on-v12 with its two reviewed manual passages is at
  `_build/verification/retirement-integrated-v12-docs-20261107-01/source`,
  source manifest SHA-256
  `311c2fd284bd72b69a78e59892199f00a4ed5a5bb131705e6ba0600db944616d`.
  It differs from the prior retirement composition only in the operator
  retirement/unknown guidance and developer live-registry/native-switch
  explanation; unrelated WIP remains excluded. No runtime test has run. A
  clean exact-candidate documentation check is being prepared.
- Static review found the root retirement operator WIP matches the isolated
  retirement-on-v12 candidate. Root `docs/developer/knowledge-storage.md` was
  clarified to distinguish the live registry from separate Session/Writer and
  source controls at the native switch, including unknown settlement and a
  decision admitted before owner loss. This WIP targets the untested retirement
  candidate and must not be presented as shipped behavior on v12 alone. It is
  in the tracked-work patch; independent wording and docs checks remain pending.
- Retirement-on-v12 candidate is at
  `_build/verification/retirement-integrated-v12-20261107-01/source`, manifest
  SHA-256 `832cfde59f9e690efce9c7c1f1ab640aae811289a3a2f92a4a73bb1f832bfaec`.
  Its retirement and close-safe patches applied cleanly, with all 13 touched
  files identical to retirement-on-v8 and all other files matching v12. It is
  untested; it needs exact-candidate native/Session controls, integrated
  regression and manual reconciliation before any completion claim.
- Disabled exact-v12 focused launchers are in
  `_build/verification/focused-regression-v12-launcher-20261107-01/`: census
  SHA `d277012774f0f74f8fc4c75df3a0b1d7d338ef38bd6226c2aadcb342d642a6c1`,
  suite SHA `5b8d2b8426a4fcfa098d24f3e429699a90d35dcc9d95e0d16960bbbeab655d3d`.
  They retain the 26 known-failure identities and are unrun. Review their
  exact seals and add any later active-suite failures before enabling them.
  The separately prepared loaded-parent direct-invocation harness is disabled
  and has unresolved nested-ExUnit concerns; do not use it as proof.
- Exact v12 documentation check passed in
  `_build/verification/docs-v12-check-20261107-01`: exit 0, 1,322 Markdown
  files, 10,594 local links, zero errors and unchanged source/index seals.
  This verifies documentation links/rules, not runtime behavior.
- Exact v11 docs check passed in
  `_build/verification/docs-v11-check-20261107-01` (1,322 Markdown files,
  10,594 local links, zero errors, exit 0, unchanged source/index seals). V12
  at `_build/verification/p30-p31-integrated-head-63f6f0fc-20261107-12/source`
  adds only the reviewed Corpus deadline-result wording. V12 source manifest
  SHA-256 is `07d7aac65945acda4e21e9615fbca60afe44968aa43dea051eb652f9c489d554`.
  It has the same runtime/tests as v11/v9. V12 has not run a docs check, test,
  or build; v9 launchers must be explicitly adapted to its seal after the
  guarded run ends and all subsequent failures are known.
- A static Research manual review found no additional v11 mismatch. Root's
  separate uncommitted Research code and documentation include the time checks
  missing from v11; they must stay coupled. In that root WIP, changed operator
  `research.md` from a boundary being "crossed" to "reached" to reflect
  equality refusal. This edit is in the tracked-work patch but remains untested
  and must not be copied alone into a candidate without the matching code.
- V11's Corpus deadline wording was also found materially imprecise: the host
  action reports `write_deadline_elapsed` while Corpus returns `refused` with
  a `store_refused` gap. A further isolated candidate is being prepared using
  the precise existing root wording; no runtime behavior is implied by docs.
- V11 at `_build/verification/p30-p31-integrated-head-63f6f0fc-20261107-11/source`
  adds only the reviewed Corpus interrupted-index recovery clarification to
  v10, without copying unrelated root Corpus WIP. Its source manifest SHA-256
  is `48d05239100c2f8393a53165b4c686f80406c4df571e9b1301605822d57d38a1`.
  Runtime/test bytes match v9. No tests or clean documentation check have run
  on v11; the v9 launchers/checks are not exact-v11 evidence. Independently
  inspect remaining Corpus deadline terminology against this exact source.
- V10 at `_build/verification/p30-p31-integrated-head-63f6f0fc-20261107-10/source`
  removes the unsupported Research paragraph from v9's manual, preserving all
  runtime/test bytes. Its source manifest SHA-256 is
  `e0e6673d538f315aa2646b5d11008c69a447dac1ab5bdfd19bc94775424ac8ca`.
  The separate shared-generation paragraph has source-level support in v10;
  this is not an integration test. V10 still predates the root Corpus recovery
  correction, so a new aligned candidate is being sealed. The v9 focused
  launchers and clean documentation check cannot be claimed as exact-v10 proof.
- V9's copied developer Knowledge manual includes a Research time-recheck
  paragraph describing newer root WIP that is absent from v9 code and tests.
  The v9 clean docs check establishes links/rules, not semantic correctness.
  Do not use v9 as a final candidate or claim that feature exists there. An
  isolated v10 is being prepared that removes the unsupported paragraph and
  checks the other newly copied shared-generation text against v9 source. Root
  Research WIP remains separate, unqualified and untouched.
- The reviewed v3 suite census excludes 132 and skips 131 cases; none are
  qualified by the selected run. Required follow-up includes document
  acquisition/capacity and lifecycle, applicable native permissions and PTY
  owner-loss controls, Research integrations, P30 assessment and final
  installed/platform acceptance. The populated notes recall and endurance gate
  remains expressly declined, including equivalent replacement consumers.
  Platform-specific exclusions and optional parser controls require their own
  applicable evidence; do not call the selected full run complete acceptance.
- Clean documentation snapshot
  `_build/verification/docs-check-v9-root-corpus-20261107-02` passed with exit
  0: 1,322 Markdown files, 10,594 local links and zero errors. It uses sealed v9
  plus the exact current root Corpus manual, with stable pre/post source, node
  and synthetic index seals. The earlier `...-01` setup exited 123 before the
  checker while attempting to hash a directory symlink; preserve it as an
  incomplete attempt. The root-worktree fixture-contaminated check remains a
  failure and is not reclassified by this clean-snapshot pass.
- A document-lifecycle review found that the operator Corpus manual grouped
  interrupted indexing with confirmed settled failure when advising draft abort.
  Root `docs/operator/corpus.md` now tells the reader to retain and investigate
  unconfirmed work before aborting or issuing a new request, and limits the
  direct abort procedure to confirmed settled failures. `git diff --check`
  passes; this fourth manual change postdates v9 and the clean docs snapshot,
  and still needs a fresh clean documentation check and candidate reconciliation.
- Integrated v9 is at
  `_build/verification/p30-p31-integrated-head-63f6f0fc-20261107-09/source`.
  It differs from v8 only in the three reviewed current manuals and the
  failure-25 policy test repair. Source manifest SHA-256
  `a69e300f477f088a6b2462a7ef8e18d944e1dc888bed839945f2555739fba373`.
  No test or build has run on v9. The full Knowledge manual includes other
  independent WIP; copying it does not qualify that work. A 26-case focused
  launcher is being prepared. The running suite is unchanged.
- The clean documentation snapshot
  `_build/verification/docs-v8-three-manual-check-20261107-01` passed the
  checker with 1,322 Markdown files and 10,593 links, zero errors and recorded
  exit 0. It uses integrated v8 plus the exact current three edited manual
  files; the source and synthetic Git index post-check seals match. Source
  manifest SHA-256
  `f2d66855c7b9d26c1983595b134a6e7feb27c02c1e05cbc9e2594df8e674365b`.
  The first identical check printed zero errors but its wrapper failed to save
  its exit because `status` is readonly in zsh; its log remains preserved.
- The guarded suite reported failure 25 in the untracked
  `test/dev/evaluation/candidate_expected_decision_policy_test.exs`: the child
  policy comparison succeeds, but the test assumed another test had not loaded
  the same module into the parent VM. Root now captures `:code.is_loaded/1`
  before the child and checks it remains unchanged. The test is `async: false`.
  This repair is not included in the tracked-work restart patch and has not run;
  incorporate it into a later candidate and test it explicitly. A targeted
  `mix format --check-formatted` returned zero but emitted a Hex corrupt atom
  table error; a repeat with isolated MIX_HOME on Elixir 1.18/OTP 27 exited 0
  with no output. This only verifies formatting, not the test's behavior.
- The root-worktree `elixir dev/check-docs.exs` run failed: its enumeration
  included retained untracked fixture snapshots, reporting 3,326 errors across
  5,330 Markdown files; Git also reported inaccessible retained receipt ledgers.
  Do not delete those fixtures or claim this as a pass. A clean v8-based
  snapshot with the current three edited manuals is being prepared for the
  relevant documentation check.
- A turnover-clock-on-v8 candidate is at
  `_build/verification/native-turnover-clock-integrated-v8-20261107-01/source`.
  It changes only the turnover driver and shared stdio clock helper; source
  manifest SHA-256 is
  `10cb73f872d4824da248e5ffeb6503cf7f617778bc6861b501abcc09d6e6abfa`.
  The shared helper's callers need compatibility checks, and the candidate has
  not been tested. Existing cohorts stay pinned to their original files. Any
  future fresh smoke must exclude recall and cannot replace the declined gate.
- Whole P30 decision/operator procedure review and Graph documentation review
  found misleading transport-cleanup wording, transient candidate status, an
  understated bounded synthetic paired journey, and ambiguous time-boundary
  wording. Corrections are in the root worktree's developer `decisions.md` and
  `knowledge-extensions.md` and operator `extensions.md`; `git diff --check`
  passes. These changes postdate the sealed v8 candidates and have not received
  a fresh documentation check or commit. Include them in a later candidate
  after v8 verification without changing the running regression snapshot.
- Integrated v8 on committed HEAD `63f6f0fc` is at
  `_build/verification/p30-p31-integrated-head-63f6f0fc-20261107-08/source`;
  its source manifest SHA-256 is
  `8df60df8bfb9a7544af37a667fea3d70e8ca3e0164b531a8803e0eff6b9bf878`.
  Its 25-case focused census and test launchers are prepared but disabled in
  `_build/verification/focused-regression-v8-launcher-20261107-01/`. Independent
  static review found no launcher blocker; the exact dry census still needs
  identity review, and no v8 test has run. Wait for session 7702 and its audit.
- A narrow retirement-on-v8 candidate is at
  `_build/verification/retirement-integrated-v8-20261107-01/source`, source
  manifest SHA-256
  `21717aea774c4a7f0b01705226a82fd5f7d589b093084e38f820b3ac70756817`.
  Its 13-path retirement patch applied cleanly; this candidate has not been
  built or tested. The previous v3 launcher does not qualify these bytes. The
  retirement work is only one document lifecycle prerequisite, not P31F closure.
- At 19:54 PST the guarded suite in session 7702 was still running, with 24
  reported failure headers and no final receipt. The user explicitly authorized
  normal cleanup for new disposable synthetic fixtures, including simulated
  unknowns; do not touch the retained 2,000-note notebook, its 2,100 records,
  or previously preserved unknown outcomes. Keep the suite running and audit
  its final result; a zero exit alone is not a passing receipt.
- The isolated v7 candidate at
  `_build/verification/p30-p31-integrated-head-09309905-20261107-07/source`
  adds the native boundary fixture repair to v6. Its source manifest SHA-256 is
  `37aef1b1766bc2d5f5b7c732770dc3656146c1e3ee6a6aac7363e235fb78f219`.
  Independent static review confirms the direct helper-boundary assertion
  works with the application under `/run`; no test has yet verified the fix.
  A later candidate incorporating HEAD `63f6f0fc` is being prepared. Recheck
  its exact source, census and focused tests before another full regression.
- Reviewed documentation corrections for managed inference ownership, cleanup
  confirmation and Corpus time-boundary equality were committed and pushed as
  `63f6f0fc`. Exact HEAD-based docs snapshot check passed 1,318 Markdown files
  and 10,578 links. Normal index still stages only the pre-existing Research
  record; other worktree edits remain. HEAD is now `63f6f0fc`. The active
  regression and prepared code candidates use earlier `09309905` plus their
  own snapshots; reconcile this docs-only commit without overwriting WIP.
- The integrated v5 candidate has been rebased onto pushed HEAD `63f6f0fc` at
  `_build/verification/p30-p31-integrated-head-63f6f0fc-20261107-01/source`.
  Source inventory SHA-256
  `dded23935d5aa23afd3f81bc76674cd18d4d9aefa442b1f3147710b2d9b45fce`.
  Only the three committed docs differ from prior v5; code/tests are identical.
  It still carries the prior v5 scoped WIP and needs a fresh source/Git census,
  focused verification and full baseline; no test has run on this new snapshot.
- A real sampled-clock gap was found in `dev/knowledge/native_notes_turnover.exs`:
  parent, child-initial and pre-effect observations can be discarded before a
  later check against an older floor. An isolated incomplete draft at
  `_build/verification/native-turnover-clock-v2-20261107-01/source` is frozen;
  do not run or promote it. Review also found discarded stdio clock samples,
  child input reuse before `inflight.json`, and loss of a sampled floor on an
  early parent crash. The isolated draft was revised with durable versioned
  attempt/input/dispatch markers, a validated full v2 closure chain, legacy
  continuation refusal and propagated owned-stdio/effect samples. Nine direct
  synthetic helper controls pass; independent review found no further definite
  static defect, but these do not exercise actual driver entry, fsync/crash,
  protected-stdio or native process behavior. A fresh non-recall integration
  is prepared but disabled at
  `_build/verification/native-turnover-clock-v2-20261107-01/integration/run-native-smoke-v2.OFF.sh`
  (SHA-256 `f146cf16bb90cdb321416d1ceedf52441e6f35e64532ed4bb5b6651fedc1bc50`).
  Independent review found its fresh seven-note non-recall path and process
  supervision appropriately scoped, but it tests neither actual rollback nor
  crash durability. Wait for regression 7702 and its audit before running it.
  No existing seed, prior unknown or declined recall fixture was accessed. Do
  not promote the draft until those boundaries are verified.
- The reviewed supervised guarded full regression on integrated v3 is active
  in exec session **7702**, enabled launcher SHA-256
  `5d3b71d67fec0984602861e75777eb903dc1f942b2e51a20af8f784c6790e4ef`.
  It uses the reviewed exact census of 4,373 selected, 131 skipped and 132
  excluded identities, with a completion guard that rejects zero-exit TERM and
  nested summaries. Synthetic HEAD/tree and resource/source/guard preflights
  are enforced; use only new disposable fixtures, do not access the declined
  notebook or previous unknowns. It may take about three hours. Poll the
  existing session, never restart on silence; after completion independently
  audit all process groups, receipts, global locks and unknown outcomes. This
  selected regression does not qualify the separately skipped/excluded gates.
- The active v3 regression has reported 15 `DecisionSessionTest` failures, all
  independently traced to teardown `if not context[:preserve_failure]` raising
  for an untagged nil value. Root now uses boolean-safe `unless`; a similar
  pattern in a separate in-progress root delegation fixture was also corrected.
  Both format successfully. The running snapshot remains unchanged; do not
  reclassify its failures or assume test bodies passed. Preserve the fresh roots
  whose cleanup callback raised, especially owner-loss/unknown cases. Let the
  suite continue to discover further failures rather than repeat the earlier
  prematurely stopped run. Isolated integrated v5 is at
  `_build/verification/p30-p31-integrated-head-09309905-20261107-05/source`;
  source manifest SHA-256
  `1df73c314f11a4a1bf6766cc59206c5964d95dcfb941afc505bdeb5c0388e151`.
  Independent comparison confirms only the Decision nil-tag fix vs v4 and one
  formatting blank line vs v3; tagged-retention behavior stays intact. V5 has
  not been run and its shifted delegation identities need a fresh census.
- The same regression then reported eight `MCP.SessionTest` failures caused by
  reusing internal Session config with the private nil fence key. A reviewed
  test-only helper now asserts nil and removes only that key at all eight root
  test sites. An additional source-window test was a false positive for the
  same reason; root now reaches the intended path and expects
  `:invalid_source_window` while preserving its unchanged-journal assertion.
  Both root files pass formatting but focused tests have not run. V6 integrating
  those fixture repairs on v5 is being prepared. The running v3 is unchanged.
- The active regression also reported a native-helper boundary test failure:
  the isolated app lives under protected `/run`, so resolution refuses there
  before reaching the app-overlap check. Root test now asserts refusal and
  checks `Sandbox.helper_boundary(app, helper)` directly for app overlap; its
  format check passes, no production boundary was weakened and the focused
  test is unrun. Independent fixture candidate v7 is being prepared.
- Integrated v4 at
  `_build/verification/p30-p31-integrated-head-09309905-20261107-04/source`
  differs from running v3 only by one formatter-required blank line in the
  delegation test, independently compared. V3's full format check failed on
  that line; v4 passes Elixir 1.18/OTP 27 formatting and its clean-snapshot docs
  check passes 1,322 Markdown files/10,592 links. V4 has not run the full
  regression; v3's results must remain attributed to v3.
- An isolated unwired `ManagedTimeHandoff` prototype passed five pure controls,
  but independent review found it does not authenticate a live sink, establish
  source-set continuity, recover high water or protect Research dispatch/delivery.
  It is not a mitigation and must not be integrated as such. First define the
  exact source-set and physical send/release boundary against existing
  ManagedToolUse/ManagedUse ownership and replay semantics.
- A follow-up P31H analysis found the host must bind the entire captured
  provided/fetched Research candidate set (not just selected citations),
  query/options/temporal fields and parent identity to the actual inference
  attempt and output release. Current managed dependency handling treats empty
  dependencies as ordinary and does not reconstruct Research rows. A narrow
  provided-only inline slice may be feasible if unsupported routes fail closed,
  but needs durable host/replay binding and physical send/release checks; do
  not claim the unwired prototype supplies these.
- The isolated document-retirement final-switch overlay is based on an older
  uncommitted foundation and does not apply cleanly to integrated v3. Its
  CollectionStore and Invocation hunks assume prior retirement authority and
  Session owner binding absent from v3. A three-way review is mapping the full
  prerequisite slice; do not apply the old patch by fuzz or run it as-is.
- A coherent isolated retirement composition is now at
  `_build/verification/retirement-integrated-v3-20261107-01`, patch SHA-256
  `46874daaf75a671e4f7884c378172b060a18cacaf1b6a0181e6aad71f2ef55f8`.
  Independent static review found P30 fence calls and P31I sources preserved
  and no definitive regression, but native/Session tests and owner-loss,
  restart, switch/acknowledgment and non-Linux qualification remain open.
  A separately reviewed disabled native launcher is
  `_build/verification/retirement-integrated-v3-launcher-20261107-01/run-retirement-v3.OFF.sh`,
  SHA-256 `7aec626aeb346ffb7b360d9cb6ca6d3c188c220c371d2ed50091118b1385e950`.
  It selects 17 native/schema, 14 normal Session and two hook cases, with
  separate built helper digest checks and a fail-stop teardown overlay. One
  test deliberately attempts close after an unknown and may kill its new owner;
  this is not proof of OS death or cleanup. It has not run; wait for regression
  7702 and its independent audit before any native test.
- A revised isolated P31H provided-only contract is at
  `_build/verification/p31h-provided-contract-20261107-01/CONTRACT.md`, SHA-256
  `5e9e645e9d0397ed90dd55e1086c63d1618ed63569c40a1e80d3177097d28664`.
  It addresses independent review on downgrade refusal, registered-only scope,
  both nil/unregistered inference routes, protected empty-dependency input,
  high-water transfer and terminal receipt. Its proposed operator-approved,
  artifact/options-pinned declarative adapter attests only the exact declared
  input array; worker closed-world behavior needs separate review. Existing
  ManagedRecipe lookup conflates missing/null/non-map and cannot be reused
  unchanged for this contract. A proposed optional one-use native review avoids
  overwriting the existing knowledge policy; ordinary approval alone is not a
  durable adapter/source-set proof. This remains a design, not enabled behavior.
- The five skipped `export_session_start_test.exs` cases target the disabled
  historical `export_v1` experiment. Current ordinary Linux Session startup
  uses the separate `header_share_v2`/`resume_share_v2` native retained-lock
  protocol. Do not unskip or alias v1 without its missing header/Writer/lock
  ownership and recovery contract; check required behaviors against existing
  v2 controls instead. The skipped v1 cases are not passes.
- A separate unrun current-v2 blocked-provider close-order control is at
  `_build/verification/session-blocked-provider-close-20261107-04` (test SHA
  `2b75b23d37c4a9cbeeff5167aac7c591f7a2b80fe5c7918bbbe807ee3af22c9e`).
  It uses the existing helper's Linux errno 11 contention classification and
  traces task/provider/Writer exit before a release request. Review notes its
  inode check is point-in-time and error-path helper cleanup is unproven; no
  actual test has run. Avoid adding the abandoned extra Rust probe.
  This is design only, not implemented or qualified Research behavior.
- The supervised census for integrated v3 finished in exec session **50654**,
  enabled launcher SHA-256
  `bf01f203c614061268af2e4aca8815f4b607b8b17193d11e87ba2950d8e3fc36`.
  A host-side observer in session **13171** matched the dry formatter's
  BEAM/parent/group identity. It recorded 4,373 selected, 131 skipped and 132
  excluded; review found identical membership to v2 with expected line shifts.
  No test bodies ran. Host audit saw no groups, input-lock holder or open files.
  After independent review, its new 608 MB synthetic scratch was removed;
  census evidence and a byte-verified Git index copy remain in the workspace.
  The old v2 census identities cannot be reused because test lines shifted.
- Exact integrated v2 build plus guarded dry-run census finished in exec
  session **44243**, enabled-launcher SHA-256
  `7ce0e25ac5aa027de600d19212aab2b07ac16ec889c0d63f57c34f10abf20f45`.
  Source/guard/host preflight passed. It uses guard v4, records selected,
  skipped and excluded identities, and runs no test bodies. Its Git checkout
  and tmpfs root are fresh and synthetic. Exit was zero; receipt lists 4,373
  selected, 131 skipped and 132 excluded. Host monitoring matched the outer
  formatter BEAM to the recorded dry-run group; postflight found no group or
  input-lock holder or open scratch files. Dry-run loads test modules and may
  have effects. All 131 skip identities were mapped to source declarations:
  125 have opt-in/helper/fixture/platform conditions, five are disabled export
  cases pending header-I/O fencing, and one is historical superseded coverage.
  All 132 excluded identities were grouped by source tags: Linux native 78,
  macOS 15, controlled TTY 20, Word native 9, memory 4, recall-many 4 and two
  integrated population drivers. These are not passed gates; small-note fresh
  synthetic recall tests are selected and distinct from the declined populated
  consumer. Source/Git postflight matched, and no scratch JSONL was observed.
  This is not a suite pass. Existing notebook and prior unknowns remain out of
  scope; other P31 acceptance remains open.
- After independent census scratch review and host process/open-file checks,
  the fresh 608 MB census scratch was removed under user-authorized synthetic
  cleanup. Census identity files, receipts, logs, source seals and reviews are
  retained under `_build/verification/p30-p31-census-20261107-01/census-v4-01`.
  Its copied Git checkout and new temporary Mix lock were disposable; no
  previously retained unknown fixture or global lock was removed.
- The guarded full-suite launcher remains disabled: review found its signal
  trap can leave a separately grouped child running and its missing-start wait
  is unbounded. A revised launcher and signal controls are being prepared.
- The reviewed integrated focused runner finished in exec session **27709**,
  enabled-launcher SHA-256
  `da75615514cada7e85cee093e110c87738535ef84f1919295a200d12172797fb`.
  Its candidate/host preflight passed. It uses a fresh private synthetic
  environment and tests corrected delegation, P30, consent, P31I and Graph;
  declined recall is excluded. A deliberately invalid HTTPS proxy rejects
  the synthetic xAI OAuth refresh path at the Ipse HTTP layer while allowing
  loopback; this is not OS network isolation. Build and all ten selected test
  stages exited zero: 73 outer passes, 91 exclusions; consent took 151.6 s.
  Independent audit of TMPDIR found matched recorded actions/invocations and
  14 verified release receipts; a later audit of the separate retained
  `source/_build/verification/fence-fixtures` found ten unmatched invocation
  intents and nine additional verified receipts. Preserve all of those unknowns
  and their original locks. Inventories matched. Host checks observed no recorded
  groups, relevant processes, open scratch files, shared input-lock holder or
  listeners owned by relevant process types. This does not establish full
  integration or settle prior unknowns; preserve retained fixtures and locks.
- After an independent review and immediate process/open-file recheck, the
  704 MB *new disposable* focused-delegation scratch
  `/run/user/1000/ipse-p30-delegation-focused-v2-20261107-01` was removed under
  the user's synthetic-cleanup authorization. Its private logs and audit remain
  under `_build/verification/p30-delegation-focused-20261107-01/focused-02`.
  Previously preserved unknown fixtures, Word artifacts and locks were not
  touched.
- After independent source/inode review and an open-file recheck, the 448 MB
  `source/docs` copy in the completed integrated focused scratch was removed
  under the user's disposable-synthetic cleanup authorization. The source
  candidate, saved pre/post seals, fixture roots (including seven fence
  journals with ten unmatched invocations), receipts and original locks remain.
  The scratch is consequently no longer a complete source copy; do not rerun
  its pre-cleanup inventory as if it still were.
- The separate Word test scratch's `source/docs` was independently verified
  as a new copy of the retained candidate docs (9,028 regular file hashes,
  node/symlink checks), and removed after an open-file/link recheck, freeing
  approximately 448 MB. Its artifact/build tree, all nine fixture roots and
  their unknown outcomes/locks remain untouched. Its scratch source is no
  longer complete; candidate and original evidence remain in the workspace.
- The completed P30-only focused scratch `source/docs` was also independently
  verified byte/type/symlink-equal to its retained candidate, with no hardlinked
  files or lock/receipt entries, then removed after host mount/open-file checks.
  Its fixture roots and original locks remain; the scratch is no longer a
  complete source copy. This freed another approximately 448 MB.
- The next full-run guard is being revised to record identities of excluded
  tests as well as selected/skipped tests. V4 synthetic selected/skip/exclude
  controls pass; independent final-byte nested/TERM checks remain. A tmpfs
  census launcher must use the reviewed final guard and audit post-dry Git
  state. The disk alternative is Btrfs, which cannot qualify protected native
  writes under the current kernel profile.
- The two-case delegation fixture rerun finished in exec session **78022**,
  enabled launcher SHA-256
  `bca97c12943a0a2ccf018cb35e3a0cc1ccdf8a8a8b6e304298bc633beb13b4d8`.
  Initial source and host preflight passed. It uses a fresh synthetic root and
  frozen combined source with the reviewed test-only nil-fence correction;
  the corresponding root file has unrelated differences. Both cases passed
  (13 excluded), with matching inventories. A host check observed no group
  members, relevant BEAM/runner, shared input-lock holder or open scratch files.
  User-authorized normal cleanup removed the fresh test journals, so no
  journal-level audit is possible. The deliberately stopped regression's
  retained fresh journals have one unmatched invocation and two unmatched
  managed-lifecycle intents; preserve their unknown outcomes and all prior
  preserved fixtures. Six receipt filenames have not yet been verified.
- An integrated candidate on pushed HEAD `09309905` now combines reviewed P30
  fence and documentation, the nil-asserting delegation fixture correction,
  Consent optimization, P31I provider carryover and P31G Graph result timing:
  `_build/verification/p30-p31-integrated-head-09309905-20261107-02/source`.
  Source inventory SHA-256
  `05791f60df71bcdce7b0af598d0afef94b8ba38924fa117488291747881c4bd0`.
  It excludes Research and other unrelated WIP. Independent integration review
  found the merged P30/P31I Saved logic sound and verified v2 differs only by
  two Graph documentation corrections. Eight pure provider-projection tests
  passed against v2's Draft/DraftNative source loaded in memory with previously
  built system-toolchain dependency beams; this is not a complete candidate
  build, Session test or baseline. The v2 Graph result-time wrapper also passed
  once with fake host callbacks and prior SDK/dependency beams; it is not a real
  transport, installed or full-suite result. Its nil-fence test fix is equivalent to, not byte-identical
  with, root's file, which has unrelated fixture work. Prior focused
  receipts support their individual snapshots only. The full diff has nested
  paths and must not be blindly applied to root or its staged Research record.
- A newer integrated v3 candidate at
  `_build/verification/p30-p31-integrated-head-09309905-20261107-03/source`
  adds five reviewed exclusive-random temporary fixture-root fixes missing in
  v2, preserving its delegation assertions. Source inventory SHA-256
  `c70398f41246e22b32ff0964ffe8558fe1ed855a61af4937fc8926102cda7dcc`.
  These test-file changes shift line identities, so the v2 census cannot be
  reused; a new disabled census launcher is being prepared. V2 focused results
  do not constitute an exact v3 candidate run.
- The combined P30 + Consent normal regression was deliberately stopped in exec session
  **30757**, enabled launcher SHA-256
  `2de980b8c5eaae84d58b271dbeda01fed4614b28f4c3a3c05b11291984f532ba`.
  Initial candidate/Git/host seals passed. It includes committed Word fix
  `09309905`, the P30 candidate, current uncommitted consent optimization,
  and reviewed exclusive-random test-root overlays. It uses a fresh private
  synthetic checkout and user-authorized normal cleanup for NEW fixtures;
  `recall_many`, `native_integrated_full` and `native_integrated_smoke` are
  excluded. It must not touch the retained notebook or any previously preserved
  unknown. Static review found no selected path accessing the retained probe;
  this is not OS confinement. The synthetic no-remote Git commit is
  `c9b52512d4288c8cbf56f40d1c7898da45e1f611`, not actual project HEAD.
  It had reported two delegation failures. To avoid waiting for a guaranteed
  failed result before the corrected integrated run, the exact boot/PID/parent/
  process-group/start-tick identity was checked and TERM sent to the verified
  fresh synthetic suite group `2177248`. The tool returned 0 and its launcher
  incorrectly recorded `stages-exited-zero` because the terminated Mix VM
  exited zero: **this run is interrupted and is not a pass**. No outer suite
  aggregate was observed; two nested test summaries are not that aggregate.
  Independent process/lock/listener/effect audit and a robust aggregate
  completion guard are required before a new suite or any cleanup.
- User explicitly chose **normal cleanup for new disposable synthetic test
  fixtures**, even when a test deliberately simulates an unknown outcome.
  This does not authorize deleting or revisiting the existing 2,000-note
  notebook, its 2,100 records, or any previously preserved unknown fixtures.
  It resolves the proposed blanket retention requirement for fresh normal-suite
  fixtures; preserve all prior audit evidence and original locks. A fresh
  P30-only full regression launcher is being prepared and independently reviewed.
- Regression **30757** passed build and started its suite stage, then was
  deliberately interrupted; no complete aggregate result exists. It reported
  two failures in
  `Ipse.DelegationSessionTest`: completed-parent idle resume and physical child
  source refusal before torn-tail repair. Both tests reuse private Session config
  containing a nil `:exact_action_fence`, which startup rejects as caller input.
  Independent review found production delegation removes the private field and
  no supported path reuses raw Session state. Root test now asserts the field is
  nil and removes it at both sites; Elixir 1.18 format check passes, but focused
  tests remain unrun. The running snapshot is unchanged and will still report
  its failures. Production fence validation is unchanged. The existing session
  has ended; do not restart it or reclassify its interrupted result.
- A reviewed disabled focused runner for those delegation tests is at
  `_build/verification/p30-delegation-focused-20261107-01/run-focused-v2.OFF.sh`
  (SHA-256 `053e4a8c67d9e00fde84956c625b2cb41e6b290d3e96d8b9ac5c93642d1216a3`).
  It tests the frozen regression source plus the nil-asserting fixture patch,
  not byte-identical root. It has not run. Wait for regression 30757 and its
  audit before execution; preflight the host seal and resources.

- A P31I-only candidate on pushed HEAD `09309905` is prepared at
  `_build/verification/p31i-carryover-head-09309905-20261107-01`; its changed
  host modules and tests match prior synthetic Session evidence, but the full
  candidate/runtime differ and it is not an exact-candidate acceptance pass.
  Independent scope review found exactly the ten intended paths, and a dry-run
  on the separate P30-only source succeeded; combined runtime is unverified.
- A Consent-only candidate on pushed HEAD `09309905` is prepared at
  `_build/verification/consent-head-only-20261107-01/source`; it has the exact
  Consent source being exercised by the running combined regression plus scoped
  developer guidance and evidence. Its root-relative patch is
  `candidate.patch` SHA-256
  `29e010599afaa6271e141d92954beafd5580eee25beb60df33e55ab3a5fd375b`
  after clarifying earlier pending-stage reclamation in developer guidance.
  The root already has overlapping WIP; never overwrite it or the pre-staged
  Research file. Independent review and exact-candidate checks remain open.
- A P31G Graph worker-only candidate is prepared at
  `_build/verification/p31g-graph-head-09309905-20261107-03/source`, with an
  eight-path normalized patch SHA-256
  `5ac5732996fda7565a4b4786856b09b2f70f2bd460c0921040b106217bfd35a9`.
  Its Graph source and focused tests match prior checked files, but the prior
  broad suite failed and this exact candidate has not passed a baseline.
  The -03 candidate adds the developer two-sample explanation and corrects
  operator wording to refusal when the boundary is reached, including equality.
- P30/Graph manual review corrected P30's order of rubric vs capture checks and
  Graph's boundary wording in root. An isolated documentation check passed
  1,324 Markdown files and 10,599 links after including the untracked Graph test;
  an earlier incomplete snapshot failed on that missing target. P30 candidate
  `_build/verification/p30-fence-head-09309905-20261107-02/source` includes the
  manual correction but not the later unrun delegation-fixture repair.
- The P31I exact-candidate focused launcher remains disabled at
  `_build/verification/p31i-carryover-head-09309905-20261107-01/run-carryover.OFF.sh`.
  Independent review verified test selection and source seals, but noted that
  the synthetic xAI OAuth credential expires after one hour and its real
  refresh fallback could be reached if the clock jumps; a fail-closed test-only
  approach is being prepared. Teardown may also repeat a cleanup call after an
  unconfirmed close. Do not describe it as OS-level network isolation.
- A revised P31I launcher `run-carryover-v2.OFF.sh` has been independently
  reviewed, with `HTTPS_PROXY=disabled` to reject the real xAI refresh path at
  Ipse's HTTP policy layer and permit loopback. A standalone, network-free
  option-selection check passed; its direct module load emitted expected
  missing-module warnings and is not a strict compile or network-isolation
  test. Keep the launcher disabled until regression 30757 finishes and is
  audited; later audit any unconfirmed Session close before retry.
- Reviewed Collection close diagnostic v3 finished in exec session
  **81817**, enabled launcher SHA-256
  `bce3cf747faf5eff9246e1974b25b247fd6f333aa898c61398d1ad673680d357`.
  Source and host preflight hashes passed. It selects three serialized
  synthetic controls, retains original fixtures/locks and does not target the
  declined notebook. Three controls passed, eight excluded. Independent audit
  found matching inventories, no observed process, listener or lock holder,
  and two valid recorded release receipts; a third journal had no release
  intent or receipt. Preserve all fixtures and original locks. One failure
  control injects state; it cannot prove the historical unconfirmed-close
  cause. The test-only tracker is not generally concurrent-linearizable.
- The earlier prepared full-suite launcher was not enabled: inventory
  identified tests outside its retained-fixture flags that can delete roots
  containing intentionally unknown or interrupted effects, including Collection
  adapter and journal tests. A private TMPDIR alone does not prevent their
  teardown from deleting contents. The user has since allowed normal cleanup
  for NEW disposable synthetic fixtures, with prior unknowns preserved. Do not
  globally suppress intentional test deletions or alter earlier evidence.
- Confirmed default-suite examples include Session recovery and file-effect,
  Collection adapter and Word fixture families. A partial test-only opt-in
  overlay retaining three families is under independent review at
  `_build/verification/full-suite-retention-scope-20261107-01`; the existing
  Word retention flag covers its family. This is not exhaustive and does not
  by itself address on-exit close retries. The proposed HEAD-based full-suite
  launcher is hard-stopped pending coverage and an isolated indexed Git setup.
- A five-file Session/owner-loss retention overlay
  `_build/verification/full-suite-retention-scope-20261107-01/retention-v2.patch`
  retains additional roots and suppresses automatic close callbacks only when
  its test flag is enabled. It is unrun and under lifecycle review; suppressing
  cleanup may leave live Sessions, and other fixture families remain uncovered.
  The isolated indexed-suite template under
  `_build/verification/p30-regression-indexed-design-09309905-20261107-01`
  has two hard stops. Independent review found its preflight census would
  wrongly include copied deps/build files and that its synthetic root-only Git
  history cannot qualify tests that require real project history. Do not enable.
- The focused consent and Collection controls are recorded at
  `docs/archive/2026-10-26-p30-p31-implementation/consent-and-close-controls-20261107.md`.
  A clean documentation snapshot containing current related records passed
  1,324 Markdown files/10,598 links; the raw root checker failure remains.
- The one-line Word boolean fixture fix was committed and pushed as
  `09309905` on `codex/p30-p31`. The nine selected cases passed using a
  retention-only diagnostic overlay; independent audit preserved the fixture
  roots and unknown outcomes. Exact-candidate 1.18/OTP 27 formatting passed and
  relevant testing/recovery manuals were reviewed. The old full suite remains
  failed. The separately staged Research record remains staged and unchanged.
  HEAD is now `09309905`; earlier HEAD-based P30 snapshots use parent
  `5f321eb2` and need the committed test fix reconciled before a later commit.
- The Word boolean fixture correction is isolated against `5f321eb2` at
  `_build/verification/word-boolean-head-only-20261107-01/candidate` and has
  no other candidate changes. Its separately reviewed retained-fixture
  diagnostic is running in exec session **43096**, enabled launcher SHA-256
  `8ac8e19cb0c03234f8e71260ac499b6035948667c1fbaefb9e12e16ac9aa69b6`.
  It selects the nine previously failed synthetic cases; source and host
  preflight passed. Its test-only retention overlay differs from the exact
  candidate, and some cases deliberately create unknown state. Wait for and
  independently audit completion, retain roots and locks; do not replay.
- The reviewed consent workload V2 finished in exec session **47042**;
  enabled-launcher SHA-256
  `d9cea484d2c1d25ee58e46c33c04a705fe637680c4e8766569f87ef321fd8789`.
  It uses a fresh retained synthetic fixture, the current optimization and the
  original 25k/65-cycle/180s test: one passed, eight excluded, in 165.6 s.
  Native build and strict compile passed. Independent audit found matching
  inventories and no observed process, listener or lock conflict; final local
  state had no live operation marked unknown. Retain all fixture roots and
  locks. This narrowly passes a modified-teardown diagnostic, not the earlier
  timed-out full suite, and its timing margin is small. V1
  was not run because its test helper failed to retain an operator home; V2
  includes the independently reviewed opt-in fix. Do not replay unknowns.
- HEAD-based P30-only build, focused Session tests and materializer finished
  in exec session **19385**, enabled launcher SHA-256
  `3a2cdd3826b6c50dbe2eb80b8df74c4546d65eaf6bfa89e3a2ff642ecbb593ef`.
  Build passed, as did 36 focused tests, seven Session tests (15 excluded),
  and one terminal materializer test. Source/host postflight inventories
  match. Independent process/effect audit is underway; retain fixtures in both
  scratch build and TMPDIR locations. Exact-candidate Elixir 1.18/OTP 27 format
  passed with an empty Mix home; a copied clean snapshot passed the docs check
  (1,319 Markdown files/10,582 links). Full baseline, commit and push remain.
- The P30 V4 pass and its independent audit are recorded in
  `docs/archive/2026-10-26-p30-p31-implementation/p30-exact-action-materializer-20261107.md`,
  with scoped links in the plan and archive index. A clean documentation
  snapshot including the current related WIP records passed 1,323 Markdown
  files/10,596 links. The raw root docs checker failed because it also scanned
  unrelated preserved untracked checkouts; preserve that failure.
- A HEAD-based P30-only candidate at
  `_build/verification/p30-fence-head-only-20261107-01/source` excludes
  unrelated retirement and P31I WIP. Independent static review found no
  concrete defect but identified interleaved files and non-root-relative patch
  paths. The integrated V4 pass does not qualify this different candidate;
  exact-candidate testing and baseline remain open, as do commit and push.
- A disabled isolated 25k/65-cycle consent workload candidate is at
  `_build/verification/consent-perf-focused-20261107-01`; independent review
  is underway before any run. It uses fresh retained synthetic fixtures and
  the current optimization, does not access declined recall, and cannot
  reclassify the earlier 180-second timeout.
- The repaired P30 materializer v4 finished in exec session **55119** using
  enabled-launcher SHA-256
  `0ac37c93fa2d58c5a1ddfbd68eca2c83d8efcb59b3eea2aeb44775a046201ee4`.
  Strict compile and one synthetic materializer test passed. Independent audit
  found paired action/invocation/worker-input/request records, eight final
  requests, three valid release receipts, no recorded process group or fixture
  listener, no open scratch files or observed lock holder, and matching nine
  host pre/post inventories. This is scoped synthetic evidence, not installed
  or whole-milestone acceptance. Preserve v4's fixture and original locks.
  It uses a new synthetic seed and scratch; no declined recall. V3's
  recorded requests matched results and all three release receipts verified,
  but the v3 fixture and original locks remain preserved.
- Independently reviewed P30 materializer v3 finished in exec session
  **48344** with enabled-launcher SHA-256
  `a5bcec54f0b0f1b949fce10fe0c25c91d967704aa223de0d196bc9bfcad0192f`.
  Compile passed; the actual test failed after a completed synthetic assessment
  because `rubric-refusal.json` was missing. It did not reach later journal
  assertions. The separately reviewed missing refusal helper was integrated
  in root `dev/evaluation/candidate_assessment_recipe.exs`, SHA-256
  `2d5b133883a8975f8af2f55520caf7e07a8f70b03b0cd293c2ab98e2f117d43d`;
  a fresh snapshot/run is needed. Pure `Code.format_string!` check passed;
  `mix format` exited zero but logged incompatible Hex BEAM metadata and is
  not clean verification. Keep the v3 synthetic fixture and original locks;
  independent effect/receipt audit is in progress. The previous v2 stopped pre-dispatch:
  independent audit found no stage claim, process, fixture or test effect,
  and its mismatch was exactly the reviewed CollectionStore retention change.
  Preserve both preflight records. Do not start another terminal test until v3
  finishes and its process, lock and effects have been independently audited.
- The long `77563` suite finished: 4,328/4,339 passed, 11 failed, 130
  skipped and 132 excluded. Inner exit was 2. The nine Word cases share the
  already-fixed boolean fixture bug; the consent timeout and unconfirmed
  CollectionStore close remain unexplained. Independent host checks found no
  observed conflict on its process group, shared lock or listener and matching
  runtime inventories. Preserve its scratch and 1,964 lock files: its unknown
  effects remain unaudited and the historical Collection root may be gone.
- The independently reviewed v2 synthetic P30 materializer launcher stopped
  in exec session **13147** during preflight, before compilation or a test
  claim, because its old host baseline source inventory did not match. Its
  enabled copy SHA-256 is
  `2d3259268ded66a799c7432e5838015d9e2cb001c82a40655ae479b740774c2d`.
  Source and manifest hash checks passed, but baseline inventory comparison
  failed. Preserve its preflight output and scratch; independent cause and
  process/effect audit are underway. No materializer result was produced.
- Whole-document P30 review found two stale statements in
  `docs/developer/decisions.md`. Root now describes the scoped pre-dispatch
  rubric/request fence and unconditional retention of the materializer fixture;
  this does not claim the terminal test passed. The root docs checker also
  scanned preserved untracked checkout trees and failed with 3,326 errors.
  A clean snapshot containing the edited manual passed with 1,319 Markdown
  files and 10,582 links, but that is not a whole-root check. Since the manual
  changed after the P30 snapshot was sealed, refresh and review its source seal.
- Read-only follow-up on the 25,000-ID consent timeout found at least 195
  whole-ledger writes in the 65-cycle workload. The optimization removes some
  duplicate validation, but no native workload establishes that it fixes the
  timeout. A retained fresh-fixture diagnostic with per-cycle timing is needed;
  preserve the original timeout and any unknown outcomes.
- The CollectionStore unconfirmed-close failure may involve a check/call race,
  but the log cannot establish its cause. An unrun isolated three-control
  diagnostic exists at `_build/verification/collection-close-race-design-20261107-01`;
  it requires independent review and a freshly built runner. It cannot prove
  the historical failure's cause. Do not weaken confirmed-close requirements.
- A P31I provider-carryover-only snapshot was prepared at
  `_build/verification/p31i-focused-candidate-20261107-SIY2jg`, independently
  review found no concrete unsafe projection or missing runtime dependency.
  It passes Elixir 1.18 formatting and its documentation check
  found 1,319 Markdown files, 10,582 links and no errors after initializing a
  separate temporary Git directory. The first docs check without Git metadata
  inspected zero files and is invalid. This snapshot has not passed its full
  baseline or been committed. The root index remains unchanged.
- An ad hoc compile/test used Elixir 1.18 with OTP 29 and older Elixir 1.20
  dependency beams: I supplied a nonexistent Erlang path and the shell fell
  back to OTP 29. Its direct test reported six failures in eight. An independent
  diagnostic identified incompatible embedded Regex structs in the older
  Provider beam; recompiling Provider in memory under Elixir 1.18 produced
  eight passing tests in that same mixed environment. Forcing OTP 27 with the
  older OTP 29 beams failed before tests. Preserve both failures and diagnostic;
  none qualifies a clean Elixir 1.18/OTP 27 baseline or invalidates prior runs.
- A disabled actual P30 materializer test launcher and current-source snapshot
  were prepared under `_build/verification/p30-materializer-root-20261107-01`.
  Independent static review found no new concrete blocker; post-suite
  lock/process/unknown-effect audit and fresh resource checks are required
  before any run. The previous baseline suite still holds shared terminal
  resources. Post-run, detached PTY descendants, listeners, journals and locks
  must be independently audited; retain scratch on uncertainty.
- A new host-sealed combined P30/P31I headless run finished in exec session
  **62635**, launched by
  `_build/verification/p30-headless-hostseal-20261107-01/run-headless-host.enabled.sh`
  (SHA-256 `6437043966a6039ac07b139ad1162e9bdb8fcc5e5331dea3d1f02508091e98cc`).
  It uses a separate private tmpfs root, omits the terminal materializer and
  declined recall, and passed initial and postflight inventory checks. Compile,
  18 pure controls, two policy controls and seven P30 Session tests exited zero.
  Independent audit verified nine release receipts and found no recorded
  surviving process groups, listeners, or open scratch files. Several invocation
  intents lack results and four events have unknown outcomes: preserve all seven
  fixture roots and their lock inodes. This is not full milestone acceptance.
- The CollectionStore uncertainty test has an uncommitted test-only opt-in
  `IPSE_KEEP_COLLECTION_UNKNOWN=1` retention flag for its synthetic root and
  shared artifact; default cleanup is unchanged. The next full-suite candidate
  and disabled launcher were updated. Independent static review found matching
  source and launcher seals and no new concrete blocker; it did not run tests.
  The resource checks are point-in-time and do not establish cgroup headroom.
- The combined root-source P30/P31I headless launcher finished in exec session
  **27832** via
  `_build/verification/p30-p31i-retirement-headless-20261107-01/run-headless.enabled.sh`
  (SHA-256 `268d954058409fd19a5187382afbb05011eef750eb44ca9094c392ecdc7a0daa`).
  Its independently reviewed launcher uses a fresh private tmpfs root and
  excludes the terminal materializer and declined recall. It stopped before
  any stage claim because toolchain owner metadata differed between the sandbox
  inventory (nobody) and host view (root), despite matching content hashes.
  Source/runtime inventories matched. The preflight output and scratch are
  retained while the namespace mapping is reviewed; no test has been claimed or
  started. Do not silently refresh the old seal. This is not acceptance.
- The test helper now honors `IPSE_KEEP_TEST_OPERATOR_HOME=1` so private
  synthetic operator homes can be retained when diagnosing failures; default
  cleanup remains unchanged. The P30 combined headless and P31I full-suite
  snapshots and disabled launchers were refreshed to include it. Their
  launchers also record uncertain spawn interruptions and compare copied
  runtime inputs before compile where applicable. Independent re-review is
  pending; neither launcher has run.
- Review of the full-suite launcher found that `test/ipse/session_test.exs`
  used a predictable `/tmp` directory and recursively deleted it. Root now uses
  a random ID and exclusive `File.mkdir!`, preventing deletion of a pre-existing
  collision. The test-only change is formatted; the separate full-suite source
  and its seals are being refreshed. The already-running older suite is unchanged.
- The root-based P30 integration overlay from
  `_build/verification/p30-root-integration-20261107-01` includes the
  materializer's exact-request/fence construction while preserving the current
  root WIP and newer route binding. It was applied as uncommitted root work
  after an independent static review. Two new root files were subsequently
  formatted with Elixir 1.18, so the older overlay inventory no longer fully
  byte-matches; the combined headless candidate is being resealed. Direct
  compile and focused pure controls passed on the pre-format snapshot,
  but combined native materializer and final baseline are unrun. The fence covers
  `decision.create`, not all possible Session actions. Review found no concrete
  extra invocation in the fixed loopback recipe, which selects the assessment
  tool and disables MCP, but the general exported caller accepts broader config.
  Do not claim whole-workload egress confinement. New untracked P30 source and
  test files are not included in `worktree.patch`; preserve the workspace.
- The corrected conservative P30 headless tests finished in exec session
  **60622** via
  `_build/verification/p30-conservative-native-candidate-20261107-01/run-headless.sh`
  (SHA-256 `554402dfd741c6b3fe9ba37423644122e80350c15eae21335e296d58194c8566`).
  The test-only correction asserts the required subscriber's unknown result
  and unconfirmed close, keeps clean no-subscriber continuation tests, and
  checks read-only fence/Saved reconstruction without issuing another action.
  The separate fixture and its patch were independently reviewed. All seven
  selected tests passed. Independent audit found one fence attempt per journal,
  at most one decision request, nine valid recorded release receipts, no
  recorded process groups or listeners, and no open scratch files. Four
  subscriber outcomes remain unknown with no later release intent; preserve
  their original roots and locks. Three other roots were deleted after an
  initial audit and byte-verified evidence copy; a later audit found two had
  unmatched invocation intents. Their original lock inodes are gone, so their
  outcomes cannot be inferred from the retained copies. No terminal-input materializer was
  included, and the original failed run remains unchanged.
- An isolated combined baseline build finished in exec session **70682** at
  `_build/verification/p31i-combined-baseline-20261107-01`. It starts from
  `2337e1ba` and selectively includes root P31I draft changes, the consent
  optimization and the corrected Word boolean fixture; it omits unrelated WIP
  and is not the final goal candidate. The first offline build stopped before
  compilation because the Hex registry cache was absent; a retry with the
  isolated cached registry passed. Elixir 1.18 formatting, strict compile,
  credential-free demo and test-environment strict compile also passed. The
  later full suite must wait for the active
  operator-input lock. See the candidate README for scope and limitations.
- A single fresh P30 consumed-fence cleanup diagnostic finished in exec
  session **15200** via
  `_build/verification/p30-fence-close-native-candidate-20261107-01/run-diagnostic.sh`
  (SHA-256 `be0495f7f8c39ec9c449aa55ee42ec24d6d1ac38efffabb7a6b776579fa24b20`).
  It compiles and runs in a separate private tmpfs root, uses no terminal input
  and preserves its fixture. The selected case failed its clean-close assertion;
  its trace shows consumed fence, `fence_refused`, successful Worker.close and
  sticky `event_cleanup_failed` before close returned unconfirmed. Scoped process
  and source checks passed; independent effects/receipt audit remains. Preserve
  the tmpfs root and do not replay. Its synchronous telemetry and
  state inspection can perturb timing and may omit failed captures, so it
  cannot reclassify the original P30 failures.
- The isolated headless P30 exact-action check finished in exec session
  **36242**, launched by
  `_build/verification/p30-exact-request-fence-20261107-01/native-preparation/run-headless-v1.enabled.sh`
  (SHA-256 `8490314bca6516b1da27feb362f78525a7004dd702d1732c1cc788e61d0bb360`).
  It uses a separate tmpfs root and omits the PTY materializer, which shares the
  active full suite's fixed operator-input lock. Compile, fence and policy stages
  exited zero; the decision stage exited 2 with 3 of 7 passing and four cases
  returning `cleanup_unconfirmed` at close after same-ID resume. All fixtures
  remain under `/run/user/1000/ipse-fence-headless-20261107-01`. Scoped host
  checks found no recorded process-group members, matching helper or open
  scratch files. Read-only journal review found each failing Session had
  already recorded a required extension-event result as unknown with cleanup
  unconfirmed; Session intentionally keeps that cleanup state sticky and
  declines to issue a clean release. The fixture's subscribed job proposes a
  decision after the fence was consumed; the fresh diagnostic above observed
  refusal and worker close in a new case, but cannot reclassify these originals.
  Review found no P30 requirement for clean recovery after this required job's
  unknown outcome. Separate no-subscriber cases already test clean same-ID
  continuation. A corrected test candidate is being prepared to assert the
  unknown and unconfirmed close instead of demanding success; do not weaken host
  unknown handling or claim subscriber recovery. Independent effect/receipt
  audit remains in progress. Preserve
  unknown effects and do not replay. Private logs may contain synthetic
  confirmation data. This is not P30 completion.
- A retained-fixture CollectionStore diagnostic is prepared at
  `_build/verification/collection-close-native-candidate-20261107-01`. Its
  fresh synthetic case passed, but its observation showed the Session was
  already down before the conditional close, so it did not reproduce the
  original error. Independent audit found its interrupted append still unknown
  and a `.pending` Collection file in its retained tmpfs root; preserve that
  entire fixture and its locks. Scoped process checks are in its README. Its
  instrumentation may perturb timing and cannot identify the original deleted
  fixture or prove receipt authenticity.
- The active `77563` full regression has now reported eleven failures. Nine
  document cases fail on the same `docx_bullet_session` boolean fixture defect
  already corrected in the root worktree and earlier `5e87be95` candidate.
  The consent timeout remains. A CollectionStore Session test also returned
  `{:error, :cleanup_unconfirmed}` when closing after deliberate native
  publication uncertainty. Its test teardown unconditionally removes its
  synthetic root, so the original effect/cleanup cannot be inferred or replayed;
  read-only review confirmed the journal had recorded the append as unknown
  before close returned `cleanup_unconfirmed`. The log does not identify which
  close boundary failed and the fixture ID was not logged. A separate retained
  diagnostic is being prepared; do not replay the original. The active
  run remains live and is not a passing baseline.
- The P31I cancelled-draft carryover candidate from
  `_build/verification/p31i-chat-completions-draft-20261107-01/source` is now
  integrated as uncommitted root work. It covers Chat Completions for OpenRouter
  and local OpenAI-compatible routes, and Responses replay for both xAI modes.
  Three root host modules compiled strictly and eight permanent projection tests
  passed directly. The untracked new test is
  `test/ipse/session/draft_chat_completions_projection_test.exs`; it is not in
  `worktree.patch`. Five changed Elixir files pass the 1.18 formatter check;
  the scoped docs checker passed 1,322 files and 10,589 links. Independent
  static review found no concrete replay-key or tool-call isolation bypass, but
  actual Session/Saved, loopback, installed and live-provider behavior remain
  partially unverified. A first concurrent, isolated chat Session run passed
  the positive two-provider case but failed the malformed-data case at Session
  startup because its synthetic OpenRouter config lacked a pinned profile. The
  run exited 2 and its two private fixture roots remain retained under
  `/run/user/1000/ipse-p31i-carryover-chat-20261107-01`. A scoped check found
  no matching process group or helper command and no open scratch files; this
  is not a complete detached-process audit. The corrected malformed case then
  passed once with a fresh fixture; three xAI-tagged Session cases passed in
  another fresh run with synthetic credentials. Scoped process/helper/open-file
  checks and source comparisons passed for both. The corrected full chat tag
  subsequently passed two tests in a fourth fresh root; an independent audit
  observed no recorded process groups, listener ports or open scratch files in
  all four runs and is reviewing retained effects. Twenty-two synthetic journals
  and release receipts from the three successful runs were copied without auth
  or lock files to the candidate's private `success-evidence-01` and each was
  independently byte-compared; the three successful scratch roots were removed
  after process/open-file audit, while the failed root remains. Whole operator/developer
  manuals were reviewed for this increment, the shared replay namespaces were
  corrected, and the docs checker passed 1,323 files / 10,593 links. The new
  untracked dated record is `docs/archive/2026-10-26-p30-p31-implementation/p31i-provider-draft-carryover-20261107.md`
  and is not included in `worktree.patch`. Final integrated verification remains.
  Do not replay the old fixture. The first attempted direct test loaded zero tests; see
  `_build/verification/p31i-draft-root-compile-20261107-01/README.md`. A
  separate focused source for the unrun Session checks is prepared at
  `_build/verification/p31i-carryover-native-candidate-20261107-01`; it has
  not been built and is not a final integrated source candidate.
- The Research host slice in `_build/verification/research-host-slice-20261107-01`
  has progressed beyond its original design to an isolated disabled prototype:
  host selection, bounded request construction, registered send draft and
  reconstructed inline evidence have pure/worker-VM controls. The export stays
  refused. Static review found a real saved-result exposure if a result is
  recorded but delivery expires. The prototype currently refuses all completed
  guarded-result restores while a usable later-use fence is developed. An
  isolated version-8 supplied-source dependency now joins the existing lineage
  and current-use barrier without inventing managed consent. An isolated
  purpose-specific no-Collection worker-input controller is wired in the draft.
  Independent review repeatedly found clock-floor gaps across Session, native
  input, transport and final delivery. The author recommends freezing this
  disabled prototype rather than patching isolated samples: the full goal needs
  a reviewed owner-bound use/clock lease, current-use/replay integration and
  an actual Session journey. Mixed dependencies, ordinary recovery and actual
  Session/socket behavior remain open. No real Session, socket or native test
  has run for this slice; do not treat a historical-only path as completion.
- A focused native-test candidate for the consent optimization is prepared at
  `_build/verification/consent-perf-native-candidate-20261107-01`. It includes
  the original unchanged compaction test and a separate teardown-only retained
  copy. Its README records an initially skipped patch and the corrected,
  byte-verified application. No native or Mix test ran; a retained-copy result
  cannot qualify the exact original test or the failed full suite.
- Independent retirement-test review found that protected Transaction ignores
  `IPSE_RUNNER_PATH` and checks the app helper digest embedded at compilation.
  The normal and instrumented checks need separate fresh builds with their
  intended helper present before host compilation. It also found an unsafe
  numeric-PID kill in one owner-control-loss fixture. The candidate and overlay
  now close the exact Session-owned Port instead; the revised case is unrun and
  tests Port closure rather than abrupt OS process death. The test's staged
  gates and cfg-gated native hook now fail closed on timeout; the revised Rust
  parses, but no native behavior has run. See the fixture review.
- The root worktree has an uncommitted consent-write performance candidate in
  `lib/ipse/extension/consent.ex`. It removes the duplicated pre-write state
  traversal while retaining complete validation in `encode_control/2` before
  staging or switching the new state. Pending reclamation may happen earlier.
  The isolated candidate compiled strictly and passed four pure and two mocked
  differential controls, repeated against the root source with a reconstructed
  HEAD baseline (the pure check emitted malformed-range warnings); synthetic 25,000-row samples
  improved, but the regression timeout's cause remains unproven. No native
  test has run and this is not yet a completed or pushed change. See
  `_build/verification/consent-perf-isolated-20261107-01/README.md`.
- A focused retirement test source has been prepared at
  `_build/verification/retirement-candidate-5e87-20261107-01`: it applies the
  isolated owner-fence overlay to baseline `5e87be95` without copying unrelated
  root Collection lineage WIP. Its README records the scoped input inventory
  and unrun tests. Seven host modules compiled directly with warnings as errors;
  afterward the owner-loss hook test was fixed to wait for the Session's DOWN
  before releasing the hook, and selected synthetic test fixtures were set to
  remain for audit on failure. It predates newer P30/Graph/Research work and is
  not the integrated final candidate. No helper or Mix test ran in it.
- Review fixed a missing memory-floor check in the still-disabled P30 native
  launcher. Consult its updated preflight and script hash; no launcher stage
  has run, and revalidation after the active regression is still required.
- A second, in-memory consent timing observation measured one 25,000-row
  `encode_control/2` at 876 ms on two schedulers; the workload performs three
  writes per successful iteration. This suggests a possible timeout mechanism,
  but does not reproduce the fixture or prove its cause. See
  `_build/verification/consent-timeout-diagnostic-20261107-01/pure-encode-observation.md`.
  Do not raise the timeout or treat the failed regression as passing.
- Independent static review of the P30 exact-action replay and egress boundary
  found no concrete bypass within its reviewed scope; see
  `_build/verification/p30-exact-request-fence-20261107-01/REPLAY-EGRESS-REVIEW.md`.
  Native Session and materializer checks remain unrun.
- The isolated retirement overlay now includes an unrun positive imported-
  control Session test and separately tagged, instrumented native before- and
  after-decision owner-loss controls. The latter require a fresh test-hook
  helper and must preserve unknown effects. Static review caught and the draft
  fixed a poison-termination handling gap; runtime qualification remains open.
- The Research host-boundary design is recorded at
  `_build/verification/research-host-slice-20261107-01/DESIGN.md`. It remains
  a proposal, not an implementation or P31H acceptance. A provided-source
  slice needs actual registered transport, current-result and saved-history
  binding; worker clock sampling alone does not enforce those boundaries.
- The active `77563` Graph/Research full regression has reported one failure:
  `ConsentCompactionTest` timed out after 180 seconds in its large synthetic
  65-iteration publish loop. The same unchanged test passed in the earlier
  `5e87be95` full run; the timeout cause is unconfirmed. Keep polling the live
  handle and do not classify the new run as passing or retry while it is active.
  Its test teardown can remove its synthetic fixture on timeout, so a future
  diagnostic needing retained state must use a separately documented test-only
  cleanup change; do not call that an unchanged-test pass.
- A test-only, unrun consent-timeout diagnostic is prepared at
  `_build/verification/consent-timeout-diagnostic-20261107-01`. Its only test
  change retains the synthetic fixture; the original workload and 180-second
  limit remain. It needs separate supervision and an independently audited
  fresh fixture after the active suite ends. It cannot turn the failed suite
  into a pass or replace a later unchanged-test/full-baseline qualification.
- The isolated P30 exact-action prototype now binds parent arguments in its
  version-2 fence and derives the expected request, rubric and admitted
  catalog identity before Session startup. Direct tests passed 10 fence and
  40 assessment controls, including policy request and 6,144-byte boundary
  parity; both sets passed again after the changed host modules compiled
  together with warnings as errors. Native parent-only mismatch and shared-artifact retention controls
  are drafted but unrun. Its old launcher inventories are stale. See
  `_build/verification/p30-exact-request-fence-20261107-01/ASSESSMENT-PROTOTYPE.md`.
  It is not integrated or native-qualified, and does not prove complete
  workload/source provenance.
- A separate one-candidate P30 materializer test is drafted and independently
  reviewed, but not run. Its changed-rubric case refuses before Session startup;
  its short loopback probe is not general network isolation. The generic fence
  test launcher does not include this materializer. Updated source inventories,
  actual native execution and independent process/effect audit remain necessary.
- A disabled combined P30 native launcher and scoped input inventory now exist
  under `_build/verification/p30-exact-request-fence-20261107-01/native-preparation`.
  It has not run. Its signal-handling review removed manual signals to possibly
  reused process groups; an interruption or missing result still needs independent
  cleanup/effect audit. Read `COMBINED-PREFLIGHT.md`, review the complete launcher
  and recheck all inputs only after the active suite has ended. The retained
  2,000-note notebook remains out of scope.
- A purpose-bound native document-retirement owner-control change is being
  developed in `_build/verification/retirement-lease` only. It has not been
  native-tested or integrated; do not treat an overlay, PID check or existing
  live-owner registry as proof of final-switch ownership.
- The tested document-retirement live-owner source and test hunks from
  `5e87be95` have been merged into the root worktree without replacing the
  staged Research record. The oversized synthetic test input was corrected to
  the previously passing size, and the separate DOCX optional-tag fixture fix
  was also applied. The relevant host files and selected tests byte-match the
  earlier candidate; a fresh direct schema run passed 11 tests and the scoped
  docs check passed. The earlier native and full-suite evidence predates the
  current merged worktree; no new native retirement test ran while the
  Graph/Research regression is active. Native owner lease through the final
  switch, unknown effects and commit/push remain open.
- A new full regression is running in unified exec session **77563** against
  isolated snapshot commit `2337e1bae486157d30096ab39c85b0e07de4ece7` in
  `_build/verification/worker-time-baseline-5f321eb2-20261107-01/source`.
  It includes the Graph and Research worker fixes on top of pushed `5f321eb2`,
  but omits unrelated root Collection/retirement WIP. Build, Elixir 1.18
  formatting, strict compile, credential-free demo, docs check and separate
  Graph/Research artifact builds passed before dispatch. Its test runtime was
  compiled separately and pinned. The launcher explicitly excludes
  `native_integrated_full`, `native_integrated_smoke` and `recall_many`; no
  declined notebook check is authorized. Poll the live handle, never retry on
  silence, and treat missing status/interruption as unknown. Private logs may
  contain synthetic confirmation codes; inspect only sanitized summaries.
  Audit processes, lock, port, source/runtime seals, temporary census and test
  outcomes before cleanup or another native test.
- The focused Graph integration run passed four tests on the root worker source.
  An independent audit confirmed the observed process group, checked lock/port
  and open files were clear. Its synthetic owner-loss case intentionally leaves
  one unknown State effect; keep its original journey and lock under
  `/run/user/1000/ipse-graph-time-focused-20261107-01` until resolved or
  explicitly dispositioned. A duplicate artifact was removed after byte comparison.
- Research had the same sampled-clock rollback gap as Graph. The controlled
  fake-clock test first reproduced a 199-to-198 rollback as an incorrect `ok`.
  The uncommitted worker now carries its pre-rerank sample through the
  continuation and requires subsequent publication samples to be nondecreasing.
  The focused domain wrapper passes, including inline, paged, cross-rerank
  and explicit historical controls; Elixir 1.18 formatting, scoped docs and a
  fresh `research/mcp-model` artifact build pass. Scoped source review found no
  concrete regression. These are worker-only checks: host dispatch and delivery
  fences, the full current-source baseline, and commit/push remain open. The
  earlier full regression predates this change.
- The Graph worker result-time increment from the passing candidate is now in
  the root worktree, including new untracked test/support and archive files.
  Independent review found that a sampled rollback remaining above the selected
  time was missed. A new control first failed, then passed after the second
  sample was required to be at least the first; the test also covers a first
  sample at expiry. The focused wrapper, Elixir 1.18 format comparison, scoped
  docs check and fresh `graph/state-explicit` artifact build pass; scoped source
  review found no further concrete regression. The old `5e87be95` full suite
  predates the rollback fix. No real MCP, Session-delivery or installed test is
  implied; relevant full baseline checks and commit/push remain open.
- The user approved the targeted Collection SDK index update. Its reviewed
  correction is committed and pushed as `aaef8038`. The scoped P30 route-binding
  increment was integrated, committed and pushed as `5f321eb2`; the staged
  Research record and other worktree changes remain. The home restart patches
  were refreshed against the new HEAD. Neither P30 nor P31 is complete.
- The guarded regression on exact local commit `5e87be95` has now finished:
  exit 0, **4,340 passed, 130 skipped, 132 excluded**, in 9,796.7 seconds.
  Its recorded post-run source/runtime seal, launch inputs and toolchain
  inventory matched; the toolchain inventories independently compare equal.
  The process group, shared Input lock and known listener were empty on a
  separate host check. A further independent audit is pending before cleaning
  the private `/run/user/1000/ipse-next-integration-662ca1b9-20261107-01`
  fixture tree or starting another native test. This result covers that local
  candidate, not later root changes or the excluded opt-in paths.
- Since the prior handoff update, the isolated P30 route-binding draft in
  `_build/verification/p30-route-binding-only-20261107-01/source` was extended
  to include Ollama context and model pin, Anthropic's fallback token limit,
  response-size limit and optional response schemas in its selected main-route
  digest. The latest direct pure run passed 37 tests; docs and Elixir 1.18
  formatting checks passed. An earlier revised test failed on an invalid
  synthetic version string and was corrected; retain that separate failure.
  The old native launcher source inventory is now stale and must not be used.
  Read `EVIDENCE.md` in that packet. Independent review found that the frozen
  decision profile timeout is a ceiling, not a fixed request timeout; docs now
  state this. Actual request provenance and broader integration remain open.
- The revised P30 route-binding draft subsequently passed its one fresh
  synthetic native Session test (seven main requests and one known-settled
  decision request). Source/runtime/system seals matched after execution;
  the process group, checked lock/port and open-file audit were clear. Minimal
  synthetic receipts, two journals and control snapshots were byte-verified
  under `native-protocol-01/evidence`, then the 1.8 MiB private scratch was
  removed. See `native-protocol-01/AUDIT.md`. This does not qualify real model
  quality, exact pre-dispatch rubric binding, full workload provenance or the
  final baseline. The candidate archive and plan were updated after the run,
  so the old launch inventory no longer represents the current source tree.
- `_build/verification/p31-research-expiry-test` contains a fresh synthetic
  one-source Research host-dispatch diagnostic and README. It has only been
  formatted and compiled with ExUnit autorun disabled, never run. It restores
  the saved journal and checks the approved action/result pair, but deliberately
  treats a refusal with zero dispatch as causally unconfirmed: the current host
  lacks an established source-expiry-specific refusal. It does not qualify
  result delivery or source-set completeness. No retained notebook is involved.
  Read the README and independently audit prerequisites before any native run.
- Research source expiry across actual host dispatch and delivery remains open.
  Existing extension descriptors do not establish a host-owned, complete
  source-time contract; do not mistake a worker-supplied deadline or digest for
  authority. Provided-source arguments can be inspected at admission, but MCP
  fetches and the worker's actual inputs need separate attribution. Any new
  contract must be bound to the admitted artifact, options and invocation, and
  enforced at actual send and result delivery without widening permissions.
- The completed guarded regression for exact local commit `5e87be95` has
  evidence in
  `_build/verification/p31-next-integration-662ca1b9-20261107-01/run-01`.
  Its 518-file census and source/runtime seal passed before dispatch; the
  integrated full/smoke and recall-many opt-in tags are explicitly excluded.
  Its private raw log may contain synthetic confirmation codes. Audit exit
  status, summary, seal, process
  group, input lock, port and temporary fixture census before further native
  tests. Clean only completed owned scratch; preserve unknown outcomes.
- After the user resumed work, the isolated `ae7297c3` integration candidate
  built successfully and passed 16 focused controls and 11 retirement Session
  controls on supported tmpfs. A first four-file run on workspace Btrfs failed
  three filesystem-admission controls; it remains a separate failed result.
  The clean Elixir 1.18 formatter check, docs checker and credential-free demo
  passed. See `_build/verification/p31-next-integration-662ca1b9-20261107-01/evidence/focused-result-20261107.md`.
- The interrupted earlier full-suite log contains nine document-acquisition
  failure headers caused by a strict boolean operator on an absent test tag.
  That fixture has a one-line correction in the isolated
  integration checkout. The full acquisition file passed 29 tests, with one
  skipped and nine excluded; a separately included tagged control passed one
  with 38 excluded. Elixir 1.18 formatting for the corrected file passed, and
  the private runtime scratch was removed after fixture preservation. See
  `evidence/word-optional-tag-test-20261107-01/EVIDENCE.md` under that packet;
  do not print its private logs. The fixture and manual corrections are now
  locally committed as `5e87be9504d74ef9bad511f773a1e122210c790d`; this is
  not on the root branch or origin. The new guarded run is described above.
- Whole-manual review found a stale private-group-append claim in the sealed
  candidate's Collection SDK chapter. A proposed, checked documentation-only
  correction is `_build/verification/p31-collection-sdk-editorial-20261107-01/group-append.patch`;
  apply/review it after the sealed run, not while the source seal is active.
  The corresponding two-paragraph correction is now applied and reviewed in
  the root worktree. The scoped root docs checker passed 1,319 files/10,576
  links after excluding unrelated untracked fixture checkouts; an earlier
  unscoped check failed on those unrelated checkouts. Automatic approval review
  rejected the proposed alternate-index commit command because its targeted
  primary-index reset could unstage existing work. The user subsequently
  approved the targeted update, and the correction was committed and pushed
  as noted above. Preserve the staged Research record.
- A one-source replacement continuation of the 1,000-source synthetic model
  passed and was independently reconciled; evidence is in
  `_build/verification/document-replacement-resume-20261107-01/EVIDENCE.md`.
  The public backup planner's 32-record/128-operation limits cannot migrate
  its 5,289 records and 20,398 prior receipts. Actual native capacity and a
  safe authenticated, resumable migration remain open.
- An isolated one-original-Session result-grouping prototype is in
  `_build/verification/p31-document-migration-20261107-01/source`, based on
  `ae7297c3` and not included in the regression. Its three pure shape/byte
  controls and five retained-result-tree budget controls passed; native Session
  and nested-budget tests are unrun. The budget is scoped to a nested callback
  tree, not every read in an effect or an entire invocation; source-page reads
  and decoded memory are not directly measured. Actual multi-Session Restore
  compatibility and its page rescan have three prepared, unrun Session tests.
  Page geometry and uncertain-cleanup retention were corrected after review;
  generic refusal still does not prove budget causality. See
  `RESTORE-BUDGET-OBSERVATION-DESIGN.md` in the migration packet. A test-only
  isolated-VM trace helper has two passing synthetic self-controls but has not
  been connected to actual Restore tests or independently qualified.
  A 4 MiB
  aggregate raw-input limit is not itself a measured decoded-memory bound.
  A pre-existing nested source-read budget concern also remains unverified.
  The binding is explicitly not a
  transferable lease or migration authority, and the existing single-result
  refactor needs compatibility and adversarial review. See
  `_build/verification/p31-document-migration-20261107-01/RESULT-GROUP-PROTOTYPE.md`
  and `FEASIBILITY.md`; do not integrate it as a complete migration path.
- An isolated P30 assessment preflight reproduction in
  `_build/verification/p30-assessment-route-20261107-01` showed that a v1
  frozen declaration still accepts a changed synthetic decision endpoint and
  service ID when engine/model match. Later consent/route membership is expected
  to refuse an unapproved route; this is not proof of unauthorized egress. A
  versioned route-profile binding repair is being developed separately and is
  not included in the active regression. Independent review also found that
  generic preflight checks only the shape of frozen source/runtime digests and
  compares the rubric after the action. Actual code/runtime binding and an
  authentic pre-egress request fence remain open; no paid call was made. The
  isolated v2 draft passes 35 direct pure tests (one excluded) but uses sampled
  inventories and BEAM MD5 observations, not complete loaded-code proof or a
  retained anti-TOCTOU fence. A generic exact-request fence also needs an
  enforced saved-session compatibility gate; older binaries ignore unknown
  header fields. A separately isolated fence prototype is under
  `_build/verification/p30-exact-request-fence-20261107-01/source`; it uses a
  new compatibility generation and has 17 standalone fence/delegation controls,
  and a warning-free direct compile against copied matching BEAMs. It still
  needs a clean Mix build, replay, native approval/dispatch and owner-loss
  verification. A standalone profiled-route attempt ran the wrong selection in
  an incomplete environment and failed 13 of 17; it is not a pass. Review
  also found active-parent replay state needed to reset on cancellation,
  non-ok turn end and a new user message; a draft repair has pure controls and
  awaits independent review and real Session tests. Do not integrate or
  qualify the partial drafts as complete.
- A separate route-only P30 increment based on root `662ca1b9` is prepared at
  `_build/verification/p30-route-binding-only-20261107-01/source`. It binds the
  dedicated assessment's public advice profile and selected main-route fields,
  retains v1 reading/scoring and refuses v1 for new Session work. Thirty-four
  direct synthetic controls pass against the p31-built runtime; independent
  code and whole relevant manual reviews found no new concrete blocker, and the
  docs checker passed 1,318 files/10,578 links. Its native protocol test remains
  unrun while the main regression runs; a disabled launcher and point-in-time
  inventories are in `native-preparation/` and require fresh source/runtime and
  native ownership checks after the suite. Source/runtime authenticity, rubric
  pre-egress and independent quality remain open; it is not milestone completion.
  Root plan and archive index contain unrelated working/staged changes; preserve
  them if integrating, committing or pushing this increment.
- HEAD and origin both pointed to
  `662ca1b9c30e0893f68e1410b72e90ac112bf2ee`; the saved staged and unstaged
  patches in `~/ipse-tmp` matched the root worktree. The handoff and patches
  are backups, not a substitute for preserving the repository and its ignored
  `_build/verification` directories across restart.
- The guarded full suite described below no longer has its session 27630 or
  supervisor PID 353491; its process group was empty at the latest host check.
  It has no `run-01/status.txt` or `outer-summary.txt`, so its result is
  incomplete/unknown, not a pass. Preserve the packet. Before another native
  run, independently audit the fixture input lock, listener and any detached
  processes. Its private log can contain synthetic confirmation codes and
  must not be printed.
- The latest host audit found no user of `/tmp/ipse-operator-1000/input.lock`,
  no listener on TCP 39657, and no visible process whose working directory was
  inside that candidate. This is a point-in-time check, not proof that all
  detached processes are absent; repeat resource checks before dispatch.
- A later, uncommitted P31I slash-input draft and prepared native PTY fixture
  reside in `_build/verification/p31i-draft-slash-20261107-01/source`. Three
  pure classifier/replay tests passed with unrelated compiler warnings; no clean
  build or native PTY test has run. The PTY fixture covers slash-path input,
  replacement, acceptance and restore; its later unrun revision also exercises
  terminal `/cancel` and refusal of an `/enhance ...` first line. Supporting
  that literal first line requires
  further durable entry/replay design; do not claim full P31I acceptance.
  The two Elixir fixture files parse with system Elixir 1.20; this is only a
  syntax check, not the required Elixir 1.18 formatter, build or PTY test.
  The modified Rust PTY driver also parses with `rustfmt --emit stdout`; this
  does not compile or run it.
  Serialize native/Mix/PTY tests with the full suite.
- Recheck current memory rather than using the historical reading below.
- The user requested only necessary copies in `~/ipse-tmp`. Existing retained
  copies are not permission to read or replay the declined notebook. Do not
  delete prior evidence or assume copies preserve inode-based authority.

## Post-restart update

- P30's critical-recall correction was independently reviewed, passed 31 pure
  tests, and was committed and pushed as `548d3e25`. Refused critical rows now
  remain unmeasured, with comparison withheld. This does not complete P30.
- P30's bounded-cost correction was independently reviewed, passed 33 pure
  tests, and was committed and pushed as `662ca1b9`. Missing or JSON-unsafe
  aggregate costs remain unmeasured; independent support improvement remains
  a separate benefit branch. This also does not complete P30.
- A public synthetic test confirmed that a fresh approved partial-retirement
  action could continue after its original Session owner died and the same ID
  resumed. A scoped live-owner registry repair and Research timing repair were
  frozen together in isolated verification commit
  `dbea54e73c9e4d34f1585bc5aa945fc3a6e909b3` under
  `_build/verification/p31-integrated-candidate-4f4c1255-20261107-01/source`.
  Their focused tests, canonical formatting and documentation checks pass.
  Native final-switch owner-loss liveness, general recovery and full milestone
  acceptance remain open. This candidate excludes the incomplete notes draft.
- One guarded default full suite for this candidate was started under unified
  exec session **27630**, with its private state in that verification packet's
  `run-01` directory. The latest state is described above. The
  opted-in 2,000-note Session/day check is disabled. Logs may include synthetic
  confirmation codes and must not be printed. The suite predates P30 commit
  `548d3e25` and `662ca1b9` and cannot qualify the full current source.
- Root worktree Research, notes and draft tests remain uncommitted. The scoped
  retirement repair is in the isolated candidate, not yet in the root worktree.
  A separate untested exploration of native final-switch fencing is under
  `_build/verification/retirement-switch-fence-dbea54e7-20261107-01/source`;
  it must not be integrated or claimed complete without the full protocol and
  native failure tests. The latest formatted patch is
  `_build/verification/retirement-switch-fence-formatted-dbea54e7.patch`, SHA-256
  `f2c7805d81acb3419fdc3f550c760b9d4e5a017b358f08d484a8f64ab1a0d853`.
  Its 13 Elixir files were formatted with Elixir 1.18 and compared by syntax
  tree and comments against the preserved pre-format patch; the Rust file was
  byte-identical. This is not a Mix formatter check, compile or test. Legacy
  saved and non-Linux multi-stage compatibility, an
  unfenced legacy one-step fallback, and unknown outcomes after the native
  decision remain open.
- A separate Graph worker timing candidate is under
  `_build/verification/p31g-graph-result-time-20261107-01/source`. Its eight
  pure synthetic tests pass, including a fake MCP callback and paged result.
  It is not in the running suite and does not establish original-file authority,
  real MCP transport or Host delivery. Relevant manuals and documentation checks
  passed in that isolated candidate; an independent source review found no new
  actionable regression. It still needs a clean build and integrated checks.
- A later isolated integration checkout combines pushed P30 commit `662ca1b9`
  with the reviewed Research, scoped retirement and Graph changes at local
  commit `ae7297c3`, under
  `_build/verification/p31-next-integration-662ca1b9-20261107-01/source`.
  Its implementation and test files match the reviewed candidates and offline
  inputs are prepared. An independent source/commit comparison found no lost
  changes or conflicting claims, and its documentation checker passed 1,320
  files and 10,583 links. No build or tests have run on that checkout. It also
  excludes the unfinished notes draft. The live full suite is for the earlier
  `dbea54e7` candidate, not this newer integration.

## Workspace state

- Repository: `/home/lexlapax/projects/lexlapax/ipse`, branch `codex/p30-p31`.
- Last pushed commit: `662ca1b9c30e0893f68e1410b72e90ac112bf2ee`.
- The worktree contains substantial unfinished, uncommitted changes. Preserve
  them. One evidence file is staged:
  `docs/archive/2026-10-26-p30-p31-implementation/research-time-boundary-20261107.md`.
  Inspect both `git diff` and `git diff --cached` after restart.
- Research's worker-side source-eligibility draft is in the root worktree; the
  later isolated `dbea54e7` candidate passed its focused controls. Host dispatch
  and Session delivery still lack a complete authenticated source-set fence.
- The future-lineage notes authorization draft spans
  `lib/ipse/cli/knowledge/management.ex`, `lib/ipse/extension/collection.ex`,
  `lib/ipse/extension/collection/managed_pages.ex`, `managed_retention.ex`,
  `lib/ipse/runner/management_terminal.ex`, `review.ex`,
  `lib/ipse/session/managed_lifecycle.ex`, and their modified tests. It is
  incomplete and intentionally **fail-closed**: no CLI route or normalizer
  enables it, and v3 current-use interpretation refuses. It has not had a clean
  compile or native end-to-end tests. It still needs authenticated scope and
  source leases, a reviewed format upgrade/rollback, expiry at publication,
  replay/current-use enforcement and full adversarial verification.
- The same-ID retirement owner issue was confirmed through the corrected public
  synthetic fixture; the scoped repair is tested in the isolated `dbea54e7`
  candidate. The root worktree's separate reproduction drafts remain unrun.

## Required boundaries and pending decisions

- The user explicitly declined a recall check on the retained 2,000-note
  synthetic notebook. Do not access, renew, replay or run an equivalent
  replacement consumer as a workaround. Preserve its 2,100 operation records
  and unknown outcomes. This leaves populated recall and annual integrated
  workload qualification open; continue other work independently.
- At the user's restart request, byte-for-byte copies of the documented
  retained synthetic root and forensic backup were placed under the private
  `/home/lexlapax/ipse-tmp/` directory, along with this handoff and patches for
  staged and unstaged changes. The copies do not preserve the originals' inode
  identity or authorize recall/replay. The original roots may disappear when
  `/tmp` is cleared. Six separate synthetic evidence directories were copied
  into `_build/verification/restart-preserved-20261107-01`; no claim is made
  that all temporary evidence was preserved.
- Automatic approval review rejected a proposed change adding
  `native_literal_lineage_retention` to the generic Collection mutation
  **refusal** condition. Its reason characterized that condition as an
  allowlist that could bypass the reviewed branch. The patch made no changes.
  User approval was requested but has not been received. Do not circumvent the
  rejection or enable the new normalizer while this guard is unresolved.
- An older pre-restart memory reading was 2,399,328 KiB available. Established minimums are
  2,621,440 KiB for formatting/docs and focused pure checks, 2,883,584 KiB for
  native/build tests, and 3,145,728 KiB for the full suite. Recheck immediately
  before dispatch; do not lower thresholds, kill unrelated processes or drop
  caches. The later environment had substantially more memory, but must still
  be checked afresh after restart.
- `/tmp` has encountered user quota failures even when `df` reports free space.
  `/run/user/1000` is a private tmpfs but has also seen a failed script setup.
  Preserve failed and unknown outcomes. Do not delete retained fixtures or
  evidence merely to recover space. Check actual quota/write availability.

## Verification and next actions

1. Recheck memory, filesystem/quota, `git status`, existing processes and the
   pending approval. Preserve all changes and failed/unknown effects.
2. Preserve the guarded suite's unknown result and recheck its resources; it
   produced no terminal summary. The confirmed public retirement reproduction
   and `dbea54e7` focused tests need not be repeated solely because older steps
   requested them.
3. Once its resources are clear, build and test the later
   `ae7297c3` integration candidate, then assess the remaining native
   final-switch fence and P31I work independently. Preserve failures and audit
   relevant processes, listeners and input locks.
4. Resolve the pending guard approval and complete the connected notes path;
   never infer authority from worker-provided proofs or reuse a consumed lease.
5. Prepare and run the full regression against the exact final candidate. The
   sealed `_build/verification/p31-combined-regression-8d29aec6-20261107-01`
   candidate predates commit `4f4c1255` and the current worktree, so it is not
   the final baseline. The previous full `3d409619` suite exited 2 with one
   failure; a separate focused fix passed, which does not change that result.
   Keep the opt-in 2,000-note Session/day test off in the default suite.
6. Complete the remaining P30/P31 acceptance items in `docs/plan.md`, whole
   operator/developer manual review, required source/platform/package/installed
   checks, adversarial post-implementation audit and reviewer handoff. Only
   declare completion after requirement-by-requirement evidence. Commit and push
   focused completed increments as `AGENTS.md` requires; never force-push.

The last completed documentation check (before the latest evidence edits) passed
1,316 Markdown files and 10,567 links. Re-run it after the current edits when
resources allow. Do not claim unrun tests, a clean build, platform support or
full milestone completion.

### 2026-11-08 isolated CLI resume suite in progress
The reviewed CLI census fingerprint is `4cdb5458676eb0da6f09c7be0751ee4f466f96e243dcb3d41fd29e47c3501e5b`. Audited duplicate cleanup left 2,151,968,768 bytes available on `/run/user/1000`; archived copies and lock files remain. The previous census `scratch/tmp` was not inspected because automatic approval review rejected that inspection. The enabled copy of the reviewed one-test launcher differs only by disabling its `exit 77` guard. Its suite started as exec session 66849, with receipts under `_build/verification/diagnose-resume-ninecase-registry-launcher-20261108-01/suite-cli-01`; do not rerun or clean the new fixture until outcome and independent postflight are known. Existing notebook and previous unknown outcomes remain out of scope.

CLI suite 01 finished: build exit 0, suite exit 2, supervisor exit 1; one selected test failed before resume because its newly written operator config omitted mandatory `"version": 1`. It is a test-only fixture error, not a passing resume verification. Guard found one failure, no skips, 61 exclusions; launcher cleanup is unconfirmed. Independent host postflight found no matching supervisor/build/suite groups, named runtimes, operator/input lock holders, or open scratch files. No fixture contents were inspected; preserve the entire failed run including unknowns and locks. A separate corrected candidate and fresh run are needed; do not reuse or clean the failed fixture or the rejected census scratch/tmp.

Corrected candidate `_build/verification/diagnose-resume-ninecase-config-version-20261108-01/source` adds only `"version" => 1` to the new CLI test fixture (manifest SHA-256 `3f37e383af774d2ffc0c7a177b164a143b6f1b98fd7536cb2d2b55e9edc4c235`). The original census identities were mechanically derived and checked against all unchanged test declarations with shifted line numbers; this is not a new census. A fresh single-test suite is running as exec session 53032, with receipts at `_build/verification/diagnose-resume-cli-config-retry-20261108-01/suite-cli-01` and new scratch `/run/user/1000/ipse-diagnose-config-retry-cli-suite-20261108-01`. The 1.8 GB minimum leaves over 1.3 GB after the previous comparable 636 MB usage. Do not rerun or clean this fixture before outcome and independent postflight. Removed only independently verified duplicate documentation from the failed CLI suite; its fixture and lock files remain.

Corrected CLI retry session 53032 exited 0. Guard and test log report 1 passed, 0 failed or skipped, 61 excluded; outcome `focused-suite-passed`, cleanup requires independent audit. This proves only the selected CLI resume behavior on the corrected isolated candidate. Independent process/lock postflight is underway; preserve its fixture until that audit and any authorized cleanup are complete. Managed-withheld two-case stage still requires census review and a guarded run.

Independent postflight of corrected CLI retry found build/suite/supervisor exits 0, pre/post source and toolchain inventories matching, no remaining matching suite processes, operator/input lock holders or open scratch files. Guard PID was self-reported; no independent live BEAM observer. Its duplicate source/docs alone was removed after independent equality and no-lock verification. The managed-question dry census started as exec session 38491, with receipts under `_build/verification/diagnose-managed-config-census-20261108-01/census-managed-01`; no test bodies run during census. Candidate integration patch `_build/verification/diagnose-root-warning-reconcile-20261108-01/root-warning.patch` is prepared but not applied, pending independent review and final combined-source testing.

After independent review and `git apply --check`, applied the 10-file warning reconciliation patch to the root worktree. It preserves the existing P30/P31 WIP and staged Research file. This combined root source is NOT covered by the isolated candidate's passing tests; focused and baseline verification remain required. `git diff --check` passes. Updated `~/ipse-tmp/restart-unstaged-latest.patch`; untracked files and the separate staged Research entry are not included in that unstaged patch.

Managed dry census session 38491 exited 0; independent review identified exactly two intended generated cases (managed question expiry and revocation), zero skipped, 204 excluded. No test bodies ran. Source/runtime/toolchain pre/post seals and synthetic Git head/tree/index match; no matching suite process, input/operator lock holder or open scratch file remained, though guard PID was self-reported and no independent live BEAM observer existed. Removed only its independently verified duplicate source/docs. The two-case actual suite remains unrun; current tmpfs available was 1,651,388,416 bytes after cleanup, so its preflight must use a realistically justified lower threshold (the comparable prior full synthetic run consumed about 636 MB) or recover further audited duplicate space first.

Managed census reviewed reference is `_build/verification/diagnose-managed-config-census-20261108-01/reviewed-census-managed`; independent identity review confirmed two selections, 0 skips, 204 exclusions. Added launcher-required source seal/review fields and rehashed the reference. Actual managed suite started as exec session 64448 using the corrected candidate and fresh scratch; receipts under `_build/verification/diagnose-managed-config-suite-20261108-01/suite-managed-01`. The launch required 1.6 GB free after 636 MB observed on the comparable preceding run; preserve new root on unexpected outcomes and audit before any cleanup.

Managed suite session 64448 exited 0; log reports 2 passed, 0 failed/skipped, 204 excluded, and launcher records `focused-suite-passed` with independent cleanup audit pending. These pass only the isolated corrected candidate, not combined root. P31H review found existing empty managed dependencies select unguarded worker calls and worker-sampled time is not host-owned; no claim of P31H qualification. A dormant receipt-only schema would not satisfy acceptance; actual source/time/send/output ownership and old-reader compatibility remain required.

Managed suite independent postflight confirmed supervisor/build/suite exit 0, 2 passed, 0 failed/skipped, 204 excluded, matching source/runtime/toolchain and synthetic Git inventories, and no matching suite processes, locks or open scratch files. Guard PID was self-reported; no independent live BEAM observer. Removed only verified duplicate managed-suite source/docs. The eight touched root Elixir files pass targeted `mix format --check-formatted` under Elixir 1.18.5/OTP 27 with isolated empty Mix archives. Full combined-root runtime verification and docs review remain open.

Combined-root focused input snapshot is `_build/verification/diagnose-combined-root-snapshot-20261108-01/source`, sealed selected-input manifest SHA `e3cb5f4091140393a2a7dcd699b626f4921a5693e78eae92e37ca532a73f7b35`. It includes 1,329 project build/test inputs, including untracked fence helpers, and omits docs and all old fixture trees; it is not a full-source baseline. A fresh workspace-disk working copy/build is being prepared; no combined-source test has yet passed. The P31F six-reply-tag fix is dormant without its matching retirement protocol, absent from current root, so it cannot be claimed or applied alone as completion.

The selected combined-root snapshot working copy/build is being prepared on workspace disk. Initial sandbox-view preflight stopped before any build claim due to system executable ownership appearing as 65534:65534 instead of the host seal's 0:0; a fresh elevated host-view preflight matched the complete unchanged seal and the build started under tracked supervision. Consult the build agent/receipts before any retry. Reviewed architecture and recovery whole documents; moved the saved-question explanation to architecture's question-recovery flow and refreshed the saved unstaged patch. A separate isolated current-docs link/manual check is in preparation.

Current integrated docs check passed in scoped synthetic Git snapshot `_build/verification/docs-root-snapshot-20261108-01`: 1,324 Markdown files, 10,604 links, manual/archive rules, 0 errors. Working-tree versions and scoped visible untracked files were included; hidden receipt trees excluded, and real index/staged Research untouched. Elixir emitted a locale warning. Combined-source build is compiling under host-view supervision; no combined tests have run yet.

Workspace-disk combined-source build `_build/verification/diagnose-combined-root-build-elevated-20261108-01/` completed exit 0: offline dependencies, 202 Elixir files, native helper and four inert bundles; source and host inventories matched pre/post and synthetic Git was clean. Process group 2747866 was empty per launcher; independent host audit is underway. This is a build, not a runtime test. A single-build, three-stage focused test/census plan is being prepared against the same source, with separate fresh synthetic test state and no declined recall or native opt-ins.

Independent combined-build postflight rechecked frozen and built selected source hashes, host source/runtime/toolchain inventories and baseline runtime/archive copies: all match. Build group/session 2747866 was absent; no named BEAM/helper, operator/input lock holder or open build-tree files were observed at audit time. No prior fixture access or deletion. The first combined-source core dry census may proceed, followed by independent selection review; actual focused tests have not yet run.

Combined-root core dry census `_build/verification/diagnose-combined-root-focused-20261108-01/core-census-01` exited 0, selecting six cases with zero skips and 114 exclusions; no test bodies ran. The separately audited built-source runner is `_build/verification/diagnose-combined-root-focused-20261108-01/run-focused.sh` SHA `2cfb61d013c70eaa81ab8cf6fec501dc2a83f47603dfcaf6fdf56fe40dc6f76c`. Exact selection, exclusions and cleanup are under independent review before the core suite. CLI and managed combined-source stages are not yet run.

Combined-root core census independently reviewed: six intended identities (warning, compacted-checkpoint unknown export, cancelled question, inert pending question, no-replay unknown operation and saved diagnosis counts), zero skipped, 114 unique reviewed exclusions. Source/runtime and isolated Mix/Hex seals reverified; no corresponding process group, helper, operator/input lock or open census files at postflight. Reviewed reference `_build/verification/diagnose-combined-root-focused-20261108-01/reviewed-core`, manifest SHA `90bc070dc7e8dfcce452e038daf03bb0d1f3e38ea4e6b05a671a69d57152395d`; actual six-test suite may now run. No new census passed tests.

The reviewed-core reference was supplemented with runner-required exact stage/source/build/exclusion binding fields; rehashed manifest is `dad72779d8bafae569cc8a8e7718032775a985be4f18e11ecd338d465fc36096`. This supersedes the prior manifest hash only; reviewed test lists were not changed. Core suite launch is pending. Separately prepared P30 synthetic recipe inventory-binding patch `_build/verification/p30-recipe-inventory-binding-20261108-01/inventory-binding.patch` (SHA `112a3e075bb605df449ed1209bb072007c5699609abcf2651724b330022c3584`); it has NOT been applied. Review found existing recipe already checks point-in-time inventories; the patch additionally binds them to declaration hashes, but helper-only tests do not yet prove real changed-file pre-dispatch refusal. It would cause old frozen recipes containing prior recipe bytes to refuse, and no old fixture may be replayed.

Combined-root core suite `_build/verification/diagnose-combined-root-focused-20261108-01/core-suite-01` exited 0: six passed, no failures/skips, 114 excluded. Independent postflight reverified source/runtime/Mix/Hex seals and matching identity lists; no suite group/session 2755180, BEAM/runner processes, operator/input lock holder or open suite files were observed. Guard PID was self-reported; no independent live observer. Combined-source CLI and managed tests still need their own reviewed censuses and runs.

Combined-root CLI suite `_build/verification/diagnose-combined-root-focused-20261108-01/cli-suite-01` exited 0 with 1 passed, 0 failures/skips and 61 excluded; exact reviewed identities and source/runtime/Mix/Hex seals matched. Independent host postflight found no suite group/session 2758045, named BEAM/runner, operator/input lock holder or open suite files; guard PID was self-reported and no independent live observer was available. Managed-question combined-source census and test remain.

Combined-root managed dry census independently reviewed: intended generated expiry and revoke cases, zero skips, 204 exclusions; source/runtime and Mix/Hex seals match, no matching stage group/session 2758784, BEAM/runner, operator/input locks or open census files. Reviewed reference `_build/verification/diagnose-combined-root-focused-20261108-01/reviewed-managed`, manifest SHA `96b868a72e90194addc99ccaff4ab590d8e90f8a4df79bf0f4da1b727d4fb260`. Its two-case suite is now running in a fresh stage copy; do not rerun or clean before outcome and audit. P30 inventory binding patch revised candidate `.../p30-recipe-inventory-binding-20261108-01/inventory-binding-v2.patch` SHA `5481297e4bc9fb30d13d2440e0b6dcdf8707f224e5f76bfd7b26deb0ce543c7f` remains unapplied; isolated actual-entry negative control passed and Elixir1.18 format passed, but positive materializer and later-race proof remain open.

Combined-root managed suite `_build/verification/diagnose-combined-root-focused-20261108-01/managed-suite-01` FAILED: first case setup returned `project_identity_filesystem_unsupported` on workspace-disk temporary filesystem; second failed closed on retain-withheld-question marker. Guard: 0 passed, 2 failed, 204 excluded, status unknown/cleanup unconfirmed. Independent host postflight found no group/session 2760354, BEAM/runner processes, matching operator/input locks or open suite files; source/runtime/Mix/Hex seals match. Seven fresh tmp entries and one retain marker remain preserved; their content was not examined. A source-based filesystem diagnosis and a fresh rerun using tmpfs only for new TMPDIR are being prepared; do not replay or remove failed run or earlier unknowns.

Managed failure cause confirmed: Linux 7.2.11-arch1-1's native protected storage profile permits qualifying tmpfs, not Btrfs; `System.tmp_dir!` placed prior fresh managed fixture on Btrfs. The failed fixture/marker remains intact. Fresh retry launched as exec session 16267 using identical sealed combined build and reviewed two-case selection, workspace-disk source/build and new private tmpfs `/run/user/1000/ipse-diagnose-managed-retry-20261108-01`; receipts `_build/verification/diagnose-combined-root-focused-20261108-01/managed-tmpfs-retry-20261108-01`. No old fixture was accessed. Await completion and independent postflight before claiming result or cleanup.

Fresh combined-root managed tmpfs retry passed 2/2, no failures/skips, 204 excluded; independent postflight matched source/runtime/Mix/Hex and reviewed identities, found no group/session 2762922, BEAM/runner, operator/input lock holders or open output/tmp files. Guard PID was self-reported with no independent live observer. The earlier failed Btrfs fixture remains intact with cleanup unconfirmed. Thus all nine narrowly selected combined-source controls pass across 6+1+2 cases; no broad baseline, P30/P31 milestone or previously declined recall is qualified by this. Updated `docs/plan.md` accurately; reran isolated `elixir dev/check-docs.exs`: 1,324 Markdown files, 10,604 links, zero errors. Full combined permitted baseline likely takes hours (prior comparable 2h45m), and qualified tmpfs headroom remains under assessment; previous full fixture peak was not measured.

Full-source snapshot `_build/verification/combined-root-full-snapshot-20261108-01/source` includes current docs and non-ignored project inputs, excluding hidden old fixtures and two ignored historical tarballs. File manifest SHA `8f576be6c963d5ddf4c6c01d3d9a234ed9fa7b88bf8c42f3e013dc607e0bcaa8`. To reclaim tmpfs without touching fixtures, archived and independently hash/node-verified four completed synthetic Git and build trees under `_build/verification/recent-synthetic-build-git-preservation-20261108-01/`, then removed only their archived non-lock regular copies; original compile.lock inodes and symlinks remain. Removed independently verified duplicate non-lock source/deps from three of those runs, preserving Cargo.lock/Jason mix.lock, telemetry and all fixture directories. Synthetic scratch Git requires archive restoration to reuse. After cleanup `/run/user/1000` had 2,065,420,288 bytes free. A full baseline fixture peak remains unknown and requires a bounded monitored run; never access the rejected census scratch/tmp or old unknowns.

Broad filtered baseline is NOT started. Agent audit found 296 represented test files containing deletion calls (including intentional in-test operations) and 251 files repository-wide with simple teardown deletions. Existing fixture flags do not cover all owners; e.g. managed collection, collection adapter/session, source window and Saved teardown can remove a fresh fixture before an unexpected unconfirmed effect is audited. User permits normal cleanup of new disposable synthetic tests including intentional unknown simulations, while unexpected unconfirmed outcomes remain to be preserved; no blanket interception or semantics-changing test edits were made. Adapted disabled full-baseline launchers exist but are not approved as proving this retention. A separate existing one-test P31F abort diagnostic census is being reviewed; no old notebook or previous unknown should be replayed.

Disabled draft full baseline scripts `_build/verification/combined-root-full-baseline-launcher-20261108-01/` contain both exit-77 and exit-78 hard stops: broad unexpected-effect fixture retention remains unproven and its low-space monitor is untested. No baseline build/census or test ran. Separate P31F single-test abort diagnostic dry census started under host view, exec session 30679, using independently sealed older retirement candidate and fresh scratch; launcher copy `_build/verification/retirement-abort-error-focused-20261107-01/run-census-space-v2.enabled.sh` SHA `16cf2095d43593375f19554fc2e52c30cf2ed7cf52fa35498fb09dff90177b74` has a 1.8 GB preflight justified by a comparable 636 MB run. Census does not execute test body; await result and independent audit. Never access old notebook or replay earlier unknowns.

P31F abort dry census independently reviewed: 1 intended selected, 0 skips, 88 excluded, no body run; host postflight had no matching processes, locks or open files. Reviewed reference `_build/verification/retirement-abort-error-focused-20261107-01/reviewed-census`, manifest SHA `d4777d4bcb8229d908c61dd08520473ae255412549a35f0e1c077904e5b7eb1d`. Removed only its independently verified duplicate source/docs, preserving fixture and locks; tmpfs free 1,896,996,864 bytes. Suite launcher preparation is underway; actual diagnostic remains unrun. In parallel P30 pure combined-root dry census selected 14, skipped 0, excluded 22; selection and host postflight are under independent review, no test body yet.

P30 pure combined-root suite `_build/verification/diagnose-combined-root-focused-20261108-01/p30pure-suite-01` passed 14, 0 failed/skipped, 22 excluded. Independently reviewed reference manifest SHA `ea2db234e374c6ee52d3a0c06970c535d245be919bc62430515ee80a77515dc5`; source/runtime/Mix/Hex and identity lists matched. Host postflight found no group/session 2782595, BEAM/runner, operator/input lock holders or open suite files; guard PID self-reported, no live independent observer. This does not qualify live P30 egress or materializer. P31F fresh abort diagnostic suite is next; no earlier uncertain outcomes are replayed.

One-shot P31F abort diagnostic session 13335 FAILED: suite exit 2, 0/1 passed, 88 excluded, diagnostic category `other`; `Session.close_confirmed(c.pid)` returned `{:error, :cleanup_unconfirmed}`. The diagnostic stopped before new journal inspection and before explicit-result/no-replay assertions. Status remains outcome unknown/cleanup unconfirmed; preserve exact fresh root `/run/user/1000/ipse-retirement-abort-error-suite-20261107-01` and all prior unknowns, never retry this effect. Receipts `_build/verification/retirement-abort-error-focused-20261107-01/{suite-v12-01,supervisor-suite-v12-01}`. Independent process/lock audit is underway. A disabled seven-case live P30 runner `_build/verification/p30-live-combined-focused-20261108-01/run-p30-live.OFF.sh` is prepared, but neither census nor test has run; wait for host audit and enough tmpfs before use.

Independent P31F failed-suite postflight: build/helper exits 0, suite 2, supervisor 1; no members of groups/sessions 2783580/2784490/2785653/2785717, named BEAM/runner, matching operator/input locks or open fresh scratch files observed. Guard PID was self-reported. This does not settle the effect or permit replay, and the retained fixture/journal/locks remain. Removed only independently verified duplicate suite source/docs. Preparing the separate P30 live dry census, not yet actual tests.

P30 live combined-root dry census independently reviewed 7 intended generated cases (different parent args; matching/nonmatching unrelated turns; approved/cancel/mismatch/owner-loss), no skips, 15 excluded; no bodies run. Source/runtime/Mix/Hex seals matched and no stage group/session 2788194, named BEAM/runner, matching operator/input lock or open files remained at postflight. Reference `_build/verification/diagnose-combined-root-focused-20261108-01/reviewed-p30live`, manifest SHA `522f58f3349d3fd3782c04325fd2ed6be112047d0fafad250d6e894505b6cff0`; live suite launch follows in a new tmpfs root. Preserve failure markers/unknowns and no retry.

P30 live combined-root suite `_build/verification/diagnose-combined-root-focused-20261108-01/p30live-suite-01` passed 7/7, 0 failures/skips, 15 excluded. Selected lists matched the reviewed reference; source/runtime/Mix/Hex seals match. Independent host postflight found no group/session 2789693, BEAM/runner, operator/input lock holders or open output/fresh scratch files; guard PID self-reported. Fresh tmpfs root `/run/user/1000/ipse-p30-live-suite-20261108-01` remains retained; prior fixtures untouched. Together with 14 pure cases this qualifies only these 21 local P30 checks, not full P30 or general egress. Updated plan and reran isolated docs check: 1,324 Markdown files / 10,604 local links / zero errors. Full snapshot prepared before this plan-only edit is stale for whole-document identity and must be refreshed before use.

P31I pure combined-root suite `_build/verification/diagnose-combined-root-focused-20261108-01/p31ipure-suite-01` passed 8/8, zero skipped/excluded. Reviewed reference SHA `9e4a244d0a06de608667f1e390a465cd632ff6d5250834bde3a70563f7fb627a`; source/runtime/Mix/Hex and identities matched. Host postflight found no group/session 2794224, BEAM/runner, matching operator/input locks or open files; guard PID self-reported without independent live observer. These are pure projection controls only, not live provider/Session/account proof. Prepared test-only P31I close-tracking patch `_build/verification/p31i-close-tracking-20261108-01/close-tracking.patch` SHA `db763570d1cea9d297c6179a856dbb664763f1fd0474ec7830a0772d9ac0cc4a`; not applied, independent review and fresh Session tests pending.

Applied independently reviewed P30 synthetic inventory-binding v2 patch to root after successful negative controls and Elixir1.18 formatting. It compares recomputed point-in-time inventories to both recipe and frozen declaration before setup and again immediately before Owner.run; it does not attest loaded code or prevent transient changes. `git diff --check` and root targeted Elixir1.18 format pass. New test `test/dev/evaluation/candidate_assessment_inventory_test.exs` is untracked and not included in `git diff` backup. Positive fresh synthetic materializer, true late-check mutation control and combined-source retest remain open. Older frozen recipes include earlier recipe bytes and must not be replayed; prior combined source/full snapshots predate this code change.

Integrated reviewed test-only P31I close-tracking v2 into `test/ipse/session/draft_vertical_test.exs`, then formatted with Elixir1.18. For selected Chat/xAI cases, marker precedes Session startup, fixture is retained on abort, and teardown does not initiate/retry close; positive cases remove marker only after assertions and confirmed closes. A failed test can leave a live Session/helper/listener; independent host/process/lock audit is mandatory, marker is not proof of quiescence. Five-case fresh combined-source census is being prepared; Session tests not yet run. P30 new inventory-comparison Mix test passed 1/1 in isolated combined build plus current recipe/test overlay (recipe SHA `6fb036dadff1d716b9a61a82fbbb3dc1707c63733293a82f213b5e866c0c068c`, test SHA `378013ad6997a1dc544974e59646cb37b759a1f73840172bf01467c3c17fe55b`); one unused recipe helper emitted an undefined test fixture warning. Initial sandbox attempt stopped before test on loopback :eperm; host-view run passed and postflight found no BEAM/runner/lock holder/open files. This does not establish the positive materializer or late race control.

P31I five-case candidate `_build/verification/p31i-combined-source-20261108-01/source` overlays current root `draft_vertical_test.exs`, P30 recipe and new inventory test on previous combined source, candidate manifest SHA `a36f3b8624b2c192266e7bc47cc2ae70fb1147bef801cbaebfd34ec3a8ca2160`; all three formatted under Elixir1.18. Fresh dry census session 87595 exited 0 and selected five intended synthetic Chat/xAI Session identities, 0 skipped, 25 excluded; no test bodies ran. Census `_build/verification/p31i-combined-source-20261108-01/p31i-census-01` under independent identity/host review. A separate suite launcher with fresh retained fixtures and disabled external HTTPS is being prepared; actual tests remain unrun.

Fresh P31I combined candidate census independently reviewed: five intended Chat/xAI Session cases, zero skipped, 25 excluded; source/runtime/Mix/Hex seals match, no stage group/session 2799109, BEAM/runner, matching operator/input locks or open census files at postflight. Reviewed reference manifest SHA `d8ac9785b64a15d5737752bf29e0e8de691ea9358c24f82464f45f40d0bc4e75`. Suite launcher independently reviewed with isolated HOME and `HTTPS_PROXY=disabled` through Ipse.HTTP (not a system-wide firewall), fresh tmpfs fixture and retained roots. First no-argument invocation exited 2 before creating output or launching a test; corrected `p31i suite` invocation is running as exec session 16569, output `_build/verification/p31i-combined-source-20261108-01/p31i-suite-01`. Await completion and audit; do not retry a failed effect.

P31I five-case combined suite session 16569 passed 5/5, 0 failures/skips, 25 excluded; reference and all source/runtime/Mix/Hex/node seals matched. Independent postflight found no group/session 2801611, BEAM/runner, operator/input lock holders or open suite/fresh tmp files. Eight fresh tmp directories including five draft fixtures are retained, no payload inspected. Guard PID self-reported, no independent live observer. This is synthetic local adapter/Session behavior, not live account verification. Plan updated to distinguish candidate evidence and isolated docs checker rerun: 1,324 Markdown, 10,604 links, zero errors.

Updated untracked inventory test to require its existing ProviderFixture support before loading recipe, removing prior warning. Fresh isolated Mix rerun passed 1/1 with no warnings; current recipe SHA `6fb036dadff1d716b9a61a82fbbb3dc1707c63733293a82f213b5e866c0c068c`, test SHA `000201c10055d85be6f1105400f377531566df24c303c9983d6afe2177a3255b`, support SHA `0092d34f9e3adeed2bf184e3ab48feabd79eeacd2b5f0e5c1b5c654ceba2dcc1`. No old fixtures or live materializer used; host postflight clear. Positive fresh synthetic materializer source composition/runner being prepared, actual test not started.

P30 materializer current-source composition `_build/verification/p30-inventory-materializer-composition-20261108-01/source` manifest SHA `8ccab498c1d7360d3fa958b54ea952faeb48bfa99e637fddff599a778a1c11bd`: exactly current recipe, draft_vertical test and revised untracked inventory test overlay prior combined build; compiled inputs unchanged, but reused BEAM retains prior synthetic Git identity, so this is a sealed hybrid, not full rebuild. Disabled one-test runner `_build/verification/p30-inventory-materializer-runner-20261108-01/run-materializer.OFF.sh` selects fresh opt-in synthetic terminal materializer, no recall. Independent static review found no scope mismatch but PTY compiler/toolchain needed host seal, process-group checks cannot prove detached child closure, 1.2 GB free-space guard has unmeasured peak and proxy is not a system firewall. No materializer test or PTY started; a host-sealed dry census is being prepared.

P30 current-recipe hybrid materializer dry census independently reviewed: one intended test, zero skipped/excluded; no PTY or body. Source/runtime, synthetic index, host inventories and explicit rustc/cc/ld/ar hashes matched. Host postflight found no group/session 2809461, BEAM/runner, operator/input lock holder or open census files; guard PID self-reported. Reviewed reference `_build/verification/diagnose-combined-root-focused-20261108-01/reviewed-p30materializer`, manifest `ff6a75c44af6f8e5c4db366c471c885d9e6906c75eb392ee1127c6d2db7850a5`. Actual fresh suite is being launched once; PTY detached descendants and unmeasured tmpfs peak remain audit limitations. Prior recipes/fixtures must not be reused.

P30 inventory-bound fresh materializer suite `_build/verification/diagnose-combined-root-focused-20261108-01/p30materializer-suite-01` exited 0: 1 passed, no skips/exclusions. Positive PTY seed froze a new recipe, assessment PTY exited zero and exercised refusal, saved replay/fence/action and confirmed Session closure; synthetic labels remain unqualified. Independent postflight verified source/runtime/Mix/Hex, synthetic Git and host/compiler inventories; no group/session 2812187, BEAM/runner/PTY processes, matching operator/input lock holders or open output/fresh scratch files observed. Fresh `/run/user/1000/ipse-p30-inventory-materializer-suite-20261108-01` retains one synthetic root, test-passed marker and 16 lock files; no payloads read/deleted. Guard PID self-reported, no independent live observer; host checks are point-in-time. This is a sealed hybrid using prior audited BEAM, not full current-source rebuild, not independent quality/live acceptance, and does not prove late-change race protection. Plan updated with point-in-time limitations.

Whole relevant decisions and operator development-workflows manuals reviewed. Updated `docs/developer/decisions.md` to teach recipe-specific declaration/inventory checks and point-in-time limitations, retain distinction from generic Owner, and include the new focused test command; operator manual needs no recipe-internal detail. Isolated docs checker initially reported the new test absent from its older snapshot, so copied only that current untracked test into the docs snapshot and reran: 1,324 Markdown files / 10,604 links / zero errors. `git diff --check` passes. User was asked whether normal cleanup may also remove NEW disposable synthetic fixtures after unexpected unconfirmed outcomes; pending reply. Existing prior notebook, prior unknowns and already retained fixtures remain untouched whatever the reply.

P31G worker Graph result-time wrapper `_build/verification/diagnose-combined-root-focused-20261108-01/p31gpure-suite-01` passed on selected-current-source hybrid manifest `8ccab498c1d7360d3fa958b54ea952faeb48bfa99e637fddff599a778a1c11bd`: outer 1 passed, and wrapper/child success requires exactly eight inner cases, no failures/skips/exclusions. Reviewed reference SHA `6b5d638a7140ece9d58426c4e51bf9482f94b6f67e4466368b21fa65e012ba61`. Independent audit verified source/runtime/Mix/Hex/synthetic Git, found no group/session 2825084, child BEAM/runner, matching operator/input locks or open suite files; guard PID self-reported. This is worker-level synthetic time behavior only, not final Session/terminal delivery, source authority or full P31G. Broad-suite unexpected-synthetic-cleanup decision remains pending.

Graph manuals reviewed as whole documents: operator Graph and developer knowledge-extensions guidance already match the worker post-preparation revalidation/rollback boundary and clearly distinguish no delivery lease; no correction needed. Static P31F abort review found no defensible specific fix: diagnostic `other` collapses multiple Session errors, and `close_confirmed` may fail for call exit/timeout, missing DOWN, share barrier poison, or task/observer/writer/lock/release checks. Later host quiescence cannot establish missing acknowledgment or effect. Do not retry or relax confirmed-close semantics; retained fresh unknown remains intact. One unrelated indexed Word pure control is available but is not itself a new acceptance closure, so was not run just to accumulate tests.

Full root `mix format --check-formatted` passed under Elixir1.18.5/OTP27 with isolated Mix archives. To clean our tmpfs footprint, independently verified the two P30 live census/suite source/.git and _build/test copies against the persistent audited build (file hashes, node modes/link targets, no hardlinks/open files) and separately verified source/non-telemetry dependency duplicates. Removed only those non-lock duplicate files and selected duplicate source trees; original `compile.lock`, Cargo/Jason lock files, telemetry/priv symlink targets, all fresh tmp/fixture roots and prior unknowns remain. Scratch Git needs restoring from persistent build before reuse. `/run/user/1000` free afterward 1,708,281,856 bytes. Research 199→198 issue is in the disabled prototype; importing dormant machinery to root would not fix an active invariant or complete P31H.

Fresh project-only current-root snapshot/build `_build/verification/current-root-build-20261108-02` has 10,381 selected project inputs and source manifest SHA `e8e3f4223500d2d1f90beaac361ba8959b24fd7ef603c637149cba28400f535c`. Offline `./dev/build.sh`, separate `mix compile --warnings-as-errors`, and `./bin/ipse demo` all exited 0 (demo `Finished.`); source/root and host inventory passed pre/post, recorded group 2834449 empty. Synthetic empty Git, dirty source labeled `uncommitted`, not a release/clean commit; broad tests not run. Independent host/process audit underway. First snapshot `_build/verification/current-root-build-20261108-01/source` accidentally copied hidden historical fixture/checkouts before stopping on a symlink; originals unchanged, copied tree retained pending independent safe-deletion boundary review. Do not mistake it for a valid snapshot or access its payloads.

Independent current-root build 02 postflight: source manifest, host pre/post inventories and demo completion verified; no group/session 2834449 members, BEAM/runner, matching operator/input locks or open build files observed. Initial snapshot 01 unexpectedly copied ~2,015,404,032 allocated bytes of hidden historical fixture/checkouts, including 57 lock-named entries and symlinks; no hardlinked regular files or special nodes. Metadata-only review cannot establish safe wholesale deletion without classifying those copied lock/evidence trees, so it remains retained, not read; original fixtures untouched and no open snapshot files observed. Be transparent with user; do not delete original evidence or follow symlinks. Broad-suite cleanup decision still pending.

While broad-suite cleanup decision remains pending, prepared an isolated disabled-prototype-only P31H owner-local clock fix `_build/verification/p31h-prototype-local-clock-20261108-01/prototype-clock.patch` SHA `1c68a97233c30371dac643844fb2569391de60723d80aa46e4324593e6dfaf67`: advance floor at accepted admission/write samples, poison rejected checks, and settle from latest matching owner/ref state. Seven deterministic simulated-write tests passed; original frozen code failed 6/7 including 199→198. Independent review found local logic sound but lacking explicit foreign-process/ref/owner-loss and ignored callback controls; those are being added if practical. No root code import, socket, Session, native or notebook tests. This does not qualify P31H: actual transport, cross-process clock transfer, source/approval binding, replay/downgrade and terminal delivery remain open.

Isolated P31H prototype clock patch v2 `_build/verification/p31h-prototype-local-clock-20261108-01/prototype-clock-v2.patch`, SHA `a5e52e09e5167672ea1356425c5f9497f736503c4f2fb1d16ffb01239f579a10`: added foreign-process, changed-ref, upstream owner-loss and ignored refused-floor controls; candidate now additionally poisons refused checking-phase floor advance and validates owner/ref at capture return. Eleven controlled-clock simulated-continuation tests passed; frozen original failed 8/11. Independent static review found no concrete regression on intended checking→sending→settlement. Limits: foreign-process test covers send/4, not low-level no-gate write predicate; wrong-phase rejected advances do not necessarily poison an already-sending gate; no actual socket/stdin, cross-owner clock transfer, durable replay/downgrade or final delivery proof. This remains disabled prototype-only, not root implementation or P31H qualification. Broad-suite cleanup choice is still pending.

P31H initial vertical-slice review found existing managed approval requires nonempty Collection dependencies and cannot authorize provided-only sources; ordinary effect approval is insufficient under the frozen contract. Chosen implementation direction is single-invocation native review of exact artifact/options/full provided set with single-use receipt (no persistent trust change). This is a code-design choice only, not authorization for real inference or trust mutations. Isolated implementation investigation is in progress; do not enable until old-reader refusal, owned source/time through send, terminal delivery and durable replay are verified. Prototype clock patch v2 alone remains disabled and insufficient. Broad-suite new unexpected synthetic cleanup choice remains pending.

Started isolated P31H disabled candidate `_build/verification/p31h-provided-invocation-review-20261108-01/source`, source manifest SHA `4f591ae0e4139f82468c1f021dba92f0cd17cbd57de12a48a8fad3943cd0041b`. It retains unconditional guarded dispatch refusal, includes the local clock v2 prototype and an inert ProvidedReviewRecord/strict reducer binding parent, identity/artifact, nonsecret offline options, host-selected time and full ordered supplied sources with duplicates. It returns record-only, never authority; actual review authentication, durable used-ID state, current-use/send/terminal transfer and old-reader refusal remain absent. Six pure record controls passed using mixed candidate/root beams with module-redefinition warnings, not an integrated build. Independent review found Unicode terminal control display risk; candidate now applies existing Terminal.escape before size/hash, tests C1/bidi, and independent recheck found that narrow defect corrected. Display contains private inputs and must not be logged. No real inference, notebook or old fixtures accessed; no root import or feature enabled.

P31H isolated Session-owned native-review draft is sealed at `_build/verification/p31h-provided-invocation-review-20261108-01/source`, manifest SHA `fef5fdcde18271e4051daace87f8c40574da6723e7a0eb779f558ccd0479349b`, node SHA `55d9f03681a3a516d40a4ebb2fd0f0ac7c58e7cfd506dd263321ff314d0afde3`; focused patch `disabled-native-review.patch` SHA `de4ed23c2de17036a3cc2ec247d25d89a331d04a319b0c70b5e0d76745d31743`, copied to `~/ipse-tmp/p31h-disabled-native-review.patch`. Draft adds a Session-owned channel/generation-bound input purpose and bounded review observation returning `:no_dispatch`; fresh Sessions remain v1 and guarded export is still refused. Candidate refuses all three reserved review event types before open_existing lock/repair and from Saved/context/Actions; actual older binary refusal untested. Eleven limited pure controls passed in mixed BEAMs with many warnings; not strict build, native PTY, replay integration, transport or output proof. Independent adversarial review underway, no root import or real inference.

Adversarial review found stale provided-review render on input-channel reset. Candidate corrected it on channel replacement, both planning generation resets, ordinary channel death and chat-review reader loss while keeping seen-invocation consumed. Three direct-handler controls passed; combined mixed-BEAM controls 14 passed with redefinition/undefined warnings, no native PTY. New isolated source manifest SHA `5e133540dd39f10d513dbf938948612d77e01e639f30850211a9c8dec0b88999`; node manifest unchanged; restartable patch `disabled-native-review-v2.patch` SHA `51bccf49430d82826448d5efd60e68f48ccbd72a311b1762e028f539592b4546` saved to `~/ipse-tmp/p31h-disabled-native-review-v2.patch`. Dispatch remains refused; prior-reader, actual native terminal, durable replay, send/delivery remain unverified. Independent recheck underway. Broad-suite cleanup decision still pending.

P31H prior-reader evidence: provenance-recorded fresh synthetic check `_build/verification/p31h-old-reader-check-20261108-01/receipt-01` exited 0 on exact sealed pre-change P31I baseline BEAMs (source base 2337e1ba..., not a release/09309905 claim). Valid v1 synthetic inspect/export/idle resume/confirmed close passed, then an edited new-layout header produced old-reader inspect/export/resume refusals with no observed file inventory/hash change or immediate provider call. Independent review verified source/runtime/executable hashes, PID/PGID 2866811 empty at host postflight, no named BEAM/runner, operator/input lock holder or open files. Guard/build provenance is sealed but no live VM observer; this is an edited complete header, not genuine new-writer journal, and does not prove other versions, transient writes, delayed effects, tool calls or native review. A separate preliminary torn-tail synthetic check passed with generic error assertions but lacks comparable provenance and does not identify marker as cause. Research remains disabled, native terminal/send/replay/delivery unqualified. Broad synthetic unexpected-outcome cleanup choice still pending.

Stopped custom P31H PTY harness work as disproportionate; unreviewed/not-runnable drafts remain `_build/verification/p31h-native-review-test-prep-20261108-01/`. No candidate native test, build, network namespace or real inference ran. Existing project test infrastructure should be reused for a future integrated native review slice. Remaining P31H boundaries: genuine admitted writer/old-reader refusal, durable replay, real Session native review/cleanup, authenticated complete source/time custody through actual send, terminal delivery/withdrawal. The selected new-layout native review path in isolated source remains unreachable/disabled and returns no-dispatch. Broad suite remains blocked on the pending explicit user choice about cleanup of NEW disposable fixtures on unexpected unconfirmed outcomes. Prior notebook, prior unknowns and retained fixtures stay untouched regardless of choice.

2026-11-08 continuation: refreshed the top-level current restart index; older rolling entries remain historical. A P30 concurrent-budget attempt using a fresh synthetic root `/run/user/1000/ipse-p30-budget-concurrency-20261108-01` returned exit 0 in 0.05s with no test output or retained guard/child receipt. No matching BEAM/test process or open fresh-root file was observed afterward; TMPDIR showed only a Mix pubsub entry and no expected fence-fixtures tree, but that does not prove the body did not begin. Outcome is unconfirmed; do not count it as a pass or retry/replay this fixture, and preserve its lock inodes. A separate current-root retirement-owner composition with native fence patch and six response tags is being compiled in isolation; previous abort unknown is not being rerun. Broad-suite cleanup choice remains pending.

Continuation P30 review found that `CandidateAssessmentSession` retried `Session.close_confirmed` in `after` after an explicit close returned unconfirmed or exited; the idle path did the same. Applied focused `close-once-v2.patch` SHA `3703a122aee8e7da7b187511d8a8ecb98c775ab383e8d299c62139a52ff8ce36` to current root: both paths use one atomic close guard, preserving the first close attempt and not automatically repeating an uncertain close. Targeted Elixir 1.18 formatter and `git diff --check` pass. Three new pure wrapper behavior tests are being run separately; real native cleanup/retention and fresh positive materializer on this new source remain unverified. The earlier unconfirmed concurrency fixture remains intact and must not be reused.

P30 close-once guard pure tests passed in `_build/verification/p30-close-once-test-20261108-02/`: 3 passed, 25 excluded, exit 0, isolated prior audited build plus exact two root-file overlays; pre/post overlay/source hashes matched and tracked PGID 2896273 was gone with no open copy files. Test callbacks cover unconfirmed return, exit, explicit success and early failure, not real native cleanup. First fresh attempt exited before test registration because isolated Mix home lacked Hex; no test fixture, no reuse of the unconfirmed concurrency root. A fresh positive materializer on the modified source is being prepared. The originally built retirement composition was found to be an older incompatible protocol and its native test was stopped before execution. The correct later protocol was merged only in an isolated candidate `_build/verification/retirement-current-later-composition-20261108-01/source`, manifest SHA `ef391d9ec39ce9b7b8f4cb4deada37254dab7b1fcd6d0353fcef3ee3a3e52b62`; three conflict areas need independent semantic review. It is building; no prior abort/owner-loss retry.

The fresh P30 close-guard synthetic materializer `_build/verification/diagnose-combined-root-focused-20261108-01/p30closeguard-suite-01` passed 1/1 with a new frozen recipe on the updated close-once source. Independent postflight verified source/runtime, synthetic Git and host inventories, and found no stage group/session 2909078, named BEAM/runner/PTY or open suite/scratch files; guard PID self-reported. It is a sealed hybrid, not full current-source runtime baseline; the earlier unconfirmed concurrency attempt remains intact. Updated `docs/developer/decisions.md` to describe one confirmed-close attempt and reran isolated docs check: 1,324 Markdown files, 10,604 links, 0 errors. The corrected later retirement candidate built/compiled/demo passed and one new positive two-lock test passed with independent postflight; candidate root patch is NOT applied and awaits merge review plus remaining native/Session controls. No earlier abort was replayed.

Retirement corrected later-protocol candidate `_build/verification/retirement-current-later-composition-20261108-01/source` built/strict-compiled/demo passed; independently reviewed three-way conflict resolutions preserve CollectionStore workspace guard, Invocation P30 fences and tagged test retention. Fresh two-lock arm/disarm positive (1/1) and separate incomplete/unarmed switch refusal (1/1) passed in distinct retained tmpfs roots; independent postflights verified seals and found their groups/locks/open files clear at inspection. One unrelated P31H BEAM was active during second host check, so no global-quiescence claim. Candidate integration patch SHA `0f9539ec0ca617c9a15133d4cf83944a57bdfdcecfefc6cfdec5bd5be5ed11f8` is NOT applied; actual positive Session and remaining protocol tests still open, prior abort/owner-loss unknowns not replayed. Distinct Session positive dry census is being prepared.

P31H disabled prototype `_build/verification/p31h-provided-duplicate-window-20261108-01/source` evolved to preserve duplicate source positions, nil no-transition cutoff, rollback/expiry poison propagation and refuse unregistered/nil dispatch. Latest candidate manifest `cab8012080e310144e470f94e6225f36dd164ffc18d0c3405fbe5c401c19a4e6` at agent's safe pause; strict incremental compile and 37 focused tests passed, no guarded dispatch enabled. Independent review is checking the latest fixes; actual transport, source/time custody across processes, durable replay and delivery remain open. Never treat this isolated candidate as merged root or complete P31H.

Applied independently reviewed retirement later-protocol + close-safe test patch `_build/verification/retirement-current-later-close-safe-20261108-01/root-integration.patch` SHA `e1fa897217903c95c842e54f1cb0caafbcfb8e42ffcab5714715068c6432178d` to root. All ten changed root files byte-match the tested close-safe candidate; `git diff --check` and targeted Elixir 1.18 format pass. Fresh distinct positive Session test passed 1/1, 88 excluded; independent source/runtime/reference and process/lock/open-file postflight clear, guard PID self-reported; it emitted an unused test-helper warning. Two preceding native positive/refusal controls pass on same runtime with an earlier test-only source version. This does not establish interrupted abort/owner-loss, remaining native cases or full integrated baseline. The new untracked native protocol test is saved separately as `~/ipse-tmp/transaction_document_retirement_test.exs`; prior unknowns and declined notebook remain untouched.

Updated root native/README.md for retirement g/b/e/k/m/l transaction protocol and linked Collection SDK to owner-retirement guidance; reviewed the relevant operator and storage sections against code, not a whole-milestone manual acceptance. A third fresh retirement single-lock arm refusal passed 1/1 with independent source/reference and process/lock postflight; it tests Elixir capability refusal, not raw native frames. Root plan now records the positive Session and two-lock/refusal controls without claiming owner-loss/recovery qualification. Isolated docs check passed: 1,324 Markdown files, 10,606 links, 0 errors. P31H candidate remains isolated/disabled; latest additional review found raw tool-output append risk, so guarded tool publication is temporarily refused until durable withdrawal/commit is implemented. Do not treat that refusal as milestone completion.

Retirement owner-loss test-only safety variant `_build/verification/retirement-ownerloss-test-variant-20261108-01/ownerloss.patch` SHA `7c01663072ac4d4b5a342b71d28f8cf2118f6817ee6b609fac6cd8c16add63b4` was independently reviewed: each case requires lost/remaining port DOWN, controller DOWN, reacquisition of the same two device/inodes before reading fresh root, and retains fixture on failure. A first dry census accidentally selected six due ExUnit include/only OR; no bodies ran, its root remains. Corrected writer-only census selected one. Fresh writer-control-loss suite `_build/verification/retirement-ownerloss-writer-20261108-01/writerloss2-suite-01` passed 1/1, 5 excluded; independent source/reference/process/lock postflight clear, PGID 2956778 gone, guard PID self-reported. This covers loss detected before source import/switch, not loss during final switch. Fresh root and all previous unknowns retained. Separate Session-control-loss census is being prepared.

Fresh Session-control-loss test `_build/verification/retirement-ownerloss-session-20261108-01/sessionloss3-suite-01` passed 1/1, 5 excluded on reviewed test-only safety variant. Independent postflight verified source/runtime/reference and no PGID 2962015, named BEAM/runner or observed open fresh fixture files; lsof warned about hugetlbfs/mqueue visibility. Three lock files and fixture remain. Along with writer-control-loss, this tests control loss before source import or final switch, not loss during final switch or earlier unknowns. Applied reviewed test-only `ownerloss.patch` SHA `7c01663072ac4d4b5a342b71d28f8cf2118f6817ee6b609fac6cd8c16add63b4` to root untracked native test and refreshed its separate `~/ipse-tmp` copy. Two unsuccessful dry-preflight attempts ran no body and remain retained; the corrected host-view census selected exactly one tag.

P31H isolated candidate added Saved.context fail-closed barrier for synthetic provided-source markers; direct in-memory regression passed. Reviewed host-view Mix run `_build/verification/p31h-context-synthetic-20261108-01` exited 2: context case passed, ResultSource synthetic journal positive control failed before the marker with `saved_result_unavailable`. Its fresh journal remains retained; point-in-time host inspection found no matching command/open files/locks but launcher did not record PID/PGID, so detached descendants cannot be excluded. Static review identifies an invalid fixture: empty metadata lacks the registered extension/catalog and fixture uses a dummy exports digest. A corrected fresh fixture is being prepared, not yet rerun; this is not proof of a product defect or a passing ResultSource barrier. The guarded-output pure reducer (4 focused controls) is isolated/unwired; Journal.source_page/feed and real output/durable replay remain unresolved. No old fixtures or retained notebook were touched.

The corrected P31H bare-marker replay controls ran in isolated fresh `_build/verification/p31h-context-synthetic-20261108-05`: compile exit 0, Saved.context case 1 passed/14 excluded, ResultSource positive-read then bare marker refusal 1 passed/16 excluded, runner exit 0. Source manifest SHA `6ea00c9cb65652991914c82fd41e192a9dc9de593df61853fd3253cd4e09e719`; independent listed source/post-build hashes and source/deps/shared/toolchain postchecks passed. No recorded groups 2977974/2978076/2978707/2978756 or named BEAM/runner at inspection; lsof saw no open run files but warned about hugetlbfs/mqueue visibility. This corrects two earlier invalid synthetic-fixture attempts, which remain preserved; it is not genuine guarded journal, native input or delivery proof. Guarded Research still refused. User's decision on unexpected NEW synthetic fixture cleanup remains pending.

Standalone HEAD+close-once composition: the first build/compile/demo and three pure tests individually passed but outer verification failed because Rebar changed telemetry's generated `source.dag`; no retroactive pass. A separately sealed post-build pure suite with a test-only operator-home retention overlay passed 3/3 and independent postflight. Its fresh materializer `_build/verification/p30-close-head-checkout-20261108-01/sealed-v2-materializer-suite-01` failed during synthetic seed before readiness (0/1); outcome unknown/cleanup unconfirmed, fresh `/run/user/1000/ipse-p30-head-sealed-v2-materializer-suite-20261108-01` retained, no previous fixture touched. Independent host audit found no recorded PGID 2990026 or named BEAM/runner/PTY, lsof visibility limited; build differs only on Mix failure tracker. Static analysis identified an omitted documented `dev/build.sh` bundle step: the build lacks `priv/extension-bundles/catalog.json` required by seed setup. This is a strong prerequisite cause, not proof it was the sole failure. A new corrected build/census is being prepared from a separate source copy; do not reuse failed seed state or relabel the failure as a pass.

Focused P30 close-once subgoal committed and pushed as `d9014d1f07f397377fe291c60da9a2144754ac4e` (parent `63f6f0fc7b509bae97e5b3afdab5e4f4f5ee4ec7`) on `origin/codex/p30-p31`. A separate index staged only the standalone HEAD-relative materializer close guard, its three tests and relevant developer-manual sentence. Standalone HEAD+patch tests: three pure controls and a fresh bundled synthetic materializer passed with reviewed postflights; test-only operator-home retention overlay used in execution is NOT in commit. Initial standalone build had a generated telemetry Rebar DAG seal mismatch, then a separate source/build seal and fully bundled build were used; prior failed seed remains preserved. Exact isolated docs check passed 1,318 Markdown/10,578 links. Real index initially contained only staged Research, was unchanged during private-index commit, then only the three committed paths were synchronized to new HEAD; staged Research and remaining WIP remain. Full P30/P31 goal is not complete, and declined recall / pending broad cleanup decision remain in force.

After pushing d9014d1f, independently verified committed close guard and all three tests still match root WIP and index contains only staged Research addition. Restored the committed manual's explicit statement that an unconfirmed close stops before journal loading in the root WIP explanation; isolated docs check again passed (1,324 Markdown / 10,606 links). Retirement standalone feasibility review found the v12 13-file patch and prior docs patch can apply against d9014d1f, but later integrated root patch cannot without WIP conflicts. An isolated HEAD+v12 composition with all close-safe and owner-loss test gates is being prepared; do not use older unsafe unknown tests, assume earlier WIP receipts certify it, or alter staged Research. Full P31F, baseline and whole goal remain open.

Standalone retirement test-hook controls on d9014d1f-derived candidate: separately built `--cfg ipse_source_switch_test_hook` helper SHA `0577b3d490f6d554c2d80ac5d6b849a4c2091902bfd2ca922c5d2073653d4e9c`, forced candidate BEAM compile bound that helper; production helper unchanged. Fresh before-decision Session-loss suite `hookbefore-suite-01` passed 1/1 (90 excluded), after-decision `hookafter-suite-01` passed 1/1 (90 excluded). Both were independently audited: source/runtime/reference seals match, no recorded stage groups 3818005/5106, named BEAM/helpers or open fresh files at host inspection; respective eight fresh lock inodes each had no /proc/locks entries. Both synthetic fixtures remain retained; after-decision physical outcome remains unknown and was not inferred or replayed. Test-only variants required owner/port shutdown and exact lock inode reacquisition before any journal/root inspection; no earlier fixture touched. The checks do not prove absence of unrelated detached descendants or qualify full P31F.
