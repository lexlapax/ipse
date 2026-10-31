# Pending acceptance — independent implementation direction

2026-10-29. The bounded direction in
[pending-acceptance-proposed-contract.md](pending-acceptance-proposed-contract.md),
SHA-256 `ff0330429485de3ac2d136396031c3fd6e8c04d8949e8f909ee2671f7e3c1396`,
is supported for implementation, subject to the concrete pre-mutation checks below.
This is a source/design review, not acceptance of an enabled effect or P31E.
No tests, effects, models or aggregate checks ran. The [plan](../../plan.md)
retains integrated acceptance and correction work.

The original [baseline](baseline.md#confirming-a-proposed-decision) and
[contracts](contracts.md#origin-proposals-and-draft-intent) explicitly authorize
an accepted decision with preserved original source plus an actual native
`accept CODE` event. They do not authorize relabeling generated/quoted material
as an operator assertion, turning acceptance into truth evidence, or granting
workspace/service authority. Standalone review has a real client identity and
needs no fabricated conversation. One selected card is a valid initial subset
of the eight-item/8 KiB maximum; unseen acceptance and unattended promotion stay
closed. Correction, rejection and bounded listing remain separate journeys.

## Minimal supported owners

Keep retained observation in the existing pending parser under
`Collection.with_managed_read`: exact actual record/revision/value hash,
original recipe and proof, signed format/live/anchor and original host deadline.
The new held callback reuses that reader; a prior closed view is insufficient
for later protected display. This review does not itself qualify its new native
control. Actual target Identity/Consent/Collection owners must cover protected
display and verified close. Whether faithful pending/historical display also
requires retaining a separate original-source owner is an open purpose
clarification, recorded in the [restart checkpoint](shared-controller-review-restart-20261029.md).
The baseline expressly requires fresh source verification before publication;
do not infer a fifth native slot merely from displaying retained derivative
provenance. Release target leases before human wait, then freshly reacquire the
actual source/identity/policy/target for publication. Historical display cannot
authorize publication or claim current source eligibility.

Reuse the actual Review channel and one-use permit with a narrow `accept`
purpose. Preserve the original120-second setup/display/input budget and existing
30-second post-input permit budget, including cleanup. Bind native render,
selection and event to the full exact facts, project/namespace, client/Session,
pin, recipe/policy, physical candidate revision/hash, text and signed deadline.
Actual verified input may be durably recorded before publication; that event
records the selection, while a separate effect outcome records whether anything
was published. An accepted-input event or replayed journal must never recreate a
permit or imply successful publication. Reserve intent/result capacity before
effect, consume only after exact fresh revalidation, and classify post-consumption
uncertainty conservatively. Inspect an interrupted operation; do not replay it.

A narrow typed Core operation and normalizer are justified. The current proposal
recipe deliberately yields `never_current`, while literal normalization requires
strong-source exact literal evidence. Reusing either as though the candidate
were a fresh literal would falsify semantics. A distinct closed accepted-decision
value, typed receipt and read projection can preserve the original proof and
make only the user's decision recallable under current policy. Keep current
`new_capture?`, retention/supersession and arbitrary worker mutation fences.
No generic interpreter, workflow engine, new native primitive or serialized
permission token is needed for this direction.

## Atomic state and bounded amendments

The proposed three public changes are sufficient in principle: delete the exact
pending row, insert an absent deterministic accepted note, and insert an absent
immutable candidate acceptance link. The same root switch must delete the old
signed pending-live row, install the signed accepted-live row and update the
accepted anchor, retaining the original pending anchor/clock. No intermediate
selected state may lose the pending row without publishing the link and note.
The original candidate/source lineage and accepted lineage must both retain
applicable suppression and shorter clocks. Changing candidate text/ID, deleting
a note, rendering again or delivering another event cannot evade original
retirement or restart an existing decision baseline.

The amended encoding choices are appropriate: lineage is
`Ipse.JSON.digest(["ipse-knowledge", 1, "accepted_decision", candidate_id, original_lineage])`;
the event uses `Ipse.JSON.digest([exact_closed_event])`; the accepted note commits
the link's actual Collection value hash using `Migration.encode`. Preserve the
original proof JSON value and fields exactly. Bind the original pending physical
hash separately; parsing/re-encoding does not preserve literal serialized proof
bytes. The link points to the note, and the note commits the link hash, avoiding
a circular digest. A link/event/receipt alone grants neither source eligibility
nor current-read authority. Retaining the immutable candidate link across later
note deletion prevents duplicate acceptance after restart; its deletion/import
and historical treatment must stay explicit rather than inherit literal behavior.

The signed pending first/deadline remains a hard limit at permit consumption
and final locked admission. The distinct first genuine decision can start its
own authorized category retention at acceptance; this does not renew pending
eligibility. An existing accepted baseline or original suppression cannot be
reset. Recheck source versions/exclusions and current active publication consent
before admission; preserve the existing native final-decision deadline and
admitted-inflight uncertainty contract, without inventing physical completion
or recall after a valid admission.

Before enabling mutation, fix the closed schemas and literal version/kind values
in code/fixtures, including complete card/render binding, source-proof digest
encoding, event observation fields, typed receipt and read interpretation.
Then measure actual encoded bounds: fully escaped displayed card at most8KiB,
existing6144-byte Collection values,64KiB input,2KiB receipt and32 read units.
Do not infer fit from the three public changes. The existing planner supports
two edits, so pending-live deletion plus accepted-live insertion can share one
live plan; accepted-anchor insertion is a separate plan. Its split/merge worst
case does not automatically satisfy the current normalizer's five-sidecar limit.
Measure distinct page edits/reads, actual sealed bytes and receipt hashes for
same-page and separate-page cases. Refuse before permit consumption if the exact
bounded plan cannot fit; do not partially publish or raise limits by assumption.

Required focused implementation evidence is one real signed pending/native
acceptance and atomic selected-root inspection; exact original proof/link/event
and deadline checks; wrong/old code, client, source, revision, policy and candidate;
expiry and revocation before consume/admission; duplicate/link conflict; and
post-staging owner loss/unknown with inspection and no replay. Saved validates
history without live authority. Typed accepted-decision current-read projection
must preserve decision-versus-premise semantics and verify the actual link,
signed live value and original source. Broader pending capacity, correction,
retention/deletion/import, multi-card and complete CLI journeys remain separately
qualified.

Source inspection additionally covered ObservedRead
`3c39c2693eaf785f36cc8d78f3c9d4def1b4de34e38a02c54b9c1152af12b70c`,
NormalizerV3 `67e4f351595e4c45b4c9f0dcd4a9c33ec9ae8971d71c311ed3f4d0d1bd9bed28`,
ManagedRecipe `9c6fb0eaa1155f412df1b51829a9dc0c37a6200fd11396a1013a356a51c21a0b`,
Planner `54c86cbf341d85f47f2278a7f91ef703b810d1018aa421a0595c164ae8314923`
and Records `90c27e59d3700e4467580c212af92b100f9788fb38a332a80676416160a7d551`.
These are source identifiers, not a frozen implementation/runtime cohort or a
whole-current-package acceptance claim.
