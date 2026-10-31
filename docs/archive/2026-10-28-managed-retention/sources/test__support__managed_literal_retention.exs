# Real native review, DomainAuth and Core publications; source members and past
# admission clocks are explicit trusted fixtures, not live Session provenance.
ExUnit.start(autorun: false)
Code.require_file("../ipse/extension/collection_normalizer_v3_integration_test.exs", __DIR__)
import ExUnit.Assertions
alias Ipse.{JSON, Journal, Usage}
alias Ipse.Extension.{Collection, ProjectIdentity}
alias Ipse.Extension.Collection.{ManagedRetention, NormalizerV3, ObservedRead}
alias Ipse.Session.{ManagedLifecycle, ManagedReference, Resources}
alias Ipse.Runner.Review
alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture

[base] = System.argv()
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

now = System.system_time(:millisecond)
day = 86_400_000

options =
  for {n, category, first} <- [
        {1, "ordinary", now - day},
        {2, "ordinary", now - 91 * day},
        {3, "current", now - day}
      ] do
    opts = %{Fixture.options(n, n - 1, "literal_source", category) | now_ms: first}

    scope = %{
      namespace: c.namespace,
      format: "managed-metadata-v3",
      operation_id: Usage.id(),
      initialize: n == 1
    }

    assert {:ok, _} = Fixture.publish(c, opts, scope, first: n == 1)
    opts
  end

[ordinary, expired, current] = options

