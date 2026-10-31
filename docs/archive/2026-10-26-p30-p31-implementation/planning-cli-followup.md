# Planning ceiling at CLI startup

2026-10-27. This is an uncommitted P31I increment, not milestone acceptance.
The [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) owns status.

The CLI accepts `--planning` for chat and run and passes the selection through
the existing execution-mode capture. Session metadata persists the mode;
resume inherits it as an enclosing ceiling even when the flag is omitted.
The terminal displays the actual active and enclosing ceilings from Session
state rather than assuming that `--yes` overrides them. A saved ceiling also
prevents an `--accept-edits` request from creating an edit grant. Combining the
two flags on a fresh invocation is refused.

Synthetic CLI tests exercise interactive and headless planning with `--yes`,
denied workspace writes, resume without the flag, a resumed edit-grant request,
and invalid option combinations. A later synthetic CLI journey loads an
operator-declared MCP read, requires explicit approval, records its result and
repeats the approval after resume without the flag. These do not prove a human
journey, live model or platform qualification. The flag
selects a ceiling at startup; an in-session transition out of planning and the
explicit deferred-decision save workflow remain unimplemented. Starting a new
ordinary session has separate context and does not implicitly publish decisions.

Fixed tree `07b9b747d960fcf6290d55a435634131597595d0` passed 101 CLI,
permissions, execution-mode, draft, research, MCP and replay tests with seed
20270718 and one case at a time. Forced test-environment compilation rebuilt
152 modules with warnings treated as errors. The retained log is
`_build/p30-current-validation.ri5cUYdZ/_build/planning-cli-tests.log`.
The snapshot predates this record and the final documentation link; its tested
runtime and test bytes match the increment. Full repository regression and the
required whole-manual and adversarial reviews remain open.

Adding the MCP CLI journey changed only the test file in the previous snapshot.
Fixed tree `5c9dd534b67a13f57c033a5fd9d5a1685b33193d` passed the same suites:
102 tests with seed 20270720 and one case at a time. The retained log is
`_build/p30-current-validation.ri5cUYdZ/_build/planning-cli-mcp-tests.log`.
This uses synthetic provider and MCP processes and is not live-server or
platform qualification.

## Resume-selected ceilings

The initial implementation inherited only the original Session header. A
synthetic normal session resumed with planning and then resumed without the
flag lost the planning ceiling (seed 20270721). The uncommitted repair checks
the latest saved mode again after acquiring the Session lock, records a changed
resume mode against the previous mode, and inherits that checkpoint on later
resume. It also binds declared-MCP startup epochs to the checkpoint while
preserving the temporary draft ceiling. Explicit denial selected at resume is
retained across a later `--yes`; malformed, reordered or widening checkpoint
controls refuse.

The fixed snapshot `5d2df9ac44897091620f32683a46541219981f77` passed 131 CLI,
mode, permissions, draft, MCP and resume tests with seed 20270724, after forced
strict test-environment compilation. Later CLI and explicit-denial tests were
added separately. Historical sessions that were resumed with a restriction by
an earlier build without a checkpoint cannot reconstruct that unrecorded
selection. These journal checks are structural and do not authenticate a
wholesale rewrite or deletion of history. In-session transitions and final
acceptance remain open.

The later test-only tree `eb4bc339a83cf0acd22fec038e0a6c8e6ed678a2` passed
20 mode, multi-resume CLI and decision-Session tests with seed 20270727 (37
unselected CLI tests excluded). The retained log is
`_build/p30-current-validation.ri5cUYdZ/_build/execution-mode-resume-extra.log`.
Further test-only tree `7e52237323e241d0795c73541ee63d4a548b7b62` passed
53 mode, MCP, multi-resume CLI and decision-Session tests with seed 20270731
(37 unselected CLI tests excluded). It includes a pending-draft epoch bound to
the persistent checkpoint, a modified checkpoint/epoch mismatch, and a legacy
header starting a new checkpoint. Its log is
`_build/p30-current-validation.ri5cUYdZ/_build/execution-mode-resume-final-tests-r2.log`.

## Resumed draft exit

A synthetic interrupted draft resumed under its temporary draft ceiling,
was cancelled, and then made an ordinary MCP call. The call completed, but
saved reconstruction rejected the history because the MCP replay tracker still
held the temporary draft mode (seed 20270802). The uncommitted repair returns
that tracker to the persisted mode on draft cancellation or consumption, while
keeping the temporary ceiling through draft completion. An actual Session test
passed after the repair (seed 20270803); a second verifies that a planning
ceiling selected at resume remains active after draft cancellation (seed
20270804). Pure replay controls exercise both cancellation and consumption,
and refuse an ordinary call before the completed draft is consumed.
Fixed tree `d568f43e798952ad933fd2761fa14adb3d22f157` passed 135 CLI,
permissions, mode, draft, research and MCP tests with seed 20270806 and one
case at a time, after forced strict test-environment compilation. The retained
log is `_build/p30-current-validation.ri5cUYdZ/_build/planning-draft-exit-tests.log`.

## Legacy knowledge ceiling checkpoint

