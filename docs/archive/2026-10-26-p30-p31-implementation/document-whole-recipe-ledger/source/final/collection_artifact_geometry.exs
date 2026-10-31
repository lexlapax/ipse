# Feasibility only: reconstruct byte-authenticated MODEL records, never native
# files, from original write hashes/boundaries and the pinned production encoder.
{opts, traces, []} =
  OptionParser.parse(System.argv(),
    strict: [artifact: :string, checkpoint: :string, summary: :string, out: :string]
  )

out = Path.expand(Keyword.fetch!(opts, :out))
true = String.starts_with?(out, Path.expand("_build") <> "/")
false = File.exists?(out)
File.mkdir_p!(out)
artifact = Path.expand(Keyword.fetch!(opts, :artifact))
manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))

for row <- manifest["files"] do
  bytes = File.read!(Path.join(artifact, row["path"]))
  true = Ipse.JSON.sha256(bytes) == row["sha256"] and byte_size(bytes) == row["bytes"]
end

for path <- Path.wildcard(Path.join(artifact, "ebin/*.beam")),
    do: {:module, _} = :code.load_abs(String.to_charlist(Path.rootname(path)))

Code.require_file("collection_recipe_model.ex", __DIR__)

defmodule Ipse.CollectionArtifactGeometry do
  alias Ipse.JSON, as: J
  alias Ipse.Extension.Collection.Migration
  alias IpseKnowledge.Evidence, as: E
  alias IpseKnowledge.Store.Collection.Generation, as: G

  def run(opts, traces, out) do
    model = :erlang.binary_to_term(File.read!(Keyword.fetch!(opts, :checkpoint)), [:safe])
    summary = Jason.decode!(File.read!(Keyword.fetch!(opts, :summary)))
    expected = Map.new(summary["final_store"]["record_descriptors"], &{&1["key"], &1})
    true = map_size(expected) == map_size(model.records)

    {hints, _} =
      Enum.reduce(traces, {%{}, %{}}, fn path, state ->
        File.stream!(path)
        |> Enum.reduce(state, fn line, state ->
          row = Jason.decode!(line)
          Enum.reduce(row["requests"], state, &hint/2)
        end)
      end)

    rows =
      model.records
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, row} ->
        body = json(row.value)
        sha = J.sha256(body)
        original = Map.fetch!(hints, {key, sha})
        true = byte_size(body) == original.bytes and sha == expected[key]["sha256"]
        true = byte_size(body) == expected[key]["logical_bytes"]

        parts =
          if original.parts == :inline,
            do: inline_parts(body),
            else: split_parts(body, original.parts)

        raw = packed(body, parts)
        true = byte_size(raw) == expected[key]["packed_bytes"]
        observed_physical = row[:record_sha256] || expected[key]["record_sha256"]
        true = is_nil(observed_physical) or observed_physical == J.sha256(raw)
        compressed = :zlib.compress(raw)
        true = inflate(compressed, byte_size(raw)) === raw

        %{
          key: key,
          logical_sha256: sha,
          logical_bytes: byte_size(body),
          part_lengths: Enum.map(parts, &byte_size/1),
          expected_physical_sha256: J.sha256(raw),
          physical_bytes: byte_size(raw),
          observed_physical_sha256: observed_physical,
          zlib_bytes: byte_size(compressed),
          payload_bytes: min(byte_size(raw), byte_size(compressed)),
          payload_sha256:
            J.sha256(if(byte_size(compressed) < byte_size(raw), do: compressed, else: raw)),
          codec: if(byte_size(compressed) < byte_size(raw), do: "zlib", else: "identity")
        }
      end)

    physical = Enum.uniq_by(rows, & &1.expected_physical_sha256)
    payloads = Enum.uniq_by(rows, & &1.payload_sha256)
    raw_bytes = Enum.sum(Enum.map(physical, & &1.physical_bytes))
    raw_alloc = Enum.sum(Enum.map(physical, &round4(&1.physical_bytes)))
    per_record_alloc = Enum.sum(Enum.map(payloads, &round4(&1.payload_bytes)))
    packs = pack_pages(rows)
    pack_alloc = Enum.sum(Enum.map(packs, &round4/1))
    poor = poor_group(model)
    random = :crypto.strong_rand_bytes(65_536)
    random_z = :zlib.compress(random)
    true = inflate(random_z, byte_size(random)) == random

    overflow_refused =
      try do
        inflate(:zlib.compress(String.duplicate("x", 100_000)), 65_536)
        false
      rescue
        ArgumentError -> true
      end

    true = overflow_refused

    result = %{
      version: 1,
      kind: "byte_authenticated_modeled_physical_record_compression",
      records: length(rows),
      unique_physical_objects: length(physical),
      observed_physical_hashes: Enum.count(rows, &(not is_nil(&1.observed_physical_sha256))),
      physical_bytes: raw_bytes,
      public_object_4096_rounding: raw_alloc,
      independent_zlib_bytes: Enum.sum(Enum.map(rows, & &1.zlib_bytes)),
      selected_identity_or_zlib_bytes: Enum.sum(Enum.map(payloads, & &1.payload_bytes)),
      per_record_payload_4096_rounding: per_record_alloc,
      proposed_one_MiB_pack_count: length(packs),
      proposed_pack_4096_rounding: pack_alloc,
      export_source_plus_per_record_payload: raw_alloc + per_record_alloc,
      export_source_plus_packed_payload: raw_alloc + pack_alloc,
      two_distinct_source_target_roots_plus_packed_payload: 2 * raw_alloc + pack_alloc,
      document_budget_bytes: 192 * 1024 * 1024,
      notes_reserved_bytes: 64 * 1024 * 1024,
      omitted_peak:
        "native metadata, artifact manifests/index/control, directory/lock allocation, old/staged pointer and file peaks, rollback/leases, cleanup and other retained data; no budget admission follows",
      provenance:
        "reconstructed model bytes matched original complete write SHA/count and original ordered part lengths; production Migration.encode used for packed wrapper; no native object files or artifact API executed",
      entropy:
        "supplied vectors repeat a short pattern and source paragraphs repeat a; favorable aggregate compression is not representative or a guaranteed ratio",
      poor_entropy_group: poor,
      arbitrary_binary_codec_control: %{
        raw_bytes: byte_size(random),
        zlib_bytes: byte_size(random_z),
        identity_or_zlib_bytes: min(byte_size(random), byte_size(random_z)),
        scope: "bounded codec expansion control only, not a semantic document/vector fixture"
      },
      bounded_inflate_overflow_refused: overflow_refused,
      representation:
        "proposed explicit identity-or-zlib per-record codec; no fallback after decode failure; 1MiB packs aligned to at-most8-record pages are sizing only, not an implemented artifact format"
    }

    File.write!(Path.join(out, "records.json"), Jason.encode!(rows), [:exclusive])
    File.write!(Path.join(out, "summary.json"), Jason.encode!(result, pretty: true), [:exclusive])
    IO.puts(Jason.encode!(result, pretty: true))
  end

  defp hint(%{"op" => op} = r, {done, pending})
       when op in ["value.put_inline", "value.prepare_inline"] do
    {Map.put(done, {r["key"], r["sha256"]}, %{bytes: r["byte_count"], parts: :inline}), pending}
  end

  defp hint(%{"op" => "value.write_parts"} = r, {done, pending}) do
    key = {r["key"], r["sha256"]}
    previous = if r["offset"] == 0, do: [], else: Map.fetch!(pending, key)
    true = Enum.sum(previous) == r["offset"]
    parts = previous ++ r["parts"]
    true = Enum.sum(parts) <= r["byte_count"]

    if Enum.sum(parts) == r["byte_count"],
      do: {Map.put(done, key, %{bytes: r["byte_count"], parts: parts}), Map.delete(pending, key)},
      else: {done, Map.put(pending, key, parts)}
  end

  defp hint(_, state), do: state
  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp inline_parts(""), do: []

  defp inline_parts(bytes) do
    part = inline_prefix(bytes, min(6144, byte_size(bytes)))
    [part | inline_parts(binary_part(bytes, byte_size(part), byte_size(bytes) - byte_size(part)))]
  end

  # Mirrors the pinned native inline adapter's private encoded-safe prefix;
  # reconstruction is additionally checked against original complete-byte hashes.
  defp inline_prefix(bytes, size) do
    part = binary_part(bytes, 0, size)

    if String.valid?(part) and byte_size(Jason.encode!(part)) <= 8192,
      do: part,
      else: inline_prefix(bytes, size - 1)
  end

  defp split_parts(bytes, sizes) do
    {parts, ""} =
      Enum.map_reduce(sizes, bytes, fn size, rest ->
        part = binary_part(rest, 0, size)
        true = String.valid?(part)
        {part, binary_part(rest, size, byte_size(rest) - size)}
      end)

    true = length(parts) in 1..10
    parts
  end

  defp packed(body, parts),
    do:
      Migration.encode(%{
        "version" => 1,
        "kind" => "document_value",
        "sha256" => J.sha256(body),
        "byte_count" => byte_size(body),
        "parts" => parts
      })

  defp inflate(bytes, maximum) do
    stream = :zlib.open()

    try do
      :ok = :zlib.inflateInit(stream)
      result = drain(stream, bytes, maximum, [], 0)
      :ok = :zlib.inflateEnd(stream)
      true = byte_size(result) == maximum
      result
    after
      :zlib.close(stream)
    end
  end

  defp drain(stream, input, maximum, acc, size) do
    {status, output} = :zlib.safeInflate(stream, input)
    size = size + IO.iodata_length(output)
    if size > maximum, do: raise(ArgumentError, "bounded inflate refused")

    case status do
      :continue -> drain(stream, <<>>, maximum, [output | acc], size)
      :finished -> IO.iodata_to_binary(Enum.reverse([output | acc]))
    end
  end

  defp pack_pages(rows) do
    pages =
      Enum.chunk_every(rows, 8)
      |> Enum.map(fn rows -> Enum.sum(Enum.map(rows, & &1.payload_bytes)) end)

    {sizes, last} =
      Enum.reduce(pages, {[], 0}, fn page, {sizes, current} ->
        true = page <= 8 * 65_536

        if current + page <= 1024 * 1024,
          do: {sizes, current + page},
          else: {[current | sizes], page}
      end)

    Enum.reverse([last | sizes])
  end

  defp round4(bytes), do: div(bytes + 4095, 4096) * 4096

  defp poor_group(model) do
    values = Map.new(model.records, fn {k, row} -> {k, row.value} end)
    root = values["generation.notes"]
    first = hd(values[hd(root["manifests"])["key"]]["rows"])
    header = values[first["header"]["key"]]

    bundles =
      Enum.map(header["source_keys"], fn key ->
        head = values["source.notes." <> key]

        bytes =
          Enum.map_join(head["blocks"], fn ref -> Enum.join(values[ref["key"]]["pieces"]) end)

        %{"source" => Jason.decode!(bytes), "head" => head}
      end)

    expected = Map.take(header, ~w(cursor vector_selection fact_selection))
    {:ok, supplied} = G.unpack_group("notes", header, values, bundles, expected)

    {supplied, _} =
      Enum.map_reduce(supplied, :rand.seed_s(:exsss, {31, 32, 33}), fn row, rng ->
        {vectors, rng} =
          Enum.map_reduce(row["vectors"], rng, fn vector, rng ->
            {coordinates, rng} =
              Enum.map_reduce(1..1024, rng, fn _, rng ->
                {v, rng} = :rand.uniform_s(rng)
                {2 * v - 1, rng}
              end)

            {:ok, new} =
              E.vector(
                Map.take(
                  vector,
                  ~w(chunk_id input_sha256 profile selection_sha256 model dimensions)
                )
                |> Map.put("values", coordinates)
              )

            {new, rng}
          end)

        {Map.put(row, "vectors", vectors), rng}
      end)

    {:ok, plan} =
      G.pack_group(
        "notes",
        header["cursor"],
        bundles,
        supplied,
        header["vector_selection"],
        header["fact_selection"]
      )

    pages =
      plan.values
      |> Enum.filter(&(&1.value["kind"] == "shared_vectors"))
      |> Enum.map(fn unit ->
        body = json(unit.value)

        parts =
          Stream.unfold(body, fn
            "" -> nil
            rest -> E.utf8_prefix(rest, 6144)
          end)
          |> Enum.to_list()

        raw = packed(body, parts)
        compressed = :zlib.compress(raw)
        true = inflate(compressed, byte_size(raw)) == raw
        %{raw_bytes: byte_size(raw), zlib_bytes: byte_size(compressed)}
      end)

    %{
      source_groups: 1,
      sources: length(bundles),
      vectors: Enum.sum(Enum.map(supplied, &length(&1["vectors"]))),
      dimensions: 1024,
      pages: length(pages),
      raw_bytes: Enum.sum(Enum.map(pages, & &1.raw_bytes)),
      zlib_bytes: Enum.sum(Enum.map(pages, & &1.zlib_bytes)),
      maximum_zlib_page: Enum.max(Enum.map(pages, & &1.zlib_bytes)),
      scope:
        "separate bounded canonical G.pack_group control with seeded finite uniform coordinates; not the retained recipe, inference or a worst-case ratio guarantee"
    }
  end
end

Ipse.CollectionArtifactGeometry.run(opts, traces, out)
