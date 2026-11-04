# P30 simultaneous committed-preflight failure: read-only audit

Dated 2026-11-04. This is a source/retained-evidence diagnosis, not a passing
simultaneous consumer control, known settlement, new actual trial or production
repair. No app, native helper, network/provider, Session resume or effect was
started. The failed actual and its original private source/runtime receipts
remain unchanged.

## Established stage and timing

The existing safe failure packet establishes both actual committed decision
preflights, both real reserve/fits calls and one fitting reservation. The first
consumer lost the one-call race. The second won the reservation but its action
failed before any decision dispatch/response/wire observation. The one reserved
model operation remains unknown with one call conservatively reserved, not a
known zero charge or successful settlement. Consumer publication intents are zero.

The retained durations are decisive against a five-second gate-timeout theory:
first request 3,026 ms includes its 2,851-ms hold; second request 384 ms includes
its 116-ms hold. The corresponding decision preflight budgets are 120,000 ms.
Thus at most 268 ms of the recorded winner request was outside the observed
hold. These do not establish the exact failure subtype.

The service ledger has sequence 14, revision 41, thirteen settled recent entries,
no active entry and no queue. All thirteen wire observations are ordinary main
requests. `InferenceSlots.Ledger.cancel_unstarted/4` would append a recent
`not_started` entry; `cancel_waiting/2` removes only the queued request. This puts
the extra request before service admission. The source window is
`InferenceSlots.admitted/10`: initial eligible check, `before_admit/6`, then
committed admission. The callback/error path removes the queued request. Final
Session dispatch admission runs through ManagedUse.with_dependencies and appends
an inference_dispatch_intent only after current-owner checks succeed. No such
decision intent exists here. The public failed-partial completion deliberately
retains no raw service-gate error, and `decision_request_failed` cannot reveal
which fast predicate or callback failed. There is no evidence for a specific
busy lock, source loss, unconditional host defect or a five-second timeout.

## Active-original hypothesis excluded

The fixture creates two original pending proposals in distinct Sessions and
calls confirmed close before starting the child consumers. Each child starts a
fresh Session without an ID; neither consumer is either original. Consumer IDs
are also distinct from one another.

Pure Saved/ManagedLineage reconstruction of each exact decision-preflight prefix
recomputes its complete dependencies_sha256. Both unions contain exactly two v3
root observations and one v7 pending-proposal observation. Occurrence/version
references resolve only to that child's own earlier original: first to first,
second to second. Neither references the other active consumer or the other
original. The decision preflight replay branch requires projection=nil and
preserves this union while clearing its pending preflight. This excludes the
proposed cross-OS-process active-original/two-consumer union explanation.
The pure receipt reports durable release intents; that marker alone is not
claimed as native cleanup authority. Confirmed closure is the fixture's actual
required original lifecycle boundary.

## Separate idle-reopen gap

Both completed histories pass Saved.restore. The first consumer then fails its
real idle reopening with invalid_semantic_admission. Pure chronology being valid
does not establish current admission. Session.open_existing first restores the
pinned activation; SemanticAdmission.resume then reconstructs current identity,
selectors/routes and pin context and calls ProjectIdentity.with_binding. Its
failure branches collapse to invalid_semantic_admission. The binding callback
uses the ordinary native index transaction; an unavailable lock can fail closed,
but that is only a source possibility, not the retained cause. The public record
lacks the failing inner return. The consumer attempts this postlude while its
peer may still be completing admission; overlap alone does not prove contention.

The fixture also mislabels the reservation winner by testing final action status
instead of the successful reservation return. Fixing that classifier would not
supply known settlement, decision egress or idle no replay. No fourth actual or
production change is proposed by this audit.

## Narrow next evidence, if separately authorized

An additional diagnostic would need to retain the existing before_admit/final
source-gate return and the exact resume substage, using bounded typed/hash-only
observations. It must preserve the same owners, current-source checks, deadlines,
reservation accounting and unknown/no-replay fences. New timing or a different
barrier cannot be used to reinterpret this failed cohort. Existing single-consumer
settlement and the native in-flight pool control retain their separate scope.

The accompanying timing/source-union outputs contain only counts, duration and
identity-relation booleans. Their scripts read supplied retained paths; they
cannot activate or replay authority. Source pins identify the inspected contracts.
The current failed public packet remains included unchanged, including its hash
manifest. No transcript, approval code, user source body, private Session ID,
journal/state file or credential is exported.
