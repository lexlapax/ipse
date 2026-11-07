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
quality. The consumer exercises below distinguish protected worker integration
from pure planning controls. A
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

For simultaneous reservation entry, wait until both native-approved consumers
have committed their decision preflights and neither has reserved a call, then
release their reservation attempts together. Classify the loser from the actual
reservation result: native-control contention establishes no budget comparison.
Require any acquired winner to return validated advice and settle its actual
usage. Confirm both work owners have closed normally and released their native
input entries before reopening either Session idle. Reconstruct each final
history and verify that reopening repeats neither inference nor its effects.
A separate passing cohort cannot resolve an earlier unknown reservation or
establish the cause of its failure.

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

## Trace a protected shadow comparison

The bundled `decision-shadow` Knowledge preset exposes `select_shadow` alongside
single-record `assess`. The ordinary native preset exposes neither experiment
tool. Use the separately reviewed finite
[local experiment grant](../operator/knowledge-permissions.md#try-a-local-shadow-assessment)
and inspect the fresh Session's `/ext` schema before requesting a comparison.
The CLI admits the exact selection descriptor as `notes.select` with
`decision.create`; an artifact cannot acquire that permission by using a similar
tool name.

Follow `Knowledge.invoke/2` from `select_shadow` through its selection phases:

1. Read actual `context.available`, then the complete bounded note index. The
   experiment requires at most sixteen records and no remaining index page.
2. Read each record through the existing protected Collection path, retaining
   its identity, read operation and original-source dependencies. Refuse missing
   or changed records and recheck the index generation.
3. Reread the allocation. Measure all eligible rows and each proposed pack with
   the ordinary recall renderer, using the smaller of the host allocation and
   the existing 8192-byte recall ceiling.
4. Bypass the decision when the complete set fits. Otherwise inspect advisory
   saved-policy availability, then submit the bounded plan through ordinary
   approval, source checks and the shared atomic reservation.
5. Reread allocation before returning advice. Compare the advised projection
   with the complete ordinary greedy baseline, which can contain more than four
   records. Never substitute a four-record decision pack for that baseline.

The result reports `selection_shadow`, the baseline, an optional candidate and
the actual source/allocation binding. It changes no context or stored note.
Refused, malformed or low-probability advice leaves the ordinary comparator;
unknown work retains its liability. A changed allocation or unavailable source
withholds the result. Advisory accounting does not reserve capacity or replace
the host's current publication checks.

Read the actual result delivery when building an experiment record. A large
comparison can reach the model as a `saved.result` receipt rather than an inline
projection. Resolve its authenticated output through `Extension.ResultSource`,
check the recorded hash and byte count, and retain the invocation's current
output-release evidence. A receipt is not a selection result, and reading saved
bytes later does not reacquire authority over their original sources.

Exercise the worker independently of native transport:

```sh
mix test test/extensions/knowledge/selection_shadow_test.exs
```

These controls cover the actual worker state machine with constructed host
replies. They do not establish original-source authority, native approval,
installed behavior or decision quality. The integrated experiment must establish
those applicable boundaries separately.

## Exercise a consumer without contacting an engine

The separately built Knowledge artifact includes
[`Knowledge.DecisionPolicy`](../../extensions/knowledge/src/knowledge/decision_policy.ex).
It plans bounded request data and maps advice to permitted IDs. Capture does not
call it automatically, and no production strategy is qualified. Neither a
`qualification_sha256` value nor an `availability` label in supplied facts grants
authority. The protected worker above obtains its own current reads and actual
allocation; supplying the same fields to this pure library does not reproduce
those checks.

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
allocation: the caller must derive the owner's grant and check the complete
rendered projection again, as the protected worker does. A complete eligible set
fitting its actual allocation bypasses
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

### Evaluate the advice

For selection evaluation, `dev/evaluation/decision_metrics.exs` compares
bounded aggregate counts using the frozen five-percentage-point supported-answer
or 20% total-cost benefit, nonregression and p95 latency thresholds. For candidate
assessment it compares false-durable reduction, useful and critical capture, and
latency. The aggregate interface accepts independently defined labels; validate
their meaning and relationships for the study before supplying counts.

The supplied gate statuses cover protocol and matched workload, plus
selection quality, citation integrity, finite resources and paired critical-case
nonregression or assessment's finite cost cap; the functions do not verify
those declarations. `critical_pairs/3` uses the existing paired-metric input to
identify baseline successes lost on specific critical queries. Missing, failed
or unmeasured pairs leave that gate unverified, even when aggregate recall is
unchanged. Independently validate the supplied critical labels and verdicts. Both
comparisons report baseline and candidate abstention counts with their denominator.
Selection experiment reports also include a paired membership observation derived
from the frozen rows and reference sets. A case recalls its critical set only
when it contains every referenced member; the report lists known losses even
when another case's gain leaves aggregate recall unchanged. Missing, refused or
otherwise failed rows remain unverified. This observation does not independently
verify the labels, workload, reviewer or paired-critical hard gate, and it does
not change the experiment's unverified disposition.
A missing measurement or gate produces an unverified disposition even if another
measured criterion failed. A `useful_candidate` is a calculation result, not
qualification: the experiment, independent review and host safety gates must
still be established. Exercise the thresholds with:

```sh
mix test test/dev/evaluation/decision_metrics_test.exs
mix test test/extensions/knowledge/decision_policy_test.exs test/ipse/decision_test.exs
```

### Materialize a candidate assessment

Use `dev/evaluation/candidate_assessment.exs` for a frozen keep/defer study,
with pending proposals and observed-durable records kept in separate strata.
For this study, false and useful labels are disjoint and critical labels are a
subset of useful labels. The scorer validates those relationships before deriving
the aggregates; it cannot establish that labels are accurate or independent.
`declare/1` creates an OFF declaration; `verify_inputs/3` checks its input,
source-receipt and baseline blobs. Freeze candidate rows before opening labels.
Pending proposals are not durable outcomes and cannot demonstrate reduced
false-durable capture. The scorer's arithmetic never establishes source
authority, independent labels or a qualified strategy.

Its companion `CandidateAssessmentSession.prepare/5` checks the frozen blobs,
selected artifact and routes without starting an actor. New Session work requires
a version 2 declaration with the digest of the host's public `advice` decision
profile. The profile binds the configured endpoint, service, model, timeout
ceiling, pricing and disclosures; a request may use a shorter timeout, so the
declaration does not fix per-request timing. The dedicated owner rejects additional decision
profiles. Its main-route digest covers provider, model, endpoint, timeout,
upstream, reasoning effort, data collection, output token and response-size limits,
step and context limits, compaction settings, optional response schemas, and the
Ollama context setting and model pin. It does not establish a fully matched workload:
other configuration, inputs and actual work still need independent comparison.
Version 1 declarations remain readable and scoreable, but cannot start
a new Session case. The recorded action is checked against the frozen profile
and effective execution before a known result is projected. These checks do not
verify the declared source or runtime digests, nor do they bind the rubric before
dispatch. A separately enabled
`run/5` then validates the original capture, current policy and exact stored
candidate before using the ordinary Session/native-approval path. Loading either
module runs no actor, and `main/1` remains disabled. Advice extraction requires a new
settled operation and the exact current output release with confirmed cleanup;
materialize complete paged results rather than treating a receipt as advice.
`result_row/5` preserves denied, refused and cancelled statuses only when the
typed action, accounting and delivered result support them. Missing closure,
partial request/response failures and untyped outer errors remain unknown.
A complete assessment reports an exact `observed_cost_nanos` total only when
every row has a cost and their sum fits the JSON-safe integer range; otherwise
that total is null, not a clipped or understated cost.
A cancelled observation does not settle, refund or remove an unknown ledger
operation. Non-advice choices, whole-task latency and cost stay null; the added
advice phase's elapsed time is not a matched whole-task measurement. Exercise
these joins before enabling an actual case:

```sh
mix test test/dev/evaluation/candidate_assessment_test.exs test/dev/evaluation/candidate_assessment_session_test.exs
```

Exercise the complete materialization path separately with the opt-in synthetic
recipe. Build the normal bundles first, then reserve the native terminal/Input
lane; this control must not overlap another operator review:

```sh
MIX_ENV=test HEX_OFFLINE=1 ./dev/build.sh
IPSE_RUN_CANDIDATE_ASSESSMENT_PROTOCOL=1 IPSE_KEEP_SHADOW_FIXTURES=1 \
  MIX_ENV=test HEX_OFFLINE=1 mix test \
  test/extensions/knowledge/candidate_assessment_evaluation_session_test.exs \
  --max-cases 1 --trace
```

The recipe reuses the ordinary experiment CLI and main-tool capture fixture in
a fresh private cohort. Its first phase closes the source and freezes the actual
candidate, baseline, routes, policy and input commitments. The second phase uses
that same one-call grant and loopback endpoint through the real Session/native
approval owner. It writes and reopens the first-row commitment before invoking
the scorer. Scripted labels explicitly say `independent:false`, so the expected
scoring result is refusal, after the label loader actually runs. A known released
row and this refusal establish materialization and label-admission behavior;
they establish neither independent labels nor a beneficial or rejected strategy.
Seven synthetic main requests and one decision request span the two phases.
Matched whole-task latency and cost remain null. Private failure roots are
preserved for inspection; the keep flag also preserves a successful root.

### Freeze a selection study

For a frozen selection study, use
`dev/evaluation/selection_experiment.exs` with a version-2 declaration. Separate
reference labels from the semantic reviews of later answers: references identify
critical note members for each case, while reviews name prediction and citation
IDs that exist only after those answers have been produced. Commit the exact
reference bytes before either answer is generated, and retain that commitment
with the study's custody evidence. This reference-only format contains no
prediction IDs, verdicts or independence assertions. In `iex -S mix`, load the
development module and bind `case_id` and `critical_note_keys` to the case's
actual identifier and reviewed note-key list before running:

```elixir
Code.require_file("dev/evaluation/selection_experiment.exs")
alias Ipse.Development.Evaluation.SelectionExperiment
references = %{
  "version" => 2,
  "rows" => [%{"case_id" => case_id, "critical_members" => critical_note_keys}]
}
reference_bytes = Jason.encode!(references)
{:ok, label_commitment} = SelectionExperiment.commit_references(reference_bytes)
```

After the ordinary engine-free answer is projected and its complete baseline
blob frozen, put that earlier `label_commitment` in the declaration's version-2
spec. `declare/1` binds source, runtime, artifact, routes, policy, finite shared
limits, case inputs and baseline hashes before candidate collection. It creates
an OFF data record, not an execution grant. `verify_inputs/3` checks the committed
input and baseline bytes; `verify_references/3` checks the reference bytes and
exact declared case population before candidate work. Neither function dispatches
an actor or gives reference labels to a predictor.

Freeze the actual first candidate rows before preparing blinded review. With
`declaration_sha` and `load` referring to the verified declaration and its
hash-addressed blob loader, the next steps are:

```elixir
{:ok, first} = SelectionExperiment.freeze_rows(declaration, declaration_sha, rows)
first_sha = Ipse.JSON.digest([first])
{:ok, template} = SelectionExperiment.prepare_reviews(
  declaration, declaration_sha, first, first_sha, load)
```

Persist the first rows and their digest before supplying the template to reviewers.
It binds the declaration, full baseline blobs and first-row population. Its flat
`semantic` list names actual opaque prediction and citation IDs without exposing
baseline/candidate arm labels, routes or engine names. Version 2 requires distinct
SHA256 prediction IDs and SHA256 citation IDs, as produced by `ProtectedAnswer`.
Its initial verdicts are
`unmeasured`, with `independent:false` and an unassigned reviewer. A matching
binding is not proof of independence: retain genuine reviewer identity, blinding
and custody evidence separately. Supply the corresponding saved answers and
evidence under those IDs, withholding arm/engine mappings from reviewers;
the template alone is not a blinded answer packet. The predictor must not
manufacture that evidence.
Only then pass the returned review bytes to `score/7`:

```elixir
SelectionExperiment.score(declaration, declaration_sha, first, first_sha,
  fn -> {:ok, reference_bytes} end,
  fn -> {:ok, reviewed_bytes} end, load)
```

The scorer verifies exact baseline and first-row bytes and the committed
references before invoking the review loader. Changed populations, foreign IDs
and citation pairs refuse. The caller still owns chronological custody: hashes
cannot prove that labels were never exposed earlier or that a supplied review
was independent. Historical version-1 declarations and combined label/review
files retain their `score/6` entry point and input format. They are not silently
converted to the separate version-2 contract; new studies should use version 2.
Both report null for an arm's unmeasured critical recall instead of converting
the uncertainty to zero or a successful count.

The scorer retains full baseline membership separately from the candidate's
four-record ceiling. Missing, unknown and unavailable rows stay unmeasured. If
any critical case's prediction is not `ok`, including a refusal or failure,
its arm's aggregate `critical_recalled` count is null even when that row still
names selected members. A noncritical refusal does not erase a known critical
count. A null critical count prevents the whole aggregate threshold comparison;
it is neither zero nor a pass. Absent latency or cost remains null. A total
cost that exceeds the JSON-safe integer bound also remains null; it is not
clipped or treated as a lower cost. The supported-answer improvement and cost
reduction are alternative benefit tests: an unmeasured cost does not erase an
independently measured supported-answer improvement. A retrieval-only output
cannot count as a supported answer. Synthetic engine
replies produce no quality comparison. Even a calculated benefit leaves the
report's disposition `unverified` and qualification `none` until the separate
protocol, matched-workload, resource and independent review evidence is
established. Exercise these distinctions with:

```sh
mix test test/dev/selection_experiment_test.exs test/dev/evaluation/selection_critical_pairs_test.exs
```

When the study also compares answers, `dev/evaluation/protected_answer.exs`
projects the protected service's saved output into those existing study rows;
it is not another inference engine. Start with a complete, settled read prefix
and its exact Actions/ManagedReads observations. Freeze the original question,
eligible source membership and helper execution before generating the baseline
answer.
The helper execution includes the selected provider/model/endpoint and token
settings, with profile `extract` and a 3000-ms request deadline in this adapter.
Both arms must match that same execution; the separately declared decision-engine
route is not the answer route.
For an operator-configured comparison, the existing
[finite experiment review](../operator/knowledge-permissions.md#try-a-local-shadow-assessment)
can include an explicit helper profile. Its separately imported and trusted
`host.model` extension must already be selected in the base catalog. The CLI
reviews the additional route before deriving the final Activation/Registry
Knowledge identity; it does not give Knowledge model capability or add a helper
effect to a decision outer. Default review still selects only main and advice.
The decision-call allocation remains distinct from ordinary helper Usage and
service accounting. The generic model-call example demonstrates the public
effect contract, not the complete protected-answer adapter or its quality.
Match the prepared execution to `ModelCall.execution/2` from the actual saved
Session header as well as to the selected configuration.

Keep the eligible read set, ordinary baseline and candidate pack distinct.
A version-1 source receipt uses its complete read set as the baseline. A
version-2 receipt instead binds the actual ordinary recall job, its allocation,
initial index, every protected read, verification index and final publication.
The adapter checks their order, common generation, current output release and
confirmed cleanup, and validates the actual ordinary rendering from those
observations. For example, eight eligible reads can yield a six-note ordinary
baseline and a four-note candidate. Eight, six and four describe different
memberships; none can replace another in the receipt or dependency checks.
The journey's read extractor must distinguish the initial empty context clear
from the final nonempty publication rather than assuming a single publication.

Prepare the complete engine-free answer with `ProtectedAnswer.baseline_request/3`,
then let the ordinary owner perform its separately approved service call.
`baseline_project/7` joins its real current release, confirmed cleanup, completed
model action and exact response to the existing baseline-blob shape. Freeze that
actual blob before collecting candidate predictions. `prepare/8` later
reprojects the prior baseline and requires exact equality with the frozen blob;
a supplied favorable prediction is insufficient. It exposes `baseline_records`
separately from the selected pack. For version 2, `publication_request/2` keeps
the complete final published items, including their grouped text, index and
coverage envelopes, as untrusted v4 context. Measuring raw note-text lengths or
replacing those items with the candidate pack does not reproduce that baseline.
Request and citation validation support a baseline of up to sixteen records;
chosen packs and candidate study rows remain limited to four. Both use the
unchanged 8192-byte v4 context and complete SDK-envelope limits. A complete
baseline that does not fit refuses; never trim it to make a comparison possible.

For both answer arms, the materializer reconstructs the real pre-entry service
lineage and requires every original read-record v4 dependency, including records
outside the selected pack. It preserves additional root or selector dependencies.
For the eight-read example, all eight original dependencies remain required
even though ordinary recall publishes six notes and the candidate uses four.
The candidate also retains the complete actual baseline entry union.
The initial delivered WorkerInput and the model helper's admitted preflight must
bind that complete union and the exact request through the existing host
validators. Reconstruct the intermediate live service suffix chronologically
from its closed pre-service basis. Ordinary Saved reconstruction applies resume
recovery, intentionally clearing admissions and helper inputs; it cannot supply
the live state immediately before a helper preflight. Keep final full Saved
validation as a separate check. Copied bare context is insufficient. These
historical joins do not replace the live owner's source checks or grant a fresh
permission lease.

For the candidate answer, `project/9` checks the original question/pack, record
revisions and hashes, exact service arguments, full Saved reconstruction and
current recorded output release before extracting a prediction. Selector commands
can use complete paged results; the answer service uses the existing bounded
inline result contract and refuses oversized output. Its closed
answer-or-abstention schema joins every supplied citation to an exact selected
note-text key/revision and UTF-8 quote range/hash, plus a range in the answer.
Those are citations to attributed derived note text, not promoted original-source
quotations or proof of entailment. Separate claims citing one span retain separate
pair IDs. The live service still owns fresh source checks and native approval;
an offline projection grants no permission. Unknown or unavailable outcomes retain
absent predictions and null unobserved timing/cost.

Keep the complete answer in its saved result and commit the first prediction
rows before preparing the version-2 review envelope. Reference-only labels were
committed before either answer; later independent answer and claim/span reviews
bind the actual output IDs through `Metrics.semantic/2` and
`SelectionExperiment.score/7`. A valid
quote join establishes byte integrity, not support or reviewer independence.
Constructed protocol tests and synthetic replies cannot establish actual model
quality. The source adapters need their own focused checks and a genuine paired
Session journey before supplying actual experiment evidence. The
[packaged synthetic v2 lifecycle](../archive/2026-10-26-p30-p31-implementation/p30-paired-selection-v2-20261106.md)
exercises physical reference freeze before startup, the actual complete baseline
before selection, first-row persistence, a later unmeasured review loader and
exact report readback after idle. It retains the
[earlier packaged CLI/protected-output qualification](../archive/2026-11-05-packaged-paired-cli/index.md).
These synthetic controls supply neither independent labels nor scored model
quality. Keep the review template unmeasured until genuine independent review:

```sh
mix test test/dev/evaluation/protected_answer_test.exs test/dev/selection_experiment_test.exs
```

### Verify the policy artifact and recall projections

The decision-policy test also compiles the actual independent artifact against
a minimal public SDK closure, then exercises it in another VM without `Ipse.Session` or
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
returns each set in recall order. Its results are data for the worker adapter;
it does not dispatch a decision or establish source freshness.

For a fully read and generation-checked worker set, `recall_decision_facts/7`
constructs version-2 planner data from those projections and returns a private
mapping from bounded decision IDs to note keys. Version 2 filters on each whole
pack's measured envelope, not the sum of note text lengths; a nil measurement
cannot establish that a pack fits. The adapter refuses incomplete read coverage
and bounded-SDK overflow. Its inputs and its result alone establish no authority:
the protected worker binds the selected IDs and allocation to its actual reads,
remeasures before use, and requires a separately authorized experiment. The helper
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
