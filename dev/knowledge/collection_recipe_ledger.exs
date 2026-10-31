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
    {:ok, ledger} = File.open(Path.join(out, "invocations.jsonl"), [:write, :exclusive])
    Process.put(:ledger, ledger)
    Process.put(:out, out)
    Process.put(:sequence, 0)
    Process.put(:variant, Keyword.get(opts, :variant, "initial"))
    Process.put(:phase, Keyword.get(opts, :phase, "build"))
    Process.put(:response, Keyword.get(opts, :response, "full"))
    Process.put(:retain_public_results, Keyword.get(opts, :public_results, false))
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

    model =
      if checkpoint = Keyword.get(opts, :resume) do
        path = Path.expand(checkpoint)
        true = String.starts_with?(path, Path.expand("_build") <> "/")
        :erlang.binary_to_term(File.read!(path), [:safe])
      else
        M.new(%{}, 1000)
      end

    model =
      if first = Keyword.get(opts, :action_id_start) do
        true = first > model.action_sequence
        %{model | action_sequence: first}
      else
        model
      end

    model =
      Enum.reduce(if(Keyword.has_key?(opts, :resume), do: [], else: 0..(count - 1)), model, fn n,
                                                                                               model ->
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

        args = %{"source" => source, "expected_revision" => 0, "continuation" => nil}
        {_, model} = source_loop(profile, args, model, n)
        model
      end)

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
        else: index_loop(profile, %{"action" => "begin", "continuation" => nil}, model, 0)

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
      kind: "actual_client_recipe_preflight",
      scope:
        "actual raw/lexical/private supplied shared controller requests; not a public producer, acquisition, model or native capacity qualification",
      resume: Keyword.get(opts, :resume),
      variant: Process.get(:variant),
      public_response: Process.get(:response),
      fresh_action_id_start: Keyword.get(opts, :action_id_start),
      sources: count,
      extracted_bytes: expected_text,
      chunks: count * 10,
      raw_source: raw,
      lexical_result: result,
      shared_result: shared_result,
      final_store: snapshot(model),
      totals: Process.get(:totals),
      full_recipe_implemented: false,
      native_operations_executed: 0,
      session_journal_measured: false,
      journal_measurement:
        "strict lower bound of actual modeled action records: two request copies plus outcome JSON; excludes metadata, invocation/result/approval/SDK2 pages, messages and Session header",
      blockers: [
        "public bounded graph/vector group producer absent",
        "GC/export-layout/import/maintenance epoch paths proposed, not implemented",
        "actual Session journal/event capture and safe cross-Session builder handoff unqualified"
      ]
    }

    File.write!(Path.join(out, "summary.json"), json(summary), [:exclusive])
    File.close(ledger)
    IO.puts(json(summary))
  end

  defp source_loop(profile, args, model, n) do
    {result, model} = invocation(C.start(profile, :put, args), model, "source", n)

    case result do
      {:done, {:continue, value}} ->
        source_loop(profile, %{args | "continuation" => value["continuation"]}, model, n)

      {:done, {:ok, %{"status" => "stored"}}} ->
        {result, model}

      other ->
        raise "source recipe refused #{inspect(other)}"
    end
  end

  defp index_loop(profile, args, model, n) do
    {result, model} = invocation(C.start(profile, :lexical_build, args), model, "lexical", n)

    case result do
      {:done, {:continue, value}} ->
        index_loop(
          profile,
          %{"action" => "next", "continuation" => value["continuation"]},
          model,
          n + 1
        )

      {:done, {:ok, _}} ->
        {inspect(result, limit: :infinity), model}

      other ->
        {inspect(other, limit: :infinity), model}
    end
  end

  defp invocation(start, model, section, item) do
    {result, model} = M.run(start, M.reset(model))
    public = public_result_cost(result, section)
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
      Enum.zip(model.requests, model.outcomes)
      |> Enum.map(fn {request, outcome} ->
        r = request["request"]

        %{
          op: r["op"],
          key: r["key"],
          sha256: r["sha256"],
          byte_count: r["byte_count"],
          parts: if(is_list(r["data"]), do: Enum.map(r["data"], &byte_size/1)),
          offset: r["offset"],
          request_sha256: J.digest([request]),
          operation_id: outcome["value"]["operation_id"],
          request_bytes: byte_size(json(request)),
          outcome_bytes: byte_size(json(outcome))
        }
      end)

    IO.binwrite(
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
          M.run(C.start(profile, :value_prepare, args), M.new(%{}, 20_000))

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
          max_frame_bytes: Enum.max(target.frames),
          prepare_plus_proposed_accept_mutations: target.effects + 1
        }
      end)

    result = %{
      values: length(rows),
      actual_prepare_mutations: Enum.sum(Enum.map(rows, & &1.actual_prepare_mutations)),
      prepare_plus_proposed_accept_mutations:
        Enum.sum(Enum.map(rows, & &1.prepare_plus_proposed_accept_mutations)),
      packed_bytes: Enum.sum(Enum.map(rows, & &1.packed_bytes)),
      max_frame_bytes: Enum.max(Enum.map(rows, & &1.max_frame_bytes)),
      semantic_note:
        "actual C.value_prepare/SDK/Core-validator costs, one isolated target per value; missing physical-layout API and pending-map migration.accept are not implemented or dispatched",
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

  defp shared_build(profile, model) do
    selection = %{
      "selection_sha256" => J.sha256("synthetic-shape-1024:" <> Process.get(:variant)),
      "profile" => "provided-shape",
      "model" => "synthetic-capacity-shape",
      "dimensions" => 1024,
      "encoding" => "float32le"
    }

    extraction = %{"kind" => "explicit", "profile" => nil, "version" => 1}

    args = %{
      "action" => "begin",
      "vector_selection" => selection,
      "fact_selection" => extraction,
      "continuation" => nil,
      "group" => nil
    }

    {value, model} = job_loop(profile, args, model, "shared_begin", 0)

    if not is_map(value) do
      {value, model}
    else
      pages =
        model.records["catalog.notes"].value["pages"] |> Enum.map(&model.records[&1["key"]].value)

      {value, model} =
        pages
        |> Enum.flat_map(& &1["rows"])
        |> Enum.chunk_every(8)
        |> Enum.with_index()
        |> Enum.reduce_while({value, model}, fn {rows, n}, {previous, m} ->
          bundles =
            Enum.map(rows, fn row ->
              head = m.records["source.notes." <> row["source_key"]].value

              bytes =
                Enum.map_join(head["blocks"], fn ref ->
                  Enum.join(m.records[ref["key"]].value["pieces"])
                end)

              %{"source" => Jason.decode!(bytes), "head" => head}
            end)

          supplied = Enum.map(bundles, fn b -> supplied(b["source"], selection, extraction) end)

          {:ok, plan} =
            IpseKnowledge.Store.Collection.Generation.pack_group(
              "notes",
              n * 8,
              bundles,
              supplied,
              selection,
              extraction
            )

          group = %{
            "plan" => plan,
            "bundles" => bundles,
            "catalog_page" => Enum.at(pages, div(n, 2))
          }

          next = %{
            args
            | "action" => "append",
              "continuation" => previous["continuation"],
              "group" => group
          }

          {v, m} = job_loop(profile, next, m, "shared_append", n)
          if is_map(v), do: {:cont, {v, m}}, else: {:halt, {v, m}}
        end)

      File.write!(
        Path.join(Process.get(:out), "shared-appended-model.term"),
        :erlang.term_to_binary(model, [:compressed]),
        [:exclusive]
      )

      if is_map(value) do
        finalize = %{args | "action" => "finalize_paged", "continuation" => value["continuation"]}
        {v, m} = final_loop(profile, finalize, model, 0)
        {if(is_map(v), do: Map.drop(v, ["job", "continuation"]), else: v), m}
      else
        {value, model}
      end
    end
  end

  defp supplied(source, selection, extraction) do
    {:ok, chunks} = Evidence.chunks(source)

    vectors =
      Enum.with_index(chunks)
      |> Enum.map(fn {chunk, n} ->
        {:ok, input} = Ipse.Extension.canonical_digest([chunk["text"]])

        {:ok, v} =
          Evidence.vector(
            Map.merge(Map.delete(selection, "encoding"), %{
              "chunk_id" => chunk["chunk_id"],
              "input_sha256" => input,
              "values" =>
                for(
                  i <- 1..1024,
                  do:
                    if(Process.get(:variant) == "initial", do: 1.0, else: 1.5) +
                      rem(i + n, 17) / 17
                )
            })
          )

        v
      end)

    [first | _] = chunks

    {:ok, citation} =
      Evidence.citation(source, first, first["start_byte"], first["start_byte"] + 32)

    facts =
      for n <- 0..19 do
        {:ok, f} =
          Evidence.fact(%{
            "subject" => source["source_id"] <> ":Entity#{rem(n, 5)}",
            "object" => source["source_id"] <> ":Entity#{rem(n + 1, 5)}",
            "predicate" =>
              "relation#{n}" <>
                if(Process.get(:variant) == "initial", do: "", else: "-replacement"),
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => nil,
            "valid_to_ms" => nil,
            "extraction" => extraction,
            "citations" => [citation]
          })

        f
      end

    %{
      "source_key" => source["source_key"],
      "source_bundle_sha256" => J.sha256(json(source)),
      "vectors" => vectors,
      "facts" => facts
    }
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
    payload
  end
end

Ipse.CollectionRecipeLedger.run(Keyword.get(opts, :sources, 1000), out, opts)
