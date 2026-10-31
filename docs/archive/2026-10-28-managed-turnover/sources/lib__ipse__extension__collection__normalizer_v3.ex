defmodule Ipse.Extension.Collection.NormalizerV3 do
  @moduledoc """
  Host-private automatic managed publication over authenticated IMB2 pages.

  Call only with the actual current Collection witness/read closure and the
  matching Identity callback capability/catalog receipt, after current consent
  and source authentication. Shaped options do not establish that provenance.
  Automatic normalization supports one fresh fixed-prefix literal or proposal.
  The separate host-only forget entry point requires an actual one-use native
  review permit and retains signed suppression. Import, adoption and resealing
  are not supported here.

  No-cache worst-case lookup costs 32 charged units: format/override/public-key
  reads (3), two semantic neighbor/value reads (10), anchor repair including a
  buddy (6), fresh live insertion repair (5), and a bounded pending-reference
  summary for proposals (8). Every read uses the original held closure; an
  independent local counter also refuses above 32 units.
  """
  alias Ipse.{JSON, Extension.CollectionPolicy, Extension.ManagedRecipe}
  alias Ipse.Extension.Collection.{Directory, ManagedPages, Migration, PendingCapacity}
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
      :ok = PendingCapacity.check(candidate, change["value"], read)
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

  @doc """
  Forget one exact signed literal under the owning host's management boundary.

  The host must journal intent and revalidate current management authority before
  entering the actual Collection callback. This does not use an automatic-capture
  grant. The actual owner-bound native permit is consumed only after the stored
  target, original root, full review facts and bounded repairs are revalidated.
  Expired or unavailable source evidence does not prevent deleting its derivative.
  """
  def forget(witness, read, options) when is_function(read, 1) do
    checked(fn ->
      true = keys?(options, ~w(request facts permit now_ms domain_cap catalog)a)

      %{
        request: request,
        facts: facts,
        permit: permit,
        now_ms: now,
        domain_cap: cap,
        catalog: catalog
      } = options

      true = JSON.safe_uint?(now)
      true = Ipse.Session.ManagedLifecycle.context?(facts["context"])
      context = facts["context"]
      recipe = context["recipe"]
      true = witness["recipe_sha256"] == JSON.digest([recipe])
      true = witness["original_request_sha256"] == JSON.digest([request])
      true = witness["operation_id"] == facts["operation_id"]
      true = witness["root"]["project"] == context["namespace"]
      true = witness["root_state"] == "present" and catalog["state"] == "active"
      :ok = catalog!(catalog, witness)
      true = Ipse.Extension.Collection.valid_request?(request)
      true = request["op"] == "commit" and request["advance_floor"] === true
      true = request["expected_generation"] === witness["root"]["generation"]
      [%{"key" => key, "expected_revision" => revision, "value" => nil}] = request["changes"]
      "note." <> lineage = key
      true = JSON.sha256?(lineage) and key == recipe["key_prefix"] <> lineage
      read = bounded_read(read)
      {:ok, format} = read.(ManagedPages.format_key())
      {false, _} = format!(cap, format, catalog, witness)
      {:ok, record} = read.(key)
      true = is_map(record) and record["key"] == key and record["revision"] === revision
      true = revision > 0 and revision <= witness["root"]["generation"]
      true = record["sha256"] == value_sha(record["value"])
      {:ok, nil} = read.(recipe["override_prefix"] <> lineage)

      {:ok, candidate} =
        ManagedRecipe.extract(
          recipe,
          key,
          record["value"],
          get_in(record["value"], recipe["evidence_path"])
        )

      true = candidate["kind"] == "literal_source" and candidate["lineage"] == lineage
      anchor = selected_row!(cap, :anchor, lineage, read, witness)
      %{"clocks" => [first, deadline, _, _], "choice" => nil, "retirement" => nil} = anchor
      true = JSON.safe_uint?(first) and first <= now
      true = is_nil(deadline) or (JSON.safe_uint?(deadline) and deadline >= first)
      live_id = ManagedPages.live_identity(key)
      live = selected_row!(cap, :live, live_id, read, witness)

      [
        packed_lineage,
        packed_value,
        packed_recipe,
        packed_policy,
        live_first,
        live_deadline,
        category,
        0
      ] = live

      true = unpack_hash(packed_lineage) == lineage
      true = unpack_hash(packed_value) == record["sha256"]
      true = unpack_hash(packed_recipe) == JSON.digest([recipe])
      true = live_first == base36(first) and live_deadline == base36(deadline)
      true = category == Map.fetch!(@categories, candidate["category"])

      metadata = %{
        "lineage" => lineage,
        "recipe_sha256" => JSON.digest([recipe]),
        "policy_sha256" => unpack_hash(packed_policy),
        "first_admitted_ms" => first,
        "valid_until_ms" => deadline,
        "category" => candidate["category"]
      }

      :ok = forget_facts!(facts, request, witness, record, metadata)

      # The exact semantic checks precede spending native authority. The outer
      # Review callback withholds success after any consumed failure or
      # unconfirmed cleanup, including a refused bounded page repair.
      {:ok, review} = Ipse.Runner.Review.consume(permit, "forget", facts)
      true = review["observed_at_ms"] <= now and review["facts_sha256"] == JSON.digest([facts])

      capsule = %{
        "version" => 2,
        "kind" => "native_management",
        "lineage" => lineage,
        "event_id" => review["event_id"],
        "display_sha256" => review["display_sha256"],
        "challenge" => review["challenge"],
        "input_sha256" => review["input_sha256"],
        "observed_at_ms" => review["observed_at_ms"],
        "target_key" => key,
        "target_value_sha256" => record["sha256"],
        "policy" => %{"kind" => "session"},
        "reason" => facts["reason"]
      }

      updated = %{
        anchor
        | "choice" => capsule,
          "retirement" => %{"target_kind" => "native_literal_note", "at_ms" => now}
      }

      {:ok, anchor_plan} = Planner.plan(cap, :anchor, [{lineage, updated}], read)
      {:ok, live_plan} = Planner.plan(cap, :live, [{live_id, nil}], read)
      true = same_root?(anchor_plan, witness) and same_root?(live_plan, witness)
      {:ok, anchors} = Planner.seal_changes(cap, witness, anchor_plan)
      {:ok, lives} = Planner.seal_changes(cap, witness, live_plan)
      extras = anchors ++ lives
      true = length(extras) in 1..5
      true = Enum.count(extras, &is_nil(&1["value"])) <= 1
      true = Enum.count(extras, &(not is_nil(&1["value"]))) <= 4
      true = length(Enum.uniq_by(extras, & &1["key"])) == length(extras)
      normalized = Map.update!(request, "changes", &(&1 ++ extras))
      true = Ipse.Extension.Collection.valid_request?(normalized)

      receipt = %{
        "version" => 3,
        "kind" => "native_literal_forget",
        "lineage" => lineage,
        "record_key" => key,
        "action_sha256" => facts["action_sha256"],
        "native_review_sha256" => JSON.digest([review]),
        "eligibility" => "retired",
        "retired_at_ms" => now,
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
      {:ok, {request, receipt}} -> {:ok, request, receipt}
      _ -> @error
    end
  end

  def forget(_, _, _), do: @error

  defp forget_facts!(facts, request, witness, record, metadata) do
    true =
      keys?(
        facts,
        ~w(version kind operation_id context collection target metadata policy reason request_sha256 scope action_sha256)
      )

    true = facts["version"] === 1 and facts["kind"] == "managed_literal_forget"
    true = id?(facts["operation_id"])

    true =
      facts["collection"] == Map.take(witness, ~w(root_state root root_sha256 manifest_sha256))

    true = facts["target"] === record and facts["metadata"] === metadata
    true = facts["request_sha256"] == JSON.digest([request])
    true = facts["policy"] === %{"kind" => "session"}

    true =
      facts["scope"] == "selected literal derivative; original journal and shared evidence remain"

    reason = facts["reason"]
    true = is_binary(reason) and String.valid?(reason) and byte_size(reason) in 1..64
    true = facts["action_sha256"] == JSON.digest([Map.delete(facts, "action_sha256")])
    true = byte_size(Jason.encode!(facts)) <= 16_384
    :ok
  end

  defp unpack_hash(value),
    do: value |> Base.url_decode64!(padding: false) |> Base.encode16(case: :lower)

  def limits,
    do: %{
      read_units: 32,
      worst_read_units: 32,
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
