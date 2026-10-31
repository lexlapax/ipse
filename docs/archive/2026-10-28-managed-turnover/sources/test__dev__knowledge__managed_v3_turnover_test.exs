unless Code.ensure_loaded?(IpseKnowledge.Notes),
  do: Code.require_file("../../../extensions/knowledge/src/notes.ex", __DIR__)

Code.require_file("../../../dev/knowledge/managed_v3_turnover.exs", __DIR__)

defmodule Ipse.Development.ManagedV3TurnoverTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.ManagedV3Turnover, as: Turnover

  test "the finite schedule retains workload floors, all checkpoints and a seven-day offline queue" do
    days = Turnover.schedule()
    assert length(days) == 365
    assert Enum.map(Enum.filter(days, & &1["checkpoint"]), & &1["day"]) == [30, 90, 365]
    assert Enum.sum(Enum.map(days, & &1["ordinary"])) == 7320
    assert Enum.sum(Enum.map(days, & &1["corrections"])) == 1460
    assert Enum.sum(Enum.map(days, & &1["forgets"])) == 730
    assert Enum.sum(Enum.map(days, & &1["temporal_supersessions"])) == 1460
    assert Enum.sum(Enum.map(days, & &1["separate_cycles"])) == 10_000
    queued = Enum.filter(days, &(&1["admit_at_ms"] > &1["source_at_ms"]))
    assert Enum.map(queued, & &1["day"]) == Enum.to_list(24..30)
    assert length(Enum.uniq(Enum.map(queued, & &1["admit_at_ms"]))) == 1
    assert Enum.at(days, 89)["ordinary"] == 40
  end

  test "production pure policy honors ordinary, history, pin and saved override clock boundaries" do
    assert Enum.all?(Turnover.clock_controls(), fn
             {key, value} when key in ~w(qualification actual_native_turnover_executed) ->
               value === false

             {_, value} ->
               value === true
           end)
  end

  test "a pure schedule and policy checks cannot masquerade as actual native turnover" do
    manifest = Turnover.manifest()
    refute manifest["qualification"]
    refute manifest["actual_native_turnover_executed"]
    assert manifest["schedule_sha256"] == Ipse.JSON.digest(Turnover.schedule())
    assert manifest["initial_persistent"] == %{"pin" => 100, "preference" => 50, "current" => 50}
    assert manifest["native_limits"]["total_bytes"] == 64 * 1024 * 1024
    assert "temporal_supersession" in manifest["remaining_native_operations"]
  end
end
