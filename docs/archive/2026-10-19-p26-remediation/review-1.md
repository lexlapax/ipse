# P26 external review, 2026-10-19

Historical external review of commit `10b9dd66d06ef28718b58530a7e5b01c7c50397a`.
The original body follows unchanged. See the [remediation record](index.md),
[current memory manual](../../operator/memory.md), and [plan](../../plan.md)
for later behavior and acceptance.

# P26 independent review at `10b9dd6`

Review date: 2026-10-19. Snapshot: `10b9dd66d06ef28718b58530a7e5b01c7c50397a`. The
request text was cut off after the snapshot hash, so this review uses that hash as
the snapshot and the P26 acceptance text in `docs/plan.md` as the requirement list.
The only commits in scope that change code are `108aa86` and `fb4627e`;
`fb4627e..10b9dd6` changes only documentation.

**Verdict:** P26 is not complete as an unqualified claim. The parts that protect
stored notes are sound and verified: scope isolation, logical storage bindings,
write approval, conflict detection on writes, and forget/suppression within one
store. But two acceptance items, TTL and derivative suppression, only hold on the
`recall` path. A model-callable tool still exposes text past both, and restoring
from export changes notes that were never forgotten (findings 1 and 2). There is
also one crash defect (finding 3). Reopen P26B narrowly for findings 1–3, or
record an explicit acceptance of them. A full redo isn't needed.

## 1. Findings, most severe first

### 1. Medium: expired notes and derivatives of forgotten notes stay readable by the model

- **Where:** `lib/ipse/extensions/memory.ex:320-321`. `inspect` is a model tool
  (`:73-77`) and returns the full record with no expiry or dependency check.
- **Trigger:** the model calls `inspect` on a source ID it knows, for example from
  an earlier recall.
- **Impact:** the full text of expired notes and of derivatives of forgotten notes
  can be read again with no approval. This lasts until someone runs `collect`. TTL
  and "suppress … derived recall" therefore protect only `recall`. The operator
  manual says only "Expiry excludes a note from recall", and an operator could
  reasonably read `retention_seconds` as a model-visibility limit.
- **Reproduction (probe P5):** remember `parent`, remember `child` derived from
  it, forget `parent`.
  - `recall` returns `[]`.
  - `inspect child` returns `"derived secret text"`.
  - On a note written already expired, `inspect` returns `"expired secret"`.
- **Fix:** for expired or blocked records, have `inspect` return inventory-style
  metadata without text, or make `inspect` a command only. Add a test for each
  case.

### 2. Medium: restoring from export changes notes that were never forgotten

- **Where:** `memory.ex:453-467` converts every blocked active record to
  suppression on export. `records.ex:120-121` makes imported suppression
  permanent.
- **Trigger:** a derivative declared before its parent exists, or any blocked
  derivative. Export the store, then restore it with the documented "complete
  current export".
- **Impact:** in the live store, writing the parent makes the child visible again,
  and the child can be updated (gen 2, no `derived_from`). In the restored store
  the child is permanently `source_suppressed`. The operator manual's export
  section never says export changes blocked notes into suppression; only the
  developer doc does.
- **Reproduction (probe P2):**

  | Store | Recall after writing parent | Child update |
  | --- | --- | --- |
  | Live | `["child","parent"]` | `stored` |
  | Restored | `["parent"]` | `source_suppressed` |

- **Fix:** export blocked actives unchanged, perhaps with a `blocked` annotation,
  and convert only records that are actually suppressed. At minimum, document the
  conversion in the operator manual and add a restore-fidelity test.

### 3. Low: `collect` on a source that was never written crashes the extension's helper process

- **Where:** `memory.ex:366`. `(previous && …) and …` evaluates `nil and …`.
- **Trigger:** `/ext …__collect {"source":"never-written","expected_revision":0}`,
  for example a typo.
- **Impact:** `BadBooleanError`. The helper's `rescue` → `System.halt(1)`
  (`bootstrap.ex:11-15`) stops it, so the extension exits. Only a read happened,
  so nothing is written. This is operator-command-only. What happens to the
  session afterwards was not exercised.
- **Reproduction (probe P1):** `{:raised, BadBooleanError, "expected a boolean on
  left-side of \"and\", got: nil"}`.
- **Fix:** use `previous != nil and …`, and add a regression test.

### 4. Low: a scope outside the binding's allowed scopes activates, then fails on every call, and the test claiming otherwise doesn't test it

- **Where:** `test/extensions_memory_session_test.exs:242`. The test is named
  "…or narrowed scope mismatch", but it only tests a missing binding.
- **Trigger:** `options.scope: "operator"` with a binding whose `scopes` is
  `["project"]`.
- **Impact:** activation succeeds (probe P4: `Registry.prepare` returns `:ok`).
  Every state call then fails with an opaque `extension_state_unavailable`.
- **Fix:** add the missing test and rename this one, or refuse the mismatch at
  activation. Document the failure in operator troubleshooting.

