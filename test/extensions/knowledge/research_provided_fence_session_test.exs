Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.KnowledgeResearchProvidedFenceSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{InferenceSlots, Journal, Session, Usage}
  alias Ipse.Extension.{Artifact, Config, Registry}
  alias Ipse.Session.ProvidedSourceSet
  alias Ipse.Test.ProviderFixture

  @name "ext__research__investigate_provided"
  @query "release quiescence"

  # The operator journey of docs/operator/research.md, "Fence a supplied-source
  # rerank through delivery": the mcp-model Research artifact is built once and
  # its options name only the provided search and fetch profiles, lexical
  # retrieval and the structured model reranker.
  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-research-provided-fence-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    artifact = Path.join(root, "research-mcp-model")

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          artifact,
          "--package",
          "research",
          "--preset",
          "mcp-model"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    options = Path.join(root, "mcp-model-options.json")

    File.write!(
      options,
      Jason.encode!(%{
        "version" => 1,
        "stores" => %{},
        "search" => %{"given" => %{"kind" => "provided", "version" => 1}},
        "fetch" => %{"given" => %{"kind" => "provided", "version" => 1}},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{},
        "rerank" => %{
          "ordered" => %{
            "kind" => "model_complete",
            "profile" => "reranker",
            "max_candidates" => 16,
            "quote_bytes" => 128,
            "output_contract" => "json_schema_v2"
          }
        },
        "extraction" => %{}
      })
    )

    %{artifact: artifact, options: options}
  end

  setup do
    base = Path.join(System.tmp_dir!(), "ipse-research-provided-fence-run-" <> Usage.id())
    home = Path.join(base, "operator")
    cwd = Path.join(base, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)
    %{base: base, home: home, cwd: cwd, sessions: Path.join(base, "sessions")}
  end

  defp listener do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(socket)
    on_exit(fn -> :gen_tcp.close(socket) end)
    {socket, "http://127.0.0.1:#{port}"}
  end

  defp no_connection!(socket), do: assert({:error, :timeout} = :gen_tcp.accept(socket, 0))

  # The package's own generator writes the disabled instance, its exact trust
  # and the separate inference file's reranker profile and registered service.
  # The reviewed instance is then enabled and admitted as operator configuration.
  defp config(c, origin) do
    inference = Path.join(c.base, "rerank-inference.json")
    output = Path.join(c.base, "operator-mcp-model.json")

    File.write!(
      inference,
      Jason.encode!(%{
        "profiles" => %{
          "reranker" => %{
            "provider" => "ollama",
            "model" => "fixture",
            "credential" => "none",
            "base_url" => origin,
            "timeout_ms" => 10_000,
            "max_output_tokens" => 1024
          }
        },
        "inference_services" => %{"local" => %{"version" => 1, "origins" => [origin]}}
      })
    )

    {log, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/config.exs",
          "--artifact",
          c.artifact,
          "--package",
          "research",
          "--preset",
          "mcp-model",
          "--instance",
          "research",
          "--options",
          c.options,
          "--inference-config",
          inference,
          "--output",
          output
        ],
        stderr_to_stdout: true
      )

    assert status == 0, log
    operator = Jason.decode!(File.read!(output))
    {:ok, artifact} = Artifact.import(c.artifact, Path.join(c.home, "extensions/artifacts"))
    assert [%{"artifact" => digest, "enabled" => false} = instance] = operator["extensions"]
    assert digest == artifact.digest

    data =
      operator
      |> Map.take(~w(extension_trust))
      |> Map.put("extensions", [Map.put(instance, "enabled", true)])

    {:ok, selected} = Config.resolve([%{scope: "operator", path: output, data: data}], [])
    {:ok, entries} = Registry.prepare(selected, c.home)

    %{
      provider: :demo,
      model: "unused",
      home: c.home,
      timeout_ms: 10_000,
      extensions: entries,
      approval: :ask,
      approval_origin: :interactive,
      headless: false,
      compact: false,
      model_profiles: operator["profiles"],
      inference_services: operator["inference_services"]
    }
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
      "query" => @query,
      "limits" => %{"max_sources" => 2, "max_body_bytes" => 1024, "timeout_ms" => 10_000},
      "sources" => sources
    }
  end

  defp source(expires \\ nil, id \\ "release", text \\ "Release requires quiescence.") do
    %{
      "source_id" => "manual:" <> id,
      "generation" => 1,
      "title" => "Release policy",
      "text" => text,
      "uri" => "local:" <> id <> "-policy",
      "observed_at_ms" => 1_700_000_000_000,
      "event_at_ms" => nil,
      "expires_at_ms" => expires
    }
  end

  defp settle(pid, approvals \\ []) do
    receive do
      {:ipse, ^pid, {:approval, ref, kind, proposed}} ->
        :ok = Session.approve(pid, ref, true)
        settle(pid, [{kind, proposed} | approvals])

      {:ipse, ^pid, {:done, status}} ->
        {status, Enum.reverse(approvals)}
    after
      15_000 -> flunk("fenced Research command did not settle")
    end
  end

  # Run one command in a fresh Session and return its settlement, the value the
  # Session shows and the closed journal.
  defp investigate(c, config, arguments) do
    pid = start(c, config)
    id = Session.info(pid).id
    assert :ok = Session.invoke_export(pid, :command, @name, arguments)
    settled = settle(pid)
    value = Session.info(pid).extension_result["value"]
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.sessions, id)
    assert :ok = ProvidedSourceSet.validate_events(events)
    assert {:ok, _} = Session.Saved.restore(events, id)
    {settled, value, events}
  end

  defp index(events, type), do: Enum.find_index(events, &(&1["type"] == type))
  defp any?(events, types), do: Enum.any?(events, &(&1["type"] in types))

  # The set intent directly follows the invocation intent and a current release
  # directly precedes the result it binds. Returns the four journal positions.
  defp fenced_delivery!(events, value, sources) do
    parent = index(events, "extension_invocation_intent")
    set = Enum.at(events, parent + 1)
    assert set["type"] == "provided_source_set_intent"
    assert ProvidedSourceSet.valid_intent?(set, Enum.at(events, parent))
    assert set["source_count"] == length(sources)
    release = index(events, "provided_source_set_release")
    result = index(events, "extension_invocation_result")
    assert parent + 1 < release and release + 1 == result
    released = Enum.at(events, release)
    assert released["decision"] == "current"
    assert released["result_sha256"] == Ipse.JSON.digest([Enum.at(events, result)])
    assert Enum.at(events, result)["value"] == value
    %{parent: parent, set: parent + 1, release: release, result: result}
  end

  defp reference(%{"citation" => citation}),
    do: "#{citation["chunk_id"]}:#{citation["start_byte"]}:#{citation["end_byte"]}"

  # A one-request native Ollama fixture. It answers the request it received with
  # the reverse of the candidate IDs carried on the wire, so a delivered order
  # can only come from this response.
  defp reranker(socket) do
    server =
      Task.async(fn ->
        {:ok, conn} = :gen_tcp.accept(socket, 12_000)
        {headers, payload} = ProviderFixture.request(conn, "")
        order = Enum.reverse(wire_candidates(payload))

        body =
          Jason.encode!(%{
            "model" => "fixture",
            "message" => %{
              "role" => "assistant",
              "content" => Jason.encode!(%{"order" => order})
            },
            "done" => true,
            "done_reason" => "stop",
            "prompt_eval_count" => 1,
            "eval_count" => 1
          }) <> "\n"

        :gen_tcp.send(
          conn,
          "HTTP/1.1 200 Fixture\r\ncontent-type: text/event-stream\r\n" <>
            "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <> body
        )

        :gen_tcp.close(conn)
        {headers, payload}
      end)

    Process.unlink(server.pid)
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    server
  end

  # The helper's user message is a label line followed by the approved
  # instruction and input as one JSON object; Research's input is itself JSON.
  defp wire_candidates(payload) do
    with {:ok, %{"messages" => messages}} when is_list(messages) <- Jason.decode(payload),
         %{"content" => content} when is_binary(content) <- List.last(messages),
         [_, task] <- String.split(content, "\n", parts: 2),
         {:ok, %{"input" => input}} when is_binary(input) <- Jason.decode(task),
         {:ok, %{"candidates" => candidates}} when is_list(candidates) <- Jason.decode(input) do
      Enum.map(candidates, & &1["id"])
    else
      _ -> []
    end
  end

  test "a supplied source is investigated without a model and delivered under the fence", c do
    {socket, origin} = listener()
    sources = [source()]
    {settled, value, events} = investigate(c, config(c, origin), args(nil, sources))
    assert settled == {:ok, []}

    assert %{"status" => "ok", "gaps" => [], "coverage" => coverage} = value
    assert %{"kind" => "provided", "source_count" => 1, "sources" => 1} = coverage

    assert [
             %{
               "citation" => %{
                 "source_id" => "manual:release",
                 "uri" => "local:release-policy",
                 "quote" => "Release requires quiescence.",
                 "origin" => %{"kind" => "provided", "receipt" => nil}
               }
             }
           ] = value["evidence"]

    at = fenced_delivery!(events, value, sources)
    set = Enum.at(events, at.set)
    assert set["transition_ms"] == nil
    assert set["selected_at_ms"] <= coverage["as_of_ms"]
    assert coverage["as_of_ms"] <= Enum.at(events, at.release)["checked_at_ms"]

    refute any?(
             events,
             ~w(extension_action_intent inference_dispatch_intent request_admitted)
           )

    no_connection!(socket)
  end

  test "a registered model rerank of the real request is fenced from set intent through release",
       c do
    {socket, origin} = listener()
    config = config(c, origin)
    supported = match?({:ok, _}, InferenceSlots.status(config, cwd: c.cwd))
    server = if supported, do: reranker(socket)
    expires = System.system_time(:millisecond) + 3_600_000

    sources = [
      source(expires),
      source(nil, "order", "Quiescence precedes release of the release.")
    ]

    {settled, value, events} = investigate(c, config, args("ordered", sources))
    assert {:ok, [{"extension:model.complete", proposed}]} = settled
    assert proposed["extension"] == "research"
    assert proposed["destination"]["origin"] == origin
    assert %{"id" => "reranker", "provider" => "ollama"} = proposed["execution"]
    request = proposed["request"]

    assert %{
             "op" => "model.complete",
             "version" => 2,
             "profile" => "reranker",
             "max_output_bytes" => 8192
           } = request

    assert request["instruction"] =~ "every supplied short candidate id exactly once"

    assert request["response_schema"] == %{
             "type" => "object",
             "properties" => %{
               "order" => %{
                 "type" => "array",
                 "minItems" => 2,
                 "maxItems" => 2,
                 "items" => %{"type" => "string", "enum" => ["e1", "e2"]}
               }
             },
             "required" => ["order"],
             "additionalProperties" => false
           }

    assert %{"query" => @query, "required_count" => 2, "candidates" => candidates} =
             Jason.decode!(request["input"])

    assert Enum.map(candidates, & &1["id"]) == ["e1", "e2"]

    assert Enum.sort(Enum.map(candidates, & &1["quote"])) ==
             Enum.sort(Enum.map(sources, & &1["text"]))

    at = fenced_delivery!(events, value, sources)
    assert Enum.at(events, at.set)["transition_ms"] == expires
    action = index(events, "extension_action_intent")
    assert Enum.at(events, action)["request"] == request
    assert at.set < action and action < at.release
    assert Enum.count(events, &(&1["type"] == "extension_action_intent")) == 1

    if supported do
      # Name the failed stage: a refusal before the fixture saw a request is a
      # fence or gate refusal; a failure after it is transport, parse or release.
      http =
        case Task.yield(server, 2_000) || Task.shutdown(server, :brutal_kill) do
          {:ok, received} -> received
          _ -> nil
        end

      stage =
        cond do
          not any?(events, ["inference_dispatch_intent"]) -> :dispatch_gate
          is_nil(http) -> :physical_send_refused
          value["status"] != "ok" -> :after_send
          true -> :released
        end

      assert stage == :released,
             "registered send stopped at #{stage}: value=#{inspect(value)} http=#{inspect(http)} " <>
               "events=#{inspect(Enum.map(events, & &1["type"]))}"

      assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 1
      dispatch = index(events, "inference_dispatch_intent")
      assert action < dispatch and dispatch < at.release
      {headers, payload} = http
      assert headers =~ "POST /api/chat"
      no_connection!(socket)
      wire = Jason.decode!(payload)
      assert wire["model"] == "fixture"
      assert wire["format"] == request["response_schema"]
      assert wire_candidates(payload) == ["e1", "e2"]

      # The delivered evidence is the lexical order reversed by the model.
      assert Enum.map(value["evidence"], &reference/1) ==
               Enum.reverse(Enum.map(candidates, & &1["ref"]))

      coverage = value["coverage"]
      assert Enum.at(events, at.set)["selected_at_ms"] <= coverage["as_of_ms"]
      assert coverage["as_of_ms"] <= Enum.at(events, at.release)["checked_at_ms"]
      assert Enum.at(events, at.release)["checked_at_ms"] < expires
    else
      # The service ledger refuses the registered route, the worker reports the
      # failed host call and that refusal, which carries no source, is delivered.
      assert %{"status" => "refused", "evidence" => [], "claims" => [], "coverage" => %{}} = value
      assert value["gaps"] == [%{"code" => "host_failed"}]
      refute any?(events, ["inference_dispatch_intent"])
      no_connection!(socket)
      IO.puts("#{inspect(__MODULE__)}: unsupported service filesystem; registered send NOT RUN")
    end
  end

  # The host fences only transitions after selection, so an expiry already in
  # the past records no transition. The worker's own eligibility check excludes
  # the source and its abstention is delivered as a current result.
  test "a source already expired at selection is excluded by the worker, not refused by the host",
       c do
    {socket, origin} = listener()
    config = config(c, origin)
    expired = source(System.system_time(:millisecond) - 1_000)
    stale = [%{"code" => "stale_source", "source_id" => "manual:release"}]

    {settled, value, events} = investigate(c, config, args(nil, [expired]))
    assert settled == {:ok, []}
    assert %{"status" => "abstain", "evidence" => [], "gaps" => ^stale} = value
    assert %{"source_count" => 1, "sources" => 0, "chunks" => 0} = value["coverage"]
    at = fenced_delivery!(events, value, [expired])
    assert Enum.at(events, at.set)["transition_ms"] == nil
    refute any?(events, ~w(extension_action_intent inference_dispatch_intent request_admitted))

    # A selected reranker has no candidates, so no approval or request follows.
    {settled, value, events} = investigate(c, config, args("ordered", [expired]))
    assert settled == {:ok, []}
    assert %{"status" => "abstain", "evidence" => [], "gaps" => ^stale} = value
    fenced_delivery!(events, value, [expired])
    refute any?(events, ~w(extension_action_intent inference_dispatch_intent request_admitted))

    # Beside a current source, only the current one is cited.
    sources = [expired, source(nil, "order", "Quiescence precedes release of the release.")]
    {settled, value, events} = investigate(c, config, args(nil, sources))
    assert settled == {:ok, []}
    assert %{"status" => "ok", "gaps" => ^stale} = value
    assert %{"source_count" => 2, "sources" => 1} = value["coverage"]
    assert [%{"citation" => %{"source_id" => "manual:order"}}] = value["evidence"]
    at = fenced_delivery!(events, value, sources)
    assert Enum.at(events, at.set)["transition_ms"] == nil
    no_connection!(socket)
  end

  # Research's argument schema requires one to ten sources, so an empty or
  # oversized set never reaches the fence: the call is refused at admission
  # without a turn. A set the schema admits but the host cannot capture is
  # refused by the fence before the worker starts.
  test "an empty, oversized or incomplete set is refused before anything is journaled", c do
    {socket, origin} = listener()
    config = config(c, origin)
    unstarted = ~w(extension_invocation_intent provided_source_set_intent)

    for sources <- [[], List.duplicate(source(), 11)] do
      pid = start(c, config)
      id = Session.info(pid).id

      assert {:error, :invalid_extension_call} =
               Session.invoke_export(pid, :command, @name, args(nil, sources))

      refute_received {:ipse, ^pid, {:error, _}}
      refute_received {:ipse, ^pid, {:done, _}}
      assert Session.info(pid).phase == :idle
      assert :ok = Session.close_confirmed(pid)
      {:ok, events} = Journal.load(c.sessions, id)
      refute any?(events, unstarted)
    end

    for incomplete <- [Map.delete(source(), "title"), Map.put(source(), "note", "extra")] do
      pid = start(c, config)
      id = Session.info(pid).id
      assert :ok = Session.invoke_export(pid, :command, @name, args(nil, [incomplete]))
      assert {:error, []} = settle(pid)
      assert_received {:ipse, ^pid, {:error, message}}
      assert message =~ "provided source set was refused before the extension started"
      assert Session.info(pid).extension_result == nil
      assert :ok = Session.close_confirmed(pid)
      {:ok, events} = Journal.load(c.sessions, id)
      refute any?(events, unstarted)
    end

    no_connection!(socket)
  end
end
