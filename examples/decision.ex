defmodule IpseDecisionExample.Create do
  @behaviour Ipse.Extension

  def describe do
    %{
      "sdk" => 1,
      "capabilities" => ~w(invoke.command host.actions host.decision),
      "exports" => %{
        "version" => 1,
        "tools" => [],
        "services" => [],
        "commands" => [
          %{
            "id" => "decide",
            "description" => "Request explicitly approved typed advice",
            "arguments_schema" => %{
              "type" => "object",
              "required" => ["request"],
              "additionalProperties" => false,
              "properties" => %{"request" => %{"type" => "object"}}
            },
            "result_schema" => %{
              "type" => "object",
              "required" => ~w(status value),
              "additionalProperties" => false,
              "properties" => %{
                "status" => %{"type" => "string", "enum" => ~w(ok failed denied)},
                "value" => %{"type" => "object"}
              }
            }
          }
        ]
      }
    }
  end

  def init(options), do: {:ok, options}

  def handle("invoke.command", payload, state),
    do:
      {:ok,
       %{"api_version" => 1, "kind" => "host_call", "request" => payload["arguments"]["request"]},
       state}

  def handle("host.actions", payload, state),
    do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
end
