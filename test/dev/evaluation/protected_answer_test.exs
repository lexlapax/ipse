defmodule Ipse.Development.Evaluation.ProtectedAnswerIsolationTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  false = :code.is_loaded(IpseKnowledge.Profiles)
  Code.require_file(__TEST_FILE__)
  result = ExUnit.run()
  if result.failures != 0 or result.skipped != 0 or result.excluded != 0 or result.total != 19,
    do: System.halt(1)
  IO.puts("PROTECTED_ANSWER_ISOLATED_PASS")
  """

  test "protected answer controls preserve the host domain boundary" do
    modules = [
      IpseKnowledge.Profiles,
      IpseKnowledge.Corpus,
      IpseKnowledge.Graph,
      IpseKnowledge.Research,
      IpseKnowledge.Adapters,
      IpseKnowledge.Evidence,
      IpseKnowledge.Store,
      IpseKnowledge.Store.State,
      IpseKnowledge.Store.MCPCAS
    ]

    before = Enum.map(modules, &:code.is_loaded/1)
    assert Enum.all?(before, &(&1 == false))

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    script =
      String.replace(
        @suite,
        "__TEST_FILE__",
        inspect(Path.expand("protected_answer_cases.exs", __DIR__))
      )

    args = ["--erl", "+S 2:2 +A 1"] ++ paths ++ ["-e", script]
    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "PROTECTED_ANSWER_ISOLATED_PASS"
    assert Enum.map(modules, &:code.is_loaded/1) == before
  end
end
