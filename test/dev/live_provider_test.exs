Code.require_file("../../dev/verification/live_provider.exs", __DIR__)
Code.require_file("../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Development.LiveProviderTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Verification.LiveProvider
  alias Ipse.Test.ProviderFixture, as: Fixture

  defp config(extra \\ %{}),
    do:
      Map.merge(
        %{provider: :gemini, model: "gemini-fixture", api_key: "live-fixture-secret"},
        extra
      )

  defp usage,
    do: %{
      "promptTokenCount" => 3,
      "toolUsePromptTokenCount" => 0,
      "candidatesTokenCount" => 2,
      "thoughtsTokenCount" => 1,
      "totalTokenCount" => 6
    }

  defp response(parts),
    do:
      Fixture.sse(%{
        "candidates" => [
          %{"content" => %{"role" => "model", "parts" => parts}, "finishReason" => "STOP"}
        ],
        "usageMetadata" => usage()
      })

  test "three real wire requests preserve signed tool history without disclosing transcripts or keys" do
    signed = [
      %{
        "functionCall" => %{
          "id" => "native-call",
          "name" => "ipse_live_echo",
          "args" => %{"value" => "p29"}
        },
        "thoughtSignature" => "PRIVATE_SIGNATURE"
      }
    ]

    {base, server} =
      Fixture.sequence([
        response([%{"text" => "IPSE_LIVE_TEXT_OK"}]),
        response(signed),
        response([%{"text" => "IPSE_LIVE_TOOL_OK"}])
      ])

    report =
      LiveProvider.run(
        config(%{base_url: base, max_output_tokens: 32, timeout_ms: 4000}),
        &Ipse.Provider.request_complete/4
      )

    assert report["status"] == "passed"
    assert report["text_verified"]
    assert report["native_tool_continuation_verified"]
    assert length(report["requests"]) == 3
    assert Enum.all?(report["requests"], &(&1["usage"]["counts"]["total_tokens"] == 6))
    assert Enum.at(report["requests"], 1)["native_continuation"]["signed_parts"] == 1
    encoded = Jason.encode!(report)

    for secret <- ~w(PRIVATE_SIGNATURE live-fixture-secret IPSE_LIVE_TEXT_OK IPSE_LIVE_TOOL_OK),
        do: refute(encoded =~ secret)

    requests = Task.await(server)

    for {headers, body} <- requests do
      assert headers =~ "x-goog-api-key: live-fixture-secret"
      assert body["generationConfig"]["maxOutputTokens"] == 32
    end

    {_, third} = Enum.at(requests, 2)
    assert Enum.at(third["contents"], 1) == %{"role" => "model", "parts" => signed}
  end

  test "a failed second request remains in the receipt with observed usage and cannot retry" do
    counter = make_ref()

    request = fn selected, _messages, _tools, emit ->
      assert selected.max_output_tokens == 1024
      assert selected.timeout_ms == 60_000
      assert selected.max_response_bytes == 65_536
      number = Process.get(counter, 0) + 1
      Process.put(counter, number)

      case number do
        1 ->
          {:ok, %{"role" => "assistant", "content" => "IPSE_LIVE_TEXT_OK"}, usage()}

        2 ->
          emit.({:provider_usage, usage()})
          {:error, "rejected live-fixture-secret"}

        _ ->
          flunk("unexpected retry")
      end
    end

    report = LiveProvider.run(config(), request)
    assert report["status"] == "failed"
    assert report["text_verified"]
    assert length(report["requests"]) == 2
    failed = List.last(report["requests"])
    assert failed["outcome"] == "failed"
    assert failed["usage"]["counts"]["total_tokens"] == 6
    assert failed["error"] == "rejected [redacted]"
    assert Process.delete(counter) == 2
  end

  test "wrong tool arguments stop after two requests instead of running arbitrary model-selected work" do
    counter = make_ref()

    request = fn _, _, _, _ ->
      number = Process.get(counter, 0) + 1
      Process.put(counter, number)

      case number do
        1 ->
          {:ok, %{"content" => "IPSE_LIVE_TEXT_OK"}, usage()}

        2 ->
          {:ok,
           %{
             "tool_calls" => [
               %{"id" => "x", "function" => %{"name" => "shell", "arguments" => "{}"}}
             ]
           }, usage()}

        _ ->
          flunk("unexpected execution")
      end
    end

    report = LiveProvider.run(config(), request)
    assert report["status"] == "failed"
    assert length(report["requests"]) == 2
    refute report["native_tool_continuation_verified"]
    assert Process.delete(counter) == 2
  end

  test "unsupported routes and configured budgets refuse before any request" do
    for selected <- [
          config(%{budget: %{"version" => 1}}),
          config(%{provider: :openai}),
          config(%{model: "Bad/Path"})
        ] do
      report = LiveProvider.run(selected, fn _, _, _, _ -> flunk("preflight bypass") end)
      assert report["status"] == "refused"
      assert report["requests"] == []
    end

    assert {:error, _} = LiveProvider.preflight(config(), "openrouter")
  end

  test "CLI requires exact explicit provider confirmation before model traffic" do
    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["dev/verify.exs", "live", "provider", "--provider", "gemini"],
        env: [
          {"IPSE_LIVE_PROVIDER_CONFIRM", nil},
          {"ERL_CRASH_DUMP", "/dev/null"},
          {"MIX_ENV", "dev"}
        ],
        stderr_to_stdout: true
      )

    assert status == 1
    assert output =~ "IPSE_LIVE_PROVIDER_CONFIRM"
    refute output =~ "live_provider_plan"
  end
end
