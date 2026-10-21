defmodule Ipse.Development.Evaluation.Contract do
  @moduledoc """
  Pure declaration ownership for matched knowledge comparisons.

  Build and validate complete plans without loading execution, model-service or
  fixture implementations. Freeze shape admission remains distinct from full
  executable validation. Runtime consumers resolve declared origins and command
  selections through the same rules; this module opens no files or services.
  """
  @safe 9_007_199_254_740_991
  @variants ~w(lexical graph_explicit graph_model dense hybrid rerank research)
  @artifacts ~w(answer dense explicit lexical model research semantic)
  @fields ~w(version mode data as_of_ms artifacts profiles embedding_profiles models interval_ms search_port blind_seed budgets storage_policy)

  @plan_fields (@fields -- ["budgets"]) ++ ~w(variants answer)
  @contracts %{
    "outputs" => %{
      "answer" => "json_schema_v2",
      "extract" => "json_schema_v2",
      "rerank" => "json_schema_v2"
    },
    "selection" => "per_strategy_eligibility_v1"
  }

  def build(spec) do
    fields = execution_fields(@fields, spec)

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
         plan =
           Map.put(
             plan,
             "variants",
             Enum.map(@variants, &variant(&1, spec["budgets"][&1], spec["version"]))
           ),
         :ok <- validate(plan) do
      {:ok, plan}
    else
      {:error, _} = error -> error
      _ -> {:error, :benchmark_spec}
    end
  rescue
    _ -> {:error, :benchmark_spec}
  end

  defp variant(id, budget, version) do
    {prepare, artifact, options, preparation, query, bindings, extra} = recipe(id, version)
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

  defp recipe("lexical", _version),
    do: {"none", "lexical", common(), %{"store" => "notes"}, query("words"), bindings(), []}

  defp recipe(id, version) when id in ~w(graph_explicit graph_model) do
    kind = if id == "graph_explicit", do: "explicit", else: "model"

    extraction =
      if kind == "explicit",
        do: %{"kind" => "explicit", "version" => 1},
        else:
          model_output(
            %{"kind" => "model_complete", "profile" => "p27_extract", "version" => 1},
            version
          )

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

  defp recipe(id, version) when id in ~w(dense hybrid rerank) do
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
            "chosen" =>
              model_output(
                %{
                  "kind" => "model_complete",
                  "profile" => "p27_rerank",
                  "max_candidates" => 16,
                  "quote_bytes" => 128
                },
                version
              )
          }),
        else: vector

    selected =
      query(if(id == "dense", do: "dense", else: "combined"))
      |> Map.put("rerank", if(id == "rerank", do: "chosen"))

    {"embedding", if(id == "rerank", do: "semantic", else: "dense"), options,
     %{"store" => "notes", "embedding" => "native"}, selected,
     Map.put(bindings(), "index", %{"instance" => "corpus", "id" => "index"}), []}
  end

  defp recipe("research", _version) do
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

  defp model_output(profile, 3), do: Map.put(profile, "output_contract", "json_schema_v2")
  defp model_output(profile, _), do: profile

  defp execution_fields(base, plan) do
    cond do
      is_map(plan) and plan["version"] == 3 -> ["contracts", "model_origin" | base]
      is_map(plan) and plan["version"] == 2 -> ["model_origin" | base]
      true -> base
    end
  end

  @doc "Admit a complete executable declaration under its original version rules."
  def validate(plan) do
    try do
      require!(exact?(plan, execution_fields(@plan_fields, plan)), :plan_shape)

      require!(
        (plan["version"] === 1 and plan["mode"] in ~w(fixture tuning heldout)) or
          (plan["version"] in [2, 3] and plan["mode"] in ~w(fixture heldout)),
        :plan_version
      )

      if plan["version"] == 3,
        do: require!(plan["contracts"] == @contracts, :evaluation_contracts)

      origin = model_origin!(plan)

      if plan["mode"] == "tuning",
        do: require!(plan["search_port"] != URI.parse(origin).port, :model_origin)

      if plan["version"] in [2, 3] do
        require!(
          Enum.all?(
            Map.values(plan["profiles"]) ++ Map.values(plan["embedding_profiles"]),
            &(&1["base_url"] == origin)
          ) and plan["search_port"] != URI.parse(origin).port,
          :model_origin
        )
      end

      require!(plan["storage_policy"] == "forget_all_then_collect_v1", :storage_policy)

      sealed = sealed?(plan["data"])
      data_fields = ~w(corpus queries split expected_queries manifest_sha256)

      require!(
        exact?(plan["data"], if(sealed, do: ["contract" | data_fields], else: data_fields)),
        :data_plan
      )

      if sealed,
        do:
          require!(
            plan["version"] in [2, 3] and plan["mode"] in ~w(fixture heldout) and
              plan["data"]["split"] == "heldout",
            :data_contract
          )

      require!(Enum.all?(~w(corpus queries), &relative?(plan["data"][&1])), :data_path)

      require!(
        is_integer(plan["data"]["expected_queries"]) and
          plan["data"]["expected_queries"] in 1..1024,
        :query_count
      )

      require!(
        is_binary(plan["data"]["split"]) and hash?(plan["data"]["manifest_sha256"]),
        :data_plan
      )

      require!(
        (uint?(plan["as_of_ms"]) or (plan["mode"] == "heldout" and plan["as_of_ms"] == "manifest")) and
          is_boolean(plan["answer"]),
        :time_or_answer
      )

      require!(
        is_integer(plan["interval_ms"]) and plan["interval_ms"] in 10..1000 and
          hash?(plan["blind_seed"]),
        :resource_or_blinding
      )

      require!(
        is_map(plan["artifacts"]) and map_size(plan["artifacts"]) in 1..16 and
          Enum.all?(plan["artifacts"], fn {id, path} -> name?(id) and is_binary(path) end),
        :artifact_plan
      )

      require!(
        Ipse.Profiles.validate(plan["profiles"], %{}) == :ok and
          Ipse.EmbeddingProfiles.validate(plan["embedding_profiles"]) == :ok,
        :profiles
      )

      require!(
        Enum.all?(Map.values(plan["profiles"]), &(&1["provider"] == "ollama")) and
          Enum.all?(Map.values(plan["embedding_profiles"]), &(&1["provider"] == "ollama")),
        :provider_scope
      )

      require!(
        is_map(plan["models"]) and
          Enum.all?(plan["models"], fn {name, hash} -> is_binary(name) and hash?(hash) end),
        :model_inventory
      )

      if plan["mode"] != "fixture" do
        selected_models =
          Enum.map(
            Map.values(plan["profiles"]) ++ Map.values(plan["embedding_profiles"]),
            & &1["model"]
          )
          |> Enum.uniq()
          |> Enum.sort()

        require!(Enum.sort(Map.keys(plan["models"])) == selected_models, :model_inventory)

        require!(
          Enum.all?(selected_models, &(&1 in ["qwen3.5:9b", "embeddinggemma:latest"])),
          :model_scope
        )

        require!(
          Enum.all?(
            Map.values(plan["profiles"]) ++ Map.values(plan["embedding_profiles"]),
            &(&1["base_url"] == origin)
          ),
          :model_origin
        )
      else
        if plan["version"] in [2, 3] do
          selected =
            Enum.map(
              Map.values(plan["profiles"]) ++ Map.values(plan["embedding_profiles"]),
              & &1["model"]
            )
            |> Enum.uniq()
            |> Enum.sort()

          require!(
            Enum.sort(Map.keys(plan["models"])) == selected and selected != [] and
              Enum.all?(selected, &Regex.match?(~r/\Afixture-[a-z0-9._-]+:[a-z0-9._-]+\z/, &1)),
            :fixture_models
          )
        else
          require!(plan["models"] == %{}, :fixture_models)
        end

        require!(
          Enum.all?(
            Map.values(plan["profiles"]) ++ Map.values(plan["embedding_profiles"]),
            fn profile ->
              origin = URI.parse(profile["base_url"] || "")

              String.starts_with?(profile["model"], "fixture-") and origin.scheme == "http" and
                origin.host == "127.0.0.1" and is_integer(origin.port) and origin.port != 11434
            end
          ),
          :fixture_model_origin
        )
      end

      variants = plan["variants"]

      require!(
        is_list(variants) and length(variants) in 1..7 and unique?(variants, & &1["id"]),
        :variants
      )

      if plan["version"] in [2, 3],
        do:
          require!(
            Enum.map(variants, & &1["id"]) == @variants and plan["answer"],
            :measured_matrix
          )

      if plan["mode"] == "heldout" do
        require!(
          Enum.map(variants, & &1["id"]) == @variants and plan["answer"] and
            plan["data"]["expected_queries"] == 50,
          :heldout_matrix
        )
      end

      Enum.each(variants, &variant!(&1, plan))

      if Enum.any?(variants, &(&1["prepare"] == "research")),
        do:
          require!(
            is_integer(plan["search_port"]) and plan["search_port"] in 1..65535,
            :search_port
          )

      if plan["mode"] == "heldout" do
        require!(
          sealed or
            plan["data"]["manifest_sha256"] ==
              "2759aebcd62f1d6368ce41dfd038ead0d4948f78ab5db4ba41ae92d7e9336063",
          :heldout_manifest
        )

        require!(
          plan["models"] == %{
            "embeddinggemma:latest" =>
              "85462619ee721b466c5927d109d4cb765861907d5417b9109caebc4e614679f1",
            "qwen3.5:9b" => "6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7"
          },
          :heldout_models
        )

        require!(
          Enum.all?(
            Map.values(plan["profiles"]),
            &(&1["model"] == "qwen3.5:9b" and &1["base_url"] == origin and
                &1["max_output_tokens"] == 4096 and &1["reasoning_effort"] == "none")
          ),
          :heldout_profiles
        )

        require!(
          Enum.all?(
            Map.values(plan["embedding_profiles"]),
            &(&1["model"] == "embeddinggemma:latest" and &1["dimensions"] == 768 and
                &1["dimension_mode"] == "native" and &1["base_url"] == origin)
          ),
          :heldout_profiles
        )
      end

      :ok
    rescue
      _ -> {:error, :plan_shape}
    catch
      {:evaluation_contract, code} -> {:error, code}
    end
  end

  @doc "Recognize Freeze's closed plan shape without admitting executable policy."
  def validate_shape(plan, :execution) do
    keys = execution_fields(@plan_fields, plan)

    if is_map(plan) and plan["version"] in [1, 2, 3] and exact?(plan, keys) and
         is_map(plan["artifacts"]) and is_map(plan["profiles"]) and
         is_map(plan["embedding_profiles"]) and
         (plan["version"] != 3 or plan["contracts"] == @contracts),
       do: :ok,
       else: {:error, :invalid_plan}
  end

  def validate_shape(plan, :portable) do
    keys = @plan_fields -- ~w(artifacts search_port)
    keys = if is_map(plan) and plan["version"] == 3, do: ["contracts" | keys], else: keys

    if exact?(plan, keys) and plan["version"] in [2, 3] and
         (plan["version"] != 3 or plan["contracts"] == @contracts) and
         Enum.all?(~w(profiles embedding_profiles), fn key ->
           is_map(plan[key]) and
             Enum.all?(plan[key], fn {id, profile} ->
               name?(id) and is_map(profile) and !Map.has_key?(profile, "base_url")
             end)
         end) do
      :ok
    else
      {:error, :invalid_experiment}
    end
  end

  @doc "Resolve the declared selected artifact without inspecting its files."
  def selection(variant, verb) do
    {:ok, selection!(variant, verb)}
  catch
    {:evaluation_contract, code} -> {:error, code}
  end

  @doc "Resolve the declared native model origin without inspecting the service."
  def model_origin(plan) do
    {:ok, model_origin!(plan)}
  catch
    {:evaluation_contract, code} -> {:error, code}
  end

  defp model_origin!(%{"version" => 1, "mode" => "tuning"} = plan) do
    origins =
      (Map.values(plan["profiles"]) ++ Map.values(plan["embedding_profiles"]))
      |> Enum.map(& &1["base_url"])
      |> Enum.uniq()

    case origins do
      [] -> "http://127.0.0.1:11434"
      ["http://127.0.0.1:11434" = origin] -> origin
      [origin] -> model_origin!(%{"version" => 2, "model_origin" => origin})
      _ -> fail!(:model_origin)
    end
  end

  defp model_origin!(%{"version" => 1}), do: "http://127.0.0.1:11434"

  defp model_origin!(%{"version" => version, "model_origin" => origin}) when version in [2, 3] do
    require!(is_binary(origin) and byte_size(origin) <= 64, :model_origin)

    case Regex.run(~r/\Ahttp:\/\/127\.0\.0\.1:([0-9]{1,5})\z/, origin) do
      [_, text] ->
        port = String.to_integer(text)

        require!(
          port in 1..65535 and port != 11434 and Integer.to_string(port) == text,
          :model_origin
        )

        origin

      _ ->
        fail!(:model_origin)
    end
  end

  defp variant!(variant, plan) do
    require!(
      exact?(variant, ~w(id prepare artifacts bindings prepare_options query_options budget)),
      :variant_shape
    )

    require!(
      variant["id"] in @variants and
        variant["prepare"] in ~w(none explicit extract embedding research),
      :variant_kind
    )

    require!(
      is_list(variant["artifacts"]) and length(variant["artifacts"]) in 1..8 and
        unique?(variant["artifacts"], & &1["instance"]),
      :variant_artifacts
    )

    Enum.each(variant["artifacts"], fn entry ->
      require!(exact?(entry, ~w(alias instance options state_binding)), :selection_shape)

      require!(
        Map.has_key?(plan["artifacts"], entry["alias"]) and name?(entry["instance"]) and
          is_map(entry["options"]),
        :selection
      )

      require!(is_nil(entry["state_binding"]) or name?(entry["state_binding"]), :state_binding)
    end)

    require!(
      is_map(variant["bindings"]) and is_map(variant["prepare_options"]) and
        is_map(variant["query_options"]),
      :variant_arguments
    )

    require!(variant["query_options"]["top_k"] in [nil, 10], :rank_capacity)

    require!(
      Ipse.Budget.Policy.validate(variant["budget"]) == :ok and
        is_integer(variant["budget"]["max_requests"]) and variant["budget"]["max_requests"] > 0,
      :variant_budget
    )

    algorithms = %{
      "lexical" => {"none", "bm25"},
      "graph_explicit" => {"explicit", "graph"},
      "graph_model" => {"extract", "graph"},
      "dense" => {"embedding", "dense"},
      "hybrid" => {"embedding", "hybrid"},
      "rerank" => {"embedding", "hybrid"},
      "research" => {"research", "bm25"}
    }

    {preparation, retrieval} = algorithms[variant["id"]]
    require!(variant["prepare"] == preparation, :variant_algorithm)
    query_owner = if preparation == "research", do: "research", else: "query"
    entry = selection!(variant, query_owner)
    options = entry["options"]

    Enum.each(variant["artifacts"], fn selected ->
      for family <- ~w(embedding extraction rerank),
          profile <- Map.values(selected["options"][family] || %{}),
          is_binary(profile["profile"]) do
        registry =
          if family == "embedding", do: plan["embedding_profiles"], else: plan["profiles"]

        require!(Map.has_key?(registry, profile["profile"]), :profile_reference)
      end

      if plan["version"] == 3 do
        for family <- ~w(extraction rerank),
            profile <- Map.values(selected["options"][family] || %{}),
            profile["kind"] == "model_complete" do
          require!(profile["output_contract"] == "json_schema_v2", :output_contract)
        end
      end
    end)

    if preparation == "research" do
      require!(variant["prepare_options"] == %{}, :preparation_arguments)

      require!(
        exact?(variant["query_options"], ~w(search fetch retrieval rerank limits sources)) and
          variant["query_options"]["sources"] == [],
        :query_arguments
      )

      limits = variant["query_options"]["limits"]

      require!(
        exact?(limits, ~w(max_sources max_body_bytes timeout_ms)) and
          is_integer(limits["max_sources"]) and limits["max_sources"] in 1..10 and
          is_integer(limits["max_body_bytes"]) and limits["max_body_bytes"] in 1..49_152 and
          is_integer(limits["timeout_ms"]) and limits["timeout_ms"] in 1000..30_000,
        :research_limits
      )
    else
      required =
        case preparation do
          "none" -> ~w(store)
          "embedding" -> ~w(store embedding)
          _ -> ~w(store extraction)
        end

      require!(exact?(variant["prepare_options"], required), :preparation_arguments)

      require!(
        exact?(variant["query_options"], ~w(store retrieval rerank top_k)) and
          variant["query_options"]["top_k"] == 10,
        :query_arguments
      )

      store = variant["prepare_options"]["store"]

      require!(
        variant["query_options"]["store"] == store and is_binary(entry["state_binding"]),
        :store_selection
      )

      require!(
        get_in(options, ["stores", store, "kind"]) == "state" and
          get_in(options, ["stores", store, "scope"]) == "project",
        :store_selection
      )

      writer = selection!(variant, "ingest")

      require!(
        writer["state_binding"] == entry["state_binding"] and
          get_in(writer, ["options", "stores", store]) == get_in(options, ["stores", store]),
        :store_selection
      )

      if preparation == "embedding",
        do:
          require!(
            get_in(options, ["retrieval", variant["query_options"]["retrieval"], "embedding"]) ==
              variant["prepare_options"]["embedding"],
            :embedding_selection
          )
    end

    require!(
      get_in(options, ["retrieval", variant["query_options"]["retrieval"], "kind"]) == retrieval,
      :variant_algorithm
    )

    if retrieval == "hybrid",
      do:
        require!(
          get_in(options, [
            "retrieval",
            variant["query_options"]["retrieval"],
            "missing_embedding"
          ]) == "refuse",
          :hidden_fallback
        )

    if variant["id"] == "rerank" do
      require!(
        get_in(options, ["rerank", variant["query_options"]["rerank"], "kind"]) ==
          "model_complete",
        :variant_algorithm
      )
    else
      require!(variant["query_options"]["rerank"] == nil, :variant_algorithm)
    end

    if preparation in ~w(explicit extract) do
      graph = selection!(variant, "extract")
      kind = if preparation == "explicit", do: "explicit", else: "model_complete"

      require!(
        get_in(graph, ["options", "extraction", variant["prepare_options"]["extraction"], "kind"]) ==
          kind,
        :variant_algorithm
      )

      store = variant["prepare_options"]["store"]

      require!(
        graph["state_binding"] == entry["state_binding"] and
          get_in(graph, ["options", "stores", store]) == get_in(options, ["stores", store]),
        :graph_store_sharing
      )
    end

    if plan["answer"],
      do:
        require!(
          is_map(variant["bindings"]["answer"]) and Map.has_key?(plan["profiles"], "p27_answer"),
          :answer_binding
        )

    require!(
      Enum.sort(Map.keys(variant["bindings"])) == Enum.sort(required_verbs(variant, plan)),
      :command_bindings
    )
  end

  defp required_verbs(variant, plan) do
    base =
      case variant["prepare"] do
        "research" -> ~w(research)
        "embedding" -> ~w(ingest inspect forget collect query index)
        kind when kind in ~w(explicit extract) -> ~w(ingest inspect forget collect query extract)
        "none" -> ~w(ingest inspect forget collect query)
      end

    if plan["answer"], do: base ++ ["answer"], else: base
  end

  defp selection!(variant, verb) do
    binding = variant["bindings"][verb]
    require!(is_map(binding), :command_binding)

    case Enum.find(variant["artifacts"], &(&1["instance"] == binding["instance"])) do
      nil -> fail!(:command_binding)
      entry -> entry
    end
  end

  defp sealed?(data), do: is_map(data) and data["contract"] == "sealed_answers_v1"

  defp relative?(value),
    do:
      is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*\z/, value) and
        Enum.all?(Path.split(value), &(&1 not in [".", ".."]))

  defp unique?(values, key), do: length(values) == length(Enum.uniq_by(values, key))
  defp name?(value), do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp uint?(value), do: is_integer(value) and value in 0..@safe
  defp require!(true, _), do: :ok
  defp require!(_, code), do: throw({:evaluation_contract, code})
  defp fail!(code), do: throw({:evaluation_contract, code})
end
