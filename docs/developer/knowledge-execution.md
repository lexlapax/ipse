# Trace a Knowledge comparison through public Sessions

The evaluator is development tooling, not an alternate Knowledge implementation.
It builds and admits independent artifacts, invokes their public commands through
Sessions, materializes complete results, and records immutable first outcomes.
The [runbook](knowledge-evaluation.md) owns setup and phase commands. This chapter
teaches the execution path and the evidence that a new strategy must preserve.

## Follow the code in execution order

| Owner under dev/evaluation | Responsibility |
| --- | --- |
| contract.exs | Pure validated plan and closed strategy declarations |
| runner.exs | Phase arguments, project/variant schedule, command approvals, first rows |
| session.exs | Public Session adapter, paging, complete results, cleanup acknowledgment |
| dataset.exs | Label-free inputs, typed source identity, later literal/reference joins |
| answer.exs | Pure evidence packing, exact model request, strict answer decoding |
| resources.exs | Canonical usage/budget reconciliation and measured coverage |
| inventory.exs | Isolated retained-store audit and exact collection approvals |
| measured_execution.exs | Sealed stage authority, captured launches, joined audit |

`dev/evaluate-knowledge.exs` loads verification Runtime and Scenarios, then enters
Runner. Runtime owns compilation/capture and cleanup. Pure `Contract.build/1`
loads no execution, fixture server, or model service. Inspect that boundary before
adding another convenience import. Installed execution must use the captured
closure rather than compile checkout sources on demand.

## Admit every selected command before reading inputs

Follow Runner's `preflight!/3`, `selection/4`, and `Session.preflight/1`.
Preflight imports exact artifacts/options, checks schemas and command catalogs,
and verifies that every binding has the correct command ID and owner.
Preparation requiring embeddings needs `index`; graph preparation needs `extract`;
answer generation needs `answer`. Similar argument shapes do not substitute owners.

Each selection starts an owned worker and initializes it. Knowledge readiness can
precede a deferred configuration error. The diagnostic therefore sends an empty
`invoke.command` directly to the worker and requires `invalid_invocation` from a
valid configuration. No returned host action executes and no inference dispatches.
The answer helper uses its ordinary schema/initialization checks. Every worker
requires confirmed native cleanup.

Measured preparation performs this admission only after sealed native authority.
It rechecks identities after preflight before opening any input. Version one
instead checks model inventory after selections; measured cells defer inventory
until their fresh model service has native listener admission. `preflight.json`
retains exact artifact/option/export hashes, catalogs, and the first failed variant.
A seal file or initialized worker is not proof of executable readiness.

```sh
mix test test/dev/evaluation/runner_test.exs
```

Change the last Research binding in its negative declaration, then add an unused
invalid retrieval profile. Both controls must refuse while corpus/query paths
still do not exist. The invalid profile can report readiness, but must fail option
validation with confirmed cleanup and zero inference. This proves ordering without
opening a private dataset.

## Project only questions and captured source bodies

After authority/catalog admission, Dataset opens at most 1 MiB per member with
Ipse's duplicate-key-rejecting JSON decoder. A sealed manifest names exactly corpus
and queries plus a pathless answer digest. Preparation never walks arbitrary
manifest members; an answer descriptor refuses. Legacy combined manifests keep
their historical recursive hashing behavior.

`queries/2` returns exactly `query_id`, `project`, and `query` in original order.
Relevance, classes, expected answers, and refusal labels stay out of Session/model
inputs. Excluded field names belong only in run metadata. Invalid or duplicate
rows refuse the complete input; the adapter never drops work to fit capacity.

`corpus/1` validates complete body hashes/lengths, UTF8, times, generation, and typed
version. All generations remain available for later citation verification.
`population/2` discards observations after the fixed as-of time and selects the
highest known generation per project/source. Ingest observed history in generation
order and apply explicit suppression before projections. Known suppression stays
permanent. A future replacement/tombstone cannot erase the earlier current view.
Exclude suppressed or expired selected versions from indexing, extraction,
Research gateway, and rerank admission. Record skipped projections.

