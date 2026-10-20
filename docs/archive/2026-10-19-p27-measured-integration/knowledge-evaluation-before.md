Historical reference only. Preserved on 2026-10-19 from
`2c2ffd7e01b6ac590937b2854543dc9537b2a67c:docs/developer/knowledge-evaluation.md`.
Relative links have been rebased; the original body and its status claims follow.
Use the [current contributor manual](../../developer/knowledge-evaluation.md).

# Measure knowledge results without exposing labels

Use this chapter to change the knowledge evaluation helpers and verify their
failure behavior. You need a built source checkout and the Elixir toolchain.
The exercises use synthetic data and local fixtures. The orchestration exercise
starts loopback search and model-protocol fixtures; it uses no model weights or
external service.
For changing the packages themselves, start with
[knowledge extension development](../../developer/knowledge-extensions.md).

## Follow the prediction and scoring boundary

The evaluation helpers have separate owners. Keep their inputs separate:

| Owner | Implementation | Input and result |
| --- | --- | --- |
| Plan | `examples/knowledge/evaluation_plan.exs` | Explicit artifacts, local profiles and seven budgets become the complete strategy matrix without opening inputs |
| Declaration and freeze | `examples/knowledge/evaluation_freeze.exs` | Source and artifact content become a portable experiment; local bindings and runtime become a separate execution seal |
| Dataset projection | `examples/knowledge/evaluation_input.exs` | Dataset bytes become separately validated corpus, label-free queries or scoring labels |
| Orchestration | `examples/knowledge/evaluation_runner.exs` | A validated variant plan becomes public Session calls, first predictions and retained execution failures |
| Owned model service | `examples/knowledge/evaluation_model_service.exs` | An explicit local runtime/cache selection becomes one private daemon lifetime and one guarded work callback |
| Session driver | `examples/knowledge/evaluation_session.exs` | Explicit artifact/profile/budget selections and public commands become durable invocation receipts |
| Answer preparation | `examples/knowledge/evaluation_answer.exs` | Saved ranked citations become a bounded request and an exact shown-span mapping |
| Independent review preparation | `examples/knowledge/evaluation_review.exs` | A complete hashed prediction grid becomes blinded cases, literal checks and an unmeasured semantic template |
| Scoring | `examples/knowledge/evaluation_score.exs`, `metrics.exs` | Hashed first predictions and independent labels/reviews become separate measurements |

The Session driver imports independent artifacts through ordinary host APIs.
It does not load the production knowledge modules into the host or call a
provider directly. Its caller supplies the approved configuration and validates
each complete proposed action. A selected profile is a route, not permission
to approve every request on that route.

