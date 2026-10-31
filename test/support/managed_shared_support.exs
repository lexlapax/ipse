# Actual Session source receipts and signed records; expiry waits for a real reviewed deadline.
defmodule Ipse.Test.ManagedSharedSupport do
  import ExUnit.Assertions
  alias Ipse.{Extension.Collection, Extension.ProjectIdentity, Session.StoredSources, Usage}
  alias Ipse.Extension.Collection.{ManagedPages, NormalizerV3, ObservedRead}

  def run(config, cwd, home, dir, session_id, ordinary, temporal, deadline) do
    admission = config.semantic_admission
    pin = admission["pin"]
    root = Ipse.Extension.SemanticAdmission.collection_root(home)
    {:ok, binding} = ProjectIdentity.existing(home, cwd)

    recipe =
      admission["policy"]["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    {:ok, snapshot} =
      Collection.execute(root, pin["namespace"], %{"op" => "snapshot"}, Usage.id())

    {:ok, page} =
      Collection.scan_visible(
        root,
        pin["namespace"],
        %{"op" => "scan", "after" => nil, "generation" => snapshot["generation"], "limit" => 8},
        Usage.id()
      )

    separate = Enum.find(page["records"], &(&1["value"]["text"] == "A separate claim to forget"))

    successor =
      Enum.find(page["records"], &(&1["value"]["text"] == "My fixture timezone is Europe/Berlin"))

    assert separate && successor

    history = fn ->
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, catalog ->
          ObservedRead.managed_history(
            root,
            pin["namespace"],
            %{"op" => "get_record", "key" => temporal["key"]},
            cap,
            catalog,
            recipe
          )
        end
      )
    end

    current = fn ->
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, catalog ->
          ObservedRead.managed_record(
            root,
            pin["namespace"],
            %{"op" => "get_record", "key" => successor["key"]},
            cap,
            catalog,
            recipe
          )
        end
      )
    end

    {:ok, old_history} = history.()
    {:ok, new_current} = current.()
    {:ok, backup} = Collection.execute(root, pin["namespace"], %{"op" => "snapshot"}, Usage.id())

    {anchor_before_record, anchor_before} =
      anchor(root, pin, home, cwd, binding, ordinary["value"]["lineage"])

    assert is_map(anchor_before["choice"])
    management_dir = Path.join(home, "knowledge-management")

    retention =
      Enum.find_value(Ipse.Journal.list(management_dir), fn entry ->
        {:ok, events} = Ipse.Journal.load(management_dir, entry["id"])
        intent = Enum.find(events, &(&1["type"] == "managed_lifecycle_intent"))
        result = Enum.find(events, &(&1["type"] == "managed_lifecycle_result"))

        if intent && result && intent["facts"]["kind"] == "managed_literal_retention" &&
             intent["facts"]["target"]["key"] == ordinary["key"],
           do: {entry["id"], events, intent, result}
      end)

    assert {retention_id, retention_events, retention_intent, retention_result} = retention
    choice = anchor_before["choice"]

    review = %{
      "version" => 1,
      "kind" => "native_review",
      "command" => "duration",
      "event_id" => choice["event_id"],
      "display_sha256" => choice["display_sha256"],
      "challenge" => choice["challenge"],
      "input_sha256" => choice["input_sha256"],
      "observed_at_ms" => choice["observed_at_ms"],
      "facts_sha256" => Ipse.JSON.digest([retention_intent["facts"]])
    }

    assert retention_result["result"]["receipt"]["native_review_sha256"] ==
             Ipse.JSON.digest([review])

    assert {:error, _} = Ipse.CLI.Knowledge.Management.expire(config, cwd, ordinary["key"])
    proofs = temporal["value"]["evidence"]["sources"] ++ successor["value"]["evidence"]["sources"]
    assert length(proofs) == 2 and Enum.all?(proofs, &(&1["session_id"] == session_id))
    context = %{config: config, session_id: Usage.id(), history_dir: dir}

    verify = fn ->
      assert {:ok, checked} = StoredSources.with_verified(context, nil, proofs, &{:ok, &1})
      assert Enum.map(checked, & &1["proof"]) == proofs
    end

    {:ok, journal_before} = File.read(Path.join(dir, session_id <> ".jsonl"))
    verify.()
    Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
    journals_before = Enum.map(Ipse.Journal.list(management_dir), & &1["id"])
    telemetry_id = "compaction-intent-" <> Usage.id()
    test_owner = self()

    assert :ok =
             :telemetry.attach(
               telemetry_id,
               [:ipse, :extension, :collection, :staged],
               fn _, _, _, _ ->
                 [entry] =
                   Enum.reject(Ipse.Journal.list(management_dir), &(&1["id"] in journals_before))

                 {:ok, during} = Ipse.Journal.load(management_dir, entry["id"])
                 intent = Enum.find(during, &(&1["type"] == "managed_lifecycle_intent"))
                 true = intent["facts"]["metadata"]["choice"] == choice
                 false = Enum.any?(during, &(&1["type"] == "managed_lifecycle_result"))
                 {_, units, :open} = Process.get({Collection, :managed_read})
                 send(test_owner, {:compaction_intent_before_switch, units})
               end,
               nil
             )

    started = System.monotonic_time(:millisecond)

    expired =
      try do
        assert {:ok, result} = Ipse.CLI.Knowledge.Management.expire(config, cwd, ordinary["key"])
        result
      after
        assert :ok = :telemetry.detach(telemetry_id)
      end

    elapsed = System.monotonic_time(:millisecond) - started
    assert_receive {:compaction_intent_before_switch, units}, 1_000
    assert units <= 32
    IO.puts("HISTORY_COMPACTION_READ_UNITS=#{units}")

    assert expired["receipt"]["publication"]["normalization"]["kind"] ==
             "managed_literal_history_expiry"

    assert expired["receipt"]["publication"]["normalization"]["retention_choice_compacted"] ==
             true

    assert {:ok, expiry_events} =
             Ipse.Journal.load(expired["journal_directory"], expired["journal_id"])

    expiry_intent = Enum.find(expiry_events, &(&1["type"] == "managed_lifecycle_intent"))
    assert expiry_intent["facts"]["metadata"]["choice"] == choice
    assert expiry_intent["facts"]["metadata"]["lineage"] == ordinary["value"]["lineage"]
    assert {:ok, ^retention_events} = Ipse.Journal.load(management_dir, retention_id)

    {anchor_after_record, anchor_after} =
      anchor(root, pin, home, cwd, binding, ordinary["value"]["lineage"])

    commitment = anchor_after["choice"]
    assert commitment["version"] == 1
    assert commitment["kind"] == "native_management_commitment"
    assert ManagedPages.compact_choice?(ordinary["value"]["lineage"], commitment, choice)

    old_page =
      Path.join([root, pin["namespace"], "objects", anchor_before_record["sha256"] <> ".json"])

    refute File.exists?(old_page)
    tampered = Map.put(choice, "reason", "Altered retained review")

    altered_facts =
      expiry_intent["facts"]
      |> put_in(["metadata", "choice"], tampered)
      |> Map.delete("action_sha256")

    altered_facts = Map.put(altered_facts, "action_sha256", Ipse.JSON.digest([altered_facts]))
    altered_file = Path.join(Path.dirname(home), "altered-expiry-intent.json")
    File.write!(altered_file, Jason.encode!(%{expiry_intent | "facts" => altered_facts}))
    altered = altered_file |> File.read!() |> Jason.decode!()

    assert altered["facts"]["action_sha256"] ==
             Ipse.JSON.digest([Map.delete(altered["facts"], "action_sha256")])

    refute ManagedPages.compact_choice?(
             ordinary["value"]["lineage"],
             commitment,
             altered["facts"]["metadata"]["choice"]
           )

    IO.puts("HISTORY_COMPACTION_SIGNED_TAMPER_REFUSED_AFTER_OLD_PAGE_GC")
    assert anchor_after["clocks"] == anchor_before["clocks"]
    assert anchor_after["retirement"] == anchor_before["retirement"]
    reclaimed = anchor_before_record["bytes"] - anchor_after_record["bytes"]
    assert reclaimed > 0
    IO.puts("HISTORY_COMPACTION_PAGE_BYTES_RECLAIMED=#{reclaimed}")
    IO.puts("HISTORY_COMPACTION_ELAPSED_MS=#{elapsed}")

    {:ok, fresh} = Collection.execute(root, pin["namespace"], %{"op" => "snapshot"}, Usage.id())

    request = %{
      "op" => "commit",
      "expected_generation" => fresh["generation"],
      "advance_floor" => true,
      "changes" => [
        %{"key" => ordinary["key"], "expected_revision" => 0, "value" => ordinary["value"]}
      ]
    }

    constraints = admission["policy"]["settings"]["constraints"][recipe["constraints_sha256"]]
    operation_id = Usage.id()

    assert {:error, :managed_normalization_refused} =
             ProjectIdentity.with_domain_publication(
               home,
               cwd,
               binding,
               %{
                 namespace: pin["namespace"],
                 format: "managed-metadata-v3",
                 operation_id: operation_id,
                 initialize: false
               },
               fn _ -> :ok end,
               fn cap, catalog ->
                 Collection.execute_managed_v3(
                   root,
                   pin["namespace"],
                   request,
                   operation_id,
                   Ipse.JSON.digest([recipe]),
                   fn witness, read ->
                     NormalizerV3.normalize(witness, read, %{
                       request: request,
                       recipe: recipe,
                       constraints: constraints,
                       verified_sources: ordinary["value"]["evidence"]["sources"],
                       policy_sha256: pin["policy_sha256"],
                       now_ms: System.system_time(:millisecond),
                       domain_cap: cap,
                       catalog: catalog
                     })
                   end
                 )
               end
             )

    old_import =
      request
      |> Map.put("op", "import")
      |> Map.merge(%{"project" => pin["namespace"], "floor" => backup["floor"]})

    assert {:failed, %{"code" => "collection_import_floor"}} =
             Collection.execute(root, pin["namespace"], old_import, Usage.id())

    verify.()
    assert {:ok, after_expiry} = history.()
    assert after_expiry["metadata"] == old_history["metadata"]
    assert {:ok, after_expiry_current} = current.()
    assert after_expiry_current["metadata"] == new_current["metadata"]

    assert {:ok, forgotten} = Ipse.CLI.Knowledge.Management.forget(config, cwd, separate["key"])

    assert forgotten["receipt"]["publication"]["normalization"]["kind"] ==
             "native_literal_forget"

    verify.()
    assert {:ok, after_forget} = history.()
    assert after_forget["metadata"] == old_history["metadata"]
    assert {:ok, after_forget_current} = current.()
    assert after_forget_current["metadata"] == new_current["metadata"]
    assert {:ok, ^journal_before} = File.read(Path.join(dir, session_id <> ".jsonl"))
    IO.puts("MANAGED_SHARED_SUPPORT_PASSED")
  end

  defp anchor(root, pin, home, cwd, binding, lineage) do
    {:ok, result} =
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, _ ->
          {:ok, view} = Collection.open_view(root, pin["namespace"])

          try do
            {:ok, neighbors} =
              Collection.view_neighbors(view, %{
                "version" => 1,
                "prefix" => ManagedPages.prefix(:anchor),
                "fence_bytes" => ManagedPages.width(:anchor),
                "needle" => lineage
              })

            key = neighbors["neighbors"]["selected"]["key"]
            {:ok, read} = Collection.view_read(view, %{"op" => "get_many", "keys" => [key]})
            assert read["witness"] == neighbors["witness"]
            [record] = read["records"]
            {:ok, page} = ManagedPages.open(cap, record, neighbors)
            {:ok, {record, page.entries[lineage]}}
          after
            assert :ok = Collection.close_view(view)
          end
        end
      )

    result
  end
end
