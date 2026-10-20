# Saved comparison quality result

Historical evaluation record, 2026-10-20. This evaluates the first saved outputs
from predictor `914bc0ad7fd1794e0c9855a20d4548b961c309f4`, admitted through the
[original-first historical reader](index.md). It is a failed quality comparison,
not P27 acceptance or corrected-source quality evidence.

Current methodology is taught in [knowledge evaluation](../../developer/knowledge-evaluation.md).
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns remaining work.
The [sanitized score summary](score-summary.json) retains metric counts and
identities. Private predictions, source text, reference answers, per-case notes
and the full score report remain outside version control.

## Independent judgment and unchanged scoring

Ten fresh internal reviewers each judged five questions across seven saved
predictions, 35 rows per reviewer. Each received only the hash-verified blinded
packet and a lossless query-filter helper. They did not receive strategy names,
the private plan, implementation, transcripts or another reviewer's judgments.
This is disjoint coverage, not duplicate panel grading or external assurance.
Actual agent identities and per-prediction reasons are retained privately. The
host did not expose exact reviewer model identifiers.

The assembly check validated all 350 unique prediction IDs, every citation-ID
set, permissible verdicts for each saved response kind, actual reviewer IDs and
the protocol-two binding. It retained the template's original literal-integrity
rows and rechecked every original packet-file hash. No row was dropped, retried,
regenerated or reclassified to turn an incomplete answer into retrieval-only.

The accepted historical reader then performed the original native audit first,
verified strict current-byte joins and scored the assembled reviews using the
existing checker and unchanged 0.90/0.95 thresholds. It made zero new model or
measurement calls. Scoring completed with exit one because the quality gates did
not pass. This exit is a retained negative result, not an execution failure.

| Identity | SHA256 |
| --- | --- |
| First merged predictions | `7209541ad95978f02daf42834a05e066b9d29c5f1b1cd33ba78179da4c582ef6` |
| Blinded packet | `679b1c753280167b8943dc359c07852fe9eb5730d56b023a4d8b25356ee631c2` |
| Review binding | `5582e72de4e188cfaaae8a4a59157683283d975adf574b082de09ff1ff513213` |
| Assembled reviews | `4af870e8439c295693786a73e7440da65f29c6c67f1b52281f0b9189094011bd` |
| Complete private score report | `ee2a5537e7d30c4bb53e5b8eca7ae2267e0589e80c748379d90d8cd900b9786c` |

## Results include failures and uncertainty

Support accuracy is **98/350, or 28%**, against a 90% threshold. Reviewers marked
97 answers supported and one abstention correct. The other 252 rows comprise
251 unsupported answers and one incorrect abstention. All 350 support judgments
are measured. The population includes 128 non-OK executions: 77 failed, 50 partial
and one refused. Eighteen additional answer rows have OK status but empty prose;
protocol completion does not make those successful answers.

Of 587 citation pairs, 423 are supported, 160 unsupported and four unmeasured.
Measured-pair precision is 423/583, about 72.6%. Full-population citation precision
remains null and its gate remains `unmeasured`. Three incomplete claims and one
interrogative prevent their reviewers from making those four pair judgments.
Their literal attribution is intact. The reviewers did not invent missing text
or treat matching bytes as entailment.

Each variant has fifty rows. Counts below retain failures in the support
denominator. Citation fractions exclude only explicitly unmeasured pairs and
are not complete precision when the last column is nonzero.

| Variant | Supported outcomes | Support accuracy | Supported/measured citation pairs | Unmeasured pairs |
| --- | --- | --- | --- | --- |
| Lexical | 25/50 | 50% | 98/112 | 2 |
| Explicit Graph | 19/50 | 38% | 88/103 | 1 |
| Model Graph | 0/50 | 0% | No pairs | 0 |
| Dense | 12/50 | 24% | 62/154 | 1 |
| Hybrid | 21/50 | 42% | 93/112 | 0 |
| Rerank | 0/50 | 0% | No pairs | 0 |
| Research | 21/50 | 42% | 82/102 | 0 |

No variant reaches the support threshold. The aggregate quality result is false;
the comparison selects no engine. The reader's `quality_measured: true` records
that independent reviews were supplied. The citation metric's own `complete`,
`unmeasured_n` and `precision` fields retain its narrower measurement limit.

## Diagnosis started from saved evidence

The model Graph variant retains partial preparation and fifty partial prediction
rows. Rerank retains 49 failed rows and one refused row. Saved receipts show nine
Graph extraction calls and 49 rerank queries without a completed invocation
result. Their elapsed times cluster near the existing 120-second complete-result
deadline. Eight other extraction replies and one rerank reply explicitly report
`invalid_model_output`. Timing is consistent with deadline loss; the exact
terminal cause still needs journal tracing before assigning a code defect.

Other failures occur after retrieval succeeds. Lexical source recall@5 is about
88.9%, while support accuracy is 50%. Reviews identify incorrect inability claims,
unsupported causal or authority claims, changed subjects, and exact cited spans
that omit part of a compound claim. The answer helper's fixed 4 KiB input and
quotation cropping are visible in its saved context receipts. These observations
identify investigation targets, not a proven repair or permission to alter this
experiment's inputs, outputs, deadlines or grading rules.

These exposed inputs and judgments are now diagnostic material. Any later tuning
or regression exercise must identify their reuse. Corrected-source matched
comparison, a fresh untouched held-out workload, remaining lifecycle acceptance
and independent external whole-P27 review remain open.
