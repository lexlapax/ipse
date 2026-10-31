defmodule Ipse.SharedProducerSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Extension.{Artifact, Config, ProjectIdentity, Registry}

  defmodule NoConversation do
    def complete(_, _, _, _), do: raise("producer invoked the conversation model")
  end

  @tag timeout: 120_000
  test "public source and shared first page use actual registered inference receipts and full approvals" do
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
        Path.expand("_build/shared-producer-corpus-20261029"),
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

    result = invoke(c, "generation_produce", args)
    assert result["status"] == "ok", inspect(result)
    assert result["coverage"]["status"] == "page_ready", inspect(result)
    assert result["coverage"]["coverage"]["validated_inference_receipt_flow"]
    refute result["coverage"]["coverage"]["model_receipt_provenance"]
    assert {:ok, events} = Journal.load(c.dir, c.id)

    admissions =
      Enum.filter(events, &(&1["type"] == "request_admitted" and &1["operation"] == "embedding"))

    effects =
      Enum.filter(
        events,
        &(&1["type"] == "extension_effect_result" and &1["kind"] == "embedding.f32le")
      )

    assert length(admissions) == 1 and length(effects) == 1
    source = hd(effects)
    assert source["data"]["dimensions"] == 1024 and length(source["data"]["vectors"]) == 2
    {:ok, project} = ProjectIdentity.existing(home, cwd)
    ns = Ipse.Extension.CollectionStore.namespace(project["project_id"])
    store = Ipse.Extension.CollectionStore.root(home)

    {:ok, physical} =
      Ipse.Extension.Collection.execute_profile(
        store,
        ns,
        %{"op" => "get", "key" => "genproducer.notes"},
        Usage.id(),
        "document_graph_v1"
      )

    ready = physical["record"]["value"]["parts"] |> Enum.join() |> Jason.decode!()

    if evidence = System.get_env("IPSE_SHARED_PRODUCER_EVIDENCE_DIR") do
      File.mkdir_p!(evidence)
      File.cp!(Path.join(c.dir, c.id <> ".jsonl"), Path.join(evidence, "synthetic-session.jsonl"))
      File.write!(Path.join(evidence, "ready.json"), Jason.encode!(ready))
      File.write!(Path.join(evidence, "output.json"), Jason.encode!(result))
    end

    assert [receipt] = ready["receipts"]

    assert receipt["operation_id"] == source["operation_id"] and
             receipt["source_sha256"] == source["source_sha256"]

    assert receipt["input_sha256"] == Enum.map(source["data"]["vectors"], & &1["input_sha256"])

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
    refute seen["coverage"]["coverage"]["validated_inference_receipt_flow"]
    refute seen["coverage"]["coverage"]["retry_available"]
    refute_receive {:embedding_wire, _}, 100

    IO.puts(
      "PUBLIC_SHARED_PRODUCER " <>
        Jason.encode!(%{
          embedding_admissions: length(admissions),
          vectors: 2,
          effects_used: result["coverage"]["coverage"]["effects_used"],
          reads_used: result["coverage"]["coverage"]["reads_used"],
          ready_bytes: byte_size(Jason.encode!(ready))
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
