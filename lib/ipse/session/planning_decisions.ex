defmodule Ipse.Session.PlanningDecisions do
  @moduledoc """
  Native, operator-authored planning decisions which remain unindexed until an
  explicit post-exit save. These records grant no publication authority.
  """
  alias Ipse.{JSON, Usage}
  alias Ipse.Session.{Input, PlanningTransition}

  @accepted ~w(channel_id code command command_observation entry_sha256 id input observation session_id text type version)
  @save ~w(accepted_sha256 decision_id observation session_id type version)
  @result ~w(accepted_sha256 decision_id session_id status type version)
  @error {:error, :invalid_planning_decision}
  @limit 16

  def parse("/plan decide " <> text) do
    if text?(text), do: {:ok, text}, else: @error
  end

  def parse(_), do: @error

  def parse_save("/plan save " <> id) do
    if id?(id), do: {:ok, id}, else: @error
  end

  def parse_save(_), do: @error

  def render(session, channel, entry, text) do
    value = %{
      "version" => 1,
      "id" => Usage.id(),
      "session_id" => session,
      "channel_id" => channel,
      "entry_sha256" => JSON.digest([entry]),
      "text" => text,
      "code" => Usage.id()
    }

    if id?(session) and id?(channel) and is_map(entry) and text?(text),
      do: {:ok, Map.put(value, "display", display(value))},
      else: @error
  end

  def accept(render, command, command_observation, input, observation) do
    event =
      render
      |> Map.delete("display")
      |> Map.merge(%{
        "type" => "planning_decision_accepted",
        "command" => command,
        "command_observation" => command_observation,
        "input" => input,
        "observation" => observation
      })

    if render["display"] == display(render) and valid_accepted?(event, render["session_id"]),
      do: {:ok, event},
      else: @error
  end

  def valid_accepted?(event, session) when is_map(event) do
    Enum.sort(Map.keys(event)) == @accepted and event["type"] == "planning_decision_accepted" and
      event["version"] === 1 and event["session_id"] === session and id?(session) and
      Enum.all?(~w(id channel_id code), &id?(event[&1])) and
      JSON.sha256?(event["entry_sha256"]) and text?(event["text"]) and
      event["command"] == "/plan decide " <> event["text"] and
      Input.valid_observation?(event["command_observation"], event["command"], 2) and
      event["command_observation"]["display_sha256"] == JSON.sha256("you> ") and
      event["input"] == "accept " <> event["code"] and
      Input.valid_observation?(event["observation"], event["input"], 2) and
      event["observation"]["display_sha256"] == JSON.sha256(display(event))
  rescue
    _ -> false
  end

  def valid_accepted?(_, _), do: false

  def save_started(session, accepted, observation) do
    %{
      "type" => "planning_decision_save_started",
      "version" => 1,
      "session_id" => session,
      "decision_id" => accepted["id"],
      "accepted_sha256" => JSON.digest([accepted]),
      "observation" => observation
    }
  end

  def refused_unstarted(session, accepted) do
    %{
      "type" => "planning_decision_save_result",
      "version" => 1,
      "session_id" => session,
      "decision_id" => accepted["id"],
      "accepted_sha256" => JSON.digest([accepted]),
      "status" => "refused_unstarted"
    }
  end

  @doc "Replay witnessed decisions and one-shot save attempts without performing effects."
  def restore(events, session) when is_list(events) do
    relevant? =
      Enum.any?(events, fn event ->
        event["type"] in ~w(planning_decision_accepted planning_decision_save_started planning_decision_save_result) or
          (event["type"] == "operator_assertion" and Map.has_key?(event, "planning_decision"))
      end)

    if relevant?, do: replay(events, session), else: {:ok, %{}}
  rescue
    _ -> @error
  end

  def restore(_, _), do: @error

  defp replay(events, session) do
    Enum.reduce_while(events, {:ok, %{}, []}, fn event, {:ok, decisions, prefix} ->
      case advance(decisions, event, prefix, session) do
        {:ok, next} -> {:cont, {:ok, next, [event | prefix]}}
        _ -> {:halt, @error}
      end
    end)
    |> case do
      {:ok, decisions, _} -> {:ok, decisions}
      error -> error
    end
  end

  defp advance(decisions, %{"type" => "planning_decision_accepted"} = event, prefix, session) do
    with true <- valid_accepted?(event, session) and map_size(decisions) < @limit,
         false <- Map.has_key?(decisions, event["id"]),
         {:ok, mode, entry} <- PlanningTransition.reconstruct(Enum.reverse(prefix), session),
         true <- is_map(entry) and mode["ceiling"] == "planning",
         true <- JSON.digest([entry]) == event["entry_sha256"] do
      {:ok,
       Map.put(decisions, event["id"], %{
         receipt: event,
         exited: false,
         attempted: false,
         asserted: false,
         later_invocation_seen: false,
         refused: false
       })}
    else
      _ -> @error
    end
  end

  defp advance(decisions, %{"type" => "planning_exited"} = event, prefix, session) do
    with {:ok, %{"ceiling" => "normal"}, nil} <-
           PlanningTransition.reconstruct(Enum.reverse([event | prefix]), session) do
      {:ok,
       Map.new(decisions, fn {id, decision} ->
         {id,
          if(decision.receipt["entry_sha256"] == event["entry_sha256"],
            do: %{decision | exited: true},
            else: decision
          )}
       end)}
    else
      _ -> @error
    end
  end

  defp advance(decisions, %{"type" => "planning_decision_save_started"} = event, prefix, session) do
    command = "/plan save " <> to_string(event["decision_id"])

    with true <- Enum.sort(Map.keys(event)) == @save and event["version"] === 1,
         true <- event["session_id"] === session and id?(event["decision_id"]),
         %{receipt: receipt, exited: true, attempted: false} = decision <-
           decisions[event["decision_id"]],
         true <- event["accepted_sha256"] == JSON.digest([receipt]),
         true <- Input.valid_observation?(event["observation"], command, 2),
         true <- event["observation"]["display_sha256"] == JSON.sha256("you> "),
         {:ok, mode, _} <- PlanningTransition.reconstruct(Enum.reverse(prefix), session),
         true <- mode["ceiling"] == "normal" and mode["enclosing_ceiling"] == "normal" do
      {:ok, Map.put(decisions, event["decision_id"], %{decision | attempted: true})}
    else
      _ -> @error
    end
  end

  defp advance(
         decisions,
         %{"type" => "operator_assertion", "planning_decision" => receipt} = event,
         prefix,
         session
       ) do
    with %{receipt: ^receipt, attempted: true, asserted: false} = decision <-
           decisions[receipt["id"]],
         true <- event["text"] == receipt["text"] and event["category"] == "ordinary",
         {:ok, mode, _} <- PlanningTransition.reconstruct(Enum.reverse(prefix), session),
         true <- mode["ceiling"] == "normal" and mode["enclosing_ceiling"] == "normal" do
      {:ok, Map.put(decisions, receipt["id"], %{decision | asserted: true})}
    else
      _ -> @error
    end
  end

  defp advance(decisions, %{"type" => "extension_invocation_intent"}, _prefix, _session) do
    # Any later invocation prevents a witnessed unstarted result. This is a
    # conservative replay fence, not attribution to a particular decision.
    {:ok,
     Map.new(decisions, fn {id, decision} ->
       if decision.attempted and decision.asserted and not decision.refused,
         do: {id, %{decision | later_invocation_seen: true}},
         else: {id, decision}
     end)}
  end

  defp advance(decisions, %{"type" => "planning_decision_save_result"} = event, prefix, session) do
    with true <- Enum.sort(Map.keys(event)) == @result and event["version"] === 1,
         true <- event["session_id"] === session and event["status"] == "refused_unstarted",
         %{
           receipt: receipt,
           attempted: true,
           asserted: true,
           later_invocation_seen: false,
           refused: false
         } = decision <- decisions[event["decision_id"]],
         true <- event["accepted_sha256"] == JSON.digest([receipt]),
         {:ok, mode, _} <- PlanningTransition.reconstruct(Enum.reverse(prefix), session),
         true <- mode["ceiling"] == "normal" and mode["enclosing_ceiling"] == "normal" do
      {:ok, Map.put(decisions, event["decision_id"], %{decision | refused: true})}
    else
      _ -> @error
    end
  end

  defp advance(decisions, _, _, _), do: {:ok, decisions}

  defp display(value) do
    Ipse.CLI.Terminal.escape(
      "Accept this operator-authored planning decision?\nDecision: " <>
        Jason.encode!(value["text"]) <>
        "\nNothing is saved to knowledge now. After leaving planning, use /plan save #{value["id"]} to review a separate save.\n" <>
        "Type accept #{value["code"]} to defer this decision. Anything else cancels.\naccept> "
    )
  end

  defp text?(text),
    do:
      is_binary(text) and String.valid?(text) and byte_size(text) in 1..1024 and
        String.trim(text) != ""

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
