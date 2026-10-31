# Exact local management review scope — 2026-10-29

Concrete scope amendment for implementation review, not a runtime gate change.
Read the [reviewed-forget direction](reviewed-forget-restoration-direction.md)
and the [original reviewed management journey](managed-forget.md). The
[plan](../../plan.md) owns acceptance. The generic native
[terminal lease design](../2026-10-29-native-shared-lease/guarded-terminal-integration-design.md)
must still be implemented and qualified before this route is enabled.

## Preserve the original management purpose

The original standalone management path deliberately accepts a selected retained
literal even when capture is disabled or its original evidence has expired or
become unavailable. `ManagedLifecycle.prepare/3` includes the complete stored
target in the proposed facts; native Review displays those facts, and
`NormalizerV3.prepare_forget/3` rederives the exact target before consuming the
one-use review. Requiring active capture permission or currently eligible
inference support would prevent the very cleanup this path was designed to
provide. Conversely, presenting those bytes as newly eligible source evidence
would exceed management authority.

Implement a host-only **local management review** purpose with this exact scope:

- The operator explicitly selects the literal key through the standalone
  management command. The trusted host resolves an existing project and
  management epoch and reads its stored record through the protected Collection
  owner. The record is a retained derivative snapshot, not a fresh assertion
  that its original source is still available or true.
- The complete proposed facts include the exact key, revision, full stored value,
  value hash, authenticated metadata/root, requested deletion or session-only
  suppression, operation digest and original provenance. Display must label the
  target's expiry/source eligibility honestly. Do not omit proposed content to
  avoid implementing its protected native display boundary.
- This scope permits only that bounded local native review of the selected
  stored record, including an expired record. It is separate from automatic
  recall, model/MCP egress, worker delivery and source publication. Saved capture
  consent, `--yes`, copied receipts or a worker-supplied purpose cannot select it.
  The existing actual terminal/client challenge remains mandatory for mutation.
- Revalidate the actual project, management epoch, selected root/record/hash and
  proposed operation under Identity, Consent and Collection ownership before
  native display admission. Transfer the exact required retained lock
  descriptions to the actual tty owners. Keep them through display writes and
  confirmed writer/descriptor closure. Their scope is the stored management
  target; expired original journals are not treated as live inference support.
- Release display leases before waiting for input. After genuine confirmation,
  reacquire and rederive the complete exact facts and current CAS under the
  effect locks. Any changed target, epoch, suppression or operation refuses.
  Consume the same-owner review once while live. Effect loss/expiry after
  consumption stays unknown under the original wrapper; no retry or successful
  late review receipt is invented.

This is faithful local inspection for a requested management action, like an
explicit faithful export retaining expired records. It does not renew TTL,
erase old disclosures or allow an automated consumer to use expired evidence.
The native observation attests only to the exact management command and facts.
It must not become a statement/category endorsement of the target's contents.

The expired target's old recall deadline is not a live-evidence display grant
for this distinct faithful management purpose. Native display still has its
own finite setup/write deadline and live owner controls. Use the existing
120,000-ms native review-input bound measured once at operation start: the host
binds its checked wall time plus that duration and the corresponding monotonic
budget before setup; a trusted earlier operation deadline can only narrow it.
Descriptor acquisition, display and input waiting do not reset that budget.
The separate existing 30,000-ms monotonic Review permit starts after genuine
input returns and still governs live one-use consumption and final success.
The expired source TTL and capture-policy `expires_at_ms` do not select this
management deadline. Do not reuse this exception in
the generic source-derived display path or manufacture a renewed source TTL.

The immediate standalone implementation needs the management journal owner and
the three target owners (Identity, Consent and Collection), within the existing
131-descriptor bound. The full generic combination of 128 external sources,
an additional live Session and all three target owners would need 132 distinct
leases. It is outside this increment unless an exact role alias is proved;
do not silently increase the cap or omit a required owner to make it fit.

## Required controls

Prove full-facts review and deletion/session suppression with revoked capture,
expired target and unavailable original source, while the current stored target
and management epoch still match. Separately prove that the same bytes remain
ineligible for ordinary recall, capture endorsement, model/MCP release and worker
delivery. Test changed root/target/epoch during input wait, stale/cross-client
confirmation and expired/reused review. Verify native display ownership,
protected-prompt redraw removal and actual all-copy closure before revocation or
target replacement can acknowledge. No protected write may be inferred from
the act of displaying a review.

Management journals must use the repaired actual native lock owner for fresh
header, intent, result and recovery. Their retained complete facts are private
management history, not an operator-statement provenance channel. No background
review, model call, workspace effect or source promotion follows from this scope.
The earlier full-facts path and all adverse gate evidence remain historical;
this amendment alone qualifies neither the display sink nor a positive journey.
