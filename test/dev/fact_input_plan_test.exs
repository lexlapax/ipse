defmodule Ipse.Development.FactInputPlanTest do
  use ExUnit.Case, async: false

  @tag timeout: 120_000
  test "planner uses the selected artifact and refuses invalid spans" do
    root = Path.join(System.tmp_dir!(), "ipse-fact-plan-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    artifact = Path.join(root, "artifact")

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          artifact,
          "--package",
          "corpus",
          "--preset",
          "collection-dense"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    source = %{
      "source_id" => "fixture:planner",
      "partition" => "notes",
      "generation" => 1,
      "title" => "Fixture",
      "text" => "Source supports review.",
      "uri" => "provided:planner",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "notes",
        "partition_or_scope" => "notes",
        "receipt" => nil,
        "historical" => false
      }
    }

    row = %{
      "subject" => "Source",
      "predicate" => "supports",
      "object" => "review",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => nil,
      "spans" => [[0, 0, 6]]
    }

    source_path = Path.join(root, "source.json")
    rows_path = Path.join(root, "rows.json")
    File.write!(source_path, Jason.encode!(source))
    File.write!(rows_path, Jason.encode!([row]))

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.map(&Path.expand(List.to_string(&1)))
      |> Enum.flat_map(&["-pa", &1])

    command =
      ["--erl", "+S 2:2"] ++
        paths ++ ["dev/knowledge/plan_fact_input.exs", artifact, source_path, rows_path]

    {output, status} =
      System.cmd(System.find_executable("elixir"), command, stderr_to_stdout: true)

    assert status == 0, output
    assert {:ok, plan} = Ipse.JSON.decode_unique(output)
    assert plan["source_id"] == "fixture:planner" and length(plan["pages"]) == 1
    assert plan["manifest"]["row_count"] == 1
    assert Regex.match?(~r/\A[0-9a-f]{32}\z/, plan["draft_id"])

    File.write!(rows_path, Jason.encode!([%{row | "spans" => [[1, 0, 6]]}]))
    {_, status} = System.cmd(System.find_executable("elixir"), command, stderr_to_stdout: true)
    assert status != 0
  end
end
