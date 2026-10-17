defmodule Ipse.Observability.Event do
  @moduledoc "Diagnostic delivery wraps shared metadata facts without replacing their identity."
  def build(source, record, sequence, elapsed) do
    with {:ok, event} <- Ipse.Lifecycle.Event.project(source, record, "metadata"),
         group = event["type"] |> String.split(".") |> hd(),
         group =
           (cond do
              String.contains?(event["type"], ".compaction_") -> "compaction"
              group in ["assistant", "answer"] -> "stream"
              group == "wait" -> "session"
              true -> group
            end),
         true <- group in Ipse.Observability.Config.groups() do
      {:ok,
       %{
         "version" => 1,
         "sequence" => sequence,
         "elapsed_ms" => elapsed,
         "group" => group,
         "level" => level(event),
         "event" => event
       }}
    else
      _ -> {:error, :unsupported_observation}
    end
  end

  def valid?(value) do
    is_map(value) and
      Enum.sort(Map.keys(value)) == ~w(elapsed_ms event group level sequence version) and
      value["version"] === 1 and uint?(value["sequence"]) and value["sequence"] > 0 and
      uint?(value["elapsed_ms"]) and value["group"] in Ipse.Observability.Config.groups() and
      value["level"] in ~w(info error debug) and
      Ipse.Lifecycle.Event.valid_metadata?(value["event"]) and
      Ipse.Extension.validate(value) == :ok
  rescue
    _ -> false
  end

  defp level(event) do
    cond do
      event["data"]["outcome"] in ~w(failed unknown) or
        event["data"]["status"] in ~w(error failed unknown) or
          String.ends_with?(event["type"], ".compaction_failed") ->
        "error"

      event["type"] == "model.usage_observed" ->
        "debug"

      true ->
        "info"
    end
  end

  defp uint?(v), do: is_integer(v) and v in 0..9_007_199_254_740_991
end
