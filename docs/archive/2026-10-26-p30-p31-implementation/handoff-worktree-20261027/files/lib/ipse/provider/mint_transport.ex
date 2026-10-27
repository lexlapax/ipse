defmodule Ipse.Provider.MintTransport do
  @moduledoc false

  # Experimental, unwired transport primitive. The caller must establish the
  # policy linearization protocol; a successful callback alone is not such a
  # protocol. Connection setup can expose destination and proxy metadata. The
  # caller must own and enforce the hard task deadline, including callbacks.
  @max_response 8_388_608
  @max_chunks 131_072
  @reserved_headers ~w(host content-length transfer-encoding proxy-authorization connection te trailer upgrade)

  def stream(url, headers, body, timeout, limit, initial, consume, admit),
    do: execute(url, headers, body, timeout, limit, initial, consume, admit, :diagnostic)

  @doc false
  def stream_witnessed(url, headers, body, timeout, limit, initial, consume, admit),
    do: execute(url, headers, body, timeout, limit, initial, consume, admit, :owned)

  defp execute(url, headers, body, timeout, limit, initial, consume, admit, mode)
       when is_binary(url) and is_list(headers) and is_binary(body) and
              is_integer(timeout) and timeout in 1..120_000 and
              is_integer(limit) and limit in 1..@max_response and byte_size(body) <= @max_response and
              is_function(consume, 2) and is_function(admit, 1) do
    with {:ok, uri} <- URI.new(url),
         true <-
           uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
             is_nil(uri.userinfo) and is_nil(uri.fragment) and is_integer(uri.port) and
             uri.port in 1..65_535 and byte_size(url) <= 2048 and
             (uri.scheme == "https" or uri.host in ["127.0.0.1", "localhost", "::1"]) and
             valid_headers?(headers) do
      deadline = System.monotonic_time(:millisecond) + timeout
      options = options(uri, timeout)

      case Mint.HTTP.connect(scheme(uri.scheme), uri.host, uri.port, options) do
        {:ok, conn} ->
          observation = socket_observation(conn, uri, mode)
          witness_ref = make_ref()
          status_key = {__MODULE__, make_ref()}
          Process.put(status_key, nil)

          checked_consume = fn event, acc ->
            case event do
              {:status, _, status} when status >= 200 ->
                if is_nil(Process.get(status_key)),
                  do: Process.put(status_key, status),
                  else: Process.put(status_key, :invalid)

              _ ->
                :ok
            end

            consume.(event, acc)
          end

          result =
            if mode == :owned and observation == :unavailable do
              {:error, :inference_cleanup_unavailable}
            else
              try do
                case admitted_send(conn, uri, headers, body, deadline, admit, mode, witness_ref) do
                  {:ok, next, ref} ->
                    case receive_response(
                           next,
                           ref,
                           deadline,
                           limit,
                           initial,
                           checked_consume,
                           {0, 0},
                           0
                         ) do
                      {:ok, _} = success ->
                        if mode == :owned,
                          do:
                            Ipse.Provider.CompletionWitness.http_complete(
                              url,
                              Process.get(status_key)
                            )

                        success

                      other ->
                        {:unknown, other}
                    end

                  {:error, :inference_request_refused} = refusal ->
                    refusal

                  _ ->
                    {:unknown, :inference_send_uncertain}
                end
              rescue
                _ -> {:unknown, :inference_request_failed}
              catch
                _, _ -> {:unknown, :inference_request_failed}
              end
            end

          close_result =
            try do
              case Mint.HTTP.close(conn) do
                {:ok, _} -> :ok
                _ -> {:error, :inference_cleanup_unconfirmed}
              end
            rescue
              _ -> {:error, :inference_cleanup_unconfirmed}
            catch
              _, _ -> {:error, :inference_cleanup_unconfirmed}
            end

          cleanup = observe_close(observation, close_result, mode)
          if mode == :owned, do: Ipse.Provider.CompletionWitness.cleaned(witness_ref, cleanup)
          Process.delete(status_key)
          if cleanup == :ok, do: result, else: {:unknown, :inference_cleanup_unconfirmed}

        _ ->
          {:error, :inference_connection_failed}
      end
    else
      _ -> {:error, :inference_connection_failed}
    end
  rescue
    _ -> {:error, :inference_request_failed}
  catch
    _, _ -> {:error, :inference_request_failed}
  end

  defp execute(_, _, _, _, _, _, _, _, _), do: {:error, :invalid_inference_request}

  defp socket_observation(_, _, :diagnostic), do: :diagnostic

  defp socket_observation(conn, %{scheme: "http"}, :owned) do
    case Mint.HTTP.get_socket(conn) do
      port when is_port(port) -> {:port, port, :erlang.monitor(:port, port)}
      _ -> :unavailable
    end
  rescue
    _ -> :unavailable
  end

  defp socket_observation(_, _, :owned), do: :unavailable

  defp observe_close(:diagnostic, :ok, :diagnostic), do: :ok

  defp observe_close({:port, port, ref}, :ok, :owned) do
    receive do
      {:DOWN, ^ref, :port, ^port, _} -> :ok
    after
      2_000 ->
        Process.demonitor(ref, [:flush])
        {:error, :inference_cleanup_unconfirmed}
    end
  end

  defp observe_close({:port, _, ref}, _, :owned) do
    Process.demonitor(ref, [:flush])
    {:error, :inference_cleanup_unconfirmed}
  end

  defp observe_close(_, _, _), do: {:error, :inference_cleanup_unconfirmed}

  defp valid_headers?(headers) when length(headers) <= 128 do
    Enum.reduce_while(headers, 0, fn
      {name, value}, total when is_binary(name) and is_binary(value) ->
        next = total + byte_size(name) + byte_size(value) + 4

        if next <= 16_384 and byte_size(name) in 1..256 and
             String.downcase(name) not in @reserved_headers and
             Regex.match?(~r/\A[!\#$%&'*+.^_`|~0-9A-Za-z-]+\z/, name) and
             Enum.all?(:binary.bin_to_list(value), &(&1 == 9 or &1 in 32..126 or &1 >= 128)) do
          {:cont, next}
        else
          {:halt, :invalid}
        end

      _, _ ->
        {:halt, :invalid}
    end) != :invalid
  end

  defp valid_headers?(_), do: false

  defp options(uri, timeout) do
    bound = min(timeout, 30_000)
    transport = [timeout: bound, send_timeout: bound, send_timeout_close: true]

    proxy =
      Enum.map(Ipse.HTTP.finch_options(uri), fn
        {:proxy, {scheme, host, port, opts}} ->
          {:proxy,
           {scheme, host, port,
            [transport_opts: transport, tunnel_timeout: bound, max_header_list_size: 16_384] ++
              opts}}

        other ->
          other
      end)

    [mode: :passive, protocols: [:http1], max_header_list_size: 16_384, transport_opts: transport] ++
      proxy
  end

  # The callback may hold policy locks while invoking this exact-owner one-use
  # continuation. It returns only after Mint has attempted the request write.
  # Once a write is attempted, any failed callback or duplicate use is unknown.
  defp admitted_send(conn, uri, headers, body, deadline, admit, mode, witness_ref) do
    owner = self()
    key = {__MODULE__, make_ref()}
    Process.put(key, :pending)

    send_once = fn ->
      cond do
        self() != owner ->
          {:error, :inference_request_refused}

        Process.get(key) in [:sending, :invalid] or match?({:sent, _, _}, Process.get(key)) ->
          Process.put(key, :invalid)
          {:error, :inference_send_uncertain}

        Process.get(key) != :pending ->
          {:error, :inference_request_refused}

        remaining(deadline) == 0 ->
          Process.put(key, :refused)
          {:error, :inference_request_refused}

        true ->
          Process.put(key, :sending)

          if mode == :owned do
            Ipse.Provider.CompletionWitness.http_started(URI.to_string(uri))
            Ipse.Provider.CompletionWitness.borrowed(witness_ref)
          end

          case Mint.HTTP.request(conn, "POST", path(uri), headers, body) do
            {:ok, next, ref} ->
              Process.put(key, {:sent, next, ref})
              :ok

            _ ->
              Process.put(key, :invalid)
              {:error, :inference_send_uncertain}
          end
      end
    end

    try do
      result =
        try do
          {:returned, admit.(send_once)}
        rescue
          _ -> :failed
        catch
          _, _ -> :failed
        end

      case {result, Process.get(key)} do
        {{:returned, :ok}, {:sent, next, ref}} -> {:ok, next, ref}
        {_, state} when state in [:pending, :refused] -> {:error, :inference_request_refused}
        _ -> {:error, :inference_send_uncertain}
      end
    after
      Process.delete(key)
    end
  end

  defp receive_response(conn, ref, deadline, limit, acc, consume, bytes, chunks) do
    timeout = remaining(deadline)

    if timeout <= 0 do
      {:error, :inference_timeout}
    else
      case Mint.HTTP.recv(conn, 0, timeout) do
        {:ok, next, events} ->
          case process_events(events, ref, deadline, limit, acc, consume, bytes, chunks) do
            {:continue, value, total, count} ->
              receive_response(next, ref, deadline, limit, value, consume, total, count)

            result ->
              result
          end

        {:error, _, %Mint.TransportError{reason: :timeout}, _} ->
          {:error, :inference_timeout}

        {:error, _, _, _} ->
          {:error, :inference_connection_failed}
      end
    end
  end

  defp process_events([], _, deadline, _, acc, _, bytes, chunks) do
    if remaining(deadline) > 0,
      do: {:continue, acc, bytes, chunks},
      else: {:error, :inference_timeout}
  end

  defp process_events([{:done, ref} | []], ref, deadline, _, acc, _, _, _) do
    if remaining(deadline) > 0, do: {:ok, acc}, else: {:error, :inference_timeout}
  end

  defp process_events([event | rest], ref, deadline, limit, acc, consume, bytes, chunks) do
    if remaining(deadline) == 0 do
      {:error, :inference_timeout}
    else
      handle_event(event, rest, ref, deadline, limit, acc, consume, bytes, chunks)
    end
  end

  defp handle_event(
         event,
         rest,
         ref,
         deadline,
         limit,
         acc,
         consume,
         {data_bytes, header_bytes} = bytes,
         chunks
       ) do
    case event do
      {:data, ^ref, data} when is_binary(data) ->
        if data_bytes + byte_size(data) <= limit and chunks < @max_chunks do
          forward(
            event,
            rest,
            ref,
            deadline,
            limit,
            acc,
            consume,
            {data_bytes + byte_size(data), header_bytes},
            chunks + 1
          )
        else
          {:error, :inference_response_too_large}
        end

      {:status, ^ref, _} when chunks < @max_chunks ->
        forward(event, rest, ref, deadline, limit, acc, consume, bytes, chunks + 1)

      {:headers, ^ref, headers} when is_list(headers) and chunks < @max_chunks ->
        size =
          Enum.reduce(headers, 0, fn {key, value}, count ->
            count + byte_size(key) + byte_size(value)
          end)

        if header_bytes + size <= 65_536,
          do:
            forward(
              event,
              rest,
              ref,
              deadline,
              limit,
              acc,
              consume,
              {data_bytes, header_bytes + size},
              chunks + 1
            ),
          else: {:error, :inference_response_too_large}

      _ ->
        {:error, :invalid_inference_response}
    end
  end

  defp forward(event, rest, ref, deadline, limit, acc, consume, bytes, chunks) do
    case consume.(event, acc) do
      {:cont, next} ->
        process_events(rest, ref, deadline, limit, next, consume, bytes, chunks)

      {:halt, result} ->
        if remaining(deadline) > 0, do: {:halted, result}, else: {:error, :inference_timeout}

      _ ->
        {:error, :invalid_inference_consumer}
    end
  end

  defp scheme("http"), do: :http
  defp scheme("https"), do: :https

  defp path(uri),
    do:
      if(uri.path in [nil, ""], do: "/", else: uri.path) <>
        if(uri.query, do: "?" <> uri.query, else: "")

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
