Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule IpseKnowledge.RecallCaptureSessionTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  alias Ipse.{JSON, Journal, Session}

  alias Ipse.Extension.{
    Catalog,
    Consent,
    ProjectIdentity,
    Registry,
    SemanticAdmission,
    SemanticConsent,
    SemanticRoutes
  }

  import Ipse.Test.ResumeAssertions

  for boundary <- [:current, :source_lost, :revoked] do
    @tag :recalled_literal_capture
    @tag recalled_capture_boundary: boundary
    @tag timeout: 120_000
    test "shipped recall/capture preserves source authority at #{boundary}" do
      recall_capture(unquote(boundary))
    end
  end

  defp recall_capture(boundary) do
    root = Path.join(System.tmp_dir!(), "ipse-recall-capture-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    seed_native_literal(root)
    seed = root |> Path.join("literal-ab-seed.json") |> File.read!() |> Jason.decode!()
    IO.puts("RECALL_CAPTURE_ROOT=" <> root)
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    history = Path.join(home, "sessions")
    text = "Synthetic new café observation"
    {base, listener, server} = capture_server(text)

    on_exit(fn ->
      monitor = Process.monitor(server.pid)
      Process.exit(server.pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 5000
      :gen_tcp.close(listener)
    end)

    activation = seed["policy"]["settings"]["activation"]

    data = %{
      "extension_trust" => [
        %{
          "artifact" => activation["artifact"],
          "capabilities" => activation["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ],
      "extensions" => [
        Map.take(activation, ~w(instance artifact options order lifetime))
        |> Map.put("enabled", true)
      ]
    }

    assert {:ok, selected} =
             Ipse.Extension.Config.resolve(
               [%{scope: "operator", path: "/fixture/recall-capture.json", data: data}],
               []
             )

    assert {:ok, entries} = Registry.prepare(selected, home)

    config = %{
      provider: :ollama,
      model: "synthetic",
      home: home,
      base_url: base,
      approval: :deny,
      approval_origin: :default_headless,
      headless: true,
      operator_questions: false,
      extensions: entries,
      timeout_ms: 5000,
      max_output_tokens: 64,
      inference_services: %{"capture" => %{"version" => 1, "origins" => [base]}}
    }

    # Trusted test setup explicitly selects the local fixture route and the
    # shipped artifact. Its read jobs run normally; capture is main-tool selected.
    assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
    control = SemanticAdmission.control_root(home)
    assert {:ok, snapshot} = Consent.existing_snapshot(control, binding["project_id"])
    assert {:ok, catalog} = Catalog.snapshot(config)
    jobs = for d <- catalog["entries"], d["stage"] == "event.job", do: JSON.digest([d])

    policy =
      snapshot["policy"]
      |> put_in(["settings", "activation"], nil)
      |> update_in(["settings", "effects"], fn effects ->
        Enum.reject(
          effects,
          &(&1["outer_sha256"] in jobs and &1["class"] == "collection.publish")
        )
      end)

    assert {:ok, selectors} = SemanticRoutes.selectors(policy["settings"]["routes"])
    assert {:ok, routes} = SemanticRoutes.resolve(config, selectors)
    policy = put_in(policy, ["settings", "routes"], routes)

    selection =
      policy["settings"]
      |> Map.drop(~w(instance identity_sha256))
      |> Map.merge(Map.take(policy, ~w(limits period_ms expires_at_ms headless)))

    assert {:ok, policy} = SemanticConsent.prepare(binding, hd(entries).identity, selection)

    assert {:ok, _} =
             Consent.replace(
               control,
               binding["project_id"],
               snapshot["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selections} = Ipse.Config.Semantics.selection(policy)
    config = Map.put(config, :semantic_selections, selections)

    assert {:ok, session} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: cwd, state_dir: history, subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)
    assert :sys.get_state(session).config.semantic_admission["status"] == "active"
    id = Session.info(session).id
    source = seed["source_journal"]
    held = source <> ".held-before-capture-result"

    on_exit(fn ->
      send(session, :release_capture_input)
      if File.exists?(held), do: File.rename!(held, source)
    end)

    if boundary != :current, do: hold_capture_input(session)
    assert :ok = Session.prompt(session, text)

    if boundary != :current do
      assert_receive {:capture_input_waiting, ^session, spec}, 30_000
      assert_literal_dependency(spec.dependencies, seed)
      assert spec.action["outcome"]["status"] == "ok"

      case boundary do
        :source_lost ->
          File.rename!(source, held)

        :revoked ->
          assert {:ok, current} = Consent.existing_snapshot(control, binding["project_id"])
          assert {:ok, _} = Consent.revoke(control, binding["project_id"], current["epoch"])
      end

      send(session, :release_capture_input)
    end

    assert_receive {:ipse, ^session, {:done, status}}, 30_000
    assert {:ok, events} = Journal.load(history, id)

    requests =
      if boundary == :current do
        assert status == :ok,
               "shipped recall/capture did not complete: #{inspect(Enum.map(events, & &1["type"]))}"

        Task.await(server, 5000)
      else
        assert status == :error
        assert_receive {:recall_capture_request, first}, 1000
        assert_receive {:recall_capture_request, second}, 1000
        refute_receive {:recall_capture_request, _}, 100
        Task.shutdown(server, :brutal_kill)
        [first, second]
      end

    first = hd(requests)["messages"] |> Jason.encode!()
    assert first =~ "note_parts_v1"
    assert first =~ seed["text"]

    assert Enum.any?(events, fn event ->
             event["type"] == "managed_read_observed" and
               Enum.any?(
                 event["dependencies"],
                 &(&1["version"] == 4 and
                     get_in(&1, ["subject", "key"]) == seed["key"])
               )
           end)

    [call] =
      for event <- events,
          event["type"] == "message",
          get_in(event, ["message", "role"]) == "assistant",
          call <- event["message"]["tool_calls"] || [],
          get_in(call, ["function", "name"]) == "source_list",
          do: call

    [lookup] =
      for event <- events,
          event["type"] == "message",
          message = event["message"],
          message["role"] == "tool",
          message["tool_call_id"] == call["id"],
          do: message

    assert get_in(lookup, ["ipse_tool_outcome", "status"]) == "result_recorded",
           "source lookup after genuine recall was refused: #{inspect(lookup["ipse_tool_outcome"])}"

    publications =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "collection.managed")
      )

    assert [publication] = publications
    assert publication["outcome"]["status"] == "ok"
    assert publication["approval"] == "saved_consent"
    assert publication["outcome"]["value"]["normalization"]["eligibility"] == "never_current"
    [change] = publication["request"]["request"]["changes"]
    assert change["value"]["text"] == text and change["value"]["state"] == "pending"
    collection = SemanticAdmission.collection_root(home)
    namespace = publication["namespace"]

    assert {:ok, stored} =
             Ipse.Extension.Collection.execute(
               collection,
               namespace,
               %{"op" => "get", "key" => change["key"]},
               Ipse.Usage.id()
             )

    assert stored["record"]["value"] == change["value"]

    assert {:ok, root_after} =
             Ipse.Extension.Collection.execute(
               collection,
               namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert root_after["generation"] ==
             publication["request"]["request"]["expected_generation"] + 1

    assert stored["record"]["revision"] == root_after["generation"]
    [proof] = change["value"]["evidence"]["sources"]
    assert proof["session_id"] == id and proof["origin"] == "unattended_input"
    assert proof["session_id"] != seed["session_id"]

    assert JSON.sha256(File.read!(if(boundary == :source_lost, do: held, else: source))) ==
             seed["source_sha256"]

    assert {:ok, settled} = Consent.existing_snapshot(control, binding["project_id"])
    operation = settled["operations"][publication["operation_id"]]
    assert operation["status"] == "settled"
    assert operation["actual"]["operations"] == 1

    assert {:ok, saved} = Session.Saved.restore(events, id)

    if boundary == :current do
      refute saved.managed_lineage.unavailable
      assert saved.worker_input_unknown == []
      assert length(requests) == 3
      wire = Jason.encode!(List.last(requests)["messages"])
      assert wire =~ seed["text"]
      assert wire =~ "Host historical metadata notice"
      assert_retained_literal(saved, publication, seed)
      assert_transition_tampering_rejected(events, id)
    else
      assert saved.managed_lineage.unavailable
      [input] = saved.worker_input_unknown

      intent =
        Enum.find(events, &(&1["type"] == "worker_input_intent" and &1["input_id"] == input))

      assert intent["invocation_id"] == publication["parent_invocation_id"]
      assert intent["payload_sha256"] == JSON.digest([Ipse.Extension.Actions.resume(publication)])

      assert Enum.any?(
               events,
               &(&1["type"] == "worker_input_result" and
                   &1["input_id"] == input and &1["status"] == "unknown")
             )

      assert length(requests) == 2
    end

    assert :ok = Session.close_confirmed(session)
    path = Path.join(history, id <> ".jsonl")
    before = File.read!(path)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: cwd, state_dir: history, subscriber: self(), id: id}
             )

    assert Session.info(resumed).phase == :idle
    assert :sys.get_state(resumed).messages == saved.messages
    assert_idle_resume_journal(path, before, id)
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, after_resume} = Consent.existing_snapshot(control, binding["project_id"])
    assert after_resume["operations"][publication["operation_id"]] == operation

    assert {:ok, ^root_after} =
             Ipse.Extension.Collection.execute(
               collection,
               namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    if File.exists?(held), do: File.rename!(held, source)
    assert JSON.sha256(File.read!(source)) == seed["source_sha256"]
  end

  defp assert_literal_dependency(dependencies, seed) do
    assert Enum.any?(
             dependencies,
             &(&1["version"] == 4 and
                 get_in(&1, ["subject", "key"]) == seed["key"])
           )
  end

  defp assert_retained_literal(saved, publication, seed) do
    lineage = saved.managed_lineage

    assert Enum.any?(lineage.root_observations, fn {_id, classification} ->
             classification == "metadata_only"
           end)

    ids = Map.fetch!(lineage.outputs, publication["parent_invocation_id"])
    dependencies = Enum.map(ids, &Map.fetch!(lineage.dictionary, &1))
    assert_literal_dependency(dependencies, seed)

    for dependency <- dependencies, dependency["version"] == 4 do
      refute Map.has_key?(lineage.root_transitions, JSON.digest([dependency]))
    end

    assert {:ok, current} = Session.ManagedLineage.dependencies(lineage, saved.messages)
    assert_literal_dependency(current, seed)
  end

  defp assert_transition_tampering_rejected(events, id) do
    assert Enum.any?(events, &(&1["type"] == "worker_input_root_transition"))

    for field <- ["own_action_sha256", "operation_id"] do
      altered =
        Enum.map(events, fn event ->
          if event["type"] == "worker_input_root_transition",
            do:
              put_in(
                event,
                ["evidence", field],
                String.duplicate("0", byte_size(event["evidence"][field]))
              ),
            else: event
        end)

      assert {:error, _} = Session.Saved.restore(altered, id)
    end

    missing = Enum.reject(events, &(&1["type"] == "worker_input_root_transition"))
    assert {:error, _} = Session.Saved.restore(missing, id)
  end

  defp hold_capture_input(session) do
    owner = self()

    hook = fn
      :released, _, _ ->
        :released

      %{action: action} = spec,
      {:in, {_, _, {:worker_input_prepare, _, _, _, "host.actions", payload}}},
      _ ->
        if payload === Ipse.Extension.Actions.resume(action) do
          send(owner, {:capture_input_waiting, self(), spec})
          receive do: (:release_capture_input -> :released)
        else
          spec
        end

      value, {:out, _, _, state}, _ ->
        action = if state.invocation, do: List.last(state.invocation.results)

        if get_in(action || %{}, ["request", "op"]) == "collection.managed" and
             get_in(action || %{}, ["outcome", "status"]) == "ok" do
          {:ok, dependencies} = Session.ManagedToolUse.invocation_dependencies(state)
          %{dependencies: dependencies, action: action}
        else
          value
        end

      value, _, _ ->
        value
    end

    assert :ok = :sys.install(session, {hook, nil})
  end

  defp seed_native_literal(root) do
    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.expand("test/support/operator_pty.rs"),
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        driver,
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("test/support/managed_literal_ab_seed.exs"), root, "seed"],
        cd: root,
        stderr_to_stdout: true
      )

    File.write!(Path.join(root, "native-seed.log"), output)
    assert status == 0, output
  end

  defp capture_server(text) do
    assert {:ok, listener} =
             :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    assert {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    task = Task.async(fn -> serve_capture(listener, text, [], owner) end)
    Process.unlink(task.pid)
    {"http://127.0.0.1:#{port}", listener, task}
  end

  defp serve_capture(listener, text, requests, owner) do
    assert {:ok, socket} = :gen_tcp.accept(listener, 30_000)

    request =
      try do
        {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
        request = Jason.decode!(bytes)
        send(owner, {:recall_capture_request, request})
        message = capture_message(request, text, length(requests))

        body =
          Jason.encode!(%{
            "model" => "synthetic",
            "message" => message,
            "done" => true,
            "prompt_eval_count" => 1,
            "eval_count" => 1
          }) <> "\n"

        assert :ok =
                 :gen_tcp.send(
                   socket,
                   "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                     body
                 )

        {request, message}
      after
        :gen_tcp.close(socket)
      end

    {request, message} = request
    requests = requests ++ [request]

    if message["tool_calls"] do
      assert length(requests) < 3
      serve_capture(listener, text, requests, owner)
    else
      :gen_tcp.close(listener)
      requests
    end
  end

  defp capture_message(_, _, 0), do: tool("source_list", %{"limit" => 32})

  defp capture_message(request, text, 1) do
    result = request["messages"] |> Enum.reverse() |> Enum.find(&(&1["role"] == "tool"))

    with value when is_binary(value) <- result["content"],
         {:ok, %{"sources" => sources}} <- Jason.decode(value),
         source when is_map(source) <-
           Enum.find(Enum.reverse(sources), &(&1["kind"] == "input.original")) do
      tool("ext__knowledge__capture", %{
        "text" => text,
        "category" => "ordinary",
        "reason" => "selected new observation",
        "event_at_ms" => nil,
        "source" => %{"handle" => source["read_handle"], "quote" => text}
      })
    else
      _ -> final_message()
    end
  end

  defp capture_message(_, _, 2), do: final_message()
  defp final_message, do: %{"role" => "assistant", "content" => "Synthetic capture finished."}

  defp tool(name, args),
    do: %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [
        %{"function" => %{"name" => name, "arguments" => args}}
      ]
    }
end
