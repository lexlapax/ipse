# Actual native Session correction followed by CLI management and real history expiry.
defmodule Ipse.Test.ManagedHistoryCLI do
  import ExUnit.Assertions
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}

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

    assert {:ok, choice} =
             Ipse.CLI.Knowledge.Management.retain(config, cwd, old_key, %{
               "kind" => "duration",
               "duration_ms" => 8_000
             })

    deadline = choice["receipt"]["publication"]["normalization"]["valid_until_ms"]
    quote = "Native replacement statement for history expiry"
    command = "/correct " <> old_key <> " " <> quote
    opts = [config: config, cwd: cwd, state_dir: session_dir, subscriber: self()]
    assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    new_id = Session.info(session).id
    assert new_id != session_id
    assert {:ok, channel} = Session.open_input_channel(session, self())

    try do
      File.write!(Path.join(config.fixture_root, "supersession-input-1"), command)
      IO.write("IPSE_SUPERSESSION_READ_1> ")

      assert {:ok, ^command, witness} =
               Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

      assert {:ok, ticket} = Session.stage_input(session, channel, command, witness)

      assert {:ok, %{"render_id" => render}} =
               Session.prepare_assertion(session, channel, command, ticket)

      assert {:ok, input, witness} =
               Session.observe_channel(
                 session,
                 channel,
                 %{"kind" => "assertion", "render_id" => render},
                 30_000
               )

      assert :ok = Session.accept_assertion_observed(session, channel, render, input, witness)
      assert_receive {:ipse, ^session, {:done, :ok}}, 20_000
    after
      assert :ok = Session.close_confirmed(session)
    end

    assert {:ok, correction} = Journal.load(session_dir, new_id)
    assert {:ok, _} = Session.Saved.restore(correction, new_id)
    [relation] = Enum.filter(correction, &(&1["type"] == "managed_supersession_intent"))
    [result] = Enum.filter(correction, &(&1["type"] == "managed_supersession_result"))
    [review] = Enum.filter(correction, &(&1["type"] == "managed_supersession_review"))
    assert result["status"] == "settled"
    assert review["operation_id"] == relation["operation_id"]
    assert result["outcome"]["publication"]["normalization"]["history_valid_until_ms"] == deadline
    assert relation["facts"]["target"]["key"] == old_key
    new_key = relation["facts"]["replacement"]["key"]
    proofs = get_in(relation, ["facts", "replacement", "value", "evidence", "sources"])

    assert Enum.any?(
             proofs,
             &(&1["session_id"] == new_id and &1["origin"] == "native_operator_assertion")
           )

    refute Enum.any?(correction, &(&1["type"] == "request_admitted"))

    assert {:ok, %{"record" => successor}} =
             Collection.execute(
               root,
               pin["namespace"],
               %{"op" => "get", "key" => new_key},
               Usage.id()
             )

    new_value = successor["value"]
    assert new_value["text"] == quote

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
