defmodule Ipse.Test.ManagedDisplayOwners do
  import ExUnit.Assertions
  alias Ipse.{JSON, Session}
  alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Runner.Transaction
  alias Ipse.Session.{ManagedUse, StoredSources}

  def run(config, cwd, home, dir, records, original_id) do
    assert length(records) == 3

    assert {:ok, consumer} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
             )

    state = :sys.get_state(consumer)
    admission = state.config.semantic_admission
    pin = admission["pin"]
    context = %{config: state.config, cwd: cwd, session_id: state.id, history_dir: dir}
    root = SemanticAdmission.collection_root(home)

    recipe =
      admission["policy"]["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    dependencies =
      for record <- records do
        assert {:ok, dependency} =
                 ProjectIdentity.with_existing_domain_auth(
                   home,
                   cwd,
                   admission["binding"],
                   %{namespace: pin["namespace"], format: "managed-metadata-v3"},
                   fn cap, catalog ->
                     Consent.with_policy(
                       SemanticAdmission.control_root(home),
                       pin["project_id"],
                       pin["epoch"],
                       pin["policy_sha256"],
                       System.system_time(:millisecond),
                       fn _ ->
                         request = %{"op" => "get_record", "key" => record["key"]}

                         with {:ok, observed} <-
                                ObservedRead.managed_record(
                                  root,
                                  pin["namespace"],
                                  request,
                                  cap,
                                  catalog,
                                  recipe
                                ),
                              proofs = record["value"]["evidence"]["sources"],
                              do:
                                ObservedRead.managed_dependency(
                                  request,
                                  observed,
                                  pin,
                                  recipe,
                                  proofs,
                                  System.system_time(:millisecond)
                                )
                       end
                     )
                   end
                 )

        dependency
      end

    assert {:ok, dependencies} = Session.ManagedReference.union([dependencies])
    source_path = Path.join(dir, original_id <> ".jsonl")
    original = File.read!(source_path)

    assert {:ok, :checked} =
             ManagedUse.with_display_dependencies(context, dependencies, fn current, held ->
               assert current == dependencies
               assert length(held.source_proofs) == 3
               assert held.active_sources == false
               assert [%{session_id: ^original_id, token: token}] = held.source_leases

               assert {:ok, %{session_id: ^original_id, identity: source}} =
                        StoredSources.share_verified_identity(token, held.source_proofs)

               assert source.pid > 0 and source.inode > 0
               assert {:error, _} = Ipse.Runner.lock(Path.join(dir, original_id <> ".lock"))
               assert {:ok, caps} = Transaction.retained_share_stack()
               assert caps == [held.identity, held.consent, held.collection]

               ids =
                 Enum.map(caps, fn cap ->
                   assert {:ok, actual} = Transaction.retained_share_identity(cap)
                   actual
                 end)

               assert Enum.map(ids, & &1.slot) == [0, 1, 2]
               assert length(Enum.uniq(Enum.map(ids, & &1.pid))) == 1
               assert length(Enum.uniq(Enum.map(ids, &{&1.device, &1.inode}))) == 3
               assert JSON.sha256(File.read!(source_path)) == JSON.sha256(original)
               {:ok, :checked}
             end)

    assert File.read!(source_path) == original

    assert {:ok, :checked} =
             ManagedUse.with_display_dependencies(context, dependencies, fn _, held ->
               assert [%{token: token}] = held.source_leases

               assert {:error, _} =
                        Task.async(fn -> StoredSources.share_identity(token) end) |> Task.await()

               {:ok, :checked}
             end)

    lock_path = Path.join(dir, original_id <> ".lock")
    assert {:ok, lock} = Ipse.Runner.lock(lock_path)
    File.write!(source_path, original <> "{partial", [:write])
    assert :ok = Ipse.Runner.unlock(lock)

    assert {:error, _} =
             ManagedUse.with_display_dependencies(context, dependencies, fn _, _ ->
               flunk("changed original source entered the display adapter")
             end)

    assert File.read!(source_path) == original <> "{partial"
    assert {:ok, lock} = Ipse.Runner.lock(lock_path)
    File.write!(source_path, original, [:write])
    assert :ok = Ipse.Runner.unlock(lock)

    assert :ok = Session.close_confirmed(consumer)
    assert {:ok, events} = Ipse.Journal.load(dir, state.id)
    assert {:ok, _} = Session.Saved.restore(events, state.id)
    refute Enum.any?(events, &(&1["type"] in ~w(request_admitted tool_started)))
    IO.puts("NATIVE_MANAGED_DISPLAY_SOURCE_OWNERS_PASSED")
  end
end
