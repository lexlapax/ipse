defmodule Ipse.Observability.Config do
  @moduledoc "Operator-only capture policy, independent of sink selection and recovery facts."
  alias Ipse.MCP.Schema

  @groups ~w(session prompt context model stream tool approval question child compaction extension turn error)
  @defaults %{
    "mode" => "off",
    "groups" => @groups,
    "level" => "info",
    "sample_every" => 1,
    "queue_events" => 256,
    "event_bytes" => 16_384,
    "file_bytes" => 10_485_760,
    "retained_files" => 2
  }
  @error {:error, :invalid_observability_policy}
  def defaults, do: @defaults
  def groups, do: @groups

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "mode" => %{"type" => "string", "enum" => ~w(off local export)},
        "groups" => %{
          "type" => "array",
          "maxItems" => length(@groups),
          "items" => %{"type" => "string", "enum" => @groups}
        },
        "level" => %{"type" => "string", "enum" => ~w(info debug)},
        "sample_every" => integer(1, 1000),
        "queue_events" => integer(1, 256),
        "event_bytes" => integer(1024, 16_384),
        "file_bytes" => integer(16_384, 10_485_760),
        "retained_files" => integer(1, 2)
      }
    }
  end

  def validate(policy) do
    with :ok <- Schema.validate_arguments(schema(), policy),
         groups = Map.get(policy, "groups", @groups),
         true <- length(groups) == length(Enum.uniq(groups)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def resolve(sources, options, environment) do
    with true <-
           Enum.all?(
             sources,
             &(&1.scope == "operator" or not Map.has_key?(&1.data, "observability"))
           ),
         operator = Enum.find(sources, &Map.has_key?(&1.data, "observability")),
         values = if(operator, do: operator.data["observability"], else: %{}),
         :ok <- validate(values),
         policy = Map.merge(@defaults, values),
         policy =
           if(environment["IPSE_OBSERVABILITY"],
             do: Map.put(policy, "mode", environment["IPSE_OBSERVABILITY"]),
             else: policy
           ),
         policy =
           if(options[:observability],
             do: Map.put(policy, "mode", options[:observability]),
             else: policy
           ),
         :ok <- validate(policy) do
      source =
        cond do
          options[:observability] -> "CLI"
          environment["IPSE_OBSERVABILITY"] -> "environment"
          operator -> operator.path
          true -> "built-in"
        end

      {:ok, %{policy: policy, mode_source: source}}
    else
      _ -> @error
    end
  end

  def policy(config), do: Map.get(config, :observability, @defaults)

  def runtime(config) do
    policy = policy(config)
    entries = Enum.filter(Map.get(config, :extensions, []), &sink?/1)

    with :ok <- validate(policy),
         true <- Enum.sort(Map.keys(policy)) == Enum.sort(Map.keys(@defaults)),
         true <- length(entries) <= 4,
         true <-
           Enum.all?(entries, fn entry ->
             Enum.count(~w(observe.local observe.export), &(&1 in entry.identity["capabilities"])) ==
               1
           end),
         true <- policy["mode"] == "off" or Enum.all?(entries, &permitted?(&1, policy)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def sink?(entry),
    do: Enum.any?(~w(observe.local observe.export), &(&1 in entry.identity["capabilities"]))

  def stage(entry),
    do:
      if("observe.export" in entry.identity["capabilities"],
        do: "observe.export",
        else: "observe.local"
      )

  defp permitted?(entry, %{"mode" => "local"}), do: stage(entry) == "observe.local"

  defp permitted?(entry, %{"mode" => "export"}),
    do: stage(entry) == "observe.local" or entry.identity["scope"] == "operator"

  defp integer(low, high), do: %{"type" => "integer", "minimum" => low, "maximum" => high}
end
