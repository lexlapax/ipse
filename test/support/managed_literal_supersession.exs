# Actual native review, Identity, and Core, with trusted synthetic source receipts.
ExUnit.start(autorun: false)
Code.require_file("../ipse/extension/collection_normalizer_v3_integration_test.exs", __DIR__)
import ExUnit.Assertions
alias Ipse.{JSON, Journal, Usage}
alias Ipse.Extension.{Collection, ManagedRecipe, ProjectIdentity}
alias Ipse.Extension.Collection.{ManagedPages, ManagedRetention, NormalizerV3, ObservedRead}
alias Ipse.Session.{ManagedLifecycle, Resources}
alias Ipse.Runner.Review
alias Ipse.Extension.CollectionNormalizerV3IntegrationTest, as: Fixture

[base, case_mode] = System.argv()
turnover_test = String.starts_with?(case_mode, "turnover_")

case_mode =
  if turnover_test, do: String.replace_prefix(case_mode, "turnover_", ""), else: case_mode

if turnover_test,
  do: Code.require_file("../../dev/knowledge/managed_v3_turnover_native.exs", __DIR__)

deadline_test = case_mode == "deadline"
binding_test = case_mode == "binding-only"
split_test = case_mode == "split"
history_expiry_test = case_mode == "history_expiry"
pin_history_test = case_mode == "pin_history"

mode =
  if deadline_test or binding_test,
    do: "ordinary",
    else:
      if(split_test or history_expiry_test or pin_history_test, do: "temporal", else: case_mode)

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

category = if mode == "ordinary", do: "ordinary", else: "current"
real_anchor = System.system_time(:millisecond)
turnover_frame = if turnover_test, do: Ipse.Development.ManagedV3TurnoverNative.frame(real_anchor)
first = real_anchor - 86_400_000
old = %{Fixture.options(1, 0, "literal_source", category) | now_ms: first}
new = Fixture.options(2, 1, "literal_source", category)
same_text = new
source = hd(new.verified_sources)
quote = "Acme has owner Sam"

source =
  source
  |> Map.merge(%{
    "quote" => quote,
    "end_byte" => byte_size(quote),
    "quote_sha256" => JSON.sha256(quote),
    "content_sha256" => JSON.sha256(quote)
  })

{:ok, new_key, new_value} =
  IpseKnowledge.Knowledge.Records.capture(
    %{
      "text" => quote,
      "category" => category,
      "reason" => "trusted fixture successor",
      "event_at_ms" => nil
    },
    source,
    10 * 86_400_000
  )

new = %{
  new
  | verified_sources: [source],
    request:
      put_in(new.request, ["changes"], [
        %{"key" => new_key, "expected_revision" => 0, "value" => new_value}
      ])
}

assert old.recipe == new.recipe

scope = %{
  namespace: c.namespace,
  format: "managed-metadata-v3",
  operation_id: Usage.id(),
  initialize: true
}

if split_test do
  Code.require_file("managed_supersession_split_seed.exs", __DIR__)
  Ipse.Test.ManagedSupersessionSplitSeed.publish(c, old, new, scope)
else
  assert {:ok, _} = Fixture.publish(c, old, scope, first: true)
end

