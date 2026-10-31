defmodule Ipse.KnowledgeCollectionJobProgressIsolationTest do
  use ExUnit.Case, async: false

  test "compact generation progress runs against independently loaded knowledge modules" do
    root = Path.expand("../../..", __DIR__)

    files =
      ~w(evidence documents documents/zip documents/docx documents/parser_stage documents/pdf store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged)
      |> Enum.map(&Path.join(root, "extensions/knowledge/src/#{&1}.ex"))

    script =
      "ExUnit.start(autorun: false); " <>
        "case Kernel.ParallelCompiler.compile(" <>
        inspect(files) <>
        ", return_diagnostics: true) do " <>
        "{:ok, _, []} -> :ok; " <>
        "{:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok; " <>
        "other -> raise inspect(other) end; " <>
        "Code.require_file(\"test/support/collection_job_progress.exs\"); " <>
        "result = ExUnit.run(); System.halt(if(result.failures == 0, do: 0, else: 1))"

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2"] ++ paths ++ ["-e", script],
        cd: root,
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "3 tests, 0 failures" or output =~ "3 passed"
  end
end
