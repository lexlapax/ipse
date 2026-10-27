defmodule Ipse.Session.SourceWindow do
  @moduledoc "Bounded projection of already validated, committed Session source receipts."
  alias Ipse.Session.SourceIndex
  alias Ipse.JSON
  @layout "session_sources_v1"
  @pending_bytes 4_194_304
  @pending_count 128
  @derive {Inspect, only: [:coverage, :pending_bytes]}
  defstruct [
    :index,
    :effective_source,
    :historical_window,
    :draft_id,
    admitted: false,
    pending: %{},
    pending_bytes: 0,
    coverage: %{}
  ]

  def layout, do: @layout
  def enabled?(config), do: config[:source_layout] == @layout

  def opened(w),
    do: %{
      "type" => "source_window_opened",
      "version" => 1,
      "session_id" => w.index.session_id,
      "window_id" => w.index.window_id,
      "policy_generation" => w.index.policy_generation
    }

  @doc "Resolve source references only after full Saved validation, before any permitted tail repair."
  def validate_sources(directory, session, events) do
    Enum.reduce_while(events, :ok, fn
      %{"type" => "source_answer_committed", "answer" => %{"effective_source" => source}}, :ok ->
        case Ipse.Journal.source_page(directory, session, source["byte_offset"], 1) do
          {:ok, %{records: [%{source: actual}]}} when actual == source -> {:cont, :ok}
          _ -> {:halt, {:error, :invalid_source_window}}
        end

      _, :ok ->
        {:cont, :ok}
    end)
  end

  @doc false
  def attach_effective_source(w, directory, session) do
    if is_map(w.pending[:user]) do
      find_effective(w, directory, session, 0, nil)
    else
      {:ok, w}
    end
  end

  defp find_effective(w, directory, session, cursor, found) do
    with {:ok, page} <- Ipse.Journal.source_page(directory, session, cursor, 32) do
      found =
        Enum.reduce(page.records, found, fn %{source: source, record: record}, acc ->
          if record == w.pending[:user], do: source, else: acc
        end)

      if page.next,
        do: find_effective(w, directory, session, page.next, found),
        else: {:ok, %{w | effective_source: found}}
    else
      _ -> {:ok, %{w | effective_source: nil}}
    end
  end

  @doc "Called only after the complete Saved prefix has passed its owning validators."
  def restore(events, session) do
    metadata = (List.first(events) || %{})["metadata"] || %{}
    true = metadata["source_layout"] in [nil, @layout]

    with {:ok, index} <- SourceIndex.new(session) do
      window = %__MODULE__{
        index: index,
        admitted: metadata["source_layout"] == @layout,
        coverage:
          Map.new(
            ~w(observed indexed unavailable capacity_refused legacy_unverified pending_gaps refused),
            &{&1, 0}
          )
      }

      {:ok, Enum.reduce(events, window, &advance(&2, &1))}
    end
  rescue
    _ -> {:error, :invalid_source_window}
  end

  def snapshot(%__MODULE__{} = w),
    do: Map.put(SourceIndex.snapshot(w.index), "coverage", w.coverage)

  def execute(%__MODULE__{} = w, operation, request) do
    case operation do
      "source.list" -> SourceIndex.list(w.index, request)
      "source.read" -> SourceIndex.read(w.index, request)
      "source.quote" -> SourceIndex.quote(w.index, request)
      _ -> {:error, :source_index_refused}
    end
  end

  @doc "Advance after append confirmation, never from a worker-provided source or origin."
  def advance(w, event, source \\ nil)
  def advance(nil, _, _), do: nil

  def advance(w, event, source) do
    next = do_advance(w, event, source)
    {:ok, index} = SourceIndex.coverage(next.index, next.coverage)
    %{next | index: index}
  end

  defp do_advance(%{draft_id: nil} = w, %{"type" => "draft_started", "draft_id" => id}, _),
    do: %{w | draft_id: id}

  defp do_advance(%{draft_id: id} = w, %{"type" => "draft_cancelled", "draft_id" => id}, _)
       when not is_nil(id), do: %{w | draft_id: nil}

  defp do_advance(%{draft_id: id} = w, %{"type" => "draft_consumed", "draft_id" => id}, _)
       when not is_nil(id), do: %{w | draft_id: nil}

  defp do_advance(%{draft_id: id} = w, _event, _) when not is_nil(id), do: w

  defp do_advance(w, %{"type" => "input_received"} = event, _), do: store(w, :input, event)

  defp do_advance(w, %{"type" => "source_window_opened"} = event, _) do
    true = Enum.sort(Map.keys(event)) == ~w(policy_generation session_id type version window_id)

    true =
      event["version"] === 1 and event["session_id"] == w.index.session_id and
        event["policy_generation"] === w.index.policy_generation and
        is_binary(event["window_id"]) and Regex.match?(~r/\A[0-9a-f]{32}\z/, event["window_id"])

    %{w | historical_window: event["window_id"]}
  end

  defp do_advance(w, %{"type" => "message", "message" => %{"role" => "user"} = m} = event, source) do
    cond do
      Map.has_key?(m, "ipse_reference") ->
        w

      input = w.pending[:input] ->
        w
        |> drop(:input)
        |> admit(SourceIndex.admit_input(w.index, input, event))
        |> Map.put(:effective_source, source)
        |> store(:user, event)

      true ->
        w |> count("legacy_unverified") |> count("observed") |> count("unavailable")
    end
  end

  defp do_advance(
         w,
         %{"type" => "message", "message" => %{"role" => "tool"} = message} = event,
         _
       ) do
    key = {:source_call, message["tool_call_id"]}

    if request = w.pending[key] do
      if get_in(message, ["ipse_tool_outcome", "status"]) == "result_recorded" do
        {:ok, value} = JSON.decode_bounded(message["content"], 8192)

        :ok =
          SourceIndex.validate_saved_read(
            w.index,
            request["op"],
            Map.delete(request, "op"),
            value,
            w.historical_window
          )
      end

      drop(w, key)
    else
      store(w, {:message, JSON.digest([event])}, event)
    end
  end

  defp do_advance(w, %{"type" => "message", "message" => %{"role" => "assistant"} = m} = event, _) do
    w =
      Enum.reduce(m["tool_calls"] || [], w, fn call, acc ->
        name = get_in(call, ["function", "name"])

        if name in ~w(source_list source_read source_quote) do
          op = String.replace(name, "_", ".")

          request =
            with {:ok, args} when is_map(args) <-
                   JSON.decode_bounded(get_in(call, ["function", "arguments"]), 16_384),
                 request = Map.put(args, "op", op),
                 :ok <- Ipse.Extension.SourceRead.validate(request),
                 do: request,
                 else: (_ -> %{"op" => op, "invalid" => true})

          store(acc, {:source_call, call["id"]}, request)
        else
          acc
        end
      end)

    text = m["content"]

    if is_binary(text) and String.valid?(text) do
      store(w, :assistant_final, text != "" and m["tool_calls"] in [nil, []])
      |> store(:assistant, %{
        "request_id" => event["request_id"],
        "assistant_sha256" => JSON.digest([m]),
        "original_sha256" => JSON.sha256(text),
        "original_bytes" => byte_size(text)
      })
    else
      drop(w, :assistant)
    end
  end

  defp do_advance(w, %{"type" => "operator_question"} = event, _), do: store(w, :question, event)

  defp do_advance(w, %{"type" => "operator_answer", "version" => 2} = event, _) do
    w
    |> drop(:question)
    |> admit(SourceIndex.admit_operator_answer(w.index, event, w.pending[:question]))
  end

  defp do_advance(w, %{"type" => "operator_answer"}, _),
    do: w |> drop(:question) |> count("legacy_unverified")

  defp do_advance(w, %{"type" => "lifecycle_answer_committed"} = event, _) do
    facts = w.pending[:assistant]

    true = facts == nil or Map.take(event, Map.keys(facts)) == facts

    if is_map(facts) do
      w
      |> drop(:assistant)
      |> drop(:assistant_final)
      |> admit(SourceIndex.admit_answer(w.index, event))
    else
      w |> count("unavailable") |> count("observed")
    end
  end

  defp do_advance(w, %{"type" => "source_answer_committed"} = wrapper, _) do
    true =
      w.admitted and Enum.sort(Map.keys(wrapper)) == ~w(answer type version) and
        wrapper["version"] === 1

    event = wrapper["answer"]

    true =
      Ipse.Session.Lifecycle.valid_answer?(event) and
        Ipse.Journal.source_matches?(event["effective_source"], w.pending[:user]) and
        event["effective_source"]["session_id"] == w.index.session_id

    do_advance(%{w | effective_source: event["effective_source"]}, event, nil)
  end

  defp do_advance(w, %{"type" => "lifecycle_tool_intent"} = event, _),
    do: store(w, {:tool, event["tool_id"]}, event)

  defp do_advance(w, %{"type" => "lifecycle_tool_outcome"} = event, _) do
    key = {:message, get_in(event, ["result_source", "record_sha256"])}
    intent = w.pending[{:tool, event["tool_id"]}]
    message = w.pending[key]

    next = w |> drop(key) |> drop({:tool, event["tool_id"]})
    name = get_in(intent || %{}, ["input", "name"])

    if name in ~w(read write edit shell) or (is_binary(name) and Ipse.MCP.external?(name)),
      do: admit(next, SourceIndex.admit_tool(w.index, intent, event, message)),
      else: next
  end

  defp do_advance(w, %{"type" => "extension_invocation_intent"} = event, _),
    do: store(w, {:parent, event["invocation_id"]}, event)

  defp do_advance(w, %{"type" => "extension_effect_result"} = event, _),
    do: store(w, {:effect, event["operation_id"]}, event)

  defp do_advance(w, %{"type" => "extension_decision_response"} = event, _),
    do: store(w, {:effect, event["request_id"]}, event)

  defp do_advance(w, %{"type" => "request_admitted", "operation" => "decision"} = event, _),
    do: store(w, {:admission, event["request_id"]}, event)

  defp do_advance(w, %{"type" => "request_finished", "operation" => "decision"} = event, _),
    do: store(w, {:completion, event["request_id"]}, event)

  defp do_advance(
         w,
         %{"type" => "extension_action_result", "request" => %{"op" => op}} = event,
         _
       )
       when op in ~w(mcp.call embedding.create decision.create) do
    id = event["operation_id"]

    result =
      if op == "decision.create" do
        SourceIndex.admit_decision(
          w.index,
          event,
          %{admission: w.pending[{:admission, id}], completion: w.pending[{:completion, id}]},
          w.pending[{:effect, id}]
        )
      else
        SourceIndex.admit_effect(
          w.index,
          event,
          w.pending[{:effect, id}],
          w.pending[{:parent, event["parent_invocation_id"]}]
        )
      end

    w |> drop({:effect, id}) |> drop({:admission, id}) |> drop({:completion, id}) |> admit(result)
  end

  defp do_advance(
         w,
         %{"type" => "extension_action_result", "request" => %{"op" => op} = request} = event,
         _
       )
       when op in ~w(source.list source.read source.quote) do
    if event["outcome"]["status"] == "ok" do
      :ok =
        SourceIndex.validate_saved_read(
          w.index,
          op,
          Map.delete(request, "op"),
          event["outcome"]["value"],
          w.historical_window
        )
    end

    w
  end

  defp do_advance(w, %{"type" => "extension_invocation_result"} = event, _),
    do: drop(w, {:parent, event["invocation_id"]})

  defp do_advance(w, %{"type" => type}, _) when type in ~w(cancelled turn_finished) do
    w =
      if not is_nil(w.pending[:input]) or w.pending[:assistant_final] == true,
        do: w |> count("observed") |> count("unavailable"),
        else: w

    Enum.reduce(Map.keys(w.pending), w, fn key, acc ->
      if key == :user, do: acc, else: drop(acc, key)
    end)
  end

  defp do_advance(w, %{"type" => "lifecycle_tool_recording_stopped"}, _),
    do: w |> count("observed") |> count("unavailable")

  defp do_advance(w, _, _), do: w

  defp admit(w, {:ok, index}) do
    added = length(index.order) - length(w.index.order)

    unavailable =
      Enum.count(
        Enum.drop(index.order, length(w.index.order)),
        &(index.entries[&1].coverage == "unavailable")
      )

    %{w | index: index}
    |> count("indexed", added)
    |> count("observed", added)
    |> count("unavailable", unavailable)
  end

  defp admit(w, {:error, :source_index_capacity}),
    do: w |> count("observed") |> count("unavailable") |> count("capacity_refused")

  defp admit(w, _), do: w |> count("observed") |> count("unavailable") |> count("refused")

  defp store(w, key, value) do
    w = drop(w, key)
    bytes = byte_size(Jason.encode!(value))

    if map_size(w.pending) < @pending_count and w.pending_bytes + bytes <= @pending_bytes do
      %{w | pending: Map.put(w.pending, key, value), pending_bytes: w.pending_bytes + bytes}
    else
      count(w, "pending_gaps")
    end
  end

  defp drop(w, key) do
    case Map.pop(w.pending, key) do
      {nil, _} ->
        w

      {value, pending} ->
        %{w | pending: pending, pending_bytes: w.pending_bytes - byte_size(Jason.encode!(value))}
    end
  end

  defp count(w, key, n \\ 1),
    do: update_in(w.coverage[key], &min((&1 || 0) + n, 9_007_199_254_740_991))
end
