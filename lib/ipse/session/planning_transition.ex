defmodule Ipse.Session.PlanningTransition do
  @moduledoc "Replay of execution ceilings and witnessed local planning transitions."
  alias Ipse.{JSON, Session.Input}
  alias Ipse.Extension.Mode

  @entry_keys ~w(checkpoint_sha256 observation session_id type version)
  @startup_keys ~w(mode_sha256 origin session_id version)
  @selected_keys ~w(checkpoint_sha256 origin session_id type version)
  @exit_keys ~w(entry_sha256 mode observation previous_sha256 session_id type version)
  @error {:error, :invalid_planning_transition}
  @mode_error {:error, :invalid_saved_execution_mode}

  @doc false
  def entry(session, checkpoint, observation) do
    %{
      "type" => "planning_entry_observed",
      "version" => 1,
      "session_id" => session,
      "checkpoint_sha256" => JSON.digest([checkpoint]),
      "observation" => observation
    }
  end

  @doc false
  def startup(session, mode) do
    %{
      "version" => 1,
      "origin" => "cli_flag",
      "session_id" => session,
      "mode_sha256" => JSON.digest([mode])
    }
  end

  @doc false
  def startup_selected(session, checkpoint) do
    %{
      "type" => "planning_start_selected",
      "version" => 1,
      "origin" => "cli_flag",
      "session_id" => session,
      "checkpoint_sha256" => JSON.digest([checkpoint])
    }
  end

  @doc false
  def exit(session, entry, current, observation) do
    %{
      "type" => "planning_exited",
      "version" => 1,
      "session_id" => session,
      "entry_sha256" => JSON.digest([entry]),
      "previous_sha256" => JSON.digest([current]),
      "mode" => Map.put(current, "ceiling", "normal"),
      "observation" => observation
    }
  end

  @doc false
  def validate_events(events, session) do
    case reconstruct(events, session) do
      {:ok, _, _} -> :ok
      _ -> @error
    end
  end

  @doc false
  def reconstruct(events, session) do
    with {:ok, state, _timeline} <- replay(events, session) do
      {:ok, state.mode, state.entry}
    end
  end

  @doc "Validated sparse historical modes; this restores no live permission."
  def mode_timeline(events, session \\ nil) do
    with {:ok, _state, timeline} <- replay(events, session) do
      {:ok, timeline}
    end
  end

  @doc false
  def mode_at([{_, _}, {next, _} | _] = timeline, position) when next <= position,
    do: mode_at(tl(timeline), position)

  def mode_at([{_, mode} | _] = timeline, _position), do: {mode, timeline}

  defp replay([%{"metadata" => metadata} | events], session) when is_map(metadata) do
    initial = metadata["execution_mode"]

    marker = metadata["planning_local_start"]

    if ((is_nil(initial) and not Map.has_key?(metadata, "execution_mode")) or Mode.valid?(initial)) and
         startup_valid?(marker, metadata, initial, session) do
      state = %{
        mode: initial,
        session: session || (marker && marker["session_id"]),
        candidate: nil,
        entry: marker
      }

      Enum.reduce_while(events, {:ok, state, [{0, initial}], 1}, fn event,
                                                                    {:ok, state, timeline,
                                                                     position} ->
        case step(state, event) do
          {:ok, next} ->
            timeline =
              if next.mode === state.mode, do: timeline, else: [{position, next.mode} | timeline]

            {:cont, {:ok, next, timeline, position + 1}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, state, timeline, _position} -> {:ok, state, Enum.reverse(timeline)}
        error -> error
      end
    else
      @mode_error
    end
  rescue
    _ -> @mode_error
  end

  defp replay(_, _), do: @mode_error

  defp step(state, %{"type" => "execution_mode_resumed"} = event) do
    previous = state.mode
    mode = event["mode"]

    valid =
      Enum.sort(Map.keys(event)) == ~w(mode previous_sha256 session_id type version) and
        (event["version"] === 1 or event["version"] === 2) and id?(event["session_id"]) and
        (is_nil(state.session) or state.session === event["session_id"]) and
        event["previous_sha256"] === JSON.digest([previous]) and Mode.valid?(mode) and
        (is_nil(previous) or
           if(event["version"] === 1,
             do: Mode.inherited?(previous, mode),
             else: Mode.resumed?(previous, mode)
           ))

    if valid do
      eligible =
        event["version"] === 2 and Mode.valid?(previous) and previous["ceiling"] == "normal" and
          previous["enclosing_ceiling"] == "normal" and
          mode["ceiling"] == "planning" and mode["enclosing_ceiling"] == "normal"

      candidate =
        if eligible do
          %{checkpoint: event, observed: mode === Map.put(previous, "ceiling", "planning")}
        end

      entry =
        if event["version"] === 2 and mode["ceiling"] == "planning",
          do: state.entry

      {:ok,
       %{
         state
         | mode: mode,
           session: event["session_id"],
           candidate: candidate,
           entry: entry
       }}
    else
      @mode_error
    end
  end

  defp step(
         %{candidate: candidate} = state,
         %{"type" => "planning_mcp_epoch", "startup" => "resume"} = event
       )
       when is_map(candidate) do
    draft_mode =
      state.mode
      |> Mode.config()
      |> Ipse.Session.Draft.draft_config()
      |> Mode.capture()

    candidate =
      cond do
        event["execution_mode"] === state.mode -> candidate
        draft_mode === {:ok, event["execution_mode"]} -> %{candidate | observed: false}
        true -> nil
      end

    {:ok, %{state | candidate: candidate}}
  end

  defp step(state, %{"type" => "planning_entry_observed"} = event) do
    candidate = state.candidate

    valid =
      is_map(candidate) and candidate.observed and Enum.sort(Map.keys(event)) == @entry_keys and
        event["version"] === 1 and event["session_id"] === state.session and
        event["session_id"] === candidate.checkpoint["session_id"] and
        event["checkpoint_sha256"] === JSON.digest([candidate.checkpoint]) and
        Input.valid_observation?(event["observation"], "/plan", 2)

    if valid, do: {:ok, %{state | candidate: nil, entry: event}}, else: @error
  end

  defp step(state, %{"type" => "planning_start_selected"} = event) do
    candidate = state.candidate

    valid =
      is_map(candidate) and Enum.sort(Map.keys(event)) == @selected_keys and
        event["version"] === 1 and event["origin"] === "cli_flag" and
        event["session_id"] === state.session and
        event["session_id"] === candidate.checkpoint["session_id"] and
        event["checkpoint_sha256"] === JSON.digest([candidate.checkpoint])

    if valid, do: {:ok, %{state | candidate: nil, entry: event}}, else: @error
  end

  defp step(state, %{"type" => "planning_exited"} = event) do
    current = state.mode

    valid =
      is_map(state.entry) and Mode.valid?(current) and current["ceiling"] == "planning" and
        Enum.sort(Map.keys(event)) == @exit_keys and event["version"] === 1 and
        event["session_id"] === state.session and
        event["entry_sha256"] === JSON.digest([state.entry]) and
        event["previous_sha256"] === JSON.digest([current]) and
        event["mode"] === Map.put(current, "ceiling", "normal") and
        Input.valid_observation?(event["observation"], "/plan exit", 2)

    if valid, do: {:ok, %{state | mode: event["mode"], candidate: nil, entry: nil}}, else: @error
  end

  defp step(state, _), do: {:ok, %{state | candidate: nil}}

  defp startup_valid?(nil, metadata, _mode, _session),
    do: not Map.has_key?(metadata, "planning_local_start")

  defp startup_valid?(marker, metadata, mode, session) when is_map(marker) do
    Enum.sort(Map.keys(marker)) == @startup_keys and marker["version"] === 1 and
      marker["origin"] === "cli_flag" and id?(marker["session_id"]) and
      (is_nil(session) or session === marker["session_id"]) and
      is_nil(metadata["delegation_origin"]) and Mode.valid?(mode) and
      mode["ceiling"] == "planning" and mode["enclosing_ceiling"] == "normal" and
      marker["mode_sha256"] === JSON.digest([mode])
  end

  defp startup_valid?(_, _, _, _), do: false
  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
