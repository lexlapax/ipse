defmodule Ipse.CLI.Models do
  @moduledoc "Explicit read-only model metadata inspection; never changes conversation configuration."
  alias Ipse.CLI.Terminal
  @options ~w(provider model base_url timeout_ms json)a

  def inspect(opts) do
    with true <- Enum.all?(Keyword.keys(opts), &(&1 in @options)),
         true <- opts[:provider] == "ollama",
         {:ok, report} <-
           Ipse.Provider.Ollama.Models.read(
             opts[:base_url],
             opts[:model],
             opts[:timeout_ms] || 10_000
           ) do
      if opts[:json] do
        Terminal.puts(Jason.encode!(report, pretty: true))
      else
        Terminal.puts(
          "Ollama #{report["runtime_version"]} at #{report["origin"]}; model #{report["model"]}."
        )

        Terminal.puts(
          "Installed manifest: #{report["manifest_sha256"]}; #{report["artifact_bytes"]} bytes."
        )

        if report["loaded"],
          do:
            Terminal.puts(
              "Loaded context reported by service: #{report["loaded"]["context_length"]}."
            ),
          else: Terminal.puts("Model is not loaded; effective context is unverified.")

        Terminal.puts(
          "Metadata is a cooperative service claim, not request attestation or proof of offline execution."
        )

        Terminal.puts("No inference, download, activation or configuration change was requested.")
      end

      0
    else
      error ->
        code =
          case error do
            {:error, reason} when is_atom(reason) -> Atom.to_string(reason)
            _ -> "invalid_ollama_inspection"
          end

        if opts[:json],
          do: Terminal.puts(:stderr, Jason.encode!(%{"version" => 1, "error" => code})),
          else:
            Terminal.puts(
              :stderr,
              "Model inspection refused (#{code}). Select --provider ollama, --model NAME and an explicit loopback --base-url; inspect the service before retrying. No model or configuration was changed."
            )

        1
    end
  end
end
