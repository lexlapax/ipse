# Managed v3 capacity controller follow-up

2026-10-27. This is a synthetic controller review, not native-capacity,
lifecycle, model or release qualification. The earlier
[static review](managed-v3-capacity-static-review/REVIEW.md) remains the source
for the broader workload gates. No storage workload or native helper was run
in this continuation, and no retained store or device was changed.

The uncommitted driver previously accepted supervisor process exit status 1
when a successful terminal frame had arrived. The native stdio runner normally
returns success after sending its terminal frame; an outer nonzero exit is not
confirmed clean completion. `collect_frames/4` now requires both the successful
terminal frame and supervisor exit status 0. The synthetic controller suite
passed 18 tests with seed 20270401, including a real `/bin/sh` port that emits a
success frame and exits 1. This validates controller handling, not native
helper cleanup or a production workload. The ordinary sandboxed Mix invocation
refused its TCP lock; the passing run used the approved local TCP permission.

A separate crash-recovery concern remains open. `save_new/2` syncs the new file,
but does not explicitly sync its parent directory. Controller attempt and child
start markers use that function before publication. An inferred risk is that a
crash or power loss can leave an effect without the directory entry needed to
prove the attempted segment, depending on filesystem guarantees. File sync alone
is not evidence that the directory entry is durable. Do not run or resume a
capacity workload until a pinned-helper, owner-only directory-sync design is
implemented and reviewed for the controller and child, including failure, crash,
existing marker and unknown-outcome paths. The existing protected directory-sync
API selects its helper independently, so calling it before proving exact helper
identity would not resolve the review's helper-pinning requirement by itself.

Source SHA-256 for this local observation:

- `dev/knowledge/managed_v3_capacity.exs`:
  `032c627c53d4c9856e1119ee5d70ef595b9d2ff61a201603170516f6db7a48e2`
- `test/dev/knowledge/managed_v3_capacity_test.exs`:
  `07c3a86deaa8f3e98081b69a9d473c4b2e3c2f2d054f19a9f1ace4da2392328f`

Both files were already untracked experiments and remain uncommitted. The
7.2.11 native profile remains unqualified, typed turnover is not implemented,
and the 2,000/4,000 and 30/90/365-day gates remain open.

## Subsequent source change: directory-sync ordering

The uncommitted controller now writes and syncs each attempt, child-start and
clean marker, then requires an explicit parent-directory sync before it can
proceed. The production callback checks the selected protected helper path
against the runtime binding and its bytes against the fixed reviewed hash before
calling the protected directory-sync API. A sync refusal leaves the exclusive
marker in place and stops that invocation; it is not retried automatically.
The test-only callback exercises ordering and failure without a native helper.

The first focused run after the change failed one old synthetic claim test
because that test had no protected helper. It was adapted to exercise the same
claim and exclusive-marker logic using an explicit test callback; the production
entry point still supplies the protected sync callback. The next run passed
19 tests, seed 20270404. This establishes only in-process ordering and refusal;
it does not prove persistence across crash, directory-sync behavior on the
selected filesystem, helper-path stability under hostile replacement, or a
native protected transaction. The workload remains blocked pending those checks
and the other review gates above. No helper, storage workload or device was run.

New source SHA-256 values are `cde235183a90fe55520b42f8b1451228ee5118062fe8db685341b6b792601711`
for the driver and `e9139017e56cfa7916936d46dd66a5013f5ebfd4e7547ae10395c9f13edd7115`
for the test. The hashes earlier in this record identify the prior revision.

A subsequent negative control called the production claim entry with an unbound
helper path. It refused before launching the helper, retained the exclusive
child-start marker, and refused a second claim. The 20-test synthetic controller
suite passed with seed 20270405; the test source SHA-256 is now
`6279aab676d79ba2e32495ff00c54a667573e836f8d2a011d91c6f918c858be8`.
This does not prove the positive native sync path or crash durability.

## Skewed page geometry control

A pure working-tree test constructs 4,000 anchor identities and 4,000 live
identities sharing the same leading hexadecimal prefix. It packs them into 80
anchor and 200 live pages, checks each page's minimum weight and round-trip
decoding, and asks the actual directory selector to locate every identity in
its corresponding page. This specifically checks that the page syntax and
ordered directory can represent a clustered population beyond the former
fixed-shard limit. It does not execute the repair planner, authenticate pages,
publish records, measure allocated storage, run the capacity controller, or
prove lifecycle/turnover capacity.

The focused page, directory, encoding and synthetic controller selection
passed 41 tests with 5 native-page cases excluded (seed 46352). A supported
native host and the remaining workload and crash-durability gates are still
required; no retained store or pending marker was changed.

## Planner control at clustered scale

The working-tree native-pages fixture now signs 80 synthetic anchor pages in
batches under separate identity operations, representing 4,000 clustered
identities. The actual planner inserts identity 4,001, seals the planned change,
and reopens the selected page. The test checks its expected revision, every
pre-existing entry on the changed page, and byte-for-byte preservation of all
other page records. Its first setup attempted to sign all 80 pages in one
operation and was refused by the existing 16-seal capability limit; the fixture
was corrected by batching, without changing the production limit.

The corrected isolated selection passed 23 page and directory tests (seed
46469). It used the existing private diagnostic graph and test-only 7.2.11
helper override described in [available-host diagnostic](available-host-diagnostic.md).
The current planner, page implementation and directory source hashes matched
that graph. An initial combined command accidentally loaded two copies of the
same fixture modules and failed compilation; the passing command loaded only
the updated copy. No actual Collection publication, crash or capacity workload
was performed. In particular, this is one unsplit anchor insertion with synthetic
observations, not a split/merge stress test, sustained 4,000-publication run,
turnover proof, protected filesystem qualification or evidence of current
authority.

The fixture was then strengthened to use 79 pages, with a 96-entry final page
and a maximum-size new anchor row. It requires the planner to split that page,
checks the old and new expected revisions, reopens both resulting pages and
compares their union to the original rows plus the new row, and checks all
unaffected page records for equality. The revised page and directory selection
passed 23 tests (seed 46471) in the same diagnostic graph. It replaces the
unsplit control described above. It still uses synthetic directory observations
and does not demonstrate merges, real Collection writes or workload capacity.
