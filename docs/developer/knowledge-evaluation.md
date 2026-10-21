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
| Verification command | `dev/verification/cli.exs`, `scenarios.exs`, `runtime.exs` | Admit a finite proof, compile its exact closure and own its selected source or installed runtime |
| Phase command | `dev/evaluation/cli.exs` | Parse declaration, freeze, measured execution, audit, review and score phases |
| Synthetic assertions | `dev/verification/measured_knowledge.exs`, `measured_authority.exs` | Preserve first predictions, tamper/scoring refusals and five independent loss controls |
| Scripted daemon | `dev/fixtures/model_service.exs` | Build only the synthetic protocol fixture, with verification mode selected before sealing |
| Declaration | `dev/evaluation/contract.exs` | Build seven strategies, admit complete plans and resolve declared command/model selections without loading execution |
| Identity | `dev/evaluation/freeze.exs` | Declare portable content and seal one closed local resolution |
| Measured execution | `dev/evaluation/measured_execution.exs` | Claim the native root, admit preparation/cells/finalization and audit their evidence |
| Kernel population | `native/ipse-bound.rs`, `ipse-measure.rs`, `ipse-sequence.rs` | Retain directory/scope authority, launch work inside cgroups and record terminal receipts |
| Domain execution | `dev/evaluation/runner.exs` | Admit catalogs, project inputs, run complete cells and finalize first predictions |
| Model lifetime | `dev/evaluation/model_service.exs` | Copy a fresh runtime/cache, own one daemon and guard one complete cell callback |
| Public Session | `dev/evaluation/session.exs` | Invoke approved public commands and retain complete results and cleanup acknowledgments |
| Dataset | `dev/evaluation/dataset.exs` | Project questions without labels, normalize delayed answers and check literal citations against hash-validated source bytes |
| Answer projection | `dev/evaluation/answer.exs` | Map shown answer spans back to complete evidence |
| Inspection | `dev/evaluation/inventory.exs`, `resources.exs` | Verify storage reachability and reconcile canonical requests with conservative budget liability |
| Review and score | `dev/evaluation/review.exs`, `score.exs`, `metrics.exs` | Blind saved predictions and measure independent semantic verdicts after recomputing literal references |

These owners use the `Ipse.Development.Evaluation` namespace. The runnable
knowledge examples remain under `examples/knowledge/`; independently distributed
domain code stays under `extensions/knowledge/`. Follow `Dataset` when changing
input projection or source identity. It performs no file IO. Runner and Score
still control when captured bytes and labels may be opened; combining pure
dataset operations does not move that authority.

The Session driver imports artifacts through ordinary host APIs. It does not load
production knowledge modules into the evaluator or call a provider directly.
Its caller validates the complete proposed action. A selected profile names a
route; it does not approve every request on that route.

Start a declaration change in `Contract.build/1` and `validate/1`.
The same owner holds the selected command and model-origin rules used by Runner.
It loads no execution, model-service or fixture implementation. For example,
this prepares the public template while its data and artifact paths are absent:

```elixir
Code.require_file("dev/evaluation/contract.exs")
spec = JSON.decode!(File.read!("examples/knowledge/benchmark-spec.json"))
spec = Map.put(spec, "blind_seed", String.duplicate("b", 64))
{:ok, plan} = Ipse.Development.Evaluation.Contract.build(spec)
:ok = Ipse.Development.Evaluation.Contract.validate(plan)
```

Run the example in `iex -S mix` from the repository root. The repeated seed is
for this declaration exercise; use `--new-blind-seed` for a real declaration.
Building a plan admits policy without importing artifacts, opening data or
running models. `validate_shape/2` has a narrower purpose: Freeze uses it to
recognize the existing execution or portable envelope before checking identities.
It does not replace full policy validation. Freeze still owns portable projection,
local resolution and filesystem identity, and generic version-one seals retain
their original map contract. Source-mode component exercises explicitly load
`dev/evaluation/runner.exs`; captured execution compiles its
declared closure before launch. Requiring only the declaration owner loads
neither execution path.

Keep labels and expected answers out of the driver, extension options and model
inputs. Query projection produces only `query_id`, `project` and `query`. Save and
hash all first predictions before review. A scorer can enforce its own loader
order; it cannot prove that another caller has never read a label file.

## Run a complete synthetic measured population

Use this exercise to trace preparation, fourteen cells, finalization, audit and
scoring without selecting model weights. Each cell owns a scripted Ollama-protocol
daemon. The workload has fifty queries, two projects and seven strategies.
It tests execution and evidence protocols, with no model-quality claim.

Build Ipse on the supported optional Linux backend. Keep the repository clean
and store the prebuilt artifacts outside it. Artifact construction completes
before the proof starts:

```sh
./scripts/build.sh
IPSE_MEASURED_PROOF=$(mktemp -d)
IPSE_PROOF_SDK="$PWD/_build/dev/lib/ipse/ebin"
elixir extensions/knowledge/build.exs --sdk "$IPSE_PROOF_SDK" \
  --output "$IPSE_MEASURED_PROOF/lexical" --package corpus --preset state-lexical
elixir extensions/knowledge/build.exs --sdk "$IPSE_PROOF_SDK" \
  --output "$IPSE_MEASURED_PROOF/dense" --package corpus --preset state-dense
elixir extensions/knowledge/build.exs --sdk "$IPSE_PROOF_SDK" \
  --output "$IPSE_MEASURED_PROOF/semantic" --package corpus --preset state-semantic
elixir extensions/knowledge/build.exs --sdk "$IPSE_PROOF_SDK" \
  --output "$IPSE_MEASURED_PROOF/explicit" --package graph --preset state-explicit
elixir extensions/knowledge/build.exs --sdk "$IPSE_PROOF_SDK" \
  --output "$IPSE_MEASURED_PROOF/model" --package graph --preset state-model
elixir extensions/knowledge/build.exs --sdk "$IPSE_PROOF_SDK" \
  --output "$IPSE_MEASURED_PROOF/research" --package research --preset mcp
elixir scripts/build-artifact.exs model-calls --sdk "$IPSE_PROOF_SDK" \
  --output "$IPSE_MEASURED_PROOF/answer"
elixir -e '
[root] = System.argv()
map = Map.new(~w(answer dense explicit lexical model research semantic),
  &{&1, Path.expand(Path.join(root, &1))})
File.write!(Path.join(root, "artifacts.json"), JSON.encode!(map), [:exclusive])
' "$IPSE_MEASURED_PROOF"
elixir scripts/verify.exs source measured-knowledge \
  --sdk "$IPSE_PROOF_SDK" --repository "$PWD" \
  --input "$IPSE_MEASURED_PROOF/artifacts.json" \
  --output "$IPSE_MEASURED_PROOF/source" --selection sealed-structured
```

