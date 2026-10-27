unless Code.ensure_loaded?(Ipse.Test.NormalizerV3Fixture) do
  Code.require_file("collection_normalizer_v3_test.exs", __DIR__)
end

defmodule Ipse.Extension.CollectionNormalizerV3IntegrationTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.{ManagedPages, Migration, NormalizerV3}
  alias Ipse.Extension.ProjectIdentity, as: Identity
  alias Ipse.Test.NormalizerV3Fixture, as: F
  alias IpseKnowledge.Knowledge.Records
  alias Ipse.{JSON, Runner}
  @moduletag timeout: 120_000

  # Author integration controls, not independent qualification. Source members
  # are explicit trusted fixtures. Every Collection record/witness comes from
  # actual publication or checked actual read views; F.read/F.witness are unused.
  # Retain isolated stores, including failures, for read-only diagnostics.
  setup do
    base = Path.join(System.tmp_dir!(), "ipse-normalizer-v3-actual-" <> Ipse.Usage.id())

    for path <- [base, base <> "/home", base <> "/work"] do
      File.mkdir!(path)
      File.chmod!(path, 0o700)
    end

    {:ok, binding} = Identity.admit(base <> "/home", base <> "/work", :folder)
    {:ok, helper} = Runner.protected_helper(base <> "/work")

    assert JSON.sha256(File.read!(helper)) ==
             JSON.sha256(File.read!(Application.app_dir(:ipse, "priv/ipse-runner")))

    %{
      base: base,
      home: base <> "/home",
      cwd: base <> "/work",
      binding: binding,
      root: base <> "/collections",
      namespace: F.namespace()
    }
  end

  test "native absence initializes then actual active literal/proposal publications retain MAC provenance",
       c do
    assert {:ok, first} = publish(c, options(1, 0), scope(c), first: true)
    assert first.read_units == 19
    assert length(first.core["normalization"]["metadata_changes"]) == 3
    assert entry(c)["state"] == "active"
    first_format = first.format
    assert first_format["revision"] == 1

    assert {:ok, second} =
             publish(c, options(2, 1, "literal_source", "preference"), scope(c, false))

    assert second.read_units == 23
    assert second.format == first_format
    assert second.core["normalization"]["valid_until_ms"] == nil
    assert {:ok, third} = publish(c, options(3, 2, "proposal"), scope(c, false))
    assert third.format == first_format
    assert third.core["normalization"]["eligibility"] == "never_current"
    assert third.core["receipt"]["generation"] == 3
    assert third.live_revision == 3 and second.live_revision == 2
  end

  test "small actual series crosses the live leaf split without synthetic metadata seeding", c do
    assert {:ok, first} = publish(c, options(1, 0), scope(c), first: true)

    {last, split?} =
      Enum.reduce(2..27, {first, false}, fn n, {_, split?} ->
        assert {:ok, result} = publish(c, options(n, n - 1), scope(c, false))
        extras = result.core["normalization"]["metadata_changes"]

        split? =
          split? or
            Enum.count(extras, &String.starts_with?(&1["key"], ManagedPages.prefix(:live))) == 2

        assert result.read_units <= 24
        {result, split?}
      end)

    assert split?
    assert last.core["receipt"]["generation"] == 27
    assert last.format["revision"] == 1
  end

  test "actual stale generation and immutable operation identity bypass the normalizer callback",
       c do
    opts = options(1, 0)
    first_scope = scope(c)
    assert {:ok, first} = publish(c, opts, first_scope, first: true)
    root_sha = first.root_sha
    conflict_scope = scope(c, false)

    assert {:conflict, _} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               conflict_scope,
               fn _ -> :ok end,
               fn _cap, _catalog ->
                 C.execute_managed_v3(
                   c.root,
                   c.namespace,
                   options(2, 0).request,
                   conflict_scope.operation_id,
                   JSON.digest([opts.recipe]),
                   fn _, _ -> flunk("CAS conflict entered callback") end
                 )
               end
             )

    assert {:existing, _} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               %{first_scope | initialize: false},
               fn _ -> :ok end,
               fn _cap, _catalog ->
                 C.execute_managed_v3(
                   c.root,
                   c.namespace,
                   opts.request,
                   first_scope.operation_id,
                   JSON.digest([opts.recipe]),
                   fn _, _ -> flunk("immutable ID replay entered callback") end
                 )
               end
             )

    assert snapshot(c, [ManagedPages.format_key()])["witness"]["root_sha256"] == root_sha
  end

  test "an active namespace cannot reset metadata against an actually absent other store", c do
    assert {:ok, first} = publish(c, options(1, 0), scope(c), first: true)
    other = %{c | root: c.base <> "/other-collections"}

    assert {:error, :managed_normalization_refused} =
             publish(other, options(2, 0), scope(c, false))

    result = snapshot(other, [ManagedPages.format_key()])
    assert result["witness"]["root_state"] == "absent"
    assert result["records"] == [nil]
    assert entry(c)["state"] == "active"
    assert snapshot(c, [ManagedPages.format_key()])["witness"]["root_sha256"] == first.root_sha
  end

  test "actual present missing format and unsigned V2 pages cannot acquire V3 authority", c do
    assert {:ok, _} = publish(c, options(1, 0), scope(c), first: true)
    other = %{c | root: c.base <> "/unsigned-collections"}

    unsigned = %{
      "key" => "host.validity.anchor.00.0",
      "expected_revision" => 0,
      "value" => %{
        "version" => 2,
        "kind" => "anchor",
        "shard" => "00",
        "page" => 0,
        "entries" => %{}
      }
    }

    assert {:ok, _} =
             C.execute(
               other.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [unsigned]
               },
               Ipse.Usage.id()
             )

    before = snapshot(other, [ManagedPages.format_key(), unsigned["key"]])
    assert before["witness"]["root_state"] == "present" and hd(before["records"]) == nil

    assert {:error, :managed_normalization_refused} =
             publish(other, options(2, 1), scope(c, false))

    after_result = snapshot(other, [ManagedPages.format_key(), unsigned["key"]])
    assert after_result == before
    assert entry(c)["state"] == "active"
  end

  test "native owner loss after committed verified C result leaves Identity prepared and outcome unknown",
       c do
    first_scope = scope(c)
    assert {:unknown, _} = publish(c, options(1, 0), first_scope, first: true, lose_owner: true)
    assert entry(c)["state"] == "prepared"
    result = snapshot(c, [ManagedPages.format_key()])
    assert result["summary"]["generation"] == 1
    assert hd(result["records"])["operation_id"] == first_scope.operation_id

    assert {:ok, inspect_result} =
             C.execute(
               c.root,
               c.namespace,
               %{"op" => "inspect", "operation_id" => first_scope.operation_id},
               Ipse.Usage.id()
             )

    assert inspect_result["operation"]["generation"] == 1
    assert {:ok, c.binding} == Identity.existing(c.home, c.cwd)

    assert {:error, _} =
             Identity.with_domain_publication(
               c.home,
               c.cwd,
               c.binding,
               scope(c, false),
               fn _ -> :ok end,
               fn _, _ -> flunk("prepared unknown auto-replayed/reconciled") end
             )

    assert entry(c)["state"] == "prepared"

    assert snapshot(c, [ManagedPages.format_key()])["witness"]["root_sha256"] ==
             result["witness"]["root_sha256"]
  end

  defp options(n, generation, kind \\ "literal_source", category \\ "ordinary") do
    opts = F.options(kind, category, 86_400_000)

    source =
      F.proof()
      |> Map.put(
        "occurrence_id",
        Integer.to_string(n, 16) |> String.downcase() |> String.pad_leading(32, "0")
      )
      |> Map.put("receipt_sha256", F.hash("actual C synthetic source #{n}"))

    text = if kind == "proposal", do: "Acme may appoint Alex", else: source["quote"]

    {:ok, key, value} =
      Records.capture(
        %{
          "text" => text,
          "category" => category,
          "reason" => "trusted fixture source",
          "event_at_ms" => nil
        },
        source,
        10 * 86_400_000
      )

    %{
      opts
      | request: %{
          "op" => "commit",
          "expected_generation" => generation,
          "advance_floor" => true,
          "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]
        },
        verified_sources: [source]
    }
  end

  defp scope(c, initialize \\ true),
    do: %{
      namespace: c.namespace,
      format: "managed-metadata-v3",
      operation_id: Ipse.Usage.id(),
      initialize: initialize
    }

  defp publish(c, opts, scope, flags \\ []) do
    authorize = fn _binding ->
      if flags[:first] do
        absent = snapshot(c, [ManagedPages.format_key()])
        assert absent["witness"]["root_state"] == "absent"
        assert absent["witness"]["root"] == nil and absent["records"] == [nil]
      end

      :ok
    end

    Identity.with_domain_publication(c.home, c.cwd, c.binding, scope, authorize, fn cap,
                                                                                    catalog ->
      result =
        C.execute_managed_v3(
          c.root,
          c.namespace,
          opts.request,
          scope.operation_id,
          JSON.digest([opts.recipe]),
          fn witness, read ->
            outcome =
              NormalizerV3.normalize(
                witness,
                read,
                Map.merge(opts, %{domain_cap: cap, catalog: catalog})
              )

            {_, units, _} = Process.get({C, :managed_read})
            Process.put(:actual_v3_read_units, units)
            outcome
          end
        )

      case result do
        {:ok, core} ->
          verified = verify_publication(c, opts, scope, cap, core)

          value =
            Map.merge(verified, %{core: core, read_units: Process.get(:actual_v3_read_units)})

          if flags[:lose_owner] do
            controller = Process.get({Ipse.Runner.Transaction, :controller})
            assert is_pid(controller)
            monitor = Process.monitor(controller)
            Process.exit(controller, :kill)
            assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 2000
          end

          if catalog["state"] == "prepared" do
            witness = %{
              version: 1,
              namespace: scope.namespace,
              format: scope.format,
              fence_id: catalog["fence_id"],
              operation_id: scope.operation_id,
              root_sha256: value.root_sha
            }

            {:first_publication, witness, value}
          else
            {:ok, value}
          end

        other ->
          other
      end
    end)
  end

  defp verify_publication(c, opts, scope, cap, core) do
    receipt = core["receipt"]
    normalization = core["normalization"]
    key = hd(opts.request["changes"])["key"]

    keys =
      Enum.uniq(
        [ManagedPages.format_key(), key] ++
          Enum.map(normalization["metadata_changes"], & &1["key"])
      )

    assert length(keys) <= 8
    {:ok, view} = C.open_view(c.root, c.namespace)

    try do
      {:ok, result} = C.view_read(view, %{"op" => "get_many", "keys" => keys})
      assert result["witness"]["root_state"] == "present"
      assert result["summary"]["generation"] == receipt["generation"]
      assert result["summary"]["floor"] == receipt["floor"]
      assert result["witness"]["root"]["generation"] == receipt["generation"]
      assert result["witness"]["root"]["manifest"] == result["witness"]["manifest_sha256"]
      assert receipt["generation"] == opts.request["expected_generation"] + 1
      records = Map.new(Enum.zip(keys, result["records"]))

      extras =
        Enum.map(normalization["metadata_changes"], fn change ->
          stored = records[change["key"]]

          %{
            "key" => change["key"],
            "expected_revision" => change["expected_revision"],
            "value" => if(stored, do: stored["value"])
          }
        end)

      normalized = Map.update!(opts.request, "changes", &(&1 ++ extras))
      assert receipt["request_sha256"] == JSON.digest([normalized])
      assert core["binding"]["original_request_sha256"] == JSON.digest([opts.request])
      assert core["binding"]["normalization_sha256"] == JSON.digest([normalization])
      assert core["binding"]["recipe_sha256"] == JSON.digest([opts.recipe])
      assert receipt["managed_binding_sha256"] == JSON.digest([core["binding"]])
      record = records[key]
      assert record["value"] == hd(opts.request["changes"])["value"]

      assert record["revision"] == receipt["generation"] and
               record["operation_id"] == scope.operation_id

      assert record["sha256"] == JSON.sha256(Migration.encode(record["value"]))
      assert {:ok, _} = ManagedPages.open_format(cap, records[ManagedPages.format_key()])
      assert normalization["format_value_sha256"] == records[ManagedPages.format_key()]["sha256"]

      Enum.each(normalization["metadata_changes"], fn change ->
        current = records[change["key"]]

        if is_nil(change["value_sha256"]) do
          assert current == nil and change["expected_revision"] > 0
        else
          assert current["revision"] == receipt["generation"] and
                   current["operation_id"] == scope.operation_id

          assert current["sha256"] == change["value_sha256"]

          if current["key"] != ManagedPages.format_key(),
            do: checked_page(view, cap, current, result)
        end
      end)

      live_id = ManagedPages.live_identity(key)

      {:ok, neighbors} =
        C.view_neighbors(view, %{
          "version" => 1,
          "prefix" => ManagedPages.prefix(:live),
          "fence_bytes" => 33,
          "needle" => live_id
        })

      live_key = neighbors["neighbors"]["selected"]["key"]
      {:ok, selected} = C.view_read(view, %{"op" => "get_many", "keys" => [live_key]})
      assert selected["witness"] == result["witness"]
      [live_record] = selected["records"]
      assert {:ok, page} = ManagedPages.open(cap, live_record, neighbors)

      [lineage, value, recipe, policy, first, deadline, category, eligibility] =
        page.entries[live_id]

      assert lineage == packed(normalization["lineage"]) and value == packed(record["sha256"])
      assert recipe == packed(JSON.digest([opts.recipe])) and policy == packed(opts.policy_sha256)
      assert String.to_integer(first, 36) == normalization["first_admitted_ms"]
      assert if(deadline, do: String.to_integer(deadline, 36)) == normalization["valid_until_ms"]

      assert category ==
               %{"ordinary" => 0, "preference" => 1, "current" => 2}[normalization["category"]]

      assert eligibility == if(normalization["eligibility"] == "current", do: 0, else: 1)

      %{
        format: records[ManagedPages.format_key()],
        root_sha: result["witness"]["root_sha256"],
        live_revision: live_record["revision"]
      }
    after
      assert :ok = C.close_view(view)
    end
  end

  defp checked_page(view, cap, record, snapshot) do
    kind =
      if String.starts_with?(record["key"], ManagedPages.prefix(:anchor)),
        do: :anchor,
        else: :live

    fence = String.replace_prefix(record["key"], ManagedPages.prefix(kind), "")

    {:ok, neighbors} =
      C.view_neighbors(view, %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(kind),
        "fence_bytes" => ManagedPages.width(kind),
        "needle" => fence
      })

    assert neighbors["witness"] == snapshot["witness"]
    assert {:ok, _} = ManagedPages.open(cap, record, neighbors)
  end

  defp snapshot(c, keys) do
    {:ok, view} = C.open_view(c.root, c.namespace)

    try do
      {:ok, result} = C.view_read(view, %{"op" => "get_many", "keys" => keys})
      result
    after
      assert :ok = C.close_view(view)
    end
  end

  defp packed(hash), do: Base.url_encode64(Base.decode16!(hash, case: :lower), padding: false)

  defp entry(c) do
    state = (c.home <> "/project-identities/index.json") |> File.read!() |> Jason.decode!()
    state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]
  end
end
