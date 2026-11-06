if System.get_env("IPSE_SPLIT_APPEND_CHILD") == "1" do
  defmodule Ipse.CollectionSplitAppendNativeTest do
    use ExUnit.Case, async: false
    alias Ipse.{JSON, Usage}
    alias Ipse.Extension.Collection
    alias Ipse.Extension.Collection.DocumentStage
    alias IpseKnowledge.Evidence
    alias IpseKnowledge.Store.Collection, as: C
    alias IpseKnowledge.Store.Collection.Generation

    @profile %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
    @vector %{
      "selection_sha256" => String.duplicate("a", 64),
      "profile" => "synthetic",
      "model" => "fixture",
      "dimensions" => 1024,
      "encoding" => "float32le"
    }
    @facts %{"kind" => "explicit", "profile" => nil, "version" => 1}

    @tag :lexical_retirement_public_pause
    test "public Corpus resumes a real paused retirement with an abort continuation" do
      # Metadata-only shape control: these 63 references are not populated sources.
      # The valid large catalog makes the job too large for one inline write.
      pages =
        for n <- 1..63 do
          %{
            "key" => "p" <> String.pad_leading(Integer.to_string(n), 90, "x"),
            "sha256" => JSON.sha256("metadata-only-page-#{n}")
          }
        end

      catalog = %{
        "version" => 1,
        "kind" => "catalog",
        "partition" => "notes",
        "generation" => 1,
        "floor" => 0,
        "sources" => 1000,
        "extracted_bytes" => 0,
        "chunks" => 0,
        "entities" => 0,
        "assertions" => 0,
        "pages" => pages
      }

      assert C.valid_catalog?(catalog, @profile)
      assert byte_size(Jason.encode!(catalog)) > 8192

      groups =
        for n <- 1..12 do
          sha = JSON.sha256("metadata-only-group-#{n}")
          %{"key" => "lexr.notes." <> sha, "sha256" => sha, "byte_count" => 2}
        end

      # This is deliberately an unpopulated but shape-valid prior job, not an
      # assertion that the catalog's sources or the group bodies were indexed.
      job = %{
        "version" => 1,
        "kind" => "lexical_job",
        "id" => Usage.id(),
        "status" => "building",
        "catalog" => catalog,
        "catalog_sha256" => JSON.sha256(IO.iodata_to_binary(Elixir.JSON.encode!(catalog))),
        "cursor" => 96,
        "unit" => 0,
        "groups" => groups,
        "root_revision" => 0,
        "index_generation" => 1
      }

      job_bytes = IO.iodata_to_binary(Elixir.JSON.encode!(job))
      assert byte_size(job_bytes) > 2 * 6144
      assert byte_size(job_bytes) <= 48 * 1024
      ctx = index_context()

      assert {:done, {:ok, _}} =
               drive(
                 C.start(@profile, :value_write, %{
                   "key" => "catalog.notes",
                   "value" => catalog,
                   "expected_revision" => 0,
                   "reuse" => false,
                   "continuation" => nil
                 }),
                 ctx
               )

      assert read(ctx, "catalog.notes")["sha256"] === job["catalog_sha256"]

      assert {:done, {:ok, _}} =
               drive(
                 C.start(@profile, :value_write, %{
                   "key" => "lexjob.notes",
                   "value" => job,
                   "expected_revision" => 0,
                   "reuse" => false,
                   "continuation" => nil
                 }),
                 ctx
               )

      old_job = read(ctx, "lexjob.notes")
      assert old_job["value"] === job

      token = %{
        "version" => 2,
        "job_id" => job["id"],
        "job_revision" => old_job["revision"],
        "work" => "unit",
        "write" => nil,
        "stages" => %{},
        "unit" => 0
      }

      fence = open_index_fence(ctx)
      close_index_fence(ctx, fence)

      options = Jason.decode!(File.read!("extensions/knowledge/options/corpus-collection.json"))
      {:ok, corpus} = IpseKnowledge.Corpus.init(options)
      refute Map.has_key?(corpus, :invalid)
      args = %{"store" => "notes", "action" => "abort", "continuation" => token}

      {paused, injected} =
        corpus_drive(
          IpseKnowledge.Corpus.handle(
            "invoke.command",
            %{"id" => "lexical_index", "arguments" => args},
            corpus
          ),
          ctx,
          true
        )

      assert injected, inspect(Map.take(paused, ~w(status gaps coverage)))
      assert paused["status"] === "draft" and paused["coverage"]["status"] === "aborting"
      continuation = paused["continuation"]
      assert continuation["id"] === "lexical_index"
      assert continuation["arguments"]["action"] === "abort"
      retirement = continuation["arguments"]["continuation"]
      assert retirement["version"] === 4 and retirement["maintenance_epoch"] === 0
      assert retirement["retirement_epoch"] === 1 and retirement["work"] === "retire"
      assert retirement["job_id"] === token["job_id"]
      assert retirement["job_revision"] === token["job_revision"]
      assert retirement["write"]["active"]["offset"] > 0
      assert retirement["write"]["active"]["offset"] < retirement["write"]["active"]["byte_count"]
      assert read(ctx, "lexjob.notes") === old_job

      bad = put_in(continuation, ["arguments", "continuation", "retirement_epoch"], 2)
      {refused, false} = corpus_invoke(corpus, bad, ctx)
      assert refused["status"] === "refused"
      assert read(ctx, "lexjob.notes") === old_job

      # Resume the exact public command with a fresh invocation and the same Session owner identity.
      resumed_ctx = put_in(ctx, [:owner, "invocation_id"], Usage.id())
      {finished, false} = corpus_invoke(corpus, continuation, resumed_ctx)
      assert finished["status"] === "ok" and finished["coverage"]["status"] === "aborted"
      retired = read(ctx, "lexjob.notes")["value"]
      assert retired["id"] === token["job_id"] and retired["status"] === "aborted"
      refute Map.has_key?(retired, "maintenance_epoch")
    end

    defp corpus_invoke(corpus, continuation, ctx) do
      corpus_drive(
        IpseKnowledge.Corpus.handle("invoke.command", continuation, corpus),
        ctx,
        false
      )
    end

    defp corpus_drive(
           {:ok, %Ipse.Extension.ResultPublication.Output{bytes: bytes}, _},
           _,
           inject
         ),
         do: {Jason.decode!(bytes), inject == :injected}

    defp corpus_drive({:ok, %{"kind" => "result", "value" => value}, _}, _, inject),
      do: {value, inject == :injected}

    defp corpus_drive({:ok, %{"kind" => "host_call", "request" => request}, state}, ctx, inject) do
      assert :ok = Ipse.Extension.CollectionStore.validate(request)
      operation = Usage.id()

      assert {:ok, result} =
               DocumentStage.execute(
                 ctx.root,
                 ctx.namespace,
                 request["request"],
                 operation,
                 ctx.owner
               )

      wrapped = %{
        "version" => 1,
        "operation_id" => operation,
        "request_sha256" => JSON.digest([request]),
        "result" => result
      }

      assert Ipse.Extension.CollectionStore.valid_outcome?(request, "ok", wrapped, operation)

      {state, inject} =
        if inject === true and request["request"]["op"] === "value.write_parts" and
             get_in(result, ["write", "state"]) === "open" do
          # Controlled budget only: retain the real native request/result, then model
          # a continuation whose earlier effects consumed this invocation's allowance.
          {put_in(state, [:cont, :inner, :effects], 16), :injected}
        else
          {state, inject}
        end

      corpus_drive(
        IpseKnowledge.Corpus.handle(
          "host.actions",
          %{"outcome" => %{"status" => "ok", "value" => wrapped}},
          state
        ),
        ctx,
        inject
      )
    end

    @tag :lexical_maintenance_stale
    test "a native maintenance fence cannot renew an old lexical job or edited continuation" do
      ctx = index_context()
      seed_index_source(ctx)
      {:done, {:continue, opened}} = index(ctx, "begin", nil)
      token = opened["continuation"]
      assert token["version"] === 2
      assert {:done, {:error, :lexical_build_exists, _}} = index(ctx, "begin", nil)
      old_job = read(ctx, "lexjob.notes")
      fence = open_index_fence(ctx)

      assert {:done, {:error, :lexical_maintenance_changed, _}} = index(ctx, "next", token)
      assert {:done, {:error, :lexical_maintenance_changed, _}} = index(ctx, "begin", nil)
      close_index_fence(ctx, fence)
      {:ok, before} = Collection.document_snapshot(ctx.root, ctx.namespace)

      assert {:done, {:error, :lexical_maintenance_changed, _}} = index(ctx, "next", token)
      edited = Map.merge(token, %{"version" => 3, "maintenance_epoch" => 1})
      assert {:done, {:error, :lexical_continuation_conflict, _}} = index(ctx, "next", edited)
      assert {:done, {:error, :lexical_build_exists, _}} = index(ctx, "begin", nil)

      for changed <- [
            Map.put(token, "job_id", Usage.id()),
            Map.update!(token, "job_revision", &(&1 + 1)),
            edited
          ] do
        assert {:done, {:error, :lexical_continuation_conflict, _}} = index(ctx, "abort", changed)
      end

      for bad <- [0, -1, 1.0, "1", nil] do
        assert {:done, {:error, :invalid_lexical_index_request, _}} =
                 index(ctx, "next", Map.put(edited, "maintenance_epoch", bad))
      end

      retirement =
        Map.merge(token, %{
          "version" => 4,
          "maintenance_epoch" => 0,
          "retirement_epoch" => 1,
          "work" => "retire",
          "write" => %{"invalid" => "checkpoint"}
        })

      for action <- ~w(begin next inspect) do
        assert {:done, {:error, :invalid_lexical_index_request, _}} =
                 index(ctx, action, retirement)
      end

      for changed <- [0, 2] do
        assert {:done, {:error, :lexical_maintenance_changed, _}} =
                 index(ctx, "abort", Map.put(retirement, "retirement_epoch", changed))
      end

      assert {:done, {:error, :invalid_collection_value, _}} = index(ctx, "abort", retirement)

      assert {:done, {:ok, inspected}} = index(ctx, "inspect", nil)
      assert inspected["status"] === "unbuilt"
      assert read(ctx, "lexjob.notes") === old_job
      assert {:ok, ^before} = Collection.document_snapshot(ctx.root, ctx.namespace)

      # Only explicit retirement uses the old token, as an exact job selector.
      old_write = %{token | "work" => "job", "write" => %{"must" => "be discarded"}}
      assert {:done, {:ok, %{"status" => "aborted"}}} = index(ctx, "abort", old_write)
      retired = read(ctx, "lexjob.notes")["value"]
      assert retired["version"] === 1 and retired["id"] === token["job_id"]
      assert retired["status"] === "aborted"
      refute Map.has_key?(retired, "maintenance_epoch")
      assert {:done, {:error, :lexical_continuation_conflict, _}} = index(ctx, "abort", token)

      assert {:done, {:continue, fresh}} = index(ctx, "begin", nil)
      assert fresh["continuation"]["maintenance_epoch"] === 1
      refute fresh["continuation"]["job_id"] === token["job_id"]
      assert {:done, {:error, :lexical_continuation_conflict, _}} = index(ctx, "abort", token)

      assert {:done, {:ok, %{"status" => "aborted"}}} =
               index(ctx, "abort", fresh["continuation"])

      assert read(ctx, "lexical.notes") === nil
    end

    @tag :lexical_maintenance_fresh
    test "a fresh lexical job after native maintenance publishes and retrieves exact source evidence" do
      ctx = index_context()
      seed_index_source(ctx)
      fence = open_index_fence(ctx)
      close_index_fence(ctx, fence)

      {:done, {:continue, opened}} = index(ctx, "begin", nil)
      assert opened["continuation"]["version"] === 3
      assert opened["continuation"]["maintenance_epoch"] === 1
      assert read(ctx, "lexjob.notes")["value"]["maintenance_epoch"] === 1

      later_fence = open_index_fence(ctx)

      assert {:done, {:error, :lexical_maintenance_changed, _}} =
               index(ctx, "abort", opened["continuation"])

      close_index_fence(ctx, later_fence)

      assert {:done, {:error, :lexical_maintenance_changed, _}} =
               index(ctx, "next", opened["continuation"])

      assert {:done, {:ok, %{"status" => "aborted"}}} =
               index(ctx, "abort", opened["continuation"])

      assert read(ctx, "lexjob.notes")["value"]["maintenance_epoch"] === 1
      assert {:done, {:continue, restarted}} = index(ctx, "begin", nil)
      assert restarted["continuation"]["maintenance_epoch"] === 2
      refute restarted["continuation"]["job_id"] === opened["continuation"]["job_id"]

      result =
        Enum.reduce_while(1..100, restarted, fn _, current ->
          case index(ctx, "next", current["continuation"]) do
            {:done, {:continue, next}} ->
              assert next["continuation"]["maintenance_epoch"] === 2
              {:cont, next}

            {:done, {:ok, selected}} ->
              {:halt, selected}

            other ->
              flunk("fresh lexical job failed: #{inspect(other)}")
          end
        end)

      assert result["status"] === "indexed"

      assert {:done, {:ok, queried}} =
               drive(
                 C.start(@profile, :lexical_query, %{
                   "query" => "Orion",
                   "top_k" => 1,
                   "as_of_ms" => 20
                 }),
                 ctx
               )

      assert queried["coverage"]["namespace_complete"]
      [evidence] = queried["evidence"]
      assert evidence["citation"]["source_id"] === "fixture:index-epoch"
      assert evidence["citation"]["quote"] === "Orion has one exact owner."
    end

    defp index_context do
      parent = Path.join(System.tmp_dir!(), "ipse-index-epoch-" <> Usage.id())
      File.mkdir!(parent)
      File.chmod!(parent, 0o700)
      on_exit(fn -> File.rm_rf!(parent) end)
      project = JSON.sha256("synthetic index epoch project")

      %{
        root: Path.join(parent, "collections"),
        namespace: Ipse.Extension.CollectionStore.namespace(project),
        interpose: false,
        owner: %{
          "project_id" => project,
          "identity_sha256" => JSON.sha256("synthetic index identity"),
          "session_id" => Usage.id(),
          "invocation_id" => Usage.id()
        }
      }
    end

    defp seed_index_source(ctx) do
      source = %{
        "source_id" => "fixture:index-epoch",
        "partition" => "notes",
        "generation" => 1,
        "title" => "Synthetic",
        "text" => "Orion has one exact owner.",
        "uri" => "provided:index-epoch",
        "observed_at_ms" => 10,
        "event_at_ms" => nil,
        "expires_at_ms" => nil,
        "origin" => %{
          "kind" => "provided",
          "store_profile" => "local",
          "partition_or_scope" => "notes",
          "receipt" => nil,
          "historical" => false
        }
      }

      assert %{"status" => "stored"} =
               put_source(ctx, %{
                 "source" => source,
                 "expected_revision" => 0,
                 "continuation" => nil
               })
    end

    defp index(ctx, action, token),
      do:
        drive(
          C.start(@profile, :lexical_build, %{"action" => action, "continuation" => token}),
          ctx
        )

    defp open_index_fence(ctx) do
      {:ok, snapshot} = Collection.document_snapshot(ctx.root, ctx.namespace)

      fence = %{
        id: Usage.id(),
        close: Usage.id(),
        epoch: snapshot["document_maintenance"]["epoch"] + 1
      }

      assert {:ok, _} =
               Collection.document_maintenance(
                 ctx.root,
                 ctx.namespace,
                 %{
                   "op" => "maintenance.open",
                   "expected_generation" => snapshot["generation"],
                   "expected_epoch" => fence.epoch - 1,
                   "maintenance_id" => fence.id,
                   "purpose" => "checkpoint_inspection",
                   "close_operation_id" => fence.close
                 },
                 Usage.id(),
                 ctx.owner
               )

      fence
    end

    defp close_index_fence(ctx, fence) do
      {:ok, snapshot} = Collection.document_snapshot(ctx.root, ctx.namespace)

      assert {:ok, _} =
               Collection.document_maintenance(
                 ctx.root,
                 ctx.namespace,
                 %{
                   "op" => "maintenance.close",
                   "expected_generation" => snapshot["generation"],
                   "expected_epoch" => fence.epoch,
                   "maintenance_id" => fence.id
                 },
                 fence.close,
                 ctx.owner
               )
    end

    @tag :split_append_native
    @tag timeout: 180_000
    test "native append keeps both metadata stages until its final verified atomic switch" do
      exercise(false)
    end

    @tag :split_append_root_race
    @tag timeout: 180_000
    test "a native root write after stage inspection prevents the final append switch" do
      exercise(true)
    end

    @tag :split_append_empty_native
    @tag timeout: 180_000
    test "explicit empty facts survive native append, paged selection and hydration" do
      exercise(false, true)
    end

    @tag :split_append_v1_selection
    @tag timeout: 180_000
    test "the original directory selection is bound to its staged Job" do
      exercise(false, true, "finalize")
    end

    @tag :projection_commit_root_race
    @tag timeout: 180_000
    test "a native write after projection stage inspection prevents the projection switch" do
      projection_commit(true)
    end

    @tag :projection_commit_native
    @tag timeout: 180_000
    test "an unchanged native snapshot permits the fact projection switch" do
      projection_commit(false)
    end

    @tag :projection_commit_fact_native
    @tag timeout: 180_000
    test "an unchanged native snapshot authenticates a populated fact projection" do
      projection_commit(false, true)
    end

    @tag :fact_input_native
    @tag timeout: 180_000
    test "a fixed fact-input slot is bound to its source, revision and expiry" do
      projection_commit(false, false, true)
    end

    defp projection_commit(interpose?, populated? \\ false, input? \\ false) do
      parent = Path.join(System.tmp_dir!(), "ipse-projection-race-" <> Usage.id())
      File.mkdir!(parent)
      File.chmod!(parent, 0o700)
      on_exit(fn -> File.rm_rf!(parent) end)

      ctx = %{
        root: Path.join(parent, "collections"),
        namespace: Ipse.Extension.CollectionStore.namespace(JSON.sha256("synthetic project")),
        interpose: interpose?,
        owner: %{
          "project_id" => JSON.sha256("synthetic project"),
          "identity_sha256" => JSON.sha256("synthetic identity"),
          "session_id" => Usage.id(),
          "invocation_id" => Usage.id()
        }
      }

      source_expiry = System.system_time(:millisecond) + 120_000
      ctx = Map.put(ctx, :source_expiry, source_expiry)

      source = %{
        "source_id" => "fixture:projection-race",
        "partition" => "notes",
        "generation" => 1,
        "title" => "Synthetic",
        "text" => "No explicit facts.",
        "uri" => "provided:projection-race",
        "observed_at_ms" => 10,
        "event_at_ms" => nil,
        "expires_at_ms" => source_expiry,
        "origin" => %{
          "kind" => "provided",
          "store_profile" => "local",
          "partition_or_scope" => "notes",
          "receipt" => nil,
          "historical" => false
        }
      }

      assert %{"status" => "stored"} =
               put_source(ctx, %{
                 "source" => source,
                 "expected_revision" => 0,
                 "continuation" => nil
               })

      if input?, do: verify_fact_input_slot(ctx, source)

      {:ok, stored} = Evidence.collection_source(source)
      {:ok, [chunk]} = Evidence.chunks(stored)
      {:ok, citation} = Evidence.citation(stored, chunk, chunk["start_byte"], chunk["end_byte"])

      {:ok, fact} =
        Evidence.fact(%{
          "subject" => "Source",
          "predicate" => "states",
          "object" => "absence",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "extraction" => @facts,
          "citations" => [citation]
        })

      args = %{
        "source_id" => source["source_id"],
        "selection" => @facts,
        "facts" => if(populated?, do: [fact], else: []),
        "expected_revision" => 0,
        "as_of_ms" => 20,
        "continuation" => nil
      }

      result = project_facts(ctx, args)
      root = read(ctx, "facts.notes." <> Evidence.sha256(source["source_id"]))

      if interpose? do
        assert {:done, {:error, _, _}} = result
        assert root == nil
        assert read(ctx, "generation.notes")["value"] == %{}
      else
        count = if(populated?, do: 1, else: 0)
        assert {:done, {:ok, %{"status" => "stored_facts", "facts" => ^count}}} = result
        assert root["value"]["facts"] == count
        assert read(ctx, "generation.notes") == nil
      end
    end

    defp verify_fact_input_slot(ctx, source) do
      {:ok, stored} = Evidence.collection_source(source)

      row = %{
        "subject" => "Source",
        "predicate" => "states",
        "object" => "absence",
        "polarity" => "positive",
        "inferred" => false,
        "valid_from_ms" => nil,
        "valid_to_ms" => nil,
        "spans" => [[0, 0, 2]]
      }

      {:ok, %{pages: [page], manifest: manifest}} =
        IpseKnowledge.Store.Collection.Projection.fact_input_pages(stored, [row])

      catalog = read(ctx, "catalog.notes")

      slot = %{
        "version" => 1,
        "kind" => "explicit_fact_input_slot",
        "draft_id" => Usage.id(),
        "source_key" => stored["source_key"],
        "catalog_sha256" => catalog["sha256"],
        "manifest" => manifest,
        "page" => page
      }

      data = IO.iodata_to_binary(Elixir.JSON.encode!(slot))

      assert {:ok, %{request: request, deadline: deadline}} =
               Collection.with_document_read(ctx.root, ctx.namespace, fn witness, reader ->
                 request = %{
                   "op" => "value.put_inline",
                   "key" => "factdraft.notes.0",
                   "expected_revision" => 0,
                   "byte_count" => byte_size(data),
                   "sha256" => JSON.sha256(data),
                   "data" => data,
                   "generation" => witness["root"]["generation"]
                 }

                 now = System.system_time(:millisecond)
                 check = Ipse.Extension.Collection.DocumentSourceUse

                 assert {:ok, proof} =
                          check.authenticate_fact_input(reader, witness, request, now)

                 assert proof.publish_before_ms === ctx.source_expiry

                 assert {:error, :document_source_use_refused} =
                          check.authenticate_fact_input(
                            reader,
                            witness,
                            request,
                            ctx.source_expiry
                          )

                 assert {:error, :document_source_use_refused} =
                          check.authenticate_fact_input(
                            reader,
                            witness,
                            %{request | "expected_revision" => 1},
                            now
                          )

                 {:ok, %{request: request, deadline: proof.publish_before_ms}}
               end)

      assert {:ok, _} =
               DocumentStage.execute(ctx.root, ctx.namespace, request, Usage.id(), ctx.owner,
                 publish_before_ms: deadline
               )

      assert read(ctx, "factdraft.notes.0")["value"] === slot

      assert {:ok, :checked} =
               Collection.with_document_read(ctx.root, ctx.namespace, fn witness, reader ->
                 assert {:error, :document_source_use_refused} =
                          Ipse.Extension.Collection.DocumentSourceUse.authenticate_fact_input(
                            reader,
                            witness,
                            request,
                            System.system_time(:millisecond)
                          )

                 {:ok, :checked}
               end)
    end

    defp project_facts(ctx, args) do
      case drive(C.start(@profile, :fact_store, args), Map.put(ctx, :projection_proof, true)) do
        {:done, {:continue, value}} ->
          token = value["continuation"]
          if ctx.interpose and length(token["stages"]) == 2, do: Process.put(:split_root_race, 0)
          project_facts(ctx, %{args | "continuation" => token})

        result ->
          result
      end
    end

    defp exercise(interpose?, empty? \\ false, final_action \\ "finalize_paged") do
      parent = Path.join(System.tmp_dir!(), "ipse-split-append-" <> Usage.id())
      File.mkdir!(parent)
      File.chmod!(parent, 0o700)

      ctx = %{
        root: Path.join(parent, "collections"),
        namespace: Ipse.Extension.CollectionStore.namespace(JSON.sha256("synthetic project")),
        interpose: interpose?,
        owner: %{
          "project_id" => JSON.sha256("synthetic project"),
          "identity_sha256" => JSON.sha256("synthetic identity"),
          "session_id" => Usage.id(),
          "invocation_id" => Usage.id()
        }
      }

      source = %{
        "source_id" => "fixture:split",
        "partition" => "notes",
        "generation" => 1,
        "title" => "Synthetic",
        "text" => "A source supports a staged relation.",
        "uri" => "provided:split",
        "observed_at_ms" => 10,
        "event_at_ms" => nil,
        "expires_at_ms" => System.system_time(:millisecond) + 120_000,
        "origin" => %{
          "kind" => "provided",
          "store_profile" => "local",
          "partition_or_scope" => "notes",
          "receipt" => nil,
          "historical" => false
        }
      }

      ctx = Map.put(ctx, :source_expiry, source["expires_at_ms"])

      assert %{"status" => "stored"} =
               put_source(ctx, %{
                 "source" => source,
                 "expected_revision" => 0,
                 "continuation" => nil
               })

      begun = job(ctx, job_args("begin", nil, nil))
      assert begun["status"] == "groups"

      {:done, {:ok, snapshot}} =
        drive(
          C.start(@profile, :source_bundles, %{
            "source_keys" => [Evidence.sha256(source["source_id"])],
            "as_of_ms" => 20
          }),
          ctx
        )

      [bundle] = snapshot["bundles"]
      stored = bundle["source"]
      {:ok, [chunk]} = Evidence.chunks(stored)
      {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

      {:ok, vector} =
        Evidence.vector(
          Map.merge(Map.delete(@vector, "encoding"), %{
            "chunk_id" => chunk["chunk_id"],
            "input_sha256" => input,
            "values" => List.duplicate(1.0, 1024)
          })
        )

      {:ok, citation} = Evidence.citation(stored, chunk, chunk["start_byte"], chunk["end_byte"])

      {:ok, fact} =
        Evidence.fact(%{
          "subject" => "Source",
          "predicate" => "supports",
          "object" => "relation",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "extraction" => @facts,
          "citations" => [citation]
        })

      supplied = [
        %{
          "source_key" => stored["source_key"],
          "source_bundle_sha256" =>
            Evidence.sha256(IO.iodata_to_binary(Elixir.JSON.encode!(stored))),
          "vectors" => [vector],
          "facts" => if(empty?, do: [], else: [fact])
        }
      ]

      {:ok, plan} = Generation.pack_group("notes", 0, [bundle], supplied, @vector, @facts)

      {:done, {:ok, page}} =
        drive(C.start(@profile, :value_read, %{"key" => "catalog.notes.0"}), ctx)

      group = %{"plan" => plan, "bundles" => [bundle], "catalog_page" => page["record"]["value"]}
      inspected = job(ctx, job_args("inspect", nil, nil))
      old_catalog = read(ctx, "catalog.notes")
      assert read(ctx, "generation.notes") == nil

      {completed, stage_counts} =
        append(ctx, job_args("append", inspected["continuation"], group), [])

      assert stage_counts == [1, 2]
      assert read(ctx, "catalog.notes")["value"] === old_catalog["value"]

      if interpose? do
        assert completed == {:error, :collection_refused}
        assert read(ctx, "generation.notes")["value"] == %{}
        assert read(ctx, "genjob.notes")["value"]["cursor"] == 0

        assert {:ok, %{"stages" => stages}} =
                 DocumentStage.execute(
                   ctx.root,
                   ctx.namespace,
                   %{"op" => "stage.list"},
                   Usage.id(),
                   ctx.owner
                 )

        assert length(stages) == 2
      else
        assert completed["status"] == "manifests" and completed["job"]["cursor"] == 1
        assert read(ctx, "generation.notes") == nil
        assert read(ctx, "genjob.notes")["value"] === completed["job"]

        if empty? do
          selected = finalize(ctx, job_args(final_action, completed["continuation"], nil))
          assert selected["status"] == "selected"
          root = read(ctx, "generation.notes")["value"]
          assert root["facts"] == 0 and root["entities"] == 0 and root["entity_pages"] == []

          assert {:ok, :checked} =
                   Collection.with_document_read(ctx.root, ctx.namespace, fn _, retained ->
                     check = Ipse.Extension.Collection.DocumentSourceUse
                     [ref] = root["manifests"]

                     assert {:ok, proof} =
                              check.authenticate_manifest_group(
                                retained,
                                "notes",
                                root["catalog_sha256"],
                                ref,
                                0
                              )

                     assert length(proof.sources) == 1
                     assert proof.header["cursor"] == 0
                     assert check.current?(proof, System.system_time(:millisecond))

                     bad = Map.put(ref, "sha256", String.duplicate("0", 64))

                     assert {:error, :document_source_use_refused} =
                              check.authenticate_manifest_group(
                                retained,
                                "notes",
                                root["catalog_sha256"],
                                bad,
                                0
                              )

                     assert {:error, :document_source_use_refused} =
                              check.authenticate_manifest_group(
                                retained,
                                "notes",
                                root["catalog_sha256"],
                                ref,
                                8
                              )

                     missing_header = fn key ->
                       if String.starts_with?(key, "gengrp."),
                         do: {:ok, nil},
                         else: retained.(key)
                     end

                     assert {:error, :document_source_use_refused} =
                              check.authenticate_manifest_group(
                                missing_header,
                                "notes",
                                root["catalog_sha256"],
                                ref,
                                0
                              )

                     assert {:ok, manifest} = DocumentStage.read_value(retained, ref["key"])

                     altered =
                       put_in(
                         manifest["value"],
                         ["rows", Access.at(0), "sources", Access.at(0), Access.at(0)],
                         String.duplicate("0", 64)
                       )

                     bytes = Jason.encode!(altered)
                     sha = JSON.sha256(bytes)

                     fake_ref = %{
                       "key" => "genman.notes." <> sha,
                       "sha256" => sha,
                       "byte_count" => byte_size(bytes)
                     }

                     fake_row = %{
                       "revision" => 1,
                       "operation_id" => Usage.id(),
                       "value" => %{
                         "version" => 1,
                         "kind" => "document_value",
                         "sha256" => sha,
                         "byte_count" => byte_size(bytes),
                         "parts" => [bytes]
                       }
                     }

                     forged = fn key ->
                       if key == fake_ref["key"], do: {:ok, fake_row}, else: retained.(key)
                     end

                     assert {:error, :document_source_use_refused} =
                              check.authenticate_manifest_group(
                                forged,
                                "notes",
                                root["catalog_sha256"],
                                fake_ref,
                                0
                              )

                     {:ok, :checked}
                   end)

          {:done, {:ok, result}} =
            drive(
              C.start(@profile, :generation_selected, %{
                "source_ids" => [source["source_id"]],
                "vector_selection" => @vector,
                "fact_selection" => @facts,
                "as_of_ms" => 20
              }),
              ctx
            )

          assert [%{"facts" => [], "vectors" => [_]}] = result["selected"]
          refute result["coverage"]["model_receipt_provenance"]
        end
      end

      IO.puts("Retained synthetic split-append native store: " <> parent)
    end

    defp job_args(action, token, group),
      do: %{
        "action" => action,
        "vector_selection" => @vector,
        "fact_selection" => @facts,
        "continuation" => token,
        "group" => group
      }

    defp put_source(ctx, args) do
      case drive(C.start(@profile, :put, args), ctx) do
        {:done, {:continue, value}} ->
          put_source(ctx, %{args | "continuation" => value["continuation"]})

        {:done, {:ok, value}} ->
          value
      end
    end

    defp job(ctx, args) do
      case drive(C.start(@profile, :generation_job, args), ctx) do
        {:done, {:continue, value}} -> job(ctx, %{args | "continuation" => value["continuation"]})
        {:done, {:ok, value}} -> value
      end
    end

    defp finalize(ctx, args) do
      result = job(Map.put(ctx, :selection_proof, true), args)

      if result["status"] == "selected",
        do: result,
        else: finalize(ctx, %{args | "continuation" => result["continuation"]})
    end

    defp append(ctx, args, counts) do
      case drive(C.start(@profile, :generation_job, args), Map.put(ctx, :group_proof, true)) do
        {:done, {:continue, value}} ->
          token = value["continuation"]
          n = length(token["stages"])
          counts = if n > 0 and n not in counts, do: counts ++ [n], else: counts
          if n > 0, do: assert(read(ctx, "generation.notes") == nil)
          if n == 2 and ctx.interpose, do: Process.put(:split_root_race, 0)
          append(ctx, %{args | "continuation" => token}, counts)

        {:done, {:ok, value}} ->
          {value, counts}

        {:done, {:error, code, _}} ->
          {{:error, code}, counts}
      end
    end

    defp drive({:call, request, continuation}, ctx) do
      assert :ok = Ipse.Extension.CollectionStore.validate(request)
      id = Usage.id()
      maybe_check_projection(ctx, request["request"])
      maybe_check_group(ctx, request["request"])
      maybe_check_selection(ctx, request["request"])

      case DocumentStage.execute(ctx.root, ctx.namespace, request["request"], id, ctx.owner) do
        {:ok, result} ->
          interpose_root(ctx, request["request"], result)

          wrapped = %{
            "version" => 1,
            "operation_id" => id,
            "request_sha256" => JSON.digest([request]),
            "result" => result
          }

          assert Ipse.Extension.CollectionStore.valid_outcome?(request, "ok", wrapped, id)
          drive(C.resume(continuation, %{"status" => "ok", "value" => wrapped}), ctx)

        {:error, :document_store_refused} ->
          drive(
            C.resume(continuation, %{
              "status" => "failed",
              "value" => %{"code" => "document_store_refused"}
            }),
            ctx
          )
      end
    end

    defp drive(done, _ctx), do: done

    defp maybe_check_selection(
           %{selection_proof: true} = ctx,
           %{"op" => "commit", "stages" => [_, _, _]} = request
         ) do
      now = System.system_time(:millisecond)

      assert {:ok, captured} =
               Collection.with_document_read(ctx.root, ctx.namespace, fn witness, read ->
                 check = Ipse.Extension.Collection.DocumentSourceUse

                 assert {:ok, proof} =
                          check.authenticate_selection_commit(
                            read,
                            witness,
                            request,
                            ctx.owner,
                            now
                          )

                 assert proof.generation === request["generation"] and proof.source_count == 1
                 assert proof.publish_before_ms > now
                 [ref] = proof.manifests

                 assert {:ok, group} =
                          check.authenticate_manifest_group(
                            read,
                            proof.partition,
                            proof.catalog_sha256,
                            ref,
                            0
                          )

                 assert group.header["vector_selection"] === proof.vector_selection
                 assert group.header["fact_selection"] === proof.fact_selection
                 assert check.current?(group, now)
                 wrong = Map.put(ctx.owner, "identity_sha256", JSON.sha256("other"))

                 assert {:error, :document_source_use_refused} =
                          check.authenticate_selection_commit(read, witness, request, wrong, now)

                 assert {:error, :document_source_use_refused} =
                          check.authenticate_selection_commit(
                            read,
                            witness,
                            request,
                            ctx.owner,
                            proof.publish_before_ms
                          )

                 missing_catalog = fn key ->
                   if key == "catalog.notes", do: {:ok, nil}, else: read.(key)
                 end

                 assert {:error, :document_source_use_refused} =
                          check.authenticate_selection_commit(
                            missing_catalog,
                            witness,
                            request,
                            ctx.owner,
                            now
                          )

                 stale_witness =
                   put_in(witness, ["root", "generation"], request["generation"] + 1)

                 assert {:error, :document_source_use_refused} =
                          check.authenticate_selection_commit(
                            read,
                            stale_witness,
                            request,
                            ctx.owner,
                            now
                          )

                 {:ok, proof}
               end)

      check = Ipse.Extension.Collection.DocumentSourceUse

      assert {:ok, result} =
               check.authenticate_selection_sources(ctx.root, ctx.namespace, captured)

      assert result.generation === request["generation"] and result.sources == 1 and
               result.groups == 1

      assert result.publish_before_ms === ctx.source_expiry

      for bad <- [
            Map.update!(captured, :generation, &(&1 + 1)),
            Map.put(captured, :source_heads_sha256, String.duplicate("0", 64)),
            Map.put(captured, :publish_before_ms, now)
          ] do
        assert {:error, :document_source_use_refused} =
                 check.authenticate_selection_sources(ctx.root, ctx.namespace, bad)
      end
    end

    defp maybe_check_selection(_, _), do: :ok

    defp maybe_check_group(
           %{group_proof: true} = ctx,
           %{"op" => "commit", "stages" => [_, _]} = request
         ) do
      now = System.system_time(:millisecond)

      guarded = %{
        "op" => "collection.store",
        "scope" => "project",
        "source_guard" => "explicit_fact_group_v1",
        "request" => request
      }

      assert :ok = Ipse.Extension.CollectionStore.validate(guarded)

      assert {:error, :document_store_refused} =
               Ipse.Extension.CollectionStore.validate(
                 put_in(guarded, ["request", "op"], "stage.inspect")
               )

      assert {:ok, :checked} =
               Collection.with_document_read(ctx.root, ctx.namespace, fn witness, read ->
                 check = Ipse.Extension.Collection.DocumentSourceUse
                 result = check.authenticate_group_commit(read, witness, request, ctx.owner, now)

                 if witness["root"]["generation"] === request["generation"] do
                   assert {:ok, facts} = result
                   assert facts.generation === request["generation"]
                   assert length(facts.source.sources) == 1
                   assert facts.publish_before_ms === ctx.source_expiry
                   assert check.current?(facts.source, now)

                   assert {:ok, catalog} = DocumentStage.read_value(read, "catalog.notes")

                   assert {:ok, group} =
                            check.authenticate_catalog_group(read, "notes", catalog["sha256"], 0)

                   assert group.sources === facts.source.sources
                   assert length(group.catalog_rows) == 1

                   for prefix <- ["gensum.", "gengrp.", "catalog.notes.0", "source.notes."] do
                     incomplete = fn key ->
                       if String.starts_with?(key, prefix), do: {:ok, nil}, else: read.(key)
                     end

                     assert {:error, :document_source_use_refused} =
                              check.authenticate_group_commit(
                                incomplete,
                                witness,
                                request,
                                ctx.owner,
                                now
                              )
                   end

                   wrong_owner = Map.put(ctx.owner, "identity_sha256", JSON.sha256("other"))

                   assert {:error, :document_source_use_refused} =
                            check.authenticate_group_commit(
                              read,
                              witness,
                              request,
                              wrong_owner,
                              now
                            )

                   assert {:error, :document_source_use_refused} =
                            check.authenticate_group_commit(
                              read,
                              witness,
                              request,
                              ctx.owner,
                              facts.publish_before_ms
                            )
                 else
                   assert {:error, :document_source_use_refused} = result
                 end

                 {:ok, :checked}
               end)
    end

    defp maybe_check_group(_, _), do: :ok

    defp maybe_check_projection(
           %{projection_proof: true} = ctx,
           %{"op" => "commit", "stages" => [_, _]} = request
         ) do
      now = System.system_time(:millisecond)

      assert {:ok, :checked} =
               Collection.with_document_read(ctx.root, ctx.namespace, fn witness, read ->
                 check = Ipse.Extension.Collection.DocumentSourceUse

                 result =
                   check.authenticate_projection_commit(read, witness, request, ctx.owner, now)

                 if witness["root"]["generation"] === request["generation"] do
                   assert {:ok, facts} = result
                   assert facts.generation === request["generation"]

                   assert facts.publish_before_ms === ctx.source_expiry and
                            facts.publish_before_ms > now

                   assert check.current?(facts.source, now)
                   wrong_owner = Map.put(ctx.owner, "identity_sha256", JSON.sha256("other"))

                   assert {:error, :document_source_use_refused} =
                            check.authenticate_projection_commit(
                              read,
                              witness,
                              request,
                              wrong_owner,
                              now
                            )

                   assert {:error, :document_source_use_refused} =
                            check.authenticate_projection_commit(
                              read,
                              witness,
                              request,
                              ctx.owner,
                              facts.publish_before_ms
                            )
                 else
                   assert {:error, :document_source_use_refused} = result
                 end

                 {:ok, :checked}
               end)
    end

    defp maybe_check_projection(_, _), do: :ok

    defp interpose_root(ctx, %{"op" => "stage.inspect"}, result) do
      case Process.get(:split_root_race) do
        0 ->
          Process.put(:split_root_race, 1)

        1 ->
          Process.delete(:split_root_race)
          data = "{}"

          request = %{
            "op" => "value.put_inline",
            "key" => "generation.notes",
            "expected_revision" => 0,
            "generation" => result["generation"],
            "data" => data,
            "sha256" => JSON.sha256(data),
            "byte_count" => byte_size(data)
          }

          assert {:ok, _} =
                   DocumentStage.execute(ctx.root, ctx.namespace, request, Usage.id(), ctx.owner)

        _ ->
          :ok
      end
    end

    defp interpose_root(_, _, _), do: :ok

    defp read(ctx, key) do
      {:ok, result} =
        Collection.with_document_read(ctx.root, ctx.namespace, fn _, read ->
          case DocumentStage.read_value(read, key) do
            {:ok, value} -> {:ok, %{value: value}}
          end
        end)

      result.value
    end
  end
else
  defmodule Ipse.CollectionSplitAppendNativeTest do
    use ExUnit.Case, async: false

    setup_all do
      root = Path.join(System.tmp_dir!(), "ipse-split-append-artifact-" <> Ipse.Usage.id())
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      artifact = Path.join(root, "corpus")

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
            "corpus",
            "--preset",
            "collection-dense"
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output
      %{artifact: artifact}
    end

    for {tag, description} <- [
          {:split_append_native,
           "native append retains both metadata stages until the final switch"},
          {:split_append_root_race, "a changed root prevents the final append switch"},
          {:projection_commit_root_race, "a changed root prevents the final projection switch"},
          {:projection_commit_native, "an unchanged snapshot permits the fact projection switch"},
          {:projection_commit_fact_native, "a populated fact projection authenticates natively"},
          {:fact_input_native, "a fact-input slot authenticates against its source and deadline"},
          {:split_append_empty_native, "empty facts survive native append and hydration"},
          {:split_append_v1_selection, "original directory selection binds its staged Job"},
          {:lexical_maintenance_stale, "maintenance cannot renew a stale lexical job"},
          {:lexical_maintenance_fresh, "a fresh lexical job publishes after maintenance"},
          {:lexical_retirement_public_pause, "public Corpus resumes a paused retirement"}
        ] do
      @tag tag
      @tag timeout: 180_000
      test description, %{artifact: artifact} do
        tag = unquote(tag)

        paths =
          :code.get_path()
          |> Enum.map(&List.to_string/1)
          |> Enum.filter(&(Path.basename(&1) == "ebin"))
          |> Enum.flat_map(&["-pa", &1])

        script =
          "ExUnit.start(autorun: false, exclude: [:test], include: [{#{inspect(tag)}, true}]); " <>
            "{:ok, _} = Application.ensure_all_started(:ipse); " <>
            "Code.require_file(#{inspect(Path.expand(__ENV__.file))}); " <>
            "result = ExUnit.run(); " <>
            "if Map.take(result, [:total, :failures, :excluded, :skipped]) != " <>
            "%{total: 11, failures: 0, excluded: 10, skipped: 0}, do: System.halt(1); " <>
            "IO.puts(\"SPLIT_APPEND_CONTROL_PASS #{tag}\")"

        {output, status} =
          System.cmd(
            System.find_executable("elixir"),
            ["--erl", "+S 2:2"] ++ paths ++ ["-pa", Path.join(artifact, "ebin"), "-e", script],
            stderr_to_stdout: true,
            env: [
              {"IPSE_SPLIT_APPEND_CHILD", "1"},
              {"ERL_LIBS", Path.dirname(Application.app_dir(:ipse))}
            ]
          )

        assert status == 0, output

        assert Enum.count(String.split(output, "\n"), &(&1 == "SPLIT_APPEND_CONTROL_PASS #{tag}")) ==
                 1

        IO.write(output)
      end
    end
  end
end
