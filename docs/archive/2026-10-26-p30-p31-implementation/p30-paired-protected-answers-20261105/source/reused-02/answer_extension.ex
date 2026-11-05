defmodule Ipse.Test.PairedAnswerExtension do
  @behaviour Ipse.Extension
  def describe do
    %{
      "sdk" => 2,
      "capabilities" => ~w(invoke.command invoke.service invoke.result.pages host.actions host.model),
      "exports" => %{
        "version" => 1, "tools" => [],
        "commands" => [%{
          "id" => "metadata", "description" => "Describe synthetic protocol scope without inference",
          "arguments_schema" => %{"type" => "object", "properties" => %{}, "required" => [], "additionalProperties" => false},
          "result_schema" => %{"type" => "object", "required" => ["scope", "inference"], "additionalProperties" => false,
            "properties" => %{"scope" => %{"type" => "string", "enum" => ["synthetic_protocol_only"]}, "inference" => %{"type" => "boolean", "enum" => [false]}}}
        }],
        "services" => [%{
          "id" => "answer_context", "description" => "Synthetic protected answer protocol",
          "arguments_schema" => %{"type" => "object", "required" => ["request"], "additionalProperties" => false,
            "properties" => %{"request" => %{"type" => "object"}}},
          "result_schema" => %{"type" => "object"}
        }]
      }
    }
  end
  def init(options), do: {:ok, options}
  def handle("invoke.command", %{"id" => "metadata", "arguments" => %{}}, state),
    do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"scope" => "synthetic_protocol_only", "inference" => false}}, state}
  def handle("invoke.service", %{"id" => "answer_context", "arguments" => %{"request" => request}}, state),
    do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
  def handle("host.actions", %{"outcome" => outcome}, state),
    do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => outcome}, state}
end
