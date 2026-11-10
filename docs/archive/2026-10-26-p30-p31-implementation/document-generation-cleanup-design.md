# Explicit generation cleanup after selection — 2026-11-09

Status: design stopped before implementation. It supplies no deletion API,
authority or acceptance. Branch `p31-root2-lifecycle` from `52d8acfd`.
Current scope remains in the [plan](../../plan.md); the operator procedure for
the supported one-rebuild limit is in the
[corpus manual](../../operator/corpus.md#rebuild-a-document-collection-near-its-limits).
This refines, and does not replace, the
[maintenance v2 proposal](document-collection-maintenance-v2-design.md).

## Operator decisions applied

Keep Root2 at full size; retain exactly one previous generation; delete only
after a new root is selected, explicitly, behind the document maintenance
barrier; at most 32 changes per commit; intent before effect; refuse any
descriptor mismatch; never replay an unknown outcome. Limits stay at 8,192 live
records, 32,768 operations, 64 KiB values and 32 changes per commit.

## What exists at `52d8acfd`

- **Retirement** is draft retirement only. `progress.retire` and `value.abort`
  with a `retire` progress tag (`DocumentDraft.retire/6`,
  `DocumentStage` abort dispatch) delete one stage's `host.stage.N.*` header,
  ready and part records and release the head's slots. A Job `abort` and a
  lexical abort retire job metadata. None deletes a published source, a selected
  root or an immutable generation value. Corpus refuses `forget` and `collect`
  on Collection stores with `collection_lifecycle_unavailable`.
- **Barrier.** `DocumentMaintenance` admits only purposes
  `checkpoint_inspection` (version 1) and `document_import` (version 2, owned by
  `DocumentMigration`). While active, every ordinary document mutation returns
  `collection_writer_fenced`; only the owner's close passes. The only callers of
  `Collection.document_maintenance/5` are tests. No operator or SDK path opens it.
- **Deletion.** The native commit accepts a change with `"value" => nil` and an
  exact `expected_revision`. Each commit spends one permanent operation receipt.
- **Root layout.** The selected root is the single key `generation.PARTITION`,
  replaced in place. It references manifest (`genman`) and entity (`genent`)
  pages; manifests reach group headers (`gengrp`) and `gensrc`/`genvec`/`genfact`
  pages. Reduction run pages (`genrun`), run directories (`genruns`) and
  summaries are reachable only from the Job record `genjob.PARTITION`, which the
  next `begin` replaces. The Job keeps the replaced root's `root_sha256` and
  revision, not its body. Values are content-addressed, so generations share
  unchanged pages.

## Arithmetic

Ledger: 5,277 live records initially and 6,910 after one rebuild; 28,258 of
32,768 operations used. A second rebuild adds about 1,633 records (8,543 >
8,192) and 9,618 operations (37,876 > 32,768).

Under the operator's one-initial-plus-one-rebuild limit, at most two generations
exist, so **no value is unique to a generation older than the retained previous
one**. The only removable families are reduction intermediates no longer
reachable from the current Job: about 157 run pages, 8 run directories and 125
summaries per completed reduction, 290 records each, 580 for both. Deleting 580
records needs `ceil(580 / 32) = 19` commits, leaving 4,510 − 19 = 4,491
operations. It frees live records but cannot make a second rebuild fit, because
the operation shortfall (37,876 − 32,768 = 5,108) is permanent.

## Why implementation stopped

1. **New authority model.** Cleanup needs a third barrier purpose whose owner
   may commit deletion-only changes while every other writer is fenced. Today no
   production code opens the barrier, and the v2 proposal forbids treating a
   worker's mark set as host-enforced reachability. Choose who opens it: a
   host-owned CLI command with its own management journal, like
   `knowledge forget`, or an extension action with a new reviewed trust selector.
2. **Retaining one previous generation needs a format change.** To delete
   values unique to older generations, the final selection must keep the
   replaced root, for example as `generation.prev.PARTITION`. That makes the
   three-stage final switch a four-stage switch and changes the measured
   9-effect selection budget.
3. **Complete traversal.** Marking must cover sources, catalog pages, lexical
   index (`lexical`, `lexp`, `lexjob`), both roots, the current Job and producer
   (`genproducer`), per-source projections and every draft head. It reuses
   `Directory`, `Generation`, `Reduction`, `Finalization` and `Paged` validators
   and must refuse an unknown edge. That alone exceeds the 800-line bound.

## Smallest correct design, if authorized

- **Host.** Add `DocumentMaintenance` purpose `generation_cleanup`. At open,
  bind the owner, the exact selected-root record (revision, physical hash and
  size) and an operation reservation of `ceil(n / 32) + 1` for close.
  Admit only the owner's `commit` requests that carry 1..32 changes, all
  deletions, no `host.*` key and exact current revisions. Recheck the bound
  selected-root descriptor in the same native CAS. Close restores idle and
  advances the epoch so stale tokens refuse.
- **Knowledge.** A `generation_cleanup` action with phases `plan`, `delete` and
  `close`. `plan` reads the bound root, the current Job, the producer, lexical
  metadata and the catalog, and computes the sweep set: content-addressed
  `gen*` keys not reachable from the current or previous root, the current Job,
  the producer or a draft head. Refuse if the Job is not `selected` or any
  descriptor fails validation. The continuation carries the sorted sweep
  digest and a cursor; each `delete` step rereads its ≤32 descriptors and sends
  one commit.
- **Journaling and recovery.** Each step is an ordinary journaled action:
  intent first, then the native commit. An unknown outcome returns no
  continuation. Inspection rereads the descriptors; a missing key is not proof
  that this step deleted it. A fresh `plan` recomputes the sweep and refuses on
  any change.
- **Tests.** Planner unit tests with seeded Root2 maps; native tests (Linux) for
  owner-only admission, foreign-writer fencing, descriptor mismatch, partial
  progress with an unknown last step, and close.
