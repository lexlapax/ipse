defmodule Ipse.Extension.CollectionMigrationTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection, as: C

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-migration-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    project = Ipse.JSON.sha256("admitted migration project")

    %{
      source: %{root: Path.join(parent, "source"), project: project},
      target: %{root: Path.join(parent, "target"), project: project}
    }
  end

  defp run(c, request, id \\ Ipse.Usage.id()), do: C.execute(c.root, c.project, request, id)

  defp put(generation, key, revision, value, floor \\ false),
    do: %{
      "op" => "commit",
      "expected_generation" => generation,
      "advance_floor" => floor,
      "changes" => [%{"key" => key, "expected_revision" => revision, "value" => value}]
    }

  defp seed(c, count) do
    changes =
      for n <- 1..count,
          do: %{
            "key" => "source#{n}",
            "expected_revision" => 0,
            "value" => %{
              "text" => "admitted source #{n}",
              "evidence" => %{"source" => n, "quote" => "original #{n}"}
            }
          }

    assert {:ok, receipt} =
             run(c, %{
               "op" => "commit",
               "expected_generation" => 0,
               "advance_floor" => false,
               "changes" => changes
             })

    receipt["generation"]
  end

  defp export(c, generation, after_key \\ nil, rows \\ []) do
    assert {:ok, page} =
             run(c, %{
               "op" => "export",
               "generation" => generation,
               "after" => after_key,
               "limit" => 32
             })

    rows = rows ++ page["records"]

    if page["next"] do
      export(c, generation, page["next"], rows)
    else
      Process.put({:operations, page["descriptor"]}, export_operations(c, generation))
      {page["descriptor"], rows}
    end
  end

  defp export_operations(c, generation, after_id \\ nil, rows \\ []) do
    assert {:ok, page} =
             run(c, %{
               "op" => "export.operations",
               "generation" => generation,
               "after" => after_id,
               "limit" => 128
             })

    rows = rows ++ page["operations"]
    if page["next"], do: export_operations(c, generation, page["next"], rows), else: rows
  end

  defp open(c, generation, descriptor) do
    id = Ipse.Usage.id()

    request = %{
      "op" => "import.open",
      "expected_generation" => generation,
      "descriptor" => descriptor
    }

    assert {:ok, receipt} = run(c, request, id)
    Process.put({:migration_operations, id}, Process.get({:operations, descriptor}, []))
    {id, receipt["generation"]}
  end

  defp pages(c, id, generation, rows) do
    generation =
      Enum.reduce(Enum.chunk_every(rows, 32), {generation, nil}, fn chunk,
                                                                    {generation, after_key} ->
        request = %{
          "op" => "import.page",
          "expected_generation" => generation,
          "migration_id" => id,
          "after" => after_key,
          "records" => Enum.map(chunk, &Map.take(&1, ~w(key value)))
        }

        page_id = Ipse.Usage.id()
        assert {:ok, receipt} = run(c, request, page_id)
        assert {:existing, %{"operation" => ^receipt}} = run(c, request, page_id)
        {receipt["generation"], List.last(chunk)["key"]}
      end)
      |> elem(0)

    Process.get({:migration_operations, id}, [])
    |> Enum.chunk_every(128)
    |> Enum.reduce({generation, nil}, fn chunk, {generation, after_id} ->
      assert {:ok, receipt} =
               run(c, %{
                 "op" => "import.operations",
                 "expected_generation" => generation,
                 "migration_id" => id,
                 "after" => after_id,
                 "operations" => chunk
               })

      {receipt["generation"], List.last(chunk)["operation_id"]}
    end)
    |> elem(0)
  end

  defp fixture_id(n),
    do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  test "typed complete import preserves managed original-normalized binding receipts", c do
    request = put(0, "note.one", 0, %{"text" => "original"}, true)

    normalized =
      Map.update!(
        request,
        "changes",
        &(&1 ++
            [
              %{
                "key" => "host.validity.one",
                "expected_revision" => 0,
                "value" => %{"anchor" => 0}
              }
            ])
      )

    operation = Ipse.Usage.id()

    assert {:ok, result} =
             C.execute_managed(
               c.source.root,
               c.source.project,
               request,
               operation,
               Ipse.JSON.sha256("recipe"),
               fn _, _ -> {:ok, normalized, %{"version" => 1}} end
             )

    {descriptor, rows} = export(c.source, 1)
    {migration, generation} = open(c.target, 0, descriptor)
    generation = pages(c.target, migration, generation, rows)

    assert {:ok, _} =
             run(c.target, %{
               "op" => "import.commit",
               "expected_generation" => generation,
               "migration_id" => migration
             })

    receipt = result["receipt"]

    assert {:ok, %{"operation" => ^receipt}} =
             run(c.target, %{"op" => "inspect", "operation_id" => operation})

    assert {:existing, %{"operation" => ^receipt}} =
             C.execute_managed(
               c.target.root,
               c.target.project,
               request,
               operation,
               Ipse.JSON.sha256("recipe"),
               fn _, _ -> flunk("imported operation cannot normalize again") end
             )

    assert {:ok, %{"record" => %{"value" => %{"anchor" => 0}}}} =
             run(c.target, %{"op" => "get", "key" => "host.validity.one"})

    assert Jason.decode!(File.read!(Path.join([c.target.root, c.target.project, "root.json"])))[
             "version"
           ] == 5
  end

  # These synthetic receipts exercise byte/count boundaries without performing
  # tens of thousands of IO operations. They are not endurance measurements.
  defp install_fixture(c, generation, count, offset, prefix) do
    assert {:ok, _} = run(c, %{"op" => "snapshot"})

    operations =
      Map.new(1..generation, fn n ->
        {fixture_id(offset + n),
         %{
           "generation" => n,
           "floor" => 0,
           "request_sha256" => Ipse.JSON.sha256("independent fixture #{offset}:#{n}")
         }}
      end)

    base = %{"text" => "", "evidence" => %{"source" => "bounded synthetic support"}}
    value = Map.put(base, "text", String.duplicate("x", 6144 - byte_size(Jason.encode!(base))))
    encoded = Ipse.Extension.Collection.Migration.encode(value)
    hash = Ipse.JSON.sha256(encoded)

    records =
      for n <- List.duplicate(nil, count) |> Enum.with_index(1), into: %{} do
        {_, index} = n
        key = "#{prefix}#{index}"

        {key,
         %{
           "key" => key,
           "revision" => 1,
           "sha256" => hash,
           "bytes" => 6144,
           "operation_id" => fixture_id(offset + 1)
         }}
      end

    state = %{
      "version" => 3,
      "project" => c.project,
      "generation" => generation,
      "floor" => 0,
      "records" => records,
      "operations" => operations,
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }

    path = Path.join(c.root, c.project)

    if count > 0 do
      object = Path.join([path, "objects", hash <> ".json"])
      File.write!(object, encoded)
      File.chmod!(object, 0o600)
    end

    bytes = Ipse.Extension.Collection.Encoding.encode(state)
    manifest = Ipse.JSON.sha256(bytes)
    file = Path.join([path, "manifests", manifest <> ".json"])
    File.write!(file, bytes)
    File.chmod!(file, 0o600)
    pointer = Path.join(path, "root.json")

    File.write!(
      pointer,
      Jason.encode!(
        Map.put(Map.take(state, ~w(version project generation floor)), "manifest", manifest)
      )
    )

    File.chmod!(pointer, 0o600)
  end

  test "opening an import reserves disjoint receipt identities and leaves no permanent fence",
       c do
    install_fixture(c.target, 32_763, 0, 0, "prior")
    install_fixture(c.source, 3, 0, 100_000, "source")
    {descriptor, []} = export(c.source, 3)

    assert {:failed, %{"code" => "collection_capacity"}} =
             run(c.target, %{
               "op" => "import.open",
               "expected_generation" => 32_763,
               "descriptor" => descriptor
             })

    assert {:ok, %{"generation" => 32_763, "migration" => nil}} =
             run(c.target, %{"op" => "status"})

    assert {:ok, _} = run(c.target, put(32_763, "still-writable", 0, %{}))
  end

  test "numeric newer floors from a divergent pre-forget fork cannot restore content", c do
    operation = Ipse.Usage.id()
    request = put(0, "forgotten", 0, %{"text" => "old support"})
    assert {:ok, _} = run(c.source, request, operation)
    assert {:ok, _} = run(c.target, request, operation)
    assert {:ok, _} = run(c.target, put(1, "forgotten", 1, nil, true))
    assert {:ok, _} = run(c.source, put(1, "fork-one", 0, %{}, true))
    assert {:ok, _} = run(c.source, put(2, "fork-two", 0, %{}, true))
    {descriptor, rows} = export(c.source, 3)
    assert descriptor["floor"] == 3
    {id, generation} = open(c.target, 2, descriptor)
    generation = pages(c.target, id, generation, rows)

    assert {:failed, %{"code" => "collection_import_lineage"}} =
             run(c.target, %{
               "op" => "import.commit",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert {:ok, %{"record" => nil, "floor" => 2}} =
             run(c.target, %{"op" => "get", "key" => "forgotten"})

    assert {:ok, _} =
             run(c.target, %{
               "op" => "import.abort",
               "expected_generation" => generation,
               "migration_id" => id
             })
  end

  test "a correction advances destructive lineage without deleting its record while a new addition does not",
       c do
    assert {:ok, _} = run(c.source, put(0, "claim", 0, %{"text" => "original"}))
    {descriptor, _} = export(c.source, 1)

    assert {:ok, %{"floor" => 0}} =
             run(c.source, put(1, "new-evidence", 0, %{"text" => "addition"}))

    assert {:ok, %{"floor" => 3}} =
             run(c.source, put(2, "claim", 1, %{"text" => "corrected"}, true))

    assert {:ok, %{"floor_anchor" => anchor}} = run(c.source, %{"op" => "snapshot"})

    assert is_binary(anchor)

    assert {:failed, %{"code" => "collection_import_floor"}} =
             run(c.source, %{
               "op" => "import.open",
               "expected_generation" => 3,
               "descriptor" => descriptor
             })

    assert {:ok, %{"record" => %{"value" => %{"text" => "corrected"}}}} =
             run(c.source, %{"op" => "get", "key" => "claim"})
  end

  test "reserved terminal capacity permits abort after all disjoint source IDs become known", c do
    install_fixture(c.target, 32_761, 0, 0, "prior")
    install_fixture(c.source, 3, 0, 100_000, "source")
    {descriptor, []} = export(c.source, 3)
    {id, generation} = open(c.target, 32_761, descriptor)
    generation = pages(c.target, id, generation, [])
    assert {:ok, %{"reserved_operation_slots" => 2}} = run(c.target, %{"op" => "status"})

    assert {:ok, receipt} =
             run(c.target, %{
               "op" => "import.abort",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert {:ok, %{"migration" => nil, "operations" => 32_767}} =
             run(c.target, %{"op" => "status"})

    assert {:ok, _} =
             run(c.target, put(receipt["generation"], "terminal-headroom-retained", 0, %{}))

    assert {:existing, _} =
             run(
               c.target,
               put(receipt["generation"], "never-replay", 0, %{}),
               fixture_id(100_001)
             )
  end

  test "a descendant export proves the exact destructive anchor before adopting a newer floor",
       c do
    operation = Ipse.Usage.id()
    request = put(0, "forgotten", 0, %{"text" => "old support"})
    assert {:ok, _} = run(c.source, request, operation)
    assert {:ok, _} = run(c.target, request, operation)
    forget_id = Ipse.Usage.id()
    forget = put(1, "forgotten", 1, nil, true)
    assert {:ok, forgotten} = run(c.source, forget, forget_id)
    assert {:ok, ^forgotten} = run(c.target, forget, forget_id)
    assert {:ok, _} = run(c.source, put(2, "new-source", 0, %{"text" => "later support"}, true))
    {descriptor, rows} = export(c.source, 3)
    {id, generation} = open(c.target, 2, descriptor)
    generation = pages(c.target, id, generation, rows)

    assert {:ok, %{"floor" => 3}} =
             run(c.target, %{
               "op" => "import.commit",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert {:ok, %{"record" => nil, "floor_anchor" => anchor}} =
             run(c.target, %{"op" => "get", "key" => "forgotten"})

    assert anchor == descriptor["floor_anchor"]

    assert {:ok, %{"operation" => ^forgotten}} =
             run(c.target, %{"op" => "inspect", "operation_id" => forget_id})
  end

  test "an aborted import receipt alias is not proof that the source applied a forget", c do
    shared = Ipse.Usage.id()
    request = put(0, "forgotten", 0, %{"text" => "old support"})
    assert {:ok, _} = run(c.source, request, shared)
    assert {:ok, _} = run(c.target, request, shared)
    assert {:ok, _} = run(c.target, put(1, "forgotten", 1, nil, true))
    {forgotten_descriptor, []} = export(c.target, 2)
    {staging, generation} = open(c.source, 1, forgotten_descriptor)
    generation = pages(c.source, staging, generation, [])

    assert {:ok, aborted} =
             run(c.source, %{
               "op" => "import.abort",
               "expected_generation" => generation,
               "migration_id" => staging
             })

    assert {:ok, advanced} = run(c.source, put(aborted["generation"], "fork-later", 0, %{}, true))
    {descriptor, rows} = export(c.source, advanced["generation"])
    {id, generation} = open(c.target, 2, descriptor)
    generation = pages(c.target, id, generation, rows)

    assert {:failed, %{"code" => "collection_import_lineage"}} =
             run(c.target, %{
               "op" => "import.commit",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert {:ok, %{"record" => nil}} = run(c.target, %{"op" => "get", "key" => "forgotten"})
  end

  @tag timeout: 300_000
  test "complete typed planning imports a near-full logical backup with all receipt IDs already known",
       c do
    # Shared fixture bytes intentionally isolate metadata/identity planning.
    # This is not a distinct-payload physical-capacity or latency qualification.
    install_fixture(c.target, 20_950, 4096, 0, "note")

    assert {:ok, %{"descriptor" => descriptor, "plan" => plan}} =
             run(c.target, %{"op" => "export.plan", "generation" => 20_950})

    assert {:failed, %{"code" => "collection_capacity"}} =
             run(c.target, %{
               "op" => "import.open",
               "expected_generation" => 20_950,
               "descriptor" => descriptor
             })

    assert {:ok, %{"record" => %{"value" => value}}} =
             run(c.target, %{"op" => "get", "key" => "note1"})

    rows = Enum.map(plan["records"], fn [key, _, _] -> %{"key" => key, "value" => value} end)
    id = Ipse.Usage.id()
    observer = "planned-upgrade-" <> Ipse.Usage.id()
    owner = self()
    observed_directory = Path.join(c.target.root, c.target.project)

    :ok =
      :telemetry.attach_many(
        observer,
        [
          [:ipse, :extension, :collection, :import_planned],
          [:ipse, :extension, :collection, :staged]
        ],
        fn event, measurements, _, _ ->
          if Process.get({C, :directory}) == observed_directory do
            case List.last(event) do
              :import_planned -> send(owner, {:import_trace, :plan, measurements.files})
              :staged -> send(owner, {:import_trace, :stage, nil})
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(observer) end)

    assert {:ok, opened} =
             run(
               c.target,
               %{
                 "op" => "import.open",
                 "expected_generation" => 20_950,
                 "descriptor" => descriptor,
                 "plan" => plan
               },
               id
             )

    assert_receive {:import_trace, kind, files}
    assert kind == :plan and files in 1..256
    assert_receive {:import_trace, :stage, nil}

    first = Enum.take(rows, 32)
    altered = List.update_at(first, 0, &put_in(&1, ["value", "text"], "substituted"))

    assert {:failed, %{"code" => "collection_import_plan"}} =
             run(c.target, %{
               "op" => "import.page",
               "expected_generation" => opened["generation"],
               "migration_id" => id,
               "after" => nil,
               "records" => altered
             })

    generation = pages(c.target, id, opened["generation"], rows)

    assert {:ok, committed} =
             run(c.target, %{
               "op" => "import.commit",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert {:ok, %{"records" => 4096, "envelope_data_bytes" => 25_165_824}} =
             run(c.target, %{"op" => "status"})

    assert {:ok, _} =
             run(c.target, %{
               "op" => "checkpoint.drop",
               "expected_generation" => committed["generation"]
             })
  end

  test "distinct staged and checkpoint references count toward the complete logical envelope",
       c do
    install_fixture(c.target, 1, 2500, 0, "prior")
    install_fixture(c.source, 1, 2500, 100_000, "source")
    {descriptor, rows} = export(c.source, 1)
    {id, generation} = open(c.target, 1, descriptor)

    result =
      Enum.reduce_while(Enum.chunk_every(rows, 32), {generation, nil}, fn chunk,
                                                                          {generation, after_key} ->
        result =
          run(c.target, %{
            "op" => "import.page",
            "expected_generation" => generation,
            "migration_id" => id,
            "after" => after_key,
            "records" => Enum.map(chunk, &Map.take(&1, ~w(key value)))
          })

        case result do
          {:ok, receipt} -> {:cont, {receipt["generation"], List.last(chunk)["key"]}}
          {:failed, %{"code" => "collection_capacity"}} -> {:halt, {:refused, generation}}
        end
      end)

    assert {:refused, generation} = result

    assert {:ok, %{"records" => 2500, "envelope_data_bytes" => bytes}} =
             run(c.target, %{"op" => "status"})

    assert bytes <= 24 * 1024 * 1024

    assert {:ok, _} =
             run(c.target, %{
               "op" => "import.abort",
               "expected_generation" => generation,
               "migration_id" => id
             })
  end

  test "complete typed export stages under a writer fence and atomically replaces active records with a rollback checkpoint",
       c do
    source_generation = seed(c.source, 70)
    {descriptor, rows} = export(c.source, source_generation)
    assert length(rows) == 70
    assert {:ok, _} = run(c.target, put(0, "prior", 0, %{"text" => "checkpoint support"}))
    {id, generation} = open(c.target, 1, descriptor)

    assert {:failed, %{"code" => "collection_writer_fenced"}} =
             run(c.target, put(generation, "racing", 0, %{}))

    assert {:ok, %{"record" => nil}} = run(c.target, %{"op" => "get", "key" => "source1"})

    assert {:failed, %{"code" => "collection_import_incomplete"}} =
             run(
               c.target,
               %{
                 "op" => "import.commit",
                 "expected_generation" => generation,
                 "migration_id" => id
               }
             )

    generation = pages(c.target, id, generation, rows)
    assert {:ok, %{"record" => nil}} = run(c.target, %{"op" => "get", "key" => "source1"})
    commit_id = Ipse.Usage.id()

    request = %{
      "op" => "import.commit",
      "expected_generation" => generation,
      "migration_id" => id
    }

    assert {:ok, committed} = run(c.target, request, commit_id)
    assert committed["checkpoint_id"] == commit_id
    assert {:existing, %{"operation" => ^committed}} = run(c.target, request, commit_id)
    assert {:ok, %{"record" => nil}} = run(c.target, %{"op" => "get", "key" => "prior"})

    assert {:ok, %{"record" => %{"value" => %{"text" => "admitted source 1"}}}} =
             run(c.target, %{"op" => "get", "key" => "source1"})

    assert {:ok, status} = run(c.target, %{"op" => "status"})
    assert status["checkpoint"]["id"] == commit_id
    assert status["accounted_allocated_bytes"] <= 64 * 1024 * 1024

    assert {:ok, _} =
             run(c.target, %{
               "op" => "rollback",
               "expected_generation" => committed["generation"],
               "checkpoint_id" => commit_id
             })

    assert {:ok, %{"record" => %{"value" => %{"text" => "checkpoint support"}}}} =
             run(c.target, %{"op" => "get", "key" => "prior"})

    assert {:ok, %{"record" => nil}} = run(c.target, %{"op" => "get", "key" => "source1"})

    assert {:ok, %{"operation" => ^committed}} =
             run(c.target, %{"op" => "inspect", "operation_id" => commit_id})

    [source_operation | _] = Process.get({:operations, descriptor})
    source_id = source_operation["operation_id"]

    assert {:ok, %{"operation" => imported_receipt}} =
             run(c.target, %{"op" => "inspect", "operation_id" => source_id})

    assert imported_receipt == source_operation["receipt"]
    assert {:ok, current} = run(c.target, %{"op" => "snapshot"})

    assert {:existing, %{"operation" => ^imported_receipt}} =
             run(c.target, put(current["generation"], "must-not-replay", 0, %{}), source_id)

    assert {:ok, %{"record" => nil}} = run(c.target, %{"op" => "get", "key" => "must-not-replay"})
  end

  test "operation ID collisions cannot rewrite a destination receipt during migration", c do
    shared_id = Ipse.Usage.id()
    assert {:ok, _} = run(c.source, put(0, "source", 0, %{"text" => "source"}), shared_id)
    assert {:ok, prior} = run(c.target, put(0, "prior", 0, %{"text" => "target"}), shared_id)
    {descriptor, [row]} = export(c.source, 1)
    {id, generation} = open(c.target, 1, descriptor)

    assert {:ok, paged} =
             run(c.target, %{
               "op" => "import.page",
               "expected_generation" => generation,
               "migration_id" => id,
               "after" => nil,
               "records" => [Map.take(row, ~w(key value))]
             })

    operations = Process.get({:operations, descriptor})

    assert {:failed, %{"code" => "collection_operation_identity"}} =
             run(
               c.target,
               %{
                 "op" => "import.operations",
                 "expected_generation" => paged["generation"],
                 "migration_id" => id,
                 "after" => nil,
                 "operations" => operations
               }
             )

    assert {:ok, %{"operation" => ^prior}} =
             run(c.target, %{"op" => "inspect", "operation_id" => shared_id})

    assert {:ok, %{"record" => %{"value" => %{"text" => "target"}}}} =
             run(c.target, %{"op" => "get", "key" => "prior"})
  end

  test "forget invalidates checkpoint rollback and rejects an old export floor", c do
    generation = seed(c.source, 2)
    {descriptor, rows} = export(c.source, generation)
    assert {:ok, _} = run(c.target, put(0, "prior", 0, %{"text" => "old content"}))
    {id, generation} = open(c.target, 1, descriptor)
    generation = pages(c.target, id, generation, rows)

    assert {:ok, committed} =
             run(c.target, %{
               "op" => "import.commit",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert {:ok, %{"record" => record}} = run(c.target, %{"op" => "get", "key" => "source1"})

    assert {:ok, forgotten} =
             run(c.target, put(committed["generation"], "source1", record["revision"], nil, true))

    assert {:failed, %{"code" => "collection_rollback_floor"}} =
             run(
               c.target,
               %{
                 "op" => "rollback",
                 "expected_generation" => forgotten["generation"],
                 "checkpoint_id" => committed["checkpoint_id"]
               }
             )

    assert {:failed, %{"code" => "collection_import_floor"}} =
             run(
               c.target,
               %{
                 "op" => "import.open",
                 "expected_generation" => forgotten["generation"],
                 "descriptor" => descriptor
               }
             )

    assert {:ok, %{"checkpoint" => nil}} = run(c.target, %{"op" => "status"})
  end

  test "ordered pages bind source digest and incomplete or altered payload cannot publish", c do
    generation = seed(c.source, 40)
    {descriptor, rows} = export(c.source, generation)
    {id, generation} = open(c.target, 0, descriptor)
    [first | _] = rows

    assert {:failed, %{"code" => "collection_import_state"}} =
             run(
               c.target,
               %{
                 "op" => "import.page",
                 "expected_generation" => generation,
                 "migration_id" => id,
                 "after" => nil,
                 "records" => [Map.take(first, ~w(key value))]
               }
             )

    altered = List.update_at(rows, 0, &put_in(&1, ["value", "text"], "altered payload"))
    generation = pages(c.target, id, generation, altered)

    assert {:failed, %{"code" => "collection_import_incomplete"}} =
             run(
               c.target,
               %{
                 "op" => "import.commit",
                 "expected_generation" => generation,
                 "migration_id" => id
               }
             )

    assert {:ok, %{"records" => 0}} = run(c.target, %{"op" => "status"})
    [source_operation | _] = Process.get({:operations, descriptor})

    assert {:ok, %{"operation" => staged_receipt}} =
             run(c.target, %{
               "op" => "inspect",
               "operation_id" => source_operation["operation_id"]
             })

    assert staged_receipt == source_operation["receipt"]

    assert {:existing, %{"generation" => ^generation, "operation" => ^staged_receipt}} =
             run(
               c.target,
               %{
                 "op" => "import.abort",
                 "expected_generation" => generation,
                 "migration_id" => id
               },
               source_operation["operation_id"]
             )

    assert {:ok, _} =
             run(c.target, %{
               "op" => "import.abort",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert Path.wildcard(Path.join([c.target.root, c.target.project, "objects", "*.json"])) == []

    assert {:ok, %{"operation" => receipt, "generation" => current}} =
             run(c.target, %{
               "op" => "inspect",
               "operation_id" => source_operation["operation_id"]
             })

    assert receipt == source_operation["receipt"]

    assert {:existing, _} =
             run(
               c.target,
               put(current, "must-not-replay-aborted-import", 0, %{}),
               source_operation["operation_id"]
             )

    assert {:ok, %{"record" => nil}} =
             run(c.target, %{"op" => "get", "key" => "must-not-replay-aborted-import"})
  end

  @tag timeout: 120_000
  test "2000 distinct maximum values migrate alongside a complete checkpoint under exact allocated quota",
       c do
    for {store, prefix} <- [{c.source, "source"}, {c.target, "prior"}] do
      Enum.reduce(Enum.chunk_every(1..2000, 128), 0, fn chunk, generation ->
        changes =
          for n <- chunk do
            value = %{"text" => "", "evidence" => %{"source" => "#{prefix}:#{n}"}}

            value =
              Map.put(
                value,
                "text",
                String.duplicate("x", 6144 - byte_size(Jason.encode!(value)))
              )

            %{"key" => "#{prefix}#{n}", "expected_revision" => 0, "value" => value}
          end

        assert {:ok, receipt} =
                 run(store, %{
                   "op" => "commit",
                   "expected_generation" => generation,
                   "advance_floor" => false,
                   "changes" => changes
                 })

        receipt["generation"]
      end)
    end

    assert {:ok, snapshot} = run(c.source, %{"op" => "snapshot"})
    {descriptor, rows} = export(c.source, snapshot["generation"])
    assert descriptor["records"] == 2000
    assert descriptor["data_bytes"] == 2000 * 6144
    assert {:ok, target_snapshot} = run(c.target, %{"op" => "snapshot"})
    {id, generation} = open(c.target, target_snapshot["generation"], descriptor)
    generation = pages(c.target, id, generation, rows)

    assert {:ok, %{"records" => 2000, "checkpoint" => nil} = staged} =
             run(c.target, %{"op" => "status"})

    assert staged["migration"]["id"] == id
    assert staged["accounted_allocated_bytes"] < 64 * 1024 * 1024

    assert {:ok, committed} =
             run(c.target, %{
               "op" => "import.commit",
               "expected_generation" => generation,
               "migration_id" => id
             })

    assert {:ok, %{"records" => 2000, "migration" => nil} = status} =
             run(c.target, %{"op" => "status"})

    assert status["checkpoint"]["id"] == committed["checkpoint_id"]
    assert status["accounted_allocated_bytes"] < 64 * 1024 * 1024
    assert {:ok, %{"record" => nil}} = run(c.target, %{"op" => "get", "key" => "prior1"})

    assert {:ok, %{"record" => %{"value" => value}}} =
             run(c.target, %{"op" => "get", "key" => "source1"})

    assert byte_size(Jason.encode!(value)) == 6144
  end
end
