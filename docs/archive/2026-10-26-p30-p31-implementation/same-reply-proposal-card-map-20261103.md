# Same-reply proposal and card: implementation map — 2026-11-03

This is a source-review map, not an implemented behavior or acceptance result.
The [frozen contract](baseline.md#confirming-a-proposed-decision) remains the
authority. It requires an explicit pending-proposal operation and an exact
card after the completed assistant reply; a model assertion is not a render
acknowledgment. The [separate guard design](chat-acceptance-session-guard-design-20261103.md)
owns the later acceptance and publication handoff. Neither this map nor the
quarantined earlier draft proves that handoff.

## Existing pieces and the missing boundary

* `Ipse.Session.Turn.finish/2` and `record_source_answer/3` record the completed
  answer before turn completion. Depending on subscriptions, the journaled
  occurrence is `source_answer_committed` or `lifecycle_answer_committed`.
  `Ipse.Session.SourceIndex.admit_answer/3` indexes the admitted **original**
  answer as `answer.original`/`assistant_proposal`, excluding reasoning and
  presentation. `SourceIndex.quote/2` checks unique exact source bytes within
  a bounded evidence window. A future handoff must bind the exact Session,
  turn, request, occurrence and version, and must not claim that original text
  was presented when a presentation transform changed it. `Lifecycle.answer/5`
  records presented bytes and their hash but does not acknowledge native
  terminal delivery. Its original and presented views are each unavailable
  when they exceed 8,192 bytes; their hashes alone cannot supply readable text.
* The existing `ext__knowledge__capture` command/tool and
  `IpseKnowledge.Knowledge.Records` can create an attributed, signed pending
  proposal under the installed recipe. `Session.invoke_assertion_capture/3`
  shows how the host starts a real command through
  `Ipse.Session.Invocation.invoke_export/4`, with the normal protected outer
  admission. That assertion path is not an assistant-proposal API or authority.
  `Writer.source_query/2` has an assertion-specific request but no equivalent
  owner-bound exact-answer proposal request.
* `answer.committed` and `after_turn` subscriptions exist, but the shipped
  Knowledge bundle subscribes to before-request recall only. More importantly,
  `Ipse.Extension.SemanticAdmission` admits `event.job` only for
  `collection.read`; an after-turn subscriber is not a protected-write shortcut.
  The existing synthetic main-model fixture in
  `test/support/headless_untrusted_capture.exs` selects a **previous** reply
  after a second user prompt. It does not exercise the required same-reply card.
* `Ipse.Session.PlanningDecisions`, `OperatorAssertion`, `Session.Input` and
  `CLI.Terminal` show useful native channel, render, input-witness and replay
  patterns. `Runner.Operator.run_guarded/4` can wait for the native display
  phase while holding input until its guard returns. None currently creates or
  durably acknowledges an assistant-proposal card. Ordinary queued terminal
  output, a model claim and a constructed receipt are not that acknowledgment.

## Smallest proposed vertical path

1. Add one bounded, explicit model-visible proposal nomination in the Knowledge
   extension. Its exact text/category/reason and any references are untrusted
   selection data, not a note, a user decision or permission. The model then
   completes the **same** reply. A typed, one-shot host-journaled nomination
   must bind the actual Session, turn, model tool call, resolved descriptor and
   artifact, exact arguments, and exact successful invocation/result; a bare
   worker reply or uncommitted call is not a nomination. The terminal final
   assistant answer must also finish successfully in that same turn with no
   remaining tool calls. Validate the historical normal/non-headless mode,
   ordering, one-use consumption and cancellation/interruption on replay. This bounded
   handoff must not automatically replay a nomination or its possible effect.
   Reject an absent, altered,
   ambiguous, oversized or unavailable original; validate supplied references
   under their own authority or explicitly refuse them. For the first slice,
   require the selected text to match both the indexed original and the actual
   presented reply; do not silently interpret a transformed or hidden answer.
   An actual native delivery acknowledgment is separately required to call
   the reply displayed: `Lifecycle.answer/5`, a subscriber message and the
   stored `presented` field provide no such acknowledgment. If the first slice
   cannot establish that evidence, it must refuse rather than imply it did.
   This is a candidate implementation, not a claim that the existing tool
   contract already supports future-source nomination.
2. After the answer is durably committed and the relevant turn/subscription
   ordering is settled, obtain a narrowly owner-validated source handle and
   quote for that exact answer. Add the missing Session/Writer source-query
   binding rather than trusting a worker-provided occurrence or caller ID.
   The current capture contract bounds the source quote to 1,024 UTF-8 bytes,
   and `SourceIndex.quote/2` also requires the entire quote to fit its selected
   evidence page. An unavailable >8,192-byte answer view or an out-of-window
   or oversized quote must be visibly refused, not truncated or guessed.
   Immediately before capture, recheck the live normal and enclosing execution
   ceilings, interactive channel and current saved Consent. Start the existing
   bundled capture command as a real owned invocation and wait for its
   authenticated outcome. Preserve existing saved Consent,
   project/epoch/recipe/source checks, seven-day and bounded pending capacity,
   journal-before-effect and conservative unknown handling. A changed bundle
   or new tool descriptor requires its normal reviewed selection and grant;
   do not silently widen an installed policy. Worker output `saved` or
   `existing` is not a signed candidate: before using either, the host must
   reread and authenticate the exact pending record, signed metadata and source
   at a retained current root, including the physical revision and value hash.
   The `existing` metadata-only index result does not renew the candidate or
   authenticate its value. Emit no card on refusal or uncertain creation.
3. Bind a Session-owned focus and render revision to the confirmed exact
   pending identity, Collection revision, value hash, source and project.
   Before display, recheck the live normal and enclosing execution ceilings,
   current Consent and the actual native channel. Retain and revalidate the
   exact candidate, root, source and policy through the native display
   acknowledgment, along with that channel's identity and liveness. Release
   the display owners before waiting for input; a later effect independently
   reacquires its current authorities. Render that complete candidate on the actual controlling native channel,
   with a fresh single-use `accept CODE` bound to Session and client. Establish
   and durably record a real native display acknowledgment before accepting
   input. The current guarded input callback is a useful primitive, but a
   purpose-specific Session bridge, cancellation-safe ownership and replay
   validation are still needed. Invalidate focus/code on edit, supersession,
   interruption, expiry or channel change; resume re-renders with a fresh code.
4. An actual exact input records the operator interaction only. It cannot by
   itself authorize publication or other tools. Later acceptance uses the
   separately reviewed native owner/Writer/source and current Consent fences;
   do not start that effect by treating a card receipt as a permit. Group
   same-journal sources for later use, surface uncertain reservation/effect
   state and never automatically replay a possibly completed operation.

The first slice may bound itself to one nomination/source and refuse unsupported
cases visibly. That does not qualify the full multi-card lifecycle or raise the
existing pending limits. Turn completion, input-reader ownership and after-turn
subscriptions need explicit sequencing: do not notify a completed idle turn,
start a competing terminal reader, or hold the Session synchronously waiting for
a task that needs a callback from that same Session. Preserve the other owner's
independent SessionSource binding work.

## Smallest real controls

Use the existing synthetic loopback model and real native PTY, but adapt the
fixture so **one user prompt** produces an explicit proposal nomination and
then a final assistant reply in the same turn. Assert the completed reply and
source occurrence precede the pending creation and native card; validate the
typed nomination against the same turn, successful tool call and exact args.
Verify the actual reply delivery and card render acknowledgments rather than
inferring them from lifecycle records. The card acknowledgment and code bind
the exact proposal/version/focus, and the
card is displayed without a second user prompt or a separate extraction/review
model request beyond the main model's ordinary tool-call continuation. Inspect
the real signed pending record and source proof; assert it remains pending and
is absent from active recall before acceptance. The protected write must use
the real selected bundle and saved consent, and unrelated workspace/tool
approvals must not change.

Add focused refusal controls for a nomination absent from the final answer,
ambiguous bytes, a changed presentation, unavailable source or unsupported
reference, a quote exceeding 1,024 bytes or its evidence page, and an answer
whose required original or presented view exceeds 8,192 bytes. Exercise a
forged, failed, cancelled, cross-turn, multiple or conflicting nominations;
also reject a changed artifact/descriptor or invocation/result and an
unsuccessful final answer or one with remaining tool calls. Test tampered
mode/order on replay and live planning, enclosing-mode and headless changes
before capture and display. Check forged `saved`/`existing` output, changed
candidate/value/root/source/policy, denied/revoked permission, native-channel
replacement and relevant owner death before and during actual display. Test
bad/bare/stale/reused codes,
unrendered and cross-client/Session attempts, edit/supersession and interrupted
render. Close/resume must preserve pending identity, issue a fresh code, and
never replay an uncertain pending write or acceptance. A real acceptance,
publication, later current-source recall and owner-loss boundaries remain
separate required controls from the guard design; the card fixture alone does
not complete P31E or establish human, installed or model-quality evidence.
