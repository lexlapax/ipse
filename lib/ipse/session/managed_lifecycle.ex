defmodule Ipse.Session.ManagedLifecycle do
  @moduledoc """
  Host-private exact facts for native management of one signed retained note.

  Preparation consumes an observation already obtained under the owning host's
  Identity and management policy boundary. It grants no authority. The owner
  must journal the returned intent before entering its protected publication
  callback. Reviewed changes pass the actual volatile Review permit; expiry
  instead follows the already signed finite policy and fresh host time through
  its distinct normalizer. Accepted decisions have a distinct target and
  fact kind; they cannot enter the literal retention or relation preparations.
  No worker operation or serialized receipt can construct that permit. Disabled
  capture and destructive management have separate policy; this module does not
  reinterpret a saved automatic-capture grant as management permission.
  """
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, ManagedRecipe, SemanticConsent}
  @error {:error, :managed_lifecycle_refused}
  @context Enum.sort(
             ~w(session_id job_id client_id project_id namespace binding_sha256 management_epoch management_sha256 original_pin recipe)
           )

  @doc "Build the complete immutable native review and journal intent from a checked managed observation."
  def prepare(context, managed, reason),
    do: prepare_forget(context, managed, reason, "managed_literal_forget")

  @doc "Prepare only destructive management of a signed accepted-decision target; grants no authority."
  def prepare_accepted_forget(context, managed, reason),
    do: prepare_forget(context, managed, reason, "managed_accepted_decision_forget")

  defp prepare_forget(context, managed, reason, kind) do
    with true <- context?(context),
         true <-
           if(kind == "managed_accepted_decision_forget",
             do:
               get_in(managed, ["metadata", "management_target"]) === "accepted_decision" and
                 get_in(managed, ["observation", "value", "record", "value", "kind"]) ===
                   "accepted_decision",
             else:
               get_in(managed, ["observation", "value", "record", "value", "kind"]) !==
                 "accepted_decision"
           ),
         true <- is_binary(reason) and String.valid?(reason) and byte_size(reason) in 1..64,
         true <- Enum.sort(Map.keys(managed)) == ~w(metadata observation),
         observation = managed["observation"],
         record when is_map(record) <- get_in(observation, ["value", "record"]),
         "note." <> lineage <- record["key"],
         true <- JSON.sha256?(lineage) and lineage == managed["metadata"]["lineage"],
         true <- JSON.digest([context["recipe"]]) == managed["metadata"]["recipe_sha256"],
         true <- observation["result_sha256"] == JSON.digest([%{"record" => record}]),
         witness = observation["witness"],
         true <- witness["root_state"] == "present" and is_map(witness["root"]),
         true <- witness["root"]["project"] == context["namespace"],
         true <- witness["manifest_sha256"] == witness["root"]["manifest"],
         summary = witness["root"] |> Map.delete("manifest") |> Map.put("version", 3),
         true <- JSON.safe_uint?(record["revision"]) and record["revision"] > 0,
         true <- record["revision"] <= witness["root"]["generation"],
         true <- record["sha256"] == JSON.sha256(Collection.Migration.encode(record["value"])),
         request = %{
           "op" => "commit",
           "expected_generation" => witness["root"]["generation"],
           "advance_floor" => true,
           "changes" => [
             %{"key" => record["key"], "expected_revision" => record["revision"], "value" => nil}
           ]
         },
         operation = Usage.id(),
         body = %{
           "version" => 1,
           "kind" => kind,
           "operation_id" => operation,
           "context" => context,
           "collection" =>
             Map.take(witness, ~w(root_state root_sha256 manifest_sha256))
             |> Map.put("root", summary),
           "target" => record,
           "metadata" => managed["metadata"],
           "policy" => %{"kind" => "session"},
           "reason" => reason,
           "request_sha256" => JSON.digest([request]),
           "scope" =>
             if(kind == "managed_accepted_decision_forget",
               do:
                 "selected accepted decision; immutable acceptance link, original journals and shared evidence remain",
               else:
                 "selected literal derivative; original journal, management review journal and shared evidence remain"
             )
         },
         facts = Map.put(body, "action_sha256", JSON.digest([body])),
         :ok <- JSON.validate_object(facts),
         true <- byte_size(Jason.encode!(facts)) <= 16_384 do
      {:ok,
       %{
         "facts" => facts,
         "request" => request,
         "intent" => %{
           "type" => "managed_lifecycle_intent",
           "version" => 1,
           "operation_id" => operation,
           "facts" => facts
         }
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Review an explicit relative retention choice without guessing the future native confirmation time."
  def prepare_retention(context, managed, policy, reason) do
    alias Ipse.Extension.Collection.ManagedRetention

    with true <- ManagedRetention.policy?(policy) do
      accepted? = get_in(managed, ["metadata", "management_target"]) == "accepted_decision"
      prepare = if accepted?, do: &prepare_accepted_forget/3, else: &prepare/3

      if policy["kind"] == "session" do
        prepare.(context, managed, reason)
      else
        with {:ok, prepared} <- prepare.(context, managed, reason),
             target = prepared["facts"]["target"],
             request =
               put_in(prepared["request"], ["changes", Access.at(0), "value"], target["value"]),
             old = prepared["facts"]["metadata"],
             gap = ManagedRetention.history_gap?(old["category"], policy),
             body =
               prepared["facts"]
               |> Map.delete("action_sha256")
               |> Map.merge(%{
                 "kind" =>
                   if(accepted?,
                     do: "managed_accepted_decision_retention",
                     else: "managed_literal_retention"
                   ),
                 "policy" => policy,
                 "old_deadline_ms" => old["valid_until_ms"],
                 "new_deadline_rule" => ManagedRetention.deadline_rule(policy),
                 "historical_gap" => gap,
                 "historical_gap_notice" =>
                   if(gap,
                     do:
                       "This reduces the selected current or persistent claim's historical coverage; other claims and shared evidence keep their own policies.",
                     else: nil
                   ),
                 "request_sha256" => JSON.digest([request])
               }),
             facts = Map.put(body, "action_sha256", JSON.digest([body])),
             :ok <- JSON.validate_object(facts),
             true <- byte_size(Jason.encode!(facts)) <= 16_384 do
          {:ok,
           %{
             prepared
             | "facts" => facts,
               "request" => request,
               "intent" => Map.put(prepared["intent"], "facts", facts)
           }}
        else
          _ -> @error
        end
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def retention_review?(command, facts, now) when is_map(facts) and is_integer(now) do
    alias Ipse.Extension.Collection.ManagedRetention

    policy = facts["policy"]
    deadline = get_in(facts, ["metadata", "valid_until_ms"])
    first = get_in(facts, ["metadata", "first_admitted_ms"])

    facts["kind"] in ~w(managed_literal_retention managed_accepted_decision_retention) and
      ManagedRetention.policy?(policy) and
      command in ~w(pin ordinary duration) and ManagedRetention.command(policy) === command and
      JSON.safe_uint?(first) and first <= now and
      facts["old_deadline_ms"] === deadline and
      (is_nil(deadline) or (JSON.safe_uint?(deadline) and now < deadline)) and
      facts["action_sha256"] === JSON.digest([Map.delete(facts, "action_sha256")])
  rescue
    _ -> false
  end

  def retention_review?(_, _, _), do: false

  @doc "Prepare exact expiry facts from an authenticated stored observation; no permission or native review is minted."
  def prepare_expiry(context, managed, now) do
    alias Ipse.Extension.Collection.ManagedRetention

    with {:ok, prepared} <-
           prepare(context, managed, "Stored signed ordinary retention deadline elapsed"),
         record = prepared["facts"]["target"],
         {:ok, candidate} <-
           ManagedRecipe.extract(
             context["recipe"],
             record["key"],
             record["value"],
             get_in(record["value"], context["recipe"]["evidence_path"])
           ),
         true <-
           ManagedRetention.expired_metadata?(
             candidate,
             record["sha256"],
             managed["metadata"],
             now
           ),
         body =
           prepared["facts"]
           |> Map.drop(["action_sha256", "policy"])
           |> Map.merge(%{
             "kind" => "managed_literal_expiry",
             "expired_at_ms" => managed["metadata"]["valid_until_ms"],
             "checked_at_ms" => now
           }),
         facts = Map.put(body, "action_sha256", JSON.digest([body])),
         :ok <- JSON.validate_object(facts),
         true <- byte_size(Jason.encode!(facts)) <= 16_384 do
      {:ok, %{prepared | "facts" => facts, "intent" => %{prepared["intent"] | "facts" => facts}}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Prepare reducing reclamation of an accepted decision after its authenticated finite deadline."
  def prepare_accepted_expiry(context, managed, now) do
    with true <-
           Ipse.Session.PendingAcceptance.expired_retained_decision_metadata?(
             managed["metadata"],
             now
           ),
         {:ok, prepared} <-
           prepare_accepted_forget(
             context,
             managed,
             "Stored signed accepted retention deadline elapsed"
           ),
         body =
           prepared["facts"]
           |> Map.drop(["action_sha256", "policy"])
           |> Map.merge(%{
             "kind" => "managed_accepted_decision_expiry",
             "expired_at_ms" => managed["metadata"]["valid_until_ms"],
             "checked_at_ms" => now
           }),
         facts = Map.put(body, "action_sha256", JSON.digest([body])),
         :ok <- JSON.validate_object(facts),
         true <- byte_size(Jason.encode!(facts)) <= 16_384 do
      {:ok, %{prepared | "facts" => facts, "intent" => %{prepared["intent"] | "facts" => facts}}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Prepare exact elapsed-history reclamation facts; this does not authorize publication."
  def prepare_history_expiry(context, managed, now) do
    alias Ipse.Extension.Collection.ManagedRetention

    with true <-
           is_map(managed) and
             Enum.sort(Map.keys(managed)) == ~w(metadata observation successor_storage),
         true <- managed["successor_storage"] in ~w(matching_record unavailable),
         {:ok, prepared} <-
           prepare(
             context,
             Map.take(managed, ~w(metadata observation)),
             "Stored signed historical retention deadline elapsed"
           ),
         true <- ManagedRetention.expired_history_metadata?(managed["metadata"], now),
         body =
           prepared["facts"]
           |> Map.drop(["action_sha256", "policy"])
           |> Map.merge(%{
             "kind" => "managed_literal_history_expiry",
             "expired_at_ms" => managed["metadata"]["valid_until_ms"],
             "checked_at_ms" => now,
             "scope" =>
               "expired historical literal; any superseded retention-choice capsule may be compacted and is preserved in this journal, signed successor edge, admission clocks, original and review journals and shared evidence remain"
           }),
         facts = Map.put(body, "action_sha256", JSON.digest([body])),
         :ok <- JSON.validate_object(facts),
         true <- byte_size(Jason.encode!(facts)) <= 16_384 do
      {:ok, %{prepared | "facts" => facts, "intent" => %{prepared["intent"] | "facts" => facts}}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Prepare exact review facts for an atomic correction or temporal successor."
  def prepare_supersession(context, managed, replacement, options, reason) do
    alias Ipse.Extension.Collection.ManagedRetention
    alias Ipse.Extension.CollectionPolicy

    with {:ok, prepared} <- prepare(context, managed, reason),
         true <- is_map(replacement) and Enum.sort(Map.keys(replacement)) == ~w(key value),
         true <-
           is_map(options) and
             Enum.sort(Map.keys(options)) ==
               Enum.sort(~w(mode constraints verified_sources policy_sha256 now_ms)a),
         %{
           mode: mode,
           constraints: constraints,
           verified_sources: sources,
           policy_sha256: policy,
           now_ms: now
         } = options,
         true <- mode in ~w(ordinary temporal) and JSON.safe_uint?(now) and JSON.sha256?(policy),
         recipe = context["recipe"],
         true <- recipe["constraints_sha256"] == JSON.digest([constraints]),
         {:ok, candidate} <-
           ManagedRecipe.extract(recipe, replacement["key"], replacement["value"], sources),
         old_record = prepared["facts"]["target"],
         {:ok, previous} <-
           ManagedRecipe.extract(
             recipe,
             old_record["key"],
             old_record["value"],
             get_in(old_record["value"], recipe["evidence_path"])
           ),
         true <- candidate["lineage"] != prepared["facts"]["metadata"]["lineage"],
         true <- candidate["text"] != previous["text"],
         true <-
           (mode == "ordinary" and candidate["category"] == "ordinary") or
             (mode == "temporal" and candidate["category"] == "current"),
         history_rule when history_rule != {:error, :managed_retention_refused} <-
           ManagedRetention.history_rule(prepared["facts"]["metadata"], mode),
         {:ok, _} <- ManagedRetention.history_deadline(prepared["facts"]["metadata"], mode, now),
         target = prepared["facts"]["target"],
         old_change = %{
           "key" => target["key"],
           "expected_revision" => target["revision"],
           "value" => target["value"]
         },
         new_change = %{
           "key" => replacement["key"],
           "expected_revision" => 0,
           "value" => replacement["value"]
         },
         request = %{prepared["request"] | "changes" => [old_change, new_change]},
         :ok <-
           CollectionPolicy.check(%{request | "changes" => [new_change]}, constraints, sources),
         body =
           prepared["facts"]
           |> Map.drop(["action_sha256", "policy"])
           |> Map.merge(%{
             "kind" => "managed_literal_supersession",
             "replacement" => replacement,
             "mode" => mode,
             "history_rule" => history_rule,
             "new_source_sha256" => JSON.digest([sources]),
             "new_policy_sha256" => policy,
             "checked_at_ms" => now,
             "request_sha256" => JSON.digest([request]),
             "scope" =>
               "atomic literal successor and noncurrent signed history; original journal and shared evidence remain"
           }),
         facts = Map.put(body, "action_sha256", JSON.digest([body])),
         :ok <- JSON.validate_object(facts),
         true <- byte_size(Jason.encode!(facts)) <= 16_384 do
      {:ok,
       %{
         prepared
         | "facts" => facts,
           "request" => request,
           "intent" => Map.put(prepared["intent"], "facts", facts)
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def context?(context), do: context?(context, "literal_source")

  @doc false
  def context?(context, kind) when kind in ~w(literal_source proposal) do
    is_map(context) and Enum.sort(Map.keys(context)) == @context and
      Enum.all?(~w(session_id job_id client_id), &id?(context[&1])) and
      Enum.all?(
        ~w(project_id namespace binding_sha256 management_sha256),
        &JSON.sha256?(context[&1])
      ) and
      JSON.safe_uint?(context["management_epoch"]) and
      original_pin?(context["original_pin"], context) and
      ManagedRecipe.valid?(context["recipe"]) and context["recipe"]["kind"] == kind
  rescue
    _ -> false
  end

  def context?(_, _), do: false

  defp original_pin?(nil, _), do: true

  defp original_pin?(pin, context),
    do:
      SemanticConsent.pin?(pin) and pin["project_id"] == context["project_id"] and
        pin["namespace"] == context["namespace"] and
        pin["binding_sha256"] == context["binding_sha256"]

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[a-f0-9]{32}\z/, value)
end
