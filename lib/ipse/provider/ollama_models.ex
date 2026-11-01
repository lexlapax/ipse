defmodule Ipse.Provider.Ollama.Models do
  @moduledoc "Bounded read-only Ollama inspection and cooperative metadata checks around registered inference jobs. No provisioning."
  alias Ipse.{HTTP, JSON, Provider}
  @limit 1_048_576
  @job {__MODULE__, :job}
  @pin_error {:error,
              "The selected Ollama model pin or loaded context could not be verified; no generated output was released."}
  @pin_schema %{
    "type" => "object",
    "properties" => %{
      "version" => %{"type" => "integer", "enum" => [1]},
      "trust_boundary" => %{"type" => "string", "enum" => ["cooperative_service_metadata"]},
      "manifest_sha256" => %{"type" => "string", "minLength" => 64, "maxLength" => 64},
      "metadata_sha256" => %{"type" => "string", "minLength" => 64, "maxLength" => 64},
      "runtime_version" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
      "minimum_context_tokens" => %{"type" => "integer", "minimum" => 512, "maximum" => 262_144}
    },
    "required" =>
      ~w(version trust_boundary manifest_sha256 metadata_sha256 runtime_version minimum_context_tokens),
    "additionalProperties" => false
  }
  @text %{"type" => "string", "maxLength" => 256}
  @row %{
    "type" => "object",
    "required" => ~w(name model digest size),
    "properties" => %{
      "name" => @text,
      "model" => @text,
      "digest" => %{"type" => "string", "minLength" => 64, "maxLength" => 64},
      "size" => %{"type" => "integer", "minimum" => 0, "maximum" => 9_007_199_254_740_991}
    }
  }
  @list %{
    "type" => "object",
    "required" => ["models"],
    "properties" => %{
      "models" => %{"type" => "array", "maxItems" => 256, "items" => @row}
    }
  }
  @version %{
    "type" => "object",
    "required" => ["version"],
    "properties" => %{
      "version" => %{"type" => "string", "minLength" => 1, "maxLength" => 64}
    }
  }
  @details %{
    "type" => "object",
    "properties" =>
      Map.new(
        ~w(format family parameter_size quantization_level),
        &{&1, %{"type" => ["string", "null"], "maxLength" => 256}}
      )
      |> Map.put("families", %{"type" => ["array", "null"], "maxItems" => 16, "items" => @text})
  }
  @show %{
    "type" => "object",
    "required" => ~w(details model_info capabilities),
    "properties" => %{
      "details" => @details,
      "model_info" => %{"type" => "object"},
      "capabilities" => %{
        "type" => "array",
        "maxItems" => 32,
        "items" => %{"type" => "string", "minLength" => 1, "maxLength" => 64}
      }
    }
  }

  def read(base_url, model, timeout_ms \\ 10_000) do
    # Reuse the host's existing loopback-only URL policy without selecting an inference provider.
    with true <- is_binary(base_url) and Provider.valid_base_url?(:openai_compatible, base_url),
         true <- Provider.model_name(model) == model and is_binary(model),
         true <- is_integer(timeout_ms) and timeout_ms in 1000..30_000 do
      config = %{provider: :ollama, base_url: base_url}
      deadline = System.monotonic_time(:millisecond) + timeout_ms
      observed = System.system_time(:millisecond)

      with {:ok, version} <- request(config, :get, "version", "", deadline, @version),
           {:ok, _} <- Version.parse(version["version"]),
           {:ok, before} <- request(config, :get, "tags", "", deadline, @list),
           {:ok, selected} <- selected(before, model),
           {:ok, show} <-
             request(
               config,
               :post,
               "show",
               Jason.encode!(%{"model" => model, "verbose" => false}),
               deadline,
               @show
             ),
           true <- descriptor?(show),
           {:ok, running} <- request(config, :get, "ps", "", deadline, @list),
           {:ok, loaded} <- loaded(running, selected),
           {:ok, after_tags} <- request(config, :get, "tags", "", deadline, @list),
           {:ok, ^selected} <- selected(after_tags, model),
           {:ok, ^version} <- request(config, :get, "version", "", deadline, @version) do
        report = report(config, model, selected, show, version, loaded, observed)

        if System.monotonic_time(:millisecond) < deadline,
          do: {:ok, report},
          else: {:error, :ollama_inspection_timed_out}
      else
        {:ok, _} -> {:error, :ollama_metadata_changed}
        :error -> {:error, :ollama_metadata_invalid}
        false -> {:error, :ollama_metadata_invalid}
        error -> error
      end
    else
      _ -> {:error, :invalid_ollama_inspection}
    end
  rescue
    _ -> {:error, :ollama_metadata_invalid}
  end

  defp request(config, method, endpoint, body, deadline, schema) do
    remaining = deadline - System.monotonic_time(:millisecond)
    url = Provider.endpoint(config, config.base_url, "/api/" <> endpoint)
    headers = if method == :post, do: [{"content-type", "application/json"}], else: []

    with true <- remaining > 0,
         {:ok, 200, bytes} <-
           HTTP.bounded_request(Finch.build(method, url, headers, body), @limit, remaining),
         {:ok, value} <- JSON.decode_bounded(bytes, @limit),
         :ok <- JSON.validate_result(schema, value) do
      {:ok, value}
    else
      false -> {:error, :ollama_inspection_timed_out}
      {:ok, _, _} -> {:error, :ollama_metadata_unavailable}
      _ -> {:error, :ollama_metadata_invalid_or_unavailable}
    end
  end

  defp selected(list, model) do
    case Enum.filter(list["models"], &(&1["name"] == model or &1["model"] == model)) do
      [row] ->
        if row["name"] == model and row["model"] == model and JSON.sha256?(row["digest"]),
          do: {:ok, row},
          else: {:error, :ollama_metadata_invalid}

      [] ->
        {:error, :ollama_model_not_installed}

      _ ->
        {:error, :ollama_metadata_invalid}
    end
  end

  defp loaded(list, selected) do
    case Enum.filter(
           list["models"],
           &(&1["name"] == selected["name"] or &1["model"] == selected["model"])
         ) do
      [] ->
        {:ok, nil}

      [row] ->
        if row["name"] == selected["name"] and row["model"] == selected["model"] and
             row["digest"] == selected["digest"] and JSON.safe_uint?(row["context_length"]) and
             row["context_length"] > 0 and
             (is_nil(row["size_vram"]) or JSON.safe_uint?(row["size_vram"])),
           do: {:ok, Map.take(row, ~w(digest context_length size size_vram))},
           else: {:error, :ollama_loaded_model_mismatch}

      _ ->
        {:error, :ollama_metadata_invalid}
    end
  end

  defp descriptor?(show) do
    architecture = show["model_info"]["general.architecture"]
    caps = show["capabilities"]

    is_binary(architecture) and Regex.match?(~r/\A[a-z][a-z0-9_]{0,63}\z/, architecture) and
      Enum.uniq(caps) == caps and
      Enum.all?(caps, &Regex.match?(~r/\A[a-z][a-z0-9_]{0,63}\z/, &1)) and
      Enum.all?(~w(template parameters license), &(is_nil(show[&1]) or is_binary(show[&1]))) and
      (is_nil(show["model_info"]["general.license"]) or
         (is_binary(show["model_info"]["general.license"]) and
            byte_size(show["model_info"]["general.license"]) <= 128)) and
      Enum.all?(
        [
          show["model_info"][architecture <> ".context_length"],
          show["model_info"][architecture <> ".embedding_length"],
          show["details"]["context_length"],
          show["details"]["embedding_length"]
        ],
        &(is_nil(&1) or (JSON.safe_uint?(&1) and &1 > 0))
      )
  end

  defp report(config, model, selected, show, version, loaded, observed) do
    uri = URI.parse(config.base_url)
    info = show["model_info"]
    architecture = info["general.architecture"]

    limits =
      if is_binary(architecture) and byte_size(architecture) <= 64,
        do:
          Map.take(info, [architecture <> ".context_length", architecture <> ".embedding_length"]),
        else: %{}

    %{
      "version" => 1,
      "kind" => "ollama_model_inspection",
      "model" => model,
      "origin" => URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}),
      "base_url_sha256" => JSON.sha256(config.base_url),
      "scan_started_at_ms" => observed,
      "observed_at_ms" => System.system_time(:millisecond),
      "runtime_version" => version["version"],
      "manifest_sha256" => selected["digest"],
      "artifact_bytes" => selected["size"],
      "declared_capabilities" => show["capabilities"],
      "declared_details" =>
        Map.new(
          Map.take(show["details"], ~w(format family families parameter_size quantization_level)),
          fn {key, value} ->
            {key, if(is_list(value), do: Enum.map(value, &label/1), else: label(value))}
          end
        ),
      "declared_license" => label(info["general.license"]),
      "license_claim_sha256" => optional_hash(info["general.license"]),
      "declared_limits" => %{
        "model_info" => limits,
        "details" => Map.take(show["details"], ~w(context_length embedding_length))
      },
      "loaded" => loaded,
      "effective_context" =>
        if(is_nil(loaded), do: "unverified_not_loaded", else: "reported_by_service"),
      "metadata_sha256" => JSON.digest([version, selected, show]),
      "template_sha256" => optional_hash(show["template"]),
      "parameters_sha256" => optional_hash(show["parameters"]),
      "license_sha256" => optional_hash(show["license"]),
      "assurance" => "cooperative_service_metadata_not_request_attestation",
      "local_execution" => "not_attested",
      "inference_calls" => 0,
      "metadata_requests" => 6
    }
  end

  defp optional_hash(value) when is_binary(value), do: JSON.sha256(value)
  defp optional_hash(_), do: nil
  defp label(value), do: Ipse.Provider.Transport.safe(value, :code)

  @doc false
  def pin_schema, do: @pin_schema

  @doc false
  def valid_pin?(pin) do
    with :ok <- JSON.validate_arguments(@pin_schema, pin),
         true <- pin["version"] === 1,
         true <- JSON.sha256?(pin["manifest_sha256"]) and JSON.sha256?(pin["metadata_sha256"]),
         true <- is_integer(pin["minimum_context_tokens"]),
         {:ok, _} <- Version.parse(pin["runtime_version"]) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  # Metadata is checked outside CompletionWitness.capture: metadata HTTP must
  # never start, complete or invalidate the selected inference witness.
  @doc false
  def begin_job(runtime, kind, timeout) do
    if Map.has_key?(runtime, :ollama_model_pin) do
      deadline = System.monotonic_time(:millisecond) + timeout

      with true <- runtime[:provider] == :ollama and kind in [:text, :embedding],
           :ok <- Ipse.Provider.Registry.validate_request(runtime),
           true <- valid_pin?(runtime.ollama_model_pin),
           nil <- Process.get(@job),
           {:ok, report} <- job_read(runtime, deadline),
           true <- pinned?(runtime, kind, report) do
        {:ok,
         %{
           owner: self(),
           ref: make_ref(),
           binding: job_binding(runtime),
           kind: kind,
           deadline: deadline
         }}
      else
        _ -> @pin_error
      end
    else
      {:ok, nil}
    end
  rescue
    _ -> @pin_error
  end

  @doc false
  def with_job(nil, runtime, fun), do: fun.(runtime)

  def with_job(check, runtime, fun) do
    with true <- check.owner == self() and is_reference(check.ref),
         true <- check.binding == job_binding(runtime),
         nil <- Process.get(@job) do
      Process.put(@job, check)

      try do
        selected =
          Map.put(
            runtime,
            :timeout_ms,
            min(runtime[:timeout_ms] || 120_000, remaining(check.deadline))
          )

        fun.(selected)
      after
        Process.delete(@job)
      end
    else
      _ -> {:unstarted, @pin_error}
    end
  end

  @doc false
  def finish_job(nil, _runtime, result), do: result

  def finish_job(check, runtime, {:ok, value, _} = result) do
    with :ok <- request_allowed?(runtime, check.kind),
         true <- check == Process.get(@job),
         {:ok, report} <- job_read(runtime, check.deadline),
         true <- pinned?(runtime, check.kind, report),
         true <- is_map(report["loaded"]),
         true <-
           report["loaded"]["context_length"] >=
             runtime.ollama_model_pin["minimum_context_tokens"],
         true <- reported_model(value, check.kind) == runtime.model,
         true <- remaining(check.deadline) > 0 do
      result
    else
      _ -> @pin_error
    end
  rescue
    _ -> @pin_error
  end

  def finish_job(_check, _runtime, result), do: result

  @doc false
  def request_allowed?(runtime, kind \\ :text) do
    if Map.has_key?(runtime, :ollama_model_pin) do
      case Process.get(@job) do
        %{owner: owner, ref: ref, binding: expected, deadline: deadline, kind: ^kind}
        when owner == self() and is_reference(ref) ->
          if runtime[:provider] == :ollama and expected == job_binding(runtime) and
               remaining(deadline) > 0, do: :ok, else: @pin_error

        _ ->
          @pin_error
      end
    else
      :ok
    end
  end

  # Carry the existing trusted job scope into the existing controlled native
  # child. This is not a serialized receipt or a permission/source grant.
  @doc false
  def inherit_job(fun) do
    case Process.get(@job) do
      nil ->
        fun

      check ->
        fn ->
          nil = Process.get(@job)
          Process.put(@job, %{check | owner: self()})
          try do: fun.(), after: Process.delete(@job)
        end
    end
  end

  defp job_read(runtime, deadline) do
    budget = min(remaining(deadline), 10_000)
    base = runtime[:base_url] || Ipse.Provider.Registry.fetch!(:ollama).default_base_url
    if budget >= 1000, do: read(base, runtime.model, budget), else: @pin_error
  end

  defp pinned?(runtime, kind, report) do
    pin = runtime.ollama_model_pin

    report["manifest_sha256"] == pin["manifest_sha256"] and
      report["metadata_sha256"] == pin["metadata_sha256"] and
      report["runtime_version"] == pin["runtime_version"] and
      report["model"] == runtime.model and
      if(kind == :embedding, do: "embedding", else: "completion") in report[
        "declared_capabilities"
      ]
  end

  defp job_binding(runtime),
    do:
      JSON.digest([
        runtime[:provider] |> to_string(),
        runtime[:model],
        runtime[:base_url],
        runtime[:ollama_model_pin],
        runtime[:ollama_context_tokens]
      ])

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
  defp reported_model(value, :embedding), do: value["reported_model"]
  defp reported_model(value, :text), do: get_in(value, ["provider_data", "reported_model"])
end
