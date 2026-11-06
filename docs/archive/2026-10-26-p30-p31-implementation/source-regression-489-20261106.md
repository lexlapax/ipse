# Interrupted 489-file source regression

Dated **2026-11-06 UTC**; execution began on **2026-11-05 Pacific time**.
Historical verification record only. The [plan](../../plan.md) owns remaining
acceptance, and [Testing](../../developer/testing.md) owns current procedures.
This attempt does not replace the earlier
[failed 478-file regression](source-regression-478-20261104.md) with a passing
baseline.

## Frozen scope and observed outcome

One independent, clean source copy at
`debcb16a779da7c5d26740e4049b311ef6a95bdc` contained **489 tracked test files**.
It used the normal application startup and the complete default test command:

```sh
mix test --no-compile --no-deps-check --max-cases 2
```

There were no test filters, partitions, expectation changes or automatic retries.
The source copy had its own Git metadata, dependency/runtime files and isolated
credential-free home and temporary directories. Existing product and test
deadlines remained unchanged. The outer coordination bound was 10,800 seconds
with a 30-second kill grace.

The run began at **17:09:48 PST**. Its retained log ends with `SIGTERM` notices at
**19:38:41 PST**, before the **20:09:48 PST** coordination deadline. The tool
handle and observed process group were subsequently absent. The interruption
cause and original test exit status are **unknown**. The automatic postphase
created an empty log but did not produce its status or final summary.

The attempt recorded **13 outer failure headers** and **two nested package
failure headers**. Nested failures are not added to the outer count. There is
no final outer ExUnit report: final passed, failed, excluded and completed-test
totals are **unknown**, rather than inferred from the 489-file census or nested
reports. The full baseline remains **unqualified**.

The observed failures concerned an OFF-preflight assertion running inside a
normally started application; a stale Word extraction-version fixture; nine
evaluation cases refusing host-loaded domain modules; a package isolation case
with two nested fixture failures; and a build-spec assertion affected by the
same host module loading. Separate focused repairs do not change this frozen
attempt or supply its missing final result.

## Later read-only closure

After confirming that the original owner was absent, one bounded invocation of
the existing pinned copy guard completed the missing immutable-copy check.
It passed for source, runtime, dependencies, Hex archive, Git metadata, pathsets
and links. The only permitted mutable runtime file was Mix's test-failure cache;
its actual bytes were separately hashed. Main was neither frozen nor audited by
this independent copy after preparation.

Launch-input hashes also passed. Current Input, listener and owned-process
checks returned the expected no-holder status with empty output and error files;
the observed process group was empty. A separate actual-host neutral check
confirmed those observations after the guard exited. These later checks establish
current integrity and cleanup, **not** the original test exit or completion of
the interrupted suite. No test, inference, native approval or retained-notebook
operation was replayed.

## Provenance and limits

The private execution directory is
`current-full-regression-debcb-20261106-01`; its safe receipt and manual closure
are retained separately from the raw log. SHA-256 identities are:

| Evidence | SHA-256 |
| --- | --- |
| Sanitized `run-01/safe-result.json` | `11056b15fb491a52e0fb6c6807ed7b75bcf5bd2b410d87f4cdc1a3fd7c504ca1` |
| Later immutable-copy result | `84bc81788523a043140774c5cadfc44404c5b429dc9cefb095c0dc2006cdf5b0` |
| Independent neutral status | `3f46889d3da05937469df21a7f6a8dbb845c6952d1e0179635538a977d244e03` |
| Activated launcher manifest | `e1cd9fa0e0e2be064ceaac1f6bfd24f8496c580cdcb7a8a888f038f70b254993` |
| Private raw log, hash only | `fa2f268a5cb86d33f4de513cd858bdb3bf6a2fcfb2c2c6357986f523cafccc51` |

The raw log, native review output and private fixture journals are not exported.
Available-space checks and a finite allocation probe were preparation controls;
effective quota/cgroup limits and whole-process peaks were not established.
The elapsed interval is not a complete-suite performance qualification.
The original retained notebook was not accessed; its denied recall and the
dependent day/year evidence remain separate open gates.
