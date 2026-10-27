defmodule Ipse.Session.ObservationReceipt do
  @moduledoc false
  alias Ipse.{JSON, Session.ManagedReference}
  alias Ipse.Extension.CollectionCall
  @error {:error, :observation_receipt_refused}
  @summary ~w(version project generation floor floor_anchor)

  # The owning Session must first validate the intent against its actual
  # parent, current caller and job. Matching JSON is not authentication.
  def bind(intent, identity, observation, result) do
    with {:ok, prepared} <- prepare(intent, identity, observation),
         true <- Ipse.Extension.Actions.valid_result?(result),
         true <- Ipse.Extension.Actions.result_intent(result) === intent,
         true <- result["outcome"] === %{"status" => "ok", "value" => prepared.value} do
      {:ok,
       %{
         "type" => "collection_observation_receipt",
         "version" => 1,
         "parent_invocation_id" => intent["parent_invocation_id"],
         "operation_id" => intent["operation_id"],
         "action_sha256" => JSON.digest([result]),
         "observation_sha256" => prepared.observation_sha256,
         "dependency" => prepared.dependency
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  # Historical structural check only. Replay must independently validate the
  # enclosing action chronology and journal, and must reject a missing receipt.
  # It cannot authenticate a fabricated receipt or establish live authority.
  def verify(result, receipt) do
    intent = Ipse.Extension.Actions.result_intent(result)
    dependency = receipt["dependency"]
    pin = get_in(intent, ["effect_binding", "pin"])
    inner = get_in(intent, ["request", "request"])
    value = get_in(result, ["outcome", "value"])

    with true <-
           exact?(
             receipt,
             ~w(type version parent_invocation_id operation_id action_sha256 observation_sha256 dependency)
           ),
         true <- receipt["type"] == "collection_observation_receipt" and receipt["version"] === 1,
         true <- Ipse.Extension.Actions.valid_result?(result),
         true <- get_in(result, ["outcome", "status"]) == "ok",
         true <- is_map(inner) and inner["op"] in ~w(get snapshot scan),
         true <-
           receipt["parent_invocation_id"] === intent["parent_invocation_id"] and
             receipt["operation_id"] === intent["operation_id"],
         true <-
           receipt["action_sha256"] === JSON.digest([result]) and
             JSON.sha256?(receipt["observation_sha256"]),
         true <- ManagedReference.dependency?(dependency) and dependency["version"] === 3,
         true <-
           dependency["project_id"] === pin["project_id"] and
             dependency["namespace"] === intent["namespace"],
         true <-
           dependency["pin_sha256"] === JSON.digest([pin]) and
             dependency["policy_generation"] === pin["epoch"],
         true <-
           dependency["subject"]["request_sha256"] === JSON.digest([inner]) and
             dependency["subject"]["result_sha256"] === JSON.digest([value]),
         true <-
           Map.take(dependency["collection"], ~w(project generation floor floor_anchor)) ===
             Map.take(value, ~w(project generation floor floor_anchor)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  # Prototype only. The Session must obtain `observation` from its owned
  # checked view, authenticate the producing caller and current authority,
  # durably bind the returned receipt to the action result, and propagate it.
  # This function cannot authenticate host-process inputs or current root.
  def prepare(intent, identity, observation) do
    request = intent["request"]
    inner = request["request"]
    binding = intent["effect_binding"]
    pin = binding["pin"]
    value = observation["value"]
    witness = observation["witness"]

    with true <- CollectionCall.valid_binding?(binding, request, identity),
         true <- inner["op"] in ~w(get snapshot scan),
         true <- intent["namespace"] == binding["namespace"],
         true <- exact?(observation, ~w(version request_sha256 result_sha256 value witness)),
         true <- observation["version"] === 1,
         true <- observation["request_sha256"] == JSON.digest([inner]),
         true <- observation["result_sha256"] == JSON.digest([value]),
         true <- root_matches?(witness, value, intent["namespace"]),
         {:ok, delivered} <- delivered(intent, inner, value),
         true <- CollectionCall.valid_outcome?(request, "ok", delivered, intent["operation_id"]),
         true <- CollectionCall.reply_fits?(intent, delivered),
         dependency = %{
           "version" => 3,
           "project_id" => pin["project_id"],
           "namespace" => intent["namespace"],
           "pin_sha256" => JSON.digest([pin]),
           "policy_generation" => pin["epoch"],
           "collection" =>
             Map.merge(
               Map.take(value, ~w(project generation floor floor_anchor)),
               Map.take(witness, ~w(root_state root_sha256 manifest_sha256))
             ),
           "subject" => %{
             "kind" => "root_observation",
             "request_sha256" => observation["request_sha256"],
             "result_sha256" => JSON.digest([delivered])
           }
         },
         true <- ManagedReference.dependency?(dependency) do
      {:ok,
       %{value: delivered, dependency: dependency, observation_sha256: JSON.digest([observation])}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp delivered(intent, %{"op" => "scan"}, value), do: CollectionCall.bound_scan(intent, value)
  defp delivered(_, _, value), do: {:ok, value}

  defp root_matches?(w, value, namespace) do
    summary = Map.take(value, @summary)

    exact?(w, ~w(version root_state root root_sha256 manifest_sha256)) and w["version"] === 2 and
      summary["project"] == namespace and
      case w["root_state"] do
        "absent" ->
          w["root"] == nil and w["root_sha256"] == nil and w["manifest_sha256"] == nil and
            summary["generation"] === 0 and summary["floor"] === 0 and
            summary["floor_anchor"] == nil

        "present" ->
          is_map(w["root"]) and JSON.sha256?(w["root_sha256"]) and
            JSON.sha256?(w["manifest_sha256"]) and w["root"]["manifest"] === w["manifest_sha256"] and
            w["root"] |> Map.delete("manifest") |> Map.put("version", 3) === summary

        _ ->
          false
      end
  end

  defp exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
