# Make an approved extension model call

`model.complete` runs one bounded text request through a named operator profile.
Use it for helper inference inside an invocation or prompt/answer job. Session
owns provider selection, exact egress approval, shared budgets, canonical usage,
and recovery. The extension supplies instruction/input and receives bounded text
plus normalized usage, without credentials or the main conversation.

Begin with `examples/model-calls/src/complete.ex`. Its command forwards a typed
request through `host_call`, then returns the committed outcome. It contains no
provider client or credential lookup. The corresponding loopback proof is a safe
place to learn this API without a paid request.

## Request and authority

Declare `host.actions` and `host.model` in the artifact and operator trust ceiling.
Return this outer protocol:

```json
{
  "api_version": 1, "kind": "host_call",
  "request": {
    "op": "model.complete", "version": 1, "profile": "extract",
    "instruction": "Extract names from the supplied text.",
    "input": "Public synthetic input",
    "max_output_bytes": 1024, "timeout_ms": 5000
  }
}
```

All seven request fields are required. Unknown fields or versions refuse.
Profile IDs start with an ASCII letter and contain at most 64 letters, digits,
underscores, or hyphens. Instruction allows at most 2,048 characters; input is
nonempty and at most 4,096 characters. The complete encoded request is at most
8 KiB, with additional SDK bounds. `max_output_bytes` is 1–8,192 and `timeout_ms`
1,000–120,000. Direct provider/model/endpoint/key overrides, tools, embeddings,
audio, and continuation are unavailable.

The model grant authorizes the supplied input's egress, not history, prompt,
answer, memory, or tool-view reads. Those sources need separate capabilities.
The host sends a fixed core-owned system instruction and a labelled user-role
JSON object containing approved `instruction` and `input`. Extension instructions
do not become system rules. Role separation neither sanitizes their meaning nor
grants effect authority to returned text.

Every call needs separate full egress approval unless session-wide `--yes`
authority is already selected. Headless denial never dispatches. Approval displays
the exact request and nonsecret execution facts: instance/artifact/session,
profile, provider/model/billing, configured endpoint digest, reasoning effort,
effective output ceiling, and deadline. A prior tool approval or question answer
cannot approve this request.

Closed destination facts disclose actual scheme/host/port as `origin` and bind
the full wire URL as `target_sha256`. The provider adapter supplies the same route
for disclosure and dispatch. Paths, userinfo, and query credentials are absent
from destination facts. Profile URLs reject userinfo, queries, fragments, and
invalid ports. Project profiles cannot choose endpoints or replace operator IDs.

## Profile and owned execution

Only named ChatGPT, OpenAI, Ollama, or Anthropic profiles perform inference.
Demo is not a model service. Missing credentials, service, or model fail without
fallback. The provider/billing mode never changes silently.

`ModelCall.prepare/2` narrows output against owner limits and shared reservation;
unsupported subscription output caps refuse. It narrows the operation/profile/
owner deadlines to at most 120 seconds. Each helper request consumes an owner
model step and ordinary action step. Extended read allowances do not enlarge
these limits. Independently bounded input fits below minimum configured context.

Host configuration supplies only the selected profile's public settings and
private budget/origin references. `Provider.Request` resolves the normal credential
reference inside the admitted provider task. The call inherits no main API key,
injected provider module, conversation, tools, SDK handles, or native continuation.
Reasoning settings follow provider-specific allowlists.

Children may use separately trusted helper profiles through host configuration
references, without receiving auth paths or arbitrary credential lookup authority
in SDK values. They retain their MCP and recursive-delegation restrictions.
Model-egress approval owns no filesystem mutation lease. Independent child helper
requests can overlap without releasing an enclosing extension tool's mutation
lease or weakening ordinary file/shell coordination.

The coordinator monitors the real worker and activation lease. Deadline, worker
death, expiry, or cancellation stops the linked provider task and closes its owned
HTTP profile. Delivered usage remains recorded. Remote work cannot be undone by
local cancellation. Text deltas do not enter the main visible stream; helper output
is not a main assistant/native continuation.

## Receipts, bounds and accounting

Before dispatch, Session records approved action, `extension_model_request`, and
canonical `request_admitted`. Request ID equals action operation ID; attempt ID
is fresh. Canonical kind is `extension`, with actual provider, billing, profile,
and original child/parent origin. Shared reservations, dispatch intent, usage
peaks, conservative settlement, and refusals follow main/summary accounting.
Attempted-request facts include refusals; budget bookings exclude them.

The accepted successful response body is at most 64 KiB. This bounds decoding,
not every HTTP buffer or process heap. Private `extension_model_response` retains
the original assistant/native data with exact IDs/digest, up to 256 KiB encoded.
The worker sees only bounded text and own-call normalized usage:

```json
{
  "version": 1,
  "request_id": "00000000000000000000000000000001",
  "attempt_id": "00000000000000000000000000000002",
  "profile": "extract", "reported_model": null, "text": "Ada",
  "usage": {"version": 1,
    "counts": {"input_tokens": null, "output_tokens": null, "total_tokens": null},
    "derived_fields": [], "quality": "unavailable", "issues": []}
}
```

Missing counters remain null under [usage semantics](usage-accounting.md#normalize-units-without-inventing-measurements).
The result is at most 12,000 encoded bytes before its continuation envelope and
contains no auth, hidden reasoning, or raw native fields. Returned tool calls,
invalid/oversized text, or unavailable bounded native receipts produce
`model_response`; nothing is silently truncated or executed. A rejected text
result can still represent completed metered inference.

Other closed failure codes are `model_limit` before admission,
`model_request_failed`, `model_timeout`, and `model_cancelled`. Transport failure
may consume resources; absent usage remains unknown. No retry, refund, or final
charge is inferred from an interrupted response.

## Recovery and verification

Metadata pins the nonsecret profile catalog and owner policy. Changed profiles
refuse before tail repair. Accounting checks helper admission against its approved
source; action validation also binds invocation session/turn. Successful cached
results must match retained response and canonical completion. Registered-child
reads validate these sources before using their facts.

Idle resume restores committed results without workers, model calls, or effects.
Interrupted dispatch retains unknown/partial work and shared liability. The helper
grant supplies no access to other requests; reports use their separate read grants.

Build and run the local HTTP proof after building Ipse:

```sh
elixir examples/model-calls/build.exs --sdk _build/dev/lib/ipse/ebin --output /tmp/ipse-model-artifact
mix run examples/model-calls/verify.exs /tmp/ipse-model-artifact
mix test test/extensions_model_call_test.exs test/extensions_model_jobs_test.exs
```

The proof checks actual loopback routing, complete approval, private response,
canonical usage, budgets, and unchanged idle-resume state. Tests add limits,
parallel children, cancellation, worker death, and corruption. Use the package
procedure in [the example README](../../examples/model-calls/README.md) for an
unchanged installed release. These are credential-free fixtures; actual billing
and model quality need separate live evaluation.
