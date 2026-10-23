defmodule IpseMCPExample.Fixture do
  @moduledoc false

  def text, do: String.duplicate("évidence λine 🌿\n", 900)

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{"text" => %{"type" => "string"}},
      "required" => ["text"]
    }
  end

  def stdio(root, mode) do
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)
    loop(root, mode)
  end

  defp loop(root, mode) do
    case IO.binread(:stdio, :line) do
      line when is_binary(line) ->
        rpc = :json.decode(line)
        record(root, rpc)

        if rpc["id"] do
          if rpc["method"] == "tools/call" and mode == "disconnect" do
            System.halt(0)
          end

          if rpc["method"] == "tools/call" and mode == "hold" do
            receive do: (:never -> :ok)
          end

          changed = File.exists?(Path.join(root, "change-descriptor"))
          result = result(rpc, changed, text())

          IO.binwrite(
            :stdio,
            :json.encode(%{"jsonrpc" => "2.0", "id" => rpc["id"], "result" => result})
          )

          IO.binwrite(:stdio, "\n")
        end

        loop(root, mode)

      _ ->
        :ok
    end
  end

  def stdio_config(root, mode \\ "normal") do
    runtime = to_string(:code.root_dir())
    erl = Path.join([runtime, "erts-" <> to_string(:erlang.system_info(:version)), "bin", "erl"])
    boot = clean_boot(runtime)
    file = :code.which(__MODULE__) |> to_string()
    %{type: :regular} = File.lstat!(file)
    true = Path.extname(file) == ".beam"

    expression =
      "application:ensure_all_started(elixir), 'Elixir.Code':'ensure_loaded!'('Elixir.IpseMCPExample.Fixture'), 'Elixir.IpseMCPExample.Fixture':stdio(" <>
        erlang_term(root) <> ", " <> erlang_term(mode) <> "), init:stop()."

    %{
      "id" => "fixture",
      "command" => erl,
      "args" => [
        "+S",
        "1:1",
        "+A",
        "1",
        "-noshell",
        "-boot",
        boot,
        "-boot_var",
        "RELEASE_LIB",
        Path.join(runtime, "lib"),
        "-pa",
        Application.app_dir(:elixir, "ebin"),
        "-pa",
        Path.dirname(file),
        "-eval",
        expression
      ],
      "tools" => ["fetch"],
      "timeout_ms" => 5000
    }
  end

  defp erlang_term(value), do: :io_lib.format(~c"~p", [value]) |> IO.iodata_to_binary()

  defp clean_boot(runtime) do
    current =
      case :init.get_argument(:boot) do
        {:ok, [[path]]} ->
          path = List.to_string(path)

          if Path.type(path) == :absolute and
               String.starts_with?(Path.expand(path), Path.join(runtime, "releases") <> "/"),
             do: Path.join(Path.dirname(path), "start_clean")

        _ ->
          nil
      end

    Enum.find([current, Path.join([runtime, "bin", "no_dot_erlang"])], fn path ->
      is_binary(path) and File.regular?(path <> ".boot")
    end) || raise "No clean bundled runtime boot file"
  end

  def record(root, rpc) do
    File.write!(
      Path.join(root, "transport.jsonl"),
      :json.encode(%{"method" => rpc["method"], "params" => rpc["params"]})
      |> IO.iodata_to_binary()
      |> Kernel.<>("\n"),
      [:append]
    )
  end

  def records(root) do
    case File.read(Path.join(root, "transport.jsonl")) do
      {:ok, bytes} -> bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
      {:error, :enoent} -> []
    end
  end

  def calls(root), do: Enum.count(records(root), &(&1["method"] == "tools/call"))
  def discoveries(root), do: Enum.count(records(root), &(&1["method"] == "tools/list"))

  def result(%{"method" => "initialize"}, _, _) do
    %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}, "resources" => %{}, "prompts" => %{}},
      "serverInfo" => %{"name" => "synthetic-mcp-actions", "version" => "1"}
    }
  end

  def result(%{"method" => "tools/list"}, changed, _) do
    %{
      "tools" => [
        %{
          "name" => "fetch",
          "description" =>
            if(changed, do: "Changed descriptor", else: "Fetch synthetic public text"),
          "inputSchema" => schema()
        }
      ]
    }
  end

  def result(%{"method" => "tools/call"}, _, text),
    do: %{"content" => [%{"type" => "text", "text" => text}]}

  def result(%{"method" => "resources/list"}, _, _),
    do: %{"resources" => [%{"uri" => "fixture://document", "name" => "document"}]}

  def result(%{"method" => "resources/read"}, _, text),
    do: %{"contents" => [%{"uri" => "fixture://document", "text" => text}]}

  def result(%{"method" => "prompts/list"}, _, _),
    do: %{
      "prompts" => [
        %{"name" => "summary", "arguments" => [%{"name" => "text", "required" => true}]}
      ]
    }

  def result(%{"method" => "prompts/get"}, _, text),
    do: %{"messages" => [%{"role" => "user", "content" => %{"type" => "text", "text" => text}}]}

  def result(_, _, _), do: %{}

  def http(root, owner, mode \\ :normal) do
    {:ok, supervisor} = Task.Supervisor.start_link()
    Process.unlink(supervisor)
    caller = self()
    ready = make_ref()

    {:ok, _} =
      Task.Supervisor.start_child(supervisor, fn ->
        {:ok, lifecycle} = GenServer.start_link(__MODULE__.HTTPLifecycle, owner)
        send(caller, {ready, lifecycle})
        monitor = Process.monitor(lifecycle)
        receive do: ({:DOWN, ^monitor, :process, ^lifecycle, _} -> :ok)
      end)

    lifecycle =
      receive do
        {^ready, pid} -> pid
      after
        2000 -> raise "HTTP fixture lifecycle did not start"
      end

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    Task.Supervisor.start_child(supervisor, fn ->
      accept(listener, supervisor, root, owner, mode, lifecycle)
    end)

    entry = %{
      "id" => "fixture",
      "transport" => "http",
      "url" => "http://127.0.0.1:#{port}/mcp",
      "allow_insecure_loopback" => true,
      "tools" => ["fetch"],
      "timeout_ms" => 5000
    }

    {%{listener: listener, supervisor: supervisor, lifecycle: lifecycle}, entry}
  end

  def http_session(%{lifecycle: lifecycle}, handler) do
    case GenServer.call(lifecycle, {:session, handler}) do
      {:ok, session} -> session
      error -> raise "HTTP fixture has no established synthetic session: #{inspect(error)}"
    end
  end

  def hold_delete(%{lifecycle: lifecycle}, session),
    do: GenServer.call(lifecycle, {:hold_delete, session})

  def release_delete(%{lifecycle: lifecycle}, session),
    do: GenServer.call(lifecycle, {:release_delete, session})

  def await_delete(%{lifecycle: lifecycle}, session, timeout \\ 5000) do
    GenServer.call(lifecycle, {:await_delete, session}, timeout)
  catch
    :exit, _ -> {:error, :delete_cleanup_unconfirmed}
  end

  def stop(%{listener: listener, supervisor: supervisor, lifecycle: lifecycle}) do
    monitor = Process.monitor(supervisor)
    lifecycle_monitor = Process.monitor(lifecycle)
    :gen_tcp.close(listener)

    try do
      Supervisor.stop(supervisor)
    catch
      :exit, {:noproc, _} -> :ok
    end

    deadline = System.monotonic_time(:millisecond) + 2000
    confirmed_stop(supervisor, monitor, deadline)
    confirmed_stop(lifecycle, lifecycle_monitor, deadline)

    :ok
  end

  defp confirmed_stop(pid, monitor, deadline) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        raise "MCP fixture process cleanup unconfirmed"
    end
  end

  defp accept(listener, supervisor, root, owner, mode, lifecycle) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, handler} =
          Task.Supervisor.start_child(supervisor, fn ->
            receive do: (:serve -> serve(socket, root, owner, mode, lifecycle))
          end)

        :ok = :gen_tcp.controlling_process(socket, handler)
        send(handler, :serve)
        accept(listener, supervisor, root, owner, mode, lifecycle)

      _ ->
        :ok
    end
  end

  defp serve(socket, root, owner, mode, lifecycle) do
    try do
      {method, headers, rpc} = read_request(socket, "")

      session =
        GenServer.call(
          lifecycle,
          {:request, self(), method, headers["mcp-session-id"], rpc["method"]}
        )

      if method == "DELETE" do
        case GenServer.call(lifecycle, {:delete_entered, session, self()}) do
          :hold ->
            receive do
              {:release_mcp_delete, ^session} -> :ok
            after
              5000 -> raise "HTTP DELETE barrier not released"
            end

          :ok ->
            :ok
        end
      end

      File.write!(
        Path.join(root, "transport.jsonl"),
        JSON.encode!(%{
          "method" => rpc["method"],
          "params" => rpc["params"],
          "http_method" => method,
          "session_id" => session
        }) <> "\n",
        [:append]
      )

      cond do
        rpc["method"] == "tools/call" and mode == :disconnect ->
          send(owner, {:extension_mcp_fixture, :dispatched, self()})

        rpc["method"] == "tools/call" and mode == :hold ->
          send(owner, {:extension_mcp_fixture, :dispatched, self()})
          {:error, :closed} = :gen_tcp.recv(socket, 0, 30_000)
          send(owner, {:extension_mcp_fixture, :closed, self()})

        true ->
          status = if method == "DELETE" or is_nil(rpc["id"]), do: 202, else: 200
          changed = File.exists?(Path.join(root, "change-descriptor"))

          body =
            if status == 202,
              do: "",
              else:
                :json.encode(%{
                  "jsonrpc" => "2.0",
                  "id" => rpc["id"],
                  "result" => result(rpc, changed, text())
                })
                |> IO.iodata_to_binary()

          sent =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 #{status} Fixture\r\ncontent-type: application/json\r\nmcp-session-id: #{session}\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )

          :ok = :gen_tcp.close(socket)

          if method == "DELETE",
            do: GenServer.call(lifecycle, {:delete_complete, session, self(), sent})
      end
    after
      :gen_tcp.close(socket)
    end
  end

  defp read_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [raw, body] ->
        [first | lines] = String.split(raw, "\r\n")

        headers =
          Map.new(lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        size = String.to_integer(headers["content-length"] || "0")
        body = read_body(socket, body, size)
        {hd(String.split(first, " ")), headers, if(body == "", do: %{}, else: :json.decode(body))}

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, buffer <> bytes)
    end
  end

  defp read_body(_, body, size) when byte_size(body) >= size, do: body

  defp read_body(socket, body, size) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
    read_body(socket, body <> bytes, size)
  end
