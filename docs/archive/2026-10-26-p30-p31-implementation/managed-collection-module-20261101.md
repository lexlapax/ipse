# Frozen managed-collection module baseline

Dated **2026-11-01**, author-run synthetic Linux verification of clean commit
`098559f` on `codex/p30-p31`. This is a failed, complete module baseline, not
milestone acceptance or a replacement for the [complete frozen suite](full-suite-20261101.md).
The [plan](../../plan.md) owns current status and
[testing](../../developer/testing.md) teaches verification and recovery assertions.

## Terminal result and unchanged inputs

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --max-cases 1 --seed 791692
```

Terminal result: **130 passed, 22 failed, 15 skipped, zero excluded**, 1,266.6
seconds, exit 2. All 167 declared cases are accounted for: 152 ran and 15 skipped.
The parent log is `/tmp/ipse-managed-collection-module-20261101.log` and retains
all 26 native approval roots. Child results are not added to the parent aggregate.
Skipped cases establish no qualified behavior. Deliberate task/transport failure
logs are separate from the 22 actual parent failures listed below.

Before launch, the candidate recorded hashes for 7,855 tracked files, 632 test-build
BEAM/app files and the selected native helper. After the terminal result and
before any repair, all those bytes were rechecked: no source/build change, no
added build-code file, the same helper, the same Git commit and a clean tracked
worktree. The [receipt](managed-collection-module-20261101.json) binds both
inventories and the terminal log. Inventory scope excludes system Elixir/ERTS,
generated child artifacts and runtime memory; it is not a complete loaded-runtime
claim. The private untracked `.serenity-*` directories were neither copied nor
opened.

## Complete parent failure list

The parser admits one- or two-space parent headings so double-digit failures
are retained; nested child headings do not add failures. Earlier partial status
output used a two-space-only expression and undercounted headings after nine.
The terminal aggregate and the following complete list are authoritative.

| # | Test | Original location |
| --- | --- | --- |
| 1 | interrupted legacy extension question withholds arguments after revoke | `test/ipse/extension/managed_collection_call_session_test.exs:1660` |
| 2 | upgraded literal v4 A cannot be discarded while candidate cites independent current B | `test/ipse/extension/managed_collection_call_session_test.exs:2148` |
| 3 | managed shell owner loss after spawn stops the process group and resumes inertly | `test/ipse/extension/managed_collection_call_session_test.exs:4496` |
| 4 | a changed managed root prevents decision helper egress | `test/ipse/extension/managed_collection_call_session_test.exs:7318` |
| 5 | a read-only export enters headless planning but cannot publish or lend ordinary approval | `test/ipse/extension/managed_collection_call_session_test.exs:3840` |
| 6 | interrupted legacy extension question withholds arguments after expiry | `test/ipse/extension/managed_collection_call_session_test.exs:1660` |
| 7 | legacy journal origin cannot publish managed metadata V2 | `test/ipse/extension/managed_collection_call_session_test.exs:3757` |
| 8 | a known conflict is recorded and conservatively settled once without retry | `test/ipse/extension/managed_collection_call_session_test.exs:7798` |
| 9 | owner loss during protected publication retains liability and cannot publish after cleanup | `test/ipse/extension/managed_collection_call_session_test.exs:8179` |
| 10 | publication cannot discard an earlier stale managed A while citing current source B | `test/ipse/extension/managed_collection_call_session_test.exs:2263` |
| 11 | nested managed MCP discovery is admitted before approval and root_change is checked at effect entry | `test/ipse/extension/managed_collection_call_session_test.exs:2762` |
| 12 | a stale helper input refuses before helper bytes and the later main request sees only withdrawn output | `test/ipse/extension/managed_collection_call_session_test.exs:7480` |
| 13 | successive protected saves settle measured input and release only verified unused input | `test/ipse/extension/managed_collection_call_session_test.exs:7826` |
| 14 | headless protected capture journals exact outer and inner bindings and settles once | `test/ipse/extension/managed_collection_call_session_test.exs:3576` |
| 15 | V2 outer Identity loss after checked deferred publication retains full liability across inert resume | `test/ipse/extension/managed_collection_call_session_test.exs:8050` |
| 16 | nested managed MCP discovery is admitted before approval and current is checked at effect entry | `test/ipse/extension/managed_collection_call_session_test.exs:2762` |
| 17 | native loss after normalization does not refund or publish a successful managed result | `test/ipse/extension/managed_collection_call_session_test.exs:7908` |
| 18 | legacy saved-consent publication refuses a full pending queue | `test/ipse/extension/managed_collection_call_session_test.exs:3183` |
| 19 | protected managed publication applies its admitted deadline policy | `test/ipse/extension/managed_collection_call_session_test.exs:1559` |
| 20 | an unrelated caller cannot use the actual current collection action or stale job reference | `test/ipse/extension/managed_collection_call_session_test.exs:8209` |
| 21 | legacy journal origin cannot publish managed metadata V3 | `test/ipse/extension/managed_collection_call_session_test.exs:3757` |
| 22 | competing legacy saved-consent Sessions cannot both publish at 63 pending records | `test/ipse/extension/managed_collection_call_session_test.exs:3229` |

## Diagnosis and next work

The shell owner-loss control physically starts and stops its owned group and
preserves an absent final target, but its new assertion incorrectly requires
usable lineage after an unconfirmed effect. Read-only reconstruction of its
retained original root finds one version-3 dependency and no effect-cleanup
record; `ManagedLineage.dependencies/2` correctly refuses. The diagnostic script
and log are `/tmp/ipse-managed-module-shell-loss-diagnostic-20261101.exs` and
`/tmp/ipse-managed-module-shell-loss-diagnostic-20261101.log`. The subsequent
shared loss-lineage repair has separate evidence; it must not be subtracted
from this frozen aggregate.

Other failures include a missing external historical literal seed, legacy
question/tracking and origin fixtures, gated legacy publication, stale helper
continuation expectations and nested extension approval. Their exact tests and
requirements remain intact pending diagnosis. A refusal earlier in a test is
not evidence that its later intended boundary is qualified. Preserve allowed
controls, effect/accounting and recovery assertions while fixing these paths;
do not turn them into blanket refusal passes.

These are automatic Linux `7.2.11-arch1-1` tmpfs/PTY/loopback controls, without
human, real-model quality, installed, non-Linux or confinement acceptance.
Full C0/capacity/lifecycle, P30/P31 completion, final whole-source/package checks
and adversarial audit remain open. The earlier complete-suite aggregate remains
3,653 passed and 54 failed at `f44b63c`; neither this module nor later focused
passes establish a new passing complete suite.

## Current V3 accounting and publication-fault controls

Dated **2026-11-01**, subsequent author-run test-only work based on committed
`d641974`. The five original accounting/fault cases used a metadata-V2 worker
publication now deliberately gated before effect. They now use the supported
single-new-record V3 request while retaining their original positive/fault
requirements. No production, native-helper or dependency change was made.

The shared synthetic provider can select an explicit sequence of capture modes.
The conflict case first makes a genuine registered capture, then submits claimed
generation zero without reading the newer managed root. Its untrusted CAS input
reaches native conflict accounting rather than an earlier stale-observation
guard. It requires exactly one conflict, full conservative settlement, two total
operations, unchanged generation/floor one and four actual local HTTP requests.
The first publication remains a necessary positive.

Successive saves reconstruct the normalized commit from the V3 receipt's ordered
metadata changes, actual stored values and observed prior revisions. They verify
every metadata hash/revision, normalized request digest and exact measured input
formula. The fixed input budget is 40,000 bytes for V3's larger conservative
sidecar reservation: the test requires actual-first plus reserved-next to fit,
while two conservative reservations exceed that budget. Both saves must succeed
and settle with all other reserved resource dimensions unchanged. Four actual
registered requests complete. This preserves the original refund boundary
rather than merely increasing the budget until two worst cases fit.

Native-owner loss still physically closes the actual Collection port after
normalization/staging, requires an unknown result and retains the full pending
reservation with no selected generation. Foreign, stale-job and altered-action
callers still queue at the live Session and all receive `collection_source_refused`,
while the original authorized caller publishes successfully.

The original Session-loss hook blocked its second source query. V3 has a new
preparation proof before its normal admission, so that point has no publishing
liability yet. Its first migrated run retained an empty ledger and failed the
required publishing-row assertion. The hook now selects the third query inside
the admitted publication callback. The controller first requires durable
`publishing`, kills the Session, waits for the actual native lock guardian to
exit, and requires full unresolved liability plus generation/floor zero. Strict
Saved/idle recovery must preserve messages, the exact ownership suffix, worker
trace and the original operation without replay or settlement.

| Seed | Selection | Result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791715 | Five migrated accounting/fault controls | 4 passed, 1 failed, 181 excluded | 32.0 | 2 |
| 791716 | Final five plus paired origin and registered-capture regressions | 11 passed, 175 excluded | 30.3 | 0 |

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only publication_accounting --only publication_fault --only legacy_origin --only registered_capture --max-cases 1 --seed 791716
```

