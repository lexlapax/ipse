# Ordinary publication deadlines and question-parent binding

Historical scoped receipt, 2026-10-29. This corrects and extends
[the first audit-repair receipt](managed-audit-repairs.md). Its source/runtime
cohort remains historical. Current milestone status belongs to
[the plan](../../plan.md). This is not P31C0 acceptance.

The subsequent [independent review](managed-publication-deadline-independent-review.md)
found that the native clock check and rename are not atomic. Its interposition
case and a defensible final-switch guarantee remain open.

The independent review correctly distinguished native CAS from a time fence.
The earlier publication prerequisite check bound the expected generation, while
ordinary Collection publication still captured Consent's clock before storage.
Staging could therefore outlive that clock check. The earlier controls did not
qualify ordinary final-switch expiry.

Both ordinary `CollectionCall` and `ManagedCollectionCall` now capture
`expires_at_ms` from the authenticated current policy snapshot used to prepare
the reservation. Inside the actual file-effect owner, Collection scopes that
trusted host deadline through staging and the final native `switch_before`.
Nested deadlines compose with the minimum and restore the previous scope.
No worker field supplies or extends this deadline. Consent still holds the exact
policy/epoch through publication; CAS remains independently required.

Arbitrary inherited managed content remains refused before publication intent.
The admitted own-publication snapshot prerequisite has no separate literal
clock; it is bound to the same policy and final CAS. New original-source receipts
have no independent temporal expiry. This section does not establish source-owner
death ordering, and does not admit an inherited finite literal dependency. The
wired literal-v4 A/B variant remains open.

Saved extension-question recovery now requires equality of the complete
`question.parent`, the actual lineage invocation's stored parent, and the active
extension reconstruction parent. Mere presence of the same invocation ID is
insufficient. Missing or same-ID mismatched parents withhold the question;
valid ordinary questions retain recovery.

Focused results:

- Strict compilation46870 passed four changed production modules with no
  diagnostics: Saved, Collection, CollectionCall and ManagedCollectionCall.
- 46874 passed six actual Session/native-storage cases in 19.1 seconds. Managed
  v3 capture and legacy unmanaged CollectionCall publication each had a current
  positive, delayed-stage deadline refusal, and stopped-native deadline refusal.
  The latter stops the actual retained transaction helper after staging, queues
  publication, resumes it after the deadline, and always resumes it in cleanup.
  Expired cases left generation0 with no visible records; current cases committed
  generation1. Each journal passed Saved reconstruction.
- 46873 passed three actual interrupted extension-question cases in 8.3 seconds:
  revoke and expiry withheld subscribers/info/answer and preserved the journal
  prefix without continuation; ordinary full-parent recovery displayed the full
  arguments and accepted an answer. The test models only the legacy producer's
  missing managed tracking; Session emits the actual action/question/source/wait
  records. Legacy metadata substitution preserves original source byte ranges.
- 46875 reran only the changed A/B control and passed in 3.2 seconds. It now
  directly asserts absence of the candidate `extension_action_intent`, in addition
  to no successful result. This supplies the assertion missing from46865's
  earlier archive claim. Ordinary captures still succeed inside that control.
- 46876 passed the changed pure parent-binding control, including missing parent,
  mismatched lineage parent, mismatched extension parent with the same ID, valid
  ordinary parent and complete managed dependency union cases.
- Scoped formatting and `git diff --check` passed. No aggregate suite was run.

Initial46871/46872 attempts stopped in fixture artifact admission because the
new fixture misspelled capability `host.question` as `host.questions`. The same
attempt exposed an unused outer cleanup variable in the test; it was removed,
while the real stopped-helper `SIGCONT` remains in its inner `after` block.
Neither attempt exercised the new behavior. Only those unexecuted focused
selections were retried. Their failed logs remain retained.

The [manifest](managed-publication-deadline-followup/manifest.json) freezes the
four production sources, focused fixtures/scripts, logs and full runtime
inventory. The new isolated graph retains the matched a51c2d helper; no native
protocol, helper, Session lock or DocumentStage source was changed. No terminal
PTY, live account or paid inference was used.

The source/effect owner-death architecture, literal-v4 A/B use, managed State and
service execution, full managed display sinks, delegation and nested result
delivery remain separately unqualified or fail closed. Supersession display
remains disabled. These limits are not closed by the native clock controls.
