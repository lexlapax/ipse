import ExUnit.Assertions
alias Ipse.{JSON, Journal, Session}
alias Ipse.Extension.{Artifact, Catalog, State}
[research_artifact, options_file, root, "save_managed_approval_research"] = System.argv()
seed = Jason.decode!(File.read!(Path.join(root, "literal-ab-seed.json")))
home = Path.join(root, "home")
cwd = Path.join(root, "project")
history = Path.join(home, "sessions")
File.mkdir_p!(Path.join(root, "operator-home"))
File.chmod!(Path.join(root, "operator-home"), 0o700)
System.put_env("HOME", Path.join(root, "operator-home"))
System.put_env("IPSE_HOME", home)
{:ok, _} = Application.ensure_all_started(:ipse)
false = Code.ensure_loaded?(IpseKnowledge.Research)

Code.require_file("research_managed_wire.exs", __DIR__)

defmodule ResearchMixedJourney do
  import ExUnit.Assertions
  alias Ipse.{Journal, Session}

  def await(pid, allow \\ true),
    do: settle(pid, allow, 0, System.monotonic_time(:millisecond) + 30_000)

  defp settle(pid, allow, count, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}} ->
        assert :ok = Ipse.Extension.State.validate(proposed["request"])
        assert proposed["request"]["scope"] == "project"
        assert is_binary(proposed["artifact_sha256"])
        assert :ok = Session.approve(pid, ref, allow)
        settle(pid, allow, count + 1, deadline)

      {:ipse, ^pid, {:approval, _, _, _}} ->
        flunk("unexpected non-State approval")

      {:ipse, ^pid, {:done, status}} ->
        {status, count}

      {:ipse, ^pid, {:error, _}} ->
        settle(pid, allow, count, deadline)

      _ ->
        settle(pid, allow, count, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("bounded mixed command did not settle")
    end
  end

  def request(root, mode, index), do: ResearchMixedWire.request(root, mode, index)

  def native_query(pid, root, cwd) do
    caller = self()
    ref = make_ref()

    assert {:ok, watcher} =
             Task.start_link(fn ->
               wait(
                 fn -> File.regular?(Path.join(root, "managed-approval-input-ready")) end,
                 System.monotonic_time(:millisecond) + 15_000
               )

               state = :sys.get_state(pid)

               assert state.phase == :managed_approval and
                        state.share_barrier.phase == :review_input

               assert get_in(state.managed_approval.input, ["call", "function", "name"]) ==
                        "ext__corpus__query"

               assert state.managed_approval.input["arguments"] == ResearchMixedWire.query_args()

               File.write!(Path.join(root, "managed-approval-control-checked"), "checked", [
                 :exclusive
               ])

               wait(
                 fn -> :sys.get_state(pid).phase == :idle end,
                 System.monotonic_time(:millisecond) + 15_000
               )

               File.write!(Path.join(root, "managed-approval-exit-ready"), "ready", [:exclusive])

               receive do
                 {:collect_mixed_watcher, ^caller, ^ref} ->
                   send(caller, {:mixed_watcher_done, ref})
               after
                 5000 -> raise "mixed watcher collection was not acknowledged"
               end
             end)

    IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

    assert Ipse.CLI.Terminal.interact(
             pid,
             Process.monitor(pid),
             true,
             "Query the retained release passage and preserve its exact attribution.",
             cwd
           ) == 0

    send(watcher, {:collect_mixed_watcher, caller, ref})
    assert_receive {:mixed_watcher_done, ^ref}, 5000
    :ok
  end

  defp wait(fun, deadline) do
    unless fun.() do
      assert System.monotonic_time(:millisecond) < deadline,
             "mixed native approval boundary not reached"

      Process.sleep(5)
      wait(fun, deadline)
    end
  end

  def events(dir, id) do
    assert {:ok, events} = Journal.load(dir, id)
    assert {:ok, saved} = Session.Saved.restore(events, id)
    {events, saved}
  end

  def input_dependencies(events, session_id, parent) do
    index = Enum.find_index(events, &(&1 == parent))
    assert is_integer(index)
    assert {:ok, prefix} = Session.Saved.restore(Enum.take(events, index + 1), session_id)
    entry = Map.fetch!(prefix.managed_lineage.invocations, parent["invocation_id"])
    assert entry.parent == parent

    assert {:ok, dependencies} =
             Session.ManagedLineage.invocation_dependencies(
               prefix.managed_lineage,
               parent["invocation_id"]
             )

    frames =
      Enum.filter(
        events,
        &(&1["type"] == "worker_input_intent" and &1["invocation_id"] == parent["invocation_id"] and
            &1["stage"] == parent["descriptor"]["stage"])
      )

    if dependencies != [], do: assert(length(frames) == 1)

    for frame <- frames do
      assert frame["parent_sha256"] == Ipse.JSON.digest([parent])
      assert frame["dependencies_sha256"] == Ipse.JSON.digest(dependencies)

      assert [delivery] =
               Enum.filter(
                 events,
                 &(&1["type"] == "worker_input_result" and &1["input_id"] == frame["input_id"])
               )

      assert delivery["intent_sha256"] == Ipse.JSON.digest([frame])
      assert delivery["status"] == "delivered"
    end

    dependencies
  end

  def output_dependencies(events, session_id, parent) do
    assert [raw] =
             Enum.filter(
               events,
               &(&1["type"] == "extension_invocation_result" and
                   &1["invocation_id"] == parent["invocation_id"])
             )

    index = Enum.find_index(events, &(&1 == raw))
    assert {:ok, prefix} = Session.Saved.restore(Enum.take(events, index), session_id)
    assert Map.has_key?(prefix.managed_lineage.invocations, parent["invocation_id"])

    assert {:ok, dependencies} =
             Session.ManagedLineage.invocation_dependencies(
               prefix.managed_lineage,
               parent["invocation_id"]
             )

    if dependencies != [] do
      assert [release] =
               Enum.filter(
                 events,
                 &(&1["type"] == "managed_output_release_intent" and
                     &1["parent_invocation_id"] == parent["invocation_id"])
               )

      assert Session.ManagedOutput.valid_intent?(
               release,
               session_id,
               parent,
               raw["actions_sha256"],
               dependencies
             )

      assert [admission] =
               Enum.filter(
                 events,
                 &(&1["type"] == "managed_output_release_result" and
                     &1["release_id"] == release["release_id"])
               )

      assert admission["decision"] == "current"
      assert Session.ManagedOutput.valid_admission?(admission, release, raw, [])

      assert [cleanup] =
               Enum.filter(
                 events,
                 &(&1["type"] == "managed_output_release_cleanup" and
                     &1["release_id"] == release["release_id"])
               )

      assert cleanup["status"] == "confirmed"
      assert Session.ManagedOutput.valid_cleanup?(cleanup, release, admission)
    end

    dependencies
  end

  def literal?(dependencies, seed) do
    Enum.any?(
      dependencies,
      &(&1["version"] == 4 and get_in(&1, ["subject", "key"]) == seed["key"])
    )
  end

  def idle(options, id, events) do
    types =
      ~w(input_received extension_invocation_intent extension_action_intent worker_input_intent inference_dispatch_intent)

    intents = Enum.filter(events, &(&1["type"] in types))

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(options, :id, id)}
             )

    assert Session.info(resumed).phase == :idle
    assert :ok = Session.close_confirmed(resumed)
    {after_events, _} = events(options[:state_dir], id)
    assert Enum.filter(after_events, &(&1["type"] in types)) == intents
  end

  def state(root, namespace) do
    assert {:ok, snapshot} =
             Ipse.Extension.State.execute(
               root,
               namespace,
               %{
                 "op" => "state.scan",
                 "scope" => "project",
                 "after" => nil,
                 "generation" => nil,
                 "limit" => 16
               },
               Ipse.Usage.id()
             )

    assert snapshot["next"] == nil
    snapshot
  end
