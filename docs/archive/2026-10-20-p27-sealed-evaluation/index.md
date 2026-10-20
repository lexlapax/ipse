# P27 sealed-answer evaluation verification

Historical investigation and verification record, 2026-10-20. This increment
follows `8a10be35ddbc304903c2892abe596597f9d8e3b6`. P27 remains open. Current
procedures belong to the [evaluation training manual](../../developer/knowledge-evaluation.md),
and acceptance belongs to the [plan](../../plan.md#p27-optional-research-graph-and-rag).

## Separate questions from committed answers

The explicit `sealed_answers_v1` data contract uses the existing version-two
evaluation declaration. Its closed manifest identifies the corpus and questions
by path and hash, and commits the separate answer file by hash without an answer
path. Prediction preparation reads the public inputs. Review and scoring require
the committed answers after validating the prediction and audit bindings.

The author tool checks a complete 50-question population, exact typed joins and
literal source references before creating a private manifest. The detached answer
file includes an author-generated nonce. These checks establish file integrity;
they cannot prove independent authorship or prevent disclosure outside the tools.
The old combined-input format retains its existing contract.

Both [review A](review-a.md) and [review B](review-b.md) found that a correctly
hashed legacy combined-question envelope could pass the new manifest verifier.
A regression reproduced that acceptance. The repair requires the strict new
question envelope on the bytes actually read, before preparation or answer access.
The reviewers also identified incomplete corpus authoring instructions and an
incorrect description of invalid-reference output. The manual now includes the
complete corpus shape and distinguishes the sealed contract's refusal before
packet creation from the legacy diagnostic packet. Both
[follow-up A](followup-a.md) and [follow-up B](followup-b.md) report no remaining
concrete finding in their reviewed scope. The archived reports retain their
original bodies with historical headers added.

## Verify the frozen implementation

The [verification receipt](verification.json) records the checks, source and
package identities, review hashes and limits. The [source inventory](source.json)
covers 461 runtime, test and tooling files. The inventory matches before and
after verification on both platforms. It does not cover every Git file or file
mode. The Linux checkout used an isolated temporary snapshot at `f667eeb`; that
snapshot is not an origin review target. Later editorial records differ.

macOS passes build, formatting, strict compilation, demo, documentation checks
and the full suite with 1,357 passing tests, one skip and 36 exclusions. Linux
passes build, formatting, strict compilation, 93 focused evaluation integration
tests, packaging and documentation checks. The Linux full suite was not rerun
for this increment.

The Linux source and installed-package subjects each produce 350 synthetic first
prediction rows with complete execution and resource audits. Their answer files
remain absent through prediction, finalization and the initial audit. Subsequent
CLI review succeeds, and scoring refuses unmeasured semantic quality as expected.
Each subject also passes ten authority refusal controls and three review-binding
refusal controls.

A separate read-only check audits each subject with its synthetic answer file
present and absent. It observes zero answer-file probes and identical audit
results, then restores the exact answer bytes. Deliberate read and stat operations
confirm that the tracer observes those calls. Its scope is synchronous file-entry
calls in the auditing process, not an OS-wide syscall trace. It performs no model
or measurement replay. Five literal JSON examples and their corpus hash and
question-answer join also pass validation.

## Keep acceptance separate

These are synthetic protocol, custody and native-resource proofs. No actual
model inference ran, no new private workload was authored, and no engine was
selected. Real-model quality remediation, the independently authored private
50-question workload, final-source matched quality and exact charged-memory
comparisons, independent semantic review and engine choice remain open.
The authorized whole-codebase and all-manual consolidation also remains open.
The [preceding tuning record](../2026-10-20-p27-quality-remediation/index.md#retain-the-bounded-tuning-outcome)
retains its incomplete result without upgrading it to acceptance evidence.
