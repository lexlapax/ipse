defmodule Ipse.Extension.Worker do
  @moduledoc "Owner-monitored independent VM bridge; never loads an artifact in the host."
  use GenServer
  alias Ipse.Extension.{Artifact, Registry}
  alias Ipse.Extension.ResultPublication
  @limit 32_768
  @traffic_limit 67_108_864

  @doc "Explicit executable admission. :trusted must equal the pinned digest."
  def start(opts),
    do:
      GenServer.start(
        __MODULE__,
        Keyword.put(opts, :cleanup_scope, Ipse.Session.Resources.current())
      )

  def call(pid, stage, payload, timeout_ms \\ 5_000) do
    GenServer.call(pid, {:invoke, stage, payload, timeout_ms}, :infinity)
  catch
    :exit, _ -> {:error, :extension_unavailable}
  end

  def close(pid, timeout \\ 3_000) do
    GenServer.call(pid, :close, timeout)
  catch
    :exit, _ -> {:error, :cleanup_unconfirmed}
  end

  @doc false
  # Private trusted-host transport. Preparation supplies no Session authority;
  # the caller must hold and settle the complete source/policy scope separately.
  def prepare_input(pid, stage, payload, timeout \\ 5_000),
    do: input_call(pid, {:prepare_input, stage, payload, timeout})

  @doc false
  def input_binding(pid, handle, stage, payload),
    do: input_call(pid, {:input_binding, handle, stage, payload}, 1_000)

  @doc false
  def bind_stdin(pid, handle, wall), do: input_call(pid, {:bind_stdin, handle, wall})

  @doc false
  def export_stdin(pid, handle, recipient),
    do: input_call(pid, {:export_stdin, handle, recipient})

  @doc false
  def settle_stdin(pid, handle), do: input_call(pid, {:settle_stdin, handle})

  @doc false
  def await_input(pid, handle), do: input_call(pid, {:await_input, handle})

  defp input_call(pid, request, timeout \\ :infinity) do
    GenServer.call(pid, request, timeout)
  catch
    :exit, _ -> {:error, :extension_input_unavailable}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(opts, :owner)
    digest = Keyword.fetch!(opts, :digest)
    options = Keyword.get(opts, :options, %{})
    protected_input = Keyword.get(opts, :protected_input, false)

    with true <- is_pid(owner) and Process.alive?(owner),
         true <- is_boolean(protected_input),
         true <-
           is_nil(opts[:input_session]) or
             (is_pid(opts[:input_session]) and Process.alive?(opts[:input_session])),
         true <- Keyword.get(opts, :trusted) == digest,
         {:ok, artifact} <- Registry.lookup(Keyword.fetch!(opts, :store), digest),
         true <- is_nil(opts[:artifact_sha256]) or opts[:artifact_sha256] == artifact.digest,
         true <- Artifact.compatible?(artifact.manifest),
         true <-
           Ipse.Extension.Catalog.sdk_capabilities?(
             artifact.manifest["sdk"],
             artifact.manifest["capabilities"]
           ),
         :ok <- Ipse.JSON.validate_arguments(artifact.manifest["options_schema"], options),
         {:ok, executable, args, environment} <- launch(artifact),
         {:ok, port, cleanup_ticket} <-
           Ipse.Runner.open_owned_stdio(
             :extension,
             opts[:cleanup_scope],
             executable,
             args,
             artifact.path,
             environment,
             86_400_000,
             protected_supervisor: protected_input
           ) do
      {:ok,
       %{
         owner: owner,
         owner_ref: Process.monitor(owner),
         port: port,
         cleanup_ticket: cleanup_ticket,
         cleanup_lease: opts[:cleanup_lease],
         options: options,
         manifest: artifact.manifest,
         artifact: artifact.digest,
         protected_input: protected_input,
         input_session: opts[:input_session],
         input: nil,
         pending: nil,
         sequence: 0,
         ready: false,
         origin: nil,
         producer: nil,
         awaiting_action: false,
         finished: false,
         buffer: <<>>,
         content: <<>>,
         traffic: 0
       }}
    else
      _ -> {:stop, :extension_admission_refused}
    end
  rescue
    _ -> {:stop, :extension_admission_refused}
  end

  @impl true
  def handle_call({:invoke, _stage, _payload, _timeout}, _from, %{pending: pending} = state)
      when not is_nil(pending) do
    {:reply, {:error, :extension_busy}, state}
  end

  def handle_call({:invoke, stage, payload, timeout}, from, state) do
    with {:ok, id, frame} <- encode_request(state, stage, payload, timeout),
         :ok <- Ipse.Runner.send_stdio(state.port, frame) do
      {:noreply, pending_request(state, id, stage, payload, timeout, from)}
    else
      _ -> {:reply, {:error, :invalid_extension_request}, state}
    end
  end

  def handle_call({:prepare_input, stage, payload, timeout}, {caller, _}, %{pending: nil} = state) do
    with true <- state.protected_input and :os.type() == {:unix, :linux},
         true <- input_caller?(state, caller),
         true <- stage != "initialize",
         {:ok, id, frame} <- encode_request(state, stage, payload, timeout),
         {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(state.port, :os_pid) do
      handle = {:worker_input, make_ref()}
      operation = <<id::64, :crypto.strong_rand_bytes(8)::binary>>

      binding = %{
        worker: self(),
        owner: state.owner,
        caller: caller,
        artifact: state.artifact,
        sequence: id,
        operation: operation,
        native_pid: pid,
        stage: stage,
        payload_sha256: Ipse.JSON.digest([payload]),
        frame_sha256: Ipse.JSON.sha256(frame),
        frame: frame
      }

      state = pending_request(state, id, stage, payload, timeout, nil)

      input = %{
        handle: handle,
        caller: caller,
        monitor: Process.monitor(caller),
        binding: Map.put(binding, :deadline, state.pending.deadline),
        phase: :prepared,
        from: nil,
        response: nil
      }

      {:reply, {:ok, handle, input.binding}, %{state | input: input}}
    else
      _ -> {:reply, {:error, :extension_input_unavailable}, state}
    end
  end

  def handle_call(
        {:input_binding, handle, stage, payload},
        {caller, _},
        %{input: %{handle: handle} = input, pending: pending} = state
      ) do
    if (caller == input.caller or caller == state.input_session) and
         stage == pending.stage and payload == pending.payload and input_live?(state),
       do: {:reply, {:ok, input.binding}, state},
       else: {:reply, {:error, :extension_input_unavailable}, state}
  end

  def handle_call(
        {:bind_stdin, handle, wall},
        {caller, _} = from,
        %{input: %{handle: handle, caller: caller, phase: :prepared} = input} = state
      ) do
    remaining = min(state.pending.deadline - now(), 5_000)

    if input_live?(state) and Ipse.JSON.safe_uint?(wall) and
         wall > System.system_time(:millisecond) and
         wall <= System.system_time(:millisecond) + remaining and
         Ipse.Runner.prepare_stdio_share(state.port, input.binding.operation, wall) == :ok do
      binding = Map.put(input.binding, :wall_deadline, wall)
      {:noreply, %{state | input: %{input | phase: :reserving, from: from, binding: binding}}}
    else
      {:reply, {:error, :extension_input_unavailable}, state}
    end
  end

  def handle_call(
        {:export_stdin, handle, recipient},
        {caller, _} = from,
        %{input: %{handle: handle, caller: caller, phase: :reserved} = input} = state
      ) do
    if input_live?(state) and
         Ipse.Runner.export_stdio_share(
           state.port,
           input.binding.operation,
           recipient,
           input.binding.frame
         ) == :ok,
       do: {:noreply, %{state | input: %{input | phase: :exporting, from: from}}},
       else: {:reply, {:error, :extension_input_unavailable}, state}
  end

  def handle_call(
        {:settle_stdin, handle},
        {caller, _} = from,
        %{input: %{handle: handle, caller: caller, phase: :exported} = input} = state
      ) do
    if input_live?(state) and
         Ipse.Runner.settle_stdio_share(state.port, input.binding.operation) == :ok,
       do: {:noreply, %{state | input: %{input | phase: :settling, from: from}}},
       else: {:reply, {:error, :extension_input_unavailable}, state}
  end

  def handle_call(
        {:await_input, handle},
        {caller, _} = from,
        %{input: %{handle: handle, caller: caller, phase: :settled} = input} = state
      ) do
    if input_live?(state) do
      state = %{
        state
        | pending: %{state.pending | from: from},
          input: %{input | phase: :released}
      }

      if is_nil(input.response) do
        {:noreply, state}
      else
        case response(state, input.response) do
          {:ok, next} -> {:noreply, next}
          :error -> stop(state, :invalid_extension_output)
        end
      end
    else
      {:reply, {:error, :extension_input_unavailable}, state}
    end
  end

  def handle_call(request, _from, state)
      when elem(request, 0) in [
             :prepare_input,
             :input_binding,
             :bind_stdin,
             :export_stdin,
             :settle_stdin,
             :await_input
           ],
      do: {:reply, {:error, :extension_input_unavailable}, state}

  def handle_call(:close, _from, state) do
    state = fail_pending(state, :extension_closed)
    result = close_helper(state)
    record_cleanup(state, result)
    {:stop, :normal, result, %{state | port: nil}}
  end

  defp encode_request(state, stage, payload, timeout) do
    with true <- Process.alive?(state.owner),
         true <- is_integer(timeout) and timeout in 1..30_000,
         true <- permitted?(state, stage, payload),
         :ok <- Ipse.Extension.validate(payload),
         id = state.sequence + 1,
         true <- id <= 9_007_199_254_740_991,
         bytes =
           Jason.encode!(%{"protocol" => 1, "id" => id, "stage" => stage, "payload" => payload}),
         true <- byte_size(bytes) <= @limit,
         do: {:ok, id, <<byte_size(bytes)::32, bytes::binary>>},
         else: (_ -> {:error, :invalid_extension_request})
  end

  defp pending_request(state, id, stage, payload, timeout, from) do
    origin =
      if stage == "initialize",
        do: nil,
        else: state.origin || %{stage: stage, invocation_id: payload["invocation_id"]}

    eligible =
      not is_nil(origin) and
        ResultPublication.eligible?(
          state.manifest["sdk"],
          state.manifest["capabilities"],
          origin.stage
        ) and
        (is_nil(state.origin) or
           (stage == "host.actions" and payload["invocation_id"] === origin.invocation_id))

    %{
      state
      | sequence: id,
        origin: origin,
        pending: %{
          id: id,
          from: from,
          timer: Process.send_after(self(), {:timeout, id}, timeout),
          deadline: now() + timeout,
          stage: stage,
          payload: payload,
          eligible: eligible
        }
    }
  end

  defp input_caller?(state, caller),
    do: caller == state.owner or Ipse.Session.Resources.authorized_effect?(state.owner, caller)

  defp input_live?(state),
    do:
      Process.alive?(state.owner) and
        Process.alive?(state.input.caller) and now() < state.pending.deadline

  defp now, do: System.monotonic_time(:millisecond)

  defp permitted?(%{producer: producer}, "result.output", payload) when not is_nil(producer),
    do: match?({:ok, _}, ResultPublication.request(producer, payload))

  defp permitted?(%{producer: producer}, _, _) when not is_nil(producer), do: false
  defp permitted?(_, "result.output", _), do: false

  defp permitted?(state, stage, payload),
    do:
      (stage == "initialize" and not state.ready and payload == state.options) or
        (state.ready and stage in state.manifest["capabilities"] and
           ResultPublication.domain_request?(
             state.manifest["sdk"],
             state.manifest["capabilities"],
             state.origin,
             state.awaiting_action,
             stage,
             payload
           ))

  @impl true
  def handle_info({port, {:data, bytes}}, %{port: port} = state) do
    state = %{state | buffer: state.buffer <> bytes, traffic: state.traffic + byte_size(bytes)}

    case frames(state) do
      {:ok, next} -> {:noreply, next}
      {:error, next} -> stop(next, :invalid_extension_output)
      :error -> stop(state, :invalid_extension_output)
    end
  end

  def handle_info({:timeout, id}, %{pending: %{id: id}} = state),
    do: stop(state, :extension_timeout)

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    record_cleanup(
      state,
      if(status in [0, 1], do: :ok, else: {:error, :cleanup_unconfirmed})
    )

    stop(%{state | port: nil}, :extension_exited)
  end

  def handle_info({:EXIT, port, _}, %{port: port} = state), do: stop(state, :extension_exited)

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state),
    do: stop(state, :owner_exited)

  def handle_info({:DOWN, ref, :process, _, _}, %{input: %{monitor: ref}} = state),
    do: stop(state, :input_owner_exited)

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    fail_pending(state, :extension_closed)

    if is_port(state.port),
      do: record_cleanup(state, close_helper(state))

    :ok
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:ready, :sequence, :traffic])}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp stop(state, reason), do: {:stop, :normal, fail_pending(state, reason)}

  defp close_helper(state),
    do: Ipse.Runner.close_stdio(state.port, if(state.finished, do: :completed, else: :cancel))

  defp record_cleanup(state, result) do
    Ipse.Session.Resources.closed(state.cleanup_ticket, result)
    confirm_cleanup(state.cleanup_lease, result)
  end

  defp fail_pending(%{pending: nil} = state, _reason), do: state

  defp fail_pending(state, reason) do
    Process.cancel_timer(state.pending.timer)
    if state.pending.from, do: GenServer.reply(state.pending.from, {:error, reason})

    if state.input do
      if state.input.from, do: GenServer.reply(state.input.from, {:error, reason})
      Process.demonitor(state.input.monitor, [:flush])
    end

    %{state | pending: nil, input: nil}
  end

  defp frames(%{traffic: traffic}) when traffic > @traffic_limit, do: :error

  defp frames(%{buffer: <<kind, size::unsigned-big-32, rest::binary>>} = state) do
    cond do
      size > 8192 ->
        :error

      byte_size(rest) < size ->
        {:ok, state}

      true ->
        <<payload::binary-size(^size), tail::binary>> = rest
        state = %{state | buffer: tail}

        case kind do
          ?O ->
            case if(
                   is_nil(state.input) or
                     state.input.phase in [:exported, :settling, :settled, :released],
                   do: messages(%{state | content: state.content <> payload}),
                   else: :error
                 ) do
              {:ok, next} -> frames(next)
              :error -> :error
            end

          kind when kind in [?B, ?F, ?K] ->
            case input_frame(state, kind, payload) do
              {:ok, next} -> frames(next)
              :error -> :error
            end

          ?S ->
            frames(state)

          kind when kind in [?X, ?E] ->
            {:error, %{state | finished: true}}

          _ ->
            :error
        end
    end
  end

  defp frames(state), do: {:ok, state}

  defp input_frame(
         %{input: %{phase: :reserving} = input} = state,
         ?B,
         <<operation::binary-size(16), pid::32, device::64, inode::64>>
       ) do
    if input_live?(state) and operation == input.binding.operation and
         pid == input.binding.native_pid and inode > 0 do
      binding = Map.put(input.binding, :pipe, %{pid: pid, device: device, inode: inode})
      GenServer.reply(input.from, {:ok, binding})
      {:ok, %{state | input: %{input | phase: :reserved, from: nil, binding: binding}}}
    else
      :error
    end
  end

  defp input_frame(
         %{input: %{phase: phase} = input} = state,
         kind,
         <<operation::binary-size(16)>>
       )
       when (kind == ?F and phase == :exporting) or (kind == ?K and phase == :settling) do
    if input_live?(state) and operation == input.binding.operation do
      GenServer.reply(input.from, :ok)

      {:ok,
       %{
         state
         | input: %{input | phase: if(kind == ?F, do: :exported, else: :settled), from: nil}
       }}
    else
      :error
    end
  end

  defp input_frame(_, _, _), do: :error

  defp messages(%{content: <<size::unsigned-big-32, rest::binary>>} = state) do
    cond do
      size > @limit ->
        :error

      byte_size(rest) < size ->
        {:ok, state}

      true ->
        <<bytes::binary-size(^size), tail::binary>> = rest

        case response(state, bytes) do
          {:ok, next} -> messages(%{next | content: tail})
          :error -> :error
        end
    end
  end

  defp messages(state), do: {:ok, state}

  defp response(%{pending: nil}, _bytes), do: :error

  defp response(%{input: %{phase: phase, response: nil} = input} = state, bytes)
       when phase in [:exported, :settling, :settled] do
    with {:ok, _message} <- response_message(state, bytes),
         do: {:ok, %{state | input: %{input | response: bytes}}},
         else: (_ -> :error)
  end

  defp response(%{input: %{phase: phase}}, _) when phase != :released, do: :error

  defp response(state, bytes) do
    with {:ok, message} <- response_message(state, bytes),
         {:ok, next} <- producer_response(state, message["result"]) do
      Process.cancel_timer(state.pending.timer)
      if state.input, do: Process.demonitor(state.input.monitor, [:flush])
      GenServer.reply(state.pending.from, {:ok, message["result"]})
      {:ok, %{next | ready: true, pending: nil, input: nil}}
    else
      _ -> :error
    end
  end

  defp response_message(state, bytes) do
    with {:ok, message} <- Ipse.JSON.decode_bounded(bytes),
         true <- is_map(message) and Enum.sort(Map.keys(message)) == ~w(id protocol result),
         true <- message["protocol"] === 1 and message["id"] === state.pending.id,
         :ok <- Ipse.Extension.validate(message["result"]),
         true <- description_valid?(state, message["result"]) do
      {:ok, message}
    else
      _ -> :error
    end
  end

  defp producer_response(%{ready: false} = state, _result), do: {:ok, state}

  defp producer_response(%{producer: producer} = state, result) when not is_nil(producer) do
    with {:ok, next} <- ResultPublication.accept(producer, state.pending.payload, result),
         do: {:ok, %{state | producer: next}}
  end

  defp producer_response(state, %{"kind" => "result_producer"} = result) do
    with true <- state.pending.eligible,
         {:ok, producer} <- ResultPublication.open(result, state.origin.invocation_id) do
      {:ok, %{state | producer: producer}}
    else
      _ -> :error
    end
  end

  defp producer_response(_state, %{"kind" => "result_chunk"}), do: :error

  defp producer_response(state, result),
    do: {:ok, %{state | awaiting_action: result["kind"] == "host_call"}}

  defp description_valid?(%{ready: true}, _result), do: true

  defp description_valid?(state, result),
    do:
      result["sdk"] === state.manifest["sdk"] and
        Ipse.Extension.Catalog.sdk_capabilities?(result["sdk"], result["capabilities"]) and
        result["capabilities"] === state.manifest["capabilities"] and
        Ipse.Extension.Catalog.normalize(result["exports"]) ==
          Ipse.Extension.Catalog.normalize(state.manifest["exports"]) and
        (result["requires"] || Ipse.Extension.Services.empty()) ==
          (state.manifest["requires"] || Ipse.Extension.Services.empty()) and
        (result["subscriptions"] || []) == (state.manifest["subscriptions"] || [])

  defp launch(artifact) do
    root = to_string(:code.root_dir())
    erts = "erts-" <> to_string(:erlang.system_info(:version))
    executable = Path.join([root, erts, "bin", "erl"])

    paths =
      Enum.map(
        [:elixir, :jason, :jsonschex, :ex_json_pointer, :ipse],
        &Application.app_dir(&1, "ebin")
      )

    boot = clean_boot(root)

    args =
      [
        "+S",
        "1:1",
        "+A",
        "1",
        "-noshell",
        "-mode",
        "interactive",
        "-boot",
        boot,
        "-boot_var",
        "RELEASE_LIB",
        Path.join(root, "lib"),
        "-pa"
      ] ++
        paths ++
        [
          "-s",
          "Elixir.Ipse.Extension.Bootstrap",
          "main",
          "-extra",
          artifact.path,
          artifact.manifest["entrypoint"]
        ]

    if boot != "" and File.regular?(executable) and File.regular?(boot <> ".boot"),
      do: {:ok, executable, args, %{"PATH" => System.get_env("PATH", "/usr/bin:/bin")}},
      else: {:error, :runtime_unavailable}
  end

  defp clean_boot(root) do
    current =
      case :init.get_argument(:boot) do
        {:ok, [[path]]} ->
          path = List.to_string(path)

          if Path.type(path) == :absolute and
               String.starts_with?(Path.expand(path), Path.join(root, "releases") <> "/"),
             do: Path.join(Path.dirname(path), "start_clean")

        _ ->
          nil
      end

    Enum.find(
      [current, Path.join([root, "bin", "no_dot_erlang"])],
      &(is_binary(&1) and File.regular?(&1 <> ".boot"))
    ) || ""
  end

  @doc "Retain the worker's native cleanup receipt even when it stops before an explicit close."
  def confirm_cleanup(nil, _result), do: :ok

  def confirm_cleanup(counters, result) do
    :atomics.put(counters, 9, if(result == :ok, do: 2, else: 3))
    :ok
  end

  def close_lease(worker, counters, slot \\ 9) do
    case :atomics.compare_exchange(counters, slot, 0, 1) do
      :ok ->
        close_claimed(worker, counters, slot)

      _ ->
        await_cleanup(counters, slot)
    end
  end

  def stop_lease_async(worker, counters, slot \\ 9) do
    if :atomics.compare_exchange(counters, slot, 0, 1) == :ok do
      Task.start_link(fn -> close_claimed(worker, counters, slot) end)
    end

    :ok
  end

  defp close_claimed(worker, counters, slot) do
    result = close(worker)
    result = if :atomics.get(counters, slot) == 2, do: :ok, else: result
    :atomics.put(counters, slot, if(result == :ok, do: 2, else: 3))
    result
  rescue
    _ ->
      :atomics.put(counters, slot, 3)
      {:error, :cleanup_unconfirmed}
  end

  def await_cleanup(counters, slot \\ 9),
    do: await_result(counters, slot, System.monotonic_time(:millisecond) + 3_500)

  defp await_result(counters, slot, deadline) do
    case :atomics.get(counters, slot) do
      2 ->
        :ok

      1 ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(2)
          await_result(counters, slot, deadline)
        else
          {:error, :cleanup_unconfirmed}
        end

      _ ->
        {:error, :cleanup_unconfirmed}
    end
  end
