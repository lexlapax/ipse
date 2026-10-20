Historical review record, 2026-10-20. Original report and correction scope are described in [the record index](index.md). Current procedures belong to [the evaluation manual](../../developer/knowledge-evaluation.md). This review does not establish P27 completion.

# Independent sealed-answer review A

Reviewed the frozen implementation diff against `main8a10be3`, the new author CLI, affected callers and tests, and the complete `docs/developer/knowledge-evaluation.md` chapter. Applied correctness, trust-boundary, verification, compatibility and code-quality lenses. No repository mutations, Git commands, builds, tests, model/service calls or private-workload reads were performed. Evidence below is static execution tracing. The coordinating agent has been notified of both findings and is addressing them; this report describes the reviewed frozen implementation, not a subsequent fix.

## Findings

### 1. [critical] A sealed plan accepts legacy label-bearing questions and opens answers before rejecting the contract mismatch

**Location:** `examples/knowledge/evaluation_runner.exs`, `verify_dataset!/2`, `prepare_inputs/3`, `project_queries/4`, `checked_public_inputs/4`, and sealed review/score loaders.

**Finding:** The sealed plan and manifest select a closed question-only format, but the public-input boundary never requires the parsed question envelope to use that format. `EvaluationInput.queries/2` intentionally supports both historical combined records and sealed questions. Its callers in the new sealed branch accept either result.

**Evidence:** Put fifty historical rows across two projects in a correctly hashed `queries.json`, with envelope `schema_version: 1`, row `split: "heldout"`, and fields such as `expected_answer` and `expected_class`. Bind those bytes in an otherwise valid new `sealed_answers_v1` manifest. `verify_dataset!/2` checks the manifest's contract and input-role hashes, but does not parse the question contract. `prepare_inputs/3` invokes `project_queries/4`, whose child verifies the hash and calls the backward-compatible parser. That parser accepts the historical envelope, strips its labels, and returns projected rows. The parent extracts only `result["queries"]`, so preparation succeeds and the sealed run has already read the combined answer-bearing file.

After finalized predictions, `checked_public_inputs/4` again accepts that historical projection and checks only its saved query/project order. The sealed review loader then calls `answer_bytes!/2`. Only after that custody-file read does `EvaluationReview.prepare/4` derive `sealed = false` from the historical questions and reject the supplied `answers` context as `invalid_context`. The score branch likewise opens answers before `Input.references/3` rejects the mismatched format. Thus the new branch neither enforces question-only public bytes nor rejects wrong public contract authority before reference access.

The existing tests reject extra fields inside an already sealed envelope, extra manifest descriptors and changed hashes. They do not cover a validly hashed legacy envelope under a sealed plan.

**Suggestion:** Preserve historical parsing, but explicitly require its projected contract to equal the plan's selected contract at the new public-input boundary before returning prepared inputs or opening answers. Reuse the validated projection in the score loader instead of parsing it a second time. Add a synthetic regression with a correctly hashed historical combined file bound by a new manifest, including an observable answer-access sentinel.

### 2. [warning] Review instructions promise an invalid-reference packet that sealed review refuses to create

**Location:** `docs/developer/knowledge-evaluation.md`, “Prepare independent review from finalized predictions”, paragraph beginning “For review, expect”; `examples/knowledge/evaluation_review.exs`, `prepare/4`.

**Finding:** The main review instructions say invalid reference spans remain visible in the written packet, set completeness false and produce a failing CLI exit. For the newly documented sealed workflow, invalid references instead prevent packet creation.

**Evidence:** After computing references, `Review.prepare/4` executes `if sealed, do: require!(Enum.all?(references, & &1["valid"]), :invalid_reference_integrity)`. This runs before packet-file construction and before the runner's `prepare_output!`. The retained-invalid-reference packet behavior applies only to the historical branch. A reader following the new sealed instructions would look for a packet and diagnostics that do not exist.

**Suggestion:** State that new sealed references fail with `invalid_reference_integrity` before output creation. Keep the existing completeness-false packet explanation explicitly scoped to historical combined datasets.

## Remaining verification limit

The brief states that the full new Linux measured and installed proof had not run. This review does not infer that those paths passed. No additional concrete findings were found in the detached joins, typed source identities, source-derived integrity checks, historical format handling, model/budget gates or first-attempt lifecycle examined here.
