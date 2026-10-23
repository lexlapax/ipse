# P27 held-out outcomes and independent review

Historical evaluation record, dated 2026-10-23. The measured implementation is
`817ab84944c347f76e297efaad313b1ec841ee91`. Final consolidated-code checks use
`b81f68fc4fa2d670348b85705fde3424aa1edcc4`; they do not change the measured version.
Use the [Corpus user manual](../../operator/corpus.md),
[evaluation training](../../developer/knowledge-evaluation.md), and
[scoring training](../../developer/knowledge-scoring.md) for current procedures.
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns milestone status.
The [whole-chapter editorial review](editorial-review.md) reported no actionable
issues at publication. Subsequent reviews identified the corrections noted below.

Correction note, 2026-10-23: `4171fb4` corrected the `a7f4982` publication's claims
about independent owner judgment and hybrid being the sole qualifying strategy.
The current follow-up additionally identifies the raw owner-resolution flag,
the measured artifact preset and placement policy. These are corrections to the
narrative; the bundle, manifest, receipts, final platform and original editorial
records retain their published bytes and original scope.

## Result and remaining acceptance

All 350 first outcomes and the joined execution/resource audit completed. Six
first outcomes failed and remain in every strategy denominator. Hybrid is the
only individually qualifying strategy in the final report: 46/50 supported
answers and 79/83 supported citation pairs. All 350 outcomes and 635 citations
have complete review as counted by the original scorer, which reports
`quality_gates_passed: true`. Final support is independently resolved for 349
outcomes and 634 citation pairs. One rerank case uses the owner's resolution,
whose raw record has `independent: true` despite not being an independent judgment.
The scorer requires that flag to count it, so `complete_review` and the global
quality gate depend on this disclosed method extension. Hybrid's scores and every
strategy's qualification are unchanged by the owner resolution.
Select the Corpus State-store hybrid configuration described below as the P27
reference path. Final platform controls, whole-manual review and the
[requirement-by-requirement acceptance audit](acceptance-audit.md) pass.
The [final platform receipts](final-platforms.json) separately bind the verified
consolidated runtime and package. P27 is complete within that recorded scope.

The [immutable evidence bundle](evidence.tar.gz) contains the original
350 predictions, all six merged result streams, workload and released references,
frozen configuration, native audit, resource summaries, all original assessments,
their bounded protocol corrections, adjudication, separate human resolution and
both the incomplete and complete scorer reports.
Its [inventory](evidence-manifest.json) records each member's original bytes and
SHA256; the [bundle receipt](bundle-receipt.json) records the archive hash and a complete
extraction/hash round trip. It contains data and review records, no model weights
or compiled runtime. This workload is now exposed and cannot be reused as new
held-out acceptance data.

Extract using OTP, without an additional archive dependency:

```sh
elixir -e '
[archive, destination] = System.argv()
File.mkdir!(destination)
:ok = :erl_tar.extract(String.to_charlist(archive),
  [:compressed, {:cwd, String.to_charlist(destination)}])
' docs/archive/2026-10-23-p27-heldout-comparison/evidence.tar.gz /tmp/ipse-p27-results
```

Choose a fresh destination. Inside it, `comparison/predictions.jsonl` contains
exactly 350 attempt-one rows. `comparison/scores-final.json` contains every
strategy and per-question metric, including failures. The earlier
`comparison/scores-model-adjudicated-r2.json` retains its incomplete-review result.

## Frozen workload and execution

The independently authored workload has 50 questions across two synthetic
projects and 22 source documents. Its metadata commitment preceded predictor
access. References were released only after both public measure/audit phases
closed successfully, the complete native audit passed, and the original retained
four-stage observation prefix matched. The unchanged release guard authorized
the committed answer bytes at `2026-10-23T07:05:52Z`.

| Identity | SHA256 |
| --- | --- |
| Measured freeze | `e142cf44a0c257f85cfc30bddba6de645a6de7e8f64ccc9a7586ad37aef407fb` |
| All 350 predictions | `3f4f3f9f8e2d258dfc20c5dfcc858af4467126b669dca674f47c95e0e7e7503e` |
| Joined native audit | `40fde78363eda9a13e789cdc92057507707ceda5686f82ee09cfac37d32a807e` |
| Released answers | `b7e447233b095561a991e08a04b57c62f22533d724836be96089ba697da05980` |
| Official blinded packet | `204328d532e1ce3d222e2c84435bb751877a7947504d6bcbcacf16a938224b99` |

