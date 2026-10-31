defmodule Ipse.Test.ManagedOutputLiteral do
  @moduledoc false
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Session.Resources

  # The caller supplies a real admitted Session configuration and a literal
  # captured by its native review. The existing management owner performs the
  # full journal, native Review, Consent and protected Core publication path.
  def shorten(config, cwd, history_dir, note_key, duration_ms) do
    assert JSON.safe_uint?(duration_ms) and duration_ms > 0
    admission = config.semantic_admission
    assert admission["status"] == "active"
    pin = admission["pin"]
    binding = admission["binding"]
    policy = admission["policy"]
    assert JSON.digest([policy]) == pin["policy_sha256"]
    assert {:ok, ^binding} = ProjectIdentity.existing(config.home, cwd)

    [recipe] =
      policy["settings"]["recipes"]
      |> Map.values()
      |> Enum.filter(&(&1["kind"] == "literal_source"))

    history = journal_digests(history_dir)
    {:ok, before} = observe(config, cwd, binding, pin, recipe, note_key)
    requested = %{"kind" => "duration", "duration_ms" => duration_ms}

    assert {:ok, result} = Management.retain(config, cwd, note_key, requested)
    assert result["storage_status"] == "settled"
    assert {:ok, after_choice} = observe(config, cwd, binding, pin, recipe, note_key)

    assert after_choice["metadata"]["first_admitted_ms"] ==
             before["metadata"]["first_admitted_ms"]

    before_record = before["observation"]["value"]["record"]
    after_record = after_choice["observation"]["value"]["record"]
    assert after_record["value"] === before_record["value"]
    assert after_record["revision"] > before_record["revision"]
    choice = after_choice["metadata"]["choice"]
    assert choice["policy"] === requested
    deadline = choice["observed_at_ms"] + duration_ms
    assert after_choice["metadata"]["valid_until_ms"] === deadline

    assert result["receipt"]["publication"]["normalization"]["valid_until_ms"] === deadline
    assert deadline > System.system_time(:millisecond)
    assert journal_digests(history_dir) === history

    assert {:ok, %{"journal_status" => "settled", "replayed" => false}} =
             Management.operation(config, cwd, result["journal_id"])

    assert {:ok, management_events} =
             Journal.load(result["journal_directory"], result["journal_id"])

    assert Enum.count(management_events, &(&1["type"] == "managed_lifecycle_intent")) == 1
    assert Enum.count(management_events, &(&1["type"] == "managed_lifecycle_result")) == 1
    refute Enum.any?(management_events, &(&1["type"] == "inference_dispatch_intent"))

    assert {:ok, control} =
             Consent.existing_snapshot(
               SemanticAdmission.control_root(config.home),
               pin["project_id"]
             )

    operation = control["operations"][result["operation_id"]]
    assert operation["status"] == "settled"
    assert operation["actual"]["model_calls"] == 0
    assert operation["actual"]["download_bytes"] == 0
    assert operation["actual"]["cost_nanos"] == 0
    deadline
  end

  defp observe(config, cwd, binding, pin, recipe, key) do
    Resources.file_effect(fn ->
      ProjectIdentity.with_existing_domain_auth(
        config.home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, catalog ->
          Consent.with_policy(
            SemanticAdmission.control_root(config.home),
            pin["project_id"],
            pin["epoch"],
            pin["policy_sha256"],
            System.system_time(:millisecond),
            fn _ ->
              ObservedRead.managed_record(
                SemanticAdmission.collection_root(config.home),
                pin["namespace"],
                %{"op" => "get_record", "key" => key},
                cap,
                catalog,
                recipe
              )
            end
          )
        end
      )
    end)
  end

  defp journal_digests(directory) do
    directory
    |> Path.join("*.jsonl")
    |> Path.wildcard()
    |> Map.new(fn path -> {path, JSON.sha256(File.read!(path))} end)
  end
end
