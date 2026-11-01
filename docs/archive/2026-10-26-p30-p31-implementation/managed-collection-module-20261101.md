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
