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

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(opts, :owner)
    digest = Keyword.fetch!(opts, :digest)
    options = Keyword.get(opts, :options, %{})

    with true <- is_pid(owner) and Process.alive?(owner),
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
             86_400_000
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
    with true <- Process.alive?(state.owner),
         true <- is_integer(timeout) and timeout >= 1 and timeout <= 30_000,
         true <- permitted?(state, stage, payload),
         :ok <- Ipse.Extension.validate(payload),
         id = state.sequence + 1,
         bytes =
           Jason.encode!(%{"protocol" => 1, "id" => id, "stage" => stage, "payload" => payload}),
         true <- byte_size(bytes) <= @limit,
         :ok <-
           Ipse.Runner.send_stdio(
             state.port,
             <<byte_size(bytes)::unsigned-big-32, bytes::binary>>
           ) do
      timer = Process.send_after(self(), {:timeout, id}, timeout)

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
             (stage == "host.actions" and
                payload["invocation_id"] === origin.invocation_id))

      {:noreply,
       %{
         state
         | pending: %{
             id: id,
             from: from,
             timer: timer,
             stage: stage,
             payload: payload,
             eligible: eligible
           },
           sequence: id,
           origin: origin
       }}
    else
      _ -> {:reply, {:error, :invalid_extension_request}, state}
    end
  end

  def handle_call(:close, _from, state) do
    state = fail_pending(state, :extension_closed)
    result = close_helper(state)
    record_cleanup(state, result)
    {:stop, :normal, result, %{state | port: nil}}
  end

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
    GenServer.reply(state.pending.from, {:error, reason})
    %{state | pending: nil}
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
            case messages(%{state | content: state.content <> payload}) do
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

  defp response(state, bytes) do
    with {:ok, message} <- Ipse.JSON.decode_bounded(bytes),
         true <- is_map(message) and Enum.sort(Map.keys(message)) == ~w(id protocol result),
         true <- message["protocol"] === 1 and message["id"] === state.pending.id,
         :ok <- Ipse.Extension.validate(message["result"]),
         true <- description_valid?(state, message["result"]),
         {:ok, next} <- producer_response(state, message["result"]) do
      Process.cancel_timer(state.pending.timer)
      GenServer.reply(state.pending.from, {:ok, message["result"]})
      {:ok, %{next | ready: true, pending: nil}}
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
