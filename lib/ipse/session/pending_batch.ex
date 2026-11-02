defmodule Ipse.Session.PendingBatch do
  @moduledoc """
  Immutable bounded selection for standalone pending review.

  A manifest is data, never acceptance authority. Each selected item still needs
  its own fresh native input, source checks, journal and one-use publication.
  """
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.ManagedRecipe
  @common ~w(project_id namespace binding_sha256 policy_sha256 capture_epoch recipe_sha256)
  @member ~w(pending_key record_revision record_sha256 text assigned_category first_admitted_ms valid_until_ms)
  @source ~w(kind origin session_id occurrence_id version_id content_sha256 start_byte end_byte)
  @manifest ~w(version kind id project_id namespace binding_sha256 policy_sha256 capture_epoch recipe_sha256 policy_expires_at_ms proposed_retention items)
  @error {:error, :pending_batch_refused}

  def keys?(keys) do
    is_list(keys) and length(keys) in 1..8 and length(Enum.uniq(keys)) == length(keys) and
      Enum.all?(keys, fn
        "pending." <> id -> JSON.sha256?(id)
        _ -> false
      end)
  end

  def prepare(cards, note_recipe, policy_deadline) do
    with true <- is_list(cards) and length(cards) in 1..8,
         true <- Enum.all?(cards, &Ipse.Session.PendingAcceptance.valid_facts?/1),
         true <- Enum.all?(cards, &(not Map.has_key?(&1, "batch"))),
         true <- ManagedRecipe.valid?(note_recipe) and note_recipe["kind"] == "literal_source",
         true <- JSON.safe_uint?(policy_deadline),
         first = hd(cards),
         true <- Enum.all?(cards, &(Map.take(&1, @common) === Map.take(first, @common))),
         true <- Enum.all?(cards, &(&1["root_sha256"] === first["root_sha256"])),
         manifest =
           Map.merge(Map.take(first, @common), %{
             "version" => 1,
             "kind" => "pending_review_manifest",
             "id" => Usage.id(),
             "policy_expires_at_ms" => policy_deadline,
             "proposed_retention" => retention(note_recipe),
             "items" => Enum.map(cards, &member/1)
           }),
         true <- valid_manifest?(manifest) do
      {:ok, manifest}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def binding(manifest, index) do
    bound = %{
      "manifest" => manifest,
      "manifest_sha256" => JSON.digest([manifest]),
      "index" => index
    }

    if valid_binding?(bound), do: {:ok, bound}, else: @error
  rescue
    _ -> @error
  end

  def valid_manifest?(manifest) do
    exact?(manifest, @manifest) and manifest["version"] === 1 and
      manifest["kind"] === "pending_review_manifest" and id?(manifest["id"]) and
      Enum.all?(@common -- ~w(capture_epoch), &JSON.sha256?(manifest[&1])) and
      positive?(manifest["capture_epoch"]) and JSON.safe_uint?(manifest["policy_expires_at_ms"]) and
      retention?(manifest["proposed_retention"]) and is_list(manifest["items"]) and
      length(manifest["items"]) in 1..8 and
      Enum.all?(manifest["items"], &member?/1) and
      keys?(Enum.map(manifest["items"], & &1["pending_key"])) and
      JSON.validate_object(manifest) == :ok and byte_size(Jason.encode!(manifest)) <= 8192
  rescue
    _ -> false
  end

  def valid_binding?(bound) do
    exact?(bound, ~w(manifest manifest_sha256 index)) and valid_manifest?(bound["manifest"]) and
      bound["manifest_sha256"] === JSON.digest([bound["manifest"]]) and
      is_integer(bound["index"]) and bound["index"] >= 0 and
      bound["index"] < length(bound["manifest"]["items"])
  rescue
    _ -> false
  end

  def member?(bound, facts) do
    valid_binding?(bound) and is_nil(facts["session_id"]) and
      Map.take(bound["manifest"], @common) === Map.take(facts, @common) and
      Enum.at(bound["manifest"]["items"], bound["index"]) === member(facts)
  rescue
    _ -> false
  end

  def selection?(bound, binding, pin, note_recipe, proposal_recipe, policy) do
    with true <- valid_binding?(bound),
         manifest = bound["manifest"] do
      manifest["project_id"] === binding["project_id"] and
        manifest["binding_sha256"] === binding["binding_sha256"] and
        manifest["namespace"] === pin["namespace"] and
        manifest["capture_epoch"] === pin["epoch"] and
        manifest["policy_sha256"] === pin["policy_sha256"] and
        manifest["recipe_sha256"] === JSON.digest([proposal_recipe]) and
        manifest["policy_expires_at_ms"] === policy["expires_at_ms"] and
        manifest["proposed_retention"] === retention(note_recipe)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp member(card),
    do: Map.put(Map.take(card, @member), "source", Map.take(card["source_proof"], @source))

  defp member?(item) do
    exact?(item, @member ++ ["source"]) and keys?([item["pending_key"]]) and
      positive?(item["record_revision"]) and JSON.sha256?(item["record_sha256"]) and
      is_binary(item["text"]) and String.valid?(item["text"]) and
      byte_size(item["text"]) in 1..2048 and
      item["assigned_category"] in ~w(ordinary preference current) and
      JSON.safe_uint?(item["first_admitted_ms"]) and JSON.safe_uint?(item["valid_until_ms"]) and
      item["first_admitted_ms"] < item["valid_until_ms"] and source?(item["source"])
  end

  defp source?(source) do
    exact?(source, @source) and
      Enum.all?(~w(session_id occurrence_id version_id), &id?(source[&1])) and
      JSON.sha256?(source["content_sha256"]) and JSON.safe_uint?(source["start_byte"]) and
      JSON.safe_uint?(source["end_byte"]) and source["start_byte"] < source["end_byte"] and
      source["end_byte"] - source["start_byte"] <= 1024 and
      source["kind"] in ~w(input.original input.operator_answer answer.original tool.outcome input.assertion.ordinary input.assertion.preference input.assertion.current) and
      source["origin"] in ~w(interactive_operator native_operator_answer native_operator_assertion unattended_input assistant_proposal typed_host_outcome)
  end

  defp retention(recipe), do: Enum.map(recipe["rules"], &Map.take(&1, ~w(category max_age_ms)))

  defp retention?(rules) do
    is_list(rules) and length(rules) in 1..8 and
      Enum.all?(rules, fn rule ->
        exact?(rule, ~w(category max_age_ms)) and
          rule["category"] in ~w(ordinary preference current) and
          ((is_nil(rule["max_age_ms"]) and rule["category"] in ~w(preference current)) or
             positive?(rule["max_age_ms"]))
      end) and rules == Enum.sort_by(rules, & &1["category"]) and
      length(Enum.uniq_by(rules, & &1["category"])) == length(rules)
  end

  defp exact?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) === Enum.sort(keys)
  defp positive?(value), do: JSON.safe_uint?(value) and value > 0
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
