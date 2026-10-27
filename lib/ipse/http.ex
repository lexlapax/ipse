defmodule Ipse.HTTP do
  @moduledoc "Owned HTTP clients and explicit proxy policy."

  # Fixed names bound atom usage. Each guardian retains its registry lease until
  # the profile has exited, including when its borrower is killed.
  @profiles for index <- 1..64, do: :"ipse_http_#{index}"

  def with_finch(fun, conn_opts \\ []) when is_function(fun, 1) do
    Application.ensure_all_started(:ipse)
    owner = self()
    reference = make_ref()
    scope = Ipse.Session.Resources.current()

    {guardian, monitor} =
      spawn_monitor(fn -> own_profile(owner, reference, conn_opts, nil, scope) end)

    borrow(fun, guardian, monitor, reference)
  end

  @doc false
  def bounded_request(request, limit, timeout \\ 15_000)
      when is_integer(limit) and limit in 1..8_388_608 and is_integer(timeout) and timeout > 0 do
    uri = %URI{scheme: to_string(request.scheme), host: request.host, port: request.port}

    options =
      [transport_opts: [timeout: min(timeout, 10_000)]] ++ finch_options(uri)

    deadline = System.monotonic_time(:millisecond) + timeout
    target = request_url(request)
    Ipse.Provider.CompletionWitness.http_started(target)

    with_finch(
      fn finch ->
        initial = %{status: nil, body: [], bytes: 0, error: nil}

        result =
          Finch.stream_while(
            request,
            finch,
            initial,
            fn event, acc ->
              cond do
                System.monotonic_time(:millisecond) >= deadline ->
                  {:halt, %{acc | error: :timeout}}

                true ->
                  bounded_event(event, acc, limit)
              end
            end,
            receive_timeout: timeout,
            request_timeout: timeout,
            pool_timeout: min(timeout, 2000)
          )

        case result do
          {:ok, %{error: nil} = acc} ->
            Ipse.Provider.CompletionWitness.http_complete(target, acc.status)
            {:ok, acc.status, acc.body |> Enum.reverse() |> IO.iodata_to_binary()}

          {:ok, %{error: error}} ->
            {:error, error}

          _ ->
            {:error, :connection_failed}
        end
      end,
      options
    )
  end

  defp bounded_event({:status, status}, acc, _), do: {:cont, %{acc | status: status}}

  defp bounded_event({:headers, headers}, acc, limit) do
    oversized =
      Enum.any?(headers, fn {key, value} ->
        String.downcase(key) == "content-length" and
          case Integer.parse(value) do
            {size, ""} -> size > limit
            _ -> false
          end
      end)

    if oversized, do: {:halt, %{acc | error: :response_too_large}}, else: {:cont, acc}
  end

  defp bounded_event({:data, bytes}, acc, limit) do
    if acc.bytes + byte_size(bytes) > limit,
      do: {:halt, %{acc | error: :response_too_large}},
      else: {:cont, %{acc | bytes: acc.bytes + byte_size(bytes), body: [bytes | acc.body]}}
  end

  defp bounded_event(_, acc, _), do: {:cont, acc}

  @doc false
  def prepare_finch(owner) do
    reference = make_ref()

    guardian =
      spawn(fn ->
        monitor = Process.monitor(owner)

        receive do
          {^reference, :borrow, borrower, options, scope} ->
            own_profile(borrower, reference, options, monitor, scope)

          {^reference, :cancel} ->
            :ok

          {:DOWN, ^monitor, :process, _, _} ->
            :ok
        end
      end)

    {guardian, reference}
  end

  @doc false
  def cancel_finch(nil), do: nil

  def cancel_finch({guardian, reference}) do
    send(guardian, {reference, :cancel})
    guardian
  end

  @doc false
  def with_finch(fun, options, {guardian, reference}) when is_function(fun, 1) do
    monitor = Process.monitor(guardian)
    send(guardian, {reference, :borrow, self(), options, Ipse.Session.Resources.current()})
    borrow(fun, guardian, monitor, reference)
  end

  def finch_guardian(owner) do
    case Registry.lookup(Ipse.Registry, {__MODULE__, :finch_borrower, owner}) do
      [{guardian, _}] -> if Process.alive?(guardian), do: guardian
      [] -> nil
    end
  end

  def await_guardian(nil), do: :ok

  def await_guardian(pid) do
    monitor = Process.monitor(pid)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      2000 ->
        Process.demonitor(monitor, [:flush])
        {:error, :cleanup_unconfirmed}
    end
  end

  defp borrow(fun, guardian, monitor, reference) do
    receive do
      {^reference, {:ok, profile}} ->
        Ipse.Provider.CompletionWitness.borrowed(reference)

        try do
          fun.(profile)
        after
          send(guardian, {reference, :finished})
          cleanup = await_cleanup(guardian, monitor, reference)
          Ipse.Provider.CompletionWitness.cleaned(reference, cleanup)
        end

      {^reference, {:error, _} = error} ->
        await_cleanup(guardian, monitor, reference)
        error

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        {:error, "Could not start an isolated HTTP client."}
    end
  end

  defp own_profile(owner, reference, conn_opts, lease_owner_monitor, scope) do
    Process.flag(:trap_exit, true)
    owner_monitor = Process.monitor(owner)

    case Ipse.Session.Resources.register(:http, scope) do
      {:ok, ticket} ->
        result =
          try do
            run_profile(owner, reference, conn_opts, lease_owner_monitor, owner_monitor, ticket)
          rescue
            _ -> {:error, :cleanup_unconfirmed}
          catch
            _, _ -> {:error, :cleanup_unconfirmed}
          end

        Ipse.Session.Resources.closed(ticket, result)
        send(owner, {reference, :cleanup, result})

      _ ->
        send(owner, {reference, {:error, "HTTP cleanup scope is closed."}})
    end
  end

  defp await_cleanup(guardian, monitor, reference) do
    receive do
      {^reference, :cleanup, result} ->
        await_exit(guardian, monitor)
        result

      {:DOWN, ^monitor, :process, ^guardian, _} ->
        {:error, :cleanup_unconfirmed}
    end
  end

  defp request_url(request) do
    URI.to_string(%URI{
      scheme: to_string(request.scheme),
      host: request.host,
      port: request.port,
      path: request.path,
      query: request.query
    })
  end

  defp run_profile(owner, reference, conn_opts, lease_owner_monitor, owner_monitor, ticket) do
    Registry.register(Ipse.Registry, {__MODULE__, :finch_borrower, owner}, nil)

    case reserve() do
      {:ok, name} ->
        try do
          case start_client(conn_opts, name) do
            {:ok, profile} ->
              profile_monitor = Process.monitor(profile)
              children = monitor_children(profile)

              send(owner, {reference, {:ok, name}})

              borrower_stopped =
                receive do
                  {^reference, :finished} ->
                    true

                  {:DOWN, ^owner_monitor, :process, ^owner, _} ->
                    true

                  {:DOWN, ^profile_monitor, :process, ^profile, _} ->
                    stop_borrower(owner, owner_monitor)

                  {:EXIT, ^profile, _} ->
                    stop_borrower(owner, owner_monitor)

                  {^reference, :cancel} ->
                    stop_borrower(owner, owner_monitor)

                  {:DOWN, ^lease_owner_monitor, :process, _, _} ->
                    stop_borrower(owner, owner_monitor)

                  {:ipse_cancel_resource, id} when ticket != nil and ticket.id == id ->
                    stop_borrower(owner, owner_monitor)
                end

              Process.demonitor(profile_monitor, [:flush])
              stop_profile(profile)
              Enum.each(children, fn {pid, ref} -> await_exit(pid, ref) end)
              if borrower_stopped, do: :ok, else: {:error, :cleanup_unconfirmed}

            _ ->
              send(owner, {reference, {:error, "Could not start an isolated HTTP client."}})
              :ok
          end
        after
          Registry.unregister(Ipse.Registry, {__MODULE__, name})
        end

      :full ->
        send(
          owner,
          {reference, {:error, "HTTP clients are busy. Retry after another request finishes."}}
        )

        :ok
    end
  end

  defp stop_borrower(owner, monitor) do
    Process.exit(owner, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^owner, _} -> true
    after
      1000 -> false
    end
  end

  defp reserve do
    Enum.find_value(@profiles, :full, fn name ->
      case Registry.register(Ipse.Registry, {__MODULE__, name}, nil) do
        {:ok, _} -> {:ok, name}
        {:error, _} -> nil
      end
    end)
  end

  defp start_client(conn_opts, name) do
    Finch.start_link(
      name: name,
      pools: %{
        default: [
          size: 1,
          count: 1,
          conn_opts: [protocols: [:http1], max_header_list_size: 16_384] ++ conn_opts
        ]
      }
    )
  end

  defp stop_profile(profile) do
    monitor = Process.monitor(profile)

    try do
      Supervisor.stop(profile, :normal, 1000)
    catch
      :exit, _ -> Process.exit(profile, :kill)
    end

    receive do
      {:DOWN, ^monitor, :process, ^profile, _} -> :ok
    after
      1_000 ->
        Process.exit(profile, :kill)
        await_exit(profile, monitor)
    end
  end

  defp monitor_children(profile) do
    for {_, pid, _, _} <- Supervisor.which_children(profile),
        is_pid(pid),
        do: {pid, Process.monitor(pid)}
  end

  defp await_exit(pid, monitor) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    end
  end

  def finch_options(uri) do
    case selected(uri) do
      nil ->
        []

      proxy ->
        headers =
          if proxy.userinfo do
            {user, password} = credentials(proxy.userinfo)
            [{"proxy-authorization", "Basic " <> Base.encode64(user <> ":" <> password)}]
          else
            []
          end

        [proxy: {:http, proxy.host, proxy.port, []}, proxy_headers: headers]
    end
  end

  defp selected(uri) do
    name = if uri.scheme == "https", do: "HTTPS_PROXY", else: "HTTP_PROXY"
    value = System.get_env(name) || System.get_env(String.downcase(name))

    if bypass?(uri.host) or value in [nil, ""] do
      nil
    else
      case URI.new(value) do
        {:ok, proxy} ->
          if proxy.scheme == "http" and proxy.host not in [nil, ""] and
               is_integer(proxy.port) and proxy.port in 1..65535 and
               proxy.path in [nil, "", "/"] and is_nil(proxy.query) and is_nil(proxy.fragment) do
            proxy
          else
            raise ArgumentError, "Unsupported proxy URL"
          end

        _ ->
          raise ArgumentError, "Unsupported proxy URL"
      end
    end
  end

  defp credentials(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, password] -> {URI.decode(user), URI.decode(password)}
      [user] -> {URI.decode(user), ""}
    end
  end

  def bypass?(host) do
    host = String.downcase(host)

    patterns =
      (System.get_env("NO_PROXY") || System.get_env("no_proxy") || "")
      |> String.split(",", trim: true)

    host in ["localhost", "::1", "[::1]"] or loopback_ipv4?(host) or
      Enum.any?(patterns, fn pattern ->
        pattern = pattern |> String.trim() |> String.downcase() |> String.replace(~r/:\d+$/, "")
        domain = String.trim_leading(pattern, ".")
        pattern == "*" or host == domain or String.ends_with?(host, "." <> domain)
      end)
  end

  defp loopback_ipv4?(host),
    do: match?({:ok, {127, _, _, _}}, :inet.parse_address(String.to_charlist(host)))
end