Selected post-run hashes, not a prelaunch or complete loaded-runtime inventory:

| File | SHA256 |
| --- | --- |
| `/tmp/ipse-publication-current-20261101.log` | `68e9b81ed91f660c58d889e6fc4948df2fb948af02ff2a8a836a998ecc71b666` |
| `/tmp/ipse-publication-current-final-20261101.log` | `c03e363e094400d512b3b055b817e86f57aea25866da8b7c08c79d149ec1e2b9` |
| Final Session test module | `0acda75f8e9d938e4380bc70d3b43a0a15a418f3efac47cb10346e424e67fee0` |

Each cohort finished before the next source edit. The first failure and both
terminal logs remain retained. The complete-module and complete-suite aggregates
above are not reduced by these focused results. These are synthetic source/local
HTTP/native controls, not installed, real-model, independent-human, non-Linux or
full-capacity acceptance. The whole Collection SDK and operator recovery manual
review from the preceding increment applies: their publication accounting,
authority, unknown-effect and no-replay explanations remain coherent. The testing
chapter now integrates the V3 source-check ordering and exact accounting exercise.
Full P30/P31 delivery and final audit remain open.
Final formatting and diff-whitespace checks exit zero. Documentation checking
reports 1,029 Markdown files, 8,525 local links and zero errors; existing private
directory discovery warnings remain separate. No runtime/build check was repeated
for this test/documentation-only increment.

