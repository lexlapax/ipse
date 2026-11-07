Code.require_file(
  Path.expand("../../../lib/ipse/extension/collection/document_migration.ex", __DIR__)
)

defmodule IpseKnowledge.CollectionBackupCases do
  use ExUnit.Case, async: false
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Index
  alias IpseKnowledge.Corpus
  alias Ipse.Extension.Collection.Migration
  alias Ipse.Extension.Collection.DocumentMigration
  alias IpseKnowledge.Evidence, as: E

  test "reconstruction keeps each original UTF-8 part and checks both physical and logical identity" do
    parts = ["{\"title\":\"", "été", "\",\"n\":2}"]
    body = IO.iodata_to_binary(parts)

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => E.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => parts
    }

    physical = Migration.encode(packed)

    {descriptors, size} =
      Enum.map_reduce(parts, 0, fn part, offset ->
        {%{"offset" => offset, "byte_count" => byte_size(part), "sha256" => E.sha256(part)},
         offset + byte_size(part)}
      end)

    row = ["sample.key", 2, String.duplicate("a", 32), E.sha256(physical), byte_size(physical)]

    layout = %{
      "version" => 1,
      "recipe" => "document_packed_layout_v1",
      "revision" => 2,
      "record_sha256" => E.sha256(physical),
      "record_bytes" => byte_size(physical),
      "sha256" => E.sha256(body),
      "byte_count" => size,
      "parts" => descriptors
    }

    assert {:ok, %{"value" => ^packed, "operation_id" => operation_id}} =
             C.backup_reconstruct(row, layout, body)

    assert operation_id == String.duplicate("a", 32)
    assert {:error, :collection_backup_corrupt} = C.backup_reconstruct(row, layout, body <> " ")

    assert {:error, :collection_backup_corrupt} =
             C.backup_reconstruct(
               row,
               put_in(layout, ["parts", Access.at(1), "sha256"], E.sha256("wrong")),
               body
             )

    assert {:error, :collection_backup_corrupt} =
             C.backup_reconstruct(List.replace_at(row, 3, E.sha256("wrong")), layout, body)

    assert {:error, :collection_backup_corrupt} =
             C.backup_reconstruct(row, put_in(layout, ["parts", Access.at(1), "offset"], 0), body)
  end

  test "layout, chunk and metadata requests stay bounded reads with request-bound responses" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}

    for {op, args, inner_op, result} <- [
          {:value_layout, %{"key" => "sample.key", "generation" => 3}, "value.layout",
           %{"generation" => 3, "key" => "sample.key", "layout" => nil}},
          {:value_read_chunk, %{"key" => "sample.key", "generation" => 3, "offset" => 12},
           "value.read",
           %{"generation" => 3, "key" => "sample.key", "offset" => 12, "data" => "x"}},
          {:backup_metadata,
           %{"generation" => 3, "section" => "records", "offset" => 0, "limit" => 8},
           "backup.metadata",
           %{"generation" => 3, "section" => "records", "offset" => 0, "rows" => []}}
        ] do
      assert {:call, request, continuation} = C.start(profile, op, args)
      assert request["request"]["op"] == inner_op
      assert C.read_request?(request)
      assert {:ok, hash} = Ipse.Extension.canonical_digest([request])

      reply = %{"status" => "ok", "value" => wrapped(request, hash, result)}

      assert {:done, {:ok, %{"coverage" => %{"reads_used" => 1, "effects_used" => 0}}}} =
               C.resume(continuation, reply)

      assert {:done, {:error, :collection_response, _}} =
               C.resume(
                 continuation,
                 put_in(reply, ["value", "request_sha256"], E.sha256("wrong"))
               )
    end

    assert {:done, {:error, :invalid_collection_backup_metadata, _}} =
             C.start(profile, :backup_metadata, %{
               "generation" => 3,
               "section" => "records",
               "offset" => 0,
               "limit" => 9
             })
  end

  test "bounded page assembly reads metadata and preserves native wrapper boundaries" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}
    parts = ["{\"title\":\"", "été", "\"}"]
    body = IO.iodata_to_binary(parts)

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => E.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => parts
    }

    physical = Migration.encode(packed)

    {part_layout, _} =
      Enum.map_reduce(parts, 0, fn part, offset ->
        {%{"offset" => offset, "byte_count" => byte_size(part), "sha256" => E.sha256(part)},
         offset + byte_size(part)}
      end)

    layout = %{
      "version" => 1,
      "recipe" => "document_packed_layout_v1",
      "revision" => 1,
      "record_sha256" => E.sha256(physical),
      "record_bytes" => byte_size(physical),
      "sha256" => E.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => part_layout
    }

    row = ["sample.key", 1, String.duplicate("c", 32), E.sha256(physical), byte_size(physical)]
    {:ok, lineage_digest} = Ipse.Extension.canonical_digest([[]])

    descriptor = %{
      "version" => 4,
      "profile" => "document_graph_v1",
      "project" => E.sha256("project"),
      "generation" => 2,
      "maintenance_epoch" => 0,
      "floor" => 0,
      "floor_anchor" => nil,
      "records" => 1,
      "data_bytes" => byte_size(physical),
      "records_sha256" => E.sha256("records"),
      "operations" => 1,
      "operations_sha256" => E.sha256("operations"),
      "envelopes_sha256" => E.sha256("envelopes"),
      "floor_lineage_count" => 0,
      "floor_lineage_sha256" => lineage_digest
    }

    responses = fn request ->
      case request["request"] do
        %{"op" => "backup.metadata", "section" => section, "offset" => 0} ->
          %{
            "generation" => 2,
            "section" => section,
            "offset" => 0,
            "next" => nil,
            "descriptor" => descriptor,
            "rows" => if(section == "records", do: [row], else: [])
          }

        %{"op" => "value.layout"} ->
          %{"generation" => 2, "key" => "sample.key", "layout" => layout}

        %{"op" => "value.read", "offset" => 0} ->
          %{
            "generation" => 2,
            "key" => "sample.key",
            "revision" => 1,
            "sha256" => E.sha256(body),
            "byte_count" => byte_size(body),
            "offset" => 0,
            "data" => body,
            "next" => nil
          }
      end
    end

    initial = C.start(profile, :backup_page, %{"generation" => 2, "offset" => 0, "limit" => 8})
    assert {:done, {:ok, page}, 4} = drive(initial, responses, 0)
    assert page["next"] == nil
    assert page["descriptor"]["floor_lineage"] == []
    assert [%{"key" => "sample.key", "value" => ^packed}] = page["records"]

    bad = fn request -> Map.put(responses.(request), "generation", 3) end
    assert {:done, {:error, :collection_response, _}, 1} = drive(initial, bad, 0)

    bad_epoch = fn request ->
      update_in(responses.(request), ["descriptor"], &Map.delete(&1, "maintenance_epoch"))
    end

    assert {:done, {:error, :collection_backup_corrupt, _}, 1} = drive(initial, bad_epoch, 0)
  end

  test "a lexical job is terminal only when aborted or exactly joined to its selected root" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}

    catalog = %{
      "version" => 1,
      "kind" => "catalog",
      "partition" => "docs",
      "generation" => 0,
      "floor" => 0,
      "sources" => 0,
      "extracted_bytes" => 0,
      "chunks" => 0,
      "entities" => 0,
      "assertions" => 0,
      "pages" => []
    }

    catalog_hash = E.sha256(IO.iodata_to_binary(JSON.encode!(catalog)))

    job = %{
      "version" => 1,
      "kind" => "lexical_job",
      "id" => String.duplicate("d", 32),
      "status" => "building",
      "catalog" => catalog,
      "catalog_sha256" => catalog_hash,
      "cursor" => 0,
      "unit" => 0,
      "groups" => [],
      "root_revision" => 0,
      "index_generation" => 1
    }

    root = %{
      "version" => 1,
      "kind" => "lexical_index",
      "recipe" => E.lexical_recipe(),
      "job_id" => job["id"],
      "generation" => 1,
      "catalog_sha256" => catalog_hash,
      "catalog_generation" => 0,
      "floor" => 0,
      "sources" => 0,
      "chunks" => 0,
      "groups" => []
    }

    assert Index.completed_job?(job, root, profile)
    assert Index.completed_job?(Map.put(job, "status", "aborted"), nil, profile)
    refute Index.completed_job?(job, nil, profile)
    refute Index.completed_job?(job, Map.put(root, "job_id", String.duplicate("e", 32)), profile)
    refute Index.completed_job?(job, Map.put(root, "generation", 2), profile)
    refute Index.completed_job?(Map.put(job, "unit", 1), root, profile)
    refute Index.completed_job?(Map.put(job, "extra", true), root, profile)
  end

  test "selected result reads verify the v3 wrapper, delivery, offsets and raw chunk hash" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}
    bytes = "selected result bytes"

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output"),
      "byte_count" => byte_size(bytes),
      "sha256" => E.sha256(bytes),
      "historical_receipt" => true
    }

    ref = %{"version" => 1, "session_id" => String.duplicate("a", 32), "delivery" => delivery}
    plan = %{ref | "session_id" => String.duplicate("b", 32)}

    assert {:call, request, continuation} =
             C.start(profile, :result_input_read, %{
               "result_input" => ref,
               "plan_input" => plan,
               "offset" => 0
             })

    assert C.read_request?(request) and request["result_input"] === ref
    assert request["plan_input"] === plan
    assert {:ok, hash} = Ipse.Extension.canonical_digest([request])

    owner = %{
      "project_id" => E.sha256("project"),
      "session_id" => String.duplicate("c", 32),
      "identity_sha256" => E.sha256("identity"),
      "invocation_id" => String.duplicate("d", 32)
    }

    result = %{
      "delivery" => delivery,
      "offset" => 0,
      "next" => nil,
      "data_base64" => Base.encode64(bytes),
      "sha256" => E.sha256(bytes),
      "origin" => nil
    }

    reply = %{
      "status" => "ok",
      "value" => %{
        "version" => 3,
        "owner" => owner,
        "operation_id" => String.duplicate("e", 32),
        "request_sha256" => hash,
        "result" => result
      }
    }

    assert {:done, {:ok, %{"data" => ^bytes, "next" => nil}}} = C.resume(continuation, reply)

    for changed <- [
          put_in(reply, ["value", "result", "sha256"], E.sha256("wrong")),
          put_in(reply, ["value", "result", "next"], byte_size(bytes)),
          put_in(reply, ["value", "result", "delivery", "output_id"], E.sha256("other")),
          put_in(reply, ["value", "owner", "invocation_id"], "invalid"),
          put_in(reply, ["value", "request_sha256"], E.sha256("wrong"))
        ] do
      assert {:done, {:error, :collection_result_input_corrupt, _}} =
               C.resume(continuation, changed)
    end
  end

  test "selected result assembly verifies the complete original delivery across chunks" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}
    text = String.duplicate("x", 7000)
    bytes = ~s({"text":") <> text <> ~s("})

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output"),
      "byte_count" => byte_size(bytes),
      "sha256" => E.sha256(bytes),
      "historical_receipt" => true
    }

    ref = %{"version" => 1, "session_id" => String.duplicate("a", 32), "delivery" => delivery}

    initial =
      C.start(profile, :selected_backup_result, %{"result_input" => ref, "plan_input" => nil})

    assert {:done, {:ok, result}, 2} = drive_input(initial, bytes, delivery, 0)
    assert result["value"] === %{"text" => text}
    assert result["raw_sha256"] === E.sha256(bytes)
    assert result["byte_count"] === byte_size(bytes)

    origin = source_origin(ref, "backup_page", provenance_descriptor())

    changed = fn offset ->
      if offset === 0, do: origin, else: Map.put(origin, "metadata_sha256", E.sha256("different"))
    end

    assert {:done, {:error, :collection_result_input_corrupt, _}, 2} =
             drive_input(initial, bytes, delivery, 0, changed)

    bad_ref = put_in(ref, ["delivery", "sha256"], E.sha256("wrong"))

    bad =
      C.start(profile, :selected_backup_result, %{"result_input" => bad_ref, "plan_input" => nil})

    assert {:done, {:error, :collection_result_input_corrupt, _}, 2} =
             drive_input(bad, bytes, bad_ref["delivery"], 0)
  end

  test "fact result assembly binds the full host owner across every input chunk" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}
    text = String.duplicate("x", 7000)
    bytes = ~s({"text":") <> text <> ~s("})

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output"),
      "byte_count" => byte_size(bytes),
      "sha256" => E.sha256(bytes),
      "historical_receipt" => true
    }

    ref = %{"version" => 1, "session_id" => String.duplicate("a", 32), "delivery" => delivery}

    owner = %{
      "project_id" => E.sha256("project"),
      "session_id" => String.duplicate("c", 32),
      "identity_sha256" => E.sha256("identity"),
      "invocation_id" => String.duplicate("d", 32)
    }

    initial = C.start(profile, :selected_fact_result, %{"result_input" => ref})

    assert {:done, {:ok, selected}, 2} =
             drive_fact_input(initial, bytes, delivery, 0, fn _ -> owner end)

    assert selected === %{
             "result_input" => ref,
             "value" => %{"text" => text},
             "raw_sha256" => E.sha256(bytes),
             "byte_count" => byte_size(bytes),
             "owner" => Map.delete(owner, "invocation_id"),
             "reads_used" => 2
           }

    for key <- ~w(project_id session_id identity_sha256 invocation_id) do
      altered =
        if key in ~w(session_id invocation_id),
          do: String.duplicate("b", 32),
          else: E.sha256("other")

      owner_at = fn offset -> if offset == 0, do: owner, else: Map.put(owner, key, altered) end

      assert {:done, {:error, :collection_result_input_corrupt, _}, 2} =
               drive_fact_input(initial, bytes, delivery, 0, owner_at)
    end
  end

  test "fact input constructor is command-only and publishes a closed paged group" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}

    state = %{
      resolved: %{
        "preset" => "collection-dense",
        "options" => %{"stores" => %{"docs" => profile}}
      },
      phase: :idle,
      ctx: nil,
      cont: nil,
      pending: nil
    }

    row = %{
      "subject" => "A",
      "predicate" => "supports",
      "object" => "B",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => nil,
      "spans" => [[0, 0, 1]]
    }

    group = %{
      "version" => 1,
      "kind" => "explicit_fact_group",
      "sources" => [
        %{"source_key" => E.sha256("source"), "facts" => [row]}
      ]
    }

    args = %{
      "store" => "docs",
      "action" => "fact_input",
      "args" => %{
        "input" => %{"version" => 1, "mode" => "publish", "value" => group}
      }
    }

    invoke = %{"id" => "source", "arguments" => args}

    assert {:ok, %Ipse.Extension.ResultPublication.Output{} = output, _} =
             Corpus.handle("invoke.command", invoke, state)

    assert {:ok, ^group} =
             Ipse.Extension.ResultDocument.decode(output.bytes, %{"type" => "object"})

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle("invoke.tool", invoke, state)

    for invalid <- [
          put_in(args, ["args", "input", "value", "sources"], []),
          put_in(
            args,
            ["args", "input", "value", "sources", Access.at(0), "facts", Access.at(0), "spans"],
            [[0, 1, 1]]
          ),
          put_in(args, ["args", "input", "value", "extra"], true),
          Map.put(args, "result_input", %{})
        ] do
      assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
               Corpus.handle("invoke.command", %{"id" => "source", "arguments" => invalid}, state)
    end

    selection = %{
      "selection_sha256" => E.sha256("selection"),
      "profile" => "encoder",
      "model" => "fixture",
      "dimensions" => 1024,
      "encoding" => "float32le"
    }

    extraction = %{"version" => 1, "kind" => "explicit", "profile" => nil}

    begin_input = %{
      "version" => 1,
      "mode" => "begin",
      "vector_selection" => selection,
      "fact_selection" => extraction,
      "continuation" => nil
    }

    begin_args = put_in(args, ["args", "input"], begin_input)

    assert {:ok, %{"kind" => "host_call", "request" => %{"request" => %{"op" => "snapshot"}}}, _} =
             Corpus.handle(
               "invoke.command",
               %{"id" => "source", "arguments" => begin_args},
               state
             )

    invalid_begin = put_in(begin_args, ["args", "input", "vector_selection", "dimensions"], 1)

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle(
               "invoke.command",
               %{"id" => "source", "arguments" => invalid_begin},
               state
             )

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output"),
      "byte_count" => 10,
      "sha256" => E.sha256("raw"),
      "historical_receipt" => true
    }

    ref = %{"version" => 1, "session_id" => String.duplicate("a", 32), "delivery" => delivery}

    producer = %{
      "version" => 2,
      "action" => "page",
      "embedding" => "encoder",
      "job_id" => String.duplicate("b", 32),
      "job_revision" => 1,
      "vector_selection" => selection,
      "fact_selection" => extraction,
      "vector_cursor" => 0,
      "previous_ready" => nil
    }

    append_args =
      args
      |> put_in(["args", "input"], %{
        "version" => 1,
        "mode" => "append",
        "producer" => producer,
        "continuation" => nil
      })
      |> Map.put("result_input", ref)

    assert {:ok,
            %{
              "kind" => "host_call",
              "request" => %{
                "result_input" => ^ref,
                "request" => %{"op" => "restore.input.read", "offset" => 0}
              }
            },
            _} =
             Corpus.handle(
               "invoke.command",
               %{"id" => "source", "arguments" => append_args},
               state
             )

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle(
               "invoke.command",
               %{"id" => "source", "arguments" => Map.delete(append_args, "result_input")},
               state
             )
  end

  test "bounded plan matches the native document migration parser and rejects altered membership" do
    body = ~s({"text":"public"})

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => E.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => [body]
    }

    physical = Migration.encode(packed)
    id = String.duplicate("a", 32)
    receipt = %{"generation" => 1, "floor" => 0, "request_sha256" => E.sha256("request")}

    native_record = %{
      "key" => "source.docs.1",
      "revision" => 1,
      "operation_id" => id,
      "sha256" => E.sha256(physical),
      "bytes" => byte_size(physical)
    }

    row = Enum.map(~w(key revision operation_id sha256 bytes), &native_record[&1])
    rows = [row]
    records = %{native_record["key"] => native_record}
    operations = [[id, receipt]]

    descriptor = %{
      "version" => 4,
      "profile" => "document_graph_v1",
      "project" => E.sha256("project"),
      "generation" => 1,
      "maintenance_epoch" => 0,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "floor_lineage_sha256" => Ipse.JSON.digest([[]]),
      "records" => 1,
      "data_bytes" => byte_size(physical),
      "records_sha256" => Migration.digest(records),
      "operations" => 1,
      "operations_sha256" => Migration.operation_digest(%{id => receipt}),
      "envelopes_sha256" => Ipse.JSON.digest([rows])
    }

    page = %{
      "descriptor" => descriptor,
      "records" => [Map.put(native_record, "value", packed)],
      "next" => nil
    }

    {:ok, raw} = Ipse.Extension.ResultDocument.encode(page, %{"type" => "object"})

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output"),
      "byte_count" => byte_size(raw),
      "sha256" => E.sha256(raw),
      "historical_receipt" => true
    }

    ref = %{"version" => 1, "session_id" => String.duplicate("b", 32), "delivery" => delivery}

    selected = %{
      "result_input" => ref,
      "value" => page,
      "raw_sha256" => E.sha256(raw),
      "byte_count" => byte_size(raw),
      "origin" => nil
    }

    assert {:ok, plan} = C.backup_plan(descriptor, rows, operations, [selected])

    target = %{
      "project" => descriptor["project"],
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "operations" => %{},
      "imported_operations" => %{},
      "migration" => nil
    }

    assert {:ok, parsed} = DocumentMigration.plan(target, plan)
    assert parsed.counts == [1] and parsed.records == records
    assert plan["plan"]["data_inputs"] == [ref]
    assert {:ok, empty_union} = Ipse.Extension.canonical_digest([[]])
    assert plan["plan"]["dependency_union_sha256"] == empty_union
    assert :ok = C.backup_verify_plan(plan, [selected])

    for bad <- [
          Map.delete(descriptor, "maintenance_epoch"),
          Map.put(descriptor, "maintenance_epoch", -1)
        ] do
      assert {:error, :collection_backup_plan_invalid} =
               C.backup_plan(bad, rows, operations, [selected])
    end

    assert {:error, :collection_backup_plan_invalid} =
             C.backup_verify_plan(put_in(plan, ["plan", "page_counts"], [2]), [selected])

    assert {:error, :collection_backup_plan_invalid} =
             C.backup_verify_plan(
               put_in(plan, ["plan", "operations", Access.at(0), Access.at(0)], "invalid"),
               [selected]
             )

    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}
    compact = descriptor |> Map.delete("floor_lineage") |> Map.put("floor_lineage_count", 0)

    responses = fn request ->
      case request["request"] do
        %{"op" => "backup.metadata", "section" => section, "offset" => 0} ->
          values =
            case section do
              "records" -> rows
              "operations" -> operations
              "lineage" -> []
            end

          %{
            "generation" => 1,
            "section" => section,
            "offset" => 0,
            "next" => nil,
            "descriptor" => compact,
            "rows" => values
          }

        %{"op" => "restore.input.read", "offset" => 0} ->
          %{
            "delivery" => delivery,
            "offset" => 0,
            "next" => nil,
            "data_base64" => Base.encode64(raw),
            "sha256" => E.sha256(raw),
            "origin" => nil
          }
      end
    end

    initial = C.start(profile, :backup_plan, %{"generation" => 1, "data_inputs" => [ref]})
    assert {:done, {:ok, ^plan}, 4} = drive_plan(initial, responses, 0)

    assert {:error, :collection_backup_plan_invalid} =
             C.backup_plan(descriptor, rows, operations, [
               put_in(selected, ["value", "next"], "wrong")
             ])

    assert {:error, :collection_backup_plan_invalid} =
             C.backup_plan(descriptor, rows, operations, [
               put_in(selected, ["raw_sha256"], E.sha256("wrong"))
             ])

    assert {:error, :collection_backup_plan_invalid} =
             C.backup_plan(descriptor, rows, [[id, Map.put(receipt, "unexpected", true)]], [
               selected
             ])
  end

  test "restore mutations bind exact selected input and treat unproven outcomes as unknown" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output"),
      "byte_count" => 10,
      "sha256" => E.sha256("raw"),
      "historical_receipt" => true
    }

    ref = %{"version" => 1, "session_id" => String.duplicate("a", 32), "delivery" => delivery}
    {:ok, binding} = Ipse.Extension.canonical_digest([ref])
    {:ok, empty_union} = Ipse.Extension.canonical_digest([[]])

    inner = %{
      "op" => "restore.open",
      "expected_generation" => 7,
      "expected_epoch" => 2,
      "input_sha256" => E.sha256("canonical"),
      "plan_binding_sha256" => binding,
      "dependency_union_sha256" => empty_union
    }

    args = %{"request" => inner, "result_input" => ref, "plan_input" => nil}
    assert {:call, request, continuation} = C.start(profile, :restore_mutation, args)
    refute C.read_request?(request)
    assert request["result_input"] === ref and not Map.has_key?(request, "plan_input")
    assert {:ok, outer_hash} = Ipse.Extension.canonical_digest([request])

    owner = %{
      "project_id" => E.sha256("project"),
      "session_id" => String.duplicate("c", 32),
      "identity_sha256" => E.sha256("identity"),
      "invocation_id" => String.duplicate("d", 32)
    }

    assert {:ok, native_hash} =
             Ipse.Extension.canonical_digest([
               inner,
               Map.take(owner, ~w(project_id session_id identity_sha256))
             ])

    operation_id = String.duplicate("e", 32)

    receipt = %{
      "generation" => 8,
      "floor" => 0,
      "request_sha256" => native_hash,
      "migration_id" => operation_id
    }

    reply = %{
      "status" => "ok",
      "value" => %{
        "version" => 3,
        "owner" => owner,
        "operation_id" => operation_id,
        "request_sha256" => outer_hash,
        "result" => receipt
      }
    }

    assert {:done, {:ok, %{"receipt" => ^receipt}}} = C.resume(continuation, reply)
    assert {:stop, :unknown_effect} = C.resume(continuation, %{"status" => "unknown"})

    assert {:stop, :unknown_effect} =
             C.resume(continuation, put_in(reply, ["value", "result", "generation"], 9))

    assert {:stop, :unknown_effect} =
             C.resume(
               continuation,
               put_in(reply, ["value", "result", "request_sha256"], E.sha256("wrong"))
             )

    assert {:done, {:error, :invalid_collection_restore, _}} =
             C.start(
               profile,
               :restore_mutation,
               put_in(args, ["request", "plan_binding_sha256"], E.sha256("wrong"))
             )
  end

  test "restore open reports an epoch greater than the source and target epochs" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}
    descriptor = Map.put(provenance_descriptor(), "maintenance_epoch", 4)
    value = %{"descriptor" => descriptor}
    {:ok, bytes} = Ipse.Extension.ResultDocument.encode(value, %{"type" => "object"})
    ref = result_ref(bytes, "epoch-plan")
    origin = source_origin(ref, "backup_plan", descriptor)

    initial =
      C.start(profile, :restore_action, %{
        "action" => "open",
        "args" => %{"expected_generation" => 7, "expected_epoch" => 2},
        "result_input" => ref,
        "plan_input" => nil
      })

    assert {:call, read, read_state} = initial
    {:ok, hash} = Ipse.Extension.canonical_digest([read])

    result = %{
      "delivery" => ref["delivery"],
      "offset" => 0,
      "next" => nil,
      "data_base64" => Base.encode64(bytes),
      "sha256" => E.sha256(bytes),
      "origin" => origin
    }

    read_reply = %{"status" => "ok", "value" => wrapped(read, hash, result)}
    assert {:call, mutation, mutation_state} = C.resume(read_state, read_reply)
    assert mutation["request"]["expected_epoch"] === 2

    owner = %{
      "project_id" => E.sha256("project"),
      "session_id" => String.duplicate("c", 32),
      "identity_sha256" => E.sha256("identity"),
      "invocation_id" => String.duplicate("d", 32)
    }

    operation_id = String.duplicate("e", 32)
    {:ok, outer_hash} = Ipse.Extension.canonical_digest([mutation])

    {:ok, native_hash} =
      Ipse.Extension.canonical_digest([
        mutation["request"],
        Map.take(owner, ~w(project_id session_id identity_sha256))
      ])

    reply = %{
      "status" => "ok",
      "value" => %{
        "version" => 3,
        "owner" => owner,
        "operation_id" => operation_id,
        "request_sha256" => outer_hash,
        "result" => %{
          "generation" => 8,
          "floor" => 0,
          "request_sha256" => native_hash,
          "migration_id" => operation_id
        }
      }
    }

    assert {:done, {:ok, %{"maintenance_epoch" => 5}}} = C.resume(mutation_state, reply)

    assert {:done, {:error, :collection_result_input_corrupt, _}} =
             C.resume(read_state, put_in(read_reply, ["value", "result", "origin"], nil))
  end

  test "source command routes bounded backup and restore references only for Collection" do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}

    state = %{
      resolved: %{
        "preset" => "collection-documents",
        "options" => %{"stores" => %{"docs" => profile}}
      },
      phase: :idle,
      ctx: nil,
      cont: nil,
      pending: nil
    }

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output"),
      "byte_count" => 10,
      "sha256" => E.sha256("raw"),
      "historical_receipt" => true
    }

    ref = %{"version" => 1, "session_id" => String.duplicate("a", 32), "delivery" => delivery}
    plan = %{ref | "session_id" => String.duplicate("b", 32)}

    invoke = fn action, backup, extra ->
      %{
        "id" => "source",
        "arguments" =>
          Map.merge(
            %{"store" => "docs", "action" => action, "args" => %{"backup" => backup}},
            extra
          )
      }
    end

    assert {:ok, %{"kind" => "host_call", "request" => status_request}, status_state} =
             Corpus.handle("invoke.command", invoke.("backup_status", %{}, %{}), state)

    assert status_request["request"]["op"] === "snapshot"
    {:ok, request_hash} = Ipse.Extension.canonical_digest([status_request])

    for {descriptor, expected_epoch, expected_status} <- [
          {%{"version" => 1, "inline_bytes" => 8192}, 0, "idle"},
          {%{
             "version" => 4,
             "inline_bytes" => 8192,
             "write_parts" => 2,
             "maintenance_epoch" => 3,
             "maintenance_status" => "active",
             "progress" => 1
           }, 3, "active"}
        ] do
      reply = %{
        "status" => "ok",
        "value" =>
          wrapped(status_request, request_hash, %{
            "generation" => 12,
            "document_store" => descriptor
          })
      }

      assert {:ok, %{"kind" => "result", "value" => %{"status" => "ok", "coverage" => coverage}},
              _} =
               Corpus.handle("host.actions", %{"outcome" => reply}, status_state)

      assert coverage === %{
               "generation" => 12,
               "maintenance_epoch" => expected_epoch,
               "maintenance_status" => expected_status
             }
    end

    malformed = %{
      "generation" => 12,
      "document_store" => %{
        "version" => 4,
        "inline_bytes" => 8192,
        "write_parts" => 2,
        "maintenance_epoch" => 3,
        "maintenance_status" => "active",
        "progress" => 0
      }
    }

    reply = %{"status" => "ok", "value" => wrapped(status_request, request_hash, malformed)}

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle("host.actions", %{"outcome" => reply}, status_state)

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle("invoke.tool", invoke.("backup_status", %{}, %{}), state)

    assert {:ok,
            %{"kind" => "host_call", "request" => %{"request" => %{"op" => "backup.metadata"}}},
            _} =
             Corpus.handle(
               "invoke.command",
               invoke.("backup_page", %{"generation" => 1, "offset" => 0, "limit" => 8}, %{}),
               state
             )

    assert {:ok,
            %{"kind" => "host_call", "request" => %{"request" => %{"op" => "backup.metadata"}}},
            _} =
             Corpus.handle(
               "invoke.command",
               invoke.("backup_plan", %{"generation" => 1}, %{"data_inputs" => [ref]}),
               state
             )

    assert {:ok,
            %{
              "kind" => "host_call",
              "request" => %{
                "result_input" => ^plan,
                "request" => %{"op" => "restore.input.read"}
              }
            },
            _} =
             Corpus.handle(
               "invoke.command",
               invoke.("restore_validate_page", %{}, %{
                 "result_input" => ref,
                 "plan_input" => plan
               }),
               state
             )

    assert {:ok,
            %{
              "kind" => "host_call",
              "request" => %{"result_input" => ^ref, "request" => %{"op" => "restore.input.read"}}
            },
            _} =
             Corpus.handle(
               "invoke.command",
               invoke.("restore_open", %{"expected_generation" => 1, "expected_epoch" => 0}, %{
                 "result_input" => ref
               }),
               state
             )

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle(
               "invoke.command",
               invoke.("backup_page", %{"generation" => 1, "offset" => 0, "limit" => 9}, %{}),
               state
             )

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle(
               "invoke.tool",
               invoke.("backup_page", %{"generation" => 1, "offset" => 0, "limit" => 8}, %{}),
               state
             )

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle(
               "invoke.command",
               invoke.("backup_page", %{"generation" => 1, "offset" => 0, "limit" => 8}, %{
                 "result_input" => ref
               }),
               state
             )
  end

  test "selected pages are checked against the complete real Source domain before publication" do
    fixture = IpseKnowledge.CollectionCompletedBackupCases.completed_source_fixture()
    assert length(fixture.records) in 1..8

    build = fn records ->
      rows =
        Enum.map(records, fn record ->
          Enum.map(~w(key revision operation_id sha256 bytes), &record[&1])
        end)

      native_records = Map.new(records, &{&1["key"], Map.delete(&1, "value")})
      id = hd(records)["operation_id"]
      receipt = %{"generation" => 1, "floor" => 0, "request_sha256" => E.sha256("request")}
      operations = [[id, receipt]]

      descriptor = %{
        "version" => 4,
        "profile" => "document_graph_v1",
        "project" => E.sha256("project"),
        "generation" => 1,
        "maintenance_epoch" => 0,
        "floor" => 0,
        "floor_anchor" => nil,
        "floor_lineage" => [],
        "floor_lineage_sha256" => Ipse.JSON.digest([[]]),
        "records" => length(records),
        "data_bytes" => Enum.reduce(records, 0, &(&1["bytes"] + &2)),
        "records_sha256" => Migration.digest(native_records),
        "operations" => 1,
        "operations_sha256" => Migration.operation_digest(%{id => receipt}),
        "envelopes_sha256" => Ipse.JSON.digest([rows])
      }

      page = %{"descriptor" => descriptor, "records" => records, "next" => nil}
      {:ok, page_bytes} = Ipse.Extension.ResultDocument.encode(page, %{"type" => "object"})
      page_ref = result_ref(page_bytes, "page")

      selected = %{
        "result_input" => page_ref,
        "value" => page,
        "raw_sha256" => E.sha256(page_bytes),
        "byte_count" => byte_size(page_bytes),
        "origin" => source_origin(page_ref, "backup_page", descriptor)
      }

      {:ok, plan} = C.backup_plan(descriptor, rows, operations, [selected])
      {:ok, plan_bytes} = Ipse.Extension.ResultDocument.encode(plan, %{"type" => "object"})
      plan_ref = result_ref(plan_bytes, "plan")

      {page, page_ref, plan_ref,
       %{
         page_ref => {page_bytes, source_origin(page_ref, "backup_page", descriptor)},
         plan_ref => {plan_bytes, source_origin(plan_ref, "backup_plan", descriptor)}
       }}
    end

    validate = fn {page, page_ref, plan_ref, inputs} ->
      responses = fn request ->
        ref = request["result_input"]
        {bytes, origin} = Map.fetch!(inputs, ref)
        offset = request["request"]["offset"]
        count = min(6144, byte_size(bytes) - offset)
        chunk = binary_part(bytes, offset, count)

        %{
          "delivery" => ref["delivery"],
          "offset" => offset,
          "next" => if(offset + count < byte_size(bytes), do: offset + count),
          "data_base64" => Base.encode64(chunk),
          "sha256" => E.sha256(chunk),
          "origin" => origin
        }
      end

      initial =
        C.start(fixture.profile, :validate_backup_page, %{
          "result_input" => page_ref,
          "plan_input" => plan_ref
        })

      {drive_plan(initial, responses, 0), page}
    end

    current = build.(fixture.records)
    assert {{:done, {:ok, page}, _}, page} = validate.(current)

    # Keep every packed envelope and catalog hash consistent while rebinding
    # the catalog key to a head and source belonging to another identity.
    repack = fn row, value ->
      body = IO.iodata_to_binary(JSON.encode!(value))

      packed = %{
        "version" => 1,
        "kind" => "document_value",
        "sha256" => E.sha256(body),
        "byte_count" => byte_size(body),
        "parts" => [body]
      }

      {:ok, physical} = Ipse.Extension.ResultDocument.encode(packed, %{"type" => "object"})

      Map.merge(row, %{
        "value" => packed,
        "sha256" => E.sha256(physical),
        "bytes" => byte_size(physical)
      })
    end

    unpack = fn row -> row["value"]["parts"] |> Enum.join() |> JSON.decode!() end
    records = Map.new(fixture.records, &{&1["key"], &1})
    original_key = fixture.source["source_key"]
    different_key = E.sha256("different-source")
    refute original_key === different_key
    source = Map.fetch!(records, "source.docs." <> original_key)
    page = Map.fetch!(records, "catalog.docs.0")
    page_value = page |> unpack.() |> put_in(["rows", Access.at(0), "source_key"], different_key)
    page = repack.(page, page_value)
    catalog = Map.fetch!(records, "catalog.docs")

    catalog_value =
      catalog |> unpack.() |> put_in(["pages", Access.at(0), "sha256"], page["value"]["sha256"])

    catalog = repack.(catalog, catalog_value)

    mismatched =
      records
      |> Map.delete(source["key"])
      |> Map.put(
        "source.docs." <> different_key,
        Map.put(source, "key", "source.docs." <> different_key)
      )
      |> Map.put(page["key"], page)
      |> Map.put(catalog["key"], catalog)
      |> Map.values()

    refute IpseKnowledge.Store.Collection.Projection.completed_backup?(
             fixture.profile,
             mismatched
           )

    assert {{:done, {:error, :collection_backup_incomplete_domain, _}, _}, _} =
             validate.(build.(mismatched))

    {page, page_ref, plan_ref, inputs} = current
    {bytes, page_origin} = Map.fetch!(inputs, page_ref)

    for bad_origin <- [
          nil,
          Map.put(page_origin, "action", "backup_plan"),
          put_in(page_origin, ["descriptor", "maintenance_epoch"], 1)
        ] do
      altered = Map.put(inputs, page_ref, {bytes, bad_origin})

      assert {{:done, {:error, :collection_backup_incomplete_domain, _}, _}, _} =
               validate.({page, page_ref, plan_ref, altered})
    end

    {plan_bytes, _} = Map.fetch!(inputs, plan_ref)

    assert {{:done, {:error, :collection_backup_plan_invalid, _}, _}, _} =
             validate.({page, page_ref, plan_ref, Map.put(inputs, plan_ref, {plan_bytes, nil})})

    incomplete = Enum.reject(fixture.records, &(&1["key"] === "catalog.docs.0"))
    assert length(incomplete) === length(fixture.records) - 1

    assert {{:done, {:error, :collection_backup_incomplete_domain, _}, _}, _} =
             validate.(build.(incomplete))
  end

  defp result_ref(bytes, label) do
    %{
      "version" => 1,
      "session_id" => String.duplicate("b", 32),
      "delivery" => %{
        "version" => 1,
        "kind" => "saved.result",
        "output_id" => E.sha256(label),
        "byte_count" => byte_size(bytes),
        "sha256" => E.sha256(bytes),
        "historical_receipt" => true
      }
    }
  end

  defp source_origin(ref, action, descriptor) do
    invocation_id = String.duplicate("d", 32)

    %{
      "version" => 1,
      "artifact_sha256" => E.sha256("artifact"),
      "invocation_id" => invocation_id,
      "command_id" => "source",
      "action" => action,
      "owner" => %{
        "project_id" => E.sha256("project"),
        "session_id" => ref["session_id"],
        "identity_sha256" => E.sha256("identity"),
        "invocation_id" => invocation_id
      },
      "descriptor" =>
        descriptor
        |> Map.delete("floor_lineage")
        |> Map.put("floor_lineage_count", length(descriptor["floor_lineage"])),
      "metadata_sha256" => E.sha256("metadata")
    }
  end

  defp provenance_descriptor do
    %{
      "version" => 4,
      "profile" => "document_graph_v1",
      "project" => E.sha256("project"),
      "generation" => 1,
      "maintenance_epoch" => 0,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "floor_lineage_sha256" => Ipse.JSON.digest([[]]),
      "records" => 0,
      "data_bytes" => 0,
      "records_sha256" => E.sha256("records"),
      "operations" => 0,
      "operations_sha256" => E.sha256("operations"),
      "envelopes_sha256" => E.sha256("envelopes")
    }
  end

  defp drive({:call, request, continuation}, responses, count) do
    assert C.read_request?(request)
    assert {:ok, hash} = Ipse.Extension.canonical_digest([request])

    reply = %{"status" => "ok", "value" => wrapped(request, hash, responses.(request))}

    drive(C.resume(continuation, reply), responses, count + 1)
  end

  defp drive({:done, value}, _, count), do: {:done, value, count}

  defp drive_input(initial, bytes, delivery, count, origin_fun \\ fn _ -> nil end)

  defp drive_input({:call, request, continuation}, bytes, delivery, count, origin_fun) do
    offset = request["request"]["offset"]
    amount = min(6144, byte_size(bytes) - offset)
    chunk = binary_part(bytes, offset, amount)
    next = if offset + amount < byte_size(bytes), do: offset + amount, else: nil
    assert {:ok, hash} = Ipse.Extension.canonical_digest([request])

    owner = %{
      "project_id" => E.sha256("project"),
      "session_id" => String.duplicate("c", 32),
      "identity_sha256" => E.sha256("identity"),
      "invocation_id" => String.duplicate("d", 32)
    }

    result = %{
      "delivery" => delivery,
      "offset" => offset,
      "next" => next,
      "data_base64" => Base.encode64(chunk),
      "sha256" => E.sha256(chunk),
      "origin" => origin_fun.(offset)
    }

    reply = %{
      "status" => "ok",
      "value" => %{
        "version" => 3,
        "owner" => owner,
        "operation_id" => String.duplicate("e", 32),
        "request_sha256" => hash,
        "result" => result
      }
    }

    drive_input(C.resume(continuation, reply), bytes, delivery, count + 1, origin_fun)
  end

  defp drive_input({:done, value}, _, _, count, _), do: {:done, value, count}

  defp drive_fact_input({:call, request, continuation}, bytes, delivery, count, owner_at) do
    offset = request["request"]["offset"]
    size = min(6144, byte_size(bytes) - offset)
    chunk = binary_part(bytes, offset, size)
    next = if offset + size < byte_size(bytes), do: offset + size, else: nil
    {:ok, hash} = Ipse.Extension.canonical_digest([request])

    reply = %{
      "status" => "ok",
      "value" => %{
        "version" => 3,
        "owner" => owner_at.(offset),
        "operation_id" => String.duplicate("e", 32),
        "request_sha256" => hash,
        "result" => %{
          "delivery" => delivery,
          "offset" => offset,
          "next" => next,
          "data_base64" => Base.encode64(chunk),
          "sha256" => E.sha256(chunk),
          "origin" => nil
        }
      }
    }

    drive_fact_input(C.resume(continuation, reply), bytes, delivery, count + 1, owner_at)
  end

  defp drive_fact_input({:done, value}, _, _, count, _), do: {:done, value, count}

  defp drive_plan({:call, request, continuation}, responses, count) do
    assert C.read_request?(request)
    assert {:ok, hash} = Ipse.Extension.canonical_digest([request])

    reply = %{"status" => "ok", "value" => wrapped(request, hash, responses.(request))}
    drive_plan(C.resume(continuation, reply), responses, count + 1)
  end

  defp drive_plan({:done, value}, _, count), do: {:done, value, count}

  defp wrapped(request, hash, result) do
    common = %{
      "operation_id" => String.duplicate("e", 32),
      "request_sha256" => hash,
      "result" => result
    }

    if request["request"]["op"] in ~w(restore.input.read backup.metadata) do
      owner = %{
        "project_id" => E.sha256("project"),
        "session_id" => String.duplicate("c", 32),
        "identity_sha256" => E.sha256("identity"),
        "invocation_id" => String.duplicate("d", 32)
      }

      Map.merge(common, %{"version" => 3, "owner" => owner})
    else
      Map.put(common, "version", 1)
    end
  end
end
