# Distinguish stale helper input from completed-output withdrawal

Dated **2026-11-01**, author-run synthetic Linux verification based on `bee7049`.
This engineering record follows the failed
[complete module baseline](managed-collection-module-20261101.md). It is not
milestone acceptance. The [plan](../../plan.md) owns remaining work;
[export-input training](../../developer/session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
and [operator recovery](../../operator/extensions.md#recover-without-replaying-unknown-work)
own current behavior. The [receipt](stale-helper-boundary-20261101.json) retains
selected source/log hashes and exact terminal results.

## Original failures and paired observation

The original tests changed the actual Collection root at the selected helper's
preflight, then expected successful turn completion and two observed HTTP requests.
The generic helper case also expected a later main request carrying a withheld
result. Those expectations predated the managed Worker-input boundary.

A diagnostic five-case run, seed 791694, retained **3 passed, 2 failed, 162
excluded**, 16.5 seconds, exit 2. Both failures were the expected successful-turn
status versus actual error. A temporary probe retained strict Saved results,
actual HTTP observations, callback traces and journals under two private synthetic
roots named in the receipt. It changed no production source and was removed.

Both stale cases observed exactly one HTTP request, the initial main request,
but two metering admissions. The helper admission finished failed/partial without
an inference-dispatch intent. Its committed action reported `model_request_failed`
or `decision_request_failed`. The previous root-read input was delivered; the
next input, carrying the failed action and the same inherited dependency digest,
remained unknown. Saved marked lineage unavailable. These are distinct network,
action, transport and accounting facts.

The three unchanged positive controls passed: the current generic helper, current
selected decision helper, and completed-Worker output withdrawal followed by a
successful main-model continuation. The last case changes the root at the second
main preflight after the Worker has completed. Its next request contains only the
withdrawal notice; the original journaled result remains intact. That projection
cannot authorize another frame to an unfinished Worker whose inherited root is
stale. The documented input contract requires uncertainty after prepared delivery
fails; manufacturing a successful callback would bypass that boundary.

## Final assertions and recovery

The two stale cases now require an error turn and exactly one observed HTTP
request. They preserve the actual root change at the original preflight and
require the failed helper action to match its exact intent. Both metering
admissions remain, with completed/final main accounting and failed/partial helper
accounting. The only inference-dispatch intent must be the initial main phase.

The complete union from committed managed-read observations must be nonempty.
Both Worker inputs commit that same digest; the unknown input's payload must be
the exact resumed failed action. Saved must retain precisely that unknown input
and unavailable lineage. After confirmed close, the same Session resumes idle
with identical messages, trace and unknown input. Its journal preserves the
closed prefix and adds only the validated ownership marker. The listener stays
alive through recovery and confirmed close, requiring no further HTTP request;
no callback or effect is replayed. Cleanup releases the test hook and stops the
owned listener even on assertion failure.

The generic case was renamed from “a stale helper input refuses before helper
bytes and the later main request sees only withdrawn output” to “a stale helper
input refuses helper egress and leaves its continuation unknown.” The separate
completed-output continuation positive remains in the same selected cohort.
No production gate, source dependency, deadline, receipt or allowance changed.

## Verification and limits

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only helper_withdrawal_boundary --max-cases 1 --seed 791695
mix test test/ipse/extension/managed_collection_call_session_test.exs --only helper_withdrawal_boundary --only managed_decision_response_current --only managed_decision_response_change --only managed_decision_response_revoke --max-cases 1 --seed 791696
```

The first final run passed **5 cases**, 162 excluded, 17.4 seconds, exit 0.
The combined result and documentation/format checks are recorded in the receipt.
The combined selection additionally covers a current held decision response,
root change during inference and policy revocation during inference; those cases
retain their original response-release and successful-action refusal assertions.

Whole affected source, extension-operator and testing chapters were reviewed.
The existing input/recovery explanation now teaches these timing boundaries;
verification guidance pairs current, stale-input and completed-output controls.
Public API/account-dependent examples were reviewed against current implementation
but no live decision service was called. The focused command examples above ran.
No dependency, native helper, runtime or package changed, so no rebuild or complete
suite was repeated for this test/documentation increment.

The frozen module remains **130 passed, 22 failed, 15 skipped** at `098559f`;
the complete suite remains **3,653 passed, 54 failed, 116 skipped, 112 excluded**
at `f44b63c`. Focused passes do not subtract from either aggregate. Other module
failures, complete C0/capacity/lifecycle/quality/installed qualification, the final
adversarial audit and full P30/P31 delivery remain open. These automatic Linux
`7.2.11-arch1-1` tmpfs/loopback controls establish no human, live-model quality,
installed, non-Linux or confinement result. External call accounting is unchanged.
