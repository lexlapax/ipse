# Independent review of fresh and resumed release claims

2026-10-29. This review covers the frozen
[fresh integration](release-receipt-integration.md) and
[framed resume](release-receipt-resume.md). Both source/runtime evidence manifests
verified, including all five standard, hook and old-helper runtime inventories.
The resume source tar's 29 files exactly matched current repository bytes at the
initial comparison. The fresh tar's 30 files differed in the six expected files
subsequently extended for resume: Session, Lock, Runner, the native runner and
transaction helper, and the Session test. No passing suite was rerun.

The review found a confirmed startup ownership defect and a separate journal-size
contract mismatch. These prevent accepting this integration as complete. The
component owner is implementing a native-owned journal mutation follow-up;
that work requires its own verification and review. This report preserves the
original cohorts and does not qualify that later repair.

## Confirmed ownership defect during resume startup

A [targeted probe](evidence/release-receipt-review/startup-loss-probe.exs) first
creates and cleanly closes a genuine Session on the frozen standard resume
runtime. A copied Session implementation then pauses immediately after the
actual retained-lock identity check and before its next owner marker. This is a
test-only scheduling rendezvous; it changes no policy, permission, helper,
signature or journal validator.

The probe kills the actual native lock helper, waits until the guard records
`lost: true`, and acquires the same real flock through an independent contender.
After the paused startup continues, `Session.start_link` returns success and
the journal's owner-marker count grows from one to two **while the contender
still holds the lock**. A further contender refuses, confirming that the first
contender has retained it. The
[result](evidence/release-receipt-review/startup-loss.log) records these facts.

The guard's loss handler notifies its owner, but Session initialization has not
yet begun handling that mailbox. The guard still accepts tracked file-effect
peers after loss, and the host Writer can append through its separate IO process.
The final close cannot produce a valid release acknowledgment from the dead
helper; that does not undo the already-observed write under another lock owner.
Another liveness precheck only moves the scheduling window. Journal mutation
needs an enforceable retained-lock boundary, including startup/torn-tail work.
The actual counterexample covers resumed startup; fresh startup shares the
marker/Writer path but was not separately subjected to this probe.

The [probe manifest](evidence/release-receipt-review/manifest.sha256) retains the
probe, result, [instrumented source](evidence/release-receipt-review/session-rendezvous.ex)
and 669-file base-runtime inventory. The base is a separate copy of the standard
resume-v2 graph; its helper is
`3537ad8f8fb298007d00c67aba40524c3c7daebf6b72f4ee8d831296fbc6b87a`.
The rendezvous Session was compiled and loaded only in the probe VM; its altered
in-memory BEAM was not separately retained. Source and compiler invocation are
retained, so this is a controlled scheduling counterexample, not an unmodified
binary or fresh-checkout acceptance receipt. No production or original frozen
file was changed, and no model service or private pilot file was accessed.

## Journal-size contract mismatch

Native `publish_release` checks the entire journal using `header_private`, whose
16,777,217-byte ceiling belongs to a single transferred header. The host Journal
admits a default 128 MiB whole-file limit. Consequently the publisher can reject
otherwise admitted larger journals and degrade a clean close to unknown. This
was identified from the exact source contracts; a populated large-Session
counterexample was not run by this reviewer. The correction must separate
journal identity/metadata validation from the bounded header transfer, retaining
the latter's limit. The component owner has received the finding.

## Fresh close: what the recorded controls establish

The inspected standard tests cover genuine header creation, original source
inode binding, clean close and signed inspection, signature corruption,
no-overwrite publication, wrong source/lock identity, native helper loss and
torn-tail recovery. The separate helper-hook controls cover Session death after
unlock before its acknowledgment, death after durable publication before its
acknowledgment, and a second BEAM owner reopening during that interval. These
controls establish the tested release/publication paths, not all startup IO.

On the reviewed clean path, the owner marker precedes runtime startup records;
the intent and conservative lifecycle closure are appended while the Writer and
lock remain owned. Dependency cleanup, Writer death and the exact framed
`U/unlocked` plus zero helper exit precede signing. The private publisher uses
retained directory descriptors, exact source and lock device/inode checks,
exclusive staging, file sync, no-replace rename and directory sync. It requires
the exact `P/published` and zero exit to confirm its response. A lost response
remains unconfirmed even if the signed sidecar later appears. Inspection checks
the latest owner/intent, helper pin, source and lock identity and signature while
retaining a native lock, and confirms that inspection lock's release. No earlier
unconfirmed lifecycle record is rewritten.

The earlier actual planning-MCP controls additionally exposed and verified the
owner-marker/nil-session compatibility repair; see the separate
[native live-read evidence](../2026-10-26-p30-p31-implementation/planning-live-mcp-resources.md).
The repair retains the pre-epoch work gate and prevents an old pending start
from becoming authorized merely because another owner marker appears.

## Resume: retained identity and remaining limits

