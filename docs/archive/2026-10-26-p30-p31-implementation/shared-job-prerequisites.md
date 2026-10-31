# Shared job prerequisite correction — 2026-10-29

This additive correction follows the [controller/read receipt](shared-generation-controller-read.md)
and its [independent counterexample](shared-controller-read-review/review-skipped-immutables.log). The original
frozen source/artifacts remain unchanged. Current scope belongs to the [plan](../../plan.md).

The reviewer demonstrated a private append checkpoint integrity defect. A caller
could recompute the plan digest and advance `unit` to the metadata portion while
all five immutable group/header/summary values were absent. The controller first
proposed job metadata with cursor eight and one summary. Tokens starting later in
metadata or at direct finish had the same omitted prerequisite check. This was a
private staging correctness issue under the closed write gate; it did not establish
an authority escalation, public append exploit or successful protected publication.

The controller now authenticates every required immutable key, complete document
hash and byte count before any metadata resume position, including direct finish.
The existing host `value.stat` verifies packed complete bytes before issuing its
descriptor. Missing or mismatched values refuse as `generation_prerequisite_missing`.
After exact owned metadata stage inspection, the controller verifies those values
again at one fixed native generation.

The extension-client `value_commit_at` helper sends the already-supported commit
request with that verified generation directly. It does not first adopt a newer
snapshot. An intervening namespace mutation therefore cannot be hidden between
verification and the atomic job/catalog CAS. The returned successful generation
must be exactly the verified generation plus one; unknown or inconsistent results
stop without a continuation. Legacy `value_commit` behavior and all host/Core/native
schemas, permissions, quotas and strict write gates remain unchanged.

Focused pure protocol control `46942` passed in 2.5 s and retained the exact newly
compiled feature BEAMs under `_build`. It covers all three edited metadata entry
positions, absent/mismatched prerequisite values, exact present values, both
pre-metadata and final passes (ten checks over five values), direct epoch-pinned
commit with no fresh snapshot, unknown stop, inconsistent success generation and
the exact successful next physical job revision. It performs zero native or model
operations. No aggregate or previous passing native suite was rerun.

The [manifest](shared-job-prerequisites/manifest.json) pins four source files, the
focused log, compiled feature hashes and original review counterexample. Generated
BEAMs remain under `_build`. This is a checkpoint/integrity repair. The controller
still ends group staging at `manifests`; streamed finalization, root/job/catalog
selection, protected write acceptance, GC, migration and full-profile qualification
remain open. Earlier write/gate evidence remains historical to its exact cohort;
this repair changes no gate or publication semantics.
