defmodule Ipse.Test.ManagedHistoryUse do
  import ExUnit.Assertions
  alias Ipse.Session.{ManagedReference, ManagedUse}
  alias Ipse.Extension.{Consent, SemanticAdmission}

  def run(config, opts, cwd, home, dir, previous) do
    assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    id = Ipse.Session.info(session).id
    active_config = :sys.get_state(session).config
    admission = active_config.semantic_admission
    pin = admission["pin"]

    {recipe_sha, _} =
      Enum.find(admission["policy"]["settings"]["recipes"], fn {_, recipe} ->
        recipe["kind"] == "literal_source"
      end)

    context = %{config: active_config, session_id: id, history_dir: dir, cwd: cwd}
    owner = self()

    assert {:ok, {dependency, successor}} =
             ManagedUse.with_history_selection(context, previous["key"], recipe_sha, fn history,
                                                                                        dependency ->
               assert history["observation"]["value"]["record"]["value"]["text"] ==
                        "My fixture timezone is UTC"

               assert history["successor_storage"] == "matching_record"
               assert dependency["version"] == 5
               assert dependency["subject"]["kind"] == "historical_record_observation"
               {:ok, {dependency, history["metadata"]["successor"]["key"]}}
             end)

    assert {:ok, [_]} = ManagedUse.with_dependencies(context, [dependency], &{:ok, &1})
    tampered = put_in(dependency, ["subject", "successor", "sha256"], Ipse.JSON.sha256("wrong"))
    refute ManagedReference.current?(dependency, tampered, System.system_time(:millisecond))

    expired =
      put_in(
        dependency,
        ["subject", "validity", "valid_until_ms"],
        System.system_time(:millisecond) - 1
      )

    refute ManagedReference.current?(expired, expired, System.system_time(:millisecond))

    assert {:ok, _} = Ipse.CLI.Knowledge.Management.forget(config, cwd, successor)
    assert {:ok, [_]} = ManagedUse.with_dependencies(context, [dependency], &{:ok, &1})

    assert {:ok, "unavailable"} =
             ManagedUse.with_history_selection(context, previous["key"], recipe_sha, fn history,
                                                                                        _ ->
               {:ok, history["successor_storage"]}
             end)

    [proof] = previous["value"]["evidence"]["sources"]
    original = Path.join(dir, proof["session_id"] <> ".jsonl")
    assert :ok = File.chmod(original, 0o000)

    try do
      assert {:error, _} =
               ManagedUse.with_dependencies(context, [dependency], fn _ ->
                 send(owner, :unexpected_use)
                 :ok
               end)

      refute_receive :unexpected_use, 10
    after
      assert :ok = File.chmod(original, 0o600)
    end

    control = SemanticAdmission.control_root(home)
    {:ok, snapshot} = Consent.existing_snapshot(control, pin["project_id"])
    assert {:ok, _} = Consent.revoke(control, pin["project_id"], snapshot["epoch"])

    assert {:error, _} =
             ManagedUse.with_dependencies(context, [dependency], fn _ ->
               send(owner, :unexpected_use)
               :ok
             end)

    refute_receive :unexpected_use, 10
    assert :ok = Ipse.Session.close_confirmed(session)
    IO.puts("MANAGED_HISTORY_USE_PASSED")
  end
end
