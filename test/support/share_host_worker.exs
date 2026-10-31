defmodule IpseTest.ShareHostWorker do
  @behaviour Ipse.Extension
  @caps ~w(invoke.command host.actions host.context)
  @descriptor %{
    "id" => "share",
    "description" => "Synthetic Session share action",
    "arguments_schema" => %{"type" => "object"},
    "result_schema" => %{"type" => "object"}
  }
  @exports %{"version" => 1, "tools" => [], "services" => [], "commands" => [@descriptor]}
  def describe, do: %{"sdk" => 1, "capabilities" => @caps, "exports" => @exports}
  def init(options), do: {:ok, options}

  def handle("invoke.command", _, state),
    do:
      {:ok,
       %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "context.available"}},
       state}

  def handle("host.actions", _, state),
    do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"done" => true}}, state}
end
