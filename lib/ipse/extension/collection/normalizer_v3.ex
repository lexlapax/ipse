defmodule Ipse.Extension.Collection.NormalizerV3 do
  @moduledoc """
  Host-private automatic managed publication over authenticated IMB2 pages.

  Call only with the actual current Collection witness/read closure and the
  matching Identity callback capability/catalog receipt, after current consent
  and source authentication. Shaped options do not establish that provenance.
  This interpreter supports one fresh fixed-prefix literal or proposal, never
  typed management, stored choices, retirement, import, adoption or resealing.

  No-cache worst-case lookup costs 24 charged units: format/override/public-key
  reads (3), two semantic neighbor/value reads (10), anchor repair including a
  buddy (6), and fresh live insertion repair (5). Every read uses the original
  held closure; an independent local counter also refuses above 32 units.
  """
  alias Ipse.{JSON, Extension.CollectionPolicy, Extension.ManagedRecipe}
  alias Ipse.Extension.Collection.{Directory, ManagedPages, Migration}
  alias Ipse.Extension.Collection.ManagedPages.Planner

  @options ~w(request recipe constraints verified_sources policy_sha256 now_ms domain_cap catalog)a
  @error {:error, :managed_normalization_refused}
  @format "managed-metadata-v3"
  @categories %{"ordinary" => 0, "preference" => 1, "current" => 2}

  @doc "Prepare an explicit unchanged public change plus bounded signed sidecars; perform no publication."
  def normalize(witness, read, options) when is_function(read, 1) do
    checked(fn ->
      true = keys?(options, @options)

      %{
        request: request,
        recipe: recipe,
        constraints: constraints,
        verified_sources: sources,
        policy_sha256: policy,
        now_ms: now,
        domain_cap: cap,
        catalog: catalog
      } = options

      true = JSON.safe_uint?(now) and JSON.sha256?(policy)
      true = ManagedRecipe.valid?(recipe) and recipe["kind"] in ~w(literal_source proposal)
      true = witness["recipe_sha256"] == JSON.digest([recipe])
      true = witness["original_request_sha256"] == JSON.digest([request])
      true = Ipse.Extension.Collection.valid_request?(request) and request["op"] == "commit"
      true = request["advance_floor"] === true
      true = request["expected_generation"] === witness["root"]["generation"]
      [change] = request["changes"]
      true = change["expected_revision"] === 0 and is_map(change["value"])
      true = recipe["constraints_sha256"] == JSON.digest([constraints])
      :ok = CollectionPolicy.check(request, constraints, sources)
      {:ok, candidate} = ManagedRecipe.extract(recipe, change["key"], change["value"], sources)
      :ok = fixed_key!(candidate)
      :ok = catalog!(catalog, witness)
      read = bounded_read(read)
      {:ok, format_record} = read.(ManagedPages.format_key())
      {initial?, format_sha} = format!(cap, format_record, catalog, witness)
      {:ok, nil} = read.(recipe["override_prefix"] <> candidate["lineage"])
      {:ok, nil} = read.(candidate["key"])
      row = selected_row!(cap, :anchor, candidate["lineage"], read, witness)
      row = row || %{"clocks" => [nil, nil, nil, nil], "choice" => nil, "retirement" => nil}
      {updated, first, deadline} = clock!(row, candidate, now)
      true = is_nil(deadline) or now < deadline
      live_id = ManagedPages.live_identity(candidate["key"])
      true = is_nil(selected_row!(cap, :live, live_id, read, witness))
      live = live(candidate, change["value"], policy, first, deadline)
      {:ok, anchor_plan} = Planner.plan(cap, :anchor, [{candidate["lineage"], updated}], read)
      {:ok, live_plan} = Planner.plan(cap, :live, [{live_id, live}], read)
      true = same_root?(anchor_plan, witness) and same_root?(live_plan, witness)
      planned = anchor_plan.changes ++ live_plan.changes
      true = length(planned) <= 5
      true = Enum.count(planned, &is_nil(&1.body)) <= 1
      true = Enum.count(planned, &(not is_nil(&1.body))) + if(initial?, do: 1, else: 0) <= 4
      true = Enum.all?(planned, &(not is_nil(&1.body) or &1.expected_revision > 0))
      {:ok, anchor_changes} = Planner.seal_changes(cap, witness, anchor_plan)
      {:ok, live_changes} = Planner.seal_changes(cap, witness, live_plan)

      {format_changes, format_sha} =
        if initial? do
          {:ok, value} =
            ManagedPages.seal(cap, witness, ManagedPages.format_key(), ManagedPages.format_body())

          {[%{"key" => ManagedPages.format_key(), "expected_revision" => 0, "value" => value}],
           value_sha(value)}
        else
          {[], format_sha}
        end

      extras = format_changes ++ anchor_changes ++ live_changes
      true = length(extras) <= 5 and Enum.count(extras, &(not is_nil(&1["value"]))) <= 4
      true = length(Enum.uniq_by(extras, & &1["key"])) == length(extras)
      normalized = Map.update!(request, "changes", &(&1 ++ extras))
      true = Ipse.Extension.Collection.valid_request?(normalized)

      receipt = %{
        "version" => 3,
        "lineage" => candidate["lineage"],
        "record_key" => candidate["key"],
        "first_admitted_ms" => first,
        "valid_until_ms" => deadline,
        "category" => candidate["category"],
        "eligibility" =>
          if(candidate["kind"] == "proposal", do: "never_current", else: "current"),
        "format_value_sha256" => format_sha,
        "metadata_changes" =>
          Enum.map(extras, fn extra ->
            %{
              "key" => extra["key"],
              "expected_revision" => extra["expected_revision"],
              "value_sha256" =>
                if(is_nil(extra["value"]), do: nil, else: value_sha(extra["value"]))
            }
          end)
      }

      true = byte_size(Migration.encode(receipt)) <= 2048
      {normalized, receipt}
    end)
    |> case do
      {:ok, {normalized, receipt}} -> {:ok, normalized, receipt}
      _ -> @error
    end
  end

  def normalize(_, _, _), do: @error

  def limits,
    do: %{
      read_units: 32,
      worst_read_units: 24,
      metadata_changes: 5,
      nonnull_values: 4,
      deletions: 1,
      receipt_bytes: 2048,
      value_bytes: 6144
    }

  defp bounded_read(read) do
    count = :atomics.new(1, [])

    fn request ->
      {:ok, cost} = Directory.cost(request)
      true = :atomics.add_get(count, 1, cost) <= 32
      read.(request)
    end
  end

  defp fixed_key!(%{"kind" => "literal_source"} = candidate) do
    true = candidate["key"] == "note." <> candidate["lineage"]
    :ok
  end

  defp fixed_key!(%{"kind" => "proposal"} = candidate) do
    {:ok, id} = ManagedRecipe.proposal_identity(candidate["lineage"], candidate["text"])
    true = candidate["key"] == "pending." <> id
    :ok
  end

  defp catalog!(catalog, witness) do
    true = keys?(catalog, ~w(version namespace key_id fence_id format state))
    true = catalog["version"] === 1 and catalog["namespace"] == witness["root"]["project"]
    true = JSON.sha256?(catalog["namespace"]) and catalog["format"] == @format
    true = catalog["state"] in ~w(prepared active)
    true = Enum.all?(~w(key_id fence_id), &id?(catalog[&1]))
    :ok
  end

  defp format!(_cap, nil, catalog, witness) do
    true = catalog["state"] == "prepared" and witness["root_state"] == "absent"
    {true, nil}
  end

  defp format!(cap, record, catalog, witness) do
    true = catalog["state"] == "active" and witness["root_state"] == "present"
    true = record["revision"] <= witness["root"]["generation"]
    {:ok, _} = ManagedPages.open_format(cap, record)
    {false, value_sha(record["value"])}
  end

  defp selected_row!(cap, kind, id, read, witness) do
    request = %{
      "op" => "neighbors",
      "request" => %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(kind),
        "fence_bytes" => ManagedPages.width(kind),
        "needle" => id
      }
    }

    {:ok, o} = read.(request)
    {:ok, _} = ManagedPages.observation(o)
    true = o["summary"] == witness["root"]

    true =
      Enum.all?(~w(root_state root_sha256 manifest_sha256), &(o["witness"][&1] == witness[&1]))

    case o["state"] do
      "uninitialized" ->
        nil

      "initialized" ->
        {:ok, record} = read.(o["neighbors"]["selected"]["key"])
        true = record["revision"] <= witness["root"]["generation"]
        {:ok, page} = ManagedPages.open(cap, record, o)
        page.entries[id]
    end
  end

  defp same_root?(plan, witness),
    do:
      plan.summary == witness["root"] and
        Enum.all?(~w(root_state root_sha256 manifest_sha256), &(plan.witness[&1] == witness[&1]))

  # Keep V2's private clock semantics intact without changing that existing
  # interpreter's bytes or introducing a generic policy framework.
  defp clock!(
         %{
           "clocks" => [note, baseline, pending, pending_base],
           "choice" => nil,
           "retirement" => nil
         } = row,
         candidate,
         now
       )
       when map_size(row) == 3 do
    true = (is_nil(note) or note <= now) and (is_nil(pending) or pending <= now)

    case candidate["kind"] do
      "literal_source" ->
        first = note || now
        next = deadline!(first, candidate["max_age_ms"])
        next = if is_nil(note), do: next, else: earlier(baseline, next)
        {%{row | "clocks" => [first, next, pending, pending_base]}, first, next}

      "proposal" ->
        first = pending || now
        next = deadline!(first, candidate["max_age_ms"])
        next = if is_nil(pending), do: next, else: earlier(pending_base, next)
        {%{row | "clocks" => [note, baseline, first, next]}, first, next}
    end
  end

  defp deadline!(_, nil), do: nil

  defp deadline!(first, age) do
    result = first + age
    true = JSON.safe_uint?(result)
    result
  end

  defp earlier(nil, value), do: value
  defp earlier(value, nil), do: value
  defp earlier(a, b), do: min(a, b)

  defp live(candidate, value, policy, first, deadline) do
    Enum.map(
      [candidate["lineage"], value_sha(value), candidate["recipe_sha256"], policy],
      fn hash -> Base.url_encode64(Base.decode16!(hash, case: :lower), padding: false) end
    ) ++
      [
        base36(first),
        base36(deadline),
        Map.fetch!(@categories, candidate["category"]),
        if(candidate["kind"] == "proposal", do: 1, else: 0)
      ]
  end

  defp base36(nil), do: nil
  defp base36(value), do: value |> Integer.to_string(36) |> String.downcase()
  defp value_sha(value), do: JSON.sha256(Migration.encode(value))
  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)

  defp checked(fun) do
    {:ok, fun.()}
  rescue
    _ -> @error
  end
end
