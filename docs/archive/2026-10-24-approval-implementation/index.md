# Session permission implementation

Implementation record, 2026-10-24, starting from `877a200`. The developer explicitly
selected implementing approval UX before the external audit, extending the P28
brief's original exclusion of approval semantics. The
[research](../2026-10-24-p28-approval-ux/index.md) and
[walkthrough](../2026-10-24-p28-walkthrough/index.md) explain the scope.
Current instructions belong to [terminal usage](../../operator/usage.md#approve-a-small-task)
and [architecture training](../../developer/architecture.md#trace-a-tool-and-its-approval).

## Implemented candidate

`48a42d81a224c069ee89250e52272d44593a5948` is committed and pushed. The
[verification receipt](verification.json) distinguishes completed checks from
running gates. Isolated source/package copies exclude unrelated user edits.
The later [machine-label request](../2026-10-24-sign-in-host-label/index.md) adds
sign-in display guidance. Its combined candidate needs a fresh hosted matrix;
the existing approval-only source result remains separate.
The combined candidate is `8ee16dc538912b01e05281fa84551472772be253`.

- Review each effect remains the interactive default. `--accept-edits` explicitly
  permits root native file edits in chat; it cannot combine with `--yes` or `run`.
- A fresh write/edit proposal offers `edits CODE`; a shell proposal offers
  `session CODE`. Once and deny remain available. Exact shell matching includes
  the entire argument map, cwd and requested sandbox policy, with no prefix/glob
  parser or new dependency.
- Session owns at most 32 shell grants, each with at most 16 KiB of arguments.
  `/permissions` inspects; `/permissions clear` revokes future dispatch authority.
  Cancellation retains grants; closing/resuming loses them. Children, MCP and
  extension/SDK effects retain separate approval. Headless denial takes precedence.
- Intent-before-effect is retained. Grant/revoke records and `approval_source`
  explain session authority without replaying it on resume. Edit grants retain
  native path checks and additionally reject hardlinks. Existing concurrent
  filesystem replacement and trusted-shell limitations remain explicit.
- The installed-package proof exercises real write/shell reuse, revocation and
  idle resume using a fixed provider and no account or development toolchain.

## Verification in progress

The first focused run had four failures in terminal fixtures that matched the old
prompt wording. The production fresh-code binding was retained; fixture expectations
were updated to the explicit “allow once” wording. The next focused run passed
all 53 tests (seed 776245, 19.1 seconds). The expanded run passes 88 tests
(seed 253648, 22.6 seconds), including the chat flag, native edit behavior and
child/release controls. Full local native-inclusive
and hosted verification is still required for this new candidate;
the older P28/P29 baseline does not establish this change's acceptance.

The fixed seven-effect task compares four writes plus three identical shell calls:
seven decisions with once-only consent, two with explicit edit/exact-command
grants. This is a deterministic fixture comparison, not a new human walkthrough
or a benchmark of arbitrary tasks. No real provider was contacted for this change.

The complete local installed-package proof passes. Its new grant control executes
four effects using two decisions, inspects and clears permissions, closes and
resumes idle. Existing upgrade, recovery, memory, MCP, extension, child and native
checks also pass. The archive reports the candidate identity and has SHA256
`a49d0663aeacdf87baa6c1bb01de9f63546bf8cdfe6935cba26ed7fa2b3aeb5e`.
Manual command checks against the packaged CLI confirm help and refusal of
`--accept-edits` with headless `run` or broad `--yes`. Source/native and hosted
Ubuntu/macOS gates remain running; installed success is not their result.

The approval-only candidate subsequently passes its complete Linux native-inclusive
suite: 1720 tests, zero failures, 19 excluded, seed 45144, 1069.3 seconds, exit 0.
Its isolated demo passes and the tracked tree remains clean. Its hosted run was
cancelled after the machine-label follow-up created a combined candidate; the
[terminal cancelled receipt](superseded-hosted.json) is not a platform pass.
The combined candidate's installed proof also passes, with archive SHA256
`916596ef2b56ad871a7791b0b405c9bcaa72819d519354211a3ca8923fa90f69`.
Its full source/native suite and hosted run 40112830571 remain in progress.

Final review reproduced an embedded-API mismatch: omitting `approval` uses the
existing `:ask` dispatch default, but grant admission initially required an
explicit key. Removing that key from the real Session fixture failed the
seven-effect case with `{:error, :grant_unavailable}` (seed 389754). Grant creation,
matching and startup edit consent now use the same default as dispatch. The
repaired focused set passes 127 tests, including implicit-mode real effects,
terminal, Auth/setup, child and release controls. The final successor candidate
requires its own complete source/installed/hosted results; previous running or
passing candidates do not prove this repair.

The `b874fc7` hosted run 40114244391 stopped at the docs gate on both platforms:
this index linked the superseded CI receipt before that JSON file was staged.
The local working-tree checker saw the untracked file; a committed checkout did
not. The [failure receipt](final-hosted-failure.json) is retained. No hosted ExUnit,
installed or later proof result is claimed for this run. The repair commits the
receipt and validates a clean committed tree before restarting the matrix.

The RC files were copied into ignored `dist/rc-rehearsal/v0.1.0-rc.1/assets` and
all four GitHub digests plus archive sidecars were rechecked. Automatic approval
review initially rejected draft deletion without explicit authorization. The
developer then authorized deleting the draft while retaining the tag/files.
Deletion succeeded; the release query returns not found and the RC tag remains
on origin at `e944fcf`. The [cleanup receipt](../2026-10-23-p28-p29-implementation/rc-assets.json)
retains both original inspection and actual deletion facts.
