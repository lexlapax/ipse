Historical review, 2026-10-20. Original report body retained below. See the [investigation and scope](index.md) and [current contributor manual](../../developer/knowledge-extensions.md).

# Independent P27 compact-contract review

## Findings

No new actionable findings.

## Coverage and evidence

- Reviewed the working-tree diff against `aa335089b007f45113f6b5bbc788ffa3d97923a5`, the compact extraction/rerank adapter, graph publication and Store validation, Corpus/Research rerank application, answer packing/decoding, evaluation approval, prediction projection/scoring, changed tests and relevant operator/developer text.
- The frozen manifest's SHA256 is `e8eca68dba146c8d95012a6fce5427e2ff91ecbda8f6e8495af9b4ef886aef87`. All nine changed non-documentation files matched their entries in it at review time.
- Extraction's short chunk ID is resolved against the selected chunks in the retained adapter arguments. Exact quote matching rejects absent or overlapping repeated matches; `Evidence.citation/4` and `valid_span?/2` recheck original source bytes, chunk bounds and provenance before Store publication. Invalid proposals reject the whole model output. The generic host call retains request/operation binding.
- Rerank maps a complete unique short-ID permutation back to canonical candidate IDs. Corpus and Research then apply it to the retained candidate set; duplicate canonical IDs cannot silently select another candidate because `Evidence.apply_rerank/2` rejects a non-unique candidate map.
- Answer preparation retains whole admitted citations, fits the longest rank prefix by encoded request bytes, records omitted original ranks, and rejects answers citing unseen IDs. The runner stores full retrieval spans independently; answer `context_evidence` is populated from cited spans only, as the documentation now says.
- No test or model run was started in this review. The brief reports focused checks; I did not treat its running broader integration as passed.

## Declared limitations, not new findings

- Dense citations remain bounded to the first 200 characters; lexical retrieval begins with the first query token; rerank sees at most a 128-byte prefix of each candidate. These constrain model quality and are openly documented.
- The benchmark's one-fact-per-chunk setup and EvaluationAuthor's narrow first-fact pattern cannot establish broader semantic quality. Existing exposed questions are tuning data only; the independent held-out set remains sealed.
- Rank-prefix answer packing can omit a later short or contradictory candidate after a larger earlier one. Coverage records this but does not assert semantic completeness. A zero-fit answer context is also explicitly distinguishable from empty retrieval.
- The real model/resource/held-out/selection work and whole-manual structural completion gates remain open. This review makes no quality or milestone-completion claim.
