defmodule Ipse.Extension.Collection.DocumentSourceUse do
  @moduledoc """
  Host-private authentication of one fixed shared-producer input batch.

  The caller supplies the actual retained document read closure. This closed
  relation authenticates stored anchors, complete source bytes and exact ranges;
  it supplies neither operator permission nor live invocation authority. The
  dispatch owner must bind the committing operation to its current invocation,
  spend the next batch once, and check current host time after blocking checks.
  No extension code runs inside the retained Collection callback.

  This checks the bounded stored byte/time relation. Document extraction receipt
  meaning, locator fidelity and domain Source validity remain extension-owned;
  authenticating bytes does not certify those claims or an author's truth.
  """
  alias Ipse.JSON, as: J
  alias Ipse.Extension.Collection.DocumentStage
  @error {:error, :document_source_use_refused}
  @claim ~w(version kind recipe partition job_id job_revision catalog_sha256 catalog_floor root_revision root_sha256 cursor embedding vector_selection fact_selection source_set_sha256 source_bindings inputs status page receipts)
  @claim_v4 @claim ++ ~w(vector_cursor vector_count previous_ready)
  @ready_v4 (@claim_v4 -- ~w(source_bindings inputs)) ++ ~w(claim input_count input_refs_sha256)
  @binding ~w(source_key head_revision head_sha256 bundle_sha256 observed_at_ms expires_at_ms historical chunking_sha256)
  @source ~w(version source_id partition generation title text uri observed_at_ms event_at_ms expires_at_ms origin source_key content_sha256)
  @max_reads 269
  @max_logical_bytes 18 * 1024 * 1024
  @max_bundle_bytes 1024 * 1024
  @job_fields ~w(version kind id partition status catalog catalog_sha256 generation root_revision root_sha256 vector_selection fact_selection cursor summaries facts)
  @job_reduction ~w(phase batch manifests runs positions entity_pages entities text_bytes chunks facts heads_sha256 entities_sha256)

  def guard?(g) do
    exact?(g, ~w(version claim_key claim_revision claim_sha256 batch_index)) and
      ((g["version"] === 1 and is_binary(g["claim_key"]) and
          Regex.match?(~r/\Agenproducer\.[a-z][a-z0-9_-]{0,15}\z/, g["claim_key"])) or
         (g["version"] === 2 and v4_key?(g["claim_key"]))) and
      positive?(g["claim_revision"]) and J.sha256?(g["claim_sha256"]) and
      is_integer(g["batch_index"]) and g["batch_index"] in 0..3
  rescue
    _ -> false
  end

  @doc "Authenticate one batch; returned facts still require the trusted live dispatch owner."
  def authenticate(read, guard, inputs, selection, maintenance) when is_function(read, 1) do
    with true <-
           exact?(maintenance, ~w(version epoch status)) and
             maintenance["version"] === 1 and maintenance["status"] === "idle" and
             J.safe_uint?(maintenance["epoch"]),
         true <- guard?(guard),
         true <- is_list(inputs) and length(inputs) in 1..2,
         state = %{reads: 0, logical_bytes: 0, bundle_bytes: 0},
         {claim_row, state} = load!(read, guard["claim_key"], state),
         true <- claim_row["revision"] === guard["claim_revision"],
         true <- claim_row["sha256"] === guard["claim_sha256"],
         true <- id?(claim_row["operation_id"]),
         claim = claim_row["value"],
         true <- claim_for_guard?(claim, guard, selection),
         partition = claim["partition"],
         {catalog_row, state} = load!(read, "catalog." <> partition, state),
         {root_row, state} = load!(read, "generation." <> partition, state),
         {job_row, state} = load!(read, "genjob." <> partition, state),
         true <- anchors?(claim, catalog_row, root_row, job_row, maintenance["epoch"]),
         page_no = div(claim["cursor"], 16),
         {page_row, state} = load!(read, "catalog.#{partition}.#{page_no}", state),
         true <- page?(page_row, page_no, catalog_row["value"], partition),
         rows = Enum.slice(page_row["value"]["rows"], rem(claim["cursor"], 16), 8),
         true <- length(rows) === length(claim["source_bindings"]),
         {sources, state} = sources!(read, claim, rows, state),
         true <- length(Enum.uniq_by(sources, & &1["head_ordinal"])) === length(sources),
         true <- source_set?(claim, sources),
         true <- input_refs?(claim, sources),
         batch = Enum.slice(claim["inputs"], guard["batch_index"] * 2, 2),
         true <- batch != [] and length(batch) === length(inputs),
         true <- Enum.zip(batch, inputs) |> Enum.all?(&input_matches?(&1, sources)) do
      {:ok,
       %{
         claim_key: guard["claim_key"],
         claim_revision: claim_row["revision"],
         claim_sha256: claim_row["sha256"],
         claim_operation_id: claim_row["operation_id"],
         batch_index: guard["batch_index"],
         batch_count: div(length(claim["inputs"]) + 1, 2),
         selection_sha256: selection["selection_sha256"],
         maintenance_epoch: maintenance["epoch"],
         sources: Enum.map(sources, &Map.take(&1, ~w(observed_at_ms expires_at_ms historical))),
         reads: state.reads,
         logical_bytes: state.logical_bytes,
         bundle_bytes: state.bundle_bytes
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate(_, _, _, _, _), do: @error

  @doc """
  Inspect a proposed source head and its existing blocks under one retained
  document read. This returns no file, Session, consent or publication authority.
  """
  def inspect_workspace_document(read, key, head) when is_function(read, 1) do
    with [_, partition, source_key] <-
           Regex.run(~r/\Asource\.([a-z][a-z0-9_-]{0,15})\.([0-9a-f]{64})\z/, key),
         true <- is_map(head) and is_integer(head["ordinal"]) and head["ordinal"] >= 0,
         true <- head?(head, source_key, div(head["ordinal"], 16)),
         {bytes, _} <-
           bundle!(read, partition, head, %{reads: 0, logical_bytes: 0, bundle_bytes: 0}),
         {:ok, decoded} <- J.decode_unique(bytes),
         source = source!(decoded, partition, head) do
      case get_in(source, ["origin", "receipt"]) do
        %{"kind" => "document_extraction"} = receipt ->
          body = document_body!(receipt, source)
          acquisition = body["acquisition"]

          with true <- body["kind"] === "document_extraction" and body["format"] === "docx",
               true <- J.sha256?(body["original_sha256"]),
               count when is_integer(count) and count > 0 <- body["original_bytes"],
               true <- J.safe_uint?(count),
               true <- is_nil(acquisition) or is_map(acquisition),
               path = if(acquisition, do: acquisition["path"]),
               operation = if(acquisition, do: acquisition["operation_id"]),
               true <- is_nil(path) or is_binary(path),
               true <- is_nil(operation) or is_binary(operation) do
            {:ok,
             %{
               "path" => path,
               "original_sha256" => body["original_sha256"],
               "original_bytes" => count,
               "acquisition_operation_id" => operation,
               "source_id" => source["source_id"],
               "generation" => source["generation"],
               "bundle_sha256" => head["bundle_sha256"]
             }}
          else
            _ -> @error
          end

        _ ->
          {:ok, :not_workspace_document}
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def inspect_workspace_document(_, _, _), do: @error

  @doc """
  Authenticate one projection source under a retained document read owner.

  The returned times and digest describe stored bytes only. Callers must bind
  the target to the exact live publication, check current time and identity,
  and fence the final write against the same Collection generation. This is
  not a publication grant and does not authenticate a fact's meaning.
  """
  def authenticate_projection_source(read, target) when is_function(read, 1) do
    with true <-
           exact?(
             target,
             ~w(partition source_key catalog_sha256 head_revision head_sha256 source_bundle_sha256)
           ),
         true <- partition?(target["partition"]),
         true <-
           Enum.all?(
             ~w(source_key catalog_sha256 head_sha256 source_bundle_sha256),
             &J.sha256?(target[&1])
           ),
         true <- positive?(target["head_revision"]),
         partition = target["partition"],
         state = %{reads: 0, logical_bytes: 0, bundle_bytes: 0},
         {catalog_row, state} <- load!(read, "catalog." <> partition, state),
         true <- is_map(catalog_row) and catalog_row["sha256"] === target["catalog_sha256"],
         catalog = catalog_row["value"],
         true <-
           is_map(catalog) and catalog["version"] === 1 and catalog["kind"] === "catalog" and
             catalog["partition"] === partition and is_integer(catalog["sources"]) and
             catalog["sources"] in 1..1000 and is_list(catalog["pages"]),
         {head_row, state} <- load!(read, "source.#{partition}.#{target["source_key"]}", state),
         true <-
           is_map(head_row) and head_row["revision"] === target["head_revision"] and
             head_row["sha256"] === target["head_sha256"],
         head = head_row["value"],
         true <- is_integer(head["ordinal"]) and head["ordinal"] in 0..(catalog["sources"] - 1),
         page_no = div(head["ordinal"], 16),
         true <- head?(head, target["source_key"], page_no),
         {page_row, state} <- load!(read, "catalog.#{partition}.#{page_no}", state),
         true <- is_map(page_row) and page?(page_row, page_no, catalog, partition),
         true <-
           %{"source_key" => target["source_key"], "head_sha256" => target["head_sha256"]} in page_row[
             "value"
           ]["rows"],
         {bytes, state} <- bundle!(read, partition, head, state),
         {:ok, decoded} <- J.decode_unique(bytes),
         source = source!(decoded, partition, head),
         true <- J.sha256(json(source)) === target["source_bundle_sha256"] do
      {:ok,
       %{
         sources: [
           %{
             "observed_at_ms" => source["observed_at_ms"],
             "expires_at_ms" => source["expires_at_ms"],
             "historical" => source["origin"]["historical"]
           }
         ],
         source_generation: source["generation"],
         content_sha256: source["content_sha256"],
         reads: state.reads,
         logical_bytes: state.logical_bytes,
         bundle_bytes: state.bundle_bytes
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_projection_source(_, _), do: @error

  @doc "Authenticate a bounded catalog group and its complete sources; this grants no publication authority."
  def authenticate_group_sources(read, group) when is_function(read, 1) do
    with true <- exact?(group, ~w(partition catalog_sha256 cursor sources)),
         true <- partition?(group["partition"]) and J.sha256?(group["catalog_sha256"]),
         true <-
           is_integer(group["cursor"]) and group["cursor"] in 0..992 and
             rem(group["cursor"], 8) === 0,
         true <- is_list(group["sources"]) and length(group["sources"]) in 1..8,
         true <-
           Enum.all?(group["sources"], fn source ->
             exact?(source, ~w(source_key ordinal text_bytes chunks bundle_sha256 head_sha256)) and
               Enum.all?(~w(source_key bundle_sha256 head_sha256), &J.sha256?(source[&1])) and
               is_integer(source["ordinal"]) and source["ordinal"] in 0..999 and
               is_integer(source["text_bytes"]) and source["text_bytes"] in 1..65_536 and
               is_integer(source["chunks"]) and source["chunks"] in 1..32
           end),
         partition = group["partition"],
         state = %{reads: 0, logical_bytes: 0, bundle_bytes: 0},
         {catalog_row, state} = load!(read, "catalog." <> partition, state),
         true <- is_map(catalog_row) and catalog_row["sha256"] === group["catalog_sha256"],
         catalog = catalog_row["value"],
         true <-
           is_map(catalog) and catalog["version"] === 1 and catalog["kind"] === "catalog" and
             catalog["partition"] === partition and is_integer(catalog["sources"]) and
             catalog["sources"] in 1..1000 and group["cursor"] < catalog["sources"] and
             length(group["sources"]) === min(8, catalog["sources"] - group["cursor"]) and
             is_list(catalog["pages"]),
         page_no = div(group["cursor"], 16),
         {page_row, state} = load!(read, "catalog.#{partition}.#{page_no}", state),
         true <- is_map(page_row) and page?(page_row, page_no, catalog, partition),
         rows =
           Enum.slice(
             page_row["value"]["rows"],
             rem(group["cursor"], 16),
             length(group["sources"])
           ),
         true <- rows === Enum.map(group["sources"], &Map.take(&1, ~w(source_key head_sha256))),
         {sources, state} =
           Enum.map_reduce(group["sources"], state, fn summary, state ->
             {head_row, state} =
               load!(read, "source.#{partition}.#{summary["source_key"]}", state)

             true = is_map(head_row) and head_row["sha256"] === summary["head_sha256"]
             head = head_row["value"]
             true = head?(head, summary["source_key"], page_no)

             true =
               Map.take(head, ~w(source_key ordinal text_bytes chunks bundle_sha256)) ===
                 Map.take(summary, ~w(source_key ordinal text_bytes chunks bundle_sha256))

             {bytes, state} = bundle!(read, partition, head, state)
             {:ok, decoded} = J.decode_unique(bytes)
             source = source!(decoded, partition, head)

             {Map.merge(
                Map.take(source, ~w(observed_at_ms expires_at_ms)),
                %{"historical" => source["origin"]["historical"]}
              ), state}
           end),
         true <-
           length(Enum.uniq_by(group["sources"], & &1["ordinal"])) === length(group["sources"]) do
      {:ok,
       %{
         sources: sources,
         reads: state.reads,
         logical_bytes: state.logical_bytes,
         bundle_bytes: state.bundle_bytes
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_group_sources(_, _), do: @error

  @doc "Read one current catalog slice and authenticate its complete sources; grants no use authority."
  def authenticate_catalog_group(read, partition, catalog_sha256, cursor)
      when is_function(read, 1) do
    with true <- partition?(partition) and J.sha256?(catalog_sha256),
         true <- is_integer(cursor) and cursor in 0..992 and rem(cursor, 8) === 0,
         state = %{reads: 0, logical_bytes: 0, bundle_bytes: 0},
         {catalog_row, state} = load!(read, "catalog." <> partition, state),
         true <- is_map(catalog_row) and catalog_row["sha256"] === catalog_sha256,
         catalog = catalog_row["value"],
         true <-
           is_map(catalog) and is_integer(catalog["sources"]) and
             catalog["sources"] in 1..1000 and cursor < catalog["sources"],
         page_no = div(cursor, 16),
         {page, state} = load!(read, "catalog.#{partition}.#{page_no}", state),
         true <- is_map(page) and page?(page, page_no, catalog, partition),
         rows =
           Enum.slice(page["value"]["rows"], rem(cursor, 16), min(8, catalog["sources"] - cursor)),
         {sources, state} =
           Enum.map_reduce(rows, state, fn row, state ->
             {head_row, state} = load!(read, "source.#{partition}.#{row["source_key"]}", state)
             true = is_map(head_row) and head_row["sha256"] === row["head_sha256"]
             head = head_row["value"]
             true = head?(head, row["source_key"], page_no)

             {Map.put(
                Map.take(head, ~w(source_key ordinal text_bytes chunks bundle_sha256)),
                "head_sha256",
                row["head_sha256"]
              ), state}
           end),
         group = %{
           "partition" => partition,
           "catalog_sha256" => catalog_sha256,
           "cursor" => cursor,
           "sources" => sources
         },
         {:ok, proof} <- authenticate_group_sources(read, group) do
      {:ok,
       proof
       |> Map.put(:catalog_rows, rows)
       |> Map.put(:catalog_source_count, catalog["sources"])
       |> Map.update!(:reads, &(&1 + state.reads))
       |> Map.update!(:logical_bytes, &(&1 + state.logical_bytes))}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_catalog_group(_, _, _, _), do: @error

  @doc "Bind one immutable manifest row to its current catalog group; this grants no publication authority."
  def authenticate_manifest_group(read, partition, catalog_sha256, manifest_ref, cursor)
      when is_function(read, 1) do
    with true <- partition?(partition) and J.sha256?(catalog_sha256),
         true <- is_integer(cursor) and cursor in 0..992 and rem(cursor, 8) === 0,
         true <-
           exact?(manifest_ref, ~w(key sha256 byte_count)) and
             J.sha256?(manifest_ref["sha256"]) and
             manifest_ref["key"] === "genman.#{partition}." <> manifest_ref["sha256"] and
             is_integer(manifest_ref["byte_count"]) and manifest_ref["byte_count"] in 2..49_152,
         {:ok, manifest} when is_map(manifest) <-
           DocumentStage.read_value(read, manifest_ref["key"]),
         true <-
           manifest["sha256"] === manifest_ref["sha256"] and
             manifest["byte_count"] === manifest_ref["byte_count"],
         page = manifest["value"],
         ordinal = div(cursor, 128),
         true <-
           exact?(page, ~w(version kind recipe ordinal rows)) and page["version"] === 1 and
             page["kind"] === "generation_manifest" and
             page["recipe"] === "ipse.evidence.shared_directory.v1" and
             page["ordinal"] === ordinal and is_list(page["rows"]),
         {:ok, proof} <- authenticate_catalog_group(read, partition, catalog_sha256, cursor),
         groups = div(proof.catalog_source_count + 7, 8),
         true <- length(page["rows"]) === min(16, groups - ordinal * 16),
         row = Enum.at(page["rows"], div(cursor, 8) - ordinal * 16),
         true <-
           exact?(row, ~w(cursor sources header)) and row["cursor"] === cursor and
             row["sources"] ===
               Enum.map(proof.catalog_rows, &[&1["source_key"], &1["head_sha256"]]),
         ref = row["header"],
         true <-
           exact?(ref, ~w(key sha256 byte_count)) and J.sha256?(ref["sha256"]) and
             ref["key"] === "gengrp.#{partition}." <> ref["sha256"] and
             is_integer(ref["byte_count"]) and ref["byte_count"] in 2..49_152,
         {:ok, header} when is_map(header) <- DocumentStage.read_value(read, ref["key"]),
         true <-
           header["sha256"] === ref["sha256"] and header["byte_count"] === ref["byte_count"] and
             is_map(header["value"]) and header["value"]["kind"] === "shared_projection_group" and
             header["value"]["cursor"] === cursor and
             header["value"]["sources"] === length(proof.catalog_rows) do
      {:ok,
       proof
       |> Map.put(:header, header["value"])
       |> Map.update!(:reads, &(&1 + 2))
       |> Map.update!(:logical_bytes, &(&1 + manifest["byte_count"] + header["byte_count"]))}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_manifest_group(_, _, _, _, _), do: @error

  @doc "Bind staged final selection to its current Job, catalog, root and manifests; grants no publication authority."
  def authenticate_selection_commit(read, witness, request, owner, now)
      when is_function(read, 1) do
    with true <-
           is_map(witness) and is_map(witness["root"]) and
             witness["root"]["generation"] === request["generation"],
         true <- request["op"] === "commit" and length(request["stages"]) === 3,
         {:ok, values} <- DocumentStage.prepared_values(read, request, owner, now),
         [job_stage] <- Enum.filter(values, &String.starts_with?(&1["key"], "genjob.")),
         ["genjob", partition] <- String.split(job_stage["key"], "."),
         true <- partition?(partition),
         [catalog_stage] <- Enum.filter(values, &(&1["key"] === "catalog." <> partition)),
         [root_stage] <- Enum.filter(values, &(&1["key"] === "generation." <> partition)),
         {:ok, catalog} when is_map(catalog) <-
           DocumentStage.read_value(read, "catalog." <> partition),
         true <-
           catalog_stage["value"] === catalog["value"] and
             catalog_stage["expected_revision"] === catalog["revision"],
         {:ok, old_row} when is_map(old_row) <-
           DocumentStage.read_value(read, "genjob." <> partition),
         old = old_row["value"],
         new = job_stage["value"],
         true <-
           is_map(old) and job_version(old) in [2, 3] and
             job_epoch(old) === Map.get(request, "maintenance_epoch", 0) and
             old["kind"] === "shared_generation_job" and
             old["partition"] === partition and old["status"] === "reducing" and
             old["catalog_sha256"] === catalog["sha256"] and old["catalog"] === catalog["value"] and
             is_map(old["reduction"]) and old["reduction"]["phase"] === "select" and
             new ===
               old |> Map.put("status", "selected") |> put_in(["reduction", "phase"], "selected"),
         {:ok, previous} <- DocumentStage.read_value(read, "generation." <> partition),
         true <-
           stamp(previous) === %{revision: old["root_revision"], sha256: old["root_sha256"]},
         root = root_stage["value"],
         reduction = old["reduction"],
         cat = catalog["value"],
         root_keys =
           ~w(version kind recipe partition generation catalog_sha256 catalog_generation floor sources extracted_bytes chunks vectors facts entities groups vector_selection fact_selection source_heads_sha256 manifests entity_pages),
         root_keys =
           root_keys ++
             if(job_version(old) === 3,
               do: ~w(entity_pages_sha256 entity_page_rows),
               else: ~w(entity_rows_sha256)
             ),
         true <-
           exact?(root, root_keys) and root["version"] === job_version(old) - 1 and
             root["kind"] === "shared_generation_directory" and root["partition"] === partition and
             root["recipe"] === "ipse.evidence.shared_directory.v#{root["version"]}" and
             root["generation"] === old["generation"] and
             root["catalog_sha256"] === catalog["sha256"] and
             root["catalog_generation"] === cat["generation"] and root["floor"] === cat["floor"] and
             root["sources"] === cat["sources"] and is_integer(root["sources"]) and
             root["sources"] in 1..1000 and
             root["extracted_bytes"] === cat["extracted_bytes"] and
             root["chunks"] === cat["chunks"] and
             root["vectors"] === cat["chunks"] and
             root["groups"] === div(root["sources"] + 7, 8) and
             root["vector_selection"] === old["vector_selection"] and
             root["fact_selection"] === old["fact_selection"] and
             root["manifests"] === reduction["manifests"] and
             root["entity_pages"] === reduction["entity_pages"] and
             root["source_heads_sha256"] === reduction["heads_sha256"] and
             root["facts"] === reduction["facts"] and root["entities"] === reduction["entities"] and
             if(job_version(old) === 3,
               do:
                 root["entity_page_rows"] === 32 and
                   root["entity_pages_sha256"] === reduction["entity_pages_sha256"],
               else: root["entity_rows_sha256"] === reduction["entities_sha256"]
             ),
         manifests = root["manifests"],
         true <-
           is_list(manifests) and length(manifests) === div(root["groups"] + 15, 16) and
             Enum.all?(manifests, fn ref ->
               exact?(ref, ~w(key sha256 byte_count)) and J.sha256?(ref["sha256"]) and
                 ref["key"] === "genman.#{partition}." <> ref["sha256"] and
                 is_integer(ref["byte_count"]) and ref["byte_count"] in 2..49_152
             end) and length(Enum.uniq_by(manifests, & &1["key"])) === length(manifests) do
      {:ok,
       %{
         generation: request["generation"],
         partition: partition,
         catalog_sha256: catalog["sha256"],
         source_count: root["sources"],
         manifests: manifests,
         source_heads_sha256: root["source_heads_sha256"],
         vector_selection: root["vector_selection"],
         fact_selection: root["fact_selection"],
         publish_before_ms: Enum.min(Enum.map(values, & &1["expires_at_ms"]))
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_selection_commit(_, _, _, _, _), do: @error

  @doc "Check every manifest group against one unchanged native generation; grants no publication authority."
  def authenticate_selection_sources(root, namespace, proof) do
    authenticate_selection_sources_with(proof, fn callback ->
      Ipse.Extension.Collection.with_document_read(root, namespace, callback)
    end)
  end

  @doc false
  def authenticate_selection_sources_with(proof, read_snapshot)
      when is_map(proof) and is_function(read_snapshot, 1) do
    with true <-
           partition?(proof[:partition]) and J.sha256?(proof[:catalog_sha256]) and
             J.sha256?(proof[:source_heads_sha256]) and J.safe_uint?(proof[:generation]) and
             is_integer(proof[:source_count]) and proof[:source_count] in 1..1000 and
             is_list(proof[:manifests]) and J.safe_uint?(proof[:publish_before_ms]),
         groups = div(proof.source_count + 7, 8),
         true <- length(proof.manifests) === div(groups + 15, 16),
         {:ok, result} <-
           Enum.reduce_while(
             0..(groups - 1),
             {:ok, %{rows: [], sources: [], reads: 0, bytes: 0}},
             fn ordinal, {:ok, acc} ->
               ref = Enum.at(proof.manifests, div(ordinal, 16))

               result =
                 read_snapshot.(fn witness, read ->
                   with true <- witness["root"]["generation"] === proof.generation,
                        {:ok, group} <-
                          authenticate_manifest_group(
                            read,
                            proof.partition,
                            proof.catalog_sha256,
                            ref,
                            ordinal * 8
                          ),
                        true <-
                          group.header["vector_selection"] === proof.vector_selection and
                            group.header["fact_selection"] === proof.fact_selection and
                            current?(group, System.system_time(:millisecond)) do
                     {:ok, group}
                   else
                     _ -> @error
                   end
                 end)

               case result do
                 {:ok, group} ->
                   {:cont,
                    {:ok,
                     %{
                       rows: acc.rows ++ group.catalog_rows,
                       sources: acc.sources ++ group.sources,
                       reads: acc.reads + group.reads,
                       bytes: acc.bytes + group.bundle_bytes
                     }}}

                 _ ->
                   {:halt, @error}
               end
             end
           ),
         true <-
           length(result.rows) === proof.source_count and
             length(result.sources) === proof.source_count and
             length(Enum.uniq_by(result.rows, & &1["source_key"])) === proof.source_count and
             J.sha256(json(%{"rows" => result.rows})) === proof.source_heads_sha256,
         now = System.system_time(:millisecond),
         true <- Enum.all?(Enum.chunk_every(result.sources, 8), &current?(%{sources: &1}, now)),
         deadlines = [proof.publish_before_ms | Enum.map(result.sources, & &1["expires_at_ms"])],
         deadline = deadlines |> Enum.reject(&is_nil/1) |> Enum.min(),
         true <- now < deadline do
      {:ok,
       %{
         generation: proof.generation,
         publish_before_ms: deadline,
         observed_after_ms: result.sources |> Enum.map(& &1["observed_at_ms"]) |> Enum.max(),
         sources: proof.source_count,
         groups: groups,
         reads: result.reads,
         bundle_bytes: result.bytes
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_selection_sources_with(_, _), do: @error

  @doc "Bind a staged group Job advance to its exact current catalog and sources; not a live write grant."
  def authenticate_group_commit(read, witness, request, owner, now) when is_function(read, 1) do
    with true <-
           is_map(witness) and is_map(witness["root"]) and
             witness["root"]["generation"] === request["generation"],
         true <- request["op"] === "commit" and length(request["stages"]) === 2,
         {:ok, values} <- DocumentStage.prepared_values(read, request, owner, now),
         [job_stage] <- Enum.filter(values, &String.starts_with?(&1["key"], "genjob.")),
         ["genjob", partition] <- String.split(job_stage["key"], "."),
         true <- partition?(partition),
         [catalog_stage] <- Enum.filter(values, &(&1["key"] === "catalog." <> partition)),
         {:ok, catalog} when is_map(catalog) <-
           DocumentStage.read_value(read, "catalog." <> partition),
         true <-
           catalog_stage["value"] === catalog["value"] and
             catalog_stage["expected_revision"] === catalog["revision"],
         {:ok, old_row} when is_map(old_row) <-
           DocumentStage.read_value(read, "genjob." <> partition),
         old = old_row["value"],
         new = job_stage["value"],
         true <-
           is_map(old) and is_map(new) and job_version(old) in [1, 2, 3] and
             job_version(new) === job_version(old) and
             job_epoch(old) === Map.get(request, "maintenance_epoch", 0) and
             old["kind"] === "shared_generation_job" and old["partition"] === partition and
             old["status"] === "groups" and old["catalog_sha256"] === catalog["sha256"] and
             old["catalog"] === catalog["value"] and id?(old["id"]),
         true <-
           Map.drop(old, ~w(status cursor summaries facts)) ===
             Map.drop(new, ~w(status cursor summaries facts)),
         true <-
           is_list(old["summaries"]) and length(old["summaries"]) <= 125 and
             is_list(new["summaries"]) and
             length(new["summaries"]) === length(old["summaries"]) + 1 and
             Enum.drop(new["summaries"], -1) === old["summaries"],
         ref = List.last(new["summaries"]),
         true <-
           exact?(ref, ~w(key sha256 byte_count)) and J.sha256?(ref["sha256"]) and
             ref["key"] === "gensum.#{partition}." <> ref["sha256"] and
             is_integer(ref["byte_count"]) and ref["byte_count"] in 2..49_152,
         {:ok, summary_row} when is_map(summary_row) <-
           DocumentStage.read_value(read, ref["key"]),
         true <-
           summary_row["sha256"] === ref["sha256"] and
             summary_row["byte_count"] === ref["byte_count"],
         summary = summary_row["value"],
         true <- exact?(summary, ~w(header ref sources entities)) and is_map(summary["header"]),
         header = summary["header"],
         true <-
           header["version"] === 1 and header["kind"] === "shared_projection_group" and
             header["cursor"] === old["cursor"] and
             header["vector_selection"] === old["vector_selection"] and
             header["fact_selection"] === old["fact_selection"] and
             is_integer(header["facts"]) and header["facts"] in 0..256 and
             is_list(summary["sources"]) and header["sources"] === length(summary["sources"]),
         header_ref = summary["ref"],
         true <-
           exact?(header_ref, ~w(key sha256 byte_count)) and J.sha256?(header_ref["sha256"]) and
             header_ref["key"] === "gengrp.#{partition}." <> header_ref["sha256"] and
             is_integer(header_ref["byte_count"]) and header_ref["byte_count"] in 2..49_152,
         {:ok, stored_header} when is_map(stored_header) <-
           DocumentStage.read_value(read, header_ref["key"]),
         true <-
           stored_header["sha256"] === header_ref["sha256"] and
             stored_header["byte_count"] === header_ref["byte_count"] and
             stored_header["value"] === header,
         true <-
           J.safe_uint?(old["cursor"]) and J.safe_uint?(old["facts"]) and
             new["cursor"] === old["cursor"] + length(summary["sources"]) and
             new["facts"] === old["facts"] + header["facts"] and
             new["status"] ===
               if(new["cursor"] === catalog["value"]["sources"], do: "manifests", else: "groups"),
         {:ok, root} <- DocumentStage.read_value(read, "generation." <> partition),
         true <- stamp(root) === %{revision: old["root_revision"], sha256: old["root_sha256"]},
         group = %{
           "partition" => partition,
           "catalog_sha256" => catalog["sha256"],
           "cursor" => old["cursor"],
           "sources" => summary["sources"]
         },
         {:ok, facts} <- authenticate_group_sources(read, group),
         true <- current?(facts, now) do
      deadlines =
        Enum.map(values, & &1["expires_at_ms"]) ++ Enum.map(facts.sources, & &1["expires_at_ms"])

      {:ok,
       %{
         generation: request["generation"],
         source: facts,
         publish_before_ms: deadlines |> Enum.reject(&is_nil/1) |> Enum.min()
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_group_commit(_, _, _, _, _), do: @error

  @doc "Authenticate one fixed fact-input slot against its current stored source, not a publication grant."
  def authenticate_fact_input(read, witness, request, now) when is_function(read, 1) do
    with true <-
           is_map(witness) and is_map(witness["root"]) and
             witness["root"]["generation"] === request["generation"],
         true <- DocumentStage.request?(request) and request["op"] === "value.put_inline",
         {:ok, slot} <- J.decode_unique(request["data"]),
         true <-
           exact?(slot, ~w(version kind draft_id source_key catalog_sha256 manifest page)) and
             slot["version"] === 1 and slot["kind"] === "explicit_fact_input_slot" and
             id?(slot["draft_id"]) and J.sha256?(slot["source_key"]) and
             J.sha256?(slot["catalog_sha256"]),
         page = slot["page"],
         manifest = slot["manifest"],
         true <-
           exact?(page, ~w(version kind source_bundle_sha256 ordinal rows)) and
             page["version"] === 1 and page["kind"] === "explicit_fact_input" and
             J.sha256?(page["source_bundle_sha256"]) and is_integer(page["ordinal"]) and
             page["ordinal"] in 0..7 and is_list(page["rows"]) and length(page["rows"]) in 1..32 and
             byte_size(json(page)) <= 7_000,
         true <-
           exact?(manifest, ~w(version source_bundle_sha256 row_count rows_sha256 page_sha256)) and
             manifest["version"] === 1 and
             manifest["source_bundle_sha256"] === page["source_bundle_sha256"] and
             is_integer(manifest["row_count"]) and manifest["row_count"] in 1..32 and
             J.sha256?(manifest["rows_sha256"]) and is_list(manifest["page_sha256"]) and
             length(manifest["page_sha256"]) in 1..8 and
             Enum.all?(manifest["page_sha256"], &J.sha256?/1) and
             Enum.at(manifest["page_sha256"], page["ordinal"]) === J.sha256(json(page)),
         ["factdraft", partition, ordinal] <- String.split(request["key"], "."),
         true <- partition?(partition) and ordinal === Integer.to_string(page["ordinal"]),
         {:ok, old} <- DocumentStage.read_value(read, request["key"]),
         true <- if(is_nil(old), do: 0, else: old["revision"]) === request["expected_revision"],
         {:ok, catalog} when is_map(catalog) <-
           DocumentStage.read_value(read, "catalog." <> partition),
         true <- catalog["sha256"] === slot["catalog_sha256"],
         {:ok, head} when is_map(head) <-
           DocumentStage.read_value(read, "source.#{partition}.#{slot["source_key"]}"),
         target = %{
           "partition" => partition,
           "source_key" => slot["source_key"],
           "catalog_sha256" => catalog["sha256"],
           "head_revision" => head["revision"],
           "head_sha256" => head["sha256"],
           "source_bundle_sha256" => page["source_bundle_sha256"]
         },
         {:ok, facts} <- authenticate_projection_source(read, target),
         true <- current?(facts, now) do
      {:ok,
       %{
         generation: request["generation"],
         source: facts,
         publish_before_ms: hd(facts.sources)["expires_at_ms"]
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_fact_input(_, _, _, _), do: @error

  @doc "Bind a sealed explicit fact projection and catalog to their stored source; not a live write grant."
  def authenticate_projection_commit(read, witness, request, owner, now)
      when is_function(read, 1) do
    with true <-
           is_map(witness) and is_map(witness["root"]) and
             witness["root"]["generation"] === request["generation"],
         true <- request["op"] === "commit" and length(request["stages"]) === 2,
         {:ok, values} <- DocumentStage.prepared_values(read, request, owner, now),
         [projection] <- Enum.filter(values, &String.starts_with?(&1["key"], "facts.")),
         root = projection["value"],
         true <-
           exact?(
             root,
             ~w(version kind recipe revision source_key source_generation content_sha256 source_bundle_sha256 selection catalog_sha256 catalog_generation floor pages facts entities)
           ),
         true <-
           root["version"] === 1 and root["kind"] === "fact_projection" and
             root["recipe"] === "ipse.evidence.fact_spans.v1" and
             root["selection"] === %{"kind" => "explicit", "profile" => nil, "version" => 1},
         [_, partition, source_key] <- String.split(projection["key"], "."),
         true <-
           partition?(partition) and J.sha256?(source_key) and root["source_key"] === source_key,
         {:ok, previous} <- DocumentStage.read_value(read, projection["key"]),
         previous_revision = if(is_nil(previous), do: 0, else: previous["value"]["revision"]),
         true <- J.safe_uint?(previous_revision) and root["revision"] === previous_revision + 1,
         [catalog_stage] <- Enum.filter(values, &(&1["key"] === "catalog." <> partition)),
         {:ok, catalog} when is_map(catalog) <-
           DocumentStage.read_value(read, "catalog." <> partition),
         true <-
           catalog_stage["value"] === catalog["value"] and
             catalog_stage["expected_revision"] === catalog["revision"] and
             root["catalog_sha256"] === catalog["sha256"] and
             root["catalog_generation"] === catalog["value"]["generation"] and
             root["floor"] === catalog["value"]["floor"],
         {:ok, head} when is_map(head) <-
           DocumentStage.read_value(read, "source.#{partition}.#{source_key}"),
         target = %{
           "partition" => partition,
           "source_key" => source_key,
           "catalog_sha256" => root["catalog_sha256"],
           "head_revision" => head["revision"],
           "head_sha256" => head["sha256"],
           "source_bundle_sha256" => root["source_bundle_sha256"]
         },
         {:ok, facts} <- authenticate_projection_source(read, target),
         true <-
           root["source_generation"] === facts.source_generation and
             root["content_sha256"] === facts.content_sha256,
         true <- projection_pages?(read, root, partition),
         true <- current?(facts, now) do
      deadlines =
        Enum.map(values, & &1["expires_at_ms"]) ++ Enum.map(facts.sources, & &1["expires_at_ms"])

      {:ok,
       %{
         generation: request["generation"],
         source: facts,
         publish_before_ms: deadlines |> Enum.reject(&is_nil/1) |> Enum.min()
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def authenticate_projection_commit(_, _, _, _, _), do: @error

  defp projection_pages?(read, root, partition) do
    facts = root["facts"]
    pages = root["pages"]
    entities = root["entities"]

    is_integer(facts) and facts in 0..32 and is_list(pages) and length(pages) <= facts and
      is_list(entities) and length(entities) <= 64 and Enum.all?(entities, &J.sha256?/1) and
      length(Enum.uniq(entities)) === length(entities) and
      ((facts === 0 and pages === [] and entities === []) or
         (facts > 0 and pages != [] and entities != [])) and
      Enum.all?(pages, fn ref ->
        exact?(ref, ~w(key sha256 byte_count)) and J.sha256?(ref["sha256"]) and
          ref["key"] === "factp.#{partition}." <> ref["sha256"] and
          is_integer(ref["byte_count"]) and ref["byte_count"] in 2..49_152 and
          case DocumentStage.read_value(read, ref["key"]) do
            {:ok, row} when is_map(row) ->
              row["sha256"] === ref["sha256"] and row["byte_count"] === ref["byte_count"]

            _ ->
              false
          end
      end)
  end

  @doc "Sample host UTC after all blocking validation; equality at expiry refuses."
  def current?(%{sources: sources}, now) do
    J.safe_uint?(now) and is_list(sources) and length(sources) in 1..8 and
      Enum.all?(sources, fn s ->
        exact?(s, ~w(observed_at_ms expires_at_ms historical)) and
          J.safe_uint?(s["observed_at_ms"]) and s["observed_at_ms"] <= now and
          s["historical"] === false and
          (is_nil(s["expires_at_ms"]) or
             (J.safe_uint?(s["expires_at_ms"]) and now < s["expires_at_ms"]))
      end)
  rescue
    _ -> false
  end

  def current?(_, _), do: false

  defp load!(read, key, state) do
    true = state.reads < @max_reads
    {:ok, row} = DocumentStage.read_value(read, key)
    bytes = if row, do: row["byte_count"], else: 0
    true = J.safe_uint?(bytes) and state.logical_bytes + bytes <= @max_logical_bytes
    {row, %{state | reads: state.reads + 1, logical_bytes: state.logical_bytes + bytes}}
  end

  defp claim?(c, selection) do
    exact?(c, @claim) and c["version"] === 3 and
      c["kind"] == "shared_projection_producer" and
      c["recipe"] == "ipse.evidence.shared_producer.first_page.v3" and
      is_binary(c["partition"]) and
      Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, c["partition"]) and id?(c["job_id"]) and
      Enum.all?(~w(job_revision catalog_floor root_revision cursor), &J.safe_uint?(c[&1])) and
      positive?(c["job_revision"]) and rem(c["cursor"], 8) == 0 and
      J.sha256?(c["catalog_sha256"]) and J.sha256?(c["source_set_sha256"]) and
      (is_nil(c["root_sha256"]) or J.sha256?(c["root_sha256"])) and
      selection?(selection) and c["vector_selection"] === selection and
      c["status"] == "pending" and is_nil(c["page"]) and c["receipts"] === [] and
      is_list(c["source_bindings"]) and length(c["source_bindings"]) in 1..8 and
      Enum.all?(c["source_bindings"], &binding?/1) and
      is_list(c["inputs"]) and length(c["inputs"]) in 1..8 and
      byte_size(json(c)) <= 8192
  end

  defp claim_for_guard?(claim, %{"version" => 1} = guard, selection),
    do: claim?(claim, selection) and guard["claim_key"] === "genproducer." <> claim["partition"]

  defp claim_for_guard?(claim, %{"version" => 2} = guard, selection),
    do: pending?(claim, guard["claim_key"]) and claim["vector_selection"] === selection

  @doc "Check only the closed v4 pending shape and slot relation; this grants no use authority."
  def pending?(c, key) do
    exact?(c, @claim_v4) and common_v4?(c, key) and c["status"] === "pending" and
      is_nil(c["page"]) and c["receipts"] === [] and
      is_list(c["source_bindings"]) and length(c["source_bindings"]) in 1..8 and
      Enum.all?(c["source_bindings"], &binding?/1) and
      is_list(c["inputs"]) and length(c["inputs"]) === input_count(c) and
      Enum.all?(c["inputs"], &input_ref?(&1, length(c["source_bindings"]))) and
      byte_size(json(c)) <= 8192
  rescue
    _ -> false
  end

  @doc "Check only the closed v4 ready shape; membership in a terminal group is separate."
  def ready?(c, key) do
    exact?(c, @ready_v4) and common_v4?(c, key) and c["status"] === "ready" and
      c["input_count"] === input_count(c) and J.sha256?(c["input_refs_sha256"]) and
      claim_stamp?(c["claim"]) and page_stamp?(c["page"], c["partition"]) and
      is_list(c["receipts"]) and length(c["receipts"]) === div(c["input_count"] + 1, 2) and
      Enum.all?(c["receipts"], &receipt?/1) and
      length(Enum.uniq_by(c["receipts"], & &1["operation_id"])) === length(c["receipts"]) and
      Enum.sum(Enum.map(c["receipts"], &length(&1["input_sha256"]))) === c["input_count"] and
      Enum.all?(Enum.drop(c["receipts"], -1), &(length(&1["input_sha256"]) === 2)) and
      byte_size(json(c)) <= 8192
  rescue
    _ -> false
  end

  defp claim_stamp?(claim),
    do:
      exact?(claim, ~w(revision sha256 operation_id)) and positive?(claim["revision"]) and
        J.sha256?(claim["sha256"]) and id?(claim["operation_id"])

  defp page_stamp?(page, partition),
    do:
      exact?(page, ~w(key sha256 byte_count)) and J.sha256?(page["sha256"]) and
        page["key"] === "genvec.#{partition}." <> page["sha256"] and
        is_integer(page["byte_count"]) and page["byte_count"] in 2..49_152

  defp receipt?(receipt) do
    exact?(receipt, ~w(operation_id source_sha256 input_sha256 raw_input_sha256)) and
      id?(receipt["operation_id"]) and J.sha256?(receipt["source_sha256"]) and
      is_list(receipt["input_sha256"]) and length(receipt["input_sha256"]) in 1..2 and
      is_list(receipt["raw_input_sha256"]) and
      length(receipt["raw_input_sha256"]) === length(receipt["input_sha256"]) and
      Enum.all?(receipt["input_sha256"] ++ receipt["raw_input_sha256"], &J.sha256?/1)
  end

  defp common_v4?(c, key) do
    c["version"] === 4 and c["kind"] === "shared_projection_producer" and
      c["recipe"] === "ipse.evidence.shared_producer.pages.v4" and
      partition?(c["partition"]) and id?(c["job_id"]) and
      positive?(c["job_revision"]) and
      Enum.all?(~w(catalog_floor root_revision), &J.safe_uint?(c[&1])) and
      is_integer(c["cursor"]) and c["cursor"] in 0..992 and rem(c["cursor"], 8) === 0 and
      is_integer(c["vector_count"]) and c["vector_count"] in 1..256 and
      is_integer(c["vector_cursor"]) and c["vector_cursor"] in 0..248 and
      rem(c["vector_cursor"], 8) === 0 and c["vector_cursor"] < c["vector_count"] and
      key === "genproducer4.#{c["partition"]}.#{div(c["vector_cursor"], 8)}" and
      previous_ready?(c) and
      Enum.all?(~w(catalog_sha256 source_set_sha256), &J.sha256?(c[&1])) and
      ((c["root_revision"] === 0 and is_nil(c["root_sha256"])) or
         (positive?(c["root_revision"]) and J.sha256?(c["root_sha256"]))) and
      selection?(c["vector_selection"]) and byte_size(c["vector_selection"]["model"]) <= 128 and
      extraction?(c["fact_selection"]) and
      is_binary(c["embedding"]) and String.valid?(c["embedding"]) and
      byte_size(c["embedding"]) in 1..64
  end

  defp previous_ready?(%{"vector_cursor" => 0, "previous_ready" => nil}), do: true

  defp previous_ready?(c) do
    previous = c["previous_ready"]

    c["vector_cursor"] > 0 and exact?(previous, ~w(key revision sha256 byte_count)) and
      previous["key"] === "genproducer4.#{c["partition"]}.#{div(c["vector_cursor"], 8) - 1}" and
      positive?(previous["revision"]) and J.sha256?(previous["sha256"]) and
      is_integer(previous["byte_count"]) and previous["byte_count"] in 1..8192
  end

  defp input_count(c), do: min(8, c["vector_count"] - c["vector_cursor"])

  defp input_ref?([si, ci, chunk, canonical, raw, start, finish], count) do
    is_integer(si) and si >= 0 and si < count and is_integer(ci) and ci in 0..31 and
      Enum.all?([chunk, canonical, raw], &J.sha256?/1) and J.safe_uint?(start) and
      J.safe_uint?(finish) and start < finish and finish <= 65_536 and finish - start <= 4096
  end

  defp input_ref?(_, _), do: false

  defp partition?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,15}\z/, value)

  defp v4_key?(value),
    do:
      is_binary(value) and
        Regex.match?(
          ~r/\Agenproducer4\.[a-z][a-z0-9_-]{0,15}\.(?:0|[1-9]|[12][0-9]|3[01])\z/,
          value
        )

  defp extraction?(value) do
    exact?(value, ~w(kind profile version)) and value["version"] === 1 and
      value["kind"] in ~w(explicit model_complete) and
      (is_nil(value["profile"]) or
         (is_binary(value["profile"]) and String.valid?(value["profile"]) and
            byte_size(value["profile"]) <= 128))
  end

  defp selection?(s),
    do:
      exact?(s, ~w(profile model dimensions encoding selection_sha256)) and
        is_binary(s["profile"]) and byte_size(s["profile"]) in 1..64 and
        is_binary(s["model"]) and byte_size(s["model"]) in 1..256 and
        s["dimensions"] === 1024 and s["encoding"] == "float32le" and
        J.sha256?(s["selection_sha256"])

  defp binding?(b),
    do:
      exact?(b, @binding) and positive?(b["head_revision"]) and
        Enum.all?(~w(source_key head_sha256 bundle_sha256 chunking_sha256), &J.sha256?(b[&1])) and
        J.safe_uint?(b["observed_at_ms"]) and
        (is_nil(b["expires_at_ms"]) or J.safe_uint?(b["expires_at_ms"])) and
        b["historical"] === false

  defp anchors?(c, catalog_row, root, job_row, epoch) do
    catalog = catalog_row["value"]
    job = job_row["value"]

    catalog["version"] === 1 and catalog["kind"] == "catalog" and
      catalog["partition"] === c["partition"] and
      catalog_row["sha256"] === c["catalog_sha256"] and
      catalog["floor"] === c["catalog_floor"] and
      is_integer(catalog["sources"]) and catalog["sources"] in 1..1000 and
      c["cursor"] < catalog["sources"] and
      stamp(root) === %{revision: c["root_revision"], sha256: c["root_sha256"]} and
      job_row["revision"] === c["job_revision"] and job_version(job) in [1, 2, 3] and
      job_epoch(job) === epoch and
      job["kind"] == "shared_generation_job" and job["status"] == "groups" and
      job["partition"] === c["partition"] and job["id"] === c["job_id"] and
      job["catalog"] === catalog and
      Map.take(
        job,
        ~w(catalog_sha256 root_revision root_sha256 cursor vector_selection fact_selection)
      ) ===
        Map.take(
          c,
          ~w(catalog_sha256 root_revision root_sha256 cursor vector_selection fact_selection)
        )
  end

  defp page?(row, page_no, catalog, partition) do
    ref = Enum.at(catalog["pages"], page_no)
    page = row["value"]

    exact?(ref, ~w(key sha256)) and ref["key"] == "catalog.#{partition}.#{page_no}" and
      ref["sha256"] === row["sha256"] and
      exact?(page, ~w(version kind partition ordinal rows)) and page["version"] === 1 and
      page["kind"] == "catalog_page" and page["partition"] === partition and
      page["ordinal"] === page_no and is_list(page["rows"]) and length(page["rows"]) in 1..16 and
      Enum.all?(page["rows"], fn r ->
        exact?(r, ~w(source_key head_sha256)) and
          J.sha256?(r["source_key"]) and J.sha256?(r["head_sha256"])
      end) and
      page["rows"] ===
        Enum.sort_by(Enum.uniq_by(page["rows"], & &1["source_key"]), & &1["source_key"])
  end

  defp sources!(read, claim, rows, state) do
    Enum.zip(claim["source_bindings"], rows)
    |> Enum.map_reduce(state, fn {binding, row}, state ->
      key = binding["source_key"]
      true = row === Map.take(binding, ~w(source_key head_sha256))
      {head_row, state} = load!(read, "source.#{claim["partition"]}.#{key}", state)
      true = head_row["revision"] === binding["head_revision"]
      true = head_row["sha256"] === binding["head_sha256"]
      head = head_row["value"]
      true = head?(head, key, div(claim["cursor"], 16))
      true = head["bundle_sha256"] === binding["bundle_sha256"]
      {bytes, state} = bundle!(read, claim["partition"], head, state)
      {:ok, source} = J.decode_unique(bytes)
      source = source!(source, claim["partition"], head)
      true = binding["observed_at_ms"] === source["observed_at_ms"]
      true = binding["expires_at_ms"] === source["expires_at_ms"]
      true = binding["historical"] === source["origin"]["historical"]
      true = binding["chunking_sha256"] === J.sha256(json(Map.take(source, ~w(version chunking))))

      {Map.merge(source, %{
         "historical" => source["origin"]["historical"],
         "chunks" => head["chunks"],
         "head_ordinal" => head["ordinal"]
       }), state}
    end)
  end

  defp head?(h, key, page) do
    fields =
      ~w(version kind source_key generation revision ordinal text_bytes chunks byte_count bundle_sha256 blocks)

    ((exact?(h, fields) and h["version"] === 1) or
       (exact?(h, fields ++ ["lexical"]) and h["version"] === 2)) and
      h["kind"] == "source_head" and h["source_key"] === key and
      is_integer(h["ordinal"]) and h["ordinal"] in 0..999 and div(h["ordinal"], 16) === page and
      positive?(h["generation"]) and positive?(h["revision"]) and
      is_integer(h["text_bytes"]) and h["text_bytes"] in 1..65_536 and
      is_integer(h["chunks"]) and h["chunks"] in 1..32 and
      is_integer(h["byte_count"]) and h["byte_count"] in 1..@max_bundle_bytes and
      J.sha256?(h["bundle_sha256"]) and is_list(h["blocks"]) and length(h["blocks"]) in 1..32
  end

  defp bundle!(read, partition, head, state) do
    {pieces, {state, _source_bytes}} =
      head["blocks"]
      |> Enum.with_index()
      |> Enum.map_reduce({state, 0}, fn {ref, ordinal}, {state, source_bytes} ->
        true = exact?(ref, ~w(key sha256)) and J.sha256?(ref["sha256"])
        true = ref["key"] === "data.#{partition}." <> ref["sha256"]
        {row, state} = load!(read, ref["key"], state)
        true = row["sha256"] === ref["sha256"]
        block = row["value"]

        true =
          (exact?(block, ~w(version kind pieces)) and block["version"] === 1) or
            (exact?(block, ~w(version kind pieces bundle_sha256 ordinal)) and
               block["version"] === 2 and block["bundle_sha256"] === head["bundle_sha256"] and
               block["ordinal"] === ordinal)

        true = block["kind"] == "source_data" and is_list(block["pieces"])
        true = length(block["pieces"]) in 1..12

        true =
          Enum.all?(
            block["pieces"],
            &(is_binary(&1) and String.valid?(&1) and byte_size(&1) <= 4096)
          )

        size = Enum.sum(Enum.map(block["pieces"], &byte_size/1))
        true = source_bytes + size <= head["byte_count"]
        true = source_bytes + size <= @max_bundle_bytes
        true = state.bundle_bytes + size <= 8 * @max_bundle_bytes
        bytes = IO.iodata_to_binary(block["pieces"])
        {bytes, {%{state | bundle_bytes: state.bundle_bytes + size}, source_bytes + size}}
      end)

    bytes = IO.iodata_to_binary(pieces)
    true = byte_size(bytes) === head["byte_count"] and byte_size(bytes) <= @max_bundle_bytes
    true = J.sha256(bytes) === head["bundle_sha256"]
    true = state.bundle_bytes <= 8 * @max_bundle_bytes
    {bytes, state}
  end

  defp source!(s, partition, head) do
    attrs = @source -- ~w(version source_key content_sha256)

    s =
      if exact?(s, attrs) or exact?(s, attrs ++ ["document"]) do
        Map.merge(s, %{
          "version" => if(Map.has_key?(s, "document"), do: 2, else: 1),
          "source_key" => J.sha256(s["source_id"]),
          "content_sha256" => J.sha256(s["text"])
        })
      else
        s
      end

    fields = if Map.has_key?(s, "document"), do: @source ++ ["document"], else: @source
    fields = if s["version"] === 3, do: fields ++ ["chunking"], else: fields
    true = exact?(s, fields) and s["version"] in [1, 2, 3]
    true = s["version"] !== 1 or not Map.has_key?(s, "document")
    true = s["version"] !== 2 or is_map(s["document"])
    true = not Map.has_key?(s, "document") or is_map(s["document"])
    true = s["version"] !== 3 or s["chunking"] === %{"version" => 2, "max_bytes" => 4096}
    true = is_binary(s["source_id"]) and byte_size(s["source_id"]) in 1..256
    true = not Regex.match?(~r/[\x00-\x1F\x7F]/u, s["source_id"])
    true = text?(s["title"], 128) and text?(s["uri"], 512)
    true = is_binary(s["text"]) and String.valid?(s["text"]) and byte_size(s["text"]) in 1..65_536
    true = s["source_key"] === J.sha256(s["source_id"]) and s["source_key"] === head["source_key"]
    true = s["content_sha256"] === J.sha256(s["text"])
    true = s["partition"] === partition and s["generation"] === head["generation"]
    true = byte_size(s["text"]) === head["text_bytes"]
    true = J.safe_uint?(s["observed_at_ms"])
    true = is_nil(s["event_at_ms"]) or J.safe_uint?(s["event_at_ms"])
    true = is_nil(s["expires_at_ms"]) or J.safe_uint?(s["expires_at_ms"])
    origin = s["origin"]
    true = exact?(origin, ~w(kind store_profile partition_or_scope receipt historical))
    true = origin["kind"] in ~w(provided fetch import) and is_boolean(origin["historical"])
    true = is_nil(origin["store_profile"]) or text?(origin["store_profile"], 256)
    true = is_nil(origin["partition_or_scope"]) or text?(origin["partition_or_scope"], 256)

    true =
      is_nil(origin["receipt"]) or
        (is_map(origin["receipt"]) and byte_size(json(origin["receipt"])) <= 8192)

    s
  end

  defp source_set?(claim, sources) do
    identities =
      Enum.map(sources, fn source ->
        source = Map.drop(source, ~w(historical chunks head_ordinal))
        [source["source_key"], J.sha256(json(source))]
      end)

    claim["source_set_sha256"] === J.sha256(json(%{"sources" => identities}))
  end

  defp input_refs?(claim, sources) do
    refs = claim["inputs"]

    spans = Enum.map(sources, &canonical_spans!/1)

    expected_positions =
      sources
      |> Enum.with_index()
      |> Enum.flat_map(fn {source, si} ->
        Enum.map(0..(source["chunks"] - 1), &[si, &1])
      end)
      |> then(fn positions ->
        if claim["version"] === 4 do
          true = length(positions) === claim["vector_count"]
          Enum.drop(positions, claim["vector_cursor"])
        else
          positions
        end
      end)
      |> Enum.take(8)

    true = Enum.map(refs, &Enum.take(&1, 2)) === expected_positions

    Enum.reduce(refs, %{}, fn [si, ci, chunk, canonical, raw, start, finish], previous ->
      source = Enum.at(sources, si)
      version = if source["version"] === 3, do: 2, else: 1
      true = J.safe_uint?(start) and J.safe_uint?(finish) and start < finish

      true =
        finish <= byte_size(source["text"]) and
          finish - start <= if(version == 2, do: 4096, else: 2048)

      true = start >= Map.get(previous, si, 0)
      true = Enum.at(Enum.at(spans, si), ci) === {start, finish}
      text = binary_part(source["text"], start, finish - start)
      true = String.valid?(text)

      true =
        chunk ===
          J.sha256(
            json([
              "ipse-knowledge",
              1,
              "chunk",
              [
                source["source_key"],
                source["generation"],
                source["content_sha256"],
                version,
                start,
                finish
              ]
            ])
          )

      true = canonical === J.digest([text]) and raw === J.sha256(text)
      Map.put(previous, si, finish)
    end)

    true
  end

  # Reproduce the closed byte-range recipe, including document segment breaks.
  # Receipt semantics and locator validity remain with the domain extension.
  defp canonical_spans!(source) do
    text = source["text"]
    receipt = get_in(source, ["origin", "receipt"])

    ranges =
      case receipt do
        %{"kind" => "document_extraction"} ->
          body = document_body!(receipt, source)
          segments = body["segments"]
          true = is_list(segments) and length(segments) in 1..32

          {ranges, offset} =
            Enum.map_reduce(segments, 0, fn segment, offset ->
              start = segment["start_byte"]
              finish = segment["end_byte"]

              true =
                J.safe_uint?(start) and J.safe_uint?(finish) and start === offset and
                  finish > start and finish <= byte_size(text)

              bytes = binary_part(text, start, finish - start)
              true = String.valid?(bytes) and J.sha256(bytes) === segment["text_sha256"]
              next = if finish == byte_size(text), do: finish, else: finish + 1
              true = next == finish or binary_part(text, finish, 1) == "\n"
              {{start, finish}, next}
            end)

          true = offset === byte_size(text)
          ranges

        _ ->
          [{0, byte_size(text)}]
      end

    max = if source["version"] === 3, do: 4096, else: 2048

    spans =
      Enum.flat_map(ranges, fn {start, finish} -> split_spans!(text, start, finish, max, []) end)

    true = length(spans) === source["chunks"]
    spans
  end

  defp document_body!(%{"version" => version} = receipt, _) when version in [1, 2], do: receipt

  defp document_body!(%{"version" => 3} = receipt, _) do
    bytes = receipt["document"]
    true = is_binary(bytes) and byte_size(bytes) <= 2048 and J.sha256(bytes) === receipt["sha256"]
    {:ok, body} = J.decode_unique(bytes)
    true = json(body) === bytes
    body
  end

  defp document_body!(%{"version" => 4} = receipt, source) do
    body = source["document"]
    true = is_map(body)

    body =
      if receipt["acquisition"],
        do: Map.put(body, "acquisition", receipt["acquisition"]),
        else: body

    bytes = json(body)

    true =
      byte_size(bytes) === receipt["manifest_bytes"] and
        J.sha256(bytes) === receipt["manifest_sha256"]

    true = is_list(body["segments"]) and length(body["segments"]) === receipt["segment_count"]
    body
  end

  defp split_spans!(_text, position, position, _max, acc), do: Enum.reverse(acc)

  defp split_spans!(text, start, finish, max, acc) do
    ending = utf8_end!(text, start, min(start + max, finish))
    true = ending > start
    split_spans!(text, ending, finish, max, [{start, ending} | acc])
  end

  defp utf8_end!(text, start, ending) do
    if String.valid?(binary_part(text, start, ending - start)),
      do: ending,
      else: utf8_end!(text, start, ending - 1)
  end

  defp input_matches?({[si, _ci, _chunk, canonical, raw, start, finish], text}, sources) do
    is_binary(text) and String.valid?(text) and
      text === binary_part(Enum.at(sources, si)["text"], start, finish - start) and
      J.sha256(text) === raw and J.digest([text]) === canonical
  end

  # Only logical schema dispatch is normalized. Stored maps and their hashes remain raw.
  defp job_version(%{"version" => version} = job) when version in [4, 5, 6] do
    base = version - 3
    fields = @job_fields ++ ["maintenance_epoch"] ++ if(base == 1, do: [], else: ["reduction"])

    reduction_fields =
      if base == 3,
        do:
          (@job_reduction -- ["entities_sha256"]) ++
            ~w(recipe entity_pages_sha256 digest_cursor verified_entities last_entity_id),
        else: @job_reduction

    if exact?(job, fields) and positive?(job["maintenance_epoch"]) and
         ((base == 1 and job["status"] in ~w(groups manifests aborted selected)) or
            (base in [2, 3] and job["status"] in ~w(reducing aborted selected) and
               exact?(job["reduction"], reduction_fields) and
               job["reduction"]["phase"] in ~w(manifests entities heads entity_digest select selected) and
               (base != 3 or job["reduction"]["recipe"] === "ipse.evidence.shared_directory.v2"))),
       do: base,
       else: nil
  end

  defp job_version(%{"version" => version}) when version in [1, 2, 3], do: version
  defp job_version(_), do: nil

  defp job_epoch(%{"version" => version} = job) when version in [4, 5, 6],
    do: job["maintenance_epoch"]

  defp job_epoch(_), do: 0

  defp stamp(nil), do: %{revision: 0, sha256: nil}
  defp stamp(row), do: %{revision: row["revision"], sha256: row["sha256"]}
  defp positive?(n), do: J.safe_uint?(n) and n > 0
  defp text?(s, max), do: is_binary(s) and String.valid?(s) and byte_size(s) <= max
  defp id?(s), do: is_binary(s) and Regex.match?(~r/\A[a-f0-9]{32}\z/, s)
  defp exact?(m, fields), do: is_map(m) and Enum.sort(Map.keys(m)) === Enum.sort(fields)
  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
end
