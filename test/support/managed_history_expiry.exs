# Actual signed-history observations and deletion; future clock is a trusted test fixture.
defmodule Ipse.Test.ManagedHistoryExpiry do
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Usage}
  alias Ipse.Extension.{Collection, ProjectIdentity}
  alias Ipse.Extension.Collection.{ManagedPages, ManagedRetention, NormalizerV3, ObservedRead}
  alias Ipse.Session.ManagedLifecycle
  alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture

  def run(c, old, new, context, successor, writer) do
    old_key = hd(old.request["changes"])["key"]
    new_key = hd(new.request["changes"])["key"]
    request = %{"op" => "get_record", "key" => old_key}

    protect = fn fun ->
      ProjectIdentity.with_existing_domain_auth(
        c.home,
        c.cwd,
        c.binding,
        %{namespace: c.namespace, format: "managed-metadata-v3"},
        fun
      )
    end

    observe = fn ->
      protect.(fn cap, catalog ->
        ObservedRead.managed_history(c.root, c.namespace, request, cap, catalog, old.recipe)
      end)
    end

    assert {:ok, history} = observe.()
    assert history["metadata"]["category"] == "history"
    assert history["metadata"]["successor"]["key"] == new_key

    assert history["metadata"]["successor"]["sha256"] ==
             successor["observation"]["value"]["record"]["sha256"]

    now = System.system_time(:millisecond)
    assert ManagedRetention.eligible_history_metadata?(history["metadata"], now)
    deadline = history["metadata"]["valid_until_ms"]
    refute ManagedRetention.expired_history_metadata?(history["metadata"], deadline - 1)
    assert ManagedRetention.expired_history_metadata?(history["metadata"], deadline)

    refute ManagedRetention.expired_history_metadata?(
             %{history["metadata"] | "valid_until_ms" => nil},
             deadline
           )

    assert {:error, :managed_lifecycle_refused} =
             ManagedLifecycle.prepare_history_expiry(context, history, deadline - 1)

    assert {:error, :collection_observation_refused} =
             ObservedRead.managed_history(c.root, c.namespace, request, nil, %{}, old.recipe)

    assert {:error, :collection_observation_refused} =
             protect.(fn cap, catalog ->
               ObservedRead.managed_history(
                 c.root,
                 c.namespace,
                 %{"op" => "get_record", "key" => new_key},
                 cap,
                 catalog,
                 new.recipe
               )
             end)

    anchor = anchor(c, protect, history["metadata"]["lineage"])

    assert {:ok, backup} =
             Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())

    assert {:ok, prepared} = ManagedLifecycle.prepare_history_expiry(context, history, deadline)
    facts = prepared["facts"]
    assert :ok = Journal.Writer.append(writer, prepared["intent"])

    publish = fn checked_at ->
      ProjectIdentity.with_domain_publication(
        c.home,
        c.cwd,
        c.binding,
        %{
          namespace: c.namespace,
          format: "managed-metadata-v3",
          operation_id: facts["operation_id"],
          initialize: false
        },
        fn _ -> :ok end,
        fn cap, catalog ->
          Collection.execute_managed_v3(
            c.root,
            c.namespace,
            prepared["request"],
            facts["operation_id"],
            JSON.digest([old.recipe]),
            fn witness, read ->
              result =
                NormalizerV3.expire_history(witness, read, %{
                  request: prepared["request"],
                  facts: facts,
                  now_ms: checked_at,
                  domain_cap: cap,
                  catalog: catalog
                })

              {_, units, _} = Process.get({Collection, :managed_read})
              assert units <= 32
              result
            end
          )
        end
      )
    end

    assert {:error, :managed_normalization_refused} = publish.(deadline - 1)
    assert {:ok, ^history} = observe.()
    assert {:ok, core} = publish.(deadline)
    assert core["normalization"]["kind"] == "managed_literal_history_expiry"
    assert core["normalization"]["valid_until_ms"] == deadline

    assert :ok =
             Journal.Writer.append(writer, %{
               "type" => "managed_lifecycle_result",
               "operation_id" => facts["operation_id"],
               "outcome" => core
             })

    assert {:error, :collection_observation_refused} = observe.()
    assert anchor(c, protect, history["metadata"]["lineage"]) == anchor

    assert {:ok, current} =
             protect.(fn cap, catalog ->
               ObservedRead.managed_record(
                 c.root,
                 c.namespace,
                 %{"op" => "get_record", "key" => new_key},
                 cap,
                 catalog,
                 new.recipe
               )
             end)

    assert current["observation"]["value"]["record"] ==
             successor["observation"]["value"]["record"]

    assert {:ok, snapshot} =
             Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())

    assert snapshot["floor"] == snapshot["generation"]

    recapture = %{
      old
      | request: Map.put(old.request, "expected_generation", snapshot["generation"]),
        now_ms: deadline + 1
    }

    assert {:error, :managed_normalization_refused} =
             Fixture.publish(c, recapture, %{
               namespace: c.namespace,
               format: "managed-metadata-v3",
               operation_id: Usage.id(),
               initialize: false
             })

    old_import =
      %{recapture.request | "op" => "import"}
      |> Map.merge(%{"project" => c.namespace, "floor" => backup["floor"]})

    assert {:failed, %{"code" => "collection_import_floor"}} =
             Collection.execute(c.root, c.namespace, old_import, Usage.id())

    IO.puts("NATIVE_HISTORY_EXPIRY_PASSED")
  end

  defp anchor(c, protect, lineage) do
    protect.(fn cap, _catalog ->
      {:ok, view} = Collection.open_view(c.root, c.namespace)

      try do
        {:ok, neighbors} =
          Collection.view_neighbors(view, %{
            "version" => 1,
            "prefix" => ManagedPages.prefix(:anchor),
            "fence_bytes" => ManagedPages.width(:anchor),
            "needle" => lineage
          })

        key = neighbors["neighbors"]["selected"]["key"]
        {:ok, read} = Collection.view_read(view, %{"op" => "get_many", "keys" => [key]})
        assert read["witness"] == neighbors["witness"]
        [record] = read["records"]
        {:ok, page} = ManagedPages.open(cap, record, neighbors)
        {:ok, {record, page.entries[lineage]}}
      after
        assert :ok = Collection.close_view(view)
      end
    end)
  end
end
