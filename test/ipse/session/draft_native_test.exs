defmodule Ipse.Session.DraftNativeTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.DraftNative

  defp assistant do
    %{
      "role" => "assistant",
      "content" => "draft answer canary",
      "provider_data" => %{
        "provider" => "openai",
        "reported_model" => "synthetic",
        "output" => [
          %{
            "type" => "reasoning",
            "id" => "rs_draft",
            "summary" => [],
            "content" => nil,
            "encrypted_content" => "opaque draft canary"
          },
          %{
            "type" => "message",
            "id" => "msg_draft",
            "role" => "assistant",
            "status" => "completed",
            "phase" => "final_answer",
            "content" => [
              %{
                "type" => "output_text",
                "text" => "draft answer canary",
                "annotations" => [],
                "logprobs" => []
              }
            ]
          }
        ]
      }
    }
  end

  test "complete stateless Responses interval can be omitted from encoded continuation" do
    prefix = [%{"role" => "user", "content" => "earlier request"}]
    segment = [%{"role" => "user", "content" => "private draft canary"}, assistant()]
    tail = [%{"role" => "user", "content" => "unrelated request"}]
    assert DraftNative.isolated_responses?(prefix, segment, tail)

    body =
      Ipse.Provider.OpenAI.request_body(
        %{provider: :chatgpt, model: "fixture"},
        prefix ++ tail,
        []
      )

    refute inspect(body) =~ "private draft canary"
    refute inspect(body) =~ "draft answer canary"
    refute inspect(body) =~ "opaque draft canary"
    assert body["store"] == false
    refute Map.has_key?(body, "previous_response_id")

    prior =
      assistant()
      |> put_in(["content"], "draft answer canary")
      |> put_in(["provider_data", "output", Access.at(0), "id"], "rs_prior")
      |> put_in(["provider_data", "output", Access.at(1), "id"], "msg_prior")

    assert DraftNative.isolated_responses?([prior], segment, tail)

    body_with_prior =
      Ipse.Provider.OpenAI.request_body(
        %{provider: :chatgpt, model: "fixture"},
        [prior | tail],
        []
      )

    assert Enum.take(body_with_prior["input"], 2) == prior["provider_data"]["output"]
  end

  test "unknown items, inconsistent visible text and ambiguous links refuse" do
    segment = [%{"role" => "user", "content" => "draft"}, assistant()]
    tail = [%{"role" => "user", "content" => "new"}]
    bad_text = put_in(assistant(), ["content"], "forged")
    refute DraftNative.isolated_responses?([], [hd(segment), bad_text], tail)
    output = get_in(assistant(), ["provider_data", "output"])

    foreign =
      put_in(
        assistant(),
        ["provider_data", "output"],
        output ++ [%{"type" => "item_reference", "id" => "msg_other"}]
      )

    refute DraftNative.isolated_responses?([], [hd(segment), foreign], tail)
    refute DraftNative.isolated_responses?([assistant()], segment, tail)

    annotated =
      put_in(
        assistant(),
        ["provider_data", "output", Access.at(1), "content", Access.at(0), "annotations"],
        [%{"type" => "file_citation", "file_id" => "old"}]
      )

    refute DraftNative.isolated_responses?([], [hd(segment), annotated], tail)
  end

  test "native function calls must match visible calls and remain paired inside the interval" do
    native = %{
      "type" => "function_call",
      "id" => "item_draft",
      "call_id" => "call_draft",
      "name" => "read",
      "arguments" => "{}",
      "status" => "completed"
    }

    call = %{
      "id" => "call_draft",
      "type" => "function",
      "function" => %{"name" => "read", "arguments" => "{}"}
    }

    assistant = %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [call],
      "provider_data" => %{"provider" => "openai", "output" => [native]}
    }

    result = %{"role" => "tool", "tool_call_id" => "call_draft", "content" => "draft tool result"}
    tail = [%{"role" => "user", "content" => "new"}]
    assert DraftNative.isolated_responses?([], [assistant, result], tail)
    refute DraftNative.isolated_responses?([], [assistant], [result | tail])
    refute DraftNative.isolated_responses?([assistant, result], [assistant, result], tail)
    unsafe = put_in(assistant, ["provider_data", "previous_response_id"], "prior")
    refute DraftNative.isolated_responses?([], [unsafe, result], tail)

    refute DraftNative.isolated_responses?(
             [],
             [put_in(assistant, ["tool_calls", Access.at(0), "id"], "forged"), result],
             tail
           )
  end
end
