# Authenticate one stored document input batch

Scoped implementation, 2026-10-29, following the
[short source-admission direction](document-producer-source-egress-independent-review.md).
The [plan](../../plan.md) owns acceptance. The new host-private
`Collection.DocumentSourceUse` module is **not wired into dispatch**. Public page
production remains refused. This is one implementation prerequisite, not source
permission, a live invocation capability or producer acceptance.

`authenticate/4` receives the actual retained document read closure, a closed
claim reference, exact next input texts and the configured vector selection.
It uses `DocumentStage.read_value/2` to load the current v3 pending claim, matching
revision/logical hash/committing operation, catalog, selected root including absence,
Job and catalog page. It authenticates each selected source head and complete
ordered source-data blocks, original byte counts/bundle hashes, normalized legacy
or complete source identity, source-set hash, original observation/expiry/historical
fields and version/chunking hash. The claim must match the authenticated Job,
catalog and current selected root. No extension code executes under this callback.

Every input reference has the exact first-eight source/chunk position, bounded
nonoverlapping UTF-8 range, range-bound chunk identity and actual raw/canonical
text digests. The next batch is exactly its selected two positions, including the
short final batch. The Host does not re-split text or interpret a Word locator:
the authority being checked is an exact slice of authenticated current stored
text. Domain extraction receipts, locator fidelity and full domain Source validity
remain extension-owned. Stored bytes are not external truth or original Session
availability. `current?/2` separately checks every original source time against
host UTC, with exclusive expiry and historical/future refusal; the final caller
must sample it after all blocking checks.

The helper returns the actual claim operation ID, reference, batch position/count,
selection hash, original time fields and measured logical reads/bytes. It does not
bind that operation to a live Session. The future dispatch caller must authenticate
the selected operator/artifact/Registry/project binding, match the claim's original
successful current-invocation CAS, spend the next batch once, terminate on unknown
or mismatch, and use the existing one-use serialized-wire EgressGate callback.
Pending storage or a restored journal must not recreate that volatile authority.
Short Identity/Collection ownership is released before long IO; an already admitted
remote request retains its in-flight liability.

The bounds are 269 selected logical reads, 18 MiB cumulative logical body bytes,
one MiB assembled per source and eight MiB total source bundles. Per-block checks
precede bundle concatenation. Values retain the existing packed/native budgets.
These are explicit input/assembly bounds and counters, **not measured peak RSS**
or evidence of the maximum populated workload.

## Evidence and corrections

The [manifest](document-source-use/manifest.json), SHA-256
`77ec4fd5cfb91e1d7be513f3c2aea0eb2d2a5a5841312f189d153b17d2f0371b`,
pins production/test snapshots, nineteen launcher/log/intermediate-fixture/freezer
files, both parent/candidate runtime/private-asset inventories and three ancestor
manifests. The candidate forks the reviewed complete logical reader graph and adds
only the new module BEAM; its native helper stays
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
The inherited graph does not contain later notes/CLI overlays and is not a new
whole-worktree build. `47179` was an exploratory compile with deprecated launcher
option warnings; its pre-review source was not separately frozen. Final production
compilation in `47180` and documentation-only clarification in `47186` have empty
compile/runtime diagnostics.

A read-only worker comparison found two early incompatibilities before tests:
source heads retain insertion ordinals while catalog rows sort by source key;
Word chunks preserve document-segment boundaries. The implementation now checks
the authenticated head's catalog-page family and unique ordinal, with catalog/hash
source ordering, and validates stored ranges without a second chunk splitter.
It also checks common source/version/origin byte shapes and bounds each block
before assembling the complete bundle. These are recorded implementation fixes,
not new workload exclusions.

`47180` initially passed three of five tests. Two test assumptions were wrong:
the fixture contains one source block plus a separate lexical block, so the
authenticated read count is seven; and catalog revision alone is not a claim
precondition when the exact captured content is unchanged. A second test-only
correction removed the assertion that changing an unreferenced lexical record
must invalidate source bytes. `47181` passed the corrected four-batch positive;
`47182` passed only the repaired referenced-anchor case. The three earlier passing
negative/time/guard cases were not rerun. Exact initial/intermediate sources and
all failures are retained.

`47183` stopped before tests on a test-only JSON alias error. `47184` then passed
the two new compatibility cases using actual private Producer seeds: reverse
insertion yields head ordinals `[1, 0]`; extracted DOCX preserves three paragraph
ranges and gaps. The developer model's uppercase operation ID is explicitly
adapted to lowercase only for these synthetic read fixtures; no native operation
history is invented. The first native case failed on an assertion reading
`witness.generation` rather than `witness.root.generation`; the storage wrapper
correctly returned unknown for that callback exception. `47185` reran only that
case with the correct witness location and passed: actual document-profile storage,
a separate real claim commit, exact native claim operation/revision, retained
complete authentication, and refusal after the reader escapes. Test teardown
removes those temporary stores; raw native receipt files are not retained.

The eight cases therefore have scoped passing executions across their recorded
fixtures, not one final aggregate run. The final source differs only by the stated
test corrections/additions and production documentation clarification. No model
call, provider dispatch, approval race, maximum-workload peak, complete public
producer, package or full-suite qualification ran. Independent implementation
review is [accepted within this unwired scope](document-source-use-independent-review.md);
the actual transport/live-invocation integration remains open. That review
discloses the reviewer's authorship of worker fixtures separately from its
read-only review of this Host implementation.
