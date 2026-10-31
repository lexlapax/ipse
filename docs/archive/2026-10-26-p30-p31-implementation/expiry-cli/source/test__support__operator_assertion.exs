ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

[root, requested_scenario] = System.argv()

scenario =
  if String.starts_with?(requested_scenario, "save_"), do: "save", else: requested_scenario

home = Path.join(root, "home")
cwd = Path.join(root, "work")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
)

File.chmod!(config_path, 0o600)

assert Ipse.CLI.run([
         "knowledge",
         "enable",
         "--cwd",
         cwd,
         "--config",
         config_path,
         "--no-project-config"
       ]) == 0

defmodule AssertionUnexpectedModel do
  def complete(config, _, _, _) do
    File.write!(Path.join(config.fixture_root, "unexpected-model"), "called")
    raise "this native command must not invoke a model"
  end
end

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: true,
  accept_edits: false,
  approval: :ask,
  approval_origin: :interactive,
  headless: false
}

{:ok, effective} =
  Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

{:ok, config} = Ipse.Config.runtime(effective, client)
config = Map.merge(config, %{provider_module: AssertionUnexpectedModel, fixture_root: root})
config = if scenario == "planning", do: Map.put(config, :execution_mode, :planning), else: config
dir = Path.join(home, "sessions")
opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]
assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
id = Ipse.Session.info(session).id
assert :sys.get_state(session).config.semantic_admission["status"] == "active"

if scenario == "revoked" do
  Task.start_link(fn ->
    deadline = System.monotonic_time(:millisecond) + 10_000

    wait = fn wait ->
      unless File.exists?(Path.join(root, "assertion-review-ready")) do
        assert System.monotonic_time(:millisecond) < deadline
        Process.sleep(5)
        wait.(wait)
      end
    end

    wait.(wait)
    {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
    control = Ipse.Extension.SemanticAdmission.control_root(home)
    {:ok, snapshot} = Ipse.Extension.Consent.snapshot(control, binding["project_id"])

    assert {:ok, _} =
             Ipse.Extension.Consent.revoke(control, binding["project_id"], snapshot["epoch"])

    File.write!(Path.join(root, "assertion-permission-revoked"), "done")
  end)
end

IO.puts("IPSE_ASSERTION_CLI_READY")
assert Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd) == 0

assert {:ok, events} = Ipse.Journal.load(dir, id)
IO.puts("ASSERTION_JOURNAL_TYPES " <> Jason.encode!(Enum.frequencies_by(events, & &1["type"])))

IO.puts(
  "ASSERTION_OUTCOMES " <>
    Jason.encode!(
      for e <- events,
          String.starts_with?(e["type"] || "", "extension_"),
          do: Map.take(e, ~w(type status error code reason outcome name stage))
    )
)

assertions = Enum.filter(events, &(&1["type"] == "operator_assertion"))

expected_assertions =
  case scenario do
    "save" -> 3
    "revoked" -> 1
    _ -> 0
  end

assert length(assertions) == expected_assertions

assert {:ok, restored} = Ipse.Session.Saved.restore(events, id)
assert restored.managed_reads.outputs == :sys.get_state(session).managed_outputs

if scenario == "save" do
  receipts = Enum.filter(events, &(&1["type"] == "managed_read_observed"))
  assert length(receipts) == 6
  [receipt | _] = receipts
  index = Enum.find_index(events, &(&1 == receipt))
  assert {:ok, prefix} = Ipse.Extension.Actions.restore(Enum.take(events, index + 1))
  assert prefix.managed_read == receipt
  assert prefix.managed_dependencies == []

  for changed <- [
        Enum.reject(events, &(&1 == receipt)),
        List.insert_at(events, index, receipt),
        List.replace_at(events, index, Map.put(receipt, "session_id", Ipse.Usage.id())),
        List.replace_at(
          events,
          index,
          Map.put(receipt, "result_sha256", Ipse.JSON.sha256("foreign result"))
        )
      ] do
    assert {:error, :invalid_extension_action} = Ipse.Session.Saved.restore(changed, id)
  end
end

