defmodule Ipse.AuthHTTPTest do
  use ExUnit.Case, async: true

  alias Ipse.Auth.HTTP

  @terminal_codes [
    "invalid_grant",
    "invalid_refresh_token",
    "token_expired",
    "refresh_token_expired",
    "refresh_token_invalidated",
    "refresh_token_reused"
  ]

  test "classifies only allowlisted terminal OAuth codes on client errors" do
    for code <- @terminal_codes do
      body = Jason.encode!(%{"error" => code, "error_description" => "private detail"})
      assert {:error, {:oauth, ^code}} = HTTP.decode_response(400, body)
      assert {:error, {:oauth, ^code}} = HTTP.decode_response(499, body)

      assert {:error, generic} = HTTP.decode_response(500, body)
      assert is_binary(generic)
      refute generic =~ code
      refute generic =~ "private detail"
    end
  end

  test "invalid client is classified as configuration while rate limits remain generic" do
    body = Jason.encode!(%{"error" => "invalid_client", "error_description" => "secret-detail"})

    for status <- [400, 401, 403, 404, 499] do
      assert {:error, {:oauth, "invalid_client"}} = HTTP.decode_response(status, body)
    end

    for status <- [429, 500] do
      assert {:error, generic} = HTTP.decode_response(status, body)
      assert is_binary(generic)
      refute generic =~ "invalid_client"
      refute generic =~ "secret-detail"
    end
  end

  test "malformed, oversized and unrecognized OAuth bodies stay generic and private" do
    assert {:error, malformed} = HTTP.decode_response(400, "{bad json")
    assert is_binary(malformed)
    refute malformed =~ "bad json"

    oversized = String.duplicate("x", 1_048_577)
    assert {:error, too_large} = HTTP.decode_response(400, oversized)
    assert is_binary(too_large)
    refute too_large =~ String.slice(oversized, 0, 30)

    unknown = Jason.encode!(%{"error" => "account_locked", "error_description" => "private"})
    assert {:error, generic} = HTTP.decode_response(400, unknown)
    assert is_binary(generic)
    refute generic =~ "account_locked"
    refute generic =~ "private"
  end
end