end

defmodule Ipse.Extension.Bootstrap do
  @moduledoc false
  alias Ipse.Extension.ResultPublication
  alias Ipse.Extension.ResultPublication.Output

  # This entrypoint runs only inside a separately launched, explicitly trusted VM.
  def main do
    {:ok, _} = Application.ensure_all_started(:elixir)
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)
    [path, name] = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
    true = Code.prepend_path(Path.join(path, "ebin"))
    module = String.to_atom("Elixir." <> name)
    loop(module, nil, false)
  rescue
    _ -> System.halt(1)
  catch
    _, _ -> System.halt(1)
  end

  defp loop(module, state, initialized) do
    with <<size::unsigned-big-32>> when size <= 32_768 <- IO.binread(:stdio, 4),
         bytes when is_binary(bytes) and byte_size(bytes) == size <- IO.binread(:stdio, size),
         {:ok, %{"protocol" => 1, "id" => id, "stage" => stage, "payload" => payload}} <-
           Jason.decode(bytes),
         true <- is_integer(id) and is_binary(stage) and is_map(payload),
         :ok <- Ipse.Extension.validate(payload) do
      {result, next, ready} = dispatch(module, stage, payload, state, initialized)
      :ok = Ipse.Extension.validate(result)
      bytes = Jason.encode!(%{"protocol" => 1, "id" => id, "result" => result})
      true = byte_size(bytes) <= 32_768
      :ok = IO.binwrite(:stdio, <<byte_size(bytes)::unsigned-big-32, bytes::binary>>)
      loop(module, next, ready)
    else
      _ -> System.halt(1)
    end
  end

  defp dispatch(module, "initialize", options, nil, false) do
    Code.ensure_loaded!(module)
    description = module.describe()
    {:ok, state} = module.init(options)

    context = %{
      domain: state,
      description: description,
      origin: nil,
      output: nil,
      producer: nil,
      awaiting_action: false
    }

    {description, context, true}
  end

  defp dispatch(_module, "result.output", payload, %{output: %Output{}} = context, true) do
    {:ok, result, producer} = ResultPublication.chunk(context.output, context.producer, payload)
    {result, %{context | producer: producer}, true}
  end

  defp dispatch(module, stage, payload, %{output: nil} = context, true)
       when stage not in ["initialize", "result.output"] do
    true =
      ResultPublication.domain_request?(
        context.description["sdk"],
        context.description["capabilities"],
        context.origin,
        context.awaiting_action,
        stage,
        payload
      )

    origin = context.origin || %{stage: stage, invocation_id: payload["invocation_id"]}

    original =
      is_nil(context.origin) or
        (stage == "host.actions" and payload["invocation_id"] === origin.invocation_id)

    {:ok, result, state} = module.handle(stage, payload, context.domain)

    case result do
      %Output{} ->
        true =
          original and
            ResultPublication.eligible?(
              context.description["sdk"],
              context.description["capabilities"],
              origin.stage
            )

        {:ok, offer} = ResultPublication.offer(result)
        {:ok, producer} = ResultPublication.open(offer, origin.invocation_id)

        {offer, %{context | domain: nil, origin: origin, output: result, producer: producer},
         true}

      result when is_map(result) ->
        true = result["kind"] not in ~w(result_producer result_chunk)

        {result,
         %{
           context
           | domain: state,
             origin: origin,
             awaiting_action: result["kind"] == "host_call"
         }, true}
    end
  end
end
