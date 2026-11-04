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
For an invalid native decision response, the action reports `decision_response`
without retaining the invalid response body. An owned, registered service can
still have an unknown reservation, and its request completion remains partial;
the diagnostic is not proof of final usage or a reason to retry. On replay the
failed action's diagnostic code is not independently established by a retained
response body and never grants advice.

Run the protocol, configuration, accounting and actual loopback Session controls:

```sh
mix test test/ipse/decision_test.exs test/ipse/provider/decision_test.exs
mix test test/ipse/provider/decision_transport_test.exs test/ipse/config/decisions_test.exs
mix test test/ipse/usage/decision_test.exs test/ipse/extension/decision_call_test.exs
mix test test/ipse/extension/decision_session_test.exs
```

These fixtures verify admission and wire behavior, including hosted wire subsets
with synthetic keys. They establish no live account eligibility or consumer
quality. The pure consumer exercise below adds zero-call planning controls. A
separately reviewed, finite [local shadow grant](../operator/knowledge-permissions.md#try-a-local-shadow-assessment)
exists for the specific saved-note experiment; broader saved helper consent and
qualified automatic consumers remain separate implementation and acceptance work in the
[plan](../plan.md#p30-advisory-decision-engines).

To exercise a shared saved allowance, hold one admitted decision's provider
response while another OS process starts a distinct Session under the same
project, policy and epoch. That Session must obtain its own native approval.
Observe its exact reservation operation inside the locked allowance check:
the first admitted call consumes the one-call allowance before settlement,
the contender receives no reservation, and only the first request reaches the
decision provider. Check that every other resource dimension fits, so another
ceiling cannot explain the refusal. After releasing the response, require the
first operation to settle and both Sessions to reopen idle without replay.

The [native concurrency fixture](../archive/2026-10-26-p30-p31-implementation/p30-inflight-native-eof-20261103.md)
shows the necessary terminal coordination. After the first approval, normal EOF
closes its idle native prompt while accepted work finishes; wait for its input
entries to release before starting the contender's terminal. `/exit` cancels
accepted work and would test a different state. This sequence tests an allowance
already held in flight; simultaneous reservation entry needs a separate race
control.

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

## Exercise a consumer without contacting an engine

The separately built Knowledge artifact includes
[`Knowledge.DecisionPolicy`](../../extensions/knowledge/src/knowledge/decision_policy.ex).
It plans bounded request data and maps advice to permitted IDs. Capture does not
call it automatically, and no production strategy is qualified. Neither a
`qualification_sha256` value nor an `availability` label in supplied facts grants
authority. Facts remain untrusted until a future host adapter verifies their
actual producers, current eligibility and resource allocation.

Run this complete fixture in `iex -S mix`:

```elixir
Code.require_file("extensions/knowledge/src/knowledge/decision_policy.ex")
alias IpseKnowledge.Knowledge.DecisionPolicy, as: Policy
policy = Policy.default("notes.assess")
facts = %{
  "version" => 1,
  "availability" => "available",
  "budget_available" => true,
  "candidates" => [%{"id" => "candidate1", "input" => "Synthetic original candidate."}],
  "alternatives" => ["keep_baseline", "defer_candidate"]
}
{:ok, production} = Policy.plan(policy, facts)
nil = production.request
experiment = Map.merge(policy, %{"strategy" => "decision", "profile" => "fixture"})
{:ok, proposed} = Policy.plan(experiment, facts, :development_experiment)
:ok = Ipse.Extension.validate_decision_request(
  Map.take(proposed.request, ~w(version profile input questions)))
```

This only constructs data. Development mode is not an experiment grant or an
egress operation; even the profile name is unresolved here. Sending that request
still needs the ordinary host capability, actual operator profile, approval,
journal, service and budget gates. Production planning always returns a zero-call
path while the qualified catalogue is empty, including when JSON supplies a hash.

Selection plans accept at most sixteen candidates and eight packs, with at most
four records per decision pack. Version 1 accepts an allocation up to 6144 bytes
and complete concatenable rendered chunks, including labels, citations and
separators; callers deduct any shared frame before supplying that allocation.
Version 2 accepts the recall worker's complete measured projections and its
allocation up to 8192 bytes. The planner adds no framing. Pack member IDs are
normalized as sets, so permutations alone cannot manufacture multiple alternatives.
Assessment accepts at most eight
candidates. Profiles use the operator profile grammar: a letter followed by
letters, digits, underscores or hyphens, at most 64 bytes; this pure exercise
does not resolve or expand the operator's registry. Supplied facts prove no actual
allocation: a future trusted host adapter must derive the owner's grant and check
the complete rendered projection again. A complete eligible set fitting its actual allocation bypasses
advice and retains every supplied eligible record. Unknown or unavailable
eligibility, incomplete coverage, and a declared fitting set without all rows
return a null action with an explicit reason. A null action means no selection
was established; it is not evidence that the eligible set is empty. A nonempty
eligible set with no usable candidate pack also returns a null action, unless
zero allocation establishes an empty projection. Complete aggregate totals must
include at least one rendered byte for each omitted eligible record; inconsistent
totals are rejected, though consistent totals still do not prove eligibility.
Zero allocation, no candidates,
zero or one unique permitted alternative, and unavailable budgets produce no request. Pack byte counts use
actual UTF-8 rendered bytes. Selection excerpts are explicitly marked partial;
assessment input is never truncated.

All source facts must fit the unchanged 16-KiB SDK object bound. Constructed input
is at most 8192 bytes, its complete escaped request at most 16 KiB, and the timeout
is 30000 ms. A private `Plan` retains bounded facts for deterministic reconstruction;
its separate 32-KiB limit does not widen any public SDK envelope or grant a handle.
Overflow refuses or selects the labelled zero-call baseline before request work.

The mapper validates the whole neutral result first, then uses the public
`Extension.select_decision/5` adapter with probability at least 0.8 and margin at
least 0.2. The margin is redundant for a normalized selected probability of 0.8
(the other choices total at most 0.2), but remains an explicit policy check.
Native raw confidence stays independent. Refusal, ties, low probability and
malformed results return labelled baseline behavior. Assessment can only retain
the ordinary baseline or defer a proposed candidate for this batch; it cannot
change its text, origin, category, TTL, evidence or permission.

For selection evaluation, `dev/evaluation/decision_metrics.exs` compares
bounded aggregate counts using the frozen five-percentage-point supported-answer
or 20% total-cost benefit, nonregression and p95 latency thresholds. For candidate
assessment it compares false-durable reduction, useful and critical capture, and
latency. The supplied gate statuses cover protocol and matched workload, plus
selection quality, citation integrity, finite resources and paired critical-case
nonregression or assessment's finite cost cap; the functions do not verify
those declarations. `critical_pairs/3` uses the existing paired-metric input to
identify baseline successes lost on specific critical queries. Missing, failed
or unmeasured pairs leave that gate unverified, even when aggregate recall is
unchanged. Independently validate the supplied critical labels and verdicts.
Both comparisons report
baseline and candidate abstention counts separately with their denominator.
A missing measurement or gate produces an unverified disposition even if another measured
criterion failed. A `useful_candidate` is a calculation result, not qualification:
the experiment, independent review and host safety gates must still be established.
Exercise the thresholds with:

```sh
mix test test/dev/evaluation/decision_metrics_test.exs
mix test test/extensions/knowledge/decision_policy_test.exs test/ipse/decision_test.exs
```

The test also compiles the actual independent artifact against a minimal public
SDK closure, then exercises it in another VM without `Ipse.Session` or
`Ipse.Extension.Artifact` on the code path. `Extension` delegates neutral request,
result and choice validation to the existing `Ipse.Decision` implementation;
there is one validator. These pure delegates retain the neutral library bounds;
sending a host action additionally requires `Extension.validate/1` and the narrower
DecisionCall envelope checks. The planner applies both. The minimal closure is `lib/ipse/json.ex`,
`lib/ipse/decision.ex` and `lib/ipse/extension.ex` (which also defines
`ResultDocument` and `ResultPublication`), plus the existing Jason/JSONSchex/JSON
Pointer dependencies. This verifies pure packaging and policy behavior, not live
quality, protected decision-helper consent, managed recall or dispatch freshness.

The Knowledge recall worker's internal `recall_projection/4` measures an ordered
subset of its already-read rows using the same grouped note assertions, index,
coverage and context renderer as ordinary recall. It returns the complete items,
rendered byte count and whether the projection fits; more than eight items cannot
be measured as a valid context selection. The function is pure and carries no
authority: an experiment must obtain and revalidate current source eligibility,
derive the real allocation, and obtain its separate consent before using it. A
worker-supplied or reconstructed context is not proof of any of those conditions.
The recall test compares the projection with actual worker output and checks
invalid subsets and oversized projections. `recall_baseline_projection/3` uses
that same measurement to reproduce ordinary recall's ordered greedy selection:
it skips a note that does not fit and continues trying later notes. Ordinary
recall calls this function itself. This baseline can contain more than four
records, so a caller-supplied decision-pack baseline is not automatically the
engine-free baseline for an experiment. `recall_pack_projections/4` applies
the same measurement to up to eight named alternatives of at most four read
rows each. It refuses duplicate or unknown members and duplicate sets, and
returns each set in recall order. Its results are data for a future adapter;
it does not dispatch a decision or establish source freshness.

For a fully read and generation-checked worker set, `recall_decision_facts/7`
constructs version-2 planner data from those projections and returns a private
mapping from bounded decision IDs to note keys. Version 2 filters on each whole
pack's measured envelope, not the sum of note text lengths; a nil measurement
cannot establish that a pack fits. The adapter refuses incomplete read coverage
and bounded-SDK overflow. Its inputs and its result remain untrusted: a future
host integration must bind the selected IDs and allocation to current source
authority, remeasure before use, and separately authorize an experiment. It
does not itself send a request or make production advice selectable.

Version-2 facts also carry a digest of the supplied generation, index, record
identities, read-operation IDs and instance. `recall_decision_projection/5`
reconstructs those facts and their ID mapping, applies validated advice or its
labelled baseline, and remeasures the selected projection. Changes to the bound
data refuse. This is an internal consistency check over the supplied worker state;
it does not reacquire source locks or establish that the state is still current.
`recall_shadow_comparison/5` pairs that reconstructed result with the actual
greedy baseline and the ordinary publication derived from it. The latter is
the fallback regardless of the policy pack returned for malformed or refused
advice. It exposes a shadow projection only for selected advice;
malformed advice, refusal and other bypasses have no shadow selection even if
the policy mapper returned its separately configured fallback pack. A baseline
whose framing does not fit is not itself a publishable projection: ordinary
recall publishes an empty item list in that case. An empty selection removes
the publisher and therefore adds no context framing even at zero allocation.
This pure comparison is not
an experiment grant, a quality measurement or a production selection route.
`recall_shadow_failure/5` handles a separate closed host-outcome shape for
denial, unknown outcome, and the declared decision failure codes. It preserves
that class in the receipt and returns the same ordinary publication without a
shadow selection. Unknown does not imply that an admitted request had no effect
or permit a retry; host reservation and source checks still govern continuation.

## Extend the subset with a refusal control

For a change exercise, alter one score label in the OpenAI fixture. Decoding must
refuse. Restore it and replace one predicate answer with its exact named refusal;
that response must remain structurally valid. Then change the reported model and
verify refusal again. The [wire tests](../../test/ipse/provider/decision_test.exs)
demonstrate these controls, typed boolean refusal and preservation of distinct raw
confidence. They are synthetic protocol evidence, not live engine/model quality.

Use the [finite experiment protocol](../archive/2026-10-26-p30-p31-implementation/qualification.md#p30-finite-experiment-declaration)
before evaluating a consumer. Only qualified useful strategies become selectable;
the pure planner does not qualify or dispatch one. Consult the
[plan](../plan.md#p30-advisory-decision-engines) for integrated operation and
consumer delivery status rather than inferring consumer quality from an admitted
operation or structurally valid result.
