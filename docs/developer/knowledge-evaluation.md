# Measure knowledge results without exposing labels

Use this chapter to follow one complete knowledge comparison, change its owners,
and diagnose a failed first execution. Start with a built, clean source checkout.
The complete measured exercise needs Linux cgroup v2, delegated systemd user
services and the toolchains listed in [dependencies](dependencies.md). The smaller
Session, scoring and identity exercises also run without that optional backend.
For package implementation, start with [knowledge extension development](knowledge-extensions.md).

## Follow the prediction and scoring boundary

A comparison has two identities. The portable experiment binds source and artifact
content, algorithms, model identities, prompts, budgets, dataset hashes and policy.
A local execution seal adds paths, the current runtime and a fresh execution ID.
One measured execution consumes that local identity. A later audit verifies its
saved first predictions before review or scoring can open labels.

Follow these owners in execution order:

| Owner | Implementation | Responsibility |
| --- | --- | --- |
| Plan | `examples/knowledge/evaluation_plan.exs` | Build the explicit seven-strategy declaration without opening inputs |
| Identity | `examples/knowledge/evaluation_freeze.exs` | Declare portable content and seal one closed local resolution |
| Measured execution | `examples/knowledge/evaluation_measured_execution.exs` | Claim the native root, admit preparation/cells/finalization and audit their evidence |
| Kernel population | `native/ipse-bound.rs`, `ipse-measure.rs`, `ipse-sequence.rs` | Retain directory/scope authority, launch work inside cgroups and record terminal receipts |
| Domain execution | `examples/knowledge/evaluation_runner.exs` | Admit catalogs, project inputs, run complete cells and finalize first predictions |
| Model lifetime | `examples/knowledge/evaluation_model_service.exs` | Copy a fresh runtime/cache, own one daemon and guard one complete cell callback |
| Public Session | `examples/knowledge/evaluation_session.exs` | Invoke approved public commands and retain complete results and cleanup acknowledgments |
| Input and answer projection | `evaluation_input.exs`, `evaluation_answer.exs` in the same directory | Keep labels outside predictor input and map shown answer spans back to complete evidence |
| Inspection | `evaluation_inventory.exs`, `evaluation_resources.exs` | Verify storage reachability and reconcile canonical requests with conservative budget liability |
| Review and score | `evaluation_review.exs`, `evaluation_integrity.exs`, `evaluation_score.exs`, `metrics.exs` | Blind saved predictions, recompute literal references from captured bytes and measure independent semantic verdicts |

The Session driver imports artifacts through ordinary host APIs. It does not load
production knowledge modules into the evaluator or call a provider directly.
Its caller validates the complete proposed action. A selected profile names a
route; it does not approve every request on that route.

Keep labels and expected answers out of the driver, extension options and model
inputs. Query projection produces only `query_id`, `project` and `query`. Save and
hash all first predictions before review. A scorer can enforce its own loader
order; it cannot prove that another caller has never read a label file.

## Run a complete synthetic measured population

Use this exercise to follow the integration before selecting real runtime or
model files. It builds seven artifacts and uses a scripted Ollama-protocol daemon
inside every measured cell. It loads no model weights and makes no quality claim.
Run it from a clean repository on the supported optional Linux backend:

```sh
./scripts/build.sh
IPSE_MEASURED_PROOF=$(mktemp -d)
mix run scripts/verify-measured-knowledge.exs -- "$PWD" "$IPSE_MEASURED_PROOF/source"
```

A successful invocation reports `synthetic: true`, `model_quality_measured: false`,
350 saved rows and complete execution/resource audit results. The workload has
fifty queries, two projects and seven strategies. Its fourteen cells each own a
fresh daemon and complete public-Session lifecycle. The driver checks selected
model calls, exclusion markers, canonical request counts, unchanged read-only
audit, first-attempt refusal and changed-evidence refusal. Its scoring controls
exercise actual v2 CLI review, an unmeasured score exit and refusal before label
or review input access. These are expected results to verify, not evidence that a
particular source, host or package has passed.

Inspect `$IPSE_MEASURED_PROOF/source/source/freeze`, the adjacent `reports`, and
the adjacent `scoring-controls` directory. A failed command
preserves its partial evidence. Read the first failed stage's `process.log`,
`started.json`, terminal receipt and domain report together. Do not remove a claim
or repeat model work against that seal. After diagnosing a synthetic failure,
choose a new output directory for a separate exercise.

To exercise a bundled runtime, use the artifacts built by the source exercise:

```sh
./scripts/package.sh
set -- dist/ipse-*.tar.gz
test "$#" -eq 1
elixir scripts/verify-measured-knowledge-package.exs \
  "$1" "$PWD" "$IPSE_MEASURED_PROOF/source/artifacts.json" \
  "$IPSE_MEASURED_PROOF/installed"
```