refute File.exists?(Path.join(root, "unexpected-model"))
refute Enum.any?(events, &(&1["type"] in ~w(request_admitted inference_dispatch_intent)))

admission = :sys.get_state(session).config.semantic_admission
pin = admission["pin"]
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

assert {:ok, snapshot} =
         Ipse.Extension.Collection.execute(
           collection,
           pin["namespace"],
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

assert {:ok, page} =
         Ipse.Extension.Collection.scan_visible(
           collection,
           pin["namespace"],
           %{
             "op" => "scan",
             "after" => nil,
             "generation" => snapshot["generation"],
             "limit" => 8
           },
           Ipse.Usage.id()
         )

assert length(page["records"]) == if(scenario == "save", do: 3, else: 0)

if scenario == "save" do
  assert Enum.sort(Enum.map(page["records"], & &1["value"]["category"])) ==
           ~w(current ordinary preference)

  for row <- page["records"] do
    assert String.starts_with?(row["key"], "note.")
    [proof] = row["value"]["evidence"]["sources"]
    assert proof["origin"] == "native_operator_assertion"
    assert proof["kind"] == "input.assertion." <> row["value"]["category"]
    assert proof["quote"] == row["value"]["text"]
  end

  # An actual protected command cannot promote the ordinary review to current.
  assert {:ok, sources} =
           Ipse.Session.sources(session, "source.list", %{"limit" => 32, "cursor" => nil})

  source = Enum.find(sources["sources"], &(&1["kind"] == "input.assertion.ordinary"))
  assert source

  # Re-reading an existing literal crosses the actual protected read path.
  ordinary_args = %{
    "text" => "Synthetic ordinary statement",
    "category" => "ordinary",
    "reason" => "synthetic repeated capture",
    "event_at_ms" => nil,
    "source" => %{"handle" => source["read_handle"], "quote" => "Synthetic ordinary statement"}
  }

  assert :ok =
           Ipse.Session.invoke_export(session, :command, "ext__knowledge__capture", ordinary_args)

  assert_receive {:ipse, ^session, {:done, :ok}}, 15_000
  assert {:ok, repeated_events} = Ipse.Journal.load(dir, id)

  assert Enum.any?(repeated_events, fn event ->
           get_in(event, ["outcome", "value", "record", "value", "text"]) == ordinary_args["text"]
         end)

  args = %{
    "text" => "Synthetic ordinary statement",
    "category" => "current",
    "reason" => "synthetic category substitution",
    "event_at_ms" => nil,
    "source" => %{"handle" => source["read_handle"], "quote" => "Synthetic ordinary statement"}
  }

  assert :ok = Ipse.Session.invoke_export(session, :command, "ext__knowledge__capture", args)
  assert_receive {:ipse, ^session, {:done, :ok}}, 15_000

  assert {:ok, later} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  assert {:ok, rows} =
           Ipse.Extension.Collection.scan_visible(
             collection,
             pin["namespace"],
             %{"op" => "scan", "after" => nil, "generation" => later["generation"], "limit" => 8},
             Ipse.Usage.id()
           )

  assert Enum.count(rows["records"], &String.starts_with?(&1["key"], "note.")) == 3
  assert [pending] = Enum.filter(rows["records"], &String.starts_with?(&1["key"], "pending."))
  assert pending["value"]["assigned_category"] == "current"
  assert pending["value"]["state"] == "pending"

  # A raw value edit cannot inherit the original signed managed publication.
  ordinary = Enum.find(rows["records"], &(&1["value"]["category"] == "ordinary"))
  altered = Map.put(ordinary["value"], "text", "Unreviewed hostile content")

  assert {:ok, _} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{
               "op" => "commit",
               "expected_generation" => later["generation"],
               "advance_floor" => true,
               "changes" => [
                 %{
                   "key" => ordinary["key"],
                   "expected_revision" => ordinary["revision"],
                   "value" => altered
                 }
               ]
             },
             Ipse.Usage.id()
           )

  assert :ok =
           Ipse.Session.invoke_export(session, :command, "ext__knowledge__capture", ordinary_args)

  assert_receive {:ipse, ^session, {:done, :ok}}, 15_000
  assert {:ok, refused_events} = Ipse.Journal.load(dir, id)

  assert Enum.any?(
           refused_events,
           &(get_in(&1, ["outcome", "value", "code"]) == "collection_source_refused")
         )

  refute Enum.any?(
           refused_events,
           &(get_in(&1, ["outcome", "value", "record", "value", "text"]) == altered["text"])
         )
