# Independent review of embedding selection bootstrap and pinning

Design/source review, 2026-10-29. The [plan](../../plan.md) owns acceptance.
This reviews [the proposal](embedding-selection-bootstrap-design.md) against
`Config.Profiles`, `EmbeddingCall` in `extension/inference.ex`, Actions, Invocation,
Host dispatch and Session snapshot/resume ownership. No implementation, runtime
test, provider call or gate change was made by this review.

## Disposition and required precision

Accepted as a justified narrow SDK gap, subject to the binding requirements
below. Existing public snapshot and hash owners are sufficient; no new protocol,
process, dependency or service-selection mechanism is needed. Implementation
and focused compatibility/zero-egress controls remain required.

The public producer currently cannot bootstrap its expected configured selection
without a trusted host-only fixture call or actual inference. `context.available`
does not supply this metadata. `Profiles.embedding_snapshot/1` already produces
the bounded public configuration and destination; Session freezes it in its
header and requires exact equality on resume. Existing
`embedding_selection_sha256/2` binds profile/operation/provider/requested model,
billing, destination origin/target and dimension semantics. Reuse that digest
exactly. It intentionally omits per-request timeout; bootstrap must not invent
a different hash by including every returned metadata field.

Read-only `embedding.profile` should return one closed requested public profile
and that digest from the frozen Session scope, under existing explicit
`host.embedding` capability/current invocation admission. Refuse absent/disabled
profiles. It must not load a model, probe connectivity, resolve alternate
credentials, reserve or charge inference Usage, or contact a provider. Keep this
read on its own dispatch/result branch rather than accidentally classifying it
as an `embedding.create` effect/source.

**Required explicit amendment:** validate both returned profile and digest
against that exact requested entry in the frozen Session snapshot in live
Actions and Saved reconstruction. Closed shape plus a self-consistent forged
profile/hash is insufficient. Preserve request/identity/parent binding and
bounded public-field validation; do not expose credentials or runtime internals.
This refines the proposal's stated existing-owner choice, not a new authority
mechanism.

Root accepted this clarification: the proposed separate read-only Actions v2
branch uses an `embedding_profile` binding containing the requested public
snapshot and selection hash, compares it exactly to frozen
`metadata.embedding_profiles`, and binds the result to it. Create's operation,
inference and source predicates remain create-only. This resolves the design
amendment; it is not yet implementation or runtime acceptance.

## Optional create pin and compatibility

Only v2 `embedding.create` may add `expected_selection_sha256`. Absent fields
must preserve the existing exact v1/v2 request/result contract. A present nil,
malformed value, extra field or v1 pin refuses. The pin remains part of the
immutable request digest and full approval arguments. Compare it to the
execution/destination selection before intent/approval admission, then again
through every existing binding-validation route, including execution and Saved
reconstruction. Matching a pin cannot replace exact frozen-scope validation.

This fences changed configured provider/model/dimensions/destination before
provider admission. It does not attest to the reported model, connectivity,
quality or current source eligibility. Keep the existing post-response reported
model/selection checks and no fallback behavior. Resume/config changes and
tampered bindings cannot silently select another destination. The producer
must send the pin once its public bootstrap exists.

Focused implementation evidence must cover old v1/v2 behavior, read capability
and snapshot/result binding, disabled/unknown profiles, all malformed pin forms,
configuration/destination changes, Saved tampering, matching actual loopback
inference and mismatched pins with zero provider calls. Ordinary create approval,
journal provenance and unknown/no-replay behavior remain unchanged.

## Separate source-policy hold

The [first producer hold](shared-producer-first-page-independent-review.md)
remains unresolved. Selection bootstrap and pinning do not bind source policy
across approval or make stale/historical source bytes eligible. Current source
checks and a trusted post-approval source/root/deadline dispatch precondition
need their own reviewed implementation. Existing managed-dispatch owners should
be evaluated first. Explicit destination approval and final page CAS cannot
waive or retroactively repair source egress. Temporary finite-TTL refusal cannot
be presented as full finite-TTL delivery.
