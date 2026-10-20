Historical review record, 2026-10-20. Original report and correction scope are described in [the record index](index.md). Current procedures belong to [the evaluation manual](../../developer/knowledge-evaluation.md). This review does not establish P27 completion.

# Independent sealed-answer implementation review

Read-only review of the supplied patch and current affected sources, including the complete `docs/developer/knowledge-evaluation.md` chapter and the untracked author script. I made no repository edits and ran no builds, tests, models, services, or private workloads. The author corrected two findings while this review was in progress; their status is recorded below.

## Open finding

### 1. [warning] The authoring chapter points to a corpus schema it does not provide
**Location:** `docs/developer/knowledge-evaluation.md:144-145`, “Project query inputs without labels.”

**Finding:** The new author instructions say the existing corpus schema is described under “Project query inputs without labels,” but that section gives validation concepts and no complete `corpus.json` envelope or document row. The new query and answer envelopes are shown, while the author must infer the corpus's required `schema_version`, `documents`, and document fields from source/tests. The author CLI refuses malformed inputs with only `invalid_dataset_or_output`, so the missing shape leaves the prescribed author workflow without a usable recovery path.

**Suggestion:** Add one complete synthetic `corpus.json` example or a direct link to an existing complete schema/example, including byte length and text hash calculation.

## Findings corrected during review

### 2. [critical, corrected in current source] Sealed runner accepted legacy query files and read answers before rejecting them
**Original location:** `examples/knowledge/evaluation_runner.exs`, `prepare_inputs/3`, `project_queries/4`, `checked_public_inputs/4`; `examples/knowledge/evaluation_input.exs`, `queries/2` and `references/3`.

**Original evidence:** A sealed manifest could commit a legacy `schema_version: 1` query file containing label fields. `EvaluationInput.queries/2` accepted and projected it; `project_queries/4` discarded the projection's contract marker, so fifty IDs across two projects reached the measured schedule. Review and score checked its saved identity order, opened detached answers, and only then rejected the answer envelope through the legacy branch of `references/3`. This broke the closed sealed query shape and malformed-public-input refusal before answer access.

**Correction inspected:** `verify_dataset!/2` now calls `sealed_questions!/2` on the same bytes it just hashed for the query member (`evaluation_runner.exs:2555-2559`). `checked_public_inputs/4` also requires that contract on the re-read, hash-checked bytes before either review or score calls `answer_bytes!/2` (`:2595-2610`). The score path reuses that projection. The new `knowledge_evaluation_plan_test.exs` case commits a legacy 50-row file under a sealed manifest and asserts `data_query_contract`, no answer access, and no prepared files. I did not execute the pending green suite.

### 3. [warning, corrected in current manual] Invalid-reference recovery instructions contradicted sealed review
**Original location:** `docs/developer/knowledge-evaluation.md:1091-1095`; `examples/knowledge/evaluation_review.exs:111-115`.

**Original evidence:** The chapter claimed invalid reference spans remain visible in a written packet. New sealed review instead returns `invalid_reference_integrity` before creating packet files. The revised paragraph at `knowledge-evaluation.md:1091-1099` now distinguishes sealed refusal before packet creation from the legacy diagnostic packet.

No further concrete runtime finding emerged from the corrected paths. This is a static review; it does not establish that the full measured or installed fixture has passed.
