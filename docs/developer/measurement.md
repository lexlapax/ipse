# Measure a complete workload and retain its authority

The optional Linux backend measures kernel workload-charged RAM. It includes
page cache and kernel allocations charged to the selected cgroup. It does not
measure process RSS, GPU memory, or an exact macOS aggregate. Sampled BEAM memory
remains a separate diagnostic. Choose the quantity before comparing results.

Use the [evaluation runbook](knowledge-evaluation.md) for declarations and phase
commands. This chapter teaches why the collector, sequence launcher, captured
evaluator, and service owner must agree before a peak becomes usable evidence.
The [dependency inventory](dependencies.md) records approval for the optional
Linux/systemd tooling. Ordinary Ipse operation and source tests do not require it.

## Read the three high-water subjects separately

A successful post-exit audit reports these distinct measurements:

| Subject | Audited field | Population and interval |
| --- | --- | --- |
| Whole lifetime | report.whole_lifetime.peak_bytes | Root workload, preparation, cells, finalization, and natural cleanup |
| Fresh stage lifetime | report.stages[].fresh_lifetime_peak_bytes | One fresh preparation, cell, or finalization scope and its descendants |
| Whole population during a stage | report.stages[].whole_population_interval_peak_bytes | Entire root population during that stage's reset/read interval |

Do not sum peaks, subtract a starting baseline, or describe them as resident bytes.
The whole lifetime includes retained charges between stages. A fresh cache uses
new inodes so it does not reuse page charges established outside that scope.
Shared-page ownership and cache/kernel charges differ from summed process memory.

For a worked field inspection, run the complete synthetic population in the
runbook. Its `source/run/verified-audit.json` retains the captured evaluator's
verified result before mutation controls. The public audit CLI prints a joined
summary/hash, with no full-report switch. Keep that result alongside native
receipts, stage records, and first predictions. A receipt alone is insufficient.
Never load a different checkout evaluator to inspect an existing captured seal.

The device policy is separate. CPU policy retains integer-zero final VRAM.
NVIDIA policy retains each selected resident model's reported size and positive
VRAM, permitting partial CPU/GPU placement. `placement_history_proven: false`
explicitly limits the observation. Final residency is not a peak or proof about
absent models or every earlier request. Synthetic residency establishes protocol
handling only. A valid resource audit establishes no held-out answer quality.

## Retain the evaluator before measuring

Creation-only `--sdk` plus `--repository` selects source-host execution;
`--archive` selects an installed host. Both require the exact clean declared
repository. A separate compiler VM builds the evaluator closure before sealing.
Retain `frozen-measured.runtime/runtime` beside the seal through execution, audit,
and scoring. Source-mode SDK/dependency/OTP/utility files remain unchanged external
prerequisites. This local capture is not a portable release archive.

`MeasuredExecution.Environment` embeds its policy in the retained BEAM. An unbound
build exposes refusal functions for its five APIs; application configuration
cannot enable them later. A fresh worker checks identities and loads the captured
bound implementation. A conflicting loaded module refuses replacement. Dynamic
launch avoids inferring policy from the bootstrap's unbound implementation; it
does not bypass module/file checks or supply a runtime fallback.

Later plain `elixir dev/evaluate-knowledge.exs` phases reopen that capture using
its expected freeze hash. The outer loader checks bounded manifests, complete
BEAM membership, and file identities before loading modules. A fresh child repeats
capture/full-seal verification and resolves relative caller paths before handoff.
The verified capture selects its entrypoint: current captures use Runner, while
older captures retain their separately captured CLI module. Reopening loads that
original module rather than borrowing a current implementation or recompiling it.
Changed or partial captures refuse. Historical source seals retain their original
full source launch checks; they cannot silently become partially captured runs.

Cold entry uses inspected `erlexec` with fresh private HOME/TMP outside evidence
and capture. It removes scratch after the phase and preserves the original
operation failure if cleanup also fails. Only the outer Linux manager retains
selected systemd user-service variables. Preparation, cells, and daemon use
separate strict environments; manager selection does not forward its environment
to work. The synthetic bootstrap is selected before sealing and cannot be
replaced by runtime control data.

## Follow authority before opening data or weights

Trace `context!/2`, `run/1`, `enter/1`, and `admit_stage!/2` in
`dev/evaluation/measured_execution.exs`. Entry rechecks source/seal and creates
exclusive launch plus fixed native-root evidence, separate from reports and the
removable registry. Deleting reports/registry never authorizes another first run.
An interrupted claim remains even if no terminal receipt exists.

The bound native descriptor retains distinct authorities:

| FD | Authority |
| --- | --- |
| 4 | Fixed native-root filesystem directory |
| 5 | Sealed attempts directory |
| 6 | Whole measured cgroup |
| 7 | Exact current workload cgroup |
| 8 | Native sequence evidence directory |