### Observation, not a defect

`forget` with `expected_revision: 0` on a source that was never written creates a
permanent suppression and uses one of the 256 record slots (probe P3). A typo'd
source ID can never be remembered afterwards. Worth one sentence in the operator
manual.

## 2. Requirements

| Requirement | Result | Evidence |
| --- | --- | --- |
| Off by default; core unchanged when off | Verified | Session test at :213 (disabled instance creates no store); full suite passes |
| Explicit session / project / operator scopes | Verified | Session tests at :191 and :315; binding test at :84 |
| Stable logical identity across code and configuration versions | Verified | Binding tests at :47 and :158 (legacy storage namespaces unchanged byte for byte), plus a code read of `State.namespace` |
| Projects cannot gain a binding | Verified | `Config.admitted?` and `Identity.valid?` require operator scope; binding test at :112 |
| Missing grant or binding refuses activation | Verified | Registry capability-ceiling check; session test at :242 (missing binding) |
| Binding scope ceiling | Partly verified | Enforced, but only when a call runs (finding 4) |
| Provenance and conflicts | Verified | Memory test at :60 (conflicting source versions, conflicting writes) |
| Retention / TTL | Failed outside recall | Recall and write-time limits verified; `inspect` exposes expired text (finding 1) |
| Writes bounded and separately approved | Verified | Session tests at :213 (full value shown in the approval prompt) and :284 (denial writes nothing) |
| Concurrent forget without resurrection | Verified within one store | Memory test at :110: write prepared before forget is rejected; re-remember and re-import refused. Cross-store safety depends on a complete export (documented limit) |
| Derivative deletion and export | Partly failed | Recall exclusion and collection verified; findings 1 and 2 |
| Approved migration and import | Verified, plus a crash | Memory test at :203; finding 3 |
| Cancellation; resumed recall unchanged | Verified | Session tests at :213 and :156 |
| Limits on history, journal, backup and erasure stated separately | Verified as documentation | Operator and developer manuals; not implemented, by design |
| No required store, embedding, remote service or silent promotion | Verified | Code read; no new dependency; session test at :191 |
| Quality and resources measured separately | Verified (reproduced) | Measurement script rerun: corpus hash `3f11a10a…` matches, `passed: true` |
| Linux/macOS hosted gates at `fb4627e` | Verified at job level only | `gh run view 39185644151`: head `fb4627e5…`, both jobs `success`. Logs and artifacts not inspected |
| Package, installed and macOS native checks | Unverified | Not run |

## 3. Commands run and results

All on Arch Linux, kernel 7.2.9, x86_64, Elixir 1.20.4 / OTP 29, cargo 1.99.0, in
a temporary detached worktree at `10b9dd6`. The worktree has been removed; the
main repository was not changed.

- **`./scripts/build.sh && mix format --check-formatted && mix compile --warnings-as-errors`:**
  passed. Formatting was checked with the 1.20.4 formatter only, not the 1.18
  floor.
- **Focused P26 tests (memory, memory session, state binding, state scan):** 19
  passed.
- **`mix test`:** 921 passed, 32 excluded, in 281 s. This matches the recorded
  953-test total.
- **`mix run scripts/measure-memory.exs`:** passed. recall@5 and exact-span
  precision were 1.0, 0 model calls, p50/p95 219,502/288,994 µs, observed VM
  77,945,656 bytes.
- **Probe tests P1–P5:** scratch tests written for this review, results quoted
  above. Deleted afterwards.
- **`gh run view 39185644151`:** success on Ubuntu and macOS-14 at `fb4627e`.
- **Doc check:** `scripts/check-docs.exs` doesn't exist at the snapshot. Running
  HEAD's checker against the snapshot docs found 132 files and 1,713 links, with
  no link or anchor errors. Its 151 errors all come from structure rules added in
  the later manual rewrite (`6096075`).

**Not run:** `./bin/ipse demo`, `./scripts/package.sh` and the installed-package
checks, macOS/native-sandbox tests, the Elixir 1.18 formatter, and the hosted
logs and artifacts. Findings 1–3 were not exercised end to end through a real
session; they are confirmed at the extension-handler and helper level.

## 4. Verdict

The architecture holds up. Notes stay out of core code, the host additions are
small and generic (bindings, byte-bounded scans, a read-step allowance that
doesn't extend write steps), and authority stays with the operator. Approval,
conflict checks on writes, and suppression are enforced correctly. The test
counts and hosted results match the record.

The completion claim goes further than the behavior on TTL and derivatives.
Findings 1 and 2 are technically consistent with how the docs are worded. But they
mean "retention" and "derivative suppression" only cover retrieval through
`recall`, and the export-based restore the manual recommends permanently
suppresses notes that were never forgotten. Fix findings 1–3, plus the test gap in
finding 4, or record them as accepted limits in the plan. After that, P26 can be
considered complete within its scope.
