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
    Ipse.Session.Resources.bind(opts[:cleanup_scope])

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
             sandbox: Map.get(server, :sandbox, :off),
             admit_start: managed_resource?(resource),
             protected_supervisor: managed_resource?(resource)
           ) do
      {:ok,
       %{
         owner: owner,
         monitor: Process.monitor(owner),
         port: port,
         resource: resource,
         server: server,
         cleanup_owner: Keyword.fetch!(opts, :cleanup_owner),
         possible_effect: Keyword.get(opts, :possible_effect),
         cleanup_ticket: cleanup_ticket,
         cleanup_result: {:error, :cleanup_unconfirmed},
         finished: false,
         private_config: Map.take(server, [:env, :redactions]),
         buffer: <<>>,
         line: <<>>,
         bytes: 0,
         messages: 0,
         pending: %{},
         start_ready: false,
         started: not managed_resource?(resource),
         start_pending: nil,
         managed_pending: nil
       }}
    else
      _ -> {:stop, :launch_failed}
    end
  end

  @impl true
  def handle_call({:send, message}, from, state) when is_map(message) do
    bytes = Jason.encode!(message) <> "\n"

    cond do
      not state.started -> prepare_start(bytes, message, from, state)
      managed_message?(state.resource, message) -> send_managed(bytes, message, from, state)
      true -> send_plain(bytes, message, state)
    end
  end

  def handle_call({:send, _}, _from, state), do: {:stop, :normal, {:error, :input_failed}, state}

  def handle_call({:managed_start, token, peer, deadline}, {peer, _}, state) do
    case state.start_pending do
      %{token: ^token, peer: nil} = pending when state.start_ready ->
        if is_integer(deadline) and System.system_time(:millisecond) < deadline do
          :atomics.put(state.possible_effect, 1, 1)

          case Ipse.Runner.grant_stdio_start(state.port, deadline) do
            :ok -> {:reply, :ok, %{state | start_pending: %{pending | peer: peer}}}
            _ -> {:reply, {:error, :input_failed}, state}
          end
        else
          {:reply, {:error, :managed_input_unavailable}, state}
        end

      _ ->
        {:reply, {:error, :managed_input_unavailable}, state}
    end
  end

  def handle_call({:managed_write, token, peer, deadline}, {peer, _}, state) do
    case state.managed_pending do
      %{token: ^token, peer: nil, nonce: nonce, bytes: bytes} = pending ->
        if is_integer(deadline) and System.system_time(:millisecond) < deadline do
          case Ipse.Runner.send_stdio_before(state.port, bytes, deadline, nonce) do
            :ok -> {:reply, :ok, %{state | managed_pending: %{pending | peer: peer}}}
            _ -> {:reply, {:error, :input_failed}, state}
          end
        else
          {:reply, {:error, :managed_input_unavailable}, state}
        end

      _ ->
        {:reply, {:error, :managed_input_unavailable}, state}
    end
  end

  def handle_call(:close, _from, state) do
    result = close_helper(state)
    {:stop, :normal, result, %{state | port: nil, cleanup_result: result}}
  end

  defp send_plain(bytes, message, state) do
    if byte_size(bytes) <= 32_768 do
      case Ipse.Runner.send_stdio(state.port, bytes) do
        :ok ->
          {:reply, :ok, %{state | pending: add_pending(state.pending, message)}}

        _ ->
          send(state.owner, {:mcp_transport_closed, :input_failed})
          {:stop, :normal, {:error, :input_failed}, state}
      end
    else
      send(state.owner, {:mcp_transport_closed, :input_limit})
      {:stop, :normal, {:error, :input_limit}, state}
    end
  end

  defp prepare_start(bytes, %{"method" => "initialize"} = message, from, state)
       when byte_size(bytes) <= 32_768 and is_nil(state.start_pending) do
    pending = %{
      bytes: bytes,
      message: message,
      from: from,
      token: make_ref(),
      peer: nil,
      task: nil,
      acked: false
    }

    next = %{state | start_pending: pending}
    {:noreply, if(next.start_ready, do: launch_start(next), else: next)}
  end

  defp prepare_start(_, _, _, state) do
    send(state.owner, {:mcp_transport_closed, :managed_input_unavailable})
    {:stop, :normal, {:error, :managed_input_unavailable}, state}
  end

  defp launch_start(%{start_pending: %{task: nil} = pending} = state) do
    %{managed_tool: managed} = state.resource
    transport = self()
    token = pending.token
    binding = start_binding(state.resource)

    task =
      Ipse.Session.Resources.async(fn ->
        case Ipse.Session.Resources.controlled_owned_effect(
               fn ->
                 Ipse.Session.ManagedToolUse.with_effect(managed, binding, fn deadline ->
                   managed_start(transport, token, deadline)
                 end)
               end,
               5_000
             ) do
          {:ok, result} -> result
          _ -> {:unknown, :managed_input_unconfirmed}
        end
      end)

    %{state | start_pending: %{pending | task: task}}
  end

  defp managed_start(transport, token, nil),
    do: managed_start(transport, token, System.system_time(:millisecond) + 5_000)

  defp managed_start(transport, token, deadline) when is_integer(deadline) do
    remaining = min(max(deadline - System.system_time(:millisecond), 0), 5_000)

    with true <- remaining > 0,
         :ok <- GenServer.call(transport, {:managed_start, token, self(), deadline}, remaining) do
      receive do
        {:managed_stdio_started, ^token} -> :ok
      after
        max(deadline - System.system_time(:millisecond), 0) ->
          {:unknown, :managed_input_unconfirmed}
      end
    else
      _ -> {:error, :managed_input_unavailable}
    end
  catch
    :exit, _ -> {:unknown, :managed_input_unconfirmed}
  end

  defp managed_start(_, _, _), do: {:error, :managed_input_unavailable}

  defp send_managed(bytes, message, from, state) do
    with true <- byte_size(bytes) <= 32_768 and is_nil(state.managed_pending),
         %{managed_tool: managed} when is_map(managed) <- state.resource,
         {:ok, binding} <- send_binding(state.resource, state.server, message) do
      transport = self()
      token = make_ref()
      nonce = :crypto.strong_rand_bytes(16)

      task =
        Ipse.Session.Resources.async(fn ->
          case Ipse.Session.Resources.controlled_owned_effect(
                 fn ->
                   Ipse.Session.ManagedToolUse.with_effect(managed, binding, fn deadline ->
                     managed_write(transport, token, nonce, deadline)
                   end)
                 end,
                 5_000
               ) do
            {:ok, result} -> result
            _ -> {:unknown, :managed_input_unconfirmed}
          end
        end)

      pending = %{
        token: token,
        nonce: nonce,
        bytes: bytes,
        from: from,
        peer: nil,
        acked: false,
        task: task
      }

      {:noreply,
       %{state | managed_pending: pending, pending: add_pending(state.pending, message)}}
    else
      _ ->
        send(state.owner, {:mcp_transport_closed, :managed_input_unavailable})
        {:stop, :normal, {:error, :managed_input_unavailable}, state}
    end
  end

  defp managed_write(transport, token, nonce, nil),
    do: managed_write(transport, token, nonce, System.system_time(:millisecond) + 5_000)

  defp managed_write(transport, token, nonce, deadline) when is_integer(deadline) do
    remaining = min(max(deadline - System.system_time(:millisecond), 0), 5_000)

    with true <- remaining > 0,
         :ok <- GenServer.call(transport, {:managed_write, token, self(), deadline}, remaining) do
      receive do
        {:managed_stdio_ack, ^nonce, 1} -> :ok
        {:managed_stdio_ack, ^nonce, 0} -> {:error, :managed_input_unavailable}
        {:managed_stdio_ack, ^nonce, 2} -> {:unknown, :managed_input_unconfirmed}
      after
        max(deadline - System.system_time(:millisecond), 0) ->
          {:unknown, :managed_input_unconfirmed}
      end
    else
      _ -> {:error, :managed_input_unavailable}
    end
  catch
    :exit, _ -> {:unknown, :managed_input_unconfirmed}
  end

  defp managed_write(_, _, _, _), do: {:error, :managed_input_unavailable}

  defp managed_message?(%{managed_discovery: discovery}, _) when is_map(discovery), do: true

  defp managed_message?(%{managed_tool: managed}, message) when is_map(managed),
    do: message["method"] in ~w(tools/call resources/read prompts/get)

  defp managed_message?(_, _), do: false

  defp managed_resource?(%{managed_tool: managed}), do: is_map(managed)
  defp managed_resource?(_), do: false

  defp add_pending(pending, %{"id" => id, "method" => method}), do: Map.put(pending, id, method)
  defp add_pending(pending, _), do: pending

  defp start_binding(%{managed_discovery: %{"id" => id, "server_sha256" => hash}}),
    do: %{"kind" => "mcp.discovery.start", "discovery_id" => id, "server_sha256" => hash}

  defp start_binding(%{managed_descriptor: %{digest: digest}}),
    do: %{"kind" => "mcp.start", "descriptor_sha256" => digest}

  defp send_binding(%{managed_discovery: discovery}, server, message) when is_map(discovery) do
    public = server |> Ipse.MCP.Config.manifest() |> Jason.encode!() |> Jason.decode!()
    context = %{"server" => public, "initialize_params" => discovery["initialize_params"]}

    if Ipse.MCP.managed_discovery_request?(context, message) do
      {:ok,
       %{
         "kind" => "mcp.discovery.send",
         "discovery_id" => discovery["id"],
         "server_sha256" => discovery["server_sha256"],
         "request" => message
       }}
    else
      :error
    end
  end

  defp send_binding(%{managed_descriptor: %{digest: digest}}, _, message) do
    if Ipse.JSON.sha256?(digest),
      do: {:ok, %{"kind" => "mcp.send", "descriptor_sha256" => digest, "request" => message}},
      else: :error
  end

  defp send_binding(_, _, _), do: :error

  @impl true
  def handle_info({ref, result}, %{start_pending: %{task: %{ref: ref}} = pending} = state) do
    Process.demonitor(ref, [:flush])
    next = %{state | start_pending: nil, started: true}

    if result == :ok do
      if is_map(next.resource[:managed_discovery]) do
        send_managed(pending.bytes, pending.message, pending.from, next)
      else
        case send_plain(pending.bytes, pending.message, next) do
          {:reply, reply, state} ->
            GenServer.reply(pending.from, reply)
            {:noreply, state}

          {:stop, reason, reply, state} ->
            GenServer.reply(pending.from, reply)
            {:stop, reason, state}
        end
      end
    else
      GenServer.reply(pending.from, {:error, :managed_input_unconfirmed})
      send(state.owner, {:mcp_transport_closed, :managed_input_unconfirmed})
      {:stop, :normal, %{state | start_pending: nil}}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _, _},
        %{start_pending: %{task: %{ref: ref}, from: from}} = state
      ) do
    GenServer.reply(from, {:error, :managed_input_unconfirmed})
    send(state.owner, {:mcp_transport_closed, :managed_input_unconfirmed})
    {:stop, :normal, %{state | start_pending: nil}}
  end

  def handle_info({ref, result}, %{managed_pending: %{task: %{ref: ref}, from: from}} = state) do
    Process.demonitor(ref, [:flush])

    if result == :ok do
      GenServer.reply(from, :ok)
      {:noreply, %{state | managed_pending: nil}}
    else
      GenServer.reply(from, {:error, :managed_input_unconfirmed})
      send(state.owner, {:mcp_transport_closed, :managed_input_unconfirmed})
      {:stop, :normal, %{state | managed_pending: nil}}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _, _},
        %{managed_pending: %{task: %{ref: ref}, from: from}} = state
      ) do
    GenServer.reply(from, {:error, :managed_input_unconfirmed})
    send(state.owner, {:mcp_transport_closed, :managed_input_unconfirmed})
    {:stop, :normal, %{state | managed_pending: nil}}
  end

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
    if state.managed_pending, do: Process.exit(state.managed_pending.task.pid, :kill)

    if state.start_pending && state.start_pending.task,
      do: Process.exit(state.start_pending.task.pid, :kill)

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
          ?R ->
            if payload == <<>> and not state.started and not state.start_ready do
              next = %{state | start_ready: true}
              next = if next.start_pending, do: launch_start(next), else: next
              parse_frames(next)
            else
              :error
            end

          ?A when payload == <<>> ->
            case state.start_pending do
              %{peer: peer, token: token, acked: false} = pending when is_pid(peer) ->
                send(peer, {:managed_stdio_started, token})
                parse_frames(%{state | start_pending: %{pending | acked: true}})

              _ ->
                :error
            end

          ?A ->
            case {payload, state.managed_pending} do
              {<<nonce::binary-size(16), status>>,
               %{nonce: nonce, peer: peer, acked: false} = pending}
              when is_pid(peer) and status in 0..2 ->
                send(peer, {:managed_stdio_ack, nonce, status})
                parse_frames(%{state | managed_pending: %{pending | acked: true}})

              _ ->
                :error
            end

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
