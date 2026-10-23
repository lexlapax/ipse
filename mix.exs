defmodule Ipse.MixProject do
  use Mix.Project

  def project do
    [
      app: :ipse,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib", "extensions/bundled"],
      start_permanent: Mix.env() == :prod,
      test_ignore_filters: [~r/^test\/support\/mcp_(catalog_)?server\.exs$/],
      escript: [main_module: Ipse.CLI],
      deps: [
        {:jason, github: "michalmuskala/jason", tag: "v1.4.4", override: true},
        {:mcp_elixir_sdk, "== 1.1.0"},
        {:jsonschex, "== 0.10.0"},
        {:req, "== 0.7.5"},
        {:plug, "== 1.20.3"}
      ],
      releases: [ipse: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl], mod: {Ipse.Application, []}]
  end
end