assert :ok =
         Resources.file_effect(fn ->
           {:ok, id} = Journal.create(base <> "/journal", %{"kind" => "synthetic_supersession"})
           {:ok, writer} = Journal.Writer.start(base <> "/journal", id, self())

           try do
             context = %{
               "session_id" => id,
               "job_id" => Usage.id(),
               "client_id" => Usage.id(),
               "project_id" => binding["project_id"],
               "namespace" => c.namespace,
               "binding_sha256" => binding["binding_sha256"],
               "management_epoch" => 0,
               "management_sha256" =>
                 JSON.digest(["management.v1", binding["project_id"], 0, nil]),
               "original_pin" => nil,
               "recipe" => old.recipe
             }

             observe = fn opts ->
               key = hd(opts.request["changes"])["key"]

               ProjectIdentity.with_existing_domain_auth(
                 c.home,
                 c.cwd,
                 c.binding,
                 %{namespace: c.namespace, format: "managed-metadata-v3"},
                 fn cap, catalog ->
                   ObservedRead.managed_record(
                     c.root,
                     c.namespace,
                     %{"op" => "get_record", "key" => key},
                     cap,
                     catalog,
                     opts.recipe
                   )
                 end
               )
             end

             if pin_history_test do
               Code.require_file("managed_history_pin.exs", __DIR__)
               Ipse.Test.ManagedHistoryPin.pin(c, old, context, observe, writer)
             end

             {:ok, before} = observe.(old)
             replacement = hd(new.request["changes"]) |> Map.take(~w(key value))
             prepared_at = System.system_time(:millisecond)

             options = %{
               mode: mode,
               constraints: new.constraints,
               verified_sources: new.verified_sources,
               policy_sha256: new.policy_sha256,
               now_ms: prepared_at
             }

             assert {:error, :managed_lifecycle_refused} =
                      ManagedLifecycle.prepare_supersession(
                        context,
                        before,
                        hd(same_text.request["changes"]) |> Map.take(~w(key value)),
                        %{options | verified_sources: same_text.verified_sources},
                        "Duplicate literal text"
                      )

             assert {:ok, prepared} =
                      ManagedLifecycle.prepare_supersession(
                        context,
                        before,
                        replacement,
                        options,
                        "Exact native reviewed successor"
                      )

             if binding_test do
               old_sources =
                 get_in(
                   before,
                   ["observation", "value", "record", "value"] ++ new.recipe["evidence_path"]
                 )

               assert {:ok, sources} =
                        Ipse.Session.ManagedSupersession.reviewed_source_set(
                          prepared["facts"],
                          new.recipe
                        )

               assert sources === Enum.uniq(old_sources ++ new.verified_sources)
               facts = prepared["facts"]
               now = System.system_time(:millisecond)
               assert Ipse.Session.ManagedSupersession.reviewed_relation?("correct", facts, now)
               refute Ipse.Session.ManagedSupersession.reviewed_relation?("supersede", facts, now)

               refute Ipse.Session.ManagedSupersession.reviewed_relation?(
                        "correct",
                        facts,
                        facts["checked_at_ms"] - 1
                      )

               refute Ipse.Session.ManagedSupersession.reviewed_relation?(
                        "correct",
                        facts,
                        facts["metadata"]["valid_until_ms"]
                      )

               altered = Map.put(facts, "history_rule", nil)

               altered =
                 Map.put(
                   altered,
                   "action_sha256",
                   JSON.digest([Map.delete(altered, "action_sha256")])
                 )

               refute Ipse.Session.ManagedSupersession.reviewed_relation?("correct", altered, now)

               active_id = hd(new.verified_sources)["session_id"]
               bound_facts = put_in(facts, ["context", "session_id"], active_id)

               bound_facts =
                 Map.put(
                   bound_facts,
                   "action_sha256",
                   JSON.digest([Map.delete(bound_facts, "action_sha256")])
                 )

               challenge = "0123456789abcdef"

               review = %{
                 "version" => 1,
                 "kind" => "native_review",
                 "command" => "correct",
                 "event_id" => Usage.id(),
                 "display_sha256" => JSON.sha256("synthetic display"),
                 "challenge" => challenge,
                 "input_sha256" => JSON.sha256("correct " <> challenge),
                 "observed_at_ms" => now,
                 "facts_sha256" => JSON.digest([bound_facts])
               }

               assert {:ok, display_sources} =
                        Ipse.Session.ManagedSupersession.reviewed_display_sources(
                          bound_facts,
                          active_id,
                          now
                        )

               assert {:ok, bound} =
                        Ipse.Session.ManagedSupersession.reviewed_publication_sources(
                          bound_facts,
                          review,
                          active_id,
                          now
                        )

               assert display_sources === bound

               other_id = Usage.id()
               no_active = put_in(bound_facts, ["context", "session_id"], other_id)

               no_active =
                 Map.put(
                   no_active,
                   "action_sha256",
                   JSON.digest([Map.delete(no_active, "action_sha256")])
                 )

               assert {:error, :managed_supersession_refused} =
                        Ipse.Session.ManagedSupersession.reviewed_display_sources(
                          no_active,
                          other_id,
                          now
                        )

               assert {:error, :managed_supersession_refused} =
                        Ipse.Session.ManagedSupersession.reviewed_display_sources(
                          bound_facts,
                          active_id,
                          bound_facts["metadata"]["valid_until_ms"]
                        )

               assert Enum.map(bound.active, & &1["session_id"]) ==
                        List.duplicate(active_id, length(bound.active))

               assert Enum.uniq(bound.active ++ bound.inactive) |> Enum.sort() ==
                        Enum.sort(sources)

               refute match?(
                        {:ok, _},
                        Ipse.Session.ManagedSupersession.reviewed_publication_sources(
                          bound_facts,
                          Map.put(review, "facts_sha256", JSON.sha256("different")),
                          active_id,
                          now
                        )
                      )

               refute match?(
                        {:ok, _},
                        Ipse.Session.ManagedSupersession.reviewed_publication_sources(
                          bound_facts,
                          review,
                          Usage.id(),
                          now
                        )
                      )

               refute match?(
                        {:ok, _},
                        Ipse.Session.ManagedSupersession.reviewed_publication_sources(
                          bound_facts,
                          Map.put(review, "observed_at_ms", now + 1),
                          active_id,
                          now
                        )
                      )

               IO.puts("NATIVE_SUPERSESSION_PASSED:binding-only")
               System.halt(0)
             end

             facts = prepared["facts"]
             assert :ok = Journal.Writer.append(writer, prepared["intent"])
             command = if mode == "ordinary", do: "correct", else: "supersede"

             root_path = Path.join([c.root, c.namespace, "root.json"])
             original_root = File.read!(root_path)
             handler = "supersession-deadline-" <> Usage.id()

             if deadline_test do
               :ok =
                 :telemetry.attach(
                   handler,
                   [:ipse, :extension, :collection, :staged],
                   fn _, _, _, _ ->
                     deadline = Process.get({Collection, :switch_deadline})
                     assert JSON.safe_uint?(deadline)
                     assert File.read!(root_path) == original_root
                     Process.sleep(max(0, deadline - System.system_time(:millisecond)) + 30)
                   end,
                   nil
                 )
             end

             reviewed =
               Review.with_review(command, facts, fn permit ->
                 result =
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
                       Collection.execute_managed_supersession(
                         c.root,
                         c.namespace,
                         prepared["request"],
                         facts["operation_id"],
                         JSON.digest([old.recipe]),
                         fn witness, read ->
                           options = %{
                             request: prepared["request"],
                             facts: facts,
                             permit: permit,
                             constraints: new.constraints,
                             verified_sources: new.verified_sources,
                             policy_sha256: new.policy_sha256,
                             now_ms: System.system_time(:millisecond),
                             capture_expires_at_ms:
                               System.system_time(:millisecond) +
                                 if(deadline_test, do: 2_000, else: 3_600_000),
                             domain_cap: cap,
                             catalog: catalog
                           }

                           assert {:error, :managed_normalization_refused} =
                                    NormalizerV3.supersede(witness, read, %{
                                      options
                                      | capture_expires_at_ms: options.now_ms
                                    })

                           assert {:error, :managed_normalization_refused} =
                                    NormalizerV3.supersede(witness, read, %{
                                      options
                                      | verified_sources: []
                                    })

                           assert :ok = Review.check(permit, command, facts)
                           result = NormalizerV3.supersede(witness, read, options)

                           {_, units, _} = Process.get({Collection, :managed_read})
                           assert units <= 32
                           IO.puts("SUPERCESSION_READ_UNITS=#{units}")

                           if split_test do
                             assert {:ok, normalized, receipt} = result

                             IO.puts(
                               "SUPERSESSION_RECEIPT_BYTES=#{byte_size(Jason.encode!(receipt))}"
                             )

                             IO.puts(
                               "SUPERSESSION_CHARGED_BYTES=#{byte_size(Jason.encode!(%{"request" => normalized, "facts" => facts, "receipt" => receipt}))}"
                             )
                           end

                           result
                         end
                       )
                     end
                   )

                 case result do
                   {:error, reason} when is_atom(reason) ->
                     IO.puts("SUPERSESSION_PUBLICATION_OUTCOME=error:" <> Atom.to_string(reason))

                   {:unknown, reason} when is_atom(reason) ->
                     IO.puts(
                       "SUPERSESSION_PUBLICATION_OUTCOME=unknown:" <> Atom.to_string(reason)
                     )

                   {:ok, _} ->
                     IO.puts("SUPERSESSION_PUBLICATION_OUTCOME=ok")

                   _ ->
                     IO.puts("SUPERSESSION_PUBLICATION_OUTCOME=other")
                 end

                 assert {:error, :native_review_refused} =
                          Review.consume(permit, command, facts)

                 if deadline_test do
                   assert {:unknown, :collection_publication_unconfirmed} = result
                   {:unknown, :publication_unconfirmed}
                 else
                   assert {:ok, core} = result

                   if turnover_test do
                     assert {:ok, consumed} = Review.consumed_receipt(permit, command, facts)

                     event =
                       Ipse.Development.ManagedV3TurnoverNative.event(
                         turnover_frame,
                         "actual_native_review_and_supersession",
                         consumed["observed_at_ms"],
                         %{
                           "clock_kind" => "actual_wall_clock",
                           "review_sha256" => JSON.digest([consumed]),
                           "source_sha256" => JSON.digest([old.verified_sources]),
                           "successor_source_sha256" => JSON.digest([new.verified_sources]),
                           "source_scope" => "synthetic_trusted_fixture",
                           "mode" => mode,
                           "first_admitted_actual_ms" =>
                             core["normalization"]["first_admitted_ms"],
                           "history_deadline_actual_ms" =>
                             core["normalization"]["history_valid_until_ms"],
                           "history_deadline_virtual_ms" =>
                             Ipse.Development.ManagedV3TurnoverNative.virtual(
                               turnover_frame,
                               core["normalization"]["history_valid_until_ms"]
                             )
                         }
                       )

                     IO.puts("TURNOVER_EVENT=" <> Jason.encode!(event))
                   end

                   {:ok, core}
                 end
               end)

             if deadline_test do
               assert :ok = :telemetry.detach(handler)
               assert {:unknown, :native_review_unconfirmed} = reviewed
               assert File.read!(root_path) == original_root

               assert {:ok, %{"operation" => nil}} =
                        Collection.execute(
                          c.root,
                          c.namespace,
                          %{"op" => "inspect", "operation_id" => facts["operation_id"]},
                          Usage.id()
                        )

               assert {:ok, ^before} = observe.(old)
               assert {:error, :collection_observation_refused} = observe.(new)
               IO.puts("NATIVE_SUPERSESSION_DEADLINE_PASSED")
             else
               assert {:ok, core} = reviewed

               assert :ok =
                        Journal.Writer.append(writer, %{
                          "type" => "managed_lifecycle_result",
                          "operation_id" => facts["operation_id"],
                          "outcome" => core
                        })

               normalization = core["normalization"]
               assert normalization["kind"] == "native_literal_supersession"
               if split_test, do: assert(length(normalization["metadata_refs"]) == 8)
               assert normalization["first_admitted_ms"] >= prepared_at

               if mode == "ordinary" do
                 assert normalization["valid_until_ms"] == before["metadata"]["valid_until_ms"]

                 assert normalization["history_valid_until_ms"] ==
                          before["metadata"]["valid_until_ms"]
               else
                 assert normalization["valid_until_ms"] == nil

                 if pin_history_test do
                   assert normalization["history_valid_until_ms"] == nil
                 else
                   assert normalization["history_valid_until_ms"] >=
                            prepared_at + 365 * 86_400_000
                 end
               end

               assert {:error, :collection_observation_refused} = observe.(old)
               assert {:ok, after_new} = observe.(new)

               assert after_new["metadata"]["first_admitted_ms"] ==
                        normalization["first_admitted_ms"]

               assert after_new["metadata"]["valid_until_ms"] == normalization["valid_until_ms"]

               assert :ok =
                        ProjectIdentity.with_existing_domain_auth(
                          c.home,
                          c.cwd,
                          c.binding,
                          %{namespace: c.namespace, format: "managed-metadata-v3"},
                          fn cap, _catalog ->
                            {:ok, view} = Collection.open_view(c.root, c.namespace)

                            try do
                              record = before["observation"]["value"]["record"]

                              {:ok, candidate} =
                                ManagedRecipe.extract(
                                  old.recipe,
                                  record["key"],
                                  record["value"],
                                  old.verified_sources
                                )

                              rows =
                                for {kind, row_id} <- [
                                      anchor: candidate["lineage"],
                                      live: ManagedPages.live_identity(record["key"])
                                    ] do
                                  {:ok, neighbors} =
                                    Collection.view_neighbors(view, %{
                                      "version" => 1,
                                      "prefix" => ManagedPages.prefix(kind),
                                      "fence_bytes" => ManagedPages.width(kind),
                                      "needle" => row_id
                                    })

                                  selected = neighbors["neighbors"]["selected"]["key"]

                                  {:ok, page_record} =
                                    Collection.view_read(view, %{
                                      "op" => "get_many",
                                      "keys" => [selected]
                                    })

                                  assert page_record["witness"] == neighbors["witness"]

                                  {:ok, page} =
                                    ManagedPages.open(cap, hd(page_record["records"]), neighbors)

                                  page.entries[row_id]
                                end

                              [anchor, live] = rows

                              assert {:ok, history} =
                                       ManagedRetention.history_metadata(
                                         candidate,
                                         record["sha256"],
                                         anchor,
                                         live
                                       )

                              assert history["successor"]["key"] == replacement["key"]

                              assert history["successor"]["sha256"] ==
                                       after_new["observation"]["value"]["record"]["sha256"]

                              assert history["valid_until_ms"] ==
                                       normalization["history_valid_until_ms"]

                              assert history["first_admitted_ms"] ==
                                       before["metadata"]["first_admitted_ms"]

                              :ok
                            after
                              assert :ok = Collection.close_view(view)
                            end
                          end
                        )

               if history_expiry_test do
                 Code.require_file("managed_history_expiry.exs", __DIR__)
                 Ipse.Test.ManagedHistoryExpiry.run(c, old, new, context, after_new, writer)

                 if turnover_test do
                   deadline = normalization["history_valid_until_ms"]

                   event =
                     Ipse.Development.ManagedV3TurnoverNative.event(
                       turnover_frame,
                       "signed_history_expired",
                       deadline,
                       %{
                         "clock_kind" => "explicit_synthetic_as_of",
                         "real_wall_after_ms" => System.system_time(:millisecond),
                         "source_sha256" => JSON.digest([old.verified_sources]),
                         "source_scope" => "synthetic_trusted_fixture"
                       }
                     )

                   IO.puts("TURNOVER_EVENT=" <> Jason.encode!(event))
                 end
               end

               if pin_history_test,
                 do: Ipse.Test.ManagedHistoryPin.check(c, old, new, context, observe, writer)

               IO.puts("NATIVE_SUPERSESSION_PASSED:" <> case_mode)
             end

             :ok
           after
             :ok = Journal.Writer.close(writer)
           end
         end)
