defmodule Ipse.Provider.DestinationTest do
  use ExUnit.Case, async: true
  alias Ipse.Provider

  test "destination disclosure uses each actual adapter route without credential lookup" do
    for {provider, origin, target} <- [
          {:chatgpt, "https://api.openai.com", "https://api.openai.com/v1/responses"},
          {:openai, "https://api.openai.com", "https://api.openai.com/v1/responses"},
          {:anthropic, "https://api.anthropic.com", "https://api.anthropic.com/v1/messages"},
          {:ollama, "http://127.0.0.1:11434", "http://127.0.0.1:11434/api/chat"}
        ] do
      assert {:ok, facts} = Provider.destination(%{provider: provider})
      assert facts["origin"] == origin
      assert facts["target_sha256"] == Ipse.JSON.sha256(target)
      assert Provider.valid_destination?(facts)
    end

    assert {:error, _} = Provider.destination(%{provider: :demo})
  end

  test "custom origin is visible while path, query, userinfo and credentials stay out of disclosure" do
    assert {:ok, facts} =
             Provider.destination(%{
               provider: :openai,
               base_url: "https://proxy.example.invalid:8443/private-tenant/",
               api_key: "synthetic-private-key"
             })

    assert facts["origin"] == "https://proxy.example.invalid:8443"

    assert facts["target_sha256"] ==
             Ipse.JSON.sha256("https://proxy.example.invalid:8443/private-tenant/responses")

    refute Jason.encode!(facts) =~ "private-tenant"
    refute Jason.encode!(facts) =~ "synthetic-private-key"

    assert {:ok, ipv6} = Provider.destination(%{provider: :ollama, base_url: "http://[::1]:4321"})
    assert ipv6["origin"] == "http://[::1]:4321"

    for root <- [
          "https://name:synthetic@example.invalid",
          "https://example.invalid?key=synthetic",
          "https://example.invalid#synthetic",
          "http://remote.example.invalid",
          "https://example.invalid:65536",
          "https://example.invalid/ bad"
        ] do
      assert {:error, _} = Provider.destination(%{provider: :openai, base_url: root})

      assert {:error, _} =
               Ipse.Profiles.validate_profile(%{
                 "provider" => "openai",
                 "model" => "fixture",
                 "base_url" => root
               })
    end
  end

  test "destination facts are closed and reject non-origin URLs or malformed digests" do
    {:ok, facts} = Provider.destination(%{provider: :openai})

    for invalid <- [
          Map.delete(facts, "origin"),
          Map.put(facts, "api_key", "synthetic"),
          Map.put(facts, "target_sha256", "raw-url"),
          Map.put(facts, "origin", "https://example.invalid/path"),
          Map.put(facts, "origin", "https://example.invalid?key=synthetic"),
          Map.put(facts, "origin", "https://name@example.invalid"),
          Map.put(facts, "origin", "http://remote.example.invalid"),
          Map.put(facts, "origin", nil)
        ],
        do: refute(Provider.valid_destination?(invalid))
  end
end