end

artifacts =
  for {instance, path} <- [
        {"research", research_artifact},
        {"corpus", Application.app_dir(:ipse, "priv/extension-bundles/corpus-state-documents")}
      ],
      into: %{} do
    assert {:ok, artifact} = Artifact.import(path, Path.join(home, "extensions/artifacts"))
    {instance, artifact}
  end

research_options = Jason.decode!(File.read!(options_file))
corpus_options = research_options |> Map.put("search", %{}) |> Map.put("fetch", %{})

operator =
  Map.merge(Jason.decode!(File.read!(Path.join(root, "mixed-route.json"))), %{
    "extensions" =>
      for(
        {instance, artifact} <- artifacts,
        do: %{
          "instance" => instance,
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => if(instance == "research", do: research_options, else: corpus_options),
          "order" => 0,
          "lifetime" => "session"
        }
      ),
    "extension_trust" =>
      for(
        {instance, artifact} <- artifacts,
        do: %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false,
          "state_bindings" => [
            %{
              "version" => 1,
              "instance" => instance,
              "id" => "research-shared",
              "scopes" => ["project"]
            }
          ]
        }
      )
  })

config_path = Path.join(root, "mixed-operator.json")
File.write!(config_path, Jason.encode!(operator), [:exclusive, :sync])
File.chmod!(config_path, 0o600)

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

