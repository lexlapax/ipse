defmodule Ipse.Session.ManagedSourceProvenanceTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.{SourceIndex, SourceWindow}

  @journal "docs/archive/2026-10-26-p30-p31-implementation/remember-terminal-headless-controls/journals/headless-direct.jsonl"

  defp window_before_read do
    {:ok, data} = File.read(@journal)
    events = data |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    id = get_in(hd(events), ["metadata", "source_origin", "session_id"])

    at =
      Enum.find_index(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "source.read")
      )

    event = Enum.at(events, at)
    {:ok, window} = SourceWindow.restore(Enum.take(events, at), id)
    {window, event}
  end

  test "replayed exact source read returns owner-indexed provenance, not caller fields" do
    {window, event} = window_before_read()
    request = Map.delete(event["request"], "op")
    value = event["outcome"]["value"]

    assert {:ok, [selected]} =
             SourceIndex.saved_read_provenances(
               window.index,
               "source.read",
               request,
               value,
               window.historical_window
             )

    assert selected["origin"] == "typed_host_outcome" and selected["kind"] == "tool.outcome"
    assert selected["provenance"] === value["provenance"]

    assert {:error, _} =
             SourceIndex.saved_read_provenances(
               window.index,
               "source.read",
               request,
               put_in(value, ["provenance", "request_id"], "forged"),
               window.historical_window
             )

    assert {:error, _} =
             SourceIndex.saved_read_provenances(
               window.index,
               "source.read",
               request,
               Map.put(value, "version_id", String.duplicate("a", 32)),
               window.historical_window
             )
  end

  test "list relation covers every exact selected occurrence and rejects altered rows" do
    {window, _} = window_before_read()
    request = %{"limit" => 32}
    assert {:ok, value} = SourceIndex.list(window.index, request)

    assert {:ok, selected} =
             SourceIndex.saved_read_provenances(
               window.index,
               "source.list",
               request,
               value,
               window.index.window_id
             )

    assert Enum.map(selected, & &1["occurrence_id"]) ==
             Enum.map(value["sources"], & &1["occurrence_id"])

    assert Enum.any?(selected, &(&1["origin"] == "typed_host_outcome"))

    tampered =
      update_in(value, ["sources", Access.at(0), "origin"], fn _ ->
        "native_operator_assertion"
      end)

    assert {:error, _} =
             SourceIndex.saved_read_provenances(
               window.index,
               "source.list",
               request,
               tampered,
               window.index.window_id
             )
  end
end
