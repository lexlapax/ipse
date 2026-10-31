# Embedding selection bootstrap and pin — independent implementation review

Scoped review, 2026-10-29. Historical evidence for the
[implementation receipt](embedding-selection-bootstrap.md), following the
[SDK design review](embedding-selection-bootstrap-independent-review.md).
The [plan](../../plan.md) remains authoritative for completion.

Disposition: accept this frozen bootstrap/pin slice. No concrete blocking defect
was found in its requested-selection binding, read authority or optional pin
enforcement. This does **not** resolve the held
[producer source-policy boundary](shared-producer-first-page-independent-review.md).
A selection pin cannot authorize expired source egress.

## Frozen evidence checked

Independently checked manifest SHA-256
`f28479373cf24fc3d82daae2e9f1c0b8370d0d137d557fcf0b39bf6157c071b9`,
all six source/test snapshots, ten retained launch/log/helper/initial-test files,
the prior Core/CLI manifest and both complete runtime inventories. Each runtime
has exactly 698 physical regular files and one recorded directory symlink; the
walk checks symlink identity without following it. Relative path sets agree.
Exactly six BEAMs differ from the prior reviewed CLI graph: Actions, Host,
EmbeddingCall, ModelCall, Inference and Session.Invocation. Other runtime files,
including the native helper, match. Recompiling the shared inference source
emits ModelCall too; this is not broader ModelCall behavior qualification.
The retained strict compiler launcher compiles four sources into those six
owners with empty compile/runtime diagnostics.

The [verification script](embedding-selection-bootstrap-review/review-manifest.exs)
and [result](embedding-selection-bootstrap-review/review-manifest.log) record the
independent hash, file-set and overlay checks. Reviewed retained controls without
repeating them: 47152 has 14 pure passes; 47153 passes the actual approved pinned
loopback inference and mismatch case, then records the separate bootstrap
resume-helper failure; 47154 passes the two corrected bootstrap/refusal cases
with 16 excluded. The already passing inference case was not repeated.

## Authority and selection findings

`embedding.profile` has its own exact request schema and Actions v2 binding. It
uses the existing `host.embedding` capability, is read-only, and is excluded from
the create/inference predicates. Host returns the profile value from the admitted
binding. There is no profile-path call into inference execution, Usage admission,
credential preparation or provider dispatch. Missing profile and missing grant
refuse before action intent; ordinary action/read limits remain applicable.

The binding retains the complete requested public profile and existing selection
hash. Live successful results must equal that binding. Actions/Saved additionally
validate it against `metadata.embedding_profiles`, rather than merely accepting a
self-consistent profile/hash pair. The actual bootstrap control changes the model
and recomputes a consistent foreign hash/binding/result while preserving the
original header; Saved rejects it. Public profile content and selection hashing
reuse the existing Profiles owner, including its existing digest fields. The
profile describes configured selection, not actual model weights or a provider's
reported model identity.

The optional `expected_selection_sha256` belongs only to the exact v2 create
request. It therefore participates in request identity and full approval
arguments. Nil/malformed hashes, extra fields and v1 pins refuse. Binding
construction checks the configured selection before approval/intent; binding
validation, execution/dispatch preparation and result validation repeat the
comparison. Existing unpinned v1/v2 requests remain valid. The actual control
observes one approval, one Usage admission and one synthetic loopback provider
request, with matching result selection and Saved reconstruction. Its subsequent
mismatch creates no approval, intent or second provider request.

## Resume repair and limits

The retained initial bootstrap test reaches the successful bootstrap and Saved
tamper checks before failing its inherited byte-identical-resume assertion.
Current native startup deliberately appends a fresh release-owner marker. The
test-only repair requires the original journal as an unchanged prefix and exactly
one appended `session_release_owner_started` record validated by the existing
release-receipt predicate, with a new owner ID absent from prior markers. Legacy
journals still require zero appended bytes. It also checks no additional action
or provider request. This is a narrow fixture correction, not permission for
arbitrary resume changes or a production journaling change.

Session tests use an isolated synthetic loopback endpoint and actual host action,
approval, accounting and Saved paths. They establish neither live-model quality
nor external-service compatibility. Existing teardown removed the temporary raw
journals and worker artifacts; only the pinned source, launchers, logs and host
runtime graphs remain. This review therefore does not claim independent retained
raw-journal/artifact reconstruction. The graph is an overlay on the recorded
ancestor, not an all-current-source build or coherent packaged release.

No runtime tests, model calls, gate changes or production edits were performed
for this review. Producer adoption, trusted source-currentness/TTL enforcement
at inference dispatch, and broader package/source qualification remain open.
