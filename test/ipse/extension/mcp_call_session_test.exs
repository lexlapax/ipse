Code.require_file("../../../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../../../dev/verification/runtime.exs", __DIR__)
Ipse.Development.Verification.Runtime.load_fixture!(:mcp)

defmodule Ipse.Extension.MCPCallSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.{Actions, Config, Registry, Artifact}
  alias IpseMCPExample.Fixture

  defmodule NoModel do
    def complete(config, _, _, _) do
      send(config.test_pid, :unexpected_mcp_model_call)
      {:error, "An explicit command must not call the conversation provider"}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-mcp-action-build-" <> Ipse.Usage.id())
    File.mkdir_p!(root)

    artifacts =
      Map.new([{:mixed, ""}, {:legacy, "host.actions.mixed"}, {:ungranted, "host.mcp"}], fn {name,
                                                                                             omit} ->
        output = Path.join(root, Atom.to_string(name))

        {log, status} =
          System.cmd(
            System.find_executable("elixir"),
            [
              Path.expand("../../../dev/build-artifact.exs", __DIR__),
              "mcp-actions",
              "--sdk",
              Application.app_dir(:ipse, "ebin"),
              "--output",
              output,
              "--omit",
              omit
            ],
            stderr_to_stdout: true
          )

        assert status == 0, log
        {name, output}
      end)

    on_exit(fn -> File.rm_rf!(root) end)
    %{artifacts: artifacts}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-extension-mcp-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    home = Path.join(root, "home")
    dir = Path.join(root, "sessions")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: home, dir: dir}
  end

  test "MCP sources that cannot fit a journal record refuse before approval or dispatch", ctx do
    selected = server(ctx, :http, :normal)

    cfg =
      config(ctx, selected)
      |> Map.merge(%{approval: :ask, journal: %{"max_record_bytes" => 65_536}})

    pid = start(ctx, cfg)
    invoke(pid)
    done(pid, :error)
    assert Fixture.calls(ctx.root) == 0
    assert Fixture.discoveries(ctx.root) == 0
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}
    ev = events(ctx, pid)

    refute Enum.any?(
             ev,
             &(&1["type"] in ~w(extension_action_intent extension_effect_result journal_limit_reached))
           )

    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert Fixture.calls(ctx.root) == 0
  end

  test "MCP full response contract fits its exact existing source-record ceiling", ctx do
    selected = server(ctx, :http, :normal)

    cfg =
      config(ctx, selected)
      |> Map.put(:journal, %{"max_record_bytes" => 262_144})

    pid = start(ctx, cfg)
    invoke(pid)
    done(pid)
    assert Fixture.calls(ctx.root) == 1
    ev = events(ctx, pid)
    assert Enum.any?(ev, &(&1["type"] == "extension_effect_result"))
    refute Enum.any?(ev, &(&1["type"] == "journal_limit_reached"))
  end

  defp server(ctx, :stdio, mode) do
    parsed_server(ctx, Fixture.stdio_config(ctx.root, Atom.to_string(mode)))
  end

  defp server(ctx, :http, mode) do
    {_fixture, server} = http_server(ctx, mode)
    server
  end

  defp http_server(ctx, mode) do
    {fixture, entry} = Fixture.http(ctx.root, self(), mode)
    on_exit(fn -> Fixture.stop(fixture) end)
    {fixture, parsed_server(ctx, entry)}
  end

  defp parsed_server(ctx, entry) do
    path = Path.join(ctx.root, "mcp.json")
    File.write!(path, Jason.encode!(%{"servers" => [entry]}))
    assert {:ok, [server]} = Ipse.MCP.Config.load(path)
    server
  end

  defp config(ctx, server, variant \\ :mixed) do
    assert {:ok, installed} =
             Artifact.import(ctx.artifacts[variant], Path.join(ctx.home, "extensions/artifacts"))

    capabilities =
      Jason.decode!(File.read!(Path.join(ctx.artifacts[variant], "extension.json")))[
        "capabilities"
      ]

    trust = %{
      "artifact" => installed.digest,
      "capabilities" => capabilities,
      "allow_project" => false,
      "allow_children" => true
    }

    trust =
      if "host.mcp" in capabilities,
        do:
          Map.put(trust, "mcp_bindings", [
            %{"instance" => "reader", "alias" => "documents", "tool" => selected_id(server)}
          ]),
        else: trust

    data = %{
      "extensions" => [
        %{
          "instance" => "reader",
          "artifact" => installed.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 1,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [trust]
    }

    assert {:ok, selections} =
             Config.resolve(
               [%{scope: "operator", path: Path.join(ctx.root, "operator.json"), data: data}],
               []
             )

    assert {:ok, entries} = Registry.prepare(selections, ctx.home)

    %{
      provider: :ollama,
      model: "unused-explicit-command",
      provider_module: NoModel,
      home: ctx.home,
      operator_home: nil,
      approval: :allow,
      extensions: entries,
      mcp_servers: [server],
      test_pid: self(),
      compact: false
    }
  end

  defp selected_id(server) do
    cond do
      server.tools != [] -> Ipse.MCP.Config.tool_id(server.id, hd(server.tools))
      server.resources != [] -> Ipse.MCP.Config.resource_id(server.id, hd(server.resources))
      true -> Ipse.MCP.Config.prompt_id(server.id, hd(server.prompts))
    end
  end

  defp start(ctx, config, id \\ nil) do
    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp request do
    %{
      "op" => "mcp.call",
      "version" => 1,
      "binding" => "documents",
      "arguments" => %{"text" => "Public synthetic request"},
      "timeout_ms" => 5000
    }
  end

  defp invoke(pid, extra \\ %{}) do
    assert :ok =
             Session.invoke_export(
               pid,
               :command,
               "ext__reader__read",
               Map.merge(%{"request" => request(), "read" => true}, extra)
             )
  end

  defp done(pid, status \\ :ok), do: assert_receive({:ipse, ^pid, {:done, ^status}}, 20_000)

  defp events(ctx, pid) do
    assert {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, _} = Session.restore_context(events)
    events
  end

  defp action_results(events), do: Enum.filter(events, &(&1["type"] == "extension_action_result"))
  defp digest(value), do: Ipse.JSON.digest([value])

  for transport <- [:stdio, :http] do
    test "#{transport}: exact approval, durable source before descriptor and complete UTF8 windows without inference",
         ctx do
      selected = server(ctx, unquote(transport), :normal)
      cfg = config(ctx, selected) |> Map.put(:approval, :ask)
      pid = start(ctx, cfg)
      invoke(pid)
      assert_receive {:ipse, ^pid, {:approval, ref, "extension:mcp.call", proposed}}, 10_000
      assert proposed["request"] == request()
      binding = proposed["effect_binding"]
      assert binding["kind"] == "mcp" and binding["version"] === 1
      assert binding["alias"] == "documents"
      assert binding["schema"] == Fixture.schema()
      assert binding["manifest"]["tool_id"] == "mcp__fixture__fetch"
      assert binding["server"]["fingerprint"] == selected.fingerprint
      assert Fixture.discoveries(ctx.root) == 1
      assert Fixture.calls(ctx.root) == 0
      assert :ok = Session.approve(pid, ref, true)
      done(pid)
      refute_receive :unexpected_mcp_model_call
      assert Fixture.calls(ctx.root) == 1
      ev = events(ctx, pid)

      intent_index =
        Enum.find_index(
          ev,
          &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "mcp.call")
        )

      source_index = Enum.find_index(ev, &(&1["type"] == "extension_effect_result"))

      result_index =
        Enum.find_index(
          ev,
          &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "mcp.call")
        )

      assert intent_index < source_index and source_index < result_index
      source = Enum.at(ev, source_index)
      call = Enum.at(ev, result_index)
      assert source["data"] == %{"text" => Fixture.text()}
      assert source["operation_id"] == call["operation_id"]
      assert call["version"] == 2 and call["namespace"] == nil
      assert call["outcome"]["value"]["source_sha256"] == source["source_sha256"]
      assert call["outcome"]["value"]["byte_count"] == byte_size(Fixture.text())
      windows = Enum.filter(action_results(ev), &(&1["request"]["op"] == "effect.result.read"))
      assert length(windows) > 2
      assert Enum.all?(windows, &(&1["namespace"] == Session.info(pid).id and &1["version"] == 2))
      texts = Enum.map(windows, & &1["outcome"]["value"]["text"])
      assert Enum.all?(texts, &(String.valid?(&1) and byte_size(&1) <= 4096))
      assert Enum.join(texts) == Fixture.text()
      assert List.last(windows)["outcome"]["value"]["complete"] == true
      value = Session.info(pid).extension_result["value"]
      assert value["bytes"] == byte_size(Fixture.text())
      assert value["sha256"] == Base.encode16(:crypto.hash(:sha256, Fixture.text()), case: :lower)
      id = Session.info(pid).id
      assert :ok = Session.close_confirmed(pid)
      path = Path.join(ctx.dir, id <> ".jsonl")
      before = File.read!(path)
      discoveries = Fixture.discoveries(ctx.root)
      resumed = start(ctx, cfg, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(path) == before
      assert Fixture.calls(ctx.root) == 1 and Fixture.discoveries(ctx.root) == discoveries
      refute_receive :unexpected_mcp_model_call
    end
  end

  for transport <- [:stdio, :http], kind <- [:resource, :prompt] do
    test "#{transport}: selected #{kind} dispatch returns a complete source through the extension",
         ctx do
      kind = unquote(kind)

      {fixture, entry} =
        if unquote(transport == :http),
          do: Fixture.http(ctx.root, self()),
          else: {nil, Fixture.stdio_config(ctx.root)}

      if fixture, do: on_exit(fn -> Fixture.stop(fixture) end)
      entry = Map.put(entry, "tools", [])

      entry =
        if unquote(kind == :resource),
          do: Map.put(entry, "resources", ["fixture://document"]),
          else: Map.put(entry, "prompts", ["summary"])

      selected = parsed_server(ctx, entry)
      cfg = config(ctx, selected) |> Map.put(:approval, :ask)
      pid = start(ctx, cfg)

      arguments =
        if unquote(kind == :resource), do: %{}, else: %{"text" => "Public synthetic request"}

      invoke(pid, %{"request" => Map.put(request(), "arguments", arguments)})
      assert_receive {:ipse, ^pid, {:approval, ref, "extension:mcp.call", proposed}}, 10_000
      assert proposed["effect_binding"]["manifest"]["kind"] == Atom.to_string(kind)
      assert proposed["effect_binding"]["manifest"]["tool_id"] == selected_id(selected)
      method = if unquote(kind == :resource), do: "resources/read", else: "prompts/get"
      refute Enum.any?(Fixture.records(ctx.root), &(&1["method"] == method))
      assert :ok = Session.approve(pid, ref, true)
      done(pid)
      ev = events(ctx, pid)
      source = Enum.find(ev, &(&1["type"] == "extension_effect_result"))
      assert source["data"]["text"] =~ Fixture.text()
      if unquote(kind == :prompt), do: assert(source["data"]["text"] =~ "[user]")

      windows =
        for result <- action_results(ev),
            result["request"]["op"] == "effect.result.read",
            do: result["outcome"]["value"]["text"]

      assert Enum.join(windows) == source["data"]["text"]
      assert Enum.count(Fixture.records(ctx.root), &(&1["method"] == method)) == 1
      refute_receive :unexpected_mcp_model_call
    end
  end

  test "user denial may follow discovery but dispatch and source persistence remain zero", ctx do
    cfg = config(ctx, server(ctx, :http, :normal)) |> Map.put(:approval, :ask)
    pid = start(ctx, cfg)
    invoke(pid)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:mcp.call", _}}, 5000
    assert Fixture.discoveries(ctx.root) == 1 and Fixture.calls(ctx.root) == 0
    assert :ok = Session.approve(pid, ref, false)
    done(pid)
    ev = events(ctx, pid)
    assert [%{"outcome" => %{"status" => "denied", "value" => %{}}}] = action_results(ev)
    refute Enum.any?(ev, &(&1["type"] == "extension_effect_result"))
    assert Fixture.calls(ctx.root) == 0
    refute_receive :unexpected_mcp_model_call
  end

  test "children, ungranted capability and missing operator aliases refuse before discovery",
       ctx do
    selected = server(ctx, :http, :normal)

    variants = [
      {config(ctx, selected), %{"request" => Map.put(request(), "binding", "unselected")}},
      {config(ctx, selected, :ungranted), %{}},
      {Map.put(config(ctx, selected), :parallel_child, true), %{}},
      {Map.put(config(ctx, selected), :delegation_origin, %{
         "parent_session_id" => Ipse.Usage.id(),
         "parent_request_id" => Ipse.Usage.id(),
         "call_id" => "synthetic-child"
       }), %{}},
      {Map.put(config(ctx, selected), :mcp_servers, []), %{}}
    ]

    for {cfg, arguments} <- variants do
      pid = start(ctx, cfg)
      invoke(pid, arguments)
      done(pid, :error)
      assert Fixture.records(ctx.root) == []
      assert action_results(events(ctx, pid)) == []
      assert :ok = Session.close_confirmed(pid)
    end
  end

  test "selected server schema rejects invalid arguments before approval or dispatch", ctx do
    cfg = config(ctx, server(ctx, :http, :normal)) |> Map.put(:approval, :ask)
    pid = start(ctx, cfg)
    invoke(pid, %{"request" => Map.put(request(), "arguments", %{"text" => 42})})
    done(pid, :error)
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}
    assert Fixture.discoveries(ctx.root) == 1
    assert Fixture.calls(ctx.root) == 0
    assert action_results(events(ctx, pid)) == []
  end

  test "an explicit answer after inert question recovery reads the same invocation source", ctx do
    cfg = config(ctx, server(ctx, :http, :normal))
    pid = start(ctx, cfg)
    invoke(pid, %{"question" => true})
    assert_receive {:ipse, ^pid, {:question, question_id, _}}, 5000
    assert Session.info(pid).phase == :question
    ev = events(ctx, pid)
    source = Enum.find(ev, &(&1["type"] == "extension_effect_result"))
    assert source != nil
    refute Enum.any?(action_results(ev), &(&1["request"]["op"] == "effect.result.read"))
    id = Session.info(pid).id
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    transport_before = Fixture.records(ctx.root)
    path = Path.join(ctx.dir, id <> ".jsonl")
    journal_before = File.read!(path)
    resumed = start(ctx, cfg, id)
    assert_receive {:ipse, ^resumed, {:question, ^question_id, _}}, 5000
    assert Session.info(resumed).phase == :question
    assert File.read!(path) == journal_before
    assert Fixture.records(ctx.root) == transport_before
    assert :ok = Session.answer(resumed, question_id, %{"continue" => "read"})
    done(resumed)
    ev = events(ctx, resumed)
    windows = Enum.filter(action_results(ev), &(&1["request"]["op"] == "effect.result.read"))
    assert Enum.all?(windows, &(&1["parent_invocation_id"] == source["parent_invocation_id"]))
    assert Enum.map_join(windows, & &1["outcome"]["value"]["text"]) == Fixture.text()
    assert Fixture.calls(ctx.root) == 1
    refute_receive :unexpected_mcp_model_call
  end

  test "descriptor drift after approval discovery never dispatches", ctx do
    cfg = config(ctx, server(ctx, :http, :normal)) |> Map.put(:approval, :ask)
    pid = start(ctx, cfg)
    invoke(pid)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:mcp.call", _}}, 5000
    File.write!(Path.join(ctx.root, "change-descriptor"), "changed")
    assert :ok = Session.approve(pid, ref, true)
    done(pid)

    assert [%{"outcome" => %{"status" => "failed", "value" => %{"code" => "mcp_refused"}}}] =
             action_results(events(ctx, pid))

    assert Fixture.calls(ctx.root) == 0 and Fixture.discoveries(ctx.root) == 2
  end

  test "reader authority cannot name an earlier invocation or alter its source hash or UTF8 offset",
       ctx do
    cfg = config(ctx, server(ctx, :http, :normal))
    pid = start(ctx, cfg)
    invoke(pid)
    done(pid)
    [call | _] = action_results(events(ctx, pid))
    descriptor = call["outcome"]["value"]

    old = %{
      "op" => "effect.result.read",
      "version" => 1,
      "operation_id" => descriptor["operation_id"],
      "source_sha256" => descriptor["source_sha256"],
      "offset" => 0,
      "limit" => 4096
    }

    invoke(pid, %{"request" => old, "read" => false})
    done(pid, :error)
    assert Fixture.calls(ctx.root) == 1
    assert :ok = Session.close_confirmed(pid)

    for override <- [
          %{"source_sha256" => String.duplicate("0", 64)},
          %{"operation_id" => String.duplicate("0", 32)},
          %{"offset" => 1}
        ] do
      fresh = start(ctx, cfg)
      invoke(fresh, %{"read_override" => override})

      receive do
        {:ipse, ^fresh, {:done, status}} -> assert status in [:ok, :error]
      after
        10_000 -> flunk("Invalid reader request did not finish")
      end

      ev = events(ctx, fresh)
      readers = Enum.filter(action_results(ev), &(&1["request"]["op"] == "effect.result.read"))
      assert Enum.all?(readers, &(&1["outcome"]["status"] != "ok"))

      assert Session.info(fresh).extension_result == nil or
               Session.info(fresh).extension_result["value"]["bytes"] == 0

      assert :ok = Session.close_confirmed(fresh)
    end
  end

  test "source, binding, namespace and recomputed window corruption refuse before torn-tail repair",
       ctx do
    cfg = config(ctx, server(ctx, :http, :normal))
    pid = start(ctx, cfg)
    invoke(pid)
    done(pid)
    ev = events(ctx, pid)
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    source = Enum.find(ev, &(&1["type"] == "extension_effect_result"))

    reader =
      Enum.find(
        ev,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "effect.result.read")
      )

    forged_text = String.duplicate("x", byte_size(reader["outcome"]["value"]["text"]))
    window_outcome = put_in(reader["outcome"], ["value", "text"], forged_text)

    forged_reader =
      reader
      |> Map.put("outcome", window_outcome)
      |> Map.put("outcome_sha256", digest(window_outcome))

    assert Actions.valid_result?(forged_reader)
    reader_position = Enum.find_index(ev, &(&1 == reader))

    prefix =
      ev |> Enum.take(reader_position + 1) |> List.replace_at(reader_position, forged_reader)

    assert {:error, _} = Actions.restore(prefix)

    changes = [
      Enum.reject(ev, &(&1 == source)),
      Enum.map(ev, fn e ->
        if e == source, do: put_in(e, ["data", "text"], "forged source"), else: e
      end),
      Enum.map(ev, fn e ->
        if e == source, do: Map.put(e, "parent_invocation_id", Ipse.Usage.id()), else: e
      end),
      Enum.map(ev, fn e ->
        if e["type"] in ~w(extension_action_intent extension_action_result) and
             e["request"]["op"] == "mcp.call",
           do: put_in(e, ["effect_binding", "alias"], "unselected"),
           else: e
      end),
      Enum.map(ev, fn e ->
        if e["type"] in ~w(extension_action_intent extension_action_result) and
             e["request"]["op"] == "effect.result.read",
           do: Map.put(e, "namespace", Ipse.Usage.id()),
           else: e
      end),
      Enum.map(ev, fn e -> if e == reader, do: forged_reader, else: e end)
    ]

    path = Path.join(ctx.dir, id <> ".jsonl")

    for corrupted <- changes do
      assert {:error, _} = Actions.restore(corrupted)
      bytes = Enum.map_join(corrupted, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  config: cfg, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
               )

      assert File.read!(path) == bytes
      assert Fixture.calls(ctx.root) == 1
    end
  end

  test "mixed authority permits 20 reads then one effect while original grants retain their step limit",
       ctx do
    selected = server(ctx, :http, :normal)
    mixed = start(ctx, config(ctx, selected))
    invoke(mixed, %{"before_reads" => 20})
    done(mixed)
    ev = events(ctx, mixed)
    results = action_results(ev)
    assert Enum.count(results, &(&1["request"]["op"] == "state.get")) == 20
    assert Enum.count(results, &(&1["request"]["op"] == "mcp.call")) == 1
    assert Enum.all?(results, &(&1["version"] == 2))
    assert Fixture.calls(ctx.root) == 1
    assert :ok = Session.close_confirmed(mixed)
    legacy = start(ctx, config(ctx, selected, :legacy))
    invoke(legacy, %{"before_reads" => 20, "read" => false})
    done(legacy, :error)
    legacy_results = action_results(events(ctx, legacy))
    assert length(legacy_results) == 16
    assert Enum.all?(legacy_results, &(&1["version"] == 1 and &1["request"]["op"] == "state.get"))
    assert Fixture.calls(ctx.root) == 1
  end

  test "mixed authority still refuses the seventeenth external effect", ctx do
    pid = start(ctx, config(ctx, server(ctx, :http, :normal)))
    invoke(pid, %{"repeat" => 17, "read" => false})
    done(pid, :error)
    ev = events(ctx, pid)
    results = action_results(ev)
    assert length(results) == 16

    assert Enum.all?(
             results,
             &(&1["request"]["op"] == "mcp.call" and &1["outcome"]["status"] == "ok")
           )

    assert Fixture.calls(ctx.root) == 16
    assert Enum.count(ev, &(&1["type"] == "extension_effect_result")) == 16
  end

  for interruption <- [:disconnect, :timeout, :cancel, :owner_loss] do
    test "#{interruption}: post-dispatch uncertainty is durable and idle resume never replays",
         ctx do
      mode = if unquote(interruption) == :disconnect, do: :disconnect, else: :hold
      {http, selected} = http_server(ctx, mode)
      cfg = config(ctx, selected)
      pid = start(ctx, cfg)
      id = Session.info(pid).id
      monitor = Process.monitor(pid)
      timeout = if unquote(interruption) == :timeout, do: 100, else: 5000
      invoke(pid, %{"request" => Map.put(request(), "timeout_ms", timeout)})
      assert_receive {:extension_mcp_fixture, :dispatched, handler}, 5000
      old_session = Fixture.http_session(http, handler)

      case unquote(interruption) do
        :cancel -> assert :ok = Session.cancel(pid)
        :owner_loss -> Process.exit(pid, :kill)
        _ -> :ok
      end

      if unquote(interruption) == :owner_loss do
        assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
      else
        done(pid, if(unquote(interruption) == :cancel, do: :cancelled, else: :error))
        assert :ok = Session.close_confirmed(pid)
      end

      if mode == :hold, do: assert_receive({:extension_mcp_fixture, :closed, ^handler}, 5000)
      assert :ok = Fixture.await_delete(http, old_session, 5000)
      assert Fixture.calls(ctx.root) == 1
      assert {:ok, ev} = Journal.load(ctx.dir, id)
      assert {:ok, _} = Session.restore_context(ev)
      refute Enum.any?(ev, &(&1["type"] == "extension_effect_result"))
      outcomes = action_results(ev)
      assert outcomes == [] or Enum.all?(outcomes, &(&1["outcome"]["status"] == "unknown"))

      assert Enum.any?(
               ev,
               &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "mcp.call")
             )

      before = Fixture.records(ctx.root)
      resumed = start(ctx, cfg, id)
      assert Session.info(resumed).phase == :idle
      assert Fixture.records(ctx.root) == before
      refute_receive :unexpected_mcp_model_call
    end
  end

  test "old HTTP DELETE completes after held POST closure before the idle-resume traffic snapshot",
       ctx do
    {http, selected} = http_server(ctx, :hold)
    cfg = config(ctx, selected)
    pid = start(ctx, cfg)
    id = Session.info(pid).id
    monitor = Process.monitor(pid)
    invoke(pid, %{"request" => Map.put(request(), "timeout_ms", 5000)})
    assert_receive {:extension_mcp_fixture, :dispatched, handler}, 5000
    old_session = Fixture.http_session(http, handler)
    assert :ok = Fixture.hold_delete(http, old_session)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    assert_receive {:extension_mcp_fixture, :closed, ^handler}, 5000
    assert_receive {:extension_mcp_fixture, :delete_waiting, ^old_session, delete_handler}, 5000

    # The old POST is closed, yet its transport's DELETE has not entered the log.
    pending = Fixture.records(ctx.root)

    assert %{"http_method" => "POST", "method" => "tools/call", "session_id" => ^old_session} =
             List.last(pending)

    assert Process.alive?(delete_handler)
    assert :ok = Fixture.release_delete(http, old_session)
    assert :ok = Fixture.await_delete(http, old_session, 5000)
    before = Fixture.records(ctx.root)

    assert before ==
             pending ++
               [
                 %{
                   "http_method" => "DELETE",
                   "method" => nil,
                   "params" => nil,
                   "session_id" => old_session
                 }
               ]

    assert Fixture.calls(ctx.root) == 1

    assert {:ok, ev} = Journal.load(ctx.dir, id)
    assert {:ok, _} = Session.restore_context(ev)

    assert Enum.any?(
             ev,
             &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "mcp.call")
           )

    refute Enum.any?(ev, &(&1["type"] == "extension_effect_result"))
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert Fixture.records(ctx.root) == before
    refute_receive :unexpected_mcp_model_call
  end
end
