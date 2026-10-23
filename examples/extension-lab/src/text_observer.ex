defmodule IpseLab.TextObserver do
  @behaviour Ipse.Extension
  @description IpseLab.Spec.description(:text_observer)
  def describe, do: @description
  def init(options), do: {:ok, options}

  def handle("stream.text", payload, state) do
    frame = payload["frame"]
    true = Ipse.Session.TextStream.valid_frame?(frame)
    {:ok, metadata} = Ipse.Session.TextStream.project_frame(frame, "metadata")

    if frame["kind"] == "text" do
      {:ok, private} = Ipse.Session.TextStream.project_frame(frame, "text.visible")
      true = metadata["event_id"] == private["event_id"]
      true = private["data"]["text"] == "Synthetic answer"
    end

    {:ok,
     %{
       "api_version" => 1,
       "kind" => "ack",
       "handle" => payload["handle"],
       "sequence" => Map.get(frame, "sequence", 0)
     }, state}
  end
end
