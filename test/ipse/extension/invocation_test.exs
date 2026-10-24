Code.require_file("../../support/stdio_probe.exs", __DIR__)
Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Extension.InvocationTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.{Catalog, Config, Registry, Artifact, Invocation}

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:sdk_model, messages, tools})

      cond do
        config[:parallel_model_calls] == true and config[:delegation_origin] == nil and
            not Enum.any?(messages, &(&1["role"] == "tool")) ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "parallel",
                 "type" => "function",
                 "function" => %{
                   "name" => "delegate_parallel",
                   "arguments" =>
                     Jason.encode!(%{
                       "tasks" => [
                         %{"task" => "First synthetic extension", "context" => "Public fixture"},
                         %{"task" => "Second synthetic extension", "context" => "Public fixture"}
                       ]
                     })
                 }
               }
             ]
           }, %{}}

        Enum.any?(messages, &(&1["role"] == "tool")) ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "finished",
             "provider_data" => %{"native" => "synthetic-private-native"}
           }, %{}}

        true ->
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
      ~w(invoke.tool invoke.command invoke.service host.actions host.state.read host.state.write host.question host.tools host.model)

    code = """
    defmodule #{entrypoint} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(marker)}, "loaded\\n", [:append]); :ok)
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("host.actions", payload, state) do
        if get_in(payload, ["checkpoint", "test_delay_ms"]) == 4000, do: Process.sleep(4000)
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
        File.write!((#{inspect(pid_file)}) <> ".ready-" <> System.pid(), System.pid()); File.rename!((#{inspect(pid_file)}) <> ".ready-" <> System.pid(), #{inspect(pid_file)})
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
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    home = Path.join(root, "home")
    {:ok, installed} = Artifact.import(source, Path.join(home, "extensions/artifacts"))
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
    :ok = Session.approve(pid, ref, "no")
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

    duplicate =
      Invocation.intent(
        intent["identity"],
        intent["descriptor"],
        intent["payload"]["arguments"],
        intent["payload"]["session_id"],
        intent["payload"]["turn_id"],
        intent["parent_call_id"],
        intent["parent_request_id"],
        intent["approval"]
      )

    {:ok, duplicate_result} =
      Invocation.build_result(duplicate, %{
        "api_version" => 1,
        "kind" => "result",
        "value" => result["value"]
      })

    position =
      Enum.find_index(
        events,
        &(get_in(&1, ["message", "ipse_extension_result", "invocation_id"]) ==
            intent["invocation_id"])
      ) + 1

    duplicate_pair =
      Enum.take(events, position) ++
        [
          duplicate,
          duplicate_result,
          %{"type" => "message", "message" => Invocation.tool_message(duplicate_result)}
        ] ++ Enum.drop(events, position)

    variants = [
      duplicate_pair,
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
    assert_receive {:ipse, ^pid, {:done, :error}}, 2000
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

  test "explicit extension inference uses a different profile, full approval and canonical usage",
       ctx do
    {base, server} = model_fixture(self())
    config = model_config(ctx.config, base)
    pid = start(%{ctx | config: config})
    request = model_request()
    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", proposed}}, 3000
    assert proposed["request"] == request
    assert proposed["execution"]["provider"] == "ollama"
    assert proposed["execution"]["id"] == "extract"
    assert proposed["execution"]["max_output_tokens"] == 32
    assert proposed["destination"]["origin"] == base

    assert proposed["destination"]["target_sha256"] ==
             Ipse.JSON.sha256(base <> "/api/chat")

    assert Ipse.Extension.ModelCall.delegated_approval?("extension:model.complete", proposed)
    refute_receive {:model_http, _, _}, 20
    :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert_receive {:model_http, headers, payload}, 1000
    refute String.downcase(headers) =~ "authorization"
    assert payload["model"] == "helper-fixture"
    assert payload["tools"] == []
    assert payload["options"] == %{"num_predict" => 32}

    assert [helper_system, helper_context] = payload["messages"]
    assert helper_system["role"] == "system"
    refute helper_system["content"] =~ request["instruction"]
    assert helper_context["role"] == "user"
    [label, encoded] = String.split(helper_context["content"], "\n", parts: 2)
    assert label =~ "Untrusted extension task context"
    assert Jason.decode!(encoded) == Map.take(request, ~w(instruction input))

    assert :ok = Task.await(server)
    assert %{"status" => "ok", "value" => value} = host_outcome(pid)
    assert value["text"] == "entities"
    assert value["reported_model"] == "helper-reported"
    assert value["usage"]["counts"]["total_tokens"] == 10
    refute Jason.encode!(value) =~ "private-thinking"
    refute_receive {:ipse, ^pid, {:text, _}}, 20
    refute_receive {:sdk_model, _, _}, 20
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, ledger} = Ipse.Usage.restore(events, Session.info(pid).id)
    [record] = Ipse.Usage.snapshot(ledger)["requests"]
    assert record["kind"] == "extension"
    assert record["provider"] == "ollama"
    assert record["model"] == "helper-fixture"
    assert record["selected_profile"] == "extract"
    assert record["request_id"] == value["request_id"]
    assert :ok = Ipse.Extension.Projection.validate_events(events)
    assert {:ok, []} = Session.restore_context(events)
    native = Enum.find(events, &(&1["type"] == "extension_model_response"))

    assert get_in(native, ["assistant", "provider_data", "message", "thinking"]) ==
             "private-thinking"

    id = Session.info(pid).id
    :ok = Session.close(pid)
    bytes = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
    calls = File.read!(ctx.called)
    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(ctx.dir, id <> ".jsonl")) == bytes
    assert File.read!(ctx.called) == calls
    refute_receive {:model_http, _, _}, 20
  end

  test "pinned OpenRouter extension inference preserves approval, private continuation and idle resume",
       ctx do
    previous = System.get_env("OPENROUTER_API_KEY")
    System.put_env("OPENROUTER_API_KEY", "fixture-router-only-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("OPENROUTER_API_KEY", previous),
        else: System.delete_env("OPENROUTER_API_KEY")
    end)

    frame = fn delta, reason ->
      %{
        "model" => "org/model",
        "provider" => "openai",
        "choices" => [%{"index" => 0, "delta" => delta, "finish_reason" => reason}]
      }
    end

    body =
      Ipse.Test.ProviderFixture.sse([
        frame.(
          %{
            "content" => "entities",
            "reasoning_details" => [
              %{"type" => "reasoning.encrypted", "data" => "private-router-continuation"}
            ]
          },
          nil
        ),
        frame.(%{}, "stop")
        |> Map.put("usage", %{
          "prompt_tokens" => 7,
          "completion_tokens" => 3,
          "total_tokens" => 10,
          "cost" => 123.45
        }),
        "[DONE]"
      ])

    {base, server} = Ipse.Test.ProviderFixture.start(body)
    config = model_config(ctx.config, base)

    route = %{
      "provider" => "openrouter",
      "model" => "org/model",
      "base_url" => base,
      "upstream" => "openai",
      "max_output_tokens" => 32
    }

    config = put_in(config, [:profiles, "extract"], route)
    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", proposed}}, 3000
    assert proposed["execution"]["provider"] == "openrouter"
    assert proposed["execution"]["upstream"] == "openai"
    assert proposed["execution"]["data_collection"] == "deny"
    assert Ipse.Extension.ModelCall.delegated_approval?("extension:model.complete", proposed)
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    {headers, payload} = Task.await(server)
    assert headers =~ "authorization: Bearer fixture-router-only-key"
    refute headers =~ "main-only-fixture"

    assert payload["provider"] == %{
             "only" => ["openai"],
             "order" => ["openai"],
             "allow_fallbacks" => false,
             "require_parameters" => true,
             "data_collection" => "deny"
           }

    assert payload["max_tokens"] == 32
    refute Map.has_key?(payload, "tools")
    assert %{"status" => "ok", "value" => value} = host_outcome(pid)
    assert value["text"] == "entities"
    assert value["usage"]["counts"]["total_tokens"] == 10
    refute Jason.encode!(value) =~ "private-router-continuation"
    refute Jason.encode!(value) =~ "123.45"
    refute_receive {:ipse, ^pid, {:text, _}}, 20
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)
    assert :ok = Ipse.Extension.Projection.validate_events(events)
    assert {:ok, ledger} = Ipse.Usage.restore(events, id)
    [record] = Ipse.Usage.snapshot(ledger)["requests"]
    assert record["provider"] == "openrouter"
    assert record["billing_mode"] == "api"
    native = Enum.find(events, &(&1["type"] == "extension_model_response"))

    assert get_in(native, ["assistant", "provider_data", "message", "reasoning_details"]) == [
             %{"type" => "reasoning.encrypted", "data" => "private-router-continuation"}
           ]

    assert :ok = Session.close(pid)
    bytes = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
    calls = File.read!(ctx.called)
    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(ctx.dir, id <> ".jsonl")) == bytes
    assert File.read!(ctx.called) == calls
  end

  test "Gemini extension inference keeps signed parts private and uses the helper's credential",
       ctx do
    previous = System.get_env("GEMINI_API_KEY")
    System.put_env("GEMINI_API_KEY", "helper-gemini-fixture-key")

    on_exit(fn ->
      if previous,
        do: System.put_env("GEMINI_API_KEY", previous),
        else: System.delete_env("GEMINI_API_KEY")
    end)

    parts = [
      %{"text" => "PRIVATE_HELPER_THOUGHT", "thought" => true},
      %{"text" => "entities", "thoughtSignature" => "PRIVATE_HELPER_SIGNATURE"}
    ]

    body =
      Ipse.Test.ProviderFixture.sse(%{
        "modelVersion" => "gemini-fixture-001",
        "candidates" => [
          %{"content" => %{"role" => "model", "parts" => parts}, "finishReason" => "STOP"}
        ],
        "usageMetadata" => %{
          "promptTokenCount" => 3,
          "toolUsePromptTokenCount" => 0,
          "candidatesTokenCount" => 2,
          "thoughtsTokenCount" => 1,
          "totalTokenCount" => 6
        }
      })

    {base, server} = Ipse.Test.ProviderFixture.start(body)
    config = model_config(ctx.config, base)

    config =
      put_in(config, [:profiles, "extract"], %{
        "provider" => "gemini",
        "model" => "gemini-fixture",
        "base_url" => base,
        "max_output_tokens" => 32
      })

    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", proposed}}, 3000
    assert proposed["execution"]["provider"] == "gemini"
    assert Ipse.Extension.ModelCall.delegated_approval?("extension:model.complete", proposed)
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    {headers, payload} = Task.await(server)
    assert headers =~ "x-goog-api-key: helper-gemini-fixture-key"
    refute headers =~ "main-only-fixture"
    assert payload["generationConfig"]["maxOutputTokens"] == 32
    refute Map.has_key?(payload, "tools")
    assert %{"status" => "ok", "value" => value} = host_outcome(pid)
    assert value["text"] == "entities"
    assert value["usage"]["counts"]["output_tokens"] == 3
    refute Jason.encode!(value) =~ "PRIVATE_HELPER"
    refute_receive {:ipse, ^pid, {:text, _}}, 20
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)
    assert :ok = Ipse.Extension.Projection.validate_events(events)
    native = Enum.find(events, &(&1["type"] == "extension_model_response"))
    assert get_in(native, ["assistant", "provider_data", "content", "parts"]) == parts
    assert {:ok, _} = Ipse.Usage.restore(events, id)
    assert :ok = Session.close(pid)
    bytes = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
    calls = File.read!(ctx.called)
    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(ctx.dir, id <> ".jsonl")) == bytes
    assert File.read!(ctx.called) == calls
  end

  test "structured inference binds full approval and native format to live and saved results",
       ctx do
    {base, server} = model_fixture(self(), text: ~s({"names":["Ada"]}))
    config = model_config(ctx.config, base)
    pid = start(%{ctx | config: config})

    request =
      structured_model_request()
      |> Map.put("input", String.duplicate("x", 4096))
      |> Map.put("instruction", String.duplicate("x", 1900))
      |> put_in(["response_schema", "description"], "")

    padding = 12_288 - byte_size(Jason.encode!(request))
    request = put_in(request, ["response_schema", "description"], String.duplicate("x", padding))
    assert byte_size(Jason.encode!(request)) == 12_288
    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", proposed}}, 3000
    assert proposed["request"] == request
    assert Ipse.Extension.ModelCall.delegated_approval?("extension:model.complete", proposed)

    for provider <- ~w(openai chatgpt anthropic) do
      facts =
        proposed["execution"]
        |> Map.put("provider", provider)
        |> Map.put(
          "billing_mode",
          Ipse.Usage.billing_mode(String.to_existing_atom(provider))
        )

      refute Ipse.Extension.ModelCall.delegated_approval?(
               "extension:model.complete",
               Map.put(proposed, "execution", facts)
             )
    end

    refute_receive {:model_http, _, _}, 20
    :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert :ok = Task.await(server)
    assert_receive {:model_http, _, wire}
    assert wire["format"] == request["response_schema"]
    assert wire["options"] == %{"num_predict" => 32}
    refute Map.has_key?(wire, "think")
    assert %{"status" => "ok", "value" => value} = host_outcome(pid)
    assert value["text"] == ~s({"names":["Ada"]})
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)
    assert {:ok, _} = Ipse.Usage.restore(events, id)
    assert {:ok, []} = Session.restore_context(events)
    :ok = Session.close(pid)

    forged_text = ~s({"names":[1]})
    source = Enum.find(events, &(&1["type"] == "extension_model_request"))

    forged =
      Enum.map(events, fn event ->
        case event["type"] do
          "extension_model_response" ->
            assistant =
              event["assistant"]
              |> Map.put("content", forged_text)
              |> put_in(["provider_data", "message", "content"], forged_text)

            {:ok, changed} = Ipse.Extension.ModelCall.response(source["admission"], assistant)
            changed

          "extension_action_result" ->
            outcome = put_in(event["outcome"], ["value", "text"], forged_text)

            event
            |> Map.put("outcome", outcome)
            |> Map.put("outcome_sha256", Ipse.JSON.digest([outcome]))

          _ ->
            event
        end
      end)

    changed_schema =
      Enum.map(events, fn event ->
        if event["type"] in ~w(extension_action_intent extension_action_result),
          do: put_in(event, ["request", "response_schema", "properties", "names", "maxItems"], 0),
          else: event
      end)

    for corrupt <- [forged, changed_schema] do
      assert {:error, _} = Ipse.Usage.restore(corrupt, id)
      path = Path.join(ctx.dir, id <> ".jsonl")
      bytes = Enum.map_join(corrupt, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  config: config, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
               )

      assert File.read!(path) == bytes
    end

    File.write!(
      Path.join(ctx.dir, id <> ".jsonl"),
      Enum.map_join(events, "", &(Jason.encode!(&1) <> "\n"))
    )

    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).phase == :idle
    assert Session.info(resumed).accounting["request_count"] == 1
    refute_receive {:model_http, _, _}, 20
  end

  test "unsupported structured profiles refuse before approval, admission or provider IO", ctx do
    for provider <- ~w(openai chatgpt anthropic) do
      profile = %{"provider" => provider, "model" => "fixture"}

      config =
        model_config(ctx.config, "http://127.0.0.1:1")
        |> Map.delete(:max_output_tokens)
        |> put_in([:profiles, "extract"], profile)

      pid = start(%{ctx | config: config})
      :ok = host_command(pid, structured_model_request())
      assert_receive {:ipse, ^pid, {:done, :error}}, 3000
      refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 20
      assert Session.info(pid).accounting["request_count"] == 0
      {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)

      refute Enum.any?(
               events,
               &(&1["type"] in ~w(extension_action_intent extension_model_request request_admitted))
             )

      :ok = Session.close(pid)
    end
  end

  test "malformed or schema-invalid completed inference stays charged without repair or replay",
       ctx do
    for text <- [
          ~s({names:[]}),
          ~s({"names":["Ada","Grace"]}),
          ~s({"names":[],"names":["Ada"]}),
          "[]"
        ] do
      {base, server} = model_fixture(self(), text: text)

      config =
        model_config(ctx.config, base)
        |> Map.merge(%{approval: :allow, budget: %{"version" => 1, "max_requests" => 1}})

      pid = start(%{ctx | config: config})
      :ok = host_command(pid, structured_model_request())
      assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
      assert :ok = Task.await(server)
      assert_receive {:model_http, _, _}

      assert host_outcome(pid) == %{
               "status" => "failed",
               "value" => %{"code" => "model_response"}
             }

      [record] = Session.info(pid).accounting["requests"]
      assert record["outcome"] == "completed"
      assert record["usage"]["counts"]["total_tokens"] == 10
      id = Session.info(pid).id
      assert {:ok, budget} = Ipse.Usage.Budget.saved(ctx.dir, id)
      assert budget["request_count"] == 1
      {:ok, events} = Journal.load(ctx.dir, id)
      native = Enum.find(events, &(&1["type"] == "extension_model_response"))
      assert native["assistant"]["content"] == text
      assert {:ok, []} = Session.restore_context(events)
      assert {:ok, _} = Ipse.Usage.restore(events, id)
      :ok = Session.close(pid)
      bytes = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
      resumed = start(%{ctx | config: config}, id)
      assert Session.info(resumed).accounting["request_count"] == 1
      assert File.read!(Path.join(ctx.dir, id <> ".jsonl")) == bytes
      refute_receive {:model_http, _, _}, 20
      :ok = Session.close(resumed)
    end
  end

  defp structured_model_request do
    Map.merge(model_request(), %{
      "version" => 2,
      "response_schema" => %{
        "type" => "object",
        "properties" => %{
          "names" => %{"type" => "array", "maxItems" => 1, "items" => %{"type" => "string"}}
        },
        "required" => ["names"],
        "additionalProperties" => false
      }
    })
  end

  test "denied extension inference never dispatches or consumes shared quota", ctx do
    {base, _} = model_fixture(self())

    config =
      model_config(ctx.config, base)
      |> Map.merge(%{approval: :deny, budget: %{"version" => 1, "max_requests" => 1}})

    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid) == %{"status" => "denied", "value" => %{}}
    refute_receive {:model_http, _, _}, 100
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert :ok = Ipse.Extension.Projection.validate_events(events)
    assert Session.info(pid).accounting["request_count"] == 0
    assert {:ok, snapshot} = Ipse.Usage.Budget.saved(ctx.dir, Session.info(pid).id)
    assert snapshot["request_count"] == 0
  end

  test "expiry while syncing inference admission closes accounting before refusing dispatch",
       ctx do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"
    pid = start(%{ctx | config: model_config(ctx.config, base)})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", _}}, 3000
    owner = self()
    started = System.monotonic_time(:millisecond) - 118_000
    timer = Process.send_after(pid, :unused_fixture_deadline, 60_000)

    state =
      :sys.replace_state(pid, fn s ->
        %{s | extension_output_clock: %{started_ms: started, timer: timer}}
      end)

    :ok =
      :sys.install(state.journal_writer, {
        fn
          :waiting, {:in, {_, _, {:append, _, %{"type" => "request_admitted"}}}}, _ ->
            send(owner, {:admission_waiting, self()})

            receive do
              :release_admission -> :released
            after
              3500 -> :released
            end

          status, _, _ ->
            status
        end,
        :waiting
      })

    :erlang.trace_pattern(
      {Ipse.Session.Invocation, :begin_inference, 3},
      [{:_, [], [{:return_trace}]}],
      []
    )

    :erlang.trace(pid, true, [:call, {:tracer, self()}])

    try do
      :ok = Session.approve(pid, ref, true)
      assert_receive {:admission_waiting, writer}, 3000
      Process.sleep(max(started + 120_001 - System.monotonic_time(:millisecond), 0))
      send(writer, :release_admission)

      assert_receive {:trace, ^pid, :return_from, {Ipse.Session.Invocation, :begin_inference, 3},
                      {:reply, {:failed, %{"code" => "model_request_failed"}}, refused}},
                     3000

      assert refused.extension_model == nil
      assert [entry] = Map.values(refused.accounting.requests)
      assert entry.completion["outcome"] == "failed"
      assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
      assert_receive {:ipse, ^pid, {:done, _}}, 3000
      assert {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
      assert {:ok, _} = Ipse.Usage.restore(events, Session.info(pid).id)
    after
      Process.cancel_timer(timer)
      if Process.alive?(pid), do: :erlang.trace(pid, false, [:call])
      :erlang.trace_pattern({Ipse.Session.Invocation, :begin_inference, 3}, false, [])
    end
  end

  test "interactive refusal records no model dispatch or shared reservation", ctx do
    {base, _} = model_fixture(self())

    config =
      model_config(ctx.config, base) |> Map.put(:budget, %{"version" => 1, "max_requests" => 1})

    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", proposed}}, 3000
    assert proposed["request"] == model_request()
    :ok = Session.approve(pid, ref, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid)["status"] == "denied"
    refute_receive {:model_http, _, _}, 20
    assert Session.info(pid).accounting["request_count"] == 0
    {:ok, budget} = Ipse.Usage.Budget.saved(ctx.dir, Session.info(pid).id)
    assert budget["request_count"] == 0
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, []} = Session.restore_context(events)
  end

  test "child model approval can proceed inside an enclosing extension mutation lease", ctx do
    {base, server} = model_fixture(self(), wait: true)

    source = %{
      scope: "operator",
      path: Path.join(ctx.root, "children.json"),
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
            "allow_children" => true
          }
        ]
      }
    }

    {:ok, catalog} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(catalog, ctx.home)
    request = model_request()

    config =
      model_config(ctx.config, base)
      |> Map.merge(%{
        extensions: entries,
        parallel_model_calls: true,
        subagents: true,
        subagent_concurrency: 2,
        budget: %{"version" => 1, "max_requests" => 7},
        tool_args: %{"text" => "nested model fixture", "host_request" => request}
      })

    pid = start(%{ctx | config: config})
    :ok = Session.prompt(pid, "Exercise nested child inference approvals.")
    assert_receive {:ipse, ^pid, {:approval, group_ref, "delegate_parallel", _}}, 3000
    :ok = Session.approve(pid, group_ref, true)
    assert_receive {:ipse, ^pid, {:approval, tool_ref, tool_name, arguments}}, 3000
    assert String.ends_with?(tool_name, "/ext__sdk__echo")
    assert arguments["host_request"] == request
    :ok = Session.approve(pid, tool_ref, true)
    assert_receive {:ipse, ^pid, {:approval, model_ref, model_name, proposed}}, 3000
    assert String.ends_with?(model_name, "/extension:model.complete")
    assert proposed["request"] == request
    :ok = Session.approve(pid, model_ref, true)
    assert_receive {:model_http, _, _}, 3000
    assert_receive {:model_socket, _}, 1000
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 20
    send(server.pid, :respond)
    assert :ok = Task.await(server)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    {:ok, budget} = Ipse.Usage.Budget.saved(ctx.dir, Session.info(pid).id)
    assert budget["request_count"] == 7
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)

    assert Enum.count(
             events,
             &(&1["type"] == "delegation_approval" and &1["decision"] == "conflict_denied")
           ) == 1

    assert {:ok, _} = Session.restore_context(events)
  end

  test "explicit Ollama none is approved, sent on the wire and retained through idle resume",
       ctx do
    {base, server} = model_fixture(self())

    config =
      model_config(ctx.config, base) |> put_in([:profiles, "extract", "reasoning_effort"], "none")

    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", proposed}}, 3000
    assert proposed["execution"]["reasoning_effort"] == "none"
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert :ok = Task.await(server)
    assert_receive {:model_http, _headers, wire}, 1000
    assert wire["think"] === false
    assert wire["options"] == %{"num_predict" => 32}
    assert host_outcome(pid)["status"] == "ok"
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_model_request" and
                 &1["execution"]["reasoning_effort"] == "none")
           )

    assert {:ok, []} = Session.restore_context(events)
    assert :ok = Session.close(pid)
    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).phase == :idle
    assert Session.info(resumed).accounting["request_count"] == 1
    refute_receive {:model_http, _, _}, 20
  end

  test "extension and main model work share admission and retain refusal accounting", ctx do
    {base, server} = model_fixture(self())

    config =
      model_config(ctx.config, base)
      |> Map.merge(%{approval: :allow, budget: %{"version" => 1, "max_requests" => 1}})

    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid)["status"] == "ok"
    assert :ok = Task.await(server)
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000

    assert host_outcome(pid) == %{
             "status" => "failed",
             "value" => %{"code" => "model_request_failed"}
           }

    :ok = Session.prompt(pid, "This main request must also be refused before dispatch.")
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    refute_receive {:sdk_model, _, _}, 20
    assert {:ok, snapshot} = Ipse.Usage.Budget.saved(ctx.dir, Session.info(pid).id)
    assert snapshot["request_count"] == 1
    assert snapshot["refused_count"] == 2
    assert Session.info(pid).accounting["request_count"] == 3
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert :ok = Ipse.Extension.Projection.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
    id = Session.info(pid).id
    :ok = Session.close(pid)
    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).accounting["request_count"] == 3
    refute_receive {:sdk_model, _, _}, 20
  end

  test "rejected extension output remains metered with private response retained", ctx do
    {base, server} = model_fixture(self())
    config = model_config(ctx.config, base) |> Map.put(:approval, :allow)
    pid = start(%{ctx | config: config})
    :ok = host_command(pid, Map.put(model_request(), "max_output_bytes", 1))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert :ok = Task.await(server)
    assert host_outcome(pid) == %{"status" => "failed", "value" => %{"code" => "model_response"}}
    [record] = Session.info(pid).accounting["requests"]
    assert record["outcome"] == "completed"
    assert record["usage"]["counts"]["total_tokens"] == 10
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert Enum.any?(events, &(&1["type"] == "extension_model_response"))
    assert {:ok, []} = Session.restore_context(events)
  end

  test "extension overdraw retains observed provider usage and stops future admission", ctx do
    {base, server} = model_fixture(self())

    config =
      model_config(ctx.config, base)
      |> Map.merge(%{
        approval: :allow,
        budget: %{"version" => 1, "max_input_tokens" => 4, "reserve_input_tokens" => 2}
      })

    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert :ok = Task.await(server)
    assert host_outcome(pid)["status"] == "failed"
    [record] = Session.info(pid).accounting["requests"]
    assert record["outcome"] == "failed"
    assert record["usage"]["counts"]["input_tokens"] == 7
    {:ok, budget} = Ipse.Usage.Budget.saved(ctx.dir, Session.info(pid).id)
    assert budget["overdrawn"]
    assert budget["request_count"] == 1
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    {:ok, budget} = Ipse.Usage.Budget.saved(ctx.dir, Session.info(pid).id)
    assert budget["request_count"] == 1
    assert budget["refused_count"] == 1
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, []} = Session.restore_context(events)
    id = Session.info(pid).id
    :ok = Session.close(pid)
    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).phase == :idle
  end

  test "cancelling extension inference closes the actual HTTP connection and retains liability",
       ctx do
    {base, server} = model_fixture(self(), wait: true)

    config =
      model_config(ctx.config, base)
      |> Map.merge(%{approval: :allow, budget: %{"version" => 1, "max_requests" => 1}})

    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:model_http, _, _}, 3000
    assert_receive {:model_socket, socket}, 1000
    :ok = Session.cancel(pid)
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 3000)
    send(server.pid, :respond)
    assert :ok = Task.await(server)
    [record] = Session.info(pid).accounting["requests"]
    assert record["outcome"] == "cancelled"
    assert record["usage"]["quality"] == "unavailable"
    {:ok, snapshot} = Ipse.Usage.Budget.saved(ctx.dir, Session.info(pid).id)
    assert snapshot["request_count"] == 1
    assert snapshot["unknown_liability_count"] == 1
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert :ok = Ipse.Extension.Projection.validate_events(events)
    refute Enum.any?(events, &(&1["type"] == "extension_action_result"))
  end

  test "worker death stops extension inference without unmetered orphan work", ctx do
    {base, server} = model_fixture(self(), wait: true)
    config = model_config(ctx.config, base) |> Map.put(:approval, :allow)
    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:model_http, _, _}, 3000
    assert_receive {:model_socket, socket}, 1000
    os_pid = await_pid(ctx.pid_file)
    assert {:ok, %{exit_code: 0}} = Ipse.Runner.run("kill -KILL " <> os_pid, ctx.root)
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 3000)
    send(server.pid, :respond)
    assert :ok = Task.await(server)
    [record] = Session.info(pid).accounting["requests"]
    assert record["outcome"] == "cancelled"
    assert record["usage"]["quality"] == "unavailable"
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, []} = Session.restore_context(events)
  end

  test "abrupt session owner loss leaves unknown liability and inert resume", ctx do
    {base, server} = model_fixture(self(), wait: true)

    config =
      model_config(ctx.config, base)
      |> Map.merge(%{approval: :allow, budget: %{"version" => 1, "max_requests" => 1}})

    pid = start(%{ctx | config: config})
    id = Session.info(pid).id
    :ok = host_command(pid, model_request())
    assert_receive {:model_http, _, _}, 3000
    assert_receive {:model_socket, socket}, 1000
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 3000
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 3000)
    send(server.pid, :respond)
    assert :ok = Task.await(server)
    {:ok, budget} = Ipse.Usage.Budget.saved(ctx.dir, id)
    assert budget["request_count"] == 1
    assert budget["unsettled_count"] == 1
    {:ok, events} = Journal.load(ctx.dir, id)
    assert {:ok, _} = Session.restore_context(events)
    path = Path.join(ctx.dir, id <> ".jsonl")
    bytes = File.read!(path)
    calls = File.read!(ctx.called)
    resumed = start(%{ctx | config: config}, id)
    assert Session.info(resumed).phase == :idle
    assert Session.info(resumed).accounting["unknown_outcome_count"] == 1
    assert File.read!(path) == bytes
    assert File.read!(ctx.called) == calls
  end

  test "extension streaming framing can exceed64KiB while returned text remains bounded", ctx do
    prefix =
      String.duplicate(
        Jason.encode!(%{"done" => false, "message" => %{"content" => ""}}) <> "\n",
        2000
      )

    assert byte_size(prefix) > 65_536 and byte_size(prefix) < 1_048_576
    {base, server} = model_fixture(self(), prefix: prefix)
    config = model_config(ctx.config, base) |> Map.put(:approval, :allow)
    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert :ok = Task.await(server)
    assert host_outcome(pid)["status"] == "ok"
    assert host_outcome(pid)["value"]["text"] == "entities"
    refute Jason.encode!(host_outcome(pid)) =~ "private-thinking"
    [record] = Session.info(pid).accounting["requests"]
    assert record["outcome"] == "completed"
    assert record["usage"]["counts"]["total_tokens"] == 10
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, []} = Session.restore_context(events)
  end

  test "extension response-byte refusal remains a failed accounted attempt", ctx do
    {base, server} = model_fixture(self(), text: String.duplicate("x", 1_048_577))
    config = model_config(ctx.config, base) |> Map.put(:approval, :allow)
    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert :ok = Task.await(server)

    assert host_outcome(pid) == %{
             "status" => "failed",
             "value" => %{"code" => "model_request_failed"}
           }

    [record] = Session.info(pid).accounting["requests"]
    assert record["outcome"] == "failed"
    assert record["usage"]["quality"] == "unavailable"
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    refute Enum.any?(events, &(&1["type"] == "extension_model_response"))
    assert {:ok, []} = Session.restore_context(events)
  end

  test "extension request deadline stops slow provider work", ctx do
    {base, server} = model_fixture(self(), wait: true)
    config = model_config(ctx.config, base) |> Map.put(:approval, :allow)
    pid = start(%{ctx | config: config})
    :ok = host_command(pid, Map.put(model_request(), "timeout_ms", 1000))
    assert_receive {:model_http, _, _}, 3000
    assert_receive {:model_socket, socket}, 1000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 3000)
    send(server.pid, :respond)
    assert :ok = Task.await(server)
    assert host_outcome(pid)["status"] == "failed"
    assert host_outcome(pid)["value"]["code"] in ~w(model_timeout model_request_failed)
    [record] = Session.info(pid).accounting["requests"]
    assert record["outcome"] in ~w(failed cancelled)
    assert record["usage"]["quality"] == "unavailable"
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, []} = Session.restore_context(events)
  end

  test "model source and returned text corruption refuse before torn-tail repair", ctx do
    {base, server} = model_fixture(self())
    config = model_config(ctx.config, base) |> Map.put(:approval, :allow)
    pid = start(%{ctx | config: config})
    :ok = host_command(pid, model_request())
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert :ok = Task.await(server)
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)

    for corrupt <- [
          Enum.reject(events, &(&1["type"] == "extension_model_request")),
          Enum.reject(events, &(&1["type"] == "extension_model_response")),
          Enum.map(events, fn event ->
            if event["type"] == "extension_model_request",
              do: put_in(event, ["execution", "provider"], "openai"),
              else: event
          end),
          Enum.map(events, fn event ->
            if event["type"] == "extension_action_result" do
              outcome = put_in(event["outcome"], ["value", "text"], "forged")

              event
              |> Map.put("outcome", outcome)
              |> Map.put("outcome_sha256", Ipse.JSON.digest([outcome]))
            else
              event
            end
          end)
        ] do
      assert {:error, _} = Ipse.Usage.restore(corrupt, id)
      path = Path.join(ctx.dir, id <> ".jsonl")
      bytes = Enum.map_join(corrupt, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  config: config, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
               )

      assert File.read!(path) == bytes
    end

    path = Path.join(ctx.dir, id <> ".jsonl")
    bytes = Enum.map_join(events, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
    File.write!(path, bytes)
    changed = put_in(config, [:profiles, "extract", "model"], "changed")

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: changed, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
             )

    assert File.read!(path) == bytes
  end

  defp model_request,
    do: %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => "extract",
      "instruction" => "Extract entities only.",
      "input" => "Synthetic explicit input",
      "max_output_bytes" => 1024,
      "timeout_ms" => 5000
    }

  defp model_config(config, base) do
    Map.merge(config, %{
      provider: :openai,
      model: "main-fixture",
      api_key: "main-only-fixture",
      profiles: %{
        "extract" => %{
          "provider" => "ollama",
          "model" => "helper-fixture",
          "base_url" => base,
          "max_output_tokens" => 32
        }
      },
      max_output_tokens: 64
    })
  end

  defp model_fixture(owner, opts \\ []) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        case :gen_tcp.accept(listener, 5000) do
          {:ok, socket} ->
            {headers, payload} = model_http_request(socket, "")
            send(owner, {:model_http, headers, Jason.decode!(payload)})

            if opts[:wait] do
              send(owner, {:model_socket, socket})
              receive do: (:respond -> :ok)
            end

            body =
              (opts[:prefix] || "") <>
                Jason.encode!(%{
                  "model" => "helper-reported",
                  "done" => true,
                  "prompt_eval_count" => 7,
                  "eval_count" => 3,
                  "message" => %{
                    "content" => opts[:text] || "entities",
                    "thinking" => "private-thinking"
                  }
                }) <> "\n"

            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )

            :gen_tcp.close(socket)

          {:error, :closed} ->
            :ok
        end

        :gen_tcp.close(listener)
        :ok
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp model_http_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, model_http_body(socket, body, String.to_integer(size))}

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
        model_http_request(socket, buffer <> bytes)
    end
  end

  defp model_http_body(_, body, size) when byte_size(body) >= size, do: body

  defp model_http_body(socket, body, size) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
    model_http_body(socket, body <> bytes, size)
  end

  test "nonboolean extension host approvals deny and leave matching receipts", ctx do
    pid = start(ctx)

    put = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "denied",
      "expected_revision" => 0,
      "value" => %{"text" => "no"}
    }

    assert :ok = host_command(pid, put)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:state.put", _}}, 3000
    assert :ok = Session.approve(pid, ref, "no")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid)["status"] == "denied"
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_action_intent"))
    assert intent["approval"] == "denied"
    assert :ok = Ipse.Extension.Actions.validate_events(events)
  end

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
    assert :ok = Ipse.Extension.Actions.validate_events(events)
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
    assert :ok = Ipse.Extension.Projection.validate_events(events)
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
    assert :ok = Ipse.Extension.Projection.validate_events(events)
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
          Enum.reject(events, &(&1["type"] in Ipse.Extension.Actions.types())),
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
      {:ok, namespace} = Ipse.Extension.State.namespace(ident, scope, cwd, session)
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
      Ipse.Extension.State.namespace(
        hd(ctx.config.extensions).identity,
        "project",
        ctx.root,
        info.id
      )

    root = Path.join(ctx.home, "extension-state-v1")

    {:ok, _} =
      Ipse.Extension.State.execute(
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
             Ipse.Extension.Projection.validate_events(
               elem(Journal.load(ctx.dir, Session.info(pid).id), 1)
             )
  end

  test "pending extension question resumes inertly and only an explicit answer starts continuation",
       ctx do
    if System.get_env("IPSE_TEST_STDIO_PROBE") == "1" do
      probe =
        Ipse.Test.StdioProbe.start(
          [Process.whereis(Ipse.Sessions), Process.whereis(Ipse.Tasks)],
          "pending-extension-question-resume"
        )

      on_exit(fn -> Ipse.Test.StdioProbe.stop(probe) end)
    end

    pid = start(ctx)
    :ok = host_command(pid, question_request(%{"next" => "finish", "test_delay_ms" => 4000}))
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
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 20_000
    assert host_outcome(resumed)["status"] == "answered"
    assert length(String.split(File.read!(ctx.called), "\n", trim: true)) == 2
  end

  test "journal exhaustion preserves a pending extension question for diagnosis and handoff",
       ctx do
    ctx = %{ctx | config: Map.put(ctx.config, :journal, %{"max_record_bytes" => 32_768})}
    pid = start(ctx)
    :ok = host_command(pid, question_request())
    assert_receive {:ipse, ^pid, {:question, question, _}}, 5_000
    id = Session.info(pid).id
    calls = File.read!(ctx.called)

    :sys.replace_state(pid, fn state ->
      assert {:error, :journal_limit_reached} =
               Ipse.Journal.Writer.append(
                 state.journal_writer,
                 %{"type" => "padding", "value" => String.duplicate("x", 32_769)}
               )

      state
    end)

    monitor = Process.monitor(pid)
    assert catch_exit(Session.answer(pid, question, answers()))
    assert_receive {:DOWN, ^monitor, :process, ^pid, :journal_limit_reached}, 5_000
    assert File.read!(ctx.called) == calls
    path = Path.join(ctx.dir, id <> ".jsonl")
    bytes = File.read!(path)
    assert {:ok, events} = Journal.load(ctx.dir, id)
    assert List.last(events)["type"] == "journal_limit_reached"
    assert {:ok, _} = Session.restore_context(events)
    assert {:ok, _} = Ipse.Session.Saved.inspect_saved(ctx.dir, id)

    assert {:ok, _} =
             Ipse.Session.Saved.export_handoff(
               ctx.dir,
               id,
               "Ask the unanswered extension question again."
             )

    assert {:error, :journal_limit_reached} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: ctx.config, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
             )

    assert File.read!(path) == bytes
    assert File.read!(ctx.called) == calls
    unsealed = Enum.drop(events, -1)

    assert Enum.count(
             unsealed,
             &(&1["type"] in ~w(extension_action_intent extension_question))
           ) >= 2

    for {event, index} <- Enum.with_index(unsealed),
        event["type"] in ~w(extension_action_intent extension_question lifecycle_question_sources) do
      prefix = Enum.take(unsealed, index + 1)
      offset = prefix |> Enum.map(&(Jason.encode!(&1) <> "\n")) |> IO.iodata_length()

      receipt =
        Ipse.Journal.limit_receipt(
          Ipse.Journal.limits(),
          offset,
          length(prefix),
          "events"
        )

      assert {:ok, _} = Session.restore_context(prefix ++ [receipt])
    end

    damaged = List.replace_at(events, -1, Map.put(List.last(events), "event_count", 0))
    assert {:error, _} = Ipse.Extension.Actions.validate_events(damaged)
    assert {:error, _} = Session.restore_context(damaged)
  end

  test "diagnostic sink receipts preserve a pending question through repeated recovery", ctx do
    source = %{
      scope: "operator",
      path: Path.join(ctx.root, "trace.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "trace",
            "artifact" => "builtin:local-trace:1",
            "enabled" => true,
            "options" => %{"directory" => Path.join(ctx.root, "trace"), "retained_leases" => 8},
            "order" => 0,
            "lifetime" => "session"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => "builtin:local-trace:1",
            "capabilities" => ["observe.local"],
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }
    }

    {:ok, selected} = Config.resolve([source], [])
    {:ok, trace} = Registry.prepare(selected, ctx.home)

    config =
      ctx.config
      |> Map.put(:extensions, trace ++ ctx.config.extensions)
      |> Map.put(:observability, Map.put(Ipse.Observability.defaults(), "mode", "local"))

    ctx = %{ctx | config: config}

    if System.get_env("IPSE_TEST_STDIO_PROBE") == "1" do
      probe =
        Ipse.Test.StdioProbe.start(Process.whereis(Ipse.Sessions), "diagnostic-question-recovery")

      on_exit(fn -> Ipse.Test.StdioProbe.stop(probe) end)
    end

    pid = start(ctx)
    :ok = host_command(pid, question_request())
    assert_receive {:ipse, ^pid, {:question, question, _}}, 3000
    id = Session.info(pid).id
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 2000
    calls = File.read!(ctx.called)
    resumed = start(ctx, id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 2000
    assert File.read!(ctx.called) == calls
    {:ok, events} = Journal.load(ctx.dir, id)
    assert :ok = Ipse.Observability.validate_events(events, id)
    assert {:ok, _} = Session.restore_context(events)
    assert {:ok, _} = Ipse.Session.Saved.inspect_saved(ctx.dir, id)

    for type <- Ipse.Observability.types() do
      event = Enum.find(events, &(&1["type"] == type))

      if event do
        corrupted =
          if type == "diagnostic_sink_intent",
            do: put_in(event, ["policy", "mode"], "off"),
            else: Map.put(event, "resource_id", Ipse.Usage.id())

        damaged = Enum.map(events, &if(&1 == event, do: corrupted, else: &1))
        assert {:error, _} = Ipse.Extension.Actions.validate_events(damaged)
        assert {:error, _} = Session.restore_context(damaged)
      end
    end

    assert {:ok, _} =
             Ipse.Session.Saved.export_handoff(
               ctx.dir,
               id,
               "Inspect the unanswered synthetic question."
             )

    :ok = Session.answer(resumed, question, answers())
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 3000
    close_result = Session.close(resumed)

    if close_result != :ok and System.get_env("IPSE_TEST_STDIO_PROBE") == "1" do
      Ipse.Test.StdioProbe.trace_files(Path.join(ctx.root, "trace"))
    end

    :ok = close_result
    again = start(ctx, id)
    assert Session.info(again).phase == :idle
    assert {:ok, _} = Ipse.Session.Saved.inspect_saved(ctx.dir, id)

    assert {:ok, _} =
             Ipse.Session.Saved.export_handoff(
               ctx.dir,
               id,
               "Continue only after reviewing the saved answer."
             )

    :ok = Session.close(again)
  end

  test "native extension question and prompt subscriptions preserve their source checkpoint",
       ctx do
    notify = notification_entry(ctx)

    config =
      ctx.config
      |> Map.put(:extensions, notify ++ ctx.config.extensions)
      |> Map.put(:tool_args, %{"text" => "question", "host_request" => question_request()})

    ctx = %{ctx | config: config}
    pid = run_tool(ctx)
    assert_receive {:ipse, ^pid, {:question, question, _}}, 3000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)
    assert Enum.any?(events, &(&1["type"] == "lifecycle_question_sources"))
    assert :ok = Ipse.Extension.Subscriptions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)

    damaged =
      Enum.map(events, fn event ->
        if event["type"] == "lifecycle_question_sources",
          do: Map.put(event, "question_id", Ipse.Usage.id()),
          else: event
      end)

    assert {:error, _} = Ipse.Extension.Actions.validate_events(damaged)
    assert {:error, _} = Session.restore_context(damaged)
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 2000
    resumed = start(ctx, id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 2000
    :ok = Session.answer(resumed, question, answers())
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 3000
    :ok = Session.close(resumed)
    assert {:ok, _} = Ipse.Session.Saved.inspect_saved(ctx.dir, id)
  end

  defp notification_entry(ctx) do
    source = Path.join(ctx.root, "notifier")
    File.mkdir_p!(Path.join(source, "ebin"))
    module = "Independent.Notify#{System.unique_integer([:positive])}"

    subscriptions = [
      %{
        "id" => "prompt",
        "event" => "prompt.effective_committed",
        "event_version" => 1,
        "view" => "metadata",
        "mode" => "notify",
        "required" => true
      }
    ]

    code = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => ["event.notify"], "subscriptions" => #{inspect(subscriptions)}}
      def init(options), do: {:ok, options}
      def handle("event.notify", payload, state), do:
        {:ok, %{"api_version" => 1, "kind" => "ack", "delivery_id" => payload["delivery_id"], "event_id" => payload["event"]["event_id"]}, state}
    end
    """

    file = Path.join(source, "fixture.ex")
    File.write!(file, code)

    {output, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(source, "ebin"), file],
        stderr_to_stdout: true
      )

    assert status == 0, output
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    manifest =
      ctx.manifest
      |> Map.drop(["exports"])
      |> Map.merge(%{
        "id" => "fixture/notifier",
        "entrypoint" => module,
        "capabilities" => ["event.notify"],
        "subscriptions" => subscriptions,
        "files" =>
          Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
            bytes = File.read!(Path.join(source, path))
            %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
          end)
      })

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    {:ok, artifact} = Artifact.import(source, Path.join(ctx.home, "extensions/artifacts"))

    data = %{
      "extensions" => [
        %{
          "instance" => "notifier",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 0,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => ["event.notify"],
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, selected} =
      Config.resolve(
        [%{scope: "operator", path: Path.join(ctx.root, "notify.json"), data: data}],
        []
      )

    {:ok, entries} = Registry.prepare(selected, ctx.home)
    entries
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
    assert :ok = Ipse.Extension.Projection.validate_events(events)
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
    assert :ok = Ipse.Extension.Projection.validate_events(events)
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
    assert :ok = Ipse.Extension.Projection.validate_events(prefix)
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

  defp tool_request(name, args, timeout \\ 1000),
    do: %{"op" => "tool.call", "name" => name, "arguments" => args, "timeout_ms" => timeout}

  test "workflow writes use full separate approval and pinned workspace context receipts", ctx do
    pid = start(ctx)
    request = tool_request("write", %{"path" => "workflow.txt", "content" => "approved"})
    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:tool.call", proposed}}, 3000
    assert proposed["request"] == request
    refute File.exists?(Path.join(ctx.root, "workflow.txt"))
    :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert File.read!(Path.join(ctx.root, "workflow.txt")) == "approved"
    assert host_outcome(pid)["status"] == "ok"
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_action_intent"))
    snapshot = Enum.find(events, &(&1["type"] == "workspace_context_snapshot"))["snapshot"]
    assert intent["context_sha256"] == Ipse.JSON.digest([snapshot])
    assert intent["namespace"] == nil
    assert :ok = Ipse.Extension.Projection.validate_events(events)
  end

  test "denied workflow writes never execute and reads need no mutation approval", ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :approval, :deny)})
    :ok = host_command(pid, tool_request("write", %{"path" => "denied.txt", "content" => "no"}))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid)["status"] == "denied"
    refute File.exists?(Path.join(ctx.root, "denied.txt"))
    File.write!(Path.join(ctx.root, "read.txt"), "read fixture")
    :ok = host_command(pid, tool_request("read", %{"path" => "read.txt"}))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid)["value"]["text"] =~ "read fixture"
    :ok = host_command(pid, tool_request("read", %{"path" => "missing.txt"}))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid) == %{"status" => "failed", "value" => %{"reason" => "tool_failed"}}
    File.write!(Path.join(ctx.root, "large-read.txt"), String.duplicate("a", 5000))
    :ok = host_command(pid, tool_request("read", %{"path" => "large-read.txt"}))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert host_outcome(pid) == %{"status" => "failed", "value" => %{"reason" => "result_limit"}}
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 20
  end

  test "new nested instructions stop workflow before write approval or tool intent", ctx do
    File.mkdir_p!(Path.join(ctx.root, "nested"))

    File.write!(
      Path.join(ctx.root, "nested/AGENTS.md"),
      "Review these synthetic instructions before writes."
    )

    pid = start(ctx)

    request =
      tool_request("write", %{"path" => "nested/result.txt", "content" => "no implicit retry"})

    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 20
    refute File.exists?(Path.join(ctx.root, "nested/result.txt"))
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    refute Enum.any?(events, &(&1["type"] == "extension_action_intent"))
    assert Enum.any?(Session.info(pid).context["sources"], &(&1["kind"] == "nested"))
    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:tool.call", _}}, 3000
    :ok = Session.approve(pid, ref, false)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    refute File.exists?(Path.join(ctx.root, "nested/result.txt"))
  end

  test "timed-out workflow shell stops without callback continuation and kills descendants",
       ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :approval, :allow)})

    request =
      tool_request(
        "shell",
        %{"command" => "(sleep 0.5; printf bad > workflow-orphan) & wait"},
        60
      )

    :ok = host_command(pid, request)
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    assert length(String.split(File.read!(ctx.called), "\n", trim: true)) == 1
    Process.sleep(600)
    refute File.exists?(Path.join(ctx.root, "workflow-orphan"))
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    result = Enum.find(events, &(&1["type"] == "extension_action_result"))
    assert result["outcome"]["status"] == "unknown"
    assert :ok = Ipse.Extension.Projection.validate_events(events)
  end

  test "workflow shell preserves completion status and refuses incomplete output", ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :approval, :allow)})
    :ok = host_command(pid, tool_request("shell", %{"command" => "printf fixture; exit 7"}))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000

    assert host_outcome(pid)["value"] == %{
             "text" => "fixture",
             "exit_code" => 7,
             "output_bytes" => 7,
             "output_truncated" => false
           }

    :ok =
      host_command(
        pid,
        tool_request("shell", %{"command" => "head -c 5000 /dev/zero | tr '\\000' x"})
      )

    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)

    assert List.last(Enum.filter(events, &(&1["type"] == "extension_action_result")))["outcome"][
             "status"
           ] == "unknown"

    :ok = host_command(pid, tool_request("shell", %{"command" => "head -c 3000 /dev/zero"}))
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
  end

  test "cancelling a workflow kills its linked tool task and actual shell group", ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :approval, :allow)})

    command =
      "printf '%s' $$ > workflow-shell-pid; (sleep 1; printf bad > workflow-cancelled) & wait"

    :ok = host_command(pid, tool_request("shell", %{"command" => command}, 5000))
    shell_pid = await_pid(Path.join(ctx.root, "workflow-shell-pid"))
    :ok = Session.cancel(pid)
    await_exit(shell_pid, ctx.root)
    Process.sleep(1100)
    refute File.exists?(Path.join(ctx.root, "workflow-cancelled"))
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert Enum.any?(events, &(&1["type"] == "extension_action_intent"))
    refute Enum.any?(events, &(&1["type"] == "extension_action_result"))
    assert :ok = Ipse.Extension.Projection.validate_events(events)
  end

  test "workflow close cannot confirm cleanup while its nested shell supervisor is stopped",
       ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :approval, :allow)})
    command = "printf '%s' $$ > nested-shell-pid; sleep 120 & wait"
    :ok = host_command(pid, tool_request("shell", %{"command" => command}, 30_000))
    shell = await_pid(Path.join(ctx.root, "nested-shell-pid"))
    coordinator = :sys.get_state(pid).task.pid
    {:links, links} = Process.info(coordinator, :links)

    [port] =
      for child <- links,
          is_pid(child),
          {:links, child_links} <- [Process.info(child, :links)],
          port <- child_links,
          is_port(port),
          do: port

    {:os_pid, helper} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(helper)])

    try do
      assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(pid)
    after
      System.cmd("kill", ["-KILL", Integer.to_string(helper)], stderr_to_stdout: true)
    end

    await_exit(shell, ctx.root)
  end

  test "unsupported workflow tools, escaped paths and altered context receipts never bypass policy",
       ctx do
    pid = start(%{ctx | config: Map.put(ctx.config, :approval, :allow)})

    for request <- [
          tool_request("delegate", %{}),
          tool_request("write", %{"path" => "../escape.txt", "content" => "no"})
        ] do
      :ok = host_command(pid, request)
      assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    end

    :ok = host_command(pid, tool_request("write", %{"path" => "good.txt", "content" => "one"}))
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)

    corrupted =
      Enum.map(events, fn event ->
        if event["type"] in Ipse.Extension.Actions.types(),
          do: Map.put(event, "context_sha256", String.duplicate("e", 64)),
          else: event
      end)

    bytes = Enum.map_join(corrupted, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
    path = Path.join(ctx.dir, id <> ".jsonl")
    File.write!(path, bytes)

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: ctx.config, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
             )

    assert File.read!(path) == bytes
    assert File.read!(Path.join(ctx.root, "good.txt")) == "one"
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
