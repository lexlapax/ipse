defmodule Ipse.Extensions.Costs do
  @moduledoc "Pure extension-side estimates from explicit rate cards; no invoice, IO or request admission."
  alias Ipse.MCP.Schema
  alias Ipse.Usage.Normalizer
  @scale 1_000_000_000
  @safe 9_007_199_254_740_991
  @token_units ~w(input input_uncached input_cached input_cache_write input_cache_write_5m input_cache_write_1h output)
  @extra_units ~w(web_search web_fetch duration_second)
  @request_keys ~w(provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)

  def schema do
    text = %{"type" => "string", "minLength" => 1, "maxLength" => 256}
    count = %{"type" => "integer", "minimum" => 0, "maximum" => Normalizer.limit()}
    rates = Map.new(@token_units ++ @extra_units, &{&1, %{"type" => "string", "maxLength" => 24}})

    row =
      object(%{
        "id" => text,
        "provider" => %{"type" => "string", "enum" => ~w(openai chatgpt anthropic ollama)},
        "billing_mode" => %{"type" => "string", "enum" => ~w(api subscription local)},
        "basis" => %{"type" => "string", "enum" => ~w(api_estimate api_equivalent local_estimate)},
        "model" => text,
        "endpoint_sha256" => %{"type" => ["string", "null"], "maxLength" => 64},
        "from" => text,
        "until" => %{"type" => ["string", "null"], "maxLength" => 10},
        "input_min" => count,
        "input_max" => %{
          "type" => ["integer", "null"],
          "minimum" => 0,
          "maximum" => Normalizer.limit()
        },
        "input_mode" => %{"type" => "string", "enum" => ~w(flat cache_split cache_ttl_split)},
        "rates" => Map.put(object(rates), "required", [])
      })

    row =
      put_in(row, ["properties", "operation"], %{"type" => "string", "enum" => ~w(text embedding)})

    card =
      object(%{
        "version" => %{"type" => "integer", "enum" => [1, 2]},
        "id" => text,
        "revision" => text,
        "currency" => %{"type" => "string", "minLength" => 3, "maxLength" => 3},
        "source" => text,
        "published_on" => text,
        "rows" => %{"type" => "array", "maxItems" => 32, "items" => row}
      })

    card
  end

  @doc "Validate closed data and nonoverlapping model/endpoint/date/token bands without fetching its source."
  def validate(card) do
    with :ok <- Schema.validate_arguments(schema(), card),
         true <- card["version"] in [1, 2] and is_integer(card["version"]),
         true <-
           Enum.all?(card["rows"], fn row ->
             if card["version"] === 1,
               do: not Map.has_key?(row, "operation"),
               else: row["operation"] in ~w(text embedding)
           end),
         true <- Regex.match?(~r/\A[A-Z]{3}\z/, card["currency"]),
         true <- date?(card["published_on"]),
         true <- source?(card["source"]),
         true <- Enum.all?(card["rows"], &row?/1),
         true <- length(Enum.uniq_by(card["rows"], & &1["id"])) == length(card["rows"]),
         true <- disjoint?(card["rows"]) do
      :ok
    else
      _ -> {:error, :invalid_rate_card}
    end
  rescue
    _ -> {:error, :invalid_rate_card}
  end

  @doc "Estimate one cumulative request snapshot; unknown dimensions never become a zero total."
  def estimate(card, request) do
    with :ok <- validate(card),
         true <- request?(request),
         {:ok, time} <- DateTime.from_unix(request["admitted_at_ms"], :millisecond) do
      base = %{
        "version" => 1,
        "card_id" => card["id"],
        "revision" => card["revision"],
        "card_sha256" => Ipse.JSON.digest([card]),
        "source" => card["source"],
        "published_on" => card["published_on"],
        "currency" => card["currency"],
        "currency_scale" => 9,
        "provider" => request["provider"],
        "billing_mode" => request["billing_mode"],
        "requested_model" => request["model"],
        "reported_model" => request["reported_model"],
        "rated_model" => request["reported_model"] || request["model"],
        "endpoint_sha256" => request["endpoint_sha256"],
        "admitted_at_ms" => request["admitted_at_ms"],
        "input_mode" => nil,
        "rounding" => "ceiling_per_request",
        "scope" => "text_tokens_and_reported_extras",
        "row_id" => nil,
        "basis" => nil,
        "status" => "unpriced",
        "amount_nanos" => nil,
        "known_amount_nanos" => nil,
        "missing" => [],
        "components" => []
      }

      base =
        if Map.has_key?(request, "operation"),
          do:
            Map.merge(base, %{
              "version" => 2,
              "operation" => request["operation"],
              "scope" =>
                if(request["operation"] == "embedding",
                  do: "embedding_tokens_and_reported_duration",
                  else: base["scope"]
                )
            }),
          else: base

      counts = request["usage"]["counts"]
      model = request["reported_model"] || request["model"]
      date = time |> DateTime.to_date() |> Date.to_iso8601()

      rows =
        Enum.filter(card["rows"], fn row ->
          row["provider"] == request["provider"] and
            Map.get(row, "operation", "text") == Map.get(request, "operation", "text") and
            row["billing_mode"] == request["billing_mode"] and
            row["model"] == model and row["endpoint_sha256"] == request["endpoint_sha256"] and
            row["from"] <= date and (is_nil(row["until"]) or date < row["until"])
        end)

      case Enum.filter(rows, &band?(&1, counts["input_tokens"])) do
        [row] -> price(base, row, request)
        [] -> {:ok, unavailable(base, request, rows, counts)}
      end
    else
      {:error, :invalid_rate_card} = error -> error
      _ -> {:error, :invalid_cost_request}
    end
  rescue
    _ -> {:error, :invalid_cost_request}
  end

  defp unavailable(base, request, rows, counts) do
    cond do
      request["billing_mode"] == "none" ->
        %{base | "status" => "not_applicable", "missing" => ["scripted_usage"]}

      request["operation"] == "embedding" and base["version"] == 2 and rows == [] ->
        %{base | "missing" => ["operation_rate_unavailable"]}

      rows != [] and is_nil(counts["input_tokens"]) ->
        %{base | "missing" => ["input_band_unknown"]}

      request["billing_mode"] == "subscription" ->
        %{base | "status" => "not_applicable", "missing" => ["subscription_is_not_api_spend"]}

      request["billing_mode"] == "local" ->
        %{base | "missing" => ["local_cost_unconfigured"]}

      true ->
        %{base | "missing" => ["rate_unavailable"]}
    end
  end

  defp price(base, row, request) do
    counts = request["usage"]["counts"]
    {units, missing} = input_units(row["input_mode"], counts)
    embedding = request["operation"] == "embedding"
    units = if embedding, do: units, else: Map.put(units, "output", counts["output_tokens"])

    extras = %{
      "web_search" => counts["provider_web_search_requests"],
      "web_fetch" => counts["provider_web_fetch_requests"],
      "duration_second" => counts["provider_duration_ns"]
    }

    extras = if embedding, do: Map.take(extras, ["duration_second"]), else: extras

    units =
      Enum.reduce(extras, units, fn {key, count}, acc ->
        if Map.has_key?(row["rates"], key) or (is_integer(count) and count > 0),
          do: Map.put(acc, key, count),
          else: acc
      end)

    {parts, missing, numerator} =
      units
      |> Enum.sort()
      |> Enum.reduce({[], missing, 0}, fn {unit, count}, {parts, missing, sum} ->
        rate = row["rates"][unit]

        cond do
          is_nil(count) ->
            {parts, ["count:" <> unit | missing], sum}

          is_nil(rate) ->
            {parts, ["rate:" <> unit | missing], sum}

          true ->
            denominator =
              cond do
                unit in @token_units -> 1_000_000
                unit == "duration_second" -> @scale
                true -> 1_000
              end

            part = amount(rate) * count * div(@scale, denominator)

            {[%{"unit" => unit, "count" => count, "rate" => rate, "per" => denominator} | parts],
             missing, sum + part}
        end
      end)

    known = if parts == [], do: nil, else: div(numerator + @scale - 1, @scale)

    missing =
      if request["outcome"] != "completed" or request["finality"] != "final",
        do: ["incomplete_request" | missing],
        else: missing

    missing =
      if is_integer(known) and known > @safe, do: ["amount_overflow" | missing], else: missing

    known = if is_integer(known) and known > @safe, do: nil, else: known
    missing = Enum.sort(Enum.uniq(missing))

    {:ok,
     %{
       base
       | "row_id" => row["id"],
         "input_mode" => row["input_mode"],
         "basis" => row["basis"],
         "status" => if(missing == [], do: "estimated", else: "partial"),
         "known_amount_nanos" => known,
         "amount_nanos" => if(missing == [], do: known),
         "missing" => missing,
         "components" => Enum.reverse(parts)
     }}
  end

  defp input_units("flat", counts), do: {%{"input" => counts["input_tokens"]}, []}

  defp input_units(mode, counts) do
    input = counts["input_tokens"]
    cached = if input == 0, do: 0, else: counts["input_cached_tokens"]
    write = if input == 0, do: 0, else: counts["input_cache_write_tokens"]
    valid = Enum.all?([input, cached, write], &is_integer/1) and cached + write <= input
    inconsistent = Enum.all?([input, cached, write], &is_integer/1) and not valid
    uncached = if valid, do: input - cached - write
    cached = if inconsistent, do: nil, else: cached
    write = if inconsistent, do: nil, else: write
    parts = %{"input_uncached" => uncached, "input_cached" => cached}
    missing = if valid, do: [], else: ["input_partition_unknown_or_inconsistent"]

    if mode == "cache_split" do
      {Map.put(parts, "input_cache_write", write), missing}
    else
      short = if write == 0, do: 0, else: counts["input_cache_write_5m_tokens"]
      long = if write == 0, do: 0, else: counts["input_cache_write_1h_tokens"]
      ttl_valid = Enum.all?([short, long, write], &is_integer/1) and short + long == write

      missing =
        if ttl_valid, do: missing, else: ["cache_ttl_partition_unknown_or_inconsistent" | missing]

      {short, long} = if ttl_valid, do: {short, long}, else: {nil, nil}

      {Map.merge(parts, %{"input_cache_write_5m" => short, "input_cache_write_1h" => long}),
       missing}
    end
  end

  defp request?(r) do
    operation = Map.get(r, "operation", "text")

    keys =
      if Map.has_key?(r, "operation"), do: @request_keys ++ ["operation"], else: @request_keys

    Schema.validate_object(r) == :ok and Enum.sort(Map.keys(r)) == Enum.sort(keys) and
      operation in ~w(text embedding) and
      (operation == "text" or r["provider"] in ~w(openai ollama)) and
      r["provider"] in ~w(openai chatgpt anthropic ollama demo) and
      r["billing_mode"] == Normalizer.billing_mode(provider(r["provider"])) and
      is_binary(r["model"]) and byte_size(r["model"]) in 1..256 and
      (is_nil(r["reported_model"]) or
         (is_binary(r["reported_model"]) and byte_size(r["reported_model"]) in 1..256)) and
      hash_or_nil?(r["endpoint_sha256"]) and is_integer(r["admitted_at_ms"]) and
      r["admitted_at_ms"] in 0..253_402_300_799_999 and
      r["outcome"] in ~w(completed failed cancelled unknown) and
      r["finality"] in ~w(final partial) and Normalizer.valid?(r["usage"], operation)
  end

  defp provider("openai"), do: :openai
  defp provider("chatgpt"), do: :chatgpt
  defp provider("anthropic"), do: :anthropic
  defp provider("ollama"), do: :ollama
  defp provider("demo"), do: :demo

  defp row?(r) do
    embedding = r["operation"] == "embedding"

    expected =
      case {embedding, r["input_mode"]} do
        {true, "flat"} ->
          ["input"]

        {false, "flat"} ->
          ~w(input output)

        {false, "cache_split"} ->
          ~w(input_uncached input_cached input_cache_write output)

        {false, "cache_ttl_split"} ->
          ~w(input_uncached input_cached input_cache_write_5m input_cache_write_1h output)

        _ ->
          []
      end

    until_valid = is_nil(r["until"]) or date?(r["until"])

    expected != [] and (not embedding or r["provider"] in ~w(openai ollama)) and
      (not embedding or Enum.all?(Map.keys(r["rates"]), &(&1 in ~w(input duration_second)))) and
      r["billing_mode"] == Normalizer.billing_mode(provider(r["provider"])) and
      r["basis"] ==
        %{
          "api" => "api_estimate",
          "subscription" => "api_equivalent",
          "local" => "local_estimate"
        }[r["billing_mode"]] and
      hash_or_nil?(r["endpoint_sha256"]) and date?(r["from"]) and until_valid and
      (is_nil(r["until"]) or r["from"] < r["until"]) and
      (is_nil(r["input_max"]) or r["input_min"] < r["input_max"]) and
      Enum.sort(Map.keys(r["rates"])) -- @extra_units == Enum.sort(expected) and
      Enum.all?(
        Map.values(r["rates"]),
        &Regex.match?(~r/\A(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,9})?\z/, &1)
      )
  end

  defp band?(r, nil), do: r["input_min"] == 0 and is_nil(r["input_max"])

  defp band?(r, count),
    do: r["input_min"] <= count and (is_nil(r["input_max"]) or count < r["input_max"])

  defp disjoint?(rows) do
    not Enum.any?(
      for({a, i} <- Enum.with_index(rows), {b, j} <- Enum.with_index(rows), i < j, do: {a, b}),
      fn {a, b} ->
        same =
          Map.take(a, ~w(provider billing_mode model endpoint_sha256 operation)) ==
            Map.take(b, ~w(provider billing_mode model endpoint_sha256 operation))

        same and overlap?(a["from"], a["until"], b["from"], b["until"]) and
          overlap?(a["input_min"], a["input_max"], b["input_min"], b["input_max"])
      end
    )
  end

  defp overlap?(a, ae, b, be), do: (is_nil(ae) or b < ae) and (is_nil(be) or a < be)
  defp hash_or_nil?(nil), do: true
  defp hash_or_nil?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{64}\z/, v)

  defp date?(v),
    do: is_binary(v) and byte_size(v) == 10 and match?({:ok, _}, Date.from_iso8601(v))

  defp source?(source) do
    uri = URI.parse(source)

    is_nil(uri.userinfo) and is_nil(uri.query) and
      ((uri.scheme == "https" and is_binary(uri.host) and uri.host != "") or
         (uri.scheme == "operator" and is_binary(uri.path) and uri.path != ""))
  end

  defp amount(text) do
    case String.split(text, ".") do
      [whole] ->
        String.to_integer(whole) * @scale

      [whole, fraction] ->
        String.to_integer(whole) * @scale +
          String.to_integer(String.pad_trailing(fraction, 9, "0"))
    end
  end

  defp object(properties),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => properties,
      "required" => Map.keys(properties)
    }
end
