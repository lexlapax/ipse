defmodule Runespell.MixProject do
  use Mix.Project

  def project do
    [
      app: :runespell,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Runespell.CLI],
      deps: [{:jason, github: "michalmuskala/jason", tag: "v1.4.4"}],
      releases: [runespell: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl], mod: {Runespell.Application, []}]
  end
end
