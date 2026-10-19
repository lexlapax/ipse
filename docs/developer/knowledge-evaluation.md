# Measure knowledge results without exposing labels

Use this chapter to change the knowledge evaluation helpers and verify their
failure behavior. You need a built source checkout and the Elixir toolchain.
The exercises use synthetic data and local fixtures. The orchestration exercise
starts loopback search and model-protocol fixtures; it uses no model weights or
external service.
For changing the packages themselves, start with
[knowledge extension development](knowledge-extensions.md).

## Follow the prediction and scoring boundary

The evaluation helpers have separate owners. Keep their inputs separate:

| Owner | Implementation | Input and result |
| --- | --- | --- |
| Freeze | `examples/knowledge/evaluation_freeze.exs` | A clean source tree, public plan and inert artifacts become a pinned manifest and copied artifacts |
| Dataset projection | `examples/knowledge/evaluation_input.exs` | Dataset bytes become separately validated corpus, label-free queries or scoring labels |
| Orchestration | `examples/knowledge/evaluation_runner.exs` | A validated variant plan becomes public Session calls, first predictions and retained execution failures |
| Session driver | `examples/knowledge/evaluation_session.exs` | Explicit artifact/profile/budget selections and public commands become durable invocation receipts |
| Answer preparation | `examples/knowledge/evaluation_answer.exs` | Saved ranked citations become a bounded request and an exact shown-span mapping |
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
[Graph recovery procedure](../operator/graph.md#replace-suppress-and-recover-a-source).

Before running predictions, record the source/artifact identities, algorithms,
prompts, profile destinations, budgets, query order and time policy. Keep labels
and expected answers out of the driver, extension options and model inputs.
Finalize raw prediction files and their hashes before opening labels. A scorer
can enforce the order of its own callbacks, but cannot prove that another caller
has never opened those files.

## Seal identities before opening inputs

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

The runner's `freeze` phase adds executable preflight after the identity seal.
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

After a complete execution freeze is verified, its input adapter may open the
declared dataset members. `EvaluationInput.queries/2` accepts the version-one
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
generation, malformed row or mismatched split as a complete input error. It never
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

## Follow a matched public-Session comparison

Run the orchestration fixture:

```sh
mix test test/knowledge_evaluation_runner_test.exs
```

Open its `matrix_plan/2` helper. It selects independently built Corpus, Graph,
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
6. Prediction failures retain their declared rows. Cleanup attempts cover the
   Session, gateway and sampler, with errors preserved in the output directory.

Compare the current-source and suppressed-source fixtures. Intentional exclusions
remain visible while complete retrieval of eligible sources can succeed. The
package owns that classification; the runner preserves its returned status.
An unpublished source, missing-vector fallback or bounded incomplete traversal
must remain partial. The [query completeness exercise](knowledge-extensions.md#trace-a-source-and-a-query)
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

After the public Session call completes, pass the saved response text and the
same bundle to `decode_answer/2`. The decoder requires one complete JSON object
with `classification`, `answer` and `claims`. Each claim references unique shown
IDs. Unknown IDs, extra fields, duplicate fields and Markdown fences refuse.
An abstention has no claims. An answer or conflict has at least one cited claim;
one source can contain conflicting statements.

The mapped result proves which shown span a claim cited. It does not establish
that the span supports the claim. Keep that semantic judgment in independent
review, alongside literal captured-source verification.

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

The scorer's support and citation thresholds are 0.90 and 0.95. Incomplete review
cannot pass. These checks do not measure authority, scope isolation, replay,
suppression, native enforcement, installed execution, latency or resources.
Follow the [plan](../plan.md#p27-optional-research-graph-and-rag) for the complete
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

Follow the seventeen-request case in the runner test. Compare the seventeen
scripted HTTP calls, restored journal records, exported requests and booked
requests. Each exported request must retain its query ID. Then follow the
one-request-budget case: two queries produce two canonical attempts, one admitted
request, one refusal and one dispatch intent. Both query rows remain present.

In the resource test, follow the historical-peak case. A request observes sixty
input tokens and later seven. Removing the sixty-token observation from the
budget must fail reconciliation even though its final counters still match.
Removing a refusal or concealing usage behind a refused admission must also fail.

### Interpret latency and measurement limits

Phase clocks use monotonic microseconds. The summary reports nearest-rank p50
and p95 in milliseconds with sample and unknown counts. Query IDs distinguish
repeated question text. Failed queries stay in the grid and in observed clocks.
Invocation timings separately count unconfirmed completion; an elapsed wait is
not proof that interrupted work finished. Canonical request duration comes from
the journal and remains unknown when unavailable.

The summary's `complete` field covers the declared clock and accounting scope.
Check `measurement_scope`, `unmeasured` and `resource_evaluation_complete` before
using it for an engine comparison. Storage reachability and OS/model process
memory remain unmeasured by this summary. The separate sampler describes the
harness BEAM only, and the file counter measures bytes under each run directory.
Neither establishes model memory, OS peak memory or complete storage lifecycle
cost. A complete clock/accounting report cannot close those evaluation gates.
