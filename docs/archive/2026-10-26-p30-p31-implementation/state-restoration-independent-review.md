# Scoped timed State integration review

Historical review, **2026-10-29**, of
[timed State restoration](state-restoration.md) against the original
[P26 expiry design](../2026-10-19-p26-remediation/expiry-write-design.md),
[restoration design](state-deadline-restoration-design.md) and
[backend review](state-native-owner-independent-review.md).
This additive record changes no runtime, test, gate or acceptance ledger.
The [plan](../../plan.md) owns milestone status; the
[State training](../../developer/extension-state.md) and
[Memory manual](../../operator/memory.md) describe current behavior.

## Disposition

The focused integrated State/Memory behaviors satisfy the original reviewed
publication-decision contract on the recorded available-host cohort. No new
effect authority or user expiry waiver is required for this restoration.
No additional concrete blocker was identified in the reviewed State delta.
The evidence includes required positive journeys and elapsed refusals, rather
than only retaining a disabled capability.

This is scoped acceptance of the restored decision behavior, not full runtime,
package/platform qualification or P30/P31 completion. The native clock decision
occurs after staging under the retained namespace lock; an admitted replacement
may physically finish later. This is the original P26 limit, not a strict
physical completion guarantee. All other primitive lifetimes and the parent's
concurrent Collection/document changes remain outside this review.

## What was inspected

The reviewer verified every entry in the
[restoration manifest](state-restoration/manifest.sha256) with `sha256sum -c`;
all matched. Actual runtime tests were not repeated. Passing owner controls,
their archived test bodies and retained failures were read together.
The final State source matches the tested snapshot exactly:
`7c94d9e23bd3d1a759faba7a6a05f2d4ff376414b0ffc3666cc59b2916ca7251`.

The tested Invocation snapshot is
`b54eb647a702ee9e169f921d3dbce2ccdc5c739cd7b7b191dce7405d5a3f0c24`.
At review time the working Invocation differed only by a separate managed
`collection.store` refusal added by the parent. That hunk is not covered by the
State test cohort. The reviewed working file hash was
`7604b9c06b797fe7488cc6413b09ee7ac414be60f89a230d8c373b228d6a07d7`.
The matching native/controller implementation and malformed-response repair
remain identified in the earlier backend evidence; no second native architecture
or legacy file-server fallback was introduced by restoration.

## Behavior and evidence

| Requirement | Actual inspected control | Assessment |
| --- | --- | --- |
| Timed State reaches the final owner | Public State and its private write backstop no longer reject all deadlines; Invocation removes only the unconditional timed-put branch. The exact approved request flows to `Transaction.state_commit` after native staging. [Contract](state-restoration/ipse-state-restoration-contract.log) and [State receipt cases](state-restoration/ipse-state-restoration-precedence2.log) pass their selected controls. | Live timed writes succeed. Elapsed failure retains actual checked time, unchanged generation/value-free old record and existing closed schema. Historical gate receipts remain interpretable. |
| CAS → elapsed → quota | The native-owner integration control constructs a revision-exhausted namespace, submits a stale deadline0 request, then matching deadline0, then matching live deadline. [Quota-precedence control](state-restoration/ipse-state-restoration-quota-precedence.log) passes. | The results are conflict, elapsed failure and quota failure, respectively, with unchanged state. Deadline0 stays valid. No schema or capacity expansion occurs. |
| Staging crossing expiry | An actual public State operation is held in the instrumented native owner after synced staging and before its final clock decision, then released after the request deadline. [Staged-expiry control](state-restoration/ipse-state-restoration-staged-expiry.log) passes. | Native `checked_at_ms >= deadline`, valid failed receipt and prior value preserved. The earlier raw after-decision control separately documents permissible later physical rename. |
| Live remember and active import | Archived Memory Session helper seeds the actual store, requests a greater source generation under `approval: :ask`, observes the real `extension:state.put` approval and approves before target expiry. The [initial absolute-path run](state-restoration/ipse-state-restoration-memory-absolute.log) passes both live cases. | Both operations return `stored`, advance revision and produce a replacement expiry beyond the original target. The request's deadline is the original target expiry, not the replacement's later expiry. |
| Delayed remember and active import | The same helper asserts the target is live when the write proposal is displayed, waits for its actual expiry, then calls `Session.approve`. [Delayed rerun](state-restoration/ipse-state-restoration-memory-delayed.log) passes both repaired fixture cases. | Both return `source_expired`; full State before/after is equal. A journaled `extension_action_result` has failed `write_deadline_elapsed`; subsequent recall is empty. These are actual approvals/worker/State/Session paths using synthetic inputs. |
| Fresh expired backup remains restorable | The broader fresh-inspection Session case builds an already-expired record, imports it into an absent target at revision0, then asks the fixture model to inspect it in a fresh Session. This is the third passed case in the initial absolute-path run. | Import returns `stored`; inspection is metadata-only and hidden text/title/provenance do not enter the model-facing tool result. Restoring expired bytes does not make them eligible recall or a live target for renewal. |
| Resume does not repeat refused work | Each delayed case closes the real Session after recall, reads the actual current journal immediately before resume, resumes idle, preserves its original byte prefix and compares action-intent counts to that pre-resume journal. It also rereads unchanged State. | The repaired assertion correctly includes the intervening recall action instead of comparing against an older snapshot. No new action or State renewal occurs on resume. Earlier assertion failures remain recorded. |
| Managed State remains separately denied | [Managed/ordinary Session controls](state-restoration/ipse-state-restoration-managed2.log) pass two selected cases. Ordinary timed and untimed requests each receive successful action receipts. Managed input first journals `managed_read_observed`, then attempts a timed put under headless `--yes`. | The managed attempt ends with error and no State action intent. Removing the generic deadline refusal did not remove current-source denial or confer saved knowledge authority. Saved reconstruction succeeds in both cases. |
| Unknown effects stay inspectable and unreplayed | The unchanged reviewed backend handles actual owner loss before/after rename and malformed native completion; a real completed replacement plus empty V reply returns unknown. State only returns known results after acknowledged native release. | Restoration preserves that handling and the existing operation-ID/no-replay architecture. This increment does not execute a new interrupted-timed-Session resume schedule or every sync/release failure; those broader boundaries are not newly claimed passed. |