`Dataset.sources/1` uses project/source/generation/typed version/body hash as its
lookup identity. Matching text or display labels alone cannot identify a version.
Authoring generates `dataset:PROJECT:DIGEST` URIs from raw SHA-256 over this ordered
JSON array:

```elixir
["dataset-source", 1, project, document_id, source_id, generation, version, body_sha256]
```

`citation_checks/2` recomputes literal half-open UTF8 spans from those source bytes.
Reference joins occur only after release; see [scoring](knowledge-scoring.md).

```sh
mix test test/dev/evaluation/dataset_test.exs
```

Change expected-answer/class/relevance fields in the legacy fixture. Question
projection must remain identical even if label validation later refuses. Change
one reference quote byte and verify `reference_checks/2` returns invalid while
question projection remains successful. These are separate boundaries.

## Follow one project and strategy cell

`Runner.schedule/2` orders fourteen cells by project and original variant order.
Each gets a fresh Session and its own fixed budget share. The measured cell owns
a new runtime/cache and daemon. Source authoring runs in a separate checked VM;
no domain package loads into the host. Captured children use
`MeasuredExecution.precompiled_command/4` with inspected BEAM paths and policy.

Trace `run_variant/9`, `prepare/4`, `invoke/4`, and `approve/1`:

1. Rebuild observed source history through public commands, including paging.
2. Prepare the declared index/extraction once and retain all public receipts.
3. Retrieve each question with fixed as-of time and the strategy's exact bindings.
4. Approve only the selected artifact, owner, profile, namespace, complete request,
   and egress. Bound embedding/text/search/fetch counts per invocation.
5. Materialize the complete result, prepare/approve the exact answer request,
   decode its first response, and save its row even on failure.
6. After all predictions for the cell are saved, suppress source copies, collect
   approved pages, close the Session/gateway, and reconcile canonical accounting.

State effects use the logical project namespace. Embedding/text use Session
identity. MCP effects have no State namespace. Do not normalize all three into a
single identity to simplify approval code. Follow an actual Research approval
through `Ipse.Extension.MCPCall` when changing this adapter.

Research fetches only URIs returned by that question's controlled search result,
each at most once. Its cell gateway has a nonrenewing allowance derived from
`query_count * (1 + max_sources)`. Fifty ten-source questions allow 550 calls.
Plans two/three divide this across separately owned cells; version one shares
one allowance. Direct callers default to 512 and may explicitly select 1..11264.
Invalid limits refuse before listening or input reads.

`gateway-calls.json` keeps bounded per-call metadata. `gateway-summary.json` counts
limit, recorded calls, rejected over-limit, and decoded requests. Excess requests
increment a counter without growing the log. Frames rejected before JSON dispatch
are outside it. Unknown tool values become `other`, not copied payloads.

```sh
mix test test/dev/evaluation/services_test.exs test/dev/evaluation/runner_test.exs
```

The 550-call fixture must refuse after exhaustion. The four-source runner case
checks exact approvals and maps a fetched capture's URI/body to current dataset
generation and typed version. Its repeated bodies and integer/string version
labels prevent a body-hash-only join. Scripted HTTP measures no model quality.

## Materialize before interpreting delivery

Read `record_invoked/9` and `complete_result/2` in the Session adapter. Inline output
already contains a domain value. SDK-2 `saved.result` output contains a delivery
descriptor, not a ranking. The driver calls `Ipse.Session.materialize_result/2`
with that exact descriptor before prediction, answer preparation, or measurement.

| Retained receipt field | Meaning |
| --- | --- |
| delivery | Original saved descriptor, or null for inline output |
| complete_result.byte_count / sha256 | Exact retained document identity |
| complete_result.bytes_base64 | Original complete bytes, without re-encoding |
| complete_result.provenance | historical_receipt, not current source eligibility |
| value | Complete decoded domain object or null |
| materialization_error | Read failure or null |
| failure_codes | Distinct classified Session errors in arrival order |

