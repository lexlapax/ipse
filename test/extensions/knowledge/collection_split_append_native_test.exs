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
        namespace: JSON.sha256("synthetic projection race"),
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
        namespace: JSON.sha256("synthetic split append"),
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
          {:split_append_v1_selection, "original directory selection binds its staged Job"}
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
            "result = ExUnit.run(); if result.failures != 0, do: System.halt(1)"

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
        assert output =~ "Result: 1 passed"
        IO.write(output)
      end
    end
  end
end
