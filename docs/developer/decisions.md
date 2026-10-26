# Validate typed advisory decisions

Use `Ipse.Decision` to validate a bounded advisory request and its complete result
before a consumer considers advice. Use `Ipse.Provider.Decision` to translate the
selected native text subset. These modules perform no IO, choose no account and
grant no authority. Transport, saved permission, reservations and journal admission
must be supplied by the operation's host owner before dispatch.

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
consumer delivery status rather than inferring availability from these pure APIs.
