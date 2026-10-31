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
  def authenticate(read, guard, inputs, selection) when is_function(read, 1) do
    with true <- guard?(guard),
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
         true <- anchors?(claim, catalog_row, root_row, job_row),
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

  def authenticate(_, _, _, _), do: @error

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

  defp anchors?(c, catalog_row, root, job_row) do
    catalog = catalog_row["value"]
    job = job_row["value"]

    catalog["version"] === 1 and catalog["kind"] == "catalog" and
      catalog["partition"] === c["partition"] and
      catalog_row["sha256"] === c["catalog_sha256"] and
      catalog["floor"] === c["catalog_floor"] and
      is_integer(catalog["sources"]) and catalog["sources"] in 1..1000 and
      c["cursor"] < catalog["sources"] and
      stamp(root) === %{revision: c["root_revision"], sha256: c["root_sha256"]} and
      job_row["revision"] === c["job_revision"] and job["version"] in [1, 2, 3] and
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

    Enum.reduce(refs, %{}, fn [si, _ci, chunk, canonical, raw, start, finish], previous ->
      source = Enum.at(sources, si)
      version = if source["version"] === 3, do: 2, else: 1
      true = J.safe_uint?(start) and J.safe_uint?(finish) and start < finish

      true =
        finish <= byte_size(source["text"]) and
          finish - start <= if(version == 2, do: 4096, else: 2048)

      true = start >= Map.get(previous, si, 0)
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

  defp input_matches?({[si, _ci, _chunk, canonical, raw, start, finish], text}, sources) do
    is_binary(text) and String.valid?(text) and
      text === binary_part(Enum.at(sources, si)["text"], start, finish - start) and
      J.sha256(text) === raw and J.digest([text]) === canonical
  end

  defp stamp(nil), do: %{revision: 0, sha256: nil}
  defp stamp(row), do: %{revision: row["revision"], sha256: row["sha256"]}
  defp positive?(n), do: J.safe_uint?(n) and n > 0
  defp text?(s, max), do: is_binary(s) and String.valid?(s) and byte_size(s) <= max
  defp id?(s), do: is_binary(s) and Regex.match?(~r/\A[a-f0-9]{32}\z/, s)
  defp exact?(m, fields), do: is_map(m) and Enum.sort(Map.keys(m)) === Enum.sort(fields)
  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
end
