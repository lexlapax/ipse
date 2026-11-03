# Bounded paged recall and missing-original classification

2026-11-02. This is a scoped isolated-snapshot result, not P31E or milestone
acceptance. The [plan](../../plan.md) owns current status; the
[operator procedure](../../operator/knowledge-permissions.md#use-bounded-current-note-recall)
describes the intended behavior after integration.

Automatic recall now alternates existing root-bound index pages with protected
reads. It can continue beyond the first page when the notes read so far fit,
and attempts the earlier 32-candidate selection when they do not, subject to
host bounds. The
worker accounts for its own successful read and page dependencies and reserves
the worst-case proof and management-journal owners before continuing. The host
still checks the complete union, including inherited history; the worker's counts
do not guarantee later admission.

Only a narrow missing-original result allows recall to continue after an
unavailable read: a single literal, single-proof record with an inactive original
Session journal absent under the identity-checked Linux source lock. Under that
lock the host checks the original directory and lock, re-observes the exact root
and record, and authenticates signed metadata, the recipe and current source
policy. It checks the absence and identities again before release. Other failures,
including an unavailable lock or ambiguous source, withhold the pass. Unsupported
platforms refuse the missing-original classification. No source bytes or later-use
absence permission are produced by this result.

The skipped-source result does not carry an absence dependency to provider
admission. A missing journal can reappear after the locked observation, so the
result remains partial and a later pass is needed to see it. The actual host's
512-read and 128-dependency/owner limits can also stop a sparse scan before a
later eligible note. Full fitting-set coverage across arbitrary sparse collections,
and a host-bound final-use absence guard, remain open.

## Recall-only checkpoint

A fresh source snapshot at the same `a6ba4874e24734cddbab5ad8c41c16bee3527e2e`
base removed the earlier uncommitted P30 shadow branch and restored the committed
capture behavior. It retained only the nine recall/source/test overlays in the
separate [recall-only fingerprints](recall-paging-recall-only-20261102.sha256),
with no P30 collection-write guard. The nine files matched those fingerprints
again after testing. The snapshot used its own dependencies, build and home;
`docs/archive` was excluded because the per-user disk quota prevented extracting
another copy of historical evidence. The selected build and tests do not use it.

Formatting and the native/bundled build passed. The 27-case child worker suite
passed through its outer test, seed 792111. The missing-source and inode-swap
controls passed **2 tests**, 28 excluded, seed 792112; the signed-record and
root-change Session control passed **1 test**, 26 excluded, seed 792113. All
three native recall journeys passed, with 2 excluded, seed 792114, in 409.6
seconds. Those journeys again used a **15-second synthetic provider timeout**;
they do not establish behavior at the default five seconds. The snapshot and
logs were retained temporarily at `/tmp/ipse-recall-checkpoint-zZLls96R`.

The later [combined P30 and recall snapshot](decision-shadow-prior-session-20261102.md)
also passed the worker suite and all three native journeys with the same synthetic
timeout. Neither checkpoint tests an installed artifact or the final full suite.
The absence reappearance and sparse-discovery limits above still apply.

## Earlier combined-source snapshot

The isolated snapshot was based on commit
`a6ba4874e24734cddbab5ad8c41c16bee3527e2e` with the nine files in the
[overlay fingerprints](recall-paging-20261102.sha256). The snapshot used separate
dependencies, build and home directories. Its `knowledge.ex` contained an
earlier uncommitted P30 shadow path; the current combined Knowledge file has
since changed. The other eight fingerprints matched the worktree after testing.
The snapshot and its logs were retained under
`/tmp/ipse-recall-verify-lUtYwujI` during this work; that temporary location is
not a durable project artifact.

- The first build failed because the new `recall_next/1` clauses were separated
  by helper definitions, producing a compiler warning. After grouping the clauses,
  the isolated build and bundle build passed.
- The first recall suite found three selection/projection regressions from an
  early fit stop. After repairing selection, all 27 inner cases passed, but the
  outer harness still expected the old case count. Correcting that assertion
  yielded **1 outer test passed**, seed 792103; its child required all 27 cases.
  These include 33 fitting notes, 96 unavailable entries before an eligible note,
  systemic-refusal handling and work/proof bounds in the worker fixture.
- The source absence and swapped-inode controls passed **2 tests**, 28 excluded,
  seed 792104. The signed-record native Session control passed **1 test**, 26
  excluded, seed 792105; it checks the typed missing result and a root change.
- The native multi-page batch passed **3 tests**, 2 excluded, seed 792106,
  in 391.4 seconds. It exercised 33 short fitting notes, an eligible note after
  a missing original, and restoration of the omitted original before model
  preflight with explicitly partial coverage. The synthetic provider timeout was
  set to **15 seconds**; the default five-second path is not established here.
  These are fixture controls, not paid, live-account or independent human results.

The current combined source, complete suite, installed artifact, larger populated
stores and final adversarial audit still require their own verification. The
earlier 32-candidate fixture switch is historical and is no longer supported by
the current test runner.
