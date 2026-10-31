defmodule Ipse.KnowledgeLexicalRunTest do
  use ExUnit.Case, async: false

  @tag :lexical_recipe
  test "exact Unicode tokenizer recipe produces complete ordered frequencies and rejects inconsistent runs" do
    root = Path.expand("../../..", __DIR__)

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    script = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.Evidence, as: E
    {:ok, source} = E.source(%{"source_id" => "fixture:lexical", "partition" => "notes",
      "generation" => 1, "title" => "Lexical recipe", "text" => "RÉSUMÉ résumé\n42 42",
      "uri" => "provided:lexical", "observed_at_ms" => 10, "event_at_ms" => nil,
      "expires_at_ms" => nil, "origin" => %{"kind" => "provided", "store_profile" => "documents",
        "partition_or_scope" => "notes", "receipt" => nil, "historical" => false}})
    {:ok, run} = E.lexical_run(source)
    assert E.valid_lexical_run?(run)
    assert run["terms"] == [["42", [[0, 2]]], ["résumé", [[0, 2]]]]
    assert run["selection"] == %{"observed_at_ms" => 10, "expires_at_ms" => nil, "historical" => false}
    assert [[_, 0, 23, 4]] = run["chunks"]
    refute E.valid_lexical_run?(put_in(run, ["terms", Access.at(0), Access.at(1), Access.at(0), Access.at(1)], 3))
    refute E.valid_lexical_run?(Map.update!(run, "terms", &Enum.reverse/1))
    refute E.valid_lexical_run?(Map.put(run, "recipe", "unknown"))
    refute E.valid_lexical_run?(put_in(run, ["terms", Access.at(0), Access.at(1), Access.at(0), Access.at(0)], 1))
    refute E.valid_lexical_run?(Map.put(run, "source_key", "other"))
    refute E.valid_lexical_run?(put_in(run, ["selection", "historical"], "false"))
    refute E.valid_lexical_run?(put_in(run, ["chunks", Access.at(0), Access.at(0)], String.duplicate("0", 64)))
    {:ok, empty} = E.lexical_run(%{source | "text" => "!!!", "content_sha256" => E.sha256("!!!")})
    assert empty["terms"] == []
    assert E.valid_lexical_run?(empty)
    IO.puts("EXACT_LEXICAL_RECIPE_PASS")
    '''

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths ++ ["-r", Path.join(root, "extensions/knowledge/src/evidence.ex"), "-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
    assert output =~ "EXACT_LEXICAL_RECIPE_PASS"
  end
end
