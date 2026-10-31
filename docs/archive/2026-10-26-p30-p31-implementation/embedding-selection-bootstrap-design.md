# Public embedding selection bootstrap and pin — 2026-10-29

Narrow SDK gap design; [independent review](embedding-selection-bootstrap-independent-review.md)
accepts the owner choice with the explicit snapshot/result binding described below.
Implementation and exact runtime evidence remain separate from this design record.
The [plan](../../plan.md) owns acceptance. The [first public producer](shared-producer-first-page.md)
currently requires a selection hash that its fixture obtains through a trusted
host API, and checks that hash only after inference. Neither an operator-facing
alias nor a synthetic fixture closes the public bootstrap or pre-egress gap.

## Existing owners and missing contract

`Config.Profiles.embedding_snapshot/1` already constructs bounded public profile
metadata: ID, provider, requested model, billing mode, endpoint hash, dimensions,
dimension mode, timeout and public destination. `embedding_selection_sha256/2`
computes the existing v2 selection digest. Session stores the snapshot in its
header and requires exact equality when resuming. This is configured selection,
not the identity of an eventual model response. No new hash protocol is needed.

`EmbeddingCall` currently validates exactly the five request fields `op`,
`version`, `profile`, `inputs`, `timeout_ms`, with versions 1 and 2. Its existing
binding includes execution and destination, is displayed for approval, and is
validated against the Session snapshot. v2 results include selection hashes.
There is no request field comparing the producer's expected hash before binding.
`context.available` reports context capacity only; Collection and source readers
do not expose the embedding snapshot. Importing configuration through a worker
filesystem read or making a dummy external inference is not a suitable bootstrap.

## Proposed bounded change

1. Add read-only `embedding.profile` under the existing explicit `host.embedding`
   capability. Its closed request contains `op`, `version: 1`, and `profile`.
   Return just the requested configured public profile plus the existing selection
   digest. Read from the frozen Session scope; no provider request, credentials,
   model loading, service reservation, quota charge or alias fallback occurs.
   Bind the read-only Actions v2 intent to that complete profile/hash and validate
   the returned value against the exact requested frozen snapshot in live Actions
   and Saved reconstruction, not merely a self-consistent supplied hash.
   Unknown or disabled profiles refuse. The result does not claim connectivity,
   loaded model identity, quality, source eligibility or inference permission.
2. Permit optional `expected_selection_sha256` only on `embedding.create` v2.
   Preserve the old exact v1/v2 shapes and v2 result version. Validate a present
   hash as SHA-256, compare it with the existing binding's execution/destination
   digest before approval/intent admission, and validate it again wherever the
   existing binding is checked, including saved reconstruction and execution.
   A mismatch refuses without contacting a provider or changing profiles.
   Absence preserves the existing explicit adapter contract; the shared producer
   must supply the pin. Do not mint authority from the digest or treat a reported
   model mismatch as an excuse to fall back.
3. Keep bootstrap and pinning within the existing Actions, EmbeddingCall,
   Session snapshot and Host dispatch owners. Reuse existing closed schemas,
   approval/journal binding and result validation. Do not add a process, package,
   alternate credential source or new service-selection mechanism.

Focused controls must cover old v1/v2 compatibility; exact read-only capability
and public-field bounds; disabled/missing profiles; malformed/extra pin fields;
changed provider/model/dimensions/destination; saved binding tampering; matching
pin actual registered-provider invocation; mismatch with zero provider calls;
ordinary approvals and replay. Use synthetic loopback transport, not a live model.

## Separate source-policy gap

This proposal does not enforce source freshness or immutable captured source
bindings across a later approval wait. The producer needs current eligibility
checks before its durable claim and every batch, plus a separately reviewed
trusted post-approval source/root/deadline precondition before inference dispatch.
Approval is not a waiver of domain source policy. Final publication CAS does not
undo earlier egress, and a stored unselected vector page does not make stale-source
egress acceptable. Existing managed dispatch machinery must be evaluated before
introducing another mechanism. Finite-TTL support remains in the full goal;
temporary refusal cannot be presented as its delivery.
