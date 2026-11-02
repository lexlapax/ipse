defmodule Ipse.CLI.Knowledge.Batch do
  @moduledoc false
  alias Ipse.{JSON, Usage}
  alias Ipse.CLI.{Knowledge.Management, Terminal}
  alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Session.{PendingAcceptance, PendingBatch}
  @error {:error, :pending_batch_refused}

  def run(config, cwd, history_dir, keys) do
    with true <- PendingBatch.keys?(keys),
         true <- is_binary(history_dir) and Path.type(history_dir) === :absolute,
         :ok <- Management.management_effect_mode(config),
         {:ok, manifest} <- prepare(config, cwd, history_dir, keys) do
      digest = JSON.digest([manifest])

      Terminal.puts(
        "Pending batch: #{manifest["id"]}; manifest #{digest}; #{length(keys)} selected items."
      )

      Enum.reduce_while(Enum.with_index(keys), {:ok, []}, fn {key, index}, {:ok, completed} ->
        {:ok, bound} = PendingBatch.binding(manifest, index)

        case Management.review(config, cwd, history_dir, key, bound) do
          {:ok, result} ->
            Terminal.puts("Accepted batch item #{index + 1} of #{length(keys)}: #{key}")
            Terminal.puts(Jason.encode!(result))
            {:cont, {:ok, completed ++ [Map.put(result, "pending_key", key)]}}

          result ->
            {:halt,
             {:halted,
              %{
                "manifest_sha256" => digest,
                "completed" => completed,
                "stopped_key" => key,
                "remaining_keys" => Enum.drop(keys, index),
                "reason" => inspect(result),
                "replayed" => false
              }}}
        end
      end)
      |> case do
        {:ok, completed} -> {:ok, %{"manifest_sha256" => digest, "completed" => completed}}
        halted -> halted
      end
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :pending_batch_unconfirmed}
  end

  defp prepare(config, cwd, history_dir, keys) do
    with {:ok, selected} <-
           Management.acceptance_source_selection(config, cwd, history_dir, Usage.id()) do
      pin = selected.context.config.semantic_admission["pin"]

      context = %{
        "operation_id" => Usage.id(),
        "journal_id" => pin["session_id"],
        "client_id" => Usage.id(),
        "session_id" => nil,
        "project_id" => selected.binding["project_id"],
        "namespace" => pin["namespace"],
        "binding_sha256" => selected.binding["binding_sha256"],
        "policy_sha256" => pin["policy_sha256"],
        "capture_epoch" => pin["epoch"],
        "render_revision" => 1,
        "recipe" => selected.selection.proposal
      }

      ProjectIdentity.with_existing_domain_auth(
        config[:home],
        cwd,
        selected.binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, catalog ->
          Consent.with_policy(
            SemanticAdmission.control_root(config[:home]),
            selected.binding["project_id"],
            pin["epoch"],
            pin["policy_sha256"],
            System.system_time(:millisecond),
            fn snapshot ->
              with {:ok, current} <- Management.selection(config[:home]),
                   true <- current === selected.selection,
                   {:ok, cards} <- read_cards(config, keys, cap, catalog, context),
                   {:ok, manifest} <-
                     PendingBatch.prepare(
                       cards,
                       selected.selection.recipe,
                       snapshot["policy"]["expires_at_ms"]
                     ) do
                {:ok, manifest}
              else
                _ -> @error
              end
            end
          )
        end
      )
    else
      _ -> @error
    end
  end

  defp read_cards(config, keys, cap, catalog, context) do
    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, cards} ->
      result =
        ObservedRead.with_managed_proposal_removal(
          SemanticAdmission.collection_root(config[:home]),
          context["namespace"],
          %{"op" => "get_record", "key" => key},
          cap,
          catalog,
          context["recipe"],
          fn managed ->
            sources =
              get_in(managed, ["observation", "value", "record", "value", "evidence", "sources"])

            PendingAcceptance.prepare(context, managed, sources, System.system_time(:millisecond))
          end
        )

      case result do
        {:ok, card} -> {:cont, {:ok, cards ++ [card]}}
        _ -> {:halt, @error}
      end
    end)
  end
end
