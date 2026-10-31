# Pure exact client/result-envelope controls, no Core/native dispatch.
import ExUnit.Assertions

prefix =
  File.read!("test/support/collection_directory.exs")
  |> String.split("# Pure protocol fixture:")
  |> hd()

{_, bindings} = Code.eval_string(prefix)
fetch = fn key -> Keyword.fetch!(bindings, key) end
alias IpseKnowledge.Evidence, as: E
alias IpseKnowledge.Store.Collection, as: C
alias IpseKnowledge.Store.Collection.Directory, as: D
alias IpseKnowledge.Store.Collection.Job
json = &IO.iodata_to_binary(JSON.encode!(&1))
profile = fetch.(:profile)

units =
  Enum.map(0..4999, fn n ->
    suffix = Integer.to_string(n) |> String.pad_leading(5, "0")
    label = String.duplicate("\\", 251) <> suffix
    [E.id("entity", ["notes", label]), label, [rem(n, 125)]]
  end)
  |> Enum.sort_by(&hd/1)
  |> Enum.chunk_every(64)
  |> Enum.with_index()
  |> Enum.map(fn {rows, n} ->
    D.immutable("notes", "genent", %{
      "version" => 1,
      "kind" => "generation_entities",
      "recipe" => "ipse.evidence.shared_directory.v1",
      "ordinal" => n,
      "rows" => rows
    })
  end)

# These label bytes are legal fact identifiers, not escaped control characters.
{_, sample} = hd(fetch.(:inputs))
fact = hd(sample["facts"])
label = units |> hd() |> Map.fetch!(:value) |> Map.fetch!("rows") |> hd() |> Enum.at(1)
assert {:ok, _} = E.fact(Map.drop(fact, ~w(version fact_id)) |> Map.put("subject", label))

# Exact longest-prefix rule of DocumentStage.slice:6144 original bytes and
# <=8192 JSON-encoded string bytes. ASCII fixture permits binary search.
piece = fn bytes ->
  search = fn search, low, high ->
    if low == high do
      binary_part(bytes, 0, low)
    else
      mid = div(low + high + 1, 2)

      if byte_size(json.(binary_part(bytes, 0, mid))) <= 8192,
        do: search.(search, mid, high),
        else: search.(search, low, mid - 1)
    end
  end

  search.(search, 0, min(byte_size(bytes), 6144))
end

reply = fn request, result ->
  {:ok, digest} = Ipse.Extension.canonical_digest([request])

  %{
    "status" => "ok",
    "value" => %{
      "version" => 1,
      "operation_id" => String.duplicate("a", 32),
      "request_sha256" => digest,
      "result" => result
    }
  }
end

marker = %{"version" => 2, "inline_bytes" => 8192, "write_parts" => 2}

read = fn read, result, records, calls ->
  case result do
    {:call, request, continuation} ->
      assert C.read_request?(request)
      r = request["request"]
      record = records[r["key"]]

      descriptor =
        if record,
          do: %{
            "revision" => 499,
            "sha256" => E.sha256(json.(record)),
            "byte_count" => byte_size(json.(record))
          }

      value =
        case r["op"] do
          "snapshot" ->
            %{"generation" => 500, "floor" => 0, "document_store" => marker}

          "value.stat" ->
            %{"generation" => 500, "key" => r["key"], "record" => descriptor}

          "value.read" ->
            bytes = json.(record)
            data = piece.(binary_part(bytes, r["offset"], byte_size(bytes) - r["offset"]))
            next = r["offset"] + byte_size(data)

            Map.merge(descriptor, %{
              "generation" => 500,
              "key" => r["key"],
              "offset" => r["offset"],
              "data" => data,
              "next" => if(next < byte_size(bytes), do: next)
            })
        end

      read.(read, C.resume(continuation, reply.(request, value)), records, calls + 1)

    terminal ->
      {terminal, calls}
  end
end

object_reads =
  Enum.map(units, fn u ->
    {{:done, {:ok, value}}, calls} =
      read.(
        read,
        C.start(profile, :object_read, Map.put(D.reference(u), "generation", 500)),
        %{u.key => u.value},
        0
      )

    assert value["value"] === u.value
    calls
  end)

