# Independent review of retained management snapshot reads

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the snapshot-read receipt](management-snapshot-read.md), final v2 manifest
SHA-256 `01ccdeba3b75a58906000ac8836c6f25e3cca6a2d65f2a34a8aabb31805dab0c`,
against the accepted [management purpose](management-display-scope.md) and
[its independent review](management-display-scope-independent-review.md).
No runtime/native edits, model/network calls or passing test reruns were made
by this review.

Accepted as a trusted host callback for an existing exact local management
snapshot. No concrete scoped blocker was found. It is not active capture,
source eligibility, display permission, publication, saved consent, an SDK
bridge or a production Management call site. Identity, target Collection,
management journal and eventual native operator ownership remain independent
requirements.

The new API requires a safe positive integer epoch and SHA-256 management
fingerprint. Its existing-only transaction validates the root/project and
protected existing directories/files, acquires the actual native control lock,
checks retained lock/writer/control identities and quota, and reads the existing
validated project ledger through that owner. It requires the stored epoch to
match exactly and recomputes `management.v1` over project, epoch and the actual
stored policy. A nil revoked policy is distinct from the old policy and epoch;
substitution, stale pins and numeric aliases do not enter the user callback.
Only epoch and policy are passed to that callback, not reservation or effect
capabilities.

The expired/revoked exception is faithful to local target-management purpose.
`with_existing_policy` retains its existing active-policy and quarantine checks;
those capture/consumer conditions are not weakened. The new helper deliberately
does not interpret expired or nil policy as a live grant. A management digest is
a content pin, not an authority token, and cannot authenticate a target, operator
input or native display destination by itself.

Known callback data returns only after the existing final retained-file and
native ownership checks and confirmed release. A helper lost while the callback
is paused cannot turn the old snapshot into known success after a new owner
revokes. No lock is dropped and reacquired to imitate continuous ownership.
The source keeps the existing-only path separate from creation, pending-file
reclamation and mutation recovery; missing state never initializes a ledger.
Existing accounting, pending bytes and stored values are not rewritten by a
normal inspection.

The shared `existing_callback` adapter now preserves a typed unknown result.
Consequently, an unknown callback stops the `with` before success-only final
identity checks, then still attempts native release. A successful release
preserves that unknown; unconfirmed release replaces it with another unknown.
Neither branch can become settled data. The same behavior applies to the older
existing-policy callback. This preserves uncertainty rather than creating retry
or settlement authority. Callback exceptions are already converted to unknown
and do not skip the release path.

Callbacks remain trusted host code. The process-local held-lock guard refuses
nested Consent mutation and the existing reverse-order entry restriction remains.
It does not sandbox arbitrary Elixir IO. The documented callback prohibition on
inference, untrusted code and storage/service effects is a host contract, not
an enforcement mechanism against hostile code in the same VM. Future native
ownership/display coordination needs separately reviewed admission and complete
lease closure. Callback completion is not later-use authority after release,
and the API adds no complete operation/display deadline.

[Manifest verification](management-snapshot-read-review/review-manifest.exs) and
[its output](management-snapshot-read-review/review-manifest.log) validate the
final six-entry manifest, two source snapshots and670 runtime files, plus the
initial seven-entry cohort, its three sources and670 runtime files. Compared
with the frozen management-journal-v3 graph, only Consent BEAM changes. Helper
`a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995`
is unchanged; later native terminal and other host graphs are excluded. The
frozen source delta is the new callback API and the uncertainty-preserving arm.
There is no coherent new whole-source or terminal integration qualification.

The recorded47099 compile reports success and47100 reports five native passes.
They cover expired capture refusal versus locked exact management inspection,
a real revocation contender blocked until release, new revoked epoch/fingerprint,
malformed/stale pins, absence and pending preservation, actual helper loss with
new-owner revocation, unknown callbacks through both APIs and same-callback
mutation refusal. Synthetic policies are already expired at the real host clock;
no host clock was changed. These are native controls and exact snapshot reads,
not successful target display or knowledge publication.

The initial47097 fixture failed after setup by using ExUnit's reserved `file`
context key; no product assertion ran. Its archived invalid fixture and failure
log remain distinct from47098's four corrected passes and the final v2 fifth
case. No aggregate was repeated or invented to enlarge coverage.

Actual Management callers, independently admitted native ownership/display,
complete Identity/Consent/Collection/journal target leases, Review and live
one-use effect revalidation, full source compatibility and final adversarial
audit remain open. No gate or broader milestone completion follows here.
