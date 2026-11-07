# Hosted storage admission diagnosis — 2026-11-06

Historical hosted evidence. The [plan](../../plan.md) owns current acceptance;
the [storage chapter](../../developer/knowledge-storage.md) describes the
current admission boundary. This is not a qualification of a new kernel or
filesystem.

An earlier Ubuntu source-test partition in
[run 42325834722](https://github.com/lexlapax/ipse/actions/runs/42325834722/job/128260788938)
reported 1,231 tests, 194 failures, 45 excluded and 24 skipped. Many failures
included protected-storage unsupported results; other timeout and assertion
failures also occurred. That job did not record its kernel or filesystem, so
its log alone does not identify the failing admission predicate.

Commit `1f26827d` adds `uname -sr` to hosted check jobs without changing the
matrix, tests, resource limits or admission policy. The later Ubuntu partition
[job 128291993474](https://github.com/lexlapax/ipse/actions/runs/42335693361/job/128291993474)
reported `Linux 7.0.0-1017-azure` and finished with 1,166 tests, 267 failures,
41 excluded and 63 skipped. The current Linux allocation profile accepts the
recorded 7.2.10 family or the exact separately qualified 7.2.11 Arch tmpfs
configuration; it rejects this Azure kernel before filesystem qualification.
This explains refusals at that admission gate. The log does not establish the
runner's filesystem or prove that every failure has this cause.

The separate [Linux package job](https://github.com/lexlapax/ipse/actions/runs/42335693361/job/128291993490)
at `1f26827d` succeeded on the same reported kernel. It passed the PDF-enabled
build and protocol checks, formatter, strict compile, CI/documentation checks,
demo, package and listed synthetic source/installed verifier steps. The generic
installed Memory fixture included 100 records and 100 queries across six
Sessions and two projects, without inference; it was not the declined retained
notebook. Other completed steps covered model-service, extension, MCP, embedding,
saved-result, document-parser and Knowledge fixtures. The Knowledge MCP proof
reported nine checks with Session acknowledgments and backend-process exit as
its cleanup scope. This job did not run the full source suite, qualify managed
Collection storage or test live models. Its success is evidence for the exact
older commit and listed synthetic steps, not the later candidate or macOS.

The hosted logs also contain terminal-input and live-MCP failures without a
demonstrated common cause. A separate macOS installed Memory action ended with
an unknown outcome as recorded in the
[Memory diagnostic](ci-memory-failure-diagnostic-20261106.md). Neither failure
is reclassified by the kernel observation. At the time of inspection the
repository had no configured self-hosted Actions runner. A supported hosted or
self-hosted environment still needs its own native qualification; do not widen
the kernel profile, skip assertions or replay an unknown effect to force a pass.
