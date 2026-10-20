Historical review, 2026-10-20. Original report body retained below. See the [investigation and scope](index.md) and [current contributor manual](../../developer/knowledge-extensions.md).

# Independent compact-contract review A

## Findings

No new actionable findings in the frozen compact extraction/rerank and answer-preparation changes, including the surrounding ownership and publication paths reviewed below.

This is a bounded code review, not P27 acceptance. The open quality, resource, independent held-out, selection and whole-codebase/all-manual structural gates remain open.

## Source identity

- Repository HEAD was `aa335089b007f45113f6b5bbc788ffa3d97923a5`.
- `/tmp/ipse-p27-quality-contract-source-before.json` has SHA256 `e8eca68dba146c8d95012a6fce5427e2ff91ecbda8f6e8495af9b4ef886aef87` and 460 entries.
- I computed SHA256 from the current files and found zero mismatches across every non-documentation entry. Documentation edits were permitted by the brief and reviewed as the current diff.
- No repository files, Git state, datasets or other review reports were modified or inspected beyond the authorized source/docs/test scope.

## Coverage and conclusions

I read the diff against the stated HEAD, the reviewer instructions/rubric/quality lens, and relevant implementation around each modified boundary.

| Boundary | Concrete checks |
| --- | --- |
| Extraction input and model proposal | Short chunk IDs are deterministic from selection order. Old offset grammar has no compatibility branch. Exact keys, polarity, selected chunk, unique exact quote, fact count and nested duplicate JSON keys are checked. Every proposal must convert before any facts are returned. |
| Byte attribution | `quote_span/2` looks for a second occurrence starting one byte after the first, so overlapping matches count. Positions are chunk-local UTF8 byte offsets converted to source offsets. `Evidence.citation/4` reconstructs the source quote, the adapter compares it to the proposal, and canonical source/span validation runs before returning facts. A forged chunk text probe could not move attribution. |
| Publication and eligibility | Traced Graph's open/adapter/commit sequence, Store's current-draft projection validation and selected-chunk checks, and query-time fact eligibility. The compact model contract does not create another write path or replace current source validation. Failure leaves the existing draft/recovery flow in charge. |
| Rerank | A complete unique short-ID permutation maps through the original ordered candidates to canonical excerpt IDs. Corpus/Research still call `Evidence.apply_rerank/2` and retain their existing revalidation/publication paths. UTF8 prefix truncation remains exact. |
| Independent approval | Evaluation approval checks the fixed instruction, selected profile, limits, exact extraction input and selection order. Rerank approval checks deterministic short IDs, unique canonical references, current eligible chunks, canonical numeric ref syntax, source span bounds and the exact 128-byte UTF8 prefix. |
| Response identity | Host `Operation` dispatch still uses `ModelCall.valid_outcome?/4`; source validation binds operation, parent invocation, identity, request hash, execution and admission. Successful model outcomes bind `request_id` to the operation. The new local IDs do not substitute for that host binding. |
| Answer formatter | Traced candidate validation, full citation retention, deterministic exact encoding, longest-prefix admission, omitted ID/rank coverage, strict shown-span mapping, runner prediction construction and scorer containment checks. Empty retrieval and zero-fit nonempty retrieval remain distinguishable. |
| Migration and claims | Reviewed updated production consumers, lifecycle/model fixtures, extraction/rerank tests and answer tests. Searched current non-archive files for old instructions and 512-byte answer-cropping descriptions; found no old model grammar caller. Reviewed the edited manual passages, their surrounding sections, indexes and P27 status. Current prose distinguishes cited spans from all shown passages and preserves the quality/selection gates. |
| Structural quality | The adapter remains one closed protocol boundary, at 805 lines. The answer helper shrinks to 350 lines. New alias/matching logic is local to the existing adapter rather than distributed across host layers. The runner was already over 1000 lines; this diff does not introduce a new threshold crossing or justify a speculative refactor during this contract repair. |

The new probes exercised a one-byte quote at the end of a chunk, overlapping repeated quotes, whole-output refusal with mixed valid/invalid facts, nested duplicate fields, exact tabs/CRLF/supplementary Unicode with absolute byte positions, forged selected-chunk text, malformed rerank IDs and extra keys, UTF8 rerank prefix truncation, and escaped answer input budgeting with exact citation round-trip.

## Verification actually run

`elixir /tmp/ipse-p27-compact-review-a/probes.exs` completed with **6 passed**. The script loads only the current Evidence, Profiles, Adapters and pure EvaluationAnswer modules. It uses synthetic values and direct fixture responses; it starts no model/network request and performs no measurement work.

Probe source and output are retained only under `/tmp/ipse-p27-compact-review-a/`. I did not run broad builds, tests, packages, installed proofs or platform jobs. I did not inspect the running broader integration terminal and make no claim about its eventual result.

## Already-declared limits, not new findings

- Exact source bytes establish attribution, not whether a proposed relationship or answer is semantically supported.
- Extraction can refuse repetitive material without a unique supporting quote. There is no automatic repair call.
- Dense first-200-grapheme excerpts, lexical first-token windows and rerank 128-byte prefixes can omit qualifications upstream.
- Prefix answer packing may omit contradictions and later candidates that would individually fit. It preserves each admitted citation, not the entire source or every relevant proposition.
- `context_evidence` records answer-cited spans. The runner separately records answer-context coverage; the prediction field is not a visibility measure.
- The benchmark's one-fact-per-chunk preparation and narrow explicit-fact author remain limitations.
- These six synthetic probes establish none of model quality, resource quality, untouched held-out readiness, engine selection, installed behavior or all-manual structural readiness.
