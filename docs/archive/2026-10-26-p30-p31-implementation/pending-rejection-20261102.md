# Reject one pending proposal without retiring shared evidence

Dated **2026-11-02**, based on `9ada4f1` plus the source inventory in the
[structured receipt](pending-rejection-20261102.json). This is bounded author-run
source/native component evidence, not independent review, installed qualification
or P31E completion. Current procedures belong to
[knowledge management](../../operator/knowledge-permissions.md#reject-one-pending-candidate)
and [contributor training](../../developer/knowledge-extensions.md#reject-a-proposal-without-retiring-its-source).
The [plan](../../plan.md) owns remaining acceptance.

## Select the smallest reducing operation

The frozen [proposal contract](baseline.md#confirming-a-proposed-decision) requires
rejection to remain available with capture disabled. The existing native
management route handled literals and accepted decisions; single-card proposal
review supported acceptance only. A pending candidate is identified by its
source lineage and exact proposed text. Several candidates and a literal can
share that source. Reusing literal retirement would incorrectly suppress the
whole lineage.

The new `knowledge reject PENDING_KEY` route reuses the management journal,
retained Identity/management Consent/Collection display, released input wait,
fresh exact `reject CODE`, volatile one-use Review permit, bounded accounting,
deferred settlement and unknown/no-replay behavior. Original source availability
and active capture consent are unnecessary for this reducing action. The existing
management epoch and installed bundle must still match.

`PendingRejection` prepares complete immutable facts, including the full proposed
request, and two public CAS changes:
remove the exact pending revision and insert `reject.<candidate_id>`. The marker
binds the candidate, original value hash/revision and management operation; it
contains no repeated proposal text and grants no positive authority. The native
normalizer reauthenticates the record, original signed anchor and live row,
reproduces the facts, consumes the actual permit and removes only that live row.
The shared source anchor is unchanged. Fresh capture and acceptance check marker
absence; the destructive floor prevents old-backup resurrection. Suppression and
journal/ledger costs remain retained, with no silent pruning or limit increase.
The reducing reader permits the shared literal's signed choice/retirement or
saved override; those cannot make a separately authenticated pending target
undeletable. Acceptance keeps its stricter reader and current-source checks.

This host change is necessary because extension code cannot mint protected
native input authority, retain the management ownership chain or sign lifecycle
index repairs. It adds no worker-selected management route, framework,
dependency, Rust protocol or provider/model call.

Capture normalization reuses the existing per-callback bounded read-cache helper
so the additional rejection lookup stays within the 32-unit ceiling. Cache scope
is one unchanged held Collection callback; it never carries observations across
owners or roots. The maximum shrink/split fixture now charges 14 units and its
proposal/summary variant 23; actual small literal initialization/follow-on cases
charge 11/13. Their old exact expectations caused the first regression failures;
the successful effect/receipt expectations were retained.

## Verification and retained failures

The first mode/options cohort passed two tests, excluding three explicitly tagged
native cases. Explicit native seed `791803` then passed three tests/four terminal
scenarios in 32.9 seconds: live and expired candidates after capture revocation,
cancellation and stale codes. The fixture uses trusted synthetic source members
and actual signed storage, native terminal input, management policy and public CLI.
It does not manufacture a genuine original Session or claim model quality.

The initial affected regression cohort, seed `791804`, ended with **77 passed,
four failed** in 65.7 seconds. All four failed old exact read-count expectations
after callback-local caching; their raw output remains retained. Updated exact
counts passed the same complete cohort at seed `791805`: **81 passed** in
69.0 seconds. Expanded native/concurrency and existing management seed `791806`
passed **21 tests, one optional case skipped**, in 339.0 seconds. After adding the
full displayed request and separate reducing reader, native seed `791807` passed
**seven tests** in 68.1 seconds, including genuine native pin/forget of a shared
literal. The final affected regression seed `791808` passed **86 tests** in
64.6 seconds, including accepted-decision lifecycle separation.

The new Session-to-CLI fixture's first two seed-`791809` attempts failed in
read-only setup before any rejection effect: `get_record` is an internal selector,
not an ordinary Collection request or ReadView request. They ended with **zero
passed, one failed, 15 excluded**, in 10.1/10.2 seconds. The fixture was corrected
to the existing bounded ReadView `get_many` API; no runtime API was widened.
Both failed stores and logs are retained. Final genuine, build and documentation
results are recorded in the structured receipt after terminal completion.

A third fresh attempt passed cancellation, then the test driver timed out at the
native disable prompt because that invocation omitted its existing `--knowledge`
answer mode. It ended with zero passed, one failed, 15 excluded in 70.6 seconds.
The driver killed its child at the fixed bound. The fixture now selects both
existing management and knowledge input modes; no runtime gate was changed.
The failed store is retained and no effect was replayed into it.

The fourth fresh-runtime seed-`791809` run passed **one test, 15 excluded**, in
11.9 seconds. It builds the actual Knowledge artifact against the copied current
SDK, captures two proposals through a real Session with synthetic main-model
behavior, completes close/resume and strict Saved checks, then invokes separate
native CLI processes for cancellation and rejection. The latter performs native
disable, makes the original source journal unavailable under its retained lock,
rejects the selected candidate, restores the original and checks exact unchanged
journal bytes, peer and anchor. The intent retains the original proof. Measured
one-operation/zero-model/download/cost settlement and read-only nonreplaying
inspection agree, and an old-floor import refuses resurrection. No real model,
paid account, installed runtime or human participant is inferred from this pass.
The retained synthetic store is
`/tmp/ipse-native-knowledge-session-2afe9067770df4fd58c54b7ea8b4bdbf`.

The default build, formatting check, warnings-as-errors compilation, isolated
credential-free demo and CLI help checks passed. The copied SDK's BEAM/app files
and native helper still match the current development build; the fresh artifact
manifest matches its isolated installed bundle. These are post-run inventories,
not a complete frozen environment or in-memory closure. Final documentation
validation checked **1,046 Markdown files and 8,659 local links with zero errors**.
Permission-denied private staging directories were not inspected or copied.

## Remaining work

Batch review, correction/defer of pending text, installed journeys, broader loss
boundaries, full selected annual workload,
physical/storage peaks and independent audit remain open. A retained suppression
record and one management operation per rejection must enter that workload's
ledger. The passing frozen full suite at `9f1707c` predates this increment and
does not qualify it. A new integrated final-candidate full suite remains required.
No live-call allowance was consumed and no release was published.
