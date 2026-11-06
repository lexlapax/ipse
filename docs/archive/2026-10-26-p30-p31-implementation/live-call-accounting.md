# Live-call accounting checkpoint — 2026-10-29

This reconciles recorded model-call consumption before further live work. It is
an accounting record, not permission for a new external action. The
[implementation record](index.md#authorization-and-external-evidence) retains
the original finite limits, and the [plan](../../plan.md) owns acceptance.

The [first pilot receipt](chatgpt-pilot.json) records 102 actual ChatGPT calls,
including its continuations. Four later private draft checks were reported in
[the projected-history record](draft-projected-history.md), and the subsequent
[handoff](handoff-20261027-enhance.md) records the combined total as 106 of 300.
The four-call count is reported by those historical records; this reconciliation
does not reconstruct their private transcripts or manufacture missing receipts.
The original pilot's statement that 198 calls remained belongs to its earlier
102-call checkpoint. The later recorded remaining allowance is 194 calls.

The new [candidate-audit implementation](pilot-candidate-audit.md) and all its
synthetic controls consumed zero live calls and downloaded no model. A read-only
configuration preflight confirmed the selected ChatGPT/gpt-6.1-sol route and no
active extensions. It read no credential contents into tool output and dispatched
no request. Its first metadata helper used the wrong receipt key and printed
zero for the old pilot count; the actual receipt's `calls` field is 102. This
helper error does not change recorded consumption.

A new nonpublishing pilot was prepared with at most 120 calls, private local
source/candidate audits, fixed exposed synthetic cases and no store effects.
Automatic approval review rejected its launch before process creation, citing
external prompt transmission and quota consumption without specific authorization
for that new run. No live request was sent; the expected run directory was absent
after rejection. No launch was retried or run indirectly before a specific approval
question was answered with explicit approval for up to 120 calls; independent
local implementation continues.

At rejection, recorded consumption remained **106 of 300**, with **194 remaining**.
That arithmetic did not override the rejection. After the user's explicit
approval, the exact prepared launch started once as exec session `84970`. It used
the configured ChatGPT/gpt-6.1-sol route, its fixed exposed synthetic cases,
private local audits and no store effects. Exec `84970` then ended with exit 0 after
request 96, but without the launcher's final result file or final outcome record.
The exact matching process was absent after exit. The retained files contain
96 completed response records, 57 audited turns and 39 proposals; the last response
is conversation 3/source 17. The cause of termination and exact attempted adapter count
are unknown. No restart, retry or continuation was attempted after observing it.

Charge the full 120-call reservation conservatively rather than refunding an
unknown in-flight request. The ledger therefore carries **226 of 300 conservatively
charged, 74 remaining**. This is not a claim that 120 requests actually occurred:
96 completed responses are proven and the exact attempt count is unavailable.
The zero exit code does not establish completion or model-quality acceptance.
Keep the raw audit/progress private; publish only a sanitized numerical receipt.
Any later request must account for this conservative charge and preserve the
original partial first outcome.

## First local primary-pair requests, 2026-10-31

The separately declared [adapter smoke](local-primary-smoke-20261031.md) made two
actual requests on the already acquired primary pair, with no retries or model
downloads. Charge2of1000local calls, leaving998. One embedding response had a
complete witness; the direct chat adapter response parsed successfully but its
witness stayed false because the harness bypassed the normal Provider wrapper.
Keep that first outcome and its scope limitation. These calls do not change the
ChatGPT226of300conservative charge or supply semantic/installed qualification.

## Native enhancement investigation, 2026-10-31

A separately prepared native CLI journey at `af5b70a` used a hard shared
four-request budget and synthetic workspace/input, on the explicitly selected
ChatGPT subscription/gpt-6.1-sol route. All four admissions have matching final
completed outcomes and the saved budget books four requests. Two file reads
failed with conflicting text/binary arguments; a shell attempt was denied by
the draft ceiling. The draft reached its three-step limit without context or
clarification. Native cancellation then preceded an unrelated request, which
returned the exact requested word. Saved reconstruction and cancellation
projection passed; the workspace was unchanged. This failed retrieve-first
journey is not quality acceptance and was not retried in its original Session.

Charge **4 additional calls: 230 of 300 conservatively charged, 70 remaining**.
The local-call ledger remains2of1000. The original private synthetic journal and
sanitized receipt are under `/tmp/ipse-enhance-live-20261031`; its journal SHA-256
is `2c18cee3b1b335582873e7456c8ea26b9237492cfd562ae1a782e8b6e725386f`.
No original authentication files or private production transcripts were copied.
The first configuration preflight omitted the configuration version and refused
before Session creation; the corrected preflight passed without model egress.

A distinct post-repair Session used the same exposed synthetic task with its own
hard four-request budget. One ordinary text read succeeded before the single
rollback question, and the native answer reached the main model. The third
request streamed a proposed draft but failed the existing64KiB response bound:
its journal outcome is failed/partial, no completed draft was admitted, and one
unknown budget liability remains. Native cancellation and the unrelated exact
answer passed afterward, with unchanged workspace and valid Saved reconstruction.
The original failed Session was not resumed or replayed.

Charge all **4 additional requests**, including the partial failure: **234 of300
conservatively charged,66remaining**. There is no refund or manual settlement of
the unknown liability. The second private synthetic journal and sanitized report
are under `/tmp/ipse-enhance-live-fixed-20261031`; journal SHA-256 is
`198edbb55dfbd5f4f929313987953fe7e060253231191fa678418fcd0cd2b7d6`.
The [provider repair record](responses-optional-tools-20261031.md) preserves both
outcomes. No further live request was attempted in this investigation.

## Complete native draft control, 2026-10-31

After the full suite and its isolated native follow-up exited, a newly prepared
Harbor case ran at `12652b2` with a matching rebuilt runtime. Its distinct native
CLI Session had a hard four-request budget, explicit ChatGPT subscription/
gpt-6.1-sol, synthetic input and no effect approval. Read, clarification and
final draft completed; cancellation preceded one unrelated exact answer.
All 4 admissions have completed/final outcomes, the budget books 4, and this new
Session has zero unsettled/unknown liabilities. No failed request was replayed.

Charge **4 additional calls: 238 of 300 conservatively charged, 62 remaining**.
The earlier partial liability and 120-call conservative reservation are unchanged;
no refund or manual settlement follows. Local usage stays 2 of 1,000, 998 remaining.
No downloads, service/model substitution or API billing occurred.
The [complete native control](enhance-complete-native-20261031.md) retains the
scope and sanitized receipt; its private synthetic journal SHA-256 is
`2d3b24970c1f126285a5d8919bf624ea3b2d706deeb87e9bf2ba445cd15198cb`.
Source/runtime/config/workspace match before and after. This is functional
development evidence, not independent quality or outgoing-wire proof.

## Pinned local Session jobs, 2026-10-31

The separately declared [two-job control](local-pinned-jobs-20261031.md) used
committed source `1d014f6`, a matching rebuilt runtime, the existing primary pair
and one registered service. The public embedding example reconstructed a complete
vector; the ordinary main Session returned its exact synthetic answer with effects
denied. Both jobs passed cooperative model/context checks, completed/final usage,
service settlement and Saved/idle-resume controls. Each had one booked request
and zero unsettled/unknown budget liabilities.

Charge **2 additional local calls: 4 of 1,000 charged, 996 remaining**. ChatGPT
stays **238 of 300 conservatively charged, 62 remaining**. No downloads, retries,
provider substitutions, manual settlements or refunds occurred. A harness artifact
path error stopped before Session creation or inference and was corrected through
a continuation preserving the original declaration/metadata. This is functional
source evidence, not independent quality, immutable weights or offline proof.

## Local pilot pre-reservation refusal, 2026-11-03

The [local-pilot refusal](pilot-local-refusal-20261103.md) followed a pinned
loopback inspection reporting zero inference calls. The launcher left empty
attempt, progress and candidate files, and its authorization directory was
absent on inspection. No reservation or inference is recorded. The account
directory's observed permissions explain the refusal under the tested code,
although the generic error did not identify its failing check. No account
permissions were changed and the pilot was not retried. Accounting remains
**4 of 1,000 local calls** and **238 of 300 conservatively charged ChatGPT calls**.

## Stopped Word comparison, 2026-11-06

The [partial Word comparison](word-semantic-03-failure-20261106.md) recorded one
admitted embedding attempt before stopping. Its journal has no inference dispatch
intent, so no embedding wire request is established; retain one conservative
charge nonetheless. Local liability is **5 of 1,000**, leaving **995** under the
existing allowance. Metadata requests are counted separately. ChatGPT remains
**238 of 300 conservatively charged**. No failed attempt was replayed or refunded.

## Supplied-Word comparison, 2026-11-06

The separately qualified [supplied-Word comparison](word-semantic-supplied-comparison-20261106.md)
completed 148 local embedding requests on the selected Qwen route, with no
automatic retry. Charge all 148 in addition to the five prior conservative
charges: **153 of 1,000 local calls**, leaving **847**. The separate metadata
HTTP ceiling was 1,788; it is not an inference-call count or an assertion that
all metadata calls occurred. ChatGPT remains **238 of 300 conservatively charged**.
