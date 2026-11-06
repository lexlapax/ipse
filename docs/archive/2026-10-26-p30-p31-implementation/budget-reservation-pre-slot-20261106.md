# Budget reservation before inference service selection

This record describes a scoped host-accounting correction evaluated on
2026-11-06. It does not establish a model-quality result or complete the P30/P31
milestones. See the [current plan](../../plan.md) and the operator's
[accounting guide](../../operator/resources.md) for current behavior.

An isolated Word comparison recorded an admitted embedding attempt, but its
registered service failed before the budget callback ran. The Session journal
then contained an admission with no corresponding ledger entry, and its saved
accounting could not be safely joined on resume. The comparison did not yield a
retrieval result. Its original evidence remains unchanged; the attempted call
remains in the conservative model-call accounting.

The host now reserves before registered-service selection and waiting. The
existing dispatch and settlement remain inside the actual callback. A failure or
interruption before dispatch leaves the reservation outstanding; it is not a
claim that an uncertain callback did not run. Unregistered execution uses the
same reservation and settlement logic. The ledger format, provider selection and
unknown-effect policy are unchanged.

This closes the observed service-selection gap, not every admission-to-ledger
gap. Managed preflight or decision preparation can refuse before the dispatch
owner reserves; an interruption can also occur before the reservation is
durable. A saved admission that cannot be reconciled to its ledger still fails
closed rather than being silently repaired or replayed.

Verification used isolated synthetic fixtures and controlled local HTTP, with no
live model calls. A registered pinned embedding control exercised a service-store
refusal, saved-state reconstruction and same-ID idle without a provider request.
Other controls covered registered and unregistered success, conservative unknown
liability, queued source/consent changes and single execution. The complete
default run of the three focused budget and inference-dispatch files passed 50
tests in 18.6 seconds, excluding the repository's default opt-in native/platform
tags. The preceding run had 48 passes and two failures from stale assertions
about queued reservations; those expectations were corrected. The normal offline
test build compiled 199 host files and four bundles. Its first attempt failed
before compilation with an empty private package cache; the second used the
existing offline cache and passed.

The credential-free demo also passed in a fresh temporary home, with the full
source inventory unchanged. Its first sandboxed invocation stopped before the
CLI because Mix could not acquire its local TCP lock; the permitted invocation
completed without a model service or credentials.

Source and runtime checks passed for the successful focused run, excluding only
Mix's test-failure bookkeeping file from the runtime inventory. Its temporary
process group was empty after the run. Two test-owned Mix files initially
prevented automatic directory removal; they were verified unused and removed
with their private temporary directory. The failure, successful test output and
source/runtime postchecks are retained in the local verification workspace. An
independent source review accepted the two host owners within the stated scope.

No historical Session or budget ledger was edited, and no failed comparison was
reclassified as successful. Fresh installed-runtime and local-model comparisons,
quality evaluation and the broader milestone acceptance remain separate work.
