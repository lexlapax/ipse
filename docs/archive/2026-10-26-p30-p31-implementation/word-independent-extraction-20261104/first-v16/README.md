# Independent Word extraction first outcomes — 2026-11-04

The independent evaluator reviewed the frozen adapter and ran exactly one pure
12-source cohort. The adapter used the shipped documents bundle
`9677e436d7969da90bb3c752c473489eb218c224f609cdcba852f1849a473fb7`
and extraction recipe `ipse-documents-v16`. Between freezing this adapter and
candidate and their execution, neither the implementation nor the input or
acceptance criteria changed; no answer-key tuning preceded this first run. The
evaluator has not developed the DOCX parser. This wording corrects the scope of
the original narrative on the same date; all first-outcome bytes remain unchanged.

All twelve first outcomes were preserved before diagnosis or remediation. All
twelve returned the typed refusal `unsupported_docx_style_visibility`; no
document or Collection source payload was produced. The adapter exited zero
because it completed and recorded the cohort. This is not twelve passing parser
cases, a semantic result, a Collection commit, installed acceptance or a model
quality result. No application, model, native input or service was started.

The private output directory is `first-outcomes-01` with mode 0700; every outcome
and claim has mode 0600. `first-outcomes.sha256` freezes its fourteen files.
All source/adapter input, full runtime bytes, runtime pathset and symlink-target
postchecks passed. `first-status.txt` records those five zero exit statuses.
The complete original files and runtime remain unchanged. The invocation used
installed `C.utf8`, one BEAM scheduler, one async thread and a private home.

The adapter itself is gold-blind. Only after first outcomes were sealed did the
evaluator inspect the private gold's schema, without disclosing gold text or
answers. The existing document gold contains 162 question-level answer records
with support quotations and source-specific locators, including paragraph, table,
revision, footnote and comment shapes. That schema could support bounded
question-support/locator spot checks after successful extraction. It is not a
complete expected rendered-text transcript, byte map, visibility/style oracle or
exhaustive extraction-fidelity reference. Its answer labels cannot by themselves
establish complete parser fidelity. No semantic scoring was performed in this
cohort, and all twelve refusals prevent a positive fidelity claim from it.

The original gold bytes were checked unchanged after this schema-only inspection;
the private schema receipt is `gold-schema-only.json`. No answer or support text
was printed, copied into this report, provided to the implementation author or
entered into Git. Any later repair or acceptance change must retain these first
refusals and be described as remediation, not the original held-out outcome.