end

source_config = :sys.get_state(session).config
assert :ok = Ipse.Session.close_confirmed(session)
assert {:ok, before_resume} = Ipse.Journal.load(dir, id)

if scenario == "save" do
  proofs = Enum.flat_map(page["records"], & &1["value"]["evidence"]["sources"])
  context = %{config: source_config, history_dir: dir, session_id: Ipse.Usage.id()}
  checked = fn c, p, fun -> Ipse.Session.StoredSources.with_verified(c, %{}, p, fun) end

  assert :retained =
           checked.(context, proofs, fn verified ->
             assert Enum.map(verified, & &1["proof"]) == proofs
             assert {:error, _} = Ipse.Runner.lock(Path.join(dir, id <> ".lock"))
             :retained
           end)

  deny = fn _ -> flunk("unavailable source reached the consumer") end
  [first | rest] = proofs

  assert {:error, :collection_source_refused} =
           checked.(context, [Map.put(first, "version_id", Ipse.Usage.id()) | rest], deny)

  assert {:error, :collection_source_refused} =
           checked.(
             put_in(
               context,
               [:config, :semantic_admission, "pin", "project_id"],
               Ipse.JSON.sha256("different project")
             ),
             proofs,
             deny
           )

  assert {:ok, lock} = Ipse.Runner.lock(Path.join(dir, id <> ".lock"))
  assert {:error, :collection_source_refused} = checked.(context, proofs, deny)
  assert :ok = Ipse.Runner.unlock(lock)

  copy = Path.join(home, "copied-sessions")
  File.mkdir!(copy)
  File.chmod!(copy, 0o700)

  for suffix <- ~w(.jsonl .lock),
      do: File.cp!(Path.join(dir, id <> suffix), Path.join(copy, id <> suffix))

  assert {:error, :collection_source_refused} =
           checked.(%{context | history_dir: copy}, proofs, deny)

  journal = Path.join(dir, id <> ".jsonl")
  original = File.read!(journal)
  File.write!(journal, "{\"torn\":", [:append])
  assert {:error, :collection_source_refused} = checked.(context, proofs, deny)
  assert File.read!(journal) == original <> "{\"torn\":"
  File.write!(journal, original)
  assert :restored = checked.(context, proofs, fn _ -> :restored end)

  assert {:error, :collection_source_refused} =
           checked.(context, proofs, fn _ ->
             raise "synthetic consumer failure"
           end)

  assert :released_after_failure = checked.(context, proofs, fn _ -> :released_after_failure end)

  # Authenticate a real reviewed note from an inactive source Session under the
  # actual domain key and current Consent, then refuse a root change in between.
  preference = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))

  recipe =
    source_config.semantic_admission["policy"]["settings"]["recipes"]
    |> Map.values()
    |> Enum.find(&(&1["kind"] == "literal_source"))

  read_intent = %{
    "namespace" => pin["namespace"],
    "effect_binding" => %{"pin" => pin},
    "request" => %{"request" => %{"op" => "get", "key" => preference["key"]}}
  }

  read_context = Map.put(context, :cwd, cwd)
  binding = source_config.semantic_admission["binding"]

  protect = fn domain, fun ->
    consent = fn cap, catalog ->
      Ipse.Extension.Consent.with_policy(
        Ipse.Extension.SemanticAdmission.control_root(home),
        pin["project_id"],
        pin["epoch"],
        pin["policy_sha256"],
        System.system_time(:millisecond),
        fn _ -> fun.(cap, catalog) end
      )
    end

    if domain do
      Ipse.Extension.ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        consent
      )
    else
      Ipse.Extension.ProjectIdentity.with_binding(home, cwd, binding, fn _ ->
        consent.(nil, nil)
      end)
    end
  end

  assert {:ok, %{"record" => ^preference}} =
           Ipse.Extension.ManagedRead.execute(read_context, read_intent, [recipe], protect)

  changed_protect = fn domain, fun ->
    if domain do
      assert {:ok, current} =
               Ipse.Extension.Collection.execute(
                 collection,
                 pin["namespace"],
                 %{"op" => "snapshot"},
                 Ipse.Usage.id()
               )

      assert {:ok, _} =
               Ipse.Extension.Collection.execute(
                 collection,
                 pin["namespace"],
                 %{
                   "op" => "commit",
                   "expected_generation" => current["generation"],
                   "advance_floor" => false,
                   "changes" => [
                     %{
                       "key" => "synthetic.unrelated",
                       "expected_revision" => 0,
                       "value" => %{"value" => "changed"}
                     }
                   ]
                 },
                 Ipse.Usage.id()
               )
    end

    protect.(domain, fun)
  end

  assert {:error, :collection_source_refused} =
           Ipse.Extension.ManagedRead.execute(
             read_context,
             read_intent,
             [recipe],
             changed_protect
           )

  assert {:ok, %{"record" => ^preference}} =
           Ipse.Extension.ManagedRead.execute(read_context, read_intent, [recipe], protect)

  # A fresh real consuming Session obtains its own pin; the source remains the
  # original inactive Session. This is current-use authority, not journal replay.
  assert {:ok, consumer} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
  consumer_state = :sys.get_state(consumer)
  consumer_pin = consumer_state.config.semantic_admission["pin"]

  consumer_context = %{
    config: consumer_state.config,
    cwd: cwd,
    history_dir: dir,
    session_id: consumer_state.id,
    owner: consumer,
    job_ref: make_ref()
  }

  consumer_intent = put_in(read_intent, ["effect_binding", "pin"], consumer_pin)

  consumer_protect = fn domain, fun ->
    callback = fn cap, catalog ->
      Ipse.Extension.Consent.with_policy(
        Ipse.Extension.SemanticAdmission.control_root(home),
        consumer_pin["project_id"],
        consumer_pin["epoch"],
        consumer_pin["policy_sha256"],
        System.system_time(:millisecond),
        fn _ -> fun.(cap, catalog) end
      )
    end

    if domain do
      Ipse.Extension.ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: consumer_pin["namespace"], format: "managed-metadata-v3"},
        callback
      )
    else
      Ipse.Extension.ProjectIdentity.with_binding(home, cwd, binding, fn _ ->
        callback.(nil, nil)
      end)
    end
  end

  assert {:ok, {_, [dependency]}} =
           Ipse.Extension.ManagedRead.execute(
             consumer_context,
             consumer_intent,
             [recipe],
             consumer_protect,
             fn value, dependencies -> {:ok, {value, dependencies}} end
           )

  assert {:ok, :used} =
           Ipse.Session.ManagedUse.with_dependencies(consumer_context, [dependency], fn [current] ->
             assert Ipse.Session.ManagedReference.current?(
                      dependency,
                      current,
                      System.system_time(:millisecond)
                    )

             assert {:error, _} = Ipse.Runner.lock(Path.join(dir, id <> ".lock"))
             {:ok, :used}
           end)

  assert {:ok, observed} =
           Ipse.Extension.Collection.ObservedRead.read(collection, consumer_pin["namespace"], %{
             "op" => "snapshot"
           })

  assert {:ok, root_dependency} =
           Ipse.Extension.Collection.ObservedRead.root_dependency(
             %{"op" => "snapshot"},
             observed,
             consumer_pin
           )

  assert {:ok, :root_used} =
           Ipse.Session.ManagedUse.with_dependencies(consumer_context, [root_dependency], fn _ ->
             {:ok, :root_used}
           end)

  assert {:ok, _} =
           Ipse.Extension.Collection.execute(
             collection,
             consumer_pin["namespace"],
             %{
               "op" => "commit",
               "expected_generation" => observed["value"]["generation"],
               "advance_floor" => false,
               "changes" => [
                 %{
                   "key" => "synthetic.use",
                   "expected_revision" => 0,
                   "value" => %{"value" => "changed"}
                 }
               ]
             },
             Ipse.Usage.id()
           )

  assert {:error, :managed_dependency_unavailable} =
           Ipse.Session.ManagedUse.with_dependencies(
             consumer_context,
             [root_dependency],
             fn _ -> flunk("stale selection reached use") end
           )

  assert {:ok, refreshed} =
           Ipse.Session.ManagedUse.with_dependencies(consumer_context, [dependency], fn [current] ->
             assert current["collection"]["generation"] > dependency["collection"]["generation"]
             {:ok, current}
           end)

  assert [%{"status" => "unavailable", "current" => nil}] =
           Ipse.Session.ManagedUse.verdicts(consumer_context, [root_dependency])

  # Historical preflight preserves precise verdicts while checking the original
  # journal once for several observations of the same unchanged literal.
  journal_bytes = File.stat!(Path.join(dir, id <> ".jsonl")).size

  bounded_context =
    put_in(consumer_context, [:config, :journal], %{
      "max_bytes" => journal_bytes + 64,
      "max_record_bytes" => journal_bytes + 64
    })

  assert {:ok, mixed_dependencies} =
           Ipse.Session.ManagedReference.union([[dependency, refreshed, root_dependency]])

  verdicts = Ipse.Session.ManagedUse.verdicts(bounded_context, mixed_dependencies)
  assert Enum.count(verdicts, &(&1["status"] == "eligible")) == 2
  assert Enum.count(verdicts, &(&1["status"] == "unavailable")) == 1

  assert Enum.find(verdicts, &(&1["dependency_sha256"] == Ipse.JSON.digest([root_dependency])))[
           "status"
         ] == "unavailable"

  assert :ok = Ipse.Session.close_confirmed(consumer)

  # Even a callback result is withheld if the retained source changes during use.
  assert {:error, :collection_source_refused} =
           checked.(context, proofs, fn _ ->
             File.write!(journal, "{\"torn\":", [:append])
             :must_not_escape
           end)

  File.write!(journal, original)
