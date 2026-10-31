# Actual Core/DomainAuth/native-review controls. Initial note sources are trusted
# synthetic fixture members; these checks do not claim Session or model origin.
ExUnit.start(autorun: false)
Code.require_file("../ipse/extension/collection_normalizer_v3_integration_test.exs", __DIR__)
import ExUnit.Assertions
alias Ipse.{JSON, Journal, Usage}
alias Ipse.Extension.{Collection, ProjectIdentity}
alias Ipse.Extension.Collection.{ManagedPages, NormalizerV3, ObservedRead}
alias Ipse.Session.{ManagedLifecycle, Resources}
alias Ipse.Runner.Review
alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture

[base, scenario] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)

for path <- [base <> "/home", base <> "/work"] do
  File.mkdir!(path)
  File.chmod!(path, 0o700)
end

{:ok, binding} = ProjectIdentity.admit(base <> "/home", base <> "/work", :folder)

c = %{
  home: base <> "/home",
  cwd: base <> "/work",
  binding: binding,
  root: base <> "/collections",
  namespace: Ipse.Test.NormalizerV3Fixture.namespace()
}

scope = %{
  namespace: c.namespace,
  format: "managed-metadata-v3",
  operation_id: Usage.id(),
  initialize: true
}

opts = Fixture.options(1, 0)
assert {:ok, _} = Fixture.publish(c, opts, scope, first: true)
[original] = opts.request["changes"]
key = original["key"]
{:ok, backup} = Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())