Use the driver's `abort` verb only after inspecting a retained draft. Supply the
selected store, source ID, exact 32-character draft ID and current root revision.
It calls the public source-abort command with its ordinary State/MCP approval;
it neither invents a replacement draft nor retries inference. See the
[Graph recovery procedure](../../operator/graph.md#replace-suppress-and-recover-a-source).

Before running predictions, record the source/artifact identities, algorithms,
prompts, profile destinations, budgets, query order and time policy. Keep labels
and expected answers out of the driver, extension options and model inputs.
Finalize raw prediction files and their hashes before opening labels. A scorer
can enforce the order of its own callbacks, but cannot prove that another caller
has never opened those files.

## Declare the complete comparison

Build the seven independent artifacts into a fresh private directory. These
commands compile artifacts without importing them or contacting a model:

```sh
IPSE_BENCHMARK=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/lexical" --package corpus --preset state-lexical
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/dense" --package corpus --preset state-dense
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/semantic" --package corpus --preset state-semantic
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/explicit" --package graph --preset state-explicit
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/model" --package graph --preset state-model
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/research" --package research --preset mcp
elixir examples/model-calls/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/answer"
cp examples/knowledge/benchmark-spec.json "$IPSE_BENCHMARK/spec.json"
```

Review `spec.json` before generating a plan. It declares a fifty-query held-out
comparison with lexical, explicit graph, model graph, dense, hybrid, rerank and
Research variants. Every variant selects the same answer helper. Its example
local profiles name Qwen and embeddinggemma with exact expected inventory
digests; review the endpoint, installed model identities and budgets for your
authorized run. There is no provider fallback or model download. The declared
`corpus.json` and `heldout.json` are relative dataset member names. Confirm the
actual member names from independently supplied metadata before freezing;
generating a plan does not verify them or open the dataset manifest.

Generate the private version-one plan used by both identity exercises below:

```sh
mix run scripts/prepare-knowledge-evaluation.exs -- --spec "$IPSE_BENCHMARK/spec.json" --output "$IPSE_BENCHMARK/plan.json" --new-blind-seed
```

Expect `status: "ok"`, the output path, its SHA256 and `variants: 7`. The script
resolves artifact paths relative to the specification, validates every variant
and writes an owner-only file. It starts no artifact worker, dataset read or
model request. Existing output paths refuse. `--new-blind-seed` requires a null
seed in the input and creates a fresh value in the private plan; it does not
print that value or make inference deterministic. Keep the plan private when
preparing independent blind review.

The example budgets explicitly cap each variant at 1024 baseline requests or
8192 requests for inference-heavy preparation. Their token caps equal their
request cap times the declared reservation. These are finite admission limits,
not predicted consumption or cost. The runner divides request and token caps
equally among projects. The baseline caps cover fifty answers even for an uneven
project split; unused shares are not transferred or renewed. Review preparation
capacity separately. Each evaluation Session explicitly sets its inference-step
limit to that project's allocated request cap plus one. This lets the next request
reach canonical budget-refusal accounting; the budget still prevents dispatch.
Preflight reports the selected `inference_step_limit`. Embedding and text calls
consume the same step allowance. Ordinary Session defaults are unchanged.
Research requests up to ten sources within its body and time bounds. Knowledge
artifacts use SDK 2 for complete results up to the 4 MiB aggregate limit, subject
to journal capacity. A capacity refusal or unavailable complete result remains
a failed row; the runner does not reduce the source set to make that row succeed.

The explicit `storage_policy: "forget_all_then_collect_v1"` selects the final
storage exercise. After saving every query prediction for a project/variant,
the runner suppresses its isolated source copies and collects their unreferenced
pages. Review that policy before freezing. The original input corpus and saved
predictions remain available for scoring; these operations use the same Session
and do not renew its inference budget. Research has no retained source store.

Run the declaration exercises before changing this format:

```sh
mix test test/knowledge_evaluation_plan_test.exs test/knowledge_evaluation_runner_test.exs
```

The CLI control generates two independent seeds, checks permissions, refuses an
overwrite and verifies that nonexistent dataset/artifact paths stay unopened.
The public-Session matrix uses this same builder with scripted profiles. A
valid plan is preparation. The identity seal and executable preflight are
separate checks. The measured identity exercise below does not run preflight
or open held-out inputs.

## Seal identities before opening inputs

Choose the identity format for your task. A version-two experiment describes
the comparison through content identities and policy. Its execution seal binds
one local resolution. Version-one seals retain their existing fixture and
prediction behavior.

### Separate the experiment from its local execution

Use the complete plan and seven artifacts prepared above. Keep the source
checkout clean, including untracked files, and use fresh output paths. Declare
the portable experiment:

```sh
mix run scripts/evaluate-knowledge.exs -- --phase declare \
  --plan "$IPSE_BENCHMARK/plan.json" \
  --output "$IPSE_BENCHMARK/experiment.json" \
  > "$IPSE_BENCHMARK/declaration-receipt.json"
IPSE_EXPERIMENT_SHA256=$(elixir -e 'receipt = JSON.decode!(File.read!(hd(System.argv()))); IO.puts(receipt["result"]["sha256"])' "$IPSE_BENCHMARK/declaration-receipt.json")
cat "$IPSE_BENCHMARK/declaration-receipt.json"
```

Expect `status: "ok"`, the experiment path, its SHA256 and the source commit.
Retain the receipt and expected hash separately from the experiment bytes.
`EvaluationFreeze.declare/3` records the clean commit, tree, tracked file hashes
and inert artifact digests. It removes source/artifact paths, profile origins
and the search port from the portable declaration. Model identities, prompts,
budgets and dataset member identities remain part of the experiment. The
declaration contains its private blind seed; keep it away from the independent
reviewer.

The declared policy selects `linux_memcg_charged_peak_bytes_v1`, CPU-only model
execution, fresh private cache inodes per cell and exactly two projects. The
optional backend is `linux_cgroup_v2_v1`. Hostnames, architecture descriptions
and tool versions do not become portable admission requirements. The kernel
quantity is workload-charged RAM, including cache and kernel charges. It does
not describe summed process RSS or device memory.

Resolve the same experiment on the machine where you intend to run it. Write
this closed four-field object, using absolute artifact and report paths:

```sh
cat > "$IPSE_BENCHMARK/resolution.json" <<EOF
{
  "artifacts": {
    "answer": "$IPSE_BENCHMARK/artifacts/answer",
    "dense": "$IPSE_BENCHMARK/artifacts/dense",
    "explicit": "$IPSE_BENCHMARK/artifacts/explicit",
    "lexical": "$IPSE_BENCHMARK/artifacts/lexical",
    "model": "$IPSE_BENCHMARK/artifacts/model",
    "research": "$IPSE_BENCHMARK/artifacts/research",
    "semantic": "$IPSE_BENCHMARK/artifacts/semantic"
  },
  "model_origin": "http://127.0.0.1:47631",
  "search_port": 47632,
  "reports": "$IPSE_BENCHMARK/reports"
}
EOF
chmod 600 "$IPSE_BENCHMARK/resolution.json"
mix run scripts/evaluate-knowledge.exs -- --phase freeze-measured \
  --experiment "$IPSE_BENCHMARK/experiment.json" \
  --experiment-sha256 "$IPSE_EXPERIMENT_SHA256" \
  --resolution "$IPSE_BENCHMARK/resolution.json" \
  --output "$IPSE_BENCHMARK/frozen-measured"
```

The artifact aliases must exactly match the declaration, and every imported
artifact must retain its declared digest. `model_origin` accepts only literal
`http://127.0.0.1:PORT`; the shared service port 11434 is forbidden. The search
port must differ from the model port. Choose both ports deliberately before
sealing. This identity operation neither starts listeners nor proves port
availability or service ownership.

`reports` must name a fresh path disjoint from the freeze directory. It cannot
contain the source checkout. The freezer resolves canonical paths before sealing
and rejects overlap or an existing report directory. An ignored report directory
inside the checkout is allowed if it stays separate from the freeze. The freezer
creates a fixed owner-only
`frozen-measured/attempts` registry, separate from disposable reports. The
registry is currently an identity boundary; creation does not claim an attempt
or authorize execution. A future measured entry must claim it before effects.

Expect a new manifest path, its SHA256 and the source commit. The version-two
manifest binds a fresh execution ID, exact experiment and resolved-plan bytes,
copied artifacts, canonical local paths, runtime identities and semantic launch
recipe. Its provenance records the observed OS, architecture, Elixir and OTP.
Keep the returned manifest hash separately and keep source/runtime bytes fixed
within this execution. Resolving the portable experiment elsewhere creates a
new local seal; it does not make an existing execution relocatable or renewable.

Follow `resolve_plan/2`, `create_v2/4` and `verify/2` in `EvaluationFreeze`.
Resolution constructs every text and embedding profile with the selected origin
before sealing. Verification checks those exact resolved bytes rather than
editing a frozen profile. The recipe has its own digest and contains no digest
of the final manifest or future native bootstrap, avoiding a circular identity.

These two CLI phases read public plans, source/runtime files and inert
artifacts. They do no dataset, provider, worker or model work and claim no
measured resource result. The existing `predict`, `verify-frozen`, `review` and
`score` paths reject a version-two seal with `measured_entry_required` before
dataset access. Complete measured lifecycle integration remains required.

Trace `EvaluationRunner.schedule/2` after resolving the plan. This pure function
accepts projected query identities, requires two projects and derives fourteen
cells in sorted-project and declared-variant order. Each cell retains the
original project count and its fixed share of the original variant budget.
Version two divides every request, token and monetary limit by that count,
rounding down. Per-request reservations and the rate card stay unchanged. A
share below its reservation refuses admission; unused amounts cannot move to
another cell. Version one divides request and token caps only; any optional
monetary cap applies independently to each project.
Research gets each project's query count times `1 + max_sources`; shares cannot
transfer or renew. The function reads no inputs or services and starts no cell.
Measured preparation must eventually supply those validated query identities.

Run the identity and real-CLI exercises before changing these boundaries:

```sh
mix test test/knowledge_evaluation_freeze_test.exs test/knowledge_evaluation_declaration_cli_test.exs test/knowledge_evaluation_schedule_test.exs
```

The CLI fixture preserves portable bytes, checks local profile resolution and
private files, rejects a changed experiment hash and refuses prediction before
opening its nonexistent dataset. It proves identity handling, not a complete
comparison or the fourteen-cell execution.

### Exercise the version-one identity contract

Build Ipse and one independent lexical Corpus artifact first. Use fresh output
paths and a clean source checkout, including untracked files:

```sh
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output /tmp/ipse-evaluation-corpus --package corpus --preset state-lexical
mix run -r examples/knowledge/evaluation_freeze.exs -e '
alias IpseKnowledgeExample.EvaluationFreeze, as: Freeze
plan = JSON.encode!(%{"version" => 1, "purpose" => "identity exercise"})
{:ok, seal} = Freeze.create(File.cwd!(), plan,
  %{"corpus" => "/tmp/ipse-evaluation-corpus"}, "/tmp/ipse-evaluation-seal")
IO.puts(JSON.encode!(seal))
{:ok, verified} = Freeze.verify(seal["path"], seal["sha256"])
IO.puts(JSON.encode!(%{"artifacts" => Map.keys(verified["artifact_paths"])}))
'
```

Expect the manifest path, its SHA256 and the source commit, followed by the
`corpus` artifact name. The exercise starts no worker or model and reads no
dataset. `create/4` copies declared artifacts through `Ipse.Extensions.Store`.
An edit to the original build cannot change that copy. The manifest binds all
tracked source files, the Git commit/tree, code-path BEAM files, native helpers,
toolchain identity and exact plan bytes.
Run creation and verification in the declared development runtime with Git
available. A source-runtime seal does not attest a different installed runtime;
installed protocol verification retains its separate archive/host identities.

Retain the printed manifest hash separately. `verify/2` requires that expected
hash, then rechecks the clean source identity, runtime, plan and copied artifacts.
Keep source and runtime files fixed through execution. Existing output directories
refuse; failed creation preserves its partial directory for inspection. Imports
remain inert. The execution caller must validate the benchmark plan and each
egress/State/MCP decision before starting work; an identity seal grants no effects.
The small exercise plan above is not a complete comparison declaration.

Run the synthetic tampering controls before changing the seal format:

```sh
mix test test/knowledge_evaluation_freeze_test.exs
```

They distinguish changed plan bytes, a changed manifest, copied-artifact tampering,
dirty source, a different clean commit and a new code-path file. The valid control
also verifies that a dataset path in a plan is never opened during sealing.

## Check every selection before opening the dataset

The version-one runner's `freeze` phase adds executable preflight after the
identity seal.
Follow `preflight!/3`, `selection/4` and `EvaluationSession.preflight/1`. Tuning,
fixture execution and frozen prediction also perform this check before opening
any dataset member, including its manifest. The direct `EvaluationFreeze.create/4`
exercise above remains an inert identity operation.
Frozen phases recheck the source, runtime, plan and copied-artifact seal after
preflight. Successful worker checks cannot authorize execution against identities
that changed during initialization.

Preflight imports the declared artifacts, resolves their exact operator options,
checks their schemas and derives every command catalog. Required verbs depend on
the preparation strategy. Embedding needs `index`, graph preparation needs
`extract`, and answer generation needs `answer`, alongside each strategy's
retrieval and source commands. An existing command with the wrong ID or owner
cannot satisfy a binding merely because its argument shape looks usable.

The check then starts an owned worker for each selection and initializes it.
Knowledge entrypoints can initialize into an invalid-configuration state, so
readiness alone cannot establish valid profiles. Preflight sends an empty
`invoke.command` diagnostic directly to that worker. A valid configuration must
return `invalid_invocation`; a deferred profile error fails the check. This is
a protocol diagnostic, not an admitted user command. No returned host action
is executed, and no inference request is dispatched. The answer helper has no
knowledge profile registry and uses its ordinary schema and initialization
checks instead.

Every worker requires a confirmed native cleanup receipt. The report records
artifact, option and export hashes, the catalogs and each initialization outcome.
After all selections pass, model inventory must match the declared profiles.
`preflight.json` retains success or the first failed variant. Failed preflight
opens no corpus or queries and starts no search gateway. Its partial directory
and any existing identity seal remain available for diagnosis. A seal file's
existence does not establish successful executable preflight.

Run the complete synthetic exercise:

```sh
mix test test/knowledge_evaluation_runner_test.exs
```

Inspect the two negative declarations in the preflight test. One changes the last
Research command binding, after earlier variants have passed. The other adds an
unused invalid retrieval profile. Both must fail while their corpus and query
paths still name nonexistent files. Confirm that the latter worker reports
initialized readiness, failed option validation and confirmed cleanup.

The CLI exercises run the actual script with compiled dependency paths. They
verify successful and failed prediction rows, copied-artifact freezing, frozen
fixture execution, mode refusal and hash rejection before label access. Failed
rows or incomplete execution produce both exit status 1 and `status: "failed"`.
Read `failed_rows` and `execution_complete` separately. A completed execution
with refused retrieval still retains its failed prediction rows.

## Project query inputs without labels

After a version-one execution freeze and preflight pass, its input adapter may
open the declared dataset members. `EvaluationInput.queries/2` accepts the version-one
query JSON bytes and the declared split. Its `queries` result contains exactly
`query_id`, `project` and `query`, preserving their input order. Relevance,
expected classes, expected answers and refusal labels remain excluded. The
separate `excluded_fields` list reports field names; keep it in run metadata,
outside Session/model inputs.

`EvaluationInput.corpus/1` checks each complete source's identity, generation,
version, byte length, SHA256, UTF8 text and timestamps. It retains all source
generations and state metadata. It neither suppresses sources automatically nor
turns metadata into model instructions. The execution plan must declare how
source lifecycle metadata becomes public ingestion/update/forget commands.

Each member is at most 1 MiB. The adapter reuses the host's duplicate-key-rejecting
JSON decoder. It refuses an oversized member, duplicate query ID, duplicate source
generation, malformed row or mismatched split as a complete input error. A project,
source ID and generation identify one source version. Another document ID or
version label cannot make a duplicate generation valid. A different project is
a separate identity. The adapter never
drops rows to make a comparison fit. Resolve any required capacity gap before
freezing the implementation intended to cover the workload.

Only the scoring phase calls `EvaluationInput.labels/2`. It normalizes full source
identities and exact byte-coordinate annotations for the existing scorer. Keep
that call inside the label loader that runs after saved prediction hashes pass.
The original expected-answer text remains available to the independent semantic
reviewer through the separately retained dataset; it is not a predictor input.

```sh
mix test test/knowledge_evaluation_input_test.exs
```

Change expected-answer, class and relevance values in its first fixture. Query
projection must remain unchanged even when those labels become invalid. Then run
the label adapter and observe its separate refusal. This tests information
separation without opening the held-out workload.

## Materialize before interpreting a result

Follow `record_invoked/8` and `complete_result/2` in the Session driver before
changing answer preparation or metrics. An inline invocation result already
contains its complete domain `value`. A larger SDK-2 result carries a
`saved.result` delivery descriptor. Its output ID, length and digest describe
retained bytes, not an evidence array or a successful retrieval status.

The driver calls `Ipse.Session.materialize_result/2` with that exact delivery.
Only a successful complete read supplies the receipt's `value` for prediction,
answer preparation and measurement. The receipt retains these fields:

| Field | Meaning |
| --- | --- |
| `delivery` | The original saved-result descriptor, or null for inline output |
| `complete_result.byte_count`, `complete_result.sha256` | Length and hash of the exact retained document |
| `complete_result.bytes_base64` | Those complete source bytes, without re-encoding the domain value |
| `complete_result.provenance` | `historical_receipt`, not a claim of current source eligibility |
| `value` | The complete decoded domain object, or null when unavailable |
| `materialization_error` | A failed-read diagnostic, or null after success |

The existing `result_sha256` binds the invocation's displayed result text. For
saved output that text describes delivery; use `complete_result.sha256` to bind
the document. Preserve both identities. The Base64 field retains the original
bytes for verification.

When materialization fails, the receipt keeps its original delivery, sets
`value: null` and reports failed status. `completion_confirmed` still records
whether the original invocation committed its matching final receipt. A completed
invocation can have an unavailable document; do not rewrite that fact as lost
completion. The driver makes no retry, replacement query or model request.
Later prediction handling must retain this first failed row rather than compute
metrics from an empty or partially decoded ranking.

Run the Session-driver suite and follow its large-result controls:

```sh
mix test test/knowledge_evaluation_session_test.exs
```

The successful control requires more than 16 KiB of complete bytes and verifies
their hash, decoded value and provenance. The forged-delivery control changes
the digest and refuses even when a supplied inline value looks usable. The
lost-source control holds completion delivery, removes the readable source in
the fixture, then releases completion. It must retain one completed first receipt
as failed, submit no second command and make zero model requests. That fixture
changes internal test state; it does not alter a saved journal or establish an
OS enforcement boundary.

For the real independently built packages, follow the [complete-result exercise](../../developer/knowledge-extensions.md#publish-and-read-the-complete-domain-value).
It checks ten full Corpus and Research quotes, Graph bases outside `top_k`,
and exact inert historical recovery. Historical reads supply the original
retrieval snapshot; they do not rerun its current-source eligibility policy.

## Exercise failed paging and lost completion

Run the public-Session failure cases before changing the driver:

```sh
mix test test/knowledge_evaluation_session_test.exs
```

The suite compiles a synthetic SDK worker in a separate process. Its source
command returns malformed paging responses or holds an invocation. Temporary
files expose the exact dispatched action and worker-start barrier. It starts no
model service and grants no host actions. These fixture file operations do not
establish an OS sandbox boundary.

Follow the two paging cases into `ingest_paged/4` and `append_parts/6`:

1. An open response starts at offset one. The driver requires zero, retains the
   completed open receipt and submits no append or publish.
2. A valid open is followed by an append with the wrong next offset. The driver
   retains both receipts and submits no publish. A later explicit inspection is
   still allowed because both commands have confirmed completion.

Then compare the held-invocation cases. A timeout with confirmed cancellation
retains its receipt and permits a later read in the same Session. Killing the
Session after the worker-start barrier produces no completion acknowledgment.
The driver reads the original journal using its pinned Session ID, retains the
intent without a result, and marks the run `unsettled`. Another invocation must
return `:completion_unconfirmed` without changing the journal or dispatch log.
`close/1` must report cleanup as unconfirmed.

The worker-exit observation prevents fixture leaks. Process absence does not
replace the missing Session cleanup acknowledgment. Keep those assertions
separate when adding owner-loss or cancellation controls. Never clear `unsettled`
to continue an interrupted evaluation or open a replacement budget root silently.

For an unexpected paging result, enable the bounded synthetic probe:

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/knowledge_evaluation_session_test.exs test/stdio_probe_test.exs
```

The probe follows both the Session and task supervisors. Invocation workers run
under the task supervisor; tracing only the Session tree misses their startup and
callback calls. It records function arities, elapsed times and classified returns,
with at most 64 samples over 20 seconds. It retains no arguments or returned
payloads. The separate failure diagnostic reports only recognized action names
and closed receipt fields. Its privacy exercise supplies private arguments,
results, reasons and an unexpected status, then verifies that none is printed.

Compare the actions reached with worker initialization, callback and close
observations. A timeout receipt establishes that the selected deadline expired;
it does not identify which component delayed completion. Keep unexpected timeout
evidence separate from the intended malformed-response case. Passing repetitions
or a later green run cannot establish the original failure's cause.

## Follow a matched public-Session comparison

Run the orchestration fixture:

```sh
mix test test/knowledge_evaluation_runner_test.exs
```

Open its `matrix_plan/2` helper and follow `EvaluationPlan.build/1`. They select independently built Corpus, Graph,
Research and text-helper artifacts, with explicit command bindings and named
profiles. Its seven variants cover lexical retrieval, explicit and model
extraction, dense retrieval, hybrid retrieval, reranking and Research. The
synthetic HTTP fixture returns declared two-coordinate vectors and scripted
text. Those outputs exercise the provider wire formats and canonical accounting;
they measure no model quality.

Follow `run_variant/9`, `prepare/4`, `invoke/4` and `approve/1` in the runner:

1. Each project and variant gets a fresh Session and a fixed share of its declared
   inference budget. Budgets are not transferred or renewed after failure.
2. Source authoring runs outside the host VM. Ingestion and explicit forget
   commands finish before projections start. Only current eligible generations
   reach index or extraction commands. Skipped projections remain recorded.
3. Each invocation logs every new public receipt, including source paging steps.
   A refusal before dispatch cannot acquire an older command's receipt.
4. Approval checks bind the selected artifact, command owner, profile and complete
   egress. Per-invocation counts restrict embedding, text, search and fetch calls.
   Research fetches only URIs returned by that query's controlled search result.
5. All variants receive the plan's fixed `as_of_ms`. Research's optional argument
   selects that same time; omitting it preserves current-time behavior after capture.
6. After saving that variant's predictions, explicit source inspection and forget
   commands suppress its source copies. Collection requires exact namespace,
   key and revision approvals derived from a verified suppressed store.
7. Prediction failures retain their declared rows. Cleanup attempts cover the
   Session, gateway and sampler, with errors preserved in the output directory.

The controlled gateway uses one finite allowance across all projects. The runner
derives it from `expected_queries * (1 + max_sources)`: one search and at most
the declared number of fetches per question. Fifty ten-source questions allow
550 calls. Changing documents or beginning another question does not renew the
allowance. Direct gateway callers retain a 512-call default and can select an
explicit integer allowance from one through 11264. Invalid limits refuse before
starting a listener. Research limits are validated before any dataset access.

Inspect `gateway-calls.json` with `gateway-summary.json`. The first contains
bounded per-call metadata. The summary reports `call_limit`, `recorded_calls`,
`rejected_over_limit` and total decoded `request_count`. Requests beyond the
allowance refuse and increment the aggregate counter without growing the log.
Malformed frames rejected before JSON dispatch do not enter these counters.
Unknown tool values are recorded as `other`, never copied into the report.

Run `mix test test/knowledge_evaluation_services_test.exs` for the complete
550-call loopback control and post-exhaustion refusal. The runner's four-source
Research case verifies the declared fetch count through actual approvals.
Search approval binds the complete version, contract, query and source limit.
Fetch approval permits each selected URI once, up to that same declared limit.
The case supplies two generations with identical text and reused version labels,
including integer `1` and string `"1"`. The raw fetch citation identifies its
captured generation one; its URI and body hash map the saved prediction to the
dataset's current generation and typed version. Retain that distinction rather than treating a matching body hash alone
as a unique source identity. The control makes no model request.

Source authoring generates `dataset:PROJECT:DIGEST` URIs. The digest hashes this
ordered JSON array with raw SHA256:

```elixir
["dataset-source", 1, project, document_id, source_id, generation, version, body_sha256]
```

Generation and the version's JSON type remain part of the identity even when
body bytes or display labels match. Keep this policy in the implementation
freeze; changing it changes citation provenance and answer inputs.

Compare the current-source and suppressed-source fixtures. Intentional exclusions
remain visible while complete retrieval of eligible sources can succeed. The
package owns that classification; the runner preserves its returned status.
An unpublished source, missing-vector fallback or bounded incomplete traversal
must remain partial. The [query completeness exercise](../../developer/knowledge-extensions.md#trace-a-source-and-a-query)
tests those distinctions through public workers. The scorer still gives partial
results zero successful retrieval utility; it does not upgrade a useful-looking passage.
The model fixture also proves that forgotten and expired text never enters its
requests. Worker, model and whole-system RSS remain unmeasured; the sampler's
start, end and sampled maximum describe only the harness BEAM.

For a change exercise, trace the Research approval through `MCPCall`. Its effect
has no State namespace. State writes use the selected logical project namespace,
while embedding and text calls use the Session identity. Changing all three to
the same namespace must refuse the mismatched effect. Keep the host's existing
contracts as the authority when changing an evaluation adapter.

## Trace an answer's evidence

`IpseKnowledgeExample.EvaluationAnswer.prepare/3` takes the query, an as-of time
and at most ten saved candidates in their existing rank order. Each candidate
has its complete `citation`. The result contains an exact `model.complete`
request for `p27_answer`, a shown context, coverage and the context's SHA256.
It executes nothing.

The helper assigns short IDs such as `e1` to evidence. It crops each quote to at
most 512 UTF8 bytes and removes lowest-ranked candidates until the encoded input
fits 4096 bytes. A cropped quote gets an adjusted end offset and quote hash.
The mapping retains source identity, provenance, times and the original captured
span. Coverage lists omissions and cropping. Preserve the full retrieval result
separately so answer-context limits cannot erase the retrieval measurement.

Saved prediction rows use version two. `evidence` keeps the complete returned
ranking; `context_evidence` holds the cited answer spans after cropping. Each
context span must be contained in an original ranked span with identical source
identity and bytes. Source and annotated-span retrieval metrics use `evidence`.
Claim/span citation judgments can refer to the corresponding context spans.
Do not replace a ranked passage with its answer excerpt to improve span scores.

Both CLI readers and the scorer accept at most 64 MiB in one prediction file
and 64 MiB across all declared files. Each JSONL row remains limited to 256 KiB.
Count serialized bytes, including JSON escapes and repeated source identities;
query count and raw quote lengths alone do not establish file capacity. Review
packets have separate limits of 32 MiB per file and 64 MiB in total. The scoring
CLI accepts a review JSON file up to 32 MiB through the host's duplicate-rejecting
decoder; manifests and dataset members retain their separate 1-MiB limits.
A size refusal keeps the first predictions for inspection. Never drop rows or
rerun model work to make a retained comparison fit a later consumer.

After the public Session call completes, pass the saved response text and the
same bundle to `decode_answer/2`. The decoder requires one complete JSON object
with `classification`, `answer` and `claims`. Each claim references unique shown
IDs. Unknown IDs, extra fields, duplicate fields and Markdown fences refuse.
An abstention has no claims. An answer or conflict has at least one cited claim;
one source can contain conflicting statements.

The mapped result proves which shown span a claim cited. It does not establish
that the span supports the claim. Keep that semantic judgment in independent
review, alongside literal captured-source verification.

## Prepare independent review from finalized predictions

Use this procedure for a completed version-one prediction. Version-two identity
seals cannot enter review through this path. Finish prediction and retain its
printed hash before preparing a review. The `review` phase verifies the execution
freeze, finalized prediction hash and exact
variant/query grid before opening reference labels. It reuses
`EvaluationScore.verified_predictions/2`; a separate permissive JSON parser
cannot substitute for the scorer's row checks. Prediction IDs must be opaque
`p-` plus SHA256 values before any label loader runs.

Set the paths and independently retained hashes from your completed freeze and
prediction steps, then choose a new review directory:

```sh
IPSE_REVIEW_FREEZE=/absolute/path/to/frozen/manifest.json
IPSE_REVIEW_FREEZE_SHA256=replace_with_the_separately_retained_freeze_sha256
IPSE_REVIEW_DATA=/absolute/path/to/dataset/manifest.json
IPSE_REVIEW_PREDICTIONS=/absolute/path/to/run/predictions.jsonl
IPSE_REVIEW_PREDICTION_SHA256=replace_with_the_recorded_final_prediction_sha256
IPSE_REVIEW_OUTPUT=/absolute/path/to/new-review-packet
mix run scripts/evaluate-knowledge.exs -- --phase review \
  --freeze "$IPSE_REVIEW_FREEZE" --freeze-sha256 "$IPSE_REVIEW_FREEZE_SHA256" \
  --data-manifest "$IPSE_REVIEW_DATA" --predictions "$IPSE_REVIEW_PREDICTIONS" \
  --prediction-sha256 "$IPSE_REVIEW_PREDICTION_SHA256" --output "$IPSE_REVIEW_OUTPUT"
```

Expect `status: "ok"`, the complete row count, `packet_sha256` and
`reference_integrity_complete: true`. Retain that packet hash separately. An
existing output path refuses. Files are owner-only in a private directory.
Invalid reference spans remain visible, set completeness false and produce a
failing CLI exit. A written packet does not establish semantic support.

Give the independent reviewer only the packet directory:

| File | Review task |
| --- | --- |
| `instructions.md` | Follow the versioned verdict definitions and record reviewer identity and limitations |
| `cases.jsonl` | Read the saved outputs and claim/span pairs, with strategy labels removed and order blinded |
| `queries.json` | Compare questions, reference answers, relevance and the fixed as-of time |
| `source-texts.json` | Check the original source bodies and their complete typed/versioned identities |
| `reference-integrity.json` | Inspect literal annotation failures before accepting reference-based scores |
| `reviews-template.json` | Copy to a separate review file and fill actual semantic verdicts |
| `manifest.json` | Verify every packet file hash and its execution/data/prediction identities |

Keep the run and freeze directories private: they contain strategy selections
and execution history. All prediction-bearing packet lists use the same seeded
order, including the template. Output style can still hint at a method; removing
labels cannot guarantee that a reviewer cannot infer one.

The `source-bytes-v1` integrity rows compare the original corpus against complete
project/source/generation/typed-version/hash identities and exact UTF8 byte spans.
The semantic template remains `unmeasured` with `independent: false`, even when
every byte check succeeds. The independent reviewer judges entailment and each
claim/span pair, using their actual identity. The generating model cannot judge
itself independently. Review flags cannot prove a reviewer's independence.
Keep notes and disagreements bound to the retained packet hash. Preserve packet
files; write completed verdicts to a separate `reviews.json`.

Run the synthetic boundary and CLI exercises before changing this workflow:

```sh
mix test test/knowledge_evaluation_review_test.exs test/knowledge_evaluation_score_test.exs test/knowledge_evaluation_runner_test.exs
```

Trace the false-claim fixture: its quotations match actual corpus bytes, but no
semantic verdict is manufactured. Then compare identical bodies with reused
integer/string version labels, a foreign project and a wrong reference offset.
The hash/grid refusal cases must not invoke the label callback. The real CLI
exercise checks private files, unchanged output after overwrite refusal and a
nonzero score exit when the supplied review is still unmeasured.

## Verify the hash-before-label rule

Run the synthetic suites:

```sh
mix test test/knowledge_evaluation_answer_test.exs
mix test test/knowledge_evaluation_score_test.exs test/knowledge_metrics_test.exs
```

Open `test/knowledge_evaluation_score_test.exs`. Follow its `inputs/3` fixture
into `EvaluationScore.score/4`. The frozen declaration names variants, queries,
a baseline, an explicit classification mapping and prediction-file hashes.
The raw JSONL blobs are supplied separately. Labels and reviews arrive through
zero-argument callbacks only after every expected raw hash and prediction row
has passed validation.

Work through the first test as a change exercise:

1. Replace the saved prediction bytes while retaining the original hash. Expect
   `:prediction_hash_mismatch` and no loader message.
2. Restore the bytes, insert a duplicate JSON key and update the file hash.
   Expect `:duplicate_prediction_key` before either loader runs.
3. Submit two rows for the same variant/query or an `attempt` other than one.
   Expect refusal rather than a best-of-several prediction.
4. Run the suites again. Check that the valid control still reaches both loaders
   and reports its measurements.

The scorer bounds raw bytes, rows, nesting, strings and collections before
loading labels. It uses OTP's JSON decoder callbacks to enforce duplicate-key
and structural limits. The answer helper uses Elixir's `JSON.decode/3`, whose
decoder options are a keyword list. The scorer uses Erlang's `:json.decode/3`,
whose callbacks are a map with an explicit `null: nil`. These APIs take different
option types. A successful parse check alone does not verify either adapter.

## Keep failed rows and different measurements

Every declared variant/query pair appears in the report. A missing prediction
becomes an explicit missing row. Failed and partial rankings retain their
observed scores, while their primary retrieval utility is zero. Queries with
no positive relevance annotations remain present with N/A retrieval scores.
Unknown measurements remain `nil`.

Read these report fields independently:

| Measurement | What it establishes |
| --- | --- |
| Source Recall@5 and nDCG@10 | Ranked full source identities against source relevance grades |
| Exact and contained span recall | Matching byte coordinates and UTF8 content against annotated spans, with independent literal integrity |
| Classification and confusion matrix | The frozen mapping of saved classes against expected classes, retaining execution failures |
| Semantic support and citation precision | Explicit independent verdicts on actual saved responses and claim/span pairs |

Several claims citing one span remain several claim/span pairs. A quote at the
wrong byte coordinates cannot gain contained-span credit from substring overlap.
Cross-project evidence is invalid even if a supplied integrity review calls it
valid. Missing or non-independent review stays unmeasured. A retrieval-only row
has no supported-answer measurement.

When the plan selects answers, an execution failure keeps `response_kind: "answer"`
with its failed status, empty claims and null answer. It remains an answer-policy
attempt, so an independent unsupported verdict counts it as zero in the support
denominator. Intentional retrieval-only plans still produce `retrieval_only` rows
whose answer metrics remain unmeasured. Neither case invents a successful answer
or a semantic review.

The scorer's support and citation thresholds are 0.90 and 0.95. Its aggregate
`semantic`, `gates` and `quality_gates_passed` fields cover the complete frozen
variant/query grid, including missing rows. `quality_gate_scope` identifies that
scope; each variant retains its own independent measurements and gates. A
complete-workload pass does not promote a failing individual engine.
Incomplete review cannot pass. The `score` CLI preserves `scores.json` and exits
nonzero for failed or unmeasured aggregate gates. These checks do not measure authority, scope isolation, replay,
suppression, native enforcement, installed execution, latency or resources.
Follow the [plan](../../plan.md#p27-optional-research-graph-and-rag) for the complete
acceptance requirements. Passing these synthetic exercises establishes helper
behavior, not held-out quality or a selected retrieval engine.

## Reconcile model work with durable accounting

Follow `persist_close/2` in the runner. It confirms owner cleanup, loads the
journal through `Ipse.Journal.load/2`, and restores canonical usage through
`Ipse.Usage.restore/2`. The session driver separately checks recoverable context
through `Ipse.Session.restore_context/1`. Use `Usage.order/1` and
`Usage.request_record/1` to export every request in admission order.
`Usage.snapshot/1` shows only the latest sixteen requests for the UI.

The runner attaches the saved budget in inspection mode and reads it under its
existing lock. `EvaluationResources.reconcile_budget/4` checks the exact request
IDs and admissions against canonical usage, including refusals. It also checks
that retained liability covers every known canonical observation, including
earlier peaks followed by smaller counters. This comparison requires one root
session and rejects additional child admissions. It does not grant authority,
change reservations, or continue the session. The live
`Ipse.Budget.validate_sources/3` requires a live checkpoint and is not a saved-ledger
inspection API.

Read the resulting files together:

| File | How to use it |
| --- | --- |
| `usage.jsonl` | Inspect every canonical request and each session's validated budget snapshot |
| `request-resources.jsonl` | Match requests to project, variant, source or query, invocation, admission/refusal, dispatch intent and settlement |
| `timings.jsonl` | Inspect individual phase and invocation clocks, outcomes and unconfirmed completion |
| `resource-summary.json` | Compare per-variant phase percentiles, query coverage, request roles, token availability and retained budget dimensions |

A canonical attempt does not prove admission or provider dispatch. A refused
attempt remains in usage while booking no request. A recorded dispatch intent
does not prove that the remote provider accepted work. Preserve completed,
failed and unknown outcomes independently from budget settlement. Missing token
counts remain unknown; embedding output tokens are not applicable. Without a
rate card, work remains unpriced. Budget dimensions report conservative booked
liability, not an invoice.

Read-only inspection remains available after inference quota exhaustion. Do not
put a blanket request-count guard around driver operations. The host admission
policy owns inference quotas.

### Verify coverage and failure accounting

Run the local scripted-provider exercises:

```sh
mix test test/knowledge_evaluation_resources_test.exs test/knowledge_evaluation_runner_test.exs
```

Follow the thirty-one-request case in the runner test. Compare the thirty-one
scripted HTTP calls, restored journal records, exported requests and booked
requests. This crosses the ordinary thirty-step default and the sixteen-request
UI snapshot. Each exported request must retain its query ID. Then follow the
one-request-budget case: two queries produce two canonical attempts, one admitted
request, one refusal and one dispatch intent. Both query rows remain present.

In the resource test, follow the historical-peak case. A request observes sixty
input tokens and later seven. Removing the sixty-token observation from the
budget must fail reconciliation even though its final counters still match.
Removing a refusal or concealing usage behind a refused admission must also fail.

### Exercise ownership of a model service

Use this exercise before connecting a cell to the native memory collector. The
cell must own the service and create its cache inside the measured scope. A
shared daemon can retain allocations from another cell, and a hardlinked cache
can reuse charges established outside the scope.

On Linux, build the native helper and run the synthetic service cases:

```sh
./scripts/build.sh
mix test test/knowledge_evaluation_model_service_test.exs
```

The fixture is a Rust HTTP server compiled from
`test/support/model_service_probe.rs`. It checks the selected environment and
answers the small Ollama inventory protocol. It loads no model and performs no
inference. The tests cover private cache contents and inodes, occupied ports,
forged child output, bounded logs, inventory failures, callback exceptions,
service loss and owner death. On macOS, the same test file checks pure selection
validation and refusal before staging because listener ownership requires Linux.

To retain the Linux case receipts outside ExUnit cleanup, compile the fixture
and choose a fresh evidence directory:

```sh
IPSE_MODEL_PROOF=$(mktemp -d)
rustc --edition=2021 -D warnings test/support/model_service_probe.rs -o "$IPSE_MODEL_PROOF/probe"
mix run scripts/verify-model-service.exs -- "$IPSE_MODEL_PROOF/probe" "$IPSE_MODEL_PROOF/evidence"
```

Expect one JSON summary whose cases all report `status: "passed"`. Inspect each
case's `verification.json` and the completed cases' `receipt.json`. Failed
operations retain partial output. Preserve those files when diagnosing a failure;
choose another output directory for another synthetic exercise. Reusing an
operation's directory must refuse without replacing its receipt or running work.

To repeat the cases with a bundled runtime, build a package and pass its archive
to the installed verifier. This example requires exactly one archive in `dist`:

```sh
./scripts/package.sh
set -- dist/ipse-*.tar.gz
test "$#" -eq 1
elixir scripts/verify-model-service-package.exs "$1" "$IPSE_MODEL_PROOF/probe" "$IPSE_MODEL_PROOF/installed"
```

Expect the same synthetic case results with `installed: true`. The verifier
extracts the package and removes development executables from its PATH. On macOS,
its result instead confirms refusal before effects. The service module and
fixture are trusted evaluation code loaded from the checkout; Runner, HTTP and
native execution use the bundled package.

Trace `EvaluationModelService.run/3` through these ownership boundaries:

1. `validate/1` checks a closed selection without IO. The selection names exact
   runtime files, hashes, model manifests, a private loopback origin and finite
   deadlines. It supplies no download, fallback or attempt-renewal authority.
2. A guarded Task creates the fresh private output and copies the selected
   runtime and complete manifest/blob closure. The native
   [`--copy-regular` mode](../../../native/README.md#copy-a-regular-file-through-a-retained-descriptor)
   refuses unsafe source descriptors. Elixir hashes the new private files.
   The owner always creates `runtime/lib/ollama`, keeping library discovery in
   the selected distribution's private layout.
3. The caller owns the native Port and drains its frames while the Task works.
   One native listener observation must identify the selected direct child
   before any inventory request. Child stdout remains opaque log data.
4. The Task checks exact tags, model capabilities and empty initial residency,
   then calls the work function once. It reports the work outcome before final
   inventory and private runtime/manifest/config rechecks. Final resident models
   must have selected digests and `size_vram: 0` under the explicit CPU policy.
5. The caller waits for the Task and HTTP clients to stop, closes the daemon,
   then persists bounded logs and the receipt. No log-file write runs in the
   live Port receive loop. Bytes drained during native close are outside the
   retained log prefix, as the receipt states.

Compare the `changed_after` case with `normal`. Both preserve the callback's
returned value, but changed final inventory makes the service receipt fail.
`work_status`, `service_status` and `native_cleanup` describe separate facts.
The owner-death case observes its known Task, Session and daemon stop separately;
it produces no final service receipt. Task termination alone does not establish
Session journal closure or canonical inference accounting.

The fixed CPU environment selects a policy that hides CUDA, ROCm and Vulkan
devices and disables cloud models. The synthetic fixture verifies those environment
values; real runtime CPU execution still needs separate verification. The selected daemon defaults use one parallel request, retain selected
models and cap loaded models at the selection count. These concrete values appear
in the receipt. Final residency supplements this policy; it cannot prove every
allocation throughout the interval. This module grants no OS sandbox and trusts
the explicitly selected runtime. Ordinary process-group containment limits still
apply.

The service owner is an independently exercised evaluation component. The current
version-two seal does not yet bind its selection or authorize measured execution.
Complete cells must claim their attempts and establish kernel membership before
calling it. Synthetic service receipts establish neither exact-memory coverage
nor model quality.

### Exercise the native aggregate collector

Use a Linux host with cgroup v2 memory accounting, `clone3(CLONE_INTO_CGROUP)`,
a delegated systemd user manager and the existing Rust/Elixir toolchains.
The [dependency inventory](../../developer/dependencies.md) records approval for this optional
benchmark tooling. Ordinary source tests and macOS operation do not require it.

```sh
./scripts/build.sh
elixir scripts/verify-memory-scope.exs "$PWD/priv/ipse-runner"
```

Expect one JSON summary with `checks: 10`, zero inference requests and a private
`evidence` directory. The verifier starts only uniquely named transient user
services and stops its own services on exit. It retains synthetic receipts for
inspection. To run the same exercise through ExUnit, include its explicit tag:

```sh
mix test test/memory_scope_test.exs --include memory_scope
```

Follow `native/ipse-measure.rs` from scope admission to clone, first reap and final
counter read. Each root command is born inside a fresh cgroup before exec.
The serial/overlap control distinguishes the simultaneous total from individual
maxima. The Erlang control captures a brief 256-MiB Port child after it exits.
Unequal nested allocations check that a parent interval resets independently of
the whole-run counter, including when the launcher ignored SIGCHLD.

Then follow the owner and collector loss cases. A preclosed lease must refuse
before command execution. A cancellation following ignored control bytes must
still be observed while the owner remains open. The scope's private native anchor
kills descendants after a nested collector dies, even while the application is
alive. Root collector loss remains a separate incomplete case: its started record
survives without a completion receipt. It does not prove that no work occurred.

Compare `peak_bytes` with `parent_interval_peak_bytes` as separate subjects.
Both are kernel charged-memory high waters. Page cache, shared-page ownership
and kernel charges make them different from summed process RSS. They do not
establish GPU/device-memory coverage or an exact macOS aggregate. Do not sum peaks
or subtract a starting baseline. See the [native protocol](../../../native/README.md#optional-exact-aggregate-memory-scopes)
for lease, output and receipt rules.

These controls verify the native collector only. The current evaluation runner
still reports its sampled BEAM memory and incomplete resource evaluation. Its
complete-cell execution and frozen aggregate receipt integration remain to be
implemented and verified. The service-owner exercise above verifies that
component separately; it does not connect it to the runner's measured entry.

### Exercise complete measured sequences

Use the same supported Linux host and built helper to verify the generic stage
launcher. This exercise needs no model service or evaluation dataset:

```sh
elixir scripts/verify-memory-sequence.exs "$PWD/priv/ipse-runner"
IPSE_SEQUENCE_TESTS=$(mktemp -d)
rustc --edition=2021 --test -D warnings native/ipse-sequence.rs \
  -o "$IPSE_SEQUENCE_TESTS/sequence"
"$IPSE_SEQUENCE_TESTS/sequence"
```

Expect six live cases and six native parser/filesystem tests. Follow one
`Stage` from its immutable binary descriptor into `stage-000.claim`, then through
the child collector's `M` receipt and two-byte `T` completion status. Preparation
and finalization use the same birth-before-exec path as cells. Their separate
scope and parent-interval peaks contribute to the whole-run counter; they are
not incremental differences to subtract from another peak.

The live fixture allocates memory in fresh preparation/finalization BEAM entries
and their brief Port children while an unrelated sibling stays alive outside
the measured root. Another case prints a forged completion frame from a failed
application. Its bytes must remain opaque logs, the stage stays failed, and the
real finalizer runs only after cleanup confirmation. Collector loss instead
leaves a permanent claim without status or summary and prevents later stages.

Then follow both writerless FIFO inputs. A bootstrap FIFO must refuse before
preparation; a preparation-produced cells FIFO must refuse before any cell or
finalizer. Descriptor admission opens nonblocking before checking the retained
FD type, so refusal does not wait for the outer run deadline.

The [native protocol](../../../native/README.md#sequence-complete-measured-stages)
owns the exact descriptor layout, limits and evidence filenames. A domain runner
still has to seal and validate the schedule, preserve original allocations and
claim the freeze before opening inputs. It must reconcile the finalizer and
outer-root receipts after exit; those records do not exist while finalization
is running. These generic controls do not implement complete evaluator cells,
model-service/cache identity, resource acceptance or held-out quality.

### Interpret latency and measurement limits

Phase clocks use monotonic microseconds. The summary reports nearest-rank p50
and p95 in milliseconds with sample and unknown counts. Query IDs distinguish
repeated question text. Failed queries stay in the grid and in observed clocks.
The enclosing projection phase includes its required storage audits. Use
`invoke_index` and `invoke_extract` timings to inspect public command durations
before those audits; execution time includes the complete measurement workload.
Invocation timings separately count unconfirmed completion; an elapsed wait is
not proof that interrupted work finished. Canonical request duration comes from
the journal and remains unknown when unavailable.

The summary's `complete` field covers the declared clock and accounting scope.
Read `storage_reachability_complete` separately. Check `measurement_scope`,
`unmeasured` and `resource_evaluation_complete` before comparing engines. The
separate sampler describes the harness BEAM only. OS process peak memory and
model process memory remain unknown. File counts under a run directory also
exclude authoring and preflight copies outside that directory; the output-wide
overview counts those copies separately. Lifecycle file lengths and sampled
harness memory do not measure whole-system memory or every storage allocation.

### Verify retained storage without querying through the audit

Follow `EvaluationInventory.snapshot/5` and the pure `Store.inventory/2` in the
independent knowledge artifact. The host validates the bounded, owner-only State
file and every record envelope through `State.valid_outcome?/4`. It checks the
namespace, version and generation sum. A separate Elixir VM loads the verified
artifact, public SDK and existing Jason runtime, then computes counts and opaque
hashes. The SDK validator needs Jason even when the audit itself uses Elixir JSON.
The host rechecks file bytes
and artifact identity afterward. Domain modules remain unloaded in the host.

Selected root references identify retained content and projections. The audit
verifies each referenced page's hash, partition, source and generation. It also
checks a repeated reference's hash before skipping traversal. Missing, deleted
or substituted pages refuse the inventory. Draft pages stay separate from
selected pages; abandoned pages become orphans. For source drafts,
`source_generation` is the old-source precondition and `target.generation` owns
the new pages. Projection drafts retain the current source generation.

Read tombstone and slot counts at namespace scope. A tombstone retains no value
from which to recover partition ownership. Collection can remove page values
while retaining their record slots and revisions. Encoded value/record bytes
use Elixir JSON; actual State file bytes are reported separately. The audit
returns no source text and must never supply retrieval or model inputs.

The runner records snapshots before ingestion, after each index/extraction
projection, after preparation, after each query, after source suppression and
after collection. Projection snapshots retain source generation and chunk ID;
their count must match public projection invocation timings. Its cache key
includes the exact State file hash, path, artifact digest
and partition. Unchanged query reads reuse the verified inventory file. Missing
storage is explicit absence; unavailable or corrupt storage remains incomplete.
Research has no retained State store and reports that distinction explicitly.

Follow `storage_lifecycle/4` after the prediction loop. It inspects each source
once, skips roots already suppressed and explicitly forgets the rest. The
post-forget inventory must be available before collection. Follow
`EvaluationInventory.collection_requests/3`: it binds owner-only namespace bytes
to their verified hash, requires every root in the selected partition to be
suppressed with no draft, and returns only exact project-scope page deletions.
The approval policy matches each request and permits each key once. Collection
uses batches of at most twelve, with at most twenty-two batches for the existing
256-slot namespace. Final inventory requires no orphan pages and unchanged slot
count. Missing lifecycle snapshots keep storage coverage incomplete.

No further quality query runs against those suppressed copies. A failed
suppression or collection keeps earlier prediction rows and reports incomplete
execution. Earlier journal text and original dataset bytes remain retained;
collection is not transcript erasure or slot recovery.

`execution-overview.json` records elapsed time from runner entry through first
prediction finalization, including preflight, input handling, cleanup and the
primary reports. CLI startup, module loading and the overview's own inspection
and receipt stay outside that clock. The overview counts regular file lengths
under the complete output directory, including authoring and preflight copies,
and separately under declared frozen inputs. Read its exclusions before adding
those counts to a storage comparison. File lengths do not measure allocated
blocks, compression, shared extents or an exact transient peak.

Run the isolated validation exercises:

```sh
mix test test/knowledge_store_test.exs test/knowledge_evaluation_inventory_test.exs
```

Follow a first ingestion and a replacement draft through append, abort, forget
and collection. Check that selected pages stay unchanged during replacement,
draft pages become orphans after abort, and collection creates tombstones
without recovering slots. Then corrupt a reference hash or substitute a foreign
page. Expect inventory refusal. In the raw-file exercise, an inconsistent
generation sum, a floating-point generation or group/world-readable State file
must fail before it can become trusted metadata.
The collection-allowance exercise separately rejects an active root, a retained
draft, changed bytes and a stale revision snapshot. Only the selected partition's
page keys can enter its approval list; roots, foreign pages and source text stay
out of that list.