The installed driver extracts the archive, retains its hash and runs the same
synthetic population through bundled `ipse eval`. Its outer release process has
no `elixir`, `elixirc`, `mix`, `rustc` or `cargo` on PATH. Child launch environments
include selected runtime and system directories; that outer assertion is not a
claim that development tools are unreachable everywhere. Artifact construction
happens before the installed run. Source helpers remain explicitly loaded from
the checkout, while BEAM/native execution uses the selected installed runtime.
A successful installed exercise is protocol evidence for that archive and host.
It does not establish real Ollama CPU execution, held-out quality or complete
failure/loss coverage. Keep actual evidence in [dated records](../archive/index.md)
and acceptance criteria in [the plan](../plan.md#p27-optional-research-graph-and-rag).

### Exercise authority and loss before accepting an execution change

Use the same prebuilt artifacts with a fresh output directory:

```sh
mix run scripts/verify-measured-authority.exs -- \
  "$PWD" "$IPSE_MEASURED_PROOF/source/artifacts.json" \
  "$IPSE_MEASURED_PROOF/authority"
```

This helper creates five separate synthetic seals. It observes the actual
preparation VM's descriptors 4 through 8 and kernel membership before inducing
owner loss, collector loss, an owned-service stop or registry replacement. The
service-stop case also checks the ordinary native helper and daemon's complete
descriptor inventories for leaked authority objects. The fifth seal selects a
fixture that exits itself after recording its first answer request. Its failed
service receipt, incomplete stage and first canonical request remain observable.

Expect five retained control results, confirmed owned-scope cleanup and refused
reentry. An absent live observation, missing cleanup or unexpected later claim
fails the exercise and preserves `failure.json`. A missed timing boundary is
not a passing capability check. The daemon-loss case permits later distinct
cells only after confirmed cleanup; it never retries the interrupted request.
Inspect its original journal and usage separately from process disappearance.
This control does not manufacture full liability reconciliation when the domain
report is unavailable. It starts only its own temporary services and stops only
those named units. These controls need the optional Linux backend and establish
no model quality.

## Declare the complete comparison

Build the seven independent artifacts into a fresh private directory. These
commands compile artifacts without importing them or contacting a model:

```sh
IPSE_BENCHMARK=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/lexical" --package corpus --preset state-lexical
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/dense" --package corpus --preset state-dense
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/semantic" --package corpus --preset state-semantic
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/explicit" --package graph --preset state-explicit
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/model" --package graph --preset state-model
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/research" --package research --preset mcp
elixir examples/model-calls/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/answer"
cp examples/knowledge/benchmark-spec.json "$IPSE_BENCHMARK/spec.json"
```

Review `spec.json` before generating a plan. It declares a fifty-query held-out
comparison with lexical, explicit graph, model graph, dense, hybrid, rerank and
Research variants. Every variant selects the same answer helper. Its example
local profiles name Qwen and embeddinggemma with exact expected inventory
digests; review the endpoint, installed model identities and budgets for your
authorized run. There is no provider fallback or model download. The declared
`corpus.json` and `heldout.json` are relative dataset member names. Confirm the
actual member names from independently supplied metadata before freezing;
generating a plan does not verify them or open the dataset manifest.

Generate the private version-one plan used by both identity exercises below:

```sh
mix run scripts/prepare-knowledge-evaluation.exs -- --spec "$IPSE_BENCHMARK/spec.json" --output "$IPSE_BENCHMARK/plan.json" --new-blind-seed
```

Expect `status: "ok"`, the output path, its SHA256 and `variants: 7`. The script
resolves artifact paths relative to the specification, validates every variant
and writes an owner-only file. It starts no artifact worker, dataset read or
model request. Existing output paths refuse. `--new-blind-seed` requires a null
seed in the input and creates a fresh value in the private plan; it does not
print that value or make inference deterministic. Keep the plan private when
preparing independent blind review.

The example budgets explicitly cap each variant at 1024 baseline requests or
8192 requests for inference-heavy preparation. Their token caps equal their
request cap times the declared reservation. These are finite admission limits,
not predicted consumption or cost. The runner divides request and token caps
equally among projects. The baseline caps cover fifty answers even for an uneven
project split; unused shares are not transferred or renewed. Review preparation
capacity separately. Each evaluation Session explicitly sets its inference-step
limit to that project's allocated request cap plus one. This lets the next request
reach canonical budget-refusal accounting; the budget still prevents dispatch.
Preflight reports the selected `inference_step_limit`. Embedding and text calls
consume the same step allowance. Ordinary Session defaults are unchanged.
Research requests up to ten sources within its body and time bounds. Knowledge
artifacts use SDK 2 for complete results up to the 4 MiB aggregate limit, subject
to journal capacity. A capacity refusal or unavailable complete result remains
a failed row; the runner does not reduce the source set to make that row succeed.

For an exposed-input tuning exercise, use a version-one plan with `mode: "tuning"`,
a numeric `as_of_ms` and `data.split: "tuning"`. Every text and embedding profile
must name the same explicit HTTP IPv4-loopback origin. The runner derives that
origin from the profiles, including a canonical private port such as
`http://127.0.0.1:47635`; it does not add another endpoint setting. A conflicting
profile, malformed origin or collision with `search_port` refuses. The default
port remains usable when explicitly selected. This does not change legacy
version-one held-out policy or version-two measured resolution.

Keep the actual service under its declared owner. Tuning starts no daemon and
grants no fallback to another endpoint. With a reviewed tuning plan, exposed
input files and an already admitted service, run:

```sh
mix run scripts/evaluate-knowledge.exs -- --phase tune \
  --plan /absolute/path/to/tuning-plan.json \
  --corpus /absolute/path/to/exposed-corpus.json \
  --queries /absolute/path/to/exposed-queries.json \
  --output /absolute/path/to/fresh-tuning-results
```

Catalog admission and `/api/tags`/`/api/show` inventory use that exact origin
before the input files open. Preserve first failures and cleanup; do not retry an
unknown request or present exposed-input tuning as fresh held-out validation.

The explicit `storage_policy: "forget_all_then_collect_v1"` selects the final
storage exercise. After saving every query prediction for a project/variant,
the runner suppresses its isolated source copies and collects their unreferenced
pages. Review that policy before freezing. The original input corpus and saved
predictions remain available for scoring; these operations use the same Session
and do not renew its inference budget. Research has no retained source store.

Run the declaration exercises before changing this format:

```sh
mix test test/knowledge_evaluation_plan_test.exs test/knowledge_evaluation_runner_test.exs
```

The CLI control generates two independent seeds, checks permissions, refuses an
overwrite and verifies that nonexistent dataset/artifact paths stay unopened.
The private-origin control declares a common tuning address and refuses divergent
profiles, malformed origins and a search-port collision. The runner control
observes an actual inventory request at the selected loopback listener, then
returns an empty inventory. That preflight failure must precede access to absent
input files and must produce no inference request.
The public-Session matrix uses this same builder with scripted profiles. A
valid plan is preparation. The identity seal and executable preflight are
separate checks. Declaration and sealing do not run workers or open held-out inputs. Measured
preparation performs executable catalog admission after native authority passes.

## Seal identities before opening inputs

Use a version-two seal for the measured path. Version-one seals keep the fixture,
tuning and frozen-prediction behavior described later in this chapter. Both
formats require separately retained expected hashes and fixed source/runtime
bytes. Git inspection uses `--no-optional-locks`, so verification does not refresh
the source index as a side effect.

### Separate the experiment from its local execution

Use the complete plan and seven artifacts prepared above. Keep the checkout
clean, including untracked files. Store receipts separately from authoritative
freeze data and disposable reports:

```sh
IPSE_RETAINED=$(mktemp -d)
mix run scripts/evaluate-knowledge.exs -- --phase declare \
  --plan "$IPSE_BENCHMARK/plan.json" \
  --output "$IPSE_BENCHMARK/experiment.json" \
  > "$IPSE_RETAINED/declaration.json"
IPSE_EXPERIMENT_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["sha256"])' "$IPSE_RETAINED/declaration.json")
```

Expect `status: "ok"`, the experiment path/hash and the source commit.
`EvaluationFreeze.declare/3` removes source/artifact paths, profile origins and
the search port. The private blind seed remains part of the experiment. Keep
that declaration away from the independent reviewer.

The declared policy selects `linux_memcg_charged_peak_bytes_v1`, CPU-only model
execution, fresh private cache inodes per cell, two projects and the optional
`linux_cgroup_v2_v2` backend. Its fixed `bounded_natural_drain_v1` completion
policy permits at most 2000 ms after leader reap, within the original workload
deadline. That policy belongs to the declaration alongside the memory quantity;
changing it requires a fresh experiment and execution seal. Local runtime/version
provenance does not become a hostname or kernel-version allowlist. A local seal
is not relocatable or renewable.

### Build the six local bindings

A resolution contains exactly `artifacts`, `model_origin`, `search_port`, `reports`,
`data_manifest` and `model_service`. The service selection is the existing closed
`EvaluationModelService.validate/1` schema. Its origin and exact model map must
match the resolved plan. The shared model port 11434 is forbidden; the search
port must differ. Sealing proves neither port availability nor listener ownership.

For an already authorized real comparison, select a reviewed local Ollama
runtime distribution and existing model cache. The runtime directory below must
contain `bin/ollama` and its complete `lib/ollama` files as regular files. The
example hashes those runtime files. Model manifests/blobs stay unopened until
cell staging. It downloads nothing and does not borrow a running service:

```sh
export IPSE_BENCHMARK
export IPSE_DATA_MANIFEST=/absolute/path/to/reviewed/dataset/manifest.json
export IPSE_OLLAMA_RUNTIME=/absolute/path/to/reviewed/ollama-distribution
export IPSE_OLLAMA_MODELS=/absolute/path/to/existing/ollama-models
mix run -r examples/knowledge/evaluation_model_service.exs -e '
root = System.fetch_env!("IPSE_BENCHMARK")
plan = JSON.decode!(File.read!(Path.join(root, "plan.json")))
{:ok, runtime} = Ipse.WorkspaceContext.canonical_path(System.fetch_env!("IPSE_OLLAMA_RUNTIME"))
{:ok, cache} = Ipse.WorkspaceContext.canonical_path(System.fetch_env!("IPSE_OLLAMA_MODELS"))
files = [Path.join(runtime, "bin/ollama") | Path.wildcard(Path.join(runtime, "lib/ollama/**/*"))]
files = for path <- Enum.sort(files), File.lstat!(path).type != :directory do
  {:ok, ^path} = Ipse.WorkspaceContext.canonical_path(path)
  %{type: :regular, size: size, mode: mode} = File.lstat!(path)
  digest = File.stream!(path, 1_048_576, []) |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1)) |> :crypto.hash_final() |> Base.encode16(case: :lower)
  %{"source" => path, "path" => Path.relative_to(path, runtime), "bytes" => size,
    "sha256" => digest, "executable" => Bitwise.band(mode, 0o111) != 0}
end
models = plan["models"]
service = %{
  "version" => 1, "origin" => "http://127.0.0.1:47631", "models" => models,
  "manifests" => Map.new(models, fn {name, _} ->
    [model, tag] = String.split(name, ":", parts: 2)
    {name, "manifests/registry.ollama.ai/library/" <> model <> "/" <> tag}
  end),
  "cache_source" => cache,
  "runtime" => %{"executable" => "bin/ollama", "files" => files},
  "limits" => %{"ready_ms" => 60000, "lifetime_ms" => 1800000, "metadata_ms" => 10000},
  "cpu_policy" => "visibility_v1"
}
:ok = IpseKnowledgeExample.EvaluationModelService.validate(service)
resolution = %{
  "artifacts" => plan["artifacts"], "model_origin" => service["origin"],
  "search_port" => 47632, "reports" => Path.join(root, "reports"),
  "data_manifest" => Path.expand(System.fetch_env!("IPSE_DATA_MANIFEST")),
  "model_service" => service
}
File.write!(Path.join(root, "resolution.json"), JSON.encode!(resolution), [:exclusive])
File.chmod!(Path.join(root, "resolution.json"), 0o600)
'
mix run scripts/evaluate-knowledge.exs -- --phase freeze-measured \
  --experiment "$IPSE_BENCHMARK/experiment.json" \
  --experiment-sha256 "$IPSE_EXPERIMENT_SHA256" \
  --resolution "$IPSE_BENCHMARK/resolution.json" \
  --output "$IPSE_BENCHMARK/frozen-measured" \
  > "$IPSE_RETAINED/freeze.json"
IPSE_FREEZE_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["sha256"])' "$IPSE_RETAINED/freeze.json")
```

Use the actual reviewed distribution layout when building a selection. Missing
libraries, symlinks or a changed manifest must refuse; do not omit required files
to make the selection pass. The held-out specification pins its permitted model
names/digests and dataset manifest. Selecting other models needs a different
reviewed experiment, not an edited execution seal.

`reports` must be fresh and disjoint from the freeze. It cannot contain the source
checkout. An ignored report directory inside the checkout is allowed. The freezer
canonicalizes local paths, copies the exact declared artifacts and creates a
private fixed `attempts` registry. Its manifest binds the registry device/inode,
source, plan, full service selection, runtime launch and semantic recipe. The
recipe derives finite preparation/finalization/cell/root deadlines and rejects a
whole lifetime over one day. Sealing starts no worker, provider or model and
opens no dataset or weight files.
The semantic recipe precedes the final manifest hash. Concrete bootstrap bytes
and tickets derive afterward, so the seal does not contain its own future hash.

### Follow authority into preparation

Read `context!/2`, `run/1`, `enter/1` and `admit_stage!/2` in
`EvaluationMeasuredExecution`. The entry rechecks the seal and the actual evaluator
source files. It creates exclusive `launch` and fixed `native-root` evidence,
separate from reports and the removable registry. Deleting reports or replacing
the registry does not authorize another first execution. Preserve an interrupted
claim even when no terminal receipt exists; work may already have happened.

The native bound descriptor retains these distinct handles:

| FD | Authority |
| --- | --- |
| 4 | Fixed native-root filesystem directory |
| 5 | Sealed attempts directory |
| 6 | Whole measured cgroup |
| 7 | Exact current workload cgroup |
| 8 | Native sequence evidence directory |

Native code validates owner/mode, current named identities and actual kernel
membership before workload launch. A stage checks its expected token/index,
ticket, exact native claim bytes and started scope identity before it reads
Prepared or opens dataset/model files. Ordinary child launches do not inherit
these authority handles. See [native scopes](../../native/README.md#optional-exact-aggregate-memory-scopes)
and [sequence framing](../../native/README.md#sequence-complete-measured-stages)
for descriptor and terminal layouts.

Preparation admits every catalog/options set before opening the dataset. It then
verifies members and projects label-free queries. Its prepared directory uses
`/proc/<preparation-VM-pid>/fd/4`, so a lock helper can resolve the owning VM's
retained directory. `/proc/self/fd/4` would refer to that helper's descriptors.
Prepared bytes include the original plan, copied artifacts, projected inputs,
effective time, exact runtime launch and schedule. Preparation persists their
hash before producing cell tickets/descriptors; future descriptor hashes do not
create a circular identity.

`EvaluationRunner.schedule/2` derives fourteen cells in sorted-project and
original-variant order. Version two divides every request, token and monetary
cap by the original two-project count, rounding down. Reservations and the rate
card remain unchanged. A share below its reservation refuses admission. Unused
amounts cannot transfer or renew. Each Research share is its project's query
count times `1 + max_sources`; its controlled gateway owns that separate finite
share. Version one divides request/token caps only and uses one gateway allowance
across projects.

### Follow one complete cell and its first predictions

The stage VM calls `EvaluationModelService.run/3` inside its fresh measured scope.
The owner copies the selected runtime and manifest/blob closure into new private
files. The caller drains the native Port while a guarded Task works. Only native
listener `P` admission permits initial HTTP inventory and the callback; child
stdout cannot supply that proof. See [owned listener observation](../../native/README.md#observe-an-owned-loopback-listener).

The callback calls `EvaluationRunner.evaluate_cell/5` with the original plan and
one schedule cell. Source authoring, ingestion, projection, all project queries,
source suppression, collection, Session close, gateway close and budget
reconciliation happen inside that cell. Authoring and inventory children use
`EvaluationMeasuredExecution.command/4`. The selected ERTS executable and clean
boot restore the exact ordered code-path set before loading scripts or starting
Ipse. They do not find Elixir or Mix on PATH.

The owner preserves callback outcome, final service admission and native cleanup
as separate facts. Task termination cannot prove domain closure or settled
provider liability. A failed cell retains its first predictions and errors.
Native sequencing proceeds only after confirmed cleanup. Finalization merges
first-cell predictions, inserts explicit unavailable rows for missing work and
seals the full grid without rerunning a question. A complete fifty-query matrix
contains 350 rows, including failed rows.

### Measure, audit and retain the authority for labels

Run only the already reviewed workload represented by this seal:

```sh
mix run scripts/evaluate-knowledge.exs -- --phase measure \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" \
  > "$IPSE_RETAINED/measure.json"
mix run scripts/evaluate-knowledge.exs -- --phase audit \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" \
  > "$IPSE_RETAINED/audit.json"
IPSE_AUDIT_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["sha256"])' "$IPSE_RETAINED/audit.json")
IPSE_PREDICTION_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["prediction_sha256"])' "$IPSE_RETAINED/audit.json")
```

Continue to review only after a successful audit. Audit joins the root M frame,
collector exits, stage M/T frames, receipt bytes and recorded file identities,
claim/scope identities, model-service cleanup, domain files, first predictions
and recomputed resource summaries. It verifies each closed cell's files, then
`EvaluationRunner.audit_merged_files/2` compares all six merged streams with
those cells in sealed schedule order. The comparison covers predictions,
execution, usage, request resources, storage resources and timings. Each stream
has a cumulative 64-MiB limit. Resource computation uses those exact checked
bytes, and `report.merged_files` binds their hashes into the audit identity.
Changing aggregate clocks or deleting requests cannot pass by recomputing a
matching summary.

The finalizer cannot observe the future outer
root receipt; read-only post-exit audit supplies that check. Keep the audit hash
outside both freeze and reports. Repeating `audit` performs inspection; repeating
`measure` must refuse.

If a stage, collector, authority handle or owner is lost, inspect its retained
claim, logs and acknowledgments. Missing completion stays unknown. A later clean
process list cannot supply a missing receipt or prove that no request dispatched.
Do not delete claims, clear `unsettled`, repair evidence in place or open a new
budget root to continue that same execution.

### Interpret the three charged-memory subjects

The CLI prints an audit summary. To inspect all joined receipts, retain the full
read-only API result under the same declared development runtime:

```sh
mix run -r examples/knowledge/evaluation_runner.exs -e '
[path, expected] = System.argv()
{:ok, audit} = IpseKnowledgeExample.EvaluationMeasuredExecution.audit(path, expected)
IO.puts(JSON.encode!(audit))
' -- "$IPSE_BENCHMARK/frozen-measured/manifest.json" "$IPSE_FREEZE_SHA256" \
  > "$IPSE_RETAINED/audit-full.json"
```

The metric is kernel workload-charged RAM, including cache and kernel charges:

| Subject | Audited field | Population and interval |
| --- | --- | --- |
| Whole lifetime | `report.whole_lifetime.peak_bytes` | Root workload, preparation, all cells and finalization through root cleanup |
| Fresh stage lifetime | `report.stages[].fresh_lifetime_peak_bytes` | That preparation, cell or finalization workload and descendants born in its fresh scope |
| Whole population during one stage | `report.stages[].whole_population_interval_peak_bytes` | The complete root population during that stage's reset/read interval |

These are distinct high-water observations. Do not sum them, subtract a starting
baseline or describe them as process RSS. The whole lifetime includes retained
charges between stages. Device memory and an exact macOS aggregate are outside
this backend. Sampled BEAM memory remains a separate diagnostic.

The measured lifetime includes natural population drain after a zero-exiting
leader. Native success requires observed empty population within the fixed
two-second allowance and the original deadline, with ownership still valid.
The audit requires version-two receipts, the exact declared completion policy,
consistent drain timings and elapsed time below each original root/stage timeout.
A service's process-group cleanup cannot substitute for that population receipt.
If forced cleanup was required, retain the failure even when the scope later
empties. Inspect it under the failed seal; do not replay that execution.

CPU visibility environment values and zero-VRAM residency checks express the
selected policy. The synthetic daemon verifies those values. They do not prove
real Ollama CPU execution or every transient device allocation. An audited
resource result also does not establish held-out quality or independent semantic
review.

For a change exercise, use the disposable synthetic measured population above.
Inspect `verify_tamper_controls!/1` in
`test/support/measured_knowledge_verification.exs`. It changes each merged stream
and separately tests two coherent rewrites: zeroed clocks with a recomputed
summary, and removed requests with a recomputed summary. Both summaries can still
report completeness. The audit must return `merged_stream_changed`, leave the
changed files untouched and accept again after the fixture restores its original
bytes. Never run these mutation controls on an actual comparison's evidence.

### Exercise the version-one identity contract

Build Ipse and one independent lexical Corpus artifact first. Use fresh output
paths and a clean source checkout, including untracked files:

```sh
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output /tmp/ipse-evaluation-corpus --package corpus --preset state-lexical
mix run -r examples/knowledge/evaluation_freeze.exs -e '
alias IpseKnowledgeExample.EvaluationFreeze, as: Freeze
plan = JSON.encode!(%{"version" => 1, "purpose" => "identity exercise"})
{:ok, seal} = Freeze.create(File.cwd!(), plan,
  %{"corpus" => "/tmp/ipse-evaluation-corpus"}, "/tmp/ipse-evaluation-seal")
IO.puts(JSON.encode!(seal))
{:ok, verified} = Freeze.verify(seal["path"], seal["sha256"])
IO.puts(JSON.encode!(%{"artifacts" => Map.keys(verified["artifact_paths"])}))
'
```

Expect the manifest path, its SHA256 and the source commit, followed by the
`corpus` artifact name. The exercise starts no worker or model and reads no
dataset. `create/4` copies declared artifacts through `Ipse.Extensions.Store`.
An edit to the original build cannot change that copy. The manifest binds all
tracked source files, the Git commit/tree, code-path BEAM files, native helpers,
toolchain identity and exact plan bytes.
Run creation and verification in the declared development runtime with Git
available. A source-runtime seal does not attest a different installed runtime;
installed protocol verification retains its separate archive/host identities.

Retain the printed manifest hash separately. `verify/2` requires that expected
hash, then rechecks the clean source identity, runtime, plan and copied artifacts.
Keep source and runtime files fixed through execution. Existing output directories
refuse; failed creation preserves its partial directory for inspection. Imports
remain inert. The execution caller must validate the benchmark plan and each
egress/State/MCP decision before starting work; an identity seal grants no effects.
The small exercise plan above is not a complete comparison declaration.

Run the synthetic tampering controls before changing the seal format:

```sh
mix test test/knowledge_evaluation_freeze_test.exs
```

They distinguish changed plan bytes, a changed manifest, copied-artifact tampering,
dirty source, a different clean commit and a new code-path file. The valid control
also verifies that a dataset path in a plan is never opened during sealing.

## Check every selection before opening the dataset

The version-one runner's `freeze` phase adds executable preflight after the
identity seal.
Follow `preflight!/3`, `selection/4` and `EvaluationSession.preflight/1`. Tuning,
fixture execution and frozen prediction also perform this check before opening
any dataset member, including its manifest. The direct `EvaluationFreeze.create/4`
exercise above remains an inert identity operation.
Frozen phases recheck the source, runtime, plan and copied-artifact seal after
preflight. Successful worker checks cannot authorize execution against identities
that changed during initialization.

Preflight imports the declared artifacts, resolves their exact operator options,
checks their schemas and derives every command catalog. Required verbs depend on
the preparation strategy. Embedding needs `index`, graph preparation needs
`extract`, and answer generation needs `answer`, alongside each strategy's
retrieval and source commands. An existing command with the wrong ID or owner
cannot satisfy a binding merely because its argument shape looks usable.

The check then starts an owned worker for each selection and initializes it.
Knowledge entrypoints can initialize into an invalid-configuration state, so
readiness alone cannot establish valid profiles. Preflight sends an empty
`invoke.command` diagnostic directly to that worker. A valid configuration must
return `invalid_invocation`; a deferred profile error fails the check. This is
a protocol diagnostic, not an admitted user command. No returned host action
is executed, and no inference request is dispatched. The answer helper has no
knowledge profile registry and uses its ordinary schema and initialization
checks instead.

Every worker requires a confirmed native cleanup receipt. The report records
artifact, option and export hashes, the catalogs and each initialization outcome.
Version one checks model inventory after the selections pass. Version two defers
HTTP inventory to each owned model service, after native listener admission.
`preflight.json` retains success or the first failed variant. Failed preflight
opens no corpus or queries and starts no search gateway. Its partial directory
and any existing identity seal remain available for diagnosis. A seal file's
existence does not establish successful executable preflight.

Run the complete synthetic exercise:

```sh
mix test test/knowledge_evaluation_runner_test.exs
```

Inspect the two negative declarations in the preflight test. One changes the last
Research command binding, after earlier variants have passed. The other adds an
unused invalid retrieval profile. Both must fail while their corpus and query
paths still name nonexistent files. Confirm that the latter worker reports
initialized readiness, failed option validation and confirmed cleanup.

The CLI exercises run the actual script with compiled dependency paths. They
verify successful and failed prediction rows, copied-artifact freezing, frozen
fixture execution, mode refusal and hash rejection before label access. Failed
rows or incomplete execution produce both exit status 1 and `status: "failed"`.
Read `failed_rows` and `execution_complete` separately. A completed execution
with refused retrieval still retains its failed prediction rows.

## Project query inputs without labels

After the execution's authority and catalog admission pass, the input adapter
opens the declared dataset members. Version two does this during measured
preparation; version one does it after its executable preflight. `EvaluationInput.queries/2` accepts the version-one
query JSON bytes and the declared split. Its `queries` result contains exactly
`query_id`, `project` and `query`, preserving their input order. Relevance,
expected classes, expected answers and refusal labels remain excluded. The
separate `excluded_fields` list reports field names; keep it in run metadata,
outside Session/model inputs.

`EvaluationInput.corpus/1` checks each complete source's identity, generation,
version, byte length, SHA256, UTF8 text and timestamps. It retains all source
generations and state metadata. It neither suppresses sources automatically nor
turns metadata into model instructions. The execution plan must declare how
source lifecycle metadata becomes public ingestion/update/forget commands.

Each member is at most 1 MiB. The adapter reuses the host's duplicate-key-rejecting
JSON decoder. It refuses an oversized member, duplicate query ID, duplicate source
generation, malformed row or mismatched split as a complete input error. A project,
source ID and generation identify one source version. Another document ID or
version label cannot make a duplicate generation valid. A different project is
a separate identity. The adapter never
drops rows to make a comparison fit. Resolve any required capacity gap before
freezing the implementation intended to cover the workload.

Only the scoring phase calls `EvaluationInput.labels/2`. It normalizes full source
identities and exact byte-coordinate annotations for the existing scorer. Keep
that call inside the label loader that runs after saved prediction hashes pass.
The original expected-answer text remains available to the independent semantic
reviewer through the separately retained dataset; it is not a predictor input.

```sh
mix test test/knowledge_evaluation_input_test.exs
```

Change expected-answer, class and relevance values in its first fixture. Query
projection must remain unchanged even when those labels become invalid. Then run
the label adapter and observe its separate refusal. This tests information
separation without opening the held-out workload.

## Materialize before interpreting a result

Follow `record_invoked/9` and `complete_result/2` in the Session driver before
changing answer preparation or metrics. An inline invocation result already
contains its complete domain `value`. A larger SDK-2 result carries a
`saved.result` delivery descriptor. Its output ID, length and digest describe
retained bytes, not an evidence array or a successful retrieval status.

The driver calls `Ipse.Session.materialize_result/2` with that exact delivery.
Only a successful complete read supplies the receipt's `value` for prediction,
answer preparation and measurement. The receipt retains these fields:

| Field | Meaning |
| --- | --- |
| `delivery` | The original saved-result descriptor, or null for inline output |
| `complete_result.byte_count`, `complete_result.sha256` | Length and hash of the exact retained document |
| `complete_result.bytes_base64` | Those complete source bytes, without re-encoding the domain value |
| `complete_result.provenance` | `historical_receipt`, not a claim of current source eligibility |
| `value` | The complete decoded domain object, or null when unavailable |
| `materialization_error` | A failed-read diagnostic, or null after success |
| `failure_codes` | Distinct classified Session error notifications observed before completion, in arrival order; no error text |

The existing `result_sha256` binds the invocation's displayed result text. For
saved output that text describes delivery; use `complete_result.sha256` to bind
the document. Preserve both identities. The Base64 field retains the original
bytes for verification.

When materialization fails, the receipt keeps its original delivery, sets
`value: null` and reports failed status. `completion_confirmed` still records
whether the original invocation committed its matching final receipt. A completed
invocation can have an unavailable document; do not rewrite that fact as lost
completion. The driver makes no retry, replacement query or model request.
Later prediction handling must retain this first failed row rather than compute
metrics from an empty or partially decoded ranking.

Run the Session-driver suite and follow its large-result controls:

```sh
mix test test/knowledge_evaluation_session_test.exs
```

The successful control requires more than 16 KiB of complete bytes and verifies
their hash, decoded value and provenance. The forged-delivery control changes
the digest and refuses even when a supplied inline value looks usable. The
lost-source control holds completion delivery, removes the readable source in
the fixture, then releases completion. It must retain one completed first receipt
as failed, submit no second command and make zero model requests. That fixture
changes internal test state; it does not alter a saved journal or establish an
OS enforcement boundary.

For the real independently built packages, follow the [complete-result exercise](knowledge-extensions.md#publish-and-read-the-complete-domain-value).
It checks ten full Corpus and Research quotes, Graph bases outside `top_k`,
and exact inert historical recovery. Historical reads supply the original
retrieval snapshot; they do not rerun its current-source eligibility policy.

## Exercise failed paging and lost completion

Run the public-Session failure cases before changing the driver:

```sh
mix test test/knowledge_evaluation_session_test.exs
```

The suite compiles a synthetic SDK worker in a separate process. Its source
command returns malformed paging responses or holds an invocation. Temporary
files expose the exact dispatched action and worker-start barrier. It starts no
model service and grants no host actions. These fixture file operations do not
establish an OS sandbox boundary.

Follow the two paging cases into `ingest_paged/4` and `append_parts/6`:

1. An open response starts at offset one. The driver requires zero, retains the
   completed open receipt and submits no append or publish.
2. A valid open is followed by an append with the wrong next offset. The driver
   retains both receipts and submits no publish. A later explicit inspection is
   still allowed because both commands have confirmed completion.

Then compare the held-invocation cases. A timeout with confirmed cancellation
retains its receipt and permits a later read in the same Session. Killing the
Session after the worker-start barrier produces no completion acknowledgment.
The driver reads the original journal using its pinned Session ID, retains the
intent without a result, and marks the run `unsettled`. Another invocation must
return `:completion_unconfirmed` without changing the journal or dispatch log.
`close/1` must report cleanup as unconfirmed.

The worker-exit observation prevents fixture leaks. Process absence does not
replace the missing Session cleanup acknowledgment. Keep those assertions
separate when adding owner-loss or cancellation controls. Never clear `unsettled`
to continue an interrupted evaluation or open a replacement budget root silently.

For an unexpected paging result, enable the bounded synthetic probe:

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/knowledge_evaluation_session_test.exs test/stdio_probe_test.exs
```

The probe follows both the Session and task supervisors. Invocation workers run
under the task supervisor; tracing only the Session tree misses their startup and
callback calls. It records function arities, elapsed times and classified returns,
with at most 64 samples over 20 seconds. It retains no arguments or returned
payloads. The separate failure diagnostic reports only recognized action names
and closed receipt fields. Its privacy exercise supplies private arguments,
results, reasons and an unexpected status, then verifies that none is printed.

Compare the actions reached with worker initialization, callback and close
observations. A timeout receipt establishes that the selected deadline expired;
it does not identify which component delayed completion. Keep unexpected timeout
evidence separate from the intended malformed-response case. Passing repetitions
or a later green run cannot establish the original failure's cause.

For a failed invocation, inspect `failure_codes` separately from `outcome`.
The driver recognizes the Session's complete-result deadline notification as
`complete_result_deadline`; other error notifications become `session_error`.
The list contains at most those two distinct codes. Raw error strings are not
copied into the receipt, and a code does not turn unknown work into a confirmed
failure or authorize a retry. Older receipts without this field cannot establish
which notification occurred.

The deadline control delivers the real timer message to a held invocation and
checks the resulting Session notification and receipt. It tests diagnostic
handling without waiting 120 seconds; it does not measure a naturally elapsed
deadline. A separate failing callback checks that its private error detail stays
out of the diagnostic receipt.

## Follow a matched public-Session comparison

Run the orchestration fixture:

```sh
mix test test/knowledge_evaluation_runner_test.exs
```

Open its `matrix_plan/2` helper and follow `EvaluationPlan.build/1`. They select independently built Corpus, Graph,
Research and text-helper artifacts, with explicit command bindings and named
profiles. Its seven variants cover lexical retrieval, explicit and model
extraction, dense retrieval, hybrid retrieval, reranking and Research. The
synthetic HTTP fixture returns declared two-coordinate vectors and scripted
text. Those outputs exercise the provider wire formats and canonical accounting;
they measure no model quality.

Follow `run_variant/9`, `prepare/4`, `invoke/4` and `approve/1` in the runner:

1. Each project and variant gets a fresh Session and a fixed share of its declared
   inference budget. Budgets are not transferred or renewed after failure.
2. Source authoring runs outside the host VM. Ingestion and explicit forget
   commands finish before projections start. Only current eligible generations
   reach index or extraction commands. Skipped projections remain recorded.
3. Each invocation logs every new public receipt, including source paging steps.
   A refusal before dispatch cannot acquire an older command's receipt.
4. Approval checks bind the selected artifact, command owner, profile and complete
   egress. Per-invocation counts restrict embedding, text, search and fetch calls.
   Research fetches only URIs returned by that query's controlled search result.
5. All variants receive the plan's fixed `as_of_ms`. Research's optional argument
   selects that same time; omitting it preserves current-time behavior after capture.
6. After saving that variant's predictions, explicit source inspection and forget
   commands suppress its source copies. Collection requires exact namespace,
   key and revision approvals derived from a verified suppressed store.
7. Prediction failures retain their declared rows. Cleanup attempts cover the
   Session, gateway and sampler, with errors preserved in the output directory.

The version-one controlled gateway uses one finite allowance across all projects.
Version two assigns disjoint shares to the separately owned Research cells. The runner
derives it from `expected_queries * (1 + max_sources)`: one search and at most
the declared number of fetches per question. Fifty ten-source questions allow
550 calls. Changing documents or beginning another question does not renew the
allowance. Direct gateway callers retain a 512-call default and can select an
explicit integer allowance from one through 11264. Invalid limits refuse before
starting a listener. Research limits are validated before any dataset access.

Inspect `gateway-calls.json` with `gateway-summary.json`. The first contains
bounded per-call metadata. The summary reports `call_limit`, `recorded_calls`,
`rejected_over_limit` and total decoded `request_count`. Requests beyond the
allowance refuse and increment the aggregate counter without growing the log.
Malformed frames rejected before JSON dispatch do not enter these counters.
Unknown tool values are recorded as `other`, never copied into the report.

Run `mix test test/knowledge_evaluation_services_test.exs` for the complete
550-call loopback control and post-exhaustion refusal. The runner's four-source
Research case verifies the declared fetch count through actual approvals.
Search approval binds the complete version, contract, query and source limit.
Fetch approval permits each selected URI once, up to that same declared limit.
The case supplies two generations with identical text and reused version labels,
including integer `1` and string `"1"`. The raw fetch citation identifies its
captured generation one; its URI and body hash map the saved prediction to the
dataset's current generation and typed version. Retain that distinction rather than treating a matching body hash alone
as a unique source identity. The control makes no model request.

Source authoring generates `dataset:PROJECT:DIGEST` URIs. The digest hashes this
ordered JSON array with raw SHA256:

```elixir
["dataset-source", 1, project, document_id, source_id, generation, version, body_sha256]
```

Generation and the version's JSON type remain part of the identity even when
body bytes or display labels match. Keep this policy in the implementation
freeze; changing it changes citation provenance and answer inputs.

Compare the current-source and suppressed-source fixtures. Intentional exclusions
remain visible while complete retrieval of eligible sources can succeed. The
package owns that classification; the runner preserves its returned status.
An unpublished source, missing-vector fallback or bounded incomplete traversal
must remain partial. The [query completeness exercise](knowledge-extensions.md#trace-a-source-and-a-query)
tests those distinctions through public workers. The scorer still gives partial
results zero successful retrieval utility; it does not upgrade a useful-looking passage.
The model fixture also proves that forgotten and expired text never enters its
requests. The sampler's start, end and sampled maximum describe only the harness
BEAM.
The v2 native audit supplies the separate charged-memory subjects described above;
neither result measures worker/model RSS or whole-system memory.

For a change exercise, trace the Research approval through `MCPCall`. Its effect
has no State namespace. State writes use the selected logical project namespace,
while embedding and text calls use the Session identity. Changing all three to
the same namespace must refuse the mismatched effect. Keep the host's existing
contracts as the authority when changing an evaluation adapter.

## Trace an answer's evidence

`IpseKnowledgeExample.EvaluationAnswer.prepare/3` takes the query, an as-of time
and at most ten saved candidates in their existing rank order. Each candidate
has its complete `citation`. The result contains an exact `model.complete`
request for `p27_answer`, a shown context, coverage and the context's SHA256.
It executes nothing.

The helper assigns short IDs such as `e1` to evidence and preserves each admitted
citation's entire quote, offsets and hash, up to the existing 1024-byte citation
limit. It takes the longest rank prefix whose exactly encoded input fits 4096
bytes. Coverage lists every omitted candidate and its original rank; it reports
no additional quote cropping. An oversized earlier candidate can exclude later
ones even when a later short quote might fit. This simple policy does not claim
optimal packing or that every contradiction reached the model. Preserve the full
retrieval result separately so answer-context limits cannot erase the retrieval
measurement. A nonempty retrieval with no admitted candidate remains distinct
from empty retrieval in coverage.

Saved prediction rows use version two. `evidence` keeps the complete returned
ranking; `context_evidence` holds only the spans actually cited by the answer,
not every passage shown to the model. Each context span must be contained in an
original ranked span with identical source
identity and bytes. Source and annotated-span retrieval metrics use `evidence`.
Claim/span citation judgments can refer to the corresponding context spans.
Do not replace a ranked passage with its answer excerpt to improve span scores.
For context-omission analysis, inspect the saved preparation bundle or reconstruct
its declared packing policy; comparing `evidence` with `context_evidence` measures
citation use as well as visibility. Complete admitted quotes may already be
partial source excerpts; this helper cannot recover upstream retrieval omissions.

Both CLI readers and the scorer accept at most 64 MiB in one prediction file
and 64 MiB across all declared files. Each JSONL row remains limited to 256 KiB.
Count serialized bytes, including JSON escapes and repeated source identities;
query count and raw quote lengths alone do not establish file capacity. Review
packets have separate limits of 32 MiB per file and 64 MiB in total. The scoring
CLI accepts a review JSON file up to 32 MiB through the host's duplicate-rejecting
decoder; manifests and dataset members retain their separate 1-MiB limits.
A size refusal keeps the first predictions for inspection. Never drop rows or
rerun model work to make a retained comparison fit a later consumer.

After the public Session call completes, pass the saved response text and the
same bundle to `decode_answer/2`. The decoder requires one complete JSON object
with `classification`, `answer` and `claims`. Each claim references unique shown
IDs. Unknown IDs, extra fields, duplicate fields and Markdown fences refuse.
An abstention has no claims. An answer or conflict has at least one cited claim;
one source can contain conflicting statements.

The mapped result proves which shown span a claim cited. It does not establish
that the span supports the claim. Keep that semantic judgment in independent
review, alongside literal captured-source verification.

## Prepare independent review from finalized predictions

Use a completed v1 prediction or an audited v2 measured execution. Retain the
first-prediction hash before preparing a review. Version two additionally requires
the separately retained audit hash and the exact sealed data/prediction paths.
The `review` phase verifies the execution freeze, first-prediction identity and
complete variant/query grid before opening reference labels. It reuses
`EvaluationScore.verified_predictions/2`; a separate permissive JSON parser
cannot substitute for the scorer's row checks. Prediction IDs must be opaque
`p-` plus SHA256 values before any label loader runs.

Keep three identities separate. The execution-freeze hash selects the experiment
and its reference data. `review_binding_sha256` binds that context, the metric
version and every verified prediction-file ID and hash. The separately retained
`packet_sha256` identifies the complete packet and its reviewer instructions.
The review binding is opaque to a reviewer. It does not reveal strategy names.

For the v2 seal above, prepare a private packet and then score a separate review:

```sh
mix run scripts/evaluate-knowledge.exs -- --phase review \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" --audit-sha256 "$IPSE_AUDIT_SHA256" \
  --data-manifest "$IPSE_DATA_MANIFEST" \
  --predictions "$IPSE_BENCHMARK/reports/predictions.jsonl" \
  --prediction-sha256 "$IPSE_PREDICTION_SHA256" \
  --output "$IPSE_BENCHMARK/review-packet"
cp "$IPSE_BENCHMARK/review-packet/reviews-template.json" "$IPSE_BENCHMARK/reviews.json"
```

The copied template remains unmeasured. Give the packet to an independent reviewer
and keep their actual verdicts in `reviews.json`. Preserve its version-two envelope
and `review_binding_sha256` exactly. Fill the existing verdict rows without
changing IDs. After that review, run:

```sh
IPSE_LABELS=$(elixir -e '[manifest, plan] = System.argv(); p = JSON.decode!(File.read!(plan)); IO.puts(Path.join(Path.dirname(manifest), p["data"]["queries"]))' "$IPSE_DATA_MANIFEST" "$IPSE_BENCHMARK/frozen-measured/plan.json")
mix run scripts/evaluate-knowledge.exs -- --phase score \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" --audit-sha256 "$IPSE_AUDIT_SHA256" \
  --data-manifest "$IPSE_DATA_MANIFEST" \
  --predictions "$IPSE_BENCHMARK/reports/predictions.jsonl" \
  --prediction-sha256 "$IPSE_PREDICTION_SHA256" \
  --labels "$IPSE_LABELS" \
  --reviews "$IPSE_BENCHMARK/reviews.json" \
  --output "$IPSE_BENCHMARK/scores"
```

`IPSE_LABELS` names the query member from the sealed plan. Scoring verifies those
label bytes against the declared member hash. An untouched template produces
unmeasured support, writes `scores.json` and
exits one; it cannot manufacture a quality pass.

For v1, use its separately retained freeze/prediction hashes and selected dataset
paths, and omit `--audit-sha256`. V1 refuses an audit argument. V2 refuses missing
or changed audit authority before labels/reviews, and refuses alternate canonical
prediction/data paths even when the caller supplies a plausible hash. The legacy
`predict` and `verify-frozen` phases refuse v2 seals with `measured_entry_required`;
use `measure` and `audit` for that format.

For review, expect `status: "ok"`, the complete row count, `packet_sha256` and
`reference_integrity_complete: true`. Retain that packet hash separately. An
existing output path refuses. Files are owner-only in a private directory.
Invalid reference spans remain visible, set completeness false and produce a
failing CLI exit. A written packet does not establish semantic support.

Give the independent reviewer only the packet directory:

| File | Review task |
| --- | --- |
| `instructions.md` | Follow the versioned verdict definitions and record reviewer identity and limitations |
| `cases.jsonl` | Read the saved outputs and claim/span pairs, with strategy labels removed and order blinded |
| `queries.json` | Compare questions, reference answers, relevance and the fixed as-of time |
| `source-texts.json` | Check the original source bodies and their complete typed/versioned identities |
| `reference-integrity.json` | Inspect literal annotation failures before accepting reference-based scores |
| `reviews-template.json` | Copy to a separate review file and fill actual semantic verdicts |
| `manifest.json` | Verify every packet file hash and its execution/data/prediction identities |

Keep the run and freeze directories private: they contain strategy selections
and execution history. All prediction-bearing packet lists use the same seeded
order, including the template. Output style can still hint at a method; removing
labels cannot guarantee that a reviewer cannot infer one.

The `source-bytes-v1` integrity rows compare the original corpus against complete
project/source/generation/typed-version/hash identities and exact UTF8 byte spans.
They help the reviewer inspect citations. At scoring time, the runner reloads
the corpus member from the verified dataset, checks its member hash, and the
scorer validates every complete document hash before recomputing all integrity
rows. Values copied or edited in `reviews.json` cannot override those checks.
Reference spans are checked against the same corpus; an invalid reference
refuses scoring with `invalid_reference_integrity`.
The semantic template remains `unmeasured` with `independent: false`, even when
every byte check succeeds. The independent reviewer judges entailment and each
claim/span pair, using their actual identity. The generating model cannot judge
itself independently. Review flags cannot prove a reviewer's independence.
Keep notes and disagreements bound to the retained packet hash. Preserve packet
files; write completed verdicts to a separate `reviews.json`.

Scoring rejects a missing, malformed or legacy version-one review envelope with
`invalid_reviews`. A well-formed binding for another subject produces
`review_binding_mismatch`. Both refusals happen before the label loader runs or
the score directory is created. Do not copy a new binding onto old judgments.
If prediction bytes or the experiment change, prepare a new packet and obtain
new judgments, retaining the old packet and review as historical evidence.
Reusing the same prediction IDs does not authorize reusing its verdicts.

Run the synthetic boundary and CLI exercises before changing this workflow:

```sh
mix test test/knowledge_evaluation_review_test.exs test/knowledge_evaluation_score_test.exs test/knowledge_evaluation_runner_test.exs
```

Trace the false-claim fixture: its quotations match actual corpus bytes, but no
semantic verdict is manufactured. Then compare identical bodies with reused
integer/string version labels, a foreign project and a wrong reference offset.
The hash/grid refusal cases must not invoke the label callback. The stale-review
fixture changes an answer and its raw file hash while retaining prediction IDs.
The old review must refuse before labels. The real CLI exercise checks missing,
legacy and wrong bindings with an absent label path, private files, unchanged
output after overwrite refusal and a nonzero exit for an unmeasured review.

## Verify the hash-before-label rule

Run the synthetic suites:

```sh
mix test test/knowledge_evaluation_answer_test.exs
mix test test/knowledge_evaluation_score_test.exs test/knowledge_metrics_test.exs
```

Open `test/knowledge_evaluation_score_test.exs`. Follow its `inputs/3` fixture
into `EvaluationScore.score/5`. The frozen declaration names variants, queries,
a baseline, an explicit classification mapping and prediction-file hashes.
Its version-two `context_sha256` names verified experiment and reference policy.
Runner supplies the verified execution-freeze hash. A direct pure caller owns
the trustworthiness of that context value.

The raw JSONL blobs are supplied separately. The scorer first validates every
expected raw hash and row. It then derives the review binding from the context,
metric version and sorted file identities. Next it loads the review and checks
its closed version-two envelope and binding. Only a matching review can reach
the corpus callback. That callback returns original corpus JSON bytes, separately
from the review. The scorer validates source hashes and recomputes literal
integrity before calling the label loader, then validates reference spans.
Execution-seal versions, prediction-row versions, scoring
declarations and review envelopes have separate version fields.

Work through the first test as a change exercise:

1. Replace the saved prediction bytes while retaining the original hash. Expect
   `:prediction_hash_mismatch` and no loader message.
2. Restore the bytes, insert a duplicate JSON key and update the file hash.
   Expect `:duplicate_prediction_key` before any loader runs.
3. Submit two rows for the same variant/query or an `attempt` other than one.
   Expect refusal rather than a best-of-several prediction.
4. Bind a valid review, change the answer and its raw file hash, and keep all IDs.
   Expect `:review_binding_mismatch` before the label callback runs.
5. Change only `context_sha256`. Expect the same binding refusal.
6. Bind a fabricated quote to its changed prediction bytes and mark its integrity
   valid in the review. Expect an invalid literal receipt and a failed citation
   gate. The valid-byte control must pass even if its review flag says invalid.
7. Corrupt a corpus body without changing its declared hash. Expect
   `:invalid_corpus` before the label callback. Change a reference offset instead;
   expect `:invalid_reference_integrity` after label validation.
8. Run the suites again. Check that the valid control reaches all three loaders
   and reports its measurements.

The scorer bounds raw bytes, rows, nesting, strings and collections before
loading labels. It uses OTP's JSON decoder callbacks to enforce duplicate-key
and structural limits. The answer helper uses Elixir's `JSON.decode/3`, whose
decoder options are a keyword list. The scorer uses Erlang's `:json.decode/3`,
whose callbacks are a map with an explicit `null: nil`. These APIs take different
option types. A successful parse check alone does not verify either adapter.

## Keep failed rows and different measurements

Every declared variant/query pair appears in the report. A missing prediction
becomes an explicit missing row. Failed and partial rankings retain their
observed scores, while their primary retrieval utility is zero. Queries with
no positive relevance annotations remain present with N/A retrieval scores.
Unknown measurements remain `nil`.

Read these report fields independently:

| Measurement | What it establishes |
| --- | --- |
| Source Recall@5 and nDCG@10 | Ranked full source identities against source relevance grades |
| Exact and contained span recall | Matching byte coordinates and UTF8 content against annotated spans, with corpus-derived literal integrity |
| Classification and confusion matrix | The frozen mapping of saved classes against expected classes, retaining execution failures |
| Semantic support and citation precision | Explicit independent verdicts on actual saved responses and claim/span pairs |

Several claims citing one span remain several claim/span pairs. A quote at the
wrong byte coordinates cannot gain contained-span credit from substring overlap.
Cross-project evidence is invalid even if a supplied integrity review calls it
valid. Missing or non-independent semantic review stays unmeasured. A retrieval-only row
has no supported-answer measurement.

When the plan selects answers, an execution failure keeps `response_kind: "answer"`
with its failed status, empty claims and null answer. It remains an answer-policy
attempt, so an independent unsupported verdict counts it as zero in the support
denominator. Intentional retrieval-only plans still produce `retrieval_only` rows
whose answer metrics remain unmeasured. Neither case invents a successful answer
or a semantic review.

The scorer's support and citation thresholds are 0.90 and 0.95. Its aggregate
`semantic`, `gates` and `quality_gates_passed` fields cover the complete frozen
variant/query grid, including missing rows. `quality_gate_scope` identifies that
scope; each variant retains its own independent measurements and gates. A
complete-workload pass does not promote a failing individual engine.
Incomplete review cannot pass. The `score` CLI preserves `scores.json` and exits
nonzero for failed or unmeasured aggregate gates. Semantic quality gates do not replace the separate native authority, cleanup,
resource, installed-execution or source-suppression checks.
Follow the [plan](../plan.md#p27-optional-research-graph-and-rag) for the complete
acceptance requirements. Passing these synthetic exercises establishes helper
behavior, not held-out quality or a selected retrieval engine.

## Reconcile model work with durable accounting

Follow `persist_close/2` in the runner. It confirms owner cleanup, loads the
journal through `Ipse.Journal.load/2`, and restores canonical usage through
`Ipse.Usage.restore/2`. The session driver separately checks recoverable context
through `Ipse.Session.restore_context/1`. Use `Usage.order/1` and
`Usage.request_record/1` to export every request in admission order.
`Usage.snapshot/1` shows only the latest sixteen requests for the UI.

The runner attaches the saved budget in inspection mode and reads it under its
existing lock. `EvaluationResources.reconcile_budget/4` checks the exact request
IDs and admissions against canonical usage, including refusals. It also checks
that retained liability covers every known canonical observation, including
earlier peaks followed by smaller counters. This comparison requires one root
session and rejects additional child admissions. It does not grant authority,
change reservations, or continue the session. The live
`Ipse.Budget.validate_sources/3` requires a live checkpoint and is not a saved-ledger
inspection API.

Read the resulting files together:

| File | How to use it |
| --- | --- |
| `usage.jsonl` | Inspect every canonical request and each session's validated budget snapshot |
| `request-resources.jsonl` | Match requests to project, variant, source or query, invocation, admission/refusal, dispatch intent and settlement |
| `timings.jsonl` | Inspect individual phase and invocation clocks, outcomes and unconfirmed completion |
| `resource-summary.json` | Compare per-variant phase percentiles, query coverage, request roles, token availability and retained budget dimensions |

A canonical attempt does not prove admission or provider dispatch. A refused
attempt remains in usage while booking no request. A recorded dispatch intent
does not prove that the remote provider accepted work. Preserve completed,
failed and unknown outcomes independently from budget settlement. Missing token
counts remain unknown; embedding output tokens are not applicable. Without a
rate card, work remains unpriced. Budget dimensions report conservative booked
liability, not an invoice.

Read-only inspection remains available after inference quota exhaustion. Do not
put a blanket request-count guard around driver operations. The host admission
policy owns inference quotas.

### Verify coverage and failure accounting

Run the local scripted-provider exercises:

```sh
mix test test/knowledge_evaluation_resources_test.exs test/knowledge_evaluation_runner_test.exs
```

Follow the thirty-one-request case in the runner test. Compare the thirty-one
scripted HTTP calls, restored journal records, exported requests and booked
requests. This crosses the ordinary thirty-step default and the sixteen-request
UI snapshot. Each exported request must retain its query ID. Then follow the
one-request-budget case: two queries produce two canonical attempts, one admitted
request, one refusal and one dispatch intent. Both query rows remain present.

In the resource test, follow the historical-peak case. A request observes sixty
input tokens and later seven. Removing the sixty-token observation from the
budget must fail reconciliation even though its final counters still match.
Removing a refusal or concealing usage behind a refused admission must also fail.

## Isolate model and native ownership

Use the smaller exercises below when a complete population fails. They let you
trace service admission, kernel collection and sequencing separately. A passing
component exercise cannot replace the complete measured audit.

### Exercise ownership of a model service

Use this smaller exercise to isolate the model owner used by a measured cell.
The cell owns the service and creates its cache inside the measured scope. A
shared daemon can retain allocations from another cell, and a hardlinked cache
can reuse charges established outside the scope.

On Linux, build the native helper and run the synthetic service cases:

```sh
./scripts/build.sh
mix test test/knowledge_evaluation_model_service_test.exs
```

The fixture is a Rust HTTP server compiled from
`test/support/model_service_probe.rs`. It checks the selected environment and
answers the small Ollama inventory protocol. It loads no model and performs no
inference. The tests cover private cache contents and inodes, occupied ports,
forged child output, bounded logs, inventory failures, callback exceptions,
service loss and owner death. On macOS, the same test file checks pure selection
validation and refusal before staging because listener ownership requires Linux.

To retain the Linux case receipts outside ExUnit cleanup, compile the fixture
and choose a fresh evidence directory:

```sh
IPSE_MODEL_PROOF=$(mktemp -d)
rustc --edition=2021 -D warnings test/support/model_service_probe.rs -o "$IPSE_MODEL_PROOF/probe"
mix run scripts/verify-model-service.exs -- "$IPSE_MODEL_PROOF/probe" "$IPSE_MODEL_PROOF/evidence"
```

Expect one JSON summary whose cases all report `status: "passed"`. Inspect each
case's `verification.json` and the completed cases' `receipt.json`. Failed
operations retain partial output. Preserve those files when diagnosing a failure;
choose another output directory for another synthetic exercise. Reusing an
operation's directory must refuse without replacing its receipt or running work.

To repeat the cases with a bundled runtime, build a package and pass its archive
to the installed verifier. This example requires exactly one archive in `dist`:

```sh
./scripts/package.sh
set -- dist/ipse-*.tar.gz
test "$#" -eq 1
elixir scripts/verify-model-service-package.exs "$1" "$IPSE_MODEL_PROOF/probe" "$IPSE_MODEL_PROOF/installed"
```

Expect the same synthetic case results with `installed: true`. The verifier
extracts the package and removes development executables from the outer release
PATH. Internal launch environments include system directories. On macOS,
its result instead confirms refusal before effects. The service module and
fixture are trusted evaluation code loaded from the checkout; Runner, HTTP and
native execution use the bundled package.

Trace `EvaluationModelService.run/3` through these ownership boundaries:

1. `validate/1` checks a closed selection without IO. The selection names exact
   runtime files, hashes, model manifests, a private loopback origin and finite
   deadlines. It supplies no download, fallback or attempt-renewal authority.
2. A guarded Task creates the fresh private output and copies the selected
   runtime and complete manifest/blob closure. The native
   [`--copy-regular` mode](../../native/README.md#copy-a-regular-file-through-a-retained-descriptor)
   refuses unsafe source descriptors. Elixir hashes the new private files.
   The owner always creates `runtime/lib/ollama`, keeping library discovery in
   the selected distribution's private layout.
3. The caller owns the native Port and drains its frames while the Task works.
   One native listener observation must identify the selected direct child
   before any inventory request. Child stdout remains opaque log data.
4. The Task checks exact tags, model capabilities and empty initial residency,
   then calls the work function once. A returned callback outcome precedes final
   inventory and private runtime/manifest/config rechecks. Final resident models
   must have selected digests and `size_vram: 0` under the explicit CPU policy.
   A callback exception preserves the raised outcome and reports `callback_raised`;
   it proceeds directly to cleanup without further HTTP inventory.
5. The caller waits for the Task and HTTP clients to stop, closes the daemon,
   then persists bounded logs and the receipt. No log-file write runs in the
   live Port receive loop. Bytes drained during native close are outside the
   retained log prefix, as the receipt states.

Compare the `changed_after` case with `normal`. Both preserve the callback's
returned value, but changed final inventory makes the service receipt fail.
`work_status`, `service_status` and `native_cleanup` describe separate facts.
The owner-death case observes its known Task, Session and daemon stop separately;
it produces no final service receipt. Task termination alone does not establish
Session journal closure or canonical inference accounting.

The fixed CPU environment selects a policy that hides CUDA, ROCm and Vulkan
devices and disables cloud models. The synthetic fixture verifies those environment
values; real runtime CPU execution still needs separate verification. The selected
daemon defaults use one parallel request, retain selected
models and cap loaded models at the selection count. These concrete values appear
in the receipt. Final residency supplements this policy; it cannot prove every
allocation throughout the interval. This module grants no OS sandbox and trusts
the explicitly selected runtime. Ordinary process-group containment limits still
apply.

The v2 resolution binds this service selection. Measured stage admission claims
the attempt and establishes kernel membership before calling the owner. A service
receipt alone still establishes neither the complete native population nor model
quality; the post-exit audit joins the cell and native evidence.

### Exercise the native aggregate collector

Use a Linux host with cgroup v2 memory accounting, `clone3(CLONE_INTO_CGROUP)`,
a delegated systemd user manager and the existing Rust/Elixir toolchains.
The [dependency inventory](dependencies.md) records approval for this optional
benchmark tooling. Ordinary source tests and macOS operation do not require it.

```sh
./scripts/build.sh
elixir scripts/verify-memory-scope.exs "$PWD/priv/ipse-runner"
elixir scripts/verify-memory-drain.exs "$PWD/priv/ipse-runner"
elixir scripts/verify-memory-terminal.exs "$PWD/priv/ipse-runner"
```

Expect separate JSON summaries with `checks: 10`, `checks: 12` and `checks: 4`,
zero inference requests and private `evidence` directories. The verifiers start
only uniquely named transient user services and stop their own services on exit.
They retain synthetic receipts for inspection. To run the same exercise through
ExUnit, include its explicit tag:

```sh
mix test test/memory_scope_test.exs --include memory_scope
```

Follow `native/ipse-measure.rs` from scope admission to clone, first reap and final
counter read. Each root command is born inside a fresh cgroup before exec.
The serial/overlap control distinguishes the simultaneous total from individual
maxima. The Erlang control captures a brief 256-MiB Port child after it exits.
Unequal nested allocations check that a parent interval resets independently of
the whole-run counter, including when the launcher ignored SIGCHLD.

Next follow the controlled tail in `scripts/verify-memory-drain.exs`. The leader
leaves a child waiting on a release file. The verifier waits for the collector's
`leader-exited.json`, then releases the child to allocate 128 MiB and exit.
Both ordinary and detached children must finish naturally, and the nested case
must include that allocation in its cell and parent interval peaks. Output EOF
does not end the population measurement.

Compare the persistent child, nonzero leader and original-deadline cases. All
remain incomplete after cleanup. Another control stops only its own collector,
allows its leader to exit, then resumes observation after the original deadline;
the zero exit must still report timeout. Owner cancellation/EOF, anchor loss,
collector loss and registry replacement happen after actual reap. Killed anchor
cleanup returns an `E` diagnostic without a final receipt; the test separately
checks the owned child disappeared. It does not invent a completion record.

Trace `population_stop` and `active_failure` in `native/ipse-measure.rs`.
One population read and its timestamp govern natural closure, cleanup and
terminal eligibility. Deadline equality refuses. Guards run during natural
drain and again at the terminal output decision. The private population decision
tests exercise exact boundaries without depending on scheduler precision.
`EvaluationMeasuredExecution.native_receipt?/2` checks the corresponding
version, policy and timings against each original timeout. A changed or missing
field cannot be supplied by a later clean process list.

The terminal verifier compiles private copies of the same native source. A
bounded diagnostic barrier pauses after natural emptiness, immediately before
the final guard. Cancellation there must fail. Its deliberately reversed guard
must accept the same cancellation, proving that the control reaches the intended
boundary. A separate delayed release must report timeout under the original
deadline. These diagnostic copies leave production source untouched and cannot
supply accepted benchmark peaks.

Then follow the owner and collector loss cases. A preclosed lease must refuse
before command execution. A cancellation following ignored control bytes must
still be observed while the owner remains open. The scope's private native anchor
kills descendants after a nested collector dies, even while the application is
alive. Root collector loss remains a separate incomplete case: its started record
survives without a completion receipt. It does not prove that no work occurred.

Compare `peak_bytes` with `parent_interval_peak_bytes` as separate subjects.
Both are kernel charged-memory high waters. Page cache, shared-page ownership
and kernel charges make them different from summed process RSS. They do not
establish GPU/device-memory coverage or an exact macOS aggregate. Do not sum peaks
or subtract a starting baseline. See the [native protocol](../../native/README.md#optional-exact-aggregate-memory-scopes)
for lease, output and receipt rules.

These controls isolate native collection. Use the complete measured-population
exercise to check how its receipts join evaluator claims, model ownership and
first predictions. The sampler remains a separate diagnostic.

### Exercise complete measured sequences

Use the same supported Linux host and built helper to verify the generic stage
launcher. This exercise needs no model service or evaluation dataset:

```sh
elixir scripts/verify-memory-sequence.exs "$PWD/priv/ipse-runner"
IPSE_SEQUENCE_TESTS=$(mktemp -d)
rustc --edition=2021 --test -D warnings native/ipse-sequence.rs \
  -o "$IPSE_SEQUENCE_TESTS/sequence"
"$IPSE_SEQUENCE_TESTS/sequence"
```

Expect the live cases and native parser/filesystem tests to pass. Follow one
`Stage` from its immutable binary descriptor into `stage-000.claim`, then through
the child collector's `M` receipt and two-byte `T` completion status. Preparation
and finalization use the same birth-before-exec path as cells. Their separate
scope and parent-interval peaks contribute to the whole-run counter; they are
not incremental differences to subtract from another peak.

The live fixture allocates memory in fresh preparation/finalization BEAM entries
and their brief Port children while an unrelated sibling stays alive outside
the measured root. Another case prints a forged completion frame from a failed
application. Its bytes must remain opaque logs, the stage stays failed, and the
real finalizer runs only after cleanup confirmation. Collector loss instead
leaves a permanent claim without status or summary and prevents later stages.

Then follow both writerless FIFO inputs. A bootstrap FIFO must refuse before
preparation; a preparation-produced cells FIFO must refuse before any cell or
finalizer. Descriptor admission opens nonblocking before checking the retained
FD type, so refusal does not wait for the outer run deadline.

The [native protocol](../../native/README.md#sequence-complete-measured-stages)
owns the exact descriptor layout, limits and evidence filenames. `EvaluationMeasuredExecution` supplies the sealed schedule, original allocations
and first claim for knowledge work. Its post-exit audit reconciles finalizer and
outer-root receipts, which do not exist while finalization runs. The generic
controls isolate sequencing; held-out quality and real model execution require
their own evidence.

### Interpret latency and measurement limits

Phase clocks use monotonic microseconds. The summary reports nearest-rank p50
and p95 in milliseconds with sample and unknown counts. Query IDs distinguish
repeated question text. Failed queries stay in the grid and in observed clocks.
The enclosing projection phase includes its required storage audits. Use
`invoke_index` and `invoke_extract` timings to inspect public command durations
before those audits; execution time includes the complete measurement workload.
Invocation timings separately count unconfirmed completion; an elapsed wait is
not proof that interrupted work finished. Canonical request duration comes from
the journal and remains unknown when unavailable.

The summary's `complete` field covers the declared clock and accounting scope.
Read `storage_reachability_complete` separately. Check `measurement_scope`,
`unmeasured` and `resource_evaluation_complete` before comparing engines. The
separate sampler describes the harness BEAM only. It does not report process RSS or device memory. The measured v2 audit separately
reports kernel charged-memory high waters; v1 has no equivalent aggregate. File counts under a run directory also
exclude authoring and preflight copies outside that directory; the output-wide
overview counts those copies separately. Lifecycle file lengths and sampled
harness memory do not measure whole-system memory or every storage allocation.

### Verify retained storage without querying through the audit

Follow `EvaluationInventory.snapshot/6` and the pure `Store.inventory/2` in the
independent knowledge artifact. The host validates the bounded, owner-only State
file and every record envelope through `State.valid_outcome?/4`. It checks the
namespace, version and generation sum. A separate VM loads the verified
artifact, public SDK and existing Jason runtime, then computes counts and opaque
hashes. The SDK validator needs Jason even when the audit itself uses Elixir JSON.
Measured inventory children first restore the sealed ERTS/ordered code paths
through `EvaluationMeasuredExecution.command/4`, then add the verified artifact's
`ebin` in that child. The `/5` wrapper uses the v1 development Elixir launcher.
The host rechecks file bytes and artifact identity afterward. Domain modules remain unloaded in the host.

Selected root references identify retained content and projections. The audit
verifies each referenced page's hash, partition, source and generation. It also
checks a repeated reference's hash before skipping traversal. Missing, deleted
or substituted pages refuse the inventory. Draft pages stay separate from
selected pages; abandoned pages become orphans. For source drafts,
`source_generation` is the old-source precondition and `target.generation` owns
the new pages. Projection drafts retain the current source generation.

Read tombstone and slot counts at namespace scope. A tombstone retains no value
from which to recover partition ownership. Collection can remove page values
while retaining their record slots and revisions. Encoded value/record bytes
use Elixir JSON; actual State file bytes are reported separately. The audit
returns no source text and must never supply retrieval or model inputs.

The runner records snapshots before ingestion, after each index/extraction
projection, after preparation, after each query, after source suppression and
after collection. Projection snapshots retain source generation and chunk ID;
their count must match public projection invocation timings. Its cache key
includes the exact State file hash, path, artifact digest
and partition. Unchanged query reads reuse the verified inventory file. Missing
storage is explicit absence; unavailable or corrupt storage remains incomplete.
Research has no retained State store and reports that distinction explicitly.

Follow `storage_lifecycle/4` after the prediction loop. It inspects each source
once, skips roots already suppressed and explicitly forgets the rest. The
post-forget inventory must be available before collection. Follow
`EvaluationInventory.collection_requests/3`: it binds owner-only namespace bytes
to their verified hash, requires every root in the selected partition to be
suppressed with no draft, and returns only exact project-scope page deletions.
The approval policy matches each request and permits each key once. Collection
uses batches of at most twelve, with at most twenty-two batches for the existing
256-slot namespace. Final inventory requires no orphan pages and unchanged slot
count. Missing lifecycle snapshots keep storage coverage incomplete.

No further quality query runs against those suppressed copies. A failed
suppression or collection keeps earlier prediction rows and reports incomplete
execution. Earlier journal text and original dataset bytes remain retained;
collection is not transcript erasure or slot recovery.

For v1, `execution-overview.json` records elapsed time from runner entry through first
prediction finalization, including preflight, input handling, cleanup and the
primary reports. CLI startup, module loading and the overview's own inspection
and receipt stay outside that clock. The overview counts regular file lengths
under the complete output directory, including authoring and preflight copies,
and separately under declared frozen inputs. Read its exclusions before adding
those counts to a storage comparison. File lengths do not measure allocated
blocks, compression, shared extents or an exact transient peak.

Run the isolated validation exercises:

```sh
mix test test/knowledge_store_test.exs test/knowledge_evaluation_inventory_test.exs
```

Follow a first ingestion and a replacement draft through append, abort, forget
and collection. Check that selected pages stay unchanged during replacement,
draft pages become orphans after abort, and collection creates tombstones
without recovering slots. Then corrupt a reference hash or substitute a foreign
page. Expect inventory refusal. In the raw-file exercise, an inconsistent
generation sum, a floating-point generation or group/world-readable State file
must fail before it can become trusted metadata.
The collection-allowance exercise separately rejects an active root, a retained
draft, changed bytes and a stale revision snapshot. Only the selected partition's
page keys can enter its approval list; roots, foreign pages and source text stay
out of that list.
