defmodule Ipse.MCP.HTTPTest do
  use ExUnit.Case, async: false
  alias Ipse.MCP.{Client, Config}

  defmodule Model do
    def complete(_, messages, _tools, _emit) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "Finished"}, %{}}
      else
        calls =
          for n <- 1..2,
              do: %{
                "id" => "network-#{n}",
                "type" => "function",
                "function" => %{
                  "name" => "mcp__remote__write",
                  "arguments" => Jason.encode!(%{"text" => "synthetic"})
                }
              }

        {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => calls}, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-http-mcp-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    previous = System.get_env("IPSE_MCP_FIXTURE_TOKEN")
    System.put_env("IPSE_MCP_FIXTURE_TOKEN", "synthetic-bearer-token")

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_MCP_FIXTURE_TOKEN", previous),
        else: System.delete_env("IPSE_MCP_FIXTURE_TOKEN")

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "explicit HTTP configuration binds endpoint/auth identity without persisting tokens",
       ctx do
    path = Path.join(ctx.root, "config.json")

    entry = %{
      "id" => "remote",
      "transport" => "http",
      "url" => "https://example.test/mcp",
      "tools" => ["write"],
      "bearer_env" => "IPSE_MCP_FIXTURE_TOKEN"
    }

    File.write!(path, Jason.encode!(%{"servers" => [entry]}))
    assert {:ok, [first]} = Config.load(path)
    refute inspect(Config.manifest(first)) =~ "synthetic-bearer-token"
    assert Config.manifest(first).endpoint == entry["url"]
    System.put_env("IPSE_MCP_FIXTURE_TOKEN", "rotated-fixture-token")
    assert {:ok, [rotated]} = Config.load(path)
    assert first.fingerprint == rotated.fingerprint

    for invalid <- [
          Map.put(entry, "url", "http://example.test/mcp"),
          Map.put(entry, "url", "https://user:password@example.test/mcp"),
          Map.put(entry, "url", "https://example.test/mcp?token=x"),
          Map.put(entry, "url", "https://example.test/mcp#fragment"),
          Map.put(entry, "bearer_env", "OPENAI_API_KEY"),
          Map.put(entry, "sandbox", "native"),
          Map.put(entry, "command", "/bin/sh"),
          Map.put(entry, "transport", "sse")
        ] do
      File.write!(path, Jason.encode!(%{"servers" => [invalid]}))
      assert {:error, _} = Config.load(path)
    end

    local = Map.put(entry, "url", "http://127.0.0.1:1234/mcp")
    File.write!(path, Jason.encode!(%{"servers" => [local]}))
    assert {:error, _} = Config.load(path)

    File.write!(
      path,
      Jason.encode!(%{"servers" => [Map.put(local, "allow_insecure_loopback", true)]})
    )

    assert {:ok, [_]} = Config.load(path)
  end

  for mode <- [:json, :sse] do
    test "#{mode} handles initialization, private session headers, exact calls and DELETE", ctx do
      {server, agent} = fixture(ctx, unquote(mode))
      assert {:ok, [tool]} = Client.discover(server, ctx.root)
      assert {:ok, text} = Client.call(tool, %{"text" => "synthetic"}, ctx.root)
      assert text =~ "synthetic"
      refute text =~ "synthetic-bearer-token"
      refute text =~ "fixture-session-token"
      requests = Agent.get(agent, & &1.requests)
      assert Enum.count(requests, &(&1.method == "DELETE")) == 2

      assert Enum.all?(
               requests,
               &(&1.headers["authorization"] == "Bearer synthetic-bearer-token")
             )

      assert Enum.all?(requests, &(&1.headers["mcp-protocol-version"] == "2025-11-25"))

      assert Enum.all?(requests, fn request ->
               if request.rpc["method"] == "initialize",
                 do: is_nil(request.headers["mcp-session-id"]),
                 else: request.headers["mcp-session-id"] == "fixture-session-token"
             end)
    end
  end

  test "authentication, redirects, oversized bodies/headers and malformed streams fail closed",
       ctx do
    for mode <- [
          :unauthorized,
          :redirect,
          :huge_body,
          :huge_error,
          :huge_headers,
          :bad_sse,
          :mixed_sse,
          :wrong_id,
          :only_ping,
          :changed_session
        ] do
      {server, agent} = fixture(ctx, mode)
      result = Client.discover(server, ctx.root)
      assert match?({:error, _}, result) or match?({:unknown, _}, result)
      refute inspect(result) =~ "synthetic-bearer-token"
      if mode == :redirect, do: assert(length(Agent.get(agent, & &1.requests)) == 1)
    end
  end

  test "descriptor drift prevents dispatch", ctx do
    {server, agent} = fixture(ctx, :drift)
    assert {:ok, [tool]} = Client.discover(server, ctx.root)
    assert {:error, message} = Client.call(tool, %{"text" => "synthetic"}, ctx.root)
    assert message =~ "changed"
    assert Agent.get(agent, & &1.calls) == 0
  end

  test "HTTP preserves exact resource and prompt selection through the shared catalog", ctx do
    {server, _} = fixture(ctx, :catalog)
    assert {:ok, descriptors} = Client.discover(server, ctx.root)
    assert length(descriptors) == 3
    resource = Enum.find(descriptors, &(Map.get(&1, :kind) == :resource))
    prompt = Enum.find(descriptors, &(Map.get(&1, :kind) == :prompt))
    assert {:ok, text} = Client.call(resource, %{}, ctx.root)
    assert text =~ "Synthetic resource data"
    assert {:ok, text} = Client.call(prompt, %{"topic" => "synthetic"}, ctx.root)
    assert text =~ "Synthetic prompt data: synthetic"
  end

  test "post-dispatch disconnect is unknown, stops the batch and never replays on resume", ctx do
    {server, agent} = fixture(ctx, :disconnect)
    {pid, opts} = session(ctx, server, :allow)
    :ok = Ipse.Session.prompt(pid, "Synthetic network write")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert Agent.get(agent, & &1.calls) == 1
    id = Ipse.Session.info(pid).id
    {:ok, events} = Ipse.Journal.load(opts[:state_dir], id)

    outcomes =
      for e <- events,
          get_in(e, ["message", "role"]) == "tool",
          do: get_in(e, ["message", "ipse_tool_outcome", "status"])

    assert outcomes == ["unknown", "not_started"]
    :ok = Ipse.Session.close(pid)

    {:ok, resumed} =
      DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

    assert {:ok, ^events} = Ipse.Journal.load(opts[:state_dir], id)
    :ok = Ipse.Session.close(resumed)
    assert Agent.get(agent, & &1.calls) == 1
  end

  test "HTTP calls retain full approvals and headless denial", ctx do
    {server, agent} = fixture(ctx, :json)
    {denied, _} = session(ctx, server, :deny)
    :ok = Ipse.Session.prompt(denied, "Denied network effects")
    assert_receive {:ipse, ^denied, {:done, :ok}}, 5000
    assert Agent.get(agent, & &1.calls) == 0
    {pid, opts} = session(ctx, server, :ask)
    :ok = Ipse.Session.prompt(pid, "Approved network effects")

    for _ <- 1..2 do
      assert_receive {:ipse, ^pid,
                      {:approval, ref, "mcp__remote__write", %{"text" => "synthetic"}}},
                     5000

      :ok = Ipse.Session.approve(pid, ref, true)
    end

    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    assert Agent.get(agent, & &1.calls) == 2
    {:ok, events} = Ipse.Journal.load(opts[:state_dir], Ipse.Session.info(pid).id)

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "tool_started")),
             &(get_in(&1, ["mcp", "origin", "transport"]) == "streamable_http" and
                 &1["approval"] == "approved")
           )
  end

  test "cancel and owner death close private network clients after dispatch", ctx do
    for action <- [:cancel, :death] do
      {server, _} = fixture(ctx, :hold)
      {pid, _} = session(ctx, server, :allow)
      :ok = Ipse.Session.prompt(pid, "Wait for network response")
      assert_receive {:http_dispatched, handler}, 5000

      if action == :cancel,
        do: assert(:ok == Ipse.Session.cancel(pid)),
        else: Process.exit(pid, :kill)

      assert_receive {:http_socket_closed, ^handler}, 3000
    end
  end

  defp session(ctx, server, approval) do
    opts = [
      cwd: ctx.root,
      state_dir: Path.join(ctx.root, "sessions"),
      subscriber: self(),
      config: %{
        provider: :demo,
        model: "fixture",
        provider_module: Model,
        home: Path.join(ctx.root, "home"),
        mcp_servers: [server],
        approval: approval
      }
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Ipse.Session.close(pid) end)
    {pid, opts}
  end

  defp fixture(ctx, mode) do
    test = self()
    {:ok, agent} = Agent.start_link(fn -> %{requests: [], calls: 0, lists: 0} end)
    {:ok, sup} = Task.Supervisor.start_link()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    Task.Supervisor.start_child(sup, fn -> accept(listener, sup, agent, mode, test) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      stop_fixture(sup)
      stop_fixture(agent)
    end)

    path = Path.join(ctx.root, "config-#{port}.json")

    File.write!(
      path,
      Jason.encode!(%{
        "servers" => [
          %{
            "id" => "remote",
            "transport" => "http",
            "url" => "http://127.0.0.1:#{port}/mcp",
            "allow_insecure_loopback" => true,
            "tools" => ["write"],
            "resources" => if(mode == :catalog, do: ["fixture://guide"], else: []),
            "prompts" => if(mode == :catalog, do: ["summarize"], else: []),
            "bearer_env" => "IPSE_MCP_FIXTURE_TOKEN",
            "timeout_ms" => 5000
          }
        ]
      })
    )

    {:ok, [server]} = Config.load(path)
    {server, agent}
  end

  defp accept(listener, sup, agent, mode, test) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, worker} =
          Task.Supervisor.start_child(sup, fn ->
            receive do
              :serve -> serve(socket, agent, mode, test)
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, worker)
        send(worker, :serve)
        accept(listener, sup, agent, mode, test)

      _ ->
        :ok
    end
  end

  defp serve(socket, agent, mode, test, transport \\ :gen_tcp) do
    try do
      {method, headers, rpc} = read_request(socket, "", transport)

      count =
        Agent.get_and_update(agent, fn s ->
          next = %{
            s
            | requests: s.requests ++ [%{method: method, headers: headers, rpc: rpc}],
              calls: s.calls + if(rpc["method"] == "tools/call", do: 1, else: 0),
              lists: s.lists + if(rpc["method"] == "tools/list", do: 1, else: 0)
          }

          {next.lists, next}
        end)

      result =
        case rpc["method"] do
          "initialize" ->
            %{
              "protocolVersion" => "2025-11-25",
              "capabilities" => %{"tools" => %{}, "resources" => %{}, "prompts" => %{}},
              "serverInfo" => %{"name" => "fixture", "version" => "1"}
            }

          "tools/list" ->
            %{
              "tools" => [
                %{
                  "name" => "write",
                  "description" =>
                    if(mode == :drift and count > 1, do: "changed", else: "stable"),
                  "inputSchema" => %{
                    "type" => "object",
                    "properties" => %{"text" => %{"type" => "string"}},
                    "required" => ["text"]
                  }
                }
              ]
            }

          "resources/list" ->
            %{
              "resources" => [
                %{"uri" => "fixture://guide", "name" => "guide", "mimeType" => "text/plain"}
              ]
            }

          "resources/read" ->
            %{
              "contents" => [
                %{
                  "uri" => "fixture://guide",
                  "mimeType" => "text/plain",
                  "text" => "Synthetic resource data"
                }
              ]
            }

          "prompts/list" ->
            %{
              "prompts" => [
                %{
                  "name" => "summarize",
                  "arguments" => [%{"name" => "topic", "required" => true}]
                }
              ]
            }

          "prompts/get" ->
            %{
              "messages" => [
                %{
                  "role" => "user",
                  "content" => %{
                    "type" => "text",
                    "text" => "Synthetic prompt data: " <> rpc["params"]["arguments"]["topic"]
                  }
                }
              ]
            }

          "tools/call" ->
            %{
              "content" => [
                %{
                  "type" => "text",
                  "text" => "synthetic synthetic-bearer-token fixture-session-token"
                }
              ]
            }

          _ ->
            %{}
        end

      if rpc["method"] == "tools/call" and mode in [:disconnect, :hold] do
        if mode == :hold do
          send(test, {:http_dispatched, self()})
          {:error, :closed} = transport.recv(socket, 0, 5000)
          send(test, {:http_socket_closed, self()})
        end
      else
        response(socket, method, rpc, result, mode, transport)
      end
    after
      transport.close(socket)
    end
  end

  defp response(socket, method, rpc, result, mode, transport) do
    status =
      cond do
        mode == :unauthorized -> 401
        mode == :redirect -> 302
        mode == :huge_error -> 401
        method == "DELETE" or is_nil(rpc["id"]) -> 202
        true -> 200
      end

    envelope = %{
      "jsonrpc" => "2.0",
      "id" => if(mode == :wrong_id, do: rpc["id"] + 99, else: rpc["id"]),
      "result" => result
    }

    body =
      cond do
        status == 202 ->
          ""

        mode in [:huge_body, :huge_error] ->
          String.duplicate("x", 262_145)

        mode == :only_ping ->
          "data: " <>
            Jason.encode!(%{"jsonrpc" => "2.0", "id" => "ping", "method" => "ping"}) <> "\n\n"

        mode in [:sse, :bad_sse, :mixed_sse] ->
          "data: " <>
            Jason.encode!(envelope) <>
            if(mode == :bad_sse, do: "\n", else: "\n\n") <>
            if(mode == :mixed_sse, do: "data: invalid\n\n", else: "")

        true ->
          Jason.encode!(envelope)
      end

    type =
      if mode in [:sse, :bad_sse, :mixed_sse, :only_ping],
        do: "text/event-stream",
        else: "application/json"

    session_id =
      if mode == :changed_session and rpc["method"] != "initialize",
        do: "changed-token",
        else: "fixture-session-token"

    extra = if mode == :huge_headers, do: "x-big: #{String.duplicate("x", 17000)}\r\n", else: ""

    socket_info = if transport == :gen_tcp, do: :inet, else: :ssl
    {:ok, {_, port}} = socket_info.sockname(socket)

    extra =
      extra <>
        if(mode == :redirect, do: "location: http://127.0.0.1:#{port}/redirected\r\n", else: "")

    transport.send(
      socket,
      "HTTP/1.1 #{status} Fixture\r\ncontent-type: #{type}\r\nmcp-session-id: #{session_id}\r\n#{extra}content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n"
    )

    transport.send(socket, body)
  end

  defp read_request(socket, buffer, transport) do
    case :binary.split(buffer, "\r\n\r\n") do
      [raw, body] ->
        [first | lines] = String.split(raw, "\r\n")

        headers =
          Map.new(lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        size = String.to_integer(headers["content-length"] || "0")
        body = read_body(socket, body, size, transport)
        method = hd(String.split(first, " "))
        {method, headers, if(body == "", do: %{}, else: Jason.decode!(body))}

      [_] ->
        {:ok, bytes} = transport.recv(socket, 0, 5000)
        read_request(socket, buffer <> bytes, transport)
    end
  end

  defp read_body(_, body, size, _transport) when byte_size(body) >= size, do: body

  defp read_body(socket, body, size, transport) do
    {:ok, bytes} = transport.recv(socket, 0, 5000)
    read_body(socket, body <> bytes, size, transport)
  end

  defp stop_fixture(pid) do
    monitor = Process.monitor(pid)

    try do
      GenServer.stop(pid)
    catch
      :exit, _ -> if Process.alive?(pid), do: Process.exit(pid, :kill)
    end

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      2000 -> raise "Fixture cleanup unconfirmed"
    end
  end

  test "HTTPS accepts a trusted matching hostname and rejects a trusted wrong hostname", ctx do
    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65537}],
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]
        ]
      })

    original =
      Enum.map(:public_key.cacerts_get(), fn
        {:cert, der, _} -> der
        der when is_binary(der) -> der
      end)

    original_path = Path.join(ctx.root, "original-ca.pem")
    trusted_path = Path.join(ctx.root, "fixture-ca.pem")

    pem = fn certs ->
      :public_key.pem_encode(Enum.map(certs, &{:Certificate, &1, :not_encrypted}))
    end

    File.write!(original_path, pem.(original))
    File.write!(trusted_path, pem.(certificate[:cacerts]))
    :ok = :public_key.cacerts_load(trusted_path)

    try do
      for host <- ["localhost", "127.0.0.1"] do
        {:ok, agent} = Agent.start_link(fn -> %{requests: [], calls: 0, lists: 0} end)
        {:ok, supervisor} = Task.Supervisor.start_link()

        {:ok, listener} =
          :ssl.listen(
            0,
            [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}] ++ certificate
          )

        {:ok, {_, port}} = :ssl.sockname(listener)
        test = self()

        Task.Supervisor.start_child(supervisor, fn ->
          accept_tls(listener, supervisor, agent, test)
        end)

        try do
          path = Path.join(ctx.root, "trusted-tls.json")

          File.write!(
            path,
            Jason.encode!(%{
              "servers" => [
                %{
                  "id" => "remote",
                  "transport" => "http",
                  "url" => "https://#{host}:#{port}/mcp",
                  "tools" => ["write"],
                  "timeout_ms" => 3000
                }
              ]
            })
          )

          {:ok, [server]} = Config.load(path)

          if host == "localhost" do
            assert {:ok, [tool]} = Client.discover(server, ctx.root)
            assert {:ok, _} = Client.call(tool, %{"text" => "synthetic"}, ctx.root)
            assert Agent.get(agent, & &1.calls) == 1
          else
            assert {:error, _} = Client.discover(server, ctx.root)

            assert_receive {:tls_fixture_failure, {:error, {:tls_alert, {alert, _}}}},
                           5000

            assert alert in [:bad_certificate, :handshake_failure]

            assert Agent.get(agent, & &1.requests) == []
          end
        after
          :ssl.close(listener)
          stop_fixture(supervisor)
          stop_fixture(agent)
        end
      end
    after
      :ok = :public_key.cacerts_load(original_path)
    end
  end

  defp accept_tls(listener, supervisor, agent, test) do
    case :ssl.transport_accept(listener) do
      {:ok, socket} ->
        {:ok, worker} =
          Task.Supervisor.start_child(supervisor, fn ->
            receive do
              :serve ->
                case :ssl.handshake(socket, 5000) do
                  {:ok, secure} ->
                    serve(secure, agent, :json, test, :ssl)

                  error ->
                    send(test, {:tls_fixture_failure, error})
                    :ssl.close(socket)
                end
            end
          end)

        :ok = :ssl.controlling_process(socket, worker)
        send(worker, :serve)
        accept_tls(listener, supervisor, agent, test)

      _ ->
        :ok
    end
  end

  test "HTTPS rejects an untrusted fixture certificate without dispatch", ctx do
    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65537}],
        peer: [digest: :sha256, key: {:rsa, 2048, 65537}]
      })

    {:ok, listener} =
      :ssl.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}] ++ certificate)

    {:ok, {_, port}} = :ssl.sockname(listener)

    handshake =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listener, 5000)
        result = :ssl.handshake(socket, 5000)
        :ssl.close(socket)
        result
      end)

    path = Path.join(ctx.root, "tls.json")

    File.write!(
      path,
      Jason.encode!(%{
        "servers" => [
          %{
            "id" => "remote",
            "transport" => "http",
            "url" => "https://127.0.0.1:#{port}/mcp",
            "tools" => ["write"],
            "timeout_ms" => 3000
          }
        ]
      })
    )

    {:ok, [server]} = Config.load(path)
    assert {:error, _} = Client.discover(server, ctx.root)
    assert {:error, {:tls_alert, {:unknown_ca, _}}} = Task.await(handshake, 5000)
    :ssl.close(listener)
  end
end