## Whole-document manual review

The reviewer read the entire State contributor chapter and Memory operator chapter,
then checked their overlapping State-expiry guidance in recovery and Corpus.
The chapters retain their reader-oriented flow: generic State ownership and CAS
teach the mechanism; Memory configuration, commands, approval, collection and
backup procedures explain the user task. They keep built-in State Memory distinct
from protected knowledge Collections and do not grant Memory automatic capture.

The expiry explanations match the implementation: original target deadline,
separate approval, CAS precedence, final post-staging native decision, possible
later physical completion, known elapsed refusal versus unknown completion,
read-time exclusion, faithful expired backups and no automatic retry. The
developer chapter also preserves managed State/service denial and historical
receipt reconstruction. Both chapters disclose stopping older in-flight writers
before an upgrade and the limits of retained conversation/tool history.

Corpus's State-backed draft paragraph and recovery's generic State paragraph
describe the same decision contract without applying it to separately gated
Collection stages. Their Collection-status text is outside this State review
and must follow the parent's separate restoration decisions. The reviewed manual
hashes identify this checkpoint, not any subsequent concurrent edits:

| Manual | SHA-256 |
| --- | --- |
| `docs/developer/extension-state.md` | `13b19e732db388a6f0dfac0bc66de0e8c0795c83bf94e99e1095dda68059e588` |
| `docs/operator/memory.md` | `1a55dadd127ec2b226daef6cf0357f89327788bb96b9c4e1100b04fb567ac886` |
| `docs/operator/recovery.md` | `badae8ae8acd5e47113e14294b63107baa8cacfcc7601abc5e49f76d72e0819e` |
| `docs/operator/corpus.md` | `15827d1cfe39d84f1bd7f7aae36bd5c3cc1f4fb85d1c420281a566427b38d7ed` |

No new CLI examples were invented or executed by this review. The archive's
commands identify exact fixture/cohort selections and preserve their initial
launch/assertion failures. The initial fixture was reconstructed and explicitly
marked as such; its old line numbers are not attributed to the repaired copy.
Documentation link verification and final coherent baseline remain parent-owned.

## Remaining limits

Evidence is synthetic and available-host scoped. It verifies actual Session and
native storage paths, not live model semantics or a human terminal trial. It does
not qualify macOS, all filesystems, blocked-kernel IO cancellation, a live mixed
upgrade with older file-server writers, or every fault boundary. The earlier
unexplained cross-process fixture readiness failure remains retained; a separate
pinned two-VM pass does not erase it.

Broader source/native/package checks, final documentation navigation checks and
P30/P31's full required journeys remain open. This scoped restoration neither
weakens source retention/current-use requirements nor supplies acceptance for
Collection/document publication, saved Consent, Review, retention changes,
managed egress or display sinks.
