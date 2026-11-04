defmodule Ipse.Session.WorkspaceAcquisition do
  @moduledoc false

  # Private projection of confirmed action results. This does not authorize a
  # file read, a staged value, or a publication; consumers must bind those to
  # their live Session and Collection owners.
  alias Ipse.Extension.WorkspaceSnapshot
  alias Ipse.JSON

  @limit 16
  @operation_limit 8_192
  @derive {Inspect, only: [:refused]}
  defstruct metadata: nil,
            cwd: nil,
            identities: %{},
            catalog: [],
            active: %{},
            completed: %{},
            legacy: %{},
            pending: nil,
            seen: MapSet.new(),
            refused: false

  def new(metadata) when is_map(metadata) do
    with cwd when is_binary(cwd) <- metadata["cwd"],
         {:ok, catalog} <- Ipse.Extension.Catalog.from_metadata(metadata) do
      %__MODULE__{
        metadata: metadata,
        cwd: cwd,
        identities: Map.new(metadata["extensions"] || [], &{&1["instance"], &1}),
        catalog: catalog["entries"]
      }
    else
      _ -> %__MODULE__{refused: true}
    end
  end

  def new(_), do: %__MODULE__{refused: true}

  def advance(%__MODULE__{} = state, event, parent, session, origin) do
    request = event["request"]

    cond do
      event["type"] === "extension_action_intent" and acquisition_request?(request) ->
        admit_intent(state, event, parent, session, origin)

      event["type"] === "extension_action_result" and acquisition_request?(request) ->
        accept_result(state, event, parent, session, origin)

      event["type"] in ~w(cancelled turn_finished) ->
        %{state | active: %{}, legacy: %{}, pending: nil}

      event["type"] === "extension_invocation_result" ->
        state
        |> bind_continuation(event, parent, session)
        |> settle_completed(event, parent, session)
        |> Map.put(:active, %{})
        |> Map.update!(:legacy, &Map.delete(&1, event["invocation_id"]))
        |> Map.put(:pending, nil)

      true ->
        state
    end
  rescue
    _ -> %{state | active: %{}, pending: nil, refused: true}
  end

  def advance(state, _, _, _, _), do: state

  defp admit_intent(state, event, parent, session, origin) do
    id = event["operation_id"]

    with false <- state.refused,
         true <- is_nil(state.pending),
         true <- MapSet.size(state.seen) < @operation_limit,
         false <- MapSet.member?(state.seen, id),
         true <- JSON.sha256?(origin),
         true <- parent?(state, parent, event, session),
         true <- Ipse.Extension.Actions.valid_intent?(event, parent, state.cwd) do
      %{state | pending: event, seen: MapSet.put(state.seen, id)}
    else
      _ -> %{state | active: %{}, pending: nil, refused: true}
    end
  end

  defp accept_result(state, event, parent, session, origin) do
    request = event["request"]

    with false <- state.refused,
         pending when is_map(pending) <- state.pending,
         true <- Ipse.Extension.Actions.result_intent(event) === pending,
         true <- Ipse.Extension.Actions.valid_result?(event),
         true <- parent?(state, parent, event, session),
         true <- JSON.sha256?(origin) do
      state = %{state | pending: nil}

      kind = if legacy_read?(request), do: "legacy", else: request["arguments"]["snapshot"]

      case {event["outcome"], kind} do
        {%{"status" => "ok", "value" => %{"text" => text}}, "start"} ->
          start(state, event, parent, session, origin, text)

        {%{"status" => "ok", "value" => %{"text" => text}}, "page"} ->
          page(state, event, parent, session, origin, text)

        {%{"status" => "ok", "value" => %{"text" => text}}, "legacy"} ->
          legacy(state, event, parent, session, origin, text)

        _ ->
          invalidate(state, request, event)
      end
    else
      _ -> %{state | active: %{}, pending: nil, refused: true}
    end
  end

  def lookup(%__MODULE__{refused: false} = state, operation, session, origin, identity) do
    case state.completed[operation] do
      %{"session_id" => ^session, "origin_sha256" => ^origin, "identity_sha256" => ^identity} =
          receipt ->
        {:ok, receipt}

      _ ->
        {:error, :workspace_acquisition_unavailable}
    end
  end

  def lookup(_, _, _, _, _), do: {:error, :workspace_acquisition_unavailable}

  def legacy_lookup(
        %__MODULE__{refused: false} = state,
        parent,
        session,
        origin,
        identity,
        path,
        sha
      ) do
    case state.legacy[parent] do
      %{
        "session_id" => ^session,
        "origin_sha256" => ^origin,
        "identity_sha256" => ^identity,
        "path" => ^path,
        "sha256" => ^sha
      } = receipt ->
        {:ok, receipt}

      _ ->
        {:error, :workspace_acquisition_unavailable}
    end
  end

  def legacy_lookup(_, _, _, _, _, _, _), do: {:error, :workspace_acquisition_unavailable}

  defp acquisition_request?(request),
    do: WorkspaceSnapshot.retained_request?(request) or legacy_read?(request)

  defp legacy_read?(request) when is_map(request) do
    args = request["arguments"]

    is_map(args) and Enum.sort(Map.keys(request)) == ~w(arguments name op timeout_ms) and
      request["op"] === "tool.call" and request["name"] === "read" and
      request["timeout_ms"] === 5_000 and
      Enum.sort(Map.keys(args)) ==
        ~w(byte_offset encoding expected_sha256 file_max_bytes max_bytes path) and
      args["encoding"] === "base64" and args["byte_offset"] === 0 and
      args["max_bytes"] === 4096 and args["file_max_bytes"] === 32_768 and
      JSON.sha256?(args["expected_sha256"]) and
      Ipse.Extension.ToolAction.validate(request) === :ok
  rescue
    _ -> false
  end

  defp legacy_read?(_), do: false

  defp legacy(state, event, parent, session, origin, text) do
    request = event["request"]

    with true <- parent?(state, parent, event, session),
         true <- Ipse.Tools.binary_read_result?(text, request["arguments"]),
         {:ok, value} <- JSON.decode_bounded(text, 8192),
         count when is_integer(count) and count in 1..32_768 <- value["byte_count"],
         true <-
           map_size(state.legacy) < @limit or
             Map.has_key?(state.legacy, event["parent_invocation_id"]) do
      receipt = %{
        "session_id" => session,
        "origin_sha256" => origin,
        "parent_invocation_id" => event["parent_invocation_id"],
        "operation_id" => event["operation_id"],
        "identity_sha256" => event["identity_sha256"],
        "path" => value["path"],
        "sha256" => value["sha256"],
        "byte_count" => count
      }

      %{state | legacy: Map.put(state.legacy, event["parent_invocation_id"], receipt)}
    else
      _ ->
        %{state | legacy: Map.delete(state.legacy, event["parent_invocation_id"]), refused: true}
    end
  end

  defp start(state, event, parent, session, origin, text) do
    request = event["request"]

    with false <- state.refused,
         true <- map_size(state.active) + map_size(state.completed) < @limit,
         true <- WorkspaceSnapshot.valid_result?(request, text),
         true <- parent?(state, parent, event, session) and JSON.sha256?(origin),
         {:ok, metadata} <- JSON.decode_bounded(text, 8192),
         handle = metadata["handle"],
         false <- Map.has_key?(state.active, handle),
         false <- Map.has_key?(state.completed, event["operation_id"]) do
      receipt = %{
        "version" => 1,
        "session_id" => session,
        "origin_sha256" => origin,
        "parent_invocation_id" => event["parent_invocation_id"],
        "operation_id" => event["operation_id"],
        "identity_sha256" => event["identity_sha256"],
        "artifact_sha256" => parent["identity"]["artifact_sha256"],
        "arguments_sha256" => JSON.digest([parent["payload"]["arguments"]]),
        "source_binding_sha256" => source_binding(parent["payload"]["arguments"]),
        "path" => metadata["path"],
        "byte_count" => metadata["byte_count"],
        "sha256" => metadata["sha256"]
      }

      active = %{receipt: receipt, offset: 0, hash: :crypto.hash_init(:sha256)}
      %{state | active: Map.put(state.active, handle, active)}
    else
      _ -> %{state | active: %{}, refused: true}
    end
  end

  defp page(state, event, parent, session, origin, text) do
    request = event["request"]
    handle = request["arguments"]["snapshot_handle"]

    with false <- state.refused,
         true <- WorkspaceSnapshot.valid_result?(request, text),
         true <- parent?(state, parent, event, session),
         %{receipt: receipt, offset: offset, hash: hash} = active <- state.active[handle],
         true <- receipt["session_id"] === session and receipt["origin_sha256"] === origin,
         true <- receipt["parent_invocation_id"] === event["parent_invocation_id"],
         true <- receipt["identity_sha256"] === event["identity_sha256"],
         true <- receipt["path"] === request["arguments"]["path"],
         true <- receipt["sha256"] === request["arguments"]["expected_sha256"],
         true <- offset === request["arguments"]["byte_offset"],
         {:ok, value} <- JSON.decode_bounded(text, 8192),
         true <- value["byte_count"] === receipt["byte_count"],
         {:ok, bytes} <- Base.decode64(value["data"]),
         next = offset + byte_size(bytes),
         hash = :crypto.hash_update(hash, bytes) do
      if is_nil(value["next"]) do
        digest = hash |> :crypto.hash_final() |> Base.encode16(case: :lower)

        if next === receipt["byte_count"] and digest === receipt["sha256"] do
          %{
            state
            | active: Map.delete(state.active, handle),
              completed: Map.put(state.completed, receipt["operation_id"], receipt)
          }
        else
          %{state | active: Map.delete(state.active, handle), refused: true}
        end
      else
        %{state | active: Map.put(state.active, handle, %{active | offset: next, hash: hash})}
      end
    else
      _ -> %{state | active: %{}, refused: true}
    end
  end

  defp invalidate(state, request, event) do
    handle = get_in(request, ["arguments", "snapshot_handle"])

    %{
      state
      | active: if(is_binary(handle), do: Map.delete(state.active, handle), else: %{}),
        legacy: Map.delete(state.legacy, event["parent_invocation_id"])
    }
  end

  @doc false
  def source_binding(outer) when is_map(outer) do
    args = outer["args"]

    if outer["action"] in ~w(read_document continue_collection_document) and
         is_binary(outer["store"]) and is_map(args) and
         is_binary(args["source_id"]) and is_binary(args["path"]) and
         is_integer(args["generation"]) do
      JSON.digest([
        %{
          "store" => outer["store"],
          "args" => Map.drop(args, ~w(expected_sha256 collection_state opening_acquisition))
        }
      ])
    end
  rescue
    _ -> nil
  end

  def source_binding(_), do: nil

  defp bind_continuation(state, event, parent, session) do
    continuation = get_in(event, ["value", "continuation"])
    outer = if is_map(continuation), do: continuation["arguments"]
    args = if is_map(outer), do: outer["args"]
    opening = if is_map(args), do: args["opening_acquisition"]
    operation = if is_map(opening), do: opening["operation_id"]
    receipt = state.completed[operation]
    plan = if is_map(args), do: get_in(args, ["collection_state", "plan_sha256"])

    if is_map(parent) and parent["invocation_id"] === event["invocation_id"] and
         parent["payload"]["session_id"] === session and
         event["identity"] === parent["identity"] and event["descriptor"] === parent["descriptor"] and
         confirmed_inline_result?(event, parent) and
         state.identities[parent["identity"]["instance"]] === parent["identity"] and
         parent["descriptor"] in state.catalog and
         Ipse.Extension.Invocation.validate_intent(parent, state.metadata) === :ok and
         get_in(event, ["value", "status"]) === "draft" and
         continuation["id"] === "source" and outer["action"] === "continue_collection_document" and
         is_map(receipt) and receipt["session_id"] === session and
         receipt["identity_sha256"] === JSON.digest([parent["identity"]]) and
         JSON.sha256?(receipt["source_binding_sha256"]) and
         receipt["source_binding_sha256"] === source_binding(parent["payload"]["arguments"]) and
         receipt["source_binding_sha256"] === source_binding(outer) and
         opening["kind"] === "workspace.read" and opening["path"] === receipt["path"] and
         args["expected_sha256"] === receipt["sha256"] and JSON.sha256?(plan) and
         ((is_nil(receipt["plan_sha256"]) and
             receipt["parent_invocation_id"] === parent["invocation_id"]) or
            receipt["plan_sha256"] === plan) do
      completed =
        state.completed
        |> Enum.reject(fn {id, candidate} ->
          id != operation and candidate["parent_invocation_id"] === parent["invocation_id"] and
            candidate["source_binding_sha256"] === receipt["source_binding_sha256"]
        end)
        |> Map.new()
        |> put_in([operation, "plan_sha256"], plan)

      %{state | completed: completed}
    else
      state
    end
  rescue
    _ -> state
  end

  # A continuation may be explicitly resumed in a later turn. Reclaim its
  # receipt only after the matching pinned invocation completes successfully.
  defp settle_completed(state, event, parent, session) do
    outer = get_in(parent || %{}, ["payload", "arguments"])
    args = if is_map(outer), do: outer["args"]
    action = if is_map(outer), do: outer["action"]

    operation =
      cond do
        action === "continue_collection_document" and is_map(args) ->
          get_in(args, ["opening_acquisition", "operation_id"])

        action === "read_document" ->
          Enum.find_value(state.completed, fn {operation, receipt} ->
            if receipt["parent_invocation_id"] === parent["invocation_id"], do: operation
          end)

        true ->
          nil
      end

    receipt = state.completed[operation]

    if is_map(parent) and is_map(receipt) and
         parent["invocation_id"] === event["invocation_id"] and
         parent["payload"]["session_id"] === session and
         event["identity"] === parent["identity"] and event["descriptor"] === parent["descriptor"] and
         confirmed_inline_result?(event, parent) and
         state.identities[parent["identity"]["instance"]] === parent["identity"] and
         parent["descriptor"] in state.catalog and
         Ipse.Extension.Invocation.validate_intent(parent, state.metadata) === :ok and
         get_in(event, ["value", "status"]) === "ok" and
         is_nil(get_in(event, ["value", "continuation"])) and
         receipt["session_id"] === session and
         receipt["identity_sha256"] === JSON.digest([parent["identity"]]) and
         JSON.sha256?(receipt["source_binding_sha256"]) and
         receipt["source_binding_sha256"] === source_binding(outer) do
      completed =
        state.completed
        |> Enum.reject(fn {id, candidate} ->
          id === operation or
            (candidate["parent_invocation_id"] === parent["invocation_id"] and
               candidate["source_binding_sha256"] === receipt["source_binding_sha256"])
        end)
        |> Map.new()

      %{state | completed: completed}
    else
      state
    end
  rescue
    _ -> state
  end

  defp confirmed_inline_result?(event, parent) do
    with true <- event["type"] === "extension_invocation_result" and event["version"] in [1, 3],
         true <- Ipse.Extension.Invocation.result_intent(event) === parent,
         true <-
           is_integer(event["action_count"]) and event["action_count"] >= 0 and
             event["action_count"] <= Ipse.Extension.Actions.limit(parent["identity"]),
         true <- JSON.sha256?(event["actions_sha256"]),
         text when is_binary(text) <- event["text"],
         true <- event["text_sha256"] === JSON.sha256(text),
         {:ok, value} <- JSON.decode_bounded(text),
         true <- value === event["value"],
         {:ok, ^value} <-
           Ipse.Extension.Catalog.validate_response(
             parent["descriptor"],
             %{"api_version" => 1, "kind" => "result", "value" => value}
           ) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp parent?(state, parent, event, session) do
    is_map(parent) and is_map(parent["identity"]) and
      parent["invocation_id"] === event["parent_invocation_id"] and
      parent["payload"]["session_id"] === session and
      JSON.digest([parent["identity"]]) === event["identity_sha256"] and
      state.identities[parent["identity"]["instance"]] === parent["identity"] and
      parent["descriptor"] in state.catalog and
      Ipse.Extension.Invocation.validate_intent(parent, state.metadata) === :ok
  end
end
