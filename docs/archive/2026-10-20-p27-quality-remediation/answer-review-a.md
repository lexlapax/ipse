Historical independent review, 2026-10-20. Original report retained below unchanged.
It reviews the six-file answer-contract repair against `98d61f5`, with the stated
coverage limits. Current procedures: [evaluation training](../../developer/knowledge-evaluation.md).
Replacement and acceptance status: [remediation record](index.md) and [P27 plan](../../plan.md#p27-optional-research-graph-and-rag).

# Answer contract review A

## Findings

No critical, warning or nit findings in the current uncommitted diff against HEAD `98d61f56c5c310cbbc1ed50f4e769abbaaaad6ce`.

## Evidence checked

- Read the full review brief and candidate-A/synthesis rationale, then inspected the actual six-file diff. The rationale was treated as intent, not correctness evidence.
- Read `examples/knowledge/evaluation_answer.exs` completely. The exact two-key wire contract is validated before derivation. Empty `answer` and `conflict` are refused, `abstain` requires empty claims, and no shown candidates requires `abstain`. Empty `open` and `abstain` receive only the documented fixed strings. Nonempty text is copied directly from validated claims with one LF between claims; classification is retained rather than repaired.
- Traced `EvaluationRunner.predict/6` into `decode_answer/2` and `answer_prediction/5`. The mapper consumes the unchanged mapped citation entries, keeps claim array order, assigns distinct claim/pair IDs and deduplicates only the context span. Its invalid-response branch keeps the existing failed row and has no retry/fallback. Read the focused runner fixture and its assertions, including the two actual requests and canonical budget count.
- Searched the repository for `candidate_ids`, with no remaining occurrences. The removed mapped duplicate has no caller. The wire's `citations` list and returned `citations` association entries remain present.
- Checked strict top-level and nested keys, duplicate-key callbacks, omitted/unknown and repeated IDs, Unicode preservation, decoded claim limits and serialized raw limits. The material body has a separate historical 8192-byte guard. Preparation, evidence identity checks, packing and all request settings are unchanged.
- Read the existing Score, Review, Integrity and Metrics consumer contracts around answer/body limits, failed rows, span identity, pair binding and semantic verdicts. These files are unchanged. Existing saved prediction-v2 rows remain admissible without requiring joined answer/claim equality.
- Read the whole developer knowledge-evaluation chapter in chunks, especially the integrated answer-evidence explanation and worked release-condition example. Its live wire, derived prose, empty decisions, unchanged saved format, pair identity and independent semantic-review limitations agree with the implementation. The chapter does not claim model quality from synthetic protocol tests.
- Applied the strict code-quality lens. This change removes the second authored answer and the unused citation-ID copy in the owning boundary. The three direct `material_answer/1` clauses are a small, local expression of the accepted contract. I found no justified further structural decomposition or complexity deletion that would warrant blocking this repair. No changed file crosses from fewer than 1000 lines to more than 1000 lines; the large runner test and manual were already over that size.

## Commands and outcomes

Read-only inspection used `git status --short`, `git rev-parse HEAD`, `git diff --stat`, `git diff --` for every changed path, `cat`, `sed`, `wc -l`, `rg -n` and `rg --files` on the named implementation, tests, manuals and retained design/log artifacts.

Executed checks:

1. `git diff --check` passed.
2. `elixir -e 'ExUnit.start(); Code.require_file("test/knowledge_evaluation_answer_test.exs")'` passed all 12 decoder tests.
3. An initial direct invocation of the Score and Metrics tests omitted the application code path. It emitted undefined-Manifest warnings and returned 17/27 passing tests, with ten `scoring_failed` errors. This was a reviewer invocation error, not a product finding. The corrected invocation below loads the existing BEAM paths without compiling or mutating repository files.
4. `elixir -pa _build/test/lib/ipse/ebin -pa _build/test/lib/jason/ebin -e 'ExUnit.start(); Code.require_file("test/knowledge_evaluation_score_test.exs"); Code.require_file("test/knowledge_evaluation_review_test.exs"); Code.require_file("test/knowledge_metrics_test.exs")'` passed all 33 tests.
5. `elixir scripts/check-docs.exs` passed, checking 287 Markdown files, 2969 local links and manual/archive rules with zero errors.

Also inspected the retained red, green-c2 and runner-c1 logs. They show the expected initial `invalid_answer_shape` failure, 15 passing decoder/fixture tests and one passing focused runner test respectively. Those logs overlap and do not constitute full-suite or real-model evidence.

## Limits

No repository source, fixture, documentation or Git state was changed. Only this report was written. No real model request, model service, SSH, package replay, measured population or private workload access occurred. I did not rerun the runner's worker/HTTP integration or the measured fixture suite, and I did not execute the full build/test baseline. Historical consumer tests used the existing application/Jason BEAM paths for their helper dependencies. The repair's output conformance cannot prove entailment, classification quality, completeness, claim coherence, exact RAM, engine selection or P27 completion.
