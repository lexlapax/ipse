defmodule Ipse.Session.ManagedLineage do
  @moduledoc "Host-derived producer lineage; current eligibility belongs to a separate owned barrier."
  alias Ipse.{JSON, Session.ManagedReference}
  @error {:error, :managed_lineage_unavailable}
  defstruct [
    :reference,
    requests: %{},
    native_requests: %{},
    output_release: nil,
    output_release_ids: %{},
    output_layout: nil,
    calls: %{},
    call_bindings: %{},
    tool_effect_ids: %{},
    tool_effect_inputs: %{},
    tool_layout: nil,
    active_tool: nil,
    tool_result_release: nil,
    tool_result_ids: %{},
    invocations: %{},
    outputs: %{},
    publishers: %{},
    pending: %{},
    effects: %{},
    dictionary: %{},
    write_facts: %{},
    admissions: %{},
    preflight: nil,
    preflight_ids: %{},
    helper_inputs: %{},
    header: nil,
    active_invocation: nil,
    admission: nil,
    strict: false,
    frozen_header: false,
    unavailable: false
  ]

  def new(session) do
    with {:ok, reference} <- ManagedReference.new(session),
         do: {:ok, %__MODULE__{reference: reference}}
  end

  def dependencies(%__MODULE__{unavailable: false} = state, messages) do
    with {:ok, active} <- ManagedReference.dependencies(state.reference, messages) do
      publishers =
        if state.frozen_header,
          do: [],
          else: Enum.map(Map.keys(state.publishers), &lookup(state, :publishers, &1))

      ManagedReference.union([active | publishers])
    end
  end

  def dependencies(_, _), do: @error

  @doc false
  def staging_output?(
        %{output_release: %{intent: intent}},
        %{"type" => "extension_invocation_result"} = event
      ),
      do: intent["parent_invocation_id"] == event["invocation_id"]

  def staging_output?(_, _), do: false

  @doc false
  def released_output_message?(
        %{output_release: %{raw: raw, admission: admission, message_seen: false}},
        %{"type" => "message", "message" => message}
      )
      when is_map(raw) and is_map(admission),
      do:
        message ==
          Ipse.Session.ManagedOutput.tool_message(
            raw,
            admission["decision"],
            admission["write_facts"]
          )

  def released_output_message?(_, _), do: false

  @doc false
  def released_tool_message?(
        %{tool_result_release: %{observed: observed, admission: admission, message_seen: false}},
        %{"type" => "message", "message" => message}
      )
      when is_map(observed) and is_map(admission),
      do:
        message ==
          Ipse.Session.ManagedToolUse.result_message(observed["message"], admission["decision"])

  def released_tool_message?(_, _), do: false

  @doc "Consume only an event and message projection already committed and validated by their owning host."
  def advance(%__MODULE__{unavailable: true} = state, _, _, _), do: {:ok, state}

  def advance(%__MODULE__{} = state, event, before, after_messages) do
    with {:ok, state} <- inputs(state, event, before),
         {:ok, state} <- project_messages(state, event, before, after_messages) do
      {:ok, state}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    :throw, :managed_lineage_capacity -> {:ok, %{state | unavailable: true}}
    _, _ -> @error
  end

  def advance(_, _, _, _), do: @error

  @preflight_keys ~w(type version intent_id session_id turn_id request_id phase admission_sha256 input_sha256 tools_sha256 snapshot_sha256 before_sha256 dependencies_sha256 route_sha256 source_generation policy_generation checked_at_ms deadline_ms)

  @doc false
  def preflight_binding(intent) do
    intent
    |> Map.take(
      ~w(session_id turn_id request_id phase route_sha256 tools_sha256 source_generation policy_generation checked_at_ms deadline_ms)
    )
    |> Map.put("version", 1)
  end

  @doc false
  def preflight_dependencies(state, phase, messages) do
    with {:ok, active} <- dependencies(state, messages),
         {:ok, inherited} <- invocation_dependencies(state, state.active_invocation) do
      ManagedReference.union([active, if(phase in ~w(model compaction), do: [], else: inherited)])
    end
  end

  @doc "Replay an owner-committed projection against its earlier independently admitted intent."
  def replay_projection(%__MODULE__{preflight: intent} = state, event, messages)
      when is_map(intent) do
    with true <- Enum.sort(Map.keys(event)) == ~w(intent_id projection type verdicts version),
         true <- event["type"] == "managed_preflight_result" and event["version"] === 1,
         true <- event["intent_id"] === intent["intent_id"],
         true <- valid_preflight?(state, intent, messages),
         {:ok, dependencies} <- preflight_dependencies(state, intent["phase"], messages),
         binding = preflight_binding(intent) do
      case intent["phase"] do
        phase when phase in ~w(model compaction) ->
          with true <- is_nil(event["verdicts"]),
               {:ok, projected} <-
                 ManagedReference.replay(
                   state.reference,
                   messages,
                   event["projection"],
                   binding,
                   state.write_facts
                 ),
               true <- phase != "compaction" or projected.messages === messages,
               next = %{state | reference: projected.state, preflight: nil},
               {:ok, active} <- dependencies(next, projected.messages),
               {:ok, next} <- put_refs(next, :requests, intent["request_id"], active) do
            {:ok, projected.messages, next}
          else
            _ -> @error
          end

        _ ->
          with true <- is_nil(event["projection"]),
               {:ok, _} <- ManagedReference.refresh(dependencies, event["verdicts"], binding) do
            {:ok, messages, %{state | preflight: nil}}
          else
            _ -> @error
          end
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def replay_projection(_, _, _), do: @error

  defp valid_preflight?(state, event, messages) do
    admission = state.admissions[event["request_id"]]
    operation = if event["phase"] in ~w(model compaction), do: "main", else: event["phase"]
    routes = get_in(state.admission || %{}, ["policy", "settings", "routes"]) || []

    with true <- Enum.sort(Map.keys(event)) == Enum.sort(@preflight_keys),
         true <- event["type"] == "managed_preflight_intent" and event["version"] === 1,
         true <- is_map(admission) and not is_nil(Ipse.Usage.operation(admission)),
         true <- event["session_id"] == state.reference.session_id,
         true <- event["turn_id"] == admission["turn_id"],
         true <- event["admission_sha256"] == JSON.digest([admission]),
         true <- event["before_sha256"] == JSON.digest(messages),
         true <- Regex.match?(~r/\A[0-9a-f]{32}\z/, event["intent_id"]),
         true <-
           event["phase"] in ~w(model compaction model.complete embedding.create decision.create),
         true <-
           Enum.all?(
             ~w(input_sha256 tools_sha256 snapshot_sha256 route_sha256),
             &JSON.sha256?(event[&1])
           ),
         true <-
           Enum.all?(
             ~w(source_generation policy_generation checked_at_ms deadline_ms),
             &JSON.safe_uint?(event[&1])
           ),
         true <- event["policy_generation"] == get_in(state.admission, ["pin", "epoch"]),
         true <- event["checked_at_ms"] >= admission["admitted_at_ms"],
         true <-
           event["deadline_ms"] >= event["checked_at_ms"] and
             event["deadline_ms"] - event["checked_at_ms"] <= 120_000,
         true <-
           Enum.any?(routes, fn route ->
             route["operation"] == operation and
               route["profile"] ==
                 Ipse.Session.InferenceDispatch.profile(event["phase"], admission) and
               route["provider"] == admission["provider"] and route["model"] == admission["model"] and
               route["billing_mode"] == admission["billing_mode"] and
               JSON.digest([route]) == event["route_sha256"]
           end),
         {:ok, deps} <- preflight_dependencies(state, event["phase"], messages),
         true <- deps != [] and event["dependencies_sha256"] == JSON.digest(deps),
         true <- preflight_input?(state, event, messages, deps) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp preflight_input?(state, %{"phase" => "model"} = event, messages, deps) do
    is_list(state.header) and
      event["input_sha256"] == JSON.digest([state.header ++ messages]) and
      event["snapshot_sha256"] == JSON.digest(["model", state.header ++ messages, deps])
  end

  defp preflight_input?(_, %{"phase" => "compaction"}, _, _), do: true

  defp preflight_input?(state, event, _, deps) do
    case Map.fetch(state.helper_inputs, event["request_id"]) do
      {:ok, input} ->
        event["input_sha256"] == JSON.digest([input]) and
          event["tools_sha256"] == JSON.digest([[]]) and
          event["snapshot_sha256"] == JSON.digest([event["phase"], input, deps])

      _ ->
        false
    end
  end

  defp inputs(state, %{"type" => "session", "metadata" => metadata}, _) do
    {:ok, output_layout} = Ipse.Session.ManagedOutput.marker(metadata)
    {:ok, tool_layout} = Ipse.Session.ManagedToolUse.marker(metadata)

    {:ok,
     %{
       state
       | admission: metadata["semantic_admission"],
         output_layout: output_layout,
         tool_layout: tool_layout,
         strict: metadata["managed_read_layout"] == Ipse.Session.ManagedReads.layout(),
         frozen_header: metadata["reference_layout"] == Ipse.Session.Reference.layout()
     }}
  end

  defp inputs(state, %{"type" => "tool_started"} = event, _) do
    {:ok, %{state | active_tool: event}}
  end

  defp inputs(state, %{"type" => "managed_tool_effect_admitted"} = event, _) do
    with true <- state.tool_layout == Ipse.Session.ManagedToolUse.layout(),
         false <- Map.has_key?(state.tool_effect_ids, event["effect_id"]),
         key =
           Ipse.Session.ManagedToolUse.effect_key(
             event["input_sha256"],
             get_in(event, ["binding", "kind"])
           ),
         false <- Map.has_key?(state.tool_effect_inputs, key),
         true <-
           get_in(event, ["binding", "kind"]) != "mcp.send" or
             match?(
               %{cleanup: "confirmed"},
               state.tool_effect_inputs[
                 Ipse.Session.ManagedToolUse.effect_key(event["input_sha256"], "mcp.start")
               ]
             ),
         %{call: _} = binding <- state.call_bindings[event["call_id"]],
         {:ok, dependencies} <- tool_dependencies(state, event["call_id"]),
         true <-
           Ipse.Session.ManagedToolUse.valid_record?(
             event,
             state.reference.session_id,
             binding,
             state.active_tool,
             dependencies
           ) do
      {:ok,
       checked(%{
         state
         | tool_effect_ids: Map.put(state.tool_effect_ids, event["effect_id"], key),
           tool_effect_inputs:
             Map.put(state.tool_effect_inputs, key, %{
               id: event["effect_id"],
               sha256: JSON.digest([event]),
               cleanup: nil
             })
       })}
    else
      _ -> @error
    end
  end

  defp inputs(state, %{"type" => "managed_tool_effect_cleanup"} = event, _) do
    with key when is_binary(key) <- state.tool_effect_ids[event["effect_id"]],
         %{cleanup: nil} = pending <- state.tool_effect_inputs[key],
         true <-
           Ipse.Session.ManagedToolUse.valid_effect_cleanup?(event, pending.id, pending.sha256) do
      {:ok,
       %{
         state
         | tool_effect_inputs:
             Map.put(state.tool_effect_inputs, key, %{pending | cleanup: event["status"]})
       }}
    else
      _ -> @error
    end
  end

  defp inputs(state, %{"type" => "managed_tool_result_observed"} = event, _) do
    with true <- state.tool_layout == Ipse.Session.ManagedToolUse.layout(),
         true <- is_nil(state.tool_result_release),
         false <- Map.has_key?(state.tool_result_ids, event["result_id"]),
         %{call: _} = binding <- state.call_bindings[event["call_id"]],
         {:ok, deps} <- tool_dependencies(state, event["call_id"]),
         true <-
           Ipse.Session.ManagedToolUse.valid_observed?(
             event,
             state.reference.session_id,
             binding,
             state.active_tool,
             deps
           ) do
      {:ok,
       checked(%{
         state
         | tool_result_release: %{observed: event, admission: nil, message_seen: false},
           tool_result_ids: Map.put(state.tool_result_ids, event["result_id"], true)
       })}
    else
      _ -> @error
    end
  end

  defp inputs(state, %{"type" => "managed_tool_result_release"} = event, _) do
    with p when is_map(p) <- state.tool_result_release,
         true <-
           is_nil(p.admission) and Ipse.Session.ManagedToolUse.valid_release?(event, p.observed) do
      {:ok, %{state | tool_result_release: %{p | admission: event}}}
    else
      _ -> @error
    end
  end

  defp inputs(state, %{"type" => "managed_tool_result_cleanup"} = event, _) do
    with p when is_map(p) <- state.tool_result_release,
         true <- is_map(p.admission) and (event["status"] == "unknown" or p.message_seen),
         true <- Ipse.Session.ManagedToolUse.valid_result_cleanup?(event, p.observed, p.admission) do
      {:ok,
       %{
         state
         | tool_result_release: nil,
           unavailable: state.unavailable or event["status"] == "unknown"
       }}
    else
      _ -> @error
    end
  end

  defp inputs(
         %{tool_result_release: %{admission: admission} = pending} = state,
         %{"type" => "message", "message" => %{"role" => "tool"} = message},
         _
       )
       when is_map(admission) do
    if not pending.message_seen and
         message ==
           Ipse.Session.ManagedToolUse.result_message(
             pending.observed["message"],
             admission["decision"]
           ),
       do: {:ok, %{state | tool_result_release: %{pending | message_seen: true}}},
       else: @error
  end

  defp inputs(state, %{"type" => "request_admitted", "request_id" => id} = event, messages) do
    with true <- is_nil(state.output_release) and is_nil(state.tool_result_release),
         {:ok, deps} <- dependencies(state, messages),
         {:ok, inherited} <- invocation_dependencies(state, state.active_invocation),
         {:ok, deps} <- ManagedReference.union([deps, inherited]) do
      with {:ok, next} <- put_refs(state, :requests, id, deps) do
        {:ok, checked(%{next | admissions: Map.put(next.admissions, id, event)})}
      end
    end
  end

  defp inputs(state, %{"type" => "request_finished", "request_id" => id}, _),
    do:
      {:ok,
       %{
         state
         | admissions: Map.delete(state.admissions, id),
           helper_inputs: Map.delete(state.helper_inputs, id)
       }}

  defp inputs(state, %{"type" => "inference_dispatch_intent"} = event, _) do
    admission = state.admissions[event["request_id"]]
    routes = get_in(state.admission || %{}, ["policy", "settings", "routes"]) || []

    bound =
      Enum.find(routes, fn route ->
        is_map(admission) and admission["provider"] == "ollama" and
          event["phase"] == "model" and admission["kind"] == "model" and
          event["session_id"] == state.reference.session_id and
          event["admission_sha256"] == JSON.digest([admission]) and
          route["operation"] == "main" and is_nil(route["profile"]) and
          route["provider"] == admission["provider"] and route["model"] == admission["model"] and
          route["billing_mode"] == admission["billing_mode"] and
          JSON.digest([route]) == event["route_sha256"]
      end)

    if bound do
      value = %{
        "provider" => bound["provider"],
        "model" => bound["model"],
        "admission_sha256" => event["admission_sha256"],
        "route_sha256" => event["route_sha256"]
      }

      {:ok,
       checked(%{
         state
         | native_requests: Map.put(state.native_requests, event["request_id"], value)
       })}
    else
      {:ok, state}
    end
  end

  defp inputs(state, %{"type" => "reference_admitted", "header" => header}, _),
    do: {:ok, %{state | header: header}}

  defp inputs(state, %{"type" => "managed_recovery"}, _),
    do:
      {:ok,
       %{
         state
         | preflight: nil,
           admissions: %{},
           helper_inputs: %{},
           unavailable:
             state.unavailable or state.output_release != nil or state.tool_result_release != nil or
               Enum.any?(state.tool_effect_inputs, fn {_, value} ->
                 value.cleanup != "confirmed"
               end)
       }}

  defp inputs(state, %{"type" => "managed_preflight_intent"} = event, messages) do
    with true <- is_nil(state.preflight),
         false <- Map.has_key?(state.preflight_ids, event["intent_id"]),
         true <- valid_preflight?(state, event, messages) do
      {:ok,
       checked(%{
         state
         | preflight: event,
           preflight_ids: Map.put(state.preflight_ids, event["intent_id"], true)
       })}
    else
      _ -> @error
    end
  end

  defp inputs(state, %{"type" => "managed_preflight_refused"} = event, _) do
    if Enum.sort(Map.keys(event)) == ~w(intent_id type version) and event["version"] === 1 and
         is_map(state.preflight) and state.preflight["intent_id"] === event["intent_id"],
       do: {:ok, %{state | preflight: nil}},
       else: @error
  end

  defp inputs(state, %{"type" => "extension_invocation_intent"} = event, messages) do
    inherited =
      case event["descriptor"]["stage"] do
        "invoke.command" ->
          {:ok, []}

        "invoke.tool" ->
          ManagedReference.union([
            lookup(state, :calls, event["parent_call_id"]),
            lookup(state, :requests, event["parent_request_id"])
          ])

        "event.job" ->
          if get_in(event, ["payload", "arguments", "event", "event", "view"]) == "metadata",
            do: {:ok, []},
            else: dependencies(state, messages)

        _ ->
          dependencies(state, messages)
      end

    with {:ok, deps} <- inherited do
      {state, refs} = pack(state, deps)
      entry = %{input: refs, reads: [], instance: event["identity"]["instance"], parent: event}

      {:ok,
       checked(%{
         state
         | invocations: Map.put(state.invocations, event["invocation_id"], entry),
           active_invocation: event["invocation_id"]
       })}
    end
  end

  defp inputs(state, %{"type" => "managed_read_observed"} = event, _),
    do: put_refs(state, :pending, event["operation_id"], event["dependencies"])

  defp inputs(
         state,
         %{"type" => "extension_action_intent", "request" => %{"op" => "context.publish"}} = event,
         _
       ) do
    instance = get_in(state.invocations, [event["parent_invocation_id"], :instance])
    {:ok, %{state | publishers: Map.delete(state.publishers, instance)}}
  end

  defp inputs(state, %{"type" => "extension_action_intent", "request" => request} = event, _) do
    if Ipse.Extension.Actions.inference?(request) do
      input =
        if request["op"] == "model.complete",
          do: Ipse.Session.Context.helper_messages(request["instruction"], request["input"]),
          else: request

      {:ok,
       checked(%{
         state
         | helper_inputs: Map.put(state.helper_inputs, event["operation_id"], input)
       })}
    else
      {:ok, state}
    end
  end

  defp inputs(state, %{"type" => "extension_action_result"} = event, _) do
    id = event["parent_invocation_id"]
    entry = Map.get(state.invocations, id, %{input: [], reads: [], instance: nil, parent: nil})

    reads =
      if event["outcome"]["status"] == "ok",
        do: lookup(state, :pending, event["operation_id"]),
        else: []

    source =
      if event["request"]["op"] == "source.read" and event["outcome"]["status"] == "ok",
        do: source_dependencies(state, event["outcome"]["value"]),
        else: []

    legacy =
      not state.strict and event["outcome"]["status"] == "ok" and
        Ipse.Session.ManagedReads.managed_mapping?(
          state.admission,
          entry.parent,
          Ipse.Extension.Actions.result_intent(event)
        ) and not Map.has_key?(state.pending, event["operation_id"])

    with {:ok, reads} <- ManagedReference.union([decode(state, entry.reads), reads, source]),
         {state, refs} = pack(state, reads),
         entry = %{entry | reads: refs},
         state = %{
           state
           | invocations: Map.put(state.invocations, id, entry),
             unavailable: legacy,
             pending: Map.delete(state.pending, event["operation_id"]),
             helper_inputs: Map.delete(state.helper_inputs, event["operation_id"])
         },
         {:ok, deps} <- invocation_dependencies(state, id) do
      state =
        if event["outcome"]["status"] == "ok" do
          {:ok, state} = put_refs(state, :effects, event["operation_id"], deps)

          if event["request"]["op"] == "context.publish" do
            {:ok, state} = put_refs(state, :publishers, entry.instance, deps)
            state
          else
            state
          end
        else
          state
        end

      {:ok, historical_write(state, event)}
    end
  end

  defp inputs(state, %{"type" => "extension_invocation_result"} = event, _) do
    id = event["invocation_id"]

    with {:ok, deps} <- invocation_dependencies(state, id),
         true <- not (state.output_layout != nil and deps != [] and is_nil(state.output_release)),
         true <-
           is_nil(state.output_release) or
             Ipse.Session.ManagedOutput.bound_result?(state.output_release.intent, event) do
      {:ok, state} = put_refs(state, :outputs, id, deps)

      state =
        if get_in(event, ["delivery", "output_id"]) do
          {:ok, state} = put_refs(state, :outputs, event["delivery"]["output_id"], deps)
          state
        else
          state
        end

      release = if state.output_release, do: %{state.output_release | raw: event}, else: nil

      {:ok,
       %{
         state
         | invocations: Map.delete(state.invocations, id),
           active_invocation: nil,
           output_release: release
       }}
    end
  end

  defp inputs(state, %{"type" => "managed_output_release_intent"} = event, _) do
    id = event["parent_invocation_id"]

    with true <- is_nil(state.output_release),
         false <- Map.has_key?(state.output_release_ids, event["release_id"]),
         entry when is_map(entry) <- state.invocations[id],
         {:ok, deps} <- invocation_dependencies(state, id),
         true <- deps != [],
         true <-
           Ipse.Session.ManagedOutput.valid_intent?(
             event,
             state.reference.session_id,
             entry.parent,
             event["actions_sha256"],
             deps
           ) do
      {:ok,
       checked(%{
         state
         | output_release: %{intent: event, raw: nil, admission: nil, message_seen: false},
           output_release_ids: Map.put(state.output_release_ids, event["release_id"], true)
       })}
    else
      _ -> @error
    end
  end

  defp inputs(state, %{"type" => "managed_output_release_result"} = event, _) do
    with release when is_map(release) <- state.output_release,
         true <- is_map(release.raw) and is_nil(release.admission),
         facts = Map.get(state.write_facts, release.raw["invocation_id"], []),
         true <-
           Ipse.Session.ManagedOutput.valid_admission?(event, release.intent, release.raw, facts) do
      publishers =
        if event["decision"] == "current",
          do: state.publishers,
          else: Map.delete(state.publishers, release.raw["identity"]["instance"])

      {:ok, %{state | output_release: %{release | admission: event}, publishers: publishers}}
    else
      _ -> @error
    end
  end

  defp inputs(state, %{"type" => "managed_output_release_cleanup"} = event, _) do
    with release when is_map(release) <- state.output_release,
         true <- is_map(release.admission),
         true <-
           event["status"] == "unknown" or
             release.raw["descriptor"]["stage"] != "invoke.tool" or release.message_seen,
         true <-
           Ipse.Session.ManagedOutput.valid_cleanup?(event, release.intent, release.admission) do
      {:ok,
       %{
         state
         | output_release: nil,
           unavailable: state.unavailable or event["status"] == "unknown"
       }}
    else
      _ -> @error
    end
  end

  defp inputs(
         %{output_release: %{admission: admission} = release} = state,
         %{"type" => "message", "message" => %{"role" => "tool"} = message},
         _
       )
       when is_map(admission) do
    if not release.message_seen and
         message ==
           Ipse.Session.ManagedOutput.tool_message(
             release.raw,
             admission["decision"],
             admission["write_facts"]
           ), do: {:ok, %{state | output_release: %{release | message_seen: true}}}, else: @error
  end

  defp inputs(state, %{"type" => type}, _) when type in ~w(cancelled turn_finished),
    do: {:ok, %{state | active_invocation: nil, pending: %{}, preflight: nil, admissions: %{}}}

  defp inputs(state, _, _), do: {:ok, state}

  defp project_messages(%{unavailable: true} = state, _, _, _), do: {:ok, state}
  defp project_messages(state, _, before, before), do: {:ok, state}

  defp project_messages(state, event, before, after_messages) do
    if Enum.take(after_messages, length(before)) == before do
      after_messages
      |> Enum.drop(length(before))
      |> Enum.with_index(length(before))
      |> Enum.reduce_while({:ok, state}, fn {message, position}, {:ok, current} ->
        with {:ok, deps, producer} <- producer(current, event, message, before),
             {:ok, current} <- admit(current, producer, position, message, deps) do
          calls = if message["role"] == "assistant", do: message["tool_calls"] || [], else: []

          current =
            Enum.reduce(calls, current, fn call, next ->
              extra =
                if get_in(call, ["function", "name"]) == "saved_result_read" do
                  case JSON.decode_bounded(get_in(call, ["function", "arguments"]), 16_384) do
                    {:ok, args} ->
                      lookup(next, :outputs, Ipse.Extension.ResultSource.request_output_id(args))

                    _ ->
                      []
                  end
                else
                  []
                end

              {:ok, inherited} = ManagedReference.union([deps, extra])
              {:ok, next} = put_refs(next, :calls, call["id"], inherited)

              bindings =
                if inherited == [],
                  do: Map.delete(next.call_bindings, call["id"]),
                  else:
                    Map.put(next.call_bindings, call["id"], %{
                      call: call,
                      request_id: event["request_id"]
                    })

              checked(%{next | call_bindings: bindings})
            end)

          {:cont, {:ok, current}}
        else
          _ -> {:halt, @error}
        end
      end)
    else
      with {:ok, deps} <- dependencies(state, before),
           producer = producer_id("checkpoint", event),
           {:ok, reference} <-
             ManagedReference.rebuild_projection(
               state.reference,
               before,
               after_messages,
               producer,
               deps
             ) do
        {:ok, %{state | reference: reference}}
      end
    end
  end

  defp producer(state, event, %{"role" => "assistant"} = message, before) do
    with {:ok, fallback} <- dependencies(state, before) do
      native = state.native_requests[event["request_id"]]

      producer =
        if is_map(native) and native["provider"] == "ollama" and
             Ipse.Session.DraftNative.plain_text_only?(message) and
             get_in(message, ["provider_data", "reported_model"]) in [nil, native["model"]] do
          %{
            "kind" => "assistant.ollama_text",
            "id" => JSON.digest([event, native]),
            "parent_id" => event["request_id"]
          }
        else
          producer_id("assistant", event)
        end

      {:ok,
       if(Map.has_key?(state.requests, event["request_id"]),
         do: lookup(state, :requests, event["request_id"]),
         else: fallback
       ), producer}
    end
  end

  defp producer(
         %{output_release: %{raw: raw, admission: %{"decision" => decision}}},
         _,
         %{"role" => "tool"},
         _
       )
       when decision != "current",
       do:
         {:ok, [],
          %{"kind" => "collection.result", "id" => raw["invocation_id"], "parent_id" => nil}}

  defp producer(state, event, %{"role" => "tool"} = message, _) do
    id = get_in(message, ["ipse_extension_result", "invocation_id"]) || event["invocation_id"]

    content =
      case JSON.decode_bounded(message["content"], 16_384) do
        {:ok, value} when is_map(value) -> source_dependencies(state, value)
        _ -> []
      end

    with {:ok, deps} <-
           ManagedReference.union([
             lookup(state, :outputs, id),
             lookup(state, :calls, message["tool_call_id"]),
             content
           ]) do
      producer =
        if is_binary(id),
          do: %{"kind" => "collection.result", "id" => id, "parent_id" => nil},
          else: producer_id("collection.result", event)

      {:ok, deps, producer}
    end
  end

  defp producer(state, %{"type" => "reference_envelope"} = event, _, _) do
    with {:ok, selected} <- Ipse.Session.Reference.selected_publishers(event) do
      groups =
        if Map.has_key?(selected, "extensions"),
          do: Enum.map(Map.keys(state.publishers), &lookup(state, :publishers, &1)),
          else: []

      with {:ok, deps} <- ManagedReference.union(groups),
           do: {:ok, deps, producer_id("reference", event)}
    end
  end

  defp producer(_, event, _, _), do: {:ok, [], producer_id("reference", event)}

  defp admit(state, _, _, _, []), do: {:ok, state}

  defp admit(state, producer, position, message, deps) do
    case ManagedReference.admit(state.reference, producer, position, message, deps) do
      {:ok, _, reference} -> {:ok, %{state | reference: reference}}
      _ -> @error
    end
  end

  defp producer_id(kind, event),
    do: %{
      "kind" => kind,
      "id" => JSON.digest([event]),
      "parent_id" => event["invocation_id"] || event["parent_invocation_id"]
    }

  defp source_dependencies(state, value) do
    provenance = if is_map(value["provenance"]), do: value["provenance"], else: %{}

    groups = [
      lookup(state, :requests, provenance["request_id"]),
      lookup(state, :outputs, provenance["invocation_id"]),
      lookup(state, :effects, provenance["operation_id"]),
      lookup(state, :outputs, value["output_id"])
    ]

    case ManagedReference.union(groups) do
      {:ok, deps} -> deps
      _ -> throw(:managed_source_lineage_refused)
    end
  end

  @doc false
  def tool_dependencies(%__MODULE__{unavailable: false} = state, id),
    do: ManagedReference.union([lookup(state, :calls, id)])

  def tool_dependencies(_, _), do: @error

  def invocation_dependencies(_, nil), do: {:ok, []}

  def invocation_dependencies(state, id) do
    case state.invocations[id] do
      %{input: input, reads: reads} ->
        ManagedReference.union([decode(state, input), decode(state, reads)])

      _ ->
        {:ok, []}
    end
  end

  defp lookup(state, field, id), do: decode(state, Map.get(Map.fetch!(state, field), id, []))
  defp decode(state, refs), do: Enum.map(refs, &Map.fetch!(state.dictionary, &1))

  defp pack(state, deps) do
    case ManagedReference.union([Map.values(state.dictionary), deps]) do
      {:ok, all} ->
        dictionary = Map.new(all, &{JSON.digest([&1]), &1})
        {%{state | dictionary: dictionary}, Enum.map(deps, &JSON.digest([&1]))}

      _ ->
        throw(:managed_lineage_capacity)
    end
  end

  defp put_refs(state, field, id, deps) do
    {state, refs} = pack(state, deps)

    values =
      if refs == [],
        do: Map.delete(Map.fetch!(state, field), id),
        else: Map.put(Map.fetch!(state, field), id, refs)

    {:ok, checked(Map.put(state, field, values))}
  end

  defp checked(state) do
    fields =
      ~w(requests native_requests output_release_ids calls call_bindings tool_effect_ids tool_effect_inputs tool_result_ids invocations outputs publishers pending effects admissions preflight_ids write_facts helper_inputs)a

    maps = Map.take(Map.from_struct(state), fields)

    if Enum.all?(maps, fn {_, value} -> map_size(value) <= 2048 end) and
         byte_size(Jason.encode!(maps)) <= 4_194_304 do
      state
    else
      throw(:managed_lineage_capacity)
    end
  end

  defp historical_write(state, event) do
    if get_in(event, ["request", "op"]) == "collection.managed" and
         get_in(event, ["outcome", "status"]) == "ok" and
         Ipse.Extension.ManagedCollectionCall.bound_outcome?(event) do
      value = event["outcome"]["value"]

      fact = %{
        "operation_id" => event["operation_id"],
        "action_sha256" => JSON.digest([event]),
        "normalization_sha256" => JSON.digest([value["normalization"]]),
        "receipt_sha256" => JSON.digest([value["receipt"]]),
        "generation" => value["receipt"]["generation"],
        "record_key" => value["normalization"]["record_key"],
        "category" => value["normalization"]["category"]
      }

      facts = Map.get(state.write_facts, event["parent_invocation_id"], []) ++ [fact]
      if length(facts) > 128, do: throw(:managed_lineage_capacity)

      checked(%{
        state
        | write_facts: Map.put(state.write_facts, event["parent_invocation_id"], facts)
      })
    else
      state
    end
  end
end
