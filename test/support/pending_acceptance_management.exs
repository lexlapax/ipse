ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)

alias Ipse.{JSON, Usage}
alias Ipse.CLI.Knowledge.Management
alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ObservedRead
alias Ipse.Journal.Writer
alias Ipse.Runner.{ManagementTerminal, Review, Transaction}
alias Ipse.Session.PendingAcceptance

[root, mode] = System.argv()

if mode in ~w(host-writer-result-after-write host-writer-result-partial),
  do: System.put_env("IPSE_TEST_JOURNAL_HOOK", root)

home = Path.join(root, "home")
cwd = Path.join(root, "work")
fixture = root |> Path.join("pending-management.json") |> File.read!() |> Jason.decode!()
{:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)
{:ok, snapshot} = Consent.existing_snapshot(control, binding["project_id"])
policy_sha = JSON.digest([snapshot["policy"]])

overall =
  System.monotonic_time(:millisecond) +
    if(mode == "host-orchestrated-expired", do: 4_000, else: 120_000)

wall = min(System.system_time(:millisecond) + 120_000, snapshot["policy"]["expires_at_ms"])
before_management = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))

result =
  if mode in ~w(host-orchestrated host-orchestrated-cancel host-orchestrated-missing host-orchestrated-path-swap host-orchestrated-race host-orchestrated-revoked host-orchestrated-expired) do
    Management.accept_pending_candidate(
      %{home: home},
      cwd,
      fixture["history_dir"],
      fixture["key"],
      overall
    )
  else
    Management.controlled_review_journal_candidate(%{home: home}, cwd, overall, fn owned ->
      {:ok, reservation} = Writer.reserve(owned.writer, %{bytes: 131_072, events: 3})

      if mode in ~w(host-source-race host-loss-before host-loss-after host-loss-synced host-writer-before host-writer-after host-writer-renamed host-writer-synced host-writer-result host-writer-result-after-write host-writer-result-partial) do
        File.write!(Path.join(root, "pending-#{mode}-journal-id"), owned.id, [:exclusive])
      end

      if mode == "host-writer-result" do
        writer = owned.writer

        watcher =
          spawn(fn ->
            receive do
              :acceptance_result_ready ->
                monitor = Process.monitor(writer)
                Process.exit(writer, :kill)

                receive do
                  {:DOWN, ^monitor, :process, ^writer, _} ->
                    File.write!(
                      Path.join(root, "pending-host-writer-result-writer-killed"),
                      "killed"
                    )
                after
                  5_000 -> :ok
                end
            after
              15_000 -> :timeout
            end
          end)

        callback = fn
          count,
          {:in,
           {:"$gen_call", _,
            {:append_reserved, _, :plain,
             %{"type" => "pending_acceptance_result", "status" => "committed"}}}},
          _ ->
            send(watcher, :acceptance_result_ready)
            receive do: (:release_result -> :ok)
            count + 1

          count, _, _ ->
            count
        end

        assert :ok = :sys.install(writer, {callback, 0})
      end

      if mode in ~w(host-writer-result-after-write host-writer-result-partial) do
        writer = owned.writer

        for name <-
              ~w(journal-hook.arm journal-partial.arm journal-after-write.ready journal-after-write.go journal-partial-write.ready journal-partial-write.go),
            do: File.rm(Path.join(root, name))

        phase = if mode == "host-writer-result-partial", do: "partial-write", else: "after-write"
        File.write!(Path.join(root, "journal-before-write.go"), "go")

        watcher =
          spawn(fn ->
            receive do
              :acceptance_result_ready ->
                deadline = System.monotonic_time(:millisecond) + 15_000

                wait = fn wait ->
                  cond do
                    File.exists?(Path.join(root, "journal-#{phase}.ready")) ->
                      :ok

                    System.monotonic_time(:millisecond) >= deadline ->
                      :timeout

                    true ->
                      Process.sleep(10)
                      wait.(wait)
                  end
                end

                if wait.(wait) == :ok do
                  monitor = Process.monitor(writer)
                  Process.exit(writer, :kill)

                  receive do
                    {:DOWN, ^monitor, :process, ^writer, _} ->
                      File.write!(
                        Path.join(root, "pending-#{mode}-killed"),
                        "killed"
                      )

                      if phase != "partial-write",
                        do: File.write!(Path.join(root, "journal-#{phase}.go"), "go")
                  after
                    5_000 -> :ok
                  end
                end
            after
              15_000 -> :timeout
            end
          end)

        callback = fn
          count,
          {:in,
           {:"$gen_call", _,
            {:append_reserved, _, :plain,
             %{"type" => "pending_acceptance_result", "status" => "committed"}}}},
          _ ->
            File.write!(Path.join(root, "journal-hook.arm"), "armed")

            if mode == "host-writer-result-partial",
              do: File.write!(Path.join(root, "journal-partial.arm"), "armed")

            send(watcher, :acceptance_result_ready)
            count + 1

          count, _, _ ->
            count
        end

        assert :ok = :sys.install(writer, {callback, 0})
      end

      if mode in ~w(host-writer-before host-writer-after host-writer-renamed host-writer-synced) do
        phase =
          case mode do
            "host-writer-before" -> "before-decision"
            "host-writer-after" -> "after-decision"
            "host-writer-renamed" -> "after-rename"
            "host-writer-synced" -> "after-sync"
          end

        writer = owned.writer

        spawn(fn ->
          marker = Path.join(cwd, "source-switch-#{phase}.ready")
          deadline = System.monotonic_time(:millisecond) + 15_000

          wait = fn wait ->
            cond do
              File.exists?(marker) ->
                :ok

              System.monotonic_time(:millisecond) >= deadline ->
                :timeout

              true ->
                Process.sleep(10)
                wait.(wait)
            end
          end

          if wait.(wait) == :ok do
            monitor = Process.monitor(writer)
            Process.exit(writer, :kill)

            receive do
              {:DOWN, ^monitor, :process, ^writer, _} ->
                File.write!(Path.join(root, "pending-#{mode}-writer-killed"), "killed")
                File.write!(Path.join(cwd, "source-switch-#{phase}.go"), "go")
            after
              5_000 -> :ok
            end
          end
        end)
      end

      context = %{
        "operation_id" => Usage.id(),
        "journal_id" => owned.id,
        "client_id" => Usage.id(),
        "session_id" => nil,
        "project_id" => binding["project_id"],
        "namespace" => fixture["namespace"],
        "binding_sha256" => binding["binding_sha256"],
        "policy_sha256" => policy_sha,
        "capture_epoch" => snapshot["epoch"],
        "render_revision" => 1,
        "recipe" => fixture["recipe"]
      }

      {:ok, source_context} =
        PendingAcceptance.management_source_context(
          home,
          fixture["history_dir"],
          binding,
          snapshot,
          owned.id,
          snapshot["policy"]["artifact_sha256"],
          fixture["note_recipe"],
          fixture["recipe"],
          System.system_time(:millisecond)
        )

      if mode == "valid" do
        missing = "pending." <> JSON.sha256("missing synthetic candidate")

        assert {:error, _} =
                 Management.with_verified_acceptance_target(
                   %{home: home},
                   cwd,
                   fixture["history_dir"],
                   owned,
                   missing,
                   fn _, _, _, _, _ -> flunk("missing target reached review") end
                 )

        source_id = hd(fixture["sources"])["session_id"]
        source_path = Path.join(fixture["history_dir"], source_id <> ".jsonl")
        lock_path = Path.join(fixture["history_dir"], source_id <> ".lock")
        original = File.read!(source_path)
        assert {:ok, lock} = Ipse.Runner.lock(lock_path)
        File.write!(source_path, "incomplete", [:append])
        assert :ok = Ipse.Runner.unlock(lock)

        assert {:error, _} =
                 Management.with_verified_acceptance_target(
                   %{home: home},
                   cwd,
                   fixture["history_dir"],
                   owned,
                   fixture["key"],
                   fn _, _, _, _, _ -> flunk("incomplete source reached review") end
                 )

        assert {:ok, lock} = Ipse.Runner.lock(lock_path)
        File.write!(source_path, original)
        assert :ok = Ipse.Runner.unlock(lock)

        assert {:ok, :verified_target} =
                 Management.with_verified_acceptance_target(
                   %{home: home},
                   cwd,
                   fixture["history_dir"],
                   owned,
                   fixture["key"],
                   fn facts, observed, read, _cap, lease ->
                     assert facts["source_proof"] === hd(fixture["sources"])
                     assert facts["pending_key"] === fixture["key"]
                     assert observed["observation"]["value"]["record"]["key"] === fixture["key"]
                     assert is_function(read, 1)
                     assert {:ok, _} = Ipse.Session.StoredSources.share_identity(lease)

                     assert :ok =
                              Ipse.Runner.Transaction.check(
                                Process.get({Ipse.Extension.Collection, :lock_held})
                              )

                     {:ok, :verified_target}
                   end
                 )
      end

      read_target = fn access, fun ->
        scope = %{namespace: fixture["namespace"], format: "managed-metadata-v3"}

        callback = fn cap, catalog ->
          Consent.with_policy(
            control,
            binding["project_id"],
            snapshot["epoch"],
            policy_sha,
            System.system_time(:millisecond),
            fn current_policy ->
              observer = fn observed, read, publish ->
                # Initial selection is historical; callers retain the source for display and planning.
                with {:ok, facts} <-
                       PendingAcceptance.prepare(
                         context,
                         observed,
                         fixture["sources"],
                         System.system_time(:millisecond)
                       ),
                     :ok <-
                       PendingAcceptance.check_source_policy(
                         facts,
                         current_policy["policy"],
                         fixture["note_recipe"],
                         System.system_time(:millisecond)
                       ) do
                  if mode == "valid" do
                    assert {:error, :pending_acceptance_refused} =
                             PendingAcceptance.check_source_policy(
                               facts,
                               current_policy["policy"],
                               Map.put(fixture["note_recipe"], "override_prefix", "other."),
                               System.system_time(:millisecond)
                             )

                    assert {:error, :pending_acceptance_refused} =
                             PendingAcceptance.check_source_policy(
                               facts,
                               current_policy["policy"],
                               fixture["note_recipe"],
                               current_policy["policy"]["expires_at_ms"]
                             )
                  end

                  if access == :publish,
                    do: fun.(facts, observed, read, cap, publish),
                    else: fun.(facts, observed, read, cap)
                end
              end

              args = [
                fixture["collection_root"],
                fixture["namespace"],
                %{"op" => "get_record", "key" => fixture["key"]},
                cap,
                catalog,
                fixture["recipe"]
              ]

              if access == :publish,
                do:
                  apply(ObservedRead, :with_managed_proposal_acceptance_plan, args ++ [observer]),
                else:
                  apply(
                    ObservedRead,
                    :with_managed_proposal_plan,
                    args ++ [fn observed, read -> observer.(observed, read, nil) end]
                  )
            end
          )
        end

        case access do
          :verify ->
            ProjectIdentity.with_existing_domain_auth(home, cwd, binding, scope, callback)

          :publish ->
            authorize = fn _ ->
              case Consent.with_policy(
                     control,
                     binding["project_id"],
                     snapshot["epoch"],
                     policy_sha,
                     System.system_time(:millisecond),
                     fn _ -> {:ok, :authorized} end
                   ) do
                {:ok, :authorized} -> :ok
                error -> error
              end
            end

            ProjectIdentity.with_domain_publication(
              home,
              cwd,
              binding,
              Map.merge(scope, %{operation_id: context["operation_id"], initialize: false}),
              authorize,
              callback
            )
        end
      end

      display_candidate =
        if mode in ~w(valid publish host-source-race host-loss-before host-loss-after host-loss-synced host-writer-before host-writer-after host-writer-renamed host-writer-synced host-writer-result host-writer-result-after-write host-writer-result-partial) do
          assert {:error, :knowledge_management_refused} =
                   Management.with_verified_acceptance_target(
                     %{home: home},
                     cwd,
                     fixture["history_dir"],
                     owned,
                     fixture["key"],
                     false,
                     fn _, _, _, _, _ -> flunk("invalid context reached review") end
                   )

          assert {:error, :knowledge_management_refused} =
                   Management.begin_acceptance_review(
                     %{home: home},
                     cwd,
                     fixture["history_dir"],
                     owned,
                     fixture["key"],
                     Map.put(context, "policy_sha256", JSON.sha256("changed policy")),
                     wall
                   )

          Management.begin_acceptance_review(
            %{home: home},
            cwd,
            fixture["history_dir"],
            owned,
            fixture["key"],
            context,
            wall
          )
        else
          with {:ok, facts} <- read_target.(:verify, fn facts, _, _, _ -> {:ok, facts} end) do
            display = fn leases ->
              lease = hd(leases)

              if mode in ~w(source-loss-display-prewrite source-loss-display-partial) do
                phase = String.replace_prefix(mode, "source-loss-display-", "")
                {:ok, identity} = Ipse.Session.StoredSources.share_identity(lease)

                File.write!(
                  Path.join(root, "pending-source-owner-pid-" <> phase),
                  Integer.to_string(identity.pid),
                  [:exclusive]
                )

                File.write!(
                  Path.join(root, "pending-source-journal-id-" <> phase),
                  owned.id,
                  [
                    :exclusive
                  ]
                )
              end

              read_target.(:verify, fn current, _observed, _read, _cap ->
                with true <- current === facts,
                     {:ok, caps} <- Transaction.retained_share_stack(),
                     {:ok, handle} <-
                       if(mode == "group-valid",
                         do:
                           ManagementTerminal.begin_accept_group_review(
                             owned,
                             caps,
                             facts,
                             wall,
                             leases
                           ),
                         else:
                           ManagementTerminal.begin_accept_review(
                             owned,
                             caps,
                             facts,
                             wall,
                             lease
                           )
                       ),
                     do: {:ok, {handle, facts}},
                     else: (_ -> {:error, :changed_target})
              end)
            end

            if mode == "group-valid" do
              with :ok <-
                     PendingAcceptance.with_verified_source(source_context, facts, fn _ -> :ok end),
                   group = [facts["source_proof"], fixture["group_source"]],
                   {:ok, {handle, ^facts}} <-
                     Ipse.Session.StoredSources.with_shareable_groups(
                       source_context,
                       group,
                       fn sources, leases ->
                         assert Enum.map(sources, & &1["proof"]) === group
                         assert length(leases) == 2
                         display.(Enum.map(leases, & &1.token))
                       end
                     ) do
                {:ok, {handle, facts}}
              end
            else
              PendingAcceptance.with_shareable_source(source_context, facts, fn _source, lease ->
                display.([lease])
              end)
            end
          end
        end

      review_result =
        with {:ok, {handle, facts}} <- display_candidate do
          if mode == "wrong-purpose" do
            assert {:error, :native_review_refused} =
                     Review.with_management_input("forget", facts, handle, fn _ ->
                       flunk("wrong purpose")
                     end)

            assert {:error, :native_review_refused} =
                     Review.with_management_input("accept", facts, handle, fn _ ->
                       flunk("reused handle")
                     end)

            {:error, :purpose_refused}
          else
            Review.with_management_input("accept", facts, handle, fn permit ->
              if mode in ~w(publish host-source-race host-loss-before host-loss-after host-loss-synced host-writer-before host-writer-after host-writer-renamed host-writer-synced host-writer-result host-writer-result-after-write host-writer-result-partial) do
                Management.publish_consumed_acceptance(
                  %{home: home},
                  cwd,
                  fixture["history_dir"],
                  owned,
                  reservation,
                  facts,
                  permit
                )
              else
                PendingAcceptance.with_shareable_source(source_context, facts, fn _source,
                                                                                  source_lease ->
                  read_target.(:publish, fn current, observed, read, cap, publish ->
                    if current === facts do
                      now = System.system_time(:millisecond)

                      with {:ok, preview} <- PendingAcceptance.preview(permit, facts, now),
                           {:ok, prepared} <-
                             PendingAcceptance.prepare_storage(
                               preview,
                               fixture["note_recipe"],
                               snapshot["policy"]["expires_at_ms"],
                               observed,
                               cap,
                               now,
                               read
                             ),
                           true <-
                             prepared["retention"]["valid_until_ms"] ===
                               snapshot["policy"]["expires_at_ms"] do
                        expired = put_in(prepared, ["retention", "valid_until_ms"], now)

                        assert {:error, :pending_acceptance_refused} =
                                 PendingAcceptance.with_sidecar_plan(
                                   preview,
                                   expired,
                                   cap,
                                   read,
                                   fn _, _ ->
                                     flunk("expired plan reached its signing callback")
                                   end
                                 )

                        PendingAcceptance.with_sidecar_plan(
                          preview,
                          prepared,
                          cap,
                          read,
                          fn sidecars, seal ->
                            assert length(sidecars.anchor.changes) + length(sidecars.live.changes) <=
                                     5

                            assert {:error, :pending_acceptance_refused} =
                                     Task.async(fn -> seal.(permit) end) |> Task.await()

                            assert {_, units, :open} =
                                     Process.get({Ipse.Extension.Collection, :managed_read})

                            assert units <= 32

                            if mode == "premature-seal" do
                              assert {:error, :pending_acceptance_refused} = seal.(permit)
                              assert {:error, :pending_acceptance_refused} = seal.(permit)

                              assert {:ok, ^preview} =
                                       PendingAcceptance.preview(permit, facts, now)

                              throw(:premature_seal_refused)
                            end

                            assert {:ok, ^preview} = PendingAcceptance.consume(permit, facts, now)
                            assert self() == owned.journal_owner

                            assert {:ok, intent} =
                                     PendingAcceptance.effect_intent(
                                       preview,
                                       prepared["public"]["request"]
                                     )

                            assert :ok =
                                     Writer.append_reserved(owned.writer, reservation, preview)

                            assert :ok = Writer.append_reserved(owned.writer, reservation, intent)
                            assert {:ok, %{changes: signed, request: normalized}} = seal.(permit)
                            assert Ipse.Extension.Collection.valid_request?(normalized)

                            assert normalized["changes"] ===
                                     prepared["public"]["request"]["changes"] ++ signed

                            assert Map.delete(normalized, "changes") ===
                                     Map.delete(prepared["public"]["request"], "changes")

                            assert PendingAcceptance.normalized_acceptance?(intent, normalized)

                            refute PendingAcceptance.normalized_acceptance?(
                                     intent,
                                     Map.put(normalized, "expected_generation", 999_999)
                                   )

                            refute PendingAcceptance.normalized_acceptance?(
                                     intent,
                                     Map.put(
                                       normalized,
                                       "changes",
                                       Enum.take(normalized["changes"], 3)
                                     )
                                   )

                            assert length(signed) ==
                                     length(sidecars.anchor.changes) +
                                       length(sidecars.live.changes)

                            assert Enum.all?(signed, fn change ->
                                     is_nil(change["value"]) or
                                       (is_map(change["value"]) and
                                          byte_size(change["value"]["mac"]) == 43)
                                   end)

                            for %{"key" => key, "value" => value} <- signed, is_map(value) do
                              kind =
                                if String.starts_with?(key, "host.validity.a."),
                                  do: "anchor",
                                  else: "live"

                              tag_context = %{
                                "version" => 1,
                                "schema" => 3,
                                "page_key" => key,
                                "kind" => kind,
                                "operation_id" => facts["operation_id"],
                                "revision" =>
                                  prepared["public"]["request"]["expected_generation"] + 1
                              }

                              body = Base.url_decode64!(value["data"], padding: false)
                              tag = Base.url_decode64!(value["mac"], padding: false)

                              assert true ==
                                       Ipse.Extension.ProjectIdentity.DomainAuth.verify(
                                         cap,
                                         tag_context,
                                         body,
                                         tag
                                       )

                              assert false ==
                                       Ipse.Extension.ProjectIdentity.DomainAuth.verify(
                                         cap,
                                         tag_context,
                                         body <> <<0>>,
                                         tag
                                       )
                            end

                            assert {:error, :pending_acceptance_refused} = seal.(permit)

                            if mode == "wrong-intent" do
                              File.write!(
                                Path.join(root, "pending-wrong-intent-journal-id"),
                                owned.id,
                                [:exclusive]
                              )

                              tampered =
                                Map.put(intent, "request_sha256", JSON.sha256("tampered"))

                              assert {:error, :native_review_refused} =
                                       Review.claim_acceptance_effect(permit, facts, tampered)

                              assert {:error, :native_review_refused} =
                                       Review.claim_acceptance_effect(permit, facts, intent)

                              throw(:wrong_intent_refused)
                            end

                            assert {:ok, receipt} =
                                     Review.claim_acceptance_effect(permit, facts, intent)

                            assert receipt === preview["review"]

                            assert {:ok, ^receipt} =
                                     Review.claimed_acceptance_receipt(permit, facts, intent)

                            assert {:ok, ^receipt} =
                                     Review.claimed_acceptance_request(
                                       permit,
                                       facts,
                                       intent,
                                       normalized
                                     )

                            assert {:error, :native_review_refused} =
                                     Review.claimed_acceptance_request(
                                       permit,
                                       facts,
                                       intent,
                                       Map.put(normalized, "extra", true)
                                     )

                            assert {:error, :native_review_refused} =
                                     Review.claimed_acceptance_receipt(
                                       permit,
                                       facts,
                                       Map.put(intent, "extra", true)
                                     )

                            assert {:error, :native_review_refused} =
                                     Review.claim_acceptance_effect(permit, facts, intent)

                            collection_cap = Process.get({Ipse.Extension.Collection, :lock_held})

                            result =
                              Transaction.with_acceptance_journal_lease(
                                collection_cap,
                                owned,
                                preview,
                                intent,
                                fn ->
                                  Transaction.with_source_lease(
                                    collection_cap,
                                    source_lease,
                                    fn ->
                                      assert :ok = Transaction.check(collection_cap)

                                      assert :ok =
                                               Transaction.acceptance_guard(
                                                 collection_cap,
                                                 preview,
                                                 intent
                                               )

                                      assert {:error, :invalid_transaction_capability} =
                                               Transaction.acceptance_guard(
                                                 collection_cap,
                                                 preview,
                                                 Map.put(intent, "extra", true)
                                               )

                                      assert {:error, :invalid_transaction_capability} =
                                               Task.async(fn ->
                                                 Transaction.acceptance_guard(
                                                   collection_cap,
                                                   preview,
                                                   intent
                                                 )
                                               end)
                                               |> Task.await()

                                      assert {:ok, ^receipt} =
                                               Review.claimed_acceptance_request(
                                                 permit,
                                                 facts,
                                                 intent,
                                                 normalized
                                               )

                                      assert {:error, :journal_share_frozen} =
                                               Writer.append_reserved(
                                                 owned.writer,
                                                 reservation,
                                                 preview
                                               )

                                      if mode in ~w(publish publish-tampered) do
                                        retention_deadline =
                                          prepared["retention"]["valid_until_ms"] ||
                                            facts["valid_until_ms"]

                                        deadline =
                                          min(retention_deadline, facts["valid_until_ms"])

                                        if mode == "publish-tampered" do
                                          assert {:error, :pending_acceptance_refused} =
                                                   Ipse.Extension.Collection.with_notes_publication_deadline(
                                                     deadline,
                                                     fn ->
                                                       publish.(
                                                         preview,
                                                         intent,
                                                         Map.put(normalized, "extra", true),
                                                         permit
                                                       )
                                                     end
                                                   )

                                          assert {:error, :pending_acceptance_refused} =
                                                   publish.(preview, intent, normalized, permit)

                                          {:ok, {:tampered, nil}}
                                        else
                                          assert {:ok, result} =
                                                   Ipse.Extension.Collection.with_notes_publication_deadline(
                                                     deadline,
                                                     fn ->
                                                       publish.(
                                                         preview,
                                                         intent,
                                                         normalized,
                                                         permit
                                                       )
                                                     end
                                                   )

                                          assert result["request_sha256"] ===
                                                   JSON.digest([normalized])

                                          assert result["managed_binding_sha256"] ===
                                                   JSON.digest([
                                                     "pending_acceptance",
                                                     1,
                                                     preview,
                                                     intent
                                                   ])

                                          assert {:error, :pending_acceptance_refused} =
                                                   publish.(preview, intent, normalized, permit)

                                          {:ok, {:published, result}}
                                        end
                                      else
                                        {:ok, :held}
                                      end
                                    end
                                  )
                                end
                              )

                            case {mode, result} do
                              {"publish", {:ok, {:published, result}}} ->
                                {:ok, {preview, intent, result, normalized}}

                              {"publish-tampered", {:ok, {:tampered, nil}}} ->
                                {:ok, {preview, intent, nil}}

                              {_, {:ok, :held}} ->
                                {:ok, {preview, intent}}

                              {_, other} ->
                                other
                            end
                          end
                        )
                      end
                    else
                      {:error, :changed_target}
                    end
                  end)
                end)
              end
            end)
          end
        end

      recorded =
        case review_result do
          {:ok, {:host_committed, event, receipt}} ->
            {:ok, {event, receipt}}

          {:ok, {event, intent, receipt, normalized}} ->
            with true <- self() == owned.journal_owner,
                 {:ok, committed} <-
                   PendingAcceptance.committed_result(event, intent, normalized, receipt),
                 :ok <- Writer.append_reserved(owned.writer, reservation, committed),
                 do: {:ok, {event, receipt}},
                 else: (_ -> {:unknown, :acceptance_journal_unconfirmed})

          {:ok, {event, intent, receipt}} ->
            with true <- self() == owned.journal_owner,
                 {:ok, unknown} <- PendingAcceptance.effect_result(intent, "unknown"),
                 :ok <- Writer.append_reserved(owned.writer, reservation, unknown),
                 do: {:ok, {event, receipt}},
                 else: (_ -> {:unknown, :acceptance_journal_unconfirmed})

          {:ok, {event, intent}} ->
            with true <- self() == owned.journal_owner,
                 {:ok, refused} <- PendingAcceptance.effect_result(intent, "refused"),
                 :ok <- Writer.append_reserved(owned.writer, reservation, refused),
                 do: {:ok, event},
                 else: (_ -> {:unknown, :acceptance_journal_unconfirmed})

          other ->
            other
        end

      if Writer.release(owned.writer, reservation) == :ok,
        do: recorded,
        else: {:unknown, :acceptance_journal_unconfirmed}
    end)
  end

