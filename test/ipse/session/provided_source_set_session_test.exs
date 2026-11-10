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
    File.mkdir_p!(Path.join(root, "ebin"))
    module = "Independent.ProvidedFenceFixture#{System.unique_integer([:positive])}"
    caps = ~w(invoke.command host.actions host.model host.embedding)

    command = %{
      "id" => "investigate",
      "description" => "Synthetic provided-only investigation",
      "arguments_schema" => %{"type" => "object"},
      "result_schema" => %{"type" => "object"},
      "source_contract" => Catalog.source_contract()
    }

    exports = Map.put(Catalog.empty(), "commands", [command])

    # The worker never states its sources to the host. A null rerank finishes
    # at once; "judge" asks for one model call and "embed" for an embedding.
    source = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}}
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

          _ ->
            {:ok, %{"api_version" => 1, "kind" => "result",
              "value" => %{"status" => "ok", "query" => args["query"]}}, state}
        end
      end

      def handle("host.actions", payload, state),
        do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"outcome" => payload["outcome"]}}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, source)

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
      "id" => "fixture/provided-fence",
      "version" => "0.1.0",
      "sdk" => 1,
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

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: root, capabilities: caps}
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

  defp config(c, base, registered) do
    {:ok, artifact} = Artifact.import(c.artifact, Path.join(c.home, "extensions/artifacts"))

    data = %{
      "extensions" => [
        %{
          "instance" => "probe",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 1,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => c.capabilities,
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

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

    assert Session.info(pid).extension_result["value"] == %{
             "status" => "ok",
             "query" => "quiescence"
           }

    assert :ok = Session.close_confirmed(pid)

    {:ok, events} = Journal.load(c.sessions, id)
    parent = index(events, &(&1["type"] == "extension_invocation_intent"))
    set = Enum.at(events, parent + 1)
    assert set["type"] == "provided_source_set_intent"
    assert ProvidedSourceSet.valid_intent?(set, Enum.at(events, parent))
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

    for rerank <- ["judge", "embed"] do
      assert :ok = Session.invoke_export(pid, :command, @name, args(rerank, [source()]))
      assert {:error, []} = settle(pid)
    end

    no_connection!(socket)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)

    refute Enum.any?(
             events,
             &(&1["type"] in ~w(extension_action_intent inference_dispatch_intent))
           )

    refute Enum.any?(events, &(&1["type"] == "request_admitted"))
    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert Enum.count(events, &(&1["type"] == "provided_source_set_intent")) == 2
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
      assert outcome["status"] == "ok"
      dispatch = index(events, &(&1["type"] == "inference_dispatch_intent"))
      assert action < dispatch and dispatch < release
      assert [{http, _}] = [Task.await(server)]
      assert http =~ "POST /api/chat"
    else
      refute outcome["status"] == "ok"
      refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))
      IO.puts("#{inspect(__MODULE__)}: unsupported service filesystem; registered send NOT RUN")
    end
  end
end
