defmodule Ipse.Lifecycle.Child do
  @moduledoc "Parent-owned child result receipts; process exit alone proves neither a result nor cleanup."
  alias Ipse.Lifecycle.Source
  @error {:error, :invalid_child_lifecycle}
  @reasons ~w(completed admission_refused worker_failed child_failed child_down timeout bounds result_unavailable cleanup_unconfirmed cancelled owner_down)

  def finished(resource, status, reason, cleanup) do
    %{
      "type" => "delegation_finished",
      "version" => 1,
      "child_id" => resource.id,
      "turn_id" => resource.turn,
      "request_id" => resource.request,
      "started_source" => resource.source,
      "status" => status,
      "reason" => reason,
      "cleanup_confirmed" => cleanup,
      "duration_ms" => max(System.monotonic_time(:millisecond) - resource.started, 0)
    }
  end

  def valid_record?(e) do
    Enum.sort(Map.keys(e)) ==
      ~w(child_id cleanup_confirmed duration_ms reason request_id started_source status turn_id type version) and
      e["type"] == "delegation_finished" and e["version"] === 1 and
      Enum.all?(~w(child_id turn_id request_id), &id?(e[&1])) and
      Source.valid?(e["started_source"]) and e["status"] in ~w(result_recorded unknown) and
      e["reason"] in @reasons and is_boolean(e["cleanup_confirmed"]) and
      (e["status"] != "result_recorded" or
         (e["reason"] == "completed" and e["cleanup_confirmed"])) and
      (e["reason"] != "completed" or e["status"] == "result_recorded") and
      is_integer(e["duration_ms"]) and e["duration_ms"] in 0..9_007_199_254_740_991
  rescue
    _ -> false
  end

  def restore(events) do
    Enum.reduce_while(events, {:ok, %{request: nil, children: %{}}}, fn e, {:ok, s} ->
      case {e["type"], e["kind"]} do
        {"request_admitted", "model"} ->
          {:cont, {:ok, %{s | request: e}}}

        {"delegation_started", _} ->
          if id?(e["child_id"]) and not Map.has_key?(s.children, e["child_id"]) do
            child = %{record: e, request: s.request, ended: false}
            {:cont, {:ok, put_in(s, [:children, e["child_id"]], child)}}
          else
            {:halt, @error}
          end

        {"delegation_finished", _} ->
          with true <- valid_record?(e),
               %{ended: false, request: request} = child <- s.children[e["child_id"]],
               true <-
                 request["request_id"] == e["request_id"] and request["turn_id"] == e["turn_id"] and
                   request["session_id"] == e["started_source"]["session_id"],
               true <- Source.matches?(e["started_source"], child.record) do
            {:cont, {:ok, put_in(s, [:children, e["child_id"]], %{child | ended: true})}}
          else
            _ -> {:halt, @error}
          end

        _ ->
          {:cont, {:ok, s}}
      end
    end)
  rescue
    _ -> @error
  end

  def validate_sources(directory, session, events) do
    with {:ok, _} <- restore(events) do
      Enum.reduce_while(events, :ok, fn e, :ok ->
        if e["type"] == "delegation_finished" do
          source = e["started_source"]

          case Ipse.Journal.source_page(directory, session, source["byte_offset"], 1) do
            {:ok, %{records: [%{source: ^source}]}} -> {:cont, :ok}
            _ -> {:halt, @error}
          end
        else
          {:cont, :ok}
        end
      end)
    end
  rescue
    _ -> @error
  end

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
