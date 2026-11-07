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

  test "OpenAI API draft withdrawal uses the same bounded Responses isolation" do
    prefix = [%{"role" => "user", "content" => "earlier request"}]
    segment = [%{"role" => "user", "content" => "private draft canary"}, assistant()]
    notice = %{"role" => "user", "content" => Ipse.Session.Draft.notice()}
    tail = [notice, %{"role" => "user", "content" => "new request"}]

    draft = %{
      status: :cancelled,
      notice: true,
      prefix_count: length(prefix),
      prefix_sha256: Ipse.JSON.digest(prefix),
      end_count: length(prefix) + length(segment),
      segment_sha256: Ipse.JSON.digest(segment)
    }

    assert DraftNative.policy(%{provider: :openai}) === :openai

    assert {:ok, projected} =
             Ipse.Session.Draft.project(draft, prefix ++ segment ++ tail, MapSet.new(), :openai)

    assert projected === prefix ++ tail

    wire =
      Ipse.Provider.OpenAI.request_body(%{provider: :openai, model: "fixture"}, projected, [])

    assert wire["store"] === false and not Map.has_key?(wire, "previous_response_id")
    refute Jason.encode!(wire) =~ "private draft canary"
    refute Jason.encode!(wire) =~ "opaque draft canary"
    refute Jason.encode!(wire) =~ "draft answer canary"

    # Identifiers shared across the withheld and retained intervals are ambiguous.
    {prior, repeated} = {assistant(), assistant()}
    overlap = [prior] ++ segment ++ tail

    overlapping_draft = %{
      draft
      | prefix_count: 1,
        prefix_sha256: Ipse.JSON.digest([prior]),
        end_count: 3
    }

    assert repeated === List.last(segment)

    assert {:error, :draft_projection_unsafe} =
             Ipse.Session.Draft.project(overlapping_draft, overlap, MapSet.new(), :openai)

    foreign = put_in(assistant(), ["provider_data", "provider"], "anthropic")
    foreign_segment = [%{"role" => "user", "content" => "private draft canary"}, foreign]
    foreign_draft = %{draft | segment_sha256: Ipse.JSON.digest(foreign_segment)}

    assert {:error, :draft_projection_unsafe} =
             Ipse.Session.Draft.project(
               foreign_draft,
               prefix ++ foreign_segment ++ tail,
               MapSet.new(),
               :openai
             )

    xai = put_in(assistant(), ["provider_data", "provider"], "xai")
    xai_segment = [%{"role" => "user", "content" => "draft"}, xai]
    xai_draft = %{draft | segment_sha256: Ipse.JSON.digest(xai_segment)}

    assert {:error, :draft_projection_unsafe} =
             Ipse.Session.Draft.project(
               xai_draft,
               prefix ++ xai_segment ++ tail,
               MapSet.new(),
               :openai
             )

    distinct_prior =
      assistant()
      |> put_in(["provider_data", "output", Access.at(0), "id"], "rs_foreign_prior")
      |> put_in(["provider_data", "output", Access.at(1), "id"], "msg_foreign_prior")

    assert DraftNative.isolated_responses?([distinct_prior], segment, tail)
    foreign_prefix = [put_in(distinct_prior, ["provider_data", "provider"], "xai")]
    mixed_history_draft = %{draft | prefix_sha256: Ipse.JSON.digest(foreign_prefix)}

    assert {:error, :draft_projection_unsafe} =
             Ipse.Session.Draft.project(
               mixed_history_draft,
               foreign_prefix ++ segment ++ tail,
               MapSet.new(),
               :openai
             )

    call = %{
      "id" => "draft-call",
      "type" => "function",
      "function" => %{"name" => "read", "arguments" => "{}"}
    }

    call_message = %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [call],
      "provider_data" => %{
        "provider" => "openai",
        "output" => [
          %{
            "type" => "function_call",
            "id" => "draft-item",
            "call_id" => "draft-call",
            "name" => "read",
            "arguments" => "{}"
          }
        ]
      }
    }

    tool_segment = [%{"role" => "user", "content" => "draft"}, call_message]
    tool_draft = %{draft | segment_sha256: Ipse.JSON.digest(tool_segment)}
    dangling_result = %{"role" => "tool", "tool_call_id" => "draft-call", "content" => "result"}

    assert {:error, :draft_projection_unsafe} =
             Ipse.Session.Draft.project(
               tool_draft,
               prefix ++ tool_segment ++ tail ++ [dangling_result],
               MapSet.new(),
               :openai
             )

    paired_segment = tool_segment ++ [dangling_result]

    paired_draft = %{
      draft
      | end_count: length(prefix) + length(paired_segment),
        segment_sha256: Ipse.JSON.digest(paired_segment)
    }

    assert {:ok, projected} =
             Ipse.Session.Draft.project(
               paired_draft,
               prefix ++ paired_segment ++ tail,
               MapSet.new(),
               :openai
             )

    assert projected === prefix ++ tail
    refute Jason.encode!(projected) =~ "draft-call"
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

  test "Ollama draft calls require exact native association and a closed interval" do
    native = %{"function" => %{"name" => "read", "arguments" => %{"path" => "private.txt"}}}
    id = "ollama_0123456789abcdef_0"

    call = %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => "read", "arguments" => Jason.encode!(%{"path" => "private.txt"})}
    }

    assistant = %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [call],
      "provider_data" => %{
        "provider" => "ollama",
        "message" => %{
          "role" => "assistant",
          "content" => "",
          "thinking" => "private thinking",
          "tool_calls" => [native]
        }
      }
    }

    result = %{"role" => "tool", "tool_call_id" => id, "content" => "private result"}
    assert DraftNative.ollama_draft_with_tools?(assistant)
    assert DraftNative.isolated_ollama?([], [assistant, result], [])
    refute DraftNative.isolated_ollama?([], [assistant], [result])
    refute DraftNative.isolated_ollama?([assistant, result], [assistant, result], [])
    refute DraftNative.isolated_ollama?([], [assistant, result, assistant, result], [])

    hidden_native = %{
      "role" => "assistant",
      "content" => "",
      "provider_data" => %{
        "provider" => "ollama",
        "message" => %{"tool_calls" => [%{"id" => id}]}
      }
    }

    refute DraftNative.isolated_ollama?([hidden_native], [assistant, result], [])

    refute DraftNative.ollama_draft_with_tools?(
             put_in(assistant, ["tool_calls", Access.at(0), "id"], "forged")
           )

    refute DraftNative.ollama_draft_with_tools?(
             put_in(assistant, ["tool_calls", Access.at(0), "function", "arguments"], "{}")
           )

    refute DraftNative.ollama_draft_with_tools?(
             put_in(
               assistant,
               ["provider_data", "message", "tool_calls", Access.at(0), "extra"],
               true
             )
           )

    assert DraftNative.ollama_draft_with_tools?(
             assistant
             |> put_in(
               ["provider_data", "message", "tool_calls", Access.at(0), "id"],
               "native-id"
             )
             |> put_in(["tool_calls", Access.at(0), "id"], "native-id")
           )
  end
end
