defmodule Ipse.Extension.SemanticRoutes do
  @moduledoc "Actual admitted route inventory plus explicitly reviewed nullable disclosure labels."
  alias Ipse.Config.{Semantics, Profiles, Decisions}
  alias Ipse.Extension.ModelCall
  @labels ~w(processing_region storage_region cache_retention account_controls)
  @selectors ~w(operation profile processing_region storage_region cache_retention account_controls)
  @operations ~w(main model.complete embedding.create decision.create)
  @error {:error, :semantic_route_unavailable}

  @doc "Select route identifiers/review labels only; actual destinations never come from these records."
  def selectors(routes) when is_list(routes) and length(routes) <= 8 do
    values = Enum.map(routes, &Map.take(&1, @selectors))
    if selectors?(values), do: {:ok, values}, else: @error
  rescue
    _ -> @error
  end

  def selectors(_), do: @error

  @doc "Pure preflight, with no authentication, model request, worker start or network IO."
  def resolve(config, selections) do
    with true <- is_map(config) and selectors?(selections),
         services = Map.get(config, :inference_services, %{}),
         :ok <- Semantics.validate_services(services) do
      Enum.reduce_while(selections, {:ok, []}, fn selected, {:ok, acc} ->
        case route(config, services, selected) do
          {:ok, route} -> {:cont, {:ok, [route | acc]}}
          _ -> {:halt, @error}
        end
      end)
      |> case do
        {:ok, routes} -> {:ok, Enum.sort_by(routes, & &1["operation"])}
        _ -> @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Review actual routes and needed origin registrations before a policy exists; grants no authority."
  def review(config, selections) do
    with true <- is_map(config) and selectors?(selections),
         base = Map.get(config, :inference_services, %{}),
         :ok <- Semantics.validate_services(base),
         {:ok, registry} <- review_registry(config, selections, base),
         :ok <- Semantics.validate_services(registry),
         {:ok, routes} <- resolve(Map.put(config, :inference_services, registry), selections) do
      {:ok, %{routes: routes, registry: registry}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp review_registry(config, selections, base) do
    Enum.reduce_while(selections, {:ok, base}, fn selected, {:ok, registry} ->
      if config[:provider] == :demo and selected["operation"] == "main" do
        {:cont, {:ok, registry}}
      else
        with {:ok, runtime} <- runtime(config, selected),
             {:ok, _, destination} <- endpoint(runtime, selected["operation"]),
             {:ok, registry} <- register_origin(registry, destination["origin"]) do
          {:cont, {:ok, registry}}
        else
          _ -> {:halt, @error}
        end
      end
    end)
  end

  defp register_origin(registry, origin) do
    case service(registry, origin) do
      {:ok, _} ->
        {:ok, registry}

      _ ->
        id = "origin-" <> binary_part(Ipse.JSON.sha256(origin), 0, 56)

        if Map.has_key?(registry, id),
          do: @error,
          else: {:ok, Map.put(registry, id, %{"version" => 1, "origins" => [origin]})}
    end
  end

  defp route(%{provider: :demo, model: model}, _services, %{"operation" => "main"} = selected) do
    {:ok,
     Map.merge(Map.take(selected, @labels), %{
       "operation" => "main",
       "profile" => nil,
       "provider" => "demo",
       "model" => model,
       "endpoint" => "demo://local",
       "service_id" => "demo",
       "billing_mode" => "none"
     })}
  end

  defp route(config, services, selected) do
    with {:ok, runtime} <- runtime(config, selected),
         {:ok, endpoint, destination} <- endpoint(runtime, selected["operation"]),
         {:ok, service_id} <- service(services, destination["origin"]),
         true <-
           selected["operation"] != "decision.create" or
             get_in(config, [:decision_profiles, selected["profile"], "service_id"]) == service_id,
         billing when is_binary(billing) <- Ipse.Usage.billing_mode(runtime.provider) do
      {:ok,
       Map.merge(Map.take(selected, @labels), %{
         "operation" => selected["operation"],
         "profile" => selected["profile"],
         "provider" => Atom.to_string(runtime.provider),
         "model" => runtime.model,
         "endpoint" => endpoint,
         "service_id" => service_id,
         "billing_mode" => billing
       })}
    else
      _ -> @error
    end
  end

  defp runtime(config, %{"operation" => "main"}) do
    with :ok <- Ipse.Provider.Registry.validate_request(config),
         {:ok, _} <- Ipse.Provider.destination(config) do
      {:ok, config}
    end
  end

  defp runtime(config, %{"operation" => "model.complete", "profile" => profile}) do
    request = %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => profile,
      "instruction" => "",
      "input" => "route preflight",
      "max_output_bytes" => 1,
      "timeout_ms" => 120_000
    }

    case ModelCall.prepare(config, request) do
      {:ok, runtime, _execution} -> {:ok, runtime}
      _ -> @error
    end
  end

  defp runtime(config, %{"operation" => "embedding.create", "profile" => profile}) do
    case Profiles.prepare_embedding(config, %{"profile" => profile, "timeout_ms" => 120_000}) do
      {:ok, runtime, _execution} -> {:ok, runtime}
      _ -> @error
    end
  end

  defp runtime(config, %{"operation" => "decision.create", "profile" => profile}) do
    case Decisions.prepare(config, %{"profile" => profile, "timeout_ms" => 120_000}) do
      {:ok, runtime, _execution} -> {:ok, runtime}
      _ -> @error
    end
  end

  defp endpoint(runtime, operation) do
    {target, destination} =
      case operation do
        "embedding.create" ->
          {Ipse.Provider.Embedding.endpoint(runtime),
           Ipse.Provider.Embedding.destination(runtime)}

        "decision.create" ->
          {Ipse.Provider.Decision.Transport.endpoint(runtime),
           Ipse.Provider.Decision.Transport.destination(runtime)}

        _ ->
          {:ok, spec} = Ipse.Provider.Registry.fetch(runtime.provider)
          {apply(spec.adapter, :endpoint, [runtime]), Ipse.Provider.destination(runtime)}
      end

    with {:ok, destination} <- destination,
         true <- Ipse.JSON.sha256(target) == destination["target_sha256"],
         do: {:ok, target, destination},
         else: (_ -> @error)
  end

  defp service(services, origin) do
    case for {id, entry} <- services, origin in entry["origins"], do: id do
      [id] -> {:ok, id}
      _ -> @error
    end
  end

  defp selectors?(values) do
    is_list(values) and length(values) <= 8 and
      Enum.all?(values, fn value ->
        is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(@selectors) and
          value["operation"] in @operations and
          if(value["operation"] == "main",
            do: is_nil(value["profile"]),
            else: profile?(value["profile"])
          ) and
          Enum.all?(@labels, &(is_nil(value[&1]) or label?(value[&1])))
      end) and length(Enum.uniq_by(values, & &1["operation"])) == length(values)
  end

  defp profile?(p), do: is_binary(p) and Regex.match?(~r/\A[A-Za-z][A-Za-z0-9_-]{0,63}\z/, p)

  defp label?(s),
    do:
      is_binary(s) and byte_size(s) in 1..512 and String.valid?(s) and
        not Enum.any?(String.to_charlist(s), &(&1 < 32 or &1 == 127))
end
