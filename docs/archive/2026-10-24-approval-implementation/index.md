# Session permission implementation

Implementation record, 2026-10-24, starting from `877a200`. The developer explicitly
selected implementing approval UX before the external audit, extending the P28
brief's original exclusion of approval semantics. The
[research](../2026-10-24-p28-approval-ux/index.md) and
[walkthrough](../2026-10-24-p28-walkthrough/index.md) explain the scope.
Current procedures belong to [terminal usage](../../operator/usage.md#approve-a-small-task)
and [architecture training](../../developer/architecture.md#trace-a-tool-and-its-approval).

## Completed local baseline and successor

The completed local baseline is `dac11dcbca0bb6787a74052885e1e02301fc2f9c`. Its runtime source
is unchanged from the default-mode repair at `b874fc7`; the subsequent commit
includes missing receipt files and reconciles the audit documentation. The
[verification receipt](verification.json) separates this candidate from earlier
successful, failed and cancelled checks. Isolated copies exclude unrelated user
edits. The [machine-label follow-up](../2026-10-24-sign-in-host-label/index.md)
initial terminal guidance is included in this baseline. Browser prefilling then
superseded that guidance to fulfill the requested authorization label; 76 focused
cases pass (seed 516367, 19.2 seconds). Its successor needs its own full
source, installed and hosted gates. The table below describes `dac11dc`, not that
later name-hint request change.

| Gate | Actual result |
| --- | --- |
| Focused permissions, Session, terminal, Auth/setup, child and release controls | 127 passed, seed 924329, 22.5 seconds |
| Build, formatting, warnings-as-errors compile and CI policy | Passed in a clean fixed source copy |
| Full Linux suite including native confinement | 1721 passed, zero failures, 19 excluded; seed 580519, 1068.8 seconds, exit 0 |
| Isolated credential-free demo | Passed after the full suite; tracked source tree remains clean |
| Complete installed-package proof | Passed; real grant reuse/revocation/resume, existing upgrade/recovery, memory, MCP, extension and child checks; inventories unchanged |
| Exact archive and runtime notices | SHA256 `7fb89d0e07e9032d1beae0d4e0f174a0a56b9284aee36bc0332ba7207233b036`; all 24 runtime-notice files rehashed against SHA256 and Git blob identities; Elixir 1.20.4/OTP 29.1.1 |
| Operator examples against packaged CLI | Build identity, machine-label code, and headless/`--yes` flag refusals passed |
| Committed-tree documentation | Clean Git checkout: 415 Markdown files, 3836 local links, zero errors |
| Hosted Ubuntu/macOS and independent proofs | Run [40114556208](https://github.com/lexlapax/ipse/actions/runs/40114556208) remains in progress; no final platform verdict yet |

No real provider was contacted for these changes. Earlier P29 live receipts and
human browser/account observations retain their own exact source and scope.

## Implemented authority

- Review each effect remains the interactive default. `--accept-edits` explicitly
  permits root native file edits in chat; it cannot combine with `--yes` or `run`.
- A fresh write/edit proposal offers `edits CODE`; a shell proposal offers
  `session CODE`. Once and deny remain available. Shell reuse matches the entire
  argument map, cwd and requested sandbox policy, without prefix/glob parsing.
- Session owns at most 32 shell grants, each with at most 16 KiB of arguments.
  `/permissions` inspects; `/permissions clear` revokes future dispatch authority.
  Cancellation retains grants; closing/resuming loses them. Children, MCP and
  extension/SDK effects retain separate approval. Headless denial takes precedence.
- Intent-before-effect is retained. Prompt grant/revoke records and each tool's
  `approval_source` explain authority without restoring it on resume. Native edit
  grants retain path checks and additionally reject hardlinks. Existing filesystem
  replacement races and trusted-shell limits remain explicit.
- Embedded callers that omit approval mode retain the same `:ask` default in
  dispatch, startup edit consent and grant admission. No dependency was added.

The fixed seven-effect task compares four writes plus three identical shell calls:
seven decisions with once-only consent, two with explicit edit/exact-command
grants. This is a fixture comparison, not a new human walkthrough or a benchmark
of arbitrary tasks. The installed control independently executes four effects
with two decisions, inspects/clears grants, closes and resumes idle.

## Verification chronology and repairs

| Candidate / check | Retained observation |
| --- | --- |
| Initial focused run, seed 675536 | Four terminal fixture failures matched the old prompt wording. Fresh-code binding was retained; expectations now match explicit allow-once wording. |
| Focused follow-ups | 53 passed, seed 776245, 19.1 seconds; then 88 passed, seed 253648, 22.6 seconds, including chat flag, native edits and child/release controls. |
| Approval-only `48a42d8` | 1720 native-inclusive tests passed, 19 excluded, seed 45144, 1069.3 seconds, exit 0; isolated demo and installed proof passed. Archive SHA256 `a49d0663aeacdf87baa6c1bb01de9f63546bf8cdfe6935cba26ed7fa2b3aeb5e`. [Hosted run cancelled](superseded-hosted.json) after the machine-label request. |
| Combined `8ee16dc` | 1721 native-inclusive tests passed, 19 excluded, seed 393182, 1062.3 seconds, exit 0; isolated demo and installed proof passed. Archive SHA256 `916596ef2b56ad871a7791b0b405c9bcaa72819d519354211a3ca8923fa90f69`. [Hosted run cancelled](superseded-combined-hosted.json) after the default-mode finding. |
| Controlled default-mode reproduction | Omitting `approval` in the real Session fixture returned `{:error, :grant_unavailable}` despite dispatch's default ask policy. One selected case failed, seed 389754. The repair aligns all three permission checks with dispatch; 127 focused cases then passed. |
| `b874fc7` hosted run 40114244391 | Both platforms stopped at docs validation: the index linked a receipt that had not been staged. Local checking saw the untracked file. [Failure retained](final-hosted-failure.json); no hosted ExUnit/installed/later success claimed. |
| Documentation repair `dac11dc` | Missing receipts committed; clean Git checkout docs validation passes. An archive-only check attempt was unsuitable because the checker requires Git metadata; the clean-checkout result replaces that attempt. Final source/installed checks pass as listed above; hosted verdict remains pending. |

Cancelled or failed matrices are not platform passes. Earlier successful suites
used explicit ask mode and do not establish the repaired implicit-mode behavior.

## Release rehearsal cleanup

The four RC files were copied into ignored
`dist/rc-rehearsal/v0.1.0-rc.1/assets` and their GitHub digests and archive sidecars
were rechecked. Automatic approval review initially rejected draft deletion without
explicit authorization. The developer then authorized deleting the draft while
retaining the tag/files. Deletion succeeded; the release query returns not found
and the RC tag remains on origin at `e944fcf`. The
[cleanup receipt](../2026-10-23-p28-p29-implementation/rc-assets.json) retains
original inspection and actual deletion facts. Stable publication remains open.
