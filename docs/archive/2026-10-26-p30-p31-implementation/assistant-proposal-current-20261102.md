# Current direct-client assistant proposal control, 2026-11-02

The earlier [headless untrusted-source controls](headless-untrusted-controls.md) observed a pre-publication failure for an assistant reply. On current source and a freshly built bundled Knowledge artifact, the same local synthetic scenario saves that reply as a pending proposal through an explicit direct-client capture command under saved consent. This supersedes the earlier observation for this narrowly specified current-source path, not the historical result or the [pending journey's remaining gaps](../../plan.md#p31-usable-knowledge-and-prompt-assistance).

The strengthened `test/support/headless_untrusted_capture.exs` checks the exact completed synthetic reply, pending value, original Session, `answer.original` and `assistant_proposal` provenance, and revalidation against Saved source history. A protected signed read checks that the stored value matches and has `never_current` eligibility. The fixture also checks that its attempted ordinary workspace write and shell effect did not run. It uses a local synthetic HTTP provider and an automated native terminal for permission setup; it makes no live model call and supplies no human attestation.

`./dev/build.sh` passed, followed by `mix test test/ipse/cli/knowledge_test.exs --only assistant_pending_direct --max-cases 1 --seed 791869` (one passed, ten excluded). The exploratory run before tightening assertions also completed successfully; its synthetic log remains at `/tmp/ipse-assistant-proposal-current-20261102.log`.

The changed-file formatting check and `mix compile --warnings-as-errors` passed. A combined run with the two adjacent actual headless argv/stdin pending controls passed three tests, with eight excluded, at seed 791870.

## Model-selected follow-up

A later synthetic follow-up starts a second Session turn with an explicit request to record the previous suggestion. The fixture does not preselect or read its source for the model: the model calls `source_list`, `source_read`, and the Knowledge capture tool, once each. The resulting signed pending value retains the exact prior assistant reply and original source proof under saved consent. A separate case replaces the actual quotation with fabricated text and verifies that no Collection publication or pending record results. Both use the same local synthetic provider and automated setup, not a live model or human reviewer.

The model-positive and fabricated-quotation cases passed together (two tests, seed 791874). The final combined run with the direct-client and adjacent headless argv/stdin controls passed five tests, with eight excluded, at seed 791875. The changed-file formatting check passed. This explicit second-turn request does not establish automatic same-reply capture, a displayed chat decision card, in-chat acceptance, human review, real-model usefulness, full-source or installed qualification.

## Standalone review of the model-selected proposal

The follow-up fixture now closes the original Session, then launches the public `knowledge review` in a separate process with the review-specific synthetic PTY. It checks the committed management journal, removal of the pending row, the accepted decision and immutable link, and exact preservation of the assistant reply's original source proof. This joins the model-selected second-turn capture to the existing standalone review path; it still does not test in-chat acceptance or a human operator.

The first attempt used a PTY mode that sent the displayed code before the `approval>` prompt, and timed out (seed 791880; `/tmp/ipse-assistant-proposal-public-review-20261102.log`). The corrected separate-process review passed one test, with 13 excluded, at seed 791881. The final combined model/direct-client/headless/review suite passed six tests, with eight excluded, at seed 791882. Changed-file formatting passed.
