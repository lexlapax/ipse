# Exact aggregate memory design, 2026-10-19

Historical design decision after `4fc3e74`, not an implemented measurement or a
P27 completion verdict. The user selected the exact simultaneous combined total
across all Ipse and model processes. This supersedes the pending scope question
in the earlier [memory investigation](resource-memory-grounding.md).
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance and
the [evaluation training manual](../../developer/knowledge-evaluation.md) owns
current implemented procedures. Commands and signatures below are proposed.
The later [native collector record](aggregate-memory-native.md) covers the first
implemented backend and its verification; this page retains the original design.
The later [portable experiment record](portable-experiment.md) resolves the
reopened metric/platform decision as workload-charged RAM with an optional Linux
backend and records the approved CPU-only policy. The proposals below retain
their original status and context.

## Choose complete fresh cells inside one measured run

Two independent design contexts compared a persistent coordinator with complete
disposable cell executables. A third context cross-reviewed both packages and
the source seams. These are independent review contexts, not different-model
claims. The selected base uses fresh complete cells. The persistent design loses
because its retained coordinator and cache state make later cells depend on the
earlier strategy order. Keep its distinction between whole-population intervals
and subordinate cell measurements, plus its independent counter-FD controls.

The caller supplies one frozen comparison, a fresh output and an admitted Linux
measurement capability. The outer entry is native, before any application BEAM
or model process. Only counter, scope, identity and cleanup bookkeeping runs
outside the measured application hierarchy.

```text
native measurement collector
  whole comparison scope
    measured native sequencer
    preparation BEAM and descendants
    fresh project/strategy cell
      complete evaluator BEAM and descendants
      owned model daemon and all model runners
    subsequent fresh cells
    finalization BEAM and descendants
```

Preparation validates the seal and produces the immutable schedule and projected
inputs. A cell owns the complete existing `run_variant/9` lifetime, including
source authoring, indexing/extraction, answers, audits, suppression, collection,
Session closure and budget reconciliation. Finalization merges the first rows,
checks the complete grid and seals prediction hashes before reference semantics
are opened. All these application processes contribute to the parent counter.

The implementation interface hides kernel paths and protocol frames:

```rust
fn execute(capability: AdmittedScope, launch: FrozenLaunch)
    -> Result<ComparisonReceipt, Refusal>; // not implemented
```

```elixir
# Called inside the measured application entry, not in an excluded outer BEAM.
EvaluationRun.execute(%{seal: seal, output: fresh_output, schedule: schedule})
# not implemented
```

Keep preparation, cell and finalization as entry modes of one evaluator owner.
Do not create shallow wrappers per stage. The existing runner's `execute/6` and
`run_variant/9` are the integration seams; ordinary Worker/MCP/shell frame
contracts remain separate.

## Name the exact kernel subject