`result_sha256` binds displayed result text. For saved output this text describes
delivery; retain `complete_result.sha256` separately. A failed materialization
keeps delivery, sets value null, and fails the row. `completion_confirmed` still
reports whether the invocation committed its matching receipt. Unavailable bytes
do not erase known completion. No replacement retrieval/model request occurs.

```sh
mix test test/dev/evaluation/session_test.exs
```

Follow the result over 16 KiB, forged digest, and lost-source cases. The last
holds delivery, removes fixture readability, then releases completion. It must
retain one completed failed receipt and make no second command/model request.
The independently built package exercise is in
[Knowledge training](knowledge-extensions.md); historical reads never rerun current
eligibility policy.

## Preserve uncertain completion and paging failures

`ingest_paged/4` requires an open offset of zero. A wrong first offset retains its
receipt and submits no append/publish. `append_parts/6` requires the exact next
offset; a wrong response submits no publish. Confirmed command completion still
permits later explicit inspection.

A timed-out invocation with confirmed cancellation may permit a later read.
Killing the Session after worker start instead leaves intent without a result.
The adapter loads that original pinned Session journal, marks `unsettled`, and
refuses another invocation with `completion_unconfirmed` without dispatch or
journal changes. Close must remain unconfirmed. Process disappearance does not
replace the missing acknowledgment or settle provider liability.