The input is exactly a JSON object with the seven keys shown above. Each value
is a normalized absolute artifact-directory path. Runtime inventories both the
map and every referent before and after the proof. The selected repository must
be a clean Git root. Its exact source files supply the proof compiler; the SDK
supplies the selected host and dependencies. No artifact build runs inside proof
execution or a measured stage.

Expect `synthetic: true`, `model_quality_measured: false`, 350 saved first rows and
complete execution/resource audit results. The driver checks exact model request
schemas, exclusion markers, canonical request counts, unchanged read-only audit,
refused reentry and changed-evidence refusal. Its review and score controls use
the actual CLI, including refusal before label or review inputs are opened.
A successful synthetic score control reports `unmeasured_quality_refused`.

`sealed-structured` selects plan three and detached answers. Each actual answer,
extraction and rerank request must have the expected task schema, shown IDs,
counts, `think: false` and output-token limit. Synthetic answer bytes stay only
in the outer proof owner's memory through preparation, all cells, finalization
and audit. Scoring then releases the exact committed bytes. The fixture mode
and identities remain explicit throughout.

For compatibility controls, `structured` uses combined fixture data with plan
three, `sealed` uses detached answers with plan two, and `default` uses combined
data with plan two. These are closed selections, not positional switches.
None changes the seal, prediction or review-envelope version.

Inspect `$IPSE_MEASURED_PROOF/source/runtime` for retained host/harness files and
`$IPSE_MEASURED_PROOF/source/run` for the fixture data, `freeze`, `reports` and
`scoring-controls`. Failed setup and execution retain partial evidence under the
fresh output. Read the first failed stage's `process.log`, `started.json`, receipt
and domain report together. Never remove a claim or rerun a consumed seal.
After diagnosing a synthetic failure, choose a fresh output for a separate proof.

To exercise an already-built compatible package with the same artifacts, set
`IPSE_ARCHIVE` to the exact file printed by the packager:

```sh
./scripts/package.sh
IPSE_ARCHIVE=/absolute/path/to/the-compatible-archive.tar.gz
elixir scripts/verify.exs installed measured-knowledge \
  --archive "$IPSE_ARCHIVE" --repository "$PWD" \
  --input "$IPSE_MEASURED_PROOF/artifacts.json" \
  --output "$IPSE_MEASURED_PROOF/installed" --selection sealed-structured
```