end

assert {:ok, resumed} =
         DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

assert :ok = Ipse.Session.close_confirmed(resumed)
assert {:ok, ^before_resume} = Ipse.Journal.load(dir, id)
refute File.exists?(Path.join(root, "unexpected-model"))

if String.starts_with?(requested_scenario, "save_forget") do
  key = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))["key"]
  arguments = ["--cwd", cwd, "--config", config_path, "--no-project-config"]
  assert Ipse.CLI.run(["knowledge", "disable"] ++ arguments) == 0

  if requested_scenario == "save_forget" do
    assert Ipse.CLI.run(["knowledge", "forget", key] ++ arguments) == 0

    assert {:ok, %{"record" => nil}} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "get", "key" => key},
               Ipse.Usage.id()
             )

    assert {:ok, ^before_resume} = Ipse.Journal.load(dir, id)

    management_directory = Path.join(home, "knowledge-management")
    [entry] = Ipse.Journal.list(management_directory)
    management_id = entry["id"]
    assert {:ok, management_events} = Ipse.Journal.load(management_directory, management_id)
    [intent] = Enum.filter(management_events, &(&1["type"] == "managed_lifecycle_intent"))
    [result] = Enum.filter(management_events, &(&1["type"] == "managed_lifecycle_result"))
    assert result["status"] == "settled"
    assert result["operation_id"] == intent["operation_id"]
    assert result["result"]["receipt"]["publication"]["normalization"]["record_key"] == key
    assert intent["facts"]["context"]["management_epoch"] > pin["epoch"]

    assert {:ok, control} =
             Ipse.Extension.Consent.existing_snapshot(
               Ipse.Extension.SemanticAdmission.control_root(home),
               pin["project_id"]
             )

    assert control["policy"] == nil
    assert control["operations"][intent["operation_id"]]["status"] == "settled"
    assert control["operations"][intent["operation_id"]]["actual"]["model_calls"] == 0
    assert control["operations"][intent["operation_id"]]["actual"]["input_bytes"] < 65_536

    management_before = File.read!(Path.join(management_directory, management_id <> ".jsonl"))
    assert Ipse.CLI.run(["knowledge", "operation", management_id] ++ arguments) == 0

    assert File.read!(Path.join(management_directory, management_id <> ".jsonl")) ==
             management_before

    assert {:ok, ^control} =
             Ipse.Extension.Consent.existing_snapshot(
               Ipse.Extension.SemanticAdmission.control_root(home),
               pin["project_id"]
             )

    assert {:ok, before_repeat} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert Ipse.CLI.run(["knowledge", "forget", key] ++ arguments) == 1

    assert {:ok, ^before_repeat} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    refute File.exists?(Path.join(root, "unexpected-model"))
  else
    if requested_scenario == "save_forget_stale" do
      Task.start(fn ->
        deadline = System.monotonic_time(:millisecond) + 15_000

        wait = fn wait ->
          unless File.exists?(Path.join(root, "forget-review-ready")) do
            assert System.monotonic_time(:millisecond) < deadline
            Process.sleep(5)
            wait.(wait)
          end
        end

        wait.(wait)
        control = Ipse.Extension.SemanticAdmission.control_root(home)
        {:ok, current} = Ipse.Extension.Consent.existing_snapshot(control, pin["project_id"])

        assert {:ok, _} =
                 Ipse.Extension.Consent.revoke(control, pin["project_id"], current["epoch"])

        File.write!(Path.join(root, "forget-control-changed"), "done")
      end)
    end

    assert Ipse.CLI.run(["knowledge", "forget", key] ++ arguments) == 1

    assert {:ok, %{"record" => record}} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "get", "key" => key},
               Ipse.Usage.id()
             )

    assert record["key"] == key
    assert {:ok, ^before_resume} = Ipse.Journal.load(dir, id)
    directory = Path.join(home, "knowledge-management")
    [entry] = Ipse.Journal.list(directory)
    assert {:ok, management} = Ipse.Journal.load(directory, entry["id"])
    [result] = Enum.filter(management, &(&1["type"] == "managed_lifecycle_result"))
    assert result["status"] == "refused"
    intents = Enum.filter(management, &(&1["type"] == "managed_lifecycle_intent"))
    assert length(intents) == if(requested_scenario == "save_forget_stale", do: 1, else: 0)
    before = File.read!(Path.join(directory, entry["id"] <> ".jsonl"))
    assert Ipse.CLI.run(["knowledge", "operation", entry["id"]] ++ arguments) == 0
    assert File.read!(Path.join(directory, entry["id"] <> ".jsonl")) == before
    refute File.exists?(Path.join(root, "unexpected-model"))
  end
