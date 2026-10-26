defmodule Ipse.Extension.ContributionsTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.Context, as: ExtensionContext
  alias Ipse.Extension.Config
  alias Ipse.Extension.Registry
  alias Ipse.Extension.Artifact
  alias Ipse.Extension.Catalog
  alias Ipse.Extension.Actions

  defmodule Model do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:context_request, messages})

      {:ok,
       %{
         "role" => "assistant",
         "content" => "fixture answer",
         "provider_data" => %{"native" => "synthetic continuation"}
       }, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-contributions-#{Ipse.Usage.id()}")
    source = Path.join(root, "artifact")
    File.mkdir_p!(Path.join(source, "ebin"))
    module = "Independent.Contributions#{System.unique_integer([:positive])}"
    marker = Path.join(root, "initialized")
    capabilities = ~w(invoke.command host.actions host.context host.tools)

    exports =
      Map.put(Catalog.empty(), "commands", [
        %{
          "id" => "publish",
          "description" => "Synthetic context fixture",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["mode"],
            "properties" => %{
              "mode" => %{"type" => "string", "enum" => ~w(assertion receipt invalid clear hang)}
            }
          },
          "result_schema" => %{"type" => "object"}
        }
      ])

    code = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options) do
        File.write!(#{inspect(marker)}, "initialized\n", [:append])
        {:ok, options}
      end
      def handle("invoke.command", payload, state) do
        mode = payload["arguments"]["mode"]
        state = Map.put(state, "mode", mode)
        if mode in ["receipt", "invalid"] do
          {:ok, call(%{"op" => "tool.call", "name" => "read", "arguments" => %{"path" => "evidence.txt"}, "timeout_ms" => 1000}), Map.put(state, "phase", "read")}
        else
          items = if mode == "clear", do: [], else: [item(%{"kind" => "assertion", "uri" => "fixture:note"}, "literal evidence")]
          {:ok, call(%{"op" => "context.publish", "items" => items}), Map.put(state, "phase", "published")}
        end
      end
      def handle("host.actions", payload, %{"phase" => "read"} = state) do
        source = %{"kind" => "receipt", "operation_id" => payload["operation_id"], "path" => ["text"]}
        text = if state["mode"] == "invalid", do: "invented evidence", else: "literal evidence"
        {:ok, call(%{"op" => "context.publish", "items" => [item(source, text)]}), Map.put(state, "phase", "published")}
      end
      def handle("host.actions", payload, state) do
        if state["mode"] == "hang", do: Process.sleep(:infinity)
        {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
      end
      defp item(source, text), do: %{"id" => "note", "version" => "1", "text" => text, "priority" => 10, "source" => source}
      defp call(request), do: %{"api_version" => 1, "kind" => "host_call", "request" => request}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, code)
    arguments = ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(source, "ebin"), file]

    {output, status} =
      System.cmd(System.find_executable("elixirc"), arguments, stderr_to_stdout: true)

    assert status == 0, output
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/contributions",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
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
        Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
          bytes = File.read!(Path.join(source, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    home = Path.join(root, "home")
    {:ok, artifact} = Artifact.import(source, Path.join(home, "extensions/artifacts"))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: artifact, home: home, artifact_root: root, marker: marker}
  end

  setup ctx do
    root = Path.join(ctx.artifact_root, "session-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "evidence.txt"), "recorded literal evidence\n")
    File.rm(ctx.marker)

    source = %{
      scope: "operator",
      path: "/fixture/operator.json",
      data: %{
        "extensions" => [
          %{
            "instance" => "notes",
            "artifact" => ctx.artifact.digest,
            "enabled" => true,
            "options" => %{},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => ctx.artifact.digest,
            "capabilities" => ctx.artifact.manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }
    }

    {:ok, selections} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selections, ctx.home)

    config = %{
      provider: :ollama,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: ctx.home,
      compact: false,
      approval: :deny,
      extensions: entries
    }

    %{
      root: root,
      dir: Path.join(root, "sessions"),
      config: config,
      identity: hd(entries).identity
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

  defp invoke(pid, mode) do
    assert :ok = Session.invoke_export(pid, :command, "ext__notes__publish", %{"mode" => mode})
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
  end

  defp start_legacy(ctx) do
    pid = start(ctx)
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    {:ok, [first | rest]} = Journal.load(ctx.dir, id)
    first = update_in(first["metadata"], &Map.delete(&1, "reference_layout"))

    File.write!(
      Path.join(ctx.dir, id <> ".jsonl"),
      Enum.map_join([first | rest], "\n", &Jason.encode!/1) <> "\n"
    )

    start(ctx, id)
  end

  test "assertions remain attributed data and model requests cache exact snapshots", ctx do
    pid = start(ctx)
    invoke(pid, "assertion")
    assert Session.info(pid).accounting["request_count"] == 0
    assert Session.diagnostics(pid)["extension_context"]["items"] == 1
    refute inspect(Session.diagnostics(pid)) =~ "literal evidence"
    assert :ok = Session.prompt(pid, "original operator request")
    assert_receive {:context_request, [system, admitted | messages]}, 3000
    assert [user, reference] = messages
    refute admitted["content"] =~ "literal evidence"
    assert Ipse.Session.Reference.reference?(reference)
    assert reference["role"] == "user"
    assert reference["content"] =~ "Assertions are unverified"
    assert reference["content"] =~ "literal evidence"
    refute system["content"] =~ "literal evidence"
    assert user == %{"role" => "user", "content" => "original operator request"}
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.dir, id)
    assert {:ok, state} = Actions.restore(events)
    [item] = state.contributions["notes"]
    assert item["provenance"]["source_action_sha256"] == nil
    assert item["source"]["kind"] == "assertion"
    snapshot = Enum.find(events, &(&1["type"] == "extension_context_snapshot"))
    assert snapshot["content"] == ExtensionContext.render(state.contributions)
    assert :ok = Session.close(pid)
    File.rm!(ctx.marker)
    bytes = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
    resumed = start(ctx, id)
    assert Session.diagnostics(resumed)["extension_context"]["items"] == 1
    refute File.exists?(ctx.marker)
    assert bytes == File.read!(Path.join(ctx.dir, id <> ".jsonl"))

    assert {:ok, restored_messages} = Session.restore_context(events)

    assert restored_messages |> List.last() |> Map.get("provider_data") == %{
             "native" => "synthetic continuation"
           }
  end

  test "receipt excerpts bind successful action provenance and refuse invented text", ctx do
    pid = start(ctx)
    invoke(pid, "receipt")
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, state} = Actions.restore(events)
    [item] = state.contributions["notes"]

    read =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "tool.call")
      )

    assert item["provenance"]["source_action_sha256"] == Ipse.JSON.digest([read])
    assert item["source"]["operation_id"] == read["operation_id"]
    invoke(pid, "invalid")

    assert Session.info(pid).extension_result["value"] == %{
             "status" => "failed",
             "value" => %{"reason" => "context_refused"}
           }

    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, next} = Actions.restore(events)
    assert next.contributions == %{}
    assert Session.diagnostics(pid)["extension_context"]["items"] == 0
    refute ExtensionContext.render(next.contributions) =~ "invented evidence"

    replacement =
      Enum.find_index(
        Enum.reverse(events),
        &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "context.publish")
      )

    cut = length(events) - replacement
    assert {:ok, interrupted} = Actions.restore(Enum.take(events, cut))
    assert interrupted.action["request"]["op"] == "context.publish"
    assert interrupted.contributions == %{}
  end

  test "legacy sessions keep mutable admission reference placement and failed-replacement behavior",
       ctx do
    pid = start_legacy(ctx)
    invoke(pid, "assertion")
    assert :ok = Session.prompt(pid, "legacy request")
    assert_receive {:context_request, [system, reference, user]}, 3000
    assert reference["content"] =~ "literal evidence"
    refute system["content"] =~ "literal evidence"
    assert user["content"] == "legacy request"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    invoke(pid, "invalid")
    assert Session.diagnostics(pid)["extension_context"]["items"] == 1
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, state} = Actions.restore(events)
    assert state.contributions["notes"] != nil
    refute Enum.any?(events, &(&1["type"] == "reference_admitted"))

    replacement =
      Enum.find_index(
        Enum.reverse(events),
        &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "context.publish")
      )

    assert {:ok, interrupted} = Actions.restore(Enum.take(events, length(events) - replacement))
    assert interrupted.contributions["notes"] != nil
  end

  test "clear replaces only current context and fresh sessions inherit none", ctx do
    pid = start(ctx)
    invoke(pid, "assertion")
    fresh = start(ctx)
    assert Session.diagnostics(fresh)["extension_context"]["items"] == 0
    invoke(pid, "clear")
    assert Session.diagnostics(pid)["extension_context"]["items"] == 0
    assert :ok = Session.prompt(pid, "after clear")
    assert_receive {:context_request, [system | _]}, 3000
    refute system["content"] =~ "literal evidence"
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, %{contributions: %{}}} = Actions.restore(events)
    assert Jason.encode!(events) =~ "literal evidence"
  end

  test "closed contracts, caller isolation, deterministic order and global byte bounds", ctx do
    item = %{
      "id" => "one",
      "version" => "v1",
      "text" => "text",
      "priority" => 1,
      "source" => %{"kind" => "assertion", "uri" => nil}
    }

    request = %{"op" => "context.publish", "items" => [item]}
    assert :ok = ExtensionContext.validate(request)

    for bad <- [
          Map.put(request, "scope", "operator"),
          put_in(request, ["items"], [item, item]),
          put_in(request, ["items", Access.at(0), "priority"], 101),
          put_in(request, ["items", Access.at(0), "source", "kind"], "verified")
        ] do
      assert {:error, _} = ExtensionContext.validate(bad)
    end

    assert {:ok, _, contexts} =
             ExtensionContext.publish(%{}, ctx.identity, request, [], Ipse.Usage.id())

    other = Map.put(ctx.identity, "instance", "other")
    high = put_in(request, ["items", Access.at(0), "priority"], 99)
    assert {:ok, _, both} = ExtensionContext.publish(contexts, other, high, [], Ipse.Usage.id())

    assert [first | _] =
             both
             |> ExtensionContext.render()
             |> String.split("\n")
             |> List.last()
             |> Jason.decode!()

    assert first["provenance"]["instance"] == "other"

    assert {:ok, _, remaining} =
             ExtensionContext.publish(
               both,
               other,
               %{"op" => "context.publish", "items" => []},
               [],
               Ipse.Usage.id()
             )

    assert remaining == contexts

    bulk = %{
      "op" => "context.publish",
      "items" =>
        for(i <- 1..8, do: %{item | "id" => "item#{i}", "text" => String.duplicate("x", 700)})
    }

    assert {:ok, _, one} = ExtensionContext.publish(%{}, ctx.identity, bulk, [], Ipse.Usage.id())
    assert {:ok, _, two} = ExtensionContext.publish(one, other, bulk, [], Ipse.Usage.id())

    assert {:error, _} =
             ExtensionContext.publish(
               two,
               Map.put(other, "instance", "third"),
               bulk,
               [],
               Ipse.Usage.id()
             )

    assert byte_size(ExtensionContext.render(two)) <= 16_384
  end

  test "missing snapshots and altered source proofs refuse before partial-tail repair", ctx do
    pid = start(ctx)
    invoke(pid, "receipt")
    assert :ok = Session.prompt(pid, "fixture request")
    assert_receive {:context_request, _}, 3000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)

    altered =
      Enum.map(events, fn event ->
        if event["type"] == "extension_action_result" and
             event["request"]["op"] == "context.publish" do
          outcome =
            put_in(
              event["outcome"],
              ["value", "items", Access.at(0), "provenance", "source_action_sha256"],
              String.duplicate("a", 64)
            )

          event
          |> Map.put("outcome", outcome)
          |> Map.put("outcome_sha256", Ipse.JSON.digest([outcome]))
        else
          event
        end
      end)

    changed_snapshot =
      Enum.map(events, fn event ->
        if event["type"] == "extension_context_snapshot",
          do:
            event
            |> Map.put("content", "replacement")
            |> Map.put("content_sha256", Ipse.JSON.sha256("replacement")),
          else: event
      end)

    for corrupted <- [
          altered,
          changed_snapshot,
          Enum.reject(events, &(&1["type"] == "extension_context_snapshot"))
        ] do
      assert {:error, _} = Actions.restore(corrupted)
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

  test "committed context survives interruption without restarting a callback", ctx do
    pid = start(ctx)
    assert :ok = Session.invoke_export(pid, :command, "ext__notes__publish", %{"mode" => "hang"})
    await_context(pid)
    assert :ok = Session.cancel(pid)
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    File.rm!(ctx.marker)
    resumed = start(ctx, id)
    assert Session.info(resumed).phase == :idle
    assert Session.diagnostics(resumed)["extension_context"]["items"] == 1
    refute File.exists?(ctx.marker)
  end

  defp await_context(pid, attempts \\ 100)
  defp await_context(_, 0), do: flunk("context did not commit")

  defp await_context(pid, attempts) do
    if Session.diagnostics(pid)["extension_context"]["items"] == 0 do
      Process.sleep(20)
      await_context(pid, attempts - 1)
    end
  end
end
