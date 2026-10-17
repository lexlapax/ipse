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
          "wrong" => %{"type" => "boolean"}
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

    capabilities = ~w(invoke.tool invoke.command invoke.service)

    code = """
    defmodule #{entrypoint} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(marker)}, "loaded\\n", [:append]); :ok)
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle(stage, payload, state) do
        File.write!(#{inspect(called)}, Jason.encode!(payload) <> "\\n", [:append])
        File.write!(#{inspect(pid_file)}, System.pid())
        if payload["arguments"]["wait"], do: Process.sleep(:infinity)
        value = if payload["arguments"]["wrong"], do: %{"wrong" => true},
          else: %{"text" => stage <> ": " <> payload["arguments"]["text"], "input_id" => payload["invocation_id"]}
        {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
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
