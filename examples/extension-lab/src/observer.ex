defmodule IpseLab.Observer do
  @behaviour Ipse.Extension
  @description IpseLab.Spec.description(:observer)
  def describe, do: @description
  def init(options), do: {:ok, options}

  def handle("event.feed", payload, state) do
    if state["hang"], do: Process.sleep(:infinity)

    {:ok,
     %{
       "api_version" => 1,
       "kind" => "ack",
       "handle" => payload["handle"],
       "sequence" => payload["sequence"],
       "event_id" => payload["event"]["event_id"]
     }, state}
  end
end
