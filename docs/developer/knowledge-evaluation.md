# Prepare and run a frozen Knowledge comparison

Use this runbook to compare seven Knowledge strategies through public Ipse
Sessions. Freeze the implementation, model policy, workload commitment, budgets,
and qualification rule before revealing private inputs. Retain every first outcome,
including failures. The measured path runs on the optional Linux cgroup backend;
ordinary Ipse use does not require it.

This chapter owns setup and phase commands. Continue with
[execution and evidence](knowledge-execution.md),
[semantic review and scoring](knowledge-scoring.md), and
[measurement and ownership](measurement.md) when changing those implementations.
Keep actual acceptance results in dated archive records and status in the plan.
A synthetic protocol proof cannot qualify model quality.

## Assign custody before creating a workload

An independent author prepares a new 50-question workload across two projects.
Before code and configuration freeze, share only a metadata commitment. Keep
corpus, questions, and answers unavailable to the implementation team. After
freezing, install the committed corpus and questions. Release answers only after
all first predictions, execution evidence, and the required post-exit audit are
frozen. Hashes commit bytes; author identity and custody records explain who
handled them. Hashes cannot prove that nobody disclosed the data elsewhere.

The author creates three UTF8 JSON files, each at most 1 MiB. A complete source
row has this form:

```json
{"schema_version":1,"documents":[{"document_id":"d1","project":"alpha","source_id":"source:one","generation":1,"version":1,"title":"Fixture","text":"A café.","created_at":"2026-01-01T00:00:00Z","observed_at":"2026-03-01T00:00:00Z","state":"current","sha256":"17279f71f4ea96992036469e0ac54aebc728033c129e8a52dc7dddfbd9e3b8d3","byte_length":8,"media_type":"text/plain; charset=utf-8"}]}
```

Every shown document field is required. The corpus allows at most 256 documents.
Project names begin with a lowercase ASCII letter and contain at most 64 lowercase
letters, digits, underscores, or hyphens. Bounds in UTF8 bytes are 128 for document
ID/title, 256 for source ID, 65536 for text, 64 for state, and 128 for media type.
All are nonempty. Generation is a positive safe integer. Version is a positive
safe integer or nonempty string of at most 64 bytes. Times are ISO8601 with
nonnegative epoch milliseconds. Project/source/generation identities are unique.

Questions contain no expected answers or relevance labels:

```json
{"contract":"sealed_answers_v1","split":"heldout","queries":[{"query_id":"q1","project":"alpha","query":"What must precede release?"}]}
```

Answers use a separate closed envelope:

```json
{"contract":"sealed_answers_v1","split":"heldout","commitment_nonce":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","answers":[{"query_id":"q1","project":"alpha","expected_class":"open","expected_refusal":false,"expected_answer":null,"relevance":[]}]}
```

These one-row illustrations are too small for the author validator. Generate a
real private nonce once with
`Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)`. The repeated `a` value
is only an example. Keeping the nonce private prevents guessing a small answer
set against the published file hash; it does not replace custody.

Every relevance entry has exactly `source`, `grade`, `start_byte`, `end_byte`, and
`quote`. Source contains exactly `project`, `source_id`, `generation`, typed
`version`, and `sha256`. Half-open UTF8 byte coordinates and quote must match the
complete captured source. Integer `1` and string `"1"` are different versions.

In the author's environment, place corpus and questions beside the intended
manifest, then validate the complete workload:

```sh
mix run dev/prepare-knowledge-dataset.exs -- \
  --corpus /author/public/corpus.json --queries /author/public/queries.json \
  --answers /author/escrow/answers.json --as-of-ms 1800000000000 \
  --output /author/public/manifest.json
```

Expect an ok receipt with `manifest_sha256`, `answers_sha256`, `query_count: 50`,
and `project_count: 2`. It prints no question, answer, source, class, or nonce.
The exclusive owner-only manifest names only corpus and queries plus a pathless
answer hash. Failure prints `invalid_dataset_or_output`; inspect private inputs
in the author's environment. Do not regenerate committed answers after predictions.

## Build the seven artifacts outside measured execution

Build Ipse first with `./dev/build.sh`. Keep the selected repository clean,
including untracked files, and create artifacts in a fresh private directory.
Artifact construction starts no model and does not import/trust the output:

