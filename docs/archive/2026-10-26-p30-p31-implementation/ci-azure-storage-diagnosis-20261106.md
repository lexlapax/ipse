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

The later [Linux package job at `6e5e4bdc`](https://github.com/lexlapax/ipse/actions/runs/42339613030/job/128304164393)
also completed successfully. Its listed steps include the PDF-enabled build,
formatter, strict compile, CI and documentation checks, demo, package, generic
installed Memory and synthetic source/installed extension, MCP, embedding,
document and Knowledge checks. The separate source partitions were still running
and macOS jobs queued when inspected. This is scoped evidence for that exact
commit; it is not a full source-suite result, managed protected-Collection or
macOS qualification, or evidence for later uncommitted changes.

The same commit's [Ubuntu source partition 4 of 4](https://github.com/lexlapax/ipse/actions/runs/42339613030/job/128304164583)
later finished with 1,231 tests, 195 failures, 45 excluded and 24 skipped on
`Linux 7.0.0-1017-azure`. The log contains many explicit protected-filesystem
refusals and separate terminal/input failures. Some document-stage wrappers
report only a generic refusal. Twelve such failures occur at the initial document
snapshot before the intended stage action; a thirteenth directly reports
`collection_filesystem_unsupported`. Source inspection shows that snapshot
admission invokes the native transaction quota preflight, for which the logged
Azure kernel is a sufficient refusal condition, before the wrapper maps the
result to a generic document refusal. Other earlier errors use that same generic
result, so the precise individual causes and the causes of all 195 failures
are not established. The other three Ubuntu partitions remained in progress and
macOS jobs queued when inspected.

Two more Ubuntu partitions subsequently finished: [partition 2](https://github.com/lexlapax/ipse/actions/runs/42339613030/job/128304164602)
reported 1,055 tests, 202 failures, 27 excluded and 27 skipped; [partition 3](https://github.com/lexlapax/ipse/actions/runs/42339613030/job/128304164580)
reported 1,168 tests, 267 failures, 41 excluded and 63 skipped. Partition 2
includes seven draft-acceptance terminal failures, including six timeouts and
one assertion waiting five seconds for a fourth replacement-read result. The
terminal log shows three completed interactions but not that fourth result;
these failures did not report a filesystem refusal, and why the reader stalled
is unestablished. The six timeout cases buffer their driver output until exit,
so the coincident driver and ExUnit deadlines leave their last phase unknown.
Partition 3 includes a document setup timeout and
generic Collection refusals whose individual causes remain opaque. The first
partition was still running and macOS jobs queued when inspected. These results
do not validate later worktree changes.

The [remaining Ubuntu partition](https://github.com/lexlapax/ipse/actions/runs/42339613030/job/128304164659)
subsequently finished with 1,208 tests, 317 failures, 11 excluded and 29
skipped. Its failures include terminal input cancellation and timeouts, and
generic managed-store unknown/refused results whose individual causes remain
unestablished. The nested synthetic recall wrapper's setup explicitly reports
`collection_filesystem_unsupported`; it did not access the declined retained
notebook. All four Ubuntu source partitions therefore failed at this commit;
macOS jobs remained queued when inspected.

One native-review fixture in that partition timed out independently of an
explicit filesystem refusal. An initial review attributed the timeout to the
driver answering before an `approval> ` prompt; that attribution was incorrect
for ordinary direct review. Its native reader flushes input before displaying
the card and does not emit a separate `approval> ` prompt. The proposed driver
change would therefore hang this path and was removed without running it; its
rejected patch remains under `_build/verification/`. The hosted log lacks the
child output needed to establish the actual timeout cause: `System.cmd` buffers
the driver's output, and the driver's own 60-second bound coincides with the
ExUnit timeout. A later bounded synthetic diagnostic must record phase and cleanup
evidence before the outer timeout; it cannot infer a native input outcome from a
written reply alone. Production flushing and deadlines are unchanged.

The hosted logs also contain terminal-input and live-MCP failures without a
demonstrated common cause. A separate macOS installed Memory action ended with
an unknown outcome as recorded in the
[Memory diagnostic](ci-memory-failure-diagnostic-20261106.md). Neither failure
is reclassified by the kernel observation. At the time of inspection the
repository had no configured self-hosted Actions runner. A supported hosted or
self-hosted environment still needs its own native qualification; do not widen
the kernel profile, skip assertions or replay an unknown effect to force a pass.