The first backend under investigation is
`linux_memcg_charged_peak_bytes_v1`. Linux cgroup v2 `memory.peak` records the
scope's aggregate charged-memory high water. It captures overlap and exited
descendants without userspace RSS sampling. Its categories include anonymous
memory, page cache and kernel charges. It is not summed process RSS or a proven
GPU/device-memory total. Shared-page ownership can differ from mapping ownership.
The [kernel manual](https://docs.kernel.org/admin-guide/cgroup-v2.html) defines
the counter, memory ownership, inherited membership and per-FD resets.

Report three different subjects separately:

| Receipt | Subject |
| --- | --- |
| Whole lifetime | Untouched parent counter for all application work |
| Whole-population cell interval | Independently reset parent FD while that cell runs, including the sequencer and retained parent charges |
| Fresh cell lifetime | Fresh cell scope, including its evaluator/model descendants but excluding other measured siblings |

Never sum these peaks or subtract a baseline. A fresh cell has fresh process
lifetimes; that does not prove all parent cache charges disappeared. These scope
and cache differences must remain visible in the comparison report.

No supported public exact macOS aggregate has been established. Unsupported
platforms refuse before inputs or inference. Linux results do not become macOS
measurements. Device-memory coverage remains unproved; do not silently disable
GPU execution, change models or claim complete device coverage. Selecting this
capability design does not yet establish the full resource acceptance gate.

## Preserve original attempts and allowances

Each cell retains the original full-plan project count when dividing its model
budget. Before launch, exclusively create and sync its permanent attempt claim.
A missing final receipt means failed or unknown work, never permission to rerun.
Each cell writes separate files; finalization merges them once. Preserve canonical
admission, dispatch, observation, settlement and retained liability separately.

Avoid a new shared mutable Research gateway ledger. The current global ceiling
is `expected_queries * (1 + max_sources)`. Seal disjoint cell shares using each
cell's original query count. Require their sum not exceed that ceiling. A started
cell permanently reserves its share; unused shares never transfer or refund.
Local gateways enforce their fixed shares. Interrupted shares stay reserved.
This is a declared policy change for the new freeze, not a claim that every
reserved call was dispatched, paid or unknown. Existing per-invocation approval
limits still permit one search and at most `max_sources` distinct fetches.

Freeze code, artifacts, launcher, metric ABI, kernel capabilities, population,
lifetimes, model executable/libraries, model/config digests, endpoint, cache and
hardware policy. The existing Serenity service does not prove matching selected
models. No old prediction, unknown request or budget root is replayed or renewed.

## Prove admission and cache ownership

A writable cgroup directory is insufficient. The native launcher must start in
an authorized delegation and place new application children in their scope before
exec, preferably using a verified `clone3(CLONE_INTO_CGROUP)` capability. Never
migrate an already running BEAM or model daemon and assume its earlier charges
move with it. Retain directory/descriptor identity through cleanup and receipt
publication. Scope names or reusable PIDs alone are insufficient identities.

Stage fresh private model-cache inodes and verify their bytes inside measurement.
Outside hashing can first-touch pages into another charged scope. Never mutate
the operator cache or use hardlinks to it. Shared runtime/library page ownership
still follows the kernel accounting subject and must be disclosed.

Normal closure requires public Session confirmation and owned model shutdown.
Forced closure kills only the retained owned hierarchy, proves emptiness, reads
the terminal counter and saves the receipt before removing scope directories.
Cleanup, effect outcome and counter coverage are separate fields. Collector loss
leaves incomplete evidence and a cleanup-only recovery path, never inference
resume. This is a controlled trusted benchmark, not a new same-UID OS sandbox.

## Actual synthetic capability evidence

Serenity has Linux `7.2.9-arch1-1` and a user-owned delegation with the memory
controller enabled. A fresh owned leaf starts at zero. Direct migration of an
SSH child into that leaf fails with permission denied. The common ancestor lies
outside the delegation, so ownership of the target does not authorize entry.

One disposable service through the existing user manager ran a native probe:

The [preserved Rust source](probes/aggregate-charged.rs) has SHA-256
`4a1c07227614a6c9040c23a8477bf12fe232025f012bf61a018fef154851cc93`.
It uses only Rust's standard library and the kernel's cgroup files. It is a
bounded historical experiment, not the production supervisor or a default test.

| Control | Actual charged peak, bytes |
| --- | ---: |
| Empty | 745,472 |
| Two sequential 64-MiB allocations | 68,345,856 |
| Two overlapping 64-MiB allocations | 135,950,336 |
| Later single allocation after independent FD reset | 68,820,992 |
| Unreset lifetime after all intervals | 135,950,336 |

Children synchronize through pipes, exit normally and are reaped. No samples or
inference run. The disposable service, cgroup and owned temporary files were
removed; existing model services and source checkouts were untouched. This proves
counter/reset behavior, not production launch, ERTS coverage or forced cleanup.

The experiment used the installed `systemd-run --user --wait --collect --pipe`
with a unique unit and `MemoryAccounting=yes`. Adopting systemd user-service
tools as an optional benchmark dependency still requires the explicit approval
specified by [AGENTS.md](../../../AGENTS.md) and the
[dependency policy](../../developer/dependencies.md#make-the-adoption-decision-explicit).
No such dependency is adopted by this design record.

## Next implementation and verification

First prove delegated native birth-before-exec and a closed owned-scope lifecycle
without models or datasets. Extend the allocation control through ERTS, include
measured preparation/finalizer allocations, exclude an unrelated sibling, and
test independent whole/interval/cell counters. Test child forks during cancel,
owner/collector loss, retained incomplete receipts and first-attempt refusal.
Test private-file first touch and the fixed nonrenewing Research shares.

Only then integrate complete cells, exact service/model identities and the freeze.
Run source, native, installed and applicable platform checks. Prepare the fresh
complete comparison after the metric/device/platform coverage is reconciled.
Model quality, semantic citation precision and engine selection remain open.
