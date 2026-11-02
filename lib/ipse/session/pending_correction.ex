defmodule Ipse.Session.PendingCorrection do
  @moduledoc """
  Exact host preparation for editing one pending candidate without accepting it.

  A correction preserves original source attribution, category, worker-recorded
  times and signed admission clocks. Its new text has a new candidate identity;
  the old identity is suppressed in the same transaction. Historical preparation
  is not publication permission. The owning caller must verify the original
  source, current capture policy, actual native input and synced journal intent
  again before the native final publication decision.
  """
  alias Ipse.JSON
  alias Ipse.Extension.{Collection, ManagedRecipe, SemanticConsent}
  alias Ipse.Session.{PendingAcceptance, PendingRejection}
  @error {:error, :pending_correction_refused}
  @reason "Operator corrected this selected proposal"
  @scope "replace selected pending text; preserve original provenance, category and expiry; edited candidate remains pending and needs fresh acceptance"

  def prepare(context, managed, text, policy_deadline, now) do
    with true <- JSON.safe_uint?(now) and JSON.safe_uint?(policy_deadline),
         true <- now < policy_deadline,
         {:ok, original} <- PendingRejection.prepare(context, managed, @reason),
         true <- SemanticConsent.pin?(context["original_pin"]),
         pin = context["original_pin"],
         true <- pin["epoch"] === context["management_epoch"],
         true <- pin["session_id"] === context["session_id"],
         true <- is_binary(text) and String.valid?(text) and byte_size(text) in 1..2048,
         true <- String.trim(text) != "",
         record = original["facts"]["target"],
         value = record["value"],
         true <- text !== value["text"],
         operation = context["job_id"],
         card_context = card_context(context),
         sources = get_in(value, context["recipe"]["evidence_path"]),
         {:ok, card} <- PendingAcceptance.prepare(card_context, managed, sources, now),
         {:ok, id} <- ManagedRecipe.proposal_identity(card["lineage"], text),
         key = "pending." <> id,
         replacement = value |> Map.put("id", id) |> Map.put("text", text),
         {:ok, candidate} <- ManagedRecipe.extract(context["recipe"], key, replacement, sources),
         true <- candidate["text"] === text and candidate["eligibility"] === "never_current",
         true <- byte_size(Collection.Migration.encode(replacement)) <= 4096,
         request = %{
           "op" => "commit",
           "expected_generation" => original["request"]["expected_generation"],
           "advance_floor" => true,
           "changes" => [
             %{"key" => record["key"], "expected_revision" => record["revision"], "value" => nil},
             %{"key" => key, "expected_revision" => 0, "value" => replacement},
             %{
               "key" => "reject." <> card["candidate_id"],
               "expected_revision" => 0,
               "value" => %{
                 "version" => 1,
                 "kind" => "corrected_proposal",
                 "candidate_id" => card["candidate_id"],
                 "lineage" => card["lineage"],
                 "record_sha256" => record["sha256"],
                 "record_revision" => record["revision"],
                 "management_operation_id" => operation,
                 "replacement_key" => key
               }
             }
           ]
         },
         true <- Collection.valid_request?(request),
         body =
           original["facts"]
           |> Map.drop(~w(action_sha256))
           |> Map.merge(%{
             "kind" => "managed_proposal_correction",
             "operation_id" => operation,
             "request" => request,
             "request_sha256" => JSON.digest([request]),
             "source_card" => card,
             "original_root" => get_in(managed, ["observation", "witness", "root"]),
             "policy_expires_at_ms" => policy_deadline,
             "publish_before_ms" => min(policy_deadline, card["valid_until_ms"]),
             "policy" => %{"kind" => "original_pending_deadline"},
             "scope" => @scope
           }),
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
    # Pure reconstruction authenticates no source, policy, native review or root.
    # The actual held publication must reproduce this preparation independently.
    record = facts["target"]
    collection = facts["collection"]
    witness = Map.put(collection, "root", facts["original_root"])

    managed = %{
      "metadata" => facts["metadata"],
      "observation" => %{
        "witness" => witness,
        "value" => %{"record" => record},
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => record["key"]}]),
        "result_sha256" => JSON.digest([%{"record" => record}])
      }
    }

    [_, replacement, _] = facts["request"]["changes"]

    with {:ok, prepared} <-
           prepare(
             facts["context"],
             managed,
             replacement["value"]["text"],
             facts["policy_expires_at_ms"],
             facts["metadata"]["first_admitted_ms"]
           ),
         true <- prepared["facts"] === facts do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc false
  def current_review?(facts, now),
    do:
      valid_facts?(facts) and JSON.safe_uint?(now) and
        facts["metadata"]["first_admitted_ms"] <= now and now < facts["publish_before_ms"]

  @doc false
  def card_context(context) do
    pin = context["original_pin"]

    %{
      "operation_id" => context["job_id"],
      "journal_id" => context["session_id"],
      "client_id" => context["client_id"],
      "session_id" => nil,
      "project_id" => context["project_id"],
      "namespace" => context["namespace"],
      "binding_sha256" => context["binding_sha256"],
      "policy_sha256" => pin["policy_sha256"],
      "capture_epoch" => pin["epoch"],
      "render_revision" => 1,
      "recipe" => context["recipe"]
    }
  end
end
