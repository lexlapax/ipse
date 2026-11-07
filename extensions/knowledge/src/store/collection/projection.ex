defmodule IpseKnowledge.Store.Collection.Projection do
  @moduledoc """
  Source-bound packed vectors and cited facts behind the existing Collection grant.

  Callers supply projections inside the extension; this adapter adds neither
  model inference nor a host capability. One explicit continuation prepares one
  value. Complete hydration is private; public callers return bounded results.
  """
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Paged
  @recipe "ipse.evidence.float32le.base64.v1"
  @fact_recipe "ipse.evidence.fact_spans.v1"
  @selection ~w(selection_sha256 profile model dimensions encoding)
  @token ~w(version plan_sha256 catalog_revision root_revision unit stages write)
  @progress_token @token ++ ~w(maintenance_epoch progress)
  @progress_fields ~w(version status head_id revision unit maintenance_epoch retirement_epoch slots active prepared plan_sha256 body_sha256 unit_limit kind)
  @page_bytes 48 * 1024
  # A retained slot also carries the bounded manifest and binding metadata.
  @fact_input_page_bytes 7_000
  @fact_input_pages 8

  @doc """
  Validate a complete bounded historical document set without changing its bytes.

  Native provenance and operator-selected input leases belong to the Host. This
  predicate independently checks the packed envelopes, then resolves every
  supported semantic reference inside this set. Missing, unknown or unfinished
  data refuses the entire set; it is never silently omitted or adopted as work.
  """
  def completed_backup?(profile, records), do: completed_backup?(profile, records, 0)

  def completed_backup?(profile, records, source_epoch) do
    with true <- E.safe_uint?(source_epoch),
         true <-
           exact?(profile, ~w(kind scope partition)) and
             profile["kind"] === "collection" and profile["scope"] === "project" and
             is_binary(profile["partition"]) and
             Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, profile["partition"]),
         true <- is_list(records) and length(records) <= 32,
         rows <- Enum.map(records, &backup_row!/1),
         true <- length(Enum.uniq_by(rows, & &1["key"])) === length(rows),
         by_key = Map.new(rows, &{&1["key"], &1}),
         true <- Enum.all?(rows, &(not String.starts_with?(&1["key"], "host."))),
         true <- backup_epochs?(profile, by_key, source_epoch) do
      if rows === [] do
        true
      else
        values = Map.new(rows, &{&1["key"], &1["value"]})
        {catalog, current, bundles, used} = backup_sources!(profile, by_key)
        used = backup_lexical!(profile, by_key, values, catalog, current, bundles, used)
        used = backup_projections!(profile, by_key, bundles, catalog, used)
        used = backup_shared!(profile, by_key, values, catalog, current, bundles, used)
        used = backup_producers!(profile, by_key, catalog, current, used)
        MapSet.new(Map.keys(by_key)) === used
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp backup_epochs?(profile, rows, source_epoch) do
    alias IpseKnowledge.Store.Collection.{Index, Job}

    Enum.all?(rows, fn {_, row} ->
      value = row["value"]

      epoch =
        case value["kind"] do
          "shared_generation_job" ->
            Job.validated_epoch(value, profile)

          "lexical_job" ->
            Index.validated_epoch(value, profile)

          "shared_projection_producer" ->
            case rows["genjob." <> profile["partition"]] do
              %{"value" => job} -> Job.validated_epoch(job, profile)
              _ -> :missing_job
            end

          _ ->
            {:ok, 0}
        end

      case epoch do
        {:ok, bound} -> bound <= source_epoch
        _ -> false
      end
    end)
  end

  defp backup_row!(row) do
    true = exact?(row, ~w(key revision operation_id sha256 bytes value))

    true =
      is_binary(row["key"]) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, row["key"])

    true =
      E.safe_positive?(row["revision"]) and is_binary(row["operation_id"]) and
        Regex.match?(~r/\A[0-9a-f]{32}\z/, row["operation_id"])

    packed = row["value"]

    true =
      exact?(packed, ~w(version kind sha256 byte_count parts)) and
        packed["version"] === 1 and packed["kind"] === "document_value"

    true =
      is_list(packed["parts"]) and length(packed["parts"]) in 1..10 and
        Enum.all?(
          packed["parts"],
          &(is_binary(&1) and String.valid?(&1) and byte_size(&1) in 1..6144)
        )

    body = IO.iodata_to_binary(packed["parts"])

    true =
      byte_size(body) in 2..61_440 and byte_size(body) === packed["byte_count"] and
        E.sha256(body) === packed["sha256"]

    {:ok, physical} = Ipse.Extension.ResultDocument.encode(packed, %{"type" => "object"})
    true = byte_size(physical) === row["bytes"] and E.sha256(physical) === row["sha256"]
    {:ok, value} = Ipse.JSON.decode_unique(body)
    true = is_map(value) and json(value) === body

    %{
      "key" => row["key"],
      "revision" => row["revision"],
      "sha256" => packed["sha256"],
      "byte_count" => byte_size(body),
      "value" => value
    }
  end

  defp backup_ref!(by_key, ref) do
    true = exact?(ref, ~w(key sha256)) or exact?(ref, ~w(key sha256 byte_count))
    row = Map.fetch!(by_key, ref["key"])

    true =
      row["sha256"] === ref["sha256"] and
        (not Map.has_key?(ref, "byte_count") or row["byte_count"] === ref["byte_count"])

    row
  end

  defp backup_immutable!(profile, row, prefix) do
    true = row["key"] === prefix <> "." <> profile["partition"] <> "." <> row["sha256"]
    row["value"]
  end

  defp backup_pieces!(values) do
    Enum.map_join(values, fn value ->
      parts = value["pieces"]

      true =
        is_list(parts) and length(parts) in 1..12 and
          Enum.all?(parts, &(is_binary(&1) and String.valid?(&1) and byte_size(&1) <= 4096))

      Enum.join(parts)
    end)
  end

  defp backup_head!(profile, by_key, head) do
    true = C.valid_source_head?(head, head["source_key"])
    blocks = Enum.map(head["blocks"], &backup_ref!(by_key, &1))

    Enum.with_index(blocks)
    |> Enum.each(fn {row, n} ->
      value = backup_immutable!(profile, row, "data")

      true =
        (exact?(value, ~w(version kind pieces)) and value["version"] === 1) or
          (exact?(value, ~w(version kind pieces bundle_sha256 ordinal)) and value["version"] === 2 and
             value["bundle_sha256"] === head["bundle_sha256"] and value["ordinal"] === n)

      true = value["kind"] === "source_data"
    end)

    bytes = backup_pieces!(Enum.map(blocks, & &1["value"]))
    true = byte_size(bytes) === head["byte_count"] and E.sha256(bytes) === head["bundle_sha256"]
    {:ok, source} = Ipse.JSON.decode_unique(bytes)

    true =
      E.valid_source?(source) and source["partition"] === profile["partition"] and
        source["source_key"] === head["source_key"] and
        source["generation"] === head["generation"] and
        byte_size(source["text"]) === head["text_bytes"]

    {:ok, chunks} = E.chunks(source)
    true = length(chunks) === head["chunks"]
    {source, used} = {source, Enum.map(blocks, & &1["key"])}

    if head["version"] === 2 do
      manifest = head["lexical"]
      lexical = Enum.map(manifest["blocks"], &backup_ref!(by_key, &1))

      Enum.with_index(lexical)
      |> Enum.each(fn {row, n} ->
        value = backup_immutable!(profile, row, "data")

        true =
          exact?(value, ~w(version kind pieces bundle_sha256 ordinal source_bundle_sha256)) and
            value["version"] === 1 and value["kind"] === "source_lexical" and
            value["source_bundle_sha256"] === head["bundle_sha256"] and
            value["bundle_sha256"] === manifest["bundle_sha256"] and value["ordinal"] === n
      end)

      bytes = backup_pieces!(Enum.map(lexical, & &1["value"]))
      {:ok, expected} = E.lexical_run(source)

      true =
        bytes === json(expected) and byte_size(bytes) === manifest["byte_count"] and
          E.sha256(bytes) === manifest["bundle_sha256"] and
          manifest["content_sha256"] === source["content_sha256"]

      {%{"source" => source, "head" => head}, used ++ Enum.map(lexical, & &1["key"])}
    else
      {%{"source" => source, "head" => head}, used}
    end
  end

  defp backup_sources!(profile, rows) do
    catalog_key = "catalog." <> profile["partition"]
    catalog = Map.fetch!(rows, catalog_key)
    true = C.valid_catalog?(catalog["value"], profile)

    pages =
      Enum.with_index(catalog["value"]["pages"])
      |> Enum.map(fn {ref, n} ->
        row = backup_ref!(rows, ref)
        true = C.valid_catalog_page?(row, ref, n, profile)
        {row, n}
      end)

    entries =
      Enum.flat_map(pages, fn {page, n} ->
        Enum.map(page["value"]["rows"], &{&1, n})
      end)

    true =
      length(entries) === catalog["value"]["sources"] and
        length(Enum.uniq_by(entries, fn {entry, _} -> entry["source_key"] end)) ===
          length(entries)

    {current, used} =
      Enum.map_reduce(
        entries,
        [catalog_key | Enum.map(pages, fn {r, _} -> r["key"] end)],
        fn {entry, page}, used ->
          key = "source." <> profile["partition"] <> "." <> entry["source_key"]
          row = Map.fetch!(rows, key)

          true =
            row["sha256"] === entry["head_sha256"] and
              row["value"]["source_key"] === entry["source_key"] and
              div(row["value"]["ordinal"], 16) === page

          {bundle, refs} = backup_head!(profile, rows, row["value"])
          {bundle, [key | refs ++ used]}
        end
      )

    true =
      Enum.sort(Enum.map(current, & &1["head"]["ordinal"])) ===
        if(current === [], do: [], else: Enum.to_list(0..(length(current) - 1)))

    true =
      Enum.sum(Enum.map(current, &byte_size(&1["source"]["text"]))) ===
        catalog["value"]["extracted_bytes"] and
        Enum.sum(Enum.map(current, & &1["head"]["chunks"])) === catalog["value"]["chunks"]

    bundles = Map.new(current, &{E.sha256(json(&1["source"])), &1})
    {bundles, used} = backup_historical_sources!(profile, rows, bundles, MapSet.new(used))
    {catalog, current, bundles, used}
  end

  defp backup_historical_sources!(profile, rows, bundles, used) do
    groups =
      rows
      |> Map.values()
      |> Enum.filter(&(&1["value"]["kind"] === "source_data" and &1["value"]["version"] === 2))
      |> Enum.group_by(& &1["value"]["bundle_sha256"])

    {bundles, used} =
      Enum.reduce(groups, {bundles, used}, fn {hash, group}, {bundles, used} ->
        true = E.sha256?(hash)
        group = Enum.sort_by(group, & &1["value"]["ordinal"])

        Enum.with_index(group)
        |> Enum.each(fn {row, n} ->
          value = backup_immutable!(profile, row, "data")

          true =
            exact?(value, ~w(version kind pieces bundle_sha256 ordinal)) and
              value["ordinal"] === n
        end)

        bytes = backup_pieces!(Enum.map(group, & &1["value"]))
        {:ok, source} = Ipse.JSON.decode_unique(bytes)

        true =
          E.sha256(bytes) === hash and E.valid_source?(source) and
            source["partition"] === profile["partition"] and bytes === json(source)

        {Map.put_new(bundles, hash, %{"source" => source, "head" => nil}),
         Enum.reduce(group, used, &MapSet.put(&2, &1["key"]))}
      end)

    groups =
      rows
      |> Map.values()
      |> Enum.filter(&(&1["value"]["kind"] === "source_lexical"))
      |> Enum.group_by(& &1["value"]["bundle_sha256"])

    used =
      Enum.reduce(groups, used, fn {hash, group}, used ->
        group = Enum.sort_by(group, & &1["value"]["ordinal"])
        [first | _] = group
        source_hash = first["value"]["source_bundle_sha256"]
        source = Map.fetch!(bundles, source_hash)["source"]

        Enum.with_index(group)
        |> Enum.each(fn {row, n} ->
          value = backup_immutable!(profile, row, "data")

          true =
            exact?(value, ~w(version kind pieces bundle_sha256 ordinal source_bundle_sha256)) and
              value["version"] === 1 and value["ordinal"] === n and
              value["source_bundle_sha256"] === source_hash
        end)

        bytes = backup_pieces!(Enum.map(group, & &1["value"]))
        {:ok, expected} = E.lexical_run(source)
        true = bytes === json(expected) and E.sha256(bytes) === hash
        Enum.reduce(group, used, &MapSet.put(&2, &1["key"]))
      end)

    {bundles, used}
  end

  defp backup_lexical!(profile, rows, values, catalog, current, bundles, used) do
    alias IpseKnowledge.Store.Collection.Index

    used =
      rows
      |> Map.values()
      |> Enum.filter(&(&1["value"]["kind"] === "lexical_run_index"))
      |> Enum.reduce(used, fn row, used ->
        header = backup_immutable!(profile, row, "lexr")

        sources =
          Enum.map(header["sources"], fn summary ->
            Map.fetch!(bundles, Enum.at(summary, 4))["source"]
          end)

        entries =
          Enum.zip(sources, header["sources"])
          |> Enum.map(fn {source, summary} ->
            {:ok, run} = E.lexical_run(source)

            %{
              "run" => run,
              "source_bundle_sha256" => E.sha256(json(source)),
              "source_revision" => Enum.at(summary, 5)
            }
          end)

        {:ok, plan} = Index.storage_plan(profile, sources, entries, header["cursor"])

        true =
          plan.header["key"] === row["key"] and
            Enum.all?(plan.values, fn unit -> Map.fetch!(values, unit.key) === unit.value end)

        Enum.reduce(plan.values, used, &MapSet.put(&2, &1.key))
      end)

    key = "lexical." <> profile["partition"]
    job_key = "lexjob." <> profile["partition"]
    root_row = rows[key]
    root = root_row && root_row["value"]

    used =
      if root do
        true =
          root["catalog_sha256"] === catalog["sha256"] and
            root["catalog_generation"] === catalog["value"]["generation"] and
            root["floor"] === catalog["value"]["floor"]

        ordered = Enum.sort_by(current, & &1["head"]["ordinal"])
        groups = Enum.map(root["groups"], fn ref -> {ref, backup_ref!(rows, ref)["value"]} end)
        true = Index.completed_backup?(profile, root, groups, ordered, values)

        keys =
          Enum.flat_map(groups, fn {ref, header} ->
            [
              ref["key"]
              | Enum.map(header["packs"], fn [hash, _, _] ->
                  "lexp." <> profile["partition"] <> "." <> hash
                end)
            ]
          end)

        Enum.reduce([key | keys], used, &MapSet.put(&2, &1))
      else
        used
      end

    if job = rows[job_key] do
      true = Index.completed_job?(job["value"], root, profile)

      Enum.each(job["value"]["groups"], fn ref ->
        true = backup_ref!(rows, ref)["value"]["kind"] === "lexical_run_index"
      end)

      MapSet.put(used, job_key)
    else
      used
    end
  end

  defp backup_projections!(profile, rows, bundles, catalog, used) do
    rows
    |> Map.values()
    |> Enum.filter(&(&1["value"]["kind"] in ~w(vector_projection fact_projection)))
    |> Enum.reduce(used, fn row, used ->
      root = row["value"]
      bundle = Map.fetch!(bundles, root["source_bundle_sha256"])
      source = bundle["source"]
      kind = if root["kind"] === "fact_projection", do: :facts, else: :vectors
      state = %{item_kind: kind, profile: profile, source: source}
      prefix = if kind === :facts, do: "facts.", else: "vector."
      true = row["key"] === prefix <> profile["partition"] <> "." <> source["source_key"]

      true =
        root?(root, state) and root["source_generation"] === source["generation"] and
          Map.fetch!(rows, "source." <> profile["partition"] <> "." <> root["source_key"])[
            "value"
          ]["bundle_sha256"] === root["source_bundle_sha256"] and
          root["content_sha256"] === source["content_sha256"] and
          root["catalog_sha256"] === catalog["sha256"] and
          root["catalog_generation"] === catalog["value"]["generation"] and
          root["floor"] === catalog["value"]["floor"]

      pages =
        Enum.map(root["pages"], fn ref ->
          page = backup_ref!(rows, ref)
          backup_immutable!(profile, page, if(kind === :facts, do: "factp", else: "vecp"))
        end)

      {:ok, items} =
        if kind === :facts,
          do: selected_facts(source, pages, root["selection"], root),
          else: unpack(source, pages, root["selection"])

      true = length(items) === root[item_field(state)]
      Enum.reduce([row["key"] | Enum.map(root["pages"], & &1["key"])], used, &MapSet.put(&2, &1))
    end)
  end

  defp backup_shared!(profile, rows, values, catalog, current, bundles, used) do
    alias IpseKnowledge.Store.Collection.{Directory, Finalization, Generation, Job}

    headers =
      rows |> Map.values() |> Enum.filter(&(&1["value"]["kind"] === "shared_projection_group"))

    {summaries, used} =
      Enum.map_reduce(headers, used, fn row, used ->
        header = backup_immutable!(profile, row, "gengrp")
        refs = header["source_pages"] ++ header["vector_pages"] ++ header["fact_pages"]
        Enum.each(refs, &backup_ref!(rows, &1))

        source_rows =
          Enum.flat_map(header["source_pages"], &Map.fetch!(values, &1["key"])["rows"])

        captured =
          Enum.map(source_rows, fn source_row ->
            head = source_row["head"]
            {bundle, _} = backup_head!(profile, rows, head)
            true = Map.has_key?(bundles, head["bundle_sha256"])
            bundle
          end)

        {:ok, data} =
          Generation.unpack_group(
            profile["partition"],
            header,
            values,
            captured,
            Map.take(header, ~w(cursor vector_selection fact_selection))
          )

        {:ok, plan} =
          Generation.pack_group(
            profile["partition"],
            header["cursor"],
            captured,
            data,
            header["vector_selection"],
            header["fact_selection"]
          )

        {:ok, summary} =
          Directory.capture(
            profile["partition"],
            plan,
            captured,
            Map.take(header, ~w(cursor vector_selection fact_selection))
          )

        true = summary["ref"]["key"] === row["key"]

        {summary,
         Enum.reduce([row["key"] | Enum.map(refs, & &1["key"])], used, &MapSet.put(&2, &1))}
      end)

    root_key = "generation." <> profile["partition"]
    root_row = rows[root_key]

    used =
      if root_row do
        root = root_row["value"]

        expected =
          Map.take(
            root,
            ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
          )
          |> Map.put("root_sha256", root_row["sha256"])

        true =
          Directory.valid_root?(root, expected) and root["catalog_sha256"] === catalog["sha256"] and
            root["catalog_generation"] === catalog["value"]["generation"] and
            root["floor"] === catalog["value"]["floor"]

        ordered = Enum.sort_by(current, & &1["head"]["ordinal"])

        groups =
          Enum.chunk_every(ordered, 8)
          |> Enum.flat_map(fn bs ->
            {:ok, result} =
              Directory.lookup(root, values, Enum.map(bs, & &1["source"]["source_key"]), expected)

            true = result["missing_source_keys"] === []
            result["groups"]
          end)
          |> Enum.uniq_by(& &1["header"]["key"])

        selected =
          Enum.map(groups, fn group -> Enum.find(summaries, &(&1["ref"] === group["header"])) end)

        true = length(selected) === root["groups"] and Enum.all?(selected, &is_map/1)

        true =
          Enum.flat_map(selected, & &1["sources"])
          |> Enum.map(&Map.take(&1, ~w(source_key head_sha256))) ===
            Enum.map(ordered, fn b ->
              %{
                "source_key" => b["source"]["source_key"],
                "head_sha256" => E.sha256(json(b["head"]))
              }
            end)

        true =
          root["sources"] === catalog["value"]["sources"] and
            root["extracted_bytes"] === catalog["value"]["extracted_bytes"] and
            root["chunks"] === catalog["value"]["chunks"] and root["vectors"] === root["chunks"] and
            root["facts"] === Enum.sum(Enum.map(selected, & &1["header"]["facts"]))

        entity_rows =
          selected
          |> Enum.with_index()
          |> Enum.flat_map(fn {summary, n} ->
            Enum.map(summary["entities"], fn [id, label] -> [id, label, n] end)
          end)
          |> Enum.group_by(&hd/1)
          |> Enum.map(fn {id, entries} ->
            [label] = Enum.map(entries, &Enum.at(&1, 1)) |> Enum.uniq()
            [id, label, Enum.map(entries, &List.last/1) |> Enum.uniq() |> Enum.sort()]
          end)
          |> Enum.sort_by(&hd/1)

        {:ok, actual_entities} = Directory.entity_rows(root, values, expected)
        true = actual_entities === entity_rows and root["entities"] === length(entity_rows)
        used = backup_reductions!(profile, rows, catalog["value"], selected, used)

        Enum.reduce(
          [root_key | Enum.map(root["manifests"] ++ root["entity_pages"], & &1["key"])],
          used,
          &MapSet.put(&2, &1)
        )
      else
        used
      end

    job_key = "genjob." <> profile["partition"]

    if job_row = rows[job_key] do
      job = job_row["value"]
      true = Job.valid?(job, profile) and job["status"] in ~w(aborted selected)

      Enum.each(job["summaries"], fn ref ->
        true =
          backup_ref!(rows, ref)["value"]["kind"] === "shared_projection_group" and
            Enum.any?(summaries, &(&1["ref"] === ref))
      end)

      if job["status"] === "selected" do
        true =
          is_map(root_row) and job["catalog"] === catalog["value"] and
            root_row["value"]["generation"] === job["generation"] and
            root_row["value"]["vector_selection"] === job["vector_selection"] and
            root_row["value"]["fact_selection"] === job["fact_selection"]

        if job["version"] in [1, 4] do
          true =
            root_row["value"]["version"] === 1 and
              job["cursor"] === job["catalog"]["sources"] and
              job["facts"] === root_row["value"]["facts"] and
              job["summaries"] ===
                root_row["value"]["manifests"]
                |> Enum.flat_map(fn ref ->
                  Map.fetch!(values, ref["key"])["rows"] |> Enum.map(& &1["header"])
                end)
        else
          {:ok, expected} = Finalization.selected_root(job)
          true = root_row["value"] === expected
        end
      end

      MapSet.put(used, job_key)
    else
      used
    end
  end

  defp backup_reductions!(profile, rows, catalog, summaries, used) do
    alias IpseKnowledge.Store.Collection.{Directory, Paged, Reduction}

    pages =
      catalog["pages"]
      |> Enum.with_index()
      |> Map.new(fn {ref, n} ->
        {n, backup_ref!(rows, ref)["value"]}
      end)

    [first | _] = summaries
    vector = first["header"]["vector_selection"]
    fact = first["header"]["fact_selection"]

    Enum.reduce([Reduction, Paged], used, fn codec, used ->
      batches =
        summaries
        |> Enum.chunk_every(16)
        |> Enum.with_index()
        |> Enum.map(fn {batch, n} ->
          {:ok, plan} = codec.batch(profile, catalog, batch, pages, n, vector, fact)
          plan
        end)

      units = Enum.flat_map(batches, & &1.values)
      values = Map.new(units, &{&1.key, &1.value})
      runs = Enum.map(batches, &Directory.reference(&1.run))

      merged =
        backup_merge_units!(
          codec,
          profile["partition"],
          runs,
          List.duplicate(0, length(runs)),
          values,
          0,
          length(summaries)
        )

      Enum.reduce(units ++ merged, used, fn unit, used ->
        if row = rows[unit.key] do
          true = row["value"] === unit.value
          MapSet.put(used, unit.key)
        else
          used
        end
      end)
    end)
  end

  defp backup_merge_units!(codec, partition, runs, positions, values, n, groups) do
    true = n <= 157

    {:ok, result} =
      if codec === Paged,
        do: Paged.merge(partition, runs, positions, values, n, groups),
        else:
          IpseKnowledge.Store.Collection.Reduction.merge(partition, runs, positions, values, n)

    units = if is_nil(result.unit), do: [], else: [result.unit]

    if result.complete,
      do: units,
      else:
        units ++
          backup_merge_units!(codec, partition, runs, result.positions, values, n + 1, groups)
  end

  defp backup_producers!(profile, rows, catalog, current, used) do
    alias IpseKnowledge.Store.Collection.{Generation, Job, Producer}
    ordered = Enum.sort_by(current, & &1["head"]["ordinal"])

    rows
    |> Map.values()
    |> Enum.filter(&(&1["value"]["kind"] === "shared_projection_producer"))
    |> Enum.reduce(used, fn row, used ->
      record = row["value"]
      job_row = Map.fetch!(rows, "genjob." <> profile["partition"])
      job = job_row["value"]

      true =
        Job.valid?(job, profile) and job["status"] in ~w(aborted selected) and
          record["status"] === "ready" and record["partition"] === profile["partition"] and
          record["job_id"] === job["id"] and record["job_revision"] <= job_row["revision"] and
          record["catalog_sha256"] === catalog["sha256"] and
          record["catalog_floor"] === catalog["value"]["floor"] and
          record["vector_selection"] === job["vector_selection"] and
          record["fact_selection"] === job["fact_selection"]

      captured = Enum.slice(ordered, record["cursor"], 8)
      true = captured !== [] and rem(record["cursor"], 8) === 0
      identities = Enum.map(captured, &[&1["source"]["source_key"], E.sha256(json(&1["source"]))])
      true = record["source_set_sha256"] === E.sha256(json(%{"sources" => identities}))

      inputs =
        captured
        |> Enum.with_index()
        |> Enum.flat_map(fn {b, si} ->
          {:ok, chunks} = E.chunks(b["source"])

          Enum.with_index(chunks)
          |> Enum.map(fn {chunk, ci} ->
            {:ok, canonical} = Ipse.Extension.canonical_digest([chunk["text"]])

            [
              si,
              ci,
              chunk["chunk_id"],
              canonical,
              E.sha256(chunk["text"]),
              chunk["start_byte"],
              chunk["end_byte"]
            ]
          end)
        end)

      offset = if record["version"] === 4, do: record["vector_cursor"], else: 0
      selected = Enum.slice(inputs, offset, 8)

      if record["version"] === 4 do
        true =
          Producer.Progress.ready?(record, row["key"]) and
            record["vector_count"] === length(inputs) and
            record["input_count"] === length(selected) and
            record["input_refs_sha256"] === E.sha256(json(selected))

        if previous = record["previous_ready"] do
          previous_row = Map.fetch!(rows, previous["key"])

          true =
            Map.take(previous_row, ~w(key revision sha256 byte_count)) === previous and
              Map.take(previous_row["value"], ~w(job_id cursor source_set_sha256)) ===
                Map.take(record, ~w(job_id cursor source_set_sha256))
        end
      else
        true =
          row["key"] === "genproducer." <> profile["partition"] and Producer.valid_record?(record)

        bindings =
          Enum.map(captured, fn b ->
            source = b["source"]

            head =
              Map.fetch!(rows, "source." <> profile["partition"] <> "." <> source["source_key"])

            %{
              "source_key" => source["source_key"],
              "head_revision" => head["revision"],
              "head_sha256" => head["sha256"],
              "bundle_sha256" => b["head"]["bundle_sha256"],
              "observed_at_ms" => source["observed_at_ms"],
              "expires_at_ms" => source["expires_at_ms"],
              "historical" => source["origin"]["historical"],
              "chunking_sha256" => E.sha256(json(Map.take(source, ~w(version chunking))))
            }
          end)

        true =
          record["source_bindings"] === bindings and
            record["inputs"] ===
              if(record["version"] === 2,
                do: Enum.map(selected, &Enum.take(&1, 5)),
                else: selected
              )
      end

      true =
        Enum.flat_map(record["receipts"], & &1["input_sha256"]) ===
          Enum.map(selected, &Enum.at(&1, 3)) and
          Enum.flat_map(record["receipts"], & &1["raw_input_sha256"]) ===
            Enum.map(selected, &Enum.at(&1, 4))

      page = backup_ref!(rows, record["page"])

      {:ok, _} =
        Generation.unpack_vector_page(
          profile["partition"],
          record["cursor"],
          captured,
          page["value"],
          record["vector_selection"],
          offset
        )

      used |> MapSet.put(row["key"]) |> MapSet.put(page["key"])
    end)
  end

  @doc false
  def valid_selection?(selection), do: selection?(selection)
  @doc false
  def valid_extraction?(selection), do: extraction?(selection)

  @doc false
  def selected_fact_root?(root, profile, source, selection, catalog) do
    s = %{item_kind: :facts, source: source, profile: profile}

    root?(root, s) and root["selection"] === selection and
      root["catalog_sha256"] === catalog["sha256"] and
      root["catalog_generation"] === catalog["value"]["generation"] and
      root["floor"] === catalog["value"]["floor"] and
      root["source_bundle_sha256"] === E.sha256(json(source)) and
      root["source_generation"] === source["generation"] and
      root["content_sha256"] === source["content_sha256"]
  rescue
    _ -> false
  end

  @doc false
  def selected_facts(source, pages, selection, root) do
    with {:ok, facts} <- unpack_facts(source, pages, selection),
         true <- length(facts) === root["facts"],
         true <- entity_ids(source, facts) === root["entities"] do
      {:ok, facts}
    else
      _ -> {:error, :fact_projection_corrupt}
    end
  rescue
    _ -> {:error, :fact_projection_corrupt}
  end

  @doc "Reconstruct explicit facts from bounded source-local chunk ordinals and byte spans."
  def facts_from_spans(source, rows) when is_list(rows) and length(rows) in 0..32 do
    selection = %{"kind" => "explicit", "profile" => nil, "version" => 1}

    with {:ok, chunks} <- E.chunks(source),
         true <-
           Enum.all?(rows, fn row ->
             exact?(
               row,
               ~w(subject predicate object polarity inferred valid_from_ms valid_to_ms spans)
             ) and
               is_list(row["spans"]) and length(row["spans"]) in 1..8
           end),
         spans <-
           Enum.flat_map(rows, fn row ->
             Enum.map(row["spans"], fn [ordinal, start, finish] ->
               true = is_integer(ordinal) and ordinal in 0..(length(chunks) - 1)
               {Enum.at(chunks, ordinal), start, finish}
             end)
           end),
         {:ok, citations} <- if(spans == [], do: {:ok, []}, else: E.citations(source, spans)),
         {facts, []} <-
           Enum.map_reduce(rows, citations, fn row, rest ->
             {selected, remaining} = Enum.split(rest, length(row["spans"]))

             attrs =
               row
               |> Map.delete("spans")
               |> Map.put("extraction", selection)
               |> Map.put("citations", selected)

             {:ok, fact} = E.fact(attrs)
             {fact, remaining}
           end),
         true <- length(Enum.uniq_by(facts, & &1["fact_id"])) === length(facts) do
      {:ok, facts}
    else
      _ -> {:error, :invalid_explicit_fact_spans}
    end
  rescue
    _ -> {:error, :invalid_explicit_fact_spans}
  end

  def facts_from_spans(_, _), do: {:error, :invalid_explicit_fact_spans}

  @doc "Plan bounded canonical compact-input pages; these values grant no storage authority."
  def fact_input_pages(source, rows) do
    with {:ok, _facts} <- facts_from_spans(source, rows),
         source_hash = E.sha256(json(source)),
         {:ok, pages} <- build_fact_input_pages(rows, source_hash),
         true <- length(pages) <= @fact_input_pages do
      {:ok, %{pages: pages, manifest: fact_input_manifest(source_hash, rows, pages)}}
    else
      _ -> {:error, :invalid_fact_input_pages}
    end
  rescue
    _ -> {:error, :invalid_fact_input_pages}
  end

  @doc "Reconstruct a complete page set against its manifest; the caller must authenticate that manifest."
  def fact_input_rows(source, pages, manifest) do
    with true <- is_list(pages) and length(pages) <= @fact_input_pages,
         source_hash = E.sha256(json(source)),
         true <-
           exact?(manifest, ~w(version source_bundle_sha256 row_count rows_sha256 page_sha256)) and
             manifest["version"] === 1 and manifest["source_bundle_sha256"] === source_hash and
             is_integer(manifest["row_count"]) and manifest["row_count"] in 0..32 and
             E.sha256?(manifest["rows_sha256"]) and is_list(manifest["page_sha256"]) and
             length(manifest["page_sha256"]) === length(pages) and
             Enum.all?(manifest["page_sha256"], &E.sha256?/1),
         true <-
           Enum.with_index(pages)
           |> Enum.all?(fn {page, ordinal} ->
             exact?(page, ~w(version kind source_bundle_sha256 ordinal rows)) and
               page["version"] === 1 and page["kind"] === "explicit_fact_input" and
               page["source_bundle_sha256"] === source_hash and page["ordinal"] === ordinal and
               is_list(page["rows"]) and length(page["rows"]) in 1..32 and
               byte_size(json(page)) <= @fact_input_page_bytes
           end),
         rows = Enum.flat_map(pages, & &1["rows"]),
         true <- manifest === fact_input_manifest(source_hash, rows, pages),
         {:ok, facts} <- facts_from_spans(source, rows),
         {:ok, expected} <- build_fact_input_pages(rows, source_hash),
         true <- expected === pages do
      {:ok, %{rows: rows, facts: facts}}
    else
      _ -> {:error, :invalid_fact_input_pages}
    end
  rescue
    _ -> {:error, :invalid_fact_input_pages}
  end

  @doc "Validate one compact page against its proposed manifest; the full set is checked on assembly."
  def fact_input_page?(source, page, manifest) do
    source_hash = E.sha256(json(source))

    exact?(manifest, ~w(version source_bundle_sha256 row_count rows_sha256 page_sha256)) and
      manifest["version"] === 1 and manifest["source_bundle_sha256"] === source_hash and
      is_integer(manifest["row_count"]) and manifest["row_count"] in 1..32 and
      E.sha256?(manifest["rows_sha256"]) and is_list(manifest["page_sha256"]) and
      length(manifest["page_sha256"]) in 1..@fact_input_pages and
      Enum.all?(manifest["page_sha256"], &E.sha256?/1) and
      exact?(page, ~w(version kind source_bundle_sha256 ordinal rows)) and
      page["version"] === 1 and page["kind"] === "explicit_fact_input" and
      page["source_bundle_sha256"] === source_hash and is_integer(page["ordinal"]) and
      page["ordinal"] in 0..(length(manifest["page_sha256"]) - 1) and
      Enum.at(manifest["page_sha256"], page["ordinal"]) === E.sha256(json(page)) and
      byte_size(json(page)) <= @fact_input_page_bytes and
      is_list(page["rows"]) and length(page["rows"]) in 1..manifest["row_count"] and
      match?({:ok, _}, facts_from_spans(source, page["rows"]))
  rescue
    _ -> false
  end

  defp fact_input_manifest(source_hash, rows, pages) do
    %{
      "version" => 1,
      "source_bundle_sha256" => source_hash,
      "row_count" => length(rows),
      "rows_sha256" => E.sha256(json(%{"rows" => rows})),
      "page_sha256" => Enum.map(pages, &E.sha256(json(&1)))
    }
  end

  defp build_fact_input_pages(rows, source_hash) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, pages} ->
      fresh = %{
        "version" => 1,
        "kind" => "explicit_fact_input",
        "source_bundle_sha256" => source_hash,
        "ordinal" => length(pages),
        "rows" => [row]
      }

      case List.last(pages) do
        nil ->
          if byte_size(json(fresh)) <= @fact_input_page_bytes,
            do: {:cont, {:ok, [fresh]}},
            else: {:halt, {:error, :fact_input_row_too_large}}

        last ->
          combined = Map.update!(last, "rows", &(&1 ++ [row]))

          cond do
            byte_size(json(combined)) <= @fact_input_page_bytes ->
              {:cont, {:ok, List.replace_at(pages, -1, combined)}}

            byte_size(json(fresh)) <= @fact_input_page_bytes and length(pages) < @fact_input_pages ->
              {:cont, {:ok, pages ++ [fresh]}}

            true ->
              {:halt, {:error, :fact_input_page_limit}}
          end
      end
    end)
  end

  def start(profile, operation, args) do
    with true <- operation in [:vector_store, :vector_selected, :fact_store, :fact_selected],
         true <- valid_args?(operation, args) do
      s = %{
        profile: profile,
        operation: operation,
        item_kind: if(operation in [:fact_store, :fact_selected], do: :facts, else: :vectors),
        args: args,
        token: Map.get(args, "continuation"),
        maintenance_epoch: nil,
        reads: 0,
        effects: 0
      }

      io(s, :snapshot, %{}, :boot)
    else
      _ -> error(:invalid_vector_projection)
    end
  rescue
    _ -> error(:invalid_vector_projection)
  end

  def resume(%{projection_state: s, inner: inner}, outcome) do
    advance(C.resume(inner, outcome), s)
  end

  @doc "Pack complete ordered chunk vectors without changing their float32 identity."
  def pack(source, vectors, selection) do
    with true <- E.valid_source?(source) and selection?(selection),
         {:ok, chunks} <- E.chunks(source),
         true <- is_list(vectors) and length(vectors) == length(chunks),
         true <- length(chunks) in 1..32,
         true <-
           Enum.zip(vectors, chunks)
           |> Enum.all?(fn {vector, chunk} ->
             E.current_vector?(vector) and Map.take(vector, @selection) === selection and
               E.vector_input_matches_chunk?(vector, chunk)
           end) do
      source_hash = E.sha256(json(source))

      pages =
        Enum.reduce(vectors, [], fn vector, pages ->
          bytes = for value <- vector["values"], into: <<>>, do: <<value::float-little-32>>

          row =
            Map.take(vector, ~w(chunk_id input_sha256 vector_sha256))
            |> Map.put("pieces", raw_parts(bytes))

          fresh = page(source_hash, length(pages), [row])

          case List.last(pages) do
            nil ->
              [fresh]

            last ->
              combined = Map.update!(last, "rows", &(&1 ++ [row]))

              if byte_size(json(combined)) <= @page_bytes do
                List.replace_at(pages, -1, combined)
              else
                pages ++ [fresh]
              end
          end
        end)

      if Enum.all?(pages, &(byte_size(json(&1)) <= @page_bytes)) do
        {:ok, pages}
      else
        {:error, :vector_page_bound}
      end
    else
      _ -> {:error, :invalid_vector_projection}
    end
  rescue
    _ -> {:error, :invalid_vector_projection}
  end

  @doc "Decode authenticated ordered pages and revalidate every exact raw chunk input."
  def unpack(source, pages, selection) do
    with true <- E.valid_source?(source) and selection?(selection),
         true <- is_list(pages) and length(pages) in 1..32,
         source_hash = E.sha256(json(source)),
         true <-
           Enum.with_index(pages)
           |> Enum.all?(fn {page, ordinal} ->
             exact?(page, ~w(version kind recipe source_bundle_sha256 ordinal rows)) and
               page["version"] === 1 and page["kind"] == "vector_page" and
               page["recipe"] == @recipe and page["source_bundle_sha256"] == source_hash and
               page["ordinal"] === ordinal and is_list(page["rows"]) and
               length(page["rows"]) in 1..32 and byte_size(json(page)) <= @page_bytes
           end),
         vectors =
           Enum.flat_map(pages, fn page ->
             Enum.map(page["rows"], fn row ->
               true = exact?(row, ~w(chunk_id input_sha256 vector_sha256 pieces))
               true = is_list(row["pieces"]) and length(row["pieces"]) in 1..4

               bytes =
                 Enum.map_join(row["pieces"], fn piece ->
                   true = is_binary(piece) and byte_size(piece) <= 5464
                   {:ok, decoded} = Base.decode64(piece)
                   true = Base.encode64(decoded) == piece
                   decoded
                 end)

               true = byte_size(bytes) == selection["dimensions"] * 4
               true = E.sha256(bytes) == row["vector_sha256"]

               values =
                 for <<value::float-little-32 <- bytes>> do
                   value
                 end

               selection
               |> Map.merge(Map.drop(row, ["pieces"]))
               |> Map.merge(%{"version" => 2, "values" => values})
             end)
           end),
         {:ok, expected_pages} <- pack(source, vectors, selection),
         true <- pages === expected_pages do
      {:ok, vectors}
    else
      _ -> {:error, :vector_projection_corrupt}
    end
  rescue
    _ -> {:error, :vector_projection_corrupt}
  end

  @doc "Pack attributable facts with exact source-local citation spans and entity labels."
  def pack_facts(source, [], selection) do
    if explicit_selection?(selection) and match?({:ok, _}, E.chunks(source)),
      do: {:ok, []},
      else: {:error, :invalid_fact_projection}
  rescue
    _ -> {:error, :invalid_fact_projection}
  end

  def pack_facts(source, facts, selection) do
    with true <- E.valid_source?(source) and extraction?(selection),
         true <- is_list(facts) and length(facts) in 1..32,
         true <-
           Enum.all?(facts, fn fact ->
             E.valid_fact?(fact) and fact["extraction"] === selection
           end),
         true <- E.valid_spans?(source, Enum.flat_map(facts, & &1["citations"])),
         true <- length(Enum.uniq_by(facts, & &1["fact_id"])) == length(facts),
         {:ok, chunks} <- E.chunks(source) do
      entities = entity_labels(facts)

      positions =
        chunks |> Enum.with_index() |> Map.new(fn {chunk, i} -> {chunk["chunk_id"], i} end)

      source_hash = E.sha256(json(source))

      pages =
        Enum.reduce(facts, [], fn fact, pages ->
          row = %{
            "fact" => Map.drop(fact, ~w(subject object citations)),
            "subject" => Enum.find_index(entities, &(&1 == fact["subject"])),
            "object" => Enum.find_index(entities, &(&1 == fact["object"])),
            "citations" =>
              Enum.map(fact["citations"], fn citation ->
                [
                  positions[citation["chunk_id"]],
                  citation["start_byte"],
                  citation["end_byte"],
                  citation["quote_sha256"]
                ]
              end)
          }

          fresh = %{
            "version" => 1,
            "kind" => "fact_page",
            "recipe" => @fact_recipe,
            "source_bundle_sha256" => source_hash,
            "ordinal" => length(pages),
            "entities" => entities,
            "rows" => [row]
          }

          case List.last(pages) do
            nil ->
              [fresh]

            last ->
              combined = Map.update!(last, "rows", &(&1 ++ [row]))

              if byte_size(json(combined)) <= @page_bytes and Paged.native_value?(combined),
                do: List.replace_at(pages, -1, combined),
                else: pages ++ [fresh]
          end
        end)

      if Enum.all?(pages, &(byte_size(json(&1)) <= @page_bytes and Paged.native_value?(&1))),
        do: {:ok, pages},
        else: {:error, :fact_page_bound}
    else
      _ -> {:error, :invalid_fact_projection}
    end
  rescue
    _ -> {:error, :invalid_fact_projection}
  end

  @doc "Regenerate full exact citations, preserving original fact and extraction identities."
  def unpack_facts(source, [], selection) do
    case pack_facts(source, [], selection) do
      {:ok, []} -> {:ok, []}
      _ -> {:error, :fact_projection_corrupt}
    end
  end

  def unpack_facts(source, pages, selection) do
    with true <- E.valid_source?(source) and extraction?(selection),
         true <- is_list(pages) and length(pages) in 1..32,
         {:ok, chunks} <- E.chunks(source),
         rows =
           Enum.flat_map(Enum.with_index(pages), fn {page, ordinal} ->
             true =
               exact?(page, ~w(version kind recipe source_bundle_sha256 ordinal entities rows))

             true =
               page["version"] === 1 and page["kind"] == "fact_page" and
                 page["recipe"] == @fact_recipe

             true =
               page["source_bundle_sha256"] == E.sha256(json(source)) and
                 page["ordinal"] === ordinal

             true = is_list(page["entities"]) and length(page["entities"]) in 1..64

             true =
               is_list(page["rows"]) and length(page["rows"]) in 1..32 and
                 byte_size(json(page)) <= @page_bytes

             Enum.map(page["rows"], fn row ->
               true = exact?(row, ~w(fact subject object citations))

               true =
                 is_integer(row["subject"]) and
                   row["subject"] in 0..(length(page["entities"]) - 1)

               true =
                 is_integer(row["object"]) and row["object"] in 0..(length(page["entities"]) - 1)

               true = is_list(row["citations"]) and length(row["citations"]) in 1..8

               {row, page["entities"]}
             end)
           end),
         true <- length(rows) in 1..32,
         spans =
           Enum.flat_map(rows, fn {row, _} ->
             Enum.map(row["citations"], fn [chunk, start, finish, _hash] ->
               true = is_integer(chunk) and chunk in 0..(length(chunks) - 1)
               {Enum.at(chunks, chunk), start, finish}
             end)
           end),
         {:ok, citations} <- E.citations(source, spans),
         {facts, []} =
           Enum.map_reduce(rows, citations, fn {row, entities}, remaining ->
             {selected, rest} = Enum.split(remaining, length(row["citations"]))

             true =
               Enum.zip(row["citations"], selected)
               |> Enum.all?(fn {[_chunk, _start, _finish, hash], citation} ->
                 citation["quote_sha256"] == hash
               end)

             fact =
               Map.merge(row["fact"], %{
                 "subject" => Enum.at(entities, row["subject"]),
                 "object" => Enum.at(entities, row["object"]),
                 "citations" => selected
               })

             true = E.valid_fact?(fact) and fact["extraction"] === selection
             {fact, rest}
           end),
         {:ok, expected} <- pack_facts(source, facts, selection),
         true <- expected === pages do
      {:ok, facts}
    else
      _ -> {:error, :fact_projection_corrupt}
    end
  rescue
    _ -> {:error, :fact_projection_corrupt}
  end

  defp valid_args?(:vector_store, args) do
    exact?(args, ~w(source_id selection vectors expected_revision as_of_ms continuation)) and
      source_id?(args["source_id"]) and selection?(args["selection"]) and is_list(args["vectors"]) and
      length(args["vectors"]) in 1..32 and E.safe_uint?(args["expected_revision"]) and
      E.safe_uint?(args["as_of_ms"]) and
      (is_nil(args["continuation"]) or token?(args["continuation"]))
  end

  defp valid_args?(:vector_selected, args) do
    exact?(args, ~w(source_id selection as_of_ms)) and source_id?(args["source_id"]) and
      selection?(args["selection"]) and E.safe_uint?(args["as_of_ms"])
  end

  defp valid_args?(:fact_store, args) do
    exact?(args, ~w(source_id selection facts expected_revision as_of_ms continuation)) and
      source_id?(args["source_id"]) and extraction?(args["selection"]) and
      is_list(args["facts"]) and length(args["facts"]) in 0..32 and
      (args["facts"] != [] or explicit_selection?(args["selection"])) and
      E.safe_uint?(args["expected_revision"]) and E.safe_uint?(args["as_of_ms"]) and
      (is_nil(args["continuation"]) or token?(args["continuation"]))
  end

  defp valid_args?(:fact_selected, args),
    do:
      exact?(args, ~w(source_id selection as_of_ms)) and source_id?(args["source_id"]) and
        extraction?(args["selection"]) and E.safe_uint?(args["as_of_ms"])

  defp selection?(s) do
    exact?(s, @selection) and E.sha256?(s["selection_sha256"]) and
      Enum.all?(~w(profile model), &(is_binary(s[&1]) and byte_size(s[&1]) in 1..128)) and
      is_integer(s["dimensions"]) and s["dimensions"] in 1..4096 and s["encoding"] == "float32le"
  end

  defp token?(t) do
    shape =
      (exact?(t, @token) and t["version"] === 1) or
        (exact?(t, @progress_token) and t["version"] === 2 and
           E.safe_positive?(t["maintenance_epoch"]) and
           (is_nil(t["progress"]) or progress?(t["progress"])))

    shape and E.sha256?(t["plan_sha256"]) and
      E.safe_uint?(t["catalog_revision"]) and E.safe_uint?(t["root_revision"]) and
      is_integer(t["unit"]) and t["unit"] in 0..34 and is_list(t["stages"]) and
      length(t["stages"]) <= 2 and Enum.all?(t["stages"], &exact?(&1, ~w(slot epoch))) and
      (is_nil(t["write"]) or is_map(t["write"])) and progress_token?(t)
  end

  defp progress_token?(%{"version" => 1}), do: true

  defp progress_token?(%{"progress" => nil} = t),
    do: t["unit"] === 0 and t["stages"] === [] and is_nil(t["write"])

  defp progress_token?(%{"progress" => p} = t) do
    p["unit"] === t["unit"] and p["maintenance_epoch"] === t["maintenance_epoch"] and
      p["prepared"] === sorted_refs(t["stages"])
  end

  defp progress?(p) do
    C.progress_receipt?(p) and p["status"] === "active" and
      is_nil(p["retirement_epoch"]) and length(p["slots"]) === 2 and
      length(p["prepared"]) <= 2 and p["unit_limit"] in 2..34 and p["kind"] === "projection"
  end

  defp io(s, operation, args, phase) do
    result =
      cond do
        is_nil(s.maintenance_epoch) or operation === :selected ->
          C.start(s.profile, operation, args)

        s.maintenance_epoch > 0 and phase in [:written, :published] ->
          C.start_with_progress(
            s.profile,
            operation,
            args,
            s.maintenance_epoch,
            progress_tag(s, phase)
          )

        true ->
          C.start_with_epoch(s.profile, operation, args, s.maintenance_epoch)
      end

    advance(result, Map.put(s, :phase, phase))
  end

  defp advance({:call, request, inner}, s) do
    read = C.read_request?(request)

    s = %{
      s
      | reads:
          s.reads +
            if read do
              1
            else
              0
            end,
        effects:
          s.effects +
            if read do
              0
            else
              1
            end
    }

    if s.reads <= 512 and s.effects <= 16 do
      {:call, request, %{projection_state: s, inner: inner}}
    else
      error(:vector_projection_budget)
    end
  end

  defp advance({:done, {:ok, value}}, s) do
    done(s, value)
  end

  defp advance({:done, {:continue, value}}, s) do
    case update_progress(s, value, s.token["unit"], s.token["stages"]) do
      {:ok, s} -> ready(s, value["continuation"])
      _ -> error(:vector_progress_unconfirmed)
    end
  end

  defp advance(other, _) do
    other
  end

  defp done(%{phase: :catalog} = s, value) do
    row = value["record"]

    with true <- is_map(row) and C.valid_catalog?(row["value"], s.profile),
         true <- is_nil(s.token) or row["revision"] == s.token["catalog_revision"] do
      s = Map.merge(s, %{catalog: row, native_generation: value["native_generation"]})

      io(
        s,
        :selected,
        %{"source_ids" => [s.args["source_id"]], "as_of_ms" => s.args["as_of_ms"]},
        :source
      )
    else
      _ -> error(:vector_catalog_changed)
    end
  end

  defp done(%{phase: :boot} = s, value) do
    with {:ok, epoch, status} <- C.snapshot_epoch(value),
         true <- status === "idle" or s.operation in [:vector_selected, :fact_selected],
         true <- is_nil(s.token) or Map.get(s.token, "maintenance_epoch", 0) === epoch,
         true <-
           epoch === 0 or s.operation in [:vector_selected, :fact_selected] or
             C.progress_supported?(value) do
      io(%{s | maintenance_epoch: epoch}, :value_read, %{"key" => catalog_key(s)}, :catalog)
    else
      _ -> error(:document_epoch_changed)
    end
  end

  defp done(%{phase: :progress} = s, value) do
    if value["progress"] === s.token["progress"] and progress_matches_plan?(s, value["progress"]),
      do: verify_values(s),
      else: error(:vector_progress_changed)
  end

  defp done(%{phase: :source} = s, value) do
    with [source] <- value["sources"],
         true <-
           value["catalog_generation"] == s.catalog["value"]["generation"] and
             value["catalog_floor"] == s.catalog["value"]["floor"] do
      s = Map.put(s, :source, source)
      io(s, :value_read, %{"key" => root_key(s)}, :root)
    else
      _ -> error(:vector_source_changed)
    end
  end

  defp done(%{phase: :root} = s, value) do
    row = value["record"]

    with true <- row == nil or root?(row["value"], s),
         true <- is_nil(s.token) or revision(row) == s.token["root_revision"] do
      s = Map.put(s, :root, row)

      if s.operation in [:vector_selected, :fact_selected] do
        read_projection(s)
      else
        prepare_plan(s)
      end
    else
      _ -> error(:vector_projection_root_changed)
    end
  end

  defp done(%{phase: :known_page, verify: [ref | rest]} = s, value) do
    row = value["record"]

    if is_map(row) and row["sha256"] == ref["sha256"] and row["byte_count"] == ref["byte_count"] do
      verify_values(%{s | verify: rest})
    else
      error(:vector_page_missing)
    end
  end

  defp done(%{phase: :known_stage, stage_verify: [{ref, ordinal} | rest]} = s, value) do
    {key, body, revision} = metadata(s, ordinal)
    stage = value["stage"]

    with true <- is_map(stage) and Map.take(stage, ~w(slot epoch)) === ref,
         true <- stage["key"] == key and stage["expected_revision"] == revision,
         true <-
           stage["sha256"] == E.sha256(json(body)) and
             stage["byte_count"] == byte_size(json(body)),
         true <- stage["state"] == "sealed" and stage["offset"] == stage["byte_count"] do
      verify_stages(%{s | stage_verify: rest, native_generation: value["generation"]})
    else
      _ -> error(:vector_stage_changed)
    end
  end

  defp done(%{phase: :written} = s, value) do
    stages =
      if s.token["unit"] < length(s.pages) do
        s.token["stages"]
      else
        s.token["stages"] ++ [value["stage"]]
      end

    unit = s.token["unit"] + 1

    case update_progress(s, value, unit, stages) do
      {:ok, s} ->
        token = s.token |> Map.put("stages", stages) |> Map.put("unit", unit)
        ready(%{s | token: token}, nil)

      _ ->
        error(:vector_progress_unconfirmed)
    end
  end

  defp done(%{phase: :published} = s, value) do
    if s.maintenance_epoch === 0 or finished_progress?(s, value["progress"]),
      do: published(s),
      else: error(:vector_progress_unconfirmed)
  end

  defp done(%{phase: :page, pending: [_ | rest]} = s, value) do
    read_page(%{s | pending: rest, hydrated: s.hydrated ++ [value["value"]]})
  end

  defp done(%{phase: :final_catalog} = s, value) do
    if value["record"] != nil and value["record"]["sha256"] == s.catalog["sha256"] and
         value["record"]["revision"] == s.catalog["revision"] do
      {:done,
       {:ok,
        %{
          "source" => s.source,
          item_field(s) => s.items,
          "revision" => s.root["value"]["revision"],
          "coverage" => coverage(s)
        }}}
    else
      error(:vector_catalog_changed)
    end
  end

  defp published(s) do
    {:done,
     {:ok,
      %{
        "status" => "stored_" <> item_field(s),
        "revision" => s.planned_root["revision"],
        item_field(s) => s.planned_root[item_field(s)],
        "pages" => length(s.pages),
        "continuation" => nil,
        "coverage" => coverage(s)
      }}}
  end

  defp prepare_plan(s) do
    with true <- logical_revision(s.root) == s.args["expected_revision"],
         true <-
           s.root == nil or
             (s.root["value"]["catalog_generation"] <= s.catalog["value"]["generation"] and
                s.root["value"]["floor"] <= s.catalog["value"]["floor"]),
         {:ok, pages} <- pack_items(s) do
      refs = Enum.map(pages, &ref(s, &1))

      root = %{
        "version" => 1,
        "kind" => projection_kind(s),
        "recipe" => recipe(s),
        "revision" => s.args["expected_revision"] + 1,
        "source_key" => s.source["source_key"],
        "source_generation" => s.source["generation"],
        "content_sha256" => s.source["content_sha256"],
        "source_bundle_sha256" => E.sha256(json(s.source)),
        "selection" => s.args["selection"],
        item_field(s) => length(s.args[item_field(s)]),
        "catalog_sha256" => s.catalog["sha256"],
        "catalog_generation" => s.catalog["value"]["generation"],
        "floor" => s.catalog["value"]["floor"],
        "pages" => refs
      }

      root =
        if s.item_kind == :facts,
          do: Map.put(root, "entities", entity_ids(s.source, s.args["facts"])),
          else: root

      plan_hash = E.sha256(json(root))

      fresh = %{
        "version" => 1,
        "plan_sha256" => plan_hash,
        "catalog_revision" => s.catalog["revision"],
        "root_revision" => revision(s.root),
        "unit" => 0,
        "stages" => [],
        "write" => nil
      }

      fresh =
        if s.maintenance_epoch > 0,
          do:
            Map.merge(fresh, %{
              "version" => 2,
              "maintenance_epoch" => s.maintenance_epoch,
              "progress" => nil
            }),
          else: fresh

      token = s.token || fresh

      count = length(pages)

      with true <- token["plan_sha256"] == plan_hash and token["unit"] <= count + 2,
           true <- length(token["stages"]) == max(token["unit"] - count, 0),
           true <- token["unit"] < count + 2 or is_nil(token["write"]) do
        s =
          Map.merge(s, %{
            token: token,
            pages: pages,
            planned_root: root,
            verify: Enum.take(refs, min(token["unit"], count))
          })

        cond do
          s.maintenance_epoch === 0 ->
            verify_values(s)

          is_nil(token["progress"]) and progress_token?(token) ->
            verify_values(s)

          progress_matches_plan?(s, token["progress"]) ->
            io(s, :progress_inspect, %{"head_id" => token["progress"]["head_id"]}, :progress)

          true ->
            error(:invalid_vector_continuation)
        end
      else
        _ -> error(:invalid_vector_continuation)
      end
    else
      _ -> error(:vector_projection_preflight)
    end
  end

  defp verify_values(%{verify: []} = s) do
    verify_stages(Map.put(s, :stage_verify, Enum.with_index(s.token["stages"])))
  end

  defp verify_values(%{verify: [ref | _]} = s) do
    io(s, :value_stat, %{"key" => ref["key"], "generation" => s.native_generation}, :known_page)
  end

  defp verify_stages(%{stage_verify: []} = s) do
    perform_unit(s)
  end

  defp verify_stages(%{stage_verify: [{ref, _} | _]} = s) do
    io(s, :stage_inspect, %{"ref" => ref}, :known_stage)
  end

  defp perform_unit(s) do
    unit = s.token["unit"]
    count = length(s.pages)

    cond do
      unit < count ->
        page = Enum.at(s.pages, unit)
        write(s, :value_write, ref(s, page)["key"], page, 0, true)

      unit < count + 2 ->
        {key, body, revision} = metadata(s, unit - count)
        write(s, :value_prepare, key, body, revision, false)

      true ->
        io(
          s,
          if(s.item_kind == :facts, do: :fact_commit_at, else: :value_commit_at),
          %{"stages" => s.token["stages"], "generation" => s.native_generation},
          :published
        )
    end
  end

  defp write(s, op, key, body, revision, reuse) do
    io(
      s,
      op,
      %{
        "key" => key,
        "value" => body,
        "expected_revision" => revision,
        "reuse" => reuse,
        "continuation" => s.token["write"],
        "reads_used" => s.reads,
        "effects_used" => s.effects
      },
      :written
    )
  end

  defp progress_tag(s, phase) do
    case s.token["progress"] do
      nil ->
        %{
          "version" => 1,
          "action" => "start",
          "kind" => "projection",
          "plan_sha256" => s.token["plan_sha256"],
          "body_sha256" => E.sha256(json(s.source)),
          "unit_limit" => length(s.pages) + 2
        }

      progress ->
        %{
          "version" => 1,
          "action" => if(phase === :published, do: "finish", else: "continue"),
          "head_id" => progress["head_id"],
          "revision" => progress["revision"],
          "unit" => progress["unit"]
        }
    end
  end

  defp progress_matches_plan?(s, p) do
    progress?(p) and p["maintenance_epoch"] === s.maintenance_epoch and
      p["plan_sha256"] === s.token["plan_sha256"] and
      p["body_sha256"] === E.sha256(json(s.source)) and
      p["unit_limit"] === length(s.pages) + 2
  end

  defp update_progress(%{maintenance_epoch: 0} = s, _, _, _), do: {:ok, s}

  defp update_progress(s, value, unit, stages) do
    p = value["progress"]
    old = s.token["progress"]

    with true <- progress_matches_plan?(s, p),
         true <- p["unit"] === unit and p["prepared"] === sorted_refs(stages),
         true <- unit === s.token["unit"] or is_nil(p["active"]),
         true <-
           is_nil(old) or (p["head_id"] === old["head_id"] and p["revision"] > old["revision"]) do
      {:ok, %{s | token: Map.put(s.token, "progress", p)}}
    else
      _ -> {:error, :vector_progress_unconfirmed}
    end
  end

  defp finished_progress?(s, p) do
    old = s.token["progress"]
    changed = ~w(status revision slots active prepared)

    exact?(p, @progress_fields) and is_map(old) and p["status"] === "finished" and
      E.safe_positive?(p["revision"]) and p["revision"] > old["revision"] and
      p["slots"] === [] and is_nil(p["active"]) and p["prepared"] === [] and
      p["unit"] === length(s.pages) + 2 and
      Map.drop(p, changed) === Map.drop(old, changed)
  end

  defp sorted_refs(refs), do: Enum.sort_by(refs, & &1["slot"])

  defp ready(s, write) do
    {:done,
     {:continue,
      %{
        "status" => "staged_" <> item_field(s),
        "continuation" => Map.put(s.token, "write", write),
        "coverage" => coverage(s)
      }}}
  end

  defp read_projection(s) do
    with true <- s.root != nil,
         root = s.root["value"],
         true <- root["selection"] === s.args["selection"],
         true <-
           root["catalog_sha256"] == s.catalog["sha256"] and
             root["catalog_generation"] == s.catalog["value"]["generation"] and
             root["floor"] == s.catalog["value"]["floor"],
         true <-
           root["source_bundle_sha256"] == E.sha256(json(s.source)) and
             root["source_generation"] == s.source["generation"] and
             root["content_sha256"] == s.source["content_sha256"] do
      read_page(Map.merge(s, %{pending: root["pages"], hydrated: []}))
    else
      _ -> error(:vector_projection_stale)
    end
  end

  defp read_page(%{pending: []} = s) do
    with {:ok, items} <- unpack_items(s),
         true <- length(items) == s.root["value"][item_field(s)],
         true <-
           s.item_kind != :facts or entity_ids(s.source, items) === s.root["value"]["entities"] do
      io(Map.put(s, :items, items), :value_read, %{"key" => catalog_key(s)}, :final_catalog)
    else
      _ -> error(:vector_projection_corrupt)
    end
  end

  defp read_page(%{pending: [ref | _]} = s) do
    io(s, :object_read, Map.put(ref, "generation", s.native_generation), :page)
  end

  defp metadata(s, 0) do
    {root_key(s), s.planned_root, s.token["root_revision"]}
  end

  defp metadata(s, 1) do
    {catalog_key(s), s.catalog["value"], s.token["catalog_revision"]}
  end

  defp page(hash, ordinal, rows) do
    %{
      "version" => 1,
      "kind" => "vector_page",
      "recipe" => @recipe,
      "source_bundle_sha256" => hash,
      "ordinal" => ordinal,
      "rows" => rows
    }
  end

  defp ref(s, page) do
    %{
      "key" => page_prefix(s) <> s.profile["partition"] <> "." <> E.sha256(json(page)),
      "sha256" => E.sha256(json(page)),
      "byte_count" => byte_size(json(page))
    }
  end

  defp root?(r, s) do
    exact?(
      r,
      ~w(version kind recipe revision source_key source_generation content_sha256 source_bundle_sha256 selection catalog_sha256 catalog_generation floor pages) ++
        [item_field(s)] ++ if(s.item_kind == :facts, do: ["entities"], else: [])
    ) and r["version"] === 1 and r["kind"] == projection_kind(s) and r["recipe"] == recipe(s) and
      r["source_key"] == s.source["source_key"] and E.safe_positive?(r["revision"]) and
      E.safe_positive?(r["source_generation"]) and projection_selection?(s, r["selection"]) and
      Enum.all?(~w(content_sha256 source_bundle_sha256 catalog_sha256), &E.sha256?(r[&1])) and
      Enum.all?(~w(catalog_generation floor), &E.safe_uint?(r[&1])) and
      is_integer(r[item_field(s)]) and
      r[item_field(s)] in 0..32 and is_list(r["pages"]) and length(r["pages"]) in 0..32 and
      length(r["pages"]) <= r[item_field(s)] and
      (r[item_field(s)] > 0 or
         (s.item_kind == :facts and explicit_selection?(r["selection"]) and r["pages"] === [])) and
      (r[item_field(s)] == 0 or r["pages"] != []) and
      (s.item_kind != :facts or
         (is_list(r["entities"]) and length(r["entities"]) in 0..64 and
            (r[item_field(s)] != 0 or r["entities"] === []) and
            (r[item_field(s)] == 0 or r["entities"] != []) and
            Enum.all?(r["entities"], &E.sha256?/1) and
            length(Enum.uniq(r["entities"])) == length(r["entities"]))) and
      Enum.all?(r["pages"], fn ref ->
        exact?(ref, ~w(key sha256 byte_count)) and
          E.sha256?(ref["sha256"]) and
          ref["key"] == page_prefix(s) <> s.profile["partition"] <> "." <> ref["sha256"] and
          is_integer(ref["byte_count"]) and
          ref["byte_count"] in 2..@page_bytes
      end)
  end

  defp coverage(s) do
    %{
      "reads_used" => s.reads,
      "effects_used" => s.effects,
      "cache_scope" =>
        if(s.item_kind == :facts, do: "source_fact_projection", else: "source_vector_projection"),
      "namespace_complete" => false,
      "population_qualified" => false,
      "quality_qualified" => false
    }
  end

  defp catalog_key(s) do
    "catalog." <> s.profile["partition"]
  end

  defp root_key(s) do
    if(s.item_kind == :facts, do: "facts.", else: "vector.") <>
      s.profile["partition"] <> "." <> E.sha256(s.args["source_id"])
  end

  defp revision(nil) do
    0
  end

  defp revision(row) do
    row["revision"]
  end

  defp logical_revision(nil) do
    0
  end

  defp logical_revision(row) do
    row["value"]["revision"]
  end

  defp source_id?(id) do
    is_binary(id) and byte_size(id) in 1..512
  end

  defp extraction?(selection),
    do:
      exact?(selection, ~w(kind profile version)) and
        selection["kind"] in ~w(explicit model_complete) and selection["version"] === 1 and
        (is_nil(selection["profile"]) or
           (is_binary(selection["profile"]) and String.valid?(selection["profile"]) and
              byte_size(selection["profile"]) <= 128))

  defp explicit_selection?(selection),
    do: selection === %{"kind" => "explicit", "profile" => nil, "version" => 1}

  defp entity_labels(facts),
    do: facts |> Enum.flat_map(&[&1["subject"], &1["object"]]) |> Enum.uniq() |> Enum.sort()

  defp entity_ids(source, facts),
    do: Enum.map(entity_labels(facts), &E.id("entity", [source["partition"], &1]))

  defp item_field(s), do: Atom.to_string(s.item_kind)
  defp recipe(%{item_kind: :facts}), do: @fact_recipe
  defp recipe(_), do: @recipe
  defp projection_kind(%{item_kind: :facts}), do: "fact_projection"
  defp projection_kind(_), do: "vector_projection"
  defp page_prefix(%{item_kind: :facts}), do: "factp."
  defp page_prefix(_), do: "vecp."
  defp projection_selection?(%{item_kind: :facts}, selection), do: extraction?(selection)
  defp projection_selection?(_, selection), do: selection?(selection)

  defp pack_items(%{item_kind: :facts} = s),
    do: pack_facts(s.source, s.args["facts"], s.args["selection"])

  defp pack_items(s), do: pack(s.source, s.args["vectors"], s.args["selection"])

  defp unpack_items(%{item_kind: :facts} = s),
    do: unpack_facts(s.source, s.hydrated, s.args["selection"])

  defp unpack_items(s), do: unpack(s.source, s.hydrated, s.args["selection"])

  defp raw_parts(""), do: []

  defp raw_parts(bytes) do
    n = min(byte_size(bytes), 4096)

    [
      Base.encode64(binary_part(bytes, 0, n))
      | raw_parts(binary_part(bytes, n, byte_size(bytes) - n))
    ]
  end

  defp json(value) do
    IO.iodata_to_binary(JSON.encode!(value))
  end

  defp exact?(m, keys) do
    is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  end

  defp error(code) do
    {:done, {:error, code, %{}}}
  end
end
