defmodule Ipse.MixProject do
  use Mix.Project

  def project do
    [
      app: :ipse,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: Ipse.CLI],
      deps: [{:jason, github: "michalmuskala/jason", tag: "v1.4.4"}],
      releases: [ipse: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [extra_applications: [:logger, :inets, :ssl], mod: {Ipse.Application, []}]
  end
end
