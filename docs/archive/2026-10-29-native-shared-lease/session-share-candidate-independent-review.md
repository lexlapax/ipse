# Independent Session share candidate review — 2026-10-29

This scoped review covers the frozen [Session sharing candidate](session-share-candidate.md)
and manifest
`77f7914becb6cd544634adbfee2571d7615a7db8006bff87a2f1e3659611166e`,
following the [retained-close review](retained-close-independent-review.md) and
[terminal design review](guarded-terminal-integration-independent-review.md).
Inspection used the exact source tar and retained tests/logs. No implementation,
gate or runtime test changed or ran. The [plan](../../plan.md) owns acceptance.

**Disposition: accept this private header/resume and Writer/Lock infrastructure
candidate. No concrete blocker was found within that declared scope.** This is
not acceptance of production Session/Host cancellation or proof barriers, owner
EOF controls, tty delivery, Management conversion or activation.

## Verified evidence

The [verifier](evidence/session-share-review/review-manifest.exs) checked all 36
manifest entries, the source tar containing 36 files, and three exact runtime
inventories: 697 standard, 696 old-helper and 697 diagnostic files. Both standard
and old runtime helpers match the retained binaries. The
[result](evidence/session-share-review/review-manifest.log) is retained.

Final v4 logs show two Writer barrier tests, two actual candidate Session tests,
four selected socket/owner-loss tests and the separate one-test old-helper
refusal. These passing controls were inspected, not repeated. Their socket tag
named `native_sandbox` selects permitted-context socket tests; it does not
qualify another sandbox backend or platform.

The standard graph contains matching Runner/helper and final Lock/Writer
compilation. Its Session BEAM came from the earlier candidate graph compiled from
the same frozen source. Earlier incremental runs are not one final-source
cohort. The initial socket failure and delayed diagnostic remain historical;
the new operation-bound native readiness frame addresses the early-exec timing
without granting activation. The first linked old-helper startup failure remains
retained; the corrected trapped-exit test proves refusal before journal creation.
Later independent Journal/Writer edits are outside this frozen review.

## Native and Writer integrity

The new Linux modes acquire the original header/resume flock at startup, retaining
native-owned header creation, journal Q/W/E, repair, lock identity and framed
release. There is no close/reacquire upgrade. Native `Y` requires completed header
creation or existing-resume mode, no pending header/journal mutation, the current
sequence/depth, next 64-bit owner ordinal, nonzero transport operation and bounded
setup remainder. Overflow refuses. While shared, every command except exact `K`
stops unconfirmed. `K` requires the same ordinal/operation and retained peer's
C/F/G settlement. Failure cannot thaw or reconstruct an old lock. The original
description remains held after successful recipient close. Constant ordinal
state avoids the Transaction prototype's 256 remembered-ID limit.

The guard derives transport identity from a private random owner epoch, ordinal
and caller operation. Only its actual owner can arm/export/settle/cancel; arming
requires the exact tracked Writer and opaque current token. A resumed owner has
fresh epoch/Writer context. Unsupported helpers refuse, and ordinary CLI/config/
worker startup has no candidate selector. Same-VM host code remains trusted;
this is not raw-message isolation or worker authorization.

Writer processes preceding calls before its share request, checks journal
path/open-file identity, offset and source origin, and snapshots its exact count
and source window with caller job/generation references. Frozen Writer rejects
append, reservation and source operations. Guard blocks tracked work and native
journal IO once armed/shared. Caller references do not establish a real Host job.
Safe cancellation is pre-export only; later cancellation poisons the share.

Thaw uses an asynchronous Writer-to-guard request. Writer can still answer the
guard's token check while premature thaw waits, avoiding a guard→Writer→guard
cycle. Only matching settled/cancelled guard state confirms thaw. Failure leaves
the barrier frozen. The synchronized premature-thaw test exercises that exact
ordering. Owner loss is handled conservatively.

## Actual ownership evidence and integration limits

An actual candidate starts, runs a synthetic prompt, closes and resumes with the
same lock inode and unchanged header. Its actual Writer snapshot contains a
source window; foreign requests refuse and pre-export cancellation safely thaws.
Native header/resume tests retain the original flock through repeated sharing,
recipient closure and a later Writer append.

The real Session-loss case shares its actual startup lock, stops the inert
recipient, kills Session and waits for the guard to exit. A contender remains
blocked until the recipient resumes and exits. This proves last-holder retention,
not immediate owner-death notification to a tty writer. In-process
`:sys.replace_state` probes and synthetic job references bypass normal Session
scheduling and do not qualify a production operation/cancellation barrier.

Production integration must prevent all relevant Session job/proof changes from
before Writer freezing through arm/export/closure. The Writer snapshot does not
seal Session state; direct owner repair/control paths must not advance between
snapshot and arm. Startup repair ordering and idle probes do not prove that
future phase. Cancellation must poison promptly without waiting on frozen Writer
IO. Actual Session/Host EOF controls, one common multi-owner deadline, recipient
mode authorization, safe redraw, forked reader/guardian all-copy close, release
before human input and Management native journaling remain open. No protected
gate may open from this receipt. The parent and Lifecycle own subsequent source,
documentation reconciliation and the coherent commit.
