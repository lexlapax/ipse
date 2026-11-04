import ExUnit.Assertions
alias Ipse.{Session, JSON}
alias Ipse.Extension.{Artifact, Config, Registry, State}
alias Ipse.Development.Fixtures.Knowledge, as: F
Code.require_file("native_pipe_scope.exs", __DIR__)
[root, artifact_path] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "project")
File.mkdir_p!(cwd)
File.mkdir_p!(home)
File.chmod!(home, 0o700)
System.put_env("HOME", home)
System.put_env("IPSE_HOME", home)
{:ok, _} = Application.ensure_all_started(:ipse)
assert :sys.get_state(Ipse.Session.Input).entries == %{}
false = Code.ensure_loaded?(IpseKnowledge.Research)

defmodule FetchTransferNoModel do
  def complete(_, _, _, _), do: raise("fetch transfer unexpectedly requested inference")
end

defmodule FetchTransferJourney do
  import ExUnit.Assertions
  alias Ipse.{Session, Journal}

  def command(pid, name, args, decision \\ :allow) do
    assert :ok = Session.invoke_export(pid, :command, name, args)
    await(pid, args, decision, %{mcp: 0, state: 0}, System.monotonic_time(:millisecond) + 20_000)
  end

  defp await(pid, args, decision, count, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:mcp.call", proposed}} ->
        request = proposed["request"]
        assert request["op"] == "mcp.call" and request["binding"] == "fetch-web"

        assert request["arguments"] == %{
                 "version" => 1,
                 "contract" => "fetch-v1",
                 "uri" => args["uri"]
               }

        assert proposed["effect_binding"]["manifest"]["tool_id"] == "mcp__knowledge_cas__fetch"
        assert :ok = Session.approve(pid, ref, decision != :deny_fetch)
        await(pid, args, decision, %{count | mcp: count.mcp + 1}, deadline)

      {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}} ->
        assert :ok = Ipse.Extension.State.validate(proposed["request"])
        assert proposed["request"]["scope"] == "project"
        assert :ok = Session.approve(pid, ref, decision != :deny_state)
        await(pid, args, decision, %{count | state: count.state + 1}, deadline)

      {:ipse, ^pid, {:approval, _, _, _}} ->
        flunk("unexpected approval kind")

      {:ipse, ^pid, {:done, :ok}} ->
        assert %{"value" => value} = Session.info(pid).extension_result
        {value, count}

      {:ipse, ^pid, {:done, _}} ->
        flunk("fetch command did not finish normally")

      {:write_effect_completed_before_record, ^pid, caller, event} when decision == :interrupt ->
        assert is_pid(caller) and event["request"]["op"] == "state.put" and
                 event["outcome"]["status"] == "ok"

        {:ok, events} = Journal.load(Process.get(:fetch_history), Process.get(:fetch_fault_id))

        assert Enum.any?(
                 events,
                 &(&1["type"] == "extension_action_intent" and
                     &1["operation_id"] == event["operation_id"])
               )

        refute Enum.any?(
                 events,
                 &(&1["type"] == "extension_action_result" and
                     &1["operation_id"] == event["operation_id"])
               )

        monitor = Process.monitor(pid)
        worker_monitor = Process.monitor(caller)
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
        assert_receive {:DOWN, ^worker_monitor, :process, ^caller, _}, 5000
        assert :ok = Ipse.Test.NativePipeScope.await_native_exit(Process.get(:fetch_native_pid))
        {{:interrupted, event["operation_id"]}, count}

      _ ->
        await(pid, args, decision, count, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("bounded fetch command did not settle")
    end
  end

  def events(options, id) do
    assert {:ok, events} = Journal.load(options[:state_dir], id)
    assert {:ok, saved} = Session.Saved.restore(events, id)

    refute Enum.any?(
             events,
             &(&1["type"] in ~w(request_intent request_admitted inference_dispatch_intent))
           )

    {events, saved}
  end

  def idle(options, id, before) do
    kinds =
      ~w(input_received extension_invocation_intent extension_action_intent worker_input_intent inference_dispatch_intent mcp_action_intent)

    assert {:ok, idle} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(options, :id, id)}
             )

    assert Session.info(idle).phase == :idle
    assert :ok = Session.close_confirmed(idle)
    {after_events, _} = events(options, id)

    assert Enum.filter(before, &(&1["type"] in kinds)) ==
             Enum.filter(after_events, &(&1["type"] in kinds))
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

{:ok, backend} = F.start_backend("research-notes")
body = "Résumé 雪: Ada owns release after audit."

page = %{
  "text" => body,
  "observed_uri" => "fixture:observed-release",
  "media_type" => "text/plain",
  "observed_at_ms" => 10
}

fault_page = %{page | "text" => "Fault capture. " <> body}

:ok =
  F.configure_web_backend(backend, %{
    "searches" => %{},
    "pages" => %{
      "fixture:release" => page,
      "fixture:alias" => page,
      "fixture:fault" => fault_page
    }
  })

