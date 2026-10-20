defmodule IpseKnowledge.Profiles do
  @moduledoc false
  @families ~w(stores search fetch retrieval embedding rerank extraction)
  @state ~w(host.actions host.actions.mixed host.state.read host.state.scan host.state.write host.state.bound)
  @mcp ~w(host.actions host.actions.mixed host.mcp host.results)
  @invoke ~w(invoke.command invoke.tool invoke.result.pages)

  def capabilities(package, preset) do
    extra =
      case {package, preset} do
        {"corpus", "state-lexical"} -> @state
        {"corpus", "state-dense"} -> @state ++ ~w(host.embedding host.results)
        {"corpus", "state-rerank"} -> @state ++ ~w(host.model)
        {"corpus", "state-semantic"} -> @state ++ ~w(host.embedding host.results host.model)
        {"corpus", "mcp-lexical"} -> @mcp
        {"corpus", "mcp-dense"} -> @mcp ++ ~w(host.embedding)
        {"corpus", "mcp-rerank"} -> @mcp ++ ~w(host.model)
        {"corpus", "mcp-semantic"} -> @mcp ++ ~w(host.embedding host.model)
        {"research", "offline"} -> []
        {"research", "mcp"} -> @mcp
        {"research", "mcp-model"} -> @mcp ++ ~w(host.model)
        {"graph", "state-explicit"} -> @state
        {"graph", "state-model"} -> @state ++ ~w(host.model)
        {"graph", "mcp-explicit"} -> @mcp
        {"graph", "mcp-model"} -> @mcp ++ ~w(host.model)
        _ -> :invalid
      end

    if extra == :invalid,
      do: {:error, :invalid_preset},
      else: Enum.sort(Enum.uniq(@invoke ++ extra))
  end

  def validate(package, preset, options) do
    caps = capabilities(package, preset)

    cond do
      not is_list(caps) ->
        {:error, :invalid_preset}

      not exact?(options, ["version" | @families]) or options["version"] != 1 ->
        {:error, :invalid_options}

      not encoded?(options) ->
        {:error, :invalid_options}

      not Enum.all?(@families, &family?(options[&1], &1)) ->
        {:error, :invalid_profile}

      not compatible?(package, preset, options, caps) ->
        {:error, :profile_authority_mismatch}

      not references?(options) ->
        {:error, :invalid_profile_reference}

      true ->
        {:ok,
         %{"package" => package, "preset" => preset, "options" => options, "capabilities" => caps}}
    end
  rescue
    _ -> {:error, :invalid_options}
  end

  def lookup(resolved, "rerank", nil) when is_map(resolved), do: {:ok, nil}

  def lookup(resolved, family, name)
      when is_map(resolved) and family in @families and is_binary(name) do
    case get_in(resolved, ["options", family, name]) do
      profile when is_map(profile) -> {:ok, profile}
      _ -> {:error, :unknown_profile}
    end
  end

  def lookup(_, _, _), do: {:error, :unknown_profile}

  defp compatible?(package, preset, o, caps) do
    allowed =
      case package do
        "corpus" -> ~w(stores retrieval embedding rerank)
        "research" -> ~w(search fetch retrieval rerank)
        "graph" -> ~w(stores extraction)
      end

    empty_unused = Enum.all?(@families -- allowed, &(o[&1] == %{}))
    store_kind = if String.starts_with?(preset, "state-"), do: "state", else: "mcp_cas"
    all_stores = Enum.all?(o["stores"], fn {_, p} -> p["kind"] == store_kind end)

    required =
      case package do
        "corpus" ->
          map_size(o["stores"]) > 0 and map_size(o["retrieval"]) > 0

        "graph" ->
          map_size(o["stores"]) > 0 and map_size(o["extraction"]) > 0

        "research" ->
          map_size(o["search"]) > 0 and map_size(o["fetch"]) > 0 and map_size(o["retrieval"]) > 0
      end

    authority =
      Enum.all?(@families, fn f ->
        Enum.all?(o[f], fn {_, p} -> Enum.all?(needs(f, p), &(&1 in caps)) end)
      end)

    offline =
      preset != "offline" or
        (Enum.all?(o["search"], fn {_, p} -> p["kind"] == "provided" end) and
           Enum.all?(o["fetch"], fn {_, p} -> p["kind"] == "provided" end))

    retrieval =
      package != "research" or Enum.all?(o["retrieval"], fn {_, p} -> p["kind"] == "bm25" end)

    empty_unused and all_stores and required and authority and offline and retrieval
  end

  defp needs("stores", %{"kind" => "state"}), do: @state

  defp needs(_, %{"kind" => kind}) when kind in ~w(mcp mcp_cas mcp_query),
    do: ~w(host.actions host.mcp host.results)

  defp needs("embedding", _), do: ~w(host.actions host.embedding host.results)
  defp needs(_, %{"kind" => "model_complete"}), do: ~w(host.actions host.model)
  defp needs(_, _), do: []

  defp family?(profiles, family),
    do:
      is_map(profiles) and map_size(profiles) <= 8 and
        Enum.all?(profiles, fn {name, p} -> name?(name) and profile?(family, p) end)

  defp profile?("stores", %{"kind" => "state"} = p),
    do:
      exact?(p, ~w(kind scope partition)) and p["scope"] in ~w(project operator session) and
        name?(p["partition"])

  defp profile?("stores", %{"kind" => "mcp_cas"} = p),
    do:
      exact?(p, ~w(kind binding partition contract)) and name?(p["binding"]) and
        name?(p["partition"]) and p["contract"] in ~w(ipse-cas-v1 ipse-cas-v2 ipse-cas-v3)

  defp profile?(f, %{"kind" => "provided"} = p) when f in ~w(search fetch),
    do: exact?(p, ~w(kind version)) and p["version"] == 1

  defp profile?(f, %{"kind" => "mcp"} = p) when f in ~w(search fetch),
    do:
      exact?(p, ~w(kind binding contract)) and name?(p["binding"]) and p["contract"] == f <> "-v1"

  defp profile?("retrieval", %{"kind" => "bm25"} = p),
    do: exact?(p, ~w(kind version)) and p["version"] == 1

  defp profile?("retrieval", %{"kind" => "dense"} = p),
    do: exact?(p, ~w(kind version embedding)) and p["version"] == 1 and name?(p["embedding"])

  defp profile?("retrieval", %{"kind" => "graph"} = p),
    do:
      exact?(p, ~w(kind version lexical depth max_nodes max_edges)) and p["version"] == 1 and
        name?(p["lexical"]) and integer?(p["depth"], 0, 4) and integer?(p["max_nodes"], 1, 128) and
        integer?(p["max_edges"], 1, 256)

  defp profile?("retrieval", %{"kind" => "hybrid"} = p),
    do:
      exact?(p, ~w(kind version lexical embedding graph rrf_k missing_embedding)) and
        p["version"] == 1 and name?(p["lexical"]) and name?(p["embedding"]) and
        (is_nil(p["graph"]) or name?(p["graph"])) and p["rrf_k"] == 60 and
        p["missing_embedding"] in ~w(refuse lexical_with_gap)

  defp profile?("retrieval", %{"kind" => "mcp_query"} = p),
    do:
      exact?(p, ~w(kind binding partition contract)) and name?(p["binding"]) and
        name?(p["partition"]) and p["contract"] == "query-v1"

  defp profile?("embedding", %{"kind" => "embedding"} = p),
    do: exact?(p, ~w(kind profile)) and name?(p["profile"])

  defp profile?("rerank", %{"kind" => "coverage"} = p),
    do: exact?(p, ~w(kind version)) and p["version"] == 1

  defp profile?("rerank", %{"kind" => "model_complete"} = p),
    do:
      model_contract?(p, ~w(kind profile max_candidates quote_bytes)) and name?(p["profile"]) and
        p["max_candidates"] == 16 and p["quote_bytes"] == 128

  defp profile?("extraction", %{"kind" => "explicit"} = p),
    do: exact?(p, ~w(kind version)) and p["version"] == 1

  defp profile?("extraction", %{"kind" => "model_complete"} = p),
    do: model_contract?(p, ~w(kind profile version)) and p["version"] == 1 and name?(p["profile"])

  defp profile?(_, _), do: false

  defp model_contract?(p, keys),
    do:
      exact?(p, keys) or
        (exact?(p, keys ++ ["output_contract"]) and p["output_contract"] == "json_schema_v2")

  defp references?(o) do
    Enum.all?(o["retrieval"], fn {name, p} ->
      lexical = p["lexical"]
      embedding = p["embedding"]
      graph = p["graph"]

      (is_nil(lexical) or get_in(o, ["retrieval", lexical, "kind"]) == "bm25") and
        (is_nil(embedding) or Map.has_key?(o["embedding"], embedding)) and
        (is_nil(graph) or get_in(o, ["retrieval", graph, "kind"]) == "graph") and
        not cyclic?(o["retrieval"], name, MapSet.new())
    end)
  end

  defp cyclic?(profiles, name, seen) do
    if MapSet.member?(seen, name) do
      true
    else
      p = profiles[name]
      refs = [p["lexical"], p["graph"]] |> Enum.reject(&is_nil/1)
      Enum.any?(refs, &cyclic?(profiles, &1, MapSet.put(seen, name)))
    end
  end

  defp exact?(p, keys),
    do: is_map(p) and map_size(p) == length(keys) and Enum.all?(keys, &Map.has_key?(p, &1))

  defp name?(s), do: is_binary(s) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,64}\z/, s)
  defp integer?(n, min, max), do: is_integer(n) and n >= min and n <= max
  defp encoded?(o), do: json?(o, 0) and byte_size(IO.iodata_to_binary(JSON.encode!(o))) <= 16_384
  defp json?(_, depth) when depth > 16, do: false
  defp json?(v, _) when is_binary(v), do: String.valid?(v) and byte_size(v) <= 8192
  defp json?(v, _) when is_integer(v) or is_boolean(v) or is_nil(v), do: true

  defp json?(v, depth) when is_map(v),
    do:
      map_size(v) <= 128 and
        Enum.all?(v, fn {k, x} -> is_binary(k) and json?(k, depth + 1) and json?(x, depth + 1) end)

  defp json?(v, depth) when is_list(v),
    do: length(v) <= 128 and Enum.all?(v, &json?(&1, depth + 1))

  defp json?(_, _), do: false
end
