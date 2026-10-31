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
end