runtime_root = Application.app_dir(:ipse)

artifacts =
  for {name, path} <- [
        {"research", artifact_path},
        {"corpus", Path.join(runtime_root, "priv/extension-bundles/corpus-state-documents")}
      ],
      into: %{} do
    assert {:ok, artifact} = Artifact.import(path, Path.join(home, "extensions/artifacts"))
    {name, artifact}
  end

research =
  Jason.decode!(
    File.read!(
      Path.expand("../../extensions/knowledge/options/research-state-fetched.json", __DIR__)
    )
  )

corpus = Map.put(research, "fetch", %{})

source = %{
  scope: "operator",
  path: Path.join(home, "fixture.json"),
  data: %{
    "extensions" =>
      for(
        {name, artifact} <- artifacts,
        do: %{
          "instance" => name,
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => if(name == "research", do: research, else: corpus),
          "order" => 0,
          "lifetime" => "session"
        }
      ),
    "extension_trust" =>
      for(
        {name, artifact} <- artifacts,
        do: %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false,
          "state_bindings" => [
            %{
              "version" => 1,
              "instance" => name,
              "id" => "research-shared",
              "scopes" => ["project"]
            }
          ],
          "mcp_bindings" =>
            if(name == "research",
              do: [
                %{
                  "instance" => name,
                  "alias" => "fetch-web",
                  "tool" => "mcp__knowledge_cas__fetch"
                }
              ],
              else: []
            )
        }
      )
  }
}

{:ok, selected} = Config.resolve([source], [])
{:ok, entries} = Registry.prepare(selected, home)

config_for = fn mode ->
  path = Path.join(root, "mcp-" <> mode <> ".json")

  File.write!(
    path,
    Jason.encode!(%{"servers" => [F.web_stdio_config("research-notes", mode, backend.port)]})
  )

  {:ok, [server]} = Ipse.MCP.Config.load(path)

  %{
    provider: :demo,
    model: "unused",
    provider_module: FetchTransferNoModel,
    home: home,
    operator_home: nil,
    extensions: entries,
    mcp_servers: [server],
    approval: :ask,
    approval_origin: :interactive,
    headless: false,
    compact: false
  }
end

options_for = fn mode ->
  [
    config: config_for.(mode),
    cwd: cwd,
    state_dir: Path.join(home, "sessions"),
    owner: self(),
    subscriber: self()
  ]
end

start = fn options ->
  assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, options})
  {pid, Session.info(pid).id}
end

args = %{
  "store" => "notes",
  "fetch" => "web",
  "uri" => "fixture:release",
  "title" => "Release",
  "quote" => "Ada owns release after audit.",
  "timeout_ms" => 3000
}

normal_options = options_for.("normal")
{pid, id} = start.(normal_options)
identity = Enum.find(entries, &(&1.identity["instance"] == "research")).identity
assert {:ok, namespace} = State.namespace(identity, "project", cwd, id)
state_root = Path.join(home, "extension-state-v1")

