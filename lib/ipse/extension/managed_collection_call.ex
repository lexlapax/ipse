defmodule Ipse.Extension.ManagedCollectionCall do
  @moduledoc "Explicit managed publication; current protected policy and host proofs supply authority."
  alias Ipse.{Extension, JSON}

  alias Ipse.Extension.{
    Collection,
    CollectionCall,
    CollectionPolicy,
    ManagedRecipe,
    SemanticAdmission,
    SemanticConsent
  }

  @error {:error, :invalid_extension_managed_collection_call}
  @binding ~w(kind version namespace pin outer_sha256 inner_op request_sha256 recipe_sha256)
  @normalization ~w(version lineage record_key first_admitted_ms valid_until_ms category eligibility anchor_key anchor_value_sha256 live_key live_value_sha256)

  def operation?(r), do: is_map(r) and r["op"] == "collection.managed"
  def capability(_), do: "host.collection.managed"
  def mutating?(r), do: operation?(r)

  def validate(r) do
    with true <- keys?(r, ~w(op request proofs recipe_sha256)) and operation?(r),
         true <- JSON.sha256?(r["recipe_sha256"]),
         true <- get_in(r, ["request", "op"]) == "commit",
         true <- get_in(r, ["request", "advance_floor"]) === true,
         :ok <-
           CollectionCall.validate(
             Map.delete(Map.put(r, "op", "collection.call"), "recipe_sha256")
           ),
         true <- byte_size(Jason.encode!(r)) <= 8192 do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def binding(config, parent, request) do
    with :ok <- validate(request),
         true <- parent["version"] === 3,
         true <- admitted_recipe?(config[:semantic_admission], request),
         {:ok, base} <- CollectionCall.binding(config, parent["identity"], legacy(request)) do
      {:ok,
       Map.merge(base, %{
         "kind" => "collection.managed",
         "version" => 2,
         "outer_sha256" => JSON.digest([parent["descriptor"]]),
         "recipe_sha256" => request["recipe_sha256"]
       })}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def valid_binding?(b, r, identity, metadata \\ nil) do
    with :ok <- validate(r),
         true <- keys?(b, @binding),
         true <- b["kind"] == "collection.managed" and b["version"] === 2,
         true <- JSON.sha256?(b["outer_sha256"]),
         true <- b["recipe_sha256"] == r["recipe_sha256"],
         base =
           b
           |> Map.drop(~w(outer_sha256 recipe_sha256))
           |> Map.merge(%{"kind" => "collection", "version" => 1}) do
      CollectionCall.valid_binding?(base, legacy(r), identity, metadata) and
        (is_nil(metadata) or admitted_recipe?(metadata["semantic_admission"], b))
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp admitted_recipe?(admission, b) do
    settings = admission["policy"]["settings"]
    # Registry membership makes this an explicit version-2 journey. It does not
    # select an effect mapping: denied read-outer attempts still need a receipt.
    match?({:ok, _}, SemanticConsent.recipe(settings, b))
  end

  @doc "Conservative exact JSON ceiling, including both full sidecar change envelopes and normalization."
  def reservation(request) do
    # Valid values are encoded with the same Jason escaping as Migration.encode.
    # Each sidecar key is <=96 ASCII bytes; revision is <=16 decimal digits.
    change = %{
      "key" => String.duplicate("k", 96),
      "expected_revision" => 9_007_199_254_740_991,
      "value" => %{}
    }

    envelope = byte_size(Jason.encode!(change)) - 2

    Map.merge(Ipse.Extension.Consent.zero(), %{
      "operations" => 1,
      "input_bytes" => byte_size(Jason.encode!(request)) + 2 * (6144 + envelope + 1) + 2048,
      "output_bytes" => 16_384
    })
  end

  def execute(context, intent) do
    parent = context.parent

    with :ok <- validate(intent["request"]),
         true <- parent["version"] === 3,
         true <-
           SemanticAdmission.valid_outer_binding?(
             parent["semantic_binding"],
             parent["identity"],
             parent["descriptor"],
             context.session_id
           ),
         true <- get_in(parent, ["semantic_binding", "class"]) == "collection.publish",
         true <- valid_binding?(intent["effect_binding"], intent["request"], context.identity),
         true <- intent["effect_binding"]["outer_sha256"] == JSON.digest([parent["descriptor"]]),
         true <- intent["effect_binding"]["pin"]["session_id"] == context.session_id,
         true <- intent["namespace"] == intent["effect_binding"]["namespace"] do
      Ipse.Session.Resources.file_effect(fn -> protected(context, intent) end)
    else
      _ -> failed("collection_consent_denied")
    end
  rescue
    _ -> failed("collection_unavailable")
  catch
    :exit, _ -> :unknown
  end

  defp protected(context, intent) do
    Ipse.Extension.ProjectIdentity.with_binding(
      context.config[:home],
      context.cwd,
      context.config[:semantic_admission]["binding"],
      fn _ ->
        with {:ok, current, proofs} <- current_sources(context, intent),
             {:ok, plan} <- plan(context, intent, current, proofs) do
          publish(context, intent, current, proofs, plan)
        else
          _ -> failed("collection_consent_denied")
        end
      end
    )
    |> normalize()
  end

  defp current_sources(c, i),
    do: GenServer.call(c.owner, {:extension_collection_sources, c.job_ref, i}, 5000)

  defp plan(c, i, current, proofs) do
    pin = i["effect_binding"]["pin"]

    Ipse.Extension.Consent.with_policy(
      SemanticAdmission.control_root(c.config[:home]),
      pin["project_id"],
      pin["epoch"],
      pin["policy_sha256"],
      now(),
      fn snapshot ->
        settings = snapshot["policy"]["settings"]
        verified = Enum.map(proofs, & &1["proof"])

        matches =
          Enum.flat_map(settings["effects"], fn m ->
            with true <-
                   m["class"] == "collection.publish" and m["inner_op"] == "collection.managed",
                 true <- m["outer_sha256"] == i["effect_binding"]["outer_sha256"],
                 {:ok, constraints} <- SemanticConsent.constraints(settings, m),
                 {:ok, recipe} <- SemanticConsent.recipe(settings, m),
                 :ok <- CollectionPolicy.check(i["request"]["request"], constraints, verified),
                 [change] <- i["request"]["request"]["changes"],
                 {:ok, _} <-
                   ManagedRecipe.extract(recipe, change["key"], change["value"], verified) do
              [{m, constraints, recipe}]
            else
              _ -> []
            end
          end)

        with [{mapping, constraints, recipe}] <- matches,
             true <- JSON.digest([recipe]) == i["request"]["recipe_sha256"],
             true <- i["approval"] in ~w(saved_consent approved session_allow),
             effect =
               Map.take(mapping, ~w(operation class outer_sha256 inner_op))
               |> Map.merge(%{
                 "id" => i["operation_id"],
                 "request_sha256" => i["request_sha256"],
                 "source_generation" => current["source_generation"],
                 "sources" =>
                   Enum.map(verified, &%{"category" => &1["origin"], "path" => &1["path"]}),
                 "reserved" => reservation(i["request"])
               }),
             {:ok, reservation} <-
               SemanticConsent.authorize(pin, snapshot, current, effect, now()) do
          {:ok, %{reservation: reservation, constraints: constraints, recipe: recipe}}
        else
          _ -> {:error, :collection_policy_refused}
        end
      end
    )
  end

  defp publish(c, i, current, proofs, plan) do
    alias Ipse.Extension.Consent
    pin = i["effect_binding"]["pin"]
    root = SemanticAdmission.control_root(c.config[:home])

    with {:ok, ticket} <- Consent.reserve(root, pin["project_id"], plan.reservation, now()),
         false <- Map.has_key?(ticket, "existing"),
         {:ok, ^ticket} <- Consent.admit(root, pin["project_id"], ticket, now()) do
      case Consent.publish(root, pin["project_id"], ticket, now(), fn ->
             with {:ok, ^current, ^proofs} <- current_sources(c, i),
                  :ok <-
                    CollectionPolicy.check(
                      i["request"]["request"],
                      plan.constraints,
                      Enum.map(proofs, & &1["proof"])
                    ) do
               case storage(c, i, proofs, plan) do
                 {status, value} when status in [:ok, :conflict, :failed] ->
                   {:ok, reservation(i["request"]),
                    %{"status" => Atom.to_string(status), "value" => value}}

                 _ ->
                   :unknown
               end
             else
               _ ->
                 {:ok, reservation(i["request"]),
                  %{"status" => "failed", "value" => %{"code" => "collection_source_refused"}}}
             end
           end) do
        {:ok, %{"status" => "settled", "receipt" => %{"status" => status, "value" => value}}}
        when status in ~w(ok conflict failed) ->
          {String.to_existing_atom(status), value}

        {:error, _} ->
          failed("collection_consent_denied")

        _ ->
          :unknown
      end
    else
      _ -> failed("collection_consent_denied")
    end
  end

  defp storage(c, i, proofs, plan) do
    request = i["request"]

    case Collection.execute_managed(
           SemanticAdmission.collection_root(c.config[:home]),
           i["namespace"],
           request["request"],
           i["operation_id"],
           request["recipe_sha256"],
           fn witness, read ->
             Collection.Normalizer.normalize(witness, read, %{
               request: request["request"],
               recipe: plan.recipe,
               constraints: plan.constraints,
               verified_sources: Enum.map(proofs, & &1["proof"]),
               policy_sha256: i["effect_binding"]["pin"]["policy_sha256"],
               now_ms: now()
             })
           end
         ) do
      {:ok, value} ->
        if valid_outcome?(request, "ok", value, i["operation_id"]) and
             CollectionCall.reply_fits?(i, value) do
          {:ok, value}
        else
          :unknown
        end

      {:conflict, value} ->
        {:conflict, value}

      {:existing, _} ->
        failed("collection_duplicate")

      {:error, reason}
      when reason in [
             :collection_capacity,
             :collection_filesystem_unsupported,
             :collection_writer_fenced
           ] ->
        failed(Atom.to_string(reason))

      {:error, _} ->
        failed("collection_unavailable")

      _ ->
        :unknown
    end
  end

  def valid_outcome?(r, status, value, id) when status in ~w(unknown denied failed conflict),
    do: validate(r) == :ok and CollectionCall.valid_outcome?(legacy(r), status, value, id)

  def valid_outcome?(r, "ok", v, _) do
    validate(r) == :ok and keys?(v, ~w(version binding normalization receipt)) and
      v["version"] === 1 and
      keys?(v["binding"], ~w(version original_request_sha256 recipe_sha256 normalization_sha256)) and
      v["binding"]["version"] === 1 and
      v["binding"]["original_request_sha256"] == JSON.digest([r["request"]]) and
      v["binding"]["recipe_sha256"] == r["recipe_sha256"] and
      v["binding"]["normalization_sha256"] == JSON.digest([v["normalization"]]) and
      normalization?(v["normalization"], r) and
      keys?(v["receipt"], ~w(generation floor request_sha256 managed_binding_sha256)) and
      Collection.Migration.receipt?(v["receipt"]) and
      v["receipt"]["managed_binding_sha256"] == JSON.digest([v["binding"]]) and
      v["receipt"]["generation"] == r["request"]["expected_generation"] + 1 and
      Extension.validate(v) == :ok
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def bound_outcome?(event) do
    binding = event["effect_binding"]

    keys?(binding, @binding) and binding["kind"] == "collection.managed" and
      binding["version"] === 2 and
      SemanticConsent.pin?(binding["pin"]) and binding["namespace"] == event["namespace"] and
      binding["pin"]["namespace"] == event["namespace"] and
      binding["pin"]["identity_sha256"] == event["identity_sha256"] and
      binding["request_sha256"] == JSON.digest([event["request"]["request"]]) and
      binding["recipe_sha256"] == event["request"]["recipe_sha256"] and
      JSON.sha256?(binding["outer_sha256"]) and binding["inner_op"] == "commit" and
      valid_outcome?(
        event["request"],
        event["outcome"]["status"],
        event["outcome"]["value"],
        event["operation_id"]
      ) and
      (event["outcome"]["status"] != "conflict" or
         event["outcome"]["value"]["project"] == event["namespace"])
  rescue
    _ -> false
  end

  defp normalization?(n, r) do
    [change] = r["request"]["changes"]

    keys?(n, @normalization) and n["version"] === 2 and n["record_key"] == change["key"] and
      JSON.sha256?(n["lineage"]) and JSON.safe_uint?(n["first_admitted_ms"]) and
      (is_nil(n["valid_until_ms"]) or
         (JSON.safe_uint?(n["valid_until_ms"]) and n["valid_until_ms"] > n["first_admitted_ms"])) and
      n["category"] in ~w(current ordinary preference) and
      n["eligibility"] in ~w(current never_current) and
      (not is_nil(n["valid_until_ms"]) or
         (n["category"] != "ordinary" and n["eligibility"] != "never_current")) and
      metadata_key?(n["anchor_key"], "anchor", n["lineage"]) and
      metadata_key?(n["live_key"], "live", JSON.sha256(change["key"])) and
      JSON.sha256?(n["anchor_value_sha256"]) and JSON.sha256?(n["live_value_sha256"]) and
      byte_size(Jason.encode!(n)) <= 2048
  end

  defp metadata_key?(key, "anchor", lineage),
    do:
      key in Enum.map(
        0..7,
        &("host.validity.anchor." <> binary_part(lineage, 0, 2) <> "." <> Integer.to_string(&1))
      )

  defp metadata_key?(key, "live", hash) do
    shard =
      hash
      |> binary_part(0, 3)
      |> String.to_integer(16)
      |> rem(512)
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(3, "0")

    key in Enum.map(0..3, &("host.validity.live." <> shard <> "." <> Integer.to_string(&1)))
  end

  defp legacy(r), do: r |> Map.delete("recipe_sha256") |> Map.put("op", "collection.call")
  defp normalize({s, _} = r) when s in [:ok, :conflict, :failed], do: r
  defp normalize({:error, _}), do: failed("collection_consent_denied")
  defp normalize(_), do: :unknown
  defp failed(code), do: {:failed, %{"code" => code}}
  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp now, do: System.system_time(:millisecond)
end
