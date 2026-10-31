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

  defp exercise(interpose?) do
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
        "facts" => [fact]
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

  defp append(ctx, args, counts) do
    case drive(C.start(@profile, :generation_job, args), ctx) do
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
