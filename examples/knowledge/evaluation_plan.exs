Code.require_file("evaluation_runner.exs", __DIR__)

defmodule IpseKnowledgeExample.EvaluationPlan do
  @moduledoc "Declare the seven matched P27 strategies without opening data, artifacts or providers."
  alias IpseKnowledgeExample.EvaluationRunner
  @variants ~w(lexical graph_explicit graph_model dense hybrid rerank research)
  @artifacts ~w(answer dense explicit lexical model research semantic)
  @fields ~w(version mode data as_of_ms artifacts profiles embedding_profiles models interval_ms search_port blind_seed budgets storage_policy)

  def build(spec) do
    fields =
      if is_map(spec) and spec["version"] == 2, do: ["model_origin" | @fields], else: @fields

    with true <- exact?(spec, fields),
         true <- exact?(spec["artifacts"], @artifacts),
         true <- exact?(spec["budgets"], @variants),
         true <- exact?(spec["profiles"], ~w(p27_answer p27_extract p27_rerank)),
         true <- exact?(spec["embedding_profiles"], ~w(p27_embedding)),
         true <-
           Enum.all?(
             Map.values(spec["profiles"]) ++ Map.values(spec["embedding_profiles"]),
             &(&1["credential"] == "none")
           ),
         plan = spec |> Map.delete("budgets") |> Map.put("answer", true),
         plan = Map.put(plan, "variants", Enum.map(@variants, &variant(&1, spec["budgets"][&1]))),
         :ok <- EvaluationRunner.validate(plan) do
      {:ok, plan}
    else
      {:error, _} = error -> error
      _ -> {:error, :benchmark_spec}
    end
  rescue
    _ -> {:error, :benchmark_spec}
  end

  defp variant(id, budget) do
    {prepare, artifact, options, preparation, query, bindings, extra} = selection(id)
    instance = if id == "research", do: "research", else: "corpus"

    %{
      "id" => id,
      "prepare" => prepare,
      "artifacts" =>
        [entry(artifact, instance, options)] ++ extra ++ [entry("answer", "answer", %{})],
      "prepare_options" => preparation,
      "query_options" => query,
      "bindings" => Map.put(bindings, "answer", %{"instance" => "answer", "id" => "complete"}),
      "budget" => budget
    }
  end

  defp entry(artifact, instance, options),
    do: %{
      "alias" => artifact,
      "instance" => instance,
      "options" => options,
      "state_binding" => if(instance in ~w(corpus graph), do: "evaluation")
    }

  defp selection("lexical"),
    do: {"none", "lexical", common(), %{"store" => "notes"}, query("words"), bindings(), []}

  defp selection(id) when id in ~w(graph_explicit graph_model) do
    kind = if id == "graph_explicit", do: "explicit", else: "model"

    extraction =
      if kind == "explicit",
        do: %{"kind" => "explicit", "version" => 1},
        else: %{"kind" => "model_complete", "profile" => "p27_extract", "version" => 1}

    graph =
      common()
      |> Map.put("retrieval", %{})
      |> Map.put("extraction", %{"chosen" => extraction})

    corpus =
      put_in(common(), ["retrieval", "graph"], %{
        "kind" => "graph",
        "version" => 1,
        "lexical" => "words",
        "depth" => 2,
        "max_nodes" => 16,
        "max_edges" => 16
      })

    {if(kind == "explicit", do: "explicit", else: "extract"), "lexical", corpus,
     %{"store" => "notes", "extraction" => "chosen"}, query("graph"),
     Map.put(bindings(), "extract", %{"instance" => "graph", "id" => "extract"}),
     [entry(kind, "graph", graph)]}
  end

  defp selection(id) when id in ~w(dense hybrid rerank) do
    vector =
      common()
      |> Map.put("embedding", %{
        "native" => %{"kind" => "embedding", "profile" => "p27_embedding"}
      })
      |> put_in(["retrieval", "dense"], %{
        "kind" => "dense",
        "version" => 1,
        "embedding" => "native"
      })
      |> put_in(["retrieval", "combined"], %{
        "kind" => "hybrid",
        "version" => 1,
        "lexical" => "words",
        "embedding" => "native",
        "graph" => nil,
        "rrf_k" => 60,
        "missing_embedding" => "refuse"
      })

    options =
      if id == "rerank",
        do:
          Map.put(vector, "rerank", %{
            "chosen" => %{
              "kind" => "model_complete",
              "profile" => "p27_rerank",
              "max_candidates" => 16,
              "quote_bytes" => 128
            }
          }),
        else: vector

    selected =
      query(if(id == "dense", do: "dense", else: "combined"))
      |> Map.put("rerank", if(id == "rerank", do: "chosen"))

    {"embedding", if(id == "rerank", do: "semantic", else: "dense"), options,
     %{"store" => "notes", "embedding" => "native"}, selected,
     Map.put(bindings(), "index", %{"instance" => "corpus", "id" => "index"}), []}
  end

  defp selection("research") do
    options =
      common()
      |> Map.put("stores", %{})
      |> Map.put("search", %{
        "web" => %{"kind" => "mcp", "binding" => "search_web", "contract" => "search-v1"}
      })
      |> Map.put("fetch", %{
        "web" => %{"kind" => "mcp", "binding" => "fetch_web", "contract" => "fetch-v1"}
      })

    {"research", "research", options, %{},
     %{
       "search" => "web",
       "fetch" => "web",
       "retrieval" => "words",
       "rerank" => nil,
       "limits" => %{"max_sources" => 10, "max_body_bytes" => 49_152, "timeout_ms" => 30_000},
       "sources" => []
     }, %{"research" => %{"instance" => "research", "id" => "investigate"}}, []}
  end

  defp common,
    do: %{
      "version" => 1,
      "stores" => %{
        "notes" => %{"kind" => "state", "scope" => "project", "partition" => "manual"}
      },
      "search" => %{},
      "fetch" => %{},
      "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
      "embedding" => %{},
      "rerank" => %{},
      "extraction" => %{}
    }

  defp query(retrieval),
    do: %{"store" => "notes", "retrieval" => retrieval, "rerank" => nil, "top_k" => 10}

  defp bindings,
    do:
      Map.new(~w(ingest inspect forget collect query), fn verb ->
        {verb,
         %{"instance" => "corpus", "id" => if(verb == "query", do: "query", else: "source")}}
      end)

  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
end
