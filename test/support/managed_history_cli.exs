# Actual CLI management and real deadline; successor source is an explicit trusted fixture.
defmodule Ipse.Test.ManagedHistoryCLI do
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Usage}
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.{NormalizerV3, ObservedRead}
  alias Ipse.Session.{ManagedLifecycle, Resources}
  alias Ipse.Runner.Review

  def run(
        config,
        cwd,
        home,
        config_path,
        page,
        admission,
        original_journal,
        session_dir,
        session_id
      ) do
    pin = admission["pin"]
    root = SemanticAdmission.collection_root(home)
    control = SemanticAdmission.control_root(home)
    {:ok, binding} = ProjectIdentity.existing(home, cwd)
    old_record = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))
    old_key = old_record["key"]
    ordinary = Enum.find(page["records"], &(&1["value"]["category"] == "ordinary"))

    recipe =
      admission["policy"]["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    constraints = admission["policy"]["settings"]["constraints"][recipe["constraints_sha256"]]

    assert {:ok, choice} =
             Ipse.CLI.Knowledge.Management.retain(config, cwd, old_key, %{
               "kind" => "duration",
               "duration_ms" => 8_000
             })

    deadline = choice["receipt"]["publication"]["normalization"]["valid_until_ms"]

    Code.require_file("../ipse/extension/collection_normalizer_v3_test.exs", __DIR__)
    [source] = ordinary["value"]["evidence"]["sources"]
    quote = "Synthetic replacement statement for history expiry"

    source =
      source
      |> Map.merge(%{
        "occurrence_id" => Usage.id(),
        "version_id" => Usage.id(),
        "quote" => quote,
        "end_byte" => byte_size(quote),
        "quote_sha256" => JSON.sha256(quote),
        "content_sha256" => JSON.sha256(quote),
        "receipt_sha256" => JSON.sha256("synthetic trusted successor receipt")
      })

    {:ok, new_key, new_value} =
      IpseKnowledge.Knowledge.Records.capture(
        %{
          "text" => quote,
          "category" => "ordinary",
          "reason" => "trusted fixture successor",
          "event_at_ms" => nil
        },
        source,
        10 * 86_400_000
      )

    protect = fn fun ->
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fun
      )
    end

    {:ok, old} =
      protect.(fn cap, catalog ->
        ObservedRead.managed_record(
          root,
          pin["namespace"],
          %{"op" => "get_record", "key" => old_key},
          cap,
          catalog,
          recipe
        )
      end)

    {:ok, snapshot} = Consent.existing_snapshot(control, binding["project_id"])
    fixture_dir = Path.join(home, "synthetic-supersession-management")
    {:ok, fixture_id} = Journal.create(fixture_dir, %{"kind" => "synthetic_history_cli_fixture"})

    context = %{
      "session_id" => fixture_id,
      "job_id" => Usage.id(),
      "client_id" => Usage.id(),
      "project_id" => binding["project_id"],
      "namespace" => pin["namespace"],
      "binding_sha256" => binding["binding_sha256"],
      "management_epoch" => snapshot["epoch"],
      "management_sha256" =>
        Consent.management_sha256(binding["project_id"], snapshot["epoch"], snapshot["policy"]),
      "original_pin" => nil,
      "recipe" => recipe
    }

    {:ok, prepared} =
      ManagedLifecycle.prepare_supersession(
        context,
        old,
        %{"key" => new_key, "value" => new_value},
        %{
          mode: "ordinary",
          constraints: constraints,
          verified_sources: [source],
          policy_sha256: pin["policy_sha256"],
          now_ms: System.system_time(:millisecond)
        },
        "Synthetic trusted successor fixture"
      )

    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)

    try do
      assert {:ok, _} =
               Resources.file_effect(fn ->
                 {:ok, writer} = Journal.Writer.start(fixture_dir, fixture_id, self())

                 try do
                   assert :ok = Journal.Writer.append(writer, prepared["intent"])

                   result =
                     Review.with_review("correct", prepared["facts"], fn permit ->
                       publication =
                         ProjectIdentity.with_domain_publication(
                           home,
                           cwd,
                           binding,
                           %{
                             namespace: pin["namespace"],
                             format: "managed-metadata-v3",
                             operation_id: prepared["facts"]["operation_id"],
                             initialize: false
                           },
                           fn _ -> :ok end,
                           fn cap, catalog ->
                             Collection.execute_managed_supersession(
                               root,
                               pin["namespace"],
                               prepared["request"],
                               prepared["facts"]["operation_id"],
                               JSON.digest([recipe]),
                               fn witness, read ->
                                 NormalizerV3.supersede(witness, read, %{
                                   request: prepared["request"],
                                   facts: prepared["facts"],
                                   permit: permit,
                                   constraints: constraints,
                                   verified_sources: [source],
                                   policy_sha256: pin["policy_sha256"],
                                   now_ms: System.system_time(:millisecond),
                                   capture_expires_at_ms: deadline + 60_000,
                                   domain_cap: cap,
                                   catalog: catalog
                                 })
                               end
                             )
                           end
                         )

                       assert {:ok, review} =
                                Review.consumed_receipt(permit, "correct", prepared["facts"])

                       assert :ok =
                                Journal.Writer.append(writer, %{
                                  "type" => "synthetic_native_review",
                                  "receipt" => review
                                })

                       publication
                     end)

                   assert {:ok, core} = result

                   assert :ok =
                            Journal.Writer.append(writer, %{
                              "type" => "synthetic_supersession_result",
                              "result" => core
                            })

                   result
                 after
                   assert :ok = Journal.Writer.close(writer)
                 end
               end)

      assert :ok = Resources.finish(scope)
    after
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end

    assert System.system_time(:millisecond) < deadline
    args = ["--cwd", cwd, "--config", config_path, "--no-project-config"]
    assert Ipse.CLI.run(["knowledge", "disable"] ++ args) == 0
    Process.sleep(max(deadline - System.system_time(:millisecond) + 10, 0))
    directory = Path.join(home, "knowledge-management")
    previous = Enum.map(Journal.list(directory), & &1["id"])
    handler = "history-cli-intent-" <> Usage.id()
    owner = self()

    assert :ok =
             :telemetry.attach(
               handler,
               [:ipse, :extension, :collection, :staged],
               fn _, _, _, _ ->
                 [entry] = Enum.reject(Journal.list(directory), &(&1["id"] in previous))
                 assert {:ok, during} = Journal.load(directory, entry["id"])
                 assert Enum.count(during, &(&1["type"] == "managed_lifecycle_intent")) == 1
                 refute Enum.any?(during, &(&1["type"] == "managed_lifecycle_result"))
                 send(owner, :history_cli_intent_before_switch)
               end,
               nil
             )

    try do
      assert Ipse.CLI.run(["knowledge", "expire", old_key] ++ args) == 0
    after
      assert :ok = :telemetry.detach(handler)
    end

    assert_receive :history_cli_intent_before_switch, 1_000
    [entry] = Enum.reject(Journal.list(directory), &(&1["id"] in previous))
    assert {:ok, events} = Journal.load(directory, entry["id"])
    [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
    [result] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_result"))
    assert intent["facts"]["kind"] == "managed_literal_history_expiry"
    assert intent["facts"]["expired_at_ms"] == deadline
    assert result["status"] == "settled"
    normalization = result["result"]["receipt"]["publication"]["normalization"]

    assert normalization["kind"] == "managed_literal_history_expiry" and
             normalization["eligibility"] == "expired"

    assert {:ok, %{"record" => nil}} =
             Collection.execute(
               root,
               pin["namespace"],
               %{"op" => "get", "key" => old_key},
               Usage.id()
             )

    assert {:ok, %{"record" => retained}} =
             Collection.execute(
               root,
               pin["namespace"],
               %{"op" => "get", "key" => new_key},
               Usage.id()
             )

    assert retained["value"] == new_value
    assert {:ok, state} = Consent.existing_snapshot(control, binding["project_id"])
    assert state["policy"] == nil
    operation = state["operations"][intent["operation_id"]]
    assert operation["status"] == "settled" and operation["actual"]["model_calls"] == 0
    assert operation["actual"]["download_bytes"] == 0 and operation["actual"]["cost_nanos"] == 0
    assert Ipse.CLI.run(["knowledge", "operation", entry["id"]] ++ args) == 0
    assert {:ok, ^original_journal} = Journal.load(session_dir, session_id)
    IO.puts("NATIVE_HISTORY_CLI_EXPIRY_PASSED")
  end
end
