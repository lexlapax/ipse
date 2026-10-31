# Pending proposal acceptance: proposed narrow typed contract

2026-10-29. This is a proposal for independent review, not implemented acceptance
or a new permission. It builds on the [pending contract gap](pending-proposal-contract-gap-review.md),
[reviewed pending projection](pending-projection-independent-review.md), and
[retained forget journey](management-forget-effect-independent-review.md). It
must preserve original provenance and never transform quoted or generated text
into `native_operator_assertion`.

## Selected card and real acceptance

A trusted owner selects exactly one `pending.<candidate-id>` row. The existing
pending parser determines schema identity and original proof; the host's active
domain capability verifies its value hash/revision, signed format/live/anchor,
recipe, initial host admission time and pending expiry. A held Collection
callback is needed for protected full-card display. The card's exact facts are
closed, versioned fields `version`, `project_id`, `namespace`, `pending_key`,
`candidate_id`, `record_schema_version`, `record_revision`, `record_sha256`,
`lineage`, `text`, `text_sha256`, `assigned_category`, `reason`, `source_proof`,
`recipe_sha256`, `publication_policy_sha256`, `first_admitted_ms`,
`valid_until_ms`, `root_sha256`, `render_revision`, `session_id` and `client_id`.
The client/session distinction is explicit: standalone has a fresh actual native
client identity and no invented conversation Session; chat binds its Session and
channel. Every displayed byte, category, source class, proof and proposed
retention is covered by the exact facts and display digest. A single fully shown
card is within the original maximum of eight cards / 8 KiB; byte and escaped
frame limits must be measured. No selection of an undisplayed card or accept-all.

Use the actual existing owner-controlled same-terminal display/input path with a
fresh code and literal `accept CODE`; plain yes, argv/stdin/--yes, old render,
wrong client/Session/version, lost owner or partial display refuses. Protected
display holds the real source/project/policy/Collection owners until the native
writer has stopped and all copies are acknowledged closed; release all display
leases before waiting for human input. The volatile one-use `Review` permit is
bound to those exact facts and actual input, never serialized or worker-supplied.
The dedicated 120-second setup/display/input boundary and post-input 30-second
permit are not restarted. Existing `ManagementTerminal` currently only accepts
`forget` and must be narrowly adapted for this purpose without its retained-target
management exemption: acceptance requires active valid publication consent and
source eligibility. A code is a selection, not permission for an effect.

The original owner journals a `pending_proposal_accepted` event before any
publication. Its closed version-1 record contains a fresh event ID, the exact
card facts/digest and render ID/revision, actual native event ID/display hash,
challenge, input hash and observed time, as supplied by the live one-use review.
It says the user accepted this decision, not that the proposal's premise is
objectively true. Journal intent and reserved result capacity precede mutation;
interrupted effect remains unknown and never auto-replays. A rejected/cancelled
or expired render cannot create that event, and the same native event cannot be
consumed twice or accepted under a different candidate/client/session. Saved
rebuild validates chronology and deduplication without recreating a permit.

## Proposed accepted state and atomic mutation

Use a distinct closed `accepted_decision` note value, not a literal-source
record. Its fields are `version`, `kind`, `lineage`, `candidate_id`, `text`,
`category`, `reason`, `source_proof`, `acceptance_event_sha256`,
`acceptance_link_sha256`, `accepted_at_ms` and `valid_until_ms`. The original
source proof value and fields exactly equal the pending proof, and the physical
pending value hash is bound separately; re-encoding does not promise identical
JSON bytes. Accepted text remains the
candidate text and no synthesized source origin is introduced. Its deterministic
lineage is `Ipse.JSON.digest(["ipse-knowledge", 1, "accepted_decision",
candidate_id, original_lineage])`, so
re-rendering or redelivery cannot mint a second lineage. The exact domain/hash
note schema needs review before implementation. The event digest is
`Ipse.JSON.digest([exact_closed_event])` and the link value hash is
`Ipse.JSON.sha256(Collection.Migration.encode(link))`, matching Collection's
native value hash. An ordinary decision's
new baseline begins at the real acceptance only for a genuinely first accepted
lineage. Any existing signed first-admission, shorter baseline or suppression
must be preserved and must never be restarted by a new render, event ID, missing
note or candidate reappearance. The old seven-day pending clock remains a hard
eligibility limit at consume and the native final decision; its original signed
first/deadline pair is retained and cannot renew the pending record. The pending
deadline does not by itself cap the distinct later decision's retention. Other categories use their
explicit authorized retention; source/permission clocks may only narrow it.

A deterministic immutable `accept.<candidate-id>` link contains the closed
fields `version`, `kind`, `candidate_id`, `pending_key`, `pending_revision`,
`pending_value_sha256`, `original_lineage`, `accepted_note_key`,
`acceptance_event_sha256` and `source_proof_sha256`. It names the deterministic
accepted note but does not contain that note's hash: the accepted note commits
the link hash, avoiding a circular digest. The signed managed live row commits
the accepted note's actual value hash. Current-use must verify the complete
link and original source proof; a link or receipt alone is not source eligibility.
The link and original acceptance event survive independently of any later
pending-row reclamation. Retention, deletion, export/import and historical
semantics for the link must be explicitly proved rather than assumed from the
existing literal path.

The smallest proposed Core operation under the actual Collection lock performs
one exact CAS: delete the selected pending row and its signed live entry; insert
the absent deterministic accepted note and absent link; retain the original
signed pending clock; insert/update the separate accepted lineage anchor and
live record, preserving any prior signed suppression. Recheck exact old physical
revision/hash, original source proofs and exclusions, active Identity/Consent,
recipe, policy, signed pending deadline and full display facts before consuming
the same-owner permit. Native final switch uses no later than the pending and
current policy deadlines. Conflicting/missing prior rows, any existing accepted
link or destination, a changed source, expired/revoked/disabled policy, reused
receipt or any unconfirmed result refuses or remains unknown. No consumed permit
is used for a second attempt.

This is a new typed mutation and receipt, not a relaxation of `new_capture?` or
its literal recipe. Its closed receipt should bind operation ID, exact selected
pending identity/revision/value hash, acceptance-event digest, new decision/link
key and value hashes, old and new root/generation and actual signed sidecar
hashes; no JSON-shaped receipt itself grants authority. It must preserve the
existing signed-floors/CAS and old-reader fail-closed semantics. Actual worst-case
page splits, distinct read-unit accounting, maximum 64 KiB input and 2 KiB receipt
must be measured; if the three record changes plus sidecars cannot fit, a
versioned bounded layout is required, not a raised public limit or partial
publication. A durable pending clock and deterministic link must continue to
prevent duplicate acceptance after restart/compaction.

## Qualification

First prove retained pending observation under actual native owner and compare
its signed deadline to worker-recorded time. Then test the render/event contract,
real native display/input and current-source lease, exact ID/revision/hash/clock,
wrong code/client/project, bare yes, expiry, source and policy changes, duplicate
receipt, owner loss and unknown/no replay. Finally exercise one real CLI
acceptance on a genuine signed pending row, inspect its linked event and atomic
selected root, original source provenance, resulting decision/use and Saved
reconstruction. Include invalidated/changed target, revoked consent, race,
interrupted publication, old backup and deletion/expiry controls. Standalone
review, current selection, read protection, all-copy closure, displayed bytes and
post-release effect revalidation remain necessary; this proposal does not itself
qualify any of them.
