# Explicit compact public generation progress

Scoped implementation record, 2026-10-29. The [plan](../../plan.md) owns
acceptance. The [whole-recipe ledger](document-whole-recipe-ledger.md) identifies
large repeated public Job results as a separate journal/ResultSource cost.
This changes presentation only; it supplies no public inference producer,
Session adoption, migration, new grant or native mutation primitive.
The [independent review](generation-compact-progress-independent-review.md)
accepts the frozen presentation slice and separate modeled ledger. A later
[actual stage-free Session handoff](generation-compact-handoff.md) has its own
source/artifact freeze and scope.

The public `generation_job` command accepts an optional `response` field:
`full` preserves the original output and remains the default;
`compact_v1` replaces the complete repeated `job` with `job_progress` and the
explicit representation marker. The worker strips this presentation field
before calling the unchanged Job controller. Every returned continuation keeps
the selected response mode and all original selection/checkpoint arguments.
Bad modes refuse before storage admission. Ordinary approval and source/CAS
rules are unchanged.

`Job.compact_result/1` retains exact outcome, continuation, stale and coverage
fields. Its progress object contains the complete logical Job value's digest
and byte count, schema version, ID/partition/status, catalog/root bindings,
selection digests, source/cursor/fact/summary counts, and bounded reduction
scalars plus reference-array counts. It does not return page arrays or source
content. The hash is of the complete encoded logical Job, **not** its packed
physical Collection object. Neither that hash nor the progress object grants
read/replay/current-source authority or serves as a complete Job value.
Paused steps without a returned Job retain their exact stage continuation and
report nil progress. Active stages retain their existing owner restrictions.

The projector checks the existing complete Job validator. Unexpected invalid
internal Job data raises rather than introducing a new known post-effect
refusal. It does not change any Job planner, publication, stage or operation-ID
behavior. Full output remains available explicitly for complete inspection.

## Exact artifact and controls

The [manifest](generation-compact-progress/manifest.sha256), SHA-256
`61b4c7492d54d100bb762664064dec2e80f63bd5eaf63f8e94708dec3352811e`,
pins28source/license/test inputs, scripts/logs,716host runtime paths,
25built-artifact files and165retained Session fixture/artifact files. The host
graph copies the frozen packed-layout cohort and has no runtime overlays.
Its helper remains7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067.
Worker Corpus/Job changes are separately built into the package, whose manifest
SHA is004654fe41ab870398d806d51ad72fa5ef6d0e5b1396133deac8a43a933e72b0.
The artifact and both initial/final Session test artifacts remain under `_build`;
no BEAM or native binary is copied into this documentation archive.

-47123 built `corpus/collection-documents` through the production builder with
  zero compile/runtime warning diagnostics.
-47124 passed three pure/protocol controls: absent/paused results retain exact
  continuations; the maximum1000-source/125-summary Job binds every omitted
  byte, including a changed last summary; maximum paged reduction reports
 157entity references as counts while retaining exact scalar progress. A complete
  public maximum-width/escaped-selection envelope falls from38,010to4,211bytes
  and changes from an actual ResultPublication output producer to inline result.
  This is an encoder control, not a full actual Session at that maximum scale.
-47125 passed the existing full-output native Session compatibility case.
  Both new compact tests reached native storage but failed at assertions that
  accidentally resolved `JSON.encode!` through the `Ipse.JSON` alias. The initial
  test source, warnings and complete failed output remain pinned.
-47126 corrected only those fixture calls to `Elixir.JSON.encode!` and passed
  both affected actual Session cases in47.3s,41excluded, with no warnings.
  Compact begin/inspect/abort matches the actual durable Job digest and exact
  full-mode continuation; reads add no mutation approvals and invalid modes
  leave storage unchanged. Paged finalization carries compact mode through its
  real draft continuations, selects the exact expected Root2 and returns an
  inline result matching the actual selected Job. Both cases validate Saved
  reconstruction. Seeds and approvals are synthetic/trusted, not model capture.

An initial leading-comma formatting error was corrected before47123; its
diagnostic remains in the tool history, not a separately retained raw source.
Test teardown did not preserve complete Session journals; passing assertions
and retained artifacts/source/logs support only the listed scope.

No native helper, Core host source, quota, provider or billing route changed.
No model/network request or aggregate suite ran. A new compact-only finalization
model is separately authorized from the retained known appended checkpoint;
the legacy ledger is immutable and did not retain all complete public outputs.
Independent scoped review, whole-manual integration and final coherent
source/package verification remain required.
