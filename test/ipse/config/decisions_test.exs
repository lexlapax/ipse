defmodule Ipse.Config.DecisionsTest do
  use ExUnit.Case, async: true
  alias Ipse.Config.Decisions

  defp profile,
    do: %{
      "operation" => "decision",
      "provider" => "system_one",
      "model" => "jev-latest",
      "expected_model" => "jev-1.13",
      "service_id" => "typesafe"
    }

  defp config(profile),
    do: %{
      extensions: [%{identity: %{"capabilities" => ["host.decision"]}}],
      decision_profiles: %{"test" => profile},
      timeout_ms: 10000
    }

  test "operator selection pins service, model identity, destination and nullable disclosures" do
    assert :ok = Decisions.validate(%{"test" => profile()})

    assert {:ok, %{"test" => selected}} =
             Decisions.resolve([
               %{scope: "operator", data: %{"decision_profiles" => %{"test" => profile()}}}
             ])

    assert selected == profile()

    assert {:error, _} =
             Decisions.resolve([%{scope: "project", data: %{"decision_profiles" => %{}}}])

    snapshot = Decisions.snapshot(config(profile()))
    assert Decisions.public_profile?(snapshot["test"])
    assert snapshot["test"]["expected_model"] == "jev-1.13"
    assert snapshot["test"]["billing_mode"] == "api"

    for key <- ~w(pricing processing_region storage_region cache_retention account_controls),
        do: assert(is_nil(snapshot["test"][key]))

    assert snapshot["test"]["destination"]["origin"] == "https://api.typesafe.ai"
    request = %{"profile" => "test", "timeout_ms" => 2000}
    assert {:ok, runtime, execution} = Decisions.prepare(config(profile()), request)
    assert runtime.model == "jev-latest"
    assert runtime.expected_model == "jev-1.13"
    refute Map.has_key?(runtime, :api_key)
    assert execution["timeout_ms"] == 2000
    assert {:ok, _} = Decisions.selection_sha256(execution, snapshot["test"]["destination"])
    refute Decisions.public_profile?(put_in(snapshot["test"], ["billing_mode"], "subscription"))
  end

  test "compatible selection is explicit and no provider, credential, or billing substitution is accepted" do
    for mutation <- [
          %{"provider" => "ollama"},
          %{"credential" => "chatgpt"},
          %{"operation" => "text"},
          %{"extra" => true},
          %{"timeout_ms" => 600_001},
          %{"provider" => "openai", "model" => "other"}
        ] do
      assert {:error, _} = Decisions.validate_profile(Map.merge(profile(), mutation))
    end

    local =
      profile()
      |> Map.put("provider", "system_one_compatible")
      |> Map.put("service_id", "local_fixture")

    assert {:error, _} = Decisions.validate_profile(local)

    assert {:error, _} =
             Decisions.validate_profile(Map.put(local, "base_url", "https://remote.invalid"))

    local = Map.put(local, "base_url", "http://127.0.0.1:4321/v1")
    assert :ok = Decisions.validate_profile(local)
    assert Decisions.snapshot(config(local))["test"]["billing_mode"] == "local"

    assert {:error, _} =
             Decisions.execution(%{"decision_profiles" => Decisions.snapshot(config(local))}, %{
               "profile" => "missing",
               "timeout_ms" => 2000
             })

    assert nil == Decisions.snapshot(%{decision_profiles: %{"bad" => %{}}})
  end
end
