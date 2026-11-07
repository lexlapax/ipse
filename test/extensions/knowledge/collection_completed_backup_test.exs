defmodule IpseKnowledge.CollectionCompletedBackupIsolationTest do
  use ExUnit.Case, async: false

  test "completed document-set validation stays in a no-App isolated child" do
    modules = [
      IpseKnowledge.Evidence,
      IpseKnowledge.Store.Collection,
      IpseKnowledge.Store.Collection.Projection,
      IpseKnowledge.Store.Collection.Index
    ]

    before = Enum.map(modules, &:code.is_loaded/1)
    assert Enum.all?(before, &(&1 === false))

    files =
      ~w(evidence adapters profiles documents documents/zip documents/docx documents/parser_stage documents/pdf
      store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation
      store/collection/directory store/collection/selected store/collection/job store/collection/reduction
      store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress)
      |> Enum.map(&Path.expand("extensions/knowledge/src/#{&1}.ex"))

    cases = Path.expand("collection_completed_backup_cases.exs", __DIR__)
    protocol = Path.expand("../../support/collection_protocol.exs", __DIR__)
    time_controls = Path.expand("../../support/collection_time.exs", __DIR__)

    script = """
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    case Kernel.ParallelCompiler.compile(#{inspect(files)}, return_diagnostics: true) do
      {:ok, _, []} -> :ok
      {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
      other -> raise inspect(other)
    end
    ExUnit.start(autorun: false)
    Code.require_file(#{inspect(protocol)})
    Code.require_file(#{inspect(cases)})
    Code.require_file(#{inspect(time_controls)})
    result = ExUnit.run()
    0 = result.failures
    0 = result.skipped
    0 = result.excluded
    19 = result.total
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    IO.puts("COMPLETED_BACKUP_ISOLATED_PASS")
    IO.puts("COLLECTION_TIME_ISOLATED_PASS")
    """

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 === ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 1:1 +A 1"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status === 0, output
    assert output =~ "COMPLETED_BACKUP_ISOLATED_PASS"

    assert Enum.count(String.split(output, ~r/\r?\n/), &(&1 === "COLLECTION_TIME_ISOLATED_PASS")) ==
             1

    assert Enum.map(modules, &:code.is_loaded/1) === before
  end
end
