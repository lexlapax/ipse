defmodule Ipse.Development.ManagedV3Turnover do
  @moduledoc "Bounded proposed turnover schedule and pure production-policy clock controls; no store mutation."
  alias Ipse.JSON
  alias IpseKnowledge.Notes
  @day 86_400_000
  @epoch 1_800_000_000_000

  def schedule do
    for day <- 1..365 do
      %{
        "day" => day,
        "source_at_ms" => @epoch + day * @day,
        "admit_at_ms" => @epoch + if(day in 24..30, do: 31, else: day) * @day,
        "ordinary" => if(day == 90, do: 40, else: 20),
        "corrections" => 4,
        "forgets" => 2,
        "temporal_supersessions" => 4,
        "separate_cycles" => div(day * 10_000, 365) - div((day - 1) * 10_000, 365),
        "checkpoint" => day in [30, 90, 365]
      }
    end
  end

  def manifest do
    %{
      "version" => 1,
      "kind" => "proposed_managed_v3_turnover",
      "epoch_ms" => @epoch,
      "initial_persistent" => %{"pin" => 100, "preference" => 50, "current" => 50},
      "turns_per_day" => 40,
      "checkpoints" => [30, 90, 365],
      "offline_days" => Enum.to_list(24..30),
      "day_90_burst_multiplier" => 2,
      "separate_cycles" => 10_000,
      "cycle_semantics" =>
        "update/correct/forget mix and targets require a frozen typed adapter before execution",
      "schedule_sha256" => JSON.digest(schedule()),
      "native_limits" => Ipse.Extension.Collection.limits(),
      "implemented_typed_increment" => "exact native-reviewed signed literal forget",
      "remaining_native_operations" =>
        ~w(pin retention_change correction temporal_supersession expiry_collect suppression_compaction import_adoption),
      "actual_native_turnover_executed" => false,
      "qualification" => false
    }
  end

  @doc "Run the production pure Notes policy against a frozen clock; performs no native IO or publication."
  def clock_controls do
    {:ok, ordinary} = Notes.new(attrs("ordinary", 1), @epoch)
    true = Notes.eligible?(ordinary, @epoch + 90 * @day - 1)
    false = Notes.eligible?(ordinary, @epoch + 90 * @day)
    {:ok, [^ordinary]} = Notes.expired([ordinary], @epoch + 90 * @day)
    {:ok, preference} = Notes.new(attrs("preference", 2), @epoch)
    true = Notes.eligible?(preference, @epoch + 366 * @day)
    {:ok, current} = Notes.new(attrs("current", 3), @epoch)
    true = Notes.eligible?(current, @epoch + 91 * @day)
    replacement = attrs("current", 3) |> Map.put("lineage", JSON.sha256("replacement support"))
    {:ok, %{"history" => history}} = Notes.supersede(current, replacement, @epoch + 91 * @day)
    true = Notes.eligible?(history, @epoch + 456 * @day - 1)
    false = Notes.eligible?(history, @epoch + 456 * @day)
    {:ok, pin} = Notes.new(attrs("pin", 4), @epoch)

    {:ok, %{"history" => pinned_history}} =
      Notes.supersede(pin, attrs("current", 4), @epoch + 91 * @day)

    true = Notes.eligible?(pinned_history, @epoch + 1000 * @day)

    {:ok, downgrade} =
      Notes.retention(
        preference,
        %{"kind" => "ordinary"},
        "Frozen operator downgrade",
        @epoch + 30 * @day,
        :absent
      )

    {:ok, recapture} =
      Notes.new(attrs("preference", 2), @epoch + 60 * @day, downgrade["override"])

    true = recapture["expires_at_ms"] == @epoch + 120 * @day

    {:ok, forgotten} =
      Notes.forget(ordinary, "Frozen operator forget", @epoch + 30 * @day, :absent)

    {:suppressed, _} =
      Notes.new(attrs("preference", 1), @epoch + 60 * @day, forgotten["override"])

    %{
      "ordinary_day_90_boundary" => true,
      "persistent_preference" => true,
      "first_temporal_update_after_day_90" => true,
      "temporal_support_365_days_after_supersession" => true,
      "pinned_history_persistent" => true,
      "recall_does_not_renew_deadline" => true,
      "saved_downgrade_deadline_not_renewed" => true,
      "saved_forget_suppresses_recapture" => true,
      "pure_policy_only" => true,
      "actual_native_turnover_executed" => false,
      "qualification" => false
    }
  end

  defp attrs(category, n) do
    %{
      "id" => JSON.sha256("note#{n}"),
      "lineage" => JSON.sha256("support#{n}"),
      "text" => "Synthetic frozen clock claim #{n}",
      "evidence" => %{"synthetic" => true},
      "category" => category,
      "reason" => "Explicit pure clock fixture",
      "observed_at_ms" => @epoch,
      "event_at_ms" => nil
    }
  end
end

if System.argv() == ["--clock-controls"] do
  unless Code.ensure_loaded?(IpseKnowledge.Notes),
    do: Code.require_file("../../extensions/knowledge/src/notes.ex", __DIR__)

  IO.puts(
    Jason.encode!(
      %{
        "manifest" => Ipse.Development.ManagedV3Turnover.manifest(),
        "clock_controls" => Ipse.Development.ManagedV3Turnover.clock_controls()
      },
      pretty: true
    )
  )
end