# Actual client write frames and real closed result validators. Host effects
# are modeled; every returned frame is checked by the existing SDK grammar.
write = fn write, result, reconstructed, parts, frames, count ->
  case result do
    {:call, request, continuation} ->
      r = request["request"]
      frame = %{"api_version" => 1, "kind" => "host_call", "request" => request}
      assert Ipse.Extension.validate(frame) == :ok

      case r["op"] do
        "snapshot" ->
          write.(
            write,
            C.resume(
              continuation,
              reply.(request, %{"generation" => 500, "floor" => 0, "document_store" => marker})
            ),
            reconstructed,
            parts,
            frames,
            count
          )

        "stage.list" ->
          write.(
            write,
            C.resume(continuation, reply.(request, %{"generation" => 500, "stages" => []})),
            reconstructed,
            parts,
            frames,
            count
          )

        "value.stat" ->
          write.(
            write,
            C.resume(
              continuation,
              reply.(request, %{"generation" => 500, "key" => r["key"], "record" => nil})
            ),
            reconstructed,
            parts,
            frames,
            count
          )

        "value.write_parts" ->
          assert r["offset"] == byte_size(reconstructed)

          assert Enum.all?(
                   r["data"],
                   &(String.valid?(&1) and byte_size(&1) <= 6144)
                 )

          next = reconstructed <> Enum.join(r["data"])

          receipt =
            Map.take(r, ~w(slot epoch key expected_revision byte_count sha256 publish))
            |> Map.merge(%{
              "offset" => byte_size(next),
              "state" => if(byte_size(next) == r["byte_count"], do: "sealed", else: "open"),
              "expires_at_ms" => 2_000_000_000_000,
              "revision" => 0
            })

          value = %{"generation" => r["generation"] + 1, "write" => receipt}
          assert C.resume(continuation, %{"status" => "unknown"}) == {:stop, :unknown_effect}

          write.(
            write,
            C.resume(continuation, reply.(request, value)),
            next,
            parts + length(r["data"]),
            frames ++ [byte_size(json.(frame))],
            count + 1
          )
      end

    {:done, {:ok, _}} ->
      {reconstructed, parts, frames, count}

    terminal ->
      flunk(inspect(terminal))
  end
end

largest = Enum.max_by(units, & &1.byte_count)

{bytes, parts, frames, writes} =
  write.(
    write,
    C.start(profile, :value_prepare, %{
      "key" => largest.key,
      "value" => largest.value,
      "expected_revision" => 0,
      "reuse" => false,
      "continuation" => nil
    }),
    "",
    0,
    [],
    0
  )

assert bytes === json.(largest.value) and parts <= 10 and Enum.max(frames) <= 16_384
unicode = %{"text" => String.duplicate("雪\\\"", 2500)}

{unicode_bytes, _, _, _} =
  write.(
    write,
    C.start(profile, :value_prepare, %{
      "key" => "unicode.fixture",
      "value" => unicode,
      "expected_revision" => 0,
      "reuse" => false,
      "continuation" => nil
    }),
    "",
    0,
    [],
    0
  )

assert unicode_bytes === json.(unicode)
escaped = %{"text" => String.duplicate("\\", 24_000)}
assert byte_size(json.(escaped)) < 48 * 1024

{escaped_bytes, escaped_parts, escaped_frames, _} =
  write.(
    write,
    C.start(profile, :value_prepare, %{
      "key" => "escaped.fixture",
      "value" => escaped,
      "expected_revision" => 0,
      "reuse" => false,
      "continuation" => nil
    }),
    "",
    0,
    [],
    0
  )

assert escaped_bytes === json.(escaped) and escaped_parts <= 10 and
         Enum.max(escaped_frames) <= 16_384

# SDK packets fitting is not native packed-value acceptance. The host also
# limits the re-encoded packed document to64KiB at seal/inline publication.
packed_size = fn value ->
  bytes = json.(value)

  parts =
    Stream.unfold(bytes, fn
      "" ->
        nil

      remaining ->
        n = min(byte_size(remaining), 6144)
        {binary_part(remaining, 0, n), binary_part(remaining, n, byte_size(remaining) - n)}
    end)
    |> Enum.to_list()

  byte_size(
    json.(%{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => E.sha256(bytes),
      "byte_count" => byte_size(bytes),
      "parts" => parts
    })
  )
