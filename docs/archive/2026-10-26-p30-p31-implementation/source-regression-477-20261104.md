# Frozen 477-file source regression — 2026-11-04

Historical execution evidence. The [plan](../../plan.md) owns current acceptance;
[testing](../../developer/testing.md) owns verification procedures. This run is
separate from the [earlier 473-file result](source-regression-groups-20261104.md).
Both failed aggregates retain their original outcomes.

The exact tracked source was `9b1a4e5edd0879804524eab0f71f28bcfc414e33`.
Its product source was unchanged from
`09f9beb4393fdbf45e5a79d8753a91c22571e248`. The copied development runtime's
embedded build commit was null; source and complete runtime bytes were pinned
independently rather than relabeled as a release build. Each group had its own
complete source/Git/index, App/Bootstrap/dependencies, normal four-bundle private
assets, Hex/Mix metadata, HOME and temporary state. Verified CoW copies used no
hardlinks. Explicit disjoint file lists selected all 477 files without a second
partition filter or optional feature flags. Only the serial group owned native
operator input. All launchers used the installed `C.utf8` locale.

## Terminal results

| Group | Files | Passed / executed | Invalid | Skipped | Excluded |
| --- | --- | --- | --- | --- | --- |
| Serial | 249 | 2,183 / 2,184 | 0 | 123 | 122 |
| Parallel 1 | 77 | 609 / 609 | 0 | 2 | 0 |
| Parallel 2 | 76 | 648 / 648 | 0 | 4 | 0 |
| Parallel 3 | 75 | 588 / 588 | 0 | 1 | 1 |
| **Outer aggregate** | **477** | **4,028 / 4,029** | **0** | **130** | **123** |

The aggregate is **failed**, with one outer failure. Serial finished in
5,621.8 seconds and returned test exit 2. Nested subprocess summaries are not
added to the outer counts. Skipped, invalid and excluded cases are separate from
the executed pass/fail denominator; the installed ExUnit counter and formatter
semantics were checked before deriving these totals.

Every group's eleven integrity postchecks passed: source, runtime and dependency
bytes; runtime/source pathsets and links; Git identity; the exact mutable Mix
failure metadata's allowed type; private Hex; and unchanged original top-level
entries with bounded new outputs. This is 44 passing checks across four groups,
not a successful test aggregate. All exact group/fixture process checks were
empty, with no unreadable same-user process records. After serial termination,
the shared native input lock had no holder. No suite or failed effect was replayed
to improve this result.

## Preserved Graph catalog failure

`IpseKnowledge.PackagesIsolationTest` failed at
`test/extensions/knowledge/packages_test.exs:1039` / assertion line 1057. Its
child `DomainPackagesSuite` test, “three independent descriptors have closed
command catalogs”, still required one tool for every package. The selected
Graph package intentionally exported both `query` and `capture`; the fixture
expectation was stale. This was the only observed outer failure.

A [later focused loader/Graph check](research-fetched-state-20261104.md)
uses exact package-specific tool IDs and passes 54 outer tests in 253.0 seconds,
including the affected package controls. Its nested totals are not added again.
That later source/test freeze does not retroactively pass this run.

## Provenance and scope

The [aggregate](source-regression-477-20261104/aggregate.json), four per-group safe
results, exact status files and empty-process receipts are retained in the
[evidence manifest](source-regression-477-20261104/evidence.sha256). The export
contains thirteen receipt files plus that manifest. It includes no raw test logs,
private transcripts, original protected-state inventories or duplicate full
source/runtime manifests.

| Pin | SHA-256 |
| --- | --- |
| Exact source manifest | `e414a352ed6dba44915c3d9036a6101b4d15fc37c7a787ebfd38a92d4e4e758c` |
| Immutable group runtime manifest | `d6aa925214d4924c10d65be4cc3b477ce2545a683eabcbb7e8f9fcca20190a8e` |
| Safe aggregate | `1abb55e89a0bbd701623724c5d0d43145ed93a8aa5d76161babccc00b43b0eb7` |
| Safe evidence manifest | `5d93861b738f327cc60373f887869e3ed7eb4088ce3cc73e34b5c5c3e5a9460f` |

Later [share-timer isolation](share-stale-timeout-20261104.md),
[fetched Research](research-fetched-state-20261104.md) and
[coalesced Worker-input reads](coalesced-worker-readview-20261104.md) have separate
focused evidence and are outside this frozen aggregate. Optional native feature
cohorts, installed behavior, retained-cohort recall, complete-day and annual
workload, and consumer quality retain their own acceptance gates. This record
does not declare P30 or P31 complete.
