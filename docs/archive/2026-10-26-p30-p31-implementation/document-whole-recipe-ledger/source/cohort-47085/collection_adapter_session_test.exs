defmodule Ipse.KnowledgeCollectionAdapterSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, JSON, Usage}
  alias Ipse.Extension.{Artifact, Catalog, Config, Registry, ProjectIdentity, Actions}

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("collection adapter attempted inference")
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-collection-adapter-artifact-" <> Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    files =
      Enum.map(
        ~w(evidence documents documents/zip documents/docx documents/parser_stage documents/pdf store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged),
        &Path.expand("extensions/knowledge/src/#{&1}.ex")
      ) ++ [Path.expand("test/support/collection_adapter_fixture.exs")]

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    assert {"", 0} =
             System.cmd(
               System.find_executable("elixirc"),
               ["--erl", "+S 2:2"] ++
                 paths ++
                 ["-o", Path.join(root, "ebin")] ++ files,
               stderr_to_stdout: true
             )

    File.write!(Path.join(root, "LICENSE"), "Apache-2.0 synthetic repository fixture")

    exports =
      Catalog.empty()
      |> Map.put(
        "commands",
        for(
          id <- ~w(put query inspect lexical index namespace vectors facts),
          do: %{
            "id" => id,
            "description" => "Synthetic packed source fixture",
            "arguments_schema" => %{"type" => "object"},
            "result_schema" => %{"type" => "object"}
          }
        )
      )

    caps =
      ~w(invoke.command invoke.result.pages host.actions host.actions.mixed host.collection.store)

    items =
      for path <- [
            "LICENSE"
            | Enum.map(Path.wildcard(Path.join(root, "ebin/*.beam")), &Path.relative_to(&1, root))
          ] do
        bytes = File.read!(Path.join(root, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    manifest = %{
      "format" => 1,
      "id" => "fixture/collection-adapter",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "IpseTest.CollectionAdapter",
      "license_file" => "LICENSE",
      "files" => items,
      "capabilities" => caps,
      "exports" => exports,
      "options_schema" => %{"type" => "object"},
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))

    if evidence = System.get_env("IPSE_COLLECTION_ARTIFACT_EVIDENCE_DIR") do
      target = Path.expand(evidence)
      File.mkdir_p!(Path.dirname(target))
      refute File.exists?(target)
      assert {:ok, _} = File.cp_r(root, target)

      IO.puts(
        "NAMESPACE_TEST_ARTIFACT " <> JSON.sha256(File.read!(Path.join(root, "extension.json")))
      )
    end

    %{artifact: root}
  end

  setup c do
    native_tmp = System.get_env("IPSE_DOCUMENT_NATIVE_TMPDIR") || System.tmp_dir!()
    root = Path.join(native_tmp, "ipse-collection-adapter-" <> Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(home)
    File.mkdir!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    selected_artifact =
      if c[:public_shared_selected] do
        output = Path.expand("_build/shared-selected-corpus-" <> Usage.id())
        on_exit(fn -> File.rm_rf!(output) end)
        sdk = Path.dirname(List.to_string(:code.which(Ipse.Extension)))

        {build, 0} =
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
              "collection-documents"
            ],
            stderr_to_stdout: true
          )

        assert build ==
                 "Built corpus/collection-documents. Import, trust and enable it explicitly.\n"

        if evidence = System.get_env("IPSE_PUBLIC_CORPUS_ARTIFACT_EVIDENCE_DIR") do
          evidence = Path.join(evidence, JSON.sha256(Atom.to_string(c.test)))
          File.mkdir_p!(Path.dirname(evidence))
          refute File.exists?(evidence)
          assert {:ok, _} = File.cp_r(output, evidence)
        end

        output
      else
        c.artifact
      end

    {:ok, artifact} = Artifact.import(selected_artifact, Path.join(home, "extensions/artifacts"))

    options =
      if c[:public_shared_selected],
        do: %{
          "version" => 1,
          "stores" => %{
            "local" => %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
          },
          "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
          "search" => %{},
          "fetch" => %{},
          "embedding" => %{},
          "rerank" => %{},
          "extraction" => %{}
        },
        else: %{}

    binding = %{
      "version" => 1,
      "instance" => "documents",
      "id" => "documents",
      "scope" => "project",
      "profile" => "document_graph_v1"
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
          "collection_bindings" => [binding]
        }
      ]
    }

    {:ok, selected} =
      Config.resolve([%{scope: "operator", path: "/fixture/adapter.json", data: data}], [])

    {:ok, entries} = Registry.prepare(selected, home)
    assert {:ok, _} = ProjectIdentity.admit(home, cwd, :folder)

    config = %{
      provider: :demo,
      provider_module: NoModel,
      model: "fixture",
      home: home,
      extensions: entries,
      approval: :ask,
      approval_origin: :interactive,
      headless: false,
      compact: false
    }

    opts = [config: config, cwd: cwd, state_dir: Path.join(home, "sessions"), subscriber: self()]
    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)

    %{
      pid: pid,
      id: Session.info(pid).id,
      opts: opts,
      home: home,
      dir: opts[:state_dir],
      fixture_root: root
    }
  end

  defp invoke(c, id, args) do
    assert :ok = Session.invoke_export(c.pid, :command, "ext__documents__" <> id, args)
    wait(c)
  end

  defp wait(c) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:collection.store", proposed}} when pid == c.pid ->
        assert :ok = Ipse.Extension.CollectionStore.validate(proposed["request"])

        if c[:finalization_control] do
          Process.put({:finalization_approvals, c.id}, [
            proposed | Process.get({:finalization_approvals, c.id}, [])
          ])

          if get_in(proposed, ["request", "request", "op"]) == "commit" and
               length(get_in(proposed, ["request", "request", "stages"])) == 3 do
            assert physical(c, "generation.notes") == c.old_selected
            if hook = c[:before_final_approval], do: hook.()
          end
        end

        assert :ok = Session.approve(pid, ref, true)
        wait(c)

      {:ipse, pid, {:done, :ok}} when pid == c.pid ->
        display = Session.info(pid).extension_result

        if Map.has_key?(display, "value") do
          display["value"]
        else
          assert {:ok, materialized} = Session.materialize_result(pid, display["delivery"])
          assert JSON.sha256(materialized.bytes) == display["delivery"]["sha256"]
          materialized.value
        end

      {:ipse, pid, {:error, error}} when pid == c.pid ->
        {:ok, events} = Journal.load(c.dir, c.id)

        trace =
          for e <- events,
              e["type"] == "extension_action_result",
              do: {get_in(e, ["request", "request", "op"]), get_in(e, ["outcome", "status"])}

        flunk(inspect({error, trace}, limit: :infinity))

      {:ipse, pid, _} when pid == c.pid ->
        wait(c)
    after
      20_000 -> flunk("collection adapter timed out")
    end
  end

  defp finish(c, args, result, between \\ fn _ -> :ok end) do
    Enum.reduce_while(1..40, result, fn _, result ->
      if result["status"] == "staged" do
        between.(result)
        next = invoke(c, "put", Map.put(args, "continuation", result["continuation"]))
        {:cont, next}
      else
        {:halt, result}
      end
    end)
  end

  defp finish_vectors(c, args, opened, between \\ fn _ -> :ok end) do
    Enum.reduce_while(1..50, opened, fn _, current ->
      if current["status"] == "staged_vectors" do
        between.(current)
        {:cont, invoke(c, "vectors", Map.put(args, "continuation", current["continuation"]))}
      else
        {:halt, current}
      end
    end)
  end

  defp finish_facts(c, args, opened, between \\ fn _ -> :ok end) do
    Enum.reduce_while(1..50, opened, fn _, current ->
      if current["status"] == "staged_facts" do
        between.(current)
        {:cont, invoke(c, "facts", Map.put(args, "continuation", current["continuation"]))}
      else
        {:halt, current}
      end
    end)
  end

  @tag :public_shared_selected
  @tag :public_generation_job_compat
  test "public generation begin and abort preserve the old selection under ordinary approvals",
       c do
    sources = seed_index_sources(c, [{"fixture:job-source", "Vega source fixture.", nil}])

    selection = %{
      "selection_sha256" => JSON.sha256("fixture-vector-32"),
      "profile" => "fixture-vector",
      "model" => "fixture-float32",
      "dimensions" => 32,
      "encoding" => "float32le"
    }

    args = %{
      "store" => "local",
      "action" => "inspect",
      "continuation" => nil,
      "vector_selection" => selection,
      "fact_selection" => %{"kind" => "explicit", "profile" => nil, "version" => 1}
    }

    seed_shared_generation(c, sources, selection, args["fact_selection"])
    old_selected = physical(c, "generation.notes")

    inspected = invoke(c, "generation_job", args)
    assert inspected["status"] == "ok" and inspected["coverage"]["job"] == nil
    begun = invoke(c, "generation_job", %{args | "action" => "begin"})
    assert begun["status"] == "ok" and begun["coverage"]["job"]["status"] == "groups"
    pending = begun["coverage"]["job"]
    assert physical(c, "generation.notes") == old_selected
    inspected = invoke(c, "generation_job", args)
    token = inspected["coverage"]["continuation"]
    assert inspected["coverage"]["job"] == pending and inspected["coverage"]["stale"] == false
    assert token["id"] == pending["id"] and token["plan_sha256"] == nil and token["unit"] == 0
    assert token["job_revision"] == physical(c, "genjob.notes")["revision"]
    aborted = invoke(c, "generation_job", %{args | "action" => "abort", "continuation" => token})
    assert aborted["status"] == "ok" and aborted["coverage"]["job"]["status"] == "aborted"
    assert physical(c, "generation.notes") == old_selected
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  @tag :public_shared_selected
  @tag :recipe_journal_cost
  @tag timeout: 120_000
  test "actual public source journal cost and known stage-free Session handoff are explicit", c do
    measure = fn context, source_id ->
      args = %{
        "store" => "local",
        "action" => "put",
        "args" => %{
          "source_id" => source_id,
          "generation" => 1,
          "expected_revision" => 0,
          "title" => "Synthetic recipe journal sample",
          "text" => String.duplicate("Visible synthetic evidence. ", 190),
          "uri" => "provided:recipe-journal",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => nil
        }
      }

      opened = invoke(context, "source", args)

      {selected, invocations} =
        Enum.reduce_while(1..20, {opened, 1}, fn _, {value, count} ->
          if value["status"] == "draft" do
            continuation = value["continuation"]
            assert continuation["id"] == "source"
            {:cont, {invoke(context, "source", continuation["arguments"]), count + 1}}
          else
            {:halt, {value, count}}
          end
        end)

      assert selected["status"] == "ok", inspect(selected)
      assert :ok = Session.close_confirmed(context.pid)
      {:ok, events} = Journal.load(context.dir, context.id)
      assert {:ok, _} = Session.Saved.restore(events, context.id)
      path = Path.join(context.dir, context.id <> ".jsonl")
      raw = File.read!(path)
      lines = String.split(raw, "\n", trim: true)
      assert byte_size(raw) == Enum.sum(Enum.map(lines, &(byte_size(&1) + 1)))

      types =
        Enum.reduce(lines, %{}, fn line, acc ->
          type = Jason.decode!(line)["type"]

          Map.update(acc, type, %{"events" => 1, "bytes" => byte_size(line) + 1}, fn old ->
            %{"events" => old["events"] + 1, "bytes" => old["bytes"] + byte_size(line) + 1}
          end)
        end)

      if out = System.get_env("IPSE_RECIPE_JOURNAL_EVIDENCE_DIR") do
        File.mkdir_p!(out)
        File.write!(Path.join(out, source_id <> ".jsonl"), raw, [:exclusive])
      end

      %{
        "bytes" => byte_size(raw),
        "events" => length(events),
        "invocations" => invocations,
        "types" => types,
        "sha256" => JSON.sha256(raw)
      }
    end

    first = measure.(c, "synthetic-first")
    assert {:ok, next_pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, c.opts})
    on_exit(fn -> if Process.alive?(next_pid), do: Session.close_confirmed(next_pid) end)
    next = %{c | pid: next_pid, id: Session.info(next_pid).id}
    refute next.id == c.id
    second = measure.(next, "synthetic-second")

    result = %{
      "first" => first,
      "second" => second,
      "native_status" => native_status(c),
      "input" =>
        "two supplied synthetic plaintext sources, 5130 bytes each; no acquisition/inference/shared producer",
      "session_boundary" =>
        "explicit close after confirmed complete source; no active stage transfer or unknown replay"
    }

    if out = System.get_env("IPSE_RECIPE_JOURNAL_EVIDENCE_DIR"),
      do:
        File.write!(Path.join(out, "summary.json"), Jason.encode!(result, pretty: true), [
          :exclusive
        ])

    IO.puts("RECIPE_JOURNAL_COST " <> Jason.encode!(result))
  end

  @tag :public_shared_selected
  @tag :public_generation_finalization
  @tag :finalization_control
  @tag timeout: 120_000
  test(
    "public finalization stages native reductions and selects the exact canonical root once",
    c,
    do: assert_shared_finalization(c)
  )

  @tag :public_shared_selected
  @tag :public_paged_finalization
  @tag :finalization_control
  @tag :paged_finalization
  @tag timeout: 120_000
  test("explicit paged finalization replaces root1 with a canonical root2 and cited retrieval", c,
    do: assert_shared_finalization(c)
  )

  defp assert_shared_finalization(c) do
    {c, args, expected} = prepare_shared_finalization(c)
    before = native_status(c)
    result = finish_shared_finalization(c, args)
    assert result["status"] == "ok", inspect(result)
    assert result["coverage"]["job"]["status"] == "selected"
    assert result["coverage"]["coverage"]["selected_changed"]
    assert body(physical(c, "generation.notes")) === expected
    assert physical(c, "generation.notes")["revision"] > c.old_selected["revision"]

    inspected =
      invoke(c, "generation_job", %{args | "action" => "inspect", "continuation" => nil})

    refute inspected["coverage"]["stale"]
    approvals = Process.get({:finalization_approvals, c.id}, [])
    assert length(approvals) > 10

    assert Enum.count(
             approvals,
             &(get_in(&1, ["request", "request", "op"]) == "commit" and
                 length(get_in(&1, ["request", "request", "stages"])) == 3)
           ) == 1

    assert Enum.all?(approvals, &(Ipse.Extension.CollectionStore.validate(&1["request"]) == :ok))
    {:ok, events} = Journal.load(c.dir, c.id)

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "extension_action_result")),
             &Actions.valid_result?/1
           )

    assert {:ok, _} = Session.Saved.restore(events, c.id)

    projection =
      invoke(c, "projection_selected", %{
        "store" => "local",
        "source_ids" => ["fixture:finalize"],
        "vector_selection" => args["vector_selection"],
        "fact_selection" => args["fact_selection"],
        "as_of_ms" => 20,
        "top_k" => 1
      })

    assert projection["status"] == "ok" and length(projection["evidence"]) == 1

    IO.puts(
      "PUBLIC_SHARED_FINALIZATION " <>
        Jason.encode!(%{
          "approvals" => length(approvals),
          "before" => before,
          "after" => native_status(c),
          "selected_generation" => expected["generation"],
          "model_calls" => 0
        })
    )
  end

  @tag :public_shared_selected
  @tag :public_generation_finalization_stale
  @tag :finalization_control
  @tag timeout: 120_000
  test "a changed native generation while the final approval waits refuses root selection", c do
    assert_shared_finalization_stale(c)
  end

  @tag :public_shared_selected
  @tag :public_paged_finalization_stale
  @tag :finalization_control
  @tag :paged_finalization
  @tag timeout: 120_000
  test("root2 refuses a changed native generation while its final approval waits", c,
    do: assert_shared_finalization_stale(c)
  )

  defp assert_shared_finalization_stale(c) do
    {c, args, _} = prepare_shared_finalization(c)

    c =
      Map.put(c, :before_final_approval, fn ->
        catalog = physical(c, "catalog.notes")
        replace(c, [{"catalog.notes", catalog["value"]}])
      end)

    refused = finish_shared_finalization(c, args)
    assert refused["status"] == "refused", inspect(refused)
    assert physical(c, "generation.notes") == c.old_selected
    assert body(physical(c, "genjob.notes"))["status"] == "reducing"
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)

    IO.puts(
      "PUBLIC_SHARED_FINALIZATION_STALE " <>
        Jason.encode!(%{"selected_unchanged" => true, "model_calls" => 0})
    )
  end

  @tag :public_shared_selected
  @tag :public_generation_finalization_unknown
  @tag :finalization_control
  @tag timeout: 120_000
  test "owner loss after native final selection retains unknown intent and never replays", c do
    assert_shared_finalization_unknown(c)
  end

  @tag :public_shared_selected
  @tag :public_paged_finalization_unknown
  @tag :finalization_control
  @tag :paged_finalization
  @tag timeout: 120_000
  test("root2 native publication before owner loss stays unknown without replay", c,
    do: assert_shared_finalization_unknown(c)
  )

  defp assert_shared_finalization_unknown(c) do
    {c, args, expected} = prepare_shared_finalization(c)
    ready = finish_shared_finalization(c, args, "select")
    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)
    owner = self()

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{
           "request" => %{
             "op" => "collection.store",
             "request" => %{"op" => "commit", "stages" => stages}
           }
         }}}},
      _
      when length(stages) == 3 ->
        send(owner, :namespace_published_before_receipt)
        receive do: (:release_namespace_unknown -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_namespace_unknown) end)

    assert :ok =
             Session.invoke_export(
               c.pid,
               :command,
               "ext__documents__generation_job",
               ready["continuation"]["arguments"]
             )

    approve_until_namespace_publication(c)
    assert body(physical(c, "generation.notes")) === expected
    status = native_status(c)
    monitor = Process.monitor(c.pid)
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    {:ok, events} = Journal.load(c.dir, c.id)
    assert List.last(events)["type"] == "extension_action_intent"
    assert length(get_in(List.last(events), ["request", "request", "stages"])) == 3
    assert {:ok, restored} = Session.Saved.restore(events, c.id)
    assert restored.extension_state.action === List.last(events)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(c.opts, :id, c.id)}
             )

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, after_events} = Journal.load(c.dir, c.id)
    assert Enum.take(after_events, length(events)) === events
    tail = Enum.drop(after_events, length(events))

    assert Enum.all?(
             tail,
             &(&1["type"] in ~w(session_release_owner_started session_release_intent lifecycle_epoch_started lifecycle_epoch_closed lifecycle_recording_stopped execution_mode_resumed))
           )

    assert {:ok, after_restore} = Session.Saved.restore(after_events, c.id)
    assert after_restore.extension_state.action === List.last(events)
    assert native_status(c) == status

    IO.puts(
      "PUBLIC_SHARED_FINALIZATION_UNKNOWN " <>
        Jason.encode!(%{
          "native_selected" => true,
          "journal_result_unknown" => true,
          "replayed" => false,
          "resume_tail_types" => Enum.map(tail, & &1["type"]),
          "model_calls" => 0
        })
    )
  end

  @tag :public_shared_selected
  @tag :public_paged_large_inspection
  @tag timeout: 120_000
  test "maximum Job3 metadata is read and materialized through actual SDK2 result pages", c do
    {c, _, _} = prepare_shared_finalization(c)
    path = Path.join(c.fixture_root, "trusted-large-job-parent.json")
    parent = physical(c, "generation.notes")

    File.write!(
      path,
      Jason.encode!(%{"parent" => body(parent), "revision" => parent["revision"]})
    )

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {bytes, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          [
            "-pa",
            Path.join(c.artifact, "ebin"),
            "test/support/generation_paged_large_seed.exs",
            path
          ],
        stderr_to_stdout: true
      )

    supplied = Jason.decode!(bytes)
    # Only synthetic metadata is seeded. This read-only inspection does not
    # qualify source population, semantic completion or root publication.
    replace(c, [
      {"catalog.notes", packed(supplied["catalog"])},
      {"genjob.notes", packed(supplied["job"])}
    ])

    before = native_status(c)
    result = invoke(c, "generation_job", supplied["arguments"])
    assert result["coverage"]["job"] === supplied["job"]
    refute result["coverage"]["stale"]
    display = Session.info(c.pid).extension_result
    assert display["delivery"]["kind"] == "saved.result"
    assert display["delivery"]["byte_count"] > 32768
    assert native_status(c) == before
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, saved} = Session.Saved.restore(events, c.id)
    assert saved.extension_state.last_display == display
    assert {:ok, materialized} = Session.materialize_result(c.pid, display["delivery"])
    assert materialized.value === result

    IO.puts(
      "PUBLIC_JOB3_PAGES " <>
        Jason.encode!(%{
          "bytes" => display["delivery"]["byte_count"],
          "entity_refs" => length(supplied["job"]["reduction"]["entity_pages"]),
          "native_unchanged" => true,
          "model_calls" => 0
        })
    )
  end

  defp prepare_shared_finalization(c) do
    sources =
      seed_index_sources(c, [{"fixture:finalize", "Vega supplied finalization evidence.", nil}])

    selection = %{
      "selection_sha256" => JSON.sha256("fixture-finalization"),
      "profile" => "fixture",
      "model" => "fixture",
      "dimensions" => 1,
      "encoding" => "float32le"
    }

    extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}
    seeded = seed_shared_generation(c, sources, selection, extraction, true)
    old_selected = physical(c, "generation.notes")
    c = Map.put(c, :old_selected, old_selected)

    args = %{
      "store" => "local",
      "action" => "begin",
      "continuation" => nil,
      "vector_selection" => selection,
      "fact_selection" => extraction
    }

    begun = invoke(c, "generation_job", args)
    assert begun["status"] == "ok", inspect(begun)
    # Supplied, already captured group data and pending job are trusted fixtures;
    # this section qualifies native finalization, not acquisition/model capture.
    pending =
      begun["coverage"]["job"]
      |> Map.put("status", "manifests")
      |> Map.put("cursor", length(sources))
      |> Map.put("summaries", [seeded["summary_ref"]])
      |> Map.put("facts", seeded["facts"])

    replace(c, [
      {seeded["summary"]["key"], packed(seeded["summary"]["value"])},
      {"genjob.notes", packed(pending)}
    ])

    inspected = invoke(c, "generation_job", %{args | "action" => "inspect"})

    {c,
     %{
       args
       | "action" => if(c[:paged_finalization], do: "finalize_paged", else: "finalize"),
         "continuation" => inspected["coverage"]["continuation"]
     }, seeded["expected_root"]}
  end

  defp finish_shared_finalization(c, args, stop_phase \\ nil) do
    Enum.reduce_while(1..100, args, fn _, arguments ->
      result = invoke(c, "generation_job", arguments)

      if result["status"] == "draft" do
        assert physical(c, "generation.notes") == c.old_selected

        if stop_phase != nil and
             get_in(result, ["coverage", "job", "reduction", "phase"]) == stop_phase,
           do: {:halt, result},
           else: {:cont, result["continuation"]["arguments"]}
      else
        {:halt, result}
      end
    end)
  end

  @tag :public_shared_selected
  @tag :public_shared_hydration
  @tag timeout: 120_000
  test "public Corpus reads fully hydrated selected supplied projections with Word citations and current-source refusal",
       c do
    ids = for n <- 0..6, do: "fixture:selected-#{n}"
    word = partial_word_source(c)

    sources =
      seed_index_sources(
        c,
        Enum.map(
          ids,
          &{&1, String.duplicate("Vega orbit ", 1800),
           if(String.ends_with?(&1, "-6"), do: 15, else: nil)}
        ) ++ [word]
      )

    selection = %{
      "selection_sha256" => JSON.sha256("fixture-vector-32"),
      "profile" => "fixture-vector",
      "model" => "fixture-float32",
      "dimensions" => 32,
      "encoding" => "float32le"
    }

    extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}
    seed_shared_generation(c, sources, selection, extraction)
    before = native_status(c)

    args = %{
      "store" => "local",
      "source_ids" => [word["source_id"], hd(ids)],
      "vector_selection" => selection,
      "fact_selection" => extraction,
      "as_of_ms" => 20,
      "top_k" => 8
    }

    result = invoke(c, "projection_selected", args)
    assert result["status"] == "partial", inspect(result)
    refute result["coverage"]["complete"]
    assert length(result["claims"]) == 2 and length(result["evidence"]) == 2
    assert result["coverage"]["facts"] == 4 and result["coverage"]["eligible_facts"] == 2
    assert Enum.count(result["gaps"], &(&1["code"] == "excluded_fact")) == 2

    assert Enum.all?(
             result["claims"],
             &(&1["predicate"] == "quotes" and &1["object"] == hd(&1["citations"])["quote"])
           )

    assert Enum.any?(result["evidence"], &is_map(&1["document"]))
    assert Enum.any?(result["gaps"], &(&1["code"] == "partial_document" and &1["warnings"] != []))
    assert result["coverage"]["effects_used"] == 0 and result["coverage"]["reads_used"] < 512
    refute result["coverage"]["later_use_authority"]
    assert native_status(c) == before
    changed = put_in(args, ["vector_selection", "model"], "different-model")
    assert invoke(c, "projection_selected", changed)["status"] == "refused"

    assert invoke(c, "projection_selected", %{args | "source_ids" => [List.last(ids)]})["status"] ==
             "refused"

    root = body(physical(c, "generation.notes"))
    manifest = body(physical(c, hd(root["manifests"])["key"]))
    header = body(physical(c, hd(manifest["rows"])["header"]["key"]))
    vector_ref = hd(header["vector_pages"])
    vector_page = body(physical(c, vector_ref["key"]))
    forged = put_in(vector_page, ["rows", Access.at(0), Access.at(2)], String.duplicate("0", 64))
    replace(c, [{vector_ref["key"], packed(forged)}])
    corrupt = invoke(c, "projection_selected", args)

    assert corrupt["status"] == "refused" and corrupt["claims"] == [] and
             corrupt["evidence"] == []

    replace(c, [{vector_ref["key"], packed(vector_page)}])
    catalog = body(physical(c, "catalog.notes"))
    replace(c, [{"catalog.notes", packed(Map.update!(catalog, "floor", &(&1 + 1)))}])
    assert invoke(c, "projection_selected", args)["status"] == "refused"

    IO.puts(
      "SHARED_SELECTED_PUBLIC " <>
        Jason.encode!(%{
          "sources" => result["coverage"]["sources"],
          "vectors" => result["coverage"]["vectors"],
          "facts" => result["coverage"]["facts"],
          "reads" => result["coverage"]["reads_used"],
          "effects" => 0,
          "typed_word_citations" => Enum.count(result["evidence"], &is_map(&1["document"]))
        })
    )
  end

  @tag :shared_projection_preview
  @tag timeout: 120_000
  test "current gated Session captures eight source bundles and previews lossless shared pages without publication",
       c do
    ids = for n <- 0..6, do: "fixture:shared-#{n}"
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {bytes, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          [
            "-pa",
            Path.join(c.artifact, "ebin"),
            "-e",
            "IO.puts(Jason.encode!(IpseTest.CollectionAdapter.source(1, true)))"
          ],
        stderr_to_stdout: true
      )

    word = Jason.decode!(bytes)

    seed_index_sources(
      c,
      Enum.map(ids, &{&1, String.duplicate("Vega orbit ", 1800), nil}) ++ [word]
    )

    ids = ids ++ [word["source_id"]]
    before = native_status(c)
    preview = invoke(c, "vectors", %{"shared" => true, "source_ids" => ids})
    assert preview["status"] == "preview", inspect(preview)

    assert preview["sources"] == 8 and preview["vectors"] >= 80 and preview["facts"] == 160 and
             preview["entities"] == 40

    assert preview["partial_sources"] == 1 and preview["document_warnings"] > 0
    assert preview["document_citations"] > 0
    assert preview["noncanonical_fact_refused"]
    assert preview["source_pages"] == 1 and preview["vector_pages"] >= 10
    assert preview["fact_pages"] <= 2
    assert preview["maximum_value_bytes"] <= 48 * 1024 and preview["header_bytes"] <= 48 * 1024
    refute preview["publication_attempted"]
    refute preview["coverage"]["evidence_readable"]
    assert native_status(c) == before
    {:ok, events} = Journal.load(c.dir, c.id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_intent"))

    assert Enum.all?(
             actions,
             &(get_in(&1, ["request", "request", "op"]) in ~w(snapshot value.stat value.read))
           )

    IO.puts("SHARED_READONLY_PREVIEW " <> Jason.encode!(preview))
  end

  @tag :shared_directory_preview
  test "actual Session binds directory lookup to captured catalog pages and refuses stale or forged bindings",
       c do
    ids = for n <- 0..7, do: "fixture:directory-#{n}"
    seed_index_sources(c, Enum.map(ids, &{&1, "Vega orbit source #{&1}.", nil}))
    before = native_status(c)

    preview =
      invoke(c, "vectors", %{
        "shared" => true,
        "directory" => true,
        "source_ids" => ids,
        "dimensions" => 32
      })

    assert preview["status"] == "preview", inspect(preview)
    assert preview["directory_groups"] == 1 and preview["directory_values"] == 2
    assert preview["directory_root_bytes"] < 16 * 1024
    assert preview["directory_lookup"]["directory_complete"]
    assert preview["directory_lookup"]["selected_headers"] == 1
    refute preview["directory_lookup"]["projection_payloads_read"]
    refute preview["directory_lookup"]["evidence_readable"]
    refute preview["directory_publication_attempted"]
    assert native_status(c) == before
    {:ok, events} = Journal.load(c.dir, c.id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_intent"))
    assert length(actions) < 512

    assert Enum.all?(
             actions,
             &(get_in(&1, ["request", "request", "op"]) in ~w(snapshot value.stat value.read))
           )

    IO.puts(
      "SHARED_DIRECTORY_PREVIEW " <>
        Jason.encode!(%{"result" => preview, "actual_read_calls" => length(actions)})
    )
  end

  @tag :document_deadline_diagnostic
  test "current SDK preserves the closed deadline-unavailable refusal without fallback or mutation",
       c do
    before = native_status(c)
    refused = invoke(c, "put", %{"raw_value" => true})
    assert refused == %{"status" => "refused", "code" => "document_store_deadline_unavailable"}
    assert native_status(c) == before
    {:ok, events} = Journal.load(c.dir, c.id)

    failed =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["outcome", "status"]) == "failed")
      )

    [event] = failed
    assert get_in(event, ["outcome", "value", "code"]) == "document_store_deadline_unavailable"
    assert Actions.valid_result?(event)

    refute Actions.valid_result?(
             put_in(event, ["outcome", "value", "code"], "invented_deadline_status")
           )

    intents = Enum.filter(events, &(&1["type"] == "extension_action_intent"))
    mutating = Enum.filter(intents, &Ipse.Extension.CollectionStore.mutating?(&1["request"]))
    assert length(mutating) == 1
    assert hd(mutating)["request"]["request"]["op"] == "value.write_parts"
    assert physical(c, "fixture.value") == nil
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  @tag :fused_value_session
  @tag timeout: 120_000
  test "actual SDK packets fall back to one part and resume a known bounded partial write", c do
    opened = invoke(c, "put", %{"raw_value" => true, "effects_used" => 14})
    assert opened["status"] == "staged", inspect(opened)
    assert opened["coverage"]["effects_used"] == 16
    active = opened["continuation"]["active"]
    assert active["offset"] == 12288 and active["state"] == "open"
    assert native_status(c)["operations"] == 2
    assert physical(c, "fixture.value") == nil
    header = physical(c, "host.stage.#{active["slot"]}.header")["value"]
    assert header["write_publish"] === true
    assert header["offset"] == active["offset"]
    stored = invoke(c, "put", %{"raw_value" => true, "continuation" => opened["continuation"]})
    assert stored["status"] == "stored", inspect(stored)
    expected = %{"paragraphs" => List.duplicate(String.duplicate("\\", 2048), 6)}
    assert body(physical(c, "fixture.value")) == expected
    assert stored["record"]["sha256"] == JSON.sha256(Jason.encode!(expected))
    assert native_status(c)["operations"] == 4
    {:ok, events} = Journal.load(c.dir, c.id)
    results = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    assert Enum.all?(results, &Actions.valid_result?/1)

    writes =
      Enum.filter(results, &(get_in(&1, ["request", "request", "op"]) == "value.write_parts"))

    assert length(writes) == 4
    assert Enum.any?(writes, &(length(&1["request"]["request"]["data"]) == 1))
    assert Enum.any?(writes, &(length(&1["request"]["request"]["data"]) == 2))

    frames =
      for event <- writes do
        assert length(event["request"]["request"]["data"]) in 1..2
        frame = %{"api_version" => 1, "kind" => "host_call", "request" => event["request"]}
        assert :ok = Ipse.Extension.validate(frame)
        byte_size(Jason.encode!(frame))
      end

    assert Enum.max(frames) <= 16384
    [first | _] = writes

    refute Actions.valid_result?(
             update_in(first, ["outcome", "value", "result", "write", "offset"], &(&1 + 1))
           )

    refute Actions.valid_result?(
             put_in(first, ["outcome", "value", "result", "write", "publish"], false)
           )

    IO.puts(
      "FUSED_ESCAPED_FRAMES " <> Jason.encode!(%{"bytes" => frames, "native_mutations" => 4})
    )
  end

  @tag :fused_value_unknown
  @tag timeout: 120_000
  test "actual owner loss after fused final publication preserves intent and does not replay",
       c do
    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)
    owner = self()

    callback = fn
      count,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{
           "request" => %{
             "op" => "collection.store",
             "request" => %{"op" => "value.write_parts"} = r
           }
         }}}},
      _ ->
        if count == 0 and
             r["offset"] + Enum.sum(Enum.map(r["data"], &byte_size/1)) == r["byte_count"] do
          send(owner, :namespace_published_before_receipt)
          receive do: (:release_namespace_unknown -> :ok)
          1
        else
          count
        end

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_namespace_unknown) end)

    assert :ok =
             Session.invoke_export(c.pid, :command, "ext__documents__put", %{"raw_value" => true})

    approve_until_namespace_publication(c)
    assert physical(c, "fixture.value") != nil
    status = native_status(c)
    monitor = Process.monitor(c.pid)
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    {:ok, events} = Journal.load(c.dir, c.id)
    assert List.last(events)["type"] == "extension_action_intent"
    assert get_in(List.last(events), ["request", "request", "op"]) == "value.write_parts"

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(c.opts, :id, c.id)}
             )

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, ^events} = Journal.load(c.dir, c.id)
    assert native_status(c) == status
  end

  @tag :fused_word_session
  @tag timeout: 120_000
  test "actual Word ingestion sends two-part packets and returns an exact source-local citation",
       c do
    args = %{"large_blocks" => true}
    stored = finish(c, args, invoke(c, "put", args))
    assert stored["status"] == "stored", inspect(stored)
    result = invoke(c, "query", %{"query" => "Nocturne migration"})
    [hit] = result["evidence"]
    assert hit["citation"]["quote"] =~ "Nocturne migration needs review."
    assert hit["citation"]["document"]["locator"]["paragraph"] == 1
    assert JSON.sha256?(hit["citation"]["document"]["original_sha256"])
    {:ok, events} = Journal.load(c.dir, c.id)

    writes =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "value.write_parts")
      )

    assert Enum.any?(writes, &(length(&1["request"]["request"]["data"]) == 2))

    frames =
      for event <- writes do
        assert Actions.valid_result?(event)
        frame = %{"api_version" => 1, "kind" => "host_call", "request" => event["request"]}
        assert :ok = Ipse.Extension.validate(frame)
        byte_size(Jason.encode!(frame))
      end

    assert Enum.max(frames) <= 16384

    IO.puts(
      "FUSED_WORD_BUDGET " <>
        Jason.encode!(%{
          "native" => native_status(c),
          "maximum_frame_bytes" => Enum.max(frames),
          "fused_writes" => length(writes)
        })
    )
  end

  @tag :packed_fact_session
  @tag timeout: 120_000
  test "packed facts retain exact Word citations and warnings while their old selection remains available",
       c do
    put_args = %{"many" => true}
    assert finish(c, put_args, invoke(c, "put", put_args))["status"] == "stored"
    tiny = %{"tiny" => true, "source_id" => "fixture:fact-vector", "text" => "Vega vector."}
    assert finish(c, tiny, invoke(c, "put", tiny))["status"] == "stored"
    vector_args = %{"action" => "put", "source_id" => tiny["source_id"]}

    assert finish_vectors(c, vector_args, invoke(c, "vectors", vector_args))["status"] ==
             "stored_vectors"

    assert invoke(c, "vectors", %{vector_args | "action" => "get"})["vectors"] == 1
    vector_root = body(physical(c, "vector.notes." <> JSON.sha256(tiny["source_id"])))

    assert Enum.sort(Map.keys(vector_root)) ==
             Enum.sort(
               ~w(version kind recipe revision source_key source_generation content_sha256 source_bundle_sha256 selection vectors catalog_sha256 catalog_generation floor pages)
             )

    assert vector_root["recipe"] == "ipse.evidence.float32le.base64.v1"
    before = native_status(c)
    args = %{"action" => "put", "source_id" => "fixture:word"}
    opened = invoke(c, "facts", args)
    assert opened["status"] == "staged_facts", inspect(opened)
    assert invoke(c, "facts", %{args | "action" => "get"})["status"] == "refused"
    final = finish_facts(c, args, opened)
    assert final["status"] == "stored_facts", inspect(final)
    assert final["facts"] == 20
    assert native_status(c)["operations"] - before["operations"] <= 8
    selected = invoke(c, "facts", %{args | "action" => "get"})
    assert selected["status"] == "ok", inspect(selected)
    assert selected["facts"] == 20 and selected["entities"] == 5
    assert selected["citation"]["document"]["locator"]["paragraph"] == 1
    assert selected["warnings"] != []
    assert selected["coverage"]["reads_used"] < 64
    args = args |> Map.put("expected_revision", 1) |> Map.put("salt", 1)

    updated =
      finish_facts(c, args, invoke(c, "facts", args), fn _ ->
        assert invoke(c, "facts", %{args | "action" => "get"})["fact_ids"] == selected["fact_ids"]
      end)

    assert updated["status"] == "stored_facts" and updated["revision"] == 2
    current = invoke(c, "facts", %{args | "action" => "get"})
    refute current["fact_ids"] == selected["fact_ids"]
    assert current["citation"] == selected["citation"]

    assert invoke(c, "facts", Map.put(%{args | "action" => "get"}, "kind", "model_complete"))[
             "status"
           ] == "refused"

    root_key = "facts.notes." <> JSON.sha256(args["source_id"])
    root = body(physical(c, root_key))
    assert length(root["entities"]) == 5
    [page_ref] = root["pages"]
    page = body(physical(c, page_ref["key"]))
    row = hd(page["rows"])
    refute Map.has_key?(row["fact"], "citations")
    [span] = row["citations"]
    assert length(span) == 4

    forged_page =
      update_in(page, ["rows", Access.at(0), "citations", Access.at(0), Access.at(1)], &(&1 + 1))

    bytes = Jason.encode!(forged_page)
    sha = JSON.sha256(bytes)
    key = "factp.notes." <> sha

    forged_root = %{
      root
      | "pages" => [%{"key" => key, "sha256" => sha, "byte_count" => byte_size(bytes)}]
    }

    replace(c, [{key, packed(forged_page)}, {root_key, packed(forged_root)}])
    assert invoke(c, "facts", %{args | "action" => "get"})["status"] == "refused"

    IO.puts(
      "FACT_NATIVE_BUDGET " <> Jason.encode!(%{"before" => before, "after" => native_status(c)})
    )
  end

  @tag :packed_fact_catalog_race
  @tag timeout: 120_000
  test "fact root selection refuses a catalog publication after the last owned-stage checks", c do
    seed_index_sources(c, [{"fixture:fact-race", "Rigel graph evidence.", nil}])
    args = %{"action" => "put", "source_id" => "fixture:fact-race"}
    assert finish_facts(c, args, invoke(c, "facts", args))["status"] == "stored_facts"
    root_key = "facts.notes." <> JSON.sha256(args["source_id"])
    before = physical(c, root_key)
    args = args |> Map.put("expected_revision", 1) |> Map.put("salt", 1)

    ready =
      Enum.reduce_while(1..50, invoke(c, "facts", args), fn _, current ->
        if length(current["continuation"]["stages"]) == 2,
          do: {:halt, current},
          else:
            {:cont, invoke(c, "facts", Map.put(args, "continuation", current["continuation"]))}
      end)

    owner = self()

    callback = fn
      count,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{"request" => %{"op" => "collection.store", "request" => %{"op" => "stage.inspect"}}}}}},
      _ ->
        count + 1

      2,
      {:in,
       {:"$gen_call", _,
        {:extension_action_begin, _,
         %{"op" => "collection.store", "request" => %{"op" => "snapshot"}}}}},
      _ ->
        send(owner, :catalog_publication_window)
        receive do: (:release_catalog_publication -> :ok)
        102

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_catalog_publication) end)

    assert :ok =
             Session.invoke_export(
               c.pid,
               :command,
               "ext__documents__facts",
               Map.put(args, "continuation", ready["continuation"])
             )

    approve_until_catalog_window(c)
    catalog = physical(c, "catalog.notes")
    replace(c, [{"catalog.notes", catalog["value"]}])
    send(c.pid, :release_catalog_publication)
    assert wait(c)["status"] == "refused"
    assert physical(c, root_key) == before
    assert invoke(c, "facts", %{args | "action" => "get"})["revision"] == 1
  end

  @tag :packed_fact_unknown
  @tag timeout: 120_000
  test "owner loss after packed fact root CAS preserves intent and cannot replay", c do
    seed_index_sources(c, [{"fixture:fact-unknown", "Rigel graph evidence.", nil}])
    args = %{"action" => "put", "source_id" => "fixture:fact-unknown"}

    ready =
      Enum.reduce_while(1..50, invoke(c, "facts", args), fn _, current ->
        if length(current["continuation"]["stages"]) == 2,
          do: {:halt, current},
          else:
            {:cont, invoke(c, "facts", Map.put(args, "continuation", current["continuation"]))}
      end)

    owner = self()
    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{
           "request" => %{
             "op" => "collection.store",
             "request" => %{"op" => "commit", "stages" => stages}
           }
         }}}},
      _
      when length(stages) == 2 ->
        send(owner, :namespace_published_before_receipt)
        receive do: (:release_namespace_unknown -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_namespace_unknown) end)

    assert :ok =
             Session.invoke_export(
               c.pid,
               :command,
               "ext__documents__facts",
               Map.put(args, "continuation", ready["continuation"])
             )

    approve_until_namespace_publication(c)
    assert body(physical(c, "facts.notes." <> JSON.sha256(args["source_id"])))["facts"] == 20
    status = native_status(c)
    monitor = Process.monitor(c.pid)
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    {:ok, events} = Journal.load(c.dir, c.id)
    assert List.last(events)["type"] == "extension_action_intent"

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(c.opts, :id, c.id)}
             )

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, ^events} = Journal.load(c.dir, c.id)
    assert native_status(c) == status
  end

  @tag :packed_vector_geometry
  test "packed float32 pages preserve complete ordered vector identities within existing string limits",
       c do
    for module <- [IpseKnowledge.Evidence, IpseKnowledge.Store.Collection.Projection] do
      assert {:module, ^module} =
               :code.load_abs(
                 Path.join([c.artifact, "ebin", Atom.to_string(module)])
                 |> String.to_charlist()
               )
    end

    e = Module.concat(["IpseKnowledge", "Evidence"])
    p = Module.concat(["IpseKnowledge", "Store", "Collection", "Projection"])

    {:ok, source} =
      e.source(%{
        "source_id" => "fixture:vector-geometry",
        "partition" => "notes",
        "generation" => 1,
        "title" => "Vector geometry",
        "text" => String.duplicate("x", 65_535),
        "uri" => "provided:geometry",
        "observed_at_ms" => 10,
        "event_at_ms" => nil,
        "expires_at_ms" => nil,
        "origin" => %{
          "kind" => "provided",
          "store_profile" => "documents",
          "partition_or_scope" => "notes",
          "receipt" => nil,
          "historical" => false
        }
      })

    {:ok, chunks} = e.chunks(source)
    assert length(chunks) == 32

    for dimensions <- [1024, 4096] do
      selection = %{
        "selection_sha256" => JSON.sha256("selected"),
        "profile" => "fixture",
        "model" => "fixture-f32",
        "encoding" => "float32le",
        "dimensions" => dimensions
      }

      vectors =
        for {chunk, n} <- Enum.with_index(chunks) do
          {:ok, input_hash} = Ipse.Extension.canonical_digest([chunk["text"]])

          {:ok, vector} =
            e.vector(
              Map.merge(Map.delete(selection, "encoding"), %{
                "chunk_id" => chunk["chunk_id"],
                "input_sha256" => input_hash,
                "values" => for(i <- 1..dimensions, do: 1.0 + rem(i + n, 17) / 17)
              })
            )

          vector
        end

      assert {:ok, pages} = p.pack(source, vectors, selection)
      assert length(pages) > 1

      for page <- pages do
        assert byte_size(Jason.encode!(page)) <= 48 * 1024
        for row <- page["rows"], piece <- row["pieces"], do: assert(byte_size(piece) <= 5464)
      end

      assert {:ok, ^vectors} = p.unpack(source, pages, selection)
      assert {:error, _} = p.unpack(source, Enum.reverse(pages), selection)
      assert {:error, _} = p.unpack(source, tl(pages), selection)
      assert {:error, _} = p.pack(source, Enum.reverse(vectors), selection)

      assert {:error, _} =
               p.pack(
                 source,
                 [put_in(hd(vectors), ["values", Access.at(0)], :nan) | tl(vectors)],
                 selection
               )

      forged =
        update_in(pages, [Access.at(0), "rows", Access.at(0), "vector_sha256"], fn _ ->
          JSON.sha256("forged")
        end)

      assert {:error, _} = p.unpack(source, forged, selection)
    end
  end

  @tag :packed_vector_session
  @tag timeout: 120_000
  test "actual Session stages packed vectors and atomically replaces their selected complete projection",
       c do
    seed_index_sources(c, [{"fixture:vectors", String.duplicate("Vega orbit ", 2000), nil}])
    args = %{"action" => "put", "source_id" => "fixture:vectors", "dimensions" => 1024}
    opened = invoke(c, "vectors", args)
    assert opened["status"] == "staged_vectors", inspect(opened)
    assert invoke(c, "vectors", %{args | "action" => "get"})["status"] == "refused"
    forged = put_in(opened, ["continuation", "unit"], opened["continuation"]["unit"] + 1)

    assert invoke(c, "vectors", Map.put(args, "continuation", forged["continuation"]))["status"] ==
             "refused"

    result = finish_vectors(c, args, opened)
    assert result["status"] == "stored_vectors", inspect(result)
    assert result["vectors"] == 11
    assert result["pages"] == 2
    selected = invoke(c, "vectors", %{args | "action" => "get"})
    assert selected["status"] == "ok", inspect(selected)
    assert selected["vectors"] == 11 and selected["dimensions"] == 1024
    assert selected["citation"]["source_id"] == "fixture:vectors"
    assert selected["coverage"]["reads_used"] < 64
    args = args |> Map.put("expected_revision", 1) |> Map.put("salt", 1)

    replaced =
      finish_vectors(c, args, invoke(c, "vectors", args), fn _ ->
        assert invoke(c, "vectors", %{args | "action" => "get"})["hashes"] == selected["hashes"]
      end)

    assert replaced["status"] == "stored_vectors" and replaced["revision"] == 2
    current = invoke(c, "vectors", %{args | "action" => "get"})
    refute current["hashes"] == selected["hashes"]
    assert current["coverage"]["reads_used"] < 64

    assert invoke(c, "vectors", %{args | "action" => "get", "dimensions" => 4096})["status"] ==
             "refused"

    {:ok, events} = Journal.load(c.dir, c.id)

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "extension_action_result")),
             &Actions.valid_result?/1
           )

    IO.puts("VECTOR_NATIVE_BUDGET " <> Jason.encode!(native_status(c)))
  end

  @tag :packed_vector_corruption
  @tag timeout: 120_000
  test "actual projection hydration refuses missing, reordered and rehashed wrong-chunk vector pages",
       c do
    seed_index_sources(c, [{"fixture:vector-corrupt", String.duplicate("Vega orbit ", 2000), nil}])

    initial_catalog = body(physical(c, "catalog.notes")) |> Map.put("floor", 1)
    replace(c, [{"catalog.notes", packed(initial_catalog)}])

    args = %{"action" => "put", "source_id" => "fixture:vector-corrupt"}
    assert finish_vectors(c, args, invoke(c, "vectors", args))["status"] == "stored_vectors"
    root_key = "vector.notes." <> JSON.sha256(args["source_id"])
    root = body(physical(c, root_key))
    assert length(root["pages"]) == 2
    [first | _] = root["pages"]
    page_row = physical(c, first["key"])
    replace(c, [{first["key"], nil}])
    assert invoke(c, "vectors", %{args | "action" => "get"})["status"] == "refused"
    replace(c, [{first["key"], page_row["value"]}])
    replace(c, [{root_key, packed(%{root | "pages" => Enum.reverse(root["pages"])})}])
    assert invoke(c, "vectors", %{args | "action" => "get"})["status"] == "refused"
    page = body(page_row) |> Map.update!("rows", &Enum.reverse/1)
    bytes = Jason.encode!(page)
    hash = JSON.sha256(bytes)
    key = "vecp.notes." <> hash

    forged = %{
      root
      | "pages" => [
          %{"key" => key, "sha256" => hash, "byte_count" => byte_size(bytes)} | tl(root["pages"])
        ]
    }

    replace(c, [{key, packed(page)}, {root_key, packed(forged)}])
    assert invoke(c, "vectors", %{args | "action" => "get"})["status"] == "refused"
    replace(c, [{root_key, packed(root)}])
    assert invoke(c, "vectors", %{args | "action" => "get"})["status"] == "ok"
    catalog = body(physical(c, "catalog.notes")) |> Map.put("floor", 0)
    replace(c, [{"catalog.notes", packed(catalog)}])
    assert invoke(c, "vectors", %{args | "action" => "get"})["status"] == "refused"
    assert invoke(c, "vectors", Map.put(args, "expected_revision", 1))["status"] == "refused"
  end

  @tag :packed_vector_catalog_race
  @tag timeout: 120_000
  test "queued projection publication refuses a changed catalog physical revision while old vectors remain selected",
       c do
    seed_index_sources(c, [{"fixture:vector-race", "Rigel vector evidence.", nil}])
    args = %{"action" => "put", "source_id" => "fixture:vector-race"}
    assert finish_vectors(c, args, invoke(c, "vectors", args))["status"] == "stored_vectors"
    root_key = "vector.notes." <> JSON.sha256(args["source_id"])
    before = physical(c, root_key)
    args = args |> Map.put("expected_revision", 1) |> Map.put("salt", 1)
    ready = vector_publication_ready(c, args)
    owner = self()

    callback = fn
      count,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{"request" => %{"op" => "collection.store", "request" => %{"op" => "stage.inspect"}}}}}},
      _ ->
        count + 1

      2,
      {:in,
       {:"$gen_call", _,
        {:extension_action_begin, _,
         %{"op" => "collection.store", "request" => %{"op" => "snapshot"}}}}},
      _ ->
        send(owner, :catalog_publication_window)
        receive do: (:release_catalog_publication -> :ok)
        102

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_catalog_publication) end)

    assert :ok =
             Session.invoke_export(
               c.pid,
               :command,
               "ext__documents__vectors",
               Map.put(args, "continuation", ready["continuation"])
             )

    approve_until_catalog_window(c)
    catalog = physical(c, "catalog.notes")
    replace(c, [{"catalog.notes", catalog["value"]}])
    send(c.pid, :release_catalog_publication)
    assert wait(c)["status"] == "refused"
    assert physical(c, root_key) == before
    assert invoke(c, "vectors", %{args | "action" => "get"})["revision"] == 1

    assert invoke(c, "vectors", Map.put(args, "continuation", ready["continuation"]))["status"] ==
             "refused"
  end

  @tag :packed_vector_unknown
  @tag timeout: 120_000
  test "interrupted vector root publication retains an unknown intent without replay", c do
    seed_index_sources(c, [{"fixture:vector-unknown", "Rigel vector evidence.", nil}])
    args = %{"action" => "put", "source_id" => "fixture:vector-unknown"}
    ready = vector_publication_ready(c, args)
    owner = self()
    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{
           "request" => %{
             "op" => "collection.store",
             "request" => %{"op" => "commit", "stages" => stages}
           }
         }}}},
      _
      when length(stages) == 2 ->
        send(owner, :namespace_published_before_receipt)
        receive do: (:release_namespace_unknown -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_namespace_unknown) end)

    assert :ok =
             Session.invoke_export(
               c.pid,
               :command,
               "ext__documents__vectors",
               Map.put(args, "continuation", ready["continuation"])
             )

    approve_until_namespace_publication(c)
    root_key = "vector.notes." <> JSON.sha256(args["source_id"])
    assert body(physical(c, root_key))["revision"] == 1
    status = native_status(c)
    monitor = Process.monitor(c.pid)
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    {:ok, events} = Journal.load(c.dir, c.id)
    assert List.last(events)["type"] == "extension_action_intent"
    assert length(get_in(List.last(events), ["request", "request", "stages"])) == 2

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(c.opts, :id, c.id)}
             )

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, ^events} = Journal.load(c.dir, c.id)
    assert native_status(c) == status
  end

  defp vector_publication_ready(c, args) do
    Enum.reduce_while(1..50, invoke(c, "vectors", args), fn _, current ->
      if length(current["continuation"]["stages"]) == 2,
        do: {:halt, current},
        else:
          {:cont, invoke(c, "vectors", Map.put(args, "continuation", current["continuation"]))}
    end)
  end

  @tag :inline_collection_session
  @tag timeout: 120_000
  test "negotiated inline source publication and namespace build retain bounded operation accounting",
       c do
    for id <- ["fixture:inline-one", "fixture:inline-two"] do
      before = native_status(c)
      args = %{"tiny" => true, "source_id" => id, "text" => "Vega exact inline evidence."}
      final = finish(c, args, invoke(c, "put", args))
      assert final["status"] == "stored", inspect(final)
      after_put = native_status(c)
      assert after_put["operations"] - before["operations"] == 6
    end

    before = native_status(c)
    built = finish_index(c, invoke(c, "index", %{"action" => "begin"}))
    assert built["status"] == "indexed", inspect(built)
    after_index = native_status(c)
    assert after_index["operations"] - before["operations"] == 7
    result = invoke(c, "namespace", %{"query" => "Vega", "top_k" => 2})
    assert result["coverage"]["namespace_complete"]
    assert result["coverage"]["eligible_sources"] == 2
    assert length(result["evidence"]) == 2
    {:ok, events} = Journal.load(c.dir, c.id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    ops = Enum.map(actions, &get_in(&1, ["request", "request", "op"]))
    assert "value.put_inline" in ops
    assert "value.prepare_inline" in ops
    refute "value.open" in ops
    refute "value.append" in ops
    assert Enum.all?(actions, &Actions.valid_result?/1)

    published =
      Enum.find(actions, &(get_in(&1, ["request", "request", "op"]) == "value.put_inline"))

    prepared =
      Enum.find(actions, &(get_in(&1, ["request", "request", "op"]) == "value.prepare_inline"))

    refute Actions.valid_result?(
             put_in(
               published,
               ["outcome", "value", "result", "record", "sha256"],
               JSON.sha256("forged")
             )
           )

    refute Actions.valid_result?(
             put_in(published, ["outcome", "value", "result", "record", "byte_count"], 1)
           )

    refute Actions.valid_result?(
             put_in(prepared, ["outcome", "value", "result", "stage", "epoch"], Usage.id())
           )

    refute Actions.valid_result?(
             put_in(prepared, ["outcome", "value", "result", "stage", "offset"], 0)
           )

    IO.puts(
      "INLINE_NATIVE_BUDGET " <>
        Jason.encode!(%{"before_index" => before, "after_index" => after_index})
    )
  end

  @tag :inline_collection_fallback
  @tag timeout: 120_000
  test "negotiation preserves legacy hosts and escaped oversized bodies retain bounded staged transport",
       c do
    args = %{
      "tiny" => true,
      "source_id" => "fixture:fallback-small",
      "text" => "Vega exact evidence."
    }

    before = native_status(c)
    assert finish(c, args, invoke(c, "put", args))["status"] == "stored"
    {:ok, events} = Journal.load(c.dir, c.id)

    snapshot =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "snapshot")
      )

    marker = get_in(snapshot, ["outcome", "value", "result", "document_store"])

    inline? =
      marker in [
        %{"version" => 1, "inline_bytes" => 8192},
        %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2}
      ]

    assert native_status(c)["operations"] - before["operations"] == if(inline?, do: 6, else: 18)

    ops =
      for event <- events,
          event["type"] == "extension_action_intent",
          do: get_in(event, ["request", "request", "op"])

    assert "value.put_inline" in ops == inline?

    args = %{
      "tiny" => true,
      "source_id" => "fixture:fallback-large",
      "text" => String.duplicate("Vega\n", 1500)
    }

    before_length = length(events)
    assert finish(c, args, invoke(c, "put", args))["status"] == "stored"
    {:ok, events} = Journal.load(c.dir, c.id)

    actions =
      events
      |> Enum.drop(before_length)
      |> Enum.filter(&(&1["type"] == "extension_action_intent"))

    op =
      if is_map(marker) and marker["write_parts"] == 2,
        do: "value.write_parts",
        else: "value.append"

    assert Enum.any?(actions, &(get_in(&1, ["request", "request", "op"]) == op))

    for event <- actions do
      assert :ok =
               Ipse.Extension.validate(%{
                 "api_version" => 1,
                 "kind" => "host_call",
                 "request" => event["request"]
               })
    end

    result = invoke(c, "query", %{"source_ids" => ["fixture:fallback-large"], "query" => "Vega"})
    assert hd(result["evidence"])["citation"]["source_id"] == "fixture:fallback-large"
  end

  @tag :inline_collection_unknown
  @tag timeout: 120_000
  test "owner loss after inline native publication retains unknown intent and cannot replay", c do
    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)
    owner = self()

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{"request" => %{"op" => "collection.store", "request" => %{"op" => "value.put_inline"}}}}}},
      _ ->
        send(owner, :namespace_published_before_receipt)
        receive do: (:release_namespace_unknown -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_namespace_unknown) end)

    assert :ok =
             Session.invoke_export(c.pid, :command, "ext__documents__put", %{
               "tiny" => true,
               "source_id" => "fixture:inline-unknown"
             })

    approve_until_namespace_publication(c)
    assert native_status(c)["operations"] == 1
    monitor = Process.monitor(c.pid)
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    {:ok, before} = Journal.load(c.dir, c.id)
    assert List.last(before)["type"] == "extension_action_intent"
    assert get_in(List.last(before), ["request", "request", "op"]) == "value.put_inline"

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(c.opts, :id, c.id)}
             )

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, ^before} = Journal.load(c.dir, c.id)
    assert native_status(c)["operations"] == 1
  end

  @tag :packed_document
  test "packed Word source crosses explicit invocations and selected query returns exact cited revision",
       c do
    args = %{"generation" => 1, "expected_revision" => 0}
    opened = invoke(c, "put", args)
    assert opened["status"] == "staged", inspect(opened)
    assert byte_size(Jason.encode!(opened["continuation"])) <= 8192
    final = finish(c, args, opened)
    assert final["status"] == "stored", inspect(final)
    result = invoke(c, "query", %{"query" => "Nocturne migration"})
    assert result["scope"] == "explicit_selected_sources"
    refute result["coverage"]["namespace_complete"]
    assert result["coverage"]["selection_complete"]
    assert result["coverage"]["reads_used"] < 512
    [hit] = result["evidence"]
    assert hit["citation"]["generation"] == 1
    assert hit["citation"]["quote"] =~ "Nocturne migration needs review."
    assert hit["citation"]["document"]["locator"]["paragraph"] == 1
    assert JSON.sha256?(hit["citation"]["document"]["original_sha256"])

    changed = %{"generation" => 2, "expected_revision" => 1}
    opened = invoke(c, "put", changed)

    final =
      finish(c, changed, opened, fn _ ->
        [old] = invoke(c, "query", %{"query" => "Nocturne migration"})["evidence"]
        assert old["citation"]["generation"] == 1
      end)

    assert final["status"] == "stored", inspect(final)
    [hit] = invoke(c, "query", %{"query" => "Nocturne migration"})["evidence"]
    assert hit["citation"]["generation"] == 2
    assert hit["citation"]["quote"] =~ "Nocturne migration needs approval."
    id = Session.info(c.pid).id
    {:ok, events} = Journal.load(c.dir, id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))
    assert Enum.all?(actions, &Actions.valid_result?/1)
    for event <- actions, do: assert(:ok = Ipse.Extension.validate(Actions.resume(event)))
    assert Enum.any?(actions, &(get_in(&1, ["request", "request", "op"]) == "stage.inspect"))
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  @tag :packed_document
  test "embedded complete typed metadata survives packing and forged continuation cannot publish",
       c do
    args = %{"generation" => 1, "expected_revision" => 0, "many" => true}
    opened = invoke(c, "put", args)
    assert opened["status"] == "staged", inspect(opened)
    forged = put_in(opened["continuation"], ["unit"], 35)
    assert invoke(c, "put", Map.put(args, "continuation", forged))["status"] == "refused"
    assert finish(c, args, opened)["status"] == "stored"
    result = invoke(c, "query", %{"query" => "Nocturne migration"})
    [hit] = result["evidence"]
    assert hit["citation"]["document"]["locator"]["paragraph"] == 24
    assert hit["citation"]["quote"] == "Nocturne migration needs review."
    assert Enum.any?(result["gaps"], &(&1["code"] == "partial_document" and &1["warnings"] != []))
  end

  @tag timeout: 120_000
  test "catalog crosses its first page and selective hydration reads only requested sources", c do
    for n <- 1..17 do
      args = %{
        "source_id" => "catalog:#{n}",
        "tiny" => true,
        "generation" => 1,
        "expected_revision" => 0
      }

      assert finish(c, args, invoke(c, "put", args))["status"] == "stored"
    end

    result =
      invoke(c, "query", %{"query" => "Index", "source_ids" => ["catalog:1", "catalog:17"]})

    assert result["catalog_generation"] == 17
    assert result["coverage"]["sources"] == 2
    assert result["coverage"]["reads_used"] < 32
    refute result["coverage"]["namespace_complete"]

    assert Enum.all?(
             result["evidence"],
             &(&1["citation"]["source_id"] in ["catalog:1", "catalog:17"])
           )
  end

  @tag :packed_document
  test "private staged metadata inspection is bound to the actual owning Session", c do
    args = %{
      "source_id" => "catalog:private",
      "tiny" => true,
      "generation" => 1,
      "expected_revision" => 0
    }

    first = invoke(c, "put", args)
    second = invoke(c, "put", Map.put(args, "continuation", first["continuation"]))
    [ref] = second["continuation"]["stages"]
    own = invoke(c, "inspect", %{"ref" => ref})
    assert own["status"] == "ok"
    assert own["value"]["result"]["stage"]["state"] == "sealed"
    assert {:ok, other} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, c.opts})
    on_exit(fn -> if Process.alive?(other), do: Session.close_confirmed(other) end)
    foreign = invoke(%{c | pid: other}, "inspect", %{"ref" => ref})
    assert foreign == %{"status" => "failed", "value" => %{"code" => "document_store_refused"}}
    assert invoke(c, "inspect", %{"ref" => ref})["status"] == "ok"
  end

  @tag :packed_corruption
  test "missing data and rehashed reordered multi-block source refuse actual selected query", c do
    args = %{"generation" => 1, "expected_revision" => 0, "large_blocks" => true}
    assert finish(c, args, invoke(c, "put", args))["status"] == "stored"
    source_key = "source.notes." <> JSON.sha256("fixture:word")
    head_row = physical(c, source_key)
    head = body(head_row)
    assert length(head["blocks"]) > 1
    data_key = hd(head["blocks"])["key"]
    data = physical(c, data_key)
    replace(c, [{data_key, nil}])
    assert invoke(c, "query", %{"query" => "Nocturne"})["status"] == "refused"
    replace(c, [{data_key, data["value"]}])
    assert invoke(c, "query", %{"query" => "Nocturne"})["evidence"] != []

    reordered = Map.update!(head, "blocks", &Enum.reverse/1)
    page_key = "catalog.notes.0"
    page = body(physical(c, page_key))

    page =
      Map.update!(page, "rows", fn [row] ->
        [Map.put(row, "head_sha256", JSON.sha256(Jason.encode!(reordered)))]
      end)

    catalog = body(physical(c, "catalog.notes"))
    catalog = put_in(catalog, ["pages", Access.at(0), "sha256"], JSON.sha256(Jason.encode!(page)))

    replace(c, [
      {source_key, packed(reordered)},
      {page_key, packed(page)},
      {"catalog.notes", packed(catalog)}
    ])

    result = invoke(c, "query", %{"query" => "Nocturne"})
    assert result["status"] == "refused"
    assert result["code"] == "selected_block_corrupt"
  end

  @tag :packed_unknown
  test "unknown native packed write yields no continuation and saved Session never replays it",
       c do
    handler = "packed-source-unknown-" <> Usage.id()
    parent = self()

    assert :ok =
             :telemetry.attach(
               handler,
               [:ipse, :extension, :collection, :staged],
               fn _, _, metadata, _ ->
                 if metadata.generation == 2 do
                   cap = Process.get({Ipse.Extension.Collection, :lock_held})
                   Port.close(cap.port)
                   send(parent, :packed_native_lost)
                 end
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler) end)
    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)

    assert :ok =
             Session.invoke_export(c.pid, :command, "ext__documents__put", %{
               "generation" => 1,
               "expected_revision" => 0
             })

    assert :unknown = wait_unknown(c)
    assert_receive :packed_native_lost
    :telemetry.detach(handler)

    if Process.alive?(c.pid) do
      assert Session.close_confirmed(c.pid) in [:ok, {:error, :cleanup_unconfirmed}]
      if Process.alive?(c.pid), do: Process.exit(c.pid, :kill)
    end

    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    assert {:ok, before} = Journal.load(c.dir, c.id)

    [last | _] =
      before |> Enum.filter(&(&1["type"] == "extension_action_result")) |> Enum.reverse()

    assert get_in(last, ["outcome", "status"]) == "unknown"
    assert get_in(last, ["request", "request", "op"]) == "value.append"

    files = fn ->
      Path.wildcard(Path.join(Ipse.Extension.CollectionStore.root(c.home), "**/*"),
        match_dot: true
      )
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{&1, JSON.sha256(File.read!(&1))})
    end

    retained = files.()

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(c.opts, :id, c.id)}
             )

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, ^before} = Journal.load(c.dir, c.id)
    assert files.() == retained
  end

  @tag :packed_lexical_run
  @tag timeout: 120_000
  test "lossless source lexical runs publish atomically and refuse missing or reordered packed data",
       c do
    first = %{
      "generation" => 1,
      "expected_revision" => 0,
      "tiny" => true,
      "source_id" => "fixture:word"
    }

    assert finish(c, first, invoke(c, "put", first))["status"] == "stored"
    old = invoke(c, "lexical", %{})
    [old_run] = old["runs"]
    assert old_run["source_revision"] == 1

    args = %{"generation" => 2, "expected_revision" => 1, "large_blocks" => true}
    opened = invoke(c, "put", args)
    assert opened["continuation"]["version"] == 3
    incompatible = put_in(opened, ["continuation", "version"], 2)

    assert invoke(c, "put", Map.put(args, "continuation", incompatible["continuation"])) ==
             %{"status" => "refused", "code" => "invalid_collection_source"}

    final =
      finish(c, args, opened, fn _ ->
        assert invoke(c, "lexical", %{})["runs"] == [old_run]
      end)

    assert final["status"] == "stored", inspect(final)

    result = invoke(c, "lexical", %{})
    refute result["coverage"]["evidence_readable"]
    [entry] = result["runs"]
    run = entry["run"]
    assert entry["source_revision"] == 2
    assert run["generation"] == 2
    assert run["recipe"] == "ipse.evidence.word_tokens.v1"
    assert run["term_count"] > 6000
    assert length(run["chunks"]) > 1
    assert ["approval", [[_, 1]]] = Enum.find(run["sample"], &(hd(&1) == "approval"))
    assert Ipse.JSON.sha256?(entry["run_sha256"])
    assert invoke(c, "query", %{"query" => "Nocturne"})["evidence"] != []

    key = "source.notes." <> JSON.sha256("fixture:word")
    head = body(physical(c, key))
    assert head["version"] == 2
    assert length(head["lexical"]["blocks"]) > 1
    first_block = hd(head["lexical"]["blocks"])["key"]
    stored_block = physical(c, first_block)
    replace(c, [{first_block, nil}])
    assert invoke(c, "lexical", %{})["status"] == "refused"
    replace(c, [{first_block, stored_block["value"]}])

    reordered = update_in(head, ["lexical", "blocks"], &Enum.reverse/1)
    replace_selected_head(c, key, reordered)

    assert invoke(c, "lexical", %{}) == %{
             "status" => "refused",
             "code" => "lexical_block_corrupt"
           }

    legacy = head |> Map.delete("lexical") |> Map.put("version", 1)
    replace_selected_head(c, key, legacy)
    assert invoke(c, "query", %{"query" => "Nocturne"})["evidence"] != []
    assert invoke(c, "lexical", %{})["status"] == "refused"
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  defp replace_selected_head(c, key, head) do
    page_key = "catalog.notes.0"
    page = body(physical(c, page_key))

    page =
      Map.update!(page, "rows", fn [row] ->
        [Map.put(row, "head_sha256", JSON.sha256(Jason.encode!(head)))]
      end)

    catalog = body(physical(c, "catalog.notes"))
    catalog = put_in(catalog, ["pages", Access.at(0), "sha256"], JSON.sha256(Jason.encode!(page)))

    replace(c, [{key, packed(head)}, {page_key, packed(page)}, {"catalog.notes", packed(catalog)}])
  end

  @tag :namespace_smoke
  @tag timeout: 120_000
  test "namespace lexical generation publishes exact global BM25 and fences a changed catalog",
       c do
    for {id, text} <- [
          {"fixture:alpha", "Orion Orion Orion evidence."},
          {"fixture:beta", "Orion brief."}
        ] do
      args = %{
        "tiny" => true,
        "source_id" => id,
        "text" => text,
        "generation" => 1,
        "expected_revision" => 0
      }

      args = if id == "fixture:beta", do: Map.put(args, "expires_at_ms", 15), else: args

      assert finish(c, args, invoke(c, "put", args))["status"] == "stored"
    end

    assert invoke(c, "namespace", %{"query" => "Orion"})["status"] == "refused"
    before = native_status(c)
    opened = invoke(c, "index", %{"action" => "begin"})
    assert opened["status"] == "building", inspect(opened)
    built = finish_index(c, opened)
    assert built["status"] == "indexed", inspect(built)
    assert built["index_generation"] == 1
    result = invoke(c, "namespace", %{"query" => "Orion", "top_k" => 2, "as_of_ms" => 12})
    assert result["status"] == "ok", inspect(result)
    assert result["coverage"]["namespace_complete"]
    assert result["coverage"]["chunks"] == 2
    assert result["coverage"]["eligible_sources"] == 2
    assert hd(result["evidence"])["citation"]["source_id"] == "fixture:alpha"
    assert result["coverage"]["reads_used"] < 32
    expired = invoke(c, "namespace", %{"query" => "Orion", "top_k" => 2, "as_of_ms" => 20})
    assert expired["coverage"]["eligible_sources"] == 1
    assert expired["coverage"]["chunks"] == 1
    assert length(expired["evidence"]) == 1
    after_index = native_status(c)

    IO.puts(
      "NAMESPACE_NATIVE_BUDGET " <> Jason.encode!(%{"before" => before, "after" => after_index})
    )

    args = %{
      "tiny" => true,
      "source_id" => "fixture:beta",
      "text" => "Orion changed.",
      "generation" => 2,
      "expected_revision" => 1
    }

    assert finish(c, args, invoke(c, "put", args))["status"] == "stored"

    assert invoke(c, "namespace", %{"query" => "Orion"}) == %{
             "status" => "refused",
             "code" => "lexical_index_stale"
           }

    rebuilt = finish_index(c, invoke(c, "index", %{"action" => "begin"}))
    assert rebuilt["status"] == "indexed", inspect(rebuilt)
    assert rebuilt["index_generation"] == 2
    assert invoke(c, "namespace", %{"query" => "Orion"})["status"] == "ok"
  end

  defp finish_index(c, opened) do
    Enum.reduce_while(1..100, opened, fn _, current ->
      if current["status"] == "building",
        do:
          {:cont,
           invoke(c, "index", %{"action" => "next", "continuation" => current["continuation"]})},
        else: {:halt, current}
    end)
  end

  @tag :namespace_groups
  @tag timeout: 120_000
  test "namespace postings cross catalog groups and match the full-source BM25 reference", c do
    sources =
      seed_index_sources(
        c,
        for n <- 0..8 do
          {"fixture:group-#{n}",
           if(n == 0,
             do: "Nebula anchor anchor exact evidence.",
             else: "Common anchor evidence #{n}."
           ), if(n == 8, do: 15, else: nil)}
        end
      )

    before = native_status(c)
    indexed = finish_index(c, invoke(c, "index", %{"action" => "begin"}))
    assert indexed["status"] == "indexed", inspect(indexed)
    root = body(physical(c, "lexical.notes"))
    assert length(root["groups"]) == 2
    actual = invoke(c, "namespace", %{"query" => "Nebula anchor", "top_k" => 3, "as_of_ms" => 20})
    assert actual["status"] == "ok", inspect(actual)
    assert actual["coverage"]["indexed_sources"] == 9
    assert actual["coverage"]["eligible_sources"] == 8
    assert actual["coverage"]["hydrated_sources"] <= 3
    assert actual["coverage"]["namespace_complete"]
    assert Enum.any?(actual["coverage"]["exclusions"], &(&1["source_id"] == "fixture:group-8"))

    {:ok, reference} =
      apply(IpseKnowledge.Evidence, :rank_lexical, [sources, "Nebula anchor", 3, 20])

    assert Enum.map(actual["evidence"], & &1["citation"]) ==
             Enum.map(reference["evidence"], & &1["citation"])

    assert Enum.map(actual["evidence"], & &1["score"]) ==
             Enum.map(reference["evidence"], & &1["score"])

    assert actual["coverage"]["reads_used"] < 64

    IO.puts(
      "NAMESPACE_GROUP_BUDGET " <>
        Jason.encode!(%{
          "before" => before,
          "after" => native_status(c),
          "query" => actual["coverage"]
        })
    )
  end

  @tag :namespace_pages
  @tag timeout: 120_000
  test "semantic posting pages use authenticated offsets and refuse missing, reordered or forged pages",
       c do
    text = Enum.map_join(1..700, " ", &"entry#{&1}")
    seed_index_sources(c, [{"fixture:pages", text, nil}])
    old_catalog = body(physical(c, "catalog.notes"))
    catalog = old_catalog |> Map.put("generation", 2) |> Map.put("floor", 1)
    replace(c, [{"catalog.notes", packed(catalog)}])
    assert finish_index(c, invoke(c, "index", %{"action" => "begin"}))["status"] == "indexed"
    root = body(physical(c, "lexical.notes"))
    [group] = root["groups"]
    header = body(physical(c, group["key"]))
    assert header["page_count"] > 2
    [hash, _, refs] = hd(header["packs"])
    pack_key = "lexp.notes." <> hash
    pack = physical(c, pack_key)
    target = hd(refs) |> Enum.at(4)
    assert invoke(c, "namespace", %{"query" => target})["status"] == "ok"
    {:ok, events} = Journal.load(c.dir, c.id)

    page_reads =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "key"]) == pack_key)
      )

    assert Enum.any?(page_reads, &(get_in(&1, ["request", "request", "offset"]) > 0))

    replace(c, [{pack_key, nil}])
    assert invoke(c, "namespace", %{"query" => target})["status"] == "refused"

    assert invoke(c, "query", %{"source_ids" => ["fixture:pages"], "query" => target})["evidence"] !=
             []

    replace(c, [{pack_key, pack["value"]}])
    assert invoke(c, "namespace", %{"query" => target})["status"] == "ok"

    reordered = update_in(header, ["packs", Access.at(0), Access.at(2)], &Enum.reverse/1)
    replace_index_header(c, root, reordered)

    assert invoke(c, "namespace", %{"query" => target}) == %{
             "status" => "refused",
             "code" => "lexical_run_directory_corrupt"
           }

    forged =
      update_in(
        header,
        ["packs", Access.at(0), Access.at(2), Access.at(0), Access.at(1)],
        &(&1 + 1)
      )

    replace_index_header(c, root, forged)

    assert invoke(c, "namespace", %{"query" => target}) == %{
             "status" => "refused",
             "code" => "collection_page_corrupt"
           }

    replace(c, [{"lexical.notes", packed(root)}, {"catalog.notes", packed(old_catalog)}])

    assert invoke(c, "index", %{"action" => "begin"}) == %{
             "status" => "refused",
             "code" => "lexical_floor_regression"
           }
  end

  defp replace_index_header(c, root, header) do
    bytes = Jason.encode!(header)
    hash = JSON.sha256(bytes)
    key = "lexr.notes." <> hash

    root =
      put_in(root, ["groups", Access.at(0)], %{
        "key" => key,
        "sha256" => hash,
        "byte_count" => byte_size(bytes)
      })

    replace(c, [{key, packed(header)}, {"lexical.notes", packed(root)}])
  end

  @tag :namespace_publication_race
  @tag timeout: 120_000
  test "a catalog revision changed before the fresh publication snapshot refuses the index CAS",
       c do
    seed_index_sources(c, [{"fixture:race", "Rigel publication remains current.", nil}])
    assert finish_index(c, invoke(c, "index", %{"action" => "begin"}))["status"] == "indexed"
    root_before = physical(c, "lexical.notes")

    ready =
      Enum.reduce_while(1..30, invoke(c, "index", %{"action" => "begin"}), fn _, current ->
        if current["source_cursor"] == 1,
          do: {:halt, current},
          else:
            {:cont,
             invoke(c, "index", %{"action" => "next", "continuation" => current["continuation"]})}
      end)

    assert ready["status"] == "building"
    owner = self()

    callback = fn
      count,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{"request" => %{"op" => "collection.store", "request" => %{"op" => "stage.inspect"}}}}}},
      _ ->
        count + 1

      count,
      {:in,
       {:"$gen_call", _,
        {:extension_action_begin, _,
         %{"op" => "collection.store", "request" => %{"op" => "snapshot"}}}}},
      _
      when count == 2 ->
        send(owner, :catalog_publication_window)
        receive do: (:release_catalog_publication -> :ok)
        count + 100

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_catalog_publication) end)

    assert :ok =
             Session.invoke_export(c.pid, :command, "ext__documents__index", %{
               "action" => "next",
               "continuation" => ready["continuation"]
             })

    approve_until_catalog_window(c)
    catalog = physical(c, "catalog.notes")
    replace(c, [{"catalog.notes", catalog["value"]}])
    send(c.pid, :release_catalog_publication)
    refused = wait(c)
    assert refused["status"] == "refused", inspect(refused)
    assert physical(c, "lexical.notes") == root_before
    assert invoke(c, "namespace", %{"query" => "Rigel"})["status"] == "ok"
    {:ok, events} = Journal.load(c.dir, c.id)
    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  defp approve_until_catalog_window(c) do
    receive do
      :catalog_publication_window ->
        :ok

      {:ipse, pid, {:approval, ref, "extension:collection.store", _}} when pid == c.pid ->
        assert :ok = Session.approve(pid, ref, true)
        approve_until_catalog_window(c)

      {:ipse, pid, {:done, status}} when pid == c.pid ->
        flunk("index ended before race window: #{inspect(status)}")

      {:ipse, pid, _} when pid == c.pid ->
        approve_until_catalog_window(c)
    after
      15_000 -> flunk("index did not reach the final fresh-snapshot boundary")
    end
  end

  @tag :namespace_unknown
  @tag timeout: 120_000
  test "owner loss after native namespace publication preserves intent and never replays on resume",
       c do
    seed_index_sources(c, [{"fixture:unknown", "Vega exact namespace evidence.", nil}])

    ready =
      Enum.reduce_while(1..30, invoke(c, "index", %{"action" => "begin"}), fn _, current ->
        if current["source_cursor"] == 1,
          do: {:halt, current},
          else:
            {:cont,
             invoke(c, "index", %{"action" => "next", "continuation" => current["continuation"]})}
      end)

    guard = :sys.get_state(c.pid).lock_guard
    guard_ref = Process.monitor(guard)
    owner = self()

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{
           "request" => %{
             "op" => "collection.store",
             "request" => %{"op" => "commit", "stages" => stages}
           }
         }}}},
      _
      when length(stages) == 2 ->
        send(owner, :namespace_published_before_receipt)
        receive do: (:release_namespace_unknown -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(c.pid, {callback, 0})
    on_exit(fn -> send(c.pid, :release_namespace_unknown) end)

    assert :ok =
             Session.invoke_export(c.pid, :command, "ext__documents__index", %{
               "action" => "next",
               "continuation" => ready["continuation"]
             })

    approve_until_namespace_publication(c)
    assert body(physical(c, "lexical.notes"))["generation"] == 1
    monitor = Process.monitor(c.pid)
    Process.exit(c.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    {:ok, before} = Journal.load(c.dir, c.id)
    last = List.last(before)
    assert last["type"] == "extension_action_intent"
    assert length(get_in(last, ["request", "request", "stages"])) == 2

    files = fn ->
      Path.wildcard(Path.join(c.home, "**/*"), match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{&1, JSON.sha256(File.read!(&1))})
    end

    retained = files.()

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(c.opts, :id, c.id)}
             )

    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, ^before} = Journal.load(c.dir, c.id)
    assert files.() == retained
  end

  @tag :collection_chunking_session
  @tag timeout: 120_000
  test "Collection Source3 and retained Source1 share a namespace without changing legacy chunk identities",
       c do
    [legacy] = seed_index_sources(c, [{"fixture:legacy", "Legacy stable evidence.", nil}])
    {:ok, [oldchunk]} = apply(IpseKnowledge.Evidence, :chunks, [legacy])
    before = invoke(c, "query", %{"source_ids" => ["fixture:legacy"], "query" => "Legacy"})
    assert hd(before["evidence"])["citation"]["version"] == 1
    assert hd(before["evidence"])["citation"]["chunk_id"] == oldchunk["chunk_id"]

    args = %{
      "tiny" => true,
      "source_id" => "fixture:long",
      "text" => String.duplicate("a", 4096) <> " needle",
      "generation" => 1,
      "expected_revision" => 0
    }

    assert finish(c, args, invoke(c, "put", args))["status"] == "stored"
    head = body(physical(c, "source.notes." <> JSON.sha256("fixture:long")))
    assert head["chunks"] == 2
    [source_ref] = head["blocks"]
    current = body(physical(c, source_ref["key"]))["pieces"] |> Enum.join() |> Jason.decode!()

    assert current["version"] == 3 and
             current["chunking"] == %{"version" => 2, "max_bytes" => 4096}

    [run_ref] = head["lexical"]["blocks"]
    run = body(physical(c, run_ref["key"]))["pieces"] |> Enum.join() |> Jason.decode!()
    assert run["version"] == 2
    assert Enum.any?(run["terms"], &(byte_size(hd(&1)) == 4096))
    assert finish_index(c, invoke(c, "index", %{"action" => "begin"}))["status"] == "indexed"
    result = invoke(c, "namespace", %{"query" => "needle"})
    assert result["status"] == "ok", inspect(result)
    citation = hd(result["evidence"])["citation"]
    assert citation["version"] == 3 and citation["chunking"] == current["chunking"]
    assert citation["start_byte"] == 4096 and citation["end_byte"] == 4103

    {:ok, reference} =
      apply(IpseKnowledge.Evidence, :rank_lexical, [[legacy, current], "needle", 1, 20])

    assert result["evidence"] == reference["evidence"]
    after_query = invoke(c, "query", %{"source_ids" => ["fixture:legacy"], "query" => "Legacy"})
    assert after_query["evidence"] == before["evidence"]
    root = body(physical(c, "lexical.notes"))
    [group] = root["groups"]
    directory = body(physical(c, group["key"]))

    assert Enum.any?(directory["packs"], fn [_, _, refs] ->
             Enum.any?(refs, &(Enum.at(&1, 2) > 4096))
           end)

    {:ok, events} = Journal.load(c.dir, c.id)

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "extension_action_result")),
             &Ipse.Extension.Actions.valid_result?/1
           )

    assert {:ok, _} = Session.Saved.restore(events, c.id)
  end

  @tag :collection_legacy_consumer
  test "the frozen legacy consumer reads its retained Source1 and refuses Source3 without reinterpretation",
       c do
    seed_index_sources(c, [{"fixture:legacy", "Legacy stable evidence.", nil}])

    args = %{
      "tiny" => true,
      "source_id" => "fixture:current",
      "text" => "Current chunk recipe.",
      "generation" => 1,
      "expected_revision" => 0
    }

    assert finish(c, args, invoke(c, "put", args))["status"] == "stored"

    assert hd(
             invoke(c, "query", %{"source_ids" => ["fixture:current"], "query" => "Current"})[
               "evidence"
             ]
           )["citation"]["version"] == 3

    old_path = legacy_consumer_artifact(c)
    {:ok, old} = Artifact.import(old_path, Path.join(c.home, "extensions/artifacts"))

    binding = %{
      "version" => 1,
      "instance" => "documents",
      "id" => "documents",
      "scope" => "project",
      "profile" => "document_graph_v1"
    }

    data = %{
      "extensions" => [
        %{
          "instance" => "documents",
          "artifact" => old.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => old.digest,
          "capabilities" => old.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false,
          "collection_bindings" => [binding]
        }
      ]
    }

    {:ok, selected} =
      Config.resolve([%{scope: "operator", path: "/fixture/legacy-reader.json", data: data}], [])

    {:ok, entries} = Registry.prepare(selected, c.home)
    config = Map.put(c.opts[:config], :extensions, entries)
    opts = Keyword.put(c.opts, :config, config)
    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    reader = %{c | pid: pid, id: Session.info(pid).id, opts: opts}

    old_result =
      invoke(reader, "query", %{"source_ids" => ["fixture:legacy"], "query" => "Legacy"})

    assert old_result["status"] == "ok"
    assert hd(old_result["evidence"])["citation"]["version"] == 1

    assert invoke(reader, "query", %{"source_ids" => ["fixture:current"], "query" => "Current"}) ==
             %{"status" => "refused", "code" => "selected_bundle_corrupt"}

    assert :ok = Session.close_confirmed(pid)
  end

  defp legacy_consumer_artifact(c) do
    root = Path.join(Path.dirname(c.artifact), "legacy-consumer-" <> Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)

    sources =
      Path.expand(
        "docs/archive/2026-10-26-p30-p31-implementation/collection-chunking/legacy-source"
      )

    legacy_manifest = Jason.decode!(File.read!(Path.join(sources, "manifest.json")))

    for {path, expected} <- legacy_manifest["sources"] do
      bytes = File.read!(Path.join(sources, path))

      assert byte_size(bytes) == expected["byte_count"] and
               JSON.sha256(bytes) == expected["sha256"]
    end

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    files =
      Enum.map(
        ~w(evidence.ex documents.ex documents/zip.ex documents/docx.ex documents/parser_stage.ex documents/pdf.ex store/collection.ex store/collection/index.ex fixture.exs),
        &Path.join(sources, &1)
      )

    assert {"", 0} =
             System.cmd(
               System.find_executable("elixirc"),
               ["--erl", "+S 2:2"] ++ paths ++ ["-o", Path.join(root, "ebin")] ++ files,
               stderr_to_stdout: true
             )

    File.cp!(Path.join(c.artifact, "LICENSE"), Path.join(root, "LICENSE"))
    manifest = Jason.decode!(File.read!(Path.join(c.artifact, "extension.json")))

    manifest =
      update_in(
        manifest,
        ["exports", "commands"],
        &Enum.reject(&1, fn item -> item["id"] in ~w(vectors facts) end)
      )

    files =
      for relative <- [
            "LICENSE"
            | Enum.map(Path.wildcard(Path.join(root, "ebin/*.beam")), &Path.relative_to(&1, root))
          ] do
        bytes = File.read!(Path.join(root, relative))
        %{"path" => relative, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    File.write!(
      Path.join(root, "extension.json"),
      Jason.encode!(Map.put(manifest, "files", files))
    )

    root
  end

  defp approve_until_namespace_publication(c) do
    receive do
      :namespace_published_before_receipt ->
        :ok

      {:ipse, pid, {:approval, ref, "extension:collection.store", _}} when pid == c.pid ->
        assert :ok = Session.approve(pid, ref, true)
        approve_until_namespace_publication(c)

      {:ipse, pid, {:done, status}} when pid == c.pid ->
        flunk("index ended before native publication: #{inspect(status)}")

      {:ipse, pid, _} when pid == c.pid ->
        approve_until_namespace_publication(c)
    after
      15_000 -> flunk("index did not reach native publication")
    end
  end

  # Direct native fixture seeding isolates index/query qualification from the
  # separately tested public ingestion protocol. Indexing validates every source
  # and recomputes its complete lexical run before publishing a generation.
  defp partial_word_source(c) do
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {bytes, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          [
            "-pa",
            Path.join(c.artifact, "ebin"),
            "-e",
            "IO.puts(Jason.encode!(IpseTest.CollectionAdapter.source(1, true)))"
          ],
        stderr_to_stdout: true
      )

    Jason.decode!(bytes)
  end

  defp seed_shared_generation(c, sources, selection, extraction, finalization \\ false) do
    catalog = body(physical(c, "catalog.notes"))

    input = %{
      "selection" => selection,
      "finalization" => finalization,
      "paged_finalization" => c[:paged_finalization] == true,
      "extraction" => extraction,
      "catalog" => catalog,
      "pages" => Enum.map(catalog["pages"], &body(physical(c, &1["key"]))),
      "bundles" =>
        Enum.map(sources, fn source ->
          %{
            "source" => source,
            "head" => body(physical(c, "source.notes." <> source["source_key"]))
          }
        end)
    }

    path = Path.join(c.fixture_root, "trusted-shared-seed.json")
    File.write!(path, Jason.encode!(input), [:exclusive])
    File.chmod!(path, 0o600)
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    {bytes, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          ["-pa", Path.join(c.artifact, "ebin"), "test/support/shared_selected_seed.exs", path],
        stderr_to_stdout: true
      )

    seeded = Jason.decode!(bytes)
    replace(c, Enum.map(seeded["values"], &{&1["key"], packed(&1["value"])}))
    seeded
  end

  defp seed_index_sources(c, items) do
    evidence = Path.join(c.artifact, "ebin/Elixir.IpseKnowledge.Evidence")

    unless :code.which(IpseKnowledge.Evidence) == String.to_charlist(evidence <> ".beam") do
      assert {:module, IpseKnowledge.Evidence} = :code.load_abs(String.to_charlist(evidence))
    end

    sources =
      Enum.map(items, fn
        source when is_map(source) ->
          assert apply(IpseKnowledge.Evidence, :valid_source?, [source])
          source

        {id, text, expiry} ->
          {:ok, source} =
            apply(IpseKnowledge.Evidence, :source, [
              %{
                "source_id" => id,
                "partition" => "notes",
                "generation" => 1,
                "title" => "Seeded source",
                "text" => text,
                "uri" => "provided:" <> id,
                "observed_at_ms" => 10,
                "event_at_ms" => nil,
                "expires_at_ms" => expiry,
                "origin" => %{
                  "kind" => "provided",
                  "store_profile" => "documents",
                  "partition_or_scope" => "notes",
                  "receipt" => nil,
                  "historical" => false
                }
              }
            ])

          source
      end)

    rows =
      Enum.with_index(sources)
      |> Enum.map(fn {source, ordinal} ->
        source_bytes = Jason.encode!(source)
        {:ok, run} = apply(IpseKnowledge.Evidence, :lexical_run, [source])
        run_bytes = Jason.encode!(run)
        assert byte_size(source_bytes) <= 32_768 and byte_size(run_bytes) <= 40_000
        source_hash = JSON.sha256(source_bytes)
        run_hash = JSON.sha256(run_bytes)

        data = %{
          "version" => 2,
          "kind" => "source_data",
          "bundle_sha256" => source_hash,
          "ordinal" => 0,
          "pieces" => utf8_pieces(source_bytes, 4096)
        }

        lexical = %{
          "version" => 1,
          "kind" => "source_lexical",
          "source_bundle_sha256" => source_hash,
          "bundle_sha256" => run_hash,
          "ordinal" => 0,
          "pieces" => utf8_pieces(run_bytes, 4096)
        }

        data_ref = %{
          "key" => "data.notes." <> JSON.sha256(Jason.encode!(data)),
          "sha256" => JSON.sha256(Jason.encode!(data))
        }

        lexical_ref = %{
          "key" => "data.notes." <> JSON.sha256(Jason.encode!(lexical)),
          "sha256" => JSON.sha256(Jason.encode!(lexical))
        }

        head = %{
          "version" => 2,
          "kind" => "source_head",
          "source_key" => source["source_key"],
          "generation" => 1,
          "revision" => 1,
          "ordinal" => ordinal,
          "text_bytes" => byte_size(source["text"]),
          "chunks" => length(run["chunks"]),
          "byte_count" => byte_size(source_bytes),
          "bundle_sha256" => source_hash,
          "blocks" => [data_ref],
          "lexical" => %{
            "version" => 1,
            "recipe" => run["recipe"],
            "content_sha256" => source["content_sha256"],
            "byte_count" => byte_size(run_bytes),
            "bundle_sha256" => run_hash,
            "blocks" => [lexical_ref]
          }
        }

        {source, head,
         [
           {data_ref["key"], packed(data)},
           {lexical_ref["key"], packed(lexical)},
           {"source.notes." <> source["source_key"], packed(head)}
         ]}
      end)

    pages =
      rows
      |> Enum.chunk_every(16)
      |> Enum.with_index()
      |> Enum.map(fn {rows, ordinal} ->
        page = %{
          "version" => 1,
          "kind" => "catalog_page",
          "partition" => "notes",
          "ordinal" => ordinal,
          "rows" =>
            Enum.map(rows, fn {source, head, _} ->
              %{
                "source_key" => source["source_key"],
                "head_sha256" => JSON.sha256(Jason.encode!(head))
              }
            end)
            |> Enum.sort_by(& &1["source_key"])
        }

        {"catalog.notes.#{ordinal}", page}
      end)

    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => "notes",
      "generation" => length(sources),
      "floor" => 0,
      "sources" => length(sources),
      "extracted_bytes" => Enum.reduce(sources, 0, &(byte_size(&1["text"]) + &2)),
      "chunks" => Enum.reduce(rows, 0, fn {_, head, _}, n -> head["chunks"] + n end),
      "entities" => 0,
      "assertions" => 0,
      "pages" =>
        Enum.map(pages, fn {key, value} ->
          %{"key" => key, "sha256" => JSON.sha256(Jason.encode!(value))}
        end)
    }

    values =
      Enum.flat_map(rows, &elem(&1, 2)) ++
        Enum.map(pages, fn {key, value} -> {key, packed(value)} end) ++
        [{"catalog.notes", packed(catalog)}]

    replace(c, values)
    sources
  end

  defp native_status(c) do
    {:ok, binding} = ProjectIdentity.existing(c.home, c.opts[:cwd])
    namespace = Ipse.Extension.CollectionStore.namespace(binding["project_id"])

    assert {:ok, status} =
             Ipse.Extension.Collection.execute_profile(
               Ipse.Extension.CollectionStore.root(c.home),
               namespace,
               %{"op" => "status"},
               Usage.id(),
               "document_graph_v1"
             )

    Map.take(status, ~w(generation floor records operations logical_bytes allocated_bytes))
  end

  defp wait_unknown(c) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:collection.store", _}} when pid == c.pid ->
        assert :ok = Session.approve(pid, ref, true)
        wait_unknown(c)

      {:ipse, pid, {:error, _}} when pid == c.pid ->
        :unknown

      {:ipse, pid, {:done, _}} when pid == c.pid ->
        flunk("unknown source write returned a completed continuation")

      {:ipse, pid, _} when pid == c.pid ->
        wait_unknown(c)
    after
      10_000 -> flunk("unknown source write did not stop")
    end
  end

  defp physical(c, key) do
    {:ok, binding} = ProjectIdentity.existing(c.home, c.opts[:cwd])
    namespace = Ipse.Extension.CollectionStore.namespace(binding["project_id"])

    assert {:ok, value} =
             Ipse.Extension.Collection.execute_profile(
               Ipse.Extension.CollectionStore.root(c.home),
               namespace,
               %{"op" => "get", "key" => key},
               Usage.id(),
               "document_graph_v1"
             )

    value["record"]
  end

  defp body(row), do: row["value"]["parts"] |> Enum.join() |> Jason.decode!()

  defp packed(value) do
    bytes = Jason.encode!(value)

    %{
      "version" => 1,
      "kind" => "document_value",
      "parts" => utf8_pieces(bytes, 6144),
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes)
    }
  end

  defp utf8_pieces(bytes, limit),
    do:
      Stream.unfold(bytes, fn
        "" ->
          nil

        rest ->
          part = fixture_utf8_prefix(rest, min(byte_size(rest), limit))
          {part, binary_part(rest, byte_size(part), byte_size(rest) - byte_size(part))}
      end)
      |> Enum.to_list()

  defp fixture_utf8_prefix(bytes, n) do
    part = binary_part(bytes, 0, n)
    if String.valid?(part), do: part, else: fixture_utf8_prefix(bytes, n - 1)
  end

  defp replace(c, values) do
    {:ok, binding} = ProjectIdentity.existing(c.home, c.opts[:cwd])
    namespace = Ipse.Extension.CollectionStore.namespace(binding["project_id"])
    root = Ipse.Extension.CollectionStore.root(c.home)

    changes =
      Enum.map(values, fn {key, value} ->
        row = physical(c, key)

        %{
          "key" => key,
          "expected_revision" => if(row, do: row["revision"], else: 0),
          "value" => value
        }
      end)

    assert {:ok, snapshot} =
             Ipse.Extension.Collection.execute_profile(
               root,
               namespace,
               %{"op" => "snapshot"},
               Usage.id(),
               "document_graph_v1"
             )

    assert {:ok, _} =
             Ipse.Extension.Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => snapshot["generation"],
                 "advance_floor" => true,
                 "changes" => changes
               },
               Usage.id(),
               "document_graph_v1"
             )
  end
end
