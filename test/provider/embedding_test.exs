defmodule Ipse.Provider.EmbeddingTest do
  use ExUnit.Case, async: false
  alias Ipse.Provider.Embedding

  test "actual wire routes match safe destination facts and do not disclose URL paths" do
    for {provider, target, origin} <- [
          {:openai, "https://api.openai.com/v1/embeddings", "https://api.openai.com"},
          {:ollama, "http://127.0.0.1:11434/api/embed", "http://127.0.0.1:11434"}
        ] do
      assert Embedding.endpoint(%{provider: provider}) == target
      assert {:ok, %{"origin" => ^origin} = facts} = Embedding.destination(%{provider: provider})
      assert facts["target_sha256"] == sha256(target)
      assert Ipse.Provider.valid_destination?(facts)
    end

    config = %{runtime(:openai, 768) | base_url: "https://proxy.example.invalid:8443/tenant"}
    assert {:ok, facts} = Embedding.destination(config)
    assert facts["origin"] == "https://proxy.example.invalid:8443"

    assert facts["target_sha256"] ==
             sha256("https://proxy.example.invalid:8443/tenant/embeddings")

    refute Jason.encode!(facts) =~ "tenant"

    for provider <- [:chatgpt, :anthropic, :demo, nil],
        do: assert({:error, _} = Embedding.destination(%{provider: provider}))

    for base <- [
          "http://remote.example.invalid",
          "https://name:secret@example.invalid",
          "https://example.invalid?secret=key",
          "https://example.invalid#fragment",
          "https://example.invalid/ bad"
        ],
        do: assert({:error, _} = Embedding.destination(%{provider: :openai, base_url: base}))
  end

  test "official nonstreaming bodies never inherit text limits or silently truncate inputs" do
    inputs = ["one", "é🙂"]

    for provider <- [:openai, :ollama], mode <- ["native", "request"] do
      config =
        runtime(provider, 4096)
        |> Map.merge(%{
          dimension_mode: mode,
          max_output_tokens: 16,
          reasoning_effort: "high",
          tools: ["ignored"],
          summary_schema: %{}
        })

      assert {:ok, body} = Embedding.request_body(config, inputs)

      expected =
        if provider == :openai,
          do: %{"model" => "fixture", "input" => inputs, "encoding_format" => "float"},
          else: %{"model" => "fixture", "input" => inputs, "truncate" => false}

      assert body ==
               if(mode == "request", do: Map.put(expected, "dimensions", 4096), else: expected)
    end

    for inputs <- [
          [],
          List.duplicate("x", 9),
          [""],
          [<<255>>],
          [String.duplicate("a", 4097)],
          List.duplicate(String.duplicate("a", 4096), 4)
        ],
        do: assert({:error, _} = Embedding.request_body(runtime(:ollama, 768), inputs))
  end

  test "OpenAI indices establish input order and ordinary 4096-dimensional vectors stay private" do
    inputs = ["first chunk", "second chunk"]

    rows = [
      %{"index" => 1, "embedding" => coordinates(4096, -2.5)},
      %{"index" => 0, "embedding" => coordinates(4096, 1.25)}
    ]

    body =
      Jason.encode!(%{
        "model" => "resolved-model",
        "data" => rows,
        "usage" => %{"prompt_tokens" => 7, "total_tokens" => 7}
      })

    assert {:ok, result, %{"prompt_tokens" => 7, "total_tokens" => 7}} =
             Embedding.parse(:openai, body, runtime(:openai, 4096), inputs)

    assert result["reported_model"] == "resolved-model"
    assert result["provider_response_sha256"] == sha256(body)
    assert Embedding.valid_result?(result, execution(:openai, 4096), inputs)

    assert Enum.map(result["vectors"], & &1["input_sha256"]) ==
             Enum.map(inputs, &Ipse.JSON.digest([&1]))

    [first, second] = Enum.map(result["vectors"], &Base.decode64!(&1["values"]))
    assert <<1.25::float-little-size(32), _::binary>> = first
    assert <<-2.5::float-little-size(32), _::binary>> = second
    assert byte_size(first) == 4096 * 4
    assert {:error, _} = Ipse.Extension.validate(result)
    assert {:error, _} = Ipse.Extension.validate(%{"vector" => coordinates(768, 1.0)})
  end

  test "Ollama supports eight 4096-wide vectors without copying raw inputs into typed data" do
    inputs = Enum.map(1..8, &"private input #{&1}")
    body = native_body(:ollama, 4096, 8)

    assert {:ok, result, %{"prompt_eval_count" => 23, "total_duration" => 500_000}} =
             Embedding.parse(:ollama, body, runtime(:ollama, 4096), inputs)

    assert length(result["vectors"]) == 8
    assert Embedding.valid_result?(result, execution(:ollama, 4096), inputs)
    refute Jason.encode!(result) =~ "private input"
    assert byte_size(Jason.encode!(result)) < 262_144
  end

  test "malformed structure, coordinate widths, indices and unsafe models refuse the whole response" do
    base = %{"model" => "fixture", "data" => [%{"index" => 0, "embedding" => [1.0, 0.5]}]}

    for native <- [
          Map.put(base, "data", []),
          Map.put(base, "data", [
            %{"index" => 0, "embedding" => [1.0, 0.5]},
            %{"index" => 0, "embedding" => [1.0, 0.5]}
          ]),
          put_in(base, ["data", Access.at(0), "index"], 0.0),
          put_in(base, ["data", Access.at(0), "index"], 1),
          put_in(base, ["data", Access.at(0), "embedding"], [1.0]),
          put_in(base, ["data", Access.at(0), "embedding"], ["1", 0.5]),
          put_in(base, ["data", Access.at(0), "embedding"], [[1], 0.5]),
          put_in(base, ["data", Access.at(0), "embedding"], [0.0, -0.0]),
          put_in(base, ["data", Access.at(0), "embedding"], [1.0e-100, 0.0]),
          put_in(base, ["data", Access.at(0), "embedding"], [1.0e100, 0.5]),
          Map.put(base, "model", "private\nmodel"),
          Map.delete(base, "model")
        ],
        do:
          assert(
            {:error, _} =
              Embedding.parse(:openai, Jason.encode!(native), runtime(:openai, 2), ["input"])
          )

    for body <- ["not json", "[]", <<255>>, String.duplicate("x", 2_097_153)],
        do: assert({:error, _} = Embedding.parse(:openai, body, runtime(:openai, 2), ["input"]))
  end

  test "saved float32 data rejects hash/input/encoding substitution and nonfinite bit patterns" do
    assert {:ok, result, _} =
             Embedding.parse(:ollama, native_body(:ollama, 768, 1), runtime(:ollama, 768), [
               "input"
             ])

    data = Map.take(result, ~w(encoding dimensions vectors))
    assert Embedding.valid_data?(data, ["input"], 768)
    refute Embedding.valid_data?(data, ["other input"], 768)
    refute Embedding.valid_data?(data, ["input"], 4096)

    for changed <- [
          Map.put(data, "extra", true),
          Map.put(data, "encoding", "json"),
          put_in(data, ["vectors", Access.at(0), "index"], 1),
          put_in(data, ["vectors", Access.at(0), "values"], "not base64"),
          put_in(data, ["vectors", Access.at(0), "vector_sha256"], String.duplicate("a", 64))
        ],
        do: refute(Embedding.valid_data?(changed, ["input"], 768))

    for word <- [0x7F800000, 0xFF800000, 0x7FC00001, 0, 0x80000000] do
      bytes = <<word::little-unsigned-size(32)>> <> :binary.copy(<<0::32>>, 767)

      changed =
        data
        |> put_in(["vectors", Access.at(0), "values"], Base.encode64(bytes))
        |> put_in(["vectors", Access.at(0), "vector_sha256"], sha256(bytes))

      refute Embedding.valid_data?(changed, ["input"], 768)
    end

    for changed <- [
          Map.put(result, "extra", true),
          Map.put(result, "provider_response_sha256", "invalid"),
          Map.put(result, "reported_model", nil)
        ],
        do: refute(Embedding.valid_result?(changed, execution(:ollama, 768), ["input"]))

    refute Embedding.valid_result?(result, %{dimensions: 768}, ["input"])
  end

  test "native missing, zero, null and invalid counters remain distinct for accounting" do
    for usage <- [
          nil,
          %{},
          %{"prompt_tokens" => 0, "total_tokens" => 0},
          %{"prompt_tokens" => nil, "total_tokens" => nil},
          %{"prompt_tokens" => -1, "total_tokens" => "invalid"},
          []
        ] do
      body =
        Jason.encode!(%{
          "model" => "fixture",
          "data" => [%{"index" => 0, "embedding" => [1.0]}],
          "usage" => usage
        })

      assert {:ok, _, ^usage} = Embedding.parse(:openai, body, runtime(:openai, 1), ["input"])
    end

    body =
      Jason.encode!(%{
        "model" => "fixture",
        "embeddings" => [[1.0]],
        "prompt_eval_count" => -1,
        "total_duration" => nil
      })

    assert {:ok, _, %{"prompt_eval_count" => -1, "total_duration" => nil}} =
             Embedding.parse(:ollama, body, runtime(:ollama, 1), ["input"])
  end

  test "real loopback POSTs use exact provider routes/auth and never emit callbacks" do
    owner = self()

    for {provider, dimensions} <- [{:openai, 4096}, {:ollama, 768}] do
      {result, request} =
        serve(native_body(provider, dimensions, 1), fn base ->
          config =
            runtime(provider, dimensions)
            |> Map.merge(%{base_url: base, api_key: "synthetic-key", dimension_mode: "request"})

          Embedding.embed(config, ["input"], fn message ->
            send(owner, {:unexpected_embedding_callback, message})
          end)
        end)

      assert {:ok, typed, _} = result
      assert Embedding.valid_result?(typed, execution(provider, dimensions), ["input"])
      expected_path = if provider == :openai, do: "/embeddings", else: "/api/embed"
      assert request.target == expected_path
      assert request.method == "POST"
      assert request.body["dimensions"] == dimensions
      assert request.body["input"] == ["input"]

      if provider == :openai do
        assert request.headers["authorization"] == "Bearer synthetic-key"
        assert request.body["encoding_format"] == "float"
      else
        refute Map.has_key?(request.headers, "authorization")
        assert request.body["truncate"] === false
      end

      refute Map.has_key?(request.body, "max_output_tokens")
      refute Map.has_key?(request.body, "options")
    end

    refute_receive {:unexpected_embedding_callback, _}
  end

  test "missing credentials refuse before opening a socket and errors never expose provider bodies" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    try do
      assert {:error, _} =
               Embedding.embed(
                 runtime(:openai, 1) |> Map.put(:base_url, "http://127.0.0.1:#{port}"),
                 ["input"],
                 fn _ -> flunk("must not emit") end
               )

      assert {:error, :timeout} = :gen_tcp.accept(listener, 50)
    after
      :gen_tcp.close(listener)
    end

    for status <- [302, 401, 429, 500] do
      {result, _} =
        serve(
          "private-provider-body synthetic-key",
          fn base ->
            Embedding.embed(
              runtime(:openai, 1) |> Map.merge(%{base_url: base, api_key: "synthetic-key"}),
              ["input"],
              fn _ -> :ok end
            )
          end,
          status: status
        )

      assert {:error, safe} = result
      refute safe =~ "private-provider-body"
      refute safe =~ "synthetic-key"
    end
  end

  test "declared and chunked oversized bodies stop at the bounded transport" do
    for framing <- [:length, :chunked] do
      {result, _} =
        serve(
          String.duplicate("x", 2_097_153),
          fn base ->
            Embedding.embed(runtime(:ollama, 1) |> Map.put(:base_url, base), ["input"], fn _ ->
              :ok
            end)
          end,
          framing: framing
        )

      assert {:error, _} = result
    end
  end

  defp runtime(provider, dimensions),
    do: %{
      provider: provider,
      model: "fixture",
      dimensions: dimensions,
      dimension_mode: "native",
      timeout_ms: 5000,
      base_url: nil
    }

  defp execution(provider, dimensions),
    do: %{
      "id" => "embedding",
      "operation" => "embedding",
      "provider" => Atom.to_string(provider),
      "model" => "fixture",
      "billing_mode" => if(provider == :openai, do: "api", else: "local"),
      "endpoint_sha256" => nil,
      "dimensions" => dimensions,
      "dimension_mode" => "native",
      "timeout_ms" => 5000
    }

  defp coordinates(dimensions, first), do: [first | List.duplicate(0.25, dimensions - 1)]

  defp native_body(:openai, dimensions, count),
    do:
      Jason.encode!(%{
        "model" => "fixture",
        "data" =>
          Enum.map(0..(count - 1), &%{"index" => &1, "embedding" => coordinates(dimensions, 1.0)}),
        "usage" => %{"prompt_tokens" => 23, "total_tokens" => 23}
      })

  defp native_body(:ollama, dimensions, count),
    do:
      Jason.encode!(%{
        "model" => "fixture",
        "embeddings" => List.duplicate(coordinates(dimensions, 1.0), count),
        "prompt_eval_count" => 23,
        "total_duration" => 500_000
      })

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp serve(body, fun, options \\ []) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    tag = make_ref()

    fixture =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 10_000)

        try do
          request = receive_request(socket, "")
          send(owner, {tag, request})
          status = Keyword.get(options, :status, 200)

          if Keyword.get(options, :framing, :length) == :chunked do
            :gen_tcp.send(socket, [
              "HTTP/1.1 #{status} Fixture\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n",
              Integer.to_string(byte_size(body), 16),
              "\r\n",
              body,
              "\r\n0\r\n\r\n"
            ])
          else
            :gen_tcp.send(socket, [
              "HTTP/1.1 #{status} Fixture\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
              body
            ])
          end
        after
          :gen_tcp.close(socket)
        end
      end)

    try do
      result = fun.("http://127.0.0.1:#{port}")

      request =
        receive do
          {^tag, request} -> request
        after
          1000 -> flunk("missing loopback request")
        end

      Task.await(fixture, 10_000)
      {result, request}
    after
      :gen_tcp.close(listener)
      Task.shutdown(fixture, :brutal_kill)
    end
  end

  defp receive_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [header, received] ->
        [line | fields] = String.split(header, "\r\n")
        [method, target, _] = String.split(line, " ")

        headers =
          Map.new(fields, fn field ->
            [key, value] = String.split(field, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        count = String.to_integer(headers["content-length"])
        body = receive_body(socket, received, count)
        %{method: method, target: target, headers: headers, body: Jason.decode!(body)}

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
        receive_request(socket, buffer <> more)
    end
  end

  defp receive_body(_socket, bytes, count) when byte_size(bytes) >= count,
    do: binary_part(bytes, 0, count)

  defp receive_body(socket, bytes, count) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
    receive_body(socket, bytes <> more, count)
  end
end
