# Independent local management-display scope review — 2026-10-29

This scoped review covers [management-display-scope.md](management-display-scope.md)
with SHA-256
`10b660919ea6eec5f4ab29bdc014b037cf29898a05061cb4721855b2b5ed7dca`,
the original [managed-forget journey](managed-forget.md),
`ManagedLifecycle.prepare/3`, `NormalizerV3.forget/3`, the standalone Management
caller and `Consent.forget_deferred/8`. It follows the
[terminal design review](../2026-10-29-native-shared-lease/guarded-terminal-integration-independent-review.md).
No code, gate or runtime control changed or ran. The [plan](../../plan.md) owns
activation and acceptance.

**Disposition: this is a faithful, explicit clarification of the original local
management purpose, subject to the deadline clarification below.** It does not
add automatic recall, inference, egress, worker delivery, saved-consent authority
or a general exception for expired source use. It does not qualify the terminal
sink or authorize enabling the still-gated management path.

The original journey deliberately supports deleting a selected retained literal
when capture is revoked/expired and original evidence is expired or unavailable.
It also requires complete native Review facts. `ManagedLifecycle.prepare/3`
places the exact full stored target and signed metadata/root context in those
facts; it does not require the original evidence to be eligible. The trusted
normalizer rederives the exact stored record, lineage metadata and root, checks
the requested suppression and then consumes the same-owner review. Its eligibility
check applies to retention; deletion expressly remains available without it.
`Consent.forget_deferred/8` likewise uses exact existing management epoch and
review rather than an automatic-capture grant. The historical management journal
retains complete target facts. Reading the faithful retained target for this
specific local deletion review was already part of that selected behavior.

The proposal appropriately makes that purpose explicit and bounded: the operator
selects one actual signed target through the standalone command; the host verifies
the existing project/management context; native display binds the exact complete
facts and real terminal/client challenge; target ownership is retained through
writes/closure; all display locks release before human input; and the effect
reacquires fresh locks and revalidates exact facts/CAS before one-use consumption.
Unavailable original support is not a missing or unauthenticated stored target.
A missing target, unknown recipe, changed epoch/root/value or invalid signature
still refuses. The scope cannot select another record, a worker display purpose,
headless approval, pin/duration/supersession or ordinary source eligibility.

**Required clarification:** define the finite trusted management-display deadline
separately from the target's historical support TTL and expired capture-policy
clock. Those old clocks are facts to label, not live capture/use grants for this
purpose; blindly including them in the terminal protocol's “minimum applicable”
deadline would prohibit the intended expired/disabled cleanup. The operation
still needs its own bounded host setup/display lifetime, current exact management
epoch and retained target/Identity/Consent/Collection ownership. A later permit
has the existing independent 30-second live-consumption rule. No clock is renewed
in the stored target and no old support becomes eligible.

Keep the eligibility label truthful: “not currently revalidated” is distinct from
a claim that an original source remains available. Do not infer live source
endorsement from the operator confirming deletion. Management journals and native
Review capsules remain private management history; their facts cannot be promoted
into an operator-statement or automatic recall channel. The proposed negative
controls for the same bytes through inference/recall/worker paths are necessary.

A positive journey still requires native-owned management header/Writer IO, the
reviewed actual tty lease/closure integration, disabled/expired capture plus
expired/unavailable-original controls, changed target/epoch during input,
wrong/reused/expired review and admitted-effect unknown without replay. The
management-only display needs the live management journal lock plus Identity,
Consent and Collection target locks; it does not need to acquire unavailable
original journals as current evidence. No production display, mutation, source
promotion or milestone acceptance follows from this purpose review. The parent
owns the proposal clarification, implementation and documentation checks.

## Accepted deadline clarification and frozen disposition

The amended scope with SHA-256
`e30d45b1135d4a2524fa10ecb02186f459d842390c40e4f58bda0f0c4cec09c9`
resolves the required clarification. It reuses the existing 120,000-ms native
review-input bound, sampled once before setup with checked wall and corresponding
monotonic budgets; an earlier trusted operation deadline only narrows it.
Acquisition, display and human waiting cannot reset that budget. Historical source
TTL and capture-policy expiry are excluded from this distinct management deadline.
The existing 30,000-ms monotonic permit begins after genuine input and preserves
its consumption/final-success rules. This explicit bounded choice is accepted;
no additional scope or architecture amendment is required by this review. The
disposition is frozen. Implementation and actual positive/adverse qualification
remain required before opening any gate.
