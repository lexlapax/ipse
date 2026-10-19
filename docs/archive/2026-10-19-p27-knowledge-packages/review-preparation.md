# Saved-prediction review preparation, 2026-10-19

Historical development-tool verification record after `a3007ee`. The containing
commit owns the review packet and quality-result changes. Follow the current
[review exercise](../../developer/knowledge-evaluation.md#prepare-independent-review-from-finalized-predictions)
for commands and expected output. This increment does not complete P27, expose
held-out inputs or supply independent semantic judgments.

## Verify the complete workload before opening references

`EvaluationScore.verified_predictions/2` shares the scorer's closed row and raw
hash validation. The public `review` phase first verifies the execution freeze,
finalized prediction hash, dataset identity and exact complete variant/query
grid. Opaque prediction IDs are required before its reference loader runs.
Only then does it parse the original corpus, questions and reference labels.

The private packet retains saved outputs, all source versions, reference answers
and as-of time. Declared strategy labels, model selections and the ordering seed
are absent. File hashes cover the versioned instructions, case and reference
banks, literal checks and initially unmeasured semantic template. The manifest
also binds execution-freeze, dataset and prediction identities. New private
output directories are required; an existing packet refuses without replacement.

Literal verification reads the original corpus independently of the saved quote.
It checks complete typed source identity, full-body hash and exact half-open UTF8
byte spans, including project identity. It does not infer semantic support or
source currency. Invalid reference spans stay visible and prevent a successful
packet CLI result. Semantic verdicts remain unmeasured and non-independent until
an actual independent reviewer supplies them. A flag cannot establish reviewer
identity or independence. Completed review is written separately, preserving the
hashed packet template and evidence.

## Preserve the controlled negatives

The scorer previously exposed only per-variant quality gates, while the score CLI
had no complete-workload gate result. A new assertion reproduced that missing
result: eight of nine scorer tests passed in 0.3 seconds, seed 283492.
The report now measures the complete frozen grid, including missing rows, against
the original 0.90 support and 0.95 citation thresholds. It retains every
per-variant gate separately. A complete-workload pass cannot select a failing
individual engine. The score CLI retains its report and exits nonzero for failed
or unmeasured aggregate gates.

The initial review, scoring, metric and public CLI/Session suites passed all
35 tests in 184.3 seconds, seed 834870. The real CLI exercised a frozen fixture,
private packet files, refused overwrite, hash-before-reference refusal and a
failing exit with an unmeasured review. A twenty-row control checks the inclusive
0.95 citation boundary, retained per-variant negatives and failure below it.

Review then found that case rows were shuffled but the semantic template and
literal list still used execution order. The strengthened ordering control
failed against that version: four of five packet tests passed in 0.4 seconds,
seed 361934. All prediction-bearing lists now use the same seeded order.
Output style can still hint at a method; label removal cannot guarantee that
inference is impossible. The controls also preserve a false claim despite exact
UTF8 quotation, reject reused typed-version/generation and foreign-project
substitutions, and retain a structurally valid wrong reference span.

The corrected combined suites passed all 36 tests in 184.2 seconds, seed 63858.
All seven changed Elixir files matched both local Elixir 1.20.3 and Elixir 1.18.5
formatting. The latter formatter ran on local OTP 29; hosted runtime verification
remains a separate receipt. No production host, domain algorithm, native helper
or packaging implementation changed. The preceding fixed-source full baseline
at `a3007ee` passed 1152 tests with both actual macOS enforcement tags; that
baseline is distinct from these development-tool checks.
Final local formatting, warnings-as-errors compilation, CI policy and the
isolated credential-free demo passed. The complete contributor chapter was
reviewed; documentation checks covered 235 files and 2590 local links without
errors.

No model inference, model download, paid service, new dependency or new agent
was used. Protocol fixtures do not establish held-out quality. The original
quality thresholds and source/model/plan freeze requirements remain unchanged.
