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

  alias Ipse.Extension.Collection.{
    Directory,
    ManagedPages,
    ManagedRetention,
    Migration,
    PendingCapacity
  }

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
  Reclaim one exactly observed signed ordinary literal after its stored deadline.

  The owning host must journal and reserve this reducing management operation
  under the current protected project/epoch before invoking Core. No capture
  grant, native review, source re-reading or worker clock is substituted for that
  authority. The original anchor and admission clocks remain unchanged, so the
  same expired source cannot be admitted with a renewed clock.
  """
  def expire(witness, read, options), do: expire_kind(witness, read, options, :ordinary)

  @doc "Reclaim one finite, elapsed historical literal while retaining its signed successor edge."
  def expire_history(witness, read, options), do: expire_kind(witness, read, options, :history)

  @doc "Reclaim an accepted decision after its signed finite deadline; retain its immutable link and admission clocks."
  def expire_accepted(witness, read, options), do: expire_kind(witness, read, options, :accepted)

  defp expire_kind(witness, read, options, kind) when is_function(read, 1) do
    cache = :ets.new(__MODULE__, [:set, :private])

    try do
      checked(fn ->
        true = keys?(options, ~w(request facts now_ms domain_cap catalog)a)

        %{request: request, facts: facts, now_ms: now, domain_cap: cap, catalog: catalog} =
          options

        true = JSON.safe_uint?(now) and Ipse.Session.ManagedLifecycle.context?(facts["context"])
        recipe = facts["context"]["recipe"]
        true = witness["recipe_sha256"] == JSON.digest([recipe])
        true = witness["original_request_sha256"] == JSON.digest([request])
        true = witness["operation_id"] == facts["operation_id"]
        true = witness["root"]["project"] == facts["context"]["namespace"]
        true = witness["root_state"] == "present" and catalog["state"] == "active"
        :ok = catalog!(catalog, witness)
        true = Ipse.Extension.Collection.valid_request?(request) and request["op"] == "commit"
        true = request["advance_floor"] === true
        true = request["expected_generation"] === witness["root"]["generation"]

        [%{"key" => "note." <> lineage = key, "expected_revision" => revision, "value" => nil}] =
          request["changes"]

        true = JSON.sha256?(lineage) and key == recipe["key_prefix"] <> lineage
        read = cached_read(read, cache)
        {:ok, format} = read.(ManagedPages.format_key())
        {false, _} = format!(cap, format, catalog, witness)
        {:ok, nil} = read.(recipe["override_prefix"] <> lineage)
        {:ok, record} = read.(key)
        true = is_map(record) and record["key"] == key and record["revision"] === revision
        true = revision > 0 and revision <= witness["root"]["generation"]
        true = record["sha256"] == value_sha(record["value"])

        anchor = selected_row!(cap, :anchor, lineage, read, witness)
        live_id = ManagedPages.live_identity(key)
        live = selected_row!(cap, :live, live_id, read, witness)

        metadata =
          if kind == :accepted do
            {:ok, link} = read.("accept." <> record["value"]["candidate_id"])

            {:ok, metadata} =
              Ipse.Session.PendingAcceptance.retained_decision_metadata(
                recipe,
                record,
                link,
                anchor,
                live
              )

            true =
              Ipse.Session.PendingAcceptance.expired_retained_decision_metadata?(metadata, now)

            metadata
          else
            {:ok, candidate} =
              ManagedRecipe.extract(
                recipe,
                key,
                record["value"],
                get_in(record["value"], recipe["evidence_path"])
              )

            true = candidate["kind"] == "literal_source" and candidate["lineage"] == lineage

            {:ok, metadata} =
              if kind == :history,
                do: ManagedRetention.history_metadata(candidate, record["sha256"], anchor, live),
                else: ManagedRetention.metadata(candidate, record["sha256"], anchor, live)

            true =
              if kind == :history,
                do: ManagedRetention.expired_history_metadata?(metadata, now),
                else:
                  ManagedRetention.expired_metadata?(candidate, record["sha256"], metadata, now)

            metadata
          end

        :ok = expiry_facts!(facts, request, witness, record, metadata, now, kind)
        {:ok, plan} = Planner.plan(cap, :live, [{live_id, nil}], read)
        true = same_root?(plan, witness)
        {:ok, lives} = Planner.seal_changes(cap, witness, plan)

        anchors =
          if kind == :history and not is_nil(anchor["choice"]) do
            # Once the finite history has elapsed, the signed retirement still
            # blocks recapture and retains the successor edge. The full reviewed
            # choice was included in the journaled expiry facts before this call.
            {:ok, commitment} = ManagedPages.compact_choice(lineage, anchor["choice"])
            compacted = %{anchor | "choice" => commitment}

            case Planner.plan(cap, :anchor, [{lineage, compacted}], read) do
              {:ok, anchor_plan} ->
                true = same_root?(anchor_plan, witness)
                planned = anchor_plan.changes

                deleted =
                  Enum.count(lives, &is_nil(&1["value"])) + Enum.count(planned, &is_nil(&1.body))

                written =
                  Enum.count(lives, &(not is_nil(&1["value"]))) +
                    Enum.count(planned, &(not is_nil(&1.body)))

                if length(lives) + length(planned) <= 5 and deleted <= 1 and written <= 4 do
                  {:ok, changes} = Planner.seal_changes(cap, witness, anchor_plan)
                  changes
                else
                  []
                end

              _ ->
                []
            end
          else
            []
          end

        extras = lives ++ anchors
        true = length(extras) in 1..5
        true = Enum.count(extras, &is_nil(&1["value"])) <= 1
        true = Enum.count(extras, &(not is_nil(&1["value"]))) <= 4
        normalized = Map.update!(request, "changes", &(&1 ++ extras))
        true = Ipse.Extension.Collection.valid_request?(normalized)

        receipt = %{
          "version" => 3,
          "kind" => expiry_kind(kind),
          "lineage" => lineage,
          "record_key" => key,
          "action_sha256" => facts["action_sha256"],
          "eligibility" => "expired",
          "first_admitted_ms" => metadata["first_admitted_ms"],
          "valid_until_ms" => metadata["valid_until_ms"],
          "checked_at_ms" => now,
          "policy_sha256" => metadata["policy_sha256"],
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

        receipt =
          if kind == :history,
            do: Map.put(receipt, "retention_choice_compacted", anchors != []),
            else: receipt

        true = byte_size(Migration.encode(receipt)) <= 2048
        {normalized, receipt}
      end)
      |> case do
        {:ok, {request, receipt}} -> {:ok, request, receipt}
        _ -> @error
      end
    after
      :ets.delete(cache)
    end
  end

  defp expire_kind(_, _, _, _), do: @error

  @doc "Prepare one native-reviewed successor and its signed, noncurrent history in the held collection callback."
  def supersede(witness, read, options) when is_function(read, 1) do
    cache = :ets.new(__MODULE__, [:set, :private])

    try do
      checked(fn ->
        true =
          keys?(
            options,
            ~w(request facts permit constraints verified_sources policy_sha256 now_ms capture_expires_at_ms domain_cap catalog)a
          )

        %{
          request: request,
          facts: facts,
          permit: permit,
          constraints: constraints,
          verified_sources: sources,
          policy_sha256: policy,
          now_ms: now,
          capture_expires_at_ms: expires,
          domain_cap: cap,
          catalog: catalog
        } = options

        true =
          JSON.safe_uint?(now) and JSON.safe_uint?(expires) and expires > now and
            JSON.sha256?(policy)

        true = Ipse.Session.ManagedLifecycle.context?(facts["context"])
        recipe = facts["context"]["recipe"]
        true = recipe["constraints_sha256"] == JSON.digest([constraints])

        true =
          witness["recipe_sha256"] == JSON.digest([recipe]) and
            witness["original_request_sha256"] == JSON.digest([request])

        true =
          witness["operation_id"] == facts["operation_id"] and
            witness["root"]["project"] == facts["context"]["namespace"]

        true = witness["root_state"] == "present" and catalog["state"] == "active"
        :ok = catalog!(catalog, witness)

        true =
          Ipse.Extension.Collection.valid_request?(request) and request["op"] == "commit" and
            request["advance_floor"] === true

        true = request["expected_generation"] === witness["root"]["generation"]
        [old_change, new_change] = request["changes"]
        true = old_change["expected_revision"] > 0 and new_change["expected_revision"] === 0

        true =
          old_change["key"] != new_change["key"] and is_map(old_change["value"]) and
            is_map(new_change["value"])

        :ok = CollectionPolicy.check(%{request | "changes" => [new_change]}, constraints, sources)

        {:ok, next} =
          ManagedRecipe.extract(recipe, new_change["key"], new_change["value"], sources)

        :ok = fixed_key!(next)

        true =
          (facts["mode"] == "ordinary" and next["category"] == "ordinary") or
            (facts["mode"] == "temporal" and next["category"] == "current")

        read = cached_read(read, cache)
        {:ok, format} = read.(ManagedPages.format_key())
        {false, _} = format!(cap, format, catalog, witness)
        {:ok, record} = read.(old_change["key"])

        true =
          is_map(record) and record["revision"] === old_change["expected_revision"] and
            record["value"] === old_change["value"]

        true = record["sha256"] == value_sha(record["value"])
        {:ok, nil} = read.(new_change["key"])

        {:ok, old} =
          ManagedRecipe.extract(
            recipe,
            record["key"],
            record["value"],
            get_in(record["value"], recipe["evidence_path"])
          )

        :ok = fixed_key!(old)
        true = old["lineage"] != next["lineage"]
        true = old["text"] != next["text"]
        {:ok, nil} = read.(recipe["override_prefix"] <> old["lineage"])
        {:ok, nil} = read.(recipe["override_prefix"] <> next["lineage"])
        anchor = selected_row!(cap, :anchor, old["lineage"], read, witness)
        old_id = ManagedPages.live_identity(record["key"])
        live = selected_row!(cap, :live, old_id, read, witness)
        {:ok, metadata} = ManagedRetention.metadata(old, record["sha256"], anchor, live)
        true = ManagedRetention.eligible_metadata?(old, record["sha256"], metadata, now)
        true = is_nil(selected_row!(cap, :anchor, next["lineage"], read, witness))
        next_id = ManagedPages.live_identity(next["key"])
        true = is_nil(selected_row!(cap, :live, next_id, read, witness))

        :ok =
          supersession_facts!(
            facts,
            witness,
            request,
            record,
            metadata,
            next,
            sources,
            policy,
            now
          )

        {:ok, _} = ManagedRetention.history_deadline(metadata, facts["mode"], now)
        command = if facts["mode"] == "ordinary", do: "correct", else: "supersede"
        {:ok, review} = Ipse.Runner.Review.consume(permit, command, facts)
        at = review["observed_at_ms"]

        true =
          review["facts_sha256"] == JSON.digest([facts]) and at >= facts["checked_at_ms"] and
            at <= now

        {:ok, history_deadline} = ManagedRetention.history_deadline(metadata, facts["mode"], at)
        fresh = %{"clocks" => [nil, nil, nil, nil], "choice" => nil, "retirement" => nil}
        {new_anchor, first, baseline} = clock!(fresh, next, now)

        deadline =
          if facts["mode"] == "ordinary",
            do: earlier(baseline, metadata["valid_until_ms"]),
            else: baseline

        true = is_nil(deadline) or deadline > now
        [_, _, pending, pending_base] = new_anchor["clocks"]
        new_anchor = %{new_anchor | "clocks" => [first, deadline, pending, pending_base]}

        retired = %{
          anchor
          | "retirement" => %{
              "record_key" => next["key"],
              "record_value_sha256" => value_sha(new_change["value"]),
              "at_ms" => at
            }
        }

        old_live =
          live
          |> List.replace_at(5, base36(history_deadline))
          |> List.replace_at(6, 4)
          |> List.replace_at(7, 2)

        new_live = live(next, new_change["value"], policy, first, deadline)

        {:ok, anchor_plan} =
          Planner.plan(
            cap,
            :anchor,
            [{old["lineage"], retired}, {next["lineage"], new_anchor}],
            read
          )

        {:ok, live_plan} =
          Planner.plan(cap, :live, [{old_id, old_live}, {next_id, new_live}], read)

        true = same_root?(anchor_plan, witness) and same_root?(live_plan, witness)
        {:ok, anchors} = Planner.seal_changes(cap, witness, anchor_plan)
        {:ok, lives} = Planner.seal_changes(cap, witness, live_plan)
        extras = anchors ++ lives
        true = length(extras) in 1..8 and Enum.all?(extras, &is_map(&1["value"]))
        true = length(Enum.uniq_by(extras, & &1["key"])) == length(extras)
        normalized = Map.update!(request, "changes", &(&1 ++ extras))
        true = Ipse.Extension.Collection.valid_request?(normalized)

        publish_before =
          [expires, metadata["valid_until_ms"], deadline, history_deadline]
          |> Enum.reject(&is_nil/1)
          |> Enum.min()

        true = publish_before > now

        receipt = %{
          "version" => 3,
          "kind" => "native_literal_supersession",
          "action_sha256" => facts["action_sha256"],
          "native_review_sha256" => JSON.digest([review]),
          "old_lineage" => old["lineage"],
          "new_lineage" => next["lineage"],
          "history_valid_until_ms" => history_deadline,
          "first_admitted_ms" => first,
          "valid_until_ms" => deadline,
          "publish_before_ms" => publish_before,
          "metadata_refs" =>
            Enum.map(extras, fn extra ->
              [extra["key"], extra["expected_revision"], value_sha(extra["value"])]
            end)
        }

        true = byte_size(Migration.encode(receipt)) <= 2048

        true =
          byte_size(
            Jason.encode!(%{"request" => normalized, "facts" => facts, "receipt" => receipt})
          ) <= 65_536

        {normalized, receipt}
      end)
      |> case do
        {:ok, {normalized, receipt}} -> {:ok, normalized, receipt}
        _ -> @error
      end
    after
      :ets.delete(cache)
    end
  end

  def supersede(_, _, _), do: @error

  defp supersession_facts!(facts, witness, request, record, metadata, next, sources, policy, now) do
    true =
      keys?(
        facts,
        ~w(version kind operation_id context collection target metadata replacement mode history_rule new_source_sha256 new_policy_sha256 checked_at_ms reason request_sha256 scope action_sha256)
      )

    true =
      facts["version"] === 1 and facts["kind"] == "managed_literal_supersession" and
        id?(facts["operation_id"])

    true =
      facts["collection"] == Map.take(witness, ~w(root_state root root_sha256 manifest_sha256))

    true = facts["target"] === record and facts["metadata"] === metadata

    true =
      facts["replacement"] === %{
        "key" => next["key"],
        "value" => List.last(request["changes"])["value"]
      }

    true = facts["history_rule"] === ManagedRetention.history_rule(metadata, facts["mode"])

    true =
      facts["new_source_sha256"] == JSON.digest([sources]) and
        facts["new_policy_sha256"] == policy

    true = JSON.safe_uint?(facts["checked_at_ms"]) and facts["checked_at_ms"] <= now
    true = facts["request_sha256"] == JSON.digest([request])

    true =
      facts["scope"] ==
        "atomic literal successor and noncurrent signed history; original journal and shared evidence remain"

    true =
      is_binary(facts["reason"]) and String.valid?(facts["reason"]) and
        byte_size(facts["reason"]) in 1..64

    true =
      facts["action_sha256"] == JSON.digest([Map.delete(facts, "action_sha256")]) and
        byte_size(Jason.encode!(facts)) <= 16_384

    :ok
  end

  defp cached_read(read, table) do
    bounded = bounded_read(read)

    fn request ->
      case :ets.lookup(table, request) do
        [{^request, result}] ->
          result

        [] ->
          result = bounded.(request)
          if match?({:ok, _}, result), do: :ets.insert(table, {request, result})
          result
      end
    end
  end

  defp expiry_facts!(facts, request, witness, record, metadata, now, kind) do
    true =
      keys?(
        facts,
        ~w(version kind operation_id context collection target metadata reason request_sha256 scope expired_at_ms checked_at_ms action_sha256)
      )

    true =
      facts["version"] === 1 and
        facts["kind"] == expiry_kind(kind)

    true = id?(facts["operation_id"])

    true =
      facts["collection"] == Map.take(witness, ~w(root_state root root_sha256 manifest_sha256))

    true = facts["target"] === record and facts["metadata"] === metadata
    true = facts["request_sha256"] == JSON.digest([request])
    true = facts["expired_at_ms"] === metadata["valid_until_ms"]

    true =
      JSON.safe_uint?(facts["checked_at_ms"]) and facts["expired_at_ms"] <= facts["checked_at_ms"]

    true = facts["checked_at_ms"] <= now

    true =
      facts["reason"] ==
        case kind do
          :history -> "Stored signed historical retention deadline elapsed"
          :accepted -> "Stored signed accepted retention deadline elapsed"
          :ordinary -> "Stored signed ordinary retention deadline elapsed"
        end

    true =
      facts["scope"] ==
        case kind do
          :history ->
            "expired historical literal; any superseded retention-choice capsule may be compacted and is preserved in this journal, signed successor edge, admission clocks, original and review journals and shared evidence remain"

          :accepted ->
            "selected accepted decision; immutable acceptance link, original journals and shared evidence remain"

          :ordinary ->
            "selected literal derivative; original journal, management review journal and shared evidence remain"
        end

    true = facts["action_sha256"] == JSON.digest([Map.delete(facts, "action_sha256")])
    true = byte_size(Jason.encode!(facts)) <= 16_384
    :ok
  end

  defp expiry_kind(:ordinary), do: "managed_literal_expiry"
  defp expiry_kind(:history), do: "managed_literal_history_expiry"
  defp expiry_kind(:accepted), do: "managed_accepted_decision_expiry"

  @doc """
  Forget one exact signed literal under the owning host's management boundary.

  The host must journal intent and revalidate current management authority before
  entering the actual Collection callback. This does not use an automatic-capture
  grant. The actual owner-bound native permit is consumed only after the stored
  target, original root, full review facts and bounded repairs are revalidated.
  Expired or unavailable source evidence does not prevent deleting its derivative.
  """
  def forget(witness, read, options), do: manage(witness, read, options, :forget)

  @doc "Forget one signed accepted decision while preserving its immutable acceptance link and original journals."
  def forget_accepted(witness, read, options),
    do: manage(witness, read, options, :forget_accepted)

  @doc "Apply an exact native-reviewed policy choice while preserving the literal value and original admission clocks."
  def retain(witness, read, options), do: manage(witness, read, options, :retain)

  defp manage(witness, read, options, action) when is_function(read, 1) do
    checked(fn ->
      forget? = action in [:forget, :forget_accepted]
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
      [%{"key" => key, "expected_revision" => revision, "value" => desired}] = request["changes"]
      true = if(forget?, do: is_nil(desired), else: is_map(desired))
      "note." <> lineage = key
      true = JSON.sha256?(lineage) and key == recipe["key_prefix"] <> lineage
      read = bounded_read(read)
      {:ok, format} = read.(ManagedPages.format_key())
      {false, _} = format!(cap, format, catalog, witness)
      {:ok, record} = read.(key)
      true = is_map(record) and record["key"] == key and record["revision"] === revision
      true = revision > 0 and revision <= witness["root"]["generation"]
      true = record["sha256"] == value_sha(record["value"])
      true = forget? or desired === record["value"]
      {:ok, nil} = read.(recipe["override_prefix"] <> lineage)

      anchor = selected_row!(cap, :anchor, lineage, read, witness)
      live_id = ManagedPages.live_identity(key)
      live = selected_row!(cap, :live, live_id, read, witness)

      {metadata, candidate} =
        if action == :forget_accepted do
          {:ok, link} = read.("accept." <> record["value"]["candidate_id"])

          {:ok, metadata} =
            Ipse.Session.PendingAcceptance.retained_decision_metadata(
              recipe,
              record,
              link,
              anchor,
              live
            )

          {metadata, nil}
        else
          {:ok, candidate} =
            ManagedRecipe.extract(
              recipe,
              key,
              record["value"],
              get_in(record["value"], recipe["evidence_path"])
            )

          true = candidate["kind"] == "literal_source" and candidate["lineage"] == lineage
          {:ok, metadata} = ManagedRetention.metadata(candidate, record["sha256"], anchor, live)
          {metadata, candidate}
        end

      true = metadata["lineage"] == lineage
      first = metadata["first_admitted_ms"]
      true = first <= now
      true = is_nil(metadata["choice"]) or metadata["choice"]["observed_at_ms"] <= now

      true =
        forget? or
          ManagedRetention.eligible_metadata?(candidate, record["sha256"], metadata, now)

      :ok = management_facts!(facts, request, witness, record, metadata, action)
      if action == :retain, do: {:ok, _, _} = ManagedRetention.selected(facts["policy"], now)

      # The exact semantic checks precede spending native authority. The outer
      # Review callback withholds success after any consumed failure or
      # unconfirmed cleanup, including a refused bounded page repair.
      command = ManagedRetention.command(facts["policy"])
      {:ok, review} = Ipse.Runner.Review.consume(permit, command, facts)
      true = review["observed_at_ms"] <= now and review["facts_sha256"] == JSON.digest([facts])
      true = review["observed_at_ms"] >= first

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
        "policy" => facts["policy"],
        "reason" => facts["reason"]
      }

      {updated, live_value, selected} =
        if forget? do
          retirement =
            if action == :forget_accepted,
              do: %{
                "record_key" => key,
                "record_value_sha256" => record["sha256"],
                "at_ms" => now
              },
              else: %{"target_kind" => "native_literal_note", "at_ms" => now}

          {%{
             anchor
             | "choice" => capsule,
               "retirement" => retirement
           }, nil, nil}
        else
          {:ok, category, deadline} =
            ManagedRetention.selected(facts["policy"], review["observed_at_ms"])

          true = is_nil(deadline) or deadline > now
          categories = ~w(ordinary preference current pin history)

          changed_live =
            live
            |> List.replace_at(5, base36(deadline))
            |> List.replace_at(6, Enum.find_index(categories, &(&1 == category)))

          {%{anchor | "choice" => capsule}, changed_live, {category, deadline}}
        end

      {:ok, anchor_plan} = Planner.plan(cap, :anchor, [{lineage, updated}], read)
      {:ok, live_plan} = Planner.plan(cap, :live, [{live_id, live_value}], read)
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
        "kind" =>
          case action do
            :forget -> "native_literal_forget"
            :forget_accepted -> "native_accepted_decision_forget"
            :retain -> "native_literal_retention"
          end,
        "lineage" => lineage,
        "record_key" => key,
        "action_sha256" => facts["action_sha256"],
        "native_review_sha256" => JSON.digest([review]),
        "eligibility" => if(forget?, do: "retired", else: "current"),
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

      receipt =
        if forget? do
          Map.put(receipt, "retired_at_ms", now)
        else
          {category, deadline} = selected

          Map.merge(receipt, %{
            "category" => category,
            "first_admitted_ms" => first,
            "valid_until_ms" => deadline,
            "policy" => facts["policy"],
            "publish_before_ms" =>
              [metadata["valid_until_ms"], deadline]
              |> Enum.reject(&is_nil/1)
              |> Enum.min(fn -> nil end),
            "historical_gap" => facts["historical_gap"]
          })
        end

      true = byte_size(Migration.encode(receipt)) <= 2048
      {normalized, receipt}
    end)
    |> case do
      {:ok, {request, receipt}} -> {:ok, request, receipt}
      _ -> @error
    end
  end

  defp manage(_, _, _, _), do: @error

  defp management_facts!(facts, request, witness, record, metadata, action) do
    fields =
      ~w(version kind operation_id context collection target metadata policy reason request_sha256 scope action_sha256)

    fields =
      if action == :retain,
        do: fields ++ ~w(old_deadline_ms new_deadline_rule historical_gap historical_gap_notice),
        else: fields

    true =
      keys?(
        facts,
        fields
      )

    kind =
      case action do
        :forget -> "managed_literal_forget"
        :forget_accepted -> "managed_accepted_decision_forget"
        :retain -> "managed_literal_retention"
      end

    true = facts["version"] === 1 and facts["kind"] == kind
    true = id?(facts["operation_id"])

    true =
      facts["collection"] == Map.take(witness, ~w(root_state root root_sha256 manifest_sha256))

    true = facts["target"] === record and facts["metadata"] === metadata
    true = facts["request_sha256"] == JSON.digest([request])
    true = ManagedRetention.policy?(facts["policy"])

    if action in [:forget, :forget_accepted] do
      true = facts["policy"] === %{"kind" => "session"}
    else
      true = facts["policy"]["kind"] != "session"
      true = facts["old_deadline_ms"] === metadata["valid_until_ms"]
      true = facts["new_deadline_rule"] === ManagedRetention.deadline_rule(facts["policy"])
      gap = ManagedRetention.history_gap?(metadata["category"], facts["policy"])
      true = facts["historical_gap"] === gap

      true =
        facts["historical_gap_notice"] ===
          if(gap,
            do:
              "This reduces the selected current or persistent claim's historical coverage; other claims and shared evidence keep their own policies.",
            else: nil
          )
    end

    true =
      facts["scope"] ==
        if(action == :forget_accepted,
          do:
            "selected accepted decision; immutable acceptance link, original journals and shared evidence remain",
          else:
            "selected literal derivative; original journal, management review journal and shared evidence remain"
        )

    reason = facts["reason"]
    true = is_binary(reason) and String.valid?(reason) and byte_size(reason) in 1..64
    true = facts["action_sha256"] == JSON.digest([Map.delete(facts, "action_sha256")])
    true = byte_size(Jason.encode!(facts)) <= 16_384
    :ok
  end

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
