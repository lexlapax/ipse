defmodule Ipse.Test.RecallDiagnosticTrace do
  @moduledoc false
  @limit 512
  @participants 256
  @targets [
    {Ipse.Provider.MintOwned, :execute, 5, {4, :timeout_ms}},
    {Ipse.Session.Resources, :controlled_owned_effect, 2, {2, :timeout_ms}},
    {Ipse.Session.Resources, :controlled_wait, 5, {5, :wait_ms}},
    {Ipse.Provider.MintTransport, :stream_witnessed, 8, {4, :timeout_ms}},
    {Ipse.Provider.MintTransport, :execute, 9, {4, :timeout_ms}},
    {Ipse.Provider.MintTransport, :admitted_send, 8, {5, :deadline_ms}},
    {Ipse.Provider.MintTransport, :remaining, 1, {1, :deadline_ms}},
    {Ipse.Session.InferenceDispatch, :gate, 4, nil},
    {Ipse.Session.InferenceDispatch, :with_current, 2, nil},
    {Ipse.Session.InferenceDispatch, :current_wire, 2, nil},
    {Ipse.Session.SourceReplayCache, :reconstruct, 2, nil},
    {Ipse.Session.SourceReplayCache, :fresh, 1, nil}
  ]
  @atoms ~w(inference_timeout inference_request_refused inference_request_failed inference_send_uncertain inference_completion_unconfirmed inference_cleanup_unavailable inference_cleanup_unconfirmed inference_connection_failed inference_connection_unconfirmed inference_response_too_large inference_scope_refused invalid_inference_request inference_dispatch_refused collection_use_refused collection_source_refused source_replay_unavailable source_index_refused cleanup_unconfirmed effect_interrupted cleanup_scope_closed nested_controlled_effect required_text_consumer_closed)a
  @messages [
    {"Managed inference transport did not confirm native completion and cleanup.",
     "transport_completion_cleanup_unconfirmed"},
    {"Managed inference was refused before its body was sent.", "managed_send_refused"},
    {"Inference dispatch validation changed while waiting; no provider request was dispatched.",
     "dispatch_validation_changed"},
    {"Inference service wait expired before dispatch; no provider request was dispatched.",
     "service_wait_expired"},
    {"Inference service wait was cancelled before dispatch.", "service_wait_cancelled"},
    {"Inference service admission is unavailable; no provider request was dispatched.",
     "service_admission_unavailable"},
    {"Managed historical content cannot be safely reused. Inspect retained history or start a fresh session; no inference was dispatched.",
     "managed_history_unavailable"}
  ]

  def start(session, owner \\ self(), control \\ false) when is_pid(session) and is_pid(owner) do
    targets =
      if control,
        do:
          @targets ++
            [{__MODULE__, :control, 1, nil}, {__MODULE__, :numeric_control, 2, {2, :timeout_ms}}],
        else: @targets

    tracer =
      spawn_link(fn ->
        loop(%{
          owner: owner,
          targets: targets,
          aliases: Map.put_new(%{owner => "fixture"}, session, "session"),
          next: 0,
          records: [],
          count: 0,
          stacks: %{},
          parents: %{},
          exits: %{},
          ancestry_overflow: false,
          truncated: false,
          stopped: false
        })
      end)

    for {module, function, arity, numeric} <- targets do
      Code.ensure_loaded!(module)

      match =
        case numeric do
          nil ->
            [{:_, [], [{:return_trace}, {:exception_trace}]}]

          {position, field} ->
            head = List.duplicate(:_, arity) |> List.replace_at(position - 1, :"$1")

            [
              {head, [{:is_integer, :"$1"}],
               [{:message, {{field, :"$1"}}}, {:return_trace}, {:exception_trace}]}
            ]
        end

      1 = :erlang.trace_pattern({module, function, arity}, match, [:local])
    end

    1 =
      :erlang.trace_pattern(
        {:erlang, :exit, 2},
        [{[:"$1", :kill], [{:is_pid, :"$1"}], [{:message, {{:killed_pid, :"$1"}}}]}],
        [:local]
      )

    true =
      :erlang.trace(:all, true, [
        :call,
        :arity,
        :procs,
        :set_on_spawn,
        :monotonic_timestamp,
        {:tracer, tracer}
      ]) > 0

    %{pid: tracer, targets: targets}
  end

  def finish(%{pid: tracer, targets: targets}) do
    stop_calls(targets)
    ref = :erlang.trace_delivered(:all)

    receive do
      {:trace_delivered, :all, ^ref} -> :ok
    after
      5_000 -> raise "diagnostic trace barrier unavailable"
    end

    send(tracer, {:collect, self(), ref})

    receive do
      {:trace_summary, ^ref, summary} -> summary
    after
      5_000 -> raise "diagnostic trace summary unavailable"
    end
  end

  def control(fun), do: fun.()
  def numeric_control(_, _), do: {:unknown, :cleanup_unconfirmed}

  def identify(%{pid: tracer}, pid) when is_pid(pid) do
    ref = make_ref()
    send(tracer, {:identify, self(), pid, ref})

    receive do
      {:identified, ^ref, name} -> name
    after
      1_000 -> raise "diagnostic actor identity unavailable"
    end
  end

  def safe_return({:error, reason}), do: Map.put(safe_error(reason), "class", "error")
  def safe_return({:unknown, reason}), do: Map.put(safe_error(reason), "class", "unknown")

  def safe_return({:ok, {_, confirmed}}) when is_boolean(confirmed),
    do: %{"class" => "ok_tuple", "confirmed" => confirmed}

  def safe_return({:ok, _}), do: %{"class" => "ok_tuple"}
  def safe_return({:ok, _, _}), do: %{"class" => "ok_tuple3"}

  def safe_return({:managed_native_result, result, _}),
    do: %{"class" => "managed_native_result", "result" => safe_return(result)}

  def safe_return(:ok), do: %{"class" => "ok"}
  def safe_return(:closed), do: %{"class" => "closed"}
  def safe_return(value) when is_integer(value), do: %{"class" => "integer", "value" => value}
  def safe_return(_), do: %{"class" => "other"}

  def safe_error(reason) when reason in @atoms, do: %{"code" => Atom.to_string(reason)}

  def safe_error(reason) when is_binary(reason) do
    found =
      Enum.find(@messages, fn {fixed, _} ->
        reason == fixed or
          (String.starts_with?(reason, "Inference service ") and
             String.ends_with?(reason, " " <> fixed))
      end)

    case found do
      {_, code} ->
        %{"code" => code}

      nil ->
        %{
          "code" => "unclassified_binary",
          "bytes" => byte_size(reason),
          "sha256" => Ipse.JSON.sha256(reason)
        }
    end
  end

  def safe_error({:error, reason}), do: safe_error(reason)
  def safe_error(_), do: %{"code" => "unclassified_term"}

  defp stop_calls(targets) do
    :erlang.trace(:all, false, [:call, :arity, :procs, :set_on_spawn, :monotonic_timestamp])

    for {module, function, arity, _} <- targets,
        do: :erlang.trace_pattern({module, function, arity}, false, [:local])

    :erlang.trace_pattern({:erlang, :exit, 2}, false, [:local])
  end

  defp loop(state) do
    receive do
      {:identify, from, pid, ref} when from == state.owner and is_pid(pid) ->
        {name, state} = alias_pid(state, pid)
        send(from, {:identified, ref, name})
        loop(state)

      {:trace_ts, pid, :call, {:erlang, :exit, 2}, {:killed_pid, target}, at} ->
        {actor, state} = alias_pid(state, pid)
        {target_name, state} = alias_pid(state, target)

        loop(
          record(state, %{
            "event" => "kill",
            "pid" => actor,
            "target" => target_name,
            "at_us" => micros(at)
          })
        )

      {:trace_ts, pid, :call, mfa, {field, number}, at}
      when is_atom(field) and is_integer(number) ->
        loop(call(state, pid, mfa, at, %{Atom.to_string(field) => number}))

      {:trace_ts, pid, :call, mfa, at} ->
        loop(call(state, pid, mfa, at, %{}))

      {:trace_ts, pid, :return_from, mfa, result, at} ->
        loop(returned(state, pid, mfa, at, safe_return(result)))

      {:trace_ts, pid, :exception_from, mfa, {class, reason}, at}
      when class in [:error, :exit, :throw] ->
        loop(
          returned(state, pid, mfa, at, %{
            "class" => Atom.to_string(class),
            "reason" => safe_error(reason)
          })
        )

      {:trace_ts, parent, :spawn, child, _, at} ->
        if map_size(state.parents) < @participants do
          loop(%{state | parents: Map.put(state.parents, child, {parent, at})})
        else
          loop(%{state | ancestry_overflow: true})
        end

      {:trace_ts, pid, :exit, reason, at} ->
        code =
          if reason in [:normal, :kill, :killed, :shutdown, :cleanup_unconfirmed],
            do: Atom.to_string(reason),
            else: "other"

        if map_size(state.exits) < @participants do
          loop(%{
            state
            | exits: Map.put(state.exits, pid, %{"code" => code, "at_us" => micros(at)})
          })
        else
          loop(%{state | ancestry_overflow: true})
        end

      {:collect, from, ref} ->
        {ancestry, state} =
          Enum.reduce(Map.keys(state.aliases), {[], state}, fn pid, {edges, acc} ->
            ancestors(acc, pid, edges, 8)
          end)

        exits =
          for {pid, row} <- state.exits,
              Map.has_key?(state.aliases, pid),
              do: Map.put(row, "pid", Map.fetch!(state.aliases, pid))

        open =
          for {pid, stack} <- state.stacks,
              {mfa, id} <- stack,
              do: %{
                "pid" => Map.fetch!(state.aliases, pid),
                "mfa" => format_mfa(mfa),
                "call_id" => id
              }

        send(
          from,
          {:trace_summary, ref,
           %{
             "version" => 1,
             "truncated" => state.truncated,
             "record_count" => state.count,
             "participant_count" => map_size(state.aliases),
             "ancestry_overflow" => state.ancestry_overflow,
             "ancestry" => Enum.uniq(ancestry),
             "exits" => exits,
             "records" => Enum.reverse(state.records),
             "open_spans" => open
           }}
        )

      _ ->
        loop(state)
    end
  end

  defp call(state, pid, mfa, at, fields) do
    {actor, state} = alias_pid(state, pid)

    if state.stopped or state.count >= @limit do
      stop_on_pressure(state)
    else
      id = state.next + 1

      state = %{
        state
        | next: id,
          stacks: Map.update(state.stacks, pid, [{mfa, id}], &[{mfa, id} | &1])
      }

      record(
        state,
        Map.merge(
          %{
            "event" => "call",
            "pid" => actor,
            "mfa" => format_mfa(mfa),
            "call_id" => id,
            "at_us" => micros(at)
          },
          fields
        )
      )
    end
  end

  defp ancestors(state, _pid, edges, 0), do: {edges, %{state | ancestry_overflow: true}}

  defp ancestors(state, pid, edges, remaining) do
    case state.parents[pid] do
      nil ->
        {edges, state}

      {parent, at} ->
        {child_name, state} = alias_pid(state, pid)
        {parent_name, state} = alias_pid(state, parent)
        row = %{"parent" => parent_name, "child" => child_name, "at_us" => micros(at)}
        ancestors(state, parent, [row | edges], remaining - 1)
    end
  end

  defp returned(state, pid, mfa, at, outcome) do
    {actor, state} = alias_pid(state, pid)

    {id, state} =
      case Map.get(state.stacks, pid, []) do
        [{^mfa, id} | rest] -> {id, %{state | stacks: Map.put(state.stacks, pid, rest)}}
        _ -> {nil, state}
      end

    record(state, %{
      "event" => "return",
      "pid" => actor,
      "mfa" => format_mfa(mfa),
      "call_id" => id,
      "at_us" => micros(at),
      "outcome" => outcome
    })
  end

  defp alias_pid(state, pid) do
    case state.aliases[pid] do
      nil when map_size(state.aliases) < @participants ->
        name = "p" <> Integer.to_string(map_size(state.aliases) + 1)
        {name, %{state | aliases: Map.put(state.aliases, pid, name)}}

      nil ->
        {"capacity", stop_on_pressure(state)}

      name ->
        {name, state}
    end
  end

  defp record(%{count: count} = state, row) when count < @limit,
    do: %{state | records: [row | state.records], count: count + 1}

  defp record(state, _), do: stop_on_pressure(state)
  defp stop_on_pressure(%{stopped: true} = state), do: state

  defp stop_on_pressure(state) do
    stop_calls(state.targets)
    %{state | truncated: true, stopped: true}
  end

  defp micros(at), do: System.convert_time_unit(at, :native, :microsecond)

  defp format_mfa({module, function, arity}),
    do:
      Atom.to_string(module) <> "." <> Atom.to_string(function) <> "/" <> Integer.to_string(arity)
end