The first checkpoint for a legacy header without an execution mode did not
consider the knowledge ceiling. A real synthetic Session resumed with knowledge
paused therefore wrote no mode checkpoint, and a later resume could restore the
default available ceiling. The new regression failed on the missing checkpoint
before the repair. The uncommitted repair also checkpoints paused or disabled
knowledge when the previous mode is absent. The Session regression creates a
legacy header, selects each restriction, closes, inspects the saved mode and
resumes with `--yes`-equivalent approval; both restrictions remain effective.
The focused mode and MCP suite passed 52 tests on the working tree with seed
46281. This does not authenticate wholesale journal rewriting or establish P31
acceptance; a restriction never recorded by an older build cannot be recovered.
The documentation checker reported 0 errors and the two edited Elixir files
passed the formatter check. A separate `mix compile --warnings-as-errors` attempt
could not acquire Mix's TCP filesystem lock (`:eperm`); test compilation and
the focused suite did run. The strict compile remains to be rerun on a suitable
host or environment.

## Planning transition provenance remains open

The original resume implementation folded saved local and enclosing ceilings
into one enclosing ceiling. An initially local planning ceiling and an initially
inherited planning ceiling therefore became indistinguishable. The later
version-2 continuation below preserves the two fields on same-owner resume,
but cannot reconstruct provenance already lost in a version-1 checkpoint.
Neither field alone authorizes an in-session exit. A transition still needs
explicit operator-bound local ownership and its prior floor, and must refuse
ambiguous legacy histories. It must also preserve approval and knowledge
restrictions, handle active or queued effects, rebind planning MCP epochs, and
keep deferred decisions subject to separate explicit save and revalidation.
No in-session exit is implemented by this follow-up.

## MCP replay restrictions across resume and draft completion

The MCP replay tracker previously ignored resume mode checkpoints when no
planning-read declarations were configured. A normal header followed by a
planning checkpoint and an undeclared MCP start was therefore accepted by this
tracker, although live dispatch applies the ceiling. A synthetic replay
regression reproduced that acceptance. The uncommitted repair updates the base
and effective replay mode at such checkpoints and checks inherited restrictions.

The tracker also retains the draft restriction after completion until actual
cancellation or consumption, and refuses planning MCP intents during that
interval. When declarations are configured, a checkpoint may be the final
durable prefix after a crash; replay now refuses work in the interval before a
new bound epoch, while allowing the next checkpoint or epoch. These are replay
controls, not proof of live external-server behavior or whole-milestone safety.
The working-tree draft, Session, MCP and mode suite passed 72 tests with seed
46285; after adding a repeated-checkpoint recovery control, the focused replay
file passed 3 tests with seed 46286. Both use synthetic inputs and services.

## Restricted session grants

The ephemeral permissions layer previously returned existing workspace or
shell grant sources, and accepted new session grants, even with a planning,
draft or read-only ceiling. The dispatch gate separately denied the actual
restricted effects; this finding does not by itself establish an executed
effect. A new test reproduced the permission-layer inconsistency (seed 46310).
The uncommitted repair refuses both applying and issuing grants under any
restricted or invalid mode, including an enclosing ceiling. It retains the
existing grant state for the previously documented temporary-draft lifecycle;
it does not implement in-session planning transitions or authorize queued work.

The permissions, mode, draft, MCP and CLI suites passed 118 tests (seed 46311).
A subsequent actual-Session test held a draft request open, checked that an
existing edit grant could not be applied or issued while drafting, cancelled
the draft and checked the prior grant again. That test and the permission suite
passed 9 tests with 16 unrelated draft cases excluded (seed 46312). The tests
use synthetic providers; no live carryover or final safety qualification is
implied.

## Same-owner resume provenance

The uncommitted implementation now uses `Mode.resume` for the same Session,
retaining active and enclosing ceilings separately and monotonically. Child
delegation still uses `Mode.inherit`, which moves the parent's strongest ceiling
into the child's enclosing floor. New changed-mode checkpoints are version 2;
saved reconstruction accepts old version-1 checkpoints using their original
rules and verifies version 2 with the new separate-floor rule. Existing version-1
histories remain restricted but cannot recover a previously collapsed origin.
Older runners that do not understand version 2 refuse those histories.

Pure mode and replay tests cover the two origins, child inheritance, tampering,
legacy checkpoints, explicit denial and knowledge restrictions. Actual Session
tests exercise both origins over multiple resumes, and the MCP and CLI tests
exercise declared reads and denied writes. The first integrated run passed
117 of 119 tests; its two failures were old CLI assertions expecting the former
collapsed display. After updating those assertions, 119 passed (seed 46362).
These are synthetic tests; explicit witnessed transitions, queued-work fencing,
deferred save, whole-source regression and final review remain open.
The synthetic child-delegation and mode suites separately passed 45 tests
(seed 46363). A forced test-environment compile rebuilt 152 modules with
warnings treated as errors; the repository formatter and documentation checker
passed. The full native and platform gates remain open.
After explicitly rejecting unknown checkpoint versions in the standalone
undeclared-MCP replay validator, the mode and replay selection passed 23 tests
(seed 46364) and the forced strict compile passed again.
