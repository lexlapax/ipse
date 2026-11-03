# Current direct-client assistant proposal control, 2026-11-02

The earlier [headless untrusted-source controls](headless-untrusted-controls.md) observed a pre-publication failure for an assistant reply. On current source and a freshly built bundled Knowledge artifact, the same local synthetic scenario saves that reply as a pending proposal through an explicit direct-client capture command under saved consent. This supersedes the earlier observation for this narrowly specified current-source path, not the historical result or the [pending journey's remaining gaps](../../plan.md#p31-usable-knowledge-and-prompt-assistance).

The strengthened `test/support/headless_untrusted_capture.exs` checks the exact completed synthetic reply, pending value, original Session, `answer.original` and `assistant_proposal` provenance, and revalidation against Saved source history. A protected signed read checks that the stored value matches and has `never_current` eligibility. The fixture also checks that its attempted ordinary workspace write and shell effect did not run. It uses a local synthetic HTTP provider and an automated native terminal for permission setup; it makes no live model call and supplies no human attestation.

`./dev/build.sh` passed, followed by `mix test test/ipse/cli/knowledge_test.exs --only assistant_pending_direct --max-cases 1 --seed 791869` (one passed, ten excluded). The exploratory run before tightening assertions also completed successfully; its synthetic log remains at `/tmp/ipse-assistant-proposal-current-20261102.log`.

The changed-file formatting check and `mix compile --warnings-as-errors` passed. A combined run with the two adjacent actual headless argv/stdin pending controls passed three tests, with eight excluded, at seed 791870.

## Model-selected follow-up

A later synthetic follow-up starts a second Session turn with an explicit request to record the previous suggestion. The fixture does not preselect or read its source for the model: the model calls `source_list`, `source_read`, and the Knowledge capture tool, once each. The resulting signed pending value retains the exact prior assistant reply and original source proof under saved consent. A separate case replaces the actual quotation with fabricated text and verifies that no Collection publication or pending record results. Both use the same local synthetic provider and automated setup, not a live model or human reviewer.

The model-positive and fabricated-quotation cases passed together (two tests, seed 791874). The final combined run with the direct-client and adjacent headless argv/stdin controls passed five tests, with eight excluded, at seed 791875. The changed-file formatting check passed. This explicit second-turn request does not establish an assistant-proposal operation with a post-reply decision card, in-chat acceptance, human review, real-model usefulness, full-source or installed qualification. Blanket extraction from final replies is not a baseline requirement.

The model-selected fixture also checks that its subscriber tool-result preview contains the actual pending key and `pending` within the terminal's first-800-character rendering limit. The model, public-review, missing-source and resume controls passed together (five tests, 11 excluded, seed 791894). This checks the emitted preview and terminal limit, not a native rendered-card acknowledgment.

## Standalone review of the model-selected proposal

The follow-up fixture now closes the original Session, then launches the public `knowledge review` in a separate process with the review-specific synthetic PTY. It checks the committed management journal, removal of the pending row, the accepted decision and immutable link, and exact preservation of the assistant reply's original source proof. This joins the model-selected second-turn capture to the existing standalone review path; it still does not test in-chat acceptance or a human operator.

The first attempt used a PTY mode that sent the displayed code before the `approval>` prompt, and timed out (seed 791880; `/tmp/ipse-assistant-proposal-public-review-20261102.log`). The corrected separate-process review passed one test, with 13 excluded, at seed 791881. The final combined model/direct-client/headless/review suite passed six tests, with eight excluded, at seed 791882. Changed-file formatting passed.

## Recall and unavailable source

The same journey now starts a fresh Session after acceptance and sends a synthetic local-provider request. It verifies that the request includes the accepted assistant-sourced decision in `note_parts_v2`, that the Session journal records a version-6 managed read, and that Saved reconstruction and confirmed close succeed. A separate fresh fixture temporarily moves the original source journal after acceptance: the next model request omits the decision. The fixture restores the source with the same hash and confirms that the Collection root did not change in either case. The setup and review remain automated native-terminal controls, not human or live-model evidence.

The positive recall and source-loss controls passed together at seed 791884. After adding the unchanged-root check, the combined headless, direct-client, model, review and recall cases passed seven tests, with eight excluded, at seed 791885. The explicit assistant-proposal/card operation, in-chat acceptance, installed use and quality qualification remain open.

## Resuming the source Session after separate acceptance

An exploratory test expected the original Session to resume and recall its newly accepted proposal. It instead ended before the synthetic provider request. Two diagnostic runs (seeds 791886 and 791887) preserved that failed expectation; the next diagnostic showed the current recall job found the decision, followed by `managed_preflight_refused` and a failed turn before provider dispatch (seed 791888). This is the documented fail-closed behavior for protected historical content that cannot safely be reused after a separate store change; the diagnostic does not establish a more specific cause.

The corrected refusal control verifies the preflight refusal and no provider request, reconstructs Saved history, retains the original journal prefix and Collection root, then starts a fresh Session that successfully recalls the accepted decision. It passed at seed 791890. The final combined proposal, review, recall, missing-source and resumed-history controls passed eight tests, with eight excluded, at seed 791891. The failed and passing synthetic logs are retained under `/tmp/ipse-assistant-proposal-resume-*-20261102.log`. This does not implement automatic rewriting or rebasing of the old history.
