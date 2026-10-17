defmodule IpseLab.ToolObserver do
  @behaviour Ipse.Extension
  @description IpseLab.Spec.description(:tool_observer)
  def describe, do: @description
  def init(options), do: {:ok, options}

  def handle("event.feed", payload, state) do
    event = payload["event"]

    case event["view"] do
      "tool.input" ->
        true = Enum.sort(Map.keys(event["data"])) == ~w(arguments_json name)
        true = is_binary(event["data"]["arguments_json"])

      "tool.result" ->
        true = Map.keys(event["data"]) == ["text"]
        true = is_binary(event["data"]["text"])

      "metadata" ->
        false = Map.has_key?(event["source"], "record_sha256")

        true =
          Enum.all?(
            Map.keys(event["data"]),
            &(&1 in ~w(input_bytes output_bytes status approval duration_ms))
          )
    end

    {:ok,
     %{
       "api_version" => 1,
       "kind" => "ack",
       "handle" => payload["handle"],
       "sequence" => payload["sequence"],
       "event_id" => event["event_id"]
     }, state}
  end
end
