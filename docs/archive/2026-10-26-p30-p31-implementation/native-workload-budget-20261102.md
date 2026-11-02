# Native workload operation floor — 2026-11-02

Dated **2026-11-02**. Author-run pure development preflight from `9f1707c` plus
the sources described here. It changes no runtime admission or storage limit.
The [plan](../../plan.md) owns open acceptance; the
[storage training chapter](../../developer/knowledge-storage.md#budget-native-effects-before-an-endurance-run)
owns current procedure. The original
[primitive workload](storage-workload-endurance.md) keeps its historical scope.
The [receipt](native-workload-budget-20261102.json) binds the source/log hashes
and both CLI reports.

Subsequent [developer clarification](workload-change-count-20261102.md) selects
10,000 mixed changes total in addition to normal annual work. The pre-clarification
comparison and its original unresolved status remain preserved below.

## Separate the two workloads

The old primitive driver starts 2,000 records in 16 batches and calls generic
one-key update/delete/recreate churn “cycles”. Its own record explicitly denies
authenticated-domain lifecycle coverage. The current protected Session capture
route permits one new public record per publication. Initial population, ordinary
additions, corrections, explicit forgetting and temporal supersession must be
counted under that actual route before attempting native endurance.

`StorageWorkload.native_operation_floor/3` requires an explicit cycle
interpretation and returns a lower bound. It retains 2,000 initial records,
20 ordinary additions, four ordinary corrections, two forgets and four temporal
supersessions per day, plus the existing doubled day-90 workload. It does not
infer pilot acceptance or count expiry, imports, compaction, recovery and control
management. It executes zero mutations and zero turns.

| Annual minimum | 10,000 mixed operations | 10,000 complete three-operation cycles |
| --- | ---: | ---: |
| Initial records | 2,000 | 2,000 |
| Ordinary additions | 7,320 | 7,320 |
| Ordinary corrections | 1,464 | 1,464 |
| Explicit forgets | 732 | 732 |
| Temporal supersessions | 1,464 | 1,464 |
| Additional churn effects | 10,000 | 30,000 |
| Lower-bound IDs | 22,980 | 42,980 |
| Excess over unchanged 32,768-ID limit | None established by this floor | At least 10,212 |

The complete-cycle interpretation is already impossible under the current ID
limit. The mixed interpretation is only not ruled out by this lower bound; it
is not a fit or acceptance proof. Pilot-derived rates may increase either
workload. Clarification of cycle semantics remains pending; no interpretation
is silently selected and no workload is frozen here. A solution must preserve
unknown liabilities and replay protection rather than resetting IDs or omitting
required operations.

## Actual checks

The pure test selection ran in a plain Elixir VM with the existing compiled
Ipse/Jason/telemetry paths and pure Notes source, without starting Ipse or any
native helper. It exited **0**: **three passed**, 0.2 seconds, seed `179715`.
The raw log is `/tmp/ipse-native-workload-budget-pure-20261102.log`. Tests
distinguish the interpretations, preserve initial/day-90 floors, reject missing
or unsupported semantics and retain false qualification/zero-execution fields.

The standalone `--native-operation-floor` CLI also exited **0**, emitting the
two rows at `/tmp/ipse-native-workload-budget-cli-20261102.jsonl`. It created no
Ipse Session or store. Both reports retain `qualification_passed: false`.
The original `--check` also exited **0**, preserving the 2,000-record seed,
maximum payloads, daily counts, 217 offline actions and delayed-history pure
checks. Strict isolated `elixirc --warnings-as-errors` compilation and changed-file
format validation passed; compiled outputs remained under `/tmp`.
The existing complete source suite at frozen `9f1707c` was running in its
independent checkout; this preflight and the separate late-clock draft are not
part of that source snapshot. No shared helper or compiled runtime was changed.

This closes only a development preflight gap. Actual protected multi-day turns,
initial capacity, concurrent owners, full lifecycle cycles, receipt/history/
suppression compaction, resource peaks and independent semantic qualification
remain open.