assert :ok =
         Resources.file_effect(fn ->
           {:ok, id} =
             Journal.create(base <> "/journal", %{"kind" => "synthetic_native_retention"})

           {:ok, writer} = Journal.Writer.start(base <> "/journal", id, self())

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
             "recipe" => ordinary.recipe
           }

           protect = fn fun ->
             ProjectIdentity.with_existing_domain_auth(
               c.home,
               c.cwd,
               c.binding,
               %{namespace: c.namespace, format: "managed-metadata-v3"},
               fun
             )
           end

           observe = fn opts ->
             key = hd(opts.request["changes"])["key"]

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
           end

           pin = %{
             "version" => 1,
             "session_id" => id,
             "project_id" => binding["project_id"],
             "worktree_id" => binding["worktree_id"],
             "binding_sha256" => binding["binding_sha256"],
             "epoch" => 1,
             "policy_sha256" => JSON.sha256("trusted current fixture policy"),
             "identity_sha256" => JSON.sha256("trusted fixture identity"),
             "namespace" => c.namespace,
             "routes_sha256" => JSON.sha256("trusted fixture routes"),
             "source_sha256" => JSON.sha256("trusted fixture sources")
           }

           dependency = fn opts, managed ->
             request = %{"op" => "get_record", "key" => hd(opts.request["changes"])["key"]}

             ObservedRead.managed_dependency(
               request,
               managed,
               pin,
               opts.recipe,
               opts.verified_sources,
               System.system_time(:millisecond)
             )
           end

           prepare = fn opts, policy ->
             {:ok, observed} = observe.(opts)

             assert {:ok, prepared} =
                      ManagedLifecycle.prepare_retention(
                        %{context | "job_id" => Usage.id(), "recipe" => opts.recipe},
                        observed,
                        policy,
                        "Native fixture selected this exact policy"
                      )

             assert :ok = Journal.Writer.append(writer, prepared["intent"])
             {prepared, observed}
           end

           publish = fn prepared, permit, facts ->
             function =
               if facts["kind"] == "managed_literal_forget",
                 do: &NormalizerV3.forget/3,
                 else: &NormalizerV3.retain/3

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
                   JSON.digest([facts["context"]["recipe"]]),
                   fn witness, read ->
                     result =
                       function.(witness, read, %{
                         request: prepared["request"],
                         facts: facts,
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

           choose = fn opts, policy ->
             {prepared, before} = prepare.(opts, policy)
             facts = prepared["facts"]

             assert {:ok, core} =
                      Review.with_review(ManagedRetention.command(policy), facts, fn permit ->
                        try do
                          assert {:ok, core} = publish.(prepared, permit, facts)
                          assert core["normalization"]["action_sha256"] == facts["action_sha256"]

                          assert {:error, :native_review_refused} =
                                   Review.consume(permit, ManagedRetention.command(policy), facts)

                          {:ok, core}
                        rescue
                          error ->
                            IO.puts(Exception.format(:error, error, __STACKTRACE__))
                            reraise error, __STACKTRACE__
                        end
                      end)

             assert :ok =
                      Journal.Writer.append(writer, %{
                        "type" => "managed_lifecycle_result",
                        "operation_id" => facts["operation_id"],
                        "outcome" => core
                      })

             {core, before, prepared}
           end

           try do
             {:ok, original} = observe.(ordinary)
             assert {:ok, old_dependency} = dependency.(ordinary, original)
             {pin_core, _, _} = choose.(ordinary, %{"kind" => "pin"})
             assert pin_core["normalization"]["category"] == "pin"
             assert pin_core["normalization"]["valid_until_ms"] == nil
             {:ok, pinned} = observe.(ordinary)

             assert pinned["observation"]["value"]["record"]["value"] ==
                      original["observation"]["value"]["record"]["value"]

             assert pinned["metadata"]["first_admitted_ms"] ==
                      original["metadata"]["first_admitted_ms"]

             assert {:ok, new_dependency} = dependency.(ordinary, pinned)

             refute ManagedReference.current?(
                      old_dependency,
                      new_dependency,
                      System.system_time(:millisecond)
                    )

             assert ManagedReference.current?(
                      new_dependency,
                      new_dependency,
                      System.system_time(:millisecond)
                    )

             {ordinary_core, _, ordinary_prepared} = choose.(ordinary, %{"kind" => "ordinary"})
             assert ordinary_prepared["facts"]["historical_gap"]
             {:ok, reduced} = observe.(ordinary)

             assert ordinary_core["normalization"]["valid_until_ms"] ==
                      reduced["metadata"]["choice"]["observed_at_ms"] + 90 * day

             {duration_core, _, _} =
               choose.(ordinary, %{"kind" => "duration", "duration_ms" => 2 * day})

             {:ok, shortened} = observe.(ordinary)

             assert duration_core["normalization"]["valid_until_ms"] ==
                      shortened["metadata"]["choice"]["observed_at_ms"] + 2 * day

             assert shortened["metadata"]["first_admitted_ms"] ==
                      original["metadata"]["first_admitted_ms"]

             {_, _, current_prepared} = choose.(current, %{"kind" => "ordinary"})
             assert current_prepared["facts"]["historical_gap"]
             assert is_binary(current_prepared["facts"]["historical_gap_notice"])

             # Expired unchanged support cannot be pinned, even after a real new review.
             {expired_prepared, expired_observed} = prepare.(expired, %{"kind" => "pin"})
             facts = expired_prepared["facts"]

             assert {:error, :managed_normalization_refused} =
                      Review.with_review("pin", facts, fn permit ->
                        assert {:error, :managed_normalization_refused} =
                                 publish.(expired_prepared, permit, facts)

                        assert :ok = Review.check(permit, "pin", facts)
                        {:error, :managed_normalization_refused}
                      end)

             assert observe.(expired) == {:ok, expired_observed}

             # Changed job facts spend/refuse the native permit and leave the target exact.
             {changed_prepared, changed_observed} = prepare.(ordinary, %{"kind" => "pin"})
             facts = changed_prepared["facts"]

             assert {:error, :native_review_refused} =
                      Review.with_review("pin", facts, fn permit ->
                        changed = put_in(facts, ["context", "job_id"], Usage.id())

                        changed =
                          Map.put(
                            changed,
                            "action_sha256",
                            JSON.digest([Map.delete(changed, "action_sha256")])
                          )

                        assert {:error, :managed_normalization_refused} =
                                 publish.(changed_prepared, permit, changed)

                        assert {:error, :native_review_refused} =
                                 Review.check(permit, "pin", facts)

                        {:error, :changed_facts}
                      end)

             assert observe.(ordinary) == {:ok, changed_observed}

             # The saved native choice remains suppressing when the selected derivative is removed.
             {forget_core, _, _} = choose.(ordinary, %{"kind" => "session"})
             assert forget_core["normalization"]["kind"] == "native_literal_forget"
             assert {:error, :collection_observation_refused} = observe.(ordinary)

             {:ok, snapshot} =
               Collection.execute(c.root, c.namespace, %{"op" => "snapshot"}, Usage.id())

             recapture = %{
               ordinary
               | request:
                   Map.put(ordinary.request, "expected_generation", snapshot["generation"]),
                 now_ms: System.system_time(:millisecond)
             }

             scope = %{
               namespace: c.namespace,
               format: "managed-metadata-v3",
               operation_id: Usage.id(),
               initialize: false
             }

             assert {:error, :managed_normalization_refused} =
                      Fixture.publish(c, recapture, scope)

             :ok
           after
             :ok = Journal.Writer.close(writer)
           end
         end)

IO.puts("NATIVE_LITERAL_RETENTION_AND_CURRENT_READER_PASSED")
