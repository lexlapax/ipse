defmodule Ipse.Extension.TextTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.{Config, Registry, Artifact, TextResources}

  defmodule Model do
    def complete(config, messages, _, emit) do
      send(config.test_pid, {:text_provider, self(), messages})
      emit.({:reason, "synthetic hidden reasoning"})
      emit.({:text, "vis"})
      emit.({:text, "ible λ"})
      if config[:hold_provider], do: receive(do: (:release -> :ok), after: (15_000 -> :ok))

      {:ok,
       %{
         "role" => "assistant",
         "content" => "visible λ",
         "provider_data" => %{"native" => "synthetic native continuation"}
       }, %{}}
    end
  end

  defmodule PressureModel do
    def complete(_config, _messages, _tools, emit) do
      text = String.duplicate("x", 64_000)
      emit.({:text, text})
      emit.({:text, text})
      {:ok, %{"role" => "assistant", "content" => text <> text}, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-worker-text-#{Ipse.Usage.id()}")
    source = Path.join(root, "artifact")
    File.mkdir_p!(Path.join(source, "ebin"))
    module = "Independent.TextSink#{System.unique_integer([:positive])}"
    file = Path.join(root, "fixture.ex")

    File.write!(file, """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => ["stream.text"]}
      def init(options) do
        File.write!(options["path"] <> ".init", "initialized\n", [:append])
        File.write!((options["path"] <> ".pid") <> ".ready-" <> System.pid(), System.pid()); File.rename!((options["path"] <> ".pid") <> ".ready-" <> System.pid(), options["path"] <> ".pid")
        {:ok, options}
      end
      def handle("stream.text", payload, state) do
        if state["mode"] == "slow" and not File.exists?(state["path"] <> ".fast"), do: Process.sleep(4000)
        File.write!(state["path"], Jason.encode!(payload) <> "\n", [:append])
        if state["mode"] == "hang" and payload["frame"]["kind"] == "text" do
          File.write!(state["path"] <> ".blocked", "blocked")
          Process.sleep(:infinity)
        end
        result = if state["mode"] == "wrong",
          do: %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "tool.call", "name" => "write", "arguments" => %{"path" => "unapproved", "content" => "bad"}, "timeout_ms" => 1000}},
          else: %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"], "sequence" => Map.get(payload["frame"], "sequence", 0)}
        {:ok, result, state}
      end
    end
    """)

    arguments = ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(source, "ebin"), file]

    {output, status} =
      System.cmd(System.find_executable("elixirc"), arguments, stderr_to_stdout: true)

    assert status == 0, output
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/text_sink",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "capabilities" => ["stream.text"],
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ~w(path mode),
        "properties" => %{
          "path" => %{"type" => "string"},
          "mode" => %{"type" => "string", "enum" => ~w(normal wrong hang slow)}
        }
      },
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
    events_source = Path.join(root, "artifact-events")
    File.mkdir_p!(Path.join(events_source, "ebin"))
    events_module = module <> "Events"
    events_file = Path.join(root, "fixture-events.ex")

    File.write!(
      events_file,
      File.read!(file)
      |> String.replace(module, events_module)
      |> String.replace(~s(["stream.text"]), ~s(["stream.text", "stream.text.events"]))
    )

    events_arguments = [
      "-pa",
      Application.app_dir(:ipse, "ebin"),
      "-o",
      Path.join(events_source, "ebin"),
      events_file
    ]

    {events_output, events_status} =
      System.cmd(System.find_executable("elixirc"), events_arguments, stderr_to_stdout: true)

    assert events_status == 0, events_output
    File.cp!(Path.join(source, "LICENSE"), Path.join(events_source, "LICENSE"))

    events_manifest = %{
      manifest
      | "version" => "0.2.0",
        "entrypoint" => events_module,
        "capabilities" => ~w(stream.text stream.text.events),
        "files" =>
          Enum.map(["LICENSE", "ebin/Elixir.#{events_module}.beam"], fn path ->
            bytes = File.read!(Path.join(events_source, path))
            %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
          end)
    }

    File.write!(Path.join(events_source, "extension.json"), Jason.encode!(events_manifest))

    {:ok, events_artifact} =
      Artifact.import(events_source, Path.join(home, "extensions/artifacts"))

    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact_root: root, artifact: artifact, events_artifact: events_artifact, home: home}
  end

  setup ctx do
    root = Path.join(ctx.artifact_root, "session-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    path = Path.join(root, "frames.jsonl")
    %{root: root, dir: Path.join(root, "sessions"), path: path}
  end

  defp config(ctx, mode \\ "normal", enabled \\ true, required \\ false) do
    source = %{
      scope: "operator",
      path: "/fixture/operator.json",
      data: %{
        "extensions" => [
          %{
            "instance" => "sink",
            "artifact" => ctx.artifact.digest,
            "enabled" => enabled,
            "options" => %{"path" => ctx.path, "mode" => mode},
            "order" => 1,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => ctx.artifact.digest,
            "capabilities" => ctx.artifact.manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false,
            "text_required" => required
          }
        ]
      }
    }

    {:ok, selections} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selections, ctx.home)

    %{
      provider: :ollama,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: ctx.home,
      approval: :deny,
      compact: false,
      extensions: entries
    }
  end

  defp start(ctx, config, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: ctx.root, state_dir: ctx.dir, subscriber: self(), id: id}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp frames(ctx) do
    case File.read(ctx.path) do
      {:ok, bytes} -> bytes |> String.split("\n") |> Enum.drop(-1) |> Enum.map(&Jason.decode!/1)
      _ -> []
    end
  end

  defp await(predicate, attempts \\ 200)
  defp await(_, 0), do: flunk("text-resource condition did not arrive")

  defp await(predicate, attempts) do
    if not predicate.() do
      Process.sleep(20)
      await(predicate, attempts - 1)
    end
  end

  test "operator-required worker delivery pins policy and completes before admission", ctx do
    selected = config(ctx, "normal", true, true)
    pid = start(ctx, selected)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "synthetic required worker")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 7_000
    assert List.last(frames(ctx))["frame"]["kind"] == "end"
    {:ok, events} = Journal.load(ctx.dir, id)
    intent = Enum.find(events, &(&1["type"] == "extension_text_intent"))
    assert intent["identity"]["text_required"] == true
    assert :ok = Session.close(pid)

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: selected, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    assert Session.info(resumed).phase == :idle
    assert :ok = Session.close(resumed)

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config(ctx), cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
             )
  end

  test "optional pressure does not let a still-closing consumer veto the next operator turn",
       ctx do
    selected =
      config(ctx, "slow")
      |> Map.put(:provider_module, PressureModel)
      |> Map.put(:context_bytes, 2_000_000)

    pid = start(ctx, selected)
    :ok = Session.prompt(pid, "first pressure turn")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 8_000
    [resource] = Map.values(:sys.get_state(pid).extension_text)
    assert Process.alive?(resource.pid)

    refute Ipse.Session.TextStream.enrolled?(
             :sys.get_state(pid).text_stream,
             resource.subscription_id,
             resource.pid
           )

    File.write!(ctx.path <> ".fast", "ready")
    :ok = Session.prompt(pid, "continue while optional delivery closes")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 2_000
    await(fn -> map_size(:sys.get_state(pid).extension_text) == 0 end)
    :ok = Session.prompt(pid, "enroll again after confirmed cleanup")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert length(String.split(File.read!(ctx.path <> ".init"), "\n", trim: true)) == 2
    assert :ok = Session.close(pid)
  end

  test "a required worker callback failure refuses the response with a delivery error", ctx do
    pid = start(ctx, config(ctx, "hang", true, true))
    :ok = Session.prompt(pid, "synthetic required callback failure")
    assert_receive {:ipse, ^pid, {:error, error}}, 8_000
    assert error =~ "Required visible-text delivery failed"
    assert_receive {:ipse, ^pid, {:done, :error}}, 2_000

    await(fn ->
      Enum.all?(:sys.get_state(pid).extension_text, fn {_, resource} -> resource.closed end)
    end)

    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_text_closed" and &1["cleanup_confirmed"] == false)
           )

    assert {:error, :cleanup_unconfirmed} = Session.close(pid)
  end

  test "a failed required callback cannot release its enrollment for the next turn", ctx do
    pid = start(ctx, Map.put(config(ctx, "wrong", true, true), :hold_provider, true))
    :ok = Session.prompt(pid, "first required failure")
    assert_receive {:text_provider, provider, _}, 5_000

    await(fn ->
      Enum.all?(:sys.get_state(pid).extension_text, fn {_, resource} -> resource.closed end)
    end)

    send(provider, :release)
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    :ok = Session.prompt(pid, "required coverage must remain lost")
    assert_receive {:ipse, ^pid, {:error, error}}, 5_000
    assert error =~ "Required visible-text delivery failed"
    assert_receive {:ipse, ^pid, {:done, :error}}, 1_000
    refute_receive {:text_provider, _, _}, 100
    assert :ok = Session.close(pid)
  end

  test "host cancellation renews required extension delivery without losing enrollment capacity",
       ctx do
    pid = start(ctx, Map.put(config(ctx, "normal", true, true), :hold_provider, true))

    for turn <- 1..5 do
      :ok = Session.prompt(pid, "cancel required delivery #{turn}")
      assert_receive {:text_provider, _, _}, 5_000
      assert :ok = Session.cancel(pid)
      assert_receive {:ipse, ^pid, {:done, :cancelled}}, 2_000
    end

    :ok = Session.prompt(pid, "new required delivery after cancellation")
    assert_receive {:text_provider, provider, _}, 5_000
    send(provider, :release)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert :ok = Session.close(pid)
  end

  test "selected worker gets private bounded ordered JSON frames after durable intent", ctx do
    pid = start(ctx, config(ctx))
    refute File.exists?(ctx.path <> ".init")
    assert :ok = Session.prompt(pid, "original input")

    assert_receive {:text_provider, _, [_system, _reference, %{"content" => "original input"}]},
                   5000

    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    await(fn -> Enum.any?(frames(ctx), &(&1["frame"]["kind"] == "end")) end)
    values = frames(ctx)
    assert hd(values)["frame"]["kind"] == "start"
    assert List.last(values)["frame"]["outcome"] == "completed"
    assert Enum.map(values, & &1["frame"]["sequence"]) == Enum.to_list(1..length(values))

    assert values
           |> Enum.filter(&(&1["frame"]["kind"] == "text"))
           |> Enum.map_join(& &1["frame"]["text"]) == "visible λ"

    refute inspect(values) =~ "hidden reasoning"
    refute inspect(values) =~ "native continuation"
    assert Enum.all?(values, &(Ipse.Extension.validate(&1) == :ok))
    {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_text_intent"))
    assert hd(values)["handle"] == intent["resource_id"]
    assert :ok = TextResources.validate_events(events, Session.info(pid).id)

    assert Enum.find_index(events, &(&1["type"] == "extension_text_ready")) <
             Enum.find_index(events, &(&1["type"] == "request_admitted"))

    refute Enum.any?(events, &Map.has_key?(&1, "frame"))
    assert Session.info(pid).accounting["request_count"] == 1
    assert :ok = Session.close(pid)
  end

  test "an independently selected v2 worker receives scoped sources without idle replay", ctx do
    ctx = %{ctx | artifact: ctx.events_artifact}
    disabled = start(ctx, config(ctx, "normal", false))
    :ok = Session.prompt(disabled, "disabled event consumer")
    assert_receive {:ipse, ^disabled, {:done, :ok}}, 5_000
    refute File.exists?(ctx.path <> ".init")
    cfg = config(ctx)
    pid = start(ctx, cfg)
    :ok = Session.prompt(pid, "selected event consumer")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    await(fn -> Enum.any?(frames(ctx), &(&1["frame"]["kind"] == "end")) end)
    received = frames(ctx)
    assert Enum.all?(received, &Ipse.Session.TextStream.valid_frame?(&1["frame"]))
    deltas = Enum.filter(received, &(&1["frame"]["kind"] == "text"))
    assert Enum.map_join(deltas, "", & &1["frame"]["text"]) == "visible λ"

    assert Enum.all?(deltas, fn p ->
             {:ok, private} = Ipse.Session.TextStream.project_frame(p["frame"], "text.visible")
             {:ok, metadata} = Ipse.Session.TextStream.project_frame(p["frame"], "metadata")
             assert private["event_id"] == metadata["event_id"]
             refute Jason.encode!(metadata) =~ "visible"
             true
           end)

    refute inspect(received) =~ "hidden reasoning"
    refute inspect(received) =~ "native continuation"
    epoch = hd(received)["frame"]["source"]["epoch_id"]
    id = Session.info(pid).id
    :ok = Session.close(pid)
    before = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
    old_frames = File.read!(ctx.path)
    File.rm!(ctx.path <> ".init")
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(ctx.path) == old_frames
    assert File.read!(Path.join(ctx.dir, id <> ".jsonl")) == before
    refute File.exists?(ctx.path <> ".init")
    :ok = Session.prompt(resumed, "new explicit event enrollment")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    await(fn -> Enum.count(frames(ctx), &(&1["frame"]["kind"] == "end")) == 2 end)
    refute List.last(frames(ctx))["frame"]["source"]["epoch_id"] == epoch
    :ok = Session.close(resumed)
  end

  test "disabled adapters initialize nothing and idle resume creates no subscription", ctx do
    disabled = start(ctx, config(ctx, "normal", false))
    assert :ok = Session.prompt(disabled, "no sink")
    assert_receive {:ipse, ^disabled, {:done, :ok}}, 5000
    refute File.exists?(ctx.path <> ".init")
    pid = start(ctx, config(ctx))
    assert :ok = Session.prompt(pid, "first")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    await(fn -> Enum.any?(frames(ctx), &(&1["frame"]["kind"] == "end")) end)
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    before = File.read!(Path.join(ctx.dir, id <> ".jsonl"))
    before_frames = File.read!(ctx.path)
    File.rm!(ctx.path <> ".init")
    resumed = start(ctx, config(ctx), id)
    assert Session.info(resumed).phase == :idle
    refute File.exists?(ctx.path <> ".init")
    assert File.read!(ctx.path) == before_frames
    assert File.read!(Path.join(ctx.dir, id <> ".jsonl")) == before
    assert :ok = Session.prompt(resumed, "explicit new prompt")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5000
    await(fn -> length(Enum.filter(frames(ctx), &(&1["frame"]["kind"] == "end"))) == 2 end)
    assert frames(ctx) |> Enum.map(& &1["handle"]) |> Enum.uniq() |> length() == 2
  end

  test "read-only reply cannot acquire effects and reports incomplete closure", ctx do
    for artifact <- [ctx.artifact, ctx.events_artifact] do
      ctx = %{ctx | artifact: artifact, path: ctx.path <> artifact.digest}
      pid = start(ctx, config(ctx, "wrong"))
      assert :ok = Session.prompt(pid, "bad consumer")
      assert_receive {:ipse, ^pid, {:done, :ok}}, 5000

      await(fn ->
        {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
        Enum.any?(events, &(&1["type"] == "extension_text_closed"))
      end)

      refute File.exists?(Path.join(ctx.root, "unapproved"))
      {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
      closed = Enum.find(events, &(&1["type"] == "extension_text_closed"))
      assert closed["reason"] == "consumer_failed"
      assert closed["cleanup_confirmed"]
      assert :ok = TextResources.validate_events(events)
      assert :ok = Session.close(pid)
    end
  end

  test "full private channel refuses activation before loading code or inference", ctx do
    pid = start(ctx, config(ctx))

    handles =
      for _ <- 1..4 do
        assert {:ok, handle} = Session.subscribe_text(pid)
        handle
      end

    assert :ok = Session.prompt(pid, "no private capacity")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    refute File.exists?(ctx.path <> ".init")
    refute_receive {:text_provider, _, _}
    assert Session.info(pid).accounting["request_count"] == 0
    for handle <- handles, do: assert(:ok = Ipse.Session.TextStream.unsubscribe(handle))
    assert :ok = Session.prompt(pid, "explicit new attempt")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
  end

  test "cancel stops a blocked callback and actual VM without replay", ctx do
    pid = start(ctx, Map.put(config(ctx, "hang"), :hold_provider, true))
    assert :ok = Session.prompt(pid, "hang consumer")
    await(fn -> File.exists?(ctx.path <> ".blocked") end)
    actual = File.read!(ctx.path <> ".pid")
    assert :ok = Session.cancel(pid)
    await_exit(actual, ctx.root)
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    File.rm!(ctx.path <> ".init")
    resumed = start(ctx, Map.put(config(ctx, "hang"), :hold_provider, true), id)
    assert Session.info(resumed).phase == :idle
    refute File.exists?(ctx.path <> ".init")
  end

  test "untrappable owner death stops a blocked consumer and actual VM", ctx do
    pid = start(ctx, Map.put(config(ctx, "hang"), :hold_provider, true))
    assert :ok = Session.prompt(pid, "owner death")
    await(fn -> File.exists?(ctx.path <> ".blocked") end)
    actual = File.read!(ctx.path <> ".pid")
    id = Session.info(pid).id
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1000
    await_exit(actual, ctx.root)
    File.rm!(ctx.path <> ".init")
    resumed = start(ctx, Map.put(config(ctx, "hang"), :hold_provider, true), id)
    assert Session.info(resumed).phase == :idle
    refute File.exists?(ctx.path <> ".init")
  end

  test "corrupt lifecycle receipts refuse before tail repair", ctx do
    pid = start(ctx, config(ctx))
    assert :ok = Session.prompt(pid, "receipt fixture")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.dir, id)

    for corrupted <- [
          Enum.reject(events, &(&1["type"] == "extension_text_ready")),
          Enum.reject(events, &(&1["type"] == "extension_text_intent")),
          Enum.map(events, fn event ->
            if event["type"] == "extension_text_ready",
              do: Map.put(event, "intent_sha256", String.duplicate("a", 64)),
              else: event
          end)
        ] do
      path = Path.join(ctx.dir, id <> ".jsonl")
      bytes = Enum.map_join(corrupted, "", &(Jason.encode!(&1) <> "\n")) <> "{partial"
      File.write!(path, bytes)

      assert {:error, _} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session,
                  config: config(ctx),
                  cwd: ctx.root,
                  state_dir: ctx.dir,
                  subscriber: self(),
                  id: id}
               )

      assert File.read!(path) == bytes
    end
  end

  defp await_exit(actual, cwd) do
    assert Regex.match?(~r/\A[0-9]+\z/, actual)

    await(fn ->
      {:ok, result} =
        Ipse.Runner.run("kill -0 " <> actual, cwd, timeout_ms: 1000, output_limit: 0)

      result.exit_code != 0
    end)
  end
end
