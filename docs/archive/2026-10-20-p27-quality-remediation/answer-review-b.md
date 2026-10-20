Historical independent review, 2026-10-20. Original report retained below unchanged.
It reviews the six-file answer-contract repair against `98d61f5`, with the stated
coverage limits. Current procedures: [evaluation training](../../developer/knowledge-evaluation.md).
Replacement and acceptance status: [remediation record](index.md) and [P27 plan](../../plan.md#p27-optional-research-graph-and-rag).

# P27 answer-contract adversarial review B

## Findings

No critical, warning, or nit finding. The uncommitted change is narrow and consistent with the stated contract. I found no concrete reachable bug or structural code-quality regression that warrants a change before this increment is reviewed.

## Evidence

- The full diff against `98d61f5` changes the decoder, raw synthetic responses, focused tests, and the developer chapter. Production `evaluation_runner.exs` is unchanged. `decode_answer/2` checks the bundle, parses one bounded JSON value with duplicate-key refusal, validates the exact two-key response and nested claim shape, derives nonempty material text from the original ordered claim texts, and maps each shown ID to the prepared citation. Empty `open` and `abstain` use only the fixed strings; empty `answer`/`conflict` and non-abstain with zero shown candidates refuse.
- The unchanged `predict/6` invokes Answer once and marks decoding failure on the existing first row without retry. `answer_prediction/5` assigns ordered `cN` claim IDs, `a-eN` cited-context IDs, and distinct `pairN-M` associations. Repeated citation of one span stores one context span and preserves both claim pairs. Retrieval evidence is populated independently before answer decoding.
- The unchanged version-two scorer validates saved `answer`, `claims`, `context_evidence`, and `citations`; Review and Integrity continue reading those same fields. Repository search found no `candidate_ids` consumer outside the removed field. There is no parallel wire interpretation or compatibility branch.
- The added tests cover classification-independent nonempty text, empty class cardinalities, raw and decoded byte limits, Unicode and escaping, nested duplicate keys, omitted/unknown IDs, repeated claims, and the runner mapping/failure path. The provided red and green logs show the intended before/after decoder failure and success, and one focused local runner integration pass. I inspected the assertions rather than treating the pass counts as quality evidence.
- The changed module remains 353 lines, and the new `material_answer/1` is a direct three-clause implementation in the canonical decoder. No new dependency, layer, cross-module feature switch, or file-size threshold crossing appears. The developer answer-tracing section describes the live two-key wire and separate version-two saved row accurately; its worked citation example is internally consistent.

## Checks and limits

Read-only commands: `cat` of the brief, decoder and design notes; `git status --short`; `git diff --stat 98d61f5`; `git diff` for all changed paths; `wc -l`; targeted `sed` reads of the runner, score, review, integrity, tests, chapter and plan; `rg` searches for callers, saved fields, old wire references and `candidate_ids`; and `sed` inspection of the supplied red/green logs. I did not run tests, compile, alter repository files, make model requests, replay measurements, use SSH, or access private datasets. The supplied logs cover overlapping fixtures, not the full suite or real-model semantic quality. A new independent held-out workload and real quality/engine measurements remain open by design.
