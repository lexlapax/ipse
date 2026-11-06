defmodule Ipse.SharedProducerFixtureTest do
  use ExUnit.Case, async: false

  test "bounded shared producer receipt flow and unknown controls in an isolated worker" do
    files =
      ~w(profiles evidence adapters store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress documents documents/zip documents/docx documents/parser_stage documents/pdf)
      |> Enum.map(&Path.expand("extensions/knowledge/src/" <> &1 <> ".ex"))

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    selection_only = System.get_env("IPSE_PRODUCER_SELECTION_ONLY") == "1"
    ranges_only = System.get_env("IPSE_PRODUCER_RANGES_ONLY") == "1"
    host_seed_only = System.get_env("IPSE_PRODUCER_HOST_SEED_ONLY") == "1"
    host_relation_seeds_only = System.get_env("IPSE_PRODUCER_HOST_RELATION_SEEDS_ONLY") == "1"
    guard_only = System.get_env("IPSE_PRODUCER_GUARD_ONLY")
    public_only = System.get_env("IPSE_PRODUCER_PUBLIC_ONLY") == "1"

    expected =
      cond do
        public_only -> 1
        guard_only == "adapter" -> 2
        guard_only == "flow" -> 1
        host_relation_seeds_only -> 2
        host_seed_only -> 1
        ranges_only -> 3
        selection_only -> 4
        true -> 22
      end

    prefix =
      cond do
        public_only ->
          "ExUnit.start(autorun: false, exclude: [:test], include: [public_entry: true]); "

        guard_only == "adapter" ->
          "ExUnit.start(autorun: false, exclude: [:test], include: [guard_adapter: true]); "

        guard_only == "flow" ->
          "ExUnit.start(autorun: false, exclude: [:test], include: [guard_flow: true]); "

        host_relation_seeds_only ->
          "ExUnit.start(autorun: false, exclude: [:test], include: [host_relation_seeds: true]); "

        host_seed_only ->
          "ExUnit.start(autorun: false, exclude: [:test], include: [host_seed: true]); "

        ranges_only ->
          "ExUnit.start(autorun: false, exclude: [:test], include: [range_claim: true]); "

        selection_only ->
          "ExUnit.start(autorun: false, exclude: [:test], include: [selection_api: true]); "

        true ->
          ""
      end

    script =
      prefix <>
        "case Kernel.ParallelCompiler.compile(" <>
        inspect(files) <>
        ",return_diagnostics: true) do {:ok,_,[]} -> :ok; {:ok,_,%{compile_warnings: [],runtime_warnings: []}} -> :ok; other -> raise inspect(other) end; Code.require_file(\"test/support/shared_producer_fixture.exs\"); " <>
        "result = ExUnit.run(); " <>
        "if Map.take(result, [:total, :failures, :excluded, :skipped]) != " <>
        "%{total: 22, failures: 0, excluded: #{22 - expected}, skipped: 0}, do: System.halt(1); " <>
        "IO.puts(\"SHARED_PRODUCER_CONTROL_PASS #{expected}\")"

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output

    assert Enum.count(
             String.split(output, "\n"),
             &(&1 == "SHARED_PRODUCER_CONTROL_PASS #{expected}")
           ) == 1

    IO.puts(output)
  end
end
