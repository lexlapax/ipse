# Review first outcomes and qualify individual strategies

Score immutable first predictions against hash-bound source bytes and independently
reviewed semantic judgments. Literal citation integrity, relevance, classification,
and answer support are different measurements. Start after the complete
[evaluation/audit workflow](knowledge-evaluation.md), never by editing a prediction
or review until it passes.

## Verify authority before opening references

Review reuses `Score.verified_predictions/2`, not a permissive alternate parser.
V2 measured execution requires separately retained execution-freeze, prediction,
and audit hashes plus exact sealed data/prediction paths. V1 keeps its historical
freeze/prediction contract and rejects audit arguments. Legacy predict/verify-frozen
refuse V2 seals with `measured_entry_required`; use measured execution/audit.

Keep these identities separate:

| Identity | Binds |
| --- | --- |
| Execution-freeze | Experiment and reference policy |
| Review binding | Context, metric version, complete verified prediction files/hashes, and declaration policy |
| Packet hash | Every packet file and reviewer instruction |
| Delayed answer hash | Exact independently committed answer bytes, without a predictor-visible path |

Plan-three scoring declaration contributes its complete validated content in a
separate binding domain. Changed contracts, qualification, or query order invalidate
old reviews even when IDs/prediction bytes match. Historical declaration-two binding
remains distinct; both use review-envelope two. Opaque bindings reveal no strategy.
Prediction IDs must be `p-` plus SHA-256 before labels load.

The scorer's order is raw prediction hashes/closed rows, binding, closed review
and matching binding, original corpus/hash/literal checks, then reference labels
and their spans. It cannot prove another caller never read a label through another
channel. Preserve independent authoring, custody, and the pre-release audit gate.

## Prepare a private blinded packet

After all first outcomes and required audits are frozen, release the identical
committed answer bytes. Use values retained separately from the verified run, not
hashes substituted after an evidence change. These commands continue the variables
and paths established in the evaluation chapter:

```sh
export IPSE_LABELS=/released/identical-committed-answers.json
elixir dev/evaluate-knowledge.exs --phase review \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" --audit-sha256 "$IPSE_AUDIT_SHA256" \
  --data-manifest "$IPSE_DATA_MANIFEST" \
  --predictions "$IPSE_BENCHMARK/reports/predictions.jsonl" \
  --prediction-sha256 "$IPSE_PREDICTION_SHA256" \
  --labels "$IPSE_LABELS" --output "$IPSE_BENCHMARK/review-packet"
cp "$IPSE_BENCHMARK/review-packet/reviews-template.json" "$IPSE_BENCHMARK/reviews.json"
```

Expected output is an ok packet receipt, complete row count, packet hash, and
reference-integrity complete. Files are owner-only; existing output refuses.
Sealed-answer input needs labels with exact answers hash, even if release path
changed. Missing/changed/invalid references refuse rather than regenerating firsts.
Packet creation establishes no semantic support. The copied template is explicitly
unmeasured/independent-false.

| Packet file | Reviewer use |
| --- | --- |
| instructions.md | Versioned definitions, reviewer identity, and limitations |
| cases.jsonl | Saved answers and claim/span pairs, blinded order/strategy labels |
| queries.json | Questions, reference answers/relevance, and fixed as-of time |
| source-texts.json | Complete original bodies and typed/versioned identities |
| reference-integrity.json | Literal annotation diagnostics |
| reviews-template.json | Copy and fill actual judgments without changing IDs/binding |
| manifest.json | File hashes and execution/data/prediction identity |

Give reviewers the packet directory, retaining run/freeze data privately because
it reveals strategies/history. Every prediction-bearing list shares seeded order.
Style can still hint at a strategy; label removal does not guarantee perfect blinding.
Keep packet bytes unchanged and write verdicts separately.

## Obtain independent semantic judgments

Byte-valid quotations can still fail to support the answer. Reviewers judge each
answer/abstention and every material claim/span pair using complete saved inputs,
not the generating model's self-assessment. A flag cannot prove independence.
Record actual reviewer identity/model, assistance, packet hash, notes, and omissions.

