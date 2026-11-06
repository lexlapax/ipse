# Internal document maintenance epoch — 2026-11-05

This is a bounded P31C1b implementation checkpoint, not completion of document
maintenance or GC. Current procedures are in the [Corpus manual](../../operator/corpus.md);
the [developer chapter](../../developer/knowledge-storage.md#fence-document-stages-before-metadata-maintenance)
teaches the internal ownership and publication boundary. The [plan](../../plan.md)
retains capacity, migration and producer-continuation requirements.

## Implemented boundary

The fixed document profile now retains a monotone metadata epoch. Its internal
open/close pair checks the actual native generation, binds the trusted project,
Session, artifact and invocation owner, and reserves exactly two disjoint
operation identities before opening. Reload rederives the opening
descriptor/checkpoint commitment from the state and its receipt. Close uses the
reserved identity and retains the epoch, records, checkpoint, destructive floor
and original operation history.

Publication admission comes from an actual protected snapshot, bound to the
canonical root, project namespace, owner, epoch and idle status. A held admission
from an earlier epoch or from the active phase refuses after close, including
when the caller refreshes the ordinary generation. A fresh idle admission can
publish. A plain document-profile commit without this context fails closed after
the first fence.

Host-owned stage headers retain that epoch without widening the worker request
or result shapes. Old stages cannot append, seal or publish after the fence;
exact abort and expired reclaim remain reducing operations under the current
native fence. The whole Stage operation and admission callback execute in one
tracked file-effect owner. Only the validated inherited deadline crosses a new
effect peer; deadline narrowing, publication-guard refusal and scope restoration
remain intact.

There is no new public SDK operation, Corpus command, capability, dependency,
destructive collector, adoption or recovery path. Source, Index, Job and
Projection continuations still need their own epoch integration. This checkpoint
does not qualify their safe continuation after maintenance or the complete
maintenance-v2 design.

## Verification and preserved failures

The final native lifecycle owner passed eleven controls. They cover stale and
active-origin admissions, root/project substitution, reserved IDs, reload
tampering, safe-integer exhaustion, stored-stage fencing, closed public outcome
shapes, document codec round trips and checkpoint/rollback preservation.

An actual public SDK Session prepares an approved stage, crosses the internal
open/close pair, refuses the old stage and approves a fresh publication. It
checks the journal's typed results, confirmed close and full Saved restoration
without a model request. The inherited deadline control separately checks
no-extension, earlier deadlines, expiry, invalid values, guard nesting and exact
scope restoration in the actual effect peer.

The complete eight affected test files passed **56 tests in 137.0 seconds**,
including existing native pinned reads, append/projection races, fact inputs,
empty facts, Stage expiry and SDK interruption/recovery. Formatting and strict
compilation passed. The final stronger reservation control uses 32,765 local
receipts plus one genuinely imported receipt, rejects reuse of that imported ID,
reserves the last two identities and closes at 32,768 total retained operations.
It and twelve selected existing migration controls passed **13 tests in 37.9
seconds**, with eleven exclusions: nine maintenance tests already covered by the
complete run, and two existing maximum migration fixtures deliberately not rerun.
The strengthened control changes only the disposable fixture; production source is
identical to the 56-test run. No full regression or full-capacity result is claimed.

An earlier assertion merely re-encoded an unchanged document-state map and did
not measure notes compatibility. It was removed. Its replacement performs two
actual notes-profile commits while an active and then stale document admission
is held. The document close leaves the notes root bytes unchanged; the notes
state contains no maintenance metadata, and its actual pointer, manifest and
blocks match an independently constructed normal notes semantic state. The final
eleven maintenance tests, all four existing Encoding tests and one existing
native notes ID/replay control passed **16 tests in 14.4 seconds**, with thirteen
other native Collection tests excluded. This is a scoped cross-profile/codec
check, not a full notes regression or unchanged-byte claim for every workload.

The first broad command reached its 180-second coordination limit while running
the existing migration file, whose near-full case has its own 300-second test
bound. It remains a timeout, not a passing full migration run. A later 36/37 run
failed an observer fixture that used `self()` inside the new effect peer; the
fixture now captures its observer explicitly. The first targeted two-case run
also exposed a missing test alias warning, corrected before the complete run.
All first logs remain preserved privately. The two existing maximum migration
fixtures remain outside this bounded checkpoint's final selected run.

Independent source review accepted the final three production owners after the
active-origin and inherited-deadline repairs. Whole-document developer and
operator review kept the new explanation in the developer chapter; the operator
chapter exposes no maintenance command and needed no change. No retained cohort,
model service, provider selection or original journal was accessed.

## Source and result commitments

These are hashes of source and retained private logs, not copies of journals or
test output. The production hashes are the independently reviewed checkpoint;
the last fixture-only strengthening does not change them.

| Owner or result | SHA-256 |
| --- | --- |
| `lib/ipse/extension/collection.ex` | `de63398e636fcfa83f9f9abb84040001b396942fde0a10d7bd009b4c365fef29` |
| `lib/ipse/extension/collection/document_maintenance.ex` | `0cae23a99f26113176d55eaedcb07c3ddb4b15cac7061d90508832ca28227bb1` |
| `lib/ipse/extension/collection/document_stage.ex` | `bb480fa8c0fae47b569d1c2478e221ecd91b258aa0a093d91c0cd9027b652185` |
| Complete eight-file run: 56 passed | `ccf4213c8c6929e014b1c4d798d52dfa6e330a40fc8b79dd51a80fe3add6dd08` |
| Final imported-ID and selected migration run: 13 passed | `663d23066190cf74a04683b8fe8ffdab5f10658a4552271cb78b8035eb0c5e3d` |
| Final maintenance/notes isolation/encoding run: 16 passed | `8c365ee29d101f491f2af8d6aef7b8ca43d3c95a01a661b34fd07a853b4f7a1b` |
| Initial broad timeout | `cc14a9825cef81a0d3e559909b1db1076f630c79e005cadc29ebe4d82d49b4fd` |
| Preserved 36/37 observer-fixture failure | `f9ef50a586059c3fd093d4cd7f6522ce605ade94ed482f4ca66aa0954404f165` |