Every strategy used the pinned `qwen3.5:9b` final-answer model with reasoning,
8192 output tokens, a 600-second answer deadline and 16384-token context.
Extraction and reranking used the same model without reasoning and retained
their two-minute contracts. Embeddings used pinned `embeddinggemma:latest`.
The selected execution policy used fresh private model-service populations and
explicit NVIDIA visibility. Existing shared services were not benchmark workers.
The finite service allowance was 24 hours per cell; natural execution took about
19 hours 39 minutes. These are distinct limits and observations.

## Independent semantic review

The [pre-release method](../2026-10-22-p27-semantic-review-policy/index.md) required
two independently blinded assessments and separate adjudication. Fresh contexts
configured as `gpt-6-astra` and `gpt-6-sol` each assessed all 350 cases and 635
citations. The host accepted explicit model overrides; no separate backend-model
attestation was returned. Neither received predictor context, strategy mapping,
or the other assessment. Their complete original files were frozen before
differences were calculated.

Thirty cases differed. A fresh context configured as `gpt-6.1-sol` assessed those
cases and all 85 associated citations, receiving anonymous paired reasons and
the original evidence. Agreement retains the first reviewer's actual record;
disagreement uses the adjudicator's complete case record and identity. These are
model assessments of supplied evidence, not human review or external truth proof.

The first score invocation refused `invalid_reviews`: six answer-kind records
had abstention verdicts. Both original reviewers independently reassessed those
six cases under the existing response-kind contract. Every other 344 record and
its notes remained unchanged. Originals were preserved, and both corrected full
assessments were frozen before differences were recalculated. The 30-case target
and all its paired inputs were unchanged, so the actual frozen adjudication was
reused with explicit parent-link provenance. No new verdict was fabricated and
no prediction, reference, threshold or runtime changed. A causal custody regression
now rejects that incompatible kind/verdict pair; all six custody tests pass.

The original captured scorer accepted the corrected schema, recomputed literal
integrity, wrote the report and exited one because review was incomplete. One
relative clause could describe either a booked survey or an unproved drill status.
The project owner judged the clause as referring to the survey and therefore
supported. This owner resolution extends the pre-registered method, which left
unresolved judgments unmeasured; it is not another independent blinded review.
That separate human judgment resolves only the remaining
answer/citation uncertainty; the first claim's existing model support and every
other case remain unchanged. All model assessments, including the uncertainty,
are retained. The final scorer invocation exited zero with complete review.
The resolution changes rerank's answer support and one citation pair, and closes
review completeness. It changes neither hybrid's scores nor any strategy's
qualification. The six earlier corrections changed verdict labels to match saved
response kinds; they changed no numeric score.

## Quality comparison

Targets were fixed before release: answer support at least 90% of all 50 first
outcomes per strategy and citation support at least 95% of all associated pairs.
All literal citation checks passed. Literal copying alone did not earn semantic
credit. Classification is reported separately from answer support.

| Strategy | Supported answers | Supported citations | Classification accuracy | Current qualification |
| --- | --- | --- | --- | --- |
| Lexical | 48/50, 96% | 88/96, 91.67% | 90% | Citation target failed |
| Explicit graph | 45/50, 90% | 91/101, 90.10% | 84% | Citation target failed |
| Model graph | 45/50, 90% | 82/93, 88.17% | 78% | Citation target failed |
| Dense | 42/50, 84% | 71/76, 93.42% | 78% | Both targets failed |
| Hybrid | 46/50, 92% | 79/83, 95.18% | 78% | Both targets passed |
| Rerank | 44/50, 88% | 84/91, 92.31% | 76% | Both targets failed |
| Research | 44/50, 88% | 85/95, 89.47% | 86% | Both targets failed |

Hybrid meets the citation target narrowly: changing one supported pair to
unsupported would put it below 95%. This single workload establishes no general
quality guarantee. Aggregate answer support is 314/350, 89.71%, and aggregate
citation support is 580/635, 91.34%. They do not pass aggregate targets. The frozen
policy qualifies individual strategies and additionally requires complete review
of the whole grid; it does not require or use aggregate success for selection.
The complete report also retains recall@5, nDCG@10, annotated span coverage,
classification confusion, paired comparisons, and every per-question outcome.

## Select the reference configuration

Choose Corpus with a project-scoped State store, BM25 plus native dense embedding
retrieval, reciprocal rank fusion with `rrf_k: 60`, no graph contribution and no
reranker. Use `embeddinggemma:latest`, native 768 dimensions, and
`missing_embedding: "refuse"`. The measured query used `top_k: 10` and retrieval
binding `combined`; the user manual's equivalent worked configuration names it
`blend`. The measured artifact uses `state-dense` with an empty `rerank` registry.
The `state-semantic` alternative adds unused `host.model` authority and was not
the measured build. This decision adds no database, default network call or
automatic provider switch.

