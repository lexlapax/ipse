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
      source_generation: Session.source_snapshot(s)["generation"],
      history_dir: Map.get(s, :dir),
      owner: self(),
      job_ref: Map.get(s, :job_ref),
      wire: wire(runtime, input, tools, phase),
      managed: managed_snapshot(s, phase),
      document_source: document_source(s, phase),
      # Attribution for ordinary Sessions grants no project identity or consent.
      project_id:
        JSON.digest([get_in(s.config, [:semantic_admission, "pin", "project_id"]) || s.cwd]),
      request_sha256: JSON.digest([input, tools]),
      priority: "foreground",
      expected: expected(s, input, tools, admission, phase)
    }
  end

  @doc false
  def wire(runtime, input, tools, phase) do
    {:ok, runtime} = Ipse.Usage.Budget.request_config(runtime)

    {kind, target, payload} =
      case phase do
        "embedding.create" ->
          {:ok, payload} = Ipse.Provider.Embedding.request_body(runtime, input["inputs"])
          {"embedding", Ipse.Provider.Embedding.endpoint(runtime), payload}

        "decision.create" ->
          {:ok, payload} =
            Ipse.Provider.Decision.encode(
              Ipse.Provider.Decision.Transport.engine(runtime.provider),
              Ipse.Extension.DecisionCall.neutral(input),
              runtime.model
            )

          {"decision", Ipse.Provider.Decision.Transport.endpoint(runtime), payload}

        _ ->
          {:ok, spec} = Ipse.Provider.Registry.fetch(runtime.provider)

          {"text", apply(spec.adapter, :endpoint, [runtime]),
           apply(spec.adapter, :request_body, [runtime, input, tools])}
      end

    body = Jason.encode!(payload)

    if byte_size(body) <= 8_388_608 do
      %{
        "kind" => kind,
        "target_sha256" => JSON.sha256(target),
        "body_sha256" => JSON.sha256(body)
      }
    end
  rescue
    _ -> nil
  end

  @doc false
  def wire_use(s, caller, phase, admission, expected, facts) do
    with true <- s.task != nil,
         true <- caller == s.task.pid or Session.Resources.authorized_effect?(s.task.pid, caller),
         {:ok, runtime, input, tools, ^admission} <- view(s, phase),
         true <- binding_current?(s, phase, expected),
         true <- is_map(facts) and facts === wire(runtime, input, tools, phase),
         {:ok, %{route: _}} <-
           Ipse.InferenceDispatch.selection(
             s.config,
             runtime,
             operation(phase),
             profile(phase, admission)
           ) do
      {:reply, :ok, s}
    else
      _ -> {:reply, {:error, :inference_dispatch_refused}, s}
    end
  rescue
    _ -> {:reply, {:error, :inference_dispatch_refused}, s}
  end

  @doc false
  def document_admit(s, caller, phase, admission, expected, wire, sources) do
    with true <- phase == "embedding.create" and not is_nil(document_source(s, phase)),
         {:reply, :ok, next} <- wire_use(s, caller, phase, admission, expected, wire) do
      Session.DocumentEmbedding.admit(next, sources)
    else
      _ -> {:reply, {:error, :document_source_use_refused}, Session.DocumentEmbedding.poison(s)}
    end
  end

  defp document_source(s, "embedding.create") do
    case s do
      %{invocation: %{action: %{intent: %{"request" => %{"source_guard" => _}}}}} ->
        Session.DocumentEmbedding.dispatch_data(s)

      _ ->
        nil
    end
  end

  defp document_source(_, _), do: nil

  @doc false
  def send(data, facts, continuation) do
    with_current(data, fn ->
      with :ok <- current_wire(data, facts),
           true <- experiment_current?(data),
           do: continuation.()
    end)
  end

  @doc false
  def release(data, result, fun) when is_function(fun, 0) do
    Session.Resources.file_effect(fn ->
      with_current(data, fn ->
        with :ok <- current_wire(data, data.wire),
             true <- experiment_current?(data),
             :ok <-
               GenServer.call(
                 data.owner,
                 {:managed_result_admit, data.job_ref, data.phase, data.admission, data.expected,
                  result_digest(result)},
                 5_000
               ),
             true <- experiment_current?(data),
             do: fun.()
      end)
    end)
  end

  defp experiment_current?(data) do
    if is_nil(data[:experiment_expires_at]) do
      true
    else
      now = System.system_time(:millisecond)

      is_integer(data[:experiment_issued_at]) and now >= data.experiment_issued_at and
        now < data.experiment_expires_at
    end
  end

  @doc false
  def result_admit(s, caller, phase, admission, expected, result_sha) do
    with true <- s.task != nil and is_nil(s.managed_result_seal),
         true <- caller == s.task.pid or Session.Resources.authorized_effect?(s.task.pid, caller),
         {:ok, _, _, _, ^admission} <- view(s, phase),
         true <- binding_current?(s, phase, expected),
         true <- JSON.sha256?(result_sha) do
      seal = %{
        request_id: admission["request_id"],
        phase: phase,
        expected: expected,
        result_sha: result_sha
      }

      {:reply, :ok, %{s | managed_result_seal: seal}}
    else
      _ -> {:reply, {:error, :inference_dispatch_refused}, s}
    end
  rescue
    _ -> {:reply, {:error, :inference_dispatch_refused}, s}
  end

  @doc false
  def consume_result(s, phase, result) do
    required =
      case Session.managed_dependencies(s, phase) do
        {:ok, %{dependencies: []}} -> false
        _ -> true
      end

    admission =
      if phase in ["model", "compaction"],
        do: s.active_request,
        else: if(s.extension_model, do: s.extension_model.admission)

    valid =
      case s.managed_result_seal do
        %{request_id: id, phase: ^phase, result_sha: sha} ->
          admission != nil and admission["request_id"] == id and sha == result_digest(result)

        _ ->
          not required
      end

    result =
      if match?({:ok, _, _}, result) and not valid,
        do: {:error, "Managed inference result was not admitted by its owner."},
        else: result

    {result, %{s | managed_result_seal: nil}}
  end

  defp result_digest({:ok, value, usage}),
    do: JSON.digest([%{"value" => value, "usage" => usage}])

  defp result_digest(_), do: nil

  defp with_current(data, fun) do
    context = %{
      config: data.config,
      cwd: data.cwd,
      session_id: data.session_id,
      history_dir: data.history_dir,
      owner: data.owner,
      job_ref: data.job_ref,
      experiment_ticket: data[:experiment_ticket],
      source_binding: {:inference, data.phase, data.expected}
    }

    Session.ManagedUse.with_dependencies(context, data.managed.dependencies, fn _ -> fun.() end)
  catch
    _, _ -> {:error, :inference_dispatch_refused}
  end

  defp current_wire(data, facts),
    do:
      GenServer.call(
        data.owner,
        {:inference_wire_use, data.job_ref, data.phase, data.admission, data.expected, facts},
        5_000
      )

  def gate(owner, job, data, facts) do
    append = fn ->
      GenServer.call(
        owner,
        {:inference_dispatch_intent, job, data.phase, data.admission, data.expected, facts},
        5_000
      )
    end

    descriptor = data.config[:semantic_admission]

    managed = Map.get(data, :managed, %{dependencies: []})

    cond do
      not is_map(managed) or not is_list(managed[:dependencies]) ->
        {:error, :inference_dispatch_refused}

      managed.dependencies != [] and not is_map(data[:wire]) ->
        {:error, :inference_dispatch_refused}

      managed.dependencies != [] ->
        context = %{
          config: data.config,
          cwd: data.cwd,
          session_id: data.session_id,
          history_dir: data.history_dir,
          owner: owner,
          job_ref: job,
          source_binding: {:inference, data.phase, data.expected}
        }

        Session.ManagedUse.with_dependencies(context, managed.dependencies, fn _ -> append.() end)

      is_map(descriptor) and descriptor["pin"] != nil ->
        pin = descriptor["pin"]

        with {:ok, _} <- SemanticAdmission.context(data.config, data.session_id, 0) do
          ProjectIdentity.with_binding(
            data.config[:home],
            data.cwd,
            descriptor["binding"],
            fn _ ->
              Consent.with_policy(
                SemanticAdmission.control_root(data.config[:home]),
                pin["project_id"],
                pin["epoch"],
                pin["policy_sha256"],
                System.system_time(:millisecond),
                fn _ -> append.() end
              )
            end
          )
        end

      true ->
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
         true <- expected(s, input, tools, current, phase) === expected,
         {:ok, %{route: route}} <-
           Ipse.InferenceDispatch.selection(
             s.config,
             runtime,
             operation(phase),
             profile(phase, current)
           ),
         true <- is_map(facts) and facts["route"] === route,
         true <- id?(facts["reservation_id"]),
         true <- pin_live?(s),
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
           }),
         true <- valid_intent?(event, current) do
      Session.record(s, event)
      {:reply, {:ok, %{"intent_id" => event["intent_id"]}}, Session.managed_event(s, event)}
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

  @doc false
  def binding_current?(s, phase, expected) do
    with {:ok, _, input, tools, admission} <- view(s, phase) do
      expected(s, input, tools, admission, phase) === expected
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp view(s, phase) when phase in ["model", "compaction"],
    do: Session.Turn.dispatch_view(s, phase)

  defp view(s, phase), do: Session.Invocation.dispatch_view(s, phase)

  defp pin_live?(s) do
    descriptor = s.config[:semantic_admission]

    is_nil(descriptor) or is_nil(descriptor["pin"]) or
      match?({:ok, _}, SemanticAdmission.context(s.config, s.id, 0))
  end

  defp expected(s, input, tools, admission, phase) do
    {:ok, mode} = Mode.capture(s.config)

    %{
      "admission_sha256" => JSON.digest([admission]),
      "input_sha256" => JSON.digest([input]),
      "tools_sha256" => JSON.digest([tools]),
      "source_sha256" => source_digest(s, phase),
      "mode_sha256" => JSON.digest([mode]),
      "pin_sha256" => JSON.digest([s.config[:semantic_admission]])
    }
  end

  defp managed_snapshot(s, phase) do
    case Session.managed_dependencies(s, phase) do
      {:ok, snapshot} -> snapshot
      _ -> nil
    end
  end

  defp source_digest(s, phase) do
    source = Session.source_snapshot(s)

    case managed_snapshot(s, phase) do
      %{dependencies: [_ | _], sha256: digest} -> JSON.digest([source, digest])
      %{dependencies: []} -> JSON.digest([source])
      _ -> JSON.digest([source, "managed_lineage_unavailable"])
    end
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
      Enum.sort(Map.keys(event)) == Enum.sort(@keys) and event["type"] == @event_type and
      event["version"] === 1 and
      event["phase"] in @phases and id?(event["intent_id"]) and id?(event["reservation_id"]) and
      event["request_id"] === admission["request_id"] and
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
          Ipse.Usage.operation(admission) == "decision" and
            event["service_id"] === admission["service_id"]
      end
  rescue
    _ -> false
  end

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
