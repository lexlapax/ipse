defmodule Ipse.Provider.BoundaryTest do
  use ExUnit.Case, async: true
  alias Ipse.Provider

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
