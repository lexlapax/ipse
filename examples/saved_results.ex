defmodule IpseSavedResultsExample.Worker do
  @behaviour Ipse.Extension
  @on_load :loaded

  def loaded do
    File.write!(Path.expand("../../worker-loads.log", File.cwd!()), System.pid() <> "\n", [
      :append
    ])

    :ok
  end

  def describe do
    %{
      "sdk" => 2,
      "capabilities" => ~w(invoke.command invoke.result.pages),
      "exports" => %{
        "version" => 1,
        "tools" => [],
        "services" => [],
        "commands" => [
          %{
            "id" => "publish",
            "description" => "Publish a complete four-MiB synthetic result",
            "arguments_schema" => %{"type" => "object", "additionalProperties" => false},
            "result_schema" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" => ~w(items pad),
              "properties" => %{
                "items" => %{"type" => "array", "items" => %{"type" => "string"}},
                "pad" => %{"type" => "string"}
              }
            }
          }
        ]
      }
    }
  end

  def init(options), do: {:ok, options}

  def handle("invoke.command", payload, options) do
    File.write!(options["callback_marker"], payload["invocation_id"] <> "\n", [:append])
    initial = %{"items" => List.duplicate(String.duplicate("x", 8192), 511), "pad" => ""}
    remaining = 4 * 1024 * 1024 - byte_size(Jason.encode!(initial))
    value = Map.put(initial, "pad", String.duplicate("y", remaining))
    {:ok, output} = Ipse.Extension.ResultPublication.prepare(value)
    {:ok, output, options}
  end
end
