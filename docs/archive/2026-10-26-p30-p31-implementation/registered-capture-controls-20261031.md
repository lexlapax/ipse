# Current capture fixture controls

2026-10-31, based on `093fb4f`. This test-only increment addresses failures34,
46 and47 in the preserved [c7cb484 full-suite receipt](full-suite-c7cb484-20261031.md).
The current [plan](../../plan.md) still owns milestone acceptance.

Those controls used legacy protected publication and an unregistered demo
callback. They now select the existing single-new-record V3 capture contract
and registered native Ollama HTTP fixture. No runtime gate, deadline, source
dependency or completion witness changed. Explicit legacy tests remain separate.

The SDK2 paged-result case retains version4, original semantic binding and saved
reconstruction assertions. It additionally requires confirmed V3 publication and
a real tool-result continuation request. The ambiguous-mapping case still
requires `collection_consent_denied` and an empty reservation ledger, followed
by the actual registered continuation. The worker-entry revocation case requires
the same denied commit and empty ledger, valid action/saved reconstruction and
exactly one native dispatch intent/request. Its turn correctly ends in error
because revoked permission also blocks the next inference request.

The first paged control passed in8.1seconds; strengthened publication checks
passed in7.9seconds. An initial three-case run passed two but failed the revocation
fixture: it waited for a second HTTP request that permission correctly forbade.
That first failure remains in
`/tmp/ipse-current-capture-controls-first-20261031.log`. Correcting the response
count and expected turn status passed all three in10.9seconds. The final run,
`mix test test/ipse/extension/managed_collection_call_session_test.exs --only registered_capture`,
passed3tests (135excluded) in11.3seconds, including the stronger dispatch-count
and saved-validation assertions. Its log is
`/tmp/ipse-current-capture-controls-final-20261031.log`. Format/diff checks pass;
the documentation checker reports977Markdown files/8136local links/0errors.

These synthetic native exchanges consume no live model allowance and prove no
semantic quality, full-suite pass, installed behavior or milestone completion.
The developer verification chapter was reviewed as a whole and now explains
the distinction between a refused publication and a revoked continuation route.
Operator Memory and native knowledge-permission chapters were reviewed; their
current procedures and limits are unchanged.
