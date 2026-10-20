defmodule MeasuredModelDaemon do
  @moduledoc "Bounded scripted Ollama wire fixture; it performs no model inference."
  @header_limit 16_384
  @body_limit 65_536
  @log_limit 16_777_216
  @request_limit 4096

  def main(control_path) do
    control = decode_file!(control_path)
    %{"version" => 1, "models" => models, "launch" => launch} = control
    true = Enum.sort(Map.keys(models)) == ~w(fixture-embedding:latest fixture-text:latest)
    true = :code.get_path() == Enum.map(launch["code_paths"], &String.to_charlist/1)

    for file <- launch["files"] do
      %{type: :regular, size: size} = File.lstat!(file["path"])
      true = size == file["bytes"]
      true = sha_file(file["path"]) == file["sha256"]
    end

    for {key, value} <- [
          {"CUDA_VISIBLE_DEVICES", "-1"},
          {"ROCR_VISIBLE_DEVICES", "-1"},
          {"OLLAMA_VULKAN", "0"},
          {"GGML_VK_VISIBLE_DEVICES", "-1"},
          {"OLLAMA_NO_CLOUD", "1"}
        ],
        do: ^value = System.fetch_env!(key)

    uri = URI.parse(System.fetch_env!("OLLAMA_HOST"))
    true = System.fetch_env!("OLLAMA_HOST") == "http://127.0.0.1:#{uri.port}"
    home = System.fetch_env!("HOME")
    File.write!(Path.join(home, "fixture-daemon.pid"), System.pid(), [:exclusive])
    File.write!(Path.join(home, "fixture-requests.jsonl"), <<>>, [:exclusive, :sync])
    File.chmod!(Path.join(home, "fixture-requests.jsonl"), 0o600)

    {:ok, listener} =
      :gen_tcp.listen(uri.port, [
        :binary,
        active: false,
        ip: {127, 0, 0, 1},
        reuseaddr: true,
        backlog: 16,
        send_timeout: 1000,
        send_timeout_close: true
      ])

    true = control["fault"] in [nil, "exit_on_answer"]

    loop(listener, %{
      models: models,
      home: home,
      requests: 0,
      log_bytes: 0,
      counts: %{},
      fault: control["fault"]
    })
  end

  def response("GET", "/api/tags", body, models) when map_size(body) == 0 do
    {"tags",
     %{
       "models" =>
         Enum.map(Enum.sort(models), fn {name, digest} ->
           %{"name" => name, "model" => name, "digest" => digest}
         end)
     }}
  end

  def response("POST", "/api/show", %{"model" => name}, models) do
    true = Map.has_key?(models, name)

    capabilities =
      if name == "fixture-text:latest", do: ["completion", "tools"], else: ["embedding"]

    {"show", %{"capabilities" => capabilities, "thinking" => %{"values" => [false]}}}
  end

  def response("GET", "/api/ps", body, _models) when map_size(body) == 0,
    do: {"resident", %{"models" => []}}

  def response(
        "POST",
        "/api/embed",
        %{"model" => "fixture-embedding:latest", "input" => inputs} = body,
        models
      ) do
    true = Map.has_key?(models, body["model"]) and is_list(inputs) and length(inputs) in 1..128

    vectors =
      Enum.map(inputs, fn input ->
        true = is_binary(input) and byte_size(input) <= 32_768
        if String.contains?(String.downcase(input), "release"), do: [1.0, 0.0], else: [0.0, 1.0]
      end)

    {"embedding", %{"model" => body["model"], "embeddings" => vectors, "prompt_eval_count" => 3}}
  end

  def response(
        "POST",
        "/api/chat",
        %{"model" => "fixture-text:latest", "messages" => messages} = body,
        models
      ) do
    true = Map.has_key?(models, body["model"]) and is_list(messages) and length(messages) in 1..32

    input =
      messages
      |> List.last()
      |> Map.fetch!("content")
      |> String.split("\n", parts: 2)
      |> List.last()
      |> JSON.decode!()
      |> Map.fetch!("input")
      |> JSON.decode!()

    {kind, answer} =
      cond do
        is_list(input["chunks"]) ->
          [chunk] = input["chunks"]

          {"extraction",
           %{
             "facts" => [
               %{
                 "subject" => "Release",
                 "predicate" => "requires",
                 "object" => "quiescence",
                 "polarity" => "positive",
                 "chunk" => chunk["id"],
                 "quote" => chunk["text"]
               }
             ]
           }}

        is_integer(input["required_count"]) ->
          true = input["required_count"] == length(input["candidates"])
          {"rerank", %{"order" => Enum.map(input["candidates"], & &1["id"])}}

        input["candidates"] == [] or input["query"] == "absent mineral" ->
          {"answer", %{"classification" => "abstain", "answer" => "No evidence.", "claims" => []}}

        true ->
          {"answer",
           %{
             "classification" => "answer",
             "answer" => "Release requires quiescence.",
             "claims" => [
               %{
                 "text" => "Release requires quiescence.",
                 "citations" => [hd(input["candidates"])["id"]]
               }
             ]
           }}
      end

    {kind,
     %{
       "model" => body["model"],
       "message" => %{"role" => "assistant", "content" => JSON.encode!(answer)},
       "done" => true,
       "done_reason" => "stop",
       "prompt_eval_count" => 8,
       "eval_count" => 8
     }}
  end

  defp loop(listener, state) do
    {:ok, socket} = :gen_tcp.accept(listener)

    next =
      try do
        {method, path, body} = request(socket, <<>>, System.monotonic_time(:millisecond) + 5_000)
        {kind, value} = response(method, path, body, state.models)
        bytes = JSON.encode!(value) <> "\n"
        true = byte_size(bytes) <= @body_limit
        {:ok, method, path, body, kind, bytes}
      rescue
        _ -> :refused
      end

    state =
      try do
        case next do
          {:ok, method, path, body, kind, bytes} ->
            recorded = record(state, method, path, body, kind)

            if state.fault == "exit_on_answer" and kind == "answer", do: System.halt(86)

            _ =
              :gen_tcp.send(socket, [
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(bytes)}\r\nconnection: close\r\n\r\n",
                bytes
              ])

            recorded

          :refused ->
            _ =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 400 Bad Request\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
              )

            state
        end
      after
        :gen_tcp.close(socket)
      end

    loop(listener, state)
  end

  defp request(socket, bytes, deadline) do
    true = byte_size(bytes) <= @header_limit + @body_limit

    case :binary.split(bytes, "\r\n\r\n") do
      [header, rest] ->
        true = byte_size(header) <= @header_limit
        [line | lines] = String.split(header, "\r\n")
        [method, path, "HTTP/1.1"] = String.split(line, " ")

        true =
          method in ["GET", "POST"] and
            path in ~w(/api/tags /api/show /api/ps /api/chat /api/embed)

        headers =
          Enum.map(lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        false = Enum.any?(headers, &(elem(&1, 0) == "transfer-encoding"))
        lengths = for {"content-length", value} <- headers, do: value

        length =
          case lengths do
            [] when method == "GET" ->
              0

            [value] ->
              {length, ""} = Integer.parse(value)
              true = length in 0..@body_limit and Integer.to_string(length) == value
              length
          end

        if byte_size(rest) < length do
          request(socket, bytes <> receive_bytes(socket, deadline), deadline)
        else
          true = byte_size(rest) == length
          body = if length == 0, do: %{}, else: decode!(rest)
          true = is_map(body)
          {method, path, body}
        end

      [_] ->
        true = byte_size(bytes) <= @header_limit
        request(socket, bytes <> receive_bytes(socket, deadline), deadline)
    end
  end

  defp receive_bytes(socket, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    true = remaining > 0
    {:ok, bytes} = :gen_tcp.recv(socket, 0, remaining)
    true = byte_size(bytes) > 0
    bytes
  end

  defp record(state, method, path, body, kind) do
    true = state.requests < @request_limit

    bytes =
      JSON.encode!(%{
        "method" => method,
        "path" => path,
        "operation" => kind,
        "model" => body["model"],
        "request" => body
      }) <> "\n"

    true = state.log_bytes + byte_size(bytes) <= @log_limit
    File.write!(Path.join(state.home, "fixture-requests.jsonl"), bytes, [:append, :sync])
    counts = Map.update(state.counts, kind, 1, &(&1 + 1))

    next = %{
      state
      | requests: state.requests + 1,
        log_bytes: state.log_bytes + byte_size(bytes),
        counts: counts
    }

    summary =
      JSON.encode!(%{
        "synthetic" => true,
        "model_inference" => false,
        "requests" => next.requests,
        "log_bytes" => next.log_bytes,
        "operations" => counts
      }) <> "\n"

    temporary = Path.join(state.home, "fixture-requests-summary.tmp")
    File.write!(temporary, summary, [:sync])
    File.chmod!(temporary, 0o600)
    File.rename!(temporary, Path.join(state.home, "fixture-requests-summary.json"))
    next
  end

  defp decode_file!(path) do
    %{type: :regular, size: size} = File.lstat!(path)
    true = size <= 1_048_576
    File.read!(path) |> decode!()
  end

  defp decode!(bytes) do
    {:ok, value} = Ipse.Extensions.Manifest.decode_json(bytes, 1_048_576)
    value
  end

  defp sha_file(path) do
    File.stream!(path, 1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end
