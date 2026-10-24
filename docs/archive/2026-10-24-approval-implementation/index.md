# Session permission implementation

Implementation record, 2026-10-24, starting from `877a200`. The developer explicitly
selected implementing approval UX before the external audit, extending the P28
brief's original exclusion of approval semantics. The
[research](../2026-10-24-p28-approval-ux/index.md) and
[walkthrough](../2026-10-24-p28-walkthrough/index.md) explain the scope.
Current instructions belong to [terminal usage](../../operator/usage.md#approve-a-small-task)
and [architecture training](../../developer/architecture.md#trace-a-tool-and-its-approval).

## Implemented candidate

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
child/release controls. Full local native-inclusive,
installed and hosted verification is still required for this new candidate;
the older P28/P29 baseline does not establish this change's acceptance.

The fixed seven-effect task compares four writes plus three identical shell calls:
seven decisions with once-only consent, two with explicit edit/exact-command
grants. This is a deterministic fixture comparison, not a new human walkthrough
or a benchmark of arbitrary tasks. No real provider was contacted for this change.

The RC files were copied into ignored `dist/rc-rehearsal/v0.1.0-rc.1/assets` and
all four GitHub digests plus archive sidecars were rechecked. The remote draft
remains unpublished. Automatic approval review rejected its deletion pending
explicit authorization; a separate question is pending. The tag is untouched.
