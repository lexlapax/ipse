defmodule Ipse.Provider.MintOwnedTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.MintOwned
  alias Ipse.Session.Resources

  defp listener do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    {socket, "http://127.0.0.1:#{port}/fixture"}
  end

  defp no_connection(listener) do
    Task.async(fn ->
      result = :gen_tcp.accept(listener, 1500)
      :gen_tcp.close(listener)
      result
    end)
  end

  defp start_owned(fun) do
    {:ok, scope} = Resources.start(self())
    parent = self()

    worker =
      spawn(fn ->
        receive do
          :start ->
            Resources.bind(scope)
            send(parent, {:result, fun.()})
            receive do: (:finish -> :ok)
        end
      end)

    :ok = Resources.attach(scope, worker)
    send(worker, :start)
    {scope, worker}
  end

  defp consume({:data, _, data}, acc), do: {:cont, acc <> data}
  defp consume(_, acc), do: {:cont, acc}

  defp recv_request(socket, bytes \\ "") when byte_size(bytes) < 8192 do
    if String.contains?(bytes, ~s("input":"fixture")) do
      bytes
    else
      {:ok, next} = :gen_tcp.recv(socket, 0, 5000)
      recv_request(socket, bytes <> next)
    end
  end

  defp run(url, admit, finish) do
    MintOwned.run(
      %{provider: :ollama, model: "fixture"},
      :text,
      url,
      [{"content-type", "application/json"}],
      ~s({"input":"fixture"}),
      4000,
      1024,
      "",
      &consume/2,
      admit,
      finish
    )
  end

  defp finish(body) do
    case Jason.decode(body) do
      {:ok, %{"done" => true}} -> {:ok, %{"role" => "assistant", "content" => "fixture"}, %{}}
      _ -> {:error, :bad_native_response}
    end
  end

  defp cleanup(scope, worker) do
    if Process.alive?(worker), do: send(worker, :finish)
    if Process.alive?(scope), do: Resources.close(scope)
  end

  test "actual TCP completion, native parse and port termination settle one owned request" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        request = recv_request(socket)
        body = ~s({"done":true})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\nconnection: keep-alive\r\n\r\n#{body}"
          )

        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        {request, result}
      end)

    {scope, worker} = start_owned(fn -> run(url, fn send -> send.() end, &finish/1) end)

    try do
      assert_receive {:result, {:settled, {:ok, %{"content" => "fixture"}, %{}}}}, 8000
      assert {request, {:error, :closed}} = Task.await(server, 6000)
      assert request =~ "POST /fixture HTTP/1.1"
    after
      cleanup(scope, worker)
    end
  end

  test "an exact outer witness accepts the completed owned child once" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _ = recv_request(socket)
        body = ~s({"done":true})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
          )

        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    runtime = %{provider: :ollama, model: "fixture"}

    {scope, worker} =
      start_owned(fn ->
        Ipse.Provider.CompletionWitness.capture(runtime, :text, url, fn ->
          run(url, fn send -> send.() end, &finish/1)
        end)
      end)

    try do
      assert_receive {:result, {{:settled, {:ok, _, _}}, true}}, 8000
      Task.await(server, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "a completed child at a different target cannot complete the outer witness" do
    {listener, url} = listener()
    server = no_connection(listener)

    runtime = %{provider: :ollama, model: "fixture"}

    {scope, worker} =
      start_owned(fn ->
        Ipse.Provider.CompletionWitness.capture(runtime, :text, url <> "/other", fn ->
          run(url, fn send -> send.() end, &finish/1)
        end)
      end)

    try do
      assert_receive {:result, {{:unknown, :inference_completion_unconfirmed}, false}}, 8000
      assert {:error, :timeout} = Task.await(server, 3000)
    after
      cleanup(scope, worker)
    end
  end

  test "a duplicate child completion invalidates the outer witness" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _ = recv_request(socket)
        body = ~s({"done":true})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
          )

        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    runtime = %{provider: :ollama, model: "fixture"}

    {scope, worker} =
      start_owned(fn ->
        Ipse.Provider.CompletionWitness.capture(runtime, :text, url, fn ->
          result = run(url, fn send -> send.() end, &finish/1)

          assert {:error, :inference_witness_refused} =
                   Ipse.Provider.CompletionWitness.reserve_owned_child(runtime, :text, url)

          result
        end)
      end)

    try do
      assert_receive {:result, {{:settled, {:ok, _, _}}, false}}, 8000
      Task.await(server, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "a capability is caller-owned, single-use and rejects substitution" do
    witness = Ipse.Provider.CompletionWitness
    runtime = %{provider: :ollama, model: "fixture"}
    url = "http://127.0.0.1:11434/api/chat"

    assert {{:error, :inference_witness_refused}, false} =
             witness.capture(runtime, :text, url, fn ->
               {:ok, capability} = witness.reserve_owned_child(runtime, :text, url)

               foreign =
                 Task.async(fn ->
                   witness.complete_owned_child(runtime, :text, url, capability)
                 end)

               assert {:error, :inference_witness_refused} = Task.await(foreign)
               witness.complete_owned_child(runtime, :text, url, make_ref())
             end)

    assert {{:error, :inference_witness_refused}, false} =
             witness.capture(runtime, :text, url, fn ->
               {:ok, capability} = witness.reserve_owned_child(runtime, :text, url)
               assert :ok == witness.complete_owned_child(runtime, :text, url, capability)
               witness.complete_owned_child(runtime, :text, url, capability)
             end)
  end

  test "an outstanding child capability cannot be completed by another HTTP observation" do
    witness = Ipse.Provider.CompletionWitness
    runtime = %{provider: :ollama, model: "test"}
    url = "http://127.0.0.1:1234/api/generate"

    assert {_, false} =
             witness.capture(runtime, :text, url, fn ->
               {:ok, _capability} = witness.reserve_owned_child(runtime, :text, url)
               ref = make_ref()
               witness.http_started(url)
               witness.borrowed(ref)
               witness.http_complete(url, 200)
               witness.cleaned(ref, :ok)
               witness.native_complete(runtime, :text)
             end)
  end

  test "a child completion cannot satisfy a different outer model, provider or kind" do
    for {runtime, kind} <- [
          {%{provider: :ollama, model: "different"}, :text},
          {%{provider: :openai, model: "fixture"}, :text},
          {%{provider: :ollama, model: "fixture"}, :decision}
        ] do
      {listener, url} = listener()
      server = no_connection(listener)

      {scope, worker} =
        start_owned(fn ->
          Ipse.Provider.CompletionWitness.capture(runtime, kind, url, fn ->
            run(url, fn send -> send.() end, &finish/1)
          end)
        end)

      try do
        assert_receive {:result, {{:unknown, :inference_completion_unconfirmed}, false}}, 8000
        assert {:error, :timeout} = Task.await(server, 3000)
      after
        cleanup(scope, worker)
      end
    end
  end

  test "policy refusal produces known-unstarted only after the actual TCP port closes" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    {scope, worker} = start_owned(fn -> run(url, fn _send -> :deny end, &finish/1) end)

    try do
      assert_receive {:result, {:unstarted, :inference_request_refused}}, 8000
      assert {:error, :closed} = Task.await(server, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "malformed native completion and post-send disconnect remain unknown" do
    for response <- ["{}", :disconnect] do
      {listener, url} = listener()

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

          if is_binary(response),
            do: :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\n{}")

          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
        end)

      {scope, worker} = start_owned(fn -> run(url, fn send -> send.() end, &finish/1) end)

      try do
        assert_receive {:result, {:unknown, _}}, 8000
        Task.await(server, 6000)
      after
        cleanup(scope, worker)
      end
    end
  end

  test "a native-looking body from a non-success HTTP response cannot settle" do
    {listener, url} = listener()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _ = recv_request(socket)
        body = ~s({"done":true})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 500 Fixture\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
          )

        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    {scope, worker} = start_owned(fn -> run(url, fn send -> send.() end, &finish/1) end)

    try do
      assert_receive {:result, {:unknown, :inference_completion_unconfirmed}}, 8000
      Task.await(server, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "owner loss after send closes the local socket and cannot publish a result" do
    {listener, url} = listener()
    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _ = recv_request(socket)
        send(parent, :wire_received)
        result = :gen_tcp.recv(socket, 0, 8000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    {scope, worker} = start_owned(fn -> run(url, fn send -> send.() end, &finish/1) end)

    try do
      assert_receive :wire_received, 5000
      ref = Process.monitor(worker)
      Process.exit(worker, :kill)
      assert_receive {:DOWN, ^ref, :process, ^worker, :killed}, 5000
      assert {:error, :closed} = Task.await(server, 9000)
      refute_receive {:result, _}, 100
    after
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "TLS without a supported socket-termination witness sends no inference body" do
    root = Path.join(System.tmp_dir!(), "ipse-mint-owned-tls-#{Ipse.Usage.id()}")
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

      server =
        Task.async(fn ->
          {:ok, socket} = :ssl.transport_accept(listener, 5000)
          {:ok, tls} = :ssl.handshake(socket, 5000)
          result = :ssl.recv(tls, 0, 6000)
          :ssl.close(tls)
          :ssl.close(listener)
          result
        end)

      {scope, worker} =
        start_owned(fn ->
          run(
            "https://localhost:#{port}/fixture",
            fn _send -> flunk("unsupported TLS reached admission") end,
            &finish/1
          )
        end)

      try do
        assert_receive {:result, {:unknown, _}}, 8000
        assert {:error, :closed} = Task.await(server, 8000)
      after
        cleanup(scope, worker)
      end
    after
      :ok = :public_key.cacerts_load(saved)
      File.rm_rf!(root)
    end
  end
end
