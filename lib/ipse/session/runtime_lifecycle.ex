defmodule Ipse.Session.RuntimeLifecycle do
  @moduledoc "Opt-in runtime epochs and operator-wait facts; records confer no execution authority."
  alias Ipse.Journal

  @types ~w(lifecycle_epoch_started lifecycle_epoch_closed lifecycle_wait_started lifecycle_wait_finished lifecycle_recording_stopped)
  @wait_keys ~w(type version session_id epoch_id wait_id kind domain turn_id request_id parent_invocation_id operation_id child_id subject_source)
  @limit 10_000
  def types, do: @types
  def limit, do: @limit

  def open(config, policy, events, session, resumed) do
    {:ok, saved} = restore(events, session)

    enabled =
      policy["mode"] in ~w(local export) or
        Enum.any?(
          Map.get(config, :extensions, []),
          &("lifecycle.record" in &1.identity["capabilities"])
        )

    if enabled and not saved.stopped do
      ctx = %{session: session, epoch: saved.epoch, active: false, wait: nil, count: saved.count}

      if saved.count > @limit - 2 do
        stop_recording(ctx)
      else
        epoch = Ipse.Usage.id()

        record = %{
          "type" => "lifecycle_epoch_started",
          "version" => 1,
          "session_id" => session,
          "epoch_id" => epoch,
          "mode" => if(resumed, do: "resume", else: "fresh"),
          "previous_epoch_id" => saved.epoch,
          "previous_state" =>
            cond do
              saved.epoch == nil -> "none"
              saved.closed -> "closed"
              true -> "unclosed"
            end
        }

        {%{ctx | epoch: epoch, active: true, count: saved.count + 1}, [record]}
      end
    else
      {nil, []}
    end
  end

  def begin_wait(nil, _, _), do: {nil, []}
  def begin_wait(%{active: false} = ctx, _, _), do: {ctx, []}

  def begin_wait(%{wait: nil} = ctx, domain, links) do
    if ctx.count > @limit - 3 do
      stop_recording(ctx)
    else
      record =
        Map.merge(
          Map.new(
            ~w(turn_id request_id parent_invocation_id operation_id child_id subject_source),
            &{&1, nil}
          ),
          links
        )
        |> Map.merge(%{
          "type" => "lifecycle_wait_started",
          "version" => 1,
          "session_id" => ctx.session,
          "epoch_id" => ctx.epoch,
          "wait_id" => Ipse.Usage.id(),
          "domain" => domain,
          "kind" =>
            if(domain in ~w(native_question extension_question), do: "question", else: "approval")
        })

      true = valid_record?(record)

      {%{
         ctx
         | wait: %{record: record, started: System.monotonic_time(:millisecond)},
           count: ctx.count + 1
       }, [record]}
    end
  end

  def finish_wait(nil, _), do: {nil, []}
  def finish_wait(%{active: false} = ctx, _), do: {ctx, []}
  def finish_wait(%{wait: nil} = ctx, _), do: {ctx, []}

  def finish_wait(ctx, outcome) do
    record =
      Map.merge(ctx.wait.record, %{
        "type" => "lifecycle_wait_finished",
        "outcome" => outcome,
        "duration_ms" => max(System.monotonic_time(:millisecond) - ctx.wait.started, 0)
      })

    true = valid_record?(record)
    {%{ctx | wait: nil, count: ctx.count + 1}, [record]}
  end

  def close(nil, _, _), do: {nil, []}
  def close(%{active: false} = ctx, _, _), do: {ctx, []}

  def close(ctx, reason, cleanup) do
    {ctx, records} = finish_wait(ctx, "interrupted")

    record = %{
      "type" => "lifecycle_epoch_closed",
      "version" => 1,
      "session_id" => ctx.session,
      "epoch_id" => ctx.epoch,
      "closure" => reason,
      "cleanup_confirmed" => cleanup
    }

    true = valid_record?(record)
    {%{ctx | active: false, count: ctx.count + 1}, records ++ [record]}
  end

  defp stop_recording(ctx) do
    record = %{
      "type" => "lifecycle_recording_stopped",
      "version" => 1,
      "session_id" => ctx.session,
      "epoch_id" => ctx.epoch,
      "reason" => "limit"
    }

    {%{ctx | active: false, wait: nil, count: ctx.count + 1}, [record]}
  end

  def restore(events, session \\ nil) do
    initial = %{
      session: session,
      epoch: nil,
      closed: false,
      wait: nil,
      count: 0,
      epochs: MapSet.new(),
      waits: MapSet.new(),
      stopped: false,
      subject: nil
    }

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, saved} ->
      if event["type"] in @types do
        case restore_record(event, saved) do
          {:ok, next} -> {:cont, {:ok, next}}
          _ -> {:halt, {:error, :invalid_runtime_lifecycle}}
        end
      else
        {:cont, {:ok, %{saved | subject: subject_after(event, saved.subject)}}}
      end
    end)
  rescue
    _ -> {:error, :invalid_runtime_lifecycle}
  end

  defp restore_record(event, saved) do
    with true <- not saved.stopped and valid_record?(event),
         true <- saved.session in [nil, event["session_id"]],
         {:ok, next} <- step(event, saved) do
      {:ok, %{next | session: event["session_id"], count: saved.count + 1}}
    else
      _ -> {:error, :invalid_runtime_lifecycle}
    end
  end

  defp step(%{"type" => "lifecycle_epoch_started"} = e, s) do
    previous =
      cond do
        s.epoch == nil -> "none"
        s.closed -> "closed"
        true -> "unclosed"
      end

    if s.count <= @limit - 2 and e["previous_epoch_id"] == s.epoch and
         e["previous_state"] == previous and
         (e["mode"] == "resume" or s.epoch == nil) and not MapSet.member?(s.epochs, e["epoch_id"]) do
      {:ok,
       %{
         s
         | epoch: e["epoch_id"],
           closed: false,
           wait: nil,
           epochs: MapSet.put(s.epochs, e["epoch_id"])
       }}
    else
      {:error, :invalid_runtime_lifecycle}
    end
  end

  defp step(%{"type" => "lifecycle_epoch_closed"} = e, s) do
    if s.count < @limit and e["epoch_id"] == s.epoch and not s.closed and s.wait == nil,
      do: {:ok, %{s | closed: true}},
      else: {:error, :invalid_runtime_lifecycle}
  end

  defp step(%{"type" => "lifecycle_wait_started"} = e, s) do
    if s.count <= @limit - 3 and e["epoch_id"] == s.epoch and not s.closed and s.wait == nil and
         not MapSet.member?(s.waits, e["wait_id"]) and subject_matches?(e, s.subject),
       do: {:ok, %{s | wait: e, waits: MapSet.put(s.waits, e["wait_id"])}},
       else: {:error, :invalid_runtime_lifecycle}
  end

  defp step(%{"type" => "lifecycle_wait_finished"} = e, s) do
    started = e |> Map.drop(~w(outcome duration_ms)) |> Map.put("type", "lifecycle_wait_started")

    if s.count < @limit and started == s.wait,
      do: {:ok, %{s | wait: nil}},
      else: {:error, :invalid_runtime_lifecycle}
  end

  defp step(%{"type" => "lifecycle_recording_stopped"} = e, s) do
    if s.count in (@limit - 2)..@limit and e["epoch_id"] == s.epoch,
      do: {:ok, %{s | stopped: true, wait: nil}},
      else: {:error, :invalid_runtime_lifecycle}
  end

  def valid_record?(%{"type" => "lifecycle_epoch_started"} = e),
    do:
      keys?(e, ~w(type version session_id epoch_id mode previous_epoch_id previous_state)) and
        common?(e) and id?(e["epoch_id"]) and
        e["mode"] in ~w(fresh resume) and optional_id?(e["previous_epoch_id"]) and
        e["previous_state"] in ~w(none closed unclosed)

  def valid_record?(%{"type" => "lifecycle_epoch_closed"} = e),
    do:
      keys?(e, ~w(type version session_id epoch_id closure cleanup_confirmed)) and common?(e) and
        id?(e["epoch_id"]) and
        e["closure"] in ~w(close owner_down cleanup_failure) and
        is_boolean(e["cleanup_confirmed"]) and
        (e["closure"] == "close" or e["cleanup_confirmed"] == false)

  def valid_record?(%{"type" => "lifecycle_recording_stopped"} = e),
    do:
      keys?(e, ~w(type version session_id epoch_id reason)) and common?(e) and
        optional_id?(e["epoch_id"]) and e["reason"] == "limit"

  def valid_record?(%{"type" => type} = e)
      when type in ~w(lifecycle_wait_started lifecycle_wait_finished) do
    keys?(
      e,
      @wait_keys ++ if(type == "lifecycle_wait_finished", do: ~w(outcome duration_ms), else: [])
    ) and
      common?(e) and id?(e["epoch_id"]) and id?(e["wait_id"]) and
      Enum.all?(
        ~w(turn_id request_id parent_invocation_id operation_id child_id),
        &optional_id?(e[&1])
      ) and
      e["domain"] in ~w(tool extension_action delegated_tool native_question extension_question) and
      e["kind"] ==
        if(e["domain"] in ~w(native_question extension_question),
          do: "question",
          else: "approval"
        ) and
      links?(e) and
      (e["subject_source"] == nil or
         (Journal.valid_source?(e["subject_source"]) and
            e["subject_source"]["session_id"] == e["session_id"] and e["kind"] == "question")) and
      (type != "lifecycle_wait_finished" or (outcome?(e) and uint?(e["duration_ms"])))
  rescue
    _ -> false
  end

  def valid_record?(_), do: false

  def question_source(events, question) do
    question_type =
      if question[:kind] == :extension, do: "extension_question", else: "operator_question"

    index =
      events
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find_value(fn {e, i} ->
        if e["type"] == question_type and
             (e["id"] == question.id or e["operation_id"] == question.id),
           do: i
      end)

    if index != nil do
      question_record = Enum.at(events, index)

      events
      |> Enum.drop(index + 1)
      |> Enum.reverse()
      |> Enum.find_value(fn e ->
        if e["type"] == "lifecycle_wait_started" and e["kind"] == "question" and
             Journal.source_matches?(e["subject_source"], question_record),
           do: e["subject_source"]
      end)
    end
  end

  def validate_sources(directory, session, events) do
    with {:ok, _} <- restore(events, session) do
      events
      |> Enum.filter(&(&1["type"] == "lifecycle_wait_started" and &1["subject_source"] != nil))
      |> Enum.uniq_by(&Map.take(&1, ~w(subject_source domain operation_id parent_invocation_id)))
      |> Enum.reduce_while(:ok, fn e, :ok ->
        source = e["subject_source"]

        with {:ok, %{records: [%{source: actual, record: record}]}} <-
               Ipse.Journal.source_page(directory, session, source["byte_offset"], 1),
             true <- actual == source,
             true <-
               (e["domain"] == "native_question" and record["type"] == "operator_question") or
                 (e["domain"] == "extension_question" and record["type"] == "extension_question" and
                    record["operation_id"] == e["operation_id"] and
                    record["parent_invocation_id"] == e["parent_invocation_id"]) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, :invalid_runtime_lifecycle_source}}
        end
      end)
    end
  rescue
    _ -> {:error, :invalid_runtime_lifecycle_source}
  end

  def describe(record) do
    if valid_record?(record) do
      type =
        case record["type"] do
          "lifecycle_epoch_started" ->
            if record["mode"] == "fresh", do: "session.started", else: "session.resumed"

          "lifecycle_epoch_closed" ->
            "session.close_committed"

          "lifecycle_wait_started" ->
            "wait.started"

          "lifecycle_wait_finished" ->
            "wait.finished"

          "lifecycle_recording_stopped" ->
            "session.recording_stopped"
        end

      data =
        Map.take(
          record,
          ~w(previous_state closure cleanup_confirmed kind domain outcome duration_ms reason)
        )

      correlations =
        Map.take(
          record,
          ~w(epoch_id previous_epoch_id wait_id turn_id request_id parent_invocation_id operation_id child_id)
        )
        |> Map.reject(fn {_, v} -> v == nil end)

      correlations =
        if record["subject_source"],
          do: Map.put(correlations, "causing_event_id", record["subject_source"]["event_id"]),
          else: correlations

      {:ok, type, nil, nil, data, correlations}
    else
      {:error, :invalid_lifecycle_event}
    end
  end

  defp common?(e), do: e["version"] === 1 and id?(e["session_id"])

  defp subject_after(%{"type" => type} = e, _)
       when type in ~w(operator_question extension_question) do
    e
  end

  defp subject_after(%{"type" => type, "id" => id}, %{"type" => "operator_question", "id" => id})
       when type in ~w(operator_answer operator_question_closed) do
    nil
  end

  defp subject_after(%{"type" => "extension_action_result", "operation_id" => id}, %{
         "type" => "extension_question",
         "operation_id" => id
       }) do
    nil
  end

  defp subject_after(_, subject), do: subject

  defp links?(e) do
    (e["domain"] == "native_question" or id?(e["turn_id"])) and
      case e["domain"] do
        "delegated_tool" ->
          id?(e["request_id"]) and id?(e["child_id"]) and e["operation_id"] == nil and
            e["parent_invocation_id"] == nil

        domain when domain in ~w(extension_action extension_question) ->
          id?(e["parent_invocation_id"]) and id?(e["operation_id"]) and e["request_id"] == nil and
            e["child_id"] == nil

        "tool" ->
          id?(e["request_id"]) and e["operation_id"] == nil and e["parent_invocation_id"] == nil and
            e["child_id"] == nil

        "native_question" ->
          e["operation_id"] == nil and e["parent_invocation_id"] == nil and e["child_id"] == nil

        _ ->
          false
      end
  end

  defp outcome?(e),
    do:
      e["outcome"] in ~w(cancelled interrupted expired) or
        (e["kind"] == "question" and e["outcome"] == "answered") or
        (e["kind"] == "approval" and e["outcome"] in ~w(approved denied))

  defp subject_matches?(%{"subject_source" => nil}, _), do: true

  defp subject_matches?(e, subject),
    do:
      is_map(subject) and Journal.source_matches?(e["subject_source"], subject) and
        ((e["domain"] == "native_question" and subject["type"] == "operator_question") or
           (e["domain"] == "extension_question" and subject["type"] == "extension_question" and
              subject["operation_id"] == e["operation_id"] and
              subject["parent_invocation_id"] == e["parent_invocation_id"]))

  defp keys?(e, keys), do: Enum.sort(Map.keys(e)) == Enum.sort(keys)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp optional_id?(v), do: v == nil or id?(v)
  defp uint?(v), do: is_integer(v) and v in 0..9_007_199_254_740_991
end
