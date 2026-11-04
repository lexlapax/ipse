defmodule Ipse.Development.RetainedReadAssertions do
  @moduledoc "Full-body note_parts_v1 assertions shared with the qualified 33-source contract."
  import ExUnit.Assertions
  @host_read_budget 512

  def publication_revisions!(journals) do
    captures =
      journals
      |> List.flatten()
      |> Enum.filter(fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "collection.managed" and
          get_in(event, ["outcome", "status"]) == "ok"
      end)
      |> Enum.reduce(%{}, fn event, acc ->
        [change] = get_in(event, ["request", "request", "changes"])
        assert change["expected_revision"] == 0
        revision = get_in(event, ["outcome", "value", "receipt", "generation"])
        assert is_integer(revision) and revision > 0
        refute Map.has_key?(acc, change["key"])
        Map.put(acc, change["key"], revision)
      end)

    journals
    |> Enum.flat_map(fn events ->
      intents =
        Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
        |> Enum.reduce(%{}, fn event, acc ->
          refute Map.has_key?(acc, event["operation_id"])
          Map.put(acc, event["operation_id"], event)
        end)

      for event <- events,
          event["type"] == "managed_lifecycle_result" and event["status"] == "settled" do
        facts = Map.fetch!(intents, event["operation_id"])["facts"]

        assert facts["kind"] == "managed_literal_retention" and
                 facts["policy"] == %{"kind" => "pin"}

        target = facts["target"]
        revision = get_in(event, ["result", "receipt", "publication", "receipt", "generation"])

        assert is_integer(revision) and is_integer(target["revision"]) and
                 revision > target["revision"]

        {revision, target}
      end
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(captures, fn {revision, target}, acc ->
      assert Map.has_key?(acc, target["key"])
      assert target["revision"] == Map.fetch!(acc, target["key"])
      Map.put(acc, target["key"], revision)
    end)
  end

  def verify!(request, events, expected) do
    prefix =
      Ipse.Extension.render_context(%{"knowledge" => []}) |> String.replace_suffix("[]", "")

    items =
      Enum.flat_map(request["messages"], fn
        %{"role" => "user"} = message ->
          case Ipse.Session.Reference.selected_publishers(message) do
            {:ok, %{"extensions" => text}} when is_binary(text) ->
              if String.starts_with?(text, prefix) do
                {:ok, items} = Jason.decode(String.replace_prefix(text, prefix, ""))
                assert is_list(items)
                items
              else
                []
              end

            _ ->
              []
          end

        _ ->
          []
      end)

    parts =
      items
      |> Enum.filter(fn item ->
        get_in(item, ["provenance", "instance"]) == "knowledge" and
          is_binary(item["id"]) and String.starts_with?(item["id"], "note_text_")
      end)
      |> Enum.flat_map(fn item ->
        {:ok, group} = Jason.decode(item["text"])
        assert group["format"] == "note_parts_v1"
        assert group["fields"] == ~w(key revision read_operation_id offset_bytes total_bytes text)
        assert Enum.all?(group["records"], &(is_list(&1) and length(&1) == 6))
        Enum.map(group["records"], &Map.new(Enum.zip(group["fields"], &1)))
      end)

    summary = verify_parts!(parts, events, expected)

    [coverage] =
      Enum.filter(
        items,
        &(&1["id"] == "note_coverage" and get_in(&1, ["provenance", "instance"]) == "knowledge")
      )

    coverage = Jason.decode!(coverage["text"])
    assert coverage["coverage"] == "partial"
    assert coverage["included"] == summary["selected"]
    assert coverage["unavailable"] == 0

    Map.merge(summary, %{
      "coverage" => coverage["coverage"],
      "coverage_included" => coverage["included"],
      "coverage_unavailable" => coverage["unavailable"],
      "allocation_bytes" => coverage["allocation_bytes"]
    })
  end

  def verify_parts!(parts, events, expected) do
    grouped = Enum.group_by(parts, & &1["key"])
    assert map_size(grouped) in 1..@host_read_budget
    selected = Map.keys(grouped)
    assert Enum.all?(selected, &Map.has_key?(expected, &1))

    reads =
      Enum.filter(events, fn event ->
        event["type"] == "extension_action_result" and
          get_in(event, ["request", "op"]) == "collection.call" and
          get_in(event, ["request", "request", "op"]) == "get" and
          get_in(event, ["outcome", "status"]) == "ok"
      end)

    for {key, selected_parts} <- grouped do
      original = expected[key]
      deadline = get_in(original, ["metadata", "valid_until_ms"])
      assert is_nil(deadline) or System.system_time(:millisecond) < deadline

      {text, count} =
        selected_parts
        |> Enum.sort_by(& &1["offset_bytes"])
        |> Enum.reduce({"", 0}, fn part, {text, offset} ->
          assert part["offset_bytes"] == offset
          assert part["total_bytes"] == byte_size(original["value"]["text"])
          assert is_binary(part["text"]) and String.valid?(part["text"])
          assert is_integer(part["revision"]) and part["revision"] > 0
          assert part["revision"] === original["revision"]
          assert is_binary(part["read_operation_id"])

          assert [committed] =
                   Enum.filter(reads, fn event ->
                     event["operation_id"] == part["read_operation_id"] and
                       get_in(event, ["request", "request", "key"]) == key
                   end)

          record = get_in(committed, ["outcome", "value", "record"])
          assert record["key"] == key and record["revision"] == part["revision"]
          assert record["sha256"] == original["record_sha256"]
          assert record["value"] === original["value"]
          {text <> part["text"], offset + byte_size(part["text"])}
        end)

      assert text == original["value"]["text"] and count == byte_size(text)
    end

    %{
      "selected" => map_size(grouped),
      "parts" => length(parts),
      "full_selected_bodies_verified" => true,
      "selected_key_sha256" => Ipse.JSON.digest([Enum.sort(selected)]),
      "selected_body_bytes" =>
        Enum.sum(Enum.map(selected, &byte_size(expected[&1]["value"]["text"])))
    }
  end
end