The inspected resume tests cover seven standard cases, two actual hook cases
and the older pinned helper's unknown-command refusal. The selected native
resume mode opens the existing lock without creation, refuses header creation
and export, and reports its retained device/inode. Under that same lock the host
revalidates the journal origin and compares the lock with the latest validated
historical intent before tail repair or the next owner marker. It does not
release and reacquire a live lock to upgrade the mode. The tests retain header
bytes and journal inode across normal resume and check missing/substituted locks.

A historical intent supplies previously observed lock identity; a positive old
sidecar is not required to establish that identity. With no earlier intent,
the current header/owner marker does not identify the original lock inode.
That path deliberately retains legacy resume and unknown close rather than
inventing a framed upgrade. Unmarked older headers retain their older behavior;
these controls do not constitute migration qualification. Non-Linux release
claims are unqualified. A later owner's claim cannot mark a prior owner's
unclosed epoch clean: owner-local selection remains separate from historical
lifecycle facts, including when recording was disabled for the new owner.

The native and host publication descriptors have bounded payloads and structured
close paths; no additional deterministic descriptor leak was identified during
this review. Unknown publication can retain staging or final files, and old
claims remain historical evidence. Full turnover/GC/resource qualification is
separate. Hostile same-user rewriting of both journal and sidecar, or arbitrary
BEAM-memory access, remains outside the cooperative identity/signature boundary.

One caller distinction remains unresolved: the owner-loss tests use
`Session.close_confirmed/1`. The production CLI uses the weaker `Session.close/1`,
whose existing non-strict wrapper can return `:ok` after the owner dies without
a reply. Thus the tested unknown-on-loss behavior must not be generalized to
every production caller without an additional caller repair or explicit
contract limitation. This source-level distinction was sent to the component
owner; no separate generic-close probe was run.

## Subsequent CLI caller repair

The CLI caller gap above was subsequently repaired by this reviewer; the parent
will independently review that implementation. `Ipse.CLI` now always invokes
`Session.close_confirmed/1` after terminal interaction, including when the
Session has already died. Inspection of `Terminal.interact` confirms it stops
its input reader but does not already close or acknowledge the Session. The
existing cleanup warning and nonzero result therefore remain the appropriate
response to missing cleanup acknowledgment. The generic Session API and all
native, Session, Writer and Runner implementation files are unchanged by this
caller repair.

A [focused public-CLI control](evidence/cli-cleanup-ack/test-47021.log) passed
two tests containing three actual Session cases in 1.9 seconds:

- Clean EOF exits zero, emits no cleanup warning and leaves a valid signed claim.
- While the CLI is paused, EOF is queued before its real Session dies. On resume,
  the CLI processes that EOF first but exits one with the cleanup warning;
  the dead owner is not treated as confirmed cleanup.
- The real CLI calls close, and the independently built helper hook holds its
  response after native unlock. Killing the actual Session before the response
  makes the CLI exit one with the warning and no release sidecar.

The EOF ordering uses a test-only process suspension and the existing IO fixture;
there is no function mock, forged permission or model call. The native loss case
uses the separate compile-time helper-hook cohort. No passing test was rerun.
The [strict CLI compile](evidence/cli-cleanup-ack/compile-47020.log),
[four-file source tar](evidence/cli-cleanup-ack/source.tar), standard/hook runtime
inventories and [manifest](evidence/cli-cleanup-ack/manifest.sha256) are retained.
The graphs copy the earlier standard and hook resume-v2 cohorts and overlay only
the repaired CLI BEAM; they are not a combined-current-source or fresh-checkout
receipt. Formatting and scoped diff checks passed.

The parent's independent implementation review accepted the one-line caller
change but identified an ambient-configuration isolation gap in the first
fixture. Its private `IPSE_HOME` did not by itself clear supported inherited
configuration selectors. The revised child clears the known Ipse configuration,
workspace and helper overrides, clears stale release-hook markers, creates an
owner-only home and reapplies only its intentional native hook. Its public CLI
call disables project configuration. Before EOF it checks the demo provider,
disabled sandbox, empty MCP/extension selections and absent shared budget.
The parent test supplies deliberately invalid ambient config/profile/sandbox
overrides so successful setup also exercises that isolation.

Only the affected two tests were rerun after that fixture change: all three
scenarios passed in 2.1 seconds at seed 47022, with no provider requests.
The [updated source tar](evidence/cli-cleanup-ack/source-v2.tar),
[test receipt](evidence/cli-cleanup-ack/test-47022.log) and
[additive manifest](evidence/cli-cleanup-ack/manifest-v2.sha256) preserve the
corrected fixture and reference the unchanged compiled CLI/runtime evidence.
The initial source, compile, test and manifest remain intact. No production
change beyond the original caller line was made during this follow-up.

This verifies the stronger production caller, not the native journal ownership
repair. The confirmed startup race and size mismatch above remain unaccepted
pending their separate implementation and review. The parent owns coherent
commit/push and batches documentation validation.

Managed output/correction and strict deadline-bearing publication remain gated.
This report grants no such authority, makes no milestone-completion claim, and
does not replace the required final combined-source, platform, manuals or
adversarial acceptance work. The parent batches documentation validation.
