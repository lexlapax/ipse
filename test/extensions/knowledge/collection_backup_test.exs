defmodule IpseKnowledge.CollectionBackupIsolationTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  false = :code.is_loaded(IpseKnowledge.Evidence)
  case Kernel.ParallelCompiler.compile(__SOURCE_FILES__, return_diagnostics: true) do
    {:ok, _, []} -> :ok
    {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
    other -> raise inspect(other)
  end
  Code.require_file(__CLASSIFIER_FILE__)
  Code.require_file(__TEST_FILE__)
  result = ExUnit.run()
  if result.failures != 0 or result.skipped != 0 or result.excluded != 0 or result.total != 24,
    do: System.halt(1)
  IO.puts("COLLECTION_BACKUP_ISOLATED_PASS")
  """

  test "backup controls do not load Knowledge modules into the host" do
    modules = [
      IpseKnowledge.Evidence,
      IpseKnowledge.Profiles,
      IpseKnowledge.Corpus,
      IpseKnowledge.Store.Collection,
      IpseKnowledge.Store.Collection.Index
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

    files =
      ~w(evidence adapters profiles documents documents/zip documents/docx documents/parser_stage documents/pdf
      store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation
      store/collection/directory store/collection/selected store/collection/job store/collection/reduction
      store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress corpus)
      |> Enum.map(&Path.expand("extensions/knowledge/src/#{&1}.ex"))

    script =
      @suite
      |> String.replace("__SOURCE_FILES__", inspect(files))
      |> String.replace(
        "__CLASSIFIER_FILE__",
        inspect(Path.expand("collection_completed_backup_cases.exs", __DIR__))
      )
      |> String.replace(
        "__TEST_FILE__",
        inspect(Path.expand("collection_backup_cases.exs", __DIR__))
      )

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 1:1 +A 1"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "COLLECTION_BACKUP_ISOLATED_PASS"
    assert Enum.map(modules, &:code.is_loaded/1) == before
  end
end
