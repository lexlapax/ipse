# Accounted extension model calls

`host.model` adds one-shot text inference to the existing finite
[host-action protocol](extension-host-calls.md). It requires `host.actions` and
explicit operator trust. The worker chooses a configured profile ID and supplies
the complete instruction/input. Session owns approval, canonical admission and
recovery; an owned linked task performs credential lookup/provider IO through the
existing adapters and [shared budget](budgets.md). No domain-specific extraction
branch, model service, embedding backend or package dependency is added.

P23F implements this capability; its acceptance status and actual source/package/
platform results belong to the [plan](../plan.md#p23-usage-cost-reporting-and-budget-controls)
and [verification record](testing.md#current-evidence-and-next-checks).

## Request and authority

A tool, command, service or prompt/answer job may return:

```json
{
  "api_version": 1,
  "kind": "host_call",
  "request": {
    "op": "model.complete",
    "version": 1,
    "profile": "extract",
    "instruction": "Extract names from the supplied text.",
    "input": "Public synthetic input",
    "max_output_bytes": 1024,
    "timeout_ms": 5000
  }
}
```

All seven request fields are required; extra fields and unsupported versions/
operations refuse. Profile IDs use the existing profile syntax. Instruction and
input are bounded to 2,048 and 4,096 characters respectively, the input is nonempty,
and the complete encoded request is at most 8 KiB. The shared plain-JSON bounds
also apply. `max_output_bytes` is 1–8,192; `timeout_ms` is 1,000–120,000. No direct
provider/model/endpoint/key override, role fallback, tools, continuation, embedding
or audio request is accepted.

The capability grants explicit model egress for supplied input; it grants no
history, prompt, answer, tool-view or memory read. Those sources still require
their separate capabilities and scope checks. Workers receive neither the main
conversation nor credentials through this operation. Retrieved text remains
untrusted input. Model output grants no effect authority.

Every call requires mutation/egress approval unless the session already has
`--yes` authority; headless denial never dispatches. The full proposed object
contains instance/artifact/session identity, the complete request and nonsecret
execution facts: profile, provider/model/billing, configured endpoint digest,
effort, effective output ceiling and deadline. Approving the enclosing tool or
answering a question does not approve this call.

The approval also includes closed `destination` facts: `origin` is the actual
scheme/host/port and `target_sha256` binds the full wire URL. The provider adapter's
same `endpoint/1` route supplies both disclosure and dispatch, including defaults;
paths, userinfo and query credentials are not printed in destination facts.
Profile URLs themselves reject userinfo/queries/fragments and invalid ports.
Project profiles cannot select endpoints or replace operator-defined IDs. The
parent's model-egress approval classification validates this additional object;
ordinary opaque mutations keep their existing leases. Original execution facts
and their configured-root endpoint digest remain unchanged.

## Profile and owned execution

Only a named real ChatGPT/OpenAI/Ollama/Anthropic profile is supported. Demo is
not inference. The host validates the profile and narrows the provider output cap
against the owner's cap and shared output reservation; unsupported subscription
caps refuse. The deadline narrows the operation, profile and owner settings to at
most 120 seconds. A call consumes an owner model step as well as an ordinary
action-chain step; extended accounting-read allowances do not enlarge this limit.
One-shot input is independently bounded below the minimum configured context size.

The selected configuration contains the profile's public settings and host-owned
budget/origin references. It inherits no main API key, injected provider module,
conversation, tools, SDK worker handles or native continuation. The shared
`Provider.Request` resolves that provider's normal credential reference only inside
the admitted provider task. Missing credentials/service/model stop without fallback.
Reasoning settings retain the existing provider-specific allowlist.

Separately trusted child instances can use the host's private profile catalog and
protected auth-directory reference, even when their main profile is another
provider. These are host configuration references, never SDK payloads or arbitrary
credential lookups. Children still cannot delegate recursively or use MCP.

Model-egress approval owns no filesystem mutation lease. Parent approvals can
admit independent child inference concurrently and can approve a model request
inside an enclosing extension tool without releasing its mutation lease. Existing
file/shell/opaque-extension conflict claims and serialization remain in force.

The coordinator monitors the actual extension worker and checks its activation
lease while waiting. Deadline, worker death, lease expiry and owner cancellation
stop the linked provider task; its owned HTTP profile then closes. Already
delivered usage is retained. This does not undo remote inference or establish a
final charge. Provider text deltas are not forwarded into the main visible-text
stream, and helper output never becomes a main assistant/native continuation.

## Receipts, bounds and accounting

Before dispatch, Session journals the approved action, `extension_model_request`
and canonical `request_admitted`. The source binds operation/invocation/identity/
request digests, effective profile facts and the exact admission. Request ID equals
the action operation ID; attempt ID is fresh. Canonical kind is `extension`, with
the actual provider, billing and selected profile. Child requests keep their
original parent session/request origin. Shared budget reservation, dispatch intent,
usage peaks, conservative settlement and refusal apply exactly as for main/summary
work. Canonical attempted requests include refusals; budget bookings exclude them.

The provider response consumer accepts at most 64 KiB of successful response body.
This bounds accepted decoding, not every HTTP-library buffer or process heap.
The final private `extension_model_response` preserves the original assistant and
native provider data, with exact IDs/digest, up to 256 KiB encoded. The worker gets
only a complete bounded text result and normalized own-call usage:

```json
{
  "version": 1,
  "request_id": "00000000000000000000000000000001",
  "attempt_id": "00000000000000000000000000000002",
  "profile": "extract",
  "reported_model": null,
  "text": "entities",
  "usage": {"version": 1, "counts": {"input_tokens": null, "output_tokens": null, "total_tokens": null}, "derived_fields": [], "quality": "unavailable", "issues": []}
}
```

The [normalized usage object](usage-accounting.md#counter-semantics) keeps missing
measurements null. The SDK result is independently valid plain JSON
and at most 12,000 encoded bytes before the continuation envelope. No hidden
reasoning, auth or raw native fields enter it. A provider-returned tool call,
oversized/invalid text or unavailable bounded native receipt produces
`model_response`; nothing is silently truncated or executed. A completed provider
request remains metered even when its text is rejected. An oversized native
response is not accepted as a continuation and its content is not retained beyond
the bound; inspect the failed receipt rather than assuming a complete capture.

Other closed failures are `model_limit` before canonical admission,
`model_request_failed` for a failed/refused provider path, and `model_timeout` or
`model_cancelled` for a coordinator stop. A failed transport may have consumed
resources; absent usage stays unknown. Unconfirmed interruption has no successful
continuation. No automatic retry or refund is inferred.

## Recovery and verification

Metadata pins the nonsecret enabled profile catalog and effective owner policy.
Changed profiles refuse resume before tail repair. Accounting validates each
extension admission against its approved source rather than weakening main/
summary provider scope. Action validation additionally binds the invocation's
session/turn. Responses bind attempt, digest and reported model; successful cached
text/usage must match the retained response and canonical completion. Registered-
child accounting reads validate these action sources before trusting their facts.
Cached accounting-read recovery folds the complete canonical source/action stream
before checking each captured snapshot; skipping other action records would lose
the approved routing authority of earlier helper requests.

Idle resume restores committed results without model calls, worker startup or
effect replay. Interrupted dispatch remains unknown/partial, with shared liability
retained. Reports can read the same canonical facts through their existing grants;
this operation grants no access to other requests. Private response records are
not prompt/answer history views or diagnostic content.

`extensions_model_call_test.exs`, `extensions_invocation_test.exs` and
`extensions_model_jobs_test.exs` cover strict requests, private routing, full
approval/denial, actual parallel child HTTP requests, nested mutation leases,
overdraw, byte/time limits, cancellation/worker death, corruption and inert resume.
The [standalone artifact](../../examples/model-calls/README.md) runs the same
credential-free proof in source and an unchanged extracted package. Existing
reports/budget fixtures and the independent seven-artifact extension lab retain
their own compatibility gates. These are local fixtures, not paid-account or
production extraction-quality evidence.
