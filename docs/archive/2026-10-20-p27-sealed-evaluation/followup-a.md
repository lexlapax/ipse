Historical review record, 2026-10-20. Original report and correction scope are described in [the record index](index.md). Current procedures belong to [the evaluation manual](../../developer/knowledge-evaluation.md). This review does not establish P27 completion.

# Sealed-answer review A follow-up

No findings.

Read-only inspection covered the corrected Runner verifier, both reference loaders, the new legacy-envelope regression, and the qualified review instructions.

The new manifest verifier requires `sealed_questions!/2` on the exact query bytes whose hash it checks. Preparation's later child read remains bound to that digest. `checked_public_inputs/4` independently enforces the sealed envelope and saved question order on the bytes used immediately before answer access. The score loader reuses its returned projection; the review loader calls it without expecting the old `:ok` return.

The regression binds a correctly hashed historical combined file containing fifty heldout rows across two projects to the new closed manifest, then expects `data_query_contract` with an empty preparation output and no traced answer-sentinel access. This addresses the previously accepted downgrade rather than a hash-corruption case.

The manual now distinguishes sealed refusal before packet-directory creation from legacy diagnostic packets retaining invalid references.

No repository edits, Git commands, builds, tests, model/service calls or private-workload reads were performed. This report does not claim the pending focused or Linux measured/installed verification passed.