end

native_packed = packed_size.(largest.value)
assert native_packed > 65_536

conservative_rows =
  largest.value["rows"]
  |> Enum.take(32)
  |> Enum.map(fn [id, label, _] -> [id, label, Enum.to_list(0..124)] end)

proposed = %{
  largest.value
  | "version" => 2,
    "recipe" => "ipse.evidence.shared_directory.v2",
    "rows" => conservative_rows
}

assert byte_size(json.(proposed)) <= 48 * 1024 and packed_size.(proposed) <= 65_536

catalog =
  fetch.(:catalog)
  |> Map.put("sources", 1000)
  |> Map.put("generation", 1000)
  |> Map.put("chunks", 10_000)
  |> Map.put("extracted_bytes", 20 * 1024 * 1024)
  |> Map.put(
    "pages",
    for(n <- 0..62, do: %{"key" => "catalog.notes.#{n}", "sha256" => E.sha256("page#{n}")})
  )

refs = Enum.map(units, &D.reference/1)

manifests =
  for n <- 0..7,
      do: %{
        "key" => "genman.notes." <> E.sha256("manifest#{n}"),
        "sha256" => E.sha256("manifest#{n}"),
        "byte_count" => 2
      }

reduction = %{
  "phase" => "entity_digest",
  "batch" => 8,
  "manifests" => manifests,
  "runs" => [],
  "positions" => [],
  "entity_pages" => refs,
  "entities" => 5000,
  "text_bytes" => catalog["extracted_bytes"],
  "chunks" => 10_000,
  "facts" => 20_000,
  "heads_sha256" => E.sha256("heads"),
  "entities_sha256" => nil
}

job =
  fetch.(:job)
  |> Map.put("version", 2)
  |> Map.put("status", "reducing")
  |> Map.put("catalog", catalog)
  |> Map.put("catalog_sha256", E.sha256(json.(catalog)))
  |> Map.put("cursor", 1000)
  |> Map.put("summaries", [])
  |> Map.put("facts", 20_000)
  |> Map.put("root_revision", 0)
  |> Map.put("root_sha256", nil)
  |> Map.put("reduction", reduction)

assert Job.valid?(job, profile)

token = %{
  "version" => 1,
  "id" => job["id"],
  "plan_sha256" => nil,
  "job_revision" => 499,
  "root_revision" => 0,
  "catalog_sha256" => job["catalog_sha256"],
  "unit" => 0,
  "write" => nil,
  "stages" => []
}

args = %{
  "action" => "finalize",
  "vector_selection" => job["vector_selection"],
  "fact_selection" => job["fact_selection"],
  "continuation" => token,
  "group" => nil
}

records =
  Map.new(units, &{&1.key, &1.value})
  |> Map.merge(%{"catalog.notes" => catalog, "genjob.notes" => job})

{{:done, {:error, :generation_job_budget, _}}, calls} =
  read.(read, C.start(profile, :generation_job, args), records, 0)

assert calls == 512

IO.write(
  Jason.encode!(%{
    "entities" => 5000,
    "pages" => length(units),
    "escaped_object_reads" => Enum.sum(object_reads),
    "job_budget_reads" => calls,
    "job_budget_refused" => true,
    "largest_page_bytes" => largest.byte_count,
    "largest_page_native_packed_bytes" => native_packed,
    "v1_native_packed_capacity_refused" => true,
    "proposed_32row_125membership_bytes" => byte_size(json.(proposed)),
    "proposed_32row_125membership_native_packed_bytes" => packed_size.(proposed),
    "write_parts" => parts,
    "write_frames" => writes,
    "maximum_write_frame_bytes" => Enum.max(frames),
    "escaped_value_accepted_bytes" => byte_size(json.(escaped)),
    "escaped_value_parts" => escaped_parts,
    "escaped_value_max_frame_bytes" => Enum.max(escaped_frames),
    "native_operations" => 0,
    "model_calls" => 0
  })
)
