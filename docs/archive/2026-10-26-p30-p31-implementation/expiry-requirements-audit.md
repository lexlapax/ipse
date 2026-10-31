# Expiry requirements and publication linearization audit

Historical design audit, **2026-10-29**, against checkout HEAD
`7afc3f26617a79eecab5f6d97cef8b48bf6375b1` and its uncommitted working tree.
This is a local-source requirements investigation, not an implementation,
qualification receipt, change to a gate, or approval of replacement semantics.
The [plan](../../plan.md) owns status; the [operator manual](../../operator/index.md)
and [developer manual](../../developer/index.md) own current behavior.
Read the [frozen baseline](baseline.md), [contracts](contracts.md),
[actual interposition](strict-deadline-interposition.md) and
[Review/State containment](strict-gate-lifetime-followup.md) with this record.
Line references below refer to the inspected files, not executable instructions.

## Finding

The original requirements are mixed. They require fresh authority at the final
locked local publication decision, atomic ordering against explicit revocation
and suppression, and eligibility checks at each later managed use. They explicitly
allow uncertainty for admitted remote effects. They do **not** uniformly require
every physical filesystem mutation to complete before a clock deadline.

There is especially strong contrary evidence for generic State: the original
[P26 expiry-write design](../2026-10-19-p26-remediation/expiry-write-design.md),
lines 94–100, says: “The linearization point is that locked publication decision.
No clock sample can promise the physical rename syscall completes before the
same wall-clock millisecond.” P31's frozen documents do not explicitly replace
that contract with physical completion. The actual late State rename therefore
disproves a stronger physical guarantee; by itself it does not disprove the
original documented State decision guarantee.

This does not justify restoring old paths without review. The current gate
record explicitly requires design review for an authorization-linearization
alternative ([interposition](strict-deadline-interposition.md), lines 123–129).
An initial reservation before parsing/staging is also too early: it cannot replace
the required final source/policy/suppression revalidation. A blanket “admitted
before expiry, so everything may publish afterward” rule would violate the
frozen local-publication and later-use requirements.

## Requirements matrix

| Boundary | Original source and exact obligation | Physical completion before expiry? | Faithful interpretation and unresolved change |
| --- | --- | --- | --- |
| Saved knowledge consent | [Baseline](baseline.md), lines 543–560: protected scoped consent, unchanged semantic authority, explicit ceilings. Lines 575–579: “Recheck them under the publication lock”; revocation “excludes later admissions/publications,” while already admitted remote requests may still send bytes. | No explicit universal clock-completion promise. `expires_at_ms` and its current propagation are implementation shapes, not a verbatim developer-selected physical deadline. | Revalidate active policy at a final locked publication decision, separately from initial reservation. Expired consent cannot start a new publication attempt. Any decision-time interpretation of elapsed consent needs a dated review; it cannot authorize stale evidence use or a post-acknowledgment publication. |
| Explicit revocation/suppression | [Original design](../2026-10-26-p30-p31-plan/index.md), lines 127–135: “A stale prepared write cannot commit after that boundary.” [Contracts](contracts.md), lines 103–112: revalidate under control then storage locks; durable revocation precedes acknowledgment and later publication fails its generation check. | Strong local ordering relative to acknowledgment, rather than a universal wall-clock completion bound. | Keep the common control/publication locks until the native effect and required sync/settlement are known, or retain an enforceable fence while unknown. Revocation must not acknowledge while an older helper can later publish under the revoked generation. Early admission alone is insufficient. |
| Source retention / managed eligibility | [Baseline](baseline.md), lines 617–638: ordinary facts expire after 90 days, reads never renew TTL, expired/missing support invalidates use. Lines 384–395 and 442–447: revalidate/retract every managed occurrence before every model dispatch, including continuations. | No demand that all old stored bytes be physically deleted at expiry. Original transcript limits are explicit. | Expired support cannot become eligible managed evidence. Late materialization must retain original expiry/lineage and cannot revive a source, renew its TTL, or make an expired dependent eligible. Exact non-model output guarantees need their own audited sink definition. Explicit faithful backups may retain expired records; that does not authorize active recall. |
| Proposal / parked-work age | [Baseline](baseline.md), lines 223–234 and 631–632; [contracts](contracts.md), lines 64–74 and 121–127: expiry invalidates acceptance codes; pending/unstarted work has seven-day bounds; expiry never confirms or retries unknown work. | No physical completion or deletion guarantee stated. | Expiry prevents a new acceptance/continuation; exact prior acceptance does not grant publication permission. Current source and consent checks remain mandatory. Preserve consumed-once state and original expiry through restart; unknown dispatched work cannot become unstarted. |
| Document stage TTL | [Document boundary](document-store-boundary.md), lines 64–85: immutable slot epoch/identity/hash, one consuming commit, one-hour host-clock TTL; “Expired append/seal/commit requests refuse”; expired reclamation uses exact epoch. | The one-hour stage TTL is an implementation-authored contract after the frozen baseline. That passage does not explicitly demand physical completion before expiry. Later strict stage gating adopts the stronger interpretation ([interposition](strict-deadline-interposition.md), lines 68–70). | A final locked admission of each exact append/seal/commit before expiry can preserve the earlier wording if the consuming decision, epoch, CAS and later use are fenced. Reclamation cannot overtake an admitted owner. This requires explicit review and compatibility documentation; an early `value.open` cannot authorize arbitrary later work. |
| Native review nonce / permit | [Review component](native-review-component.md), lines 18–40: same-process opaque permit, exact revalidation under effect locks, first genuine-owner attempt spends it, 30-second monotonic lifetime, callback exit deletes it; errors/loss after consumption are unconfirmed. [Review audit](native-review-audit.md), lines 17–18: “Expired consumption refuses; final success is withheld.” | Original component promises freshness at consumption and withholding of final success after observed expiry/loss. It does not promise cancellation/rollback of a previously consumed physical effect. | Native observed review is attestation, never effect permission. An exact one-use effect consumed while live may become unknown after expiry under the original component. It must not be reused or reported known-success through the old Review wrapper. The later late-forget receipt proves a physical effect happened, not that the original wrapper promised rollback. Current stricter forget gate still stands pending reviewed semantics. |
| Generic `state.put.write_before_ms` | [P26 design](../2026-10-19-p26-remediation/expiry-write-design.md), lines 8–14 records the user's chosen rejection of renewal when expiry occurs while waiting for approval. Lines 87–100 select CAS-first locked clock decision plus final post-staging check and explicitly disclaim physical completion in the same millisecond. | Explicitly **no**, for the original generic contract. | Preserve the exact approved field, exclusive deadline, CAS precedence, final locked decision, unchanged known-failure summary and no automatic retry. Restoring this decision contract is supported by original provenance, but current gate/manual changes require explicit review and fresh compatibility checks. Dropping the field is not a repair. |
| Retention-policy mutation deadline | [Retention deadline record](../2026-10-28-retention-publication-deadline/index.md), lines 12–35: minimum old/new effective deadline, trusted host propagation, actual wall-clock check immediately before `renameat`; unknown staging remains inspectable and review cannot be reused. | This implementation receipt specifies a pre-rename comparison, not physical syscall completion. Later strict-gate interpretation is stronger. | A pin/duration change cannot be admitted after the target's old deadline to revive expired evidence. Exact final-decision semantics and eligibility of any later materialized replacement must be reviewed, especially when changing to persistence. Cannot inherit a late remote-effect exception automatically. |

