Historical independent review, 2026-10-20. Original report retained below unchanged.
It covers the nine-file whole-chunk-first excerpt repair against `08ecc55`,
with the stated limits. Current procedures: [knowledge training](../../developer/knowledge-extensions.md).
Replacement and acceptance status: [remediation record](index.md) and [P27 plan](../../plan.md#p27-optional-research-graph-and-rag).

# Independent review of the revised whole-chunk excerpt diff

Reviewed the current nine-file working-tree diff against `08ecc55`. Its SHA-256 at review time was `7d967bca2aabc24ab018ded1e574d4f79c99f970f795e9ff5284df4135766d01`. The earlier report reviewed a different policy and is not evidence for this verdict.

## Verdict and findings

No concrete reachable defect found in the revised selector or its caller migration. No structural blocker found. This verdict covers deterministic byte selection and the inspected protocol paths. It does not establish semantic completeness or model-answer quality.

The short-chunk branch at `extensions/knowledge/src/evidence.ex:760-766` checks the original chunk byte length and selects `{0, byte_size(text)}`. Query validation precedes that branch, so a malformed query does not bypass the existing boundary. `chunks/1` produces nonempty UTF-8 chunks from validated sources; `citation/4` independently checks the 1024-byte limit, chunk identity, exact source bytes, and UTF-8 span. Thus the shortcut retains all original text for a valid chunk of at most 1024 bytes, including text outside the query's terms. It changes no score input.

For longer chunks, the original-token grouping and two queue passes remain. The first pass finds maximal distinct normalized query-term coverage in a legal 1024-byte core; the second compares shortest, then earliest start/end (`evidence.ex:769-849`). Oversized original tokens are omitted only from excerpt coverage. BM25 still reads their normalized terms through `tokens/1`. A window with no matching whole token takes the last complete mechanical unit prefix within 1024 bytes or the UTF-8 prefix when the first unit is longer (`evidence.ex:866-879`).

The revised context priority is implemented by finding the earliest preceding unit whose start fits with the core's whole-unit hull, then taking consecutive following units while the 1024-byte bound holds (`evidence.ex:881-906`). This preserves all intervening bytes and implements previous-context priority. When the hull itself exceeds the bound, `centered_span/2` uses a 1024-byte window (`evidence.ex:912-925`). The initial window contains the core because the core is at most 1024 bytes; clamping to text edges can only move its start left or end right relative to that core. The core starts and ends at original UTF-8 token boundaries. Moving a continuation-byte start forward and end backward therefore cannot remove the core. The selected span remains contiguous and codepoint safe.

## Structural judgment

`Evidence` now has 1086 lines, up from 931 at the baseline. The threshold crossing deserves review. I would waive it here for a concrete ownership reason: the added selector is one contiguous operation beside candidate construction; it shares `token_offsets/1` with BM25 and finishes through Evidence's authoritative `citation/4`. Corpus's old dense-specific prefix policy is removed. A standalone selector file would either duplicate normalization or require another public text-index interface and artifact/test-loader wiring. Moving both tokenization and the selector into a text module is the only coherent extraction I see; it moves the two-pass algorithm rather than deleting its complexity. The new complete-chunk shortcut also avoids all token, unit, and queue work for small chunks. No further behavior-preserving deletion is apparent from the current paths.

The normalized-token rows are regrouped by original source span inside `excerpt/3`; a future tokenizer record shaped around original tokens could remove this regrouping. That change would also touch BM25's term stream. With only these two consumers, it is not a current blocker. The new short/long branch belongs at the excerpt boundary and does not add retriever-specific flags or branches.

## Callers, identity, and documentation

Corpus passes its already validated query to remote selection and dense candidates (`corpus.ex:260-267,424-430,565-599`); lexical ranking passes the raw query to `candidate/5`, and Research still enters through lexical ranking (`evidence.ex:223-264`, `research.ex:327`). A repository-wide `rg` found no direct `rank_remote/4` caller. `extensions/knowledge/build.exs` compiles the same Evidence helper for independently selected SDK-2 knowledge artifacts. Graph's exact fact-support citations still use the existing citation path. `order/1` remains score, span key, scope key; `fuse/3` still uses scoped chunk identity; `candidate_id/1` still binds the final span. Bounds can legitimately change span-sensitive ties and component ranks. The adapter's 128-byte rerank view and Answer's saved-citation packing remain separate downstream limits.

I searched the current operator/developer manuals and `extensions/knowledge/README.md` for old 200-grapheme, 512-byte, first-match, and one-neighbor claims. The changed manual sections describe whole chunks, long-chunk cropping, earlier-context priority, source-byte identity, and limitations consistently. The documentation check found no broken local targets.

## Commands and limits

- `git diff 08ecc55 --` all nine modified paths; `git status --short --branch`; `wc -l extensions/knowledge/src/evidence.ex`; source/caller and manual searches with `rg -n`; and read-only inspection of Evidence, Corpus, Research, Adapters, Answer preparation, artifact build specification, and affected manual sections.
- `mix test test/knowledge_evidence_test.exs test/knowledge_packages_test.exs test/knowledge_domain_regressions_test.exs` exited 0 with 31 outer tests passed. Some outer tests execute embedded suites in isolated VMs, so 31 is not their internal assertion count. The revised controls include a full four-sentence short chunk, explicit omissions on oversized chunks, original Unicode coordinates, an exhaustive sampled-window oracle, and encoded Answer packing.
- `elixir scripts/check-docs.exs` exited 0: 290 Markdown files and 2991 local links, zero errors. `git diff --check 08ecc55` exited 0.

I did not run an SDK artifact build, full suite, platform proof, package launch, inference, external service, measurement replay, or private workload. The earlier partial Mac/Linux proofs are not passing receipts. The reported exposed-data containment diagnostic is not a quality test oracle. No repository file was edited for this review.
