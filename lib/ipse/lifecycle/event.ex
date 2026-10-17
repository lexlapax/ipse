defmodule Ipse.Lifecycle.Event do
  @moduledoc "Typed host projections of journal facts; choosing a view is not a subscriber permission grant."
  alias Ipse.Lifecycle.Source
  alias Ipse.Extensions.{Manifest, Projection}

  @doc "Project one supported occurrence into metadata or its explicit private prompt view. No callbacks run."
  def project(source, record, view) do
    with true <- Source.matches?(source, record),
         {:ok, type, private_view, text, metrics, correlations} <- describe(record),
         {:ok, reference, data} <- data(source, view, private_view, text, metrics),
         envelope = %{
           "version" => 1,
           "data_version" => 1,
           "event_id" => source["event_id"],
           "type" => type,
           "source" => reference,
           "origin" => "host",
           "view" => view,
           "correlations" => correlations,
           "data" => data
         },
         :ok <- Ipse.Extension.validate(envelope) do
      {:ok, envelope}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_lifecycle_event}
    end
  rescue
    _ -> {:error, :invalid_lifecycle_event}
  end

  defp describe(%{"type" => "extension_prompt_received"} = record) do
    if Enum.sort(Map.keys(record)) == ~w(original original_sha256 type version) and
         record["version"] === 1 and text?(record["original"]) and
         record["original_sha256"] == Manifest.sha256(record["original"]) do
      {:ok, "prompt.received", "prompt.original", record["original"],
       %{"input_bytes" => byte_size(record["original"])}, %{}}
    else
      {:error, :invalid_lifecycle_event}
    end
  end

  defp describe(%{"type" => "message", "message" => %{"role" => "user", "content" => text}}) do
    if text?(text),
      do:
        {:ok, "prompt.expanded_committed", "prompt.expanded", text,
         %{"input_bytes" => byte_size(text)}, %{}},
      else: {:error, :invalid_lifecycle_event}
  end

  defp describe(%{"type" => "extension_transform_result", "stage" => "transform.prompt"} = record) do
    intent =
      record
      |> Map.drop(~w(input output result output_sha256))
      |> Map.put("type", "extension_transform_intent")

    with {:ok, expected} <- Projection.build(intent, record["input"], record["result"]),
         true <- expected == record do
      {:ok, "prompt.projection_committed", "prompt.projection", record["output"],
       %{
         "input_bytes" => byte_size(record["input"]),
         "output_bytes" => byte_size(record["output"])
       },
       %{
         "operation_id" => record["request_id"],
         "artifact_sha256" => record["identity"]["artifact_sha256"]
       }}
    else
      _ -> {:error, :invalid_lifecycle_event}
    end
  end

  defp describe(_), do: {:error, :unsupported_lifecycle_record}

  defp data(source, "metadata", _private, _text, metrics) do
    with {:ok, reference} <- Source.metadata(source) do
      {:ok, reference, metrics}
    end
  end

  defp data(source, view, view, text, _metrics) do
    case Ipse.Extension.validate(%{"text" => text}) do
      :ok -> {:ok, source, %{"text" => text}}
      _ -> {:error, :private_lifecycle_view_too_large}
    end
  end

  defp data(_, _, _, _, _), do: {:error, :lifecycle_view_unavailable}
  defp text?(value), do: is_binary(value) and String.valid?(value)
end
