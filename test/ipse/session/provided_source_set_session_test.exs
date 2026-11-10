Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Session.ProvidedSourceSetSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{InferenceSlots, Journal, Session, Usage}
  alias Ipse.Extension.{Artifact, Catalog, Config, Registry}
  alias Ipse.Session.ProvidedSourceSet
  alias Ipse.Test.ProviderFixture

  @name "ext__probe__investigate"

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-provided-fence-fixture-" <> Usage.id())
    caps = ~w(invoke.command invoke.result.pages host.actions host.model host.embedding)

    command = %{
      "id" => "investigate",
      "description" => "Synthetic provided-only investigation",
      "arguments_schema" => %{"type" => "object"},
      "result_schema" => %{"type" => "object"},
      "source_contract" => Catalog.source_contract()
    }

    exports = Map.put(Catalog.empty(), "commands", [command])

    # The worker never states its sources to the host. A null rerank finishes
    # at once; "judge" asks for one model call, "embed" for an embedding and
    # "tool" for a workspace write.
    # "stale" reports an as-of time before selection and "saved" offers a paged
    # saved result. Every other result reports the worker's current time.
    probe =
      build(Path.join(root, "probe"), "provided-fence", 2, caps, exports, nil, fn module ->
        """
        defmodule #{module} do
          @behaviour Ipse.Extension
          def describe, do: %{"sdk" => 2, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}}
          def init(options), do: {:ok, options}

          def handle("invoke.command", %{"arguments" => args}, state) do
            case args["rerank"] do
              "judge" ->
                {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => %{
                  "op" => "model.complete", "version" => 1, "profile" => "answer",
                  "instruction" => "Order the candidates", "input" => args["query"],
                  "max_output_bytes" => 1024, "timeout_ms" => 3000}}, state}

              "embed" ->
                {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => %{
                  "op" => "embedding.create", "version" => 1, "profile" => "search",
                  "inputs" => [args["query"]], "timeout_ms" => 3000}}, state}

              "tool" ->
                {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => %{
                  "op" => "tool.call", "name" => "write", "timeout_ms" => 1000,
                  "arguments" => %{"path" => "forbidden", "content" => "denied"}}}, state}

              "stale" ->
                result(%{"status" => "ok", "query" => args["query"], "coverage" => %{"as_of_ms" => 1}}, state)

              "saved" ->
                {:ok, reply} = Ipse.Extension.ResultPublication.prepare_paged(value(%{"query" => args["query"]}))
                {:ok, reply, state}

              _ ->
                result(value(%{"status" => "ok", "query" => args["query"]}), state)
            end
          end

          def handle("host.actions", payload, state),
            do: result(value(%{"outcome" => payload["outcome"]}), state)

          defp value(value), do: Map.put(value, "coverage", %{"as_of_ms" => System.system_time(:millisecond)})
          defp result(value, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
        end
        """
      end)

    # A separate metadata feed observes every admitted invocation.
    admitted = %{
      "id" => "admitted",
      "event" => "extension.invocation_admitted",
      "event_version" => 1,
      "view" => "metadata",
      "mode" => "feed",
      "queue_events" => 8
    }

    feed =
      build(
        Path.join(root, "feed"),
        "provided-feed",
        1,
        ["event.feed"],
        Catalog.empty(),
        [admitted],
        fn module ->
          """
          defmodule #{module} do
            @behaviour Ipse.Extension
            def describe, do: %{"sdk" => 1, "capabilities" => ["event.feed"], "subscriptions" => #{inspect([admitted])}, "exports" => #{inspect(Catalog.empty())}}
            def init(options), do: {:ok, options}

            def handle("event.feed", payload, state),
              do: {:ok, %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"],
                "sequence" => payload["sequence"], "event_id" => payload["event"]["event_id"]}, state}
          end
          """
        end
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: probe, feed_artifact: feed, capabilities: caps}
  end

  defp build(root, id, sdk, caps, exports, subscriptions, source) do
    File.mkdir_p!(Path.join(root, "ebin"))
    module = "Independent.ProvidedFenceFixture#{System.unique_integer([:positive])}"
    file = Path.join(root, "fixture.ex")
    File.write!(file, source.(module))

    {log, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(root, "ebin"), file],
        stderr_to_stdout: true
      )

    assert status == 0, log
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")
    paths = ["LICENSE", "ebin/Elixir.#{module}.beam"]

    manifest = %{
      "format" => 1,
      "id" => "fixture/" <> id,
      "version" => "0.1.0",
      "sdk" => sdk,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => caps,
      "exports" => exports,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(paths, fn path ->
          bytes = File.read!(Path.join(root, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    manifest =
      if subscriptions, do: Map.put(manifest, "subscriptions", subscriptions), else: manifest

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    root
  end

  setup do
    base = Path.join(System.tmp_dir!(), "ipse-provided-fence-" <> Usage.id())
    home = Path.join(base, "operator")
    cwd = Path.join(base, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)
    %{home: home, cwd: cwd, sessions: Path.join(base, "sessions")}
  end

  defp listener do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(socket)
    on_exit(fn -> :gen_tcp.close(socket) end)
    {socket, "http://127.0.0.1:#{port}"}
  end

  defp no_connection!(socket), do: assert({:error, :timeout} = :gen_tcp.accept(socket, 0))

  defp config(c, base, registered, feed \\ false) do
    selected =
      [{"probe", c.artifact, c.capabilities, "persistent"}] ++
        if(feed, do: [{"feed", c.feed_artifact, ["event.feed"], "session"}], else: [])

    {extensions, trust} =
      selected
      |> Enum.with_index(1)
      |> Enum.map(fn {{instance, path, caps, lifetime}, order} ->
        {:ok, artifact} = Artifact.import(path, Path.join(c.home, "extensions/artifacts"))

        {%{
           "instance" => instance,
           "artifact" => artifact.digest,
           "enabled" => true,
           "options" => %{},
           "order" => order,
           "lifetime" => lifetime
         },
         %{
           "artifact" => artifact.digest,
           "capabilities" => caps,
           "allow_project" => false,
           "allow_children" => false
         }}
      end)
      |> Enum.unzip()

    data = %{"extensions" => extensions, "extension_trust" => trust}

    {:ok, selected} =
      Config.resolve([%{scope: "operator", path: Path.join(c.home, "o.json"), data: data}], [])

    {:ok, entries} = Registry.prepare(selected, c.home)

    config = %{
      provider: :demo,
      model: "unused",
      home: c.home,
      timeout_ms: 3000,
      extensions: entries,
      approval: :ask,
      approval_origin: :interactive,
      headless: false,
      compact: false,
      model_profiles: %{
        "answer" => %{
          "provider" => "ollama",
          "model" => "fixture",
          "base_url" => base,
          "timeout_ms" => 3000
        }
      },
      embedding_profiles: %{
        "search" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture",
          "base_url" => base,
          "dimensions" => 2,
          "dimension_mode" => "native",
          "timeout_ms" => 3000
        }
      }
    }

    if registered,
      do:
        Map.put(config, :inference_services, %{"local" => %{"version" => 1, "origins" => [base]}}),
      else: config
  end

  defp start(c, config) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.cwd, state_dir: c.sessions, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    pid
  end

  defp args(rerank, sources) do
    %{
      "search" => "given",
      "fetch" => "given",
      "retrieval" => "words",
      "rerank" => rerank,
      "query" => "quiescence",
      "limits" => %{"max_sources" => 10, "max_body_bytes" => 4096, "timeout_ms" => 5000},
      "sources" => sources
    }
  end

  defp source(expires \\ nil) do
    %{
      "source_id" => "manual:release",
      "generation" => 1,
      "title" => "Release policy",
      "text" => "Release requires quiescence.",
      "uri" => "local:release-policy",
      "observed_at_ms" => 1_700_000_000_000,
      "event_at_ms" => nil,
      "expires_at_ms" => expires
    }
  end

  defp settle(pid, approve \\ fn _ -> true end, approvals \\ []) do
    receive do
      {:ipse, ^pid, {:approval, ref, kind, proposed}} ->
        :ok = Session.approve(pid, ref, approve.(proposed))
        settle(pid, approve, [kind | approvals])

      {:ipse, ^pid, {:done, status}} ->
        {status, Enum.reverse(approvals)}
    after
      15_000 -> flunk("fenced command did not settle")
    end
  end

  defp index(events, fun), do: Enum.find_index(events, fun)

  test "a current result is delivered after its journaled set and restores only as history", c do
    {_, base} = listener()
    pid = start(c, config(c, base, false))
    id = Session.info(pid).id
    assert :ok = Session.invoke_export(pid, :command, @name, args(nil, [source()]))
    assert {:ok, []} = settle(pid)

    assert %{"status" => "ok", "query" => "quiescence", "coverage" => %{"as_of_ms" => as_of}} =
             Session.info(pid).extension_result["value"]

    assert :ok = Session.close_confirmed(pid)

    {:ok, events} = Journal.load(c.sessions, id)
    parent = index(events, &(&1["type"] == "extension_invocation_intent"))
    set = Enum.at(events, parent + 1)
    assert set["type"] == "provided_source_set_intent"
    assert ProvidedSourceSet.valid_intent?(set, Enum.at(events, parent))
    assert set["selected_at_ms"] <= as_of
    assert set["transition_ms"] == nil and set["source_count"] == 1
    release = index(events, &(&1["type"] == "provided_source_set_release"))
    result = index(events, &(&1["type"] == "extension_invocation_result"))
    assert parent < release and release + 1 == result
    assert Enum.at(events, release)["decision"] == "current"

    assert Enum.at(events, release)["result_sha256"] ==
             Ipse.JSON.digest([Enum.at(events, result)])

    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config(c, base, false),
         cwd: c.cwd,
         state_dir: c.sessions,
         id: id,
         subscriber: self()}
      )

    assert Session.info(resumed).extension_result["value"] == %{
             "status" => "withheld",
             "reason" => "provided_sources_historical",
             "historical_receipt" => true
           }

    assert :ok = Session.close_confirmed(resumed)
  end

  test "an unregistered route and non-model host calls refuse before approval or provider IO",
       c do
    {socket, base} = listener()
    pid = start(c, config(c, base, false))
    id = Session.info(pid).id

    for rerank <- ["judge", "embed", "tool"] do
      assert :ok = Session.invoke_export(pid, :command, @name, args(rerank, [source()]))
      assert {:error, []} = settle(pid)
    end

    refute File.exists?(Path.join(c.cwd, "forbidden"))
    no_connection!(socket)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)

    refute Enum.any?(
             events,
             &(&1["type"] in ~w(extension_action_intent inference_dispatch_intent))
           )

    refute Enum.any?(events, &(&1["type"] == "request_admitted"))
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert Enum.count(events, &(&1["type"] == "provided_source_set_intent")) == 3
    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "approval delayed past a transition refuses dispatch and withholds delivery", c do
    {socket, base} = listener()
    pid = start(c, config(c, base, true))
    id = Session.info(pid).id
    expires = System.system_time(:millisecond) + 1_500
    assert :ok = Session.invoke_export(pid, :command, @name, args("judge", [source(expires)]))

    late = fn _ ->
      Process.sleep(max(expires - System.system_time(:millisecond) + 50, 0))
      true
    end

    assert {:error, ["extension:model.complete"]} = settle(pid, late)
    no_connection!(socket)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)

    assert Enum.find(events, &(&1["type"] == "provided_source_set_intent"))["transition_ms"] ==
             expires

    refute Enum.any?(events, &(&1["type"] in ~w(inference_dispatch_intent request_admitted)))
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    release = Enum.find(events, &(&1["type"] == "provided_source_set_release"))
    assert release["decision"] == "withheld" and release["checked_at_ms"] >= expires
    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "an interrupted fenced invocation restores without a result and is never replayed", c do
    {socket, base} = listener()
    config = config(c, base, true)
    pid = start(c, config)
    id = Session.info(pid).id
    assert :ok = Session.invoke_export(pid, :command, @name, args("judge", [source()]))
    assert_receive {:ipse, ^pid, {:approval, _, "extension:model.complete", _}}, 15_000
    assert :ok = Session.cancel(pid)
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 15_000
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)
    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.cwd, state_dir: c.sessions, id: id, subscriber: self()}
      )

    assert Session.info(resumed).phase == :idle
    assert :ok = Session.close_confirmed(resumed)
    {:ok, reopened} = Journal.load(c.sessions, id)

    for type <- ~w(provided_source_set_intent extension_action_intent inference_dispatch_intent) do
      assert Enum.count(reopened, &(&1["type"] == type)) ==
               Enum.count(events, &(&1["type"] == type))
    end

    refute Enum.any?(reopened, &(&1["type"] == "extension_invocation_result"))
    no_connection!(socket)
  end

  test "a registered current dispatch is bound from set intent through physical send and release",
       c do
    content = Jason.encode!(%{"order" => ["e1"]})

    body =
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => content},
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }) <> "\n"

    {base, server} = ProviderFixture.start(body, 200, "", :whole)
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    config = config(c, base, true)
    pid = start(c, config)
    id = Session.info(pid).id
    supported = match?({:ok, _}, InferenceSlots.status(config, cwd: c.cwd))
    assert :ok = Session.invoke_export(pid, :command, @name, args("judge", [source()]))
    assert {:ok, ["extension:model.complete"]} = settle(pid)
    outcome = Session.info(pid).extension_result["value"]["outcome"]
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)
    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)
    set = index(events, &(&1["type"] == "provided_source_set_intent"))
    action = index(events, &(&1["type"] == "extension_action_intent"))
    release = index(events, &(&1["type"] == "provided_source_set_release"))
    assert set < action and action < release

    if supported do
      # Name the failed stage: a refusal before the fixture saw a request is a
      # fence or gate refusal; a failure after it is transport, parse or release.
      Process.unlink(server.pid)

      http =
        case Task.yield(server, 6_000) do
          {:ok, {headers, _}} -> headers
          _ -> nil
        end

      stage =
        cond do
          not Enum.any?(events, &(&1["type"] == "inference_dispatch_intent")) -> :dispatch_gate
          is_nil(http) -> :physical_send_refused
          outcome["status"] != "ok" -> :after_send
          true -> :released
        end

      assert stage == :released,
             "registered send stopped at #{stage}: outcome=#{inspect(outcome)} " <>
               "events=#{inspect(Enum.map(events, & &1["type"]))}"

      dispatch = index(events, &(&1["type"] == "inference_dispatch_intent"))
      assert action < dispatch and dispatch < release
      assert http =~ "POST /api/chat"
    else
      refute outcome["status"] == "ok"
      refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))
      IO.puts("#{inspect(__MODULE__)}: unsupported service filesystem; registered send NOT RUN")
    end
  end

  # The physical-send check runs before the connection opens, so a request can
  # cross the transition on the wire. Its output and the result stay withheld.
  test "a transition after the physical send withholds the model output and the result", c do
    {socket, base} = listener()
    config = config(c, base, true)

    if match?({:ok, _}, InferenceSlots.status(config, cwd: c.cwd)) do
      pid = start(c, config)
      id = Session.info(pid).id
      expires = System.system_time(:millisecond) + 2_000

      content =
        Jason.encode!(%{
          "model" => "fixture",
          "message" => %{
            "role" => "assistant",
            "content" => Jason.encode!(%{"order" => ["e1"]})
          },
          "done" => true,
          "done_reason" => "stop",
          "prompt_eval_count" => 1,
          "eval_count" => 1
        }) <> "\n"

      server =
        Task.async(fn ->
          {:ok, conn} = :gen_tcp.accept(socket, 10_000)
          {headers, _} = ProviderFixture.request(conn, "")
          Process.sleep(max(expires - System.system_time(:millisecond) + 100, 0))

          :gen_tcp.send(
            conn,
            "HTTP/1.1 200 Fixture\r\ncontent-type: text/event-stream\r\n" <>
              "content-length: #{byte_size(content)}\r\nconnection: close\r\n\r\n" <> content
          )

          :gen_tcp.close(conn)
          headers
        end)

      assert :ok = Session.invoke_export(pid, :command, @name, args("judge", [source(expires)]))
      assert {:error, ["extension:model.complete"]} = settle(pid)
      assert_received {:ipse, ^pid, {:error, message}}
      assert message =~ "before delivery; the result was withheld"
      assert Task.await(server, 10_000) =~ "POST /api/chat"
      assert :ok = Session.close_confirmed(pid)
      {:ok, events} = Journal.load(c.sessions, id)
      dispatch = index(events, &(&1["type"] == "inference_dispatch_intent"))
      release = index(events, &(&1["type"] == "provided_source_set_release"))
      assert dispatch < release
      assert Enum.at(events, release)["decision"] == "withheld"
      assert Enum.at(events, release)["checked_at_ms"] >= expires
      refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
      assert :ok = ProvidedSourceSet.validate_events(events)
      assert {:ok, _} = Session.Saved.restore(events, id)
    else
      IO.puts("#{inspect(__MODULE__)}: unsupported service filesystem; send-to-release NOT RUN")
    end
  end

  test "a feed observing the admitted parent records its delivery after the set intent", c do
    {_, base} = listener()
    config = config(c, base, false, true)
    pid = start(c, config)
    id = Session.info(pid).id
    assert :ok = Session.invoke_export(pid, :command, @name, args(nil, [source()]))
    assert {:ok, []} = settle(pid)
    assert :ok = Session.close_confirmed(pid)

    {:ok, events} = Journal.load(c.sessions, id)
    parent = index(events, &(&1["type"] == "extension_invocation_intent"))
    assert Enum.at(events, parent + 1)["type"] == "provided_source_set_intent"
    feed = index(events, &(&1["type"] == "extension_feed_delivery_intent"))
    assert is_integer(feed) and feed > parent + 1
    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.cwd, state_dir: c.sessions, id: id, subscriber: self()}
      )

    assert Session.info(resumed).extension_result["value"]["historical_receipt"] == true
    assert :ok = Session.close_confirmed(resumed)
  end

  test "a journal ending after a bare contract intent resumes as never started", c do
    {_, base} = listener()
    config = config(c, base, false)
    pid = start(c, config)
    id = Session.info(pid).id
    assert :ok = Session.invoke_export(pid, :command, @name, args(nil, [source()]))
    assert {:ok, []} = settle(pid)
    assert :ok = Session.close_confirmed(pid)

    # Simulate a crash between the two appends: keep every line through the
    # invocation intent and nothing after it.
    path = Path.join(c.sessions, id <> ".jsonl")
    lines = path |> File.read!() |> String.split("\n", trim: true)

    parent =
      Enum.find_index(lines, &(Jason.decode!(&1)["type"] == "extension_invocation_intent"))

    File.write!(path, Enum.map_join(Enum.take(lines, parent + 1), &(&1 <> "\n")))
    {:ok, truncated} = Journal.load(c.sessions, id)
    assert List.last(truncated)["type"] == "extension_invocation_intent"
    assert :ok = ProvidedSourceSet.validate_events(truncated)
    assert {:ok, _} = Session.Saved.restore(truncated, id)

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.cwd, state_dir: c.sessions, id: id, subscriber: self()}
      )

    assert Session.info(resumed).phase == :idle
    assert :ok = Session.close_confirmed(resumed)
    {:ok, reopened} = Journal.load(c.sessions, id)

    refute Enum.any?(
             reopened,
             &(&1["type"] in ~w(provided_source_set_intent provided_source_set_release extension_invocation_result))
           )

    assert :ok = ProvidedSourceSet.validate_events(reopened)
  end

  test "a journal without room for both begin records writes neither", c do
    {_, base} = listener()
    probe = start(c, config(c, base, false))
    probe_id = Session.info(probe).id
    assert :ok = Session.invoke_export(probe, :command, @name, args(nil, [source()]))
    assert {:ok, []} = settle(probe)
    assert :ok = Session.close_confirmed(probe)
    {:ok, events} = Journal.load(c.sessions, probe_id)
    before = index(events, &(&1["type"] == "extension_invocation_intent"))

    # Around the limit that fits only the invocation intent and its quota
    # marker, the pair is either written together or refused with neither.
    for slack <- -1..3 do
      config = Map.put(config(c, base, false), :journal, %{"max_events" => before + 2 + slack})
      pid = start(c, config)
      id = Session.info(pid).id
      monitor = Process.monitor(pid)
      assert :ok = Session.invoke_export(pid, :command, @name, args(nil, [source()]))

      receive do
        {:ipse, ^pid, {:done, _}} -> :ok
        {:DOWN, ^monitor, :process, ^pid, _} -> :ok
      after
        15_000 -> flunk("limited invocation did not settle")
      end

      message =
        receive do
          {:ipse, ^pid, {:error, message}} -> message
        after
          0 -> nil
        end

      if Process.alive?(pid), do: Session.close_confirmed(pid)
      {:ok, saved} = Journal.load(c.sessions, id)

      parent = index(saved, &(&1["type"] == "extension_invocation_intent"))

      if slack <= 0 do
        assert parent == nil
        refute Enum.any?(saved, &(&1["type"] == "provided_source_set_intent"))
        assert message =~ "cannot hold the provided-source invocation and its source-set record"
        assert message =~ "recovery.md#continue-in-a-fresh-session"
        refute message =~ "Job continuation"
      else
        assert Enum.at(saved, parent + 1)["type"] == "provided_source_set_intent"
      end

      assert :ok = ProvidedSourceSet.validate_events(saved)
    end
  end

  test "an empty or oversized source set is refused before anything is journaled", c do
    {_, base} = listener()

    for sources <- [[], List.duplicate(source(), 11)] do
      pid = start(c, config(c, base, false))
      id = Session.info(pid).id
      assert :ok = Session.invoke_export(pid, :command, @name, args(nil, sources))
      assert {:error, []} = settle(pid)
      assert_received {:ipse, ^pid, {:error, message}}
      assert message =~ "provided source set was refused before the extension started"
      assert :ok = Session.close_confirmed(pid)
      {:ok, events} = Journal.load(c.sessions, id)

      refute Enum.any?(
               events,
               &(&1["type"] in ~w(extension_invocation_intent provided_source_set_intent))
             )
    end
  end

  test "a result reporting an as-of time before selection is withheld", c do
    {_, base} = listener()
    pid = start(c, config(c, base, false))
    id = Session.info(pid).id
    assert :ok = Session.invoke_export(pid, :command, @name, args("stale", [source()]))
    assert {:error, []} = settle(pid)
    assert_received {:ipse, ^pid, {:error, message}}
    assert message =~ "as-of time outside its provided source set"
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)
    release = Enum.find(events, &(&1["type"] == "provided_source_set_release"))
    assert release["decision"] == "withheld"
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "a fenced invocation cannot open saved output pages", c do
    {_, base} = listener()
    pid = start(c, config(c, base, false))
    id = Session.info(pid).id
    assert :ok = Session.invoke_export(pid, :command, @name, args("saved", [source()]))
    assert {:error, []} = settle(pid)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)
    assert Enum.any?(events, &(&1["type"] == "provided_source_set_intent"))

    refute Enum.any?(
             events,
             &(&1["type"] in ~w(extension_output_begin extension_output_chunk extension_output_seal extension_invocation_result provided_source_set_release))
           )

    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "owner inference boundaries apply the fence clock exactly", c do
    {socket, base} = listener()
    pid = start(c, config(c, base, true))
    expires = System.system_time(:millisecond) + 3_600_000
    assert :ok = Session.invoke_export(pid, :command, @name, args("judge", [source(expires)]))
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:model.complete", _}}, 15_000
    test = self()

    # The boundaries run in the Session owner against a copy of its state; the
    # owner keeps its original state and the pending approval is then denied.
    :sys.replace_state(pid, fn owner ->
      send(test, {:boundaries, boundaries(owner, expires)})
      owner
    end)

    assert_receive {:boundaries, results}, 15_000
    assert :ok = Session.approve(pid, ref, false)
    settle(pid)
    no_connection!(socket)

    assert Enum.map(results, &elem(&1, 0)) ==
             ~w(begin_inference commit wire_use result_admit)a

    for {boundary, checks} <- results do
      assert checks == %{rollback: :refused, transition: :refused, before: :admitted},
             "#{boundary}: #{inspect(checks)}"
    end
  end

  # Drives each owner boundary with one state at three fence clock readings:
  # below the high-water, exactly at the transition and one millisecond before
  # it. Only the clock differs between the three calls.
  defp boundaries(owner, transition) do
    action = owner.invocation.action
    intent = Map.put(action.intent, "approval", "approved")

    s = %{
      owner
      | invocation: %{owner.invocation | action: %{action | intent: intent}},
        task: %{owner.task | pid: self()}
    }

    # Record the approved action exactly as an approval would.
    s = Session.record_extension_action(s, intent)

    at = fn s, now ->
      fence = Map.put(s.invocation.provided_set, :clock, fn -> now end)
      %{s | invocation: %{s.invocation | provided_set: fence}}
    end

    before = transition - 1
    label = fn admitted -> if admitted, do: :admitted, else: :refused end

    check = fn name, s, call, admitted? ->
      {name,
       Map.new([rollback: before - 1, transition: transition, before: before], fn {key, now} ->
         {key, label.(admitted?.(call.(at.(s, now))))}
       end)}
    end

    # begin_inference journals accounting when it admits, so its refused cases
    # run first and its single admitted call, which raises the high-water to
    # `before`, supplies the state for the later boundaries.
    begin = &Session.Invocation.begin_inference(&1, :extension_model_begin, intent)
    begun? = &match?({:reply, {:ok, _, _, _}, _}, &1)
    selected = s.invocation.provided_set.intent["selected_at_ms"]
    rollback = label.(begun?.(begin.(at.(s, selected - 1))))
    at_transition = label.(begun?.(begin.(at.(s, transition))))
    {:reply, {:ok, _, admission, dispatch}, s} = begin.(at.(s, before))
    phase = "model.complete"
    expected = dispatch.expected

    {:ok, %{route: route}} =
      Ipse.InferenceDispatch.selection(s.config, dispatch.runtime, phase, "answer")

    commit =
      &Session.InferenceDispatch.commit(&1, self(), phase, admission, expected, %{
        "route" => route,
        "reservation_id" => Usage.id()
      })

    wire =
      &Session.InferenceDispatch.wire_use(&1, self(), phase, admission, expected, dispatch.wire)

    digest = Ipse.JSON.sha256("model output")

    result =
      &Session.InferenceDispatch.result_admit(&1, self(), phase, admission, expected, digest)

    [
      {:begin_inference, %{rollback: rollback, transition: at_transition, before: :admitted}},
      check.(:commit, s, commit, &match?({:reply, {:ok, _}, _}, &1)),
      check.(:wire_use, s, wire, &match?({:reply, :ok, _}, &1)),
      check.(:result_admit, s, result, &match?({:reply, :ok, _}, &1))
    ]
  end
end
