defmodule Ipse.Test.ManagedPinnedHistorySession do
  import ExUnit.Assertions
  alias Ipse.Extension.{Collection, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.{ManagedRetention, ObservedRead}

  def run(config, cwd, home, previous, events) do
    admission = config.semantic_admission
    pin = admission["pin"]
    root = SemanticAdmission.collection_root(home)

    intent =
      Enum.find(events, fn event ->
        event["type"] == "managed_supersession_intent" and
          get_in(event, ["facts", "target", "key"]) == previous["key"]
      end)

    assert intent
    facts = intent["facts"]
    assert facts["metadata"]["category"] == "pin"
    assert facts["history_rule"] == nil

    history = fn ->
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        admission["binding"],
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, catalog ->
          ObservedRead.managed_history(
            root,
            pin["namespace"],
            %{"op" => "get_record", "key" => previous["key"]},
            cap,
            catalog,
            facts["context"]["recipe"]
          )
        end
      )
    end

    assert {:ok, before} = history.()
    assert before["metadata"]["previous_category"] == "pin"
    assert before["metadata"]["valid_until_ms"] == nil
    assert before["successor_storage"] == "matching_record"
    assert before["metadata"]["successor"]["key"] == facts["replacement"]["key"]

    far = System.system_time(:millisecond) + 1000 * 365 * 86_400_000
    assert ManagedRetention.eligible_history_metadata?(before["metadata"], far)
    refute ManagedRetention.expired_history_metadata?(before["metadata"], far)

    assert {:error, :managed_lifecycle_refused} =
             Ipse.Session.ManagedLifecycle.prepare_history_expiry(facts["context"], before, far)

    assert {:ok, snapshot} =
             Collection.execute(root, pin["namespace"], %{"op" => "snapshot"}, Ipse.Usage.id())

    session_id = facts["context"]["session_id"]
    source_path = Path.join([home, "sessions", session_id <> ".jsonl"])
    source_bytes = File.read!(source_path)

    assert {:ok, _} =
             Ipse.CLI.Knowledge.Management.forget(config, cwd, facts["replacement"]["key"])

    assert {:ok, after_forget} = history.()
    assert after_forget["successor_storage"] == "unavailable"
    assert after_forget["metadata"] === before["metadata"]
    assert after_forget["observation"]["value"] === before["observation"]["value"]
    assert ManagedRetention.eligible_history_metadata?(after_forget["metadata"], far)

    assert {:ok, next} =
             Collection.execute(root, pin["namespace"], %{"op" => "snapshot"}, Ipse.Usage.id())

    assert next["generation"] == snapshot["generation"] + 1
    assert next["floor"] == next["generation"]
    assert File.read!(source_path) === source_bytes
    assert {:ok, stored} = Ipse.Journal.load(Path.join(home, "sessions"), session_id)
    assert {:ok, _} = Ipse.Session.Saved.restore(stored, session_id)
    refute File.exists?(Path.join(Path.dirname(home), "unexpected-model"))

    assert :ok =
             Ipse.Session.ManagedSupersession.validate_events(
               events,
               facts["context"]["session_id"]
             )

    IO.puts("NATIVE_PINNED_HISTORY_SESSION_PASSED")
  end
end
