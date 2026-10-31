defmodule Ipse.Provider.MintSocketTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.MintTransport

  # These controls exercise the owned socket continuation only. Their callbacks
  # are fixtures, not Session authority or signed managed-source proofs.
  test "a refused or elapsed admission makes no TCP connection" do
    for admission <- [
          fn _ -> {:error, :denied} end,
          fn send -> send.(System.system_time(:millisecond)) end
        ] do
      {listener, url} = listener()
      assert {:error, :inference_request_refused} = request(url, admission)
      assert {:error, :timeout} = :gen_tcp.accept(listener, 200)
      :gen_tcp.close(listener)
    end
  end

  test "the owner sends the exact body once and closes the socket after its response" do
    {listener, url} = listener()
    parent = self()
    server = Task.async(fn -> serve(listener, parent) end)

    assert {:ok, ["{}"]} =
             request(url, fn send -> send.(System.system_time(:millisecond) + 3000) end)

    assert_receive {:socket_body, "{\"text\":\"synthetic\"}"}, 1000
    assert {:error, :closed} = Task.await(server, 5000)
  end

  test "a duplicate continuation never sends a second request and makes the outcome unknown" do
    {listener, url} = listener()
    parent = self()
    server = Task.async(fn -> serve(listener, parent) end)

    assert {:unknown, :inference_send_uncertain} =
             request(url, fn send ->
               deadline = System.system_time(:millisecond) + 3000
               assert :ok = send.(deadline)
               assert {:error, :inference_request_refused} = send.(deadline)
               :ok
             end)

    assert_receive {:socket_body, "{\"text\":\"synthetic\"}"}, 1000
    assert {:error, :closed} = Task.await(server, 5000)
  end

  test "a foreign process cannot spend the owner continuation" do
    {listener, url} = listener()

    assert {:error, :inference_request_refused} =
             request(url, fn send ->
               deadline = System.system_time(:millisecond) + 3000
               task = Task.async(fn -> send.(deadline) end)
               assert {:error, :inference_request_refused} = Task.await(task)
               assert {:error, :inference_request_refused} = send.(deadline)
               :ok
             end)

    assert {:error, :timeout} = :gen_tcp.accept(listener, 200)
    :gen_tcp.close(listener)
  end

  test "TLS rejects an untrusted peer and confirms closure for a trusted fixture" do
    root = Path.join(System.tmp_dir!(), "ipse-mcp-tls-" <> Ipse.Usage.id())
    File.mkdir!(root)

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

    encode = fn certs ->
      :public_key.pem_encode(Enum.map(certs, &{:Certificate, &1, :not_encrypted}))
    end

    original_path = Path.join(root, "original.pem")
    fixture_path = Path.join(root, "fixture.pem")
    File.write!(original_path, encode.(original))
    File.write!(fixture_path, encode.(certificate[:cacerts]))

    try do
      {listener, url} = tls_listener(certificate)

      failed =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5000)
          result = :ssl.handshake(socket, 5000)
          :ssl.close(listener)
          result
        end)

      assert {:unknown, :inference_connection_unconfirmed} =
               request(url, fn send -> send.(System.system_time(:millisecond) + 3000) end)

      assert {:error, _} = Task.await(failed, 5000)
      assert :ok = :public_key.cacerts_load(fixture_path)

      {listener, url} = tls_listener(certificate)
      parent = self()

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5000)
          {:ok, tls} = :ssl.handshake(socket, 5000)
          request = receive_tls_request(tls, "")
          send(parent, {:tls_request, request})

          :ok =
            :ssl.send(
              tls,
              "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: keep-alive\r\n\r\n{}"
            )

          closed = :ssl.recv(tls, 0, 5000)
          :ssl.close(tls)
          :ssl.close(listener)
          closed
        end)

      assert {:ok, ["{}"]} =
               request(url, fn send -> send.(System.system_time(:millisecond) + 3000) end)

      assert_receive {:tls_request, received}, 1000
      assert received =~ ~s({"text":"synthetic"})
      assert {:error, :closed} = Task.await(server, 5000)
    after
      :ok = :public_key.cacerts_load(original_path)
      File.rm_rf!(root)
    end
  end

  defp request(url, admission) do
    MintTransport.stream_socket(
      url,
      [{"content-type", "application/json"}],
      ~s({"text":"synthetic"}),
      5000,
      4096,
      [],
      fn
        {:data, _, bytes}, chunks -> {:cont, [bytes | chunks]}
        _, chunks -> {:cont, chunks}
      end,
      admission
    )
  end

  defp listener do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    {listener, "http://127.0.0.1:#{port}/mcp"}
  end

  defp tls_listener(certificate) do
    {:ok, listener} = :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)
    {:ok, {_, port}} = :ssl.sockname(listener)
    {listener, "https://localhost:#{port}/mcp"}
  end

  defp receive_tls_request(socket, bytes) do
    if String.contains?(bytes, ~s({"text":"synthetic"})) do
      bytes
    else
      {:ok, chunk} = :ssl.recv(socket, 0, 5000)
      receive_tls_request(socket, bytes <> chunk)
    end
  end

  defp serve(listener, parent) do
    {:ok, socket} = :gen_tcp.accept(listener, 5000)
    bytes = receive_request(socket, "")
    [_, body] = String.split(bytes, "\r\n\r\n", parts: 2)
    send(parent, {:socket_body, body})

    _ =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: keep-alive\r\n\r\n{}"
      )

    closed = :gen_tcp.recv(socket, 0, 5000)
    :gen_tcp.close(socket)
    :gen_tcp.close(listener)
    closed
  end

  defp receive_request(socket, bytes) do
    case String.split(bytes, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        [_, length] = Regex.run(~r/(?:^|\r\n)content-length:\s*(\d+)/i, headers)

        if byte_size(body) >= String.to_integer(length),
          do: bytes,
          else: receive_request(socket, bytes <> receive_bytes(socket))

      _ ->
        receive_request(socket, bytes <> receive_bytes(socket))
    end
  end

  defp receive_bytes(socket) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
    bytes
  end
end
