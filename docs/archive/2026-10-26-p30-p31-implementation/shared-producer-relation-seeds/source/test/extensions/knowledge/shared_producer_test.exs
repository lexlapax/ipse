defmodule Ipse.SharedProducerFixtureTest do
  use ExUnit.Case, async: false

  test "bounded shared producer receipt flow and unknown controls in an isolated worker" do
    files =
      ~w(profiles evidence store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer adapters documents documents/zip documents/docx documents/parser_stage documents/pdf)
      |> Enum.map(&Path.expand("extensions/knowledge/src/" <> &1 <> ".ex"))

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    selection_only = System.get_env("IPSE_PRODUCER_SELECTION_ONLY") == "1"
    ranges_only = System.get_env("IPSE_PRODUCER_RANGES_ONLY") == "1"
    host_seed_only = System.get_env("IPSE_PRODUCER_HOST_SEED_ONLY") == "1"
    host_relation_seeds_only = System.get_env("IPSE_PRODUCER_HOST_RELATION_SEEDS_ONLY") == "1"

    prefix =
      cond do
        host_relation_seeds_only ->
          "ExUnit.start(exclude: [:test], include: [host_relation_seeds: true]); "

        host_seed_only ->
          "ExUnit.start(exclude: [:test], include: [host_seed: true]); "

        ranges_only ->
          "ExUnit.start(exclude: [:test], include: [range_claim: true]); "

        selection_only ->
          "ExUnit.start(exclude: [:test], include: [selection_api: true]); "

        true ->
          ""
      end

    script =
      prefix <>
        "case Kernel.ParallelCompiler.compile(" <>
        inspect(files) <>
        ",return_diagnostics: true) do {:ok,_,[]} -> :ok; {:ok,_,%{compile_warnings: [],runtime_warnings: []}} -> :ok; other -> raise inspect(other) end; Code.require_file(\"test/support/shared_producer_fixture.exs\")"

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output

    expected =
      cond do
        host_relation_seeds_only -> "Result: 2 passed"
        host_seed_only -> "Result: 1 passed"
        ranges_only -> "Result: 3 passed"
        selection_only -> "Result: 4 passed"
        true -> "Result: 19 passed"
      end

    assert output =~ expected
    IO.puts(output)
  end
end
