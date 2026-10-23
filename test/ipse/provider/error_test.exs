defmodule Ipse.Provider.ErrorTest do
  use ExUnit.Case, async: true
  alias Ipse.Provider.Transport

  test "known ChatGPT codes retain bounded safe metadata and fixed recovery hints" do
    cases = [
      {403, "subscription_sharing_user_not_eligible", "ChatGPT plan usage is unavailable"},
      {429, "subscription_sharing_usage_limit_exceeded", "blocked by a limit or app setting"},
      {503, "subscription_sharing_usage_unavailable", "Preserve sign-in"},
      {400, "subscription_sharing_unsupported_capability", "unsupported ChatGPT plan capability"},
      {403, "subscription_sharing_route_not_supported", "POST /v1/responses"},
      {401, "subscription_sharing_invalid_user", "subscriber context was rejected"},
      {403, "chatpass_v2_scope_not_authorized", "permission context does not authorize"},
      {403, "chatpass_v2_invalid_authorization_context", "permission context does not authorize"},
      {503, "subscription_sharing_user_unavailable", "temporarily unavailable"}
    ]

    for {status, code, hint} <- cases do
      body =
        Jason.encode!(%{
          "error" => %{"code" => code, "param" => "tools[0]", "message" => "secret body text"}
        })

      assert {:error, text} =
               Transport.http_error(
                 status,
                 body,
                 [{~c"x-request-id", ~c"req_fixture-123"}],
                 :chatgpt
               )

      assert text =~ "HTTP #{status}"
      assert text =~ "body=error"
      assert text =~ "code=#{code}"
      assert text =~ "param=tools[0]"
      assert text =~ "request_id=req_fixture-123"
      assert text =~ hint
      refute text =~ "secret body text"
    end
  end

  test "direct admission detail keeps shape and safe request id, never detail prose" do
    assert {:error, text} =
             Transport.http_error(
               403,
               Jason.encode!(%{"detail" => "secret account and token detail"}),
               [{~c"x-request-id", ~c"req-detail-2"}],
               :chatgpt
             )

    assert text =~ "HTTP 403; body=detail"
    assert text =~ "request_id=req-detail-2"
    assert text =~ "serving region"
    refute text =~ "secret account"
  end

  test "malformed, oversized, and unsafe fields are bounded and omitted" do
    assert {:error, malformed} = Transport.http_error(403, "not json: secret", [], :chatgpt)
    assert malformed =~ "body=invalid"
    refute malformed =~ "secret"

    assert {:error, oversized} =
             Transport.http_error(403, String.duplicate("x", 32_769), [], :chatgpt)

    assert oversized =~ "body=oversize"
    assert byte_size(oversized) < 1_000

    body =
      Jason.encode!(%{
        "error" => %{
          "code" => "subscription_sharing_user_not_eligible\nrequest_id=forged",
          "param" => "key=secret",
          "message" => "should not be echoed"
        }
      })

    assert {:error, unsafe} =
             Transport.http_error(
               403,
               body,
               [{~c"x-request-id", ~c"bad value\nsecret"}],
               :chatgpt
             )

    refute unsafe =~ "request_id=forged"
    refute unsafe =~ "key=secret"
    refute unsafe =~ "bad value"
    refute unsafe =~ "should not be echoed"
  end

  test "generic API errors preserve the existing status contract" do
    assert {:error, "Provider returned HTTP 401."} =
             Transport.http_error(401, ~s({"error":{"message":"do not echo"}}), [], :openai)
  end

  test "ChatGPT direct 401 and generic 500 retain status, shape, and request ID" do
    assert {:error, unauthorized} =
             Transport.http_error(
               401,
               ~s({"detail":"private diagnostic"}),
               [{~c"x-request-id", ~c"req-401"}],
               :chatgpt
             )

    assert unauthorized =~ "HTTP 401; body=detail"
    assert unauthorized =~ "request_id=req-401"
    assert unauthorized =~ "selected account and granted scopes"
    refute unauthorized =~ "private diagnostic"

    assert {:error, unavailable} =
             Transport.http_error(
               500,
               ~s({"error":{"param":"model","message":"private diagnostic"}}),
               [{~c"x-request-id", ~c"req-500"}],
               :chatgpt
             )

    assert unavailable =~ "HTTP 500; body=error; param=model; request_id=req-500"
    assert unavailable =~ "Check ChatGPT plan access"
    refute unavailable =~ "private diagnostic"
  end

  test "stream error classification ignores provider message text" do
    assert {:error, text} =
             Transport.stream_error(%{
               "type" => "response.failed",
               "request_id" => "req_stream-5",
               "response" => %{
                 "status_code" => 429,
                 "error" => %{
                   "code" => "subscription_sharing_usage_limit_exceeded",
                   "param" => "model",
                   "message" => "secret stream message"
                 }
               }
             })

    assert text =~ "HTTP 429"
    assert text =~ "request_id=req_stream-5"
    assert text =~ "code=subscription_sharing_usage_limit_exceeded"
    refute text =~ "secret stream message"
  end

  test "stream HTTP request ID takes precedence and secret-like fields are rejected" do
    assert {:error, text} =
             Transport.stream_error(
               %{
                 "request_id" => "event-id",
                 "error" => %{"code" => "sk-secret-value", "param" => "bearer-secret"}
               },
               :chatgpt,
               "req-header-8"
             )

    assert text =~ "request_id=req-header-8"
    refute text =~ "event-id"
    refute text =~ "sk-secret-value"
    refute text =~ "bearer-secret"
  end
end
