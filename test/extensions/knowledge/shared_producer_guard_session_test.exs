defmodule Ipse.SharedProducerGuardSessionTest do
  use ExUnit.Case, async: false
  import Ipse.Test.ResumeAssertions
  alias Ipse.{Journal, Session, Usage}
  alias Ipse.Extension.{Artifact, Collection, CollectionStore, Config, ProjectIdentity, Registry}
  alias Ipse.Extension.Collection.DocumentStage

  defmodule NoConversation do
    def complete(_, _, _, _), do: raise("document fixture called the conversation model")
  end

  setup_all do
    artifact =
      case System.get_env("IPSE_DOCUMENT_GUARD_ARTIFACT") do
        nil -> canonical_artifact()
        selected -> Path.expand(selected)
      end

    %{artifact: artifact}
  end

  defp canonical_artifact do
    root = Path.expand("_build/document-guard-fixture-" <> Usage.id())
    package = Path.join(root, "package/extensions/knowledge")
    File.mkdir_p!(Path.dirname(package))
    {:ok, _} = File.cp_r("extensions/knowledge", package)
    File.cp!("LICENSE", Path.join(root, "package/LICENSE"))
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
        ],
        stderr_to_stdout: true
      )

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

        File.write!(
          Path.join(destination, Path.basename(root) <> "-home.json"),
          Jason.encode!(%{
            root: root,
            home: home,
            cwd: cwd,
            synthetic_fixture: true,
            original_retained_for_read_only_inspection: true
          })
        )
      else
        File.rm_rf!(root)
      end
    end)

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    server = spawn(fn -> http(listener, owner, c[:control_wire] == true) end)

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

    if evidence = System.get_env("IPSE_DOCUMENT_GUARD_EVIDENCE") do
      directory = Path.join(evidence, "attempt-metadata")
      File.mkdir_p!(directory)

      File.write!(
        Path.join(directory, Path.basename(root) <> ".json"),
        Jason.encode!(%{
          host_sha256: hd(entries).identity["host_sha256"],
          artifact_sha256: artifact.digest,
          app_modules: length(Application.spec(:ipse, :modules)),
          operator_binding: Map.delete(operator, "instance"),
          native_home_retained: true,
          synthetic_fixture: true
        })
      )
    end

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
      inference_services: %{
        "local" => %{"version" => 1, "origins" => ["http://127.0.0.1:#{port}"]}
      },
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

    opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})

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
      artifact: c.artifact,
      opts: opts,
      operator: Map.delete(operator, "instance")
    }
  end

  defp prepare(c, expiry?) do
    source_count =
      cond do
        expiry? == :selected -> 1
        expiry? == :v4 -> 6
        expiry? == :multigroup -> 9
        true -> 4
      end

    finite_expiry = if expiry? == :finite, do: System.system_time(:millisecond) + 120_000

    expiry =
      Enum.reduce(1..source_count, nil, fn i, expiry ->
        expiry =
          cond do
            expiry? == :finite -> finite_expiry
            expiry? == true and i == source_count -> System.system_time(:millisecond) + 30_000
            true -> expiry
          end

        text =
          if expiry? == :multigroup or (expiry? in [:v4, :selected] and i == source_count),
            do: "Source #{i}: short final source",
            else: "Source #{i}: " <> String.duplicate("alpha β ", 830)

        assert byte_size(text) in 1..8192

        assert expiry? == :multigroup or (i == source_count and expiry? in [:v4, :selected]) or
                 byte_size(text) > 4096

        source = %{
          "source_id" => "fixture:guard:#{i}",
          "generation" => 1,
          "expected_revision" => 0,
          "title" => "Synthetic guard source #{i}",
          "text" => text,
          "uri" => "provided:guard:#{i}",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => if(expiry? == :finite or i == source_count, do: expiry, else: nil)
        }

        stored = invoke(c, "source", %{"store" => "local", "action" => "put", "args" => source})
        assert finish_source(stored, c).value["status"] == "ok"

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

    args =
      if expiry? in [:v4, :selected, :multigroup] do
        args
        |> Map.put("version", 2)
        |> Map.put("vector_cursor", 0)
        |> Map.put("previous_ready", nil)
      else
        args
      end

    {args, expiry}
  end

  defp finish_source(
         %{value: %{"continuation" => %{"id" => "source", "arguments" => args}}} = result,
         c
       ) do
    assert result.value["status"] == "draft"
    invoke(c, "source", args) |> finish_source(c)
  end

  defp finish_source(result, _), do: result

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
        if hook = c[:before_store_approval], do: hook.(proposed)
        assert :ok = Session.approve(pid, ref, true)
        wait(c, %{acc | store: acc.store + 1})

      {:ipse, pid, {:approval, ref, "extension:embedding.create", proposed}} when pid == c.pid ->
        assert proposed["request"]["version"] === 2
        assert proposed["request"]["source_guard"]["batch_index"] === acc.embedding
        assert proposed["request"]["expected_selection_sha256"] === c.vector["selection_sha256"]
        assert proposed["effect_binding"]["version"] === 2
        assert proposed["effect_binding"]["source_binding"]["operator_binding"] === c.operator

        if hook = c[:before_embedding_approval], do: hook.()

        if acc.expiry do
          assert acc.embedding == 0
          assert System.system_time(:millisecond) < acc.expiry
          Process.sleep(max(acc.expiry - System.system_time(:millisecond) + 5, 0))
        end

        assert :ok = Session.approve(pid, ref, true)
        wait(c, %{acc | embedding: acc.embedding + 1})

      {:embedding_wire, inputs, bytes} ->
        wait(c, %{acc | wires: acc.wires ++ [%{inputs: inputs, bytes: bytes}]})

      {:embedding_wire_blocked, server, inputs, bytes} ->
        if hook = c[:after_embedding_sent], do: hook.()
        send(server, :return_embedding_body)
        wait(c, %{acc | wires: acc.wires ++ [%{inputs: inputs, bytes: bytes}]})

      {:ipse, pid, {:done, :ok}} when pid == c.pid ->
        display = Session.info(pid).extension_result

        value =
          if display["delivery"] do
            assert {:ok, materialized} = Session.materialize_result(pid, display["delivery"])
            assert Ipse.JSON.sha256(materialized.bytes) === display["delivery"]["sha256"]
            materialized.value
          else
            display["value"]
          end

        Map.put(acc, :value, value)

      {:ipse, pid, {:error, error}} when pid == c.pid ->
        {:ok, events} = Journal.load(c.dir, c.id)

        trace =
          events
          |> Enum.take(-12)
          |> Enum.map(fn e ->
            {e["type"], get_in(e, ["request", "request", "op"]),
             get_in(e, ["request", "source_guard"]), get_in(e, ["outcome", "status"])}
          end)

        flunk(
          "document producer error: #{inspect(error)}; recent action types: #{inspect(trace)}"
        )

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
    positive(c, false, "positive")
  end

  @tag public_fact_stage_session: true, timeout: 240_000
  test "public compact explicit fact staging uses guarded Session publication and exact source spans",
       c do
    c = open(c)
    {_args, _} = prepare(c, :selected)
    source_id = "fixture:guard:1"

    facts =
      for n <- 1..2 do
        %{
          "subject" => "Source #{n}",
          "predicate" => "mentions",
          "object" => "fixture",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "spans" => [[0, 0, 6]]
        }
      end

    args = %{
      "store" => "local",
      "version" => 2,
      "action" => "facts",
      "source_id" => source_id,
      "expected_revision" => 0,
      "facts" => facts,
      "continuation" => nil
    }

    invalid = put_in(args, ["facts", Access.at(1), "spans", Access.at(0)], [1, 0, 1])
    assert invoke(c, "generation_produce", invalid).value["status"] == "refused"
    root_key = "facts.notes." <> Ipse.JSON.sha256(source_id)
    assert logical(c, root_key) == nil
    result = finish_public_facts(c, args)
    assert result.value["status"] == "ok" and result.value["coverage"]["facts"] == 2
    root = logical(c, root_key)["value"]
    assert root["facts"] == 2 and root["selection"] == c.facts
    assert length(root["pages"]) == 1
    page = logical(c, hd(root["pages"])["key"])["value"]

    assert Enum.all?(page["rows"], fn row ->
             row["citations"] == [[0, 0, 6, Ipse.JSON.sha256("Source")]]
           end)

    {:ok, events} = Journal.load(c.dir, c.id)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "source_guard"]) == "explicit_fact_projection_v1" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  defp finish_public_facts(c, args) do
    result = invoke(c, "generation_produce", args)

    case result.value["continuation"] do
      %{"id" => "generation_produce", "arguments" => next} -> finish_public_facts(c, next)
      nil -> result
    end
  end

  @tag public_group_append_session: true, timeout: 300_000
  test "public dense producer appends guarded vectors and explicit facts and selects the generation",
       c do
    c = open(c)
    {page_args, _} = prepare(c, :selected)
    page = invoke(c, "generation_produce", page_args)
    assert page.value["status"] == "ok"
    assert page.value["coverage"]["coverage"]["all_pages_ready"]

    append = page_args |> Map.put("action", "append") |> Map.put("continuation", nil)
    before_job = logical(c, "genjob.notes")
    assert invoke(c, "generation_produce", append).value["status"] == "refused"
    assert logical(c, "genjob.notes") === before_job

    fact_args = %{
      "store" => "local",
      "version" => 2,
      "action" => "facts",
      "source_id" => "fixture:guard:1",
      "expected_revision" => 0,
      "facts" => [
        %{
          "subject" => "Source",
          "predicate" => "mentions",
          "object" => "fixture",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "spans" => [[0, 0, 6]]
        }
      ],
      "continuation" => nil
    }

    assert finish_public_facts(c, fact_args).value["status"] == "ok"

    group = finish_public_facts(c, append)
    assert group.value["status"] == "ok", inspect(group.value)
    assert group.value["coverage"]["status"] == "manifests"
    assert group.value["coverage"]["job_progress"]["cursor"] == 1
    assert logical(c, "generation.notes") == nil

    finalize = %{
      "store" => "local",
      "action" => "finalize_paged",
      "guard_sources" => true,
      "continuation" => group.value["coverage"]["continuation"],
      "vector_selection" => c.vector,
      "fact_selection" => c.facts,
      "response" => "compact_v1"
    }

    selected = finish_public_job(c, finalize)
    assert selected.value["status"] == "ok", inspect(selected.value)
    assert selected.value["coverage"]["status"] == "selected"
    assert logical(c, "generation.notes")["value"]["sources"] == 1
    {:ok, events} = Journal.load(c.dir, c.id)

    for guard <- ~w(explicit_fact_group_v1 explicit_generation_selection_v1) do
      assert Enum.any?(events, fn event ->
               event["type"] == "extension_action_result" and
                 get_in(event, ["request", "source_guard"]) == guard and
                 get_in(event, ["outcome", "status"]) == "ok"
             end)
    end

    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  defp finish_public_job(c, args) do
    result = invoke(c, "generation_job", args)

    case result.value["continuation"] do
      %{"id" => "generation_job", "arguments" => next} -> finish_public_job(c, next)
      nil -> result
    end
  end

  @tag public_two_group_handoff: true, timeout: 600_000
  test "public producer builds two groups across confirmed Session handoffs", c do
    c = open(c)
    {first_args, _} = prepare(c, :multigroup)
    first_page = invoke(c, "generation_produce", first_args)
    assert first_page.value["status"] == "ok" and first_page.value["continuation"] == nil
    assert first_page.value["coverage"]["coverage"]["all_pages_ready"]

    for n <- 1..9 do
      args = %{
        "store" => "local",
        "version" => 2,
        "action" => "facts",
        "source_id" => "fixture:guard:#{n}",
        "expected_revision" => 0,
        "facts" => [
          %{
            "subject" => "Source #{n}",
            "predicate" => "mentions",
            "object" => "fixture",
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => nil,
            "valid_to_ms" => nil,
            "spans" => [[0, 0, 6]]
          }
        ],
        "continuation" => nil
      }

      assert finish_public_facts(c, args).value["status"] == "ok"
    end

    c = fresh_public_session(c)

    inspect_args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => c.vector,
      "fact_selection" => c.facts,
      "response" => "compact_v1"
    }

    inspected = invoke(c, "generation_job", inspect_args)

    assert inspected.value["coverage"]["continuation"]["job_revision"] ==
             first_args["job_revision"]

    append = first_args |> Map.put("action", "append") |> Map.put("continuation", nil)
    first_group = finish_public_facts(c, append)
    assert first_group.value["status"] == "ok", inspect(first_group.value)
    assert first_group.value["coverage"]["status"] == "groups"
    assert first_group.value["coverage"]["job_progress"]["cursor"] == 8
    first_token = first_group.value["coverage"]["continuation"]

    assert first_token["unit"] == 0 and first_token["stages"] == [] and
             first_token["write"] == nil

    c = fresh_public_session(c)
    inspected = invoke(c, "generation_job", inspect_args)

    assert inspected.value["coverage"]["continuation"]["job_revision"] ==
             first_token["job_revision"]

    second_args = Map.put(first_args, "job_revision", first_token["job_revision"])
    second_page = invoke(c, "generation_produce", second_args)
    assert second_page.value["status"] == "ok", inspect(second_page.value)
    assert second_page.value["continuation"] == nil
    append = second_args |> Map.put("action", "append") |> Map.put("continuation", nil)
    second_group = finish_public_facts(c, append)
    assert second_group.value["status"] == "ok", inspect(second_group.value)
    assert second_group.value["coverage"]["status"] == "manifests"
    assert second_group.value["coverage"]["job_progress"]["cursor"] == 9
    token = second_group.value["coverage"]["continuation"]
    assert token["unit"] == 0 and token["stages"] == [] and token["write"] == nil

    c = fresh_public_session(c)
    inspected = invoke(c, "generation_job", inspect_args)
    assert inspected.value["coverage"]["continuation"]["job_revision"] == token["job_revision"]

    finalize = %{
      "store" => "local",
      "action" => "finalize_paged",
      "guard_sources" => true,
      "continuation" => inspected.value["coverage"]["continuation"],
      "vector_selection" => c.vector,
      "fact_selection" => c.facts,
      "response" => "compact_v1"
    }

    selected = finish_public_job(c, finalize)
    assert selected.value["status"] == "ok", inspect(selected.value)
    root = logical(c, "generation.notes")["value"]
    assert root["sources"] == 9 and root["facts"] == 9 and root["groups"] == 2
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  defp fresh_public_session(c) do
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, c.opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    %{c | pid: pid, id: Session.info(pid).id}
  end

  @tag public_group_append_multipage: true, timeout: 600_000
  test "public append combines six source fact projections and two vector pages", c do
    c = open(c)
    {page_args, _} = prepare(c, :v4)
    first = invoke(c, "generation_produce", page_args)
    assert first.value["status"] == "ok"
    %{"id" => "generation_produce", "arguments" => next} = first.value["continuation"]
    second = invoke(c, "generation_produce", next)
    assert second.value["status"] == "ok" and second.value["continuation"] == nil
    assert second.value["coverage"]["coverage"]["all_pages_ready"]

    for n <- 1..6 do
      args = %{
        "store" => "local",
        "version" => 2,
        "action" => "facts",
        "source_id" => "fixture:guard:#{n}",
        "expected_revision" => 0,
        "facts" => [
          %{
            "subject" => "Source #{n}",
            "predicate" => "mentions",
            "object" => "fixture",
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => nil,
            "valid_to_ms" => nil,
            "spans" => [[0, 0, 6]]
          }
        ],
        "continuation" => nil
      }

      assert finish_public_facts(c, args).value["status"] == "ok"
    end

    # All page and fact operations have completed; no staged continuation is
    # transferred across Session ownership. Reinspect through the same project.
    {:ok, first_events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(first_events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, c.opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    c = %{c | pid: pid, id: Session.info(pid).id}

    inspect_args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => c.vector,
      "fact_selection" => c.facts,
      "response" => "compact_v1"
    }

    inspected = invoke(c, "generation_job", inspect_args)
    assert inspected.value["status"] == "ok"

    assert inspected.value["coverage"]["continuation"]["job_revision"] ==
             page_args["job_revision"]

    append = page_args |> Map.put("action", "append") |> Map.put("continuation", nil)
    group = finish_public_facts(c, append)
    assert group.value["status"] == "ok", inspect(group.value)
    assert group.value["coverage"]["status"] == "manifests"
    assert group.value["coverage"]["job_progress"]["cursor"] == 6
    assert group.value["coverage"]["job_progress"]["facts"] == 6
    assert logical(c, "generation.notes") == nil

    finalize = %{
      "store" => "local",
      "action" => "finalize_paged",
      "guard_sources" => true,
      "continuation" => group.value["coverage"]["continuation"],
      "vector_selection" => c.vector,
      "fact_selection" => c.facts,
      "response" => "compact_v1"
    }

    result = finish_public_job(c, finalize)
    assert result.value["status"] == "ok", inspect(result.value)
    root = logical(c, "generation.notes")["value"]
    assert root["sources"] == 6 and root["facts"] == 6
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  @tag public_fact_stage_batch: true, timeout: 240_000
  test "public Session stages a 32-fact batch with 256 citations through bounded continuations",
       c do
    c = open(c)
    {_args, _} = prepare(c, :selected)

    facts =
      for n <- 1..32 do
        %{
          "subject" => "Subject #{n}",
          "predicate" => "cites",
          "object" => "source",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "spans" => List.duplicate([0, 0, 6], 8)
        }
      end

    args = %{
      "store" => "local",
      "version" => 2,
      "action" => "facts",
      "source_id" => "fixture:guard:1",
      "expected_revision" => 0,
      "facts" => facts,
      "continuation" => nil
    }

    args =
      1..240
      |> Enum.map(fn width ->
        wide =
          Enum.with_index(facts, 1)
          |> Enum.map(fn {fact, n} ->
            fact
            |> Map.put("subject", String.duplicate("s", width) <> Integer.to_string(n))
            |> Map.put("object", String.duplicate("o", width))
          end)

        %{args | "facts" => wide}
      end)
      |> Enum.take_while(&(byte_size(Jason.encode!(&1)) <= 12_000))
      |> List.last()

    assert byte_size(Jason.encode!(args)) in 11_900..12_000
    assert :ok = Ipse.Extension.validate(%{"id" => "generation_produce", "arguments" => args})
    result = finish_public_facts(c, args)

    assert result.value["status"] == "ok" and result.value["coverage"]["facts"] == 32,
           inspect(result.value, limit: 20)

    root = logical(c, "facts.notes." <> Ipse.JSON.sha256(args["source_id"]))["value"]
    rows = Enum.flat_map(root["pages"], fn ref -> logical(c, ref["key"])["value"]["rows"] end)
    assert length(rows) == 32 and Enum.all?(rows, &(length(&1["citations"]) == 8))
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  @tag public_fact_page_session: true, timeout: 240_000
  test "public fact input page uses a fixed guarded slot and explicit revision", c do
    c = open(c)
    {_args, _} = prepare(c, :selected)
    id = "fixture:guard:1"
    key = Ipse.JSON.sha256(id)
    head = logical(c, "source.notes." <> key)["value"]

    bytes =
      Enum.map_join(head["blocks"], fn ref ->
        logical(c, ref["key"])["value"]["pieces"] |> IO.iodata_to_binary()
      end)

    source_hash = Ipse.JSON.sha256(bytes)

    row = %{
      "subject" => "Source",
      "predicate" => "mentions",
      "object" => "fixture",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => nil,
      "spans" => [[0, 0, 6]]
    }

    page = %{
      "version" => 1,
      "kind" => "explicit_fact_input",
      "source_bundle_sha256" => source_hash,
      "ordinal" => 0,
      "rows" => [row]
    }

    hash = fn value -> Ipse.JSON.sha256(IO.iodata_to_binary(JSON.encode!(value))) end

    manifest = %{
      "version" => 1,
      "source_bundle_sha256" => source_hash,
      "row_count" => 1,
      "rows_sha256" => hash.(%{"rows" => [row]}),
      "page_sha256" => [hash.(page)]
    }

    args = %{
      "store" => "local",
      "version" => 2,
      "action" => "facts_page",
      "source_id" => id,
      "draft_id" => Usage.id(),
      "manifest" => manifest,
      "page" => page,
      "expected_slot_revision" => 0
    }

    slot_query = %{"store" => "local", "version" => 2, "action" => "facts_slots"}
    empty_slots = invoke(c, "generation_produce", slot_query).value["coverage"]["slots"]
    assert length(empty_slots) == 8 and Enum.all?(empty_slots, &(&1["revision"] == 0))

    staged = invoke(c, "generation_produce", args)

    assert staged.value["status"] == "ok" and
             staged.value["coverage"]["status"] == "fact_input_staged"

    slot = logical(c, "factdraft.notes.0")
    {:ok, before_list} = Journal.load(c.dir, c.id)
    listed = invoke(c, "generation_produce", slot_query).value["coverage"]["slots"]
    {:ok, after_list} = Journal.load(c.dir, c.id)

    refute Enum.any?(Enum.drop(after_list, length(before_list)), fn event ->
             get_in(event, ["request", "request", "op"]) == "value.read" and
               String.starts_with?(
                 get_in(event, ["request", "request", "key"]) || "",
                 "factdraft."
               )
           end)

    assert hd(listed) == %{"ordinal" => 0, "revision" => slot["revision"], "occupied" => true}
    assert slot["value"]["page"] == page and slot["value"]["manifest"] == manifest
    assert invoke(c, "generation_produce", args).value["status"] == "refused"
    assert logical(c, "factdraft.notes.0") == slot

    commit = %{
      "store" => "local",
      "version" => 2,
      "action" => "facts_commit",
      "source_id" => id,
      "draft_id" => args["draft_id"],
      "manifest" => manifest,
      "expected_revision" => 0,
      "continuation" => nil
    }

    assert invoke(c, "generation_produce", %{commit | "draft_id" => Usage.id()}).value["status"] ==
             "refused"

    assert logical(c, "facts.notes." <> key) == nil
    first = invoke(c, "generation_produce", commit)
    assert %{"id" => "generation_produce", "arguments" => next} = first.value["continuation"]

    replaced =
      invoke(c, "generation_produce", %{
        args
        | "draft_id" => Usage.id(),
          "expected_slot_revision" => slot["revision"]
      })

    assert replaced.value["status"] == "ok"
    replacement = logical(c, "factdraft.notes.0")
    assert replacement["revision"] > slot["revision"]
    assert invoke(c, "generation_produce", next).value["status"] == "refused"
    assert logical(c, "facts.notes." <> key) == nil

    assert invoke(c, "generation_produce", %{
             args
             | "expected_slot_revision" => replacement["revision"]
           }).value["status"] == "ok"

    completed = finish_public_facts(c, next)
    assert completed.value["status"] == "ok" and completed.value["coverage"]["facts"] == 1
    assert logical(c, "facts.notes." <> key)["value"]["facts"] == 1

    current_slot = logical(c, "factdraft.notes.0")
    head_key = "source.notes." <> key

    hook = fn proposed ->
      if proposed["request"]["source_guard"] == "explicit_fact_input_v1" do
        fixture_replace(c, head_key, logical(c, head_key)["value"])
      end
    end

    stale = %{
      args
      | "draft_id" => Usage.id(),
        "expected_slot_revision" => current_slot["revision"]
    }

    assert invoke(Map.put(c, :before_store_approval, hook), "generation_produce", stale).value[
             "status"
           ] == "refused"

    assert logical(c, "factdraft.notes.0") == current_slot

    {:ok, events} = Journal.load(c.dir, c.id)

    assert Enum.any?(
             events,
             &(get_in(&1, ["request", "source_guard"]) == "explicit_fact_input_v1" and
                 &1["type"] == "extension_action_result" and
                 get_in(&1, ["outcome", "status"]) == "ok")
           )

    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  @tag public_fact_multipart_session: true, timeout: 600_000
  test "eight public fixed slots stage maximum-width facts and assemble the guarded projection",
       c do
    c = open(c)
    {_args, _} = prepare(c, :selected)
    id = "fixture:guard:1"
    source_key = Ipse.JSON.sha256(id)
    head = logical(c, "source.notes." <> source_key)["value"]

    bytes =
      Enum.map_join(head["blocks"], fn ref ->
        logical(c, ref["key"])["value"]["pieces"] |> IO.iodata_to_binary()
      end)

    {:ok, source} = Ipse.JSON.decode_unique(bytes)

    modules = [IpseKnowledge.Evidence, IpseKnowledge.Store.Collection.Projection]
    unloaded = Enum.filter(modules, &(:code.is_loaded(&1) == false))

    for module <- unloaded do
      beam = Path.join([c.artifact, "ebin", Atom.to_string(module)])
      assert {:module, ^module} = :code.load_abs(String.to_charlist(beam))
    end

    on_exit(fn ->
      for module <- unloaded,
          do:
            (
              :code.delete(module)
              :code.soft_purge(module)
            )
    end)

    rows =
      for n <- 1..32 do
        %{
          "subject" =>
            String.duplicate("\\\"", 126) <> String.pad_leading(Integer.to_string(n), 2, "0"),
          "predicate" => String.duplicate("\\\"", 64),
          "object" => String.duplicate("\\\"", 128),
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "spans" => List.duplicate([0, 0, 6], 8)
        }
      end

    assert {:ok, %{pages: pages, manifest: manifest}} =
             apply(IpseKnowledge.Store.Collection.Projection, :fact_input_pages, [source, rows])

    assert length(pages) in 2..8
    draft_id = Usage.id()

    commit = %{
      "store" => "local",
      "version" => 2,
      "action" => "facts_commit",
      "source_id" => id,
      "draft_id" => draft_id,
      "manifest" => manifest,
      "expected_revision" => 0,
      "continuation" => nil
    }

    for {page, index} <- Enum.with_index(pages) do
      args = %{
        "store" => "local",
        "version" => 2,
        "action" => "facts_page",
        "source_id" => id,
        "draft_id" => draft_id,
        "manifest" => manifest,
        "page" => page,
        "expected_slot_revision" => 0
      }

      assert invoke(c, "generation_produce", args).value["status"] == "ok"

      if index == 0 do
        assert invoke(c, "generation_produce", commit).value["status"] == "refused"
        assert logical(c, "facts.notes." <> source_key) == nil
      end
    end

    result = finish_public_facts(c, commit)
    {:ok, debug_events} = Journal.load(c.dir, c.id)

    debug =
      for event <- debug_events,
          event["type"] == "extension_action_result" and
            get_in(event, ["outcome", "status"]) != "ok",
          do:
            {get_in(event, ["request", "request", "op"]), get_in(event, ["outcome", "status"]),
             get_in(event, ["outcome", "value", "code"])}

    assert result.value["status"] == "ok" and result.value["coverage"]["facts"] == 32,
           inspect({result.value, Enum.take(debug, -12)}, limit: 30)

    root = logical(c, "facts.notes." <> source_key)["value"]
    assert root["facts"] == 32

    for {page, index} <- Enum.with_index(pages) do
      assert logical(c, "factdraft.notes.#{index}")["value"]["page"] == page
    end

    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  @tag public_fact_page_expiry: true, timeout: 180_000
  test "fact-input slot refuses when its source expires while approval waits", c do
    c = open(c)
    expires = System.system_time(:millisecond) + 25_000
    id = "fixture:slot-expiry"

    source = %{
      "source_id" => id,
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Synthetic",
      "text" => "Source expiry.",
      "uri" => "provided:expiry",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => expires
    }

    assert finish_source(
             invoke(c, "source", %{"store" => "local", "action" => "put", "args" => source}),
             c
           ).value["status"] == "ok"

    key = Ipse.JSON.sha256(id)
    head = logical(c, "source.notes." <> key)["value"]

    bytes =
      Enum.map_join(head["blocks"], fn ref ->
        logical(c, ref["key"])["value"]["pieces"] |> IO.iodata_to_binary()
      end)

    source_hash = Ipse.JSON.sha256(bytes)

    row = %{
      "subject" => "Source",
      "predicate" => "mentions",
      "object" => "expiry",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => nil,
      "spans" => [[0, 0, 6]]
    }

    page = %{
      "version" => 1,
      "kind" => "explicit_fact_input",
      "source_bundle_sha256" => source_hash,
      "ordinal" => 0,
      "rows" => [row]
    }

    hash = fn value -> Ipse.JSON.sha256(IO.iodata_to_binary(JSON.encode!(value))) end

    manifest = %{
      "version" => 1,
      "source_bundle_sha256" => source_hash,
      "row_count" => 1,
      "rows_sha256" => hash.(%{"rows" => [row]}),
      "page_sha256" => [hash.(page)]
    }

    args = %{
      "store" => "local",
      "version" => 2,
      "action" => "facts_page",
      "source_id" => id,
      "draft_id" => Usage.id(),
      "manifest" => manifest,
      "page" => page,
      "expected_slot_revision" => 0
    }

    hook = fn proposed ->
      if proposed["request"]["source_guard"] == "explicit_fact_input_v1" do
        assert System.system_time(:millisecond) < expires
        Process.sleep(max(expires - System.system_time(:millisecond) + 25, 0))
      end
    end

    assert invoke(Map.put(c, :before_store_approval, hook), "generation_produce", args).value[
             "status"
           ] == "refused"

    assert logical(c, "factdraft.notes.0") == nil
  end

  @tag document_guard_v4_pages: true, timeout: 240_000
  test "actual public v4 continuation produces two guarded pages", c do
    c = open(c)
    {args, _} = prepare(c, :v4)
    before = logical(c, "generation.notes")
    assert before == nil
    first = invoke(c, "generation_produce", args)
    assert first.value["status"] == "ok"
    assert first.value["coverage"]["status"] == "page_ready"
    assert first.embedding == 4 and length(first.wires) == 4
    assert %{"id" => "generation_produce", "arguments" => next} = first.value["continuation"]
    assert next["vector_cursor"] == 8 and next["store"] == "local"
    second = invoke(c, "generation_produce", next)
    assert second.value["status"] == "ok"
    assert second.value["coverage"]["status"] == "page_ready"
    assert second.value["continuation"] == nil
    assert second.value["coverage"]["coverage"]["all_pages_ready"]
    assert second.embedding == 2 and length(second.wires) == 2
    assert logical(c, "generation.notes") === before

    for {cursor, previous} <- [{0, nil}, {8, next["previous_ready"]}] do
      inspected =
        invoke(c, "generation_produce", %{
          args
          | "action" => "inspect",
            "vector_cursor" => cursor,
            "previous_ready" => previous
        })

      assert inspected.value["status"] == "ok"
      assert inspected.value["coverage"]["status"] == "page_ready"
    end

    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
    save(c, "v4-pages", %{first: first, second: second}, events, %{old_selection: before})
  end

  @tag document_guard_selected_reuse: true, timeout: 240_000
  test "a selected synthetic prior group permits native immutable vector-page reuse", c do
    c = open(c)
    {args, _} = prepare(c, :selected)
    first = invoke(c, "generation_produce", args)
    assert first.value["status"] == "ok"
    assert first.value["coverage"]["coverage"]["all_pages_ready"]
    page = first.value["coverage"]["page"]
    assert is_map(page)
    page_before = logical(c, page["key"])
    assert page_before["sha256"] == page["sha256"]

    job_args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => c.vector,
      "fact_selection" => c.facts
    }

    inspected = invoke(c, "generation_job", job_args)

    abort_args = %{
      job_args
      | "action" => "abort",
        "continuation" => inspected.value["coverage"]["continuation"]
    }

    assert invoke(c, "generation_job", abort_args).value["status"] == "ok"

    # This is a trusted fixture bootstrap, not an assertion that public fact
    # production and finalization already exist.
    seeded = seed_selected_group(c)
    assert page["key"] in Enum.map(seeded["values"], & &1["key"])
    root_before = logical(c, "generation.notes")
    assert root_before["value"]["version"] == 2
    begun = invoke(c, "generation_job", %{job_args | "action" => "begin"})
    assert begun.value["status"] == "ok"
    token = begun.value["coverage"]["continuation"]
    next = %{args | "job_id" => token["id"], "job_revision" => token["job_revision"]}
    slot_key = "genproducer4.notes.0"
    original_slot = logical(c, slot_key)["value"]
    forged_sha = String.duplicate("a", 64)

    forged =
      Map.put(original_slot, "page", %{
        "key" => "genvec.notes." <> forged_sha,
        "sha256" => forged_sha,
        "byte_count" => 2
      })

    fixture_replace(c, slot_key, forged)
    {:ok, before_forgery} = Journal.load(c.dir, c.id)
    rejected = invoke(c, "generation_produce", next)
    assert rejected.value["status"] == "refused", inspect(rejected.value)
    assert rejected.embedding == 0 and rejected.wires == []
    {:ok, after_forgery} = Journal.load(c.dir, c.id)
    assert Enum.take(after_forgery, length(before_forgery)) == before_forgery

    refute Enum.any?(Enum.drop(after_forgery, length(before_forgery)), fn event ->
             event["type"] == "extension_action_intent" and
               CollectionStore.mutating?(event["request"])
           end)

    assert logical(c, "generation.notes") == root_before
    fixture_replace(c, slot_key, original_slot)
    {:ok, before} = Journal.load(c.dir, c.id)
    reused = invoke(c, "generation_produce", next)
    assert reused.value["status"] == "ok", inspect(reused.value)
    assert reused.value["coverage"]["page"] == page
    assert reused.embedding == 1
    assert logical(c, page["key"]) == page_before
    assert logical(c, "generation.notes") == root_before
    {:ok, after_events} = Journal.load(c.dir, c.id)
    assert Enum.take(after_events, length(before)) == before

    refute Enum.any?(Enum.drop(after_events, length(before)), fn event ->
             request = get_in(event, ["request", "request"])

             event["type"] == "extension_action_intent" and is_map(request) and
               request["key"] == page["key"] and
               request["op"] in ~w(value.write_parts value.put_inline value.prepare_inline value.open)
           end)

    assert {:ok, _} = Session.Saved.restore(after_events, c.id)

    inspected_again = invoke(c, "generation_job", job_args)

    abort_again = %{
      job_args
      | "action" => "abort",
        "continuation" => inspected_again.value["coverage"]["continuation"]
    }

    assert invoke(c, "generation_job", abort_again).value["status"] == "ok"
    third = invoke(c, "generation_job", %{job_args | "action" => "begin"})
    assert third.value["status"] == "ok"
    token = third.value["coverage"]["continuation"]
    stale_args = %{args | "job_id" => token["id"], "job_revision" => token["job_revision"]}
    fixture_replace(c, "generation.notes", root_before["value"])
    changed_root = logical(c, "generation.notes")
    assert changed_root["value"] == root_before["value"]
    assert changed_root["revision"] != root_before["revision"]
    {:ok, before_stale} = Journal.load(c.dir, c.id)
    stale = invoke(c, "generation_produce", stale_args)
    assert stale.value["status"] == "refused", inspect(stale.value)
    assert stale.embedding == 0 and stale.wires == []
    {:ok, after_stale} = Journal.load(c.dir, c.id)
    assert Enum.take(after_stale, length(before_stale)) == before_stale

    refute Enum.any?(Enum.drop(after_stale, length(before_stale)), fn event ->
             event["type"] == "extension_action_intent" and
               CollectionStore.mutating?(event["request"])
           end)

    assert logical(c, "generation.notes") == changed_root
    assert logical(c, page["key"]) == page_before
    assert :ok = Session.close_confirmed(c.pid)
    assert {:ok, closed_events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(closed_events, c.id)
  end

  defp fixture_replace(c, key, value) do
    row = logical(c, key)
    bytes = Jason.encode!(value)

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "parts" => [bytes],
      "byte_count" => byte_size(bytes),
      "sha256" => Ipse.JSON.sha256(bytes)
    }

    assert {:ok, snapshot} =
             Collection.execute_profile(
               c.store,
               c.namespace,
               %{"op" => "snapshot"},
               Usage.id(),
               "document_graph_v1"
             )

    assert {:ok, _} =
             Collection.execute_profile(
               c.store,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => snapshot["generation"],
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => key, "expected_revision" => row["revision"], "value" => packed}
                 ]
               },
               Usage.id(),
               "document_graph_v1"
             )
  end

  @tag document_guard_selected_delayed: true, timeout: 240_000
  test "selected root change while embedding approval waits refuses before egress", c do
    assert_selected_delayed(c, :root)
  end

  @tag document_guard_selected_delayed: true, timeout: 240_000
  test "source head change while selected embedding approval waits refuses before egress", c do
    assert_selected_delayed(c, :source)
  end

  defp assert_selected_delayed(c, target) do
    c = open(c)
    {args, _} = prepare(c, :selected)
    first = invoke(c, "generation_produce", args)
    assert first.value["status"] == "ok"
    page = first.value["coverage"]["page"]
    page_before = logical(c, page["key"])

    job_args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => c.vector,
      "fact_selection" => c.facts
    }

    inspected = invoke(c, "generation_job", job_args)

    assert invoke(c, "generation_job", %{
             job_args
             | "action" => "abort",
               "continuation" => inspected.value["coverage"]["continuation"]
           }).value["status"] == "ok"

    _ = seed_selected_group(c)
    root = logical(c, "generation.notes")

    changed_key =
      if target == :root,
        do: "generation.notes",
        else: "source.notes." <> Ipse.JSON.sha256("fixture:guard:1")

    changed_before = logical(c, changed_key)
    begun = invoke(c, "generation_job", %{job_args | "action" => "begin"})
    assert begun.value["status"] == "ok"
    token = begun.value["coverage"]["continuation"]
    next = %{args | "job_id" => token["id"], "job_revision" => token["job_revision"]}
    test_owner = self()

    hook = fn ->
      fixture_replace(c, changed_key, changed_before["value"])
      send(test_owner, :selected_source_changed_before_approval)
    end

    changed = invoke(Map.put(c, :before_embedding_approval, hook), "generation_produce", next)
    assert_receive :selected_source_changed_before_approval
    assert changed.embedding == 1
    assert changed.wires == []
    refute_receive {:embedding_wire, _, _}, 200
    assert changed.value["status"] == "refused", inspect(changed.value)
    after_root = logical(c, "generation.notes")
    after_changed = logical(c, changed_key)
    assert after_changed["value"] == changed_before["value"]
    assert after_changed["revision"] != changed_before["revision"]

    if target == :source,
      do: assert(after_root == root),
      else: assert(after_root == after_changed)

    assert logical(c, page["key"]) == page_before
    assert logical(c, "genproducer4.notes.0")["value"]["status"] == "pending"
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, closed} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(closed, c.id)
  end

  @tag document_guard_selected_inflight: true, timeout: 240_000
  test "selected root change after embedding send refuses ready publication", c do
    assert_selected_inflight(c, :root)
  end

  @tag document_guard_selected_inflight: true, timeout: 240_000
  test "source head change after embedding send refuses ready publication", c do
    assert_selected_inflight(c, :source)
  end

  defp assert_selected_inflight(c, target) do
    c = c |> Map.put(:control_wire, true) |> open()
    {args, _} = prepare(c, :selected)
    first = invoke(c, "generation_produce", args)
    assert first.value["status"] == "ok"
    page = first.value["coverage"]["page"]
    page_before = logical(c, page["key"])

    job_args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => c.vector,
      "fact_selection" => c.facts
    }

    inspected = invoke(c, "generation_job", job_args)

    assert invoke(c, "generation_job", %{
             job_args
             | "action" => "abort",
               "continuation" => inspected.value["coverage"]["continuation"]
           }).value["status"] == "ok"

    _ = seed_selected_group(c)
    root = logical(c, "generation.notes")

    changed_key =
      if target == :root,
        do: "generation.notes",
        else: "source.notes." <> Ipse.JSON.sha256("fixture:guard:1")

    changed_before = logical(c, changed_key)
    begun = invoke(c, "generation_job", %{job_args | "action" => "begin"})
    assert begun.value["status"] == "ok"
    token = begun.value["coverage"]["continuation"]
    next = %{args | "job_id" => token["id"], "job_revision" => token["job_revision"]}
    owner = self()

    hook = fn ->
      fixture_replace(c, changed_key, changed_before["value"])
      send(owner, :selected_source_changed_after_send)
    end

    result = invoke(Map.put(c, :after_embedding_sent, hook), "generation_produce", next)
    assert_receive :selected_source_changed_after_send
    assert result.embedding == 1 and length(result.wires) == 1
    assert result.value["status"] == "refused", inspect(result.value)
    changed = logical(c, changed_key)

    assert changed["value"] == changed_before["value"] and
             changed["revision"] != changed_before["revision"]

    if target == :source, do: assert(logical(c, "generation.notes") == root)
    assert logical(c, page["key"]) == page_before
    assert logical(c, "genproducer4.notes.0")["value"]["status"] == "pending"
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, closed} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(closed, c.id)
  end

  @tag document_guard_ready_approval: true, timeout: 240_000
  test "selected root change during ready approval fences the native publication", c do
    assert_ready_approval_fenced(c, :root)
  end

  @tag document_guard_ready_approval: true, timeout: 240_000
  test "source head change during ready approval fences the native publication", c do
    assert_ready_approval_fenced(c, :source)
  end

  defp assert_ready_approval_fenced(c, target) do
    c = open(c)
    {args, _} = prepare(c, :selected)
    first = invoke(c, "generation_produce", args)
    assert first.value["status"] == "ok"
    page = first.value["coverage"]["page"]
    page_before = logical(c, page["key"])

    job_args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => c.vector,
      "fact_selection" => c.facts
    }

    inspected = invoke(c, "generation_job", job_args)

    assert invoke(c, "generation_job", %{
             job_args
             | "action" => "abort",
               "continuation" => inspected.value["coverage"]["continuation"]
           }).value["status"] == "ok"

    _ = seed_selected_group(c)
    root = logical(c, "generation.notes")

    changed_key =
      if target == :root,
        do: "generation.notes",
        else: "source.notes." <> Ipse.JSON.sha256("fixture:guard:1")

    changed_before = logical(c, changed_key)
    begun = invoke(c, "generation_job", %{job_args | "action" => "begin"})
    assert begun.value["status"] == "ok"
    token = begun.value["coverage"]["continuation"]
    next = %{args | "job_id" => token["id"], "job_revision" => token["job_revision"]}
    owner = self()

    hook = fn proposed ->
      request = get_in(proposed, ["request", "request"])

      if is_map(request) and request["op"] == "value.put_inline" and
           request["key"] == "genproducer4.notes.0" do
        case Jason.decode(request["data"]) do
          {:ok, %{"status" => "ready"}} ->
            fixture_replace(c, changed_key, changed_before["value"])
            send(owner, :source_changed_at_ready_approval)

          _ ->
            :ok
        end
      end
    end

    {:ok, before_ready} = Journal.load(c.dir, c.id)
    result = invoke(Map.put(c, :before_store_approval, hook), "generation_produce", next)
    assert_receive :source_changed_at_ready_approval
    assert result.embedding == 1 and length(result.wires) == 1
    assert result.value["status"] == "refused", inspect(result.value)
    changed = logical(c, changed_key)

    assert changed["value"] == changed_before["value"] and
             changed["revision"] != changed_before["revision"]

    if target == :source, do: assert(logical(c, "generation.notes") == root)
    assert logical(c, page["key"]) == page_before
    assert logical(c, "genproducer4.notes.0")["value"]["status"] == "pending"
    {:ok, events} = Journal.load(c.dir, c.id)
    assert Enum.take(events, length(before_ready)) == before_ready

    ready_result =
      Enum.find(Enum.drop(events, length(before_ready)), fn event ->
        request = get_in(event, ["request", "request"])

        event["type"] == "extension_action_result" and is_map(request) and
          request["op"] == "value.put_inline" and request["key"] == "genproducer4.notes.0" and
          match?({:ok, %{"status" => "ready"}}, Jason.decode(request["data"]))
      end)

    assert ready_result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "document_store_refused"}
           }

    assert {:ok, _} = Session.Saved.restore(events, c.id)
    assert :ok = Session.close_confirmed(c.pid)
    {:ok, closed} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(closed, c.id)
  end

  @tag document_guard_owner_loss: true, timeout: 240_000
  test "Session death during guarded embedding closes the socket and never replays", c do
    assert_guarded_owner_loss(c, :empty)
  end

  @tag document_guard_owner_loss: true, timeout: 240_000
  test "Session death during selected-root embedding preserves the selected generation", c do
    assert_guarded_owner_loss(c, :selected)
  end

  defp assert_guarded_owner_loss(c, mode) do
    c = c |> Map.put(:control_wire, true) |> open()
    {args, _} = prepare(c, :selected)

    {args, prior_root, prior_page} =
      if mode == :selected do
        first = invoke(c, "generation_produce", args)
        assert first.value["status"] == "ok"
        page = first.value["coverage"]["page"]
        page_before = logical(c, page["key"])

        job_args = %{
          "store" => "local",
          "action" => "inspect",
          "continuation" => nil,
          "vector_selection" => c.vector,
          "fact_selection" => c.facts
        }

        inspected = invoke(c, "generation_job", job_args)

        assert invoke(c, "generation_job", %{
                 job_args
                 | "action" => "abort",
                   "continuation" => inspected.value["coverage"]["continuation"]
               }).value["status"] == "ok"

        _ = seed_selected_group(c)
        root = logical(c, "generation.notes")
        assert root["value"]["version"] == 2
        begun = invoke(c, "generation_job", %{job_args | "action" => "begin"})
        assert begun.value["status"] == "ok"
        token = begun.value["coverage"]["continuation"]

        {%{args | "job_id" => token["id"], "job_revision" => token["job_revision"]}, root,
         {page["key"], page_before}}
      else
        {args, nil, nil}
      end

    id = c.id
    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)
    owner_ref = Process.monitor(c.pid)

    assert {:ok, prior_events} = Journal.load(c.dir, id)

    assert :ok =
             Session.invoke_export(c.pid, :command, "ext__documents__generation_produce", args)

    {server, inputs} = await_embedding_wire(c)
    assert length(inputs) == 1
    assert logical(c, "genproducer4.notes.0")["value"]["status"] == "pending"
    assert logical(c, "generation.notes") == prior_root
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, _, :killed}, 5_000
    assert_receive {:DOWN, ^guard_ref, :process, _, _}, 5_000
    send(server, {:observe_close, self()})
    assert_receive {:embedding_socket_closed, {:error, :closed}}, 6_000
    assert {:ok, events} = Journal.load(c.dir, id)
    assert Enum.take(events, length(prior_events)) == prior_events
    new_events = Enum.drop(events, length(prior_events))

    assert [_] =
             Enum.filter(
               new_events,
               &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "embedding.create")
             )

    assert [embedding_intent] =
             Enum.filter(
               new_events,
               &(&1["type"] == "extension_action_intent" and
                   get_in(&1, ["request", "op"]) == "embedding.create")
             )

    refute Enum.any?(
             events,
             &(&1["type"] == "extension_action_result" and
                 &1["operation_id"] == embedding_intent["operation_id"])
           )

    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.extension_state.unknown or is_map(saved.extension_state.action)
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(c.opts, :id, id)})

    on_exit(fn -> if Process.alive?(resumed), do: Session.close_confirmed(resumed) end)
    assert Session.info(resumed).phase == :idle
    assert_idle_resume_journal(path, before, id)
    refute_receive {:embedding_wire_blocked, _, _, _}, 500
    assert logical(c, "generation.notes") == prior_root

    if prior_page do
      {key, before_page} = prior_page
      assert logical(c, key) == before_page
    end

    assert logical(c, "genproducer4.notes.0")["value"]["status"] == "pending"
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, closed} = Journal.load(c.dir, id)
    assert {:ok, _} = Session.Saved.restore(closed, id)
  end

  @tag document_guard_ready_owner_loss: true, timeout: 240_000
  test "Session death after native ready publication retains unknown intent and never replays",
       c do
    c = open(c)
    {args, _} = prepare(c, :selected)
    first = invoke(c, "generation_produce", args)
    assert first.value["status"] == "ok"
    page = first.value["coverage"]["page"]
    page_before = logical(c, page["key"])

    job_args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => c.vector,
      "fact_selection" => c.facts
    }

    inspected = invoke(c, "generation_job", job_args)

    assert invoke(c, "generation_job", %{
             job_args
             | "action" => "abort",
               "continuation" => inspected.value["coverage"]["continuation"]
           }).value["status"] == "ok"

    _ = seed_selected_group(c)
    root = logical(c, "generation.notes")
    begun = invoke(c, "generation_job", %{job_args | "action" => "begin"})
    assert begun.value["status"] == "ok"
    token = begun.value["coverage"]["continuation"]
    next = %{args | "job_id" => token["id"], "job_revision" => token["job_revision"]}
    id = c.id
    guard_ref = Process.monitor(:sys.get_state(c.pid).lock_guard)
    owner_ref = Process.monitor(c.pid)
    owner = self()

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{
           "request" => %{
             "op" => "collection.store",
             "request" => %{
               "op" => "value.put_inline",
               "key" => "genproducer4.notes.0",
               "data" => data
             }
           }
         }}}},
      _ ->
        case Jason.decode(data) do
          {:ok, %{"status" => "ready"}} ->
            send(owner, :ready_published_before_receipt)
            receive do: (:release_ready_receipt -> :ok)
            1

          _ ->
            0
        end

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    assert {:ok, prior} = Journal.load(c.dir, id)

    assert :ok =
             Session.invoke_export(c.pid, :command, "ext__documents__generation_produce", next)

    assert await_ready_receipt(c, 0) == 1
    ready_before = logical(c, "genproducer4.notes.0")
    assert ready_before["value"]["status"] == "ready"
    assert logical(c, "generation.notes") == root
    assert logical(c, page["key"]) == page_before
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, _, :killed}, 5_000
    assert_receive {:DOWN, ^guard_ref, :process, _, _}, 5_000
    assert {:ok, events} = Journal.load(c.dir, id)
    assert Enum.take(events, length(prior)) == prior

    [intent] =
      Enum.filter(Enum.drop(events, length(prior)), fn event ->
        request = get_in(event, ["request", "request"])

        event["type"] == "extension_action_intent" and is_map(request) and
          request["op"] == "value.put_inline" and request["key"] == "genproducer4.notes.0" and
          match?({:ok, %{"status" => "ready"}}, Jason.decode(request["data"]))
      end)

    refute Enum.any?(
             events,
             &(&1["type"] == "extension_action_result" and
                 &1["operation_id"] == intent["operation_id"])
           )

    assert {:ok, saved} = Session.Saved.restore(events, id)
    assert saved.extension_state.unknown or is_map(saved.extension_state.action)
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(c.opts, :id, id)})

    on_exit(fn -> if Process.alive?(resumed), do: Session.close_confirmed(resumed) end)
    assert Session.info(resumed).phase == :idle
    assert_idle_resume_journal(path, before, id)
    refute_receive {:embedding_wire, _, _}, 500
    assert logical(c, "genproducer4.notes.0") == ready_before
    assert logical(c, "generation.notes") == root
    assert logical(c, page["key"]) == page_before
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, closed} = Journal.load(c.dir, id)
    assert {:ok, _} = Session.Saved.restore(closed, id)
  end

  defp await_ready_receipt(c, wires) do
    receive do
      :ready_published_before_receipt ->
        wires

      {:ipse, pid, {:approval, ref, "extension:collection.store", proposed}} when pid == c.pid ->
        assert CollectionStore.validate(proposed["request"]) == :ok
        assert :ok = Session.approve(pid, ref, true)
        await_ready_receipt(c, wires)

      {:ipse, pid, {:approval, ref, "extension:embedding.create", _}} when pid == c.pid ->
        assert :ok = Session.approve(pid, ref, true)
        await_ready_receipt(c, wires)

      {:embedding_wire, _, _} ->
        await_ready_receipt(c, wires + 1)

      {:ipse, pid, {:done, status}} when pid == c.pid ->
        flunk("producer completed before receipt interposition: #{inspect(status)}")

      {:ipse, pid, _} when pid == c.pid ->
        await_ready_receipt(c, wires)
    after
      45_000 -> flunk("ready publication did not reach its receipt boundary")
    end
  end

  defp await_embedding_wire(c) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:collection.store", proposed}} when pid == c.pid ->
        assert CollectionStore.validate(proposed["request"]) == :ok
        assert :ok = Session.approve(pid, ref, true)
        await_embedding_wire(c)

      {:ipse, pid, {:approval, ref, "extension:embedding.create", proposed}} when pid == c.pid ->
        assert proposed["request"]["source_guard"]["batch_index"] == 0
        assert :ok = Session.approve(pid, ref, true)
        await_embedding_wire(c)

      {:embedding_wire_blocked, server, inputs, _bytes} ->
        {server, inputs}

      {:ipse, pid, {:done, status}} when pid == c.pid ->
        flunk("producer stopped before guarded embedding: #{inspect(status)}")

      {:ipse, pid, _} when pid == c.pid ->
        await_embedding_wire(c)
    after
      45_000 -> flunk("guarded embedding did not reach the synthetic service")
    end
  end

  defp seed_selected_group(c) do
    source_attrs = %{
      "source_id" => "fixture:guard:1",
      "generation" => 1,
      "title" => "Synthetic guard source 1",
      "text" => "Source 1: short final source",
      "uri" => "provided:guard:1",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "partition" => "notes",
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "local",
        "partition_or_scope" => "notes",
        "receipt" => nil,
        "historical" => false
      }
    }

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    source_command =
      "[attrs] = System.argv(); {:ok, source} = IpseKnowledge.Evidence.collection_source(Jason.decode!(attrs)); IO.puts(Jason.encode!(source))"

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          [
            "-pa",
            Path.join(c.artifact, "ebin"),
            "-e",
            source_command,
            Jason.encode!(source_attrs)
          ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    source = Jason.decode!(output)
    catalog = logical(c, "catalog.notes")["value"]
    pages = Enum.map(catalog["pages"], &logical(c, &1["key"])["value"])
    head = logical(c, "source.notes." <> source["source_key"])["value"]

    input = %{
      "selection" => c.vector,
      "extraction" => c.facts,
      "catalog" => catalog,
      "pages" => pages,
      "bundles" => [%{"source" => source, "head" => head}],
      "finalization" => true,
      "paged_finalization" => true
    }

    path = Path.join(c.home, "synthetic-selected-seed.json")
    File.write!(path, Jason.encode!(input), [:exclusive])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          ["-pa", Path.join(c.artifact, "ebin"), "test/support/shared_selected_seed.exs", path],
        stderr_to_stdout: true
      )

    assert status == 0, output
    seeded = Jason.decode!(output)
    values = seeded["values"] ++ seeded["expected_root_values"]

    values =
      Enum.reject(values, &(&1["key"] == "generation.notes")) ++
        [%{"key" => "generation.notes", "value" => seeded["expected_root"]}]

    changes =
      Enum.map(values, fn item ->
        key = item["key"]
        row = logical(c, key)
        bytes = Jason.encode!(item["value"])

        value = %{
          "version" => 1,
          "kind" => "document_value",
          "parts" => [bytes],
          "byte_count" => byte_size(bytes),
          "sha256" => Ipse.JSON.sha256(bytes)
        }

        %{
          "key" => key,
          "expected_revision" => if(row, do: row["revision"], else: 0),
          "value" => value
        }
      end)

    # Preserve the produced immutable page's revision and prove the fixture's
    # independently assembled page is byte-for-byte the same.
    changes =
      Enum.reject(changes, fn change ->
        if String.starts_with?(change["key"], "genvec.notes.") and logical(c, change["key"]) do
          assert logical(c, change["key"])["value"] == Jason.decode!(hd(change["value"]["parts"]))
          true
        else
          false
        end
      end)

    changes =
      changes
      |> Enum.group_by(& &1["key"])
      |> Enum.map(fn {_key, duplicates} ->
        assert length(Enum.uniq(duplicates)) == 1
        hd(duplicates)
      end)

    assert {:ok, snapshot} =
             Collection.execute_profile(
               c.store,
               c.namespace,
               %{"op" => "snapshot"},
               Usage.id(),
               "document_graph_v1"
             )

    assert {:ok, _} =
             Collection.execute_profile(
               c.store,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => snapshot["generation"],
                 "advance_floor" => true,
                 "changes" => changes
               },
               Usage.id(),
               "document_graph_v1"
             )

    seeded
  end

  @tag document_guard_finite_positive: true, timeout: 180_000
  test "all finite source deadlines remain live through four actual guarded batches", c do
    positive(c, :finite, "finite-positive")
  end

  defp positive(c, mode, evidence_kind) do
    c = open(c)
    {args, deadline} = prepare(c, mode)
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

    if mode == :finite do
      assert is_integer(deadline)
      assert System.system_time(:millisecond) < deadline
      assert Enum.all?(ready["value"]["source_bindings"], &(&1["expires_at_ms"] === deadline))
    end

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

    save(c, evidence_kind, output, events, %{
      ready: ready,
      old_selection: before,
      unchanged_selection: true,
      original_finite_expiry: deadline,
      finished_at_ms: System.system_time(:millisecond)
    })

    IO.puts(
      "DOCUMENT_GUARD_POSITIVE " <>
        Jason.encode!(%{
          batches: 4,
          store_approvals: output.store,
          body_requests: length(output.wires),
          unchanged_selection: true,
          case: evidence_kind,
          original_finite_expiry: deadline,
          finished_at_ms: System.system_time(:millisecond)
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

  defp http(listener, owner, control_wire) do
    case :gen_tcp.accept(listener, 120_000) do
      {:ok, socket} ->
        bytes = read_http(socket, "")
        wire = Jason.decode!(bytes)

        respond? =
          if control_wire do
            send(owner, {:embedding_wire_blocked, self(), wire["input"], byte_size(bytes)})

            receive do
              :return_embedding_body ->
                true

              {:observe_close, observer} ->
                send(observer, {:embedding_socket_closed, :gen_tcp.recv(socket, 0, 5_000)})
                false
            end
          else
            send(owner, {:embedding_wire, wire["input"], byte_size(bytes)})
            true
          end

        body =
          Jason.encode!(%{
            "model" => "fixture-model",
            "embeddings" => Enum.map(wire["input"], fn _ -> List.duplicate(1.0, 1024) end),
            "prompt_eval_count" => 2
          })

        if respond? do
          :gen_tcp.send(socket, [
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
            body
          ])
        end

        :gen_tcp.close(socket)
        http(listener, owner, control_wire)

      {:error, :timeout} ->
        http(listener, owner, control_wire)

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