try do
  before = FetchTransferJourney.state(state_root, namespace)

  {denied, %{mcp: 1, state: 0}} =
    FetchTransferJourney.command(pid, "ext__research__fetch_retain", args, :deny_fetch)

  assert denied["status"] == "refused" and
           FetchTransferJourney.state(state_root, namespace) == before

  {denied, %{mcp: 1, state: 1}} =
    FetchTransferJourney.command(pid, "ext__research__fetch_retain", args, :deny_state)

  assert denied["status"] == "refused" and
           FetchTransferJourney.state(state_root, namespace) == before

  {stored, count} = FetchTransferJourney.command(pid, "ext__research__fetch_retain", args)
  assert stored["status"] == "ok" and count.mcp == 1 and count.state > 0
  assert stored["coverage"]["native_receipt"] == false
  target = "research.provided:" <> JSON.sha256(body)
  assert stored["coverage"]["source_id"] == target

  query_args = %{
    "store" => "notes",
    "retrieval" => "words",
    "rerank" => nil,
    "query" => "release",
    "top_k" => 3,
    "as_of_ms" => 20
  }

  {query, %{mcp: 0, state: 0}} =
    FetchTransferJourney.command(pid, "ext__corpus__query", query_args)

  assert [evidence] = query["evidence"]
  citation = evidence["citation"]
  assert citation["quote"] == body and citation["content_sha256"] == JSON.sha256(body)
  assert citation["start_byte"] == 0 and citation["end_byte"] == byte_size(body)
  assert citation["origin"]["kind"] == "fetch" and citation["origin"]["historical"] == false
  receipt = citation["origin"]["receipt"]
  assert receipt == stored["coverage"]["derivation"]

  assert receipt["quote"] == args["quote"] and receipt["start_byte"] == byte_size("Résumé 雪: ") and
           receipt["end_byte"] == byte_size(body)

  {inspected, _} =
    FetchTransferJourney.command(pid, "ext__corpus__source", %{
      "store" => "notes",
      "action" => "inspect",
      "args" => %{"source_id" => target}
    })

  {forgotten, _} =
    FetchTransferJourney.command(pid, "ext__corpus__source", %{
      "store" => "notes",
      "action" => "forget",
      "args" => %{"source_id" => target, "expected_revision" => inspected["coverage"]["revision"]}
    })

  assert forgotten["status"] == "ok"
  {events, _} = FetchTransferJourney.events(normal_options, id)

  assert [actual_fetch] =
           Enum.filter(
             events,
             &(&1["type"] == "extension_action_result" and
                 &1["operation_id"] == receipt["descriptor"]["operation_id"])
           )

  assert actual_fetch["request"]["op"] == "mcp.call" and
           actual_fetch["request"]["arguments"]["uri"] == args["uri"]

  assert actual_fetch["outcome"]["status"] == "ok" and
           actual_fetch["outcome"]["value"] == receipt["descriptor"]

  assert :ok = Session.close_confirmed(pid)
  FetchTransferJourney.idle(normal_options, id, events)
  {fresh, fresh_id} = start.(normal_options)
  frozen = FetchTransferJourney.state(state_root, namespace)

  {refused, %{mcp: 1, state: 0}} =
    FetchTransferJourney.command(
      fresh,
      "ext__research__fetch_retain",
      args |> Map.put("uri", "fixture:alias") |> Map.put("quote", "Résumé 雪")
    )

  assert refused["status"] == "refused" and
           FetchTransferJourney.state(state_root, namespace) == frozen

  {missing, %{mcp: 1, state: 0}} =
    FetchTransferJourney.command(
      fresh,
      "ext__research__fetch_retain",
      Map.put(args, "uri", "fixture:missing")
    )

  assert missing["status"] == "refused" and
           FetchTransferJourney.state(state_root, namespace) == frozen

  {empty, _} = FetchTransferJourney.command(fresh, "ext__corpus__query", query_args)
  assert empty["evidence"] == []
  {events, _} = FetchTransferJourney.events(normal_options, fresh_id)
  assert :ok = Session.close_confirmed(fresh)
  FetchTransferJourney.idle(normal_options, fresh_id, events)

  for mode <-
        ~w(fetch_partial fetch_changed_body fetch_forged_hash fetch_forged_receipt fetch_wrong_uri fetch_refused) do
    options = options_for.(mode)
    {negative, negative_id} = start.(options)

    {refused, %{mcp: 1, state: 0}} =
      FetchTransferJourney.command(negative, "ext__research__fetch_retain", args)

    assert refused["status"] == "refused" and
             FetchTransferJourney.state(state_root, namespace) == frozen

    {events, _} = FetchTransferJourney.events(options, negative_id)

    refute Enum.any?(
             events,
             &(&1["type"] == "extension_action_intent" and
                 get_in(&1, ["request", "op"]) == "state.put")
           )

    assert :ok = Session.close_confirmed(negative)
    FetchTransferJourney.idle(options, negative_id, events)
  end

  {fault, fault_id} = start.(normal_options)
  {:os_pid, source_owner_pid} = Port.info(:sys.get_state(fault).lock, :os_pid)
  Process.put(:fetch_native_pid, source_owner_pid)
  Process.put(:fetch_history, normal_options[:state_dir])
  Process.put(:fetch_fault_id, fault_id)
  collector = self()

  hook = fn
    false, {:in, {:"$gen_call", {caller, _}, {:extension_action_commit, _, event}}}, _
    when is_map(event) ->
      if event["request"]["op"] == "state.put" and event["outcome"]["status"] == "ok" do
        send(collector, {:write_effect_completed_before_record, self(), caller, event})

        receive do
          :unreachable_fault_release -> :ok
        after
          5000 -> exit(:fault_witness_unconfirmed)
        end
      end

      false

    state, _, _ ->
      state
  end

  assert :ok = :sys.install(fault, {hook, false})

  {{:interrupted, operation}, counts} =
    FetchTransferJourney.command(
      fault,
      "ext__research__fetch_retain",
      Map.put(args, "uri", "fixture:fault"),
      :interrupt
    )

  assert counts.mcp == 1 and counts.state == 1
  {events, saved} = FetchTransferJourney.events(normal_options, fault_id)
  assert saved.extension_state.action["operation_id"] == operation

  refute Enum.any?(
           events,
           &(&1["type"] == "extension_action_result" and &1["operation_id"] == operation)
         )

  FetchTransferJourney.idle(normal_options, fault_id, events)
  assert :ok = F.stop_backend(backend)
  assert :sys.get_state(Ipse.Session.Input).entries == %{}

  IO.puts(
    "fetched_state_journey=pass actual_mcp_fetch=true ordinary_approvals=true exact_quote_and_derivation=true same_body_forget_aliases=true malformed_fetch_state_intents=0 interrupted_write_unknown=true saved_and_idle_no_replay=true model_calls=0 tty_reads=0"
  )
after
  if Process.alive?(pid), do: Session.close_confirmed(pid)
  if Process.alive?(backend.pid), do: F.stop_backend(backend)
end