if mode in ~w(publish publish-tampered host-orchestrated) do
  {event, receipt} =
    if mode == "host-orchestrated" do
      assert {:closed, {:ok, {:host_committed, event, receipt}}} = result
      {event, receipt}
    else
      assert {:closed, {:ok, {event, receipt}}} = result
      {event, receipt}
    end

  assert PendingAcceptance.valid_event?(event)
  journal_id = event["facts"]["journal_id"]
  assert {:ok, records} = Ipse.Journal.load(Path.join(home, "knowledge-management"), journal_id)

  if mode in ~w(publish host-orchestrated) do
    assert {:ok, []} = PendingAcceptance.unknown_effects(records, journal_id)
    assert [committed] = Enum.filter(records, &(&1["type"] == "pending_acceptance_result"))
    assert committed["status"] == "committed" and committed["receipt"] === receipt
    assert [intent] = Enum.filter(records, &(&1["type"] == "pending_acceptance_intent"))
    without_result = Enum.reject(records, &(&1["type"] == "pending_acceptance_result"))
    assert {:ok, [^intent]} = PendingAcceptance.unknown_effects(without_result, journal_id)

    assert {:ok, %{event: ^event, intent: ^intent, result: ^committed}} =
             PendingAcceptance.resolve_committed(records, journal_id, JSON.digest([event]))

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.resolve_committed(without_result, journal_id, JSON.digest([event]))

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.resolve_committed(records, journal_id, JSON.sha256("other"))

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.validate_events(
               List.replace_at(
                 records,
                 -1,
                 put_in(committed, ["receipt", "request_sha256"], JSON.sha256("tampered"))
               ),
               journal_id
             )
  else
    assert {:ok, [_]} = PendingAcceptance.unknown_effects(records, journal_id)
  end

  File.write!(
    Path.join(root, "pending-management-#{mode}.json"),
    Jason.encode!(%{"event" => event, "receipt" => receipt}),
    [:exclusive]
  )
