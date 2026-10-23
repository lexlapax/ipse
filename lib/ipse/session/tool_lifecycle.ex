defmodule Ipse.Session.ToolLifecycle do
  @moduledoc "Opt-in source-bound views of admitted model-selected tools; observation confers no approval."
  alias Ipse.Journal
  @types ~w(lifecycle_tool_intent lifecycle_tool_outcome lifecycle_tool_recording_stopped)
  @limit 10_000
  @input ~w(type version session_id epoch_id tool_id turn_id request_id proposal_source call_index intent_source approval input input_bytes input_sha256)
  @output ~w(type version session_id epoch_id tool_id turn_id request_id tool_source result_source status approval duration_ms result result_bytes result_sha256)
  @error {:error, :invalid_tool_lifecycle}
  def types, do: @types
  def limit, do: @limit

  def enabled?(config),
    do:
      Enum.any?(
        Map.get(config, :extensions, []),
        &("lifecycle.tools" in &1.identity["capabilities"])
      )

  def open(config, events, session, runtime, directory, question) do
    if enabled?(config) do
      {:ok, saved} = restore(events, session)

      ctx = %{
        session: session,
        epoch: if(runtime, do: runtime.epoch),
        count: saved.count,
        recording: not saved.stopped,
        proposal: nil,
        active: nil
      }

      ctx =
        case question do
          %{kind: :extension, call: call, parent: parent} when call != nil ->
            active =
              Enum.find_value(saved.tools, fn {_, r} ->
                if not r.ended and r.call == call and
                     r.record["request_id"] == parent["parent_request_id"],
                   do: r
              end)

            if is_map(active) and ctx.recording do
              {:ok, source} =
                find_source(directory, session, active.record["intent_source"], active.record)

              %{ctx | active: %{record: active.record, source: source, started: nil}}
            else
              ctx
            end

          _ ->
            ctx
        end

      if ctx.recording and (runtime == nil or not runtime.active),
        do: stop(ctx, "epoch_unavailable"),
        else: {ctx, []}
    else
      {nil, []}
    end
  end

  def recording?(%{recording: true}), do: true
  def recording?(_), do: false
  def active?(%{recording: true, active: active}), do: active != nil
  def active?(_), do: false

  def snapshot(nil),
    do: %{"enabled" => false, "recording" => false, "recorded_facts" => 0, "active_tool" => false}

  def snapshot(ctx),
    do: %{
      "enabled" => true,
      "recording" => ctx.recording,
      "recorded_facts" => ctx.count,
      "active_tool" => active?(ctx)
    }

  def summary(events) do
    {:ok, saved} = restore(events)
    ended = Enum.count(saved.tools, fn {_, tool} -> tool.ended end)

    %{
      "admitted" => map_size(saved.tools),
      "recorded_outcomes" => ended,
      "incomplete" => map_size(saved.tools) - ended,
      "recording_stopped" => saved.stopped
    }
  end

  def proposal(nil, _, _, _), do: {nil, []}
  def proposal(%{recording: false} = ctx, _, _, _), do: {ctx, []}
  def proposal(ctx, nil, _, _), do: stop(ctx, "source_unavailable")

  def proposal(ctx, source, record, turn),
    do: {%{ctx | proposal: %{source: source, record: record, turn: turn}}, []}

  def start(nil, _, _, _, _), do: {nil, []}
  def start(%{recording: false} = ctx, _, _, _, _), do: {ctx, []}
  def start(ctx, nil, _, _, _), do: stop(ctx, "source_unavailable")

  def start(ctx, source, intent, call, remaining) do
    cond do
      ctx.count > @limit - 2 ->
        stop(ctx, "limit")

      ctx.proposal == nil or ctx.active != nil ->
        stop(ctx, "binding_unavailable")

      true ->
        calls = ctx.proposal.record["message"]["tool_calls"]
        index = length(calls) - remaining

        if Enum.at(calls, index) == call and index >= 0 do
          data = input(call)

          record = %{
            "type" => "lifecycle_tool_intent",
            "version" => 1,
            "session_id" => ctx.session,
            "epoch_id" => ctx.epoch,
            "tool_id" => Ipse.Usage.id(),
            "turn_id" => ctx.proposal.turn,
            "request_id" => ctx.proposal.record["request_id"],
            "proposal_source" => ctx.proposal.source,
            "call_index" => index,
            "intent_source" => source,
            "approval" => intent["approval"],
            "input" => bounded(data),
            "input_bytes" => bytes(data),
            "input_sha256" => digest(data)
          }

          true = valid?(record)
          {%{ctx | count: ctx.count + 1}, [record]}
        else
          stop(ctx, "binding_unavailable")
        end
    end
  end

  def bind(ctx, source, record),
    do: %{
      ctx
      | active: %{record: record, source: source, started: System.monotonic_time(:millisecond)}
    }

  def finish(nil, _, _), do: {nil, []}
  def finish(%{recording: false} = ctx, _, _), do: {ctx, []}
  def finish(%{active: nil} = ctx, _, _), do: {ctx, []}
  def finish(ctx, nil, _), do: stop(ctx, "source_unavailable")

  def finish(ctx, source, message_record) do
    start = ctx.active.record
    message = message_record["message"]
    data = %{"text" => message["content"]}

    record = %{
      "type" => "lifecycle_tool_outcome",
      "version" => 1,
      "session_id" => ctx.session,
      "epoch_id" => ctx.epoch,
      "tool_id" => start["tool_id"],
      "turn_id" => start["turn_id"],
      "request_id" => start["request_id"],
      "tool_source" => ctx.active.source,
      "result_source" => source,
      "status" => message["ipse_tool_outcome"]["status"],
      "approval" => message["ipse_tool_outcome"]["approval"],
      "duration_ms" =>
        if(ctx.active.started,
          do: max(System.monotonic_time(:millisecond) - ctx.active.started, 0)
        ),
      "result" => bounded(data),
      "result_bytes" => bytes(data),
      "result_sha256" => digest(data)
    }

    true = valid?(record)
    {%{ctx | active: nil, count: ctx.count + 1}, [record]}
  end

  defp stop(ctx, reason) do
    record = %{
      "type" => "lifecycle_tool_recording_stopped",
      "version" => 1,
      "session_id" => ctx.session,
      "epoch_id" => ctx.epoch,
      "reason" => reason
    }

    {%{ctx | recording: false, active: nil, proposal: nil, count: ctx.count + 1}, [record]}
  end

  def valid?(record) do
    valid_record?(record)
  rescue
    _ -> false
  end

  defp valid_record?(%{"type" => "lifecycle_tool_intent"} = e),
    do:
      keys?(e, @input) and common?(e) and
        id?(e["epoch_id"]) and id?(e["tool_id"]) and id?(e["turn_id"]) and id?(e["request_id"]) and
        refs?(e, ~w(proposal_source intent_source)) and
        e["proposal_source"]["byte_offset"] < e["intent_source"]["byte_offset"] and
        Ipse.JSON.safe_uint?(e["call_index"]) and
        e["approval"] in ~w(approved session_allow not_required) and
        view?(e, "input")

  defp valid_record?(%{"type" => "lifecycle_tool_outcome"} = e),
    do:
      keys?(e, @output) and common?(e) and
        id?(e["epoch_id"]) and id?(e["tool_id"]) and id?(e["turn_id"]) and id?(e["request_id"]) and
        refs?(e, ~w(tool_source result_source)) and
        e["tool_source"]["byte_offset"] < e["result_source"]["byte_offset"] and
        e["status"] in ~w(result_recorded error unknown) and
        e["approval"] in ~w(approved session_allow not_required) and
        (e["duration_ms"] == nil or Ipse.JSON.safe_uint?(e["duration_ms"])) and view?(e, "result")

  defp valid_record?(%{"type" => "lifecycle_tool_recording_stopped"} = e),
    do:
      keys?(e, ~w(type version session_id epoch_id reason)) and common?(e) and
        (e["epoch_id"] == nil or id?(e["epoch_id"])) and
        e["reason"] in ~w(limit source_unavailable epoch_unavailable binding_unavailable)

  defp valid_record?(_), do: false

  def private_data?("tool.input", data),
    do:
      keys?(data, ~w(name arguments_json)) and
        Enum.all?(Map.values(data), &(is_binary(&1) and String.valid?(&1))) and
        bytes(data) <= 8192

  def private_data?("tool.result", data),
    do:
      keys?(data, ~w(text)) and is_binary(data["text"]) and String.valid?(data["text"]) and
        bytes(data) <= 8192

  def private_data?(_, _), do: false

  def describe(e) do
    if valid?(e) do
      correlations =
        Map.take(e, ~w(epoch_id tool_id turn_id request_id))
        |> Map.reject(fn {_, v} -> v == nil end)

      case e["type"] do
        "lifecycle_tool_intent" ->
          {:ok, "tool.intent_committed", "tool.input", e["input"],
           %{"input_bytes" => e["input_bytes"], "approval" => e["approval"]},
           Map.put(correlations, "causing_event_id", e["intent_source"]["event_id"])}

        "lifecycle_tool_outcome" ->
          {:ok, "tool.outcome_recorded", "tool.result", e["result"],
           Map.take(e, ~w(status approval duration_ms))
           |> Map.reject(fn {_, v} -> v == nil end)
           |> Map.put("output_bytes", e["result_bytes"]),
           Map.put(correlations, "causing_event_id", e["tool_source"]["event_id"])}

        _ ->
          {:ok, "tool.recording_stopped", nil, nil, %{"reason" => e["reason"]}, correlations}
      end
    else
      @error
    end
  end

  def restore(events, session \\ nil) do
    initial = %{
      session: session,
      epoch: nil,
      request: nil,
      assistant: nil,
      started: nil,
      result: nil,
      position: 0,
      tools: %{},
      count: 0,
      stopped: false
    }

    Enum.reduce_while(events, {:ok, initial}, fn e, {:ok, s} ->
      case step(e, s) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, @error}
      end
    end)
  rescue
    _ -> @error
  end

  defp step(%{"type" => type} = e, s) when type in @types do
    with true <- not s.stopped and valid?(e) and s.session in [nil, e["session_id"]],
         {:ok, next} <- apply_record(e, s) do
      {:ok, %{next | count: s.count + 1, session: e["session_id"]}}
    else
      _ -> @error
    end
  end

  defp step(%{"type" => "lifecycle_epoch_started", "epoch_id" => epoch}, s),
    do: {:ok, %{s | epoch: epoch}}

  defp step(%{"type" => "request_admitted", "kind" => "model"} = e, s),
    do: {:ok, %{s | request: e}}

  defp step(%{"type" => "message", "message" => %{"role" => "assistant"}} = e, s),
    do: {:ok, %{s | assistant: e, position: 0}}

  defp step(%{"type" => "message", "message" => %{"role" => "tool"}} = e, s),
    do: {:ok, %{s | result: e, position: s.position + 1}}

  defp step(%{"type" => "tool_started"} = e, s),
    do: {:ok, %{s | started: %{record: e, index: s.position}}}

  defp step(_, s), do: {:ok, s}

  defp apply_record(%{"type" => "lifecycle_tool_intent"} = e, s) do
    call = get_in(s.assistant, ["message", "tool_calls"]) |> Enum.at(e["call_index"])

    with true <- s.count <= @limit - 2 and not Map.has_key?(s.tools, e["tool_id"]),
         true <-
           s.epoch == e["epoch_id"] and s.request["session_id"] == e["session_id"] and
             s.request["request_id"] == e["request_id"] and s.request["turn_id"] == e["turn_id"],
         true <-
           s.assistant["request_id"] == e["request_id"] and
             Journal.source_matches?(e["proposal_source"], s.assistant),
         true <-
           s.started.index == e["call_index"] and
             Journal.source_matches?(e["intent_source"], s.started.record),
         true <-
           s.started.record["call_id"] == call["id"] and
             s.started.record["name"] == call["function"]["name"] and
             s.started.record["approval"] == e["approval"],
         true <- matches_view?(e, "input", input(call)),
         {:ok, arguments} <- Jason.decode(call["function"]["arguments"]),
         true <- s.started.record["arguments"] in [nil, arguments] do
      {:ok, %{s | tools: Map.put(s.tools, e["tool_id"], %{record: e, call: call, ended: false})}}
    else
      _ -> @error
    end
  end

  defp apply_record(%{"type" => "lifecycle_tool_outcome"} = e, s) do
    with %{record: start, call: call, ended: false} = tool <- s.tools[e["tool_id"]],
         true <-
           s.count < @limit and s.epoch == e["epoch_id"] and
             s.request["request_id"] == e["request_id"] and
             start["request_id"] == e["request_id"] and start["turn_id"] == e["turn_id"],
         true <-
           s.started.index == start["call_index"] and
             Journal.source_matches?(start["intent_source"], s.started.record),
         true <-
           Journal.source_matches?(e["tool_source"], start) and
             Journal.source_matches?(e["result_source"], s.result),
         true <-
           s.result["message"]["tool_call_id"] == call["id"] and
             s.result["message"]["ipse_tool_outcome"] == Map.take(e, ~w(status approval)),
         true <- matches_view?(e, "result", %{"text" => s.result["message"]["content"]}) do
      {:ok, put_in(s, [:tools, e["tool_id"]], %{tool | ended: true})}
    else
      _ -> @error
    end
  end

  defp apply_record(%{"type" => "lifecycle_tool_recording_stopped"} = e, s) do
    if s.count <= @limit and e["epoch_id"] in [nil, s.epoch] and
         (e["reason"] != "limit" or s.count >= @limit - 1),
       do: {:ok, %{s | stopped: true}},
       else: @error
  end

  def validate_sources(directory, session, events) do
    with {:ok, _} <- restore(events, session) do
      refs =
        Enum.flat_map(events, fn e ->
          case e["type"] do
            "lifecycle_tool_intent" -> [e["proposal_source"], e["intent_source"]]
            "lifecycle_tool_outcome" -> [e["tool_source"], e["result_source"]]
            _ -> []
          end
        end)

      references =
        Enum.reduce_while(Enum.uniq(refs), :ok, fn source, :ok ->
          case Ipse.Journal.source_page(directory, session, source["byte_offset"], 1) do
            {:ok, %{records: [%{source: ^source}]}} -> {:cont, :ok}
            _ -> {:halt, @error}
          end
        end)

      with :ok <- references do
        Enum.reduce_while(events, :ok, fn event, :ok ->
          source =
            case event["type"] do
              "lifecycle_tool_intent" -> event["intent_source"]
              "lifecycle_tool_outcome" -> event["result_source"]
              _ -> nil
            end

          if source do
            case find_source(directory, session, source, event) do
              {:ok, _} -> {:cont, :ok}
              _ -> {:halt, @error}
            end
          else
            {:cont, :ok}
          end
        end)
      end
    end
  rescue
    _ -> @error
  end

  defp find_source(directory, session, source, record),
    do: find_source(directory, session, source["byte_offset"], record, 10)

  defp find_source(_, _, _, _, 0), do: @error

  defp find_source(directory, session, cursor, record, remaining) do
    with {:ok, %{records: [actual], next: next}} <-
           Ipse.Journal.source_page(directory, session, cursor, 1) do
      cond do
        actual.record == record -> {:ok, actual.source}
        next != nil -> find_source(directory, session, next, record, remaining - 1)
        true -> @error
      end
    end
  end

  defp input(call),
    do: %{"name" => call["function"]["name"], "arguments_json" => call["function"]["arguments"]}

  defp bounded(data), do: if(bytes(data) <= 8192, do: data)

  defp view?(e, key),
    do:
      Ipse.JSON.safe_uint?(e[key <> "_bytes"]) and Ipse.JSON.sha256?(e[key <> "_sha256"]) and
        if(e[key] == nil,
          do: e[key <> "_bytes"] > 8192,
          else:
            private_data?("tool." <> if(key == "input", do: "input", else: "result"), e[key]) and
              bytes(e[key]) == e[key <> "_bytes"] and digest(e[key]) == e[key <> "_sha256"]
        )

  defp matches_view?(e, key, data),
    do:
      e[key] == bounded(data) and e[key <> "_bytes"] == bytes(data) and
        e[key <> "_sha256"] == digest(data)

  defp refs?(e, keys),
    do:
      Enum.all?(keys, &(Journal.valid_source?(e[&1]) and e[&1]["session_id"] == e["session_id"]))

  defp bytes(data), do: byte_size(Jason.encode!(data))
  defp digest(data), do: Ipse.JSON.digest([data])
  defp keys?(e, keys), do: is_map(e) and Enum.sort(Map.keys(e)) == Enum.sort(keys)
  defp common?(e), do: e["version"] === 1 and id?(e["session_id"])
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
end
