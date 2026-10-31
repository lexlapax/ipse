# Shared job staging and public selected hydration — 2026-10-29

This historical component receipt follows the [directory](shared-generation-directory.md),
[cardinality repair](shared-directory-cardinality.md) and
[exact citation-origin repair](shared-citation-origin-canonical.md). Current scope
belongs to the [plan](../../plan.md) and [Corpus manual](../../operator/corpus.md).
It is the first job staging/read increment. Streamed generation finalization,
protected publication and populated capacity remain open.

## Intended mutation contracts and current gate

The extension-owned Job controller supports begin/inspect/abort and private
validated group append through existing Collection operations. A group is checked
against the captured raw catalog page, exact ordered source/head identities,
selectors and canonical full group hydration. Its immutable values and compact
capture summary precede job progress. A continuation consumes at most one such
immutable value; final group metadata prepares job and captured catalog together,
then consumes both in one CAS. The selected root stays unchanged.

Tokens bind job ID, physical job/root revisions, captured catalog, complete unit
plan digest, unit position and exact stage/write progress. Before metadata
consumption, owned sealed stages are re-inspected against their intended target,
full hash/size/offset and expected physical revision. Unknown effects stop without
a continuation, fallback or automatic replay. Inspector tokens come from the
actual retained job revision for an explicit recovery/abort operation. Job startup
reads require one coherent native generation; catalog or selected-root changes
make the job stale or refuse progress.

Every mutation uses `value_prepare` and `value_commit`, including short metadata.
There is no untimed inline fallback. The current strict stage/publication gate
refuses those writes as `document_store_deadline_unavailable`. Actual begin and
abort controls preserve the old records. These tests do not establish successful
job publication, successful group mutation, a working abort under this temporary
gate, or native unknown-after-commit behavior. The latter has only a pure protocol
stop control here. Existing finite host stages remain; job rows themselves require
explicit abort and their broader reclamation policy remains part of open GC work.

After complete group staging, the implemented state is `manifests`. The controller
does not claim it has built manifests/entity reductions or selected a generation.
Its coverage explicitly says `finalization_available: false`. Completing the
accepted build requires bounded manifest batches, entity-run merge/page phases,
complete head/entity digest phases, and a final atomic root/job/catalog three-ref
selection. A one-shot read of 125 full capture summaries plus 63 catalog pages
would exceed 512 reads, so that shortcut is not implemented.

## Real read-only public continuation

`collection-documents` adds `projection_selected` and `generation_job`; old preset
capabilities and Source 1/2/3, per-source vector/fact and lexical layouts remain.
The generic Collection grant, namespace, quotas and approval path are unchanged.
Projection/extraction and directory root validators are reused through small
validation bridges; there is no new dependency, framework, Core or native code.

Selected reads bind the actual current catalog, directory root digest,
generation/floor and exact selectors. They authenticate complete manifest chains,
only the selected headers, all pages of each selected group, and complete raw
source bundles. Canonical hydration checks every vector/input/fact/citation.
Requested sources must be eligible at the captured `as_of_ms`; the final native
generation and exact catalog are rechecked before returning any projection.
The private result is a coherent snapshot, with `later_use_authority: false` and
`model_receipt_provenance: false`, not a reusable authorization seal.

The public command returns bounded `top_k` supplied claims in stored order, exact
citations, complete partial-document warnings and explicit source/vector/fact
counts. Existing fact validity-window policy excludes expired/future facts and
reports `excluded_fact`. A partial document produces `status: partial` and
`coverage.complete: false`. All requested projection payloads still hydrate before
output; no silent truncation or lexical/model fallback occurs.

The read continuation enforces 512 read calls and zero effects. Current fixture
hydration needs 93 reads. Wider/multiple groups can hit that bound and refuse
without partial evidence; scalable selective paging/continuations remain required
before full-profile query acceptance. Nothing here reads a whole 20 MiB namespace
snapshot through a single SDK object or widens the 16 KiB protocol.

## Focused evidence

- `46926` actual official Corpus Session passed the first complete read plus
  expired source, corrupted vector page, changed model and stale floor refusals.
  The initial `46924` fixture omitted `bm25.version` and refused before hydration;
  that failure is retained.
- `46936` passed actual public job inspection/begin/abort controls in 10.9 s.
  Begin proposes one strict prepared mutation and refuses with the closed gate
  diagnostic. A separately seeded pending fixture job yields a fresh exact
  revision token; abort also refuses without changing it. No selected root changes.
  `46941` adds a fully seeded existing selected generation and verifies the same
  refusals preserve that exact root and its physical revision.
- `46934` passed pure append/changed-catalog/model/aborted-job admission,
  coherent-start refusal, exact read-envelope dispatch and unknown-stop controls
  in 2.6 s. These are protocol fixtures, not native mutation qualification.
- `46937` and `46938` cover the citation-origin repair described separately.
- `46939` passed the public fact-window exclusions with a single captured query
  time. `46940` passed the final partial-document behavior in 37.0 s. The official
  public command hydrated two requested sources, 34 supplied 32-dimensional
  vectors and four supplied literal quote facts; two eligible claims returned,
  two facts outside their validity interval were explicitly excluded, and one typed Word citation plus
  its warning remained. All runtime calls were reads; native status was unchanged.

Trusted initial fixture data was generated from seven ordinary sources and one
actual parsed synthetic partial DOCX, then seeded through ordinary untimed Core
fixture writes on `/tmp` tmpfs. That setup is not approved workspace acquisition,
protected ingestion, actual model inference or installed Word quality. The actual
Session worker reads the resulting source/group/directory values only through
documented SDK host calls; it does not read worker filesystem paths.

Intermediate passing runs and failed harness attempts are retained. `46931` passed
the job gate but its second setup collided with a shared evidence destination;
the harness now isolates retained official artifacts by test. Later public read
runs implement distinct canonical-origin, fact-window and partial-status changes;
no aggregate or retained capacity workload was rerun.

The [manifest](shared-generation-controller-read/manifest.json) pins exact source,
chronological logs, retained fixture/official artifacts, compiled feature hashes
and the isolated gated host/helper inventory. Generated artifacts stay under
`_build`; only source, logs and provenance are archived. No model, account or
external service calls occurred.

Still open: streamed finalization and atomic selection, model receipt provenance,
later-use authority, selective full-profile query bounds, safe GC/job reclamation,
migration/floors, and complete initial/staged-replacement/rebuild accounting for
raw sources, lexical values, directories, native metadata and journals. The
8,192-key/32,768-operation/192 MiB document and 256 MiB total ceilings remain.
Prior planned key/byte figures are not whole-profile peak measurements. The actual
populated/rebuild and representative ordinary Word qualifications remain required.
