defmodule Ipse.MCP.StdioTransport do
  @moduledoc "MCP SDK transport over Ipse's bounded OS pipe supervisor."
  use GenServer
  @behaviour MCP.Transport
  @line_limit 262_144
  @traffic_limit 1_048_576

  @impl true
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl true
  def send_message(pid, message), do: GenServer.call(pid, {:send, message})
  @impl true
  def close(pid), do: close(pid, 3_000)

  def close(pid, timeout) do
    GenServer.call(pid, :close, timeout)
  catch
    :exit, _ -> {:error, :cleanup_unconfirmed}
  end

  @doc false
  def admit_response(message, pending, private_config) do
    with true <- bounded?(message, 0),
         {:ok, message, next} <- admit(message, pending) do
      {:ok, sanitize_identity(message, private_config), next}
    else
      _ -> :error
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(opts, :owner)
    server = Keyword.fetch!(opts, :server)
    cwd = Keyword.fetch!(opts, :cwd)
    resource = Keyword.get(opts, :resource)

    with :ok <- register(resource),
         {:ok, port, cleanup_ticket} <-
           Ipse.Runner.open_owned_stdio(
             :mcp,
             opts[:cleanup_scope],
             server.command,
             server.args,
             cwd,
             server.env,
             server.timeout_ms,
             sandbox: Map.get(server, :sandbox, :off)
           ) do
      {:ok,
       %{
         owner: owner,
         monitor: Process.monitor(owner),
         port: port,
         resource: resource,
         cleanup_owner: Keyword.fetch!(opts, :cleanup_owner),
         cleanup_ticket: cleanup_ticket,
         cleanup_result: {:error, :cleanup_unconfirmed},
         finished: false,
         private_config: Map.take(server, [:env, :redactions]),
         buffer: <<>>,
         line: <<>>,
         bytes: 0,
         messages: 0,
         pending: %{}
       }}
    else
      _ -> {:stop, :launch_failed}
    end
  end

  @impl true
  def handle_call({:send, message}, _from, state) do
    bytes = Jason.encode!(message) <> "\n"

    if byte_size(bytes) <= 32_768 do
      case Ipse.Runner.send_stdio(state.port, bytes) do
        :ok ->
          pending =
            if Map.has_key?(message, "id") and Map.has_key?(message, "method"),
              do: Map.put(state.pending, message["id"], message["method"]),
              else: state.pending

          {:reply, :ok, %{state | pending: pending}}

        _ ->
          send(state.owner, {:mcp_transport_closed, :input_failed})
          {:stop, :normal, {:error, :input_failed}, state}
      end
    else
      send(state.owner, {:mcp_transport_closed, :input_limit})
      {:stop, :normal, {:error, :input_limit}, state}
    end
  end

  def handle_call(:close, _from, state) do
    result = close_helper(state)
    {:stop, :normal, result, %{state | port: nil, cleanup_result: result}}
  end

  @impl true
  def handle_info({port, {:data, bytes}}, %{port: port} = state) do
    next = %{state | buffer: state.buffer <> bytes, bytes: state.bytes + byte_size(bytes)}

    case parse_frames(next) do
      {:ok, next} -> {:noreply, next}
      {:error, next} -> stop(next, :invalid_transport)
      :error -> stop(state, :invalid_transport)
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    result = if status in [0, 1], do: :ok, else: {:error, :cleanup_unconfirmed}
    stop(%{state | port: nil, cleanup_result: result}, :closed)
  end

  def handle_info({:EXIT, port, _}, %{port: port} = state),
    do: stop(state, :closed)

  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, owner, _}, %{owner: owner} = state), do: {:stop, :normal, state}
  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state) do
    result =
      if is_port(state.port), do: close_helper(state), else: state.cleanup_result

    Ipse.Session.Resources.closed(state.cleanup_ticket, result)
    send(state.cleanup_owner, {:mcp_cleanup, self(), result})
    :ok
  end

  @impl true
  def format_status(%{state: state} = status),
    do: %{status | state: Map.take(state, [:bytes, :messages]), message: :redacted}

  defp register(nil), do: :ok

  defp register(%{owner: owner, job_ref: ref}),
    do: GenServer.call(owner, {:mcp_register, ref, self()})

  defp close_helper(state),
    do: Ipse.Runner.close_stdio(state.port, if(state.finished, do: :completed, else: :cancel))

  defp stop(state, reason) do
    send(state.owner, {:mcp_transport_closed, reason})
    {:stop, :normal, state}
  end

  defp parse_frames(%{bytes: bytes}) when bytes > @traffic_limit, do: :error

  defp parse_frames(%{buffer: <<kind, size::unsigned-big-32, rest::binary>>} = state) do
    cond do
      size > @line_limit ->
        :error

      byte_size(rest) < size ->
        {:ok, state}

      true ->
        <<payload::binary-size(^size), tail::binary>> = rest
        state = %{state | buffer: tail}

        case kind do
          ?O ->
            case lines(state, payload) do
              {:ok, next} -> parse_frames(next)
              :error -> :error
            end

          ?S ->
            parse_frames(state)

          ?X ->
            send(state.owner, {:mcp_transport_closed, :closed})
            {:ok, %{state | finished: true}}

          ?E ->
            {:error, %{state | finished: true}}

          _ ->
            :error
        end
    end
  end

  defp parse_frames(state), do: {:ok, state}

  defp lines(state, bytes) do
    parts = :binary.split(state.line <> bytes, "\n", [:global])
    tail = List.last(parts)

    if byte_size(tail) > @line_limit do
      :error
    else
      Enum.reduce_while(Enum.drop(parts, -1), {:ok, %{state | line: tail}}, fn line, {:ok, acc} ->
        with true <- byte_size(line) <= @line_limit and acc.messages < 256,
             {:ok, message} when is_map(message) <- Jason.decode(line),
             true <- bounded?(message, 0),
             {:ok, message, pending} <- admit(message, acc.pending) do
          message = sanitize_identity(message, acc.private_config)
          send(acc.owner, {:mcp_message, message})
          {:cont, {:ok, %{acc | messages: acc.messages + 1, pending: pending}}}
        else
          _ -> {:halt, :error}
        end
      end)
    end
  end

  # Strict admission keeps malformed payloads and arbitrary IDs out of SDK logs.
  defp admit(%{"jsonrpc" => "2.0", "id" => id} = message, pending)
       when is_integer(id) or (is_binary(id) and byte_size(id) <= 128) do
    method = pending[id]

    cond do
      is_map_key(message, "method") ->
        request(message, pending)

      method == nil ->
        :error

      is_map_key(message, "result") and not is_map_key(message, "error") ->
        if method == "initialize",
          do: initialization(message, pending),
          else: {:ok, message, Map.delete(pending, id)}

      is_map(message["error"]) and is_integer(message["error"]["code"]) and
          not is_map_key(message, "result") ->
        safe = %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{
            "code" => message["error"]["code"],
            "message" => "MCP server protocol error"
          }
        }

        {:ok, safe, Map.delete(pending, id)}

      true ->
        :error
    end
  end

  defp admit(%{"jsonrpc" => "2.0", "method" => method} = message, pending)
       when is_binary(method) and not is_map_key(message, "id") do
    if method in [
         "notifications/tools/list_changed",
         "notifications/resources/list_changed",
         "notifications/prompts/list_changed"
       ] or is_map_key(message, "result") or
         is_map_key(message, "error"),
       do: :error,
       else: if(byte_size(method) <= 128, do: {:ok, message, pending}, else: :error)
  end

  defp admit(_, _), do: :error

  defp request(%{"method" => method} = message, pending)
       when is_binary(method) and byte_size(method) <= 128 and not is_map_key(message, "result") and
              not is_map_key(message, "error"),
       do: {:ok, message, pending}

  defp request(_, _), do: :error

  defp initialization(%{"result" => result, "id" => id} = message, pending) do
    with %{
           "protocolVersion" => "2025-11-25",
           "serverInfo" => %{"name" => name, "version" => version},
           "capabilities" => capabilities
         } <- result,
         true <- is_binary(name) and is_binary(version) and is_map(capabilities),
         supported = Map.take(capabilities, ["tools", "resources", "prompts"]),
         true <- Enum.all?(supported, fn {_, value} -> is_map(value) end) do
      # Ignore server instructions and all capabilities outside this client slice.
      safe =
        Map.take(result, ["protocolVersion", "serverInfo"])
        |> Map.put("capabilities", Map.new(supported, fn {key, _} -> {key, %{}} end))

      {:ok, %{message | "result" => safe}, Map.delete(pending, id)}
    else
      _ -> :error
    end
  end

  defp bounded?(_, depth) when depth > 32, do: false

  defp bounded?(value, depth) when is_map(value) and map_size(value) <= 512,
    do: Enum.all?(value, fn {k, v} -> is_binary(k) and bounded?(v, depth + 1) end)

  defp bounded?(value, depth) when is_list(value) and length(value) <= 512,
    do: Enum.all?(value, &bounded?(&1, depth + 1))

  defp bounded?(value, _) when is_binary(value), do: String.valid?(value)
  defp bounded?(value, _), do: is_number(value) or is_boolean(value) or is_nil(value)

  defp sanitize_identity(
         %{"result" => %{"serverInfo" => %{"name" => name, "version" => version} = info}} =
           message,
         config
       )
       when is_binary(name) and is_binary(version) do
    info =
      info
      |> Map.take(["name", "version"])
      |> Map.new(fn {key, value} -> {key, Ipse.MCP.Config.redact(value, config)} end)

    put_in(message, ["result", "serverInfo"], info)
  end

  defp sanitize_identity(message, _), do: message
end
