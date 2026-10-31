# Independent review of the held signed-target adapter

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the held-target receipt](management-held-target.md), manifest SHA-256
`65505253ebcc71b826a5849829f8e9703a41b11369f90cd6567f36aad49a7d09`,
against the repaired [Collection callback](collection-held-read-independent-review.md#additive-v2-repair-disposition)
and [Consent snapshot](management-snapshot-read-independent-review.md).
No runtime edits, passing test reruns, model/network or new native calls were
made by this review.

Accepted as a trusted host adapter for a held signed literal observation. No
concrete scoped blocker was found. This authenticates stored structure under
retained Collection ownership; it is neither current-source eligibility nor
capture, display, Review, publication or live-use authority. No production
Management caller or protected gate is enabled.

The new entry accepts the existing exact get-record request for a valid `note.`
lineage, selected literal recipe and matching active managed-metadata-v3 domain
catalog. It delegates ownership to repaired `Collection.with_managed_read`,
then reuses the existing literal parser. Its get-many adapter validates the
bounded request, requires a present root, uses the exact retained root bytes/
manifest and reads each key through the same native closure. Neighbor reads use
the existing four-unit directory operation. There is no alternate filesystem IO
or worker protocol, and all reads share the32-unit budget and exact callback
lifetime. The ordinary literal path requires13 units: three initial keys, two
four-unit neighbor selections and two selected metadata-page reads.

Before invoking the continuation, the common parser requires the actual public
record, fixed signed format and absent legacy override, opens the signed live
and anchor rows, rederives the literal candidate/lineage from the selected recipe,
and binds the signed metadata to the actual value hash. Neighbor and selected
page reads must have the exact first summary and root witness. Signed page
verification retains its opaque matching domain-auth capability and range/ref
checks. A substituted recipe or changed public value cannot reach the trusted
continuation with the old signed metadata.

The released-view literal reader and existing metadata-row users now delegate
to those same parsing functions. Their observation bytes, request/result digests,
root witness and metadata interpretation are preserved. The focused proposal
regression protects that shared helper; this new API itself admits literals,
not held pending-proposal or history selection. Missing roots/records, override
records, retired targets and wrong format do not gain a fallback path.

The trusted continuation runs while Collection is held, and the surrounding
Identity/domain-auth and management Consent callbacks are a caller obligation.
The adapter does not accept a Consent fingerprint or independently prove that
outer Consent ownership exists. The positive fixture supplies that actual stack;
no JSON recipe, catalog map or proof-shaped value alone supplies the opaque
domain capability. Same-VM hostile code is not the boundary.

The returned proof remains original stored provenance, not an authenticated
current source or operator endorsement. Signed expiry can already be past; it
is returned faithfully without renewing it or converting revoked capture into
consent. Continuation success still passes the repaired Collection token/native
checks and release, and actual caller composition retains the outer owners.
A typed unknown is not forced into an observation success. This does not fence
arbitrary trusted callback IO or authorize native display; its separate complete
ownership, payload, operation and closure admission remains necessary.

[Verification](management-held-target-review/review-manifest.exs) and
[its result](management-held-target-review/review-manifest.log) validate all11
manifest entries, seven source/fixture snapshots and726 runtime files. The
runtime differs from Collection-read v2 only in ObservedRead BEAM; the repaired
Collection, Directory, Consent and helper
`a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995`
remain unchanged. Notes, Contracts and Records sources are separately loaded
fixture dependencies, not extra overlaid host BEAMs. Later tty/Session/Host
cohorts and a whole-source build are excluded.

The retained47113 compile reports empty diagnostics.47115 reports four selected
actual native tests,33excluded, with no warning. They establish exact equality
to the existing signed reader under a real Identity→Consent→Collection stack
with expired target and revoked synthetic capture policy; unchanged revoked
accounting; pre-continuation refusal for substituted recipe/changed value; and
existing literal/proposal parsing. The synthetic signed fixture and native
storage/domain authentication are real controls, not ordinary acquisition or
current source truth. Owner-loss, history, cancellation and display schedules
are not supplied by these four passes.

47114's two passes retain the Contracts/Records fixture load-order warning. The
final fixture loads Contracts before Records. Its complete initial fixture
snapshot was not retained, so that earlier source cohort is not independently
rebuildable and is not relabeled warning-free. No passing aggregate was repeated.

Actual Management command/journal composition, matched tty and native owners,
all-copy close and confirmed exporter settlement, real-chain loss/backpressure,
Review release/input and live one-use effect revalidation, coherent baseline/
package checks and final audit remain open. No broader acceptance follows.
