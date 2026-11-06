defmodule Ipse.Extension.CollectionDocumentSourceUseIsolationTest do
  use ExUnit.Case, async: false

  @tag timeout: 120_000
  test "document source controls do not load the Knowledge domain into the host" do
    before = :code.is_loaded(IpseKnowledge.Evidence)

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++ paths ++ ["test/support/collection_document_source_use_entry.exs"],
        stderr_to_stdout: true
      )

    assert status == 0, output

    assert Enum.count(String.split(output, "\n"), &(&1 == "DOCUMENT_SOURCE_USE_CONTROL_PASS 15")) ==
             1

    assert [measurement] = Regex.run(~r/SELECTION_SOURCE_MODEL \{[^\n]+\}/, output)
    IO.puts(measurement)
    assert :code.is_loaded(IpseKnowledge.Evidence) == before
  end

  @tag :native_sandbox
  @tag :selection_native_capacity
  @tag timeout: 600_000
  test "populated native storage authenticates all 1000 small source records" do
    native_capacity(:source_selection_capacity_native)
  end

  @tag :native_sandbox
  @tag :selection_native_fulltext
  @tag timeout: 600_000
  test "populated native storage authenticates 1000 sources with 20,480,000 text bytes" do
    native_capacity(:source_selection_fulltext_native)
  end

  @tag :native_sandbox
  @tag :selection_native_switch
  @tag timeout: 600_000
  test "populated native selection fences changed generations before publication" do
    native_capacity(:source_selection_switch_native)
  end

  @tag :native_sandbox
  @tag :selection_native_rebuild
  @tag timeout: 600_000
  test "populated native selection preserves the previous root on a generation race" do
    native_capacity(:source_selection_rebuild_native)
  end

  defp native_capacity(tag) do
    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    script =
      "ExUnit.start(autorun: false, exclude: [:test], include: [{#{inspect(tag)}, true}]); " <>
        "{:ok, _} = Application.ensure_all_started(:ipse); " <>
        "Code.require_file(\"test/support/collection_document_source_use_suite.exs\"); " <>
        "result = ExUnit.run(); if result.failures != 0, do: System.halt(1)"

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2"] ++ paths ++ ["-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert [measurement] = Regex.run(~r/NATIVE_SELECTION_CAPACITY \{[^\n]+\}/, output)
    IO.puts(measurement)
  end
end
