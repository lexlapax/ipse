defmodule Ipse.InferenceSlots do
  @moduledoc """
  Internal protected operator-scoped inference admission, independent of project consent.

  Each explicitly selected service has one native lease across models, projects,
  aliases and API paths. This schedules Ipse dispatches, not arbitrary daemon
  clients. A retained admitted marker survives timeout, owner/native death and
  local socket cleanup. Acquiring its now-free OS lock never proves remote
  quiescence; only a trusted known-terminal callback or exact operator
  reconciliation can clear it. This module authenticates neither callback
  classification nor operator interaction. The owning provider/UI must do that.

  `run/5` releases the native lease before returning: tools, project consent and
  storage publication follow outside this callback. Calling under project locks
  or recursively is refused. Ordinary unselected Sessions need not invoke this
  API. Explicit waits are at most 60 seconds and callback deadlines at most 100
  seconds; larger configured deadlines refuse rather than being shortened.
  Persisted service aliases cannot be rebound by editing configuration.

  One protected 1 MiB tree includes the ledger, all eight fixed lease directories,
  their retained locks and staging. The limited filesystem profile is the same
  fail-closed native profile used by the other protected ledgers. Trusted core
  BEAM callers and cooperative protected operator state are assumed; process
  messages and structs do not isolate adversarial code in this VM.
  """
  alias Ipse.{
    JSON,
    InferenceSlots.Ledger,
    InferenceSlots.Store,
    Session.Resources,
    Runner.Transaction
  }

  alias Ipse.Extension.SemanticRoutes
  @held {__MODULE__, :active}
  @handles {__MODULE__, :handles}
  @error {:error, :invalid_service_slot_request}
  @meta ~w(session_id project_id request_sha256 priority)
  @selectors ~w(operation profile processing_region storage_region cache_retention account_controls)

  defmodule Handle do
    @moduledoc false
    @enforce_keys [
      :owner,
      :worker,
      :scope,
      :ref,
      :monitor,
      :scope_monitor,
      :watchdog,
      :id,
      :service_id,
      :wait_deadline
    ]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(_, _), do: "#InferenceSlots.Handle<private>"
    end
  end

  def run(config, selector, meta, opts, fun) do
    with {:ok, handle} <- start(config, selector, meta, opts, fun), do: await(handle)
  end

  def start(config, selector, meta, opts, fun) do
    with :ok <- assert_order(),
         true <- map_size(Process.get(@handles, %{})) < 64,
         true <- valid_options?(opts) and is_function(fun, 1),
         true <- keys?(meta, @meta) and keys?(selector, @selectors),
         {:ok, [route]} <- SemanticRoutes.resolve(config, [selector]),
         full_meta =
           Map.merge(meta, %{
             "dispatch_timeout_ms" => opts[:dispatch_timeout_ms],
             "route_sha256" => JSON.digest([route])
           }),
         true <- Ledger.meta?(full_meta),
         {:ok, scope} <- Resources.start(self()) do
      owner = self()
      upstream = Resources.file_effect_owner()
      ref = make_ref()
      id = Ipse.Usage.id()
      deadline = mono() + opts[:wait_ms]

      {worker, monitor} =
        spawn_monitor(fn ->
          receive do
            {:begin_service_slot, ^ref} ->
              Resources.bind(scope)
              :ok = Resources.bind_effect_owner(upstream)
              Process.put(@held, true)

              watchdog =
                receive do
                  {:service_watchdog, pid} -> pid
                end

              result =
                work(
                  config,
                  route,
                  full_meta,
                  opts |> Keyword.put(:watchdog, watchdog) |> Keyword.put(:upstream, upstream),
                  fun,
                  owner,
                  ref,
                  id,
                  deadline
                )

              send(owner, {ref, :result, result})

              receive do
                {^ref, :finished} -> :ok
              after
                10_000 -> :ok
              end
          end
        end)

      case attach(scope, worker) do
        :ok ->
          watchdog = spawn(fn -> watchdog(owner, worker, scope, ref, deadline) end)
          scope_monitor = Process.monitor(scope)
          send(worker, {:service_watchdog, watchdog})
          send(worker, {:begin_service_slot, ref})

          handle = %Handle{
            owner: owner,
            worker: worker,
            scope: scope,
            ref: ref,
            monitor: monitor,
            scope_monitor: scope_monitor,
            watchdog: watchdog,
            id: id,
            service_id: route["service_id"],
            wait_deadline: deadline
          }

          Process.put(@handles, Map.put(Process.get(@handles, %{}), ref, handle))
          {:ok, handle}

        _ ->
          Process.exit(worker, :kill)
          Resources.close(scope)
          Process.demonitor(monitor, [:flush])
          {:error, :service_slot_unavailable}
      end
    else
      {:error, _} = error -> error
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def await(%Handle{owner: owner} = h) when owner == self() do
    if valid_handle?(h), do: await(h, :waiting, h.wait_deadline, nil), else: @error
  end

  def await(_), do: @error

  def cancel(%Handle{owner: owner} = handle) when owner == self() do
    if valid_handle?(handle) do
      send(self(), {:cancel_service_slot, handle.ref})
      send(handle.worker, {:cancel_service_slot, handle.ref, :service_cancelled})
      send(handle.watchdog, {handle.ref, :cancel})
      :ok
    else
      @error
    end
  end

  def cancel(_), do: @error

  @doc "Bounded protected facts; admitted work is conservatively reported as unresolved."
  def status(config, opts) do
    with :ok <- assert_order(), {:ok, context} <- Store.context(config[:home], opts[:cwd]) do
      Store.transaction(context, fn state -> {:read, state} end)
    end
  end

  @doc "Only a trusted operator UI may supply a verified exact-reservation reconciliation receipt."
  def reconcile(config, service_id, id, revision, receipt, opts) do
    with :ok <- assert_order(),
         true <- Ledger.receipt?(receipt),
         {:ok, context} <- Store.context(config[:home], opts[:cwd]),
         {:ok, slot} <-
           Store.transaction(context, fn state -> {:read, Ledger.slot(state, service_id)} end),
         true <- is_integer(slot),
         {:ok, cap} <- Store.acquire_service(context, slot, 10_000) do
      result =
        Store.transaction(context, fn state ->
          Ledger.reconcile(state, service_id, id, revision, receipt, wall())
        end)

      release(cap, result)
    else
      {:error, _} = error -> error
      {:unknown, _} = unknown -> unknown
      _ -> {:error, :service_reconciliation_refused}
    end
  end

  def assert_order do
    if Process.get(@held, false) != false or Process.get({Transaction, :controller}) != nil or
         Enum.any?(
           [Ipse.Extension.ProjectIdentity, Ipse.Extension.Consent, Ipse.Extension.Collection],
           fn module -> Process.get({module, :lock_held}, false) != false end
         ) do
      {:error, :service_slot_lock_order}
    else
      :ok
    end
  end

  defp work(config, route, meta, opts, fun, owner, ref, id, deadline) do
    with {:ok, context} <- Store.context(config[:home], opts[:cwd]),
         remaining when remaining > 0 <- deadline - mono(),
         origins = get_in(config, [:inference_services, route["service_id"], "origins"]),
         {:ok, _} <-
           Store.transaction(context, fn state ->
             Ledger.enqueue(state, route["service_id"], origins, id, meta, wall(), remaining)
           end) do
      wait(context, route, meta, opts, fun, owner, ref, id, deadline)
    else
      {:error, _} = error -> error
      {:unknown, _} -> unknown(route, id)
      _ -> {:error, :service_wait_timeout}
    end
  rescue
    _ -> unknown(route, id)
  catch
    _, _ -> unknown(route, id)
  end

  defp wait(context, route, meta, opts, fun, owner, ref, id, deadline) do
    cancellation = cancellation(ref)

    cond do
      cancellation != nil ->
        cancel_waiting(context, id, cancellation)

      mono() >= deadline ->
        cancel_waiting(context, id, :service_wait_timeout)

      true ->
        case Store.transaction(context, fn state ->
               {:read,
                {Ledger.eligible?(state, id, wall()), Ledger.slot(state, route["service_id"])}}
             end) do
          {:ok, {true, slot}} ->
            case Store.acquire_service(context, slot, meta["dispatch_timeout_ms"] + 10_000) do
              {:ok, cap} ->
                admitted(context, cap, route, meta, opts, fun, owner, ref, id, deadline)

              {:error, :transaction_busy} ->
                pause(context, route, meta, opts, fun, owner, ref, id, deadline)

              _ ->
                unknown(route, id)
            end

          {:ok, {false, _}} ->
            pause(context, route, meta, opts, fun, owner, ref, id, deadline)

          {:error, :service_busy} ->
            pause(context, route, meta, opts, fun, owner, ref, id, deadline)

          _ ->
            unknown(route, id)
        end
    end
  end

  defp pause(context, route, meta, opts, fun, owner, ref, id, deadline) do
    notify(owner, opts[:notify], ref, %{
      "state" => "waiting",
      "priority" => meta["priority"],
      "remaining_ms" => max(deadline - mono(), 0)
    })

    receive do
      {:cancel_service_slot, ^ref, reason}
      when reason in [:service_cancelled, :service_wait_timeout] ->
        cancel_waiting(context, id, reason)
    after
      min(max(deadline - mono(), 0), 500) ->
        wait(context, route, meta, opts, fun, owner, ref, id, deadline)
    end
  end

  defp admitted(context, cap, route, meta, opts, fun, owner, ref, id, deadline) do
    result =
      Store.transaction(context, fn state ->
        cond do
          not Ledger.eligible?(state, id, wall()) ->
            {:read, :not_eligible}

          is_map(get_in(state, ["services", route["service_id"], "active"])) ->
            {:read,
             {:unresolved, get_in(state, ["services", route["service_id"], "active", "id"])}}

          true ->
            Ledger.admit(state, id, wall())
        end
      end)

    case result do
      {:ok, :not_eligible} ->
        case release(cap, :ok) do
          :ok -> wait(context, route, meta, opts, fun, owner, ref, id, deadline)
          _ -> unknown(route, id)
        end

      {:ok, {:unresolved, active_id}} ->
        _ = cancel_waiting(context, id, :service_unresolved)

        release(
          cap,
          {:unknown, %{"service_id" => route["service_id"], "reservation_id" => active_id}}
        )

      {:ok, _} ->
        cancellation = cancellation(ref)

        result =
          if cancellation != nil or mono() >= deadline do
            case Store.transaction(context, fn state ->
                   Ledger.cancel_unstarted(state, route["service_id"], id, wall())
                 end) do
              {:ok, _} -> {:error, cancellation || :service_wait_timeout}
              _ -> unknown(route, id)
            end
          else
            dispatch_deadline = mono() + meta["dispatch_timeout_ms"]
            send(owner, {ref, :admitted, cap.controller, dispatch_deadline})

            send(
              opts[:watchdog],
              {ref, :admitted, cap.controller, dispatch_deadline}
            )

            notify(owner, opts[:notify], ref, %{
              "state" => "admitted",
              "reservation_id" => id,
              "service_id" => route["service_id"]
            })

            invoke(context, cap, route, fun, id, owner, opts[:upstream], ref, dispatch_deadline)
          end

        send(owner, {ref, :releasing})
        send(opts[:watchdog], {ref, :releasing})
        release(cap, result)

      _ ->
        release(cap, unknown(route, id))
    end
  end

  defp invoke(context, cap, route, fun, id, owner, upstream, ref, deadline) do
    case fun.(%{"reservation_id" => id, "route" => route}) do
      {:settled, value} ->
        with true <-
               mono() < deadline and cancellation(ref) == nil and Process.alive?(owner) and
                 Process.alive?(upstream),
             :ok <- Transaction.check(cap),
             {:ok, _} <-
               Store.transaction(context, fn state ->
                 Ledger.settle(state, route["service_id"], id, wall())
               end),
             do: {:ok, value},
             else: (_ -> unknown(route, id))

      _ ->
        unknown(route, id)
    end
  rescue
    _ -> unknown(route, id)
  catch
    _, _ -> unknown(route, id)
  end

  defp cancel_waiting(context, id, reason) do
    case Store.transaction(context, fn state -> Ledger.cancel_waiting(state, id) end) do
      {:ok, _} -> {:error, reason}
      _ -> {:unknown, %{"reservation_id" => id}}
    end
  end

  defp await(h, phase, deadline, native_monitor) do
    receive do
      {ref, :result, result} when ref == h.ref ->
        finish(h, result, native_monitor)

      {ref, :admitted, controller, dispatch_deadline} when ref == h.ref ->
        if phase == :cancelling do
          terminate(h, native_monitor)
        else
          if native_monitor, do: Process.demonitor(native_monitor, [:flush])
          await(h, :admitted, dispatch_deadline, Process.monitor(controller))
        end

      {ref, :releasing} when ref == h.ref ->
        if native_monitor, do: Process.demonitor(native_monitor, [:flush])
        await(h, :releasing, mono() + 5_000, nil)

      {ref, :status, _} when ref == h.ref ->
        await(h, phase, deadline, native_monitor)

      {:inference_slot, ref, _} when ref == h.ref ->
        await(h, phase, deadline, native_monitor)

      {:cancel_service_slot, ref} when ref == h.ref ->
        if phase == :waiting do
          send(h.worker, {:cancel_service_slot, h.ref, :service_cancelled})
          await(h, :cancelling, mono() + 5_000, native_monitor)
        else
          terminate(h, native_monitor)
        end

      {:DOWN, monitor, :process, _, _} when monitor == native_monitor ->
        await(h, :native_lost, mono() + 2_000, nil)

      {:DOWN, monitor, :process, _, _} when monitor in [h.monitor, h.scope_monitor] ->
        terminate(h, native_monitor)
    after
      max(deadline - mono(), 0) ->
        if phase == :waiting do
          send(h.worker, {:cancel_service_slot, h.ref, :service_wait_timeout})
          await(h, :cancelling, mono() + 5_000, native_monitor)
        else
          terminate(h, native_monitor)
        end
    end
  end

  defp finish(h, result, native_monitor) do
    forget_handle(h)
    if native_monitor, do: Process.demonitor(native_monitor, [:flush])
    cleanup = Resources.finish(h.scope)
    send(h.worker, {h.ref, :finished})
    Resources.close(h.scope)
    Process.demonitor(h.monitor, [:flush])
    Process.demonitor(h.scope_monitor, [:flush])

    if cleanup == :ok,
      do: result,
      else: {:unknown, %{"service_id" => h.service_id, "reservation_id" => h.id}}
  end

  defp terminate(h, native_monitor) do
    forget_handle(h)
    if native_monitor, do: Process.demonitor(native_monitor, [:flush])
    Process.exit(h.worker, :kill)
    Resources.stop_async(h.scope)
    _ = Resources.close(h.scope)
    Process.demonitor(h.monitor, [:flush])
    Process.demonitor(h.scope_monitor, [:flush])
    {:unknown, %{"service_id" => h.service_id, "reservation_id" => h.id}}
  end

  defp attach(scope, worker) do
    Resources.attach(scope, worker)
  catch
    :exit, _ -> {:error, :service_slot_unavailable}
  end

  defp watchdog(owner, worker, scope, ref, deadline) do
    Process.flag(:trap_exit, true)
    Process.link(worker)
    monitors = Enum.map([owner, worker, scope], &Process.monitor/1)
    watchdog_wait(worker, scope, ref, :waiting, deadline, monitors, nil)
  end

  defp watchdog_wait(
         worker,
         scope,
         ref,
         phase,
         deadline,
         [owner_ref, worker_ref, scope_ref] = monitors,
         native
       ) do
    receive do
      {^ref, :cancel} ->
        if phase == :waiting do
          send(worker, {:cancel_service_slot, ref, :service_cancelled})
          watchdog_wait(worker, scope, ref, :cancelling, mono() + 5_000, monitors, native)
        else
          stop_worker(scope, worker)
        end

      {^ref, :admitted, controller, dispatch_deadline} ->
        if phase == :cancelling do
          stop_worker(scope, worker)
        else
          if native, do: Process.demonitor(native, [:flush])

          watchdog_wait(
            worker,
            scope,
            ref,
            :admitted,
            dispatch_deadline,
            monitors,
            Process.monitor(controller)
          )
        end

      {^ref, :releasing} ->
        if native, do: Process.demonitor(native, [:flush])
        watchdog_wait(worker, scope, ref, :releasing, mono() + 5_000, monitors, nil)

      {:DOWN, monitor, :process, _, _} when monitor == native ->
        watchdog_wait(worker, scope, ref, :native_lost, mono() + 2_000, monitors, nil)

      {:DOWN, monitor, :process, _, _} when monitor in [owner_ref, worker_ref, scope_ref] ->
        stop_worker(scope, worker)

      {:EXIT, ^worker, _} ->
        stop_worker(scope, worker)
    after
      max(deadline - mono(), 0) ->
        if phase == :waiting do
          send(worker, {:cancel_service_slot, ref, :service_wait_timeout})
          watchdog_wait(worker, scope, ref, :cancelling, mono() + 5_000, monitors, native)
        else
          stop_worker(scope, worker)
        end
    end
  end

  defp stop_worker(scope, worker) do
    Process.exit(worker, :kill)
    Resources.stop_async(scope)
  end

  defp valid_handle?(handle), do: Process.get(@handles, %{})[handle.ref] === handle

  defp forget_handle(handle),
    do: Process.put(@handles, Map.delete(Process.get(@handles, %{}), handle.ref))

  defp release(cap, result) do
    case {Transaction.check(cap), Transaction.release(cap)} do
      {:ok, :ok} -> result
      _ -> {:unknown, :service_state_unconfirmed}
    end
  end

  defp cancellation(ref) do
    receive do
      {:cancel_service_slot, ^ref, reason}
      when reason in [:service_cancelled, :service_wait_timeout] ->
        reason
    after
      0 -> nil
    end
  end

  defp notify(owner, notify, ref, status) do
    send(owner, {ref, :status, status})
    if is_pid(notify), do: send(notify, {:inference_slot, ref, status})
  end

  defp unknown(route, id),
    do: {:unknown, %{"service_id" => route["service_id"], "reservation_id" => id}}

  defp valid_options?(opts),
    do:
      Keyword.keyword?(opts) and
        Keyword.keys(opts) -- [:cwd, :wait_ms, :dispatch_timeout_ms, :notify] == [] and
        length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
        is_integer(opts[:wait_ms]) and opts[:wait_ms] in 1..60_000 and
        is_integer(opts[:dispatch_timeout_ms]) and opts[:dispatch_timeout_ms] in 1..100_000 and
        (is_nil(opts[:notify]) or is_pid(opts[:notify]))

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp mono, do: System.monotonic_time(:millisecond)
  defp wall, do: System.system_time(:millisecond)
end
