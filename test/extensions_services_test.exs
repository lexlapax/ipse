defmodule Ipse.Extensions.ServicesTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Services, Catalog, Config, Registry, Store}

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-services-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    descriptor = %{
      "id" => "query",
      "description" => "Synthetic typed retrieval",
      "arguments_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "text" => %{"type" => "string"},
          "wait" => %{"type" => "boolean"},
          "host_call" => %{"type" => "boolean"}
        },
        "required" => ["text"]
      },
      "result_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"text" => %{"type" => "string"}, "source_id" => %{"type" => "string"}},
        "required" => ~w(text source_id)
      }
    }

    requires = %{
      "version" => 1,
      "services" => [
        Map.merge(Map.drop(descriptor, ~w(id description)), %{
          "alias" => "search",
          "contract" => 1
        })
      ]
    }

    target_exports = Map.put(Catalog.empty(), "services", [descriptor])

    command =
      descriptor |> Map.put("id", "compose") |> Map.put("result_schema", %{"type" => "object"})

    caller_exports = target_exports |> Map.put("commands", [command])
    caller_caps = ~w(invoke.command invoke.service host.actions host.services)
    caller_marker = Path.join(root, "caller-loaded")
    target_marker = Path.join(root, "target-loaded")
    target_pid = Path.join(root, "target-pid")
    called = Path.join(root, "target-payload")
    caller_module = "Independent.ServiceCaller#{System.unique_integer([:positive])}"
    target_module = "Independent.ServiceTarget#{System.unique_integer([:positive])}"

    caller_code = """
    defmodule #{caller_module} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(caller_marker)}, "loaded"); :ok)
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caller_caps)}, "exports" => #{inspect(caller_exports)}, "requires" => #{inspect(requires)}}
      def init(options), do: {:ok, options}
      def handle("host.actions", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
      def handle(_, payload, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call",
        "request" => %{"op" => "service.call", "alias" => "search", "arguments" => payload["arguments"], "checkpoint" => %{"next" => "finish"}}}, state}
    end
    """

    target_code = """
    defmodule #{target_module} do
      @behaviour Ipse.Extension
      @on_load :loaded
      def loaded, do: (File.write!(#{inspect(target_marker)}, "loaded"); :ok)
      def describe, do: %{"sdk" => 1, "capabilities" => ["invoke.service"], "exports" => #{inspect(target_exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.service", payload, state) do
        File.write!(#{inspect(called)}, Jason.encode!(payload))
        File.write!((#{inspect(target_pid)}) <> ".ready-" <> System.pid(), System.pid()); File.rename!((#{inspect(target_pid)}) <> ".ready-" <> System.pid(), #{inspect(target_pid)})
        if payload["arguments"]["wait"], do: Process.sleep(:infinity)
        result = if payload["arguments"]["host_call"],
          do: %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "tool.call", "name" => "write", "arguments" => %{"path" => "unapproved", "content" => "bad"}, "timeout_ms" => 1000}},
          else: %{"api_version" => 1, "kind" => "result", "value" => %{"text" => "retrieved: " <> payload["arguments"]["text"], "source_id" => "fixture:one"}}
        {:ok, result, state}
      end
    end
    """

    home = Path.join(root, "home")

    caller =
      build(
        root,
        home,
        "caller",
        caller_module,
        caller_code,
        caller_exports,
        caller_caps,
        requires
      )

    target =
      build(
        root,
        home,
        "target",
        target_module,
        target_code,
        target_exports,
        ["invoke.service"],
        Services.empty()
      )

    for file <- [caller_marker, target_marker, target_pid, called], do: File.rm(file)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      artifact_root: root,
      home: home,
      caller: caller,
      target: target,
      descriptor: descriptor,
      caller_marker: caller_marker,
      target_marker: target_marker,
      target_pid: target_pid,
      called: called
    }
  end

  defp build(root, home, id, module, code, exports, capabilities, requires) do
    source = Path.join(root, id)
    File.mkdir_p!(Path.join(source, "ebin"))
    file = Path.join(source, "fixture.ex")
    File.write!(file, code)

    arguments = [
      "-pa",
      Application.app_dir(:ipse, "ebin"),
      "-pa",
      Application.app_dir(:jason, "ebin"),
      "-o",
      Path.join(source, "ebin"),
      file
    ]

    {output, status} =
      System.cmd(System.find_executable("elixirc"), arguments, stderr_to_stdout: true)

    assert status == 0, output
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/service_#{id}",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "exports" => exports,
      "requires" => requires,
      "capabilities" => capabilities,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
          bytes = File.read!(Path.join(source, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    {:ok, installed} = Store.import(source, Path.join(home, "extensions/artifacts"))
    installed
  end

  setup ctx do
    for path <- [ctx.caller_marker, ctx.target_marker, ctx.target_pid, ctx.called],
        do: File.rm(path)

    root = Path.join(ctx.artifact_root, "session-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    binding = %{
      "caller" => "client",
      "alias" => "search",
      "target" => "retrieval",
      "artifact" => ctx.target.digest,
      "service" => "query"
    }

    instances =
      Enum.with_index([{"client", ctx.caller}, {"retrieval", ctx.target}], 1)
      |> Enum.map(fn {{id, artifact}, order} ->
        %{
          "instance" => id,
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{},
          "order" => order,
          "lifetime" => "persistent"
        }
      end)

    trust =
      Enum.map([ctx.caller, ctx.target], fn artifact ->
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false,
          "service_bindings" => if(artifact.digest == ctx.caller.digest, do: [binding], else: [])
        }
      end)

    source = %{
      scope: "operator",
      path: Path.join(root, "operator.json"),
      data: %{"extensions" => instances, "extension_trust" => trust}
    }

    {:ok, selections} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selections, ctx.home)

    config = %{
      provider: :demo,
      model: "scripted",
      home: ctx.home,
      approval: :ask,
      extensions: entries
    }

    %{
      root: root,
      dir: Path.join(root, "state"),
      source: source,
      selections: selections,
      entries: entries,
      binding: binding,
      config: config
    }
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

  test "inert requirements resolve reviewed target identity without loading either artifact",
       ctx do
    refute File.exists?(ctx.caller_marker)
    refute File.exists?(ctx.target_marker)
    [caller, target] = ctx.entries

    assert caller.identity["services"] == [
             %{
               "alias" => "search",
               "instance" => "retrieval",
               "name" => "ext__retrieval__query",
               "contract" => 1,
               "target_sha256" => Ipse.JSON.digest([target.identity])
             }
           ]

    assert :ok = Registry.revalidate(ctx.config)
    assert Services.resolve(ctx.entries) == {:ok, ctx.entries}
  end

  test "missing targets, bindings, schemas and cycles refuse before executable activation", ctx do
    [caller, target] = ctx.entries
    assert {:error, _} = Services.resolve([%{caller | bindings: []}, target])
    assert {:error, _} = Services.resolve([caller])

    changed =
      put_in(caller.requires, ["services", Access.at(0), "result_schema"], %{"type" => "object"})

    caller_bad = %{
      caller
      | requires: changed,
        identity: Map.put(caller.identity, "requires_sha256", Services.digest(changed))
    }

    assert {:error, _} = Services.resolve([caller_bad, target])

    back = %{
      "version" => 1,
      "services" => [
        Map.merge(Map.drop(ctx.descriptor, ~w(id description)), %{
          "alias" => "back",
          "contract" => 1
        })
      ]
    }

    target_bad = %{
      target
      | requires: back,
        identity:
          target.identity
          |> Map.put("capabilities", ~w(invoke.service host.actions host.services))
          |> Map.put("requires_sha256", Services.digest(back)),
        bindings: [
          %{
            "caller" => "retrieval",
            "alias" => "back",
            "target" => "client",
            "artifact" => ctx.caller.digest,
            "service" => "query"
          }
        ]
    }

    assert {:error, _} = Services.resolve([caller, target_bad])
    refute File.exists?(ctx.target_marker)
    refute File.exists?(ctx.caller_marker)
  end

  test "operator binding declarations are closed and project text cannot grant a route", ctx do
    assert Services.validate_bindings([ctx.binding])
    refute Services.validate_bindings([ctx.binding, ctx.binding])
    refute Services.validate_bindings([Map.put(ctx.binding, "extra", true)])
    project = %{ctx.source | scope: "project"}
    assert {:error, _} = Config.resolve([project], [])
    assert {:error, _} = Services.validate_requirements(%{"version" => 2, "services" => []}, [])

    request = %{
      "op" => "service.call",
      "alias" => "unknown",
      "arguments" => %{"text" => "query"},
      "checkpoint" => %{}
    }

    assert {:error, _} = Services.lookup(ctx.config, hd(ctx.entries).identity, request)
    request = Map.put(request, "alias", "search")

    changed =
      Enum.map(ctx.entries, fn entry ->
        if entry.identity["instance"] == "retrieval",
          do: put_in(entry, [:identity, "source_sha256"], String.duplicate("e", 64)),
          else: entry
      end)

    assert {:error, _} =
             Services.lookup(%{extensions: changed}, hd(ctx.entries).identity, request)
  end

  test "owned service jobs return typed value and provenance with zero model requests", ctx do
    pid = start(ctx)
    :ok = Session.invoke_export(pid, :command, "ext__client__compose", %{"text" => "query"})
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    info = Session.info(pid)
    outcome = info.extension_result["value"]
    assert outcome["status"] == "ok"

    assert outcome["value"]["result"] == %{
             "text" => "retrieved: query",
             "source_id" => "fixture:one"
           }

    assert outcome["value"]["service"]["artifact_sha256"] == ctx.target.digest
    assert info.accounting["request_count"] == 0
    {:ok, events} = Journal.load(ctx.dir, info.id)
    assert :ok = Ipse.Extensions.Projection.validate_events(events)
    intent = Enum.find(events, &(&1["type"] == "extension_action_intent"))
    payload = Jason.decode!(File.read!(ctx.called))
    assert payload["invocation_id"] == intent["operation_id"]
    assert payload["parent_invocation_id"] == intent["parent_invocation_id"]
    assert payload["service_contract"] == 1
    refute Enum.any?(events, &(&1["type"] == "message"))
    :ok = Session.close(pid)
    File.rm!(ctx.caller_marker)
    File.rm!(ctx.target_marker)
    path = Path.join(ctx.dir, info.id <> ".jsonl")
    before = File.read!(path)
    resumed = start(ctx, info.id)
    assert Session.info(resumed).extension_result == info.extension_result
    refute File.exists?(ctx.caller_marker)
    refute File.exists?(ctx.target_marker)
    assert File.read!(path) == before
  end

  test "value-service replies cannot escalate into host actions", ctx do
    pid = start(ctx)

    :ok =
      Session.invoke_export(pid, :command, "ext__client__compose", %{
        "text" => "query",
        "host_call" => true
      })

    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    refute File.exists?(Path.join(ctx.root, "unapproved"))
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert Enum.count(events, &(&1["type"] == "extension_action_intent")) == 1
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
  end

  test "owner cancellation kills the actual service VM and never replays its unfinished call",
       ctx do
    pid = start(ctx)

    :ok =
      Session.invoke_export(pid, :command, "ext__client__compose", %{
        "text" => "query",
        "wait" => true
      })

    actual = await_pid(ctx.target_pid)
    :ok = Session.cancel(pid)
    await_exit(actual, ctx.root)
    id = Session.info(pid).id
    :ok = Session.close(pid)
    File.rm!(ctx.target_marker)
    resumed = start(ctx, id)
    assert Session.info(resumed).phase == :idle
    refute File.exists?(ctx.target_marker)
  end

  test "altered service provenance and deleted job receipts refuse before tail repair", ctx do
    pid = start(ctx)
    :ok = Session.invoke_export(pid, :command, "ext__client__compose", %{"text" => "query"})
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)

    for corrupted <- [
          Enum.reject(events, &(&1["type"] in Ipse.Extensions.Actions.types())),
          Enum.map(events, fn event ->
            if event["type"] == "extension_action_result" do
              value =
                put_in(
                  event["outcome"],
                  ["value", "service", "artifact_sha256"],
                  String.duplicate("e", 64)
                )

              event
              |> Map.put("outcome", value)
              |> Map.put("outcome_sha256", Ipse.JSON.digest([value]))
            else
              event
            end
          end)
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

  defp await_pid(path, attempts \\ 150)
  defp await_pid(_, 0), do: flunk("service worker did not start")

  defp await_pid(path, attempts) do
    case File.read(path) do
      {:ok, pid} ->
        pid

      _ ->
        Process.sleep(20)
        await_pid(path, attempts - 1)
    end
  end

  defp await_exit(pid, cwd, attempts \\ 150)
  defp await_exit(_, _, 0), do: flunk("service worker survived cancellation")

  defp await_exit(pid, cwd, attempts) do
    assert Regex.match?(~r/\A[0-9]+\z/, pid)
    {:ok, result} = Ipse.Runner.run("kill -0 " <> pid, cwd, timeout_ms: 1000, output_limit: 0)

    if result.exit_code == 0,
      do:
        (
          Process.sleep(20)
          await_exit(pid, cwd, attempts - 1)
        )
  end
end
