Code.require_file("../../dev/verification/knowledge_builds.exs", __DIR__)

defmodule KnowledgeBuildsTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Verification.KnowledgeBuilds, as: Builds

  test "checks each package's explicit export and catalog identities" do
    for {package, commands, tools} <- [
          {"corpus", ~w(source query index), ~w(query)},
          {"research", ~w(investigate ledger), ~w(investigate)},
          {"graph", ~w(source extract identity query), ~w(query capture)}
        ] do
      exports = %{
        "commands" => Enum.map(commands, &%{"id" => &1}),
        "tools" => Enum.map(tools, &%{"id" => &1})
      }

      entries =
        for {ids, stage} <- [{commands, "invoke.command"}, {tools, "invoke.tool"}],
            id <- ids,
            do: %{"stage" => stage, "id" => id}

      assert Builds.exports_match?(package, exports)
      assert Builds.catalog_match?(package, %{"entries" => entries})

      refute Builds.exports_match?(
               package,
               put_in(exports, ["commands", Access.at(0), "id"], "wrong")
             )

      refute Builds.catalog_match?(package, %{"entries" => tl(entries)})
      refute Builds.catalog_match?(package, %{"entries" => [hd(entries) | entries]})
    end
  end
end
