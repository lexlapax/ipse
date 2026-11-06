defmodule Ipse.KnowledgeCollectionJobProgressIsolationTest do
  use ExUnit.Case, async: false

  @tag :exunit_output_contract
  test "compact generation progress runs against independently loaded knowledge modules" do
    root = Path.expand("../../..", __DIR__)

    files =
      ~w(evidence adapters profiles documents documents/zip documents/docx documents/parser_stage documents/pdf store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress)
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
        "result = ExUnit.run(); " <>
        "if Map.take(result, [:total, :failures, :skipped, :excluded]) != " <>
        "%{total: 4, failures: 0, skipped: 0, excluded: 0}, do: System.halt(1); " <>
        "IO.puts(\"COLLECTION_JOB_PROGRESS_CONTROL_PASS\")"

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

    assert Enum.count(
             String.split(output, ~r/\r?\n/),
             &(&1 === "COLLECTION_JOB_PROGRESS_CONTROL_PASS")
           ) === 1
  end
end
