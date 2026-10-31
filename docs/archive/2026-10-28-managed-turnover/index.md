# Managed turnover: first typed lifecycle increment

Historical implementation record, 2026-10-28. Current scope and status belong to
[the plan](../../plan.md); the accepted workload is retained in
[the frozen knowledge baseline](../2026-10-26-p30-p31-implementation/baseline.md#evidence-retention-forgetting-and-migration)
and [qualification contract](../2026-10-26-p30-p31-implementation/qualification.md).
This record supplements the separate
[4,000-publication capacity result](../2026-10-26-p30-p31-implementation/capacity-available-host.md).
It does not replace that result or its retained failures, and is not annual
turnover or milestone acceptance.

## Required workload and implementation gap

The accepted endurance floor is 30 simulated workdays at 40 turns/day,
20 new ordinary items/day, four corrections and two forgets/day, with 200
persistent notes: 100 pins, 50 preferences and 50 current temporal assertions.
It continues to day 90 and day 365, includes four temporal supersessions/day,
a seven-day offline queue, restarts/imports and overlapping OS processes, and
separately counts 10,000 update/correct/forget cycles. Ordinary support expires
after 90 days; temporal history survives 365 days after supersession and pinned
support stays pinned. Reads cannot renew deadlines. The provisional domain and
total envelopes remain 24 MiB and 64 MiB; normal supported intake must not pause.
The workload requires representative and maximum-size values and measured intake
may increase the floor. The static-review proposal also calls out a day-90 burst.

Before this increment, NormalizerV3 admitted only fresh literals and proposals.
Pure `IpseKnowledge.Notes` retention functions and compact management capsule
syntax did not supply a protected typed lifecycle API. Translating forget,
correction or expiry into generic raw Collection writes would not satisfy that
gap. This section implements the first typed increment: exact native-reviewed
forgetting of one signed literal note. Pinning, duration changes, correction,
temporal history, expiry collection, bounded suppression compaction and domain
import/adoption remain necessary before actual annual turnover can run.

## Implemented boundary

`Ipse.Session.ManagedLifecycle.prepare/3` builds immutable review facts and a
journal intent from an already authenticated managed literal observation. Facts
bind the owning session/job/client nonces, project, namespace, worktree binding,
current management epoch/fingerprint, optional historical pin, exact literal
recipe, current native root, selected key/revision/value, signed policy/clocks,
reason, operation ID and action digest. The full target is displayed by the
existing native Review primitive; JSON-shaped facts grant no permission.

`NormalizerV3.forget/3` runs only inside the actual locked managed Core callback.
It rechecks the exact original request/root, signed format, live and anchor
pages, selected value hash, source lineage, category, recipe and clock baseline.
It consumes the actual same-owner one-use native Review permit against those
exact facts before signing the changes. It atomically deletes the selected
public literal and its live row, and retains a signed anchor with a native
management capsule and literal retirement. The original admission/deadline
clocks remain unchanged. Same-support automatic recapture refuses; older
imports refuse below the advanced native floor. Original journals and shared
source evidence remain distinct from the removed derivative.

The later disclosure-only change explicitly includes the retained management
review journal in the native facts; `disclosure-followup.json` preserves that
source separately from the original executed component snapshot. The subsequent
[protected Consent and CLI integration](../2026-10-26-p30-p31-implementation/managed-forget.md)
and [narrow tmpfs profile admission](../2026-10-28-native-profile/index.md) have
their own receipts and limitations.

Forgetting does not require the original evidence to remain current or the
note's TTL to remain unexpired. The standalone owning caller must separately
revalidate protected management authority and mode ceilings, durably journal
intent, reserve finite management resources and settle only after outer cleanup.
The existing automatic-capture grant and `Consent.with_policy` read callback
are not mutation authorization. Root integration of its new Consent management
transaction and standalone CLI is a separate section, not established by these
direct component checks.

Bounds remain 32 charged reads, at most five metadata changes, four nonnull
6-KiB sidecars, one metadata deletion and a 2-KiB normalization receipt. A native
permit remains in its creating process: preview, terminal review and subsequent
reacquisition/publication must all run in the same outer Resources file-effect
process. Terminal IO runs after preview locks are released.

## Checks actually run

- The two changed production modules compiled with warnings as errors.
- Three focused schedule/production pure-policy tests passed in 0.2 seconds.
  These exercise exact ordinary day-90 expiry, a first temporal update after
  day 90, history's 365-day boundary, persistent preference and pinned history,
  nonrenewing saved downgrade deadlines and saved forget suppression.
- Two focused native tests cover three actual PTY scenarios. The final receipt
  is retained in [the final log](focused-native-final.log). A real Review permit
  is consumed in the actual Core transaction. The old signed ordinary fixture
  is already expired at the actual host time and remains deletable. Nil and
  forged JSON permits refuse; changed client facts invalidate the genuine
  permit; bare yes cancels. Refused/cancelled stores retain the exact prior
  root. Successful forgetting retains authenticated suppression, blocks
  recapture and old-floor import, and a duplicate operation ID never executes
  the callback twice. A genuine owner-only Journal.Writer persists the intent
  before mutation. This fixture does not invoke the new Consent transaction.
- Focused formatting and whitespace checks cover the owned files. No aggregate
  suite or repeated capacity publication workload was run.

The native checks use a new private override directory
`_build/turnover-sol-20261028/ebin` over the unchanged frozen
`_build/capacity-sol-20261028-02` runtime. Only the two production modules are
overridden there. The helper hash is
`86d6226c868b7095c6ba7460cc0b42832e98fb70feea0779fb3473ac7bb28a6a`;
its explicit private Linux 7.2.11 test profile is diagnostic. Product admission
remains unchanged. Fixture origins are trusted synthetic source members, while
the terminal, native Collection publications, DomainAuth tags and readbacks are
actual. No model, live account or product Session journey is claimed.

Initial sandbox runs failed before terminal review because the filesystem
sandbox presents `/tmp` with owner UID 65534; the unchanged native channel
requires a root-owned sticky temporary root. The failures are retained. The
controls now explicitly assert that a supposedly reviewed scenario entered its
callback, preventing a refusal from masquerading as a changed-facts pass.
Native checks passed outside that filesystem sandbox, with the same helper.
No lock file was deleted and no channel/storage gate was weakened.

## Retained artifacts and next qualification

[The clock report](clock-controls.json) and developer controller explicitly say
that their frozen schedule is proposed and no native annual turnover executed.
They preserve all workload floors, checkpoints and seven offline source days;
cycle mix/targets and the remaining typed adapters still require freezing before
execution. Pure policy checks are not native capacity, elapsed performance or
actual 30/90/365-day turnover evidence.

`provenance.json` binds the source snapshots, overridden modules, frozen base
runtime and diagnostic helper. `manifest.json` lists every retained artifact's
digest and size. All earlier 4,000-publication graphs, stores, frozen drivers,
pending oracles and failure logs remain untouched.

Next qualify the actual standalone management owner through its new protected
Consent reservation, native terminal and installed CLI, including disabled or
revoked capture, stale epoch/root, cancellation, owner loss and unknown cleanup.
Then implement the remaining typed lifecycle operations and freeze their exact
cycle/clock/payload protocol before a bounded real turnover run. This component
pass does not mark P31C1a or the notes release complete.
