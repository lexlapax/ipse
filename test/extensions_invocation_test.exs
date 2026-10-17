defmodule Ipse.Extensions.InvocationTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Catalog, Config, Registry, Store, Manifest, Invocation}

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:sdk_model, messages, tools})

      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok,
         %{
           "role" => "assistant",
           "content" => "finished",
           "provider_data" => %{"native" => "synthetic-private-native"}
         }, %{}}
      else
        response =
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "provider_data" => %{"native" => "synthetic-private-native"},
             "tool_calls" => [
               %{
                 "id" => "native-extension-call",
                 "type" => "function",
                 "function" => %{
                   "name" => "ext__sdk__echo",
                   "arguments" => Jason.encode!(config[:tool_args] || %{"text" => "hello"})
                 }
               }
             ]
           }, %{}}

        if config[:duplicate] do
          {:ok, assistant, usage} = response
          {:ok, Map.update!(assistant, "tool_calls", &(&1 ++ &1)), usage}
        else
          response
        end
      end
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-sdk-artifact-#{Ipse.Usage.id()}")
    source = Path.join(root, "source")
    File.mkdir_p!(Path.join(source, "ebin"))
    marker = Path.join(root, "loaded")
    called = Path.join(root, "called")
    pid_file = Path.join(root, "worker-pid")
    entrypoint = "Independent.SDK#{System.unique_integer([:positive])}"

    descriptor = %{
      "id" => "echo",
      "description" => "Synthetic typed SDK operation",
      "arguments_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "text" => %{"type" => "string", "maxLength" => 1024},
          "wait" => %{"type" => "boolean"},
          "wrong" => %{"type" => "boolean"},
          "host_request" => %{"type" => "object"},
          "repeat" => %{"type" => "boolean"}
        },
        "required" => ["text"]
      },
      "result_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"text" => %{"type" => "string"}, "input_id" => %{"type" => "string"}},
        "required" => ["text", "input_id"]
      }
    }

    exports =
      Map.new(Catalog.empty(), fn
        {"version", value} -> {"version", value}
        {group, _} -> {group, [descriptor]}
      end)

    capabilities =
      ~w(invoke.tool invoke.command invoke.service host.actions host.state.read host.state.write host.question)

    code = """
    defmodule #{entrypoint} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(marker)}, "loaded\\n", [:append]); :ok)
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("host.actions", payload, state) do
        File.write!(#{inspect(called)}, Jason.encode!(payload) <> "\\n", [:append])
        response = if get_in(payload, ["checkpoint", "write_request"]),
          do: %{"api_version" => 1, "kind" => "host_call", "request" => payload["checkpoint"]["write_request"]},
          else: if(state["repeat"],
          do: %{"api_version" => 1, "kind" => "host_call", "request" => state["request"]},
          else: %{"api_version" => 1, "kind" => "result", "value" => %{"text" => Jason.encode!(payload["outcome"]), "input_id" => payload["invocation_id"]}})
        {:ok, response, state}
      end
      def handle(stage, payload, state) do
        File.write!(#{inspect(called)}, Jason.encode!(payload) <> "\\n", [:append])
        File.write!(#{inspect(pid_file)}, System.pid())
        if payload["arguments"]["wait"], do: Process.sleep(:infinity)
        value = if payload["arguments"]["wrong"], do: %{"wrong" => true},
          else: %{"text" => stage <> ": " <> payload["arguments"]["text"], "input_id" => payload["invocation_id"]}
        if payload["arguments"]["host_request"] do
          request = payload["arguments"]["host_request"]
          {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request},
            %{"request" => request, "repeat" => payload["arguments"]["repeat"]}}
        else
          {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
        end
      end
    end
    """

    code_path = Path.join(root, "fixture.ex")
    File.write!(code_path, code)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        [
          "-pa",
          Application.app_dir(:ipse, "ebin"),
          "-pa",
          Application.app_dir(:jason, "ebin"),
          "-o",
          Path.join(source, "ebin"),
          code_path
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.rm(marker)
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/sdk",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => entrypoint,
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => capabilities,
      "exports" => exports,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", "ebin/Elixir.#{entrypoint}.beam"], fn path ->
          bytes = File.read!(Path.join(source, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    home = Path.join(root, "home")
    {:ok, installed} = Store.import(source, Path.join(home, "extensions/artifacts"))
    refute File.exists?(marker)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      artifact_root: root,
      source: source,
      home: home,
      digest: installed.digest,
      capabilities: capabilities,
      marker: marker,
      called: called,
      pid_file: pid_file,
      manifest: manifest
    }
  end

  setup ctx do
    for path <- [ctx.marker, ctx.called, ctx.pid_file], do: File.rm(path)
    File.rm_rf!(Path.join(ctx.home, "extension-state-v1"))
    root = Path.join(ctx.artifact_root, "session-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    source = %{
      scope: "operator",
      path: Path.join(root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "sdk",
            "artifact" => ctx.digest,
            "enabled" => true,
            "options" => %{},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => ctx.digest,
            "capabilities" => ctx.capabilities,
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }
    }

    {:ok, catalog} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(catalog, ctx.home)
    refute File.exists?(ctx.marker)

    config = %{
      provider: :ollama,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: ctx.home,
      approval: :ask,
      extensions: entries
    }

    %{root: root, dir: Path.join(root, "state"), config: config}
  end

  defp start(ctx, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: ctx.config, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp run_tool(ctx) do
    pid = start(ctx)
    :ok = Session.prompt(pid, "use the reviewed extension tool")
    assert_receive {:ipse, ^pid, {:approval, ref, "ext__sdk__echo", arguments}}, 2000
    assert arguments == (ctx.config[:tool_args] || %{"text" => "hello"})
    refute File.exists?(ctx.marker)
    :ok = Session.approve(pid, ref, true)
    pid
  end

  test "typed tool approval precedes executable load and receipts preserve original native data",
       ctx do
    pid = run_tool(ctx)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    result = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    assert result["value"]["input_id"] == intent["invocation_id"]
    assert result["value"]["text"] == "invoke.tool: hello"
    assert result["parent_call_id"] == "native-extension-call"
    assert :ok = Invocation.validate_events(events)
    assert File.read!(ctx.marker) == "loaded\n"
    assert {:ok, messages} = Session.restore_context(events)
    assert Enum.count(messages, &(&1["role"] == "tool")) == 1

    assert Enum.any?(
             messages,
             &(get_in(&1, ["provider_data", "native"]) == "synthetic-private-native")
           )

    assert Invocation.tool_message(result) in messages
    payload = ctx.called |> File.read!() |> String.trim() |> Jason.decode!()

    assert Enum.sort(Map.keys(payload)) ==
             ~w(api_version arguments id invocation_id session_id turn_id)

    assert payload == intent["payload"]
    refute Jason.encode!(payload) =~ "synthetic-private-native"
    assert_receive {:sdk_model, _, tools}
    assert Enum.any?(tools, &(get_in(&1, ["function", "name"]) == "ext__sdk__echo"))
  end

  test "denial never initializes extension code or creates a callback intent", ctx do
    pid = start(ctx)
    :ok = Session.prompt(pid, "tool fixture")
    assert_receive {:ipse, ^pid, {:approval, ref, _, _}}, 2000
    :ok = Session.approve(pid, ref, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute File.exists?(ctx.marker)
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_intent"))
  end

  test "commands and services use typed owned workers without model dispatch and restore inertly",
       ctx do
    pid = start(ctx)
    assert length(Session.exports(pid)["entries"]) == 3

    for kind <- [:command, :service] do
      assert :ok = Session.invoke_export(pid, kind, "ext__sdk__echo", %{"text" => "operator"})
      assert_receive {:ipse, ^pid, {:extension_result, display}}, 2000
      assert display["stage"] == "invoke.#{kind}"
      assert display["value"]["text"] == "invoke.#{kind}: operator"
      assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
      refute_receive {:sdk_model, _, _}, 0
    end

    info = Session.info(pid)
    assert info.accounting["request_count"] == 0
    {:ok, events} = Journal.load(ctx.dir, info.id)
    assert :ok = Invocation.validate_events(events)
    assert {:ok, []} = Session.restore_context(events)
    :ok = Session.close(pid)
    bytes = File.read!(Path.join(ctx.dir, info.id <> ".jsonl"))
    loads = File.read!(ctx.marker)
    resumed = start(ctx, info.id)
    assert Session.info(resumed).extension_result == info.extension_result
    assert File.read!(ctx.marker) == loads
    assert File.read!(Path.join(ctx.dir, info.id <> ".jsonl")) == bytes
  end

  test "wrong result schemas stop work with an unknown receipt instead of retry", ctx do
    ctx = %{ctx | config: Map.put(ctx.config, :tool_args, %{"text" => "hello", "wrong" => true})}
    pid = run_tool(ctx)
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert :ok = Invocation.validate_events(events)
    assert Enum.count(events, &(&1["type"] == "extension_invocation_intent")) == 1
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))

    assert Enum.any?(
             events,
             &(get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "unknown")
           )

    assert File.read!(ctx.marker) == "loaded\n"
  end

  test "cached result repairs the crash window before the redundant tool message without callbacks",
       ctx do
    pid = run_tool(ctx)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)
    {:ok, expected} = Session.restore_context(events)
    :ok = Session.close(pid)
    reduced = Enum.reject(events, &(get_in(&1, ["message", "ipse_extension_result"]) != nil))
    assert {:ok, ^expected} = Session.restore_context(reduced)
    path = Path.join(ctx.dir, id <> ".jsonl")
    File.write!(path, Enum.map_join(reduced, "\n", &Jason.encode!/1) <> "\n")
    loads = File.read!(ctx.marker)
    resumed = start(ctx, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(ctx.marker) == loads
  end

  test "receipt corruption, deletion and replay refuse resume before truncated-tail repair",
       ctx do
    pid = run_tool(ctx)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)
    :ok = Session.close(pid)
    intent = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    result = Enum.find(events, &(&1["type"] == "extension_invocation_result"))

    variants = [
      Enum.reject(events, &(&1 == intent)),
      Enum.reject(events, &(&1 == result)),
      Enum.map(events, fn e -> if e == result, do: Map.put(e, "text", "{}"), else: e end),
      Enum.map(events, fn e -> if e == result, do: Map.put(e, "secret", "unexpected"), else: e end),
      events ++ [result],
      Enum.map(events, fn e ->
        if e == intent, do: put_in(e, ["payload", "arguments", "text"], "changed"), else: e
      end)
    ]

    path = Path.join(ctx.dir, id <> ".jsonl")
    loads = File.read!(ctx.marker)

    for broken <- variants do
      assert {:error, _} = Session.restore_context(broken)
      bytes = Enum.map_join(broken, "\n", &Jason.encode!/1) <> "\n{partial"
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  config: ctx.config,
                  cwd: ctx.root,
                  state_dir: ctx.dir,
                  subscriber: self(),
                  id: id}
               )

      assert File.read!(path) == bytes
      assert File.read!(ctx.marker) == loads
    end
  end

  test "cancel and owner death stop the invocation VM and preserve unknown receipts", ctx do
    for action <- [:cancel, :kill] do
      File.rm(ctx.pid_file)
      pid = start(ctx)
      id = Session.info(pid).id

      :ok =
        Session.invoke_export(pid, :command, "ext__sdk__echo", %{"text" => "wait", "wait" => true})

      os_pid = await_pid(ctx.pid_file)

      if action == :cancel do
        assert :ok = Session.cancel(pid)
        assert_receive {:ipse, ^pid, {:done, :cancelled}}, 2000
        :ok = Session.close(pid)
      else
        monitor = Process.monitor(pid)
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2000
      end

      await_exit(os_pid, ctx.root)
      {:ok, events} = Journal.load(ctx.dir, id)
      assert Invocation.count(events) == 1
      refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
      assert :ok = Invocation.validate_events(events)
      loads = File.read!(ctx.marker)
      resumed = start(ctx, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(ctx.marker) == loads
      :ok = Session.close(resumed)
    end
  end

  test "callback quota and invalid arguments refuse initialization", ctx do
    pid = start(ctx)
    assert {:error, _} = Session.invoke_export(pid, :command, "ext__sdk__echo", %{"text" => 3})

    assert {:error, _} =
             Session.invoke_export(pid, :command, "ext__unknown__echo", %{"text" => "x"})

    :sys.replace_state(pid, &%{&1 | extension_invocations: Invocation.limit()})
    assert {:error, _} = Session.invoke_export(pid, :command, "ext__sdk__echo", %{"text" => "x"})
    refute File.exists?(ctx.marker)
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert Invocation.count(events) == 0
  end

  test "duplicate provider call IDs cannot initialize a tool even with session-wide approval",
       ctx do
    ctx = %{ctx | config: ctx.config |> Map.put(:duplicate, true) |> Map.put(:approval, :allow)}
    pid = start(ctx)
    :ok = Session.prompt(pid, "malformed call fixture")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2000
    refute File.exists?(ctx.marker)
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert Invocation.count(events) == 0
  end

  defp host_command(pid, request, extra \\ %{}) do
    Session.invoke_export(
      pid,
      :command,
      "ext__sdk__echo",
      Map.merge(%{"text" => "state fixture", "host_request" => request}, extra)
    )
  end

  defp host_outcome(pid),
    do: Session.info(pid).extension_result["value"]["text"] |> Jason.decode!()

  test "host writes need their own full approval and reads recover without executing callbacks",
       ctx do
    pid = start(ctx)

    put = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "note",
      "expected_revision" => 0,
      "value" => %{"text" => "remembered"}
    }

    assert :ok = host_command(pid, put)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}}, 3000
    assert proposed["request"] == put
    assert proposed["extension"] == "sdk"
    refute File.exists?(Path.join(ctx.home, "extension-state-v1"))
    assert Session.info(pid).phase == :extension_approval
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid)["status"] == "ok"
    assert host_outcome(pid)["value"]["record"]["revision"] == 1

    assert :ok = host_command(pid, %{"op" => "state.get", "scope" => "project", "key" => "note"})
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 20
    assert host_outcome(pid)["value"]["record"]["value"] == put["value"]
    info = Session.info(pid)
    {:ok, events} = Journal.load(ctx.dir, info.id)
    assert :ok = Ipse.Extensions.Actions.validate_events(events)
    assert Enum.count(events, &(&1["type"] == "extension_action_result")) == 2
    assert info.accounting["request_count"] == 0
    :ok = Session.close(pid)
    called = File.read!(ctx.called)
    path = Path.join(ctx.dir, info.id <> ".jsonl")
    before = File.read!(path)
    resumed = start(ctx, info.id)
    assert Session.info(resumed).extension_result == info.extension_result
    assert File.read!(ctx.called) == called
    assert File.read!(path) == before
  end

  test "denied host state proposals never create business records", ctx do
    request = %{
      "op" => "state.delete",
      "scope" => "operator",
      "key" => "note",
      "expected_revision" => 0
    }

    pid = start(ctx)
    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:state.delete", _}}, 3000
    :ok = Session.approve(pid, ref, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid) == %{"status" => "denied", "value" => %{}}
    refute File.exists?(Path.join(ctx.home, "extension-state-v1"))
    readonly = start(%{ctx | config: Map.put(ctx.config, :approval, :deny)})
    :ok = host_command(readonly, request)
    assert_receive {:ipse, ^readonly, {:done, :ok}}, 3000
    refute_receive {:ipse, ^readonly, {:approval, _, _, _}}, 20
    assert host_outcome(readonly)["status"] == "denied"
    refute File.exists?(Path.join(ctx.home, "extension-state-v1"))
  end

  test "cancel during separate host approval stops the real VM and leaves no write", ctx do
    request = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "note",
      "expected_revision" => 0,
      "value" => %{}
    }

    pid = start(ctx)
    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:approval, ref, _, _}}, 3000
    actual_pid = await_pid(ctx.pid_file)
    :ok = Session.cancel(pid)
    await_exit(actual_pid, ctx.root)
    assert {:error, :no_pending_approval} = Session.approve(pid, ref, true)
    refute File.exists?(Path.join(ctx.home, "extension-state-v1"))
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert Enum.count(events, &(&1["type"] == "extension_action_intent")) == 0
    assert :ok = Ipse.Extensions.Projection.validate_events(events)
  end

  test "finite continuation budget stops a callback loop without a seventeenth host action",
       ctx do
    pid = start(ctx)

    :ok =
      host_command(pid, %{"op" => "state.get", "scope" => "session", "key" => "note"}, %{
        "repeat" => true
      })

    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert Enum.count(events, &(&1["type"] == "extension_action_result")) == 16
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert :ok = Ipse.Extensions.Projection.validate_events(events)
  end

  test "deleted or replayed host receipts refuse recovery before repairing tail", ctx do
    pid = start(ctx)
    :ok = host_command(pid, %{"op" => "state.get", "scope" => "project", "key" => "note"})
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)
    event = Enum.find(events, &(&1["type"] == "extension_action_result"))

    for corrupted <- [
          List.delete(events, event),
          Enum.reject(events, &(&1["type"] in Ipse.Extensions.Actions.types())),
          events ++ [event],
          Enum.map(events, fn e ->
            if e == event, do: put_in(e, ["outcome", "value", "record", "revision"], 99), else: e
          end)
        ] do
      bytes = Enum.map_join(corrupted, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
      path = Path.join(ctx.dir, id <> ".jsonl")
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  [
                    config: ctx.config,
                    cwd: ctx.root,
                    state_dir: ctx.dir,
                    subscriber: self(),
                    id: id
                  ]}
               )

      assert File.read!(path) == bytes
    end
  end

  test "project-scoped extension cannot select operator state", ctx do
    entries = Enum.map(ctx.config.extensions, &put_in(&1, [:identity, "scope"], "project"))
    pid = start(%{ctx | config: Map.put(ctx.config, :extensions, entries)})
    :ok = host_command(pid, %{"op" => "state.get", "scope" => "operator", "key" => "note"})
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    refute File.exists?(Path.join(ctx.home, "extension-state-v1"))
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    refute Enum.any?(events, &(&1["type"] == "extension_action_intent"))
  end

  test "host namespaces isolate session, project, instance, artifact and configuration source",
       ctx do
    identity = hd(ctx.config.extensions).identity
    id = Ipse.Usage.id()

    namespace = fn ident, scope, cwd, session ->
      {:ok, namespace} = Ipse.Extensions.State.namespace(ident, scope, cwd, session)
      namespace
    end

    assert namespace.(identity, "operator", ctx.root, id) ==
             namespace.(identity, "operator", ctx.root <> "/other", Ipse.Usage.id())

    assert namespace.(identity, "project", ctx.root, id) ==
             namespace.(identity, "project", ctx.root, Ipse.Usage.id())

    refute namespace.(identity, "project", ctx.root, id) ==
             namespace.(identity, "project", ctx.root <> "/other", id)

    refute namespace.(identity, "session", ctx.root, id) ==
             namespace.(identity, "session", ctx.root, Ipse.Usage.id())

    for changed <- [
          Map.put(identity, "instance", "other"),
          Map.put(identity, "artifact_sha256", String.duplicate("e", 64)),
          Map.put(identity, "source_sha256", String.duplicate("f", 64))
        ] do
      refute namespace.(identity, "operator", ctx.root, id) ==
               namespace.(changed, "operator", ctx.root, id)
    end
  end

  test "unknown host operation commits no continuation or final callback and never replays on resume",
       ctx do
    pid = start(ctx)
    info = Session.info(pid)

    {:ok, namespace} =
      Ipse.Extensions.State.namespace(
        hd(ctx.config.extensions).identity,
        "project",
        ctx.root,
        info.id
      )

    root = Path.join(ctx.home, "extension-state-v1")

    {:ok, _} =
      Ipse.Extensions.State.execute(
        root,
        namespace,
        %{"op" => "state.get", "scope" => "project", "key" => "note"},
        Ipse.Usage.id()
      )

    file = Path.join([root, namespace, "state.json"])
    File.write!(file, "{broken")
    File.chmod!(file, 0o600)
    :ok = host_command(pid, %{"op" => "state.get", "scope" => "project", "key" => "note"})
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    {:ok, events} = Journal.load(ctx.dir, info.id)
    result = Enum.find(events, &(&1["type"] == "extension_action_result"))
    assert result["outcome"] == %{"status" => "unknown", "value" => %{}}
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert length(String.split(File.read!(ctx.called), "\n", trim: true)) == 1
    :ok = Session.close(pid)
    calls = File.read!(ctx.called)
    path = Path.join(ctx.dir, info.id <> ".jsonl")
    before = File.read!(path)
    resumed = start(ctx, info.id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(ctx.called) == calls
    assert File.read!(path) == before
    assert File.read!(file) == "{broken"
  end

  defp question_request(checkpoint \\ %{"next" => "finish"}) do
    %{
      "op" => "operator.question",
      "checkpoint" => checkpoint,
      "arguments" => %{
        "questions" => [
          %{
            "id" => "choice",
            "prompt" => "Choose a synthetic option",
            "kind" => "single",
            "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}],
            "recommended" => "a"
          },
          %{
            "id" => "tags",
            "prompt" => "Choose synthetic tags",
            "kind" => "multiple",
            "options" => [%{"id" => "a", "label" => "A"}, %{"id" => "b", "label" => "B"}]
          },
          %{"id" => "note", "prompt" => "Enter a synthetic note", "kind" => "text"}
        ]
      }
    }
  end

  defp answers, do: %{"choice" => "b", "tags" => ["a", "b"], "note" => "fixture answer"}

  test "structured extension command closes VM before asking and validates explicit answers",
       ctx do
    pid = start(ctx)
    request = question_request()
    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:question, id, args}}, 3000
    assert args == request["arguments"]
    await_exit(await_pid(ctx.pid_file), ctx.root)
    assert Session.info(pid).phase == :question
    refute_receive {:ipse, ^pid, {:done, _}}, 30
    path = Path.join(ctx.dir, Session.info(pid).id <> ".jsonl")
    before = File.read!(path)
    assert {:error, _} = Session.answer(pid, "stale", answers())
    assert {:error, _} = Session.answer(pid, id, %{"choice" => "a"})
    assert File.read!(path) == before
    :ok = Session.answer(pid, id, answers())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid) == %{"status" => "answered", "value" => %{"answers" => answers()}}
    assert Session.info(pid).accounting["request_count"] == 0

    [initial, resumed] =
      File.read!(ctx.called) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert initial["arguments"]["host_request"] == request
    assert resumed["checkpoint"] == request["checkpoint"]

    assert :ok =
             Ipse.Extensions.Projection.validate_events(
               elem(Journal.load(ctx.dir, Session.info(pid).id), 1)
             )
  end

  test "pending extension question resumes inertly and only an explicit answer starts continuation",
       ctx do
    pid = start(ctx)
    :ok = host_command(pid, question_request())
    assert_receive {:ipse, ^pid, {:question, id, _}}, 3000
    session_id = Session.info(pid).id
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 1000
    calls = File.read!(ctx.called)
    path = Path.join(ctx.dir, session_id <> ".jsonl")
    before = File.read!(path)
    resumed = start(ctx, session_id)
    assert_receive {:ipse, ^resumed, {:question, ^id, _}}, 2000
    assert File.read!(path) == before
    assert File.read!(ctx.called) == calls
    :ok = Session.answer(resumed, id, answers())
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 3000
    assert host_outcome(resumed)["status"] == "answered"
    assert length(String.split(File.read!(ctx.called), "\n", trim: true)) == 2
  end

  test "native extension tool question keeps its real call and approval across inert resume",
       ctx do
    ctx = %{
      ctx
      | config:
          Map.put(ctx.config, :tool_args, %{
            "text" => "question",
            "host_request" => question_request()
          })
    }

    pid = run_tool(ctx)
    assert_receive {:ipse, ^pid, {:question, question_id, _}}, 3000
    id = Session.info(pid).id
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 1000
    resumed = start(ctx, id)
    assert_receive {:ipse, ^resumed, {:question, ^question_id, _}}, 2000
    :ok = Session.answer(resumed, question_id, answers())
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 3000
    {:ok, events} = Journal.load(ctx.dir, id)
    assert :ok = Ipse.Extensions.Projection.validate_events(events)
    messages = for %{"type" => "message", "message" => message} <- events, do: message

    result =
      Enum.find(
        messages,
        &(&1["role"] == "tool" and &1["tool_call_id"] == "native-extension-call")
      )

    assert result["ipse_tool_outcome"] == %{
             "status" => "result_recorded",
             "approval" => "approved"
           }

    assert Enum.any?(
             messages,
             &(&1["provider_data"] == %{"native" => "synthetic-private-native"})
           )
  end

  test "extension answers do not authorize a following host write", ctx do
    pid = start(ctx)

    put = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "note",
      "expected_revision" => 0,
      "value" => %{}
    }

    :ok = host_command(pid, question_request(%{"write_request" => put}))
    assert_receive {:ipse, ^pid, {:question, id, _}}, 3000
    :ok = Session.answer(pid, id, answers())
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}}, 3000
    assert proposed["request"] == put
    refute File.exists?(Path.join(ctx.home, "extension-state-v1"))
    :ok = Session.approve(pid, ref, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid)["status"] == "denied"
    refute File.exists?(Path.join(ctx.home, "extension-state-v1"))
  end

  test "cancelled extension question records no answer or executable continuation", ctx do
    pid = start(ctx)
    :ok = host_command(pid, question_request())
    assert_receive {:ipse, ^pid, {:question, id, _}}, 3000
    :ok = Session.cancel(pid)
    assert {:error, _} = Session.answer(pid, id, answers())
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_action_result" and &1["outcome"]["status"] == "cancelled")
           )

    refute Enum.any?(events, &(&1["type"] == "extension_continuation_intent"))
    assert :ok = Ipse.Extensions.Projection.validate_events(events)
  end

  test "unavailable operator questions stop without selecting recommendations", ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :operator_questions, false)})
    :ok = host_command(pid, question_request())
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    refute_receive {:ipse, ^pid, {:question, _, _}}, 20
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    refute Enum.any?(events, &(&1["type"] in ~w(extension_question extension_action_intent)))
  end

  test "question and continuation corruption refuse resume before tail repair", ctx do
    pid = start(ctx)
    :ok = host_command(pid, question_request())
    assert_receive {:ipse, ^pid, {:question, question_id, _}}, 3000
    :ok = Session.answer(pid, question_id, answers())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)
    continuation = Enum.find(events, &(&1["type"] == "extension_continuation_intent"))

    for corrupted <- [
          Enum.reject(events, &(&1["type"] == "extension_question")),
          List.delete(events, continuation),
          Enum.map(events, fn event ->
            if event["type"] == "extension_question",
              do: Map.update!(event, "steps", &(&1 + 1)),
              else: event
          end),
          events ++ [continuation]
        ] do
      path = Path.join(ctx.dir, id <> ".jsonl")
      bytes = Enum.map_join(corrupted, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  config: ctx.config,
                  cwd: ctx.root,
                  state_dir: ctx.dir,
                  subscriber: self(),
                  id: id}
               )

      assert File.read!(path) == bytes
    end
  end

  test "interrupted answer continuation remains idle and never restarts executable initialization",
       ctx do
    pid = start(ctx)
    :ok = host_command(pid, question_request())
    assert_receive {:ipse, ^pid, {:question, question_id, _}}, 3000
    :ok = Session.answer(pid, question_id, answers())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)
    index = Enum.find_index(events, &(&1["type"] == "extension_continuation_intent"))
    prefix = Enum.take(events, index + 1)
    assert :ok = Ipse.Extensions.Projection.validate_events(prefix)
    path = Path.join(ctx.dir, id <> ".jsonl")
    bytes = Enum.map_join(prefix, "", &(Jason.encode!(&1) <> "\n"))
    File.write!(path, bytes)
    calls = File.read!(ctx.called)
    File.rm!(ctx.marker)
    resumed = start(ctx, id)
    assert Session.info(resumed).phase == :idle
    assert Session.info(resumed).question == nil
    refute File.exists?(ctx.marker)
    assert File.read!(ctx.called) == calls
    assert File.read!(path) == bytes
  end

  test "an answer exceeding its checkpoint envelope is rejected without recording or truncation",
       ctx do
    pid = start(ctx)
    :ok = host_command(pid, question_request(%{"data" => String.duplicate("x", 8170)}))
    assert_receive {:ipse, ^pid, {:question, question_id, _}}, 3000
    path = Path.join(ctx.dir, Session.info(pid).id <> ".jsonl")
    before = File.read!(path)

    assert {:error, _} =
             Session.answer(
               pid,
               question_id,
               Map.put(answers(), "note", String.duplicate("a", 8000))
             )

    assert File.read!(path) == before
    assert Session.info(pid).phase == :question
    :ok = Session.answer(pid, question_id, answers())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
  end

  defp await_pid(path, attempts \\ 150)
  defp await_pid(_, 0), do: flunk("invocation VM did not start")

  defp await_pid(path, attempts) do
    case File.read(path) do
      {:ok, pid} ->
        if Regex.match?(~r/\A[0-9]+\z/, pid) do
          pid
        else
          Process.sleep(20)
          await_pid(path, attempts - 1)
        end

      _ ->
        Process.sleep(20)
        await_pid(path, attempts - 1)
    end
  end

  defp await_exit(pid, cwd, attempts \\ 150)
  defp await_exit(_, _, 0), do: flunk("invocation VM survived cancellation")

  defp await_exit(pid, cwd, attempts) do
    {:ok, result} = Ipse.Runner.run("kill -0 " <> pid, cwd, timeout_ms: 1000, output_limit: 0)
    refute result.timed_out

    if result.exit_code == 0 do
      Process.sleep(20)
      await_exit(pid, cwd, attempts - 1)
    end
  end
end
