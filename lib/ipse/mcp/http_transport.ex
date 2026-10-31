defmodule Ipse.MCP.HTTPTransport do
  @moduledoc "Bounded, session-owned Streamable HTTP adapter for the existing MCP SDK."
  use GenServer
  @behaviour MCP.Transport
  alias Ipse.MCP.StdioTransport
  @body_limit 262_144
  @traffic_limit 1_048_576

  # SDK ownership uses a monitor so its exit cannot interrupt asynchronous pool cleanup.
  def start_link(opts), do: GenServer.start(__MODULE__, opts)
  def send_message(pid, message), do: GenServer.call(pid, {:send, message})
  def close(pid), do: StdioTransport.close(pid)

  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    server = Keyword.fetch!(opts, :server)
    resource = Keyword.get(opts, :resource)
    Ipse.Session.Resources.bind(opts[:cleanup_scope])

    if match?(%{managed_tool: managed} when is_map(managed), resource),
      do: Process.flag(:trap_exit, true)

    registered =
      case resource do
        nil -> :ok
        %{owner: session, job_ref: ref} -> GenServer.call(session, {:mcp_register, ref, self()})
      end

    with :ok <- registered,
         {:ok, cleanup_ticket} <- Ipse.Session.Resources.register(:mcp, opts[:cleanup_scope]) do
      Process.send_after(self(), :expired, server.timeout_ms)

      {:ok,
       %{
         owner: owner,
         owner_ref: Process.monitor(owner),
         server: server,
         resource: resource,
         cleanup_owner: Keyword.fetch!(opts, :cleanup_owner),
         possible_effect: Keyword.get(opts, :possible_effect),
         cleanup_ticket: cleanup_ticket,
         session_id: nil,
         deadline: now() + server.timeout_ms,
         queue: [],
         task: nil,
         task_managed: false,
         task_guardian: nil,
         pending: %{},
         active_id: nil,
         bytes: 0,
         messages: 0,
         closing: false,
         cleanup_uncertain: false,
         cleanup_result: {:error, :cleanup_unconfirmed},
         close_from: nil
       }}
    else
      _ -> {:stop, :cancelled}
    end
  end

  def handle_call({:send, message}, _from, %{closing: false} = s) when is_map(message) do
    encoded = Jason.encode!(message)

    case managed_binding(s.resource, s.server, message) do
      {:ok, binding} ->
        enqueue(encoded, message, binding, s)

      :error ->
        send(s.owner, {:mcp_transport_closed, :managed_input_unavailable})
        {:reply, {:error, :managed_input_unavailable}, begin_close(s, nil)}
    end
  end

  def handle_call({:send, _}, _, s), do: {:reply, {:error, :closed}, s}
  def handle_call(:close, from, s), do: {:noreply, begin_close(s, from)}

  defp enqueue(encoded, message, binding, s) do
    if byte_size(encoded) <= 32_768 and s.bytes + byte_size(encoded) <= @traffic_limit and
         length(s.queue) < 16 and s.messages < 256 do
      pending =
        if Map.has_key?(message, "id") and Map.has_key?(message, "method"),
          do: Map.put(s.pending, message["id"], message["method"]),
          else: s.pending

      next = %{
        s
        | queue:
            s.queue ++
              [{encoded, if(Map.has_key?(message, "method"), do: message["id"]), binding}],
          pending: pending,
          bytes: s.bytes + byte_size(encoded),
          messages: s.messages + 1
      }

      {:reply, :ok, launch(next)}
    else
      send(s.owner, {:mcp_transport_closed, :input_limit})
      {:reply, {:error, :input_limit}, begin_close(s, nil)}
    end
  end

  defp managed_binding(%{managed_tool: managed, managed_discovery: discovery}, server, message)
       when is_map(managed) and is_map(discovery) do
    public = server |> Ipse.MCP.Config.manifest() |> Jason.encode!() |> Jason.decode!()
    context = %{"server" => public, "initialize_params" => discovery["initialize_params"]}

    if Ipse.MCP.managed_discovery_request?(context, message) do
      kind =
        if message["method"] == "initialize",
          do: "mcp.discovery.start",
          else: "mcp.discovery.send"

      {:ok,
       %{
         "kind" => kind,
         "discovery_id" => discovery["id"],
         "server_sha256" => discovery["server_sha256"],
         "request" => message
       }}
    else
      :error
    end
  end

  defp managed_binding(%{managed_tool: managed} = resource, _, message) when is_map(managed) do
    if message["method"] in ~w(initialize tools/call resources/read prompts/get) do
      case resource do
        %{managed_descriptor: %{digest: digest}} ->
          if Ipse.JSON.sha256?(digest) do
            binding = %{"kind" => "mcp.start", "descriptor_sha256" => digest}

            if message["method"] == "initialize",
              do: {:ok, binding},
              else: {:ok, %{binding | "kind" => "mcp.send"} |> Map.put("request", message)}
          else
            :error
          end

        _ ->
          :error
      end
    else
      {:ok, nil}
    end
  end

  defp managed_binding(_, _, _), do: {:ok, nil}

  def handle_info({ref, result}, %{task: %{ref: ref}} = s) do
    Process.demonitor(ref, [:flush])

    uncertain =
      s.cleanup_uncertain or (s.task_managed and result == {:error, :cleanup_unconfirmed})

    s = %{s | task: nil, task_managed: false, task_guardian: nil, cleanup_uncertain: uncertain}

    cond do
      s.closing ->
        finish_close(s, result != {:error, :cleanup_unconfirmed})

      true ->
        case receive_response(s, result) do
          {:ok, next} ->
            {:noreply, launch(next)}

          :error ->
            send(s.owner, {:mcp_transport_closed, :invalid_http_transport})
            {:noreply, begin_close(s, nil)}
        end
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref, closing: false} = s),
    do: {:noreply, begin_close(s, nil)}

  def handle_info({:DOWN, ref, :process, _, _}, %{task: %{ref: ref}} = s) do
    s = %{s | cleanup_uncertain: s.cleanup_uncertain or s.task_managed}

    if s.closing do
      finish_close(%{s | task: nil, task_managed: false}, false)
    else
      send(s.owner, {:mcp_transport_closed, :http_worker_stopped})
      {:noreply, begin_close(s, nil)}
    end
  end

  def handle_info(:expired, %{closing: false} = s) do
    send(s.owner, {:mcp_transport_closed, :deadline})
    {:noreply, begin_close(s, nil)}
  end

  def handle_info(_, s), do: {:noreply, s}

  def terminate(_, s) do
    if s.task, do: Process.exit(s.task.pid, :kill)
    Ipse.HTTP.cancel_finch(s.task_guardian)
    Ipse.Session.Resources.closed(s.cleanup_ticket, s.cleanup_result)
    send(s.cleanup_owner, {:mcp_cleanup, self(), s.cleanup_result})
  end

  def format_status(%{state: s} = status),
    do: %{status | state: Map.take(s, [:bytes, :messages, :closing]), message: :redacted}

  defp launch(%{task: nil, queue: [{body, id, binding} | rest], closing: false} = s) do
    timeout = max(s.deadline - now(), 1)

    {task, guardian} =
      if binding,
        do: managed_request_task(s, body, timeout, binding),
        else: request_task(s, :post, body, timeout)

    %{
      s
      | queue: rest,
        task: task,
        task_managed: not is_nil(binding),
        task_guardian: guardian,
        active_id: id
    }
  end

  defp launch(s), do: s

  defp managed_request_task(s, body, timeout, binding) do
    task =
      Ipse.Session.Resources.async(fn ->
        case Ipse.Session.Resources.controlled_owned_effect(
               fn -> managed_post(s, body, timeout, binding) end,
               min(timeout, 120_000)
             ) do
          {:ok, result} -> result
          _ -> {:error, :cleanup_unconfirmed}
        end
      end)

    {task, nil}
  end

  defp managed_post(s, body, timeout, binding) do
    headers = [
      {"accept", "application/json, text/event-stream"},
      {"content-type", "application/json"},
      {"accept-encoding", "identity"},
      {"mcp-protocol-version", "2025-11-25"}
    ]

    headers = if s.session_id, do: [{"mcp-session-id", s.session_id} | headers], else: headers

    headers =
      case Map.values(s.server.env) do
        [token] -> [{"authorization", "Bearer " <> token} | headers]
        [] -> headers
      end

    initial = %{status: nil, headers: %{}, chunks: []}

    admission = fn send_once ->
      Ipse.Session.ManagedToolUse.with_effect(s.resource.managed_tool, binding, fn deadline ->
        deadline = deadline || System.system_time(:millisecond) + min(timeout, 120_000)

        with true <- is_integer(deadline) and System.system_time(:millisecond) < deadline,
             :ok <- mark_managed_start(s.possible_effect, binding),
             true <- System.system_time(:millisecond) < deadline do
          send_once.(deadline)
        else
          _ -> {:error, :managed_input_unavailable}
        end
      end)
    end

    case Ipse.Provider.MintTransport.stream_socket(
           s.server.url,
           headers,
           body,
           timeout,
           @body_limit,
           initial,
           &consume_managed/2,
           admission
         ) do
      {:ok, %{status: status, headers: response_headers, chunks: chunks}}
      when is_integer(status) ->
        {:ok,
         %{
           status: status,
           headers: response_headers,
           body: chunks |> Enum.reverse() |> IO.iodata_to_binary(),
           private: %{}
         }}

      # The socket adapter's unknown variants do not all prove that the owned
      # socket was observed closed. Preserve that uncertainty through DELETE.
      {:unknown, _} ->
        {:error, :cleanup_unconfirmed}

      _ ->
        {:error, :managed_input_unconfirmed}
    end
  rescue
    _ -> {:error, :cleanup_unconfirmed}
  catch
    _, _ -> {:error, :cleanup_unconfirmed}
  end

  defp mark_managed_start(possible_effect, %{"kind" => kind})
       when kind in ["mcp.start", "mcp.discovery.start"] do
    :atomics.put(possible_effect, 1, 1)
    :ok
  end

  defp mark_managed_start(_, _), do: :ok

  defp consume_managed({:status, _, status}, %{status: nil} = state) when status >= 200,
    do: {:cont, %{state | status: status}}

  defp consume_managed({:headers, _, headers}, %{status: status} = state)
       when is_integer(status) do
    headers =
      Enum.reduce(headers, state.headers, fn {name, value}, acc ->
        Map.update(acc, String.downcase(name), [value], &(&1 ++ [value]))
      end)

    {:cont, %{state | headers: headers}}
  end

  defp consume_managed({:data, _, bytes}, state),
    do: {:cont, %{state | chunks: [bytes | state.chunks]}}

  defp consume_managed(_, _), do: {:halt, :invalid_http_response}

  defp request_task(s, method, body, timeout, previous_guardian \\ nil) do
    parent = self()
    server = s.server
    session_id = s.session_id
    lease = Ipse.HTTP.prepare_finch(parent)

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        worker = self()

        guard =
          spawn(fn ->
            parent_ref = Process.monitor(parent)
            worker_ref = Process.monitor(worker)

            receive do
              {:DOWN, ^parent_ref, :process, _, _} -> Process.exit(worker, :kill)
              {:DOWN, ^worker_ref, :process, _, _} -> :ok
              :finished -> :ok
            end
          end)

        result =
          try do
            with :ok <- Ipse.HTTP.await_guardian(previous_guardian) do
              if method == :delete and is_nil(session_id) do
                :ok
              else
                proxy_options = Ipse.HTTP.finch_options(URI.parse(server.url))

                Ipse.HTTP.with_finch(
                  fn finch ->
                    # The Finch guardian closes this private pool on borrower death too.
                    headers = [
                      {"accept", "application/json, text/event-stream"},
                      {"content-type", "application/json"},
                      {"accept-encoding", "identity"},
                      {"mcp-protocol-version", "2025-11-25"}
                    ]

                    headers =
                      if session_id, do: [{"mcp-session-id", session_id} | headers], else: headers

                    headers =
                      case Map.values(server.env) do
                        [token] -> [{"authorization", "Bearer " <> token} | headers]
                        [] -> headers
                      end

                    into = fn {:data, bytes}, {req, resp} ->
                      if byte_size(resp.body) + byte_size(bytes) > @body_limit do
                        {:halt,
                         {req, %{resp | private: Map.put(resp.private, :ipse_limit, true)}}}
                      else
                        {:cont, {req, %{resp | body: resp.body <> bytes}}}
                      end
                    end

                    Req.request(
                      method: method,
                      url: server.url,
                      body: body,
                      headers: headers,
                      finch: [name: finch, pool_timeout: min(timeout, 2000)],
                      raw: true,
                      retry: false,
                      redirect: false,
                      into: into,
                      receive_timeout: timeout
                    )
                  end,
                  proxy_options,
                  lease
                )
              end
            end
          rescue
            _ -> {:error, :http_failure}
          catch
            _, _ -> {:error, :http_failure}
          end

        cleanup = lease |> Ipse.HTTP.cancel_finch() |> Ipse.HTTP.await_guardian()
        send(guard, :finished)
        if cleanup == :ok, do: result, else: {:error, :cleanup_unconfirmed}
      end)

    {task, lease}
  end

  defp receive_response(s, {:ok, response}) do
    bytes = byte_size(response.body)
    type = header(response.headers, "content-type")
    received_id = header(response.headers, "mcp-session-id")

    valid_id =
      is_nil(received_id) or
        (byte_size(received_id) in 1..1024 and Regex.match?(~r/\A[\x21-\x7e]+\z/, received_id))

    cond do
      response.private[:ipse_limit] == true or not valid_id or s.bytes + bytes > @traffic_limit ->
        :error

      s.session_id && received_id && s.session_id != received_id ->
        :error

      received_id && is_nil(s.session_id) && s.pending[s.active_id] != "initialize" ->
        :error

      header(response.headers, "content-encoding") not in [nil, "identity"] ->
        :error

      response.status == 202 and response.body == "" and is_nil(s.active_id) ->
        {:ok, %{s | bytes: s.bytes + bytes}}

      response.status == 200 ->
        with {:ok, messages} <- decode(type, response.body),
             true <- messages != [] and length(messages) + s.messages <= 256,
             {:ok, next, safe} <- admit_messages(s, messages, received_id),
             true <- not is_nil(s.active_id) and not Map.has_key?(next.pending, s.active_id) do
          Enum.each(safe, &send(s.owner, {:mcp_message, &1}))
          {:ok, %{next | session_id: s.session_id || received_id, bytes: s.bytes + bytes}}
        else
          _ -> :error
        end

      true ->
        :error
    end
  end

  defp receive_response(_, _), do: :error

  defp decode(type, body) do
    cond do
      is_binary(type) and String.starts_with?(String.downcase(type), "application/json") ->
        case Jason.decode(body) do
          {:ok, message} when is_map(message) -> {:ok, [message]}
          _ -> :error
        end

      is_binary(type) and String.starts_with?(String.downcase(type), "text/event-stream") ->
        {events, tail} = MCP.Transport.SSE.feed(MCP.Transport.SSE.new_parser(), body)

        if String.trim(tail) == "" do
          Enum.reduce_while(events, {:ok, []}, fn event, {:ok, messages} ->
            case event[:data] do
              data when data in [nil, ""] ->
                {:cont, {:ok, messages}}

              data ->
                case Jason.decode(data) do
                  {:ok, message} when is_map(message) -> {:cont, {:ok, messages ++ [message]}}
                  _ -> {:halt, :error}
                end
            end
          end)
        else
          :error
        end

      true ->
        :error
    end
  end

  defp admit_messages(s, messages, received_id) do
    session_tokens = Enum.reject([s.session_id, received_id], &is_nil/1)

    Enum.reduce_while(messages, {:ok, s, []}, fn message, {:ok, current, safe_messages} ->
      supported = not Map.has_key?(message, "method") or message["method"] == "ping"

      private =
        Map.put(
          current.server,
          :redactions,
          Map.get(current.server, :redactions, Map.values(current.server.env)) ++ session_tokens
        )

      admission =
        if supported,
          do: StdioTransport.admit_response(message, current.pending, private),
          else: :error

      case admission do
        {:ok, safe, pending} ->
          safe =
            if current.pending[message["id"]] == "initialize" or not Map.has_key?(safe, "result"),
              do: safe,
              else: Map.update!(safe, "result", &redact_session(&1, session_tokens))

          {:cont,
           {:ok, %{current | pending: pending, messages: current.messages + 1},
            safe_messages ++ [safe]}}

        :error ->
          {:halt, :error}
      end
    end)
  end

  defp redact_session(value, tokens) when is_binary(value),
    do: Enum.reduce(tokens, value, &String.replace(&2, &1, "[redacted]"))

  defp redact_session(value, tokens) when is_list(value),
    do: Enum.map(value, &redact_session(&1, tokens))

  defp redact_session(value, tokens) when is_map(value),
    do:
      Map.new(value, fn {key, item} ->
        {redact_session(key, tokens), redact_session(item, tokens)}
      end)

  defp redact_session(value, _), do: value

  defp begin_close(%{closing: true} = s, from), do: %{s | close_from: s.close_from || from}

  defp begin_close(s, from) do
    guardian = Ipse.HTTP.cancel_finch(s.task_guardian)
    uncertain = s.cleanup_uncertain or (not is_nil(s.task) and s.task_managed)

    if s.task do
      Process.exit(s.task.pid, :kill)
      Process.demonitor(s.task.ref, [:flush])
    end

    s = %{
      s
      | closing: true,
        queue: [],
        task: nil,
        task_managed: false,
        task_guardian: nil,
        cleanup_uncertain: uncertain,
        close_from: from || s.close_from
    }

    {task, lease} = request_task(s, :delete, "", 1500, guardian)
    %{s | task: task, task_guardian: lease, session_id: nil}
  end

  defp finish_close(s, confirmed) do
    result =
      if confirmed and not s.cleanup_uncertain, do: :ok, else: {:error, :cleanup_unconfirmed}

    if s.close_from, do: GenServer.reply(s.close_from, result)
    {:stop, :normal, %{s | cleanup_result: result}}
  end

  defp header(headers, name) do
    case Map.get(headers, name, []) do
      [value] when is_binary(value) -> value
      [] -> nil
      _ -> "\n"
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
