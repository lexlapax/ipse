defmodule Ipse.Extension.Collection.Normalizer do
  @moduledoc """
  Trusted managed-publication interpreter with packed, retained source clocks.

  Call only inside Collection.execute_managed's callback, after current consent
  and source authentication. Schemas and authenticated proof membership are
  rechecked, but this module attests neither its caller nor operator acceptance.
  Automatic publication supports one new literal or pending value. Correction,
  typed acceptance and operator override creation require separate host journeys.
  """
  alias Ipse.{JSON, Extension.CollectionPolicy, Extension.ManagedRecipe}
  alias Ipse.Extension.Collection.Migration
  @options ~w(request recipe constraints verified_sources policy_sha256 now_ms)a
  @prefix "host.validity."
  @source_fields ~w(session_id occurrence_id version_id kind origin content_sha256 receipt_sha256)
  @live ~w(version record_key lineage first_admitted_ms valid_until_ms category eligibility recipe_sha256 policy_sha256 record_value_sha256 sources)
  @error {:error, :managed_normalization_refused}

  @doc "Return an explicit normalized commit and a hash-bound host receipt; never execute publication."
  def normalize(witness, read, options) when is_function(read, 1) do
    with true <- keys?(options, @options),
         %{
           request: request,
           recipe: recipe,
           constraints: constraints,
           verified_sources: sources,
           policy_sha256: policy,
           now_ms: now
         } <- options,
         true <- JSON.safe_uint?(now) and JSON.sha256?(policy),
         true <- ManagedRecipe.valid?(recipe),
         true <- recipe["kind"] in ~w(literal_source proposal),
         true <- witness["recipe_sha256"] == JSON.digest([recipe]),
         true <- witness["original_request_sha256"] == JSON.digest([request]),
         true <- Ipse.Extension.Collection.valid_request?(request) and request["op"] == "commit",
         true <- request["advance_floor"] === true,
         true <- request["expected_generation"] === witness["root"]["generation"],
         [change] <- request["changes"],
         true <- change["expected_revision"] === 0 and is_map(change["value"]),
         true <- recipe["constraints_sha256"] == JSON.digest([constraints]),
         :ok <- CollectionPolicy.check(request, constraints, sources),
         {:ok, candidate} <-
           ManagedRecipe.extract(recipe, change["key"], change["value"], sources),
         {:ok, nil} <- read.(recipe["override_prefix"] <> candidate["lineage"]),
         {:ok, anchor_bucket} <- bucket(read, :anchor, candidate["lineage"]),
         {:ok, row} <- anchor_row(anchor_bucket, candidate["lineage"]),
         {:ok, updated, first, deadline} <- clock(row, candidate, now),
         true <- is_nil(deadline) or now < deadline,
         {:ok, anchor_change} <- put(anchor_bucket, candidate["lineage"], updated),
         live_id = JSON.sha256(candidate["key"]),
         {:ok, live_bucket} <- bucket(read, :live, live_id),
         true <- not Map.has_key?(live_bucket.index, live_id),
         live = live(candidate, change["value"], policy, first, deadline),
         true <- live?(live_id, live),
         {:ok, live_change} <- put(live_bucket, live_id, live) do
      normalized = Map.update!(request, "changes", &(&1 ++ [anchor_change, live_change]))

      receipt = %{
        "version" => 2,
        "lineage" => candidate["lineage"],
        "record_key" => candidate["key"],
        "first_admitted_ms" => first,
        "valid_until_ms" => deadline,
        "category" => candidate["category"],
        "eligibility" => live["eligibility"],
        "anchor_key" => anchor_change["key"],
        "anchor_value_sha256" => JSON.sha256(Migration.encode(anchor_change["value"])),
        "live_key" => live_change["key"],
        "live_value_sha256" => JSON.sha256(Migration.encode(live_change["value"]))
      }

      {:ok, normalized, receipt}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def normalize(_, _, _), do: @error

  @doc "Fixed packed metadata limits; overflow refuses and never evicts an anchor."
  def limits do
    %{
      "anchor_shards" => 256,
      "anchor_pages" => 8,
      "anchors_per_page" => 16,
      "live_shards" => 512,
      "live_pages" => 4,
      "live_per_page" => 4,
      "value_bytes" => 6144
    }
  end

  # Clocks are separate: an unaccepted paraphrase cannot start an ordinary
  # note's observation window, and another paraphrase cannot renew its own.
  defp clock([note_first, baseline, pending_first, pending_base, nil], candidate, now)
       when (is_nil(note_first) or note_first <= now) and
              (is_nil(pending_first) or pending_first <= now) do
    case candidate["kind"] do
      "literal_source" ->
        first = note_first || now

        with {:ok, rule_deadline} <- deadline(first, candidate["max_age_ms"]),
             baseline =
               if(is_nil(note_first), do: rule_deadline, else: earlier(baseline, rule_deadline)) do
          {:ok, [first, baseline, pending_first, pending_base, nil], first, baseline}
        end

      "proposal" ->
        first = pending_first || now

        with {:ok, expires} <- deadline(first, candidate["max_age_ms"]),
             expires =
               if(is_nil(pending_first), do: expires, else: earlier(pending_base, expires)) do
          {:ok, [note_first, baseline, first, expires, nil], first, expires}
        end
    end
  end

  # No typed management journey creates overrides yet. Stored legacy JSON or an
  # unexpected metadata choice cannot stand in for that missing host receipt.
  defp clock(_, _, _), do: @error

  defp deadline(_, nil), do: {:ok, nil}

  defp deadline(first, age) do
    if JSON.safe_uint?(first + age), do: {:ok, first + age}, else: @error
  end

  defp earlier(nil, value), do: value
  defp earlier(value, nil), do: value
  defp earlier(a, b), do: min(a, b)

  defp anchor_row(bucket, identity) do
    case bucket.index[identity] do
      nil -> {:ok, [nil, nil, nil, nil, nil]}
      {_page, value} -> {:ok, value}
    end
  end

  defp live(candidate, value, policy, first, deadline) do
    %{
      "version" => 2,
      "record_key" => candidate["key"],
      "lineage" => candidate["lineage"],
      "first_admitted_ms" => first,
      "valid_until_ms" => deadline,
      "category" => candidate["category"],
      "eligibility" => if(candidate["kind"] == "proposal", do: "never_current", else: "current"),
      "recipe_sha256" => candidate["recipe_sha256"],
      "policy_sha256" => policy,
      "record_value_sha256" => JSON.sha256(Migration.encode(value)),
      "sources" => Enum.map(candidate["sources"], &Map.take(&1, @source_fields))
    }
  end

  defp bucket(read, kind, identity) do
    {shard, pages, capacity} = dimensions(kind, identity)

    Enum.reduce_while(
      0..(pages - 1),
      {:ok,
       %{kind: kind, shard: shard, capacity: capacity, pages: [], index: %{}, absent: false}},
      fn page, {:ok, acc} ->
        key = @prefix <> Atom.to_string(kind) <> "." <> shard <> "." <> Integer.to_string(page)

        case read.(key) do
          {:ok, nil} ->
            {:cont,
             {:ok,
              %{acc | absent: true, pages: acc.pages ++ [%{key: key, revision: 0, value: nil}]}}}

          {:ok, %{"key" => ^key, "revision" => revision, "value" => value}} ->
            if not acc.absent and JSON.safe_uint?(revision) and revision > 0 and
                 page?(value, kind, shard, page, capacity) and
                 Enum.all?(value["entries"], fn {id, _} -> not Map.has_key?(acc.index, id) end) and
                 (page == 0 or map_size(List.last(acc.pages).value["entries"]) == capacity) do
              index = Map.new(value["entries"], fn {id, row} -> {id, {page, row}} end)

              {:cont,
               {:ok,
                %{
                  acc
                  | pages: acc.pages ++ [%{key: key, revision: revision, value: value}],
                    index: Map.merge(acc.index, index)
                }}}
            else
              {:halt, @error}
            end

          _ ->
            {:halt, @error}
        end
      end
    )
  end

  defp dimensions(:anchor, identity), do: {binary_part(identity, 0, 2), 8, 16}

  defp dimensions(:live, identity) do
    shard = identity |> binary_part(0, 3) |> String.to_integer(16) |> rem(512)
    {shard |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(3, "0"), 4, 4}
  end

  defp page?(value, kind, shard, page, capacity) do
    keys?(value, ~w(version kind shard page entries)) and value["version"] === 2 and
      value["kind"] == Atom.to_string(kind) and value["shard"] == shard and value["page"] === page and
      is_map(value["entries"]) and map_size(value["entries"]) in 1..capacity and
      Enum.all?(value["entries"], fn {id, row} ->
        JSON.sha256?(id) and elem(dimensions(kind, id), 0) == shard and
          if(kind == :anchor, do: anchor?(row), else: live?(id, row))
      end) and bounded?(value)
  rescue
    _ -> false
  end

  defp put(bucket, identity, row) do
    selected =
      case bucket.index[identity] do
        {page, _} ->
          Enum.at(bucket.pages, page)

        nil ->
          Enum.find(
            bucket.pages,
            &(is_nil(&1.value) or map_size(&1.value["entries"]) < bucket.capacity)
          )
      end

    if selected do
      page = Enum.find_index(bucket.pages, &(&1.key == selected.key))

      value =
        selected.value ||
          %{
            "version" => 2,
            "kind" => Atom.to_string(bucket.kind),
            "shard" => bucket.shard,
            "page" => page,
            "entries" => %{}
          }

      value = Map.update!(value, "entries", &Map.put(&1, identity, row))

      if bounded?(value),
        do:
          {:ok,
           %{"key" => selected.key, "expected_revision" => selected.revision, "value" => value}},
        else: @error
    else
      @error
    end
  end

  defp anchor?([first, baseline, pending, pending_base, nil]) do
    nullable_uint?(first) and nullable_uint?(baseline) and nullable_uint?(pending) and
      nullable_uint?(pending_base) and
      (not is_nil(first) or not is_nil(pending)) and
      (not is_nil(first) or is_nil(baseline)) and
      (is_nil(baseline) or baseline >= first) and
      ((is_nil(pending) and is_nil(pending_base)) or
         (is_integer(pending) and is_integer(pending_base) and pending_base >= pending))
  end

  defp anchor?(_), do: false

  defp live?(id, value) do
    keys?(value, @live) and value["version"] === 2 and
      Ipse.Extension.Collection.valid_request?(%{"op" => "get", "key" => value["record_key"]}) and
      JSON.sha256(value["record_key"]) == id and JSON.sha256?(value["lineage"]) and
      JSON.safe_uint?(value["first_admitted_ms"]) and nullable_uint?(value["valid_until_ms"]) and
      (is_nil(value["valid_until_ms"]) or value["valid_until_ms"] >= value["first_admitted_ms"]) and
      value["category"] in ~w(ordinary preference current) and
      value["eligibility"] in ~w(current never_current) and
      (value["category"] != "ordinary" or is_integer(value["valid_until_ms"])) and
      (value["eligibility"] != "never_current" or is_integer(value["valid_until_ms"])) and
      Enum.all?(~w(recipe_sha256 policy_sha256 record_value_sha256), &JSON.sha256?(value[&1])) and
      is_list(value["sources"]) and length(value["sources"]) == 1 and
      Enum.all?(value["sources"], &source?/1) and
      (value["eligibility"] != "current" or
         Enum.all?(value["sources"], fn source ->
           source["origin"] in ~w(interactive_operator native_operator_answer typed_host_outcome) and
             (source["origin"] != "typed_host_outcome" or value["category"] == "ordinary")
         end))
  rescue
    _ -> false
  end

  defp source?(source) do
    keys?(source, @source_fields) and
      Enum.all?(~w(session_id occurrence_id version_id), fn key ->
        is_binary(source[key]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, source[key])
      end) and
      Enum.all?(~w(content_sha256 receipt_sha256), &JSON.sha256?(source[&1])) and
      source["kind"] in ~w(input.original input.operator_answer answer.original tool.outcome) and
      source["origin"] in ~w(interactive_operator native_operator_answer typed_host_outcome unattended_input assistant_proposal) and
      source_kind?(source)
  end

  defp source_kind?(%{"origin" => origin, "kind" => kind}) do
    case origin do
      "interactive_operator" -> kind == "input.original"
      "unattended_input" -> kind == "input.original"
      "native_operator_answer" -> kind == "input.operator_answer"
      "assistant_proposal" -> kind == "answer.original"
      "typed_host_outcome" -> kind == "tool.outcome"
    end
  end

  defp nullable_uint?(nil), do: true
  defp nullable_uint?(value), do: JSON.safe_uint?(value)

  defp bounded?(value),
    do: JSON.validate_object(value) == :ok and byte_size(Migration.encode(value)) <= 6144

  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
end
