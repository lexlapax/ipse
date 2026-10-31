# Independent shared controller and selected-read review — 2026-10-29

This historical review covers the frozen [controller/read increment](shared-generation-controller-read.md)
and [citation-origin correction](shared-citation-origin-canonical.md), following
the [directory review](shared-generation-directory-independent-review.md) and
[cardinality repair](shared-directory-cardinality.md). The [plan](../../plan.md)
owns current acceptance status. This review makes no runtime, native, production
or provider changes. It does not qualify protected publication, complete Word
quality, model provenance, later-use authority, streamed finalization, atomic
selection, GC, migration or populated capacity.

## Evidence identity and limits

The [manifest verifier](shared-controller-read-review/review-manifests.exs) checked
controller manifest digest
`e24c54dba3017d8d278715e984660b0d0d9dc9bd6db306baa637196572df733a`
and origin manifest digest
`57b9d3d6b83c7021e728dd59eb5b9770a81ac745791af6231a9aac49e3c0e11a`.
It verified all 22 controller source files, 18 logs, 29 artifact inventories
containing 533 files, 209 host BEAM hashes, the native helper, and three ancestor
manifest hashes. It also verified both origin repair sources, three logs,
14 repaired feature BEAMs, the pre-repair generation BEAM and the original probe.
The [result](shared-controller-read-review/review-manifests.log) is retained.
Generated sources and BEAMs remain under the manifest's `_build` paths; the
verifier is a local retained-evidence check, not a fresh-checkout build recipe.

The passing suites were inspected rather than repeated. The exact `46940`
fixture exercises the official public Corpus worker through SDK reads: 93 reads,
zero effects, two requested sources, 34 supplied 32-dimensional vectors and four
supplied literal quote facts. At its single captured `as_of_ms`, two eligible
claims return and two expired facts produce explicit exclusions. The typed
partial Word citation and warnings remain, `status` is `partial`, and coverage
is incomplete. Changed model selection, an expired requested source, a corrupted
vector page and a changed catalog floor refuse without claims or evidence.

The fixture's raw sources, projections and selection are trusted untimed native
setup data. They do not establish protected acquisition or ingestion, actual
model inference, representative ordinary Word quality, or installed-user
acceptance. Full private vector hydration is not a public full-vector frame-bound
qualification. The current read bound can refuse wider selections; dry estimates
and directory geometry do not measure whole-profile or replacement peak capacity.

The exact `46941` control seeds an existing selected generation and compares its
complete physical root record before and after refused begin and abort attempts.
Inspection returns the retained job's physical revision. Both mutations propose
strict prepared metadata and hit `document_store_deadline_unavailable`; neither
successfully writes a job nor demonstrates a working native abort. The `46934`
append, changed-catalog/model, aborted-job, startup-coherence and unknown-stop
controls are pure protocol fixtures. Their unknown result proves no next request
or continuation; it is not native unknown-after-commit qualification.

## Concrete continuation defect

One integrity defect was reproduced against the exact retained
`tested-fixture-partial-hydration-final` artifact. The
[counterexample](shared-controller-read-review/review-skipped-immutables.exs)
constructs a valid eight-source append and responds only to its bounded read
requests. An ordinary append first proposes a content-addressed `gensrc` value.
Editing its continuation to retain the exact computed plan digest while setting
`unit` to the immutable-value count changes the first proposed effect to
`genjob.notes` metadata. All five required group/header/summary values are absent
from the simulated store, and none were read. The proposed job nevertheless
advances to cursor eight with one summary reference. The
[result](shared-controller-read-review/review-skipped-immutables.log) is retained:

```text
required_immutable_values: 5
required_immutable_values_present: 0
required_immutable_values_read: 0
proposed_job_cursor: 8
proposed_job_summary_count: 1
edited_token_first_target: "genjob.notes"
native_operations: 0
protected_publication_demonstrated: false
```

