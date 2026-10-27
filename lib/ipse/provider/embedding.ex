defmodule Ipse.Provider.Embedding do
  @moduledoc "Typed OpenAI and Ollama embeddings over the existing bounded owned HTTP client."
  import Bitwise
  @encoding "float32le.base64"
  @body_limit 2_097_152
  @error {:error, "Embedding response or configuration is invalid or unavailable."}

  def endpoint(%{provider: :openai} = config),
    do:
      Ipse.Provider.endpoint(
        config,
        Ipse.Provider.Registry.fetch!(:openai).default_base_url,
        "/embeddings"
      )

  def endpoint(%{provider: :ollama} = config),
    do:
      Ipse.Provider.endpoint(
        config,
        Ipse.Provider.Registry.fetch!(:ollama).default_base_url,
        "/api/embed"
      )

  def endpoint(_), do: raise(ArgumentError, "Unsupported embedding provider.")

  def destination(config) do
    with target when is_binary(target) <- endpoint(config),
         {:ok, uri} <- URI.new(target),
         facts = %{
           "origin" => URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}),
           "target_sha256" => Ipse.JSON.sha256(target)
         },
         true <- Ipse.Provider.valid_destination?(facts) do
      {:ok, facts}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def request_body(config, inputs) do
    with true <- runtime?(config) and inputs?(inputs) do
      body =
        case config.provider do
          :openai ->
            %{"model" => config.model, "input" => inputs, "encoding_format" => "float"}

          :ollama ->
            %{"model" => config.model, "input" => inputs, "truncate" => false}
        end

      body =
        if config.dimension_mode == "request",
          do: Map.put(body, "dimensions", config.dimensions),
          else: body

      {:ok, body}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def embed(config, inputs, emit) when is_function(emit, 1) do
    with {:ok, body} <- request_body(config, inputs),
         {:ok, _} <- destination(config),
         {:ok, headers} <- headers(config),
         timeout = config[:timeout_ms] || 120_000,
         true <- is_integer(timeout) and timeout in 1..120_000,
         request = Finch.build(:post, endpoint(config), headers, Jason.encode!(body)),
         {:ok, status, bytes} <- Ipse.HTTP.bounded_request(request, @body_limit, timeout),
         true <- status in 200..299 do
      case parse(config.provider, bytes, config, inputs) do
        {:ok, _, _} = result ->
          Ipse.Provider.CompletionWitness.native_complete(config, :embedding)
          result

        result ->
          result
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def embed(_, _, _), do: @error

  def parse(provider, body, config, inputs) do
    with true <- provider in [:openai, :ollama] and config[:provider] == provider,
         true <- runtime?(config) and inputs?(inputs),
         true <- is_binary(body) and byte_size(body) <= @body_limit,
         {:ok, native} when is_map(native) <- Jason.decode(body),
         model when is_binary(model) <- native["model"],
         true <- Ipse.Provider.model_name(model) == model,
         {:ok, rows} <- native_vectors(provider, native, length(inputs)),
         {:ok, vectors} <- vectors(rows, inputs, config.dimensions),
         result = %{
           "kind" => "embedding",
           "version" => 1,
           "encoding" => @encoding,
           "reported_model" => model,
           "dimensions" => config.dimensions,
           "vectors" => vectors,
           "provider_response_sha256" => Ipse.JSON.sha256(body)
         } do
      {:ok, result, native_usage(provider, native)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Validate private typed results against string-keyed public execution facts and exact inputs."
  def valid_result?(result, execution, inputs) do
    keys?(
      result,
      ~w(kind version encoding reported_model dimensions vectors provider_response_sha256)
    ) and
      execution?(execution) and
      result["kind"] == "embedding" and result["version"] === 1 and
      Ipse.Provider.model_name(result["reported_model"]) == result["reported_model"] and
      is_binary(result["reported_model"]) and
      Ipse.JSON.sha256?(result["provider_response_sha256"]) and
      valid_data?(
        Map.take(result, ~w(encoding dimensions vectors)),
        inputs,
        execution["dimensions"]
      )
  rescue
    _ -> false
  end

  @doc "Validate closed private float32 data without weakening the public SDK string or array bounds."
  def valid_data?(data, inputs, dimensions) do
    inputs?(inputs) and
      valid_data_hashes?(data, Enum.map(inputs, &Ipse.JSON.digest([&1])), dimensions)
  rescue
    _ -> false
  end

  def valid_data?(data) do
    hashes = Enum.map(data["vectors"], & &1["input_sha256"])

    length(hashes) in 1..8 and Enum.all?(hashes, &Ipse.JSON.sha256?/1) and
      valid_data_hashes?(data, hashes, data["dimensions"])
  rescue
    _ -> false
  end

  defp valid_data_hashes?(data, hashes, dimensions) do
    keys?(data, ~w(encoding dimensions vectors)) and dimensions?(dimensions) and
      data["dimensions"] === dimensions and data["encoding"] == @encoding and
      is_list(data["vectors"]) and length(data["vectors"]) == length(hashes) and
      Enum.zip(data["vectors"], Enum.with_index(hashes))
      |> Enum.all?(fn {vector, {input_hash, index}} ->
        keys?(vector, ~w(index input_sha256 vector_sha256 values)) and
          vector["index"] === index and vector["input_sha256"] == input_hash and
          Ipse.JSON.sha256?(vector["vector_sha256"]) and is_binary(vector["values"]) and
          byte_size(vector["values"]) == 4 * div(dimensions * 4 + 2, 3) and
          case Base.decode64(vector["values"]) do
            {:ok, bytes} ->
              byte_size(bytes) == dimensions * 4 and Base.encode64(bytes) == vector["values"] and
                Ipse.JSON.sha256(bytes) == vector["vector_sha256"] and valid_coordinates?(bytes)

            _ ->
              false
          end
      end)
  rescue
    _ -> false
  end

  defp native_vectors(:openai, native, count) do
    rows = native["data"]

    with true <- is_list(rows) and length(rows) == count,
         true <- Enum.all?(rows, &(is_map(&1) and is_integer(&1["index"]))),
         true <- Enum.sort(Enum.map(rows, & &1["index"])) == Enum.to_list(0..(count - 1)) do
      {:ok, rows |> Enum.sort_by(& &1["index"]) |> Enum.map(& &1["embedding"])}
    else
      _ -> @error
    end
  end

  defp native_vectors(:ollama, native, count) do
    rows = native["embeddings"]
    if is_list(rows) and length(rows) == count, do: {:ok, rows}, else: @error
  end

  defp native_usage(:openai, native) do
    case native["usage"] do
      usage when is_map(usage) -> Map.take(usage, ~w(prompt_tokens total_tokens))
      other -> other
    end
  end

  defp native_usage(:ollama, native), do: Map.take(native, ~w(prompt_eval_count total_duration))

  defp vectors(rows, inputs, dimensions) do
    Enum.zip(rows, Enum.with_index(inputs))
    |> Enum.reduce_while({:ok, []}, fn {coordinates, {input, index}}, {:ok, acc} ->
      case vector(coordinates, dimensions) do
        {:ok, bytes} ->
          entry = %{
            "index" => index,
            "input_sha256" => Ipse.JSON.digest([input]),
            "vector_sha256" => Ipse.JSON.sha256(bytes),
            "values" => Base.encode64(bytes)
          }

          {:cont, {:ok, [entry | acc]}}

        _ ->
          {:halt, @error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp vector(values, dimensions) when is_list(values) and length(values) == dimensions do
    bytes =
      Enum.map(values, fn value ->
        if is_integer(value) or (is_float(value) and value == value and abs(value) < 1.0e308),
          do: <<value::float-little-size(32)>>,
          else: throw(:invalid_coordinate)
      end)
      |> IO.iodata_to_binary()

    if valid_coordinates?(bytes), do: {:ok, bytes}, else: @error
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp vector(_, _), do: @error

  defp valid_coordinates?(bytes) do
    words = for <<bits::little-unsigned-size(32) <- bytes>>, do: bits

    Enum.all?(words, &(band(&1, 0x7F800000) != 0x7F800000)) and
      Enum.any?(words, &(band(&1, 0x7FFFFFFF) != 0))
  end

  defp execution?(execution) do
    keys =
      ~w(id operation provider model billing_mode endpoint_sha256 dimensions dimension_mode timeout_ms)

    is_map(execution) and keys?(Map.delete(execution, "destination"), keys) and
      is_binary(execution["id"]) and
      Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, execution["id"]) and
      execution["operation"] == "embedding" and execution["provider"] in ~w(openai ollama) and
      is_binary(execution["model"]) and
      Ipse.Provider.model_name(execution["model"]) == execution["model"] and
      execution["billing_mode"] == if(execution["provider"] == "openai", do: "api", else: "local") and
      (is_nil(execution["endpoint_sha256"]) or Ipse.JSON.sha256?(execution["endpoint_sha256"])) and
      dimensions?(execution["dimensions"]) and execution["dimension_mode"] in ~w(native request) and
      is_integer(execution["timeout_ms"]) and execution["timeout_ms"] in 1..120_000 and
      (not Map.has_key?(execution, "destination") or
         Ipse.Provider.valid_destination?(execution["destination"]))
  end

  defp runtime?(config) do
    is_map(config) and config[:provider] in [:openai, :ollama] and
      is_binary(config[:model]) and Ipse.Provider.model_name(config[:model]) == config[:model] and
      dimensions?(config[:dimensions]) and config[:dimension_mode] in ~w(native request)
  end

  defp inputs?(inputs) do
    is_list(inputs) and length(inputs) in 1..8 and
      Enum.all?(inputs, &(is_binary(&1) and String.valid?(&1) and byte_size(&1) in 1..4096)) and
      Enum.reduce(inputs, 0, &(byte_size(&1) + &2)) <= 12_288 and
      Ipse.Extension.validate(%{"inputs" => inputs}) == :ok
  end

  defp headers(%{provider: :openai, api_key: key})
       when is_binary(key) and byte_size(key) in 1..16_384 do
    if String.valid?(key) and not Regex.match?(~r/[\x00-\x20\x7f]/, key),
      do: {:ok, [{"authorization", "Bearer " <> key} | json_headers()]},
      else: @error
  end

  defp headers(%{provider: :ollama}), do: {:ok, json_headers()}
  defp headers(_), do: @error

  defp json_headers,
    do: [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"accept-encoding", "identity"}
    ]

  defp dimensions?(value), do: is_integer(value) and value in 1..4096
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
