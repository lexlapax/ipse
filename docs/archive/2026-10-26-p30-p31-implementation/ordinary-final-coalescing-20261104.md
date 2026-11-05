# Coalesced ordinary final-use observations

2026-11-04, US/Pacific. Historical engineering checkpoint. Current behavior is
taught in [Session sources](../../developer/session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
and the [Collection SDK](../../developer/collection-sdk.md#revalidate-reads-and-downstream-use).
The [plan](../../plan.md) owns remaining P30/P31 acceptance.

## Concrete failure and bounded repair

The retained-cohort read delivered all 36 Worker inputs, then withheld the final
extension output. Its main request ended with partial finality and an unresolved
service outcome; this does not establish that no provider dispatch occurred.
Its last delivered input and final
output committed the same dependency digest. That history remains failed, with
its partial request and quarantined reservation unchanged. This investigation
does not retrospectively identify every earlier failure's cause.

A separate protected STORAGE-only comparison reproduced one concrete bottleneck
under the unchanged DomainAuth lease. It used 32 distinct eligible literal specs
selected from the historical synthetic seed's audit metadata. These are the same
storage class, not a claim to reproduce the failed output's exact 32 selections.
No original-source lease, Session, provider request, regrant or reconciliation ran in that
component. Coalesced ran first to warm storage for ordinary:

| Arm | Completed | Callback time | Views opened | Verify/crypto calls | Result |
| --- | --- | --- | --- | --- | --- |
| Existing coalesced observer | 32 | 655,325 µs | 1 | 96/96 | Success |
| Ordinary per-record observer | 24 | 5,058,054 µs | 25 | 73/73 | `domain_callback_expired` |

Positive crypto-counter coverage, a live upstream parent, verification counts
below 128 and conservative input upper bounds of 595,968/453,184 bytes exclude
the call-count and one-MiB input limits in this component. They establish the
five-second callback expiry here, not an exact trace of the earlier Session.
Both arms did not succeed, so their observation-equality field is intentionally
null. [All seven component statuses](ordinary-final-coalescing-20261104/storage-status.txt)
are zero; [minimal services closed](ordinary-final-coalescing-20261104/storage-services-closed.json).
The full 4,945-object original baseline, nine external objects and all six inert
or quarantined consumers were preserved. No settlement or zero-egress claim
follows from that preservation.

The repair selects the existing coalesced version-4 observer in **both** ordinary
`ManagedUse.with_dependencies_owned/4` protected observations. The helper's private
name now describes both Worker and ordinary use. Each pass starts fresh; original
source retention remains between them. Exact current dependency/root equality,
source checks and expiry remain mandatory. The existing adapter alone chooses
its genuine initial index/slot-capacity fallback. No new cache authority, native
protocol, permission, TTL, call allowance, candidate ceiling or source grant was
added. Other dependency versions and historical/approval/display/publication
observation routes remain unchanged.

## Separate verification outcomes

The private source compiles with zero diagnostics; 43 existing ManagedUse and
ManagedReference pure checks pass without starting Ipse. The complete amended
authentic test owner also compiles with zero diagnostics before any test body.
The current main normal build, strict compile and credential-free demo then pass;
the actual uses a complete private copy of that TEST App and dependencies with
no BEAM override. This is a worktree snapshot, not a clean committed release.

Actual01's fresh native-approved split8 seed passes. Ordinary two-batch passes,
root-only reads, changed context/dependencies, unavailable recipe/source,
stale roots, expiry/revocation and genuine sixteen-slot fallback all pass, as do
delivery, strict Saved reconstruction and confirmed close. The **attempt remains
failed**: its new idle helper reopened with default approval instead of the
original explicit allow/yes mode. A legitimate `execution_mode_resumed` record
violated that helper's owner-marker-only suffix expectation. The idle phase and
saved messages had already matched. Its [classification](ordinary-final-coalescing-20261104/actual01-classification.json),
[failed result](ordinary-final-coalescing-20261104/actual01-result.json) and
[closed statuses](ordinary-final-coalescing-20261104/actual01-status.txt) are preserved.

The fixture correction preserves the original approval mode; it does not weaken
the journal assertion. **Fresh actual02 passes one selected case in 22.1 seconds**,
with 201 other cases excluded. It repeats the above positive/negative boundaries,
then confirms close and same-ID idle reopening with strict journal/no-replay
checks. [Result](ordinary-final-coalescing-20261104/actual02-result.json) and
[statuses](ordinary-final-coalescing-20261104/actual02-status.txt) show success and
all six source/runtime/private/driver/path/link checks at zero. Operator and
owned-process checks are empty. Actual01 was never resumed as a retry.

Separate current-main focused verification also passes four selected cases in
34.8 seconds, including the existing root-change-during-worker-processing and
root-change-during-generation controls (`managed_collection_call_session_test.exs`
6158 and 8106 in the baseline). These are nonadditive with the fixture result;
they supply actual source/root withdrawal evidence after the same core repair.

The [source pins](ordinary-final-coalescing-20261104/source-pins.json) bind actual02
module origins, complete source/runtime inventories, native helper,
driver and test bytes. Exact [source/test](ordinary-final-coalescing-20261104/source-and-test.patch),
[idle-fixture](ordinary-final-coalescing-20261104/idle-fixture.patch) and
[manual](ordinary-final-coalescing-20261104/manuals.patch) deltas are retained.
The [packet manifest](ordinary-final-coalescing-20261104/manifest.sha256) hashes the
content-free receipts; no original journal, transcript, capability, configuration
or private body is copied into this archive.

## Remaining gates

This qualifies bounded ordinary final-use delivery on the fresh eight-source
fixture. It does not qualify a successful retained 2,000-note inference, resolve
its quarantined request, establish the full regression aggregate, or measure
populated-day/30-/90-/365-day throughput. The retained DAY driver remains OFF
until explicit recovery/upgrade review, new current proofs and one successful
ordinary retained read close their separate gates. Earlier failed reads and
unknown outcomes remain inert; neither this repair nor Saved reconstruction
replays or settles them.
