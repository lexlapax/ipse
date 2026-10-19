# Measure knowledge results without exposing labels

Use this chapter to change the knowledge evaluation helpers and verify their
failure behavior. You need a built source checkout and the Elixir toolchain.
The exercises use synthetic saved data. They start no model or external service.
For changing the packages themselves, start with
[knowledge extension development](knowledge-extensions.md).

## Follow the prediction and scoring boundary

Evaluation has three different owners. Keep their inputs separate:

| Owner | Implementation | Input and result |
| --- | --- | --- |
| Session driver | `examples/knowledge/evaluation_session.exs` | Explicit artifact/profile/budget selections and public commands become durable invocation receipts |
| Answer preparation | `examples/knowledge/evaluation_answer.exs` | Saved ranked citations become a bounded request and an exact shown-span mapping |
| Scoring | `examples/knowledge/evaluation_score.exs`, `metrics.exs` | Hashed first predictions and independent labels/reviews become separate measurements |

The Session driver imports independent artifacts through ordinary host APIs.
It does not load the production knowledge modules into the host or call a
provider directly. Its caller supplies the approved configuration and validates
each complete proposed action. A selected profile is a route, not permission
to approve every request on that route.

Before running predictions, record the source/artifact identities, algorithms,
prompts, profile destinations, budgets, query order and time policy. Keep labels
and expected answers out of the driver, extension options and model inputs.
Finalize raw prediction files and their hashes before opening labels. A scorer
can enforce the order of its own callbacks, but cannot prove that another caller
has never opened those files.

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

Read the saved journal through `Ipse.Journal.load/2`, validate recovery with
`Ipse.Session.restore_context/1`, and reconstruct usage through
`Ipse.Usage.restore/2`. Compare it with `Ipse.Budget.saved/2`. An attempt record
does not itself prove provider dispatch or a budget reservation. A refused
attempt can remain in accounting while the shared budget books no request.

For each actual request, preserve completed, failed and unknown outcomes.
If a failed stream has no durable token observation, report unknown usage and
the retained reservation. Do not report zero tokens or zero cost. No configured
rate card means unpriced work. Read-only inspection after inference quota
exhaustion remains useful; do not put a blanket request-count guard around every
driver operation. The host's real admission policy owns inference quotas.
