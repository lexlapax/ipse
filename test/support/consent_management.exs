import ExUnit.Assertions
alias Ipse.{JSON, Usage, Session.Resources, Runner.Review}
alias Ipse.Extension.Consent

[root, scenario] = System.argv()
{:ok, _} = Application.ensure_all_started(:ipse)
control = Path.join(root, "control")
project = JSON.sha256("synthetic management project")
now = System.system_time(:millisecond)

policy = %{
  "version" => 1,
  "project" => project,
  "artifact_sha256" => JSON.sha256("synthetic artifact"),
  "source_sha256" => JSON.sha256("synthetic source"),
  "operations" => ["knowledge.capture"],
  "settings" => %{},
  "limits" => Map.put(Consent.zero(), "operations", 1),
  "period_ms" => 1000,
  "expires_at_ms" => now + 1,
  "headless" => false
}

assert {:ok, _} = Consent.replace(control, project, 0, policy, now)
if scenario == "revoked", do: assert({:ok, _} = Consent.revoke(control, project, 1))
assert {:ok, snapshot} = Consent.existing_snapshot(control, project)
epoch = snapshot["epoch"]
fingerprint = Consent.management_sha256(project, epoch, snapshot["policy"])
operation = Usage.id()

body = %{
  "kind" => "managed_literal_forget",
  "operation_id" => operation,
  "target" => "synthetic Consent component; no Collection mutation",
  "context" => %{
    "project_id" => project,
    "management_epoch" => epoch,
    "management_sha256" => fingerprint
  }
}

facts = Map.put(body, "action_sha256", JSON.digest([body]))

request = %{
  "id" => operation,
  "operation" => "collection.forget",
  "artifact_sha256" => policy["artifact_sha256"],
  "source_sha256" => JSON.digest([facts]),
  "policy_sha256" => fingerprint,
  "request_sha256" => facts["action_sha256"],
  "source_generation" => 1,
  "reserved" =>
    Map.merge(Consent.zero(), %{
      "operations" => 1,
      "input_bytes" => 65_536,
      "output_bytes" => 16_384
    }),
  "headless" => false
}

before = File.read!(Path.join([control, project, "control.json"]))
forged = %Review.Permit{owner: self(), ref: make_ref()}

assert {:error, :consent_management_refused} =
         Consent.forget_deferred(control, project, epoch, request, forged, facts, now + 10, fn ->
           flunk("forged review reached a management callback")
         end)

assert File.read!(Path.join([control, project, "control.json"])) == before

result =
  Resources.file_effect(fn ->
    Review.with_review("forget", facts, fn permit ->
      cond do
        scenario == "stale" ->
          assert {:ok, _} = Consent.revoke(control, project, epoch)

          assert {:error, :consent_management_refused} =
                   Consent.forget_deferred(
                     control,
                     project,
                     epoch,
                     request,
                     permit,
                     facts,
                     now + 10,
                     fn ->
                       flunk("old management epoch reached effect")
                     end
                   )

          {:error, :consent_management_refused}

        scenario == "forbidden" ->
          before = File.read!(Path.join([control, project, "control.json"]))

          for bad <- [
                put_in(request, ["reserved", "model_calls"], 1),
                Map.put(request, "headless", true),
                Map.put(request, "source_sha256", JSON.sha256("foreign facts")),
                Map.put(request, "operation", "shell")
              ] do
            assert {:error, :consent_management_refused} =
                     Consent.forget_deferred(
                       control,
                       project,
                       epoch,
                       bad,
                       permit,
                       facts,
                       now + 10,
                       fn ->
                         flunk("management widened its effect authority")
                       end
                     )

            assert File.read!(Path.join([control, project, "control.json"])) == before
          end

          {:error, :consent_management_refused}

        true ->
          publication =
            Consent.forget_deferred(
              control,
              project,
              epoch,
              request,
              permit,
              facts,
              now + 10,
              fn ->
                assert {:error, :consent_unavailable} = Consent.revoke(control, project, epoch)
                assert {:ok, receipt} = Review.consume(permit, "forget", facts)

                if scenario == "unknown",
                  do: raise("synthetic failure after consuming the review")

                {:ok, request["reserved"],
                 %{
                   "action_sha256" => facts["action_sha256"],
                   "native_review_sha256" => JSON.digest([receipt]),
                   "synthetic" => true
                 }}
              end
            )

          if scenario == "unknown" do
            assert {:unknown, :publication_unconfirmed} = publication
            publication
          else
            assert {:ok, %{"ticket" => _} = packet} = publication

            assert {:error, :consent_management_refused} =
                     Consent.forget_deferred(
                       control,
                       project,
                       epoch,
                       request,
                       permit,
                       facts,
                       now + 10,
                       fn ->
                         flunk("consumed management review replayed")
                       end
                     )

            {:ok, packet}
          end
      end
    end)
  end)

assert {:ok, state} = Consent.existing_snapshot(control, project)

case scenario do
  value when value in ~w(revoked expired) ->
    assert {:ok, packet} = result
    assert state["operations"][operation]["status"] == "publishing"
    assert state["operations"][operation]["actual"] == nil

    assert {:ok, _} =
             Consent.settle(
               control,
               project,
               packet["ticket"],
               {:known, packet["actual"], packet["receipt"]}
             )

    assert {:ok, settled} = Consent.existing_snapshot(control, project)
    assert settled["operations"][operation]["status"] == "settled"
    assert settled["policy"] === snapshot["policy"]

    assert {:error, :consent_publication_refused} =
             Consent.publish_deferred(control, project, packet["ticket"], now + 10, fn ->
               flunk("management ticket became ordinary capture authority")
             end)

  "unknown" ->
    assert {:unknown, :native_review_unconfirmed} = result
    assert state["operations"][operation]["status"] == "publishing"
    assert state["operations"][operation]["actual"] == nil

  value when value in ~w(stale forbidden) ->
    assert {:error, :consent_management_refused} = result
    refute Map.has_key?(state["operations"], operation)
end

IO.puts("CONSENT_MANAGEMENT_#{String.upcase(scenario)}_PASSED")