assert {:ok, effective} =
         Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

assert {:ok, config} = Ipse.Config.runtime(effective, client)

refute Map.has_key?(config, :provider_module)
assert config.provider == :ollama
assert config.base_url == get_in(operator, ["profiles", "mixed", "base_url"])
config = Map.put(config, :compact, false)

assert {:ok, _} = Catalog.snapshot(config)
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

assert {:ok, original_root} =
         Ipse.Extension.Collection.execute(
           collection,
           seed["namespace"],
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

provided = %{
  "source_id" => "external:explicit-user",
  "title" => "Release",
  "text" => "Résumé 雪: Ada owns release after audit.",
  "uri" => "provided:explicit-user",
  "observed_at_ms" => 10,
  "event_at_ms" => nil,
  "expires_at_ms" => nil
}

retain_args = %{
  "store" => "notes",
  "source" => provided,
  "quote" => "Ada owns release after audit."
}

query_args = %{
  "store" => "notes",
  "retrieval" => "words",
  "rerank" => nil,
  "query" => "release",
  "top_k" => 3,
  "as_of_ms" => 20
}

assert provided == ResearchMixedWire.provided()
assert retain_args == ResearchMixedWire.retain_args()
assert query_args == ResearchMixedWire.query_args()

script = root
options = [config: config, cwd: cwd, state_dir: history, subscriber: self()]
assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, options})
id = Session.info(pid).id
assert :sys.get_state(pid).config.semantic_admission["status"] == "active"
assert :ok = Session.prompt(pid, "Recall the recorded note before my explicit source transfer.")
assert {:ok, 0} = ResearchMixedJourney.await(pid)
{first, _} = ResearchMixedJourney.request(script, :positive, 0)
assert Jason.encode!(first) =~ seed["text"]
assert Jason.encode!(first) =~ "note_parts_v1"

# This is the public command route used by /ext, with the user's original
# literal arguments. No model tool invocation is relabelled as a command.
assert :ok = Session.invoke_export(pid, :command, "ext__research__retain", retain_args)
assert {:ok, approvals} = ResearchMixedJourney.await(pid)
assert approvals > 0
retained = Session.info(pid).extension_result["value"]
assert retained["status"] == "ok"
assert retained["coverage"]["source_id"] == "research.provided:" <> JSON.sha256(provided["text"])

assert :ok = ResearchMixedJourney.native_query(pid, root, cwd)
{second, _} = ResearchMixedJourney.request(script, :positive, 1)
{third, _} = ResearchMixedJourney.request(script, :positive, 2)
assert Jason.encode!(second) =~ seed["text"]
refute Jason.encode!(second) =~ provided["text"]
assert Jason.encode!(third) =~ seed["text"]
assert Jason.encode!(third) =~ provided["text"]
assert Enum.any?(third, &(&1["role"] == "assistant" and &1["content"] == "MIXED_INITIAL_READY"))

assert [message] =
         Enum.filter(third, &(&1["role"] == "tool" and &1["tool_name"] == "ext__corpus__query"))

result = Jason.decode!(message["content"])
assert [evidence] = result["evidence"]
citation = evidence["citation"]
assert citation["quote"] == provided["text"]
assert citation["content_sha256"] == JSON.sha256(provided["text"])
assert citation["quote_sha256"] == JSON.sha256(provided["text"])
assert citation["start_byte"] == 0 and citation["end_byte"] == byte_size(provided["text"])
origin = citation["origin"]
assert origin["kind"] == "provided" and origin["historical"] == false
assert origin["receipt"] == retained["coverage"]["derivation"]
assert origin["receipt"]["start_byte"] == byte_size("Résumé 雪: ")
assert origin["receipt"]["quote"] == retain_args["quote"]
assert origin["receipt"]["source_id"] == provided["source_id"]
assert origin["receipt"]["body_sha256"] == JSON.sha256(provided["text"])
assert ResearchMixedWire.count(root, :positive) == 3
{events, saved} = ResearchMixedJourney.events(history, id)

assert [command] =
         Enum.filter(
           events,
           &(&1["type"] == "extension_invocation_intent" and
               &1["descriptor"]["name"] == "ext__research__retain")
         )

assert command["descriptor"]["stage"] == "invoke.command" and
         command["payload"]["arguments"] == retain_args

assert [] == ResearchMixedJourney.input_dependencies(events, id, command)
assert [] == ResearchMixedJourney.output_dependencies(events, id, command)

assert [query] =
         Enum.filter(
           events,
           &(&1["type"] == "extension_invocation_intent" and
               &1["descriptor"]["name"] == "ext__corpus__query")
         )

