defmodule Ipse.InferenceDispatch do
  @moduledoc false
  alias Ipse.{InferenceSlots, JSON, Session.Resources}
  alias Ipse.Extension.SemanticRoutes
  alias Ipse.Provider.CompletionWitness
  @labels ~w(processing_region storage_region cache_retention account_controls)

  # The caller is the existing Session-owned inference task. It alone runs the
  # final gate, retaining the Session's ordinary caller/job checks. The separate
  # coordinator and actual slot callback never acquire that authority by ancestry.
  def run(config, runtime, operation, profile, context, emit, final_gate, execute) do
    with {:ok, selected} <- selection(config, runtime, operation, profile) do
      case selected do
        :unregistered ->
          Ipse.Usage.Budget.run(runtime, context.admission, emit, fn admitted, guarded ->
            execute.(admitted, guarded, nil)
          end)

        %{selector: selector, route: route, target: target} ->
          selected(
            config,
            runtime,
            operation,
            context,
            emit,
            final_gate,
            execute,
            selector,
            route,
            target
          )
      end
    else
      _ -> {:error, "Inference service selection is invalid; no provider request was dispatched."}
    end
  end

  def selection(_config, %{provider: :demo}, "main", nil), do: {:ok, :unregistered}

  def selection(config, runtime, operation, profile) do
    registry = config[:inference_services] || %{}

    with :ok <- Ipse.Config.Semantics.validate_services(registry),
         {:ok, target, destination} <- destination(runtime, operation) do
      case for {id, entry} <- registry, destination["origin"] in entry["origins"], do: id do
        [] ->
          {:ok, :unregistered}

        [_] ->
          selector =
            Map.merge(Map.new(@labels, &{&1, nil}), %{
              "operation" => operation,
              "profile" => profile
            })

          with {:ok, [route]} <- SemanticRoutes.resolve(config, [selector]),
               true <-
                 route["endpoint"] == target and route["model"] == runtime.model and
                   route["provider"] == to_string(runtime.provider) and
                   route["billing_mode"] == Ipse.Usage.billing_mode(runtime.provider) do
            {:ok, %{selector: selector, route: route, target: target}}
          else
            _ -> {:error, :inference_route_changed}
          end

        _ ->
          {:error, :inference_service_ambiguous}
      end
    end
  rescue
    _ -> {:error, :inference_route_unavailable}
  end

  defp selected(
         config,
         runtime,
         operation,
         context,
         emit,
         final_gate,
         execute,
         selector,
         route,
         target
       ) do
    timeout = runtime[:timeout_ms] || 120_000

    if not (is_integer(timeout) and timeout in 1..100_000) do
      {:error,
       "The selected inference service requires a configured request timeout at most 100000 ms; the current timeout is unsupported. Review the operator configuration. No provider request was dispatched."}
    else
      caller = self()
      upstream = Resources.file_effect_owner()
      ref = make_ref()
      wait_ms = Map.get(context, :wait_ms, 60_000)
      deadline = mono() + wait_ms + timeout + 20_000
      meta = Map.take(context, [:session_id, :project_id, :request_sha256, :priority])
      meta = Map.new(meta, fn {key, value} -> {Atom.to_string(key), value} end)

      task =
        Resources.async(fn ->
          :ok = Resources.bind_effect_owner(upstream)
          coordinator = self()

          before = fn facts ->
            challenge = make_ref()
            monitor = Process.monitor(caller)
            send(caller, {ref, :gate, self(), challenge, facts})

            try do
              receive do
                {^ref, ^challenge, response} -> response
                {:DOWN, ^monitor, :process, ^caller, _} -> {:error, :dispatch_owner_lost}
              after
                5_000 -> {:error, :dispatch_gate_timeout}
              end
            after
              Process.demonitor(monitor, [:flush])
            end
          end

          opts = [
            cwd: context.cwd,
            wait_ms: wait_ms,
            dispatch_timeout_ms: timeout,
            notify: caller,
            before_admit: before
          ]

          callback = fn facts ->
            with :ok <- InferenceSlots.current_check() do
              buffer_key = {__MODULE__, ref}

              Process.put(buffer_key, %{
                chunks: [],
                bytes: 0,
                count: 0,
                entered: false,
                overflow: false,
                started: mono()
              })

              buffered_emit = fn
                {:text, text} when is_binary(text) and byte_size(text) > 0 ->
                  buffer = Process.get(buffer_key)

                  if buffer.count == 0,
                    do:
                      emit.(
                        {:inference_service_timing,
                         %{"upstream_first_text_ms" => mono() - buffer.started}}
                      )

                  if buffer.count < 8192 and buffer.bytes + byte_size(text) <= 8_388_608 do
                    Process.put(buffer_key, %{
                      buffer
                      | chunks: [text | buffer.chunks],
                        bytes: buffer.bytes + byte_size(text),
                        count: buffer.count + 1
                    })
                  else
                    Process.put(buffer_key, %{buffer | overflow: true})
                  end

                {:text, _} ->
                  :ok

                event ->
                  emit.(event)
              end

              try do
                {result, terminal?} =
                  CompletionWitness.capture(runtime, kind(operation), target, fn ->
                    Ipse.Usage.Budget.run(runtime, context.admission, buffered_emit, fn admitted,
                                                                                        guarded ->
                      with :ok <- InferenceSlots.current_check() do
                        Process.put(buffer_key, %{Process.get(buffer_key) | entered: true})
                        execute.(admitted, guarded, facts[:prepared])
                      end
                    end)
                  end)

                buffer = Process.get(buffer_key)

                result =
                  if buffer.overflow,
                    do:
                      {:error,
                       "Selected inference text exceeded its private publication buffer; no assistant text was published."},
                    else: result

                send(coordinator, {ref, :provider_result, result, Enum.reverse(buffer.chunks)})

                cond do
                  not buffer.entered ->
                    {:unstarted, result}

                  terminal? ->
                    {:settled, result}

                  true ->
                    if match?({:ok, _, _}, result), do: emit.({:provider_usage, elem(result, 2)})
                    :unknown
                end
              after
                Process.delete(buffer_key)
              end
            end
          end

          try do
            outcome = InferenceSlots.run(config, selector, meta, opts, callback)

            {original, chunks} =
              receive do
                {^ref, :provider_result, result, chunks} -> {result, chunks}
              after
                0 -> {nil, []}
              end

            {:dispatch_result, outcome, original, chunks}
          rescue
            _ -> {:dispatch_result, {:unknown, %{}}, nil, []}
          catch
            _, _ -> {:dispatch_result, {:unknown, %{}}, nil, []}
          end
        end)

      try do
        await(task, ref, route, final_gate, emit, deadline, nil)
      after
        Task.shutdown(task, :brutal_kill)
      end
    end
  end

  defp await(task, ref, route, gate, emit, deadline, original) do
    receive do
      {^ref, :gate, worker, challenge, facts} ->
        response =
          if facts["route"] == route and mono() < deadline,
            do: gate.(facts),
            else: {:error, :inference_route_changed}

        send(worker, {ref, challenge, response})
        await(task, ref, route, gate, emit, deadline, original)

      {:inference_slot, _, status} ->
        emit.({:inference_service_status, Map.put(status, "service_id", route["service_id"])})
        await(task, ref, route, gate, emit, deadline, original)

      {monitor, {:dispatch_result, {:ok, result}, _, chunks}} when monitor == task.ref ->
        Process.demonitor(task.ref, [:flush])
        if match?({:ok, _, _}, result), do: Enum.each(chunks, &emit.({:text, &1}))
        result

      {monitor, {:dispatch_result, {:error, reason}, _, _}} when monitor == task.ref ->
        Process.demonitor(task.ref, [:flush])
        local_error(reason)

      {monitor, {:dispatch_result, _, original, _}} when monitor == task.ref ->
        Process.demonitor(task.ref, [:flush])
        unknown(route, original)

      {:DOWN, monitor, :process, _, _} when monitor == task.ref ->
        unknown(route, original)
    after
      max(deadline - mono(), 0) -> unknown(route, original)
    end
  end

  defp local_error({:service_gate_refused, _}),
    do:
      {:error,
       "Inference dispatch validation changed while waiting; no provider request was dispatched."}

  defp local_error(:service_wait_timeout),
    do:
      {:error,
       "Inference service wait expired before dispatch; no provider request was dispatched."}

  defp local_error(:service_cancelled),
    do: {:error, "Inference service wait was cancelled before dispatch."}

  defp local_error(:service_filesystem_unsupported),
    do:
      {:error,
       "The selected inference service ledger filesystem is unsupported; no provider request was dispatched."}

  defp local_error(_),
    do:
      {:error, "Inference service admission is unavailable; no provider request was dispatched."}

  defp unknown(route, original) do
    detail =
      case original do
        {:error, message} when is_binary(message) -> " " <> String.slice(message, 0, 500)
        {:error, reason} when is_atom(reason) -> " " <> Atom.to_string(reason)
        _ -> ""
      end

    {:error,
     "Inference service #{route["service_id"]} has an unknown outcome. Inspect and reconcile its exact reservation before continuing; no request was replayed." <>
       detail}
  end

  defp destination(runtime, operation) do
    {target, facts} =
      case operation do
        "embedding.create" ->
          {Ipse.Provider.Embedding.endpoint(runtime),
           Ipse.Provider.Embedding.destination(runtime)}

        "decision.create" ->
          {Ipse.Provider.Decision.Transport.endpoint(runtime),
           Ipse.Provider.Decision.Transport.destination(runtime)}

        _ ->
          {:ok, spec} = Ipse.Provider.Registry.fetch(runtime.provider)
          {apply(spec.adapter, :endpoint, [runtime]), Ipse.Provider.destination(runtime)}
      end

    with {:ok, facts} <- facts,
         true <- JSON.sha256(target) == facts["target_sha256"],
         do: {:ok, target, facts},
         else: (_ -> {:error, :invalid_inference_destination})
  end

  defp kind("embedding.create"), do: :embedding
  defp kind("decision.create"), do: :decision
  defp kind(_), do: :text
  defp mono, do: System.monotonic_time(:millisecond)
end
