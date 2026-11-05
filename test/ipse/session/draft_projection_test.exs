defmodule Ipse.Session.DraftProjectionTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.Draft
  alias Ipse.JSON

  test "draft replay binds the instruction version and retains legacy prompts" do
    session = String.duplicate("1", 32)
    turn = String.duplicate("2", 32)
    id = String.duplicate("3", 32)
    original = "/enhance Build a report"
    current = Draft.effective(original)
    legacy = Draft.effective(original, 1)

    assert current =~ "Check available relevant context before asking questions"
    assert current =~ "Ask only about material"

    assert legacy ==
             "Draft a clearer version of the request below. Do not carry out the request. Return only the proposed request.\n\nBuild a report"

    for {version, effective} <- [{1, legacy}, {2, current}] do
      started =
        Draft.started(session, turn, id, original, effective, [], nil, nil)
        |> Map.put("version", version)

      input = %{
        "type" => "input_received",
        "session_id" => session,
        "turn_id" => turn,
        "text" => original,
        "text_sha256" => JSON.sha256(original),
        "effective_sha256" => JSON.sha256(effective),
        "source_id" => "source"
      }

      assert {:ok, draft} = Draft.advance(nil, started, session)
      assert {:ok, _} = Draft.advance(draft, input, session)

      other = if version == 1, do: 2, else: 1
      assert {:ok, mismatched} = Draft.advance(nil, Map.put(started, "version", other), session)
      assert {:error, :invalid_saved_draft} = Draft.advance(mismatched, input, session)
    end
  end

  defp projection(segment, prefix \\ []) do
    notice = %{"role" => "user", "content" => Draft.notice()}

    draft = %{
      status: :cancelled,
      notice: true,
      prefix_count: length(prefix),
      prefix_sha256: JSON.digest(prefix),
      end_count: length(prefix) + length(segment),
      segment_sha256: JSON.digest(segment)
    }

    {draft, prefix ++ segment ++ [notice, %{"role" => "user", "content" => "new task"}]}
  end

  test "complete draft interval is withheld, but the neutral notice and new intent remain" do
    prefix = [
      %{"role" => "user", "content" => "old"},
      %{"role" => "assistant", "content" => "old reply"}
    ]

    segment = [
      %{"role" => "user", "content" => "secret draft"},
      %{"role" => "assistant", "content" => "draft answer"}
    ]

    {draft, messages} = projection(segment, prefix)
    assert {:ok, [_, _, notice, new]} = Draft.project(draft, messages)
    assert notice["content"] == Draft.notice() and new["content"] == "new task"
  end

  test "changed bound prefix, draft, notice and invalid range refuse" do
    {draft, messages} = projection([%{"role" => "user", "content" => "draft"}])

    assert {:error, :draft_projection_unsafe} =
             Draft.project(
               draft,
               List.replace_at(messages, 0, %{"role" => "user", "content" => "changed"})
             )

    assert {:error, :draft_projection_unsafe} =
             Draft.project(
               draft,
               List.replace_at(messages, 1, %{"role" => "user", "content" => "forged"})
             )

    assert {:error, :draft_projection_unsafe} = Draft.project(%{draft | end_count: 99}, messages)
  end

  test "opaque continuation, checkpoint and reference inside the removed interval refuse" do
    for marker <- ["provider_data", "ipse_checkpoint", "ipse_reference"] do
      segment = [%{"role" => "assistant", "content" => "sensitive", marker => %{}}]
      {draft, messages} = projection(segment)
      assert {:error, :draft_projection_unsafe} = Draft.project(draft, messages)
    end
  end

  test "a self-hashed reference is not evidence of a host occurrence" do
    id = String.duplicate("a", 32)
    content = Ipse.Session.Reference.content(%{"runtime" => %{}})

    event = %{
      "version" => 1,
      "session_id" => id,
      "turn_id" => id,
      "epoch" => 1,
      "source_generation" => 1,
      "policy_generation" => 0,
      "content" => content,
      "content_sha256" => JSON.sha256(content)
    }

    reference = Ipse.Session.Reference.message(event)
    assert Ipse.Session.Reference.reference?(reference)
    {draft, messages} = projection([reference])
    assert {:error, :draft_projection_unsafe} = Draft.project(draft, messages)
    assert {:ok, _} = Draft.project(draft, messages, MapSet.new([JSON.digest([reference])]))
  end

  test "interrupted consumption still authenticates the withdrawn segment" do
    {cancelled, messages} = projection([%{"role" => "user", "content" => "secret"}])
    incomplete = cancelled |> Map.put(:status, :consumed) |> Map.put(:accepted_message, false)
    segment_only = Enum.take(messages, incomplete.end_count)
    assert {:ok, ^segment_only} = Draft.project(incomplete, segment_only)

    assert {:error, :draft_projection_unsafe} =
             Draft.project(
               incomplete,
               segment_only ++ [%{"role" => "user", "content" => "unexpected"}]
             )

    assert {:error, :draft_projection_unsafe} =
             Draft.project(
               %{incomplete | segment_sha256: String.duplicate("0", 64)},
               segment_only
             )
  end

  test "Ollama no-tool drafts withdraw thinking and reject unsafe native continuations" do
    native = %{
      "role" => "assistant",
      "content" => "private proposal",
      "provider_data" => %{
        "provider" => "ollama",
        "reported_model" => "fixture",
        "message" => %{
          "role" => "assistant",
          "content" => "private proposal",
          "thinking" => "",
          "tool_calls" => []
        }
      }
    }

    segment = [%{"role" => "user", "content" => "private draft"}, native]
    {cancelled, messages} = projection(segment)
    assert {:ok, projected} = Draft.project(cancelled, messages, MapSet.new(), :ollama)
    refute Jason.encode!(projected) =~ "private proposal"
    refute Jason.encode!(projected) =~ "private draft"

    accepted = %{cancelled | status: :consumed} |> Map.put(:accepted_message, true)
    assert {:ok, ^projected} = Draft.project(accepted, messages, MapSet.new(), :ollama)

    with_thinking =
      put_in(native, ["provider_data", "message", "thinking"], "draft-only thinking canary")

    refute Ipse.Session.DraftNative.plain_text_only?(with_thinking)
    assert Ipse.Session.DraftNative.ollama_draft_without_tools?(with_thinking)

    {thinking_draft, thinking_history} =
      projection([%{"role" => "user", "content" => "draft"}, with_thinking])

    assert {:ok, thinking_projected} =
             Draft.project(thinking_draft, thinking_history, MapSet.new(), :ollama)

    refute Jason.encode!(thinking_projected) =~ "draft-only thinking canary"
    accepted_thinking = %{thinking_draft | status: :consumed} |> Map.put(:accepted_message, true)

    assert {:ok, ^thinking_projected} =
             Draft.project(accepted_thinking, thinking_history, MapSet.new(), :ollama)

    for thinking <- [nil, %{}, <<255>>, :binary.copy("x", 8_388_609)] do
      malformed = put_in(native, ["provider_data", "message", "thinking"], thinking)
      refute Ipse.Session.DraftNative.ollama_draft_without_tools?(malformed)
    end

    unsafe = [
      put_in(native, ["provider_data", "message", "content"], "different native text"),
      put_in(native, ["provider_data", "message", "role"], "user"),
      put_in(native, ["provider_data", "provider"], "other"),
      put_in(native, ["provider_data", "message", "tool_calls"], nil),
      put_in(native, ["provider_data", "message", "tool_calls"], [%{"function" => %{}}]),
      Map.put(native, "tool_calls", [%{"function" => %{}}]),
      put_in(native, ["provider_data", "message", "unknown"], "opaque"),
      put_in(native, ["provider_data", "unexpected"], "opaque")
    ]

    for message <- unsafe do
      {draft, history} = projection([%{"role" => "user", "content" => "draft"}, message])

      assert {:error, :draft_projection_unsafe} =
               Draft.project(draft, history, MapSet.new(), :ollama)
    end

    {draft, history} = projection(segment)
    assert {:error, :draft_projection_unsafe} = Draft.project(draft, history)

    earlier = put_in(native, ["provider_data", "message", "thinking"], "earlier thinking")
    later = put_in(native, ["provider_data", "message", "thinking"], "later thinking")
    call = %{"id" => "outside-call", "function" => %{"name" => "read", "arguments" => "{}"}}
    call_message = %{"role" => "assistant", "content" => "", "tool_calls" => [call]}

    result = %{
      "role" => "tool",
      "tool_call_id" => "outside-call",
      "content" => "unknown result",
      "ipse_tool_outcome" => %{"status" => "unknown"}
    }

    prefix = [earlier, call_message, result]
    {draft, history} = projection(segment, prefix)
    history = history ++ [later, call_message, result]
    assert {:ok, visible} = Draft.project(draft, history, MapSet.new(), :ollama)
    assert Enum.take(visible, 3) == prefix
    assert Enum.take(visible, -3) == [later, call_message, result]

    assert {:error, :draft_projection_unsafe} =
             Draft.project(draft, history ++ [call_message], MapSet.new(), :ollama)
  end

  test "Anthropic text-only draft withdraws exact interval while retaining native outside history" do
    native = %{
      "role" => "assistant",
      "content" => "private proposal café 雪",
      "provider_data" => %{
        "provider" => "anthropic",
        "reported_model" => "fixture-model",
        "content" => [%{"type" => "text", "text" => "private proposal café 雪"}]
      }
    }

    prior = %{
      "role" => "assistant",
      "content" => "prior",
      "provider_data" => %{
        "provider" => "anthropic",
        "content" => [
          %{"type" => "thinking", "thinking" => "prior hidden", "signature" => "prior signature"},
          %{"type" => "text", "text" => "prior"}
        ]
      }
    }

    later =
      put_in(prior, ["content"], "later")
      |> put_in(["provider_data", "content"], [%{"type" => "text", "text" => "later"}])

    assert Ipse.Session.DraftNative.policy(%{provider: :anthropic}) == :anthropic

    {draft, history} =
      projection([%{"role" => "user", "content" => "private input"}, native], [prior])

    history = history ++ [later]

    assert {:ok, [^prior, notice, new, ^later]} =
             Draft.project(draft, history, MapSet.new(), :anthropic)

    assert notice["content"] == Draft.notice()
    assert new["content"] == "new task"
    assert {:error, :draft_projection_unsafe} = Draft.project(draft, history)
  end

  test "Anthropic opaque, changed and tool-bearing drafts refuse instead of stripping fields" do
    native = %{
      "role" => "assistant",
      "content" => "private",
      "provider_data" => %{
        "provider" => "anthropic",
        "content" => [%{"type" => "text", "text" => "private"}]
      }
    }

    unsafe = [
      put_in(native, ["provider_data", "content"], [
        %{"type" => "thinking", "thinking" => "hidden", "signature" => "signed"},
        %{"type" => "text", "text" => "private"}
      ]),
      put_in(native, ["provider_data", "content"], [
        %{"type" => "redacted_thinking", "data" => "opaque"}
      ]),
      put_in(native, ["provider_data", "content"], [%{"type" => "text", "text" => "different"}]),
      put_in(native, ["provider_data", "content"], [
        %{"type" => "text", "text" => "private", "citations" => []}
      ]),
      put_in(native, ["provider_data", "content"], [
        %{"type" => "tool_use", "id" => "call", "name" => "read", "input" => %{}}
      ]),
      put_in(native, ["provider_data", "provider"], "gemini"),
      put_in(native, ["provider_data", "unexpected"], "opaque"),
      put_in(native, ["provider_data", "reported_model"], %{bad: true}),
      Map.put(native, "tool_calls", [%{"id" => "call", "function" => %{}}])
    ]

    for message <- unsafe do
      {draft, history} = projection([%{"role" => "user", "content" => "private"}, message])

      assert {:error, :draft_projection_unsafe} =
               Draft.project(draft, history, MapSet.new(), :anthropic)
    end
  end

  test "Anthropic validator rejects invalid UTF-8 before JSON history encoding" do
    refute Ipse.Session.DraftNative.anthropic_draft_without_tools?(%{
             "role" => "assistant",
             "content" => <<255>>,
             "provider_data" => %{
               "provider" => "anthropic",
               "content" => [%{"type" => "text", "text" => <<255>>}]
             }
           })
  end
end
