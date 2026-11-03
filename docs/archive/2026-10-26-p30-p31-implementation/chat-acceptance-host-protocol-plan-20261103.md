# Chat acceptance host protocol: proposed work, 2026-11-03

Historical planning note. This records a source review, not an implementation or
test result. Current scope and status remain in [the plan](../../plan.md). The
existing supported path is the separate native `ipse knowledge review KEY`
management command; it does not claim an in-chat Session decision.

The proposed chat slice selects one existing pending proposal whose original
source Session is closed, displays its exact card in another live Session and
accepts it using fresh native input. It must keep the original source and the
decision Session distinct. It does not cover an active original source or
automatic post-reply cards.

1. Add Session-owned intake and reservation for one selected candidate. Bind
   the candidate, Session, client, policy and render revision to the actual
   journal owner, with a compatible journal layout marker and resume rules.
2. Add an acceptance-specific native review and publication handoff. The
   Session must retain control of its writer and lock, record the decision and
   effect intent before publication, revalidate source and consent, consume one
   exact fresh input, and preserve unknown outcomes without replay on loss.
3. Authenticate and retain the committed decision Session journal during later
   use, using the host-admitted history directory, including a custom state
   directory. Retain the separate original source and all existing current-use
   fences; refuse when either cannot be established.
4. Exercise the complete native chat-to-fresh-Session journey and its negative
   controls, review operator and developer documents as whole paths, and run
   the required focused and baseline checks before reporting completion.

The gate requires an actual Session-owned journal and native terminal, exact
displayed card and fresh acceptance, committed publication, saved reconstruction,
and later provider admission in a separate Session. Controls must cover stale or
wrong input, changed or missing source, revoked or expired consent, interruption
around effect intent and no automatic replay, plus an isolated custom state
directory. Tests must verify ordinary approvals remain intact. Synthetic
fixtures do not establish installed, live-account or human acceptance evidence.

This is not a command adapter: the current management terminal and transaction
require their file-effect worker to own matching management controls and the
journal, while the live Session retains its own writer and lock. The existing
Session terminal ticket is restricted to managed supersession. Reusing either
without a new owner-bound handoff would assert ownership the caller does not
have. The subsequent journal resolver currently accepts management journals
only. These are source-review findings; no new code or tests were run for this
note.
