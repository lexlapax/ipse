defmodule IpseLab.Metadata do
  @behaviour Ipse.Extension
  @description IpseLab.Spec.description(:metadata)
  def describe, do: @description
  def init(options), do: {:ok, options}

  def handle("event.notify", payload, state) do
    event = payload["event"]
    true = event["view"] == "metadata"
    %{"input_bytes" => bytes} = event["data"]
    true = is_integer(bytes)
    true = Map.keys(event["data"]) == ["input_bytes"]
    false = Map.has_key?(event["source"], "record_sha256")

    {:ok,
     %{
       "api_version" => 1,
       "kind" => "ack",
       "delivery_id" => payload["delivery_id"],
       "event_id" => event["event_id"]
     }, state}
  end
end