else
  if mode in ~w(valid group-valid) do
    assert {:closed, {:ok, event}} = result
    assert PendingAcceptance.valid_event?(event)
    assert event["facts"]["pending_key"] == fixture["key"]
    journal_id = event["facts"]["journal_id"]
    assert {:ok, records} = Ipse.Journal.load(Path.join(home, "knowledge-management"), journal_id)
    assert :ok = PendingAcceptance.validate_events(records, journal_id)
    assert Enum.count(records, &(&1["type"] == "pending_proposal_accepted")) == 1

    assert Enum.map(
             Enum.filter(
               records,
               &(&1["type"] in ~w(pending_proposal_accepted pending_acceptance_intent pending_acceptance_result))
             ),
             & &1["type"]
           ) == ~w(pending_proposal_accepted pending_acceptance_intent pending_acceptance_result)

    assert event in records
    assert {:ok, []} = PendingAcceptance.unknown_effects(records, journal_id)
    assert [intent] = Enum.filter(records, &(&1["type"] == "pending_acceptance_intent"))
    assert [refused] = Enum.filter(records, &(&1["type"] == "pending_acceptance_result"))
    without_result = Enum.reject(records, &(&1["type"] == "pending_acceptance_result"))
    assert {:ok, [^intent]} = PendingAcceptance.unknown_effects(without_result, journal_id)
    header = hd(records)

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.validate_events([header, intent, event], journal_id)

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.validate_events([header, event, intent, intent], journal_id)

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.validate_events(
               [header, event, intent, refused, refused],
               journal_id
             )

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.validate_events(
               [header, event, Map.put(intent, "request_sha256", JSON.sha256("tampered"))],
               journal_id
             )

    assert {:error, :pending_acceptance_refused} =
             PendingAcceptance.effect_result(intent, "committed")

    assert {:ok, unknown} = PendingAcceptance.effect_result(intent, "unknown")

    assert {:ok, [^intent]} =
             PendingAcceptance.unknown_effects([header, event, intent, unknown], journal_id)

    event_file =
      if mode == "group-valid",
        do: "pending-management-group-event.json",
        else: "pending-management-event.json"

    File.write!(Path.join(root, event_file), Jason.encode!(event), [
      :exclusive
    ])
  else
    case mode do
      mode when mode in ~w(cancel stale) ->
        assert {:closed, {:error, :native_review_refused}} = result

      "wrong-purpose" ->
        assert {:unknown, :knowledge_management_cleanup_unconfirmed} = result

      "race" ->
        assert {:closed, {:error, :consent_read_refused}} = result

      mode when mode in ~w(source-race host-source-race) ->
        assert {:closed, {:error, :collection_source_refused}} = result

        if mode == "host-source-race" do
          journal_id = root |> Path.join("pending-#{mode}-journal-id") |> File.read!()

          assert {:ok, records} =
                   Ipse.Journal.load(Path.join(home, "knowledge-management"), journal_id)

          refute Enum.any?(
                   records,
                   &(&1["type"] in ~w(pending_proposal_accepted pending_acceptance_intent pending_acceptance_result))
                 )
        end

      "host-orchestrated-path-swap" ->
        assert {:closed, {:error, :collection_source_refused}} = result

        [path] =
          Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"])) -- before_management

        assert {:ok, %{events: records, tail: :none}} = Ipse.Journal.read_path(path)

        refute Enum.any?(
                 records,
                 &(&1["type"] in ~w(pending_proposal_accepted pending_acceptance_intent pending_acceptance_result))
               )

      mode
      when mode in ~w(host-orchestrated-cancel host-orchestrated-missing host-orchestrated-race host-orchestrated-revoked host-orchestrated-expired) ->
        if mode == "host-orchestrated-expired" do
          assert {:unknown, :knowledge_management_cleanup_unconfirmed} = result
        else
          assert {:closed, {:error, _}} = result
        end

        [path] =
          Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"])) -- before_management

        assert {:ok, %{events: records, tail: :none}} = Ipse.Journal.read_path(path)

        refute Enum.any?(
                 records,
                 &(&1["type"] in ~w(pending_proposal_accepted pending_acceptance_intent pending_acceptance_result))
               )

      "host-writer-result-partial" ->
        assert match?({:unknown, _}, result) or match?({:closed, {:unknown, _}}, result) or
                 match?({:closed, {:error, _}}, result)

        journal_id = root |> Path.join("pending-#{mode}-journal-id") |> File.read!()
        path = Path.join([home, "knowledge-management", journal_id <> ".jsonl"])
        before = File.read!(path)
        assert {:ok, %{events: records, tail: tail}} = Ipse.Journal.read_path(path)
        assert tail != :none
        assert :ok = PendingAcceptance.validate_events(records, journal_id)
        assert {:ok, [_]} = PendingAcceptance.unknown_effects(records, journal_id)

        assert {:ok, %{"journal_status" => "unknown", "replayed" => false}} =
                 Management.operation(%{home: home}, cwd, journal_id)

        assert File.read!(path) == before

      "host-writer-result-after-write" ->
        assert match?({:unknown, _}, result) or match?({:closed, {:unknown, _}}, result) or
                 match?({:closed, {:error, _}}, result)

        journal_id = root |> Path.join("pending-#{mode}-journal-id") |> File.read!()

        assert {:ok, records} =
                 Ipse.Journal.load(Path.join(home, "knowledge-management"), journal_id)

        assert :ok = PendingAcceptance.validate_events(records, journal_id)

        assert [%{"status" => "committed"}] =
                 Enum.filter(records, &(&1["type"] == "pending_acceptance_result"))

        assert {:ok, []} = PendingAcceptance.unknown_effects(records, journal_id)

      mode
      when mode in ~w(host-loss-before host-loss-after host-loss-synced host-writer-before host-writer-after host-writer-renamed host-writer-synced host-writer-result) ->
        assert match?({:unknown, _}, result) or match?({:closed, {:unknown, _}}, result) or
                 match?({:closed, {:error, _}}, result)

        journal_id = root |> Path.join("pending-#{mode}-journal-id") |> File.read!()

        assert {:ok, records} =
                 Ipse.Journal.load(Path.join(home, "knowledge-management"), journal_id)

        assert {:ok, [_]} = PendingAcceptance.unknown_effects(records, journal_id)

      "denied-source" ->
        assert {:closed, {:error, :pending_acceptance_refused}} = result

      "premature-seal" ->
        assert match?({:closed, {:error, _}}, result) or match?({:closed, {:unknown, _}}, result)

      "wrong-intent" ->
        assert match?({:closed, {:error, _}}, result) or match?({:closed, {:unknown, _}}, result)
        journal_id = root |> Path.join("pending-wrong-intent-journal-id") |> File.read!()

        assert {:ok, records} =
                 Ipse.Journal.load(Path.join(home, "knowledge-management"), journal_id)

        assert [intent] = Enum.filter(records, &(&1["type"] == "pending_acceptance_intent"))
        assert {:ok, [^intent]} = PendingAcceptance.unknown_effects(records, journal_id)
        refute Enum.any?(records, &(&1["type"] == "pending_acceptance_result"))

      mode when mode in ~w(source-loss-display-prewrite source-loss-display-partial) ->
        assert match?({:unknown, _}, result) or match?({:closed, {:error, _}}, result)
        phase = String.replace_prefix(mode, "source-loss-display-", "")
        lost_journal = root |> Path.join("pending-source-journal-id-" <> phase) |> File.read!()

        assert {:ok, records} =
                 Ipse.Journal.load(Path.join(home, "knowledge-management"), lost_journal)

        refute Enum.any?(
                 records,
                 &(&1["type"] in ~w(pending_proposal_accepted pending_acceptance_intent))
               )
    end

    refute File.exists?(Path.join(root, "pending-management-event.json"))
  end
end

IO.puts("PENDING_MANAGEMENT_REVIEW_#{String.upcase(mode)}_PASSED")