`Job.plan/1` checks the reconstructed plan digest, unit bound and metadata-stage
count, then resumes at the caller-supplied unit. A digest binds the plan but does
not prove prior immutable writes occurred. The controller verifies sealed
metadata stages before consumption, but the frozen implementation never verifies
that every referenced immutable value exists with its exact planned contents
before preparing metadata. Thus an edited continuation can skip the prerequisite
writes. The current strict gate prevents the first proposed metadata mutation;
the probe does not demonstrate native publication or a selected-root change.
The component owner received the exact script and result for repair.

## Other inspected boundaries

Selected hydration binds the current catalog, root digest, generation/floor and
exact selectors. It authenticates all manifest pages before directory lookup,
selected headers, all selected group pages, and complete raw source bundles.
Every native read generation must agree; the final read rechecks the exact
catalog. Canonical group repacking validates the complete vector/input/fact and
citation payload before output. Source eligibility uses the captured query time.
The result explicitly denies later-use authority and model receipt provenance.
No further concrete selected-read defect was found in this scope.

The origin correction regenerates each complete citation from its exact raw
source/chunk/span and requires strict equality, closing the demonstrated nested
`1` versus `1.0` receipt alias without changing legacy Evidence/Projection
validation. The frozen focused regression proves canonical exact round-trip,
legacy acceptance of the alias with unchanged fact ID, and shared refusal. Its
recorded `46937` result and the later actual public hydration were inspected.
No additional citation losslessness defect was found.

The job controller deliberately ends group staging at `manifests` and reports
`finalization_available: false`. Its final metadata operation switches job plus
captured catalog, and never the selected root. Streamed reductions/manifests and
the final root/job/catalog selection remain unimplemented. No completed
milestone, full-profile query acceptance or protected write acceptance follows
from these receipts. The parent owns plan/index updates and documentation checks.

## Prerequisite repair disposition

The additive [prerequisite correction](shared-job-prerequisites.md) addresses the
private continuation defect above. Its manifest digest
`1945be650522a3d6d06317f834640c4de5112981d72e3f54f82980e1f6d3cffd`
verified against all four frozen source files, the focused log, fourteen exact
compiled feature BEAMs, the predecessor manifest, the original counterexample and
its log, and the original frozen fixture factory. The
[verifier](shared-controller-read-review/review-prerequisite-manifest.exs) and
[result](shared-controller-read-review/review-prerequisite-manifest.log) are retained.

The reviewer reran only the original skipped-immutable counterexample against
the retained repaired artifact. The
[repair probe](shared-controller-read-review/review-skipped-immutables-repair.exs)
reuses the original synthetic setup and read simulator, changing its artifact and
terminal observation. With the same five prerequisite values absent and the same
edited unit cursor, it now reads the prerequisite descriptor and refuses with
`generation_prerequisite_missing` before proposing any effect. The
[result](shared-controller-read-review/review-skipped-immutables-repair.log)
records zero proposed effects and zero native operations. The original frozen
probe and result remain unchanged.

Source comparison confirms that every resumed metadata entry position, including
direct finish, authenticates all immutable keys against exact complete-value
hashes and byte counts. Missing and mismatched descriptors refuse. After both
owned sealed metadata stages are inspected with their exact contents and
expected physical revisions, a second prerequisite pass uses that same native
generation. The final commit uses `value_commit_at` to send this verified
generation directly, with no intervening snapshot that could adopt a later
namespace state. Its successful reply must advance the pinned generation by
exactly one; unknown or inconsistent success stops without a continuation.
Legacy `value_commit` retains its existing behavior.

The frozen `46942` focused evidence was inspected rather than rerun. It covers
all three edited metadata positions, missing/mismatched and exact-present
prerequisites, both five-value verification passes, final generation 500 without
a fresh snapshot, unknown/inconsistent-generation stop, and next job revision
501. No further concrete defect was found in this narrow repair. This closes the
reported private checkpoint defect; it does not establish successful protected
writes, native race/unknown-after-commit qualification, a public append surface,
authority escalation, or completed generation selection. Current public/native
write gates and the broader acceptance limits remain unchanged. The parent
batches documentation validation and commits.
