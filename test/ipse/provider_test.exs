defmodule Ipse.ProviderTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider
  alias Ipse.Provider.OpenAI
  alias Ipse.Provider.Anthropic

  describe "provider/boundary" do
    test "subscription endpoint validation is enforced below the CLI" do
      config = %{provider: :chatgpt, api_key: "private-fixture-token"}

      assert Provider.endpoint(config, "https://api.openai.com/v1", "/responses") ==
               "https://api.openai.com/v1/responses"

      for url <- [
            "https://attacker.invalid",
            "https://api.openai.com.attacker.invalid/v1",
            "https://user@api.openai.com/v1",
            "http://api.openai.com/v1",
            "http://user@127.0.0.1:1234",
            "http://127.0.0.1.attacker.invalid"
          ] do
        assert_raise ArgumentError, fn ->
          Provider.endpoint(
            Map.put(config, :base_url, url),
            "https://api.openai.com/v1",
            "/responses"
          )
        end
      end

      assert {:error, error} =
               Provider.complete(
                 Map.put(config, :base_url, "https://attacker.invalid"),
                 [],
                 [],
                 fn _ -> :ok end
               )

      refute error =~ config.api_key
    end

    test "explicit API endpoint overrides remain supported" do
      assert Provider.endpoint(
               %{provider: :openai, base_url: "http://localhost:1234/v1/"},
               "https://api.openai.com/v1",
               "/responses"
             ) == "http://localhost:1234/v1/responses"
    end
  end

  describe "provider/destination" do
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

      assert {:ok, ipv6} =
               Provider.destination(%{provider: :ollama, base_url: "http://[::1]:4321"})

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
                 Ipse.Config.Profiles.validate_profile(%{
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

  describe "provider/limits" do
    test "caps validate provider capability and integer bounds without inventing a subscription limit" do
      for provider <- [:chatgpt, :openai, :anthropic, :ollama, :demo] do
        assert :ok = Provider.validate_output_limit(%{provider: provider})
      end

      for {provider, minimum} <- [openai: 16, anthropic: 1, ollama: 1] do
        for value <- [minimum, Provider.max_output_tokens()] do
          assert :ok =
                   Provider.validate_output_limit(%{provider: provider, max_output_tokens: value})
        end

        for value <- [0, -1, 1.5, "32", false, Provider.max_output_tokens() + 1] do
          assert {:error, _} =
                   Provider.validate_output_limit(%{provider: provider, max_output_tokens: value})
        end
      end

      assert {:error, _} =
               Provider.validate_output_limit(%{provider: :openai, max_output_tokens: 15})

      assert {:error, message} =
               Provider.validate_output_limit(%{provider: :chatgpt, max_output_tokens: 128})

      assert message =~ "does not support"

      assert {:error, _} =
               Provider.validate_output_limit(%{provider: :demo, max_output_tokens: 128})

      assert {:error, ^message} =
               Ipse.Provider.complete(
                 %{provider: :chatgpt, max_output_tokens: 128},
                 [],
                 [],
                 fn _ ->
                   flunk("unsupported request must not dispatch")
                 end
               )
    end

    test "Responses API cap preserves native continuation and never reaches subscription requests" do
      native = [%{"type" => "reasoning", "encrypted_content" => "synthetic-opaque"}]

      messages = [
        %{"role" => "assistant", "provider_data" => %{"provider" => "openai", "output" => native}}
      ]

      config = %{provider: :openai, model: "fixture", max_output_tokens: 256}
      body = OpenAI.request_body(config, messages, [])
      assert body["max_output_tokens"] == 256
      assert body["input"] == native
      assert body["store"] == false

      refute Map.has_key?(
               OpenAI.request_body(Map.delete(config, :max_output_tokens), [], []),
               "max_output_tokens"
             )

      refute Map.has_key?(
               OpenAI.request_body(%{provider: :chatgpt, model: "fixture"}, [], []),
               "max_output_tokens"
             )

      assert_raise ArgumentError, fn ->
        OpenAI.request_body(%{config | provider: :chatgpt}, [], [])
      end
    end

    test "Anthropic cap narrows its existing bound and preserves the uncapped request shape" do
      config = %{provider: :anthropic, model: "fixture"}
      assert Anthropic.request_body(config, [], [])["max_tokens"] == 8192

      assert Anthropic.request_body(Map.put(config, :max_output_tokens, 32), [], [])["max_tokens"] ==
               32

      assert Anthropic.request_body(Map.put(config, :max_output_tokens, 20_000), [], [])[
               "max_tokens"
             ] == 8192

      assert Anthropic.request_body(
               Map.merge(config, %{max_tokens: 24, max_output_tokens: 32}),
               [],
               []
             )["max_tokens"] == 24
    end
  end
end
