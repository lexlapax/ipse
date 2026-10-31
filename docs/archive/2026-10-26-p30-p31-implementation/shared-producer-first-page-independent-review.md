# Independent review of the first public shared-vector producer

Scoped read-only review, 2026-10-29. The [plan](../../plan.md) owns acceptance.
This reviews [the first-page receipt](shared-producer-first-page.md), its
[bounded design](shared-producer-v1-design.md) and manifest SHA-256
`92c215154e5d948f66f02adb12af21793f9619d3c69cdb83a5a66c9c1d6a5245`.
No production edits, aggregate/controller tests, native/model effects or network
calls were made by this review.

## Disposition: source-policy hold

Do not accept this cohort as a public inference producer while it can send
policy-ineligible source bytes. A durable claim and explicit destination/input
approval cannot waive source policy. This is separate from the already
documented post-response selection check and from later page publication.

The concrete source path is in the frozen
[Producer](shared-producer-first-page/source/extensions/knowledge/src/store/collection/producer.ex):
`:catalog_page` requests `source_bundles` with `as_of_ms: 0`; `:bundles`
authenticates catalog membership and complete bundle hashes but never calls
`Evidence.current?/2`. After confirmed claim commit, `infer/1` emits embedding
requests from captured text, and does so again for each later batch without a
fresh eligibility or anchor check. Existing eligibility requires observation
time no later than now, an unexpired finite deadline and nonhistorical origin.
Thus an already expired, historical or future-dated authenticated bundle can
reach inference. Expiry during the invocation need not alter any checked
anchor, so final CAS can also store that unselected page.

The implementation owner confirmed this source reading. This is an
inspection-based reachable-policy finding, not a new observed expired-source
network counterexample. The actual positive fixture does not qualify that
negative case. Later query filtering, a retained source-set digest, no selected
root change, or full-argument approval cannot retroactively fence egress.

## Bounded repair requirements

Keep the first-page scope and original cohort immutable. Authenticate and check
the supported current source policy before creating a claim and before every
new inference batch. The check must include original observation time,
historical state and finite expiry, with equality refusing. Bind the exact
captured source versions/inputs and Job/catalog/root/pending claim; changed
bindings cannot silently rebase. Stop without a retry/adoption token on
expiry, change or unknown, preserving the existing pending/unknown liability.
Account for every added read and effect under the same 512/16 bounds; do not trim
inputs or receipts to recover capacity.

A worker check before emitting `embedding.create` alone does not enforce a
post-approval dispatch boundary: an operator can wait while source policy
expires or changes. The current request carries neither source eligibility nor
expected source-state guards into trusted Host inference admission. Root and
the implementation owner must choose a reviewed narrow Host-owned source-bound
admission using existing owners, or a genuinely fail-closed supported subset
until that boundary exists. Unsupported source policy must refuse, not be
declared waived by explicit endpoint approval. Do not label a worker precheck,
final publication CAS, or query eligibility as that dispatch fence.

Focused controls should show zero inference admissions for expired, historical
and future sources; expiry/change while awaiting approval must be refused at
the actual selected policy boundary. Changed source/Job/catalog/root/pending
bindings between batches must stop further inference. Existing claim-before-
inference, mismatch/unknown/no-replay, final CAS and combined bounds must remain.
No new runtime counterexample was needed to identify this hold; repair controls
must attach to the repaired exact source/artifact/Host cohort.

## Evidence verified and unaffected findings

The [verification script](shared-producer-first-page-review/review-manifest.exs)
and [result](shared-producer-first-page-review/review-manifest.log) verify all
725 pinned rows: fifteen sources, eight logs, four actual-data reports,
26 artifact files, 669 resolved runtime paths, two ancestors and the design
snapshot. The runtime inventory pins all non-cache physical runtime files;
36 existing `.mix` cache files are outside it and nine telemetry sources are
reached through the inherited source symlink. It is not an all-current-source
or complete physical-directory inventory. Existing executable module changes
against the compact artifact are Corpus, Profiles and Generation, plus the new
Producer module; Adapters, Evidence, Job and other existing controller code
digests remain unchanged. Host/native/quota code is unchanged.

The captured actual synthetic journal independently verifies that confirmed
claim commit precedes embedding intent. Its ready receipt operation/source and
canonical/raw input hashes match the actual EffectResult, and both shared-page
float32 byte arrays equal that actual source. This supports the one executed
registered loopback receipt flow, not authentication of arbitrary historical
stored receipt shapes or paid/model-quality evidence. The existing
`model_receipt_provenance` flag correctly remains false.

The opt-in dense preset adds embedding/result capabilities; the old document
preset grants are unchanged and no model-completion capability is added.
Requests accept only the closed first-page arguments, with configured alias
selection and explicit normal approvals. Claim preparation checks complete
stages and captured anchors at one native generation before CAS. Only its
confirming volatile invocation enters inference. Unknown inference/commit
outcomes stop; a later pending/ready record offers no retry or active-stage
adoption. Public `unknown_effect` is a diagnostic refusal code, not proof that
no effect or durable claim occurred.

Adapters validate bounded result pages, operation/source/input/vector hashes,
finite float32 coordinates and complete vector lengths. Producer checks actual
reported profile/model/dimensions/encoding/selection against the expectation.
The existing request has no expected-selection dispatch guard: an altered
registered alias/model can be contacted before returned mismatch is detected.
That documented limitation prevents publication but remains a separate
pre-egress boundary; no implicit provider/billing fallback is qualified.

Final page/ready preparation verifies complete stage identities, hashes, sizes
and expected revisions, then rechecks Job/catalog/root and pending claim at the
same generation and commits without rebase. Old selected evidence and Job cursor
remain unchanged. The new vector-page adapter uses the existing shared row/page
codec, with original source/chunk positions and complete source-set commitment;
the retained full-page control compares exact old `pack_group` bytes.

I inspected strict build, isolated five-case controls, actual Session and
read-only journal reduction. The closed eight-vector case reports 69 reads,
12 effects, four calls, 45,064-byte page, 4,354-byte ready metadata and a
12,759-byte maximum SDK frame. The actual two-vector case reports 51 reads/
6 effects and the 783,207-byte/287-event captured journal. These are distinct
synthetic cohorts, not populated full-profile capacity. Initial short-fixture,
sandbox and wrong event-field failures remain preserved; the later portable
wrapper change is not another native qualification.

Remaining pages, facts, group/header/summary append, selected-root completion,
bootstrap, explicit abandonment/recovery, provenance packing, full operation-ID
ledger and source/raw/lexical/native/journal/rebuild peaks remain open. The
first page does not qualify GC/migration, representative Word fidelity or the
complete C1b/F profile, independently of the blocking source-policy repair.
