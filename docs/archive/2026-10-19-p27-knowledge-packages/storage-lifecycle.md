# Post-prediction storage lifecycle, 2026-10-19

Historical implementation and verification record after `250080e`. The
containing commit owns the changes. Current contributor instructions are in the
[evaluation manual](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-evaluation.md#verify-retained-storage-without-querying-through-the-audit).
This increment does not expose held-out inputs, run model weights, select an
engine or complete P27.

## Reproduce missing measurement coverage

The resource summary required preparation and query snapshots but could report
complete storage coverage without post-forget or post-collection measurements.
The strengthened coverage test retained all original snapshots and removed each
new lifecycle phase in turn. The old implementation incorrectly accepted the
missing phase: four of five tests passed, seed 840609, in 0.1 seconds.

The declaration now requires the closed policy
`forget_all_then_collect_v1`. Retained-store strategies explicitly bind `collect`
alongside ingestion, inspection and forget. Research has no retained State store.
The runner writes every first prediction for a project/variant before invoking
this policy. It then inspects and suppresses each source copy, measures retained
storage, collects unreferenced pages, measures again and closes the same Session.
There is no additional quality query, model request or budget renewal.

Collection approval binds the verified private State file hash, selected project
namespace, page key and exact revision. Every selected-partition root must be
suppressed with no draft before a page can enter the allowance. Roots and foreign
pages cannot enter it. Collection retains the existing twelve-page command bound
and a finite twenty-two-batch ceiling for a 256-slot namespace. Final inventory
requires no orphan pages and unchanged namespace slots. Journal text and original
input data remain retained; collection does not recover capacity or erase history.

The runner also measures every index/extraction projection, retaining source,
generation and chunk identity. Storage completeness requires projection snapshot
counts to match public invocation timings, including failed operations. Required
forget/collection snapshots and query snapshots must each have complete coverage.

## Preserve integration evidence

The first integrated resource, declaration and public-Session run passed nineteen
of twenty tests in 175.6 seconds, seed 541124. The failing assertion expected
one inventory artifact for the seventeen-query cache control. The new lifecycle
correctly produced three distinct inventories. The revised control still requires
all seventeen unchanged query snapshots to reuse the preparation inventory; it
also checks the later suppression and collection inventories explicitly.

The expanded run passed twenty-one of twenty-two tests in 177.0 seconds,
seed 918543. Its new raw-State allowance fixture created a directory with default
permissions; State correctly refused it before the first write. The fixture now
sets owner-only permissions, preserving the production refusal.

The corrected resource, raw-State audit, declaration and public-Session suites
passed all 23 tests in 178.7 seconds, seed 506577. They include all seven variants,
current/suppressed/expired sources, exact projection counts, independent source
suppression, orphan collection, retained slots and tombstones, seventeen-query
cache reuse, budget exhaustion and an empty corpus with explicit absent storage.
The allowance controls reject active roots, retained drafts, changed/stale
snapshots and non-private State files, and exclude foreign pages and payloads.
All eight changed Elixir files matched both local Elixir 1.20.3 and Elixir 1.18.5
formatting; the latter ran on local OTP 29 and is not hosted runtime evidence.

The final full local suite passed 1152 tests with 17 Linux-only exclusions in
663.1 seconds, seed 566544. Strict stdio tracing and both actual macOS enforcement
tags were enabled, with source files fixed throughout the run. Build, formatting,
warnings-as-errors compilation, CI policy and the isolated credential-free demo
passed. The contributor chapter was reviewed as a complete manual. Documentation
checks covered 234 files and 2586 local links without errors.

No host SDK, domain algorithm, native helper, dependency or package implementation
changed. The existing independently built artifacts implement public collection.
OS/model process memory remains unmeasured under the original policy; harness
samples and regular file lengths do not establish whole-system peak resources.
