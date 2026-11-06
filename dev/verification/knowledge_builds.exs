defmodule Ipse.Development.Verification.KnowledgeBuilds do
  @moduledoc false

  @exports %{
    "corpus" => %{commands: ~w(source query index), tools: ~w(query)},
    "research" => %{commands: ~w(investigate ledger), tools: ~w(investigate)},
    "graph" => %{commands: ~w(source extract identity query), tools: ~w(query capture)}
  }

  def expected(package), do: Map.fetch!(@exports, package)

  def exports_match?(package, exports) do
    expected = expected(package)

    Enum.all?([:commands, :tools], fn group ->
      ids = Enum.map(exports[Atom.to_string(group)], & &1["id"])
      Enum.sort(ids) == Enum.sort(expected[group])
    end)
  end

  def catalog_match?(package, catalog) do
    expected = expected(package)

    wanted =
      for {group, stage} <- [commands: "invoke.command", tools: "invoke.tool"],
          id <- expected[group],
          do: {stage, id}

    actual = Enum.map(catalog["entries"], &{&1["stage"], &1["id"]})
    Enum.sort(actual) == Enum.sort(wanted)
  end
end