end

if requested_scenario == "save_retention" do
  key = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))["key"]
  arguments = ["--cwd", cwd, "--config", config_path, "--no-project-config"]
  assert Ipse.CLI.run(["knowledge", "disable"] ++ arguments) == 0
  {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)

  recipe =
    admission["policy"]["settings"]["recipes"]
    |> Map.values()
    |> Enum.find(&(&1["kind"] == "literal_source"))

  read = fn ->
    Ipse.Extension.ProjectIdentity.with_existing_domain_auth(
      home,
      cwd,
      binding,
      %{namespace: pin["namespace"], format: "managed-metadata-v3"},
      fn cap, catalog ->
        Ipse.Extension.Collection.ObservedRead.managed_record(
          collection,
          pin["namespace"],
          %{"op" => "get_record", "key" => key},
          cap,
          catalog,
          recipe
        )
      end
    )
  end

  assert {:ok, original} = read.()
  value = original["observation"]["value"]["record"]["value"]
  first = original["metadata"]["first_admitted_ms"]
  directory = Path.join(home, "knowledge-management")

  for {policy_args, kind} <- [
        {["--policy", "pin"], "pin"},
        {["--policy", "automatic"], "ordinary"},
        {["--policy", "duration", "--days", "7"], "duration"}
      ] do
    previous = Ipse.Journal.list(directory) |> Enum.map(& &1["id"])
    assert Ipse.CLI.run(["knowledge", "retention", key] ++ policy_args ++ arguments) == 0
    [entry] = Enum.reject(Ipse.Journal.list(directory), &(&1["id"] in previous))
    assert {:ok, history} = Ipse.Journal.load(directory, entry["id"])
    [intent] = Enum.filter(history, &(&1["type"] == "managed_lifecycle_intent"))
    [result] = Enum.filter(history, &(&1["type"] == "managed_lifecycle_result"))
    assert result["status"] == "settled"
    assert intent["facts"]["kind"] == "managed_literal_retention"
    assert intent["facts"]["policy"]["kind"] == kind
    assert {:ok, current} = read.()
    assert current["metadata"]["first_admitted_ms"] == first
    assert current["observation"]["value"]["record"]["value"] == value
    assert current["metadata"]["choice"]["policy"]["kind"] == kind

    if kind == "pin",
      do: assert(is_nil(current["metadata"]["valid_until_ms"])),
      else: assert(current["metadata"]["valid_until_ms"] > System.system_time(:millisecond))

    assert Ipse.CLI.run(["knowledge", "operation", entry["id"]] ++ arguments) == 0
  end

  assert Ipse.CLI.run(["knowledge", "retention", key, "--policy", "session"] ++ arguments) == 0

  assert {:ok, %{"record" => nil}} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "get", "key" => key},
             Ipse.Usage.id()
           )

  assert {:ok, ^before_resume} = Ipse.Journal.load(dir, id)
  refute File.exists?(Path.join(root, "unexpected-model"))