The shared verifier extracts the archive and compiles the same trusted proof
closure against its SDK before launch. The installed host uses those BEAM files,
the bundled ERTS and captured utility paths, with no system development tools on
its runtime PATH. It retains the extracted runtime for later evidence checks.
The source checkout remains a declared, unchanged input; the installed process
does not compile or require its source files. Follow the
[shared verification runtime](testing.md#follow-compilation-and-execution-ownership)
for compiler, input and lifetime ownership.

A successful installed proof establishes the exercised protocols for that archive
and host. It does not establish real Ollama CPU execution, held-out quality or
all failure/loss behavior. Keep results in [dated records](../archive/index.md)
and acceptance criteria in [the plan](../plan.md#p27-optional-research-graph-and-rag).

### Exercise authority and loss before accepting an execution change

Use the same map and a fresh output for five independent seals:

```sh
elixir scripts/verify.exs source measured-authority \
  --sdk "$IPSE_PROOF_SDK" --repository "$PWD" \
  --input "$IPSE_MEASURED_PROOF/artifacts.json" \
  --output "$IPSE_MEASURED_PROOF/authority"
```

`dev/verification/measured_authority.exs` observes the actual preparation VM's
file descriptors 4 through 8 and kernel membership before inducing owner loss,
collector loss, an owned-service stop or registry replacement. Service-stop also
checks ordinary native-helper and daemon descriptors for leaked authority objects.
The fifth seal selects a daemon that exits after recording its first answer
request. Its failed service receipt, incomplete stage and first canonical request
remain observable.

Expect five retained control results, confirmed owned-scope cleanup and refused
reentry. Missing live observation, cleanup or an unexpected later claim fails the
proof and preserves `failure.json`. A missed timing boundary is a failure.
The daemon-loss case permits distinct later cells after confirmed cleanup and
never retries the interrupted request. Inspect its journal and usage separately
from process disappearance. Missing domain evidence cannot establish full
liability reconciliation.

Repeat the same controls against an installed runtime with another fresh output:

```sh
elixir scripts/verify.exs installed measured-authority \
  --archive "$IPSE_ARCHIVE" --repository "$PWD" \
  --input "$IPSE_MEASURED_PROOF/artifacts.json" \
  --output "$IPSE_MEASURED_PROOF/authority-installed"
```

Both authority modes start and stop only their own temporary services. Their
retained runtime and `run` evidence follow the same layout as measured knowledge.
They require the optional Linux backend and measure no model quality.

## Declare the complete comparison

For a new acceptance workload, first obtain a metadata-only commitment from an
independent author. Keep their corpus, questions and answers unavailable to the
implementation team until code and configuration are frozen. The author retains
the answer bytes until every first prediction and the measured audit are frozen.
A hash commits bytes; provenance and custody records establish who authored and
handled them. Neither prevents disclosure through another channel.

The author prepares three UTF8 JSON files, each at most 1 MiB. `corpus.json` uses
`schema_version: 1` and a `documents` array of at most 256 complete source rows.
This complete one-document example has matching body bytes, length and SHA256:

```json
{"schema_version":1,"documents":[{"document_id":"d1","project":"alpha","source_id":"source:one","generation":1,"version":1,"title":"Fixture","text":"A café.","created_at":"2026-01-01T00:00:00Z","observed_at":"2026-03-01T00:00:00Z","state":"current","sha256":"17279f71f4ea96992036469e0ac54aebc728033c129e8a52dc7dddfbd9e3b8d3","byte_length":8,"media_type":"text/plain; charset=utf-8"}]}
```

Every shown document field is required. A project name starts with a lowercase
ASCII letter and contains at most 64 lowercase letters, digits, underscores or
hyphens. Bound `document_id` and title to 128 UTF8 bytes, `source_id` to 256, body
text to 65536, state to 64 and media type to 128. These fields are nonempty.
Generation is a positive safe integer; version is a positive safe integer or a
nonempty string of at most 64 bytes. Times are ISO8601 values with nonnegative
epoch milliseconds. Use distinct project/source/generation identities. The
corpus adapter preserves additional metadata as excluded field names, while
projecting only the documented source fields. It validates complete body hashes
and lengths; [input projection](#project-query-inputs-without-labels) explains
lifecycle handling and duplicate generation refusal.

`queries.json` has this closed envelope and exactly these three fields per row:

```json
{"contract":"sealed_answers_v1","split":"heldout","queries":[{"query_id":"q1","project":"alpha","query":"What must precede release?"}]}
```

The separately retained answer file has a private random nonce and normalized
source identities. This one-row illustration is too small for the fifty-question
author validator. Source hashes and span bytes must match the actual corpus:

```json
{"contract":"sealed_answers_v1","split":"heldout","commitment_nonce":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","answers":[{"query_id":"q1","project":"alpha","expected_class":"open","expected_refusal":false,"expected_answer":null,"relevance":[]}]}
```

Generate the actual nonce once with
`Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)` in the author's Elixir
tooling. Keep it in the final answer bytes, outside shared metadata. The repeated
`a` value above is a synthetic example. A withheld nonce prevents guessing a
small answer set against its published file hash; it does not replace custody.
Each nonempty relevance entry has exactly `source`, `grade`, `start_byte`,
`end_byte` and `quote`. `source` has exactly `project`, `source_id`, `generation`,
typed `version` and `sha256`. Coordinates are half-open UTF8 byte offsets into
the complete captured source. Integer `1` and string `"1"` are different versions.

In the author's custody, place `corpus.json` and `queries.json` beside the intended
manifest output, then validate all fifty query identities across two projects:

```sh
mix run scripts/prepare-knowledge-dataset.exs -- \
  --corpus /author/public/corpus.json --queries /author/public/queries.json \
  --answers /author/escrow/answers.json --as-of-ms 1800000000000 \
  --output /author/public/manifest.json
```

Expect `status: "ok"`, `manifest_sha256`, `answers_sha256`, `query_count: 50` and
`project_count: 2`. No source, question, answer, class or nonce appears in this
receipt. The validator checks complete joins and literal references, creates an
owner-only manifest exclusively and refuses an overwrite. A failure prints only
`invalid_dataset_or_output`; inspect the private files in the author's environment.
Do not regenerate committed bytes after observing predictions.

The closed manifest binds only the two predictor inputs and the pathless answer
digest:

```json
{"contract":"sealed_answers_v1","as_of_ms":1800000000000,"inputs":{"corpus":{"path":"corpus.json","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"},"queries":{"path":"queries.json","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}},"answers_sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}
```

These illustrative digests are placeholders. The author tool computes real hashes
over exact bytes. Share only its metadata receipt before freezing. Install the
committed manifest, corpus and questions at the resolved dataset location after
freezing; do not install the answers yet.

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
elixir scripts/build-artifact.exs model-calls --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/answer"
cp examples/knowledge/benchmark-spec.json "$IPSE_BENCHMARK/spec.json"
```

Review `spec.json` before generating a plan. The template declares a fifty-query held-out
comparison with lexical, explicit graph, model graph, dense, hybrid, rerank and
Research variants. Every variant selects the same answer helper. Its example
local profiles name Qwen and embeddinggemma with exact expected inventory
digests; review the endpoint, installed model identities and budgets for your
authorized run. There is no provider fallback or model download. The declared
template retains the historical combined query/answer contract. Its exposed
workload is suitable only for tuning and historical reproduction. For the new
workload, set `version: 3`, `model_origin` to one canonical private IPv4-loopback
origin, and every profile's `base_url` to that same origin. Set `data` to:

```json
{"contract":"sealed_answers_v1","corpus":"corpus.json","queries":"queries.json","split":"heldout","expected_queries":50,"manifest_sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}
```

Replace the illustrative digest with the independently retained author receipt's
`manifest_sha256`. Keep the model selections, seven variants and budgets under
review. The subsequent portable declaration removes local endpoint bindings and
the execution resolution supplies them again. Generating a plan does not open
the manifest, corpus, questions or answers. Their paths may still be absent.

Plan three also requires this exact `contracts` object:

```json
{"outputs":{"answer":"json_schema_v2","extract":"json_schema_v2","rerank":"json_schema_v2"},"selection":"per_strategy_eligibility_v1"}
```

`Contract.build/1` adds the matching output-contract selections to
extraction and rerank profiles. Full validation refuses a changed selection.
All three text tasks use the host's schema-bound `model.complete` version-two
request. The answer, extraction and rerank schemas differ and bind the IDs
actually supplied to each task. Schema conformance does not establish factual
support. Independent semantic review remains required.

Keep format versions separate when tracing a run:

| Object | New comparison version | Responsibility |
| --- | --- | --- |
| Executable and portable plan | 3 | Fix text output contracts and individual strategy qualification |
| Experiment and local execution seal | 2 | Bind portable policy and one measured local resolution |
| Answer preparation bundle and model request | 2 | Retain the complete schema-bound approved request |
| Saved prediction row and independent review envelope | 2 | Preserve first outcomes and bound judgments |
| Scoring declaration | 3 | Bind the complete validated declaration and prediction files to review |
| Score report | 2 | Publish eligibility, disqualifications and complete-grid diagnostics |
| Metric implementation | 1 | Retain the historical diagnostic definitions |

Historical plans one and two keep their original closed fields and selection
rules. Adding `contracts` to either refuses. Choose the new generation explicitly
before freezing. An old experiment cannot acquire the new qualification policy
through a scoring command or a changed review file.

For example, convert the copied template without reading any dataset member:

```sh
export IPSE_DATA_MANIFEST_SHA256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
elixir -e '
[path, manifest_sha256] = System.argv()
origin = "http://127.0.0.1:47631"
spec = JSON.decode!(File.read!(path))
spec = Map.merge(spec, %{
  "version" => 3, "model_origin" => origin,
  "contracts" => %{
    "outputs" => Map.new(~w(answer extract rerank), &{&1, "json_schema_v2"}),
    "selection" => "per_strategy_eligibility_v1"
  }
})
spec = Enum.reduce(~w(profiles embedding_profiles), spec, fn key, acc ->
  Map.update!(acc, key, &Map.new(&1, fn {name, profile} ->
    {name, Map.put(profile, "base_url", origin)}
  end))
end)
spec = Map.update!(spec, "data", &Map.merge(&1, %{
  "contract" => "sealed_answers_v1", "queries" => "queries.json",
  "manifest_sha256" => manifest_sha256
}))
File.write!(path, JSON.encode!(spec) <> "\n")
' "$IPSE_BENCHMARK/spec.json" "$IPSE_DATA_MANIFEST_SHA256"
```

The repeated `f` digest makes this a declaration exercise. For a real comparison,
set the variable to the author's retained manifest hash before running it.
This command changes only the private specification copy. Review its selected
model identities and limits before proceeding.

Generate the private plan:

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
version-one held-out policy or version-two measured resolution. V1 rejects the
new sealed-answer contract. Plans two and three permit it in `heldout` and explicitly synthetic
`fixture` mode; the question/answer split remains `heldout` in either mode.
Fixture mode requires fixture model names and inventory. It cannot satisfy the
held-out model gates.

The public source command validates the plan before preparing Research's local
search/fetch fixture. Runtime compiles its two declared BEAM modules in a separate
compiler process, loads the checked bytes and runs the phase in the caller's
development environment. A tuning or fixture-verification command owns a temporary
runtime that is removed after either a successful or failed phase. CLI
`evaluate/1` returns the result to Runtime so inventory checks and cleanup finish
before the outer command prints its summary and exits. Lexical-only plans and
declarations need no fixture compilation. This fixture transports the admitted
gateway calls; it does not provide model answers.

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
freeze data and retained first-prediction reports:

```sh
IPSE_RETAINED=$(mktemp -d)
mix run scripts/evaluate-knowledge.exs -- --phase declare \
  --plan "$IPSE_BENCHMARK/plan.json" \
  --output "$IPSE_BENCHMARK/experiment.json" \
  > "$IPSE_RETAINED/declaration.json"
IPSE_EXPERIMENT_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["sha256"])' "$IPSE_RETAINED/declaration.json")
```

Expect `status: "ok"`, the experiment path/hash and the source commit.
`Freeze.declare/3` removes source/artifact paths, profile origins and
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
`ModelService.validate/1` schema. Its origin and exact model map must
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
mix run -r dev/evaluation/model_service.exs -e '
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
:ok = Ipse.Development.Evaluation.ModelService.validate(service)
resolution = %{
  "artifacts" => plan["artifacts"], "model_origin" => service["origin"],
  "search_port" => 47632, "reports" => Path.join(root, "reports"),
  "data_manifest" => Path.expand(System.fetch_env!("IPSE_DATA_MANIFEST")),
  "model_service" => service
}
File.write!(Path.join(root, "resolution.json"), JSON.encode!(resolution), [:exclusive])
File.chmod!(Path.join(root, "resolution.json"), 0o600)
'
elixir scripts/evaluate-knowledge.exs --phase freeze-measured \
  --sdk _build/dev/lib/ipse/ebin --repository "$PWD" \
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

### Retain the evaluator before sealing

The creation-only `--sdk` and `--repository` options select precompiled source-host
execution for `freeze-measured`. Use `--archive /absolute/path/to/compatible.tar.gz`
instead of `--sdk` to select an installed host. Both choices require the clean
declared repository. Later phases reject these preparation options.
Before freezing, a separate compiler VM builds the exact evaluator closure from
that repository. The freezer retains the runtime under
`$IPSE_BENCHMARK/frozen-measured.runtime/runtime`; keep that directory beside the
freeze for the entire execution, audit and scoring lifetime. Retained source-mode
SDK, dependency, OTP and utility files are still unchanged external prerequisites.
This local capture is not a portable runtime archive.

Later `scripts/evaluate-knowledge.exs` calls with the freeze path and expected hash
reopen the captured evaluator. Use plain `elixir` for that path. The outer entry
checks the bounded manifest, complete BEAM membership and file identities before
loading the selected modules. A fresh child verifies the same captured files and
runs the normal full freeze validation before its phase. It resolves supplied
relative paths against the caller's working directory before handing off.
A partial or changed capture refuses rather than falling back to checkout source.
Source-mode historical seals retain their documented source execution path.

The cold entry uses the inspected `erlexec` and a fresh private HOME/TMP outside
the freeze evidence and captured runtime. It removes this scratch after each
invocation and preserves the original operation failure if cleanup also fails.
Only the outer Linux manager retains the selected systemd
user-service environment. Preparation, cell and daemon environments retain their
separate strict policies. Selecting the manager does not forward its variables
to the measured work. The scripted fixture selects its verified bootstrap before
sealing; runtime control data cannot downgrade that choice.

### Follow authority into preparation

Read `context!/2`, `run/1`, `enter/1` and `admit_stage!/2` in
`MeasuredExecution`. The entry rechecks the seal and the actual evaluator
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

`Runner.schedule/2` derives fourteen cells in sorted-project and
original-variant order. Plans two and three divide every request, token and monetary
cap by the original two-project count, rounding down. Reservations and the rate
card remain unchanged. A share below its reservation refuses admission. Unused
amounts cannot transfer or renew. Each Research share is its project's query
count times `1 + max_sources`; its controlled gateway owns that separate finite
share. Version one divides request/token caps only and uses one gateway allowance
across projects.

### Follow one complete cell and its first predictions

The stage VM calls the internal `ModelService.run/4` inside its fresh
measured scope, supplying the verified environment constructor for that execution.
The owner copies the selected runtime and manifest/blob closure into new private
files. The caller drains the native Port while a guarded Task works. Only native
listener `P` admission permits initial HTTP inventory and the callback; child
stdout cannot supply that proof. See [owned listener observation](../../native/README.md#observe-an-owned-loopback-listener).

The callback calls `Runner.evaluate_cell/6` with the original plan,
one schedule cell and its execution context. That context selects the precompiled
child roles and their verified environment. Source authoring, ingestion,
projection, all project queries,
source suppression, collection, Session close, gateway close and budget
reconciliation happen inside that cell. Captured authoring and inventory
children use `MeasuredExecution.precompiled_command/4`. The child
checks ordered code-path membership and inspected BEAM bytes, loads Environment,
enters its policy, loads the requested role, then compiles the fixed expression.
`command/4` remains the original source-compatibility branch.
These children use the selected ERTS and do not require Elixir or Mix on PATH.

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
elixir scripts/evaluate-knowledge.exs --phase measure \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" \
  > "$IPSE_RETAINED/measure.json"
elixir scripts/evaluate-knowledge.exs --phase audit \
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
`Runner.audit_merged_files/2` compares all six merged streams with
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

The public CLI prints the joined audit summary; it has no full-report option.
Keep its result and hash alongside the native receipts, stage records and first
predictions. A receipt read alone is not the complete joined audit. Do not load
a different source evaluator to inspect a captured seal.

For this chapter's worked field inspection, use the complete synthetic proof's
`$IPSE_MEASURED_PROOF/source/run/verified-audit.json`. Its verified result contains
the `report` fields below. The proof saved that result through the captured
evaluator after native execution, before its tamper and scoring controls.

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
`dev/verification/measured_knowledge.exs`. It changes each merged stream
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
mix run -r dev/evaluation/freeze.exs -e '
alias Ipse.Development.Evaluation.Freeze, as: Freeze
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

A complete version-one Research plan also needs executable gateway fixture files
through later prediction and review. Use the public source entry, rather than
calling `Freeze.create/4` directly, to prepare that prerequisite:

```sh
mix run scripts/evaluate-knowledge.exs -- --phase freeze \
  --plan /absolute/path/to/reviewed-v1-plan.json \
  --output /absolute/path/to/fresh-source-freeze
```

Runtime retains the two compiled fixture modules under
`fresh-source-freeze.runtime/runtime/harness` before the ordinary version-one
snapshot. Keep that sibling directory with the seal. Later public frozen commands
check the separately retained manifest hash, inspect the captured fixture bytes
and reuse those exact paths without recompiling. They still require the original
complete source/runtime identity. The manifest format is unchanged. If the caller
already supplies a coherent pair of compiled fixture modules, the seal records
those caller-owned paths instead; their lifetime remains the caller's duty.
Existing source-mode version-two seals keep their original full launch checks.
Fixture adoption does not permit a partial capture of evaluator modules to use
the source route.

A historical seal without fixture files stays fixture-free. Research prediction
with such a seal refuses with `research_fixture_missing` after identity verification
and before opening the dataset. Create a fresh seal with the required fixture.
Changed, missing, duplicate or conflicting captured fixture modules refuse; no
replacement is compiled during reopen.

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
Follow `preflight!/3`, `selection/4` and `Session.preflight/1`. Tuning,
fixture execution and frozen prediction also perform this check before opening
any dataset member, including its manifest. The direct `Freeze.create/4`
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
preparation; version one does it after its executable preflight. New sealed
manifests admit exactly their corpus and query input roles. No answer pathname is
present, and preparation never traverses arbitrary manifest members. An extra
answer descriptor refuses. The legacy reader preserves recursive member hashing
for historical manifests, including their combined query/reference file.

`Dataset.queries/2` accepts the strict sealed question envelope or the
historical version-one bytes and declared split. Its `queries` result contains exactly
`query_id`, `project` and `query`, preserving their input order. Relevance,
expected classes, expected answers and refusal labels remain excluded. The
separate `excluded_fields` list reports field names; keep it in run metadata,
outside Session/model inputs.

`Dataset.corpus/1` checks each complete source's identity, generation,
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

`Dataset.sources/1` builds a lookup from that same validated corpus using the
typed project, source, generation, version and body-hash identity.
`citation_checks/2` compares prediction spans against those bytes;
`reference_checks/2` checks normalized reference spans after answer release.
Both use exact half-open UTF8 byte coordinates and quotes. These literal verdicts
do not establish semantic support. Review and Score call these operations rather
than trusting byte-check verdicts supplied in a review file.

Review and scoring load references only after their authority and first-prediction
checks. `Dataset.references/3` validates every detached answer, exact
query/project identity equality and duplicate typed relevance spans before it
builds lookup maps. It returns normalized score labels in original question
order and a separate expected-answer lookup for the independent review packet.
Reordered answers normalize to question order. Changed public question bytes
fail their manifest hash; a changed identity order also fails the saved sequence
check before answer loading. Public corpus and question bytes are hash-checked
again on the same bytes actually parsed. Review validates their semantics before
opening answers. Scoring retains its corpus-before-label boundary.

`Dataset.labels/2` remains the historical scorer adapter and also accepts
the new answer envelope. The runner uses `references/3` for a new workload so the
complete question join cannot be skipped. Neither API gives the predictor any
expected answer, reference class or refusal label.

```sh
mix test test/knowledge_evaluation_dataset_test.exs
```

Change expected-answer, class and relevance values in its first fixture. Query
projection must remain unchanged even when those labels become invalid. Then run
the label adapter and observe its separate refusal. This tests information
separation without opening the held-out workload.
Next, use its literal-span fixture to change one byte of a reference quote while
keeping the source identity. `reference_checks/2` must return `valid: false`.
The unchanged query projection still succeeds; byte validity and label release
remain separate questions.

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

Open its `matrix_plan/2` helper and follow `Contract.build/1`. They select independently built Corpus, Graph,
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
Plans two and three assign disjoint shares to the separately owned Research cells. The runner
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

`Ipse.Development.Evaluation.Answer.prepare/3` takes the query, an as-of time
and at most ten saved candidates in their existing rank order. Each candidate
has its complete `citation`. The result contains an exact `model.complete`
request for `p27_answer`, a shown context, coverage and the context's SHA256.
It executes nothing.

For plan three, Runner calls `prepare/4` with `"json_schema_v2"`. Its version-two
bundle retains the same six fields, including the complete version-two request.
After fitting the input, the helper derives `response_schema` from only the
shown evidence IDs. With no shown evidence, the schema permits only `abstain`
and zero claims. Bundle validation reconstructs that schema, so adding an
omitted ID or substituting another schema refuses before answer decoding.
The existing `prepare/3` keeps its version-one request and bundle contract.

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

After the public Session call completes, pass the saved response text and the
same bundle to `decode_answer/2`. The model writes exactly `classification` and
`claims`. It does not write an independent prose answer. Each claim contains only
`text` and `citations`; its text is nonblank and at most 1024 UTF8 bytes. Its
citation list contains one to ten unique shown IDs. Unknown or omitted IDs,
extra or duplicate fields, invalid UTF8, trailing content and Markdown fences
refuse the whole response. The raw JSON remains bounded to 8192 bytes.

The decoder resolves each ID to its original shown citation and derives the
material answer from the claim texts in order, joined by one LF. It preserves
each decoded text exactly, including whitespace, Unicode and embedded newlines.
It adds no classification-dependent prose to a nonempty answer. Changing a
classification therefore cannot change those material statements, although the
classification can still be wrong.

| Classification | Claims | Derived answer |
| --- | --- | --- |
| `answer` | One to eight | Ordered claim texts joined by one LF |
| `conflict` | One to eight | The same derivation; claims state the incompatible positions and their scope |
| `open` | Zero to eight | The same derivation when nonempty; otherwise `The shown evidence leaves this question unresolved.` |
| `abstain` | None | `I cannot answer from the shown evidence.` |

Without any shown candidates, only `abstain` with no claims is valid. With shown
evidence, an empty `open` or `abstain` can still be semantically incorrect. Neither
receives support credit from output conformance. One source can contain an
unresolved conflict; neither the decoder nor independent review requires two
different sources.

For example, this synthetic prepared model input contains a release condition
and its exception:

```json
{"query":"Can the field kit ship before its checksum manifest is ready?","as_of_ms":1000,"candidates":[{"id":"e1","source_id":"kit-policy","generation":1,"observed_at_ms":100,"event_at_ms":null,"quote":"For the field kit, release requires a checksum manifest. This requirement is waived for local rehearsal copies."}]}
```

A response that preserves both facts is:

```json
{"classification":"answer","claims":[{"text":"The field kit requires a checksum manifest for release, except for local rehearsal copies.","citations":["e1"]}]}
```

The decoded `answer` is exactly that claim's text. The short ID resolves to the
complete validated citation supplied to preparation; the model supplies no source
hash or byte coordinates. Each cited span must support its whole associated
claim. If support differs between factual points, the model must split them into
separate claims. Matching words alone do not establish support, and the helper
does not infer equivalence between differently named entities or procedures.

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

Claim IDs follow array order as `c1`, `c2` and so on. Cited context IDs are `a-e1`,
`a-e2` and so on. Two claims citing the same span retain two distinct review pairs,
such as `pair1-1` and `pair2-1`, while storing that context span once. Repeated
claim text is not deduplicated. The version-two saved format still contains both
`answer` and `claims`, and historical prediction readers remain unchanged. Only
the live model response loses the redundant `answer` field. Old raw responses
containing that field refuse, including `answer: null`.

Both CLI readers and the scorer accept at most 64 MiB in one prediction file
and 64 MiB across all declared files. Each JSONL row remains limited to 256 KiB.
Count serialized bytes, including JSON escapes and repeated source identities;
query count and raw quote lengths alone do not establish file capacity. Review
packets have separate limits of 32 MiB per file and 64 MiB in total. The scoring
CLI accepts a review JSON file up to 32 MiB through the host's duplicate-rejecting
decoder; manifests and dataset members retain their separate 1-MiB limits.
A size refusal keeps the first predictions for inspection. Never drop rows or
rerun model work to make a retained comparison fit a later consumer.

To trace the change through real Session and worker execution, run the focused
synthetic exercise from the repository root:

```sh
mix test test/knowledge_evaluation_answer_test.exs test/knowledge_evaluation_runner_test.exs --only answer_contract
```

The decoder exercise changes the class without changing the material answer.
The runner exercise retains two claims sharing one span and verifies distinct
pair IDs. It also returns an invalid response for the next query and checks that
the saved first row stays failed, with no prose answer, claims or retry. Retrieval
evidence remains available for inspection. The exercise uses a local scripted
model server, not actual model inference or a quality workload.

Derivation removes a second independently written prose body. It cannot establish
that a claim follows from its citation, that a class is correct, that the answer
is complete, or that two claims agree. Keep those semantic judgments in
independent review, alongside literal captured-source verification.

Trace the structured request through `Session.invoke/3`. Its new answer
argument is exactly `%{"request" => request}`. The driver validates the request
and evaluator byte limits, then forwards it unchanged. Historical four-field
arguments still construct their version-one request. Mixed argument forms refuse.
Runner records the canonical complete request hash beside `context_sha256`
before dispatch. Approval binds the complete request, including its schema.
For extraction and rerank, Runner independently derives the expected schema
after checking the input and source identities. It does not load a producer's
domain adapter to decide what to approve.

The host validates the returned JSON against the approved schema before domain
decoding. A completed invalid response retains its raw text and charged usage.
The evaluator keeps the failed first outcome without repair, retry or fallback.
The decoder still checks UTF8 byte limits, duplicate citations, attribution and
class-specific rules. A schema's character limit cannot replace those byte checks.

## Prepare independent review from finalized predictions

Use a completed v1 prediction or an audited v2 measured execution. Retain the
first-prediction hash before preparing a review. Version two additionally requires
the separately retained audit hash and the exact sealed data/prediction paths.
The `review` phase verifies the execution freeze, first-prediction identity and
complete variant/query grid before opening reference labels. It reuses
`Score.verified_predictions/2`; a separate permissive JSON parser
cannot substitute for the scorer's row checks. Prediction IDs must be opaque
`p-` plus SHA256 values before any label loader runs.

Keep three identities separate. The execution-freeze hash selects the experiment
and its reference data. `review_binding_sha256` binds that context, the metric
version and every verified prediction-file ID and hash. The separately retained
`packet_sha256` identifies the complete packet and its reviewer instructions.
For a plan-three comparison, scoring declaration three contributes its complete
validated content to a distinct review-binding domain. Changing the output
contracts, qualification policy or query order invalidates an old review, even
when prediction IDs and bytes remain the same. Historical scoring declaration
two retains its original binding. The review envelope remains version two in
both cases. The binding is opaque to a reviewer. It does not reveal strategy names.

For the v2 seal above, prepare a private packet and then score a separate review:

```sh
export IPSE_LABELS=/released/identical-committed-answers.json
elixir scripts/evaluate-knowledge.exs --phase review \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" --audit-sha256 "$IPSE_AUDIT_SHA256" \
  --data-manifest "$IPSE_DATA_MANIFEST" \
  --predictions "$IPSE_BENCHMARK/reports/predictions.jsonl" \
  --prediction-sha256 "$IPSE_PREDICTION_SHA256" \
  --labels "$IPSE_LABELS" \
  --output "$IPSE_BENCHMARK/review-packet"
cp "$IPSE_BENCHMARK/review-packet/reviews-template.json" "$IPSE_BENCHMARK/reviews.json"
```

The copied template remains unmeasured. Give the packet to an independent reviewer
and keep their actual verdicts in `reviews.json`. Preserve its version-two envelope
and `review_binding_sha256` exactly. Fill the existing verdict rows without
changing IDs. After that review, run:

```sh
elixir scripts/evaluate-knowledge.exs --phase score \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" --audit-sha256 "$IPSE_AUDIT_SHA256" \
  --data-manifest "$IPSE_DATA_MANIFEST" \
  --predictions "$IPSE_BENCHMARK/reports/predictions.jsonl" \
  --prediction-sha256 "$IPSE_PREDICTION_SHA256" \
  --labels "$IPSE_LABELS" \
  --reviews "$IPSE_BENCHMARK/reviews.json" \
  --output "$IPSE_BENCHMARK/scores"
```

For the new contract, `IPSE_LABELS` names the answer bytes released after the
audit. Their release path can differ from author escrow; exact bytes must match
`answers_sha256`. Review requires `--labels` for this contract and reports separate
`queries_sha256` and `answers_sha256` packet identities. Missing or changed answers
refuse without regenerating predictions. An untouched template produces
unmeasured support, writes `scores.json` and
exits one; it cannot manufacture a quality pass.

For a legacy combined dataset, omit `--labels` from review and supply the declared
query/reference member to score. Its summary retains `query_labels_sha256`. For
v1, use its separately retained freeze/prediction hashes and selected dataset
paths, and omit `--audit-sha256`. V1 refuses an audit argument. V2 refuses missing
or changed audit authority before labels/reviews, and refuses alternate canonical
prediction/data paths even when the caller supplies a plausible hash. The legacy
`predict` and `verify-frozen` phases refuse v2 seals with `measured_entry_required`;
use `measure` and `audit` for that format.

For review, expect `status: "ok"`, the complete row count, `packet_sha256` and
`reference_integrity_complete: true`. Retain that packet hash separately. An
existing output path refuses. Files are owner-only in a private directory.
For the sealed-answer contract, an invalid reference refuses with
`invalid_reference_integrity` before creating the packet directory. Investigate
the committed private references without changing first predictions. Legacy
combined datasets retain invalid references in a diagnostic packet, set
completeness false and produce a failing CLI exit. A written packet does not
establish semantic support.

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
into `Score.score/5`. The frozen declaration names variants, queries,
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

For plan three, read the report's `contracts` and `quality_gate_scope` first.
`per_strategy_eligibility_v1` applies the support threshold 0.90 and citation
threshold 0.95 to each strategy separately. A strategy's support gate divides
its independently supported or correct-abstention outcomes by all fifty declared
first outcomes. A recorded failed outcome contributes zero. Its citation gate
requires at least one reviewed pair and uses the supported fraction of all
claim/span pairs, with corpus-derived literal checks. The thresholds are inclusive.

`eligible_variants` lists strategies passing both gates. `disqualified_variants`
retains every weaker strategy and its gate values. All seven strategies and
350 report rows remain available in `variants`; a qualifier cannot hide a
weaker result. Eligibility permits later selection, but the scorer chooses no
engine and implements no tie-breaker. Resource, latency and other acceptance
evidence still need assessment before an engine decision.

`quality_gates_passed` additionally requires `complete_first_grid` and
`complete_review`. Every declared pair must have a distinct saved attempt-one
outcome. A materialized missing row is diagnostic, not a saved first outcome.
Every first outcome needs an independent review entry, including a failed
retrieval-only outcome whose applicable verdict is `unmeasured`. Every actual
answer or abstention needs a measured verdict, and every cited pair needs a
measured independent judgment and literal check. An eligible strategy cannot
compensate for missing outcomes or unfinished reviews elsewhere in the grid.

The aggregate `semantic` and `gates` fields remain diagnostics with the original
metric definitions. In particular, a failed retrieval-only row leaves diagnostic
support accuracy null while contributing zero to the new strategy gate's
fifty-outcome denominator. Historical scoring declaration two produces report
one with `quality_gate_scope: "complete_frozen_grid"`; its quality flag still
uses aggregate gates. Do not reinterpret that historical flag as individual
qualification.

The `score` CLI preserves `scores.json` and exits nonzero when the declared
quality policy fails or remains unmeasured. Run the score-suite qualification
exercise: 45 supported firsts with five reviewed failures must meet 0.90;
44 supported firsts must fail. Remove one failure's independent review entry
or leave an actual answer unmeasured. Both must block a quality pass. Semantic
quality gates do not replace the separate native authority, cleanup, resource,
installed-execution or source-suppression checks.
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
existing lock. `Resources.reconcile_budget/4` checks the exact request
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
`dev/fixtures/model_service_probe.rs`. It checks the selected environment and
answers the small Ollama inventory protocol. It loads no model and performs no
inference. The tests cover private cache contents and inodes, occupied ports,
forged child output, bounded logs, inventory failures, callback exceptions,
service loss and owner death. On macOS, the same test file checks pure selection
validation and refusal before staging because listener ownership requires Linux.

To retain the Linux case receipts outside ExUnit cleanup, compile the fixture
and choose a fresh evidence directory:

```sh
IPSE_MODEL_PROOF=$(mktemp -d)
rustc --edition=2021 -D warnings dev/fixtures/model_service_probe.rs -o "$IPSE_MODEL_PROOF/probe"
elixir scripts/verify.exs source model-service \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_MODEL_PROOF/probe" \
  --output "$IPSE_MODEL_PROOF/evidence"
```

Expect one JSON summary whose cases all report `status: "passed"`. Inspect each
case's `verification.json` and the completed cases' `receipt.json`. Failed
operations retain partial output. Preserve those files when diagnosing a failure;
choose another output directory for another synthetic exercise. Reusing an
operation's directory must refuse without replacing its receipt or running work.

To repeat the cases with a bundled runtime, build a package and pass its archive
to the installed verifier. Set `IPSE_ARCHIVE` to the exact file printed by the
packager for this host:

```sh
./scripts/package.sh
IPSE_ARCHIVE=/absolute/path/to/the-compatible-archive.tar.gz
elixir scripts/verify.exs installed model-service \
  --archive "$IPSE_ARCHIVE" --input "$IPSE_MODEL_PROOF/probe" \
  --output "$IPSE_MODEL_PROOF/installed"
```

Expect the same 21 synthetic cases with `verification.mode: "installed"`.
The common verifier compiles the two trusted proof modules before host launch.
Runner, HTTP and native execution use the selected package. The proof child's
PATH contains declared utilities and bundled Erlang, with no development commands.
Both modes retain case evidence under the chosen output and dispose their common
host runtime. On macOS both modes instead confirm refusal before effects.
This Rust service fixture is separate from the scripted per-cell daemon used by
the complete measured proof.

Trace `ModelService.run/3` through these ownership boundaries:

The public `run/3` contract remains available. Its internal `run/4` form accepts
an optional verified environment constructor. The guarded staging worker calls
that constructor once under the existing staging deadline. Launch and receipt
reuse the same admitted environment. The measured fixture selects this policy
before sealing and binds the required Environment BEAM; service control data
cannot switch verification off later.

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
`MeasuredExecution.native_receipt?/2` checks the corresponding
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
owns the exact descriptor layout, limits and evidence filenames. `MeasuredExecution` supplies the sealed schedule, original allocations
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

Follow `Inventory.snapshot/6` and the pure `Store.inventory/2` in the
independent knowledge artifact. The host validates the bounded, owner-only State
file and every record envelope through `State.valid_outcome?/4`. It checks the
namespace, version and generation sum. A separate VM loads the verified
artifact, public SDK and existing Jason runtime, then computes counts and opaque
hashes. The SDK validator needs Jason even when the audit itself uses Elixir JSON.
Captured measured inventory children use `precompiled_command/4` to verify
ordered code-path membership and inspected BEAM bytes. They load Environment,
enter its policy, load the inventory role and compile the fixed expression,
then add the verified artifact's `ebin` only in that child. `command/4` retains the
genuine source-compatibility branch; the `/5` inventory wrapper uses the v1
development Elixir launcher.
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
`Inventory.collection_requests/3`: it binds owner-only namespace bytes
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