Hybrid is the only strategy meeting both targets under the final adjudicated
scores. Lexical had higher answer
support and fewer model requests, but failed citation support. The graph, dense,
rerank and Research variants also fail at least one target and are rejected for
this reference choice. Adding rerank increases requests without qualifying quality.
Hybrid retains two failed first outcomes and higher observed request/storage
cost than lexical; the quality gate does not erase those tradeoffs.

The [subsequent independent review](../2026-10-23-p27-independent-review/index.md#n3-the-reference-selection-depends-on-adjudication)
identified material sensitivity to reviewer disagreement. Recomputing each
primary assessment separately gives these supported-answer and citation counts:

| Strategy | Reviewer A alone | Reviewer B alone | Final adjudicated scores |
| --- | --- | --- | --- |
| Hybrid | 46/50; 79/83, qualifies | 46/50; 83/83, qualifies | 46/50; 79/83, qualifies |
| Lexical | 48/50; 86/96, fails | 49/50; 92/96, qualifies | 48/50; 88/96, fails |
| Rerank | 43/50; 83/91, fails | 45/50; 87/91, qualifies | 44/50; 84/91, fails |

Thus hybrid qualifies under either primary review, but the claim that it alone
qualifies depends on adjudication. All four unsupported hybrid citation pairs
were disputed and resolved in reviewer A's direction. Adjudication followed the
recorded procedure; review completeness additionally uses the owner resolution
disclosed above. The result does not establish a reviewer-independent ranking.

The answer-side result applies to the frozen 9B final-answer policy, not arbitrary
providers or corpora. Corpus query itself returns evidence and does not silently
enable that answer helper. Operator-controlled alternatives remain available for
other tasks, and credential-free lexical search remains supported.

## Matched resources and limits

Query latency includes retrieval and final-answer work, including observed failed
outcomes. Quantiles use nearest rank over all 50 queries. Request counts include
answer, preparation, embedding and rerank model requests as applicable. Canonical
accounting and both project budget snapshots reconcile; no request remains
unattributed or unsettled. Local inference is unpriced, not measured zero cost.

| Strategy | Failed first outcomes | Query median / p95, seconds | Model requests | Fresh cell charged-RAM peaks, GiB, project one / two |
| --- | --- | --- | --- | --- |
| Lexical | 0 | 185.4 / 327.2 | 50 | 13.11 / 15.48 |
| Explicit graph | 0 | 198.9 / 378.8 | 50 | 16.88 / 11.02 |
| Model graph | 1 | 191.7 / 306.3 | 70 | 13.11 / 20.34 |
| Dense | 3 | 194.4 / 369.9 | 120 | 12.74 / 16.55 |
| Hybrid | 2 | 198.6 / 342.1 | 120 | 13.43 / 17.43 |
| Rerank | 0 | 198.3 / 319.1 | 170 | 20.99 / 18.28 |
| Research | 0 | 191.0 / 331.8 | 50 | 16.89 / 18.39 |

The kernel metric is `linux_memcg_charged_peak_bytes_v1`. It includes charged RAM,
page cache and kernel allocations; it is neither process RSS nor GPU VRAM. Each
table value is an exact lifetime peak of one fresh project/strategy cell. Do not
sum those peaks. The separate whole-experiment peak is 37,449,637,888 bytes,
about 34.88 GiB. Parent interval peaks can include retained charge from earlier
cells and are retained separately in the audit.

The resource record contains both projects' state-file, artifact, journal/budget,
reachability and post-collection measurements for every strategy. For hybrid,
state files after preparation were 112,191 and 111,354 bytes. After the declared
forget-and-collect policy they were 16,730 bytes each, retaining suppression
metadata. Journals and budget files remained separate, about 11.9 MB per project;
collection is not a claim of journal erasure. Research has no retained state
store, recorded as not applicable rather than an invented zero-byte measurement.

The placement policy is `nvidia_visible_mixed_v1`, with partial model residency on
an 8 GiB GPU and remaining work on CPU. This mixed placement affects latency;
the results are not an all-GPU or CPU-only comparison.
This is one fixed-order, two-project comparison on one host. Fresh cell identities
do not establish identical hardware/cache scheduling, repeated-trial confidence,
exact process-resident memory, peak VRAM or a general engine ranking. The Linux
measurement backend remains optional and imposes no host requirement on ordinary
Ipse use. Final consolidated-code correctness receipts remain separately versioned.
