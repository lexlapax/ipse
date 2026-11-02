# Leave a pending proposal for later without renewing it

Dated **2026-11-02**, based on `4bcf7cb` plus the source inventory in the
[structured receipt](pending-deferral-20261102.json). This is an author-run
component record. The [plan](../../plan.md) owns remaining acceptance; current
procedures belong to the [operator manual](../../operator/knowledge-permissions.md#leave-a-proposal-for-later)
and [contributor training](../../developer/knowledge-extensions.md#leave-the-exact-candidate-pending).

## Keep deferral a choice to review later

The [frozen contract](baseline.md#confirming-a-proposed-decision) requires an
explicit defer choice while bounding pending lifetime to seven days. It does
not require a persisted snooze deadline. `knowledge defer PENDING_KEY` therefore
reads the exact candidate and signed clocks, reports `pending` or `expired`,
and leaves storage unchanged. It cannot extend expiry, suppress recapture,
start a model or worker, create a charged operation, or save an acceptance event.
Later acceptance requires its own fresh native display and current source/consent
checks. JSON and nonterminal clients can request this read: its response grants
no human attestation or publication authority.

`Management.defer/3` reuses protected existing identity, the installed recipe,
existing management snapshot and the retained signed historical proposal reader.
It remains available after capture disable/revocation, after expiry and when
the original source journal is unavailable. Its bounded response includes the
key, exact revision/value hash, signed first/deadline and observation time.
There is no new Rust protocol, dependency, native limit or mutable storage kind.

## Verification and scope

The focused option/target checks passed three tests at seed `791818`. The first
native cohort, seed `791819`, passed three and failed five tests in 41.7 seconds:
repeated signed deferral and unchanged-state checks passed, but the fixture
expected a management-level error for an absent key. The held reader actually
returns `collection_observation_refused`. Only that fixture expectation changed;
the failed log and fresh stores were retained, with no replay.

The corrected cohort passed **eight tests in 70.9 seconds**, including repeated
JSON deferral after revocation, visible signed expiry, shared-source retention,
missing/malformed targets and the subsequent native rejection controls. Each
deferral leaves the exact Collection, complete control snapshot and existing
journal bytes unchanged. The fresh-SDK actual Session-produced candidate journey
passed **one test/17 excluded in 18.7 seconds**, including deferral while the
original journal was unavailable, later native correction and separate fresh
acceptance. Its main-model behavior is synthetic. Final build, CLI, formatting,
strict compilation, demo/help, manual checks and post-run inventory are retained
in the structured receipt.

Synthetic source members and main-model behavior
do not qualify real model quality, human use, installed platforms or the selected
annual workload. Batch review, broader loss/geometry, independent audit and final
integrated full-source acceptance remain open. No release is published and no
live-call allowance is consumed.
