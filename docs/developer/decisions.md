# Validate typed advisory decisions

Use `decision.create` for an explicitly approved advisory request. The owning
Session pins an operator profile, journals intent and request admission, and
dispatches bounded HTTP outside its GenServer. Advice grants no authority to
publish, run a tool or change a route. Begin with the complete
[operator procedure](../operator/extensions.md#request-typed-advice-explicitly),
then trace the host sequence below before extending a consumer.

## Trace a request through the Session

Build `examples/decision.ex` with the `decision-calls` recipe in
`dev/build-artifact.exs`. The separate artifact needs `invoke.command`,
`host.actions` and `host.decision`; its command returns a host-call continuation.
It cannot choose credentials or endpoints in its request:

```json
{"op":"decision.create","version":1,"profile":"advice","input":"The selected release requires a signed checklist.","questions":[{"id":"required","type":"predicate","instructions":"Does the input explicitly require a checklist?"}],"timeout_ms":30000}
```

`Extension.DecisionCall` validates the closed neutral request plus SDK bounds.
The neutral library allows 16-KiB input, but the host SDK limits any string to
8192 bytes and the complete escaped object to 16 KiB. An oversized request
refuses without truncation. Deadlines are 1000..120000 milliseconds, narrowed by
the selected profile and Session policy.

`Config.Decisions` resolves at most eight operator-only profiles, snapshots their
service/model/endpoint/subset/disclosure facts and derives one execution. These
profiles are independent of text roles and embedding profiles. The selected
expected model must match the response; OpenAI's admitted subset fixes both
requested and expected model to `gpt-6-luna`. Missing disclosures remain null.
`service_id` is an explicit operator identity, not proof of hosting or residency.

Session and `Session.Invocation` bind request, identity, profile and destination
before full-argument approval. Denial and an insufficient per-record journal
ceiling send zero requests. The conservative 65536-byte capacity check reserves
no aggregate journal space; later exhaustion can still interrupt publication.
The ordinary shared Budget gate runs before HTTP. Decision endpoints supply no
enforceable output-token cap, so a policy requiring one refuses without dispatch.
Unknown work retains liability and never retries automatically.

Follow this committed order through `Extension.Actions` and `Usage`:

```text
extension_action_intent → extension_decision_request → request_admitted
→ request_usage_observed → extension_decision_response → request_finished
→ extension_action_result
```

The optional usage observation appears only when counters are available.
`Provider.Decision.Transport` uses the existing owned HTTP client, a 65536-byte
response ceiling and duplicate-free bounded JSON parsing. It validates the whole
native response before normalized advice becomes an inline SDK value. It sends
only the approved input/questions. Parent history, main tools, credentials and
opaque continuation never enter the worker. Hosted OpenAI and System One resolve
their own fixed environment key inside the task; compatible System One requires
explicit loopback and sends no credential. There is no route substitution.

Usage metadata version 3 admits explicit `operation: "decision"` records while
preserving text version 1 and embedding version 2. Request/source/response,
normalized usage, completion and action result are cross-bound during replay.
Successful advice requires the durable validated response and completed metering.
Cancellation or owner death closes owned transport, leaves partial/unknown work
and publishes no advice. Idle resume validates saved facts without HTTP. A
delegated call needs its own parent-relayed approval, explicit child artifact grant
and shared parent reservation; child MCP and recursive delegation remain denied.

Run the protocol, configuration, accounting and actual loopback Session controls:

```sh
mix test test/ipse/decision_test.exs test/ipse/provider/decision_test.exs
mix test test/ipse/provider/decision_transport_test.exs test/ipse/config/decisions_test.exs
mix test test/ipse/usage/decision_test.exs test/ipse/extension/decision_call_test.exs
mix test test/ipse/extension/decision_session_test.exs
```

These fixtures verify admission and wire behavior, including hosted wire subsets
with synthetic keys. They establish no live account eligibility or consumer
quality. Saved knowledge consent, zero-call applicability and qualified automatic
consumers remain separate implementation/acceptance work in the
[plan](../plan.md#p30-advisory-decision-engines).

## Build one request and inspect its wire form

From a built checkout:

```sh
mix test test/ipse/decision_test.exs test/ipse/provider/decision_test.exs
```

The [request fixture](../../test/fixtures/decisions/request.json) contains a
predicate, a choice over stable string IDs and a score over ordered rubric labels.
Read it alongside the [wire adapter](../../lib/ipse/provider/decision.ex):

```elixir
request = Jason.decode!(File.read!("test/fixtures/decisions/request.json"))
:ok = Ipse.Decision.validate_request(request)
{:ok, body} = Ipse.Provider.Decision.encode(:openai, request, "gpt-6-luna")
IO.inspect(body["questions"])
```

Run that snippet in `iex -S mix`. It constructs data only. The bounded neutral
subset permits 1..32 questions, 2..16 string choices or rubric levels, 16-KiB input
and a 32-KiB complete request. IDs use a bounded ASCII identifier grammar. Unknown
fields, boolean choices, duplicate IDs and oversized/invalid UTF-8 input refuse.
Never coerce a native boolean into a string choice to make an answer fit.

The OpenAI subset uses named questions, a `predicate` probability, discrete choice
values and ordered score labels. It supports `gpt-6-luna` explicitly and requests
explicit caching without breakpoints, so this wire subset enables no cache reuse.
The System One subset maps predicates to `noul`, choices to named criteria and
scores to an ordered criteria list. Both selected wire subsets admit at most ten
score levels. A
request outside that subset refuses rather than dropping levels or switching
engines. Loopback-compatible System One uses the same wire subset; its endpoint
and actual engine identity remain separately selected facts.

The public wire contracts are described by the
[OpenAI Decisions reference](https://developers.openai.com/api/reference/resources/decisions/methods/create)
and [TypeSafe System One reference](https://docs.typesafe.ai/api/system-one).
Protocol compatibility does not establish self-hostable Jev or account eligibility.

## Validate the whole response before using any answer

`decode/4` requires the expected reported model, exact question identities/count,
correct types, complete unique option coverage and finite probabilities in [0,1].
Probability sums use an absolute tolerance of 0.000001. Score distributions must
reproduce the fractional probability-weighted score within that tolerance; native
score labels/legend must match the submitted rubric. Normalization retains every
probability and orders rows by submitted choices/levels for deterministic consumers.

Raw native confidence is preserved independently from the distribution. A model
may report confidence different from its selected option's probability. Neither
number is a calibrated consumer guarantee. Do not invent confidence from the
largest probability or infer truth from structural validity.

An OpenAI per-question refusal is a valid answer kind. Other independent answers
remain available, but any consumer depending on the refused predicate must defer.
System One's selected subset has no documented per-question refusal mapping;
unknown shapes refuse the complete response. Structural corruption in any answer
invalidates the whole result. A malformed result is never converted to a negative
answer or a zero-confidence success.

`select/5` accepts only choice advice that selects an already-permitted alternative
above the consumer's chosen probability threshold. It cannot establish that the
alternative is enabled, that evidence is current or that publication is authorized.
The caller must filter alternatives before egress, then revalidate evidence,
permission and resources at the ordinary effect boundary. Required prerequisite
questions must also be checked by that caller. No successful helper return runs
an action.

## Extend the subset with a refusal control

For a change exercise, alter one score label in the OpenAI fixture. Decoding must
refuse. Restore it and replace one predicate answer with its exact named refusal;
that response must remain structurally valid. Then change the reported model and
verify refusal again. The [wire tests](../../test/ipse/provider/decision_test.exs)
demonstrate these controls, typed boolean refusal and preservation of distinct raw
confidence. They are synthetic protocol evidence, not live engine/model quality.

Use the [finite experiment protocol](../archive/2026-10-26-p30-p31-implementation/qualification.md#p30-finite-experiment-declaration)
before evaluating a consumer. Only qualified useful strategies become selectable;
fit-in-context notes and absent candidates bypass decision calls. Consult the
[plan](../plan.md#p30-advisory-decision-engines) for integrated operation and
consumer delivery status rather than inferring consumer quality from an admitted
operation or structurally valid result.
