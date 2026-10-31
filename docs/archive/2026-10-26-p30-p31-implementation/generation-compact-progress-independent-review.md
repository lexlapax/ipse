# Independent review of explicit compact generation progress

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[compact progress](generation-compact-progress.md), manifest SHA-256
`61b4c7492d54d100bb762664064dec2e80f63bd5eaf63f8e94708dec3352811e`,
and the separate [compact finalization ledger](document-compact-finalization-ledger.md).
No runtime edits, native effects, controller/test reruns or model/network calls
were made by this review. A later fresh-Session test is outside this freeze and
is not credited here.

## Disposition and evidence

Accepted as explicit presentation of bounded generation progress. No concrete
blocker was found. Default/full behavior and controller authority remain
unchanged. Compact output reduces repeated Job-result transport; it does not
provide a full Job, stage adoption, inference provenance or capacity acceptance.

The [verification script](generation-compact-progress-review/review-manifest.exs)
and [result](generation-compact-progress-review/review-manifest.log) verify all
16 top-level entries, 28 frozen source/license/test inputs, 716 inventoried graph
paths, 25 built-artifact files and 165 retained Session fixture/artifact paths.
All 705 ancestor Host paths match the packed-layout cohort; the broader graph
inventory also includes inherited diagnostic material. There are no Host
overlays and the pinned 7e helper is unchanged. The package manifest hash is
`004654fe41ab870398d806d51ad72fa5ef6d0e5b1396133deac8a43a933e72b0`;
all 24 declared files verify. Executable BEAM code digests against the frozen
Root2 public artifact differ only in Corpus and Job. Other binary build-metadata
differences do not imply controller changes.

The same verification checks all 51 rows of the separate ledger manifest
`31bc1edfc68842076f7115e27abf2348304be27fd79120ea6fef4a652b229ee2`,
including retained traces/models, reports, artifact and immutable ancestor. All
655 retained public objects use compact representation and retain the response
mode in their continuations. This is read-only evidence verification, not a
repeat of the modeled controller or native controls.

## Presentation and continuation boundary

Corpus accepts only omitted/default `full`, explicit `full` or `compact_v1` in
the added optional schema field. Its exact request check removes only that
field, then passes the same original controller arguments with presentation
fields stripped. Invalid modes refuse before Collection admission. Both draft
continuation paths copy the original public arguments and replace only the
controller continuation, preserving response mode, selections and checkpoint.
Legacy full output uses the previous value directly, including its original
continuation behavior.

Job adds one pure projector; its planner, validator, storage requests, stage
state, operation IDs, CAS and unknown-write behavior are untouched. Projection
validates the complete Job, hashes and counts its complete encoded logical
value, then exposes fixed identity/status/root/catalog bindings, selection
digests, source/cursor/fact/summary counts and bounded reduction scalars/reference
counts. Original status, continuation, stale and coverage fields remain exact.
Absent or paused results without a Job report nil progress and preserve their
stage continuation. Unexpected invalid internal Job data raises; it does not
manufacture a new known refusal after an effect or retry an unknown write.

The digest includes omitted summaries and reduction arrays; changing an omitted
last summary changes it. It is not the packed physical Collection-object hash,
a read capability, current-source attestation or resumable Job replacement.
Full inspection remains available. In particular, a compact result does not
remove active-stage owner restrictions or authorize cross-Session adoption.

## Controls and ledger limits

I inspected the clean package build, three maximum/pure controls, retained
legacy full-output native compatibility and two corrected compact native
Session cases. The latter cover begin/inspect/abort, matching durable logical
hashes, exact full-mode continuation, unchanged storage/approval count for
reads, invalid-mode refusal, actual paged Root2 finalization, inline result and
Saved reconstruction. Their seeds and approvals are explicitly synthetic and
trusted. Initial tests reached storage but failed fixture assertions through
the wrong JSON alias; corrected fixture calls and both chronological logs are
retained. Complete Session journals were not retained after teardown. The
initial formatting failure exists only in tool history and is not a frozen raw
source/log claim.

The maximum encoder control reduces a 38,010-byte full public envelope to
4,211 bytes with escaped selections; it is not a full actual Session at that
scale. The separate closed-model run retains all 655 public objects, including
one inspection, and reports all 654 finalization replies inline, zero paged
result-source slots and a maximum 1,839-byte complete reply frame. The retained
comparison source checks identical selected descriptors, model generation,
totals and request geometry/payload hashes/counts/parts/sizes against legacy
finalization. Fresh IDs/epochs legitimately change request digests; the initial
overstrict digest comparison and corrected reducer are both retained.

That model uses a known synthetic appended checkpoint and fresh action IDs,
with no native replay or acquisition/rebuild rerun. Its exact 5,277-descriptor
selection and generation 19,640 are model results. Finalization still requires
104,036 modeled action events and at least 161,950,045 action-pair bytes before
other Session records, exceeding one existing Session. Compact output removes
the modeled paged-result bottleneck, not the need for durable boundaries or
full native allocation/history accounting. Public production, safe handoff,
GC/export/import, representative Word quality and installed-host/full-profile
capacity remain open.

## Additive actual stage-free handoff

The separate `generation-compact-handoff` manifest SHA-256
`c20a02ad8bc4c314eff4e90ca9f9b38848fc765fa16003780b8871b4b94f8ca8`
is accepted for its narrow actual handoff. Its
[verification](generation-compact-handoff-review/review-manifest.exs) and
[result](generation-compact-handoff-review/review-manifest.log) check seven
manifest entries, the single frozen test source, 716 unchanged parent runtime
paths and 45 retained artifact paths. The delta is a test plus its phase-stop
helper condition; no worker, Host, controller or helper implementation changes.

The retained 47128 control passes one native case in 34.2 seconds, 43 excluded.
It pauses at a known committed `entity_digest` phase and explicitly checks
`unit == 0`, `write == nil`, `stages == []`, unchanged old selection and durable
Job bytes. The old Session closes confirmed before a new Session with a distinct
ID starts. Fresh explicit inspection supplies a current revision-bound token;
it matches the durable Job digest without rewriting it. Continuation reaches
the exact expected selected Root2, both Saved reconstructions validate, and the
old journal bytes remain unchanged. This is a small trusted synthetic native
journey, not active-stage adoption, unknown-write replay, imported checkpoint
acceptance or a complete maximum-profile recipe. No passing control was rerun
for this review.