outcome =
  Resources.file_effect(fn ->
    # A real owner-only writer is used before the actual Core publication. The
    # product's distinct management Consent transaction is integrated separately.
    {:ok, id} = Journal.create(base <> "/journal", %{"kind" => "synthetic_native_management"})
    {:ok, writer} = Journal.Writer.start(base <> "/journal", id, self())

    protect = fn fun ->
      ProjectIdentity.with_existing_domain_auth(
        c.home,
        c.cwd,
        c.binding,
        %{namespace: c.namespace, format: "managed-metadata-v3"},
        fun
      )
    end

    try do
      {:ok, observed} =
        protect.(fn cap, catalog ->
          ObservedRead.managed_record(
            c.root,
            c.namespace,
            %{"op" => "get_record", "key" => key},
            cap,
            catalog,
            opts.recipe
          )
        end)

      context = %{
        "session_id" => id,
        "job_id" => Usage.id(),
        "client_id" => Usage.id(),
        "project_id" => binding["project_id"],
        "namespace" => c.namespace,
        "binding_sha256" => binding["binding_sha256"],
        "management_epoch" => 0,
        "management_sha256" => JSON.digest(["management.v1", binding["project_id"], 0, nil]),
        "original_pin" => nil,
        "recipe" => opts.recipe
      }

      {:ok, prepared} =
        ManagedLifecycle.prepare(context, observed, "Forget selected synthetic claim")

      facts = prepared["facts"]
      assert :ok = Journal.Writer.append(writer, prepared["intent"])

      publish = fn permit, selected_facts ->
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
              JSON.digest([opts.recipe]),
              fn witness, read ->
                result =
                  NormalizerV3.forget(witness, read, %{
                    request: prepared["request"],
                    facts: selected_facts,
                    permit: permit,
                    now_ms: System.system_time(:millisecond),
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

      # JSON, nil and cross-owner lookalikes cannot authorize even a perfectly
      # signed target. A genuine permit is checked in the same Core callback.
      for forged <- [nil, %{"kind" => "native_review", "origin" => "native_operator"}] do
        assert {:error, :managed_normalization_refused} = publish.(forged, facts)
      end

      assert {:ok, :native} = Ipse.Runner.operator_channel()
      assert Resources.active?()
      assert Process.alive?(Resources.file_effect_owner())
      assert JSON.validate_object(facts) == :ok
      assert byte_size(Jason.encode!(facts)) <= 16_384

      result =
        Review.with_review("forget", facts, fn permit ->
          Process.put(:managed_forget_review_entered, true)

          if scenario == "changed" do
            changed = put_in(facts, ["context", "client_id"], Usage.id())

            changed =
              Map.put(
                changed,
                "action_sha256",
                JSON.digest([Map.delete(changed, "action_sha256")])
              )

            assert {:error, :managed_normalization_refused} = publish.(permit, changed)
            assert {:error, :managed_normalization_refused} = publish.(permit, facts)
            {:error, :changed_management_facts}
          else
            assert {:ok, core} = publish.(permit, facts)
            assert core["normalization"]["kind"] == "native_literal_forget"
            assert core["normalization"]["action_sha256"] == facts["action_sha256"]
            assert core["receipt"]["floor"] > backup["floor"]
            assert {:existing, _} = publish.(permit, facts)
            assert {:error, :native_review_refused} = Review.consume(permit, "forget", facts)
            {:ok, core}
          end
        end)

      assert Process.get(:managed_forget_review_entered, false) == (scenario != "cancel")

      case scenario do
        "valid" ->
          assert {:ok, core} = result

          assert :ok =
                   Journal.Writer.append(writer, %{
                     "type" => "managed_lifecycle_result",
                     "operation_id" => facts["operation_id"],
                     "outcome" => core
                   })

          assert {:ok, %{"record" => nil}} =
                   Collection.execute(
                     c.root,
                     c.namespace,
                     %{"op" => "get", "key" => key},
                     Usage.id()
                   )

          # Same-support automatic capture cannot erase the signed suppression.
          next = %{opts | request: Map.put(opts.request, "expected_generation", 2)}

          assert {:error, :managed_normalization_refused} =
                   Fixture.publish(c, next, %{scope | operation_id: Usage.id(), initialize: false})

          # An old backup cannot restore the deleted public note after the floor.
          import_request =
            %{next.request | "op" => "import"}
            |> Map.merge(%{"project" => c.namespace, "floor" => backup["floor"]})

          assert {:failed, %{"code" => "collection_import_floor"}} =
                   Collection.execute(c.root, c.namespace, import_request, Usage.id())

          # Authenticate the retained anchor after Core has reclaimed old objects.
          assert {:ok, :retained} =
                   protect.(fn cap, _ ->
                     {:ok, view} = Collection.open_view(c.root, c.namespace)

                     try do
                       lineage = observed["metadata"]["lineage"]

                       {:ok, neighbors} =
                         Collection.view_neighbors(view, %{
                           "version" => 1,
                           "prefix" => ManagedPages.prefix(:anchor),
                           "fence_bytes" => ManagedPages.width(:anchor),
                           "needle" => lineage
                         })

                       anchor_key = neighbors["neighbors"]["selected"]["key"]

                       {:ok, page} =
                         Collection.view_read(view, %{"op" => "get_many", "keys" => [anchor_key]})

                       [record] = page["records"]
                       {:ok, opened} = ManagedPages.open(cap, record, neighbors)
                       anchor = opened.entries[lineage]
                       assert anchor["choice"]["kind"] == "native_management"
                       assert anchor["choice"]["policy"] == %{"kind" => "session"}

                       assert anchor["choice"]["target_value_sha256"] ==
                                observed["observation"]["value"]["record"]["sha256"]

                       assert anchor["retirement"]["target_kind"] == "native_literal_note"
                       assert anchor["clocks"] == [86_400_000, 91 * 86_400_000, nil, nil]
                       {:ok, :retained}
                     after
                       :ok = Collection.close_view(view)
                     end
                   end)

        "changed" ->
          assert {:error, :native_review_refused} = result

        "cancel" ->
          assert {:error, :native_review_refused} = result
      end

      unless scenario == "valid" do
        assert {:ok, ^backup} =
                 Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())
      end

      {:ok, scenario}
    after
      :ok = Journal.Writer.close(writer)
    end
  end)

assert {:ok, ^scenario} = outcome
IO.puts("NATIVE_MANAGED_LITERAL_FORGET_" <> String.upcase(scenario) <> "_PASSED")
