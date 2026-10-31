# Independent review of private management journal/control sharing

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
the [prerequisite receipt](management-share-controls.md), manifest SHA-256
`3dd4c3e51017e1e6258b69a438373431dfbb1ca4998949da2e915a7b6d515121`,
against the [Management journal repair](management-journal-owner-design.md),
[held-target review](management-held-target-independent-review.md) and
[private tty bridge review](../2026-10-29-native-shared-lease/tty-session-bridge-independent-review.md).
No runtime/native edits, model/network calls, gates or test reruns were made.

## Disposition

Accepted as an inactive standalone-management prerequisite. No new blocking
defect was found within that scope. The original management journal can use
the existing sharing owner/Writer protocol without releasing its original
lock, and the actual CLI caller and tracked journal peer can own distinct native
controls. These are private same-VM interfaces to trusted callbacks. They do
not constitute protected display, settled-close, Review or effect authority.
Ordinary management header mode and public forget/retain gates stay unchanged.

## Evidence and its limits

The [verification script](management-share-controls-review/review-manifest.exs)
and [result](management-share-controls-review/review-manifest.log) verify all
40 manifest entries, 39 frozen sources, each complete 697-physical-file runtime
inventory and eight retained feature BEAMs per graph. Current controls differ
from the earlier journal-positive graph only in Management, Resources and
Runner; the old-helper graph differs from that earlier graph only in Runner
and its matching helper. The new helper and Journal/Writer source bytes equal
the reviewed tty-bridge cohort. The current control graph is not a whole-source
qualification of every current subsystem.

The final source contains the journal transfer, older-helper refusal,
owner-loss, replay and stalled-transfer test bodies. I inspected their retained
logs and the clean compile markers. The initial six stale-base warnings remain
unqualified evidence. The clean original-journal positive is stored under a
`v1-test` sequence filename; Life clarified that its launch used the clean v2
graph, after that graph's compile. The retained test log prints no graph path
and no separate launch script was saved, so that attribution depends on the
original execution transcript rather than an independently retained launch
receipt. This review does not infer it from the filename.

The earlier whole Management/test source for journal-positive and old-helper
controls was not saved before additive control-waiter functions were introduced.
The owner-loss/replay controls also preceded the stalled-test insertion, without
an exact earlier whole test-file snapshot. Exact earlier binaries/inventories,
logs and unchanged retained bodies support their separate observations; they
do not establish one final source-identical aggregate cohort.

## Source boundary

The journal candidate resolves an existing project and acquires its original
native `header_share_v2` lock before creating the header. The same native owner
writes/fsyncs header and Writer appends. Metadata retains the management and
native-owner markers and original source identity; it does not add the signed
release marker. Writer is tracked by that guard. Its barrier drains existing
work, captures the exact offset/count/identity, refuses appends, and binds the
owner's operation/token. Guard arming checks that exact tracked Writer barrier;
export and settlement retain token/operation and native transport binding.
Writer thaw consults the guard's settled/cancelled state. Writer closes before
the outer guard is released, and failed closure/release preserves uncertainty.

The controlled candidate starts its original five-second monotonic setup budget
before opening either sender or journal. CLI owns its Port; the file-effect
peer owns the journal Port. Sender readiness precedes pipe-identity use.
The management-only waiter binds its request to the original ticket and exact
tracked effect pid, permits one CLI handoff and checks the original deadline
and exact bounded H/T operation/role frames. Journal handoff additionally
requires the actual Port owner and consumes its ticket before sending.
Foreign-process calls cannot use either control; replay closes the affected
sender and poisons the result. Native endpoint authentication remains the
previously reviewed handoff protocol.

Generic `file_effect/2` behavior is preserved. Once arbitrary file IO has begun,
it can outlive the caller; this candidate cannot promise hard cancellation or
a bounded return for every blocked file callback. Failed/transferred waiter
phases may wait for that peer to finish. `{:transferred, value}` records the
handoff and callback return only, including any nested uncertain callback
result; it is not a new post-deadline effect-success or all-copy-close receipt.

## Observed controls and next boundary

The journal control freezes an actual append, transfers the original description
to an inert authenticated collector, proves a contender remains blocked,
settles, thaws and appends again. Older helper refusal occurs before any
journal header. The two native observers distinguish CLI death while the
journal peer still lives, then that peer's later death. Foreign requests and
replays refuse; the stalled handshake ends uncertain at the original setup
deadline. No tty, protected fact, actual Review or all-copy display closure is
exercised here.

Protected integration still needs immutable full target facts under actual
Identity/Consent/Collection owners, the intended four attested roles, exact
native tty/input bindings, independently established close/settlement ordering,
accepted management wall and monotonic budgets, safe input/redraw and live
one-use Review with fresh final revalidation. The five-second private setup
budget and transfer callback do not replace those rules or authorize the
pending production journey.
