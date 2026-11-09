unless Code.ensure_loaded?(Ipse.Extension.CollectionNormalizerV3IntegrationTest) do
  Code.require_file("collection_normalizer_v3_integration_test.exs", __DIR__)
end

defmodule Ipse.Extension.CollectionExpiryNativeTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage
  alias Ipse.{JSON, Journal, Usage}
  alias Ipse.Extension.{Collection, ProjectIdentity}
  alias Ipse.Extension.Collection.{ManagedPages, NormalizerV3, ObservedRead}
  alias Ipse.Session.{ManagedLifecycle, Resources}
  alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture
  @day 86_400_000

  setup do
    base = Path.join(System.tmp_dir!(), "ipse-managed-expiry-" <> Usage.id())

    for path <- [base, base <> "/home", base <> "/work"] do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    {:ok, binding} = ProjectIdentity.admit(base <> "/home", base <> "/work", :folder)

    %{
      base: base,
      home: base <> "/home",
      cwd: base <> "/work",
      binding: binding,
      root: base <> "/collections",
      namespace: Ipse.Test.NormalizerV3Fixture.namespace()
    }
  end

  defp observe(c, opts) do
    ProjectIdentity.with_existing_domain_auth(
      c.home,
      c.cwd,
      c.binding,
      %{namespace: c.namespace, format: "managed-metadata-v3"},
      fn cap, catalog ->
        ObservedRead.managed_record(
          c.root,
          c.namespace,
          %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]},
          cap,
          catalog,
          opts.recipe
        )
      end
    )
  end

  defp context(c, recipe, id) do
    %{
      "session_id" => id,
      "job_id" => Usage.id(),
      "client_id" => Usage.id(),
      "project_id" => c.binding["project_id"],
      "namespace" => c.namespace,
      "binding_sha256" => c.binding["binding_sha256"],
      "management_epoch" => 1,
      "management_sha256" => JSON.digest(["management.v1", c.binding["project_id"], 1, nil]),
      "original_pin" => nil,
      "recipe" => recipe
    }
  end

  defp expire(c, prepared, now, transform \\ & &1) do
    facts = prepared["facts"]

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
      fn actual ->
        if actual === c.binding, do: :ok, else: {:error, :changed_binding}
      end,
      fn cap, catalog ->
        Collection.execute_managed_v3(
          c.root,
          c.namespace,
          prepared["request"],
          facts["operation_id"],
          JSON.digest([facts["context"]["recipe"]]),
          fn witness, read ->
            options =
              transform.(%{
                request: prepared["request"],
                facts: facts,
                now_ms: now,
                domain_cap: cap,
                catalog: catalog
              })

            options =
              put_in(
                options.facts["action_sha256"],
                JSON.digest([Map.delete(options.facts, "action_sha256")])
              )

            NormalizerV3.expire(witness, read, options)
          end
        )
      end
    )
  end

  defp get(c, key),
    do: Collection.execute(c.root, c.namespace, %{"op" => "get", "key" => key}, Usage.id())

  @tag :managed_expiry
  @tag :managed_expiry_native
  test "actual signed expiry preserves clocks, refuses persistent or forged targets and fences recapture/import",
       c do
    now = System.system_time(:millisecond)

    options =
      for {n, category, first} <- [
            {1, "ordinary", now - 91 * @day},
            {2, "ordinary", now - @day},
            {3, "preference", now - 200 * @day},
            {4, "current", now - 200 * @day}
          ] do
        opts = %{Fixture.options(n, n - 1, "literal_source", category) | now_ms: first}

        assert {:ok, _} =
                 Fixture.publish(
                   c,
                   opts,
                   %{
                     namespace: c.namespace,
                     format: "managed-metadata-v3",
                     operation_id: Usage.id(),
                     initialize: n == 1
                   },
                   first: n == 1
                 )

        opts
      end

    [expired | persistent] = options
    {:ok, selected} = observe(c, expired)
    root_path = Path.join([c.root, c.namespace, "root.json"])
    before = File.read!(root_path)
    anchor_key = ManagedPages.page_key(:anchor, ManagedPages.zero(:anchor))
    {:ok, anchor_before} = get(c, anchor_key)
    {:ok, backup} = Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())

    assert :ok =
             Resources.file_effect(fn ->
               {:ok, id} =
                 Journal.create(c.base <> "/journal", %{"kind" => "synthetic_managed_expiry"})

               {:ok, writer} = Journal.Writer.start(c.base <> "/journal", id, self())
               context = context(c, expired.recipe, id)

               try do
                 for opts <- persistent do
                   {:ok, managed} = observe(c, opts)

                   assert {:error, :managed_lifecycle_refused} =
                            ManagedLifecycle.prepare_expiry(
                              %{context | "recipe" => opts.recipe},
                              managed,
                              now
                            )
                 end

                 assert {:ok, prepared} = ManagedLifecycle.prepare_expiry(context, selected, now)
                 assert :ok = Journal.Writer.append(writer, prepared["intent"])

                 assert {:error, :managed_normalization_refused} =
                          expire(c, prepared, selected["metadata"]["valid_until_ms"] - 1)

                 for change <- [
                       fn o -> %{o | domain_cap: nil} end,
                       fn o -> put_in(o.facts["metadata"]["valid_until_ms"], 0) end,
                       fn o ->
                         put_in(o.facts["target"]["sha256"], JSON.sha256("substituted"))
                       end,
                       fn o -> put_in(o.facts["checked_at_ms"], now + 1) end
                     ] do
                   assert {:error, :managed_normalization_refused} =
                            expire(c, prepared, now, change)

                   assert File.read!(root_path) == before
                 end

                 assert {:ok, core} = expire(c, prepared, now)
                 receipt = core["normalization"]

                 assert receipt["kind"] == "managed_literal_expiry" and
                          receipt["eligibility"] == "expired"

                 assert receipt["first_admitted_ms"] == selected["metadata"]["first_admitted_ms"]
                 assert receipt["valid_until_ms"] == selected["metadata"]["valid_until_ms"]
                 refute Map.has_key?(receipt, "native_review_sha256")
                 assert length(receipt["metadata_changes"]) <= 3
                 assert byte_size(Jason.encode!(receipt)) <= 2048
                 assert core["receipt"]["floor"] > backup["floor"]
                 assert {:ok, %{"record" => nil}} = get(c, prepared["facts"]["target"]["key"])
                 assert {:ok, anchor_after} = get(c, anchor_key)
                 assert anchor_after["record"] === anchor_before["record"]

                 assert :ok =
                          Journal.Writer.append(writer, %{
                            "type" => "managed_lifecycle_result",
                            "operation_id" => prepared["facts"]["operation_id"],
                            "outcome" => core
                          })

                 {:ok, snapshot} =
                   Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())

                 recapture = %{
                   expired
                   | now_ms: now,
                     request:
                       Map.put(expired.request, "expected_generation", snapshot["generation"])
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

                 :ok
               after
                 :ok = Journal.Writer.close(writer)
               end
             end)
  end
end
