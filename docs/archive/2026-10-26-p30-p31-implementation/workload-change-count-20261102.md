# Annual workload change count — 2026-11-02

Developer clarification in the project conversation on **2026-11-02**:

> 10,000 changes total is fine

The question explicitly distinguished 10,000 mixed changes from 10,000 rounds
containing all three actions. Both choices were described as additional to the
simulated year of normal use. The selected requirement is therefore **10,000
mixed update/correct/forget changes total**, in addition to that year's normal
workload. The three-action interpretation is a retained comparison, not the
required churn count.

This clarifies the ambiguous “cycles” term in the historical
[qualification contract](qualification.md#storage-and-performance). It preserves
the initial 2,000-note floor, 30/90/365-day journeys, daily ordinary additions,
corrections, forgetting, temporal supersessions, doubled burst, offline/restart/
concurrency/import requirements, retention, storage and quality gates. It changes
no native permission, runtime limit, paid-call allowance or release authority.

## Apply the selected count

Use `StorageWorkload.native_operation_floor(365, 10_000, :mixed_operations)` for
the initial arithmetic preflight. Its **22,980** minimum IDs exclude expiry,
imports, compaction, recovery and control management. Actual intake/mix still
needs pilot ratification and a complete native effect ledger. The lower bound
is below the unchanged 32,768-ID limit; it does not prove that the complete
workload fits.

The [receipt geometry probe](native-receipt-geometry-20261102.md) measures
4,899,325 canonical packed bytes for 22,980 synthetic managed receipts with
2,000 public descriptors in its all-floor-advancing scenario. That measurement
omits actual values, signed sidecars, migration and resource peaks. It supplies
no native capacity or endurance acceptance.

The earlier 42,980-ID/8,639,325-byte scenario remains valid evidence for the
unselected three-action comparison. A storage redesign must be justified by
the selected complete workload and actual bounds; this clarification alone
neither requires an ID-only increase nor establishes that no repair is needed.

The [current plan](../../plan.md) owns implementation status, and the
[storage training chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns the runnable preflights. The primitive driver's churn does not become
authenticated native lifecycle coverage through this count clarification.
