# Small worker handoff diagnostic, 2026-11-03

Historical synthetic diagnostic; this is not acceptance of the annual workload or an explanation of the retained full-day failure. See [the full-day failure record](integrated-full-day-failure-20261103.md) and [separate retained probe](retained-probe-20261103.md). The failed cohort was not touched by this experiment.

An isolated snapshot of commit `b10df4a556c097b686eecba1267e3d6425f0f8bc` excluded duplicate archive files and overlaid the three diagnostic files below. The native build passed. A focused redaction and timing unit test passed with ExUnit seed `791961`. A fresh synthetic fixture created eight notes across two original source journals; the existing actual-Session current-source test then passed (one executed, 197 excluded, seed `791960`, 17.5 seconds). It did not use a paid provider or change production deadlines or source checks.

Exact copies of the tested [tracer](worker-handoff-small-20261103/tested-worker-handoff-trace.exs), [unit test](worker-handoff-small-20261103/tested-worker-handoff-trace-test.exs), [original wrapper](worker-handoff-small-20261103/tested-worker-handoff-wrapper.exs), and [unit test log](worker-handoff-small-20261103/unit-test.log) are retained alongside the report. These are historical evidence; the corrected working-tree wrapper remains unverified.

The wrapper itself exited **1**, despite the underlying test passing. Its original success guard incorrectly required `result.total == 1`; ExUnit reported 198 total, including 197 excluded. A [corrected draft wrapper](worker-handoff-small-20261103/corrected-worker-handoff-wrapper-unverified.exs) subtracts excluded and skipped tests. That one-line correction has not been rerun or independently verified; do not describe the wrapper as passing. The source-loss control was not run.

The retained redacted [report](worker-handoff-small-20261103/report.json) has 80 finished spans, no dropped trace events and no unmatched calls. All 11 journaled worker inputs were delivered and their dependency digests matched, with observed counts increasing from one to ten. The following elapsed ranges are instrumented measurements, not an uncontended benchmark:

| Phase | Calls | Minimum–maximum |
| --- | ---: | ---: |
| `WorkerInput.call` | 15 | 0.515–744.728 ms |
| `ManagedUse.with_worker_dependencies` | 11 | 89.897–706.186 ms |
| `StoredSources.with_shareable_union` | 10 | 139.839–557.652 ms |
| `SessionSource.with_worker_input` | 11 | 19.221–70.755 ms |
| `Worker.bind_stdin` | 11 | 0.040–0.236 ms |
| `Worker.export_stdin` | 11 | 0.081–5.315 ms |
| `Worker.settle_stdin` | 11 | 0.049–0.261 ms |

The timing spans are aggregate observations, not uniquely paired with each journal record. The fixture used two source journals and reached ten observed dependencies; the prior 2,000-note probe had a different workload and failed with an unknown worker-input outcome. These results establish neither a five-second timeout nor another cause for that failure.

The report includes only synthetic identifiers, journal hashes, bounded function names, timestamps, durations, outcomes and input metadata; it contains no source bodies, prompts or credentials. The [intent](worker-handoff-small-20261103/intent.json) and [test output](worker-handoff-small-20261103/ipse-handoff-current-control.log) are retained alongside it. The seed and complete journals remain in the temporary synthetic fixture, not in this archive.

SHA-256 fingerprints:

```text
67211c4d326a920cf9c2e8390169cdb9adf99b26b9e2243c815043319e6d547e  test/support/worker_handoff_trace.exs
26934758543cf4d3d4026b0a48d970c5e0125441267b49366da9fdcb46497173  test/dev/knowledge/worker_handoff_trace_test.exs
4ddbe1247352ab2c9422031cc9bb45d21fcb317ffaa3fb6d063730d06cebca89  tested dev/verification/worker_handoff_trace.exs
5929886c667d42d91f277ac517b6965310de897104059f496a52ffac4b880981  corrected, unverified dev/verification/worker_handoff_trace.exs
d9c0d8871139ac0ab56e9dd77aa0a9c9aaae78b92729e1a03f43831400dc9b7b  synthetic literal-ab-seed.json (not archived)
893afca80a5243b9b0b21055420f96cc385fd6ade4a608899fbe6e6fb250e88d  worker-handoff-small-20261103/intent.json
5c75dbf346a5f3f7d961554ca3f6b5b360a4cace94b2946fdd9f07f78d5885cd  worker-handoff-small-20261103/ipse-handoff-current-control.log
cb96b8251f34e87518b71391b902e38d1564b774b8480f08e478335454e74bd3  worker-handoff-small-20261103/report.json
67211c4d326a920cf9c2e8390169cdb9adf99b26b9e2243c815043319e6d547e  worker-handoff-small-20261103/tested-worker-handoff-trace.exs
26934758543cf4d3d4026b0a48d970c5e0125441267b49366da9fdcb46497173  worker-handoff-small-20261103/tested-worker-handoff-trace-test.exs
4ddbe1247352ab2c9422031cc9bb45d21fcb317ffaa3fb6d063730d06cebca89  worker-handoff-small-20261103/tested-worker-handoff-wrapper.exs
7861ccb8be22b058371a50a3cd5d74fc67f1c1965c4439b51afb9940642a8337  worker-handoff-small-20261103/unit-test.log
```

Commands ran from `/tmp/ipse-handoff-b10df4a5` with `IPSE_HOME` set to its isolated `ipse-home`, `ERL_FLAGS='+S 2:2'` and `TMPDIR=/tmp`:

```sh
IPSE_BUILD_COMMIT=b10df4a556c097b686eecba1267e3d6425f0f8bc ./dev/build.sh
mix test test/dev/knowledge/worker_handoff_trace_test.exs --max-cases 1 --seed 791961
elixir test/support/managed_literal_pair_runner.exs /tmp/ipse-handoff-eight-current-b10-01 _build/test/lib split
MIX_ENV=test mix run dev/verification/worker_handoff_trace.exs /tmp/ipse-handoff-eight-current-b10-01 current /tmp/ipse-handoff-trace-current-b10-01
```

Only the final command returned nonzero, for the guard reason above. The existing full-day evidence remains unknown; no effect or unresolved turn was retried.