```sh
IPSE_BENCHMARK=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/lexical" --package corpus --preset state-lexical
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/dense" --package corpus --preset state-dense
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/semantic" --package corpus --preset state-semantic
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/explicit" --package graph --preset state-explicit
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/model" --package graph --preset state-model
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/research" --package research --preset mcp
elixir dev/build-artifact.exs model-calls --sdk _build/dev/lib/ipse/ebin --output "$IPSE_BENCHMARK/artifacts/answer"
cp dev/evaluation/benchmark-spec.json "$IPSE_BENCHMARK/spec.json"
```

Review the private template. It selects lexical, explicit graph, model graph,
dense, hybrid, rerank, and Research strategies, each with the same answer helper.
The example model names/digests and budgets require review for the authorized run.
There is no download or provider fallback. The exposed template workload uses
historical combined data and is suitable for tuning or reproduction only.

For a new workload, select plan three, one private IPv4-loopback model origin,
detached answers, and individual strategy qualification. This conversion reads
only the private specification:

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

Replace the illustrative repeated `f` hash with the author's independently
retained manifest hash. The data contract also retains `corpus: "corpus.json"`,
`split: "heldout"`, and `expected_queries: 50` from the template.
All text and embedding profiles must use the same selected origin. The shared
model port 11434 is forbidden for measured execution. The search port must differ.

## Fix answer and budget policy before generating a plan

Plan three requires this closed contracts object:

```json
{"outputs":{"answer":"json_schema_v2","extract":"json_schema_v2","rerank":"json_schema_v2"},"selection":"per_strategy_eligibility_v1"}
```

For longer final answers, change only `outputs.answer` to `json_schema_v3`.
Set `p27_answer.model_call_timeout_ms` in 120001..600000,
`p27_answer.max_output_tokens` to 8192, omit its `reasoning_effort`, and set every
variant's output reservation to 8192. Review aggregate output-token budgets too.
Keep extraction and rerank at 4096 tokens with explicit reasoning `none` and no
extended deadline override. Knowledge SDK-2 calls retain their two-minute limit;
the SDK-1 answer helper supports the separate longer call.

Each real-model cell checks the pinned model's `thinking.default: true` and support
for both thinking selections. Omitting a setting alone does not prove the backend
default. Longer deadlines and valid JSON establish no factual support.

Budgets are finite admission limits, not predicted consumption or prices.
The template uses 1024 baseline requests or 8192 for inference-heavy preparation,
with token caps equal to request cap times reservation. The runner divides every
cap across the original two projects, rounding down. Unused shares never transfer
or renew. Each Session's inference-step limit is its request share plus one, so
the next attempted request can reach canonical refusal accounting. Both text and
embedding calls consume that allowance.

`storage_policy: "forget_all_then_collect_v1"` explicitly suppresses isolated
source copies and collects unreferenced pages after predictions. It uses the same
Session and budget. Research has no retained source store. Review this policy
before freezing; original corpus and prediction evidence remain retained.

Generate the private plan after reviewing all selections:

```sh
mix run dev/prepare-knowledge-evaluation.exs -- \
  --spec "$IPSE_BENCHMARK/spec.json" --output "$IPSE_BENCHMARK/plan.json" --new-blind-seed
```

Expect an ok receipt, path/hash, and seven variants. The null input seed becomes
a fresh private seed, never printed. It blinds review ordering, not inference.
Artifact paths resolve relative to the specification. Existing output refuses.
This step opens no dataset/artifact or model service. Install the committed
manifest, corpus, and questions only at the agreed post-freeze boundary; answers
remain elsewhere.

## Bind a fresh service and local output paths

The local resolution has exactly six keys: `artifacts`, `model_origin`,
`search_port`, `reports`, `data_manifest`, and `model_service`. Model service origin,
model map, device policy, and context must match the experiment. Sealing does not
prove a port is available or owned.

Choose a nonrenewing service lifetime for the whole project/strategy cell,
including staging, readiness, inventory, ingestion, projections, all queries,
answers, suppression/collection, close, and final inventory. The maximum is
86400000 ms per cell. Twenty-five 600-second answers alone permit 4 hours
10 minutes; a request deadline is not a cell budget. Exposed prompt duration is
a diagnostic, not a forecast. Filesystem work has no separately proved elapsed
bound and coordinator waits can exceed the SDK deadline. Agree the overall run
limit before sealing. An early stop retains an incomplete comparison.

