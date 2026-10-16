defmodule Ipse.ToolResultCompactionTest do
  use ExUnit.Case, async: true
  alias Ipse.Compaction

  defp system, do: %{"role" => "system", "content" => "Host rules"}

  defp exchange(id, status \\ "result_recorded") do
    [
      %{
        "role" => "assistant",
        "content" => "",
        "provider_data" => %{
          "provider" => "openai",
          "output" => [%{"type" => "reasoning", "encrypted_content" => "opaque-#{id}"}]
        },
        "tool_calls" => [
          %{
            "id" => id,
            "function" => %{"name" => "read", "arguments" => ~s({"path":"#{id}.txt"})}
          }
        ]
      },
      %{
        "role" => "tool",
        "tool_call_id" => id,
        "content" =>
          "Beginning #{id}\n" <> String.duplicate("synthetic detail ", 500) <> "\nEnd #{id}",
        "ipse_tool_outcome" => %{"status" => status, "approval" => "not_required"}
      }
    ]
  end

  defp history do
    [%{"role" => "user", "content" => "Assess documents; preserve existing work."}] ++
      Enum.flat_map(
        1..6,
        &exchange("call-#{&1}", if(&1 == 3, do: "unknown", else: "result_recorded"))
      )
  end

  defp config, do: %{context_bytes: 100_000, compact_threshold_bytes: 32_000}

  test "one long turn retains users, native payloads, calls, outcomes and recent batches" do
    original = history()
    assert {:tool_results, projected, event} = Compaction.prepare(original, config(), system())
    assert event["after_bytes"] < event["before_bytes"]
    assert event["after_bytes"] <= config().compact_threshold_bytes
    assert Enum.at(projected, 0) == Enum.at(original, 0)
    assert Enum.take(projected, -4) == Enum.take(original, -4)
    assert Enum.at(projected, 6) == Enum.at(original, 6)

    for {before, after_message} <- Enum.zip(original, projected) do
      if after_message["ipse_result_excerpt"] do
        assert Map.drop(after_message, ["content", "ipse_result_excerpt"]) ==
                 Map.drop(before, ["content"])

        assert after_message["content"] =~ "incomplete excerpt"
        assert after_message["content"] =~ "Beginning #{before["tool_call_id"]}"
        assert after_message["content"] =~ "End #{before["tool_call_id"]}"
        assert after_message["ipse_result_excerpt"]["byte_count"] == byte_size(before["content"])
      else
        assert after_message == before
      end
    end

    assert {:ok, ^projected} =
             Compaction.restore_tool_results(original, Jason.decode!(Jason.encode!(event)))

    assert :skip = Compaction.prepare(projected, config(), system())
  end

  test "never splits the two newest parallel tool batches" do
    original = history()
    last = Enum.at(original, -2)
    extra_call = %{"id" => "extra", "function" => %{"name" => "read", "arguments" => "{}"}}
    last = Map.update!(last, "tool_calls", &(&1 ++ [extra_call]))
    extra_result = exchange("extra") |> List.last()
    messages = Enum.drop(original, -2) ++ [last, List.last(original), extra_result]
    cfg = Map.put(config(), :compact_threshold_bytes, 41_000)
    assert {:tool_results, projected, _} = Compaction.prepare(messages, cfg, system())
    assert Enum.take(projected, -5) == Enum.take(messages, -5)
  end

  test "rejects pending calls, corrupt projections, and oversized retained state" do
    original = history()
    assert {:error, reason} = Compaction.prepare(Enum.drop(original, -1), config(), system())
    assert reason =~ "unresolved tool call"
    assert {:tool_results, _, event} = Compaction.prepare(original, config(), system())

    for corrupt <- [
          Map.put(event, "version", 2),
          Map.put(event, "indices", [2]),
          Map.put(event, "prefix_sha256", "bad"),
          Map.put(event, "projection_sha256", "bad"),
          Map.put(event, "covered_messages", 0)
        ] do
      assert {:error, :invalid_tool_result_checkpoint} =
               Compaction.restore_tool_results(original, corrupt)
    end

    large_user =
      List.replace_at(original, 0, %{
        "role" => "user",
        "content" => String.duplicate("pinned user goal ", 3000)
      })

    assert {:error, reason} = Compaction.prepare(large_user, config(), system())
    assert reason =~ "retained user requests"

    assert {:error, _} =
             Compaction.prepare(original, %{context_bytes: 10_000, compact: false}, system())
  end

  test "later reductions and summary checkpoints retain original result provenance" do
    original = history()
    assert {:tool_results, projected, event} = Compaction.prepare(original, config(), system())
    extended = projected ++ exchange("later-1") ++ exchange("later-2")

    assert {:tool_results, second, second_event} =
             Compaction.prepare(
               extended,
               Map.put(config(), :compact_threshold_bytes, 38_000),
               system()
             )

    assert {:ok, ^projected} = Compaction.restore_tool_results(original, event)
    assert {:ok, ^second} = Compaction.restore_tool_results(extended, second_event)

    turns =
      second ++
        [
          %{"role" => "user", "content" => "Second turn"},
          %{"role" => "assistant", "content" => "Noted"},
          %{"role" => "user", "content" => "Third turn"}
        ]

    assert {:ok, plan} =
             Compaction.prepare(
               turns,
               %{context_bytes: 100_000, compact_threshold_bytes: 10_000},
               system()
             )

    original_result = Enum.at(original, 2)["content"]
    first = hd(plan.actions)["outcome"]
    assert first["byte_count"] == byte_size(original_result)
    assert first["sha256"] == Base.encode16(:crypto.hash(:sha256, original_result), case: :lower)
    assert first["excerpt"] == String.slice(original_result, 0, 256)
  end
end