## Provenance and authority

The [first delivery design](../2026-10-26-p30-p31-plan/index.md), lines 25–33,
records the developer's selected persistent project permission and re-review for
changed scope/services/limits. The [first audit answers](../2026-10-26-p30-p31-plan-review/index.md),
lines 20–40, record next-session activation, saved headless knowledge permission,
qualified graph/PDF quality and the Rust exception; concrete retention targets are
expressly design judgments. No quoted developer answer selects physical
no-late-rename semantics. The P26 expiry decision is a recorded user choice with
a separately selected generic design; its clock-completion disclaimer is material.

Design judgments are still implementation constraints once frozen. The
[second audit](../2026-10-26-p30-p31-plan-review2/index.md), lines 19–22,
explicitly distinguishes them from new developer answers. The
[final handoff](../2026-10-26-p30-p31-final-handoff/implementation.md),
lines 71–78, requires a dated amendment for evidence changing a contract.
The [frozen contracts](contracts.md), lines 3–7, constrain implementation without
claiming current support. Later physical-deadline containment is an authored
stronger interpretation, with real adverse evidence, rather than a new verbatim
user decision. It must not be silently erased or used to pretend earlier tests
qualified atomic physical expiry.

The available-host/profile instruction does not waive authority, source retention,
review binding, safety, or usable positive journeys. [Plan acceptance](../../plan.md),
lines 930–968, still requires them on the available host. A disabled-safe subset
does not complete P30/P31. Physical deadline completion would require a separate
enforceable primitive and time/linearization definition; another userspace check,
timer kill or seccomp continuation cannot establish it.

## Candidate design for explicit review

This is a viable requirements-level direction, **not** a proved implementation or
approval to remove gates. Use separate named contracts for final publication
admission, managed eligibility at use, and strict physical deadlines. Do not rename
an old physical-deadline promise while leaving its callers/receipts ambiguous.

1. The trusted Elixir host authenticates project/worktree, source origin, active
   policy and budgets. Native helpers own only small OS operations and retained
   locks. Worker JSON, copied receipts, SDK fields, artifacts with the same name
   and arbitrary PIDs cannot create authority. Same-user hostile BEAM/native code
   remains outside the cooperative protected-state trust model; name the tested
   OS/filesystem profile exactly.
