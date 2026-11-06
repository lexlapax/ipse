# Request-level preflight only. No native store, Session, inference or acquisition.
# Invoke with the frozen Root2 artifact/SDK; output paths must be new under _build.
{opts, [], []} =
  OptionParser.parse(System.argv(),
    strict: [
      artifact: :string,
      out: :string,
      sources: :integer,
      resume: :string,
      variant: :string,
      phase: :string,
      response: :string,
      action_id_start: :integer,
      public_results: :boolean
    ]
  )

artifact = Path.expand(Keyword.fetch!(opts, :artifact))
out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)
File.mkdir_p!(out)
manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))

for row <- manifest["files"] do
  bytes = File.read!(Path.join(artifact, row["path"]))
  true = byte_size(bytes) == row["bytes"]
  true = Ipse.JSON.sha256(bytes) == row["sha256"]
end

for path <- Path.wildcard(Path.join(artifact, "ebin/*.beam")),
    do: {:module, _} = :code.load_abs(String.to_charlist(Path.rootname(path)))

Code.require_file("collection_recipe_model.ex", __DIR__)

defmodule Ipse.CollectionRecipeLedger do
  alias IpseKnowledge.{Documents, Evidence}
  alias IpseKnowledge.Store.Collection, as: C
  alias Ipse.CollectionRecipeModel, as: M
  alias Ipse.JSON, as: J

  def run(count, out, opts) when count in 1..1000 do
    trace_write = Keyword.get(opts, :trace_write, &IO.binwrite/2)
    true = is_function(trace_write, 2)
    {:ok, ledger} = File.open(Path.join(out, "invocations.jsonl"), [:write, :exclusive])
    Process.put(:ledger, ledger)
    Process.put(:trace_write, trace_write)
    Process.put(:out, out)
    Process.put(:sequence, 0)
    Process.put(:variant, Keyword.get(opts, :variant, "initial"))
    Process.put(:phase, Keyword.get(opts, :phase, "build"))
    Process.put(:response, Keyword.get(opts, :response, "compact_v1"))
    Process.put(:retain_public_results, Keyword.get(opts, :public_results, false))
    Process.put(:embedding_pages, %{})
    Process.put(:embedding_calls, 0)

    Process.put(
      :controller_result_hook,
      Keyword.get(opts, :controller_result_hook, fn _section, result -> result end)
    )

    true = Process.get(:phase) in ~w(build finalize transport)
    true = Process.get(:response) in ~w(full compact_v1)

    Process.put(:totals, %{
      reads: 0,
      effects: 0,
      invocations: 0,
      minimum_action_journal_bytes: 0,
      action_events: 0,
      max_frame_bytes: 0
    })

    samples = Map.new([2097, 2096], &{&1, document(&1)})
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}

    configuration =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{
        "version" => 1,
        "stores" => %{"local" => profile},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{"learned" => %{"kind" => "embedding", "profile" => "encoder"}}
      })

    {:ok, resolved} = IpseKnowledge.Profiles.validate("corpus", "collection-dense", configuration)
    Process.put(:resolved, resolved)

    model =
      if checkpoint = Keyword.get(opts, :resume) do
        path = Path.expand(checkpoint)
        true = String.starts_with?(path, Path.expand("_build") <> "/")
        :erlang.binary_to_term(File.read!(path), [:safe])
      else
        M.new(%{}, 0)
      end

    false = Keyword.has_key?(opts, :action_id_start)
    publication_baseline = length(model.publications)

    source_result =
      Enum.reduce_while(
        if(Keyword.has_key?(opts, :resume), do: [], else: 0..(count - 1)),
        model,
        fn n, model ->
          payload = samples[if(n < 252, do: 2097, else: 2096)]
          receipt = Evidence.document_storage_receipt!(payload["document"])

          source = %{
            "source_id" => "fixture:recipe:" <> String.pad_leading(Integer.to_string(n), 4, "0"),
            "partition" => "notes",
            "generation" => 1,
            "title" => "Recipe ledger supplied synthetic document",
            "text" => payload["text"],
            "uri" => "provided:capacity.docx",
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

          source =
            if receipt["version"] == 4,
              do: Map.put(source, "document", payload["document"]),
              else: source

          args =
            Map.take(
              source,
              ~w(source_id generation title uri observed_at_ms event_at_ms expires_at_ms)
            )
            |> Map.merge(%{
              "expected_revision" => 0,
              "filename" => "capacity.docx",
              "bytes_base64" => Base.encode64(payload["original_bytes"])
            })

          {result, model} =
            public_loop(
              "source",
              %{"store" => "local", "action" => "put_document", "args" => args},
              model,
              "source",
              n
            )

          case result do
            {:ok, %{"status" => "ok"}} -> {:cont, model}
            other -> {:halt, {:stopped, other, model}}
          end
        end
      )

    case source_result do
      {:stopped, reason, _model} ->
        :ok = File.close(ledger)
        {:stopped, reason}

      model ->
        catalog = model.records["catalog.notes"].value
        expected_text = min(count, 252) * 20_979 + max(count - 252, 0) * 20_969
        true = catalog["sources"] == count and catalog["extracted_bytes"] == expected_text
        true = catalog["chunks"] == count * 10
        raw = snapshot(model)

        File.write!(
          Path.join(out, "source-summary.json"),
          json(%{totals: Process.get(:totals), store: raw}),
          [:exclusive]
        )

        {result, model} =
          if Process.get(:phase) in ~w(finalize transport),
            do: {"existing lexical selection retained", model},
            else:
              public_loop(
                "lexical_index",
                %{"store" => "local", "action" => "begin", "continuation" => nil},
                model,
                "public_lexical",
                0
              )

        if Process.get(:phase) !== "build" or match?({:ok, %{"status" => "ok"}}, result) do
          File.write!(
            Path.join(out, "lexical-model.term"),
            :erlang.term_to_binary(model, [:compressed]),
            [:exclusive]
          )

          File.write!(
            Path.join(out, "lexical-summary.json"),
            json(%{totals: Process.get(:totals), store: snapshot(model)}),
            [:exclusive]
          )

          {shared_result, model} =
            if Process.get(:phase) == "transport",
              do: {transport(profile, model), model},
              else: shared(profile, model)

          File.write!(
            Path.join(out, "final-model.term"),
            :erlang.term_to_binary(model, [:compressed]),
            [:exclusive]
          )

          summary = %{
            version: 1,
            kind: "public_controller_recipe_model",
            phase: Process.get(:phase),
            scope:
              if(Process.get(:phase) === "build",
                do:
                  "actual public Corpus controllers with modeled Native/embedding replies and production result codecs; not Native, provider or capacity qualification",
                else:
                  "legacy SDK-helper diagnostic with modeled replies; not a complete public controller or migration journey"
              ),
            resume: Keyword.get(opts, :resume),
            variant: Process.get(:variant),
            requested_response: Process.get(:response),
            public_response:
              if(Process.get(:phase) === "build", do: "compact_v1", else: Process.get(:response)),
            fresh_generation: 0,
            sources: count,
            extracted_bytes: expected_text,
            chunks: count * 10,
            raw_source: raw,
            lexical_result: terminal_summary(result),
            shared_result: terminal_summary(shared_result),
            final_store: snapshot(model),
            totals: Process.get(:totals),
            full_recipe_implemented: false,
            native_operations_executed: 0,
            session_journal_measured: false,
            journal_measurement:
              "strict lower bound of actual modeled action records: two request copies plus outcome JSON; excludes metadata, invocation/result/approval/SDK2 pages, messages and Session header",
            native_mutation_ids_modeled: map_size(model.operations),
            action_high_water_marks: model.peaks,
            result_publications:
              model.publications
              |> Enum.drop(publication_baseline)
              |> Enum.map(&Map.drop(&1, [:bytes])),
            model_embedding_calls: Process.get(:embedding_calls),
            capacity_fit: nil,
            full_session_journal_bytes: nil,
            blockers: [
              "fact inputs use bounded per-source publications and the actual assembly controller; each request retains the fixed frame limit",
              "full-target lifecycle/migration and physical/Session peak not executed by this model"
            ]
          }

          File.write!(Path.join(out, "summary.json"), json(summary), [:exclusive])
          :ok = File.close(ledger)
          IO.puts(json(summary))
        else
          :ok = File.close(ledger)
          {:stopped, result}
        end
    end
  end

  defp invocation(start, model, section, item) do
    {result, model} = M.run(start, M.reset(model))
    record_invocation(result, model, section, item)
  end

  defp public_invocation(command, arguments, model, section, item) do
    {result, model} =
      M.public(Process.get(:resolved), command, arguments, model, &embedding_reply/2)

    {result, model} = Process.get(:controller_result_hook).(section, {result, model})

    record_invocation(result, model, section, item)
  end

  defp record_invocation(result, model, section, item) do
    public =
      cond do
        match?({:blocked, _}, result) ->
          %{kind: "blocked", output_events: 0}

        section === "source" or String.starts_with?(section, "public_") ->
          List.last(model.public_results)

        true ->
          public_result_cost(result, section)
      end

    # Actions.result retains the complete intent, including request; an action
    # pair therefore necessarily contains this many JSON bytes before overhead.
    lower =
      Enum.zip(model.requests, model.outcomes)
      |> Enum.reduce(0, fn {r, o}, acc -> acc + 2 * byte_size(json(r)) + byte_size(json(o)) end)

    totals = Process.get(:totals)

    totals = %{
      totals
      | reads: totals.reads + model.reads,
        effects: totals.effects + model.effects,
        invocations: totals.invocations + 1,
        minimum_action_journal_bytes: totals.minimum_action_journal_bytes + lower,
        action_events: totals.action_events + 2 * length(model.requests),
        max_frame_bytes: max(totals.max_frame_bytes, Enum.max(model.frames, fn -> 0 end))
    }

    Process.put(:totals, totals)
    sequence = Process.get(:sequence) + 1
    Process.put(:sequence, sequence)

    requests =
      Enum.zip([model.requests, model.outcomes, model.action_ids])
      |> Enum.map(fn {request, outcome, action_id} ->
        r = request["request"] || request
        id = outcome["value"]["operation_id"]

        %{
          op: r["op"],
          key: r["key"],
          sha256: r["sha256"],
          byte_count: r["byte_count"],
          parts: if(is_list(r["data"]), do: Enum.map(r["data"], &byte_size/1)),
          offset: r["offset"],
          request_sha256: J.digest([request]),
          operation_id: id,
          action_id: action_id,
          outcome_status: outcome["status"],
          class:
            if(request["op"] === "collection.store",
              do: if(C.read_request?(request), do: "collection_read", else: "native_mutation"),
              else:
                if(request["op"] === "embedding.create",
                  do: "embedding_attempt",
                  else: "adapter_read"
                )
            ),
          native_receipt_modeled: is_binary(id) and Map.has_key?(model.operations, id),
          request_bytes: byte_size(json(request)),
          outcome_bytes: byte_size(json(outcome))
        }
      end)

    :ok =
      Process.get(:trace_write).(
        Process.get(:ledger),
        json(%{
          sequence: sequence,
          section: section,
          item: item,
          generation: model.generation,
          reads: model.reads,
          effects: model.effects,
          stage_count: map_size(model.stages),
          record_count: map_size(model.records),
          head_count: map_size(model.heads),
          peaks: model.peaks,
          unknown_requests: model.unknown,
          terminal_status:
            case result do
              {:blocked, _} -> "blocked"
              {:stop, _} -> "unknown"
              {:refused, _} -> "refused"
              _ -> "other"
            end,
          public_result: public,
          requests: requests
        }) <> "\n"
      )

    {result, M.reset(model)}
  end

  defp snapshot(model) do
    rows =
      model.records
      |> Enum.map(fn {key, row} ->
        %{
          key: key,
          revision: row.revision,
          logical_bytes: byte_size(json(row.value)),
          packed_bytes: M.packed_bytes(row.value),
          sha256: J.sha256(json(row.value))
        }
      end)

    %{
      generation: model.generation,
      records: length(rows),
      active_stages: map_size(model.stages),
      body_bytes: Enum.sum(Enum.map(rows, & &1.logical_bytes)),
      packed_bytes: Enum.sum(Enum.map(rows, & &1.packed_bytes)),
      allocation_4096_lower_bound:
        Enum.sum(Enum.map(rows, &(div(&1.packed_bytes + 4095, 4096) * 4096))),
      record_descriptors: Enum.sort_by(rows, & &1.key)
    }
  end

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))

  defp terminal_summary({:ok, value}), do: %{status: "modeled_known", value: value}

  defp terminal_summary({:blocked, reason}),
    do: %{status: "blocked", code: Atom.to_string(reason)}

  defp terminal_summary({:stop, reason}), do: %{status: "unknown", code: Atom.to_string(reason)}
  defp terminal_summary({:refused, value}), do: %{status: "refused", value: value}
  defp terminal_summary(value), do: value

  defp transport(profile, model) do
    rows =
      model.records
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, row} ->
        args = %{
          "key" => key,
          "value" => row.value,
          "expected_revision" => 0,
          "reuse" => false,
          "continuation" => nil
        }

        # A new isolated target for each value measures actual preparation frames;
        # migration acceptance is deliberately not fabricated as a public request.
        {{:done, {:ok, prepared}}, target} =
          M.run(C.start(profile, :value_prepare, args), M.new(%{}, 0))

        stage = target.stages[{prepared["stage"]["slot"], prepared["stage"]["epoch"]}]
        true = stage["state"] == "sealed" and stage["value"] === row.value
        body = json(row.value)

        lengths =
          Stream.unfold(body, fn
            "" -> nil
            rest -> Evidence.utf8_prefix(rest, 6144)
          end)
          |> Enum.map(&byte_size/1)

        %{
          key: key,
          body_sha256: J.sha256(body),
          body_bytes: byte_size(body),
          packed_bytes: M.packed_bytes(row.value),
          original_part_lengths: lengths,
          actual_prepare_mutations: target.effects,
          actual_prepare_reads: target.reads,
          modeled_start_generation: 0,
          modeled_final_generation: target.generation,
          max_frame_bytes: Enum.max(target.frames)
        }
      end)

    result = %{
      values: length(rows),
      actual_prepare_mutations: Enum.sum(Enum.map(rows, & &1.actual_prepare_mutations)),
      packed_bytes: Enum.sum(Enum.map(rows, & &1.packed_bytes)),
      max_frame_bytes: Enum.max(Enum.map(rows, & &1.max_frame_bytes)),
      semantic_note:
        "C.value_prepare/SDK/Core-validator costs over a fresh zero-based modeled target per value; this helper does not execute the implemented public backup/restore APIs or establish whole-migration cost",
      per_value: rows
    }

    File.write!(Path.join(Process.get(:out), "per-value-transport.json"), json(result), [
      :exclusive
    ])

    Map.drop(result, [:per_value])
  end

  defp shared(profile, model) do
    if Process.get(:phase) == "finalize" do
      job = model.records["genjob.notes"].value

      args = %{
        "action" => "inspect",
        "vector_selection" => job["vector_selection"],
        "fact_selection" => job["fact_selection"],
        "continuation" => nil,
        "group" => nil
      }

      {inspected, model} = job_loop(profile, args, model, "checkpoint_inspect", 0)

      final_loop(
        profile,
        %{args | "action" => "finalize_paged", "continuation" => inspected["continuation"]},
        model,
        0
      )
    else
      shared_build(profile, model)
    end
  end

  defp shared_build(_profile, model) do
    selection = %{
      "selection_sha256" => J.sha256("declared-fixture-encoder:" <> Process.get(:variant)),
      "profile" => "encoder",
      "model" => "fixture-model",
      "dimensions" => 1024,
      "encoding" => "float32le"
    }

    Process.put(:selection, selection)
    extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}

    begin_args = %{
      "store" => "local",
      "action" => "fact_input",
      "args" => %{
        "input" => %{
          "version" => 1,
          "mode" => "begin",
          "vector_selection" => selection,
          "fact_selection" => extraction,
          "continuation" => nil
        }
      }
    }

    {{:ok, begun}, model} = public_loop("source", begin_args, model, "public_begin", 0)
    token = begun["coverage"]["continuation"]
    count = model.records["catalog.notes"].value["sources"]

    {last, model} =
      captured_groups(model, count)
      |> Enum.with_index()
      |> Enum.reduce_while({token, model}, fn {ordinals, group}, {job, model} ->
        case publish_group(ordinals, model, group) do
          {{:blocked, :public_input_frame} = blocked, model} ->
            {:halt, {blocked, model}}

          {{:published, ref}, model} ->
            producer = %{
              "version" => 2,
              "action" => "page",
              "embedding" => "learned",
              "job_id" => job["id"],
              "job_revision" => job["job_revision"],
              "vector_selection" => selection,
              "fact_selection" => extraction,
              "vector_cursor" => 0,
              "previous_ready" => nil
            }

            {{:ok, _}, model} =
              public_loop(
                "generation_produce",
                Map.put(producer, "store", "local"),
                model,
                "public_page",
                group
              )

            append = %{
              "store" => "local",
              "action" => "fact_input",
              "result_input" => ref,
              "args" => %{
                "input" => %{
                  "version" => 1,
                  "mode" => "append",
                  "producer" => producer,
                  "continuation" => nil
                }
              }
            }

            case public_loop("source", append, model, "public_append", group) do
              {{:ok, value}, model} -> {:cont, {value["coverage"]["continuation"], model}}
              other -> {:halt, other}
            end

          other ->
            {:halt, other}
        end
      end)

    if is_map(last) do
      args = %{
        "store" => "local",
        "action" => "finalize_paged",
        "vector_selection" => selection,
        "fact_selection" => extraction,
        "continuation" => last,
        "response" => "compact_v1",
        "guard_sources" => true
      }

      public_loop("generation_job", args, model, "public_finalize", 0)
    else
      {last, model}
    end
  end

  defp publish_group(ordinals, model, group) do
    {refs, model} =
      Enum.reduce_while(ordinals, {[], model}, fn ordinal, {refs, model} ->
        case public_invocation(
               "source",
               fact_arguments([ordinal]),
               model,
               "public_fact_publish",
               ordinal
             ) do
          {{:published, ref}, model} -> {:cont, {refs ++ [ref], model}}
          {failure, model} -> {:halt, {failure, model}}
        end
      end)

    if is_list(refs) do
      args = %{
        "store" => "local",
        "action" => "fact_input",
        "data_inputs" => refs,
        "args" => %{"input" => %{"version" => 1, "mode" => "assemble"}}
      }

      public_invocation("source", args, model, "public_fact_assemble", group)
    else
      {refs, model}
    end
  end

  defp captured_groups(model, count) do
    # These are the rows emitted by the modeled public Source controller, in
    # exactly the catalog-page order subsequently captured by Progress.page.
    ordinals =
      Map.new(0..(count - 1), fn ordinal ->
        {J.sha256("fixture:recipe:" <> String.pad_leading(Integer.to_string(ordinal), 4, "0")),
         ordinal}
      end)

    groups =
      Enum.flat_map(model.records["catalog.notes"].value["pages"], fn ref ->
        page = Map.fetch!(model.records, ref["key"]).value
        true = J.sha256(json(page)) === ref["sha256"]
        Enum.map(page["rows"], &Map.fetch!(ordinals, &1["source_key"])) |> Enum.chunk_every(8)
      end)

    true = Enum.sort(List.flatten(groups)) === Enum.to_list(0..(count - 1))
    groups
  end

  defp fact_arguments(ordinals) do
    sources =
      Enum.map(ordinals, fn ordinal ->
        id = "fixture:recipe:" <> String.pad_leading(Integer.to_string(ordinal), 4, "0")

        rows =
          for n <- 0..19 do
            %{
              "subject" => id <> ":Entity#{rem(n, 5)}",
              "object" => id <> ":Entity#{rem(n + 1, 5)}",
              "predicate" =>
                "relation#{n}" <>
                  if(Process.get(:variant) === "initial", do: "", else: "-replacement"),
              "polarity" => "positive",
              "inferred" => false,
              "valid_from_ms" => nil,
              "valid_to_ms" => nil,
              "spans" => [[0, 0, 32]]
            }
          end

        %{"source_key" => J.sha256(id), "facts" => rows}
      end)

    %{
      "store" => "local",
      "action" => "fact_input",
      "args" => %{
        "input" => %{
          "version" => 1,
          "mode" => "publish",
          "value" => %{"version" => 1, "kind" => "explicit_fact_group", "sources" => sources}
        }
      }
    }
  end

  defp public_loop(command, args, model, section, item) do
    case public_invocation(command, args, model, section, item) do
      {{:ok, %{"continuation" => %{"id" => next, "arguments" => arguments}}}, model} ->
        public_loop(next, arguments, model, section, item)

      {{:ok, %{"status" => "refused"} = value}, model} ->
        {{:refused, value}, model}

      terminal ->
        terminal
    end
  end

  defp embedding_reply(%{"op" => "embedding.create"} = r, model) do
    id = Ipse.Usage.id()
    source = J.sha256("synthetic-embedding:" <> id)
    selection = Process.get(:selection)
    true = r["expected_selection_sha256"] === selection["selection_sha256"]
    base = if Process.get(:variant) === "initial", do: 1.0, else: 1.5
    bytes = for i <- 1..1024, into: <<>>, do: <<base + rem(i, 17) / 17::float-little-32>>

    pages =
      Enum.with_index(r["inputs"])
      |> Map.new(fn {text, index} ->
        {:ok, input} = Ipse.Extension.canonical_digest([text])
        {{id, index}, %{bytes: bytes, input: input, source: source}}
      end)

    Process.put(:embedding_pages, Map.merge(Process.get(:embedding_pages), pages))
    Process.put(:embedding_calls, Process.get(:embedding_calls) + 1)

    value = %{
      "version" => 2,
      "request_id" => id,
      "attempt_id" => id,
      "profile" => r["profile"],
      "reported_model" => selection["model"],
      "selection_sha256" => selection["selection_sha256"],
      "usage" => nil,
      "result" => %{
        "version" => 2,
        "operation_id" => id,
        "source_sha256" => source,
        "kind" => "embedding.f32le",
        "encoding" => "float32le.base64",
        "dimensions" => 1024,
        "vector_count" => length(r["inputs"])
      }
    }

    {%{"status" => "ok", "value" => value}, model}
  end

  defp embedding_reply(%{"op" => "effect.result.read"} = r, model) do
    page = Map.fetch!(Process.get(:embedding_pages), {r["operation_id"], r["vector_index"]})
    count = min(r["limit"], 1024 - r["offset"])
    last = r["offset"] + count === 1024

    value = %{
      "version" => 2,
      "operation_id" => r["operation_id"],
      "source_sha256" => page.source,
      "kind" => "embedding.f32le",
      "encoding" => "float32le.base64",
      "vector_index" => r["vector_index"],
      "dimensions" => 1024,
      "offset" => r["offset"],
      "complete" => last,
      "next" => if(last, do: nil, else: r["offset"] + count),
      "input_sha256" => page.input,
      "vector_sha256" => J.sha256(page.bytes),
      "values" => Base.encode64(binary_part(page.bytes, r["offset"] * 4, count * 4))
    }

    {%{"status" => "ok", "value" => value}, model}
  end

  defp job_loop(profile, args, model, section, n) do
    public_args = Map.put(Map.delete(args, "group"), "store", "local")

    public_args =
      if Process.get(:response) == "compact_v1",
        do: Map.put(public_args, "response", "compact_v1"),
        else: public_args

    Process.put(:public_job_args, public_args)
    {result, model} = invocation(C.start(profile, :generation_job, args), model, section, n)

    case result do
      {:done, {:continue, value}} ->
        job_loop(profile, %{args | "continuation" => value["continuation"]}, model, section, n)

      {:done, {:ok, value}} ->
        {value, model}

      other ->
        {inspect(other, limit: :infinity), model}
    end
  end

  defp public_result_cost(result, section)
       when section in ~w(shared_begin shared_finalize checkpoint_inspect) do
    args = Process.get(:public_job_args)
    true = is_map(args)

    present = fn value ->
      if Process.get(:response) == "compact_v1",
        do: IpseKnowledge.Store.Collection.Job.compact_result(value),
        else: value
    end

    {status, value, continuation} =
      case result do
        {:done, {:continue, value}} ->
          {"draft", Map.drop(present.(value), ["continuation"]),
           %{
             "id" => "generation_job",
             "arguments" => Map.put(args, "continuation", value["continuation"])
           }}

        {:done, {:ok, %{"status" => status} = value}}
        when status != "selected" and section == "shared_finalize" ->
          {"draft", Map.drop(present.(value), ["continuation"]),
           %{
             "id" => "generation_job",
             "arguments" => Map.put(args, "continuation", value["continuation"])
           }}

        {:done, {:ok, value}} ->
          {"ok", present.(value), nil}

        _ ->
          {"refused", %{}, nil}
      end

    output = %{
      "version" => 1,
      "status" => status,
      "evidence" => [],
      "claims" => [],
      "gaps" => [],
      "coverage" => value,
      "continuation" => continuation
    }

    if Process.get(:retain_public_results),
      do:
        File.write!(
          Path.join(Process.get(:out), "public-results.jsonl"),
          json(%{section: section, output: output}) <> "\n",
          [:append]
        )

    case Ipse.Extension.ResultPublication.prepare(output) do
      {:ok, %Ipse.Extension.ResultPublication.Output{} = encoded} ->
        %{
          kind: "sdk2_paged",
          document_bytes: encoded.byte_count,
          output_events: 2 + div(encoded.byte_count + 4095, 4096),
          pages: div(encoded.byte_count + 4095, 4096),
          source_slots: 1,
          scope:
            "actual ResultPublication encoding of the public Corpus result shape; not a Session append/admission"
        }

      {:ok, inline} ->
        %{
          kind: "inline",
          document_bytes: byte_size(json(output)),
          frame_bytes: byte_size(json(inline)),
          output_events: 0,
          source_slots: 0
        }

      {:error, reason} ->
        %{kind: "refused", reason: inspect(reason)}
    end
  end

  defp public_result_cost(_, _), do: nil

  defp final_loop(profile, args, model, n) do
    {v, model} = job_loop(profile, args, model, "shared_finalize", n)

    if is_map(v) and v["status"] != "selected",
      do: final_loop(profile, %{args | "continuation" => v["continuation"]}, model, n + 1),
      else: {v, model}
  end

  defp document(size) do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    body =
      Enum.map_join(1..10, fn _ ->
        "<w:p><w:r><w:t>" <> String.duplicate("a", size) <> "</w:t></w:r></w:p>"
      end)

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"capacity.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ],
        [:memory]
      )

    {:ok, extraction} = Documents.extract(bytes, "capacity.docx")
    {:ok, payload} = Documents.source_payload(extraction, 65536, 2)
    Map.put(payload, "original_bytes", bytes)
  end
end

case Ipse.CollectionRecipeLedger.run(Keyword.get(opts, :sources, 1000), out, opts) do
  :ok -> :ok
  {:stopped, reason} -> raise "controller stopped: #{inspect(reason)}"
end