For diagnosis, use the bounded metadata-only fixture probe:

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/dev/evaluation/session_test.exs test/ipse/runner/diagnostics_test.exs
```

It follows Session and task supervisors, samples at most 64 calls over 20 seconds,
and records arities, elapsed times, and classified returns without arguments or
payloads. A timeout establishes the deadline expired, not which component delayed.
Keep accidental timeouts separate from intended malformed-response controls.

Failure codes are at most `complete_result_deadline` and `session_error`. Raw
error text is excluded. A code authorizes no retry and cannot turn unknown work
into confirmed failure. The timer fixture injects the real timer message rather
than measuring 120 seconds of elapsed time; its privacy control must omit supplied
private arguments, results, and reasons.

## Pack and decode schema-bound answers

`Answer.prepare/3` is pure. It takes a query, as-of time, and at most ten ranked
candidates with complete citations. `/4` selects `json_schema_v2`; `/5` selects
`json_schema_v3` and its frozen longer deadline. It returns the complete approved
model request, shown context/IDs, coverage, and context SHA-256.

```elixir
Code.require_file("dev/evaluation/answer.exs")
{:ok, bundle} = Ipse.Development.Evaluation.Answer.prepare(
  "What does release require?", 1_800_000_000_000, [],
  "json_schema_v3", 480_000
)
3 = bundle["request"]["version"]
480_000 = bundle["request"]["timeout_ms"]
```

Run in `iex -S mix`. Empty evidence permits only abstention and no claims.
For nonempty input, the helper keeps the longest rank prefix whose exactly encoded
input fits 4096 bytes. Quotes retain full offsets/hash within the 1024-byte
citation limit. It never crops quotes further. One oversized early candidate can
exclude later short ones. Coverage lists every omission; this is not optimal
packing or proof that all contradictions reached the model.

The response schema derives only from shown IDs. Validation reconstructs it;
adding an omitted ID or another schema refuses. The model returns exactly
classification and claims, without a second independently written prose answer:

```json
{"classification":"answer","claims":[{"text":"Release requires a checksum manifest, except for local rehearsal copies.","citations":["e1"]}]}
```

Each claim has nonblank text at most 1024 UTF8 bytes and 1..10 unique shown IDs.
Unknown IDs, extra/duplicate fields, invalid UTF8, fences, trailing content, and
raw JSON over 8192 bytes refuse the whole first response. The host first validates
the approved schema; domain decoding additionally checks bytes and attribution.
A completed invalid response retains charged usage and raw text without repair.

| Classification | Claims | Derived material answer |
| --- | --- | --- |
| answer | 1..8 | Exact texts in order, joined by one LF |
| conflict | 1..8 | Same derivation; claims state positions and scope |
| open | 0..8 | Same derivation, or the fixed unresolved message when empty |
| abstain | none | Fixed cannot-answer-from-evidence message |

Changing classification cannot rewrite nonempty material claim texts. Empty open
or abstention can still be semantically wrong. A single source can contain a
conflict. Valid schema proves neither support nor completeness.

Prediction row two retains the full retrieval ranking in `evidence`.
`context_evidence` contains actually cited spans, not everything shown. Each must
be contained in an original ranked span with identical identity/bytes. Retrieval
metrics use the ranking. Do not substitute an answer excerpt to improve its score.
For visibility analysis inspect the saved preparation/packing coverage.

Claim IDs follow `c1`, `c2`; context IDs follow `a-e1`, `a-e2`. Two claims citing
one span retain separate pairs such as `pair1-1` and `pair2-1`. Claim text is not
deduplicated. Saved rows still contain derived answer and claims; old live model
responses with an `answer` field refuse, including null.

The driver forwards exact `%{"request" => request}` arguments for versions two/three.
Mixed historical/current argument forms refuse. It records complete request and
context hashes before dispatch. Extraction/rerank approval independently derives
the schema from checked input/source identities rather than importing a producer's
adapter as approval authority.

```sh
mix test test/dev/evaluation/answer_test.exs test/dev/evaluation/runner_test.exs --only answer_contract
```

The fixture checks invariant material text, distinct shared-span pairs, and a
failed first row with no answer/claims/retry. Full retrieval evidence remains.
Both prediction readers and scorer admit at most 64 MiB per/all prediction files,
256 KiB per JSONL row. Count JSON escapes and repeated identities. Review packet
limits are separately 32 MiB per file/64 MiB total; review JSON is 32 MiB and
manifest/dataset members remain 1 MiB. Preserve size-refused firsts; never drop rows.

## Reconcile requests, clocks, and stored copies

`persist_close/2` confirms owner cleanup, loads the journal, and restores canonical
usage with `Ipse.Usage.restore/2`. Export every request with `Usage.order/1` and
`request_record/1`; UI snapshots show only the latest sixteen. Context recovery
uses `Ipse.Session.restore_context/1` separately.

`Resources.reconcile_budget/4` attaches the existing saved ledger in inspection
mode under its lock. It checks exact request IDs/admissions/refusals and every
known historical peak, even if later counters decreased. It requires one root
and rejects extra child admissions. It neither grants authority nor renews work.
Live `Ipse.Usage.Budget.validate_sources/3` needs a live checkpoint; it is not this
saved-ledger inspection API.

| File | Inspect |
| --- | --- |
| usage.jsonl | Every canonical request and validated budget snapshot |
| request-resources.jsonl | Project/variant/source/query, invocation, admission, dispatch intent, settlement |
| timings.jsonl | Phase/invocation clocks, failed outcomes, unconfirmed completion |
| resource-summary.json | Coverage, role counts, latency percentiles, token availability, booked liability |

An attempt is not admission; admission/intent is not proof of remote acceptance.
Keep completed, failed, and unknown outcomes separate from settlement. Missing
tokens stay unknown. Embedding output tokens are not applicable. Without a rate
card work is unpriced. Booked liability is conservative admission accounting,
not an invoice. Read-only inspection remains available after quota exhaustion.

Inventory verifies owner-only bounded State envelopes and generation sums, then
loads the exact artifact/SDK/Jason in a separate checked VM. Domain modules stay
out of the host. It validates selected page hashes, partition/source/generation,
including repeated references before traversal is skipped. Missing or substituted
pages refuse. Draft pages are separate; aborted pages become orphans. Source
drafts bind old-source preconditions while `target.generation` owns new pages.

Snapshots precede ingestion and follow projections, preparation, every query,
suppression, and collection. Projection counts must match command timings.
The cache key includes exact file bytes/hash/path, artifact digest, and partition.
Unchanged reads may reuse verified inventory. Missing storage is explicit absence;
corrupt/unavailable storage remains incomplete. No source text returns and inventory
must never become retrieval/model input. Record values/encoded envelopes and actual
file bytes are separate measurements.

After predictions, inspect/suppress every active root. Collection requires a
verified unchanged owner-only file, every selected root suppressed, and no draft.
Only exact project page keys/revisions enter once-only approvals, in batches of
at most twelve and at most twenty-two batches for 256 slots. Final inventory needs
no orphan pages and unchanged slot count. Tombstones keep revisions/slots and
have no value from which to infer partition ownership. Collection is neither
transcript erasure nor slot recovery. No later quality query runs on those copies.

```sh
mix test test/dev/evaluation/resources_test.exs test/dev/evaluation/inventory_test.exs test/extensions/knowledge/store_test.exs
```

Trace the 31-request runner control beyond UI/ordinary-step defaults, then its
one-request budget with two attempts/one dispatch/one refusal. Remove an earlier
60-token peak followed by seven and require reconciliation refusal. For inventory,
corrupt a referenced hash, generation sum, file mode, active root, retained draft,
or stale revision. Each must refuse metadata/collection admission while preserving
selected content and failed prediction rows.

## Check an exposed answer before private freezing


Use a built source checkout, the answer artifact and the reviewed version-three
`resolution.json` from the [runbook](knowledge-evaluation.md). Prepare `plan.json` with the extended-answer profile you
intend to measure. This exercise uses one public checksum statement. Replace its
query and citation with representative exposed evidence when checking prompt fit.
Never use private questions or reference answers for this step. One small prompt
checks the route and context admission; it cannot establish the largest prompt's
headroom or held-out quality.

Choose a fresh output outside the checkout. Save this trusted driver there, then
run it from the repository root. It approves only the exact answer-helper request,
starts one fresh owned daemon, invokes the public Session once and saves its
first result, accounting and cleanup. It downloads nothing and performs no main
conversation request.

```sh
IPSE_PREFLIGHT=$(mktemp -d)
cat > "$IPSE_PREFLIGHT/probe.exs" <<'ELIXIR'
for file <- ~w(answer model_service session),
  do: Code.require_file("dev/evaluation/" <> file <> ".exs", File.cwd!())
