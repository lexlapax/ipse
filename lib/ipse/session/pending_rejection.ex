defmodule Ipse.Session.PendingRejection do
  @moduledoc """
  Exact host facts for rejecting one retained proposal without publishing it.

  The retained source lineage can be shared by other proposals and literal
  notes. Rejection therefore preserves its signed anchor and clocks and records
  a candidate-specific suppression. Preparation grants no authority: the host
  must obtain the actual signed observation, display all facts, journal intent,
  recheck management policy and consume a live native Review permit.
  """
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, ManagedRecipe}
  alias Ipse.Session.ManagedLifecycle
  @error {:error, :pending_rejection_refused}
  @scope "selected pending candidate only; its suppression, original journals, shared source and other candidates remain"

  def prepare(context, managed, reason), do: prepare(context, managed, reason, Usage.id())

  defp prepare(context, managed, reason, operation) do
    with true <- ManagedLifecycle.context?(context, "proposal"),
         true <- is_binary(operation) and Regex.match?(~r/\A[0-9a-f]{32}\z/, operation),
         true <- is_binary(reason) and String.valid?(reason) and byte_size(reason) in 1..64,
         true <- keys?(managed, ~w(metadata observation)),
         observation when is_map(observation) <- managed["observation"],
         record when is_map(record) <- get_in(observation, ["value", "record"]),
         "pending." <> id <- record["key"],
         true <- JSON.sha256?(id) and record["value"]["id"] === id,
         true <-
           record["value"]["kind"] === "proposal" and record["value"]["state"] === "pending",
         {:ok, candidate} <-
           ManagedRecipe.extract(
             context["recipe"],
             record["key"],
             record["value"],
             get_in(record["value"], context["recipe"]["evidence_path"])
           ),
         {:ok, ^id} <- ManagedRecipe.proposal_identity(candidate["lineage"], candidate["text"]),
         metadata = managed["metadata"],
         true <-
           keys?(
             metadata,
             ~w(lineage recipe_sha256 policy_sha256 first_admitted_ms valid_until_ms category eligibility)
           ),
         true <-
           metadata["lineage"] === candidate["lineage"] and
             metadata["recipe_sha256"] === JSON.digest([context["recipe"]]) and
             JSON.sha256?(metadata["policy_sha256"]) and
             metadata["category"] === candidate["category"] and
             metadata["eligibility"] === "never_current",
         true <-
           JSON.safe_uint?(metadata["first_admitted_ms"]) and
             JSON.safe_uint?(metadata["valid_until_ms"]) and
             metadata["first_admitted_ms"] <= metadata["valid_until_ms"],
         true <-
           observation["request_sha256"] ===
             JSON.digest([%{"op" => "get_record", "key" => record["key"]}]),
         true <- observation["result_sha256"] === JSON.digest([%{"record" => record}]),
         witness when is_map(witness) <- observation["witness"],
         true <- witness["root_state"] === "present" and is_map(witness["root"]),
         true <-
           witness["root"]["project"] === context["namespace"] and
             witness["manifest_sha256"] === witness["root"]["manifest"],
         true <-
           JSON.safe_uint?(record["revision"]) and record["revision"] > 0 and
             record["revision"] <= witness["root"]["generation"],
         true <- record["sha256"] === JSON.sha256(Collection.Migration.encode(record["value"])),
         suppression = %{
           "version" => 1,
           "kind" => "rejected_proposal",
           "candidate_id" => id,
           "lineage" => candidate["lineage"],
           "record_sha256" => record["sha256"],
           "record_revision" => record["revision"],
           "management_operation_id" => operation
         },
         request = %{
           "op" => "commit",
           "expected_generation" => witness["root"]["generation"],
           "advance_floor" => true,
           "changes" => [
             %{"key" => record["key"], "expected_revision" => record["revision"], "value" => nil},
             %{"key" => "reject." <> id, "expected_revision" => 0, "value" => suppression}
           ]
         },
         true <- Collection.valid_request?(request),
         body = %{
           "version" => 1,
           "kind" => "managed_proposal_reject",
           "operation_id" => operation,
           "context" => context,
           "collection" =>
             Map.take(witness, ~w(root_state root_sha256 manifest_sha256))
             |> Map.put(
               "root",
               witness["root"] |> Map.delete("manifest") |> Map.put("version", 3)
             ),
           "target" => record,
           "metadata" => metadata,
           "policy" => %{"kind" => "session"},
           "reason" => reason,
           "request_sha256" => JSON.digest([request]),
           "request" => request,
           "scope" => @scope
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

  @doc false
  def valid_facts?(facts) do
    # Reconstruct only the pure preparation shape. This check authenticates no
    # witness, source or input; the actual held normalizer must reproduce it.
    record = facts["target"]
    collection = facts["collection"]

    witness =
      Map.put(
        collection,
        "root",
        Map.put(collection["root"], "manifest", collection["manifest_sha256"])
      )

    managed = %{
      "metadata" => facts["metadata"],
      "observation" => %{
        "witness" => witness,
        "value" => %{"record" => record},
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => record["key"]}]),
        "result_sha256" => JSON.digest([%{"record" => record}])
      }
    }

    with {:ok, prepared} <-
           prepare(facts["context"], managed, facts["reason"], facts["operation_id"]),
         true <- facts === prepared["facts"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc false
  def revalidate(facts, request, witness, record, metadata) do
    valid_facts?(facts) and facts["target"] === record and facts["metadata"] === metadata and
      facts["request_sha256"] === JSON.digest([request]) and
      facts["collection"] === Map.take(witness, ~w(root_state root root_sha256 manifest_sha256))
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
