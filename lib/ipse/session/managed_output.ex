defmodule Ipse.Session.ManagedOutput do
  @moduledoc "Owned release of managed worker results; historical records never grant current delivery."
  alias Ipse.{JSON, Session}
  alias Ipse.Extension.{Invocation, Registry, ResultSource}
  alias Ipse.Session.{ManagedLineage, ManagedUse, Resources}
  alias Ipse.Session.Invocation, as: CurrentInvocation
  @layout "managed_output_release_v1"
  @error {:error, :managed_output_unavailable}
  @intent_keys ~w(type version release_id session_id parent_invocation_id parent_sha256 actions_sha256 result_sha256 dependencies_sha256 kind checked_at_ms deadline_ms)
  @result_keys ~w(type version release_id intent_sha256 decision write_facts projection_sha256 checked_at_ms deadline_ms)
  @cleanup_keys ~w(type version release_id result_sha256 status)

  def layout, do: @layout

  def write_facts(actions) do
    Enum.flat_map(actions, fn event ->
      if get_in(event, ["request", "op"]) == "collection.managed" and
           get_in(event, ["outcome", "status"]) == "ok" and
           Ipse.Extension.ManagedCollectionCall.bound_outcome?(event) do
        value = event["outcome"]["value"]

        [
          %{
            "operation_id" => event["operation_id"],
            "action_sha256" => JSON.digest([event]),
            "normalization_sha256" => JSON.digest([value["normalization"]]),
            "receipt_sha256" => JSON.digest([value["receipt"]]),
            "generation" => value["receipt"]["generation"],
            "record_key" => value["normalization"]["record_key"],
            "category" => value["normalization"]["category"]
          }
        ]
      else
        []
      end
    end)
  end

  def marker(metadata) do
    case Map.fetch(metadata, "managed_output_layout") do
      :error -> {:ok, nil}
      {:ok, @layout} -> {:ok, @layout}
      _ -> @error
    end
  end

  def intent(session, parent, result, deps, now, deadline) do
    %{
      "type" => "managed_output_release_intent",
      "version" => 1,
      "release_id" => Ipse.Usage.id(),
      "session_id" => session,
      "parent_invocation_id" => parent["invocation_id"],
      "parent_sha256" => JSON.digest([parent]),
      "actions_sha256" => result["actions_sha256"],
      "result_sha256" => JSON.digest([result]),
      "dependencies_sha256" => JSON.digest(deps),
      "kind" => if(result["version"] in [2, 4], do: "saved", else: "inline"),
      "checked_at_ms" => now,
      "deadline_ms" => deadline
    }
  end

  def valid_intent?(event, session, parent, actions_sha, deps \\ nil) do
    keys?(event, @intent_keys) and event["type"] == "managed_output_release_intent" and
      event["version"] === 1 and id?(event["release_id"]) and
      event["session_id"] == session and event["parent_invocation_id"] == parent["invocation_id"] and
      event["parent_sha256"] == JSON.digest([parent]) and event["actions_sha256"] == actions_sha and
      JSON.sha256?(event["result_sha256"]) and JSON.sha256?(event["dependencies_sha256"]) and
      (is_nil(deps) or event["dependencies_sha256"] == JSON.digest(deps)) and
      event["kind"] in ~w(inline saved) and JSON.safe_uint?(event["checked_at_ms"]) and
      JSON.safe_uint?(event["deadline_ms"]) and event["deadline_ms"] >= event["checked_at_ms"] and
      event["deadline_ms"] - event["checked_at_ms"] <= 120_000
  rescue
    _ -> false
  end

  def bound_result?(intent, event),
    do:
      event["invocation_id"] == intent["parent_invocation_id"] and
        event["actions_sha256"] == intent["actions_sha256"] and
        JSON.digest([event]) == intent["result_sha256"] and
        intent["kind"] == if(event["version"] in [2, 4], do: "saved", else: "inline")

  def admission(intent, raw, decision, facts, now, deadline) do
    %{
      "type" => "managed_output_release_result",
      "version" => 1,
      "release_id" => intent["release_id"],
      "intent_sha256" => JSON.digest([intent]),
      "decision" => decision,
      "write_facts" => facts,
      "projection_sha256" => JSON.digest([delivery(raw, decision, facts)]),
      "checked_at_ms" => now,
      "deadline_ms" => deadline
    }
  end

  def valid_admission?(event, intent, raw, facts) do
    keys?(event, @result_keys) and event["type"] == "managed_output_release_result" and
      event["version"] === 1 and event["release_id"] == intent["release_id"] and
      event["intent_sha256"] == JSON.digest([intent]) and bound_result?(intent, raw) and
      event["decision"] in ~w(current historical_write withdrawn) and
      event["write_facts"] == if(event["decision"] == "historical_write", do: facts, else: []) and
      (event["decision"] != "historical_write" or facts != []) and
      JSON.safe_uint?(event["checked_at_ms"]) and JSON.safe_uint?(event["deadline_ms"]) and
      event["checked_at_ms"] >= intent["checked_at_ms"] and
      event["deadline_ms"] <= intent["deadline_ms"] and
      (event["decision"] != "current" or event["checked_at_ms"] < event["deadline_ms"]) and
      event["projection_sha256"] ==
        JSON.digest([delivery(raw, event["decision"], event["write_facts"])])
  rescue
    _ -> false
  end

  def cleanup(intent, admission, status),
    do: %{
      "type" => "managed_output_release_cleanup",
      "version" => 1,
      "release_id" => intent["release_id"],
      "result_sha256" => JSON.digest([admission]),
      "status" => status
    }

  def valid_cleanup?(event, intent, admission),
    do:
      keys?(event, @cleanup_keys) and event["type"] == "managed_output_release_cleanup" and
        event["version"] === 1 and event["release_id"] == intent["release_id"] and
        event["result_sha256"] == JSON.digest([admission]) and
        event["status"] in ~w(confirmed unknown)

  def delivery(raw, "current", []), do: Invocation.delivery(raw)

  def delivery(_, "historical_write", facts),
    do: %{
      "value" => %{
        "status" => "historical_write_outcome",
        "current_eligibility" => "not_established",
        "outcomes" => facts
      }
    }

  def delivery(_, "withdrawn", []),
    do: %{
      "value" => %{
        "status" => "withheld",
        "reason" => "managed_dependencies_unavailable",
        "historical_receipt" => true
      }
    }

  def tool_message(raw, "current", []), do: Invocation.tool_message(raw)

  def tool_message(raw, decision, facts) do
    raw
    |> Invocation.tool_message()
    |> Map.put("content", Jason.encode!(delivery(raw, decision, facts)["value"]))
    |> Map.delete("ipse_extension_result")
  end

  def display(raw, decision, facts),
    do:
      Map.merge(
        %{"name" => raw["descriptor"]["name"], "stage" => raw["descriptor"]["stage"]},
        delivery(raw, decision, facts)
      )

  @doc false
  def release(owner, job, kind, payload) do
    case GenServer.call(owner, {:managed_output_prepare, job, kind, payload}, 5_000) do
      {:ok, :ordinary} ->
        {:ordinary, payload}

      {:ok, spec} ->
        release_prepared(owner, job, spec)

      _ ->
        {:unknown, "Managed worker output could not be prepared; inspect its original receipts."}
    end
  catch
    :exit, _ -> {:unknown, "Managed worker output was interrupted; delivery is unconfirmed."}
  end

  defp release_prepared(owner, job, spec) do
    entered = :atomics.new(1, signed: false)

    result =
      Resources.file_effect(fn ->
        ManagedUse.with_dependencies(spec.context, spec.dependencies, fn current ->
          :atomics.put(entered, 1, 1)

          GenServer.call(
            owner,
            {:managed_output_admit, job, spec.intent["release_id"], :current,
             use_deadline(spec, current)},
            5_000
          )
        end)
      end)

    cond do
      result == {:ok, spec.intent["release_id"]} ->
        finish_release(owner, job, spec, "confirmed")

      :atomics.get(entered, 1) != 0 ->
        finish_release(owner, job, spec, "unknown")

      true ->
        case GenServer.call(
               owner,
               {:managed_output_admit, job, spec.intent["release_id"], :fallback, nil},
               5_000
             ) do
          {:ok, _} -> finish_release(owner, job, spec, "confirmed")
          _ -> {:unknown, "Managed worker output was withheld; delivery is unconfirmed."}
        end
    end
  end

  defp finish_release(owner, job, spec, status) do
    case GenServer.call(
           owner,
           {:managed_output_cleanup, job, spec.intent["release_id"], status},
           5_000
         ) do
      :ok when status == "confirmed" ->
        {:extension_released, spec.intent["release_id"]}

      _ ->
        {:unknown,
         "Managed worker output publication may already have occurred; cleanup is unconfirmed."}
    end
  end

  defp use_deadline(spec, current) do
    deadlines =
      for dependency <- current,
          deadline = get_in(dependency, ["subject", "validity", "valid_until_ms"]),
          is_integer(deadline),
          do: deadline

    policy = get_in(spec.context, [:config, :semantic_admission, "policy", "expires_at_ms"])

    Enum.min([
      spec.intent["deadline_ms"] | deadlines ++ if(is_integer(policy), do: [policy], else: [])
    ])
  end

  @doc false
  def prepare(s, caller, kind, payload) do
    with true <- worker?(s, caller) and is_nil(s.managed_output_release),
         parent when is_map(parent) <- s.invocation.parent,
         true <- is_nil(s.invocation.action) and not s.invocation.interrupted,
         true <- CurrentInvocation.output_timely?(s) and Registry.live?(parent["identity"]),
         {:ok, raw, index} <- validate_output(s, kind, payload),
         {:ok, deps} <-
           ManagedLineage.invocation_dependencies(
             s.managed_lineage,
             parent["invocation_id"],
             s.invocation.managed_reads
           ) do
      if deps == [] do
        {:reply, {:ok, :ordinary}, s}
      else
        now = System.system_time(:millisecond)

        remaining =
          if s.extension_output_clock,
            do: max(120_000 - CurrentInvocation.output_elapsed(s), 0),
            else: 120_000

        intent = intent(s.id, parent, raw, deps, now, now + remaining)
        Session.record(s, intent)
        s = Session.managed_event(s, intent)

        s =
          if kind == :saved,
            do: CurrentInvocation.record_output(s, raw, true),
            else:
              (
                Session.record(s, raw)
                s
              )

        s = Session.managed_event(s, raw)

        s =
          if kind == :saved,
            do: %{
              s
              | extension_result_sources: %{
                  s.extension_result_sources
                  | recorded:
                      Map.put(s.extension_result_sources.recorded, raw["invocation_id"], raw)
                }
            },
            else: s

        snapshot = %{
          dependencies: deps,
          sha256: JSON.digest([intent, raw, deps]),
          input_sha256: JSON.digest([raw]),
          plan: nil
        }

        pending = %{
          intent: intent,
          raw: raw,
          index: index,
          snapshot: snapshot,
          job: s.job_ref,
          worker: s.task.pid,
          parent: parent,
          actions_sha: JSON.digest(s.invocation.results),
          admission: nil,
          cleanup: nil
        }

        next = %{s | managed_output_release: pending}

        context = %{
          config: s.config,
          cwd: s.cwd,
          session_id: s.id,
          history_dir: s.dir,
          owner: self(),
          job_ref: s.job_ref,
          source_binding: {:snapshot, "extension.result", snapshot.sha256}
        }

        {:reply, {:ok, %{intent: intent, context: context, dependencies: deps}}, next}
      end
    else
      _ -> {:reply, @error, s}
    end
  end

  defp validate_output(s, :inline, event) do
    with {:ok, ^event} <-
           Invocation.build_result(
             s.invocation.parent,
             %{"api_version" => 1, "kind" => "result", "value" => event["value"]},
             s.invocation.results
           ),
         do: {:ok, event, nil},
         else: (_ -> @error)
  end

  defp validate_output(s, :saved, delivery) do
    with true <- s.extension_output != nil and s.extension_output_clock != nil,
         {:ok, event} <-
           Invocation.build_saved_result(
             s.invocation.parent,
             delivery,
             s.invocation.results,
             CurrentInvocation.output_elapsed(s)
           ),
         {:ok, index} <- ResultSource.publish(s.extension_result_sources, event),
         do: {:ok, event, index},
         else: (_ -> @error)
  end

  defp validate_output(_, _, _), do: @error

  @doc false
  def snapshot(s) do
    with pending when is_map(pending) <- s.managed_output_release,
         true <- binding_current?(s, pending),
         do: {:ok, pending.snapshot},
         else: (_ -> @error)
  end

  defp binding_current?(s, p),
    do:
      s.job_ref == p.job and s.task != nil and s.task.pid == p.worker and
        s.invocation.parent == p.parent and is_nil(s.invocation.action) and
        not s.invocation.interrupted and JSON.digest(s.invocation.results) == p.actions_sha

  @doc false
  def admit(s, caller, id, mode, deadline) do
    with true <- worker?(s, caller),
         p when is_map(p) <- s.managed_output_release,
         true <- binding_current?(s, p) and p.intent["release_id"] == id and is_nil(p.admission),
         true <- Registry.live?(p.parent["identity"]),
         now = System.system_time(:millisecond),
         true <-
           mode == :fallback or
             (mode == :current and JSON.safe_uint?(deadline) and
                deadline <= p.intent["deadline_ms"] and now < deadline),
         facts = Map.get(s.managed_lineage.write_facts, p.raw["invocation_id"], []),
         decision =
           if(mode == :current,
             do: "current",
             else: if(facts == [], do: "withdrawn", else: "historical_write")
           ),
         selected = if(decision == "historical_write", do: facts, else: []),
         admission =
           admission(
             p.intent,
             p.raw,
             decision,
             selected,
             now,
             if(mode == :current, do: deadline, else: p.intent["deadline_ms"])
           ) do
      Session.record(s, admission)
      next = Session.managed_event(s, admission)

      next = %{
        next
        | extension_contributions:
            if(decision == "current",
              do: s.invocation.pending_contributions || s.extension_contributions,
              else: Map.delete(s.extension_contributions, p.parent["identity"]["instance"])
            ),
          managed_output_release: %{p | admission: admission}
      }

      # This check follows durable writes immediately before the actual release.
      if mode == :current and System.system_time(:millisecond) >= deadline do
        {:reply, @error, next}
      else
        case publish(next, p.raw, admission) do
          {:ok, published} -> {:reply, {:ok, id}, published}
          {:error, withheld} -> {:reply, @error, withheld}
        end
      end
    else
      _ -> {:reply, @error, s}
    end
  end

  defp publish(s, raw, admission) do
    case raw["descriptor"]["stage"] do
      "invoke.tool" ->
        message = tool_message(raw, admission["decision"], admission["write_facts"])

        if admission["decision"] == "current",
          do: Session.Turn.commit_tool_result(s, hd(s.calls), message, admission["deadline_ms"]),
          else: {:ok, Session.Turn.commit_tool_result(s, hd(s.calls), message)}

      "event.job" ->
        {:ok, s}

      _ ->
        display = display(raw, admission["decision"], admission["write_facts"])

        if admission["decision"] != "current" or
             System.system_time(:millisecond) < admission["deadline_ms"] do
          Session.notify(s, {:extension_result, display})
          {:ok, %{s | extension_result: display}}
        else
          {:error, s}
        end
    end
  end

  @doc false
  def finish(s, caller, id, status) do
    with true <- worker?(s, caller),
         p when is_map(p) <- s.managed_output_release,
         true <- binding_current?(s, p) and p.intent["release_id"] == id,
         true <- is_map(p.admission) and is_nil(p.cleanup) and status in ~w(confirmed unknown),
         event = cleanup(p.intent, p.admission, status) do
      Session.record(s, event)

      s =
        if status == "unknown",
          do: %{
            s
            | messages: withhold_pending(s.messages, s.managed_lineage),
              extension_result:
                if(p.raw["descriptor"]["stage"] in ~w(invoke.command invoke.service),
                  do: display(p.raw, "withdrawn", []),
                  else: s.extension_result
                ),
              extension_contributions:
                Map.delete(s.extension_contributions, p.parent["identity"]["instance"])
          },
          else: s

      next = Session.managed_event(s, event)

      sources =
        if status == "confirmed" and p.admission["decision"] == "current" and p.index,
          do: p.index,
          else: s.extension_result_sources

      {:reply, :ok,
       %{next | managed_output_release: %{p | cleanup: status}, extension_result_sources: sources}}
    else
      _ -> {:reply, @error, s}
    end
  end

  @doc false
  def complete(s, id) do
    with p when is_map(p) <- s.managed_output_release,
         true <- p.intent["release_id"] == id and p.cleanup == "confirmed",
         true <- completion_bound?(s, p) do
      s =
        if p.admission["decision"] == "current",
          do: Session.PendingNomination.record_result(s, p.parent, p.raw),
          else: s

      handoff =
        if s.phase == :extension_command and is_map(Map.get(s, :post_reply_capture)) do
          if known_capture?(s, p),
            do: Session.ChatReviewHandoff.prepare(s, p.parent, p.raw),
            else: {:error, :chat_review_unavailable}
        else
          :not_applicable
        end

      next = CurrentInvocation.release_output(s)

      next = %{
        next
        | managed_output_release: nil,
          managed_outputs:
            Map.put(s.managed_outputs, p.raw["invocation_id"], s.invocation.managed_reads),
          invocation: %CurrentInvocation{}
      }

      cond do
        handoff != :not_applicable ->
          {:noreply, CurrentInvocation.finish_chat_review(next, handoff)}

        p.raw["descriptor"]["stage"] == "invoke.tool" ->
          {:noreply, Session.Turn.next_tool(next)}

        true ->
          {:noreply,
           Session.Turn.finish(
             next,
             if(p.admission["decision"] == "withdrawn", do: :error, else: :ok)
           )}
      end
    else
      _ ->
        {:noreply,
         Session.Turn.fail(
           s,
           "Managed worker publication is unconfirmed; inspect retained receipts."
         )}
    end
  end

  defp completion_bound?(s, p) do
    s.job_ref == p.job and s.invocation.parent === p.parent and
      is_nil(s.invocation.action) and not s.invocation.interrupted and
      JSON.digest(s.invocation.results) == p.actions_sha and Registry.live?(p.parent["identity"]) and
      valid_admission?(p.admission, p.intent, p.raw, write_facts(s.invocation.results))
  end

  defp known_capture?(_s, %{admission: %{"decision" => "current"}}), do: true

  # A known completed write may outlive its earlier root observation. It selects
  # a review target only; Management must reread and authenticate that target and
  # its original source before any card or publication authority exists.
  defp known_capture?(s, %{admission: %{"decision" => "historical_write"}} = p) do
    with %{"status" => "saved", "key" => "pending." <> _ = key, "receipt" => receipt} <-
           p.raw["value"],
         [fact] <- p.admission["write_facts"],
         true <- fact["record_key"] === key,
         [action] <-
           Enum.filter(s.invocation.results, &(&1["operation_id"] === fact["operation_id"])),
         true <- action["parent_invocation_id"] === p.parent["invocation_id"],
         true <- Ipse.Extension.Actions.valid_result?(action),
         true <- Ipse.Extension.ManagedCollectionCall.new_capture?(action["request"]),
         true <- Ipse.Extension.ManagedCollectionCall.bound_outcome?(action),
         true <- action["outcome"]["status"] === "ok",
         true <- action["outcome"]["value"] === receipt,
         true <- write_facts([action]) === [fact],
         [%{"key" => ^key, "expected_revision" => 0}] <- action["request"]["request"]["changes"] do
      true
    else
      _ -> false
    end
  end

  defp known_capture?(_, _), do: false

  @doc false
  def complete_event(s, caller, id) do
    with true <- worker?(s, caller),
         p when is_map(p) <- s.managed_output_release,
         true <- p.intent["release_id"] == id and p.cleanup == "confirmed",
         true <- p.raw["descriptor"]["stage"] == "event.job",
         delivery when is_map(delivery) <- s.event_intent do
      outcome =
        if p.admission["decision"] == "current",
          do: Invocation.event_outcome(s.invocation.results),
          else: "failed"

      Session.record(s, Ipse.Extension.Subscriptions.result(delivery, outcome, true))

      next = %{
        s
        | managed_output_release: nil,
          invocation: %CurrentInvocation{},
          event_intent: nil,
          extension_mcp_context: nil
      }

      if outcome == "failed",
        do:
          Session.notify(
            s,
            {:status, "Managed event output was withheld; inspect its release receipts."}
          )

      {:reply, {:ok, outcome}, next}
    else
      _ -> {:reply, @error, s}
    end
  end

  defp worker?(s, caller),
    do:
      s.phase in [:tool, :extension_command, :extension_service, :extension_events] and
        s.task != nil and s.job_ref != nil and
        (s.task.pid == caller or Resources.authorized_effect?(s.task.pid, caller))

  @doc false
  def withhold_pending(messages, %{output_release: %{raw: raw, admission: admission}})
      when is_map(raw) and is_map(admission) do
    original = tool_message(raw, admission["decision"], admission["write_facts"])
    replacement = tool_message(raw, "withdrawn", [])

    case Enum.reverse(messages) do
      [^original | rest] -> Enum.reverse([replacement | rest])
      _ -> messages
    end
  end

  def withhold_pending(messages, _), do: messages

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
