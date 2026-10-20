# Pure synthetic capacity evidence. No private data, inference, service or native calls.
# Usage: elixir /tmp/ipse-p27-review-capacity-probe.exs /absolute/path/to/ipse
repo =
  case System.argv() do
    [path] -> Path.expand(path)
    [] -> File.cwd!()
    _ -> raise "usage: elixir review-capacity-probe.exs [REPOSITORY_ROOT]"
  end

for relative <- ["examples/knowledge/evaluation_review.exs", "examples/knowledge/evaluation_answer.exs",
                 "extensions/knowledge/src/evidence.ex", "lib/ipse/json.ex"] do
  unless File.regular?(Path.join(repo, relative)), do: raise("missing source: #{relative}")
end

# Reuse the checkout's already-built, locked dependency/runtime modules. Installs nothing.
paths = Path.wildcard(Path.join(repo, "_build/dev/lib/*/ebin"))
if paths == [], do: raise("build this checkout before running the pure probe")
Code.prepend_paths(paths)
Code.require_file(Path.join(repo, "examples/knowledge/evaluation_review.exs"))
Code.require_file(Path.join(repo, "examples/knowledge/evaluation_answer.exs"))
Code.require_file(Path.join(repo, "extensions/knowledge/src/evidence.ex"))
sha = fn bytes -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) end
body = "word evidence"
variants = ~w(lexical graph_explicit graph_model dense hybrid rerank research)
queries = for number <- 1..50, do: %{"query_id" => "q#{number}",
  "project" => if(number <= 25, do: "alpha", else: "beta")}
rows = for variant <- variants, query <- queries do
  evidence = for number <- 1..10 do
    %{"span_id" => "r#{number}", "source" => %{"project" => query["project"],
      "source_id" => "source#{number}", "generation" => 1, "version" => 1,
      "sha256" => sha.(body)}, "start_byte" => 0, "end_byte" => byte_size(body), "quote" => body}
  end
  context = for {span, number} <- Enum.with_index(evidence, 1),
    do: Map.put(span, "span_id", "a-e#{number}")
  claims = for number <- 1..8, do: %{"claim_id" => "c#{number}", "text" => "Evidence is present."}
  pairs = for claim <- 1..8, span <- 1..10, do: %{"citation_id" => "pair#{claim}-#{span}",
    "claim_id" => "c#{claim}", "span_id" => "a-e#{span}"}
  %{"version" => 2, "prediction_id" => "p-" <> sha.(variant <> query["query_id"]),
    "variant" => variant, "query_id" => query["query_id"], "project" => query["project"],
    "attempt" => 1, "status" => "ok", "top_k" => 10, "predicted_class" => "answer",
    "response_kind" => "answer", "answer" => "Evidence is present.", "claims" => claims,
    "evidence" => evidence, "context_evidence" => context, "citations" => pairs}
end
bytes = Enum.map_join(rows, "\n", &JSON.encode!/1) <> "\n"
freeze = %{"version" => 1, "metric_version" => 1, "variants" => variants,
  "baseline" => "lexical", "queries" => queries,
  "files" => [%{"id" => "predictions", "sha256" => sha.(bytes)}],
  "classification_map" => Map.new(~w(answer conflict open abstain), &{&1, &1})}
documents = for project <- ["alpha", "beta"], number <- 1..10 do
  %{"document_id" => "#{project}-#{number}", "project" => project, "source_id" => "source#{number}",
    "generation" => 1, "version" => 1, "title" => "Synthetic", "text" => body,
    "created_at" => "2026-01-01T00:00:00Z", "observed_at" => "2026-01-01T00:00:00Z",
    "state" => "current", "sha256" => sha.(body), "byte_length" => byte_size(body),
    "media_type" => "text/plain"}
end
reference_queries = Enum.map(queries, &Map.merge(&1, %{"query" => "word", "split" => "synthetic",
  "expected_class" => "answer", "expected_refusal" => false, "relevance" => [],
  "expected_answer" => "Evidence"}))
context = %{"as_of_ms" => 1, "split" => "synthetic",
  "corpus" => JSON.encode!(%{"schema_version" => 1, "documents" => documents}),
  "queries" => JSON.encode!(%{"schema_version" => 1, "queries" => reference_queries})}
{:ok, packet} = IpseKnowledgeExample.EvaluationReview.prepare(freeze, %{"predictions" => bytes},
  fn -> {:ok, context} end, sha.("synthetic"))
review = packet["files"]["reviews-template.json"]
350 = packet["summary"]["rows"]
true = byte_size(review) > 1_048_576 and byte_size(review) < 33_554_432
{:error, :invalid_json} = Ipse.Extensions.Manifest.decode_json(review, 1_048_576)
{:ok, _} = Ipse.JSON.decode_unique(review)

# Separately establish that the exact matched helper permits this row's pair counts.
candidates = for number <- 1..10 do
  {:ok, source} = IpseKnowledge.Evidence.source(%{"source_id" => "source#{number}",
    "partition" => "manual", "generation" => 1, "title" => "Synthetic", "text" => body,
    "uri" => "dataset:synthetic:#{number}", "observed_at_ms" => 1, "event_at_ms" => nil,
    "expires_at_ms" => nil, "origin" => %{"kind" => "provided", "store_profile" => "notes",
      "partition_or_scope" => "manual", "receipt" => nil, "historical" => false}})
  {:ok, [chunk]} = IpseKnowledge.Evidence.chunks(source)
  {:ok, citation} = IpseKnowledge.Evidence.citation(source, chunk, 0, byte_size(body))
  %{"citation" => citation, "score" => 1.0, "method" => "bm25"}
end
{:ok, bundle} = IpseKnowledgeExample.EvaluationAnswer.prepare("word", 1, candidates)
ids = for number <- 1..10, do: "e#{number}"
claims = for _ <- 1..8, do: %{"text" => "Evidence is present.", "citations" => ids}
response = JSON.encode!(%{"classification" => "answer", "answer" => "Evidence is present.", "claims" => claims})
{:ok, decoded} = IpseKnowledgeExample.EvaluationAnswer.decode_answer(response, bundle)
10 = length(bundle["shown"])
8 = length(decoded["claims"])
80 = Enum.sum(for claim <- decoded["claims"], do: length(claim["citations"]))
true = byte_size(bundle["request"]["input"]) <= 4096 and byte_size(response) <= 8192
source_hashes = Map.new([
  "examples/knowledge/evaluation_review.exs", "examples/knowledge/evaluation_score.exs",
  "examples/knowledge/evaluation_answer.exs", "extensions/knowledge/src/evidence.ex",
  "lib/ipse/extensions/manifest.ex", "lib/ipse/json.ex"
], fn path -> {path, sha.(File.read!(Path.join(repo, path)))} end)
IO.puts(JSON.encode!(%{"rows" => 350, "predictions_bytes" => byte_size(bytes),
  "review_bytes" => byte_size(review), "packet_total_bytes" =>
    Enum.sum(for {_, contents} <- packet["files"], do: byte_size(contents)),
  "shown_candidates" => 10, "shown_input_bytes" => byte_size(bundle["request"]["input"]),
  "answer_bytes" => byte_size(response), "claims" => 8, "citation_pairs" => 80,
  "manifest_decoder_refuses_oversize" => true, "existing_json_decoder_accepts" => true,
  "inference_requests" => 0, "private_data_reads" => 0, "source_sha256" => source_hashes}))