Select a reviewed existing runtime distribution and model cache. This example
requires `bin/ollama` and complete regular `lib/ollama` files, hashes the runtime,
and downloads nothing. It does not borrow a running daemon:

```sh
export IPSE_BENCHMARK
export IPSE_DATA_MANIFEST=/absolute/path/to/reviewed/dataset/manifest.json
export IPSE_OLLAMA_RUNTIME=/absolute/path/to/reviewed/ollama-distribution
export IPSE_OLLAMA_MODELS=/absolute/path/to/existing/ollama-models
# Example maximum allowance per cell. Record the chosen budget before sealing.
export IPSE_MODEL_CELL_LIFETIME_MS=86400000
mix run -r dev/evaluation/model_service.exs -e '
root = System.fetch_env!("IPSE_BENCHMARK")
plan = JSON.decode!(File.read!(Path.join(root, "plan.json")))
{:ok, runtime} = Ipse.Workspace.canonical_path(System.fetch_env!("IPSE_OLLAMA_RUNTIME"))
{:ok, cache} = Ipse.Workspace.canonical_path(System.fetch_env!("IPSE_OLLAMA_MODELS"))
files = [Path.join(runtime, "bin/ollama") | Path.wildcard(Path.join(runtime, "lib/ollama/**/*"))]
files = for path <- Enum.sort(files), File.lstat!(path).type != :directory do
  {:ok, ^path} = Ipse.Workspace.canonical_path(path)
  %{type: :regular, size: size, mode: mode} = File.lstat!(path)
  digest = File.stream!(path, 1_048_576, []) |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1)) |> :crypto.hash_final() |> Base.encode16(case: :lower)
  %{"source" => path, "path" => Path.relative_to(path, runtime), "bytes" => size,
    "sha256" => digest, "executable" => Bitwise.band(mode, 0o111) != 0}
end
models = plan["models"]
service = %{
  "version" => 3, "origin" => "http://127.0.0.1:47631", "models" => models,
  "manifests" => Map.new(models, fn {name, _} ->
    [model, tag] = String.split(name, ":", parts: 2)
    {name, "manifests/registry.ollama.ai/library/" <> model <> "/" <> tag}
  end),
  "cache_source" => cache,
  "runtime" => %{"executable" => "bin/ollama", "files" => files},
  "limits" => %{"ready_ms" => 60000,
    "lifetime_ms" => String.to_integer(System.fetch_env!("IPSE_MODEL_CELL_LIFETIME_MS")),
    "metadata_ms" => 10000},
  "device_selection" => %{"policy" => "cpu_only"},
  "context_tokens" => 16384
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
```

This creates a CPU selection with explicit context. For an authorized GPU run,
check `nvidia-smi -L` and replace the selection before declaration:

```sh
# Replace this placeholder with the complete UUID from nvidia-smi -L.
export IPSE_MODEL_GPU_UUID='GPU-REPLACE-WITH-THE-REPORTED-UUID'
mix run -r dev/evaluation/model_service.exs -e '
path = Path.join(System.fetch_env!("IPSE_BENCHMARK"), "resolution.json")
resolution = JSON.decode!(File.read!(path))
service = resolution["model_service"] |> Map.merge(%{
  "device_selection" => %{
    "policy" => "nvidia_visible_mixed_v1",
    "uuid" => System.fetch_env!("IPSE_MODEL_GPU_UUID")
  }
})
:ok = Ipse.Development.Evaluation.ModelService.validate(service)
File.write!(path, JSON.encode!(Map.put(resolution, "model_service", service)))
'
```

Use one complete physical `GPU-` UUID with canonical lowercase hexadecimal groups.
Indices, abbreviations, MIG IDs, lists, and extra fields refuse. The policy permits
partial CPU/GPU placement. Every final resident model must report positive VRAM;
an embedding model cannot mask a resident CPU-only answer model. CPU policy hides
accelerators and requires integer-zero final VRAM. Neither final snapshot proves
continuous placement or peaks. ROCm, Vulkan, and cloud models stay disabled.

