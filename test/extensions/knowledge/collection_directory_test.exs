defmodule Ipse.KnowledgeCollectionDirectoryTest do
  use ExUnit.Case, async: false
  @tag :shared_directory_codec
  test "two manifest pages bind exact catalog heads and selected groups without projection payloads" do
    result = run_fixture("test/support/collection_directory.exs")
    assert result["groups"] == 17 and result["manifest_pages"] == 2
    assert result["selected_headers"] == 2 and result["native_operations"] == 0
    refute result["publication_attempted"]
    IO.puts("SHARED_DIRECTORY_CODEC " <> Jason.encode!(result))
  end

  @tag :generation_job_prerequisites
  test "edited append checkpoints cannot skip missing immutable units or adopt a later commit epoch" do
    result = run_fixture("test/support/generation_job_prerequisites.exs")
    assert result["edited_metadata_positions"] == 2
    assert result["immutable_units"] == 5
    assert result["final_checks"] == 5
    assert result["pinned_commit_generation"] == 500
    assert result["native_operations"] == 0
    IO.puts("GENERATION_JOB_PREREQUISITES " <> Jason.encode!(result))
  end

  @tag :generation_reduction
  test "streamed manifests and bounded entity merge reproduce the canonical directory" do
    result = run_fixture("test/support/generation_reduction.exs")
    assert result["manifest_batches"] == 2
    assert result["entity_pages"] == 5
    assert result["canonical_equal"]
    assert result["native_operations"] == 0
    IO.puts("GENERATION_REDUCTION " <> Jason.encode!(result))
  end

  @tag :generation_empty_runs
  test "empty and mixed entity runs reduce to the canonical directory across batches" do
    result = run_fixture("test/support/generation_empty_runs.exs")
    assert result["cases"] == 6 and result["groups"] == 17
    assert result["native_operations"] == 0
  end

  @tag :generation_finalization
  test "durable reduction phases retain the old root until a pinned three-stage selection" do
    result = run_fixture("test/support/generation_finalization.exs")
    assert result["phases"] == 10
    assert result["selection_stages"] == 3
    assert result["canonical_equal"]
    assert result["native_operations"] == 0
    IO.puts("GENERATION_FINALIZATION " <> Jason.encode!(result))
  end

  @tag :metadata_transport_geometry
  test "escaped metadata preserves exact packet bytes and refuses the measured digest read overflow" do
    result = run_fixture("test/support/metadata_transport_geometry.exs")
    assert result["entities"] == 5000
    assert result["pages"] == 79
    assert result["escaped_object_reads"] > 512
    assert result["job_budget_refused"]
    assert result["write_parts"] <= 10
    assert result["native_operations"] == 0
    IO.puts("METADATA_TRANSPORT_GEOMETRY " <> Jason.encode!(result))
  end

  @tag :generation_paged
  test "explicit root2 finalization preserves v1 and verifies each ordered entity page durably" do
    result = run_fixture("test/support/generation_paged.exs")
    assert result["phases"] == 22
    assert result["selection_stages"] == 3
    assert result["canonical_equal"]
    assert result["root_version"] == 2
    assert result["native_operations"] == 0
    IO.puts("GENERATION_PAGED " <> Jason.encode!(result))
  end

  @tag :generation_paged_budget
  test "complete maximum-width root2 selection stays within native and SDK invocation limits" do
    result = run_fixture("test/support/generation_paged_budget.exs")
    assert result["references"] == 165
    assert result["proof_reads"] == 330
    assert result["reads"] <= 512
    assert result["effects"] <= 16
    assert result["native_operations"] == 0
    IO.puts("GENERATION_PAGED_BUDGET " <> Jason.encode!(result))
  end

  @tag :generation_paged_phase_budgets
  @tag timeout: 120_000
  test "maximum metadata manifest and eight-run merge steps retain complete invocation budgets" do
    result = run_fixture("test/support/generation_paged_phases.exs")
    assert result["manifest"]["maximum_reads"] <= 512
    assert result["merge"]["maximum_reads"] <= 512
    assert result["manifest"]["maximum_effects"] <= 16
    assert result["merge"]["maximum_effects"] <= 16
    IO.puts("GENERATION_PAGED_PHASE_BUDGETS " <> Jason.encode!(result))
  end

  @tag :generation_paged_catalog
  test "all125manifest groups bind1000ordered unique source heads before digest progress" do
    result = run_fixture("test/support/generation_paged_catalog.exs")
    assert result["sources"] == 1000 and result["groups"] == 125
    assert result["catalog_pages"] == 63
    assert result["negative_effects"] == 0
    IO.puts("GENERATION_PAGED_CATALOG " <> Jason.encode!(result))
  end

  defp run_fixture(fixture) do
    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    files =
      ~w(evidence documents documents/zip documents/docx documents/parser_stage documents/pdf store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged)
      |> Enum.map(&Path.expand("extensions/knowledge/src/#{&1}.ex"))

    compiler =
      case System.get_env("IPSE_COLLECTION_DIRECTORY_BEAM_DIR") do
        nil ->
          "Kernel.ParallelCompiler.compile(" <> inspect(files) <> ", return_diagnostics: true)"

        path ->
          path = Path.expand(Path.join(path, Path.basename(fixture, ".exs")))
          assert String.starts_with?(path, Path.expand("_build") <> "/")
          refute File.exists?(path)
          File.mkdir_p!(path)

          "Kernel.ParallelCompiler.compile_to_path(" <>
            inspect(files) <> ", " <> inspect(path) <> ", return_diagnostics: true)"
      end

    script =
      "case " <>
        compiler <>
        " do {:ok, _, []} -> :ok; {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok; other -> raise inspect(other) end; Code.require_file(" <>
        inspect(fixture) <> ")"

    {output, 0} =
      System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    {:ok, result} = Jason.decode(output)
    result
  end
end