For acceptance, obtain two complete independently blinded assessments from distinct
models, each different from the predictor. Freeze both raw reviews before sharing
disagreements. A fresh blinded adjudicator resolves every disagreement; unresolved
judgments stay unmeasured. Keep raw reviews/adjudication and bind the final scorer
input to that evidence. The generic scorer validates one final review envelope;
it does not automatically prove this multi-review procedure occurred.

Publish qualification under each primary review as a sensitivity check beside
the final adjudicated scores. A selected strategy can pass under both reviewers
while the claim that it alone qualifies depends on adjudication. Preserve the
frozen selection policy; this comparison does not replace adjudicated verdicts.
If an owner resolves residual uncertainty outside the recorded review method,
label that decision as an owner resolution and method extension. Retain the
uncertainty, exact affected judgments, and its effect on completeness and gates.
The scorer counts a measured judgment only with `independent: true`; it cannot
establish independence from that flag. If a retained owner-resolution record uses
this compatibility flag, disclose the raw value and its effect on `complete_review`
and the global quality gate. The flag does not make the owner independent. Keep
new unresolved judgments unmeasured unless the recorded procedure resolves them
or the owner explicitly approves and discloses a method extension.

No fabricated template values or simple majority label replaces source inspection.
Several claims citing the same span are several pairs. Correct bytes are a
prerequisite, not a semantic verdict. Wrong project/version/coordinates cannot gain
credit from matching substrings elsewhere. A retrieval-only row has no supported-
answer measurement; actual failed answer attempts need independent unsupported
verdicts rather than disappearing.

Choose the verdict from the saved `response_kind`, then assess its content:

| Saved response kind | Permitted answer verdicts |
| --- | --- |
| `answer` | `supported`, `unsupported`, `unmeasured` |
| `abstention` | `correct_abstention`, `incorrect_abstention`, `unmeasured` |
| `retrieval_only` | `unmeasured` |

For example, an `answer` can say that the supplied records contain no founding
date. Assess whether that statement follows from the evidence and use an answer
verdict. Its cautious wording does not change the saved kind to `abstention`.
Conversely, assess a declared abstention with the abstention verdicts. The scorer
refuses an incompatible kind/verdict pair with `invalid_reviews`.

Validate this contract before freezing a review pair. If a submitted assessment
needs correction, retain its original bytes and reasons. Have each affected
reviewer reassess the cases independently, preserving every unaffected judgment,
and freeze the revised pair before comparing it. Record the correction and its
scope; never silently translate verdicts or edit predictions to satisfy the schema.

## Recompute literal integrity from original corpus bytes

`source-bytes-v1` checks full project/source/generation/typed-version/hash identity
and half-open UTF-8 span/quote. Integer `1` and string `"1"` are distinct versions.
Runner reloads the hash-verified corpus; Score validates each complete body hash
and recomputes every integrity row. Reviewer-supplied byte-valid flags cannot
make fabricated citations valid, or invalidate genuinely matching bytes.
Reference spans use the same corpus and must validate before scoring.

Raw JSONL has bounded bytes/rows/nesting/strings/collections and duplicate-key
rejection before loaders. The scorer uses Erlang JSON callback options as a map
with explicit null-to-nil; Answer uses Elixir JSON keyword options. A parser smoke
test alone does not prove these distinct admission paths.

Missing/malformed/legacy review envelopes produce `invalid_reviews`. A valid envelope
for another subject produces `review_binding_mismatch`. Both refuse before label loading
or score-directory creation. Never transplant a new binding onto old judgments.
Changed predictions/experiment need a new packet and new review; preserve old ones
as historical evidence.

## Keep all first outcomes and measurements visible

Every declared strategy/query pair remains in reports. Missing predictions become
diagnostic missing rows, not saved first outcomes. Attempt other than one or duplicate
pairs refuse; there is no best-of-several selection. Failed/partial rankings retain
observed diagnostics while primary retrieval utility is zero. No-positive-relevance
queries remain with N/A retrieval scores. Unknown measurement stays null.

