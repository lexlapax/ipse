defmodule Ipse.Usage.Normalizer do
  @moduledoc "Allowlisted provider counters; absent or invalid metering never becomes zero."
  @limit 1_000_000_000_000
  @fields ~w(input_tokens output_tokens total_tokens input_uncached_tokens input_cached_tokens input_cache_write_tokens input_cache_write_5m_tokens input_cache_write_1h_tokens output_reasoning_tokens provider_web_search_requests provider_web_fetch_requests provider_duration_ns)
  @billing %{
    chatgpt: "subscription",
    openai: "api",
    ollama: "local",
    anthropic: "api",
    demo: "none"
  }
  def fields, do: @fields
  def limit, do: @limit
  def billing_mode(provider), do: @billing[provider]

  def normalize(:demo, _usage), do: record(empty(), [], "not_applicable", [])

  def normalize(provider, usage) when provider in [:chatgpt, :openai, :ollama, :anthropic] do
    usage = if is_nil(usage), do: %{}, else: usage

    with true <- is_map(usage),
         {:ok, counts} <- extract(provider, usage),
         {:ok, counts, derived} <- derive(provider, counts),
         true <- consistent?(counts) do
      quality =
        cond do
          is_integer(counts["input_tokens"]) and is_integer(counts["output_tokens"]) ->
            "totals_known"

          Enum.any?(Map.values(counts), &is_integer/1) ->
            "partial"

          true ->
            "unavailable"
        end

      record(counts, derived, quality, [])
    else
      _ -> record(empty(), [], "invalid", ["invalid_or_inconsistent_provider_counters"])
    end
  rescue
    _ -> record(empty(), [], "invalid", ["invalid_or_inconsistent_provider_counters"])
  end

  def normalize(_, _), do: record(empty(), [], "invalid", ["unsupported_provider"])

  def normalize(provider, operation, raw) when operation in [:text, "text"],
    do: normalize(provider, raw)

  def normalize(provider, operation, raw) when operation in [:embedding, "embedding"] do
    raw = if is_nil(raw), do: %{}, else: raw

    with true <- provider in [:openai, :ollama],
         true <- is_map(raw),
         {:ok, counts} <- embedding_counts(provider, raw),
         true <- embedding_consistent?(counts) do
      {counts, derived} =
        if is_integer(counts["input_tokens"]) and is_nil(counts["total_tokens"]),
          do: {Map.put(counts, "total_tokens", counts["input_tokens"]), ["total_tokens"]},
          else: {counts, []}

      quality =
        cond do
          is_integer(counts["input_tokens"]) and is_integer(counts["total_tokens"]) ->
            "totals_known"

          Enum.any?(Map.values(counts), &is_integer/1) ->
            "partial"

          true ->
            "unavailable"
        end

      embedding_record(counts, derived, quality, [])
    else
      _ ->
        issue =
          if provider in [:openai, :ollama],
            do: "invalid_or_inconsistent_provider_counters",
            else: "unsupported_provider"

        embedding_record(empty(), [], "invalid", [issue])
    end
  rescue
    _ -> embedding_record(empty(), [], "invalid", ["invalid_or_inconsistent_provider_counters"])
  end

  def normalize(_, _, _), do: record(empty(), [], "invalid", ["unsupported_provider"])

  def valid?(usage, "text"), do: is_map(usage) and usage["version"] === 1 and valid?(usage)
  def valid?(usage, "embedding"), do: is_map(usage) and usage["version"] === 2 and valid?(usage)
  def valid?(_, _), do: false

  @doc "Validate stored normalized counters without accessing provider data or credentials."
  def valid?(
        %{
          "version" => 1,
          "counts" => counts,
          "derived_fields" => derived,
          "quality" => quality,
          "issues" => issues
        } = record
      ) do
    Ipse.MCP.Schema.validate_object(record) == :ok and
      Enum.sort(Map.keys(record)) == ~w(counts derived_fields issues quality version) and
      is_map(counts) and Enum.all?(Map.keys(counts), &(&1 in @fields)) and
      Enum.all?(~w(input_tokens output_tokens total_tokens), &Map.has_key?(counts, &1)) and
      Enum.all?(Map.values(counts), &(is_nil(&1) or counter?(&1))) and
      is_list(derived) and length(derived) == length(Enum.uniq(derived)) and
      Enum.all?(derived, &(&1 in ~w(input_tokens total_tokens))) and
      Enum.all?(derived, &is_integer(counts[&1])) and
      quality in ~w(totals_known partial unavailable invalid not_applicable) and
      is_list(issues) and
      Enum.all?(
        issues,
        &(&1 in ~w(invalid_or_inconsistent_provider_counters unsupported_provider))
      ) and
      consistent?(counts) and quality_matches?(counts, quality)
  rescue
    _ -> false
  end

  def valid?(%{"version" => 2, "operation" => "embedding"} = record) do
    counts = record["counts"]
    derived = record["derived_fields"]
    quality = record["quality"]
    issues = record["issues"]

    Ipse.MCP.Schema.validate_object(record) == :ok and
      Enum.sort(Map.keys(record)) ==
        ~w(counts derived_fields issues not_applicable_fields operation quality version) and
      record["not_applicable_fields"] == ["output_tokens"] and
      is_map(counts) and Enum.sort(Map.keys(counts)) == Enum.sort(@fields) and
      Enum.all?(Map.values(counts), &(is_nil(&1) or counter?(&1))) and
      Enum.all?(
        @fields -- ~w(input_tokens total_tokens provider_duration_ns),
        &is_nil(counts[&1])
      ) and
      derived in [[], ["total_tokens"]] and
      (derived == [] or
         (is_integer(counts["input_tokens"]) and is_integer(counts["total_tokens"]))) and
      embedding_consistent?(counts) and
      is_list(issues) and
      Enum.all?(
        issues,
        &(&1 in ~w(invalid_or_inconsistent_provider_counters unsupported_provider))
      ) and
      ((quality == "invalid" and issues != []) or (quality != "invalid" and issues == [])) and
      embedding_quality?(counts, quality)
  rescue
    _ -> false
  end

  def valid?(_), do: false

  defp embedding_counts(provider, raw) do
    paths =
      case provider do
        :openai ->
          %{"input_tokens" => ["prompt_tokens"], "total_tokens" => ["total_tokens"]}

        :ollama ->
          %{"input_tokens" => ["prompt_eval_count"], "provider_duration_ns" => ["total_duration"]}
      end

    Enum.reduce_while(paths, {:ok, empty()}, fn {field, path}, {:ok, counts} ->
      case read(raw, path) do
        nil ->
          {:cont, {:ok, counts}}

        value when is_integer(value) and value >= 0 and value <= @limit ->
          {:cont, {:ok, Map.put(counts, field, value)}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp embedding_consistent?(counts),
    do:
      is_nil(counts["input_tokens"]) or is_nil(counts["total_tokens"]) or
        counts["input_tokens"] == counts["total_tokens"]

  defp embedding_quality?(counts, "totals_known"),
    do: is_integer(counts["input_tokens"]) and is_integer(counts["total_tokens"])

  defp embedding_quality?(counts, quality) when quality in ~w(unavailable invalid),
    do: Enum.all?(Map.values(counts), &is_nil/1)

  defp embedding_quality?(counts, "partial"),
    do:
      Enum.any?(Map.values(counts), &is_integer/1) and
        not embedding_quality?(counts, "totals_known")

  defp embedding_quality?(_, _), do: false

  defp embedding_record(counts, derived, quality, issues),
    do: %{
      "version" => 2,
      "operation" => "embedding",
      "counts" => counts,
      "derived_fields" => derived,
      "quality" => quality,
      "issues" => issues,
      "not_applicable_fields" => ["output_tokens"]
    }

  defp extract(provider, raw) do
    paths =
      case provider do
        p when p in [:chatgpt, :openai] ->
          %{
            "input_tokens" => ["input_tokens"],
            "output_tokens" => ["output_tokens"],
            "total_tokens" => ["total_tokens"],
            "input_cached_tokens" => ["input_tokens_details", "cached_tokens"],
            "input_cache_write_tokens" => ["input_tokens_details", "cache_write_tokens"],
            "output_reasoning_tokens" => ["output_tokens_details", "reasoning_tokens"]
          }

        :anthropic ->
          %{
            "input_uncached_tokens" => ["input_tokens"],
            "output_tokens" => ["output_tokens"],
            "input_cached_tokens" => ["cache_read_input_tokens"],
            "input_cache_write_tokens" => ["cache_creation_input_tokens"],
            "input_cache_write_5m_tokens" => ["cache_creation", "ephemeral_5m_input_tokens"],
            "input_cache_write_1h_tokens" => ["cache_creation", "ephemeral_1h_input_tokens"],
            "output_reasoning_tokens" => ["output_tokens_details", "thinking_tokens"],
            "provider_web_search_requests" => ["server_tool_use", "web_search_requests"],
            "provider_web_fetch_requests" => ["server_tool_use", "web_fetch_requests"]
          }

        :ollama ->
          Map.new(
            ~w(input_tokens output_tokens input_cached_tokens provider_duration_ns),
            &{&1, [&1]}
          )
      end

    Enum.reduce_while(paths, {:ok, empty()}, fn {field, path}, {:ok, counts} ->
      case read(raw, path) do
        nil ->
          {:cont, {:ok, counts}}

        value when is_integer(value) and value >= 0 and value <= @limit ->
          {:cont, {:ok, Map.put(counts, field, value)}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp read(value, []), do: value
  defp read(nil, _path), do: nil
  defp read(map, [key | rest]) when is_map(map), do: read(Map.get(map, key), rest)
  defp read(_, _), do: :invalid

  defp derive(provider, counts) do
    {counts, derived} =
      if provider == :anthropic do
        parts =
          Enum.map(
            ~w(input_uncached_tokens input_cached_tokens input_cache_write_tokens),
            &counts[&1]
          )

        if Enum.all?(parts, &is_integer/1),
          do: {Map.put(counts, "input_tokens", Enum.sum(parts)), ["input_tokens"]},
          else: {counts, []}
      else
        {counts, []}
      end

    {counts, derived} =
      if is_nil(counts["total_tokens"]) and is_integer(counts["input_tokens"]) and
           is_integer(counts["output_tokens"]) do
        {Map.put(counts, "total_tokens", counts["input_tokens"] + counts["output_tokens"]),
         derived ++ ["total_tokens"]}
      else
        {counts, derived}
      end

    if Enum.all?(Map.values(counts), &(is_nil(&1) or counter?(&1))),
      do: {:ok, counts, derived},
      else: :error
  end

  defp consistent?(counts) do
    input = counts["input_tokens"]
    output = counts["output_tokens"]
    total = counts["total_tokens"]

    (is_nil(input) or is_nil(output) or is_nil(total) or input + output == total) and
      subset?(counts["input_cached_tokens"], input) and
      subset?(counts["input_cache_write_tokens"], input) and
      subset?(counts["output_reasoning_tokens"], output) and
      subset?(counts["input_cache_write_5m_tokens"], counts["input_cache_write_tokens"]) and
      subset?(counts["input_cache_write_1h_tokens"], counts["input_cache_write_tokens"])
  end

  defp subset?(nil, _), do: true
  defp subset?(_, nil), do: true
  defp subset?(part, total), do: part <= total
  defp counter?(value), do: is_integer(value) and value >= 0 and value <= @limit
  defp empty, do: Map.new(@fields, &{&1, nil})

  defp record(counts, derived, quality, issues),
    do: %{
      "version" => 1,
      "counts" => counts,
      "derived_fields" => derived,
      "quality" => quality,
      "issues" => issues
    }

  defp quality_matches?(counts, "totals_known"),
    do: is_integer(counts["input_tokens"]) and is_integer(counts["output_tokens"])

  defp quality_matches?(counts, quality) when quality in ~w(unavailable invalid not_applicable),
    do: Enum.all?(Map.values(counts), &is_nil/1)

  defp quality_matches?(counts, "partial"),
    do:
      Enum.any?(Map.values(counts), &is_integer/1) and
        not (is_integer(counts["input_tokens"]) and is_integer(counts["output_tokens"]))
end