## Current V3 binding follow-up

Dated **2026-11-01**, test/documentation work based on committed `94ff9c4`.
The original headless binding test used metadata V2 and the unregistered demo
continuation. It now performs successful supported V3 capture through the
registered synthetic adapter, preserving all original outer-policy, descriptor,
class, request/recipe, expiry, receipt and legacy-outer tamper controls. Its page
substitution uses an actual V3 anchor metadata entry and another valid V3 fence
instead of the obsolete V2 `anchor_key` field. A separate downgrade of the
effect's `metadata_version` also refuses. Outcome hashes are recomputed before
validation; each changed inner record must fail both result validation and Saved
reconstruction.

The unchanged positive requires successful normalization with `never_current`
eligibility, generation/floor one, one visible record, one settled operation,
two actual local HTTP requests, confirmed close and idle recovery with no
Worker replay. Action/result version 3 and its effect binding version 3 plus
`metadata_version: 3` are asserted independently. The SDK receipt table and
binding explanation were corrected during whole-chapter review to distinguish
these current fields from historical metadata-V2 effect binding version 2.
No production or authority behavior changed; current operator procedures and
the preceding whole recovery-manual review remain applicable.

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only publication_binding --only publication_accounting --max-cases 1 --seed 791717
```

Terminal result: **3 passed, 183 excluded**, 17.4 seconds, exit 0. Selected
post-run hashes, not a prelaunch/complete loaded-runtime inventory:

| File | SHA256 |
| --- | --- |
| `/tmp/ipse-publication-binding-v3-20261101.log` | `8c0836b15174ba29e349456d714c84505a4c9b049082a7629048f86d74895b89` |
| Final Session test module | `154f362740d74dd3b184cb768af956bafed7cbf8b77d772c93656103d466e1ee` |

The frozen failed complete-module/suite aggregates remain unchanged above.
This synthetic source control supplies no installed, external-model, independent
quality or full P30/P31 acceptance. No native helper, dependency or runtime
source changed and no external model call was added.
Final formatting and diff-whitespace checks exit zero. Documentation checking
reports 1,029 Markdown files, 8,526 local links and zero errors; existing private
directory discovery warnings remain separate.
