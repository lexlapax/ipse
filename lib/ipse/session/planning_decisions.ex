defmodule Ipse.Session.PlanningDecisions do
  @moduledoc """
  Native operator-authored and assistant-proposed planning decisions remain
  unindexed until an explicit post-exit save. These records grant no publication
  authority.
  """
  alias Ipse.{JSON, Usage}
  alias Ipse.Session.{Input, PlanningTransition, SourceWindow}

  @accepted ~w(channel_id code command command_observation entry_sha256 id input observation session_id text type version)
  @assistant_accepted ~w(channel_id code command command_observation entry_sha256 id input observation request_id session_id source_proof text turn_id type version)
  @save ~w(accepted_sha256 decision_id observation session_id type version)
  @assistant_save ~w(accepted_sha256 channel_id code command_observation decision_id id input observation scope session_id type version)
  @result ~w(accepted_sha256 decision_id session_id status type version)
  @error {:error, :invalid_planning_decision}
  @limit 16

  def parse("/plan decide " <> text) do
    if text?(text), do: {:ok, text}, else: @error
  end

  def parse(_), do: @error

  def parse_assistant("/plan decide-assistant " <> text) do
    if text?(text), do: {:ok, text}, else: @error
  end

  def parse_assistant(_), do: @error

  def parse_save("/plan save " <> id) do
    if id?(id), do: {:ok, id}, else: @error
  end

  def parse_save(_), do: @error

  @doc false
  def status(decision, assistant_current?) do
    cond do
      decision.refused ->
        "save_refused_before_publication"

      decision.attempted ->
        "save_started_inspect_journal"

      decision.exited and decision.receipt["version"] == 2 and not assistant_current? ->
        "source_unavailable_for_save"

      decision.exited ->
        "ready_for_save_review"

      true ->
        "waiting_for_planning_exit"
    end
  end

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

  def render_assistant(session, channel, entry, text, turn, request, proof) do
    with {:ok, render} <- render(session, channel, entry, text),
         true <- id?(turn) and id?(request),
         true <- assistant_proof?(proof, session, text) do
      value =
        render
        |> Map.delete("display")
        |> Map.merge(%{
          "version" => 2,
          "turn_id" => turn,
          "request_id" => request,
          "source_proof" => proof
        })

      {:ok, Map.put(value, "display", display(value))}
    else
      _ -> @error
    end
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
    version_ok =
      case event["version"] do
        1 ->
          Enum.sort(Map.keys(event)) == @accepted and
            event["command"] == "/plan decide " <> event["text"]

        2 ->
          Enum.sort(Map.keys(event)) == @assistant_accepted and
            event["command"] == "/plan decide-assistant " <> event["text"] and
            id?(event["turn_id"]) and id?(event["request_id"]) and
            assistant_proof?(event["source_proof"], session, event["text"])

        _ ->
          false
      end

    version_ok and event["type"] == "planning_decision_accepted" and
      event["session_id"] === session and id?(session) and
      Enum.all?(~w(id channel_id code), &id?(event[&1])) and
      JSON.sha256?(event["entry_sha256"]) and text?(event["text"]) and
      Input.valid_observation?(event["command_observation"], event["command"], 2) and
      event["command_observation"]["display_sha256"] == JSON.sha256("you> ") and
      event["input"] == "accept " <> event["code"] and
      Input.valid_observation?(event["observation"], event["input"], 2) and
      event["observation"]["display_sha256"] == JSON.sha256(display(event))
  rescue
    _ -> false
  end

  def valid_accepted?(_, _), do: false

  defp assistant_proof?(proof, session, text) when is_map(proof) do
    proof["session_id"] === session and proof["kind"] === "answer.original" and
      proof["origin"] === "assistant_proposal" and proof["quote"] === text and
      match?({:ok, _}, Ipse.Extension.ManagedRecipe.source_identity(proof))
  rescue
    _ -> false
  end

  defp assistant_proof?(_, _, _), do: false

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

  def stage_render(session, channel, accepted, scope) do
    value = %{
      "version" => 2,
      "id" => Usage.id(),
      "session_id" => session,
      "channel_id" => channel,
      "decision_id" => accepted["id"],
      "accepted_sha256" => JSON.digest([accepted]),
      "scope" => scope,
      "code" => Usage.id()
    }

    if accepted["version"] === 2 and valid_accepted?(accepted, session) and
         id?(channel) and is_map(scope),
       do: {:ok, Map.put(value, "display", stage_display(value, accepted))},
       else: @error
  end

  def stage_started(render, accepted, command_observation, input, observation) do
    event =
      render
      |> Map.delete("display")
      |> Map.merge(%{
        "type" => "planning_decision_save_started",
        "command_observation" => command_observation,
        "input" => input,
        "observation" => observation
      })

    if render["display"] === stage_display(render, accepted) and valid_stage?(event, accepted),
      do: {:ok, event},
      else: @error
  end

  defp valid_stage?(event, accepted) do
    command = "/plan save " <> to_string(accepted["id"])

    Enum.sort(Map.keys(event)) == @assistant_save and event["version"] === 2 and
      event["type"] == "planning_decision_save_started" and
      valid_accepted?(accepted, event["session_id"]) and accepted["version"] === 2 and
      event["decision_id"] === accepted["id"] and
      event["accepted_sha256"] === JSON.digest([accepted]) and
      Enum.all?(~w(id channel_id code), &id?(event[&1])) and is_map(event["scope"]) and
      Input.valid_observation?(event["command_observation"], command, 2) and
      event["command_observation"]["display_sha256"] === JSON.sha256("you> ") and
      event["input"] === "stage " <> event["code"] and
      Input.valid_observation?(event["observation"], event["input"], 2) and
      event["observation"]["display_sha256"] === JSON.sha256(stage_display(event, accepted))
  rescue
    _ -> false
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
         true <- JSON.digest([entry]) == event["entry_sha256"],
         true <- assistant_source_current?(event, prefix, session) do
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

  defp advance(
         decisions,
         %{"type" => "planning_decision_save_started", "version" => 2} = event,
         prefix,
         session
       ) do
    with %{receipt: receipt, exited: true, attempted: false} = decision <-
           decisions[event["decision_id"]],
         true <- valid_stage?(event, receipt) and event["session_id"] === session,
         {:ok, mode, _} <- PlanningTransition.reconstruct(Enum.reverse(prefix), session),
         true <- mode["ceiling"] == "normal" and mode["enclosing_ceiling"] == "normal",
         true <- assistant_source_current?(receipt, prefix, session),
         {:ok, admission} <- Ipse.Session.Saved.semantic_admission(Enum.reverse(prefix), session),
         {:ok, scope} <- Ipse.Session.OperatorAssertion.scope(admission),
         true <- event["scope"] === scope do
      {:ok, Map.put(decisions, event["decision_id"], %{decision | attempted: true})}
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
         1 <- receipt["version"],
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
    with 1 <- receipt["version"],
         %{receipt: ^receipt, attempted: true, asserted: false} = decision <-
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

  defp assistant_source_current?(%{"version" => 1}, _, _), do: true

  defp assistant_source_current?(event, prefix, session) do
    with {:ok, window} <- SourceWindow.restore(Enum.reverse(prefix), session) do
      SourceWindow.planning_answer_current?(
        window,
        event["entry_sha256"],
        event["turn_id"],
        event["request_id"],
        event["source_proof"]
      )
    else
      _ -> false
    end
  end

  defp display(value) do
    if value["version"] == 2 do
      Ipse.CLI.Terminal.escape(
        "Accept this exact assistant proposal as a planning decision?\nAssistant proposal: " <>
          Jason.encode!(value["text"]) <>
          "\nNothing is saved to knowledge now. After leaving planning, use /plan save #{value["id"]} to review a separate save.\n" <>
          "Type accept #{value["code"]} to defer this decision. Anything else cancels.\naccept> "
      )
    else
      Ipse.CLI.Terminal.escape(
        "Accept this operator-authored planning decision?\nDecision: " <>
          Jason.encode!(value["text"]) <>
          "\nNothing is saved to knowledge now. After leaving planning, use /plan save #{value["id"]} to review a separate save.\n" <>
          "Type accept #{value["code"]} to defer this decision. Anything else cancels.\naccept> "
      )
    end
  end

  defp stage_display(value, accepted) do
    Ipse.CLI.Terminal.escape(
      "Stage this accepted assistant proposal for independent knowledge review?\nAssistant proposal: " <>
        Jason.encode!(accepted["text"]) <>
        "\nDestination: " <>
        Jason.encode!(value["scope"]) <>
        "\nThis creates a pending proposal, not a published note. Close this session and run ipse knowledge review with the returned pending key to review it independently.\n" <>
        "Type stage #{value["code"]} to stage it. Anything else cancels.\nstage> "
    )
  end

  defp text?(text),
    do:
      is_binary(text) and String.valid?(text) and byte_size(text) in 1..1024 and
        String.trim(text) != ""

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
