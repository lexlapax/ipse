defmodule Ipse.Provider.MintTransportTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.MintTransport

  defp listener do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {socket, "http://127.0.0.1:#{port}/test?q=1"}
  end

  defp consume(event, acc), do: {:cont, [event | acc]}

  defp header_bytes(socket, bytes \\ "") when byte_size(bytes) < 16_384 do
    if String.contains?(bytes, "\r\n\r\n") do
      bytes
    else
      {:ok, next} = :gen_tcp.recv(socket, 0, 5000)
      header_bytes(socket, bytes <> next)
    end
  end

  defp request_bytes(socket, bytes \\ "") when byte_size(bytes) < 16_384 do
    if String.contains?(bytes, "fixture"),
      do: bytes,
      else:
        (
          {:ok, next} = :gen_tcp.recv(socket, 0, 5000)
          request_bytes(socket, bytes <> next)
        )
  end

  test "connects before refusal and sends no request bytes" do
    {listener, url} = listener()
    owner = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        send(owner, :connected)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    assert {:error, :inference_request_refused} =
             MintTransport.stream(url, [], "fixture", 5000, 100, [], &consume/2, fn _send ->
               send(owner, :admitted)
               :deny
             end)

    assert_receive :connected
    assert_receive :admitted
    assert {:error, :closed} = Task.await(server, 6000)
  end

  test "returns bounded response events and refuses excess bytes" do
    for {response, limit, expectation} <- [{"hello", 5, :ok}, {"hello!", 5, :large}] do
      {listener, url} = listener()

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          {:ok, request} = :gen_tcp.recv(socket, 0, 5000)

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n#{response}"
            )

          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          request
        end)

      result =
        MintTransport.stream(url, [], "fixture", 5000, limit, [], &consume/2, fn send ->
          send.()
        end)

      assert Task.await(server, 6000) =~ "POST /test?q=1 HTTP/1.1"

      case expectation do
        :ok ->
          assert {:ok, events} = result
          assert Enum.any?(events, &match?({:status, _, 200}, &1))
          assert Enum.any?(events, &match?({:data, _, "hello"}, &1))

        :large ->
          assert {:unknown, {:error, :inference_response_too_large}} = result
      end
    end
  end

  test "repeated informational headers are bounded cumulatively" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _ = request_bytes(socket)

        message =
          "HTTP/1.1 103 Early Hints\r\nx-fixture: " <> String.duplicate("a", 1000) <> "\r\n\r\n"

        :gen_tcp.send(socket, List.duplicate(message, 70))
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    assert {:unknown, {:error, :inference_response_too_large}} =
             MintTransport.stream(url, [], "fixture", 5000, 100, [], &consume/2, fn send ->
               send.()
             end)

    Task.await(server, 6000)
  end

  test "killing the owner closes its connected socket" do
    {listener, url} = listener()
    owner = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {:ok, _} = :gen_tcp.recv(socket, 0, 5000)
        send(owner, :request_received)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    task =
      Task.async(fn ->
        MintTransport.stream(url, [], "fixture", 5000, 100, [], &consume/2, fn send -> send.() end)
      end)

    assert_receive :request_received, 5000
    assert Task.shutdown(task, :brutal_kill) == nil
    assert {:error, :closed} = Task.await(server, 6000)
  end

  test "receive deadline closes the socket without retry" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {:ok, _} = :gen_tcp.recv(socket, 0, 5000)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    assert {:unknown, {:error, :inference_timeout}} =
             MintTransport.stream(url, [], "fixture", 200, 100, [], &consume/2, fn send ->
               send.()
             end)

    assert {:error, :closed} = Task.await(server, 6000)
  end

  test "the owner can cancel a blocked admission callback and close the socket" do
    {listener, url} = listener()
    owner = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    task =
      Task.async(fn ->
        MintTransport.stream(url, [], "fixture", 5000, 100, [], &consume/2, fn _send ->
          send(owner, :blocked_admission)
          receive do: (:never -> :ok)
        end)
      end)

    assert_receive :blocked_admission, 5000
    assert Task.shutdown(task, :brutal_kill) == nil
    assert {:error, :closed} = Task.await(server, 6000)
  end

  test "an external owner can cancel a stalled socket send" do
    {listener, url} = listener()
    owner = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        send(owner, :send_peer_connected)
        receive do: (:finish -> :ok)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    task =
      Task.async(fn ->
        MintTransport.stream(
          url,
          [],
          :binary.copy("x", 8_388_608),
          200,
          100,
          [],
          &consume/2,
          fn send -> send.() end
        )
      end)

    assert_receive :send_peer_connected
    result = Task.yield(task, 1500) || Task.shutdown(task, :brutal_kill)
    assert is_nil(result) or match?({:ok, {:unknown, _}}, result)
    send(server.pid, :finish)
    assert :ok = Task.await(server, 6000)
  end

  test "a successful callback must actually invoke its continuation" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    assert {:error, :inference_request_refused} =
             MintTransport.stream(url, [], "fixture", 5000, 100, [], &consume/2, fn _send ->
               :ok
             end)

    assert {:error, :closed} = Task.await(server, 6000)
  end

  test "a repeated continuation cannot send twice and makes the outcome uncertain" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        request = request_bytes(socket)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        {request, result}
      end)

    assert {:unknown, :inference_send_uncertain} =
             MintTransport.stream(url, [], "fixture", 5000, 100, [], &consume/2, fn send ->
               assert :ok = send.()
               assert {:error, :inference_send_uncertain} = send.()
               :ok
             end)

    assert {request, {:error, :closed}} = Task.await(server, 6000)
    assert request =~ "POST /test?q=1 HTTP/1.1"
  end

  test "the owner may hold its policy lock through the actual request write" do
    {listener, url} = listener()
    lock = :atomics.new(1, [])
    owner = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {:ok, _} = :gen_tcp.recv(socket, 0, 5000)
        send(owner, {:observed_lock, :atomics.get(lock, 1)})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok"
          )

        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    assert {:ok, _} =
             MintTransport.stream(url, [], "fixture", 5000, 100, [], &consume/2, fn send ->
               :atomics.put(lock, 1, 1)

               assert {:error, :inference_request_refused} =
                        Task.async(fn -> send.() end) |> Task.await()

               assert :ok = send.()
               assert_receive {:observed_lock, 1}, 5000
               :atomics.put(lock, 1, 0)
               :ok
             end)

    assert :ok = Task.await(server, 6000)
  end

  test "remote plaintext HTTP is refused before connect and admission" do
    assert {:error, :inference_connection_failed} =
             MintTransport.stream(
               "http://example.invalid/test",
               [],
               "fixture",
               5000,
               100,
               [],
               &consume/2,
               fn _ ->
                 flunk("remote plaintext reached admission")
               end
             )
  end

  test "unbounded and malformed outbound headers refuse before connect" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        result = :gen_tcp.accept(listener, 500)
        :gen_tcp.close(listener)
        result
      end)

    for headers <- [
          [{"authorization", String.duplicate("a", 16_385)}],
          List.duplicate({"x-test", "a"}, 129),
          [{"bad header", "value"}],
          [{"x-test", "fixture\r\ninjected: true"}],
          [{"Host", "other.invalid"}],
          [{"Content-Length", "0"}],
          [{"Transfer-Encoding", "chunked"}],
          [{"Proxy-Authorization", "fixture"}],
          [{"Connection", "upgrade"}],
          [{"Upgrade", "websocket"}],
          [{"", "value"}]
        ] do
      assert {:error, :inference_connection_failed} =
               MintTransport.stream(url, headers, "fixture", 5000, 100, [], &consume/2, fn _ ->
                 flunk("bad headers reached admission")
               end)
    end

    assert {:error, :timeout} = Task.await(server, 1000)
  end

  test "HTTPS proxy connection failure does not invoke admission or send the inference body" do
    {listener, proxy} = listener()

    prior =
      for key <- ~w(HTTPS_PROXY NO_PROXY https_proxy no_proxy),
          into: %{},
          do: {key, System.get_env(key)}

    proxy =
      String.replace(proxy, "/test?q=1", "")
      |> String.replace("http://", "http://fixture:secret@")

    try do
      System.put_env("HTTPS_PROXY", proxy)
      System.put_env("NO_PROXY", "")

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          {:ok, request} = :gen_tcp.recv(socket, 0, 5000)

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 403 Forbidden\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
            )

          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          request
        end)

      assert {:error, :inference_connection_failed} =
               MintTransport.stream(
                 "https://example.invalid/test",
                 [],
                 "stale fixture",
                 5000,
                 100,
                 [],
                 &consume/2,
                 fn _send -> flunk("proxy refusal reached admission") end
               )

      request = Task.await(server, 6000) |> String.downcase()
      assert request =~ "connect example.invalid:443 http/1.1"

      assert request =~
               "proxy-authorization: basic " <> String.downcase(Base.encode64("fixture:secret"))

      refute request =~ "stale fixture"
    after
      for {key, value} <- prior do
        if is_nil(value), do: System.delete_env(key), else: System.put_env(key, value)
      end
    end
  end

  test "a stalled HTTPS CONNECT observes the configured tunnel bound" do
    {listener, proxy} = listener()

    prior =
      for key <- ~w(HTTPS_PROXY NO_PROXY https_proxy no_proxy),
          into: %{},
          do: {key, System.get_env(key)}

    proxy = String.replace(proxy, "/test?q=1", "")

    try do
      System.put_env("HTTPS_PROXY", proxy)
      System.put_env("NO_PROXY", "")

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          {:ok, request} = :gen_tcp.recv(socket, 0, 5000)
          result = :gen_tcp.recv(socket, 0, 5000)
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          {request, result}
        end)

      started = System.monotonic_time(:millisecond)

      assert {:error, :inference_connection_failed} =
               MintTransport.stream(
                 "https://example.invalid/test",
                 [],
                 "fixture",
                 200,
                 100,
                 [],
                 &consume/2,
                 fn _send -> flunk("stalled tunnel reached admission") end
               )

      assert System.monotonic_time(:millisecond) - started < 3000
      assert {request, {:error, :closed}} = Task.await(server, 6000)
      assert request =~ "CONNECT example.invalid:443"
    after
      for {key, value} <- prior do
        if is_nil(value), do: System.delete_env(key), else: System.put_env(key, value)
      end
    end
  end

  test "HTTPS proxy authorization is absent from the tunneled origin request" do
    root = Path.join(System.tmp_dir!(), "ipse-mint-proxy-tls-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65537}],
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"example.invalid"}]}]
        ]
      })

    original =
      Enum.map(:public_key.cacerts_get(), fn
        {:cert, der, _} -> der
        der when is_binary(der) -> der
      end)

    pem = fn certs ->
      :public_key.pem_encode(Enum.map(certs, &{:Certificate, &1, :not_encrypted}))
    end

    saved = Path.join(root, "original.pem")
    trusted = Path.join(root, "fixture.pem")
    File.write!(saved, pem.(original))
    File.write!(trusted, pem.(certificate[:cacerts]))
    {listener, proxy} = listener()

    prior =
      for key <- ~w(HTTPS_PROXY NO_PROXY https_proxy no_proxy),
          into: %{},
          do: {key, System.get_env(key)}

    proxy =
      String.replace(proxy, "/test?q=1", "")
      |> String.replace("http://", "http://fixture:secret@")

    try do
      :ok = :public_key.cacerts_load(trusted)
      System.put_env("HTTPS_PROXY", proxy)
      System.put_env("NO_PROXY", "")

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          connect = header_bytes(socket)
          :ok = :gen_tcp.send(socket, "HTTP/1.1 200 Connection Established\r\n\r\n")
          {:ok, tls} = :ssl.handshake(socket, [:binary, active: false] ++ certificate, 5000)
          {:ok, origin} = :ssl.recv(tls, 0, 5000)

          :ok =
            :ssl.send(tls, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\nok")

          :ssl.close(tls)
          :gen_tcp.close(listener)
          {String.downcase(connect), String.downcase(origin)}
        end)

      assert {:ok, _} =
               MintTransport.stream(
                 "https://example.invalid/test",
                 [],
                 "fixture",
                 5000,
                 100,
                 [],
                 &consume/2,
                 fn send -> send.() end
               )

      assert {connect, origin} = Task.await(server, 6000)

      assert connect =~
               "proxy-authorization: basic " <> String.downcase(Base.encode64("fixture:secret"))

      assert origin =~ "post /test http/1.1"
      refute origin =~ "proxy-authorization"
    after
      :ok = :public_key.cacerts_load(saved)

      for {key, value} <- prior do
        if is_nil(value), do: System.delete_env(key), else: System.put_env(key, value)
      end

      File.rm_rf!(root)
    end
  end

  test "external owner cancellation closes a stalled HTTPS proxy connection" do
    {listener, proxy} = listener()

    prior =
      for key <- ~w(HTTPS_PROXY NO_PROXY https_proxy no_proxy),
          into: %{},
          do: {key, System.get_env(key)}

    proxy = String.replace(proxy, "/test?q=1", "")
    parent = self()

    try do
      System.put_env("HTTPS_PROXY", proxy)
      System.put_env("NO_PROXY", "")

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          _ = header_bytes(socket)
          send(parent, :proxy_waiting)
          result = :gen_tcp.recv(socket, 0, 5000)
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
          result
        end)

      request =
        Task.async(fn ->
          MintTransport.stream(
            "https://example.invalid/test",
            [],
            "fixture",
            5000,
            100,
            [],
            &consume/2,
            fn _ -> flunk("stalled tunnel reached admission") end
          )
        end)

      assert_receive :proxy_waiting, 5000
      assert Task.shutdown(request, :brutal_kill) == nil
      assert {:error, :closed} = Task.await(server, 6000)
    after
      for {key, value} <- prior do
        if is_nil(value), do: System.delete_env(key), else: System.put_env(key, value)
      end
    end
  end

  test "a policy revoked during TLS connection is checked before request bytes" do
    root = Path.join(System.tmp_dir!(), "ipse-mint-tls-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)

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

    pem = fn certs ->
      :public_key.pem_encode(Enum.map(certs, &{:Certificate, &1, :not_encrypted}))
    end

    saved = Path.join(root, "original.pem")
    trusted = Path.join(root, "fixture.pem")
    File.write!(saved, pem.(original))
    File.write!(trusted, pem.(certificate[:cacerts]))

    try do
      :ok = :public_key.cacerts_load(trusted)

      {:ok, listener} =
        :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)

      {:ok, {_, port}} = :ssl.sockname(listener)
      policy = :atomics.new(1, [])
      :atomics.put(policy, 1, 1)
      parent = self()

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5000)
          send(parent, :before_handshake)
          receive do: (:continue_handshake -> :ok)
          {:ok, tls} = :ssl.handshake(socket, 5000)
          result = :ssl.recv(tls, 0, 5000)
          :ssl.close(tls)
          :ssl.close(listener)
          result
        end)

      request =
        Task.async(fn ->
          MintTransport.stream(
            "https://localhost:#{port}/fixture",
            [],
            "stale",
            5000,
            100,
            [],
            &consume/2,
            fn send ->
              send(parent, :checked_policy)
              if :atomics.get(policy, 1) == 1, do: send.(), else: :deny
            end
          )
        end)

      assert_receive :before_handshake, 5000
      refute_receive :checked_policy, 50
      :atomics.put(policy, 1, 0)
      send(server.pid, :continue_handshake)
      assert {:error, :inference_request_refused} = Task.await(request, 6000)
      assert_receive :checked_policy
      assert {:error, :closed} = Task.await(server, 6000)

      {:ok, listener} =
        :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)

      {:ok, {_, port}} = :ssl.sockname(listener)

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5000)
          result = :ssl.handshake(socket, 5000)
          :ssl.close(socket)
          :ssl.close(listener)
          result
        end)

      assert {:error, :inference_connection_failed} =
               MintTransport.stream(
                 "https://127.0.0.1:#{port}/fixture",
                 [],
                 "fixture",
                 5000,
                 100,
                 [],
                 &consume/2,
                 fn _send ->
                   flunk("hostname mismatch reached admission")
                 end
               )

      assert {:error, _} = Task.await(server, 6000)

      {:ok, listener} =
        :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)

      {:ok, {_, port}} = :ssl.sockname(listener)

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5000)
          send(parent, :cancel_tls_ready)
          receive do: (:continue_handshake -> :ok)
          result = :ssl.handshake(socket, 5000)
          :ssl.close(socket)
          :ssl.close(listener)
          result
        end)

      request =
        Task.async(fn ->
          MintTransport.stream(
            "https://localhost:#{port}/fixture",
            [],
            "fixture",
            5000,
            100,
            [],
            &consume/2,
            fn send -> send.() end
          )
        end)

      assert_receive :cancel_tls_ready, 5000
      assert Task.shutdown(request, :brutal_kill) == nil
      send(server.pid, :continue_handshake)
      assert {:error, _} = Task.await(server, 6000)
    after
      :ok = :public_key.cacerts_load(saved)
      File.rm_rf!(root)
    end
  end
end
