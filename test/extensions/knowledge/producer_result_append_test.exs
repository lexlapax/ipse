defmodule IpseKnowledge.ProducerResultAppendIsolationTest do
  use ExUnit.Case, async: false

  test "selected-result group append uses isolated authentic controllers without App or inference services" do
    files =
      ~w(evidence adapters profiles documents documents/zip documents/docx documents/parser_stage documents/pdf
      store/collection store/collection/index store/collection/projection store/collection/generation
      store/collection/directory store/collection/selected store/collection/job store/collection/reduction
      store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress)
      |> Enum.map(&Path.expand("extensions/knowledge/src/#{&1}.ex"))

    cases = Path.expand("producer_result_append_cases.exs", __DIR__)

    script = """
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    case Kernel.ParallelCompiler.compile(#{inspect(files)}, return_diagnostics: true) do
      {:ok, _, []} -> :ok
      {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
      other -> raise inspect(other)
    end
    ExUnit.start(autorun: false)
    Code.require_file("dev/knowledge/collection_recipe_model.ex")
    Code.require_file(#{inspect(cases)})
    result = ExUnit.run()
    %{total: 7, failures: 0, skipped: 0, excluded: 0} = Map.take(result, [:total, :failures, :skipped, :excluded])
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    IO.puts("PRODUCER_RESULT_APPEND_PASS")
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

    assert Enum.count(String.split(output, ~r/\r?\n/), &(&1 === "PRODUCER_RESULT_APPEND_PASS")) ===
             1
  end
end
