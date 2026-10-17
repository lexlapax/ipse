defmodule Ipse.Lifecycle.Ephemeral do
  @moduledoc "Private v2 text-frame projections; live identities are not journal positions or permission grants."
  @normal ~w(version kind session_id generation stream_id request_id subscription_id sequence source)
  @closed ~w(version kind subscription_id session_id complete reason unsent_bytes unsent_frames pending_bytes unacknowledged_bytes source)
  @reasons ~w(unsubscribed consumer_down owner_down invalid_chunk backpressure_timeout control_queue_full position_limit)
  @types %{
    "start" => "text.started",
    "text" => "text.delta",
    "end" => "text.finished",
    "closed" => "text.subscription_closed"
  }
  @max 9_007_199_254_740_991

  def source(epoch, frame, offset) do
    base = %{
      "version" => 1,
      "kind" => "ephemeral",
      "session_id" => frame["session_id"],
      "epoch_id" => epoch
    }

    body =
      if frame["kind"] == "closed" do
        Map.merge(base, %{
          "scope" => "subscription",
          "subscription_id" => frame["subscription_id"]
        })
      else
        Map.merge(base, %{
          "scope" => "stream",
          "stream_id" => frame["stream_id"],
          "request_id" => frame["request_id"],
          "start_byte" => offset,
          "end_byte" => offset + byte_size(frame["text"] || "")
        })
      end

    Map.put(body, "event_id", identity(body, frame["kind"]))
  end

  def project(frame, view) do
    with true <- valid_frame?(frame),
         {:ok, data} <- data(frame, view),
         event = %{
           "version" => 1,
           "data_version" => 1,
           "event_id" => frame["source"]["event_id"],
           "type" => @types[frame["kind"]],
           "source" => frame["source"],
           "origin" => "host",
           "view" => view,
           "correlations" =>
             if(frame["kind"] == "closed", do: %{}, else: Map.take(frame, ["request_id"])),
           "data" => data
         },
         :ok <- Ipse.Extension.validate(event) do
      {:ok, event}
    else
      _ -> {:error, :invalid_ephemeral_event}
    end
  rescue
    _ -> {:error, :invalid_ephemeral_event}
  end

  def valid_frame?(frame) do
    source = frame["source"]

    frame["version"] === 2 and id?(frame["session_id"]) and id?(frame["subscription_id"]) and
      source["session_id"] == frame["session_id"] and valid_source?(source, frame["kind"]) and
      fields?(frame) and Ipse.Extension.validate(frame) == :ok
  rescue
    _ -> false
  end

  defp fields?(%{"kind" => "closed"} = f) do
    keys?(f, @closed) and f["complete"] === false and f["reason"] in @reasons and
      f["source"]["subscription_id"] == f["subscription_id"] and
      Enum.all?(~w(unsent_bytes unsent_frames pending_bytes unacknowledged_bytes), &uint?(f[&1]))
  end

  defp fields?(f) do
    extra =
      case f["kind"] do
        "start" -> []
        "text" -> ["text"]
        "end" -> ~w(outcome complete)
        _ -> ["unsupported"]
      end

    keys?(f, @normal ++ extra) and f["generation"] === 1 and id?(f["request_id"]) and
      id?(f["stream_id"]) and uint?(f["sequence"]) and f["sequence"] > 0 and
      f["stream_id"] == f["source"]["stream_id"] and f["request_id"] == f["source"]["request_id"] and
      position?(f)
  end

  defp position?(%{"kind" => "start", "source" => s}),
    do: s["start_byte"] == 0 and s["end_byte"] == 0

  defp position?(%{"kind" => "text", "source" => s, "text" => t}) do
    is_binary(t) and String.valid?(t) and byte_size(t) in 1..2048 and
      s["end_byte"] - s["start_byte"] == byte_size(t)
  end

  defp position?(%{"kind" => "end", "source" => s} = f) do
    s["start_byte"] == s["end_byte"] and f["outcome"] in ~w(completed failed cancelled unknown) and
      f["complete"] === (f["outcome"] == "completed")
  end

  defp position?(_), do: false

  defp valid_source?(s, kind) do
    s["version"] === 1 and s["kind"] == "ephemeral" and id?(s["session_id"]) and
      id?(s["epoch_id"]) and
      source_fields?(s, kind) and s["event_id"] == identity(Map.delete(s, "event_id"), kind)
  end

  defp source_fields?(s, "closed") do
    keys?(s, ~w(version kind session_id epoch_id scope subscription_id event_id)) and
      s["scope"] == "subscription" and id?(s["subscription_id"])
  end

  defp source_fields?(s, kind) when kind in ~w(start text end) do
    keys?(
      s,
      ~w(version kind session_id epoch_id scope stream_id request_id start_byte end_byte event_id)
    ) and
      s["scope"] == "stream" and id?(s["stream_id"]) and id?(s["request_id"]) and
      uint?(s["start_byte"]) and
      uint?(s["end_byte"]) and s["end_byte"] >= s["start_byte"]
  end

  defp source_fields?(_, _), do: false

  defp data(%{"kind" => "text", "text" => text}, "text.visible"), do: {:ok, %{"text" => text}}

  defp data(%{"kind" => "text", "text" => text}, "metadata"),
    do: {:ok, %{"output_bytes" => byte_size(text)}}

  defp data(%{"kind" => "start"}, "metadata"), do: {:ok, %{}}
  defp data(%{"kind" => "end"} = f, "metadata"), do: {:ok, Map.take(f, ~w(outcome complete))}

  defp data(%{"kind" => "closed"} = f, "metadata"),
    do:
      {:ok,
       Map.take(
         f,
         ~w(complete reason unsent_bytes unsent_frames pending_bytes unacknowledged_bytes)
       )}

  defp data(_, _), do: {:error, :unsupported_view}

  defp identity(body, kind),
    do:
      Ipse.Compaction.digest([
        %{"domain" => "ipse.ephemeral.text.v1", "kind" => kind, "source" => body}
      ])
      |> binary_part(0, 32)

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp uint?(v), do: is_integer(v) and v in 0..@max
end
