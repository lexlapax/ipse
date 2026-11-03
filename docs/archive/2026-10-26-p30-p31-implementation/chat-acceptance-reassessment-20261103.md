# Chat decision acceptance: architecture reassessment, 2026-11-03

This is a point-in-time design assessment, not a completion claim. It reviews
the [frozen acceptance contract](baseline.md#confirming-a-proposed-decision),
the paused Session-owned draft and a separate management-owner alternative.
The base revision inspected was `184dac3bd8e77d1fe860be5af596ea55df26c289`;
the draft was uncommitted. This record does not replace the frozen contract.

## Required user journey

After a completed assistant reply, the host displays the exact journaled proposal
as a decision card. An explicit fresh `accept CODE` must select that exact
proposal and version, and the chat capability must bind the project, client and
actual Session. The host records the render revision and interactive acceptance;
stale, reused, cross-Session and unknown codes fail. Interruption requires a
freshly displayed code, and receipt redelivery must not publish twice. Source,
consent, ownership and effect checks still apply. The frozen text requires a
Session-bound interaction and durable records; it does not itself specify that
the acceptance event must live in the conversation's own journal.

## What exists and what is proposed

The existing [standalone native review](pending-review-cli-20261031.md) has its
own review client and management owner. It supports explicit card acceptance,
journal-before-effect, source and consent checks, and no automatic replay. It
uses a closed original Session source; asking the user to leave chat and run it
is not the required same-reply, Session-bound journey.

The [Session-owned host protocol](chat-acceptance-host-protocol-plan-20261103.md)
is a later proposed implementation, not an additional frozen user requirement.
The paused draft attempts a bounded in-chat review of a selected proposal from
a closed prior Session. It does not yet demonstrate the required card immediately
after the creating reply or acceptance from an active same-Session source. It
includes a conservative one-acceptance-event-per-Session guard; that restriction
and the rest of the draft are not established shipped behavior. The existing
[journal-binding record](pending-chat-journal-binding-20261102.md) explains the
current binding, not a proof that no other safe binding is possible.

The preserved draft is at `/tmp/ipse-chat-acceptance-first-failure-20261103/`:
`current-draft.patch` has SHA-256
`2c0972deb288c81175e1e0e1302bc2fcaa15b9aa36ccc9f2f8c7172e610a02ac`, with
separate copies of untracked draft files. In the latest synthetic journey the
card appeared and its exact code was entered, but the Session returned
unconfirmed; reconstruction reported `invalid_extension_action`. The fixture
removed its journal, so the exact cause and publication stage remain unknown.
The retained synthetic log `prompt-fixed-journey.log` has SHA-256
`a5b3b03440cc37939fb9544b10a2ff5ea6dbf6c1b328f1667fcd991900a5896f`;
it is not reproduced here. These temporary files are investigation evidence,
not durable repository artifacts. The 16 draft files were subsequently
quarantined there with a verified `draft-files/SHA256SUMS` inventory and removed
from the worktree; they have not been merged into the tested branch.

## Active source and the separate-owner option

The creating Session still owns its source lock when the post-reply card is
shown. A closed-source lease cannot simply be acquired for that active source.
The current draft's `PendingAcceptance.with_shareable_source/3` refuses a source
from the consuming Session; its union variant identifies an active source but
requires the caller to retain and share the actual Session/Writer owner. Existing
`Runner.SessionSource` has an owner-sharing route for its supersession path, but
that alone does not establish an acceptance handoff.

There is a concrete composition constraint: the transaction controller's
writer-control import requires no existing writer control and no source
operations. The existing management acceptance lease imports its writer and
source; simply nesting an active Session/Writer import after it is therefore not
supported by that controller state. There is also a direct contradiction in
the current draft's final handoff: `SessionSource.with_chat_acceptance` imports
Session control before publication, but Collection publication calls
`Transaction.acceptance_guard`. Its native `j` operation requires **no**
Session control, exactly two live source leases and a live writer control, with
the transaction at the expected three-lock depth. The draft's active-source
handoff therefore cannot pass this guard as written. Preserve `j` and its
existing invariants for its current management-acceptance use.
These are static source findings; they do not establish the cause of the earlier
synthetic failure or rule out every other owner arrangement.

A separate real management owner could in principle bind a verified chat
Session/client and its own journal, with a Session-authorized terminal handoff,
durable intent before publication, and revalidation at final use. One possible
approach would close and authenticate the committed management journal as an
inactive source before sharing the active chat owner. That approach would need
new journal-prefix and identity proofs, safe recovery and no-replay controls; it
is a hypothesis, not an existing API or a demonstrated simpler solution. IDs
supplied by a caller cannot substitute for proof of the real Session and client.

On source inspection, a Session-owned route with a new purpose-specific native
guard may be the smaller change: it could validate the actual active Session
and its Writer together with the exact recorded acceptance and source owners.
That scope and its safety remain unproven. A separate management owner also
needs a new guard: the existing `j` cannot admit active Session control. It must
additionally establish a trustworthy committed management-journal prefix as
an inactive source, or safely hand off two active Writers. Neither mechanism
currently demonstrates the required combined ownership and recovery contract.

## Recommended next decision

Preserve the draft and failure evidence. Before further implementation or a
native run of this contradicted handoff, review the competing owner protocols:
a Session-owned route with a specifically justified active-source acceptance
guard, and a separate management-owner route with independently authenticated
chat identity and source ownership. For each, identify the live owners and
leases at final publication, the journal-before-effect and recovery rules, and
how the exact Session/client, consent and source remain bound. Select the
smallest protocol that can satisfy those requirements without weakening the
existing guard by assumption. Then design focused native positive and negative
controls for that protocol before attempting the complete journey. The decisive
controls must include loss of each relevant Session, Writer and source owner
before and during final publication; acceptance of the exact displayed
proposal/version/code only, with altered, stale, cross-client and cross-Session
cards refused; and interrupted intent, unknown outcome, resume and duplicate
receipt cases that never automatically replay a possibly completed effect.
Verify successful publication and later use with all owners live as well.

The eventual acceptance gate still needs the completed reply and exact card,
fresh interactive code and client/Session binding, publication and later use,
plus stale source/code, cancellation, owner loss, interrupted or unknown
outcomes and no automatic replay. Until these are demonstrated, neither the
draft nor the standalone review closes the frozen post-reply requirement.