`context_tokens` accepts 1..1048576. Extended-answer declarations require it to
exceed every text output allowance. That cannot prove prompt fit. Run the
[exposed answer exercise](knowledge-execution.md#check-an-exposed-answer-before-private-freezing)
with exact model, reasoning, output, and context settings before private freezing.
Inspect actual loaded context and every first result. A failed decode, unknown
request, wrong context, or unconfirmed cleanup blocks freezing.

## Declare portable policy and seal one execution

A declaration retains content identities, blind seed, device/context policy, and
measurement recipe. It removes artifact/source paths, origins, and search port.
The local seal adds exact paths, runtime bytes, GPU UUID, ports, and registry
identity. A UUID change needs a fresh local seal; a context/device-policy change
also needs a fresh declaration. No hostname or kernel-version allowlist is implied.

Store phase receipts separately from authoritative freeze and report data:

```sh
IPSE_RETAINED=$(mktemp -d)
mix run dev/evaluate-knowledge.exs -- --phase declare \
  --plan "$IPSE_BENCHMARK/plan.json" \
  --resolution "$IPSE_BENCHMARK/resolution.json" \
  --output "$IPSE_BENCHMARK/experiment.json" \
  > "$IPSE_RETAINED/declaration.json"
IPSE_EXPERIMENT_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["sha256"])' "$IPSE_RETAINED/declaration.json")
elixir dev/evaluate-knowledge.exs --phase freeze-measured \
  --sdk _build/dev/lib/ipse/ebin --repository "$PWD" \
  --experiment "$IPSE_BENCHMARK/experiment.json" \
  --experiment-sha256 "$IPSE_EXPERIMENT_SHA256" \
  --resolution "$IPSE_BENCHMARK/resolution.json" \
  --output "$IPSE_BENCHMARK/frozen-measured" \
  > "$IPSE_RETAINED/freeze.json"
IPSE_FREEZE_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["sha256"])' "$IPSE_RETAINED/freeze.json")
```

Both receipts must report ok. Keep the printed hashes separately. The selected
repository must remain clean and fixed. Use creation-only `--archive` instead of
`--sdk` for a compatible installed host; later phases reject these options.
Keep `frozen-measured.runtime/runtime` beside the seal throughout execution,
audit, and scoring. It is a retained local evaluator, not a portable runtime archive.
Changed/missing captures refuse instead of compiling current checkout replacements.

Reports must be fresh, disjoint from the freeze, and must not contain the source
checkout. An ignored directory within the checkout is permitted. Sealing binds
its fixed attempts registry, source, plan, artifacts, launch, full service
selection, and finite semantic recipe. It starts no worker, model, dataset read,
or weight read. Measurement authority is neither relocatable nor renewable.

For service allowance `L` ms, each cell gets `L + 30000`; the measured root gets
`14 * (L + 30000) + 498000`. Preparation/finalization each receive 180000 ms.
At the 24-hour cell-service maximum the root allocation is 14 days, 15 minutes,
18 seconds. These are upper allocations, not runtime predictions. Capture and
controller work precede the root clock. See [measurement](measurement.md).

## Execute once and audit after natural closure

Run only the already reviewed workload represented by the seal:

```sh
elixir dev/evaluate-knowledge.exs --phase measure \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" \
  > "$IPSE_RETAINED/measure.json"
elixir dev/evaluate-knowledge.exs --phase audit \
  --freeze "$IPSE_BENCHMARK/frozen-measured/manifest.json" \
  --freeze-sha256 "$IPSE_FREEZE_SHA256" \
  > "$IPSE_RETAINED/audit.json"
IPSE_AUDIT_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["sha256"])' "$IPSE_RETAINED/audit.json")
IPSE_PREDICTION_SHA256=$(elixir -e 'r = File.read!(hd(System.argv())) |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(); IO.puts(r["result"]["prediction_sha256"])' "$IPSE_RETAINED/audit.json")
```

Retain successful closed measure/audit CLI phases and the complete joined audit
before releasing labels. A finalizer cannot observe its future outer root receipt;
post-exit audit supplies that check. The audit joins native scope/claim identity,
root and stage frames, service cleanup, receipts, domain files, all first
predictions, and six merged streams. A receipt viewed alone is insufficient.
Audit is read-only and repeatable. A second measure must refuse.

Missing owner, collector, stage, or completion evidence remains unknown. A later
clean process list cannot prove no request dispatched. Never delete claims,
clear `unsettled`, replace first outcomes, repair receipts in place, or create a
new budget root to continue the same execution. Finalization preserves failures
and fills missing work explicitly so the complete 50-by-seven grid has 350 rows.
Continue with [independent scoring](knowledge-scoring.md) after the release gate.

## Prove the workflow with synthetic data first

On a supported Linux backend, reuse the seven prebuilt artifacts above and create
an absolute artifact map:

```sh
elixir -e '
[root] = System.argv()
map = Map.new(~w(answer dense explicit lexical model research semantic),
  &{&1, Path.expand(Path.join([root, "artifacts", &1]))})
File.write!(Path.join(root, "artifacts.json"), JSON.encode!(map), [:exclusive])
' "$IPSE_BENCHMARK"
elixir dev/verify.exs source measured-knowledge \
  --sdk _build/dev/lib/ipse/ebin --repository "$PWD" \
  --input "$IPSE_BENCHMARK/artifacts.json" \
  --output "$IPSE_BENCHMARK/synthetic-source" --selection sealed-structured
```

Expect `synthetic: true`, `model_quality_measured: false`, 350 first rows, complete
execution/resource audits, and a scoring control `unmeasured_quality_refused`.
The scripted daemon loads no weights. The proof checks exact schemas, approved
requests, source exclusions, canonical counts, read-only audit, consumed-seal
refusal, tampering, and pre-label admission. Inspect retained `runtime` and `run`
subdirectories, including `freeze`, `reports`, and `scoring-controls`.

Use fresh outputs for these closed selections:

| Selection | Exercised policy |
| --- | --- |
| sealed-structured | Plan three, detached answers, schema-bound answer/extract/rerank |
| sealed-long-answers | Longer final answers, explicit 16384 context, 24-hour service allocation |
| sealed-gpu-answers | Same longer answers with scripted NVIDIA visibility/residency |
| structured | Plan three, historical combined fixture data |
| sealed | Plan two, detached answers |
| default | Plan two, combined fixture data |

The long-answer server replies promptly. This checks multi-day timeout admission
and natural completion, not days of elapsed execution. The GPU fixture needs no
physical GPU and proves no real placement or peak VRAM. Bound the synthetic proof
job independently and retain stalled/failed evidence.

For an installed proof, build a compatible package and use its exact printed path:

```sh
./dev/package.sh
IPSE_ARCHIVE=/absolute/path/to/the-compatible-archive.tar.gz
elixir dev/verify.exs installed measured-knowledge \
  --archive "$IPSE_ARCHIVE" --repository "$PWD" \
  --input "$IPSE_BENCHMARK/artifacts.json" \
  --output "$IPSE_BENCHMARK/synthetic-installed" --selection sealed-structured
```

The verifier compiles the trusted proof closure before launch. The installed host
runs captured BEAMs and bundled ERTS without development tools on runtime PATH.
The clean source checkout remains a declared input. See
[compiler and execution ownership](testing.md#follow-compilation-and-runtime-ownership).
A package proof establishes the exercised archive/host protocols, not real model
quality or every ownership-loss case.

## Recognize compatibility paths

Plans one/two preserve historical closed fields and reject the new `contracts`.
Plan three fixes output contracts and per-strategy qualification. Explicit-context
experiments use version three; historical automatic-context experiments use two.
Measured seals are version two, prediction rows/review envelopes two, scoring
declarations three, score reports two, and metric definitions one. An old seal
cannot acquire new qualification policy from changed labels or a score command.

Version-one source freezes keep their original identity/prediction route and
full source/runtime checks. Public `--phase freeze` retains Research's two compiled
gateway modules beside the seal. A missing historical gateway refuses with
`research_fixture_missing`; reopening never compiles a replacement. Source seals
are not installed-runtime attestations. Direct `Freeze.create/4` is an inert
identity operation and not a complete comparison declaration.

Exposed tuning uses a version-one tuning plan, numeric as-of time, tuning split,
and one explicit shared loopback origin in every text/embedding profile. It starts
no daemon and falls back nowhere:

```sh
mix run dev/evaluate-knowledge.exs -- --phase tune \
  --plan /absolute/path/to/tuning-plan.json \
  --corpus /absolute/path/to/exposed-corpus.json \
  --queries /absolute/path/to/exposed-queries.json \
  --output /absolute/path/to/fresh-tuning-results
```

Catalog and model inventory admission precede input reads. Preserve first failures.
Exposed tuning cannot become a fresh held-out result. Run plan/runner/freeze tests
before changing declaration, custody, or compatibility behavior:

```sh
mix test test/dev/evaluation/plan_test.exs test/dev/evaluation/runner_test.exs test/dev/evaluation/freeze_test.exs
```
