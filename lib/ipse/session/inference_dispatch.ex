defmodule Ipse.Session.InferenceDispatch do
  @moduledoc false
  alias Ipse.{JSON, Session}
  alias Ipse.Extension.{Consent, Mode, ProjectIdentity, SemanticAdmission}
  @event_type "inference_dispatch_intent"
  @phases ~w(model compaction model.complete embedding.create decision.create)
  @hashes ~w(admission_sha256 input_sha256 tools_sha256 source_sha256 mode_sha256 pin_sha256 route_sha256)
  @keys ~w(type version intent_id session_id turn_id request_id attempt_id phase service_id reservation_id) ++
          @hashes

  # This is a content-free dispatch INTENT, not evidence that HTTP began. A
  # later slot admission may still refuse it. Replay never dispatches anything.
  def prepare(s, runtime, input, tools, phase, admission) do
    %{
      config: s.config,
      runtime: runtime,
      phase: phase,
      admission: admission,
      cwd: s.cwd,
      session_id: s.id,
      # Attribution for ordinary Sessions grants no project identity or consent.
      project_id:
        JSON.digest([get_in(s.config, [:semantic_admission, "pin", "project_id"]) || s.cwd]),
      request_sha256: JSON.digest([input, tools]),
      priority: "foreground",
      expected: expected(s, input, tools, admission)
    }
  end

  def gate(owner, job, data, facts) do
    append = fn ->
      GenServer.call(
        owner,
        {:inference_dispatch_intent, job, data.phase, data.admission, data.expected, facts},
        5_000
      )
    end

    descriptor = data.config[:semantic_admission]

    if is_map(descriptor) and descriptor["pin"] != nil do
      pin = descriptor["pin"]

      with {:ok, _} <- SemanticAdmission.context(data.config, data.session_id, 0) do
        ProjectIdentity.with_binding(data.config[:home], data.cwd, descriptor["binding"], fn _ ->
          Consent.with_policy(
            SemanticAdmission.control_root(data.config[:home]),
            pin["project_id"],
            pin["epoch"],
            pin["policy_sha256"],
            System.system_time(:millisecond),
            fn _ -> append.() end
          )
        end)
      end
    else
      append.()
    end
  catch
    :exit, _ -> {:error, :inference_dispatch_refused}
  end

  def commit(s, caller, phase, admission, expected, facts) do
    with true <- not is_nil(s.task),
         true <- caller == s.task.pid or Session.Resources.authorized_effect?(s.task.pid, caller),
         {:ok, runtime, input, tools, current} <- view(s, phase),
         true <- current === admission,
         true <- expected(s, input, tools, current) === expected,
         {:ok, %{route: route}} <-
           Ipse.InferenceDispatch.selection(
             s.config,
             runtime,
             operation(phase),
             profile(phase, current)
           ),
         true <- is_map(facts) and facts["route"] === route,
         true <- id?(facts["reservation_id"]),
         true <- pin_live?(s) do
      event =
        Map.merge(expected, %{
          "type" => @event_type,
          "version" => 1,
          "intent_id" => Ipse.Usage.id(),
          "session_id" => s.id,
          "turn_id" => s.turn_id,
          "request_id" => current["request_id"],
          "attempt_id" => current["attempt_id"],
          "phase" => phase,
          "service_id" => route["service_id"],
          "reservation_id" => facts["reservation_id"],
          "route_sha256" => JSON.digest([route])
        })

      Session.record(s, event)
      {:reply, {:ok, %{"intent_id" => event["intent_id"]}}, s}
    else
      _ -> {:reply, {:error, :inference_dispatch_refused}, s}
    end
  rescue
    _ -> {:reply, {:error, :inference_dispatch_refused}, s}
  end

  def operation(phase) when phase in ["model", "compaction"], do: "main"
  def operation(phase), do: phase
  def profile(phase, _) when phase in ["model", "compaction"], do: nil
  def profile(_, admission), do: admission["selected_profile"]

  defp view(s, phase) when phase in ["model", "compaction"],
    do: Session.Turn.dispatch_view(s, phase)

  defp view(s, phase), do: Session.Invocation.dispatch_view(s, phase)

  defp pin_live?(s) do
    descriptor = s.config[:semantic_admission]

    is_nil(descriptor) or is_nil(descriptor["pin"]) or
      match?({:ok, _}, SemanticAdmission.context(s.config, s.id, 0))
  end

  defp expected(s, input, tools, admission) do
    {:ok, mode} = Mode.capture(s.config)

    %{
      "admission_sha256" => JSON.digest([admission]),
      "input_sha256" => JSON.digest([input]),
      "tools_sha256" => JSON.digest([tools]),
      "source_sha256" => JSON.digest([Session.source_snapshot(s)]),
      "mode_sha256" => JSON.digest([mode]),
      "pin_sha256" => JSON.digest([s.config[:semantic_admission]])
    }
  end

  def validate_events(events) do
    Enum.reduce_while(events, {:ok, %{}, MapSet.new()}, fn event, {:ok, active, seen} ->
      case event["type"] do
        boundary
        when boundary in ~w(input_received cancelled turn_finished lifecycle_epoch_started lifecycle_epoch_closed) ->
          {:cont, {:ok, %{}, seen}}

        "request_admitted" ->
          {:cont, {:ok, Map.put(active, event["request_id"], event), seen}}

        "request_finished" ->
          {:cont, {:ok, Map.delete(active, event["request_id"]), seen}}

        @event_type ->
          admission = active[event["request_id"]]

          if valid_intent?(event, admission) and not MapSet.member?(seen, event["intent_id"]) do
            {:cont, {:ok, active, MapSet.put(seen, event["intent_id"])}}
          else
            {:halt, {:error, :invalid_inference_dispatch_intent}}
          end

        _ ->
          {:cont, {:ok, active, seen}}
      end
    end)
    |> case do
      {:ok, _, _} -> :ok
      error -> error
    end
  rescue
    _ -> {:error, :invalid_inference_dispatch_intent}
  end

  def valid_intent?(event, admission) do
    is_map(admission) and not is_nil(Ipse.Usage.operation(admission)) and
      Enum.sort(Map.keys(event)) == Enum.sort(@keys) and event["version"] === 1 and
      event["phase"] in @phases and id?(event["intent_id"]) and id?(event["reservation_id"]) and
      event["session_id"] === admission["session_id"] and
      event["turn_id"] === admission["turn_id"] and
      event["attempt_id"] === admission["attempt_id"] and
      event["admission_sha256"] == JSON.digest([admission]) and
      Enum.all?(@hashes, &JSON.sha256?(event[&1])) and
      is_binary(event["service_id"]) and
      Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, event["service_id"]) and
      case event["phase"] do
        phase when phase in ["model", "compaction"] ->
          admission["kind"] == phase

        "model.complete" ->
          admission["kind"] == "extension" and Ipse.Usage.operation(admission) == "text"

        "embedding.create" ->
          Ipse.Usage.operation(admission) == "embedding"

        "decision.create" ->
          Ipse.Usage.operation(admission) == "decision"
      end
  rescue
    _ -> false
  end

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
