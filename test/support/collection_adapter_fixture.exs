defmodule IpseTest.CollectionAdapter do
  @behaviour Ipse.Extension
  alias IpseKnowledge.{Documents, Evidence}
  alias IpseKnowledge.Store.Collection

  @caps ~w(invoke.command invoke.result.pages host.actions host.actions.mixed host.collection.store)
  @exports %{
    "version" => 1,
    "tools" => [],
    "services" => [],
    "commands" =>
      for(
        id <- ~w(put query inspect lexical index namespace vectors facts),
        do: %{
          "id" => id,
          "description" => "Synthetic packed source fixture",
          "arguments_schema" => %{"type" => "object"},
          "result_schema" => %{"type" => "object"}
        }
      )
  }
  def describe, do: %{"sdk" => 2, "capabilities" => @caps, "exports" => @exports}
  def init(options), do: {:ok, options}

  def handle("invoke.command", payload, state) do
    args = payload["arguments"]
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    mode =
      if payload["id"] == "vectors" and args["group_mode"] in ~w(group_job group_append),
        do: args["group_mode"],
        else: payload["id"]

    state = Map.merge(state, %{mode: mode, args: args})

    case mode do
      "put" when :erlang.map_get("retire_progress", args) == true ->
        drive(
          Collection.start(profile, :snapshot, %{}),
          Map.merge(state, %{mode: "retire_progress", retire_phase: :snapshot})
        )

      "put" when :erlang.is_map_key("inspect_progress", args) ->
        drive(
          Collection.start(profile, :progress_inspect, %{"head_id" => args["inspect_progress"]}),
          state
        )

      "group_job" ->
        operation =
          if args["guarded_selection"] == true,
            do: :guarded_generation_finalize,
            else: :generation_job

        drive(
          Collection.start(profile, operation, %{
            "action" => args["action"],
            "vector_selection" => vector_selection(args),
            "fact_selection" => fact_selection(args),
            "continuation" => args["continuation"],
            "group" => nil
          }),
          state
        )

      "group_append" ->
        drive(
          Collection.start(profile, :source_bundles, %{
            "source_keys" =>
              Enum.map(args["source_ids"] || [args["source_id"]], &Evidence.sha256/1),
            "as_of_ms" => 20
          }),
          Map.put(state, :group_phase, :source)
        )

      "put" when :erlang.map_get("raw_value", args) == true ->
        value =
          if args["fact_key"] || args["draft_key"] || args["job_key"] || args["generation_key"],
            do: %{"synthetic" => true},
            else: %{"paragraphs" => List.duplicate(String.duplicate("\\", 2048), 6)}

        key =
          cond do
            args["fact_key"] -> "facts.notes." <> Evidence.sha256("fixture:forged")
            args["draft_key"] -> "factdraft.notes.0"
            args["job_key"] -> "genjob.notes"
            args["generation_key"] -> "generation.notes"
            true -> "fixture.value"
          end

        drive(
          Collection.start(profile, :value_write, %{
            "key" => key,
            "value" => value,
            "expected_revision" => 0,
            "reuse" => false,
            "continuation" => args["continuation"],
            "effects_used" => args["effects_used"] || 0
          }),
          Map.put(state, :mode, "value")
        )

      "facts" ->
        if args["action"] == "get" do
          drive(
            Collection.start(profile, :fact_selected, %{
              "source_id" => args["source_id"],
              "selection" => fact_selection(args),
              "as_of_ms" => 20
            }),
            Map.put(state, :fact_phase, :get)
          )
        else
          drive(
            Collection.start(profile, :selected, %{
              "source_ids" => [args["source_id"]],
              "as_of_ms" => 20
            }),
            Map.put(state, :fact_phase, :source)
          )
        end

      "vectors" ->
        if args["shared_selected"] == true do
          drive(
            Collection.start(profile, :generation_selected, %{
              "source_ids" => args["source_ids"],
              "vector_selection" => vector_selection(args),
              "fact_selection" => fact_selection(args),
              "as_of_ms" => args["as_of_ms"] || 20
            }),
            Map.put(state, :vector_phase, :shared_selected)
          )
        else
          if args["shared"] == true do
            drive(
              Collection.start(profile, :source_bundles, %{
                "source_keys" => Enum.map(args["source_ids"], &Evidence.sha256/1),
                "as_of_ms" => 20
              }),
              Map.put(state, :vector_phase, :shared)
            )
          else
            if args["action"] == "get" do
              drive(
                Collection.start(profile, :vector_selected, %{
                  "source_id" => args["source_id"],
                  "selection" => vector_selection(args),
                  "as_of_ms" => 20
                }),
                Map.put(state, :vector_phase, :get)
              )
            else
              drive(
                Collection.start(profile, :selected, %{
                  "source_ids" => [args["source_id"]],
                  "as_of_ms" => 20
                }),
                Map.put(state, :vector_phase, :source)
              )
            end
          end
        end

      "put" ->
        source =
          if args["tiny"] == true,
            do: tiny(args["source_id"], args["generation"] || 1, args),
            else:
              source(
                args["generation"] || 1,
                args["many"] == true,
                if(args["large_blocks"], do: 6500, else: 1600)
              )

        request = %{
          "source" => source,
          "expected_revision" => args["expected_revision"] || 0,
          "continuation" => args["continuation"]
        }

        request =
          if Map.has_key?(args, "effects_used"),
            do: Map.put(request, "effects_used", args["effects_used"]),
            else: request

        result =
          if Map.has_key?(args, "primitive_epoch"),
            do: Collection.start_with_epoch(profile, :put, request, args["primitive_epoch"]),
            else: Collection.start(profile, :put, request)

        drive(result, state)

      "query" ->
        drive(
          Collection.start(profile, :selected, %{
            "source_ids" => args["source_ids"] || ["fixture:word"],
            "as_of_ms" => 20
          }),
          state
        )

      "lexical" ->
        drive(
          Collection.start(profile, :lexical, %{
            "source_ids" => args["source_ids"] || ["fixture:word"],
            "as_of_ms" => 20
          }),
          state
        )

      "index" ->
        drive(
          Collection.start(profile, :lexical_build, %{
            "action" => args["action"] || "begin",
            "continuation" => args["continuation"]
          }),
          state
        )

      "namespace" ->
        drive(
          Collection.start(profile, :lexical_query, %{
            "query" => args["query"] || "Nocturne",
            "top_k" => args["top_k"] || 1,
            "as_of_ms" => args["as_of_ms"] || 20
          }),
          state
        )

      "inspect" ->
        {:ok,
         %{
           "api_version" => 1,
           "kind" => "host_call",
           "request" => %{
             "op" => "collection.store",
             "scope" => "project",
             "request" => %{"op" => "snapshot"}
           }
         }, Map.put(state, :inspect_step, :snapshot)}
    end
  end

  def handle(
        "host.actions",
        %{"outcome" => %{"status" => "ok", "value" => value}},
        %{mode: "inspect", inspect_step: :snapshot} = state
      ) do
    request =
      Map.merge(state.args["ref"], %{
        "op" => "stage.inspect",
        "generation" => value["result"]["generation"]
      })

    {:ok,
     %{
       "api_version" => 1,
       "kind" => "host_call",
       "request" => %{"op" => "collection.store", "scope" => "project", "request" => request}
     }, %{state | inspect_step: :done}}
  end

  def handle("host.actions", %{"outcome" => outcome}, %{mode: "inspect"} = state),
    do: finish(outcome, state)

  def handle("host.actions", %{"outcome" => outcome}, state) do
    continuation =
      if state.mode == "group_job" and state.args["action"] == "abort" and
           state.args["force_retirement_pause"] == true and
           get_in(state.continuation, [:inner, :request, "request", "op"]) == "value.write_parts" and
           get_in(outcome, ["value", "result", "write", "state"]) == "open" do
        # Controlled budget after a real successful native write; no outcome is fabricated.
        state.continuation
        |> put_in([:generation_job, :effects], 16)
        |> put_in([:inner, :effects], 16)
      else
        state.continuation
      end

    drive(Collection.resume(continuation, outcome), state)
  end

  defp drive({:call, request, continuation}, state) do
    request =
      cond do
        state.mode == "group_job" and state.args["omit_selection_guard"] == true and
            request["source_guard"] == "explicit_generation_selection_v1" ->
          Map.delete(request, "source_guard")

        state.mode == "group_append" and state.args["omit_group_guard"] == true and
            request["source_guard"] == "explicit_fact_group_v1" ->
          Map.delete(request, "source_guard")

        state.mode == "facts" and state.args["omit_guard"] == true ->
          Map.delete(request, "source_guard")

        state.mode == "facts" and state.args["wrong_group_guard"] == true and
            request["source_guard"] == "explicit_fact_projection_v1" ->
          Map.put(request, "source_guard", "explicit_fact_group_v1")

        true ->
          request
      end

    {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request},
     Map.put(state, :continuation, continuation)}
  end

  defp drive({:done, {:continue, value}}, state), do: finish(value, state)

  defp drive({:done, {:ok, value}}, %{mode: "value"} = state),
    do: finish(Map.put(value, "status", "stored"), state)

  defp drive(
         {:done, {:ok, snapshot}},
         %{mode: "retire_progress", retire_phase: :snapshot} = state
       ) do
    progress = state.args["progress"]
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    with {:ok, epoch, "idle"} <- Collection.snapshot_epoch(snapshot),
         true <- Collection.progress_supported?(snapshot),
         true <- Collection.progress_receipt?(progress) do
      drive(
        Collection.start_with_progress(
          profile,
          :progress_retire,
          %{"generation" => snapshot["generation"]},
          epoch,
          %{
            "version" => 1,
            "action" => "retire",
            "head_id" => progress["head_id"],
            "revision" => progress["revision"]
          }
        ),
        %{state | retire_phase: :done}
      )
    else
      _ -> finish(%{"status" => "refused", "code" => "invalid_progress_retirement"}, state)
    end
  end

  defp drive({:done, {:ok, value}}, %{mode: "retire_progress", retire_phase: :done} = state),
    do: finish(Map.put(value, "status", "retired"), state)

  defp drive({:done, {:ok, snapshot}}, %{mode: "group_append", group_phase: :source} = state) do
    bundles = Enum.sort_by(snapshot["bundles"], & &1["source"]["source_key"])
    selection = vector_selection(state.args)

    supplied =
      Enum.map(bundles, fn bundle ->
        source = bundle["source"]
        {:ok, chunks} = Evidence.chunks(source)

        vectors =
          Enum.map(chunks, fn chunk ->
            {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

            {:ok, vector} =
              Evidence.vector(
                Map.merge(Map.delete(selection, "encoding"), %{
                  "chunk_id" => chunk["chunk_id"],
                  "input_sha256" => input,
                  "values" => List.duplicate(1.0, selection["dimensions"])
                })
              )

            vector
          end)

        %{
          "source_key" => source["source_key"],
          "source_bundle_sha256" => Evidence.sha256(IO.iodata_to_binary(JSON.encode!(source))),
          "vectors" => vectors,
          "facts" => []
        }
      end)

    {:ok, plan} =
      IpseKnowledge.Store.Collection.Generation.pack_group(
        "notes",
        state.args["cursor"] || 0,
        bundles,
        supplied,
        selection,
        fact_selection(state.args)
      )

    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    drive(
      Collection.start(profile, :value_read, %{
        "key" => "catalog.notes.#{div(state.args["cursor"] || 0, 16)}"
      }),
      state
      |> Map.put(:group_phase, :page)
      |> Map.put(:group_bundles, bundles)
      |> Map.put(:group_plan, plan)
    )
  end

  defp drive({:done, {:ok, page}}, %{mode: "group_append", group_phase: :page} = state) do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    group = %{
      "plan" => state.group_plan,
      "bundles" => state.group_bundles,
      "catalog_page" => page["record"]["value"]
    }

    drive(
      Collection.start(profile, :guarded_generation_append, %{
        "action" => "append",
        "vector_selection" => vector_selection(state.args),
        "fact_selection" => fact_selection(state.args),
        "continuation" => state.args["continuation"],
        "group" => group
      }),
      Map.put(state, :group_phase, :job)
    )
  end

  defp drive({:done, {:ok, snapshot}}, %{mode: "facts", fact_phase: :source} = state) do
    [source] = snapshot["sources"]
    {:ok, [chunk | _]} = Evidence.chunks(source)

    {:ok, citation} =
      Evidence.citation(
        source,
        chunk,
        chunk["start_byte"],
        min(chunk["end_byte"], chunk["start_byte"] + 32)
      )

    facts =
      for n <- 0..19 do
        {:ok, fact} =
          Evidence.fact(%{
            "subject" => "Entity#{rem(n, 5)}",
            "object" => "Entity#{rem(n + 1, 5)}",
            "predicate" => "relation#{n}-#{state.args["salt"] || 0}",
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => nil,
            "valid_to_ms" => nil,
            "extraction" => fact_selection(state.args),
            "citations" => [citation]
          })

        fact
      end

    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    drive(
      Collection.start(profile, :fact_store, %{
        "source_id" => source["source_id"],
        "selection" => fact_selection(state.args),
        "facts" => facts,
        "expected_revision" => state.args["expected_revision"] || 0,
        "as_of_ms" => 20,
        "continuation" => state.args["continuation"]
      }),
      %{state | fact_phase: :store}
    )
  end

  defp drive(
         {:done, {:ok, %{"source" => source, "facts" => facts} = snapshot}},
         %{mode: "facts"} = state
       ) do
    entities = facts |> Enum.flat_map(&[&1["subject"], &1["object"]]) |> Enum.uniq()
    receipt = Evidence.document_receipt(source)

    finish(
      %{
        "status" => "ok",
        "revision" => snapshot["revision"],
        "facts" => length(facts),
        "entities" => length(entities),
        "fact_ids" => Enum.map(facts, & &1["fact_id"]),
        "citation" => hd(hd(facts)["citations"]),
        "warnings" => if(is_map(receipt), do: receipt["warnings"], else: []),
        "coverage" => snapshot["coverage"]
      },
      state
    )
  end

  defp drive({:done, {:ok, snapshot}}, %{mode: "vectors", vector_phase: :shared_selected} = state) do
    selected = snapshot["selected"]
    facts = Enum.flat_map(selected, & &1["facts"])
    citations = Enum.map(selected, fn item -> hd(hd(item["facts"])["citations"]) end)

    warnings =
      Enum.flat_map(selected, fn item ->
        case Evidence.document_receipt(item["source"]) do
          nil -> []
          receipt -> receipt["warnings"]
        end
      end)

    finish(
      %{
        "status" => "ok",
        "sources" => length(selected),
        "vectors" => Enum.sum(Enum.map(selected, &length(&1["vectors"]))),
        "facts" => length(facts),
        "citations" => citations,
        "warnings" => warnings,
        "coverage" => snapshot["coverage"]
      },
      state
    )
  end

  defp drive({:done, {:ok, snapshot}}, %{mode: "vectors", vector_phase: :shared} = state) do
    bundles = snapshot["bundles"]

    bundles =
      if state.args["directory"],
        do: Enum.sort_by(bundles, & &1["source"]["source_key"]),
        else: bundles

    selection = vector_selection(state.args)
    extraction = fact_selection(state.args)

    supplied =
      Enum.map(bundles, fn bundle ->
        source = bundle["source"]
        {:ok, chunks} = Evidence.chunks(source)

        vectors =
          for {chunk, n} <- Enum.with_index(chunks) do
            {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

            {:ok, vector} =
              Evidence.vector(
                Map.merge(Map.delete(selection, "encoding"), %{
                  "chunk_id" => chunk["chunk_id"],
                  "input_sha256" => input,
                  "values" => for(i <- 1..selection["dimensions"], do: 1.0 + rem(i + n, 17) / 17)
                })
              )

            vector
          end

        [first | _] = chunks

        {:ok, citation} =
          Evidence.citation(
            source,
            first,
            first["start_byte"],
            min(first["end_byte"], first["start_byte"] + 32)
          )

        facts =
          for n <- 0..19 do
            {:ok, fact} =
              Evidence.fact(%{
                "subject" => "#{source["source_id"]}:Entity#{rem(n, 5)}",
                "predicate" => "relation#{n}",
                "object" => "#{source["source_id"]}:Entity#{rem(n + 1, 5)}",
                "polarity" => "positive",
                "inferred" => false,
                "valid_from_ms" => nil,
                "valid_to_ms" => nil,
                "extraction" => extraction,
                "citations" => [citation]
              })

            fact
          end

        %{
          "source_key" => source["source_key"],
          "source_bundle_sha256" => Evidence.sha256(IO.iodata_to_binary(JSON.encode!(source))),
          "vectors" => vectors,
          "facts" => facts
        }
      end)

    {:ok, plan} =
      IpseKnowledge.Store.Collection.Generation.pack_group(
        "notes",
        0,
        bundles,
        supplied,
        selection,
        extraction
      )

    values = Map.new(plan.values, &{&1.key, &1.value})
    expected = %{"cursor" => 0, "vector_selection" => selection, "fact_selection" => extraction}

    {:ok, ^supplied} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        plan.header,
        values,
        bundles,
        expected
      )

    [bundle | _] = bundles
    [data | _] = supplied
    [fact | _] = data["facts"]
    noncanonical = Map.put(fact, "version", 1.0)
    true = Evidence.valid_fact?(noncanonical)
    true = noncanonical["fact_id"] === fact["fact_id"]
    true = noncanonical["citations"] === fact["citations"]

    {:ok, legacy_pages} =
      IpseKnowledge.Store.Collection.Projection.pack_facts(
        bundle["source"],
        [noncanonical],
        extraction
      )

    {:ok, [^noncanonical]} =
      IpseKnowledge.Store.Collection.Projection.unpack_facts(
        bundle["source"],
        legacy_pages,
        extraction
      )

    noncanonical_supplied = put_in(supplied, [Access.at(0), "facts", Access.at(0)], noncanonical)

    {:error, :invalid_shared_projection_group} =
      IpseKnowledge.Store.Collection.Generation.pack_group(
        "notes",
        0,
        bundles,
        noncanonical_supplied,
        selection,
        extraction
      )

    [first | _] = plan.values

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        plan.header,
        Map.delete(values, first.key),
        bundles,
        expected
      )

    reversed =
      Map.update!(plan.header, "vector_pages", fn
        [only] -> [only, only]
        pages -> Enum.reverse(pages)
      end)

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        reversed,
        values,
        bundles,
        expected
      )

    mismatched = put_in(plan.header, ["vector_selection", "model"], "different-model")

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        mismatched,
        values,
        bundles,
        expected
      )

    [vector_ref | rest] = plan.header["vector_pages"]
    vector_page = Map.fetch!(values, vector_ref["key"])

    forged =
      update_in(vector_page, ["rows", Access.at(0), Access.at(2)], fn _ ->
        String.duplicate("0", 64)
      end)

    bytes = IO.iodata_to_binary(JSON.encode!(forged))
    sha = Evidence.sha256(bytes)
    key = "genvec.notes." <> sha

    forged_header =
      Map.put(plan.header, "vector_pages", [
        %{"key" => key, "sha256" => sha, "byte_count" => byte_size(bytes)} | rest
      ])

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        forged_header,
        Map.put(values, key, forged),
        bundles,
        expected
      )

    [fact_ref | rest] = plan.header["fact_pages"]
    fact_page = Map.fetch!(values, fact_ref["key"])

    forged =
      update_in(
        fact_page,
        ["rows", Access.at(0), Access.at(8), Access.at(0), Access.at(1)],
        &(&1 + 1)
      )

    bytes = IO.iodata_to_binary(JSON.encode!(forged))
    sha = Evidence.sha256(bytes)
    key = "genfact.notes." <> sha

    forged_header =
      Map.put(plan.header, "fact_pages", [
        %{"key" => key, "sha256" => sha, "byte_count" => byte_size(bytes)} | rest
      ])

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        forged_header,
        Map.put(values, key, forged),
        bundles,
        expected
      )

    [source_ref | source_tail] = plan.header["source_pages"]
    source_page = Map.fetch!(values, source_ref["key"])
    forged_source = put_in(source_page, ["rows", Access.at(0), "warning_count"], 999)
    bytes = IO.iodata_to_binary(JSON.encode!(forged_source))
    sha = Evidence.sha256(bytes)
    key = "gensrc.notes." <> sha

    forged_header =
      Map.put(plan.header, "source_pages", [
        %{"key" => key, "sha256" => sha, "byte_count" => byte_size(bytes)} | source_tail
      ])

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        forged_header,
        Map.put(values, key, forged_source),
        bundles,
        expected
      )

    changed_head = update_in(bundles, [Access.at(0), "head", "revision"], &(&1 + 1))

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        plan.header,
        values,
        changed_head,
        expected
      )

    {:error, _} =
      IpseKnowledge.Store.Collection.Generation.unpack_group(
        "notes",
        plan.header,
        values,
        Enum.reverse(bundles),
        expected
      )

    preview =
      %{
        "status" => "preview",
        "sources" => plan.header["sources"],
        "vectors" => plan.header["vectors"],
        "facts" => plan.header["facts"],
        "entities" => plan.header["entities"],
        "partial_sources" => plan.header["partial_sources"],
        "document_warnings" =>
          Enum.sum(
            Enum.map(bundles, fn b ->
              case Evidence.document_receipt(b["source"]) do
                nil -> 0
                receipt -> length(receipt["warnings"])
              end
            end)
          ),
        "document_citations" =>
          Enum.count(
            for(
              data <- supplied,
              fact <- data["facts"],
              citation <- fact["citations"],
              do: citation
            ),
            &is_map(&1["document"])
          ),
        "source_pages" => length(plan.header["source_pages"]),
        "vector_pages" => length(plan.header["vector_pages"]),
        "fact_pages" => length(plan.header["fact_pages"]),
        "leaf_values" => length(plan.values),
        "maximum_value_bytes" => Enum.max(Enum.map(plan.values, & &1.byte_count)),
        "header_bytes" => plan.header_unit.byte_count,
        "coverage" => snapshot["coverage"],
        "publication_attempted" => false,
        "noncanonical_fact_refused" => true,
        "population_qualified" => false
      }

    if state.args["directory"] do
      {:ok, summary} =
        IpseKnowledge.Store.Collection.Directory.capture("notes", plan, bundles, expected)

      ctx = %{
        summary: summary,
        preview: preview,
        native_generation: snapshot["native_generation"],
        pages: []
      }

      drive(
        Collection.start(
          %{"kind" => "collection", "scope" => "project", "partition" => "notes"},
          :value_read,
          %{"key" => "catalog.notes"}
        ),
        state |> Map.put(:directory, ctx) |> Map.put(:vector_phase, :directory_catalog)
      )
    else
      finish(preview, state)
    end
  end

  defp drive({:done, {:ok, result}}, %{mode: "vectors", vector_phase: :directory_catalog} = state) do
    true = result["native_generation"] === state.directory.native_generation
    catalog = result["record"]["value"]
    ctx = Map.put(state.directory, :catalog, catalog)
    directory_page(%{state | directory: ctx})
  end

  defp drive({:done, {:ok, result}}, %{mode: "vectors", vector_phase: :directory_page} = state) do
    true = result["native_generation"] === state.directory.native_generation
    ctx = Map.update!(state.directory, :pages, &(&1 ++ [result["record"]["value"]]))
    directory_page(%{state | directory: ctx})
  end

  defp drive({:done, {:ok, snapshot}}, %{mode: "vectors", vector_phase: :source} = state) do
    [source] = snapshot["sources"]
    {:ok, chunks} = Evidence.chunks(source)
    selection = vector_selection(state.args)

    vectors =
      for {chunk, ordinal} <- Enum.with_index(chunks) do
        {:ok, hash} = Ipse.Extension.canonical_digest([chunk["text"]])

        values =
          for index <- 1..selection["dimensions"],
              do: 1.0 + rem(index + ordinal + (state.args["salt"] || 0), 17) / 17

        {:ok, vector} =
          Evidence.vector(
            Map.merge(Map.delete(selection, "encoding"), %{
              "chunk_id" => chunk["chunk_id"],
              "input_sha256" => hash,
              "values" => values
            })
          )

        vector
      end

    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    drive(
      Collection.start(profile, :vector_store, %{
        "source_id" => state.args["source_id"],
        "selection" => selection,
        "vectors" => vectors,
        "expected_revision" => state.args["expected_revision"] || 0,
        "as_of_ms" => 20,
        "continuation" => state.args["continuation"]
      }),
      %{state | vector_phase: :store}
    )
  end

  defp drive(
         {:done, {:ok, %{"vectors" => vectors, "source" => source} = snapshot}},
         %{mode: "vectors"} = state
       ) do
    {:ok, chunks} = Evidence.chunks(source)
    [first | _] = chunks

    {:ok, citation} =
      Evidence.citation(
        source,
        first,
        first["start_byte"],
        min(first["end_byte"], first["start_byte"] + 32)
      )

    finish(
      %{
        "status" => "ok",
        "revision" => snapshot["revision"],
        "vectors" => length(vectors),
        "hashes" => Enum.map(vectors, & &1["vector_sha256"]),
        "dimensions" => hd(vectors)["dimensions"],
        "citation" => citation,
        "coverage" => snapshot["coverage"]
      },
      state
    )
  end

  defp drive({:done, {:ok, snapshot}}, %{mode: "query"} = state) do
    {:ok, rank} =
      Evidence.rank_lexical(snapshot["sources"], state.args["query"] || "Nocturne", 1, 20)

    rank = Evidence.query_scope(rank, snapshot["sources"], [], 20)

    coverage = rank["coverage"] |> Map.delete("complete") |> Map.merge(snapshot["coverage"])

    value =
      rank
      |> Map.put("scope", "explicit_selected_sources")
      |> Map.put("coverage", coverage)
      |> Map.put("catalog_generation", snapshot["catalog_generation"])

    finish(value, state)
  end

  defp drive({:done, {:ok, snapshot}}, %{mode: "lexical"} = state) do
    runs =
      Enum.map(snapshot["runs"], fn entry ->
        run = entry["run"]

        summary =
          run
          |> Map.delete("terms")
          |> Map.put("term_count", length(run["terms"]))
          |> Map.put(
            "sample",
            Enum.filter(run["terms"], &(hd(&1) in ~w(approval evidence index)))
          )

        Map.put(entry, "run", summary)
      end)

    finish(Map.put(snapshot, "runs", runs), state)
  end

  defp drive({:done, {:ok, value}}, state), do: finish(value, state)

  defp drive({:done, {:error, code, _}}, state),
    do: finish(%{"status" => "refused", "code" => Atom.to_string(code)}, state)

  defp drive({:stop, :unknown_effect}, state), do: finish(%{"status" => "unknown"}, state)

  defp finish(value, state) do
    {:ok, reply} = Ipse.Extension.ResultPublication.prepare(value)
    {:ok, reply, state}
  end

  defp directory_page(state) do
    ctx = state.directory

    case Enum.at(ctx.catalog["pages"], length(ctx.pages)) do
      nil ->
        profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

        {:ok, directory} =
          IpseKnowledge.Store.Collection.Directory.pack(
            profile,
            ctx.catalog,
            ctx.pages,
            [ctx.summary],
            1
          )

        expected =
          Map.take(
            directory.root,
            ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
          )
          |> Map.put("root_sha256", directory.root_unit.sha256)

        values =
          Map.new(directory.values, &{&1.key, &1.value})
          |> Map.put(ctx.summary["ref"]["key"], ctx.summary["header"])

        keys = Enum.map(ctx.summary["sources"], & &1["source_key"])

        {:ok, lookup} =
          IpseKnowledge.Store.Collection.Directory.lookup(
            directory.root,
            values,
            Enum.take(keys, 2),
            expected
          )

        {:ok, entities} =
          IpseKnowledge.Store.Collection.Directory.entity_rows(directory.root, values, expected)

        true = length(entities) == directory.root["entities"]

        true = length(lookup["groups"]) == 1 and lookup["missing_source_keys"] == []
        [manifest | _] = directory.root["manifests"]

        {:error, _} =
          IpseKnowledge.Store.Collection.Directory.lookup(
            directory.root,
            Map.delete(values, manifest["key"]),
            keys,
            expected
          )

        {:error, _} =
          IpseKnowledge.Store.Collection.Directory.lookup(
            directory.root,
            values,
            keys,
            Map.update!(expected, "floor", &(&1 + 1))
          )

        {:error, _} =
          IpseKnowledge.Store.Collection.Directory.lookup(
            directory.root,
            values,
            keys,
            Map.put(expected, "catalog_sha256", String.duplicate("0", 64))
          )

        altered = put_in(values, [ctx.summary["ref"]["key"], "partial_sources"], 0)
        # Plain sources may already have zero; use an always-different count.
        altered = put_in(altered, [ctx.summary["ref"]["key"], "partial_sources"], 999)

        {:error, _} =
          IpseKnowledge.Store.Collection.Directory.lookup(directory.root, altered, keys, expected)

        forged_pages =
          update_in(ctx.pages, [Access.at(0), "rows", Access.at(0), "head_sha256"], fn _ ->
            String.duplicate("0", 64)
          end)

        forged_catalog =
          put_in(
            ctx.catalog,
            ["pages", Access.at(0), "sha256"],
            Evidence.sha256(IO.iodata_to_binary(JSON.encode!(hd(forged_pages))))
          )

        {:error, _} =
          IpseKnowledge.Store.Collection.Directory.pack(
            profile,
            forged_catalog,
            forged_pages,
            [ctx.summary],
            1
          )

        finish(
          Map.merge(ctx.preview, %{
            "directory_groups" => directory.root["groups"],
            "directory_values" => length(directory.values),
            "directory_root_bytes" => directory.root_unit.byte_count,
            "directory_entities" => length(entities),
            "directory_lookup" => lookup["coverage"],
            "directory_publication_attempted" => false
          }),
          state
        )

      ref ->
        drive(
          Collection.start(
            %{"kind" => "collection", "scope" => "project", "partition" => "notes"},
            :value_read,
            %{"key" => ref["key"]}
          ),
          Map.put(state, :vector_phase, :directory_page)
        )
    end
  end

  defp vector_selection(args),
    do: %{
      "selection_sha256" => Evidence.sha256("fixture-vector-#{args["dimensions"] || 1024}"),
      "profile" => "fixture-vector",
      "model" => "fixture-float32",
      "dimensions" => args["dimensions"] || 1024,
      "encoding" => "float32le"
    }

  defp fact_selection(args),
    do: %{"kind" => args["kind"] || "explicit", "profile" => nil, "version" => 1}

  def source(generation, many, entries \\ 1600) do
    phrase =
      if generation == 1,
        do: "Nocturne migration needs review.",
        else: "Nocturne migration needs approval."

    paragraph = fn text -> "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" end

    body =
      if many do
        Enum.map_join(1..24, fn n ->
          paragraph.(if(n == 24, do: phrase, else: "Paragraph #{n} has exact résumé context."))
        end) <> "<w:p><w:r><w:sym w:char=\"F0FC\"/></w:r></w:p>"
      else
        paragraph.(Enum.map_join(1..entries, " ", &"entry#{&1}") <> " " <> phrase)
      end

    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"source.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ]
        |> Enum.map(fn {name, bytes} ->
          fixed = {{2000, 1, 1}, {0, 0, 0}}

          info =
            File.Stat.to_record(%File.Stat{
              size: byte_size(bytes),
              type: :regular,
              access: :read_write,
              atime: fixed,
              mtime: fixed,
              ctime: fixed,
              mode: 0o100644,
              links: 1,
              major_device: 0,
              minor_device: 0,
              inode: 0,
              uid: 0,
              gid: 0
            })

          {name, bytes, info}
        end),
        [:memory]
      )

    {:ok, extraction} = Documents.extract(bytes, "source.docx")
    {:ok, payload} = Documents.source_payload(extraction, 65_536)
    receipt = Evidence.document_storage_receipt!(payload["document"])

    attrs = %{
      "source_id" => "fixture:word",
      "partition" => "notes",
      "generation" => generation,
      "title" => "Synthetic Word source",
      "text" => payload["text"],
      "uri" => "provided:source.docx",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "documents",
        "partition_or_scope" => "notes",
        "receipt" => receipt,
        "historical" => false
      }
    }

    attrs =
      if receipt["version"] == 4, do: Map.put(attrs, "document", payload["document"]), else: attrs

    {:ok, source} = Evidence.source(attrs)
    source
  end

  defp tiny(id, generation, args) do
    {:ok, source} =
      Evidence.source(%{
        "source_id" => id,
        "partition" => "notes",
        "generation" => generation,
        "title" => "Catalog source",
        "text" => args["text"] || "Index evidence for #{id}.",
        "uri" => "provided:" <> id,
        "observed_at_ms" => args["observed_at_ms"] || 10,
        "event_at_ms" => nil,
        "expires_at_ms" => args["expires_at_ms"],
        "origin" => %{
          "kind" => "provided",
          "store_profile" => "documents",
          "partition_or_scope" => "notes",
          "receipt" => nil,
          "historical" => args["historical"] || false
        }
      })

    source
  end
end
