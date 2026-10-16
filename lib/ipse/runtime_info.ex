defmodule Ipse.RuntimeInfo do
  @moduledoc "Allowlisted runtime facts shared by the terminal and model context."

  def snapshot(config, reported_model \\ nil, historical_model \\ nil) do
    %{
      application: "Ipse",
      version: Application.spec(:ipse, :vsn) |> to_string(),
      provider: provider_name(config[:provider]),
      requested_model: model_name(config[:model]),
      reported_model: model_name(reported_model),
      historical_reported_model: model_name(historical_model),
      execution:
        config
        |> Map.get(:execution, %{})
        |> then(&Map.take(&1 || %{}, [:id, :role, :reasoning_effort]))
    }
  end

  def format(info) do
    """
    Ipse version: #{info.version}
    Configured provider: #{info.provider || "unavailable"}
    Requested model: #{info.requested_model || "unavailable"}
    Execution profile: #{inspect(Map.get(info, :execution, %{}))}
    Last response model (current run): #{info.reported_model || "unavailable"}
    Saved session's last response model: #{info.historical_reported_model || "unavailable"}
    Model identifiers may be aliases; the exact backend revision is unknown.
    """
  end

  def model_name(value) when is_binary(value) and byte_size(value) in 1..200 do
    if Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._:\/@+\-]*\z/, value), do: value
  end

  def model_name(_), do: nil

  defp provider_name(value) when value in [:chatgpt, :openai, :ollama, :anthropic, :demo],
    do: Atom.to_string(value)

  defp provider_name(_), do: nil
end
