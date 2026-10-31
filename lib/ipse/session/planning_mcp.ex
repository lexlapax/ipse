defmodule Ipse.Session.PlanningMCP do
  @moduledoc "Replay binding for operator-declared MCP reads under planning ceilings."
  alias Ipse.{JSON, MCP.Planning}
  @error {:error, :invalid_planning_mcp_history}
  @keys ~w(call_id declaration_sha256 draft_id epoch_id session_id start_sha256 turn_id type version)
  @ordinary_keys ~w(call_id epoch_id session_id start_sha256 turn_id type version)
  @epoch_keys ~w(declaration_sha256 epoch_id execution_mode previous_epoch_id session_id startup type version)

  def intent(session, turn, draft, epoch_id, start, declaration) do
    %{
      "type" => "planning_mcp_read_intent",
      "version" => 1,
      "session_id" => session,
      "turn_id" => turn,
      "draft_id" => draft,
      "epoch_id" => epoch_id,
      "call_id" => start["call_id"],
      "start_sha256" => JSON.digest([start]),
      "declaration_sha256" => JSON.digest([declaration])
    }
  end

  def ordinary_intent(session, turn, epoch_id, start) do
    %{
      "type" => "mcp_epoch_intent",
      "version" => 1,
      "session_id" => session,
      "turn_id" => turn,
      "epoch_id" => epoch_id,
      "call_id" => start["call_id"],
      "start_sha256" => JSON.digest([start])
    }
  end

  def epoch(session, epoch_id, previous, startup, mode, reads) do
    %{
      "type" => "planning_mcp_epoch",
      "version" => 1,
      "session_id" => session,
      "epoch_id" => epoch_id,
      "previous_epoch_id" => previous,
      "startup" => startup,
      "execution_mode" => mode,
      "declaration_sha256" => JSON.digest([reads])
    }
  end

  def last_epoch(events) do
    Enum.find_value(Enum.reverse(events), fn event ->
      if event["type"] == "planning_mcp_epoch", do: event["epoch_id"]
    end)
  end

  def validate_events(events, nil) when is_list(events) do
    session =
      get_in(List.first(events) || %{}, ["metadata", "source_origin", "session_id"]) ||
        Enum.find_value(events, fn event ->
          if event["type"] in ~w(draft_started planning_mcp_read_intent planning_mcp_epoch mcp_epoch_intent),
            do: event["session_id"]
        end) || ""

    case events do
      [%{"metadata" => metadata} | _] when is_map(metadata) -> validate_events(events, session)
      _ -> validate_events([%{"metadata" => %{}} | events], session)
    end
  end

  def validate_events([%{"metadata" => metadata} | _] = events, session)
      when is_map(metadata) and is_binary(session) do
    reads = get_in(metadata, ["configuration", "planning_mcp_reads"]) || %{}
    mode = metadata["execution_mode"]

    protocol = metadata["planning_mcp_protocol"]

    if Ipse.Journal.validate_limit_events(events) == :ok and Planning.validate(reads) == :ok and
         ((reads == %{} and is_nil(protocol)) or (reads != %{} and protocol === 1)) do
      initial = %{
        draft: nil,
        draft_completed: false,
        pending: nil,
        pending_owner_changed: false,
        catalog: nil,
        request: nil,
        assistant: nil,
        mode: mode,
        base_mode: mode,
        startup_checkpoint: nil,
        protocol: protocol,
        release_layout: metadata["release_receipt_layout"],
        epoch: nil,
        epochs: MapSet.new(),
        started_calls: MapSet.new(),
        reads: reads,
        servers: Map.get(metadata, "mcp_servers", [])
      }

      Enum.reduce_while(tl(events), {:ok, initial}, fn event, {:ok, state} ->
        case step(state, event, session) do
          {:ok, next} -> {:cont, {:ok, next}}
          _ -> {:halt, @error}
        end
      end)
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    else
      @error
    end
  rescue
    _ -> @error
  end

  def validate_events(_, _), do: @error

  # The enclosing limit validator requires this receipt to be valid and final.
  # It authorizes no missing epoch, paired start, or subsequent dispatch.
  defp step(state, %{"type" => "journal_limit_reached"} = event, _) do
    if Ipse.Journal.valid_limit_receipt?(event), do: {:ok, state}, else: @error
  end

  # An owner marker grants no MCP authority and does not clear an unfinished
  # pre-start intent or mode checkpoint. The next epoch must still resolve it.
  defp step(state, %{"type" => "session_release_owner_started"} = event, session) do
    if state.release_layout == Ipse.Session.ReleaseReceipt.layout() and
         Ipse.Session.ReleaseReceipt.valid_owner_marker?(event, session),
       do: {:ok, %{state | pending_owner_changed: is_map(state.pending)}},
       else: @error
  end

  defp step(%{pending: pending} = state, %{"type" => "planning_mcp_epoch"} = event, session)
       when is_map(pending),
       do: step(%{state | pending: nil, pending_owner_changed: false}, event, session)

  defp step(%{pending: pending} = state, %{"type" => "execution_mode_resumed"} = event, session)
       when is_map(pending),
       do: step(%{state | pending: nil, pending_owner_changed: false}, event, session)

  defp step(%{pending: pending} = state, %{"type" => "tool_started"} = start, session)
       when is_map(pending) do
    valid =
      if state.pending_owner_changed do
        false
      else
        case pending["type"] do
          "planning_mcp_read_intent" -> valid_pair?(state, pending, start, session)
          "mcp_epoch_intent" -> valid_ordinary_pair?(state, pending, start, session)
          _ -> false
        end
      end

    if valid do
      key = {state.request["request_id"], pending["turn_id"], start["call_id"]}

      if MapSet.member?(state.started_calls, key),
        do: @error,
        else: {:ok, %{state | pending: nil, started_calls: MapSet.put(state.started_calls, key)}}
    else
      @error
    end
  end

  # A crash after the pre-start record cannot have dispatched this call. A new
  # lifecycle epoch discards it; replay never launches the recorded request.
  defp step(%{protocol: nil, pending: pending} = state, %{"type" => "lifecycle_epoch_started"}, _)
       when is_map(pending),
       do: {:ok, %{state | pending: nil}}

  defp step(%{pending: pending}, _, _) when is_map(pending), do: @error

  defp step(state, %{"type" => "planning_mcp_epoch"} = event, session) do
    mode = event["execution_mode"]

    if state.protocol === 1 and Enum.sort(Map.keys(event)) == @epoch_keys and
         event["version"] === 1 and event["session_id"] === session and id?(event["epoch_id"]) and
         event["previous_epoch_id"] === state.epoch and
         not MapSet.member?(state.epochs, event["epoch_id"]) and
         event["declaration_sha256"] === JSON.digest([state.reads]) and
         epoch_mode?(state, event["startup"], mode) do
      {:ok,
       %{
         state
         | epoch: event["epoch_id"],
           epochs: MapSet.put(state.epochs, event["epoch_id"]),
           mode: mode,
           base_mode: state.startup_checkpoint || state.base_mode,
           startup_checkpoint: nil
       }}
    else
      @error
    end
  end

  defp step(%{protocol: 1, epoch: nil}, _, _), do: @error

  defp step(%{protocol: 1} = state, %{"type" => "execution_mode_resumed", "mode" => mode}, _),
    do: {:ok, %{state | startup_checkpoint: mode}}

  defp step(%{protocol: 1} = state, %{"type" => "planning_exited", "mode" => mode}, _) do
    if transition_exit?(state, mode),
      do: {:ok, %{state | startup_checkpoint: mode}},
      else: @error
  end

  defp step(%{protocol: nil} = state, %{"type" => "planning_exited", "mode" => mode}, _) do
    if transition_exit?(state, mode),
      do: {:ok, %{state | mode: mode, base_mode: mode}},
      else: @error
  end

  defp step(
         %{protocol: nil} = state,
         %{"type" => "execution_mode_resumed", "mode" => mode} = event,
         _
       ) do
    if (event["version"] === 1 or event["version"] === 2) and
         Ipse.Extension.Mode.valid?(mode) and
         (is_nil(state.base_mode) or
            if(event["version"] === 1,
              do: Ipse.Extension.Mode.inherited?(state.base_mode, mode),
              else: event["version"] === 2 and Ipse.Extension.Mode.resumed?(state.base_mode, mode)
            )),
       do: {:ok, %{state | mode: mode, base_mode: mode}},
       else: @error
  end

  # The mode checkpoint is durable before its epoch. A crash can leave this
  # prefix, but no call or other work may be attributed to the preceding epoch.
  defp step(%{protocol: 1, startup_checkpoint: checkpoint}, _, _) when is_map(checkpoint),
    do: @error

  defp step(state, %{"type" => "mcp_catalog", "version" => 1, "tools" => tools}, _)
       when is_list(tools),
       do: {:ok, %{state | catalog: tools}}

  defp step(state, %{"type" => "request_admitted", "kind" => "model"} = request, _),
    do: {:ok, %{state | request: request, assistant: nil}}

  defp step(state, %{"type" => "message", "message" => %{"role" => "assistant"}} = event, _),
    do: {:ok, %{state | assistant: event}}

  defp step(state, %{"type" => "draft_started"} = event, _),
    do:
      {:ok,
       %{state | draft: Map.take(event, ~w(draft_id turn_id session_id)), draft_completed: false}}

  defp step(state, %{"type" => "draft_completed"}, _),
    do: {:ok, %{state | draft_completed: true}}

  defp step(state, %{"type" => type}, _)
       when type in ~w(draft_cancelled draft_consumed),
       do: {:ok, %{state | draft: nil, draft_completed: false, mode: state.base_mode}}

  defp step(state, %{"type" => "planning_mcp_read_intent"} = event, session) do
    if planning?(state) and Enum.sort(Map.keys(event)) == @keys and
         event["version"] === 1 and event["session_id"] === session and
         JSON.sha256?(event["start_sha256"]) and JSON.sha256?(event["declaration_sha256"]) and
         is_binary(event["call_id"]) and id?(event["turn_id"]) and
         event["epoch_id"] === state.epoch and id?(event["epoch_id"]) and
         event["draft_id"] === draft_id(state),
       do: {:ok, %{state | pending: event}},
       else: @error
  end

  defp step(state, %{"type" => "mcp_epoch_intent"} = event, session) do
    if state.protocol === 1 and not restricted?(state) and
         Ipse.Extension.Mode.valid?(state.mode) and state.mode["approval"] != "deny" and
         Enum.sort(Map.keys(event)) == @ordinary_keys and event["version"] === 1 and
         event["session_id"] === session and event["epoch_id"] === state.epoch and
         id?(event["epoch_id"]) and id?(event["turn_id"]) and is_binary(event["call_id"]) and
         JSON.sha256?(event["start_sha256"]),
       do: {:ok, %{state | pending: event}},
       else: @error
  end

  defp step(state, %{"type" => "tool_started"} = event, _) do
    if (state.protocol === 1 or restricted?(state)) and
         (Ipse.MCP.external?(event["name"]) or is_map(event["mcp"])),
       do: @error,
       else: {:ok, state}
  end

  defp step(state, _, _), do: {:ok, state}

  defp valid_pair?(state, intent, start, session) do
    manifest = start["mcp"]
    declaration = state.reads[start["name"]]

    is_map(manifest) and is_map(declaration) and valid_manifest?(state, manifest) and
      Enum.sort(Map.keys(start)) ==
        ~w(approval approval_source arguments call_id mcp name sandbox_requested type) and
      not Map.has_key?(manifest, "kind") and
      bound_call?(state, intent, start, session) and
      manifest in state.catalog and manifest["tool_id"] === start["name"] and
      manifest["server_id"] === declaration["server_id"] and
      manifest["name"] === declaration["tool"] and
      manifest["descriptor_sha256"] === declaration["descriptor_sha256"] and
      get_in(manifest, ["origin", "configured_endpoint_fingerprint"]) ===
        declaration["endpoint_sha256"] and
      start["approval"] ===
        if(state.mode["approval"] == "ask", do: "approved", else: "session_allow") and
      start["approval_source"] === start["approval"] and
      intent ===
        intent(session, intent["turn_id"], draft_id(state), state.epoch, start, declaration) and
      (is_nil(state.draft) or
         (state.draft["session_id"] === session and state.draft["turn_id"] === intent["turn_id"]))
  end

  defp valid_ordinary_pair?(state, intent, start, session) do
    manifest = start["mcp"]

    is_map(manifest) and valid_manifest?(state, manifest) and
      Enum.sort(Map.keys(start)) ==
        ~w(approval approval_source arguments call_id mcp name sandbox_requested type) and
      manifest["tool_id"] === start["name"] and
      start["approval"] ===
        if(state.mode["approval"] == "ask", do: "approved", else: "session_allow") and
      start["approval_source"] === start["approval"] and
      intent === ordinary_intent(session, intent["turn_id"], state.epoch, start) and
      bound_call?(state, intent, start, session)
  end

  defp valid_manifest?(state, manifest) do
    server = manifest["server_id"]
    origin = get_in(manifest, ["origin", "configured_endpoint_fingerprint"])

    expected =
      if is_binary(server) and Regex.match?(~r/\A[a-z][a-z0-9_]{0,23}\z/, server) do
        case {manifest["kind"], manifest["name"], manifest["source"]} do
          {nil, name, nil} when is_binary(name) ->
            Ipse.MCP.Config.tool_id(server, name)

          {"resource", name, source}
          when is_binary(name) and is_binary(source) and name == source ->
            Ipse.MCP.Config.resource_id(server, source)

          {"prompt", name, source}
          when is_binary(name) and is_binary(source) and name == source ->
            Ipse.MCP.Config.prompt_id(server, source)

          _ ->
            nil
        end
      end

    is_list(state.catalog) and is_list(state.servers) and manifest in state.catalog and
      JSON.sha256?(origin) and origin in state.servers and
      JSON.sha256?(manifest["descriptor_sha256"]) and manifest["tool_id"] === expected and
      is_binary(expected)
  end

  defp bound_call?(%{request: request, assistant: assistant}, intent, start, session)
       when is_map(request) and is_map(assistant) do
    calls = get_in(assistant, ["message", "tool_calls"])

    request["session_id"] === session and request["turn_id"] === intent["turn_id"] and
      assistant["request_id"] === request["request_id"] and is_list(calls) and
      Enum.count(calls, &(&1["id"] === start["call_id"])) == 1 and
      Enum.count(calls, fn call ->
        call["id"] === start["call_id"] and
          get_in(call, ["function", "name"]) === start["name"] and
          case JSON.decode_bounded(get_in(call, ["function", "arguments"])) do
            {:ok, arguments} -> arguments === start["arguments"]
            _ -> false
          end
      end) == 1
  end

  defp bound_call?(_, _, _, _), do: false

  defp planning?(%{draft_completed: true}), do: false

  defp planning?(%{mode: mode, draft: draft}) when is_map(mode),
    do:
      Ipse.Extension.Mode.valid?(mode) and mode["ceiling"] != "read_only" and
        mode["enclosing_ceiling"] != "read_only" and mode["approval"] != "deny" and
        (is_map(draft) or mode["ceiling"] == "planning" or
           mode["enclosing_ceiling"] == "planning")

  defp planning?(_), do: false
  defp restricted?(%{draft: draft}) when is_map(draft), do: true

  defp restricted?(%{mode: mode}) when is_map(mode),
    do: mode["ceiling"] != "normal" or mode["enclosing_ceiling"] != "normal"

  defp restricted?(_), do: false
  defp draft_id(%{draft: nil}), do: nil
  defp draft_id(%{draft: draft}), do: draft["draft_id"]
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  defp epoch_mode?(%{epoch: nil, base_mode: base}, "fresh", mode),
    do: Ipse.Extension.Mode.valid?(base) and mode === base

  defp epoch_mode?(%{startup_checkpoint: checkpoint, draft: draft}, "resume", mode)
       when is_map(checkpoint) do
    draft_mode =
      if is_map(draft) do
        checkpoint
        |> Ipse.Extension.Mode.config()
        |> Ipse.Session.Draft.draft_config()
        |> Ipse.Extension.Mode.capture()
      end

    mode === checkpoint or draft_mode === {:ok, mode}
  end

  defp epoch_mode?(%{base_mode: base}, "resume", mode) do
    Ipse.Extension.Mode.inherited?(base, mode) or Ipse.Extension.Mode.resumed?(base, mode)
  end

  defp epoch_mode?(_, _, _), do: false

  defp transition_exit?(state, mode) do
    is_nil(state.draft) and is_nil(state.startup_checkpoint) and
      Ipse.Extension.Mode.valid?(state.base_mode) and state.mode === state.base_mode and
      state.base_mode["ceiling"] == "planning" and
      mode === Map.put(state.base_mode, "ceiling", "normal")
  end
end