defmodule ContextProbeNoMain do
  def complete(_, _, _, _), do: raise("unexpected main inference")
end
alias Ipse.Development.Evaluation.{Answer, ModelService, Session}
alias Ipse.Extension.{Manifest, ModelCall}
[benchmark, root] = System.argv()
plan = File.read!(Path.join(benchmark, "plan.json")) |> JSON.decode!()
resolution = File.read!(Path.join(benchmark, "resolution.json")) |> JSON.decode!()
service = resolution["model_service"]
profile = plan["profiles"]["p27_answer"]
3 = service["version"]
true = service["origin"] == profile["base_url"]
true = service["context_tokens"] > profile["max_output_tokens"]
timeout = profile["model_call_timeout_ms"]
true = is_integer(timeout) and timeout in 120001..600000
save = fn name, value ->
  path = Path.join(root, name)
  File.write!(path, JSON.encode!(value) <> "\n", [:exclusive, :sync])
  File.chmod!(path, 0o600)
end
quote = "A release includes its checksums."
hash = &Ipse.JSON.sha256/1
citation = %{
  "version" => 1, "source_id" => "manual-source", "source_key" => hash.("manual-source"),
  "generation" => 1, "content_sha256" => hash.(quote), "chunk_id" => hash.("manual-chunk"),
  "start_byte" => 0, "end_byte" => byte_size(quote), "quote" => quote,
  "quote_sha256" => hash.(quote), "uri" => "provided:context-probe",
  "observed_at_ms" => 1000, "event_at_ms" => nil,
  "origin" => %{"kind" => "provided", "ledger_class" => "open"}
}
{:ok, bundle} = Answer.prepare("What does a release include?", 1000,
  [%{"citation" => citation}], "json_schema_v3", timeout)
artifact_path = plan["artifacts"]["answer"]
artifact_bytes = File.read!(Path.join(artifact_path, "extension.json"))
{:ok, artifact} = Manifest.decode(artifact_bytes)
digest = hash.(artifact_bytes)
trust = %{"artifact" => digest, "capabilities" => artifact["capabilities"],
  "allow_project" => false, "allow_children" => false}
