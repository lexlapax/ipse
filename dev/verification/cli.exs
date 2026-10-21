Code.require_file("scenarios.exs", __DIR__)
Code.require_file("runtime.exs", __DIR__)
Code.require_file("package.exs", __DIR__)

defmodule Ipse.Development.Verification.CLI do
  @moduledoc "Closed command grammar for source and installed verification scenarios."
  alias Ipse.Development.Verification.{Package, Runtime, Scenarios}

  def main(argv) do
    {scenario, options} = parse!(argv)

    report =
      case scenario do
        "package" -> Runtime.run(scenario, options, &Package.run/2)
        _ -> Runtime.run(scenario, options)
      end

    IO.puts(:json.encode(report))
  end

  def parse!([mode, scenario | argv]) when mode in ~w(source installed) do
    true = scenario in Scenarios.names()
    false = mode == "source" and scenario == "package"

    {options, [], []} =
      OptionParser.parse(argv,
        strict: [
          sdk: [:string, :keep],
          archive: [:string, :keep],
          input: [:string, :keep],
          output: [:string, :keep],
          repository: [:string, :keep],
          selection: [:string, :keep]
        ]
      )

    true = length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options)))
    required = if mode == "source", do: :sdk, else: :archive
    forbidden = if mode == "source", do: :archive, else: :sdk
    true = Keyword.has_key?(options, required) and Keyword.has_key?(options, :input)
    false = Keyword.has_key?(options, forbidden)
    true = Keyword.has_key?(options, :output) == Scenarios.output_required?(scenario)
    true = Keyword.has_key?(options, :repository) == Scenarios.repository_required?(scenario)
    :ok = Scenarios.selection!(scenario, Keyword.get(options, :selection, "default"))
    {scenario, options}
  end

  def parse!(_),
    do:
      raise(
        "usage: elixir scripts/verify.exs source|installed SCENARIO --sdk EBIN|--archive ARCHIVE --input PATH [--selection MODE] [--output EVIDENCE] [--repository CLEAN_REPO]"
      )
end