assert query["descriptor"]["stage"] == "invoke.tool"
call_id = query["parent_call_id"]
assert is_binary(call_id)

assert Enum.any?(saved.messages, fn message ->
         Enum.any?(message["tool_calls"] || [], fn call ->
           call["id"] == call_id and get_in(call, ["function", "name"]) == "ext__corpus__query"
         end)
       end)

assert [internal_message] =
         Enum.filter(saved.messages, &(&1["role"] == "tool" and &1["tool_call_id"] == call_id))

assert internal_message["ipse_tool_outcome"]["status"] == "result_recorded"
assert Jason.decode!(internal_message["content"]) == result

deps = ResearchMixedJourney.input_dependencies(events, id, query)
assert ResearchMixedJourney.literal?(deps, seed)

assert ResearchMixedJourney.literal?(
         ResearchMixedJourney.output_dependencies(events, id, query),
         seed
       )

assert saved.managed_lineage.source_producers["outputs:" <> query["invocation_id"]] == true

assert Enum.any?(
         events,
         &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "state.put" and
             &1["outcome"]["status"] == "ok" and &1["approval"] == "approved")
       )

refute saved.managed_lineage.unavailable
assert :ok = Session.close_confirmed(pid)
ResearchMixedJourney.idle(options, id, events)
assert ResearchMixedWire.count(root, :positive) == 3

# A different body would need a new write. Saved notes and --yes cannot grant
# that unsupported managed-derived State mutation.
negative_args =
  retain_args
  |> put_in(["source", "source_id"], "external:model-tool")
  |> put_in(["source", "text"], "Different body: Bert owns release after review.")
  |> Map.put("quote", "Bert owns release after review.")

assert negative_args == ResearchMixedWire.negative_args()

negative_config = Map.merge(config, %{approval: :allow, approval_origin: :yes})
negative_options = Keyword.put(options, :config, negative_config)
assert {:ok, negative} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, negative_options})
negative_id = Session.info(negative).id
assert :sys.get_state(negative).config.semantic_admission["status"] == "active"

entry =
  Enum.find(:sys.get_state(negative).config.extensions, &(&1.identity["instance"] == "research"))

assert {:ok, namespace} = State.namespace(entry.identity, "project", cwd, negative_id)
state_root = Path.join(home, "extension-state-v1")
before_state = ResearchMixedJourney.state(state_root, namespace)
assert :ok = Session.prompt(negative, "Try the model-selected supplied-source retention tool.")
{negative_status, negative_approvals} = ResearchMixedJourney.await(negative)
assert negative_status == :error
assert negative_approvals == 0
{negative_messages, _} = ResearchMixedJourney.request(script, :negative, 0)
assert Jason.encode!(negative_messages) =~ seed["text"]
{negative_events, negative_saved} = ResearchMixedJourney.events(history, negative_id)
assert negative_saved.worker_input_unknown == []

assert [tool] =
         Enum.filter(
           negative_events,
           &(&1["type"] == "extension_invocation_intent" and
               &1["descriptor"]["name"] == "ext__research__retain")
         )

assert tool["descriptor"]["stage"] == "invoke.tool" and
         tool["payload"]["arguments"] == negative_args

tool_deps = ResearchMixedJourney.input_dependencies(negative_events, negative_id, tool)
assert ResearchMixedJourney.literal?(tool_deps, seed)

refute Enum.any?(
         negative_events,
         &(&1["type"] in ~w(extension_action_intent extension_action_result) and
             get_in(&1, ["request", "op"]) in ~w(state.put state.delete))
       )

assert ResearchMixedJourney.state(state_root, namespace) == before_state
assert ResearchMixedWire.count(root, :negative) in [1, 2]
assert :ok = Session.close_confirmed(negative)
ResearchMixedJourney.idle(negative_options, negative_id, negative_events)
assert {:ok, original_events} = Journal.load(history, seed["session_id"])
assert {:ok, _} = Session.Saved.restore(original_events, seed["session_id"])
assert JSON.sha256(File.read!(seed["source_journal"])) == seed["source_sha256"]

assert {:ok, ^original_root} =
         Ipse.Extension.Collection.execute(
           collection,
           seed["namespace"],
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

IO.puts(
  "mixed_h1_coexistence=pass native_seed=1 explicit_command_approved=true positive_main_requests=3 corpus_tool_quote_attributed=true managed_tool_state_mutations=0 state_snapshot_unchanged=true original_bytes_unchanged=true saved_and_idle_no_replay=true negative_status=#{negative_status} negative_worker_input_unknown=#{length(negative_saved.worker_input_unknown)}"
)
