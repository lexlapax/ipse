defmodule Ipse.Extensions.Worker do
  @moduledoc "Owner-monitored independent VM bridge; never loads an artifact in the host."
  use GenServer
  alias Ipse.Extensions.{Manifest, Registry}
  @limit 32_768
  @traffic_limit 67_108_864

  @doc "Explicit executable admission. :trusted must equal the pinned digest."
  def start(opts), do: GenServer.start(__MODULE__, opts)

  def call(pid, stage, payload, timeout_ms \\ 5_000) do
    GenServer.call(pid, {:invoke, stage, payload, timeout_ms}, :infinity)
  catch
    :exit, _ -> {:error, :extension_unavailable}
  end

  def close(pid) do
    GenServer.call(pid, :close, 3_000)
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
         true <- Manifest.compatible?(artifact.manifest),
         :ok <- Ipse.MCP.Schema.validate_arguments(artifact.manifest["options_schema"], options),
         {:ok, executable, args, environment} <- launch(artifact),
         {:ok, port} <-
           Ipse.Runner.open_stdio(executable, args, artifact.path, environment, 86_400_000) do
      {:ok,
       %{
         owner: owner,
         owner_ref: Process.monitor(owner),
         port: port,
         options: options,
         manifest: artifact.manifest,
         pending: nil,
         sequence: 0,
         ready: false,
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
    permitted =
      (stage == "initialize" and not state.ready and payload == state.options) or
        (state.ready and stage in state.manifest["capabilities"])

    with true <- Process.alive?(state.owner),
         true <- is_integer(timeout) and timeout >= 1 and timeout <= 30_000,
         true <- permitted,
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

      {:noreply,
       %{state | pending: %{id: id, from: from, timer: timer, stage: stage}, sequence: id}}
    else
      _ -> {:reply, {:error, :invalid_extension_request}, state}
    end
  end

  def handle_call(:close, _from, state) do
    state = fail_pending(state, :extension_closed)
    result = Ipse.Runner.close_stdio(state.port)
    {:stop, :normal, result, %{state | port: nil}}
  end

  @impl true
  def handle_info({port, {:data, bytes}}, %{port: port} = state) do
    state = %{state | buffer: state.buffer <> bytes, traffic: state.traffic + byte_size(bytes)}

    case frames(state) do
      {:ok, next} -> {:noreply, next}
      :error -> stop(state, :invalid_extension_output)
    end
  end

  def handle_info({:timeout, id}, %{pending: %{id: id}} = state),
    do: stop(state, :extension_timeout)

  def handle_info({port, {:exit_status, _}}, %{port: port} = state),
    do: stop(state, :extension_exited)

  def handle_info({:EXIT, port, _}, %{port: port} = state), do: stop(state, :extension_exited)

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state),
    do: stop(state, :owner_exited)

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    fail_pending(state, :extension_closed)
    if is_port(state.port), do: Ipse.Runner.close_stdio(state.port)
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
    with {:ok, message} <- Manifest.decode_json(bytes),
         true <- is_map(message) and Enum.sort(Map.keys(message)) == ~w(id protocol result),
         true <- message["protocol"] === 1 and message["id"] === state.pending.id,
         :ok <- Ipse.Extension.validate(message["result"]),
         true <- description_valid?(state, message["result"]) do
      Process.cancel_timer(state.pending.timer)
      GenServer.reply(state.pending.from, {:ok, message["result"]})
      {:ok, %{state | ready: true, pending: nil}}
    else
      _ -> :error
    end
  end

  defp description_valid?(%{ready: true}, _result), do: true

  defp description_valid?(state, result),
    do: result["sdk"] === 1 and result["capabilities"] === state.manifest["capabilities"]

  defp launch(artifact) do
    root = to_string(:code.root_dir())
    erts = "erts-" <> to_string(:erlang.system_info(:version))
    executable = Path.join([root, erts, "bin", "erl"])
    paths = Enum.map([:elixir, :jason, :ipse], &Application.app_dir(&1, "ebin"))
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
          "Elixir.Ipse.Extensions.Bootstrap",
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
end
