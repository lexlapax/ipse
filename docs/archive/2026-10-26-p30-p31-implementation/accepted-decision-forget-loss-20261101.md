# Accepted-decision forgetting after durable effect and native-owner loss

Dated **2026-11-01**. Author-controlled source evidence on base `6f8df15`,
with the test-only changes described here. Historical verification record;
[the plan](../../plan.md) owns milestone acceptance and
[testing](../../developer/testing.md) owns the repeatable procedure.
This extends [accepted-decision forgetting](accepted-decision-forget-20261101.md).
It is not an independent audit, installed qualification or passing full suite.

## Required observation and implementation

A reviewed forget can already have removed an accepted decision when its native
owner disappears. The caller must not report success, roll back the durable
effect, release its uncertain accounting liability or automatically repeat it.
Inspection must remain read-only.

The existing genuine capture/acceptance/recall journey now exercises a third
management case after cancellation and an unmodified successful forget. It uses
the second independently accepted decision and its public returned note key.
Capture is disabled and the original Session source is temporarily unavailable,
with restoration under its retained lock. Original Session journals must remain
byte-identical.

The isolated CLI child loads `accepted_decision_forget_loss.exs`. It compiles a
test-only Collection overlay adding a pause immediately after the existing
native durable root switch succeeds, before subsequent collection cleanup.
The original switch result is preserved. The watcher checks the exact Collection
path, target deletion request and actual incremented root generation, then kills
the OS PID from that live transaction controller's actual Port. It observes the
controller's terminal monitor event and closed Port before releasing the effect.
The native helper, runtime source files, permission rules and storage format are
unchanged. This is a controlled-host fault, not an unmodified runtime execution.

The genuine fixture then requires:

- CLI exit 1 with no successful forget confirmed; actual target absent.
- Immutable acceptance link unchanged; the previously removed peer stays absent.
- Domain-authenticated anchor retaining the native management capsule and exact
  removed key/value hash; reacceptance planning from that anchor refuses.
- Exactly one new management operation and exact accepted-decision intent.
- An unconfirmed management result and a still-publishing protected reservation.
- Two explicit inspections reporting those same statuses with `replayed: false`,
  unchanged journal bytes and unchanged complete protected control snapshot.
- Original Session journals unchanged after restoration.

## Terminal observations

All native/terminal cohorts ran serially, without another author build or PTY
cohort overlapping them. All commands completed with exit 0:

| Command scope | Result | Retained log |
| --- | --- | --- |
| `managed_v3_turnover_native_test.exs`, seed 791607, max-cases 1 | 1 passed, 25.9 s | `/tmp/ipse-turnover-native-baseline-20261101.log` |
| Supersession Session/native and history-use Session files, seed 791608, max-cases 1 | 15 passed, 220.9 s | `/tmp/ipse-lifecycle-current-baseline-20261101.log` |
| Explicit `genuine_pending_accepted_recall`, seed 791609, max-cases 1 | 1 passed, 7 excluded, 47.4 s | `/tmp/ipse-accepted-forget-loss-native-20261101.log` |

The first control retains actual native review times separately from explicitly
supplied synthetic future expiry. It does not establish elapsed annual turnover.
The lifecycle cohort includes correction, temporal replacement, cross-session
sources, pin/history, shared-evidence choice compaction, revocation, cancellation,
deadline and post-effect-loss controls. Those passes do not diagnose every old
full-suite failure or create a new whole-suite aggregate.

The final genuine root is
`/tmp/ipse-native-knowledge-session-0fa8e5f2bbea7c14cca5cb40fc74a9f2`.
Its `accepted-post_effect_loss.log` records overlay source SHA-256
`6d3ec3b1d2d9bb2188761006d6b866046543169a9a85fac424b56f90096bb792`
and the observed `knowledge_management_cleanup_unconfirmed` outcome, followed
by the passing control marker. Successful and cancellation logs remain separate.

Formatting, strict compilation, CI action policy and the credential-free demo
passed. The pure accepted-target and turnover-policy files passed **7 tests**
at seed 791610 in 0.1 s. Documentation checks passed **1,009 Markdown files and
8,383 local links with zero errors**. Pre-existing inaccessible private-ledger
directory warnings were retained; those directories were not inspected or changed.
The operator permission chapter's existing uncertainty/recovery instructions
remain accurate; the developer testing chapter now teaches the exact controlled
loss observation and runnable opt-in command.

The post-run inventory is `/tmp/ipse-accepted-loss-inventory-20261101.json`,
SHA-256 `8eb2d3093c610109e29c81e5f2e404a6a2efafb2b893fd657af7b5007b549c04`.
It records 19 source/helper/build/dependency inputs, nine command logs and
14 retained synthetic journals/child logs. It was generated after execution,
not frozen before launch. The helper remains unchanged from the preceding
accepted-forget implementation. No new complete build/package was required for
these test/document-only changes; the final whole-source candidate still needs
its complete build and suite.

No real model calls, downloads, new dependencies, package or external review were
used. Non-session accepted retention/expiry/replacement, sustainable compaction,
actual turnover, complete source-suite and installed/domain qualification remain
open. The last complete source aggregate remains **3,538 passed, 60 failed,
109 skipped, 112 excluded** at `e86b1b8`; these focused passes do not replace it.