end

defmodule IpseMCPExample.Fixture.HTTPLifecycle do
  @moduledoc false
  use GenServer

  @impl true
  def init(owner), do: {:ok, %{owner: owner, sessions: %{}, handlers: %{}}}

  @impl true
  def handle_call({:request, handler, http_method, supplied, rpc_method}, _from, state) do
    if map_size(state.handlers) >= 1024 or
         (rpc_method == "initialize" and map_size(state.sessions) >= 128) do
      {:stop, :fixture_lifetime_limit, {:error, :fixture_lifetime_limit}, state}
    else
      session =
        cond do
          rpc_method == "initialize" ->
            "fixture-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

          is_binary(supplied) and Map.has_key?(state.sessions, supplied) ->
            supplied

          true ->
            nil
        end

      sessions =
        if rpc_method == "initialize",
          do:
            Map.put(state.sessions, session, %{
              status: :pending,
              gate: false,
              delete_handler: nil,
              waiters: []
            }),
          else: state.sessions

      monitor = Process.monitor(handler)

      row = %{
        session: session,
        established: is_binary(session) and supplied == session,
        http_method: http_method,
        monitor: monitor
      }

      {:reply, session,
       %{state | sessions: sessions, handlers: Map.put(state.handlers, handler, row)}}
    end
  end

  def handle_call({:session, handler}, _from, state) do
    result =
      case state.handlers[handler] do
        %{session: session, established: true} -> {:ok, session}
        _ -> {:error, :session_not_established}
      end

    {:reply, result, state}
  end

  def handle_call({:hold_delete, session}, _from, state) do
    case state.sessions[session] do
      %{status: :pending} = entry ->
        {:reply, :ok, put_in(state.sessions[session], %{entry | gate: true})}

      _ ->
        {:reply, {:error, :delete_already_started_or_unknown}, state}
    end
  end

  def handle_call({:delete_entered, session, handler}, _from, state) do
    case state.sessions[session] do
      %{status: :pending} = entry ->
        status = if entry.gate, do: :waiting, else: :running

        state =
          put_in(state.sessions[session], %{entry | status: status, delete_handler: handler})

        if entry.gate,
          do: send(state.owner, {:extension_mcp_fixture, :delete_waiting, session, handler})

        {:reply, if(entry.gate, do: :hold, else: :ok), state}

      _ ->
        {:reply, {:error, :unexpected_delete}, state}
    end
  end

  def handle_call({:release_delete, session}, _from, state) do
    case state.sessions[session] do
      %{status: :waiting, delete_handler: handler} = entry ->
        send(handler, {:release_mcp_delete, session})
        {:reply, :ok, put_in(state.sessions[session], %{entry | gate: false, status: :running})}

      _ ->
        {:reply, {:error, :delete_not_waiting}, state}
    end
  end

  def handle_call({:delete_complete, session, handler, sent}, _from, state) do
    case state.sessions[session] do
      %{delete_handler: ^handler} = entry ->
        result = if sent == :ok, do: :ok, else: {:error, :delete_ack_incomplete}
        Enum.each(entry.waiters, &GenServer.reply(&1, result))

        state =
          put_in(state.sessions[session], %{
            entry
            | status: if(sent == :ok, do: :complete, else: :failed),
              waiters: []
          })

        {:reply, result, state}

      _ ->
        {:reply, {:error, :unexpected_delete_completion}, state}
    end
  end

  def handle_call({:await_delete, session}, from, state) do
    case state.sessions[session] do
      %{status: :complete} ->
        {:reply, :ok, state}

      %{status: :failed} ->
        {:reply, {:error, :delete_ack_incomplete}, state}

      %{waiters: waiters} = entry when length(waiters) < 128 ->
        {:noreply, put_in(state.sessions[session], %{entry | waiters: [from | waiters]})}

      _ ->
        {:reply, {:error, :unknown_or_unbounded_delete_wait}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, handler, _}, state) do
    case state.handlers[handler] do
      %{monitor: ^ref, session: session, http_method: "DELETE"} ->
        case state.sessions[session] do
          %{status: status} = entry when status not in [:complete, :failed] ->
            Enum.each(entry.waiters, &GenServer.reply(&1, {:error, :delete_ack_incomplete}))
            {:noreply, put_in(state.sessions[session], %{entry | status: :failed, waiters: []})}

          _ ->
            {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end
end
