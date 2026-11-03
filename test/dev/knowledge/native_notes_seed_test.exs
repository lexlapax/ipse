Code.require_file("../../../dev/knowledge/native_notes_seed.ex", __DIR__)

defmodule Ipse.Development.NativeNotesSeedTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.NativeNotesSeed, as: Seed

  test "the complete initial population preserves the native daily ceiling and required mix" do
    plan = Seed.plan("initial")
    actions = Enum.flat_map(plan, & &1["actions"])
    captures = Enum.filter(actions, &(&1["op"] == "capture"))
    assert length(captures) == 2000
    assert length(actions) == 2100

    assert Enum.frequencies_by(captures, & &1["category"]) == %{
             "ordinary" => 1900,
             "preference" => 50,
             "current" => 50
           }

    pins = Enum.filter(actions, &(&1["op"] == "pin"))
    assert Enum.map(pins, & &1["number"]) == Enum.to_list(1..100)
    assert Enum.all?(captures, &(&1["number"] > 100 or &1["category"] == "ordinary"))
    assert Enum.all?(plan, &(length(&1["actions"]) in 1..8))
    assert Enum.map(plan, & &1["day"]) |> Enum.uniq() == Enum.to_list(0..20)

    assert Enum.group_by(plan, & &1["day"])
           |> Enum.all?(fn {_, segments} ->
             Enum.sum(Enum.map(segments, &length(&1["actions"]))) == 100
           end)

    assert Enum.map(captures, & &1["number"]) == Enum.to_list(1..2000)
  end

  test "the independent smoke plan spans fresh days and all native categories without claiming the full seed" do
    assert [first, second] = Seed.plan("smoke")
    assert first["day"] == 0 and second["day"] == 1
    assert length(first["actions"]) == 4 and length(second["actions"]) == 4
    assert Enum.frequencies_by(first["actions"], & &1["op"]) == %{"capture" => 3, "pin" => 1}
    assert Enum.all?(second["actions"], &(&1["category"] == "ordinary"))
  end

  test "recorded time summaries ignore deadlines and invalid values while retaining nested maxima" do
    events = [
      %{"checked_at_ms" => 5, "deadline_ms" => 999, "nested" => [%{"observed_at_ms" => 8}]},
      %{"checked_at_ms" => 7, "created_at_ms" => -1, "other" => %{"observed_at_ms" => 3}},
      %{"checked_at_ms" => "future", "finished_at_ms" => 9_007_199_254_740_992}
    ]

    assert Seed.recorded_times(events) == %{
             "events" => 3,
             "maxima_ms" => %{"checked_at_ms" => 7, "observed_at_ms" => 8}
           }

    assert Seed.recorded_times([]) == %{"events" => 0, "maxima_ms" => %{}}
  end

  test "the optional synthetic fixture route is explicit and restricted to loopback" do
    config = Seed.fixture_config(42_123)
    assert config["roles"]["main"] == "synthetic"
    assert config["profiles"]["synthetic"]["provider"] == "ollama"
    assert config["profiles"]["synthetic"]["base_url"] == "http://127.0.0.1:42123"
    assert config["inference_services"]["local"]["origins"] == ["http://127.0.0.1:42123"]

    for invalid <- [0, 65_536, -1, "42123"],
        do: assert_raise(FunctionClauseError, fn -> Seed.fixture_config(invalid) end)
  end
end
