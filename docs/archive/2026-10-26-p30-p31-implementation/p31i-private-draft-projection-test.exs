defmodule Ipse.Session.DraftProjectionTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.Draft
  alias Ipse.JSON

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

  test "interrupted consumption still authenticates the withdrawn segment" do
    {cancelled, messages} = projection([%{"role" => "user", "content" => "secret"}])
    incomplete = cancelled |> Map.put(:status, :consumed) |> Map.put(:accepted_message, false)
    segment_only = Enum.take(messages, incomplete.end_count)
    assert {:ok, ^segment_only} = Draft.project(incomplete, segment_only)

    assert {:error, :draft_projection_unsafe} =
             Draft.project(
               %{incomplete | segment_sha256: String.duplicate("0", 64)},
               segment_only
             )
  end
end
