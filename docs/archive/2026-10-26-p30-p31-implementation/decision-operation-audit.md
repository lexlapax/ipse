# Admitted decision operation increment

Historical engineering record, **2026-10-26**, after `9da1ede` on
`codex/p30-p31`. The [plan](../../plan.md) owns delivery status;
[operator procedures](../../operator/extensions.md#request-typed-advice-explicitly)
and [developer training](../../developer/decisions.md) describe the operation.
This component audit does not close P30/P31 or qualify an automatic consumer.

## Implemented boundary

Operator-only decision profiles pin the exact provider, requested/expected model,
service identity, safe destination and nullable service disclosures. OpenAI,
hosted System One and explicit loopback-compatible System One retain separate
credential/billing choices. The owned bounded HTTP transport uses the shared
HTTP client and strict native subset; no main history, tools, credentials or
continuation enters the worker. No dependency was added.

`host.decision` requires `host.actions`, ordinary full-argument approval and
the shared budget gate. Session journals intent and request admission before
egress. Private request/response records, typed advice, canonical usage version 3,
completion and final action result cross-bind during replay. The existing
text/embedding coordinator now also owns decision cancellation/deadlines.
Decision prices require explicitly tagged version-3 rate-card rows. Unsupported
output-token reservations refuse without HTTP. Unknown work retains liability;
idle resume does not redispatch. Child decisions need separate parent-relayed
approval, an explicitly inherited artifact and the parent budget.

The public `decision-calls` builder recipe compiles `examples/decision.ex` as a
separately imported command. It is a concrete explicit-effect example, not a
default knowledge strategy or an account-access probe.

## Incremental independent review and controls

A separate agent reviewed the configuration, transport, DecisionCall,
Session/Invocation/Actions integration and Usage v3. It checked pre-dispatch
selection/destination binding, zero-egress denial and budget refusal,
source/response/completion/result cross-binding, cancellation liability and
resume pinning. It reported no additional actionable source defect in those
scopes. That review was static; it did not independently rerun the root's
owner-death/child controls and is not the final milestone audit.

Root-authored actual loopback tests cover approval before egress, hosted native
wire subsets with synthetic keys, credential absence from journals, compatible
no-auth wire, service/model/usage/result tampering, record-capacity and budget
refusal, malformed distributions, cancellation, timeout, owner death and idle
resume. A delegated job separately approves root and child decisions and verifies
the parent's five-request settlement and child v3 receipts. Eight concurrent
decision attempts against one remaining reservation dispatch exactly one HTTP
request and retain seven refusals.

Early dynamic failures were fixture errors: a demo main provider did not support
the requested output budget; a budget refusal correctly retained a failed canonical
admission; a child accounting-only stream excluded private response payloads;
and a direct BudgetStore fixture omitted its private session directory. The
assertions/prerequisites were corrected without weakening zero-egress, binding,
cleanup or shared-liability controls. Some concurrent component edits temporarily
prevented global compilation; those failed logs are not passing test evidence.

The standalone decision suite passed **9 tests** in 6.1 seconds after these
repairs. The preceding combined run passed **125/126**, with only the direct
BudgetStore prerequisite failure; its repaired combined run passed **126 tests**
in 51.9 seconds. The separate example/builder and
eight-case decision run passed **17 tests**. Strict compilation and the
documentation checker passed at their stated checkpoints. Raw private log names
use `/tmp/ipse-decision-session-`; failed logs are retained beside successful
ones rather than relabelled.

## Limits and next evidence

Paid account access, protocol compatibility against a live hosted engine,
measured prices, calibrated probabilities and useful consumer quality are
unverified. No live decision call was made. Saved semantic knowledge consent,
endpoint-wide service slots, applicability/bypass mappings and finite paired
consumer experiments remain separate required work. Full fixed-source,
Linux/macOS/package/installed evidence must name its actual revision; focused
tests do not supply it.