reserve = service["context_tokens"]
cap = profile["max_output_tokens"]
runtime = %{
  provider: :ollama, model: "no-main", provider_module: ContextProbeNoMain,
  compact: false, max_steps: 2, timeout_ms: timeout,
  profiles: %{"p27_answer" => profile},
  budget: %{"version" => 1, "max_requests" => 1, "max_input_tokens" => reserve,
    "max_output_tokens" => cap, "reserve_input_tokens" => reserve, "reserve_output_tokens" => cap}
}
approval_runtime = Map.put(runtime, :extensions,
  [%{identity: %{"capabilities" => artifact["capabilities"]}}])
approve = fn review ->
  proposed = review.proposed
  true = review.verb == "answer" and ModelCall.delegated_approval?(review.name, proposed)
  true = proposed["extension"] == "answer" and proposed["artifact_sha256"] == digest
  true = proposed["namespace"] == Process.get(:context_probe).session_id
  true = proposed["request"] == bundle["request"]
  {:ok, selected, execution} = ModelCall.prepare(approval_runtime, bundle["request"])
  {:ok, destination} = Ipse.Provider.destination(selected)
  true = proposed["execution"] == execution and proposed["destination"] == destination
  {:approve, %{name: review.name, proposed: proposed}}
end
save.("prepared.json", bundle)
result = ModelService.run(service, Path.join(root, "service"), fn ->
  {:ok, run} = Session.open(%{
    root: root, project: "exposed", variant: "context-probe", runtime: runtime,
    artifacts: [%{instance: "answer", path: artifact_path, digest: digest,
      options: %{}, order: 0, trust: trust}],
    bindings: %{"answer" => %{"instance" => "answer", "id" => "complete"}},
    required_verbs: ["answer"], timeout_ms: timeout + 60000, approval_validator: approve
  })
  Process.put(:context_probe, run)
  try do
    invoked = Session.invoke(run, "answer", %{"request" => bundle["request"]})
    {status, receipt, next} = invoked
    Process.put(:context_probe, next)
    first = if status == :ok, do: receipt,
      else: %{"error" => inspect(receipt), "receipt" => List.last(next.receipts)}
    save.("first-result.json", %{"status" => to_string(status), "result" => first})
    {:ok, snapshot} = Session.snapshot(next)
    save.("accounting.json", snapshot["accounting"])
    {:ok, receipt, _} = invoked
    {:ok, decoded} = Answer.decode_answer(receipt["value"]["value"]["text"], bundle)
    save.("decoded.json", decoded)
    :passed
  after
    closed = Session.close(Process.get(:context_probe))
    save.("close.json", %{"status" => to_string(elem(closed, 0)), "receipt" => elem(closed, 1)})
    {:ok, _} = closed
  end
end)
save.("service-receipt.json", result.receipt)
{:returned, :passed} = result.work
:ok = ModelService.verify_receipt(service, Path.join(root, "service"), result.receipt)
IO.puts(JSON.encode!(%{"status" => "passed", "context_tokens" => service["context_tokens"],
  "resident" => result.receipt["inventory_after"]["resident"], "quality_measured" => false}))
ELIXIR
mix run "$IPSE_PREFLIGHT/probe.exs" "$IPSE_BENCHMARK" "$IPSE_PREFLIGHT"
```

Expect `status: "passed"`, the selected completion model's exact `context_length`,
`close.json` status `ok` and confirmed native/staging cleanup in the service receipt.
Inspect `accounting.json` for the completed request's input/output counts and finality.
The decoded file establishes schema and citation mapping, not semantic support.
For larger exposed prompts, compare total tokens with context and retain every
first outcome. A wrong context, failed decode, unknown request or unconfirmed
cleanup blocks private freezing. Preserve its directory and diagnose it before
starting a separately authorized diagnostic in another fresh output. Never rerun
this driver into its existing service directory.
