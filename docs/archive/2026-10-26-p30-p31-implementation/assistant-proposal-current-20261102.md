# Current direct-client assistant proposal control, 2026-11-02

The earlier [headless untrusted-source controls](headless-untrusted-controls.md) observed a pre-publication failure for an assistant reply. On current source and a freshly built bundled Knowledge artifact, the same local synthetic scenario saves that reply as a pending proposal through an explicit direct-client capture command under saved consent. This supersedes the earlier observation for this narrowly specified current-source path, not the historical result or the [pending journey's remaining gaps](../../plan.md#p31-usable-knowledge-and-prompt-assistance).

The strengthened `test/support/headless_untrusted_capture.exs` checks the exact completed synthetic reply, pending value, original Session, `answer.original` and `assistant_proposal` provenance, and revalidation against Saved source history. A protected signed read checks that the stored value matches and has `never_current` eligibility. The fixture also checks that its attempted ordinary workspace write and shell effect did not run. It uses a local synthetic HTTP provider and an automated native terminal for permission setup; it makes no live model call and supplies no human attestation.

`./dev/build.sh` passed, followed by `mix test test/ipse/cli/knowledge_test.exs --only assistant_pending_direct --max-cases 1 --seed 791869` (one passed, ten excluded). The exploratory run before tightening assertions also completed successfully; its synthetic log remains at `/tmp/ipse-assistant-proposal-current-20261102.log`.

The changed-file formatting check and `mix compile --warnings-as-errors` passed. A combined run with the two adjacent actual headless argv/stdin pending controls passed three tests, with eight excluded, at seed 791870.

This is explicit client selection after a completed reply. It does not establish automatic model-selected capture, a displayed chat decision card, in-chat acceptance, human review, real-model usefulness, full-source or installed qualification.
