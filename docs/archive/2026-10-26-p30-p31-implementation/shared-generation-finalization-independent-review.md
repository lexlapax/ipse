# Independent shared-generation finalization review — 2026-10-29

This additive scoped review covers the frozen [finalization increment](shared-generation-finalization.md),
its `Reduction`, `Finalization`, Job version-two bridge and public Corpus
`finalize` routing, following the reviewed [prerequisite repair](shared-job-prerequisites.md)
and [controller/read review](shared-generation-controller-read-independent-review.md).
The [plan](../../plan.md) owns completion status. No implementation, gate, native
helper or production artifact changed during this review.

## Evidence identity

The finalization manifest digest
`5031bab3f8e92da7af655359a236d1d12c16868de752bbca86e5b6d630e475d3`
verified against all twelve frozen source files, six chronological logs, six
compiled cohorts containing 101 files, all 24 official public artifact files,
and the exact predecessor prerequisite manifest. The
[verifier](shared-finalization-review/review-manifest.exs) and
[result](shared-finalization-review/review-manifest.log) are retained. Generated
source/BEAM paths remain under `_build`; this is retained-evidence verification,
not a fresh-checkout build recipe.

The passing pure controls and official public build were inspected rather than
rerun. `46943` compares complete reduced root/directory values strictly with the
existing Directory version-one output. `46947` reconstructs durable jobs across
ten phases for 136 sources and 136 supplied facts: two manifest batches, five
entity pages, head and entity digests, then selection. Each phase also traverses
the real Collection client request/result validator to its first proposed effect.
The retained protocol counts peak at 86 reads before that effect; final pre-staged
selection uses 29 reads, checks seven immutable refs twice, inspects three sealed
stages and proposes one generation-500 three-stage CAS. Correct generation 501,
missing prerequisite, stale catalog, unknown stop, closed-gate diagnostic and
selected-job inspection controls are present. The separate `46948` official
`corpus/collection-documents` build completed without diagnostics. None of these
controls dispatched an effect to Core or a native helper.

## Reviewed integrity path

A manifest batch authenticates at most sixteen captured summaries against exact
catalog pages, source-head order, canonical group cardinality and common vector/
fact selectors. It derives the existing manifest schema and sorted entity
occurrences. Run directories bind their ordinal and exact immutable pages.
Merge consumes at most eight runs using durable per-run positions, returns an
exact missing reference instead of treating it as empty, and emits at most one
sixty-four-row entity page. Rows retain exact entity identities/labels and sorted
unique group membership. The complete entity digest phase checks global row
order and uniqueness across output page boundaries before selection; a local
merge page by itself is not the final proof.

Private Job version two is distinct from the unchanged selected Directory
version-one schema. Its shape binds complete group staging, batch counts,
manifest/run refs, merge positions, entity-page counts and phase-appropriate
hashes. Captured text/chunk/fact totals must match before leaving manifest
reduction. Run refs disappear only after entity merge completes; the head and
entity digests are separate durable phases. Earlier version-one jobs remain
inspectable and their append plan hashes retain their previous shape. Selection
constructs the canonical version-one root, rather than introducing a second
reader format. The ordinary Source/vector/fact and selected-reader contracts
remain separate and unchanged by these sources.

The controller authenticates every demanded reduction input's complete stored
hash/size at the same native generation as its coherent catalog/root/job startup.
It fixes the next job, immutable outputs and any root selection into one exact
plan. The existing edited-checkpoint repair still checks every required immutable
output before any metadata resume position and again after sealed metadata stage
inspection. Final selection adds all manifest/entity-page refs to that proof;
they are included in the plan digest. Caller-supplied unit/stage progress cannot
replace those existence/hash/size checks.

Earlier phases prepare job and captured catalog only. Final selection additionally
prepares the selected root with its captured physical revision. All sealed stages
are checked for exact slot/epoch, intended key, complete hash/size/offset and
expected revision at one native generation. The final proof uses that same
generation and `value_commit_at` sends it directly, with no fresh snapshot that
could hide an intervening change. Namespace generation and record CAS preserve
the old selection until the final atomic job/catalog/root switch. No conflict is
rebased. Unknown effects return no next request or continuation. A known
intermediate commit returns the next explicit `finalize` continuation; final
selection returns a completed command result.

No additional concrete defect was found in this scoped review. Source inspection
and the retained controls were sufficient; no speculative counterexample,
aggregate suite, native mutation, model request or previous passing cohort was
run for this review.

## Qualification limits

The counts above are a small pure/protocol fixture, not actual native phase
mutation, root selection, owner-loss/CAS race, unknown-after-commit, full-profile
capacity or installed Word acceptance. A successful artifact build is not a
public Session finalization journey. Existing native gates remain governed by
their own reviewed implementation and receipts; this component review opens none.
Model receipt provenance and later-use authority remain unqualified.

The complete invocation retains 512-read/sixteen-effect ceilings and individual
immutable values retain the existing 48 KiB format bound. Wide/heavily escaped
metadata may refuse at value or total-read bounds. Digest phases read directory
metadata, but still scan complete manifest/entity chains within one invocation;
full-profile metadata geometry and any needed versioned continuation/digest
representation remain open. This review does not lower accepted targets or
convert estimates into measured capacity.

A populated initial build and rebuild still need complete source/projection/
lexical/directory/native metadata/journal accounting, old-plus-staged overlap,
lifetime keys/operations, safe run/job reclamation, GC and migration. The prior
protected/publication, model, source-authority and representative Word limits
remain separate. The parent owns plan/index/handoff reconciliation, global
documentation checks and the coherent commit.
