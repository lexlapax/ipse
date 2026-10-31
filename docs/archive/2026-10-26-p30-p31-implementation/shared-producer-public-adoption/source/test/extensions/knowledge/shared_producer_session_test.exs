defmodule Ipse.SharedProducerSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Extension.{Artifact, Config, ProjectIdentity, Registry}

  defmodule NoConversation do
    def complete(_, _, _, _), do: raise("producer invoked the conversation model")
  end

  setup do
    artifact =
      case System.get_env("IPSE_SHARED_PRODUCER_ARTIFACT") do
        nil ->
          output = Path.expand("_build/shared-producer-session-" <> Usage.id())
          on_exit(fn -> File.rm_rf!(output) end)
          sdk = Path.dirname(List.to_string(:code.which(Ipse.Extension)))

          {build, status} =
            System.cmd(
              System.find_executable("elixir"),
              [
                "--erl",
                "+S 2:2",
                "extensions/knowledge/build.exs",
                "--sdk",
                sdk,
                "--output",
                output,
                "--package",
                "corpus",
                "--preset",
                "collection-dense"
              ],
              stderr_to_stdout: true
            )

          assert status == 0, build
          output

        selected ->
          Path.expand(selected)
      end

    %{producer_artifact: artifact}
  end

  @tag timeout: 120_000
  test "public source setup and producer inspect are read-only without an existing claim",
       c do
    root = Path.join(System.tmp_dir!(), "ipse-shared-producer-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    server = spawn(fn -> http(listener, owner) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(server, :kill)
    end)

    base = "http://127.0.0.1:#{port}"

    {:ok, artifact} =
      Artifact.import(
        c.producer_artifact,
        Path.join(home, "extensions/artifacts")
      )

    options =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{
        "version" => 1,
        "stores" => %{
          "local" => %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
        },
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{"learned" => %{"kind" => "embedding", "profile" => "encoder"}}
      })

    data = %{
      "extensions" => [
        %{
          "instance" => "documents",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => options,
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false,
          "collection_bindings" => [
            %{
              "version" => 1,
              "instance" => "documents",
              "id" => "documents",
              "scope" => "project",
              "profile" => "document_graph_v1"
            }
          ]
        }
      ]
    }

    {:ok, selected} =
      Config.resolve(
        [%{scope: "operator", path: "/fixture/shared-producer.json", data: data}],
        []
      )

    {:ok, entries} = Registry.prepare(selected, home)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)

    config = %{
      provider: :ollama,
      provider_module: NoConversation,
      model: "unused",
      home: home,
      extensions: entries,
      approval: :ask,
      approval_origin: :interactive,
      headless: false,
      compact: false,
      embedding_profiles: %{
        "encoder" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture",
          "dimensions" => 1024,
          "dimension_mode" => "native",
          "base_url" => base,
          "timeout_ms" => 5000
        }
      }
    }

    request = %{
      "op" => "embedding.create",
      "version" => 2,
      "profile" => "encoder",
      "inputs" => ["binding only"],
      "timeout_ms" => 120_000
    }

    {:ok, binding} = Ipse.Extension.EmbeddingCall.binding(config, request)

    {:ok, selection_sha} =
      Ipse.Config.Profiles.embedding_selection_sha256(
        binding["execution"],
        binding["destination"]
      )

    vectors = %{
      "selection_sha256" => selection_sha,
      "profile" => "encoder",
      "model" => "fixture-model",
      "dimensions" => 1024,
      "encoding" => "float32le"
    }

    facts = %{"kind" => "explicit", "profile" => nil, "version" => 1}
    opts = [config: config, cwd: cwd, state_dir: Path.join(home, "sessions"), subscriber: self()]
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    c = %{pid: pid, home: home, cwd: cwd, dir: opts[:state_dir], id: Session.info(pid).id}

    setup =
      invoke(c, "generation_produce", %{
        "store" => "local",
        "version" => 1,
        "action" => "selection",
        "embedding" => "learned"
      })

    assert setup["status"] == "ok"
    assert setup["coverage"]["selection_sha256"] == selection_sha
    assert setup["coverage"]["configured_profile"]["id"] == "encoder"
    assert setup["coverage"]["configured_profile"]["model"] == "fixture"
    assert setup["coverage"]["reported_model"] == nil
    assert setup["coverage"]["coverage"]["effects_used"] == 0
    assert {:ok, bootstrap_events} = Journal.load(c.dir, c.id)
    assert [bootstrap] = Enum.filter(bootstrap_events, &(&1["type"] == "extension_action_result"))

    assert bootstrap["request"]["op"] == "embedding.profile" and
             bootstrap["approval"] == "not_required"

    assert bootstrap["effect_binding"]["kind"] == "embedding_profile"

    refute Enum.any?(
             bootstrap_events,
             &(&1["type"] in ~w(request_admitted extension_effect_result extension_embedding_request))
           )

    refute_receive {:embedding_wire, _}, 20

    source = %{
      "source_id" => "fixture:public-producer",
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Synthetic public producer",
      "text" => String.duplicate("alpha beta ", 500),
      "uri" => "provided:producer",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

    assert Ipse.Extension.validate(source) == :ok

    result =
      invoke(c, "source", %{"store" => "local", "action" => "put", "args" => source})
      |> finish_source(c)

    assert result["status"] == "ok"

    begun =
      invoke(c, "generation_job", %{
        "store" => "local",
        "action" => "begin",
        "continuation" => nil,
        "vector_selection" => vectors,
        "fact_selection" => facts,
        "response" => "compact_v1"
      })

    token = begun["coverage"]["continuation"]

    args = %{
      "store" => "local",
      "version" => 1,
      "action" => "page",
      "embedding" => "learned",
      "job_id" => token["id"],
      "job_revision" => token["job_revision"],
      "vector_selection" => vectors,
      "fact_selection" => facts
    }

    {:ok, project} = ProjectIdentity.existing(home, cwd)
    ns = Ipse.Extension.CollectionStore.namespace(project["project_id"])
    store = Ipse.Extension.CollectionStore.root(home)

    status = fn ->
      {:ok, value} =
        Ipse.Extension.Collection.execute_profile(
          store,
          ns,
          %{"op" => "status"},
          Usage.id(),
          "document_graph_v1"
        )

      Map.take(value, ~w(generation records operations))
    end

    before = status.()
    assert {:ok, initial_events} = Journal.load(c.dir, c.id)
    before_actions = Enum.count(initial_events, &(&1["type"] == "extension_action_intent"))
    result = invoke(c, "generation_produce", %{args | "action" => "inspect"})
    assert result["status"] == "ok"
    assert result["coverage"]["status"] == "absent"
    assert status.() === before
    assert {:ok, events} = Journal.load(c.dir, c.id)
    assert Enum.count(events, &(&1["type"] == "extension_action_intent")) > before_actions

    refute Enum.any?(
             Enum.drop(events, length(initial_events)),
             &(&1["type"] == "extension_action_intent" and
                 Ipse.Extension.CollectionStore.mutating?(&1["request"]))
           )

    refute Enum.any?(
             events,
             &(&1["type"] in ~w(extension_embedding_request request_admitted extension_effect_result))
           )

    {:ok, physical} =
      Ipse.Extension.Collection.execute_profile(
        store,
        ns,
        %{"op" => "get", "key" => "genproducer.notes"},
        Usage.id(),
        "document_graph_v1"
      )

    assert physical["record"] == nil

    if evidence = System.get_env("IPSE_SHARED_PRODUCER_EVIDENCE_DIR") do
      File.mkdir_p!(evidence)
      File.cp!(Path.join(c.dir, c.id <> ".jsonl"), Path.join(evidence, "synthetic-session.jsonl"))

      File.write!(
        Path.join(evidence, "native-boundary.json"),
        Jason.encode!(%{before: before, after: status.(), claim: nil})
      )

      File.write!(Path.join(evidence, "output.json"), Jason.encode!(result))
    end

    assert {:ok, empty} =
             Ipse.Extension.Collection.execute_profile(
               store,
               ns,
               %{"op" => "get", "key" => "generation.notes"},
               Usage.id(),
               "document_graph_v1"
             )

    assert empty["record"] == nil
    assert {:ok, _} = Session.Saved.restore(events, c.id)
    seen = invoke(c, "generation_produce", %{args | "action" => "inspect"})
    assert seen["coverage"]["status"] == "absent"
    refute seen["coverage"]["coverage"]["validated_inference_receipt_flow"]
    refute seen["coverage"]["coverage"]["retry_available"]
    refute_receive {:embedding_wire, _}, 100

    IO.puts(
      "PUBLIC_SHARED_PRODUCER_INSPECT " <>
        Jason.encode!(%{
          embedding_admissions: 0,
          claim: nil,
          unchanged_native_boundary: status.() === before,
          read_only_inspect: true
        })
    )
  end

  defp finish_source(%{"continuation" => %{"id" => id, "arguments" => args}}, c),
    do: invoke(c, id, args) |> finish_source(c)

  defp finish_source(result, _), do: result

  defp invoke(c, id, args) do
    assert :ok = Session.invoke_export(c.pid, :command, "ext__documents__" <> id, args)
    wait(c)
  end

  defp wait(c) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:collection.store", proposed}} when pid == c.pid ->
        assert Ipse.Extension.CollectionStore.validate(proposed["request"]) == :ok
        assert :ok = Session.approve(pid, ref, true)
        wait(c)

      {:ipse, pid, {:approval, ref, "extension:embedding.create", proposed}} when pid == c.pid ->
        assert proposed["request"]["profile"] == "encoder" and
                 proposed["execution"]["dimensions"] == 1024

        assert proposed["effect_binding"]["kind"] == "embedding"
        assert :ok = Session.approve(pid, ref, true)
        wait(c)

      {:embedding_wire, input} ->
        assert length(input) == 2
        wait(c)

      {:ipse, pid, {:done, :ok}} when pid == c.pid ->
        Session.info(pid).extension_result["value"]

      {:ipse, pid, {:error, error}} when pid == c.pid ->
        flunk(inspect(error))

      {:ipse, pid, _} when pid == c.pid ->
        wait(c)
    after
      30_000 -> flunk("public shared producer timed out")
    end
  end

  defp http(listener, owner) do
    case :gen_tcp.accept(listener, 30_000) do
      {:ok, socket} ->
        wire = read_http(socket, "") |> Jason.decode!()
        send(owner, {:embedding_wire, wire["input"]})

        body =
          Jason.encode!(%{
            "model" => "fixture-model",
            "embeddings" => Enum.map(wire["input"], fn _ -> List.duplicate(1.0, 1024) end),
            "prompt_eval_count" => 2
          })

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
          body
        ])

        :gen_tcp.close(socket)
        http(listener, owner)

      _ ->
        :ok
    end
  end

  defp read_http(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        read_body(socket, body, String.to_integer(size))

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
        read_http(socket, bytes <> more)
    end
  end

  defp read_body(_, bytes, size) when byte_size(bytes) >= size, do: binary_part(bytes, 0, size)

  defp read_body(socket, bytes, size) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
    read_body(socket, bytes <> more, size)
  end
end
