defmodule Ipse.Provider.MintEmbeddingTest do
  use ExUnit.Case, async: false

  alias Ipse.Provider.MintEmbedding
  alias Ipse.Session.Resources

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

  defp listen do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)

    {socket,
     %{
       provider: :ollama,
       model: "fixture",
       dimensions: 2,
       dimension_mode: "native",
       timeout_ms: 4000,
       base_url: "http://127.0.0.1:#{port}"
     }}
  end

  defp request(socket, bytes \\ "") do
    case :binary.split(bytes, "\r\n\r\n") do
      [head, body] ->
        [_, length] = Regex.run(~r/content-length: (\d+)/i, head)
        size = String.to_integer(length)

        if byte_size(body) >= size,
          do: {head, binary_part(body, 0, size)},
          else: request_more(socket, bytes)

      _ ->
        request_more(socket, bytes)
    end
  end

  defp request_more(socket, bytes) do
    {:ok, next} = :gen_tcp.recv(socket, 0, 5000)
    request(socket, bytes <> next)
  end

  defp cleanup(scope, worker) do
    if Process.alive?(worker), do: send(worker, :finish)
    if Process.alive?(scope), do: Resources.close(scope)
  end

  test "derives an Ollama embedding request and publishes only after full native completion" do
    {listener, config} = listen()

    config =
      Map.put(config, :headers, [{"authorization", "Bearer injected"}, {"x-extra", "injected"}])

    request = %{
      "op" => "embedding.create",
      "version" => 1,
      "profile" => "embed",
      "inputs" => ["alpha"],
      "timeout_ms" => 4000
    }

    {:ok, expected} = Ipse.Session.InferenceWire.derive("embedding.create", config, request, [])

    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {headers, body} = request(socket)
        send(parent, {:wire, headers, body})
        data = ~s({"model":"fixture","embeddings":[[1.0,2.0]]})

        :ok =
          :gen_tcp.send(
            socket,
            "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(data)}\r\n\r\n" <>
              binary_part(data, 0, 10)
          )

        send(parent, :partial_sent)
        receive do: (:continue -> :ok)
        :ok = :gen_tcp.send(socket, binary_part(data, 10, byte_size(data) - 10))
        closed = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        closed
      end)

    {scope, worker} =
      start_owned(fn ->
        MintEmbedding.embed(config, ["alpha"], fn facts, send ->
          assert Ipse.Session.InferenceWire.matches?(expected, facts)
          Kernel.send(parent, {:facts, facts})
          send.()
        end)
      end)

    try do
      assert_receive {:wire, headers, body}, 5000
      assert headers =~ "POST /api/embed HTTP/1.1"

      assert {:ok, %{"model" => "fixture", "input" => ["alpha"], "truncate" => false}} =
               Jason.decode(body)

      assert_receive {:facts, facts}, 5000

      assert facts == %{
               "kind" => "embedding",
               "provider" => "ollama",
               "model" => "fixture",
               "target_sha256" => Ipse.JSON.sha256(config.base_url <> "/api/embed"),
               "body_sha256" => Ipse.JSON.sha256(body)
             }

      refute String.downcase(headers) =~ "authorization:"
      refute String.downcase(headers) =~ "x-extra:"
      assert_receive :partial_sent, 5000
      refute_receive {:result, _}, 150
      send(server.pid, :continue)
      assert_receive {:result, {:settled, {:ok, result, _}}}, 5000
      assert result["kind"] == "embedding"

      assert Ipse.Provider.Embedding.valid_data?(
               Map.take(result, ~w(encoding dimensions vectors)),
               ["alpha"],
               2
             )

      assert {:error, :closed} = Task.await(server, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "invalid endpoint, provider, inputs and dimensions refuse before any connection" do
    {listener, config} = listen()

    for {runtime, inputs} <- [
          {%{config | provider: :openai}, ["alpha"]},
          {%{config | base_url: "http://example.com"}, ["alpha"]},
          {%{config | dimensions: 0}, ["alpha"]},
          {config, []}
        ] do
      assert {:unstarted, :invalid_inference_request} =
               MintEmbedding.embed(runtime, inputs, fn _, _ -> flunk("admission") end)
    end

    assert {:error, :timeout} = :gen_tcp.accept(listener, 200)
    :gen_tcp.close(listener)
  end

  test "malformed native data after sending remains unknown and is not published" do
    {listener, config} = listen()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        _ = request(socket)
        :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\n{}")
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    {scope, worker} =
      start_owned(fn -> MintEmbedding.embed(config, ["alpha"], fn _, send -> send.() end) end)

    try do
      assert_receive {:result, {:unknown, _}}, 6000
      Task.await(server, 6000)
    after
      cleanup(scope, worker)
    end
  end

  test "admission refusal sends no request body and returns only after socket closure" do
    {listener, config} = listen()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        result = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        result
      end)

    {scope, worker} =
      start_owned(fn -> MintEmbedding.embed(config, ["alpha"], fn _, _ -> :deny end) end)

    try do
      assert_receive {:result, {:unstarted, :inference_request_refused}}, 6000
      assert {:error, :closed} = Task.await(server, 6000)
    after
      cleanup(scope, worker)
    end
  end
end
