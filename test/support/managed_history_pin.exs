# Actual pin and supersession; source membership is a trusted fixture.
defmodule Ipse.Test.ManagedHistoryPin do
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal}
  alias Ipse.Extension.{Collection, ProjectIdentity}
  alias Ipse.Extension.Collection.{ManagedRetention, NormalizerV3, ObservedRead}
  alias Ipse.Session.ManagedLifecycle
  alias Ipse.Runner.Review

  def pin(c, old, context, observe, writer) do
    {:ok, initial} = observe.(old)

    {:ok, prepared} =
      ManagedLifecycle.prepare_retention(
        context,
        initial,
        %{"kind" => "pin"},
        "Pin exact prior assertion"
      )

    facts = prepared["facts"]
    assert :ok = Journal.Writer.append(writer, prepared["intent"])

    assert {:ok, core} =
             Review.with_review("pin", facts, fn permit ->
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
                     Collection.execute_managed_v3(
                       c.root,
                       c.namespace,
                       prepared["request"],
                       facts["operation_id"],
                       JSON.digest([old.recipe]),
                       fn witness, read ->
                         NormalizerV3.retain(witness, read, %{
                           request: prepared["request"],
                           facts: facts,
                           permit: permit,
                           now_ms: System.system_time(:millisecond),
                           domain_cap: cap,
                           catalog: catalog
                         })
                       end
                     )
                   end
                 )

               assert {:ok, core} = result
               {:ok, core}
             end)

    assert core["normalization"]["category"] == "pin"

    assert :ok =
             Journal.Writer.append(writer, %{
               "type" => "managed_lifecycle_result",
               "operation_id" => facts["operation_id"],
               "outcome" => core
             })

    :ok
  end

  def check(c, old, new, context, observe, writer) do
    key = hd(old.request["changes"])["key"]

    observe_history = fn ->
      ProjectIdentity.with_existing_domain_auth(
        c.home,
        c.cwd,
        c.binding,
        %{namespace: c.namespace, format: "managed-metadata-v3"},
        fn cap, catalog ->
          ObservedRead.managed_history(
            c.root,
            c.namespace,
            %{"op" => "get_record", "key" => key},
            cap,
            catalog,
            old.recipe
          )
        end
      )
    end

    assert {:ok, history} = observe_history.()

    assert history["metadata"]["previous_category"] == "pin"
    assert history["metadata"]["valid_until_ms"] == nil
    assert history["successor_storage"] == "matching_record"
    far = System.system_time(:millisecond) + 1000 * 365 * 86_400_000
    assert ManagedRetention.eligible_history_metadata?(history["metadata"], far)
    refute ManagedRetention.expired_history_metadata?(history["metadata"], far)

    assert {:error, :managed_lifecycle_refused} =
             ManagedLifecycle.prepare_history_expiry(context, history, far)

    assert {:ok, current} = observe.(new)
    assert {:ok, prepared} = ManagedLifecycle.prepare(context, current, "Forget exact successor")
    facts = prepared["facts"]
    assert :ok = Journal.Writer.append(writer, prepared["intent"])

    assert {:ok, core} =
             Review.with_review("forget", facts, fn permit ->
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
                     Collection.execute_managed_v3(
                       c.root,
                       c.namespace,
                       prepared["request"],
                       facts["operation_id"],
                       JSON.digest([new.recipe]),
                       fn witness, read ->
                         NormalizerV3.forget(witness, read, %{
                           request: prepared["request"],
                           facts: facts,
                           permit: permit,
                           now_ms: System.system_time(:millisecond),
                           domain_cap: cap,
                           catalog: catalog
                         })
                       end
                     )
                   end
                 )

               assert {:ok, core} = result
               {:ok, core}
             end)

    assert :ok =
             Journal.Writer.append(writer, %{
               "type" => "managed_lifecycle_result",
               "operation_id" => facts["operation_id"],
               "outcome" => core
             })

    assert {:ok, retained} = observe_history.()
    assert retained["successor_storage"] == "unavailable"
    assert retained["metadata"] == history["metadata"]
    assert retained["observation"]["value"] == history["observation"]["value"]
    assert ManagedRetention.eligible_history_metadata?(retained["metadata"], far)

    IO.puts("NATIVE_PINNED_HISTORY_PASSED")
  end
end