Native admission checks owner/mode, current named identity, and actual kernel
membership before launching work. A stage verifies token/index, ticket, exact
claim bytes, and started scope before opening Prepared, dataset, or models.
Ordinary children must not inherit these handles. The native manual owns
[scope descriptors](../../native/README.md#optional-exact-aggregate-memory-scopes)
and [sequence framing](../../native/README.md#sequence-complete-measured-stages).

Preparation admits all catalogs/options before dataset reads, then validates and
projects label-free inputs. Its prepared path uses `/proc/<preparation-VM-pid>/fd/4`.
`/proc/self/fd/4` would resolve in a lock helper rather than the owning VM.
Prepared binds plan, copied artifacts, inputs, effective time, runtime, and schedule
before future cell ticket/descriptor hashes, avoiding circular identity.

The schedule contains fourteen sorted-project/original-variant cells. Plans
two/three divide request, token, and monetary caps by original project count,
rounding down without transferring shares or changing reservations/rate cards.
A share below reservation refuses. The controlled Research gateway has its own
fixed project share. See [execution](knowledge-execution.md).

## Separate service work from cleanup and inventory

Each measured cell calls `ModelService.run/4` inside its fresh scope with the
verified environment constructor. Public `run/3` remains available outside that
captured path. The constructor runs once under the existing staging deadline;
launch and receipt reuse that environment. Control data cannot turn validation off.

Trace these steps in `dev/evaluation/model_service.exs`:

1. `validate/1` checks a closed runtime/cache/model/origin/deadline selection
   without IO, download, fallback, or attempt-renewal authority.
2. A guarded Task creates fresh private output and copies runtime plus complete
   manifest/blob closure. Native `--copy-regular` refuses unsafe source descriptors;
   Elixir hashes the private copies. `runtime/lib/ollama` preserves library layout.
3. The caller drains the native Port while staging works. A native `P` listener
   observation must identify the direct daemon child before HTTP inventory or the
   work callback. Child stdout is opaque log data, never listener proof.
4. Initial inventory checks exact tags/capabilities and empty residency. The work
   callback runs once. Returned work precedes final inventory and runtime/cache
   rechecks. A callback exception preserves the raised outcome, marks
   `callback_raised`, and goes directly to cleanup without more HTTP inventory.
5. Final resident digests must match. CPU requires integer-zero VRAM; GPU requires
   a nonempty set and `0 < size_vram <= size` for every row. Version three checks
   positive context on every resident, exact selected context for completion
   models, presence of all configured completion models, and unchanged before/
   after capabilities. Embedding-only context may be smaller. Missing data fails.
6. The owner stops Task/HTTP clients and daemon, then writes bounded logs/receipt.
   No log-file write blocks the live Port receive loop. Bytes drained during
   native close are outside the retained log prefix, as the receipt reports.

`work_status`, `service_status`, and `native_cleanup` are separate. A returned
callback can accompany invalid final inventory. Killing its Task cannot prove
Session closure, canonical accounting, or native population completion. Owner
death can leave no final service receipt; preserve that absence.

Both device policies disable cloud models, ROCm, and Vulkan. NVIDIA changes CUDA
visibility to one selected UUID. Defaults allow one parallel request, retain selected
models, and cap loaded models at the selection count; receipts show those values.
The explicitly selected runtime is trusted. This owner grants no OS sandbox.

During audit, `verify_receipt/4` reads the known `started.json`, matches its config
to the frozen selection, reconstructs the deterministic expected environment,
and validates capability/residency/context again. Receipt contents cannot choose
that constructor or override visibility/context. Legacy service receipts retain
their original versioned checks. A service receipt alone does not establish the
complete native population.

## Require natural population closure under original deadlines

The native root is born inside its fresh cgroup before exec using
`clone3(CLONE_INTO_CGROUP)`. After a zero-exiting leader, the fixed
`bounded_natural_drain_v1` policy allows at most 2000 ms for observed natural
emptiness, still within the original deadline and with authority intact.
Output EOF or process-group cleanup does not end population measurement.
Forced cleanup keeps failure even if the scope later becomes empty.

`population_stop` and `active_failure` in `native/ipse-measure.rs` use one population
read/timestamp for closure and terminal eligibility. Deadline equality refuses.
Guards run during drain and immediately before terminal output.
`MeasuredExecution.native_receipt?/2` requires version-two receipts, policy,
consistent drain timings, and elapsed time below original root/stage deadlines.
A later process list cannot supply missing fields or receipts.

Sequencing reads immutable stage descriptors, creates permanent claims, joins
native `M` receipts with two-byte `T` completion status, then admits the next
stage only after confirmed cleanup. Preparation/finalization follow the same
birth-before-exec path. Collector loss leaves a claim without completion and
prevents later stages. Forged application completion bytes remain opaque logs.
Writerless bootstrap/cell FIFOs refuse using nonblocking descriptor admission
before any corresponding work, rather than hanging until the run deadline.

The finalizer cannot read its future outer-root receipt. Post-exit audit joins
root/stage frames, exits, receipt bytes/file identity, scope/claim identity,
service/domain evidence, first predictions, and recomputed resources. It compares
all six merged streams against audited cells in sealed order. Raw cell execution
is bounded to 64 MiB each, fourteen cells in total; auditing uses 64-KiB chunks
and aggregate hashing rather than one giant binary. Other merged streams remain
32 MiB each. Parsed resource bytes come from the same checked chunks, not a later
unchecked reopen. `report.merged_files` binds the aggregate hashes.

Zeroing clocks or deleting requests plus recomputing summaries must still fail
`merged_stream_changed`. Use only the disposable synthetic proof's
`verify_tamper_controls!/1` in `dev/verification/measured_knowledge.exs` to exercise
those mutations. It restores original fixture bytes and requires audit to pass
again. Never mutate real comparison evidence.

## Prove ownership and loss behavior independently

Use Linux with cgroup v2 memory accounting, clone3 support, a delegated systemd
user manager, and the existing Rust/Elixir toolchains. These commands create/stop
only their own uniquely named transient services and preserve evidence:

```sh
./dev/build.sh
elixir dev/verify-memory-scope.exs "$PWD/priv/ipse-runner"
elixir dev/verify-memory-drain.exs "$PWD/priv/ipse-runner"
elixir dev/verify-memory-terminal.exs "$PWD/priv/ipse-runner"
elixir dev/verify-memory-sequence.exs "$PWD/priv/ipse-runner"
mix test test/dev/platform/memory_scope_test.exs --include memory_scope
```

The first three summaries expect 10, 12, and 4 checks, with zero inference.
Serial/overlap allocations distinguish simultaneous totals from individual
maxima. A brief 256-MiB Port child must remain in the peak after exit. Nested
unequal allocations check independent parent interval resets. Drain controls
release ordinary/detached children after leader reap to allocate another 128 MiB;
fresh and parent interval peaks must include it.

Persistent children, nonzero leaders, cancellation, expired original deadlines,
anchor loss, collector loss, and registry replacement remain incomplete. The
terminal verifier compiles private diagnostic source copies with a barrier before
the final guard; a deliberately reversed guard proves the cancellation control
reaches that boundary. Those diagnostic binaries cannot supply accepted peaks.
The sequence controls include unrelated siblings outside the root, forged frames,
and FIFO refusals. Run native parser/filesystem tests separately:

```sh
IPSE_SEQUENCE_TESTS=$(mktemp -d)
rustc --edition=2021 --test -D warnings native/ipse-sequence.rs \
  -o "$IPSE_SEQUENCE_TESTS/sequence"
"$IPSE_SEQUENCE_TESTS/sequence"
```

For model service ownership, use the scripted Rust inventory daemon:

```sh
mix test test/dev/evaluation/model_service_test.exs
IPSE_MODEL_PROOF=$(mktemp -d)
rustc --edition=2021 -D warnings dev/fixtures/model_service_probe.rs -o "$IPSE_MODEL_PROOF/probe"
elixir dev/verify.exs source model-service \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_MODEL_PROOF/probe" \
  --output "$IPSE_MODEL_PROOF/evidence"
```

Expect 31 retained synthetic cases, including wrong/missing/unobserved context,
occupied ports, private inodes, changed inventory, callback exceptions, service
loss, and owner death. No model loads. On macOS this proof instead confirms
pre-staging refusal. Repeat with a compatible package and fresh output using
`installed model-service --archive "$IPSE_ARCHIVE"`; installed runtime PATH has
no development commands. Inspect each verification/receipt and preserve failures.

Finally run the integrated loss controls with the runbook's seven-artifact map:

```sh
elixir dev/verify.exs source measured-authority \
  --sdk _build/dev/lib/ipse/ebin --repository "$PWD" \
  --input "$IPSE_BENCHMARK/artifacts.json" --output "$IPSE_BENCHMARK/authority-source"
```

Five independent seals observe live preparation FDs 4..8 and membership before
owner loss, collector loss, service stop, registry replacement, or daemon loss
after its first answer request. Expect owned-scope cleanup and refused reentry.
The daemon-loss case may admit later distinct cells only after cleanup; it never
retries the interrupted request. Missing domain closure remains distinct from
process disappearance. Repeat as `installed measured-authority` with the exact
archive and a fresh output to verify that runtime too. These controls measure
no model quality and cannot replace the complete execution/audit join.

## Interpret latency and storage coverage honestly

Phase clocks use monotonic microseconds; nearest-rank p50/p95 use milliseconds,
with sample/unknown counts. Failed query clocks remain recorded. Projection
phases include storage audits; `invoke_index`/`invoke_extract` isolate public
commands before those audits. Unconfirmed completion has its own count, and an
elapsed wait does not prove remote work ended. Canonical request duration remains
unknown when the journal cannot establish it.

Read `complete`, `storage_reachability_complete`, `measurement_scope`, `unmeasured`,
and `resource_evaluation_complete` separately. Storage file lengths are not
allocated blocks, compression/shared extents, or exact transient storage peaks.
Run-directory counts exclude authoring/preflight copies outside it; output-wide
overviews count them separately with stated exclusions. Version-one overview
clocks start at runner entry and exclude CLI/module startup plus their own final
inspection. Version one has no equivalent charged-memory aggregate. Preserve
these limits when selecting an eligible strategy or publishing comparisons.