2. Journal immutable operation intent before admission; reserve finite resources
   durably. Complete slow parsing/model work outside control/storage locks.
   Before publication acquire retained cross-VM locks in control → storage order
   and any required source leases in a specified global order. Recheck actual
   identity, policy and suppression generations, source versions/deadlines, mode,
   target CAS, review binding and stage epoch. Initial reservation authorizes no
   later publication by itself.
3. Define the final admission linearization point as the trusted owner making
   the irrevocable one-use publication decision under those locks, after staging
   and all blocking validation. Sample the authoritative clock there; equality
   refuses. The selected operation binds exact operation ID, root/generation,
   target, immutable staged digest, source union, policy epoch/hash, review facts,
   stage epoch and deadline minimum. No callback, new mutable target, arbitrary
   command, rebase, additional write or retry follows that admission. Record the
   observed decision time and contract version; it is not a physical completion
   timestamp. A userspace scheduling stop after that decision is explicitly an
   in-flight admitted attempt, rather than claimed clock-atomic rename.
4. Retain lock/source ownership across the actual fixed native operation and
   required sync/receipt handling. No successor or revocation acknowledgment may
   pass an old helper that can still change the root. Owner loss must stop/fence
   dependents and prove quiescence or retain unknown/quarantine until inspection.
   Releasing an Elixir-side lock is insufficient if an old native actor survives.
   Scheduling suspension can make wall-clock settlement or revocation waiting
   unbounded; finite byte/count budgets and an attempted cancellation do not prove
   a physical deadline. Report timeout/unknown without a false successful revoke.
5. Review consumption is same-owner, exact-facts and once only. A spent permit
   cannot be serialized into a new capability, reset after timeout, transferred to
   a later task or used for another effect. Preserve the old Review wrapper's
   unknown result after expired/lost completion. Any replacement that can report a
   late known result needs a distinct reviewed result contract and exact durable
   native effect evidence; the original review event alone cannot supply it.
6. Retain original expiry and full causal source union in materialized data.
   Every later effective use checks current authority, source/suppression revisions
   and wall-clock expiry. Explicit faithful backup/historical inspection is a
   separate operation, never a grant of active eligibility. An expired source cannot support newly active durable
   evidence by copying it into a fresh record. A policy extension/pin must itself
   be admitted against a live target under its reviewed rule; never manufacture a
   later expiry from reads or a lost attempt. Reclamation/slot reuse is serialized
   against the admitted operation and exact original epoch.
7. Loss between decision, rename, sync, ledger settlement and Session receipt
   preserves uncertainty and resource liability until exact operation/root
   inspection. Known elapsed refusal proves no attempted root effect under that
   decision; partial staging may still exist. Receipt loss never rolls back a
   known effect or triggers replay. Resume distinguishes unstarted from consumed,
   admitted, unknown and settled work.

## Required evidence before enabling affected paths

No diagnostic or runtime test was rerun for this audit. Future reviewed repair
must include current positives as well as refusals:

- Live capture, saved eligible headless capture, later recall, exact proposal
  acceptance, disabled-store forget, pin/duration/session-only retention, document
  append/seal/commit and original State live renewal/fresh-expired-backup controls.
- Pause the actual unmodified owner before final decision: expiry must refuse;
  pause after decision at actual syscall entry: a late effect must have the
  explicitly chosen admitted/unknown result and must not create eligible expired
  data. Distinguish these schedules in assertions rather than declaring the
  second schedule a passed strict physical fence.
- Two OS processes race revocation/suppression, stage expiry/reclaim/slot reuse
  and target CAS. Prove no old actor writes after successful acknowledgment or
  successor admission; include parent death, retained helper, lost receipt and
  release failure. Inspect persisted roots/ledgers and actual later-use bytes.
- Re-render/stale/cross-client/foreign-owner/changed-facts/replay review controls;
  genuine live consumption followed by expiry or owner loss must preserve the
  old unknown result. Validate exact immutable operation binding and no rebase.
- Source A expired plus fresh source B must not admit A through a merged lineage;
  test continuation, compaction/resume, reads, display/export, model/MCP release
  and publication separately. No TTL renewal or unsafe retained-history projection.
- Check exclusive clock equality, clock failure and declared rollback limits,
  minimum nested deadlines/restoration, State CAS-first precedence and old receipt
  reconstruction. Qualify each actual available platform/profile and installed
  journey; missing evidence remains open.

The existing strict Collection deadline gates, reviewed-effect gate and State
deadline refusal remain unchanged by this audit. An implementation may preserve
the original generic State decision contract through a reviewed repair; it cannot
silently substitute that for a strict physical API, native Review's live-success
rule, source eligibility, or revocation acknowledgment ordering. A departure
that permits new stale-source use, widens grants or changes operator-visible
retention requires a concrete developer decision, not an inferred host waiver.