| Measurement | Meaning |
| --- | --- |
| Recall@5 / nDCG@10 | Full source identity against relevance grades |
| Exact/contained span recall | Literal corpus-derived coordinates/content against annotated spans |
| Classification/confusion | Frozen class mapping, including execution failures |
| Semantic support/citation precision | Independent actual response and claim/span judgments |

An answer-policy execution failure retains response-kind answer, null answer, and
empty claims. It is still a failed first attempt, not retrieval-only. Intentional
retrieval-only plans remain separately unmeasured for answer semantics. Diagnostic
aggregate definitions and strategy-qualification denominators are not interchangeable.

## Qualify each strategy before choosing an engine

Plan three selects `per_strategy_eligibility_v1`. Its inclusive targets are:

- Answer support at least 0.90: independently supported or correct-abstention outcomes
  divided by all fifty declared first outcomes. Recorded failures count zero.
- Citation support at least 0.95: independently supported fraction of all claim/span
  pairs, with recomputed literal checks and at least one reviewed pair.

Eligible variants pass both; every weaker variant retains its gate values and
disqualification. Publish all seven strategies and all 350 rows. An eligible variant
cannot compensate for missing outcomes or unfinished reviews elsewhere.
`quality_gates_passed` additionally requires a complete distinct attempt-one grid
and complete independent review. Every actual answer/abstention needs a measured
verdict, every cited pair a measured independent judgment/literal check, and every
failed retrieval-only outcome its applicable unmeasured review entry.

The scorer chooses no engine or tie-breaker. Compare eligible choices using resource,
latency, storage, coverage, and other acceptance evidence, then record the selected
strategy/configuration and reasons. Reject below-target choices without hiding them.
[The plan](../plan.md#p27-optional-research-graph-and-rag) owns full milestone criteria.
Historical declaration-two reports retain aggregate whole-grid gates; do not
reinterpret their old quality flag as individual qualification.

## Score the final bound review

```sh
elixir dev/evaluate-knowledge.exs --phase score \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" --audit-sha256 "$IPSE_AUDIT_SHA256" \
  --data-manifest "$IPSE_DATA_MANIFEST" \
  --predictions "$IPSE_BENCHMARK/reports/predictions.jsonl" \
  --prediction-sha256 "$IPSE_PREDICTION_SHA256" \
  --labels "$IPSE_LABELS" --reviews "$IPSE_BENCHMARK/reviews.json" \
  --output "$IPSE_BENCHMARK/scores"
```

Untouched templates write unmeasured scores and exit one. Declared quality failure
also retains scores with nonzero exit, without changing input data. Legacy combined
review omits labels and retains its query-label hash; score receives its declared
reference member. V2 measured seals refuse missing/changed audit or alternate sealed
paths before reviews/labels. Exact version contracts remain explicit.

## Exercise loader order and adversarial inputs

```sh
mix test test/dev/evaluation/review_test.exs test/dev/evaluation/score_test.exs
mix test test/dev/evaluation/answer_test.exs test/extensions/knowledge/metrics_test.exs
mix test test/dev/evaluation/runner_test.exs
```

Follow raw-byte/hash mismatch, duplicate key with updated hash, duplicate pair,
attempt-two, changed answer with same ID, and changed context. None may reach labels.
Then bind a fabricated citation and mark its reviewer integrity valid: literal
checks must fail. A valid-byte control must pass despite the opposite review flag.
Corrupt corpus hash before labels, then wrong reference offset after labels. The
valid control reaches review/corpus/label loaders in order.

Qualification controls require 45 supported plus five reviewed failures to meet 0.90;
44 fails. Remove a failure review or leave a real answer unmeasured, and quality
must remain blocked. These prove scorer behavior, not actual held-out quality,
independent reviewer custody, native authority/cleanup, or installed execution.
