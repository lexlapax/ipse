defmodule Ipse.Usage.Costs do
  @moduledoc "Pure estimates from explicit rate cards; no invoice, IO or request admission."
  alias Ipse.JSON, as: Schema
  alias Ipse.Usage
  @scale 1_000_000_000
  @safe 9_007_199_254_740_991
  @token_units ~w(input input_uncached input_cached input_cache_write input_cache_write_5m input_cache_write_1h output)
  @extra_units ~w(web_search web_fetch duration_second)
  @request_keys ~w(provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)
  @decision_ids ~w(openai system_one system_one_compatible)

  def schema do
    text = %{"type" => "string", "minLength" => 1, "maxLength" => 256}
    count = %{"type" => "integer", "minimum" => 0, "maximum" => Usage.counter_limit()}
    rates = Map.new(@token_units ++ @extra_units, &{&1, %{"type" => "string", "maxLength" => 24}})

    row =
      object(%{
        "id" => text,
        "provider" => %{
          "type" => "string",
          "enum" => Enum.uniq(Ipse.Provider.Registry.rate_card_ids() ++ @decision_ids)
        },
        "billing_mode" => %{"type" => "string", "enum" => Ipse.Provider.Registry.billing_modes()},
        "basis" => %{"type" => "string", "enum" => Ipse.Provider.Registry.cost_bases()},
        "model" => text,
        "endpoint_sha256" => %{"type" => ["string", "null"], "maxLength" => 64},
        "from" => text,
        "until" => %{"type" => ["string", "null"], "maxLength" => 10},
        "input_min" => count,
        "input_max" => %{
          "type" => ["integer", "null"],
          "minimum" => 0,
          "maximum" => Usage.counter_limit()
        },
        "input_mode" => %{"type" => "string", "enum" => ~w(flat cache_split cache_ttl_split)},
        "rates" => Map.put(object(rates), "required", [])
      })

    row =
      put_in(row, ["properties", "operation"], %{
        "type" => "string",
        "enum" => ~w(text embedding decision)
      })

    card =
      object(%{
        "version" => %{"type" => "integer", "enum" => [1, 2, 3]},
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
         true <- card["version"] in [1, 2, 3] and is_integer(card["version"]),
         true <-
           Enum.all?(card["rows"], fn row ->
             case card["version"] do
               1 ->
                 not Map.has_key?(row, "operation") and
                   row["provider"] in Ipse.Provider.Registry.rate_card_ids()

               2 ->
                 row["operation"] in ~w(text embedding) and
                   row["provider"] in Ipse.Provider.Registry.rate_card_ids()

               3 ->
                 row["operation"] in ~w(text embedding decision)
             end
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
              "version" => if(request["operation"] == "decision", do: 3, else: 2),
              "operation" => request["operation"],
              "scope" =>
                if(request["operation"] == "embedding",
                  do: "embedding_tokens_and_reported_duration",
                  else:
                    if(request["operation"] == "decision",
                      do: "decision_tokens",
                      else: base["scope"]
                    )
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

      request["operation"] in ~w(embedding decision) and rows == [] ->
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
      operation in ~w(text embedding decision) and
      ((operation == "text" and r["provider"] in Ipse.Provider.Registry.ids()) or
         (operation == "embedding" and Ipse.Provider.Registry.embedding?(r["provider"])) or
         (operation == "decision" and r["provider"] in @decision_ids)) and
      r["billing_mode"] == Usage.billing_mode(provider(r["provider"])) and
      is_binary(r["model"]) and byte_size(r["model"]) in 1..256 and
      (is_nil(r["reported_model"]) or
         (is_binary(r["reported_model"]) and byte_size(r["reported_model"]) in 1..256)) and
      hash_or_nil?(r["endpoint_sha256"]) and is_integer(r["admitted_at_ms"]) and
      r["admitted_at_ms"] in 0..253_402_300_799_999 and
      r["outcome"] in ~w(completed failed cancelled unknown) and
      r["finality"] in ~w(final partial) and Usage.valid_usage?(r["usage"], operation)
  end

  defp provider(value), do: Usage.provider(value)

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

    expected != [] and
      if(r["operation"] == "decision",
        do:
          r["provider"] in @decision_ids and
            Enum.all?(Map.keys(r["rates"]), &(&1 in @token_units)),
        else: r["provider"] in Ipse.Provider.Registry.rate_card_ids()
      ) and
      (not embedding or Ipse.Provider.Registry.embedding?(r["provider"])) and
      (not embedding or Enum.all?(Map.keys(r["rates"]), &(&1 in ~w(input duration_second)))) and
      r["billing_mode"] == Usage.billing_mode(provider(r["provider"])) and
      r["basis"] ==
        Ipse.Provider.Registry.cost_basis(r["billing_mode"]) and
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

  alias Ipse.Usage

  @fields ~w(operation provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)
  @limit 10_000

  def summary(card, limit \\ @limit) when is_integer(limit) and limit in 1..40_000 do
    with :ok <- validate(card), do: {:ok, %{card: card, requests: %{}, limit: limit}}
  end

  @doc "Replace the contribution for an actual request attempt, never add cumulative observations as deltas."
  def put_request(state, request) do
    key = {request["session_id"], request["request_id"], request["attempt_id"]}

    admission =
      request
      |> Map.drop(~w(outcome finality duration_ms reported_model usage))
      |> then(&Ipse.JSON.digest([&1]))

    with true <- Usage.valid_request_record?(request),
         true <- map_size(state.requests) < state.limit or Map.has_key?(state.requests, key),
         true <-
           not Map.has_key?(state.requests, key) or state.requests[key].admission == admission,
         {:ok, quote} <- estimate(state.card, Map.take(request, @fields)) do
      contribution = %{
        admission: admission,
        group:
          {request["provider"], request["billing_mode"], quote["basis"],
           request["operation"] || "text"},
        amount: quote["amount_nanos"],
        known: quote["known_amount_nanos"],
        overflow: "amount_overflow" in quote["missing"],
        final: request["outcome"] == "completed" and request["finality"] == "final",
        unknown: request["outcome"] == "unknown",
        counts: request["usage"]["counts"]
      }

      {:ok, %{state | requests: Map.put(state.requests, key, contribution)}}
    else
      _ -> {:error, :invalid_summary_request}
    end
  rescue
    _ -> {:error, :invalid_summary_request}
  end

  def report(state, snapshot, enumeration_complete) do
    report_scope(state, snapshot, enumeration_complete, snapshot["request_count"], [
      snapshot["source"]["session_id"]
    ])
  end

  def tree_report(state, snapshot, discovery, children, descriptors) do
    snapshots = for %{"snapshot" => s} <- children, s != nil, do: s
    count = if discovery, do: discovery["child_count"]
    captured = Enum.count(children, &(&1["complete"] == true))

    unknown =
      Enum.count(descriptors, &(&1["status"] != "result_recorded" or not &1["cleanup_confirmed"]))

    legacy = snapshot["legacy_unmetered"] or Enum.any?(snapshots, & &1["legacy_unmetered"])
    expected = snapshot["request_count"] + Enum.sum(Enum.map(snapshots, & &1["request_count"]))
    sessions = [snapshot["source"]["session_id"] | Enum.map(snapshots, & &1["child_id"])]
    complete = count != nil and captured == count

    report =
      report_scope(
        state,
        %{snapshot | "legacy_unmetered" => legacy},
        complete,
        expected,
        sessions
      )

    gaps =
      children
      |> Enum.reject(& &1["complete"])
      |> Enum.map(&(&1["error"] || "scan_limit"))
      |> Enum.frequencies()

    unvisited = if count, do: count - length(children), else: 0

    gaps =
      if unvisited > 0,
        do: Map.update(gaps, "scan_limit", unvisited, &(&1 + unvisited)),
        else: gaps

    Map.merge(report, %{
      "coverage" => "session_tree",
      "snapshot" => snapshot,
      "discovery_snapshot" => discovery,
      "child_count" => count,
      "captured_child_count" => captured,
      "unknown_child_outcome_count" => unknown,
      "legacy_unmetered" => legacy,
      "gap_count" => if(count, do: count - captured),
      "gap_reasons" => gaps,
      "child_manifest_sha256" => Ipse.JSON.digest([children]),
      "cost_estimate_complete" => report["cost_estimate_complete"] and unknown == 0
    })
  end

  defp report_scope(state, snapshot, enumeration_complete, expected, sessions) do
    enumeration_complete =
      enumeration_complete and map_size(state.requests) == expected and
        Enum.all?(Map.keys(state.requests), fn {session, _, _} ->
          session in sessions
        end)

    groups =
      state.requests
      |> Map.values()
      |> Enum.group_by(& &1.group)
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map(fn {{provider, billing, basis, operation}, rows} ->
        known = sum(Enum.map(rows, & &1.known))
        amounts = Enum.map(rows, & &1.amount)
        overflow = known.overflow or Enum.any?(rows, & &1.overflow)

        group = %{
          "provider" => provider,
          "billing_mode" => billing,
          "basis" => basis,
          "request_count" => length(rows),
          "unknown_cost_count" => Enum.count(amounts, &is_nil/1),
          "unknown_outcome_count" => Enum.count(rows, & &1.unknown),
          "partial_request_count" => Enum.count(rows, &(not &1.final)),
          "amount_nanos" =>
            if(Enum.all?(amounts, &is_integer/1) and not overflow, do: known.value),
          "known_amount_nanos" => if(not overflow, do: known.value),
          "overflow" => overflow,
          "counts" =>
            Map.new(Usage.counter_fields(), fn field ->
              values = Enum.map(rows, & &1.counts[field])
              subtotal = sum(values)
              complete = Enum.all?(rows, & &1.final) and Enum.all?(values, &is_integer/1)

              counters = %{
                "total" => if(complete, do: subtotal.value),
                "known_subtotal" => subtotal.value,
                "unknown_count" => Enum.count(values, &is_nil/1),
                "overflow" => subtotal.overflow
              }

              counters =
                if operation == "embedding" and field == "output_tokens",
                  do: counters |> Map.put("unknown_count", 0) |> Map.put("not_applicable", true),
                  else: counters

              {field, counters}
            end)
        }

        if operation in ~w(embedding decision),
          do: Map.put(group, "operation", operation),
          else: group
      end)

    complete =
      enumeration_complete and not snapshot["legacy_unmetered"] and
        Enum.all?(groups, &is_integer(&1["amount_nanos"]))

    %{
      "status" => "summarized",
      "coverage" => "session",
      "snapshot" => snapshot,
      "request_count" => map_size(state.requests),
      "enumeration_complete" => enumeration_complete,
      "cost_estimate_complete" => complete,
      "groups" => groups,
      "rate_card" =>
        Map.take(state.card, ~w(id revision currency source published_on))
        |> Map.put("sha256", Ipse.JSON.digest([state.card])),
      "currency_scale" => 9,
      "rounding" => "ceiling_per_request"
    }
  end

  defp sum(values) do
    known = Enum.filter(values, &is_integer/1)
    value = Enum.sum(known)
    overflow = value > @safe
    %{value: if(known != [] and not overflow, do: value), overflow: overflow}
  end
end