end

if requested_scenario == "save_expire" do
  key = Enum.find(page["records"], &(&1["value"]["category"] == "preference"))["key"]
  arguments = ["--cwd", cwd, "--config", config_path, "--no-project-config"]
  assert Ipse.CLI.run(["knowledge", "disable"] ++ arguments) == 0

  assert {:ok, choice} =
           Ipse.CLI.Knowledge.Management.retain(config, cwd, key, %{
             "kind" => "duration",
             "duration_ms" => 2000
           })

  deadline = choice["receipt"]["publication"]["normalization"]["valid_until_ms"]
  assert deadline > System.system_time(:millisecond)
  Process.sleep(max(deadline - System.system_time(:millisecond) + 5, 0))
  directory = Path.join(home, "knowledge-management")
  previous = Ipse.Journal.list(directory) |> Enum.map(& &1["id"])
  assert Ipse.CLI.run(["knowledge", "expire", key] ++ arguments) == 0
  [entry] = Enum.reject(Ipse.Journal.list(directory), &(&1["id"] in previous))
  assert {:ok, history} = Ipse.Journal.load(directory, entry["id"])
  [intent] = Enum.filter(history, &(&1["type"] == "managed_lifecycle_intent"))
  [result] = Enum.filter(history, &(&1["type"] == "managed_lifecycle_result"))
  assert intent["facts"]["kind"] == "managed_literal_expiry"
  assert intent["facts"]["expired_at_ms"] == deadline
  assert result["status"] == "settled"
  assert result["result"]["receipt"]["publication"]["normalization"]["eligibility"] == "expired"

  assert {:ok, %{"record" => nil}} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "get", "key" => key},
             Ipse.Usage.id()
           )

  assert Ipse.CLI.run(["knowledge", "operation", entry["id"]] ++ arguments) == 0
  assert {:ok, ^before_resume} = Ipse.Journal.load(dir, id)

  assert {:ok, control} =
           Ipse.Extension.Consent.existing_snapshot(
             Ipse.Extension.SemanticAdmission.control_root(home),
             pin["project_id"]
           )

  operation = control["operations"][intent["operation_id"]]
  assert operation["status"] == "settled"
  assert operation["actual"]["model_calls"] == 0
  assert operation["actual"]["download_bytes"] == 0
  assert operation["actual"]["cost_nanos"] == 0
  refute File.exists?(Path.join(root, "unexpected-model"))
end

IO.puts("NATIVE_ASSERTION_#{String.upcase(requested_scenario)}_PASSED")
