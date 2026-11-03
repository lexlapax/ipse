Code.require_file("../../../dev/knowledge/native_notes_seed.ex", __DIR__)
Code.require_file("../../../dev/knowledge/native_notes_workload.ex", __DIR__)

defmodule Ipse.Development.NativeQuotaClockTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.NativeNotesWorkload, as: Workload
  alias Ipse.Extension.Consent
  alias Ipse.{JSON, Usage}

  test "the planned day ends where the actual consent quota rolls over" do
    day = 86_400_000
    seed = 1_800_000_000_000
    real_start = seed + 3_600_000
    previous = seed + 20 * day
    assert {:ok, anchor} = Workload.clock_day(seed, 21, real_start, previous)
    at_last_ms = anchor["end_ms"] - 1
    at_reset = anchor["end_ms"]
    assert div(at_last_ms, day) + 1 == div(at_reset, day)

    parent = Path.join(System.tmp_dir!(), "ipse-quota-clock-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "control")
    project = JSON.sha256("quota-clock-project")

    policy = %{
      "version" => 1,
      "project" => project,
      "artifact_sha256" => JSON.sha256("quota-clock-artifact"),
      "source_sha256" => JSON.sha256("quota-clock-source"),
      "operations" => ["knowledge.capture"],
      "settings" => %{},
      "limits" => Map.put(Consent.zero(), "operations", 1),
      "period_ms" => day,
      "expires_at_ms" => at_reset + day,
      "headless" => true
    }

    assert {:ok, %{"epoch" => 1}} = Consent.replace(root, project, 0, policy, anchor["start_ms"])

    request = fn ->
      %{
        "id" => Usage.id(),
        "operation" => "knowledge.capture",
        "artifact_sha256" => policy["artifact_sha256"],
        "source_sha256" => policy["source_sha256"],
        "policy_sha256" => JSON.digest([policy]),
        "request_sha256" => JSON.sha256("quota-clock-request"),
        "source_generation" => 1,
        "reserved" => Map.put(Consent.zero(), "operations", 1),
        "headless" => true
      }
    end

    first = request.()
    assert {:ok, ticket} = Consent.reserve(root, project, first, at_last_ms)
    assert {:ok, ^ticket} = Consent.admit(root, project, ticket, at_last_ms)
    assert {:ok, _} = Consent.settle(root, project, ticket, {:known, first["reserved"]})

    assert {:error, :consent_reservation_refused} =
             Consent.reserve(root, project, request.(), at_last_ms)

    assert {:ok, _} = Consent.reserve(root, project, request.(), at_reset)

    real_at_reset = real_start + (at_reset - anchor["start_ms"])
    assert {:error, :fixture_clock_refused} = Workload.clock_now(anchor, real_at_reset, previous)
  end
end
