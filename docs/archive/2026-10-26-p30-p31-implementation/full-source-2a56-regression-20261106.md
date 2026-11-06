# Frozen 2a56 full-source regression, 2026-11-06

Historical verification record. [Testing](../../developer/testing.md) owns the
current procedure, and [the plan](../../plan.md) owns remaining acceptance.
This completed failed run is not a current-source passing baseline and does not
replace the [earlier interrupted 489-file attempt](source-regression-489-20261106.md).

## Frozen scope and final result

One independent source copy at
`2a56c60b8f8bcabe047f189d37f82f4e12cb8b5a` contained **497 tracked test files**.
Its qualified runtime contained 243 host modules and 16 applications. The
host-only preparation compile passed 199 source files without warnings, bound
BuildInfo and compile-source paths to that copy, and preserved the copied
dependencies, native helper and four normal bundles. It did not rebuild those
bundles or mutate main's runtime.

The normal-start whole default command was:

```sh
mix test --no-compile --no-deps-check --max-cases 2
```

There were no filters, partitions or automatic retries. The command used an
isolated credential-free HOME/operator configuration, pinned Hex archive,
private temporary paths and two scheduler/async threads. Its independent Git
metadata had no alternates or hardlink dependency on the main checkout. The
outer coordination limit was **10,800 seconds plus 30 seconds kill grace**;
product and test deadlines were unchanged.

The actual terminal result was **exit 2**, after **9,447.2 seconds**: 345.8 seconds
reported async and 9,101.4 seconds sync. The final outer ExUnit summary was:

```text
Result: 4184/4188 passed, 136 skipped, 124 excluded
```

There were **four outer test failures**. Nested subprocess reports are separate
scopes and are not added to that denominator or failure count.

| Frozen failing test | Boundary |
| --- | --- |
| `Ipse.InferenceDispatchTest`: “postqueue refusal performs no provider callback or budget reservation” | Stale expectation that an unentered callback left no durable budget booking |
| `Ipse.InferenceDispatchTest`: “a provably unentered budget callback records not_started and a fresh request uses the only HTTP call” | Stale admission/accounting expectations under retained pre-slot reservation |
| `Ipse.KnowledgeCollectionDirectoryTest`: “two manifest pages bind exact catalog heads and selected groups without projection payloads” | Synthetic response fixture returned `collection_response` where the fixture expected `generation_job_changed` |
| `Ipse.Session.OllamaModelPinTest`: “a preflight mismatch settles unstarted without sending input or booking inference” | Stale zero-unknown-liability expectation after model precheck refused |

Separate [whole-file budget and Ollama fixture repairs](budget-reservation-fixtures-20261106.md)
retain conservative booking and no automatic refund. The
[directory fixture](../../../test/support/collection_directory.exs) has its own
later response-shape correction; the
[bounded public restore journey](document-result-restore-public-20261106.md)
is separate evidence, not a rerun of this directory test or this full suite.
The [child-counter repairs](ci-child-result-counters-20261106.md) likewise retain
their independent representative scopes. None changes the frozen four failures
or establishes a current-source full pass.

## Integrity and cleanup

The original suite was polled through its terminal outcome. The launcher recorded
`primary=2` and `test_exit=2`; immutable-copy and launch-input posts both returned
zero. The completed copy check covered 10,293 source paths, 497 test files,
1,521 runtime leaves, 51 SCM files and 133 Hex files. It permitted only the
existing Mix test-failure metadata path, whose actual bytes were separately
hashed. Main's subsequently changing source and runtime were not frozen by the
independent run.

The launcher observed no Input holder, fixed-port-39657 listener or scoped
process, with the expected no-match status and empty output/error files. Its
observed process group was empty. A separate actual-host check confirmed that
the bounded PID, group and scoped helpers were absent and both Input and the
listener were free. These are terminal cleanup observations, not an explanation
for any failed assertion. Future native TTY work still requires its own
serialized ownership checks.

Resource admission included available-memory/free-space checks and an allocated
32 MiB random-data/fsync probe in the selected private temporary filesystem.
It does not establish an unlimited quota, cgroup capacity or exact whole-run
peak. No original retained notebook was read, and no paid provider or real model
service was used. Synthetic fixtures and their existing local transports remain
within this source-regression scope.

## Evidence commitments

Private evidence remains under `new-full-regression-20261106-01`. The following
are safe metadata/result commitments; no raw test log, Session journal, private
source content or copied runtime is exported.

| Evidence | SHA-256 |
| --- | --- |
| Preparation handoff | `f1c19515baf5acd57bffde3007a1fdac138bb14a55d6ca20b2ad7fe9f89bfc3d` |
| Prepared runtime | `2522784afac18b192e6fbbee15bbf6bbf3d37965c044794afae04eb615c2ecc6` |
| Runtime qualification | `6b68fda2a30b58f4ae3d867f738264123d9df9f73a754e44a4e3f6e4baec10f8` |
| Reviewed launcher | `2a0deac52f508c0c4754924c16d672fa720d03cea398d73d7990ad2acabde2c2` |
| Launch-input manifest | `4422151af118984a2a1e97669c59a995b0e7fae9f1e72d7a4ebe5dcd2056e62a` |
| Final outer summary | `64aaa6e9378660f3f389cefcf2581d6d146e873b361a3653f8355b699757c232` |
| Terminal/post status | `d3c709d30f600b5244a04645b561132cf91724319063a30e579b8ba55d068dcf` |
| Final immutable-copy report | `6341ace5ac37fe9b9912c9162545e0165a37af09606574855fb4ec36cdf72e17` |
| Each empty independent PID/group/Input/listener observation file | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

The independent cleanup command's exit-zero outcome was confirmed separately by
the operator of that command; empty files alone do not encode its exit status.
The completed aggregate remains failed. Hosted CI, installed-package
qualification, subsequent Native changes and full mixed-target capacity require
their own evidence.
