defmodule Ipse.SharedProducerGuardSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Extension.{Artifact, Collection, CollectionStore, Config, ProjectIdentity, Registry}
  alias Ipse.Extension.Collection.DocumentStage

  defmodule NoConversation do
    def complete(_, _, _, _), do: raise("document fixture called the conversation model")
  end

  setup_all do
    artifact =
      case System.get_env("IPSE_DOCUMENT_GUARD_ARTIFACT") do
        nil -> private_artifact()
        selected -> Path.expand(selected)
      end

    %{artifact: artifact}
  end

  defp private_artifact do
    root = Path.expand("_build/document-guard-fixture-" <> Usage.id())
    package = Path.join(root, "package/extensions/knowledge")
    File.mkdir_p!(Path.dirname(package))
    {:ok, _} = File.cp_r("extensions/knowledge", package)
    File.cp!("LICENSE", Path.join(root, "package/LICENSE"))
    corpus = Path.join(package, "src/corpus.ex")
    source = File.read!(corpus)
    gate = "finish(state, refused(:shared_producer_source_dispatch_unavailable))"
    true = length(String.split(source, gate)) === 2

    private =
      "advance(IpseKnowledge.Store.Collection.Producer.start(state.resolved, profile, Map.delete(args, \"store\")), %{state | phase: :collection_producer, ctx: %{args: args}})"

    File.write!(corpus, String.replace(source, gate, private, global: false))
    output = Path.join(root, "artifact")
    sdk = :code.which(Ipse.Extension) |> List.to_string() |> Path.dirname()

    {build, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "--erl",
          "+S 2:2",
          Path.join(package, "build.exs"),
          "--sdk",
          sdk,
          "--output",
          output,
          "--package",
          "corpus",
          "--preset",
          "collection-dense"
        ], stderr_to_stdout: true)

    assert status == 0, build
    on_exit(fn -> File.rm_rf!(root) end)
    output
  end

  defp open(c) do
    root = Path.join(System.tmp_dir!(), "ipse-document-guard-session-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)

    on_exit(fn ->
      if evidence = System.get_env("IPSE_DOCUMENT_GUARD_EVIDENCE") do
        destination = Path.join(evidence, "attempt-journals")
        File.mkdir_p!(destination)

        for journal <- Path.wildcard(Path.join(home, "sessions/*.jsonl")) do
          File.cp!(journal, Path.join(destination, Path.basename(journal)))
        end
      end

      File.rm_rf!(root)
    end)

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    server = spawn(fn -> http(listener, owner) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(server, :kill)
    end)

    {:ok, artifact} = Artifact.import(c.artifact, Path.join(home, "extensions/artifacts"))

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

    operator = %{
      "version" => 2,
      "instance" => "documents",
      "id" => "documents",
      "scope" => "project",
      "profile" => "document_graph_v1",
      "source_use" => "shared_producer_v1"
    }

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
          "collection_bindings" => [operator]
        }
      ]
    }

    {:ok, selected} =
      Config.resolve([%{scope: "operator", path: "/fixture/document-guard.json", data: data}], [])

    {:ok, entries} = Registry.prepare(selected, home)
    {:ok, project} = ProjectIdentity.admit(home, cwd, :folder)

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
          "model" => "fixture-model",
          "dimensions" => 1024,
          "dimension_mode" => "native",
          "base_url" => "http://127.0.0.1:#{port}",
          "timeout_ms" => 5000
        }
      }
    }

    request = %{"op" => "embedding.profile", "version" => 1, "profile" => "encoder"}
    scope = %{"embedding_profiles" => Ipse.Config.Profiles.embedding_snapshot(config)}
    {:ok, binding} = Ipse.Extension.EmbeddingCall.profile_binding(scope, request)

    vector = %{
      "selection_sha256" => binding["selection_sha256"],
      "profile" => "encoder",
      "model" => "fixture-model",
      "dimensions" => 1024,
      "encoding" => "float32le"
    }

    facts = %{"kind" => "explicit", "profile" => nil, "version" => 1}
    dir = Path.join(home, "sessions")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, [config: config, cwd: cwd, state_dir: dir, subscriber: self()]}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)

    %{
      pid: pid,
      id: Session.info(pid).id,
      dir: dir,
      home: home,
      cwd: cwd,
      vector: vector,
      facts: facts,
      store: CollectionStore.root(home),
      namespace: CollectionStore.namespace(project["project_id"]),
      operator: Map.delete(operator, "instance")
    }
  end

  defp prepare(c, expiry?) do
    expiry =
      Enum.reduce(1..8, nil, fn i, expiry ->
        expiry =
          if expiry? and i == 8, do: System.system_time(:millisecond) + 30_000, else: expiry

        source = %{
          "source_id" => "fixture:guard:#{i}",
          "generation" => 1,
          "expected_revision" => 0,
          "title" => "Synthetic guard source #{i}",
          "text" => "Exact source #{i}: α beta preserved.",
          "uri" => "provided:guard:#{i}",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => if(i == 8, do: expiry, else: nil)
        }

        assert invoke(c, "source", %{"store" => "local", "action" => "put", "args" => source}).value[
                 "status"
               ] == "ok"

        expiry
      end)

    begun =
      invoke(c, "generation_job", %{
        "store" => "local",
        "action" => "begin",
        "continuation" => nil,
        "vector_selection" => c.vector,
        "fact_selection" => c.facts,
        "response" => "compact_v1"
      })

    assert begun.value["status"] == "ok"
    token = begun.value["coverage"]["continuation"]

    args = %{
      "store" => "local",
      "version" => 1,
      "action" => "page",
      "embedding" => "learned",
      "job_id" => token["id"],
      "job_revision" => token["job_revision"],
      "vector_selection" => c.vector,
      "fact_selection" => c.facts
    }

    {args, expiry}
  end

  defp logical(c, key) do
    {:ok, value} =
      Collection.with_document_read(c.store, c.namespace, fn _, read ->
        DocumentStage.read_value(read, key)
      end)

    value
  end

  defp invoke(c, id, args, expiry \\ nil) do
    assert :ok = Session.invoke_export(c.pid, :command, "ext__documents__" <> id, args)
    wait(c, %{store: 0, embedding: 0, wires: [], expiry: expiry})
  end

  defp wait(c, acc) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:collection.store", proposed}} when pid == c.pid ->
        assert CollectionStore.validate(proposed["request"]) == :ok
        assert proposed["effect_binding"]["operator_binding"] === c.operator
        assert :ok = Session.approve(pid, ref, true)
        wait(c, %{acc | store: acc.store + 1})

      {:ipse, pid, {:approval, ref, "extension:embedding.create", proposed}} when pid == c.pid ->
        assert proposed["request"]["version"] === 2
        assert proposed["request"]["source_guard"]["batch_index"] === acc.embedding
        assert proposed["request"]["expected_selection_sha256"] === c.vector["selection_sha256"]
        assert proposed["effect_binding"]["version"] === 2
        assert proposed["effect_binding"]["source_binding"]["operator_binding"] === c.operator

        if acc.expiry do
          assert acc.embedding == 0
          assert System.system_time(:millisecond) < acc.expiry
          Process.sleep(max(acc.expiry - System.system_time(:millisecond) + 5, 0))
        end

        assert :ok = Session.approve(pid, ref, true)
        wait(c, %{acc | embedding: acc.embedding + 1})

      {:embedding_wire, inputs, bytes} ->
        wait(c, %{acc | wires: acc.wires ++ [%{inputs: inputs, bytes: bytes}]})

      {:ipse, pid, {:done, :ok}} when pid == c.pid ->
        Map.put(acc, :value, Session.info(pid).extension_result["value"])

      {:ipse, pid, {:error, error}} when pid == c.pid ->
        flunk("document producer error: #{inspect(error)}")

      {:ipse, pid, _} when pid == c.pid ->
        wait(c, acc)
    after
      45_000 -> flunk("guarded producer timed out")
    end
  end

  defp save(c, name, output, events, extra) do
    if directory = System.get_env("IPSE_DOCUMENT_GUARD_EVIDENCE") do
      destination = Path.join(directory, name)
      File.mkdir_p!(destination)

      File.cp!(
        Path.join(c.dir, c.id <> ".jsonl"),
        Path.join(destination, "synthetic-session.jsonl")
      )

      File.write!(Path.join(destination, "output.json"), Jason.encode!(output))

      File.write!(
        Path.join(destination, "facts.json"),
        Jason.encode!(
          Map.merge(extra, %{
            events: length(events),
            journal_bytes: File.stat!(Path.join(c.dir, c.id <> ".jsonl")).size
          })
        )
      )
    end
  end

  @tag document_guard_positive: true, timeout: 180_000
  test "actual Session binds native pending claim and four guarded batches before first-page publication",
       c do
    c = open(c)
    {args, _} = prepare(c, false)
    before = logical(c, "generation.notes")
    assert before == nil
    output = invoke(c, "generation_produce", args)
    assert output.value["status"] == "ok"
    assert output.value["coverage"]["status"] == "page_ready"
    assert output.embedding == 4 and length(output.wires) == 4
    assert logical(c, "generation.notes") === before
    ready = logical(c, "genproducer.notes")
    assert ready["value"]["status"] == "ready"
    assert length(ready["value"]["receipts"]) == 4
    {:ok, events} = Journal.load(c.dir, c.id)

    embeddings =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "embedding.create")
      )

    assert length(embeddings) == 4
    assert Enum.map(embeddings, & &1["request"]["source_guard"]["batch_index"]) === [0, 1, 2, 3]
    assert Enum.map(embeddings, & &1["request"]["inputs"]) === Enum.map(output.wires, & &1.inputs)

    assert Enum.all?(
             embeddings,
             &(&1["outcome"]["status"] == "ok" and
                 &1["outcome"]["value"]["reported_model"] == "fixture-model")
           )

    assert {:ok, _} = Session.Saved.restore(events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)

    save(c, "positive", output, events, %{
      ready: ready,
      old_selection: before,
      unchanged_selection: true
    })

    IO.puts(
      "DOCUMENT_GUARD_POSITIVE " <>
        Jason.encode!(%{
          batches: 4,
          store_approvals: output.store,
          body_requests: length(output.wires),
          unchanged_selection: true
        })
    )
  end

  @tag document_guard_expiry: true, timeout: 180_000
  test "source expiring while actual first-batch approval waits sends no HTTP body and keeps pending uncertainty",
       c do
    c = open(c)
    {args, expiry} = prepare(c, true)
    before = logical(c, "generation.notes")
    output = invoke(c, "generation_produce", args, expiry)
    assert output.value["status"] == "refused"
    assert output.embedding == 1 and output.wires == []
    refute_receive {:embedding_wire, _, _}, 200
    assert logical(c, "generation.notes") === before
    pending = logical(c, "genproducer.notes")
    assert pending["value"]["status"] == "pending"
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)

    save(c, "expiry", output, events, %{
      pending: pending,
      expiry: expiry,
      old_selection: before,
      http_body_requests: 0
    })

    IO.puts(
      "DOCUMENT_GUARD_EXPIRY " <>
        Jason.encode!(%{
          approvals: output.embedding,
          http_body_requests: 0,
          pending: true,
          unchanged_selection: true
        })
    )
  end

  defp http(listener, owner) do
    case :gen_tcp.accept(listener, 120_000) do
      {:ok, socket} ->
        bytes = read_http(socket, "")
        wire = Jason.decode!(bytes)
        send(owner, {:embedding_wire, wire["input"], byte_size(bytes)})

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
