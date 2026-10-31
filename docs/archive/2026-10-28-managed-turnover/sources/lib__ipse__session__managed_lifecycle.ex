defmodule Ipse.Session.ManagedLifecycle do
  @moduledoc """
  Host-private exact facts for native management of one signed literal note.

  Preparation consumes an observation already obtained under the owning host's
  Identity and management policy boundary. It grants no authority. The owner
  must journal the returned intent before entering its protected publication
  callback, and pass the actual volatile Review permit to NormalizerV3.forget/3.
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
  def prepare(context, managed, reason) do
    with true <- context?(context),
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
           "kind" => "managed_literal_forget",
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
           "scope" => "selected literal derivative; original journal and shared evidence remain"
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
  def context?(context) do
    is_map(context) and Enum.sort(Map.keys(context)) == @context and
      Enum.all?(~w(session_id job_id client_id), &id?(context[&1])) and
      Enum.all?(
        ~w(project_id namespace binding_sha256 management_sha256),
        &JSON.sha256?(context[&1])
      ) and
      JSON.safe_uint?(context["management_epoch"]) and
      original_pin?(context["original_pin"], context) and
      ManagedRecipe.valid?(context["recipe"]) and context["recipe"]["kind"] == "literal_source"
  rescue
    _ -> false
  end

  defp original_pin?(nil, _), do: true

  defp original_pin?(pin, context),
    do:
      SemanticConsent.pin?(pin) and pin["project_id"] == context["project_id"] and
        pin["namespace"] == context["namespace"] and
        pin["binding_sha256"] == context["binding_sha256"]

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[a-f0-9]{32}\z/, value)
end
