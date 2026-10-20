Code.require_file("../examples/knowledge/proof.exs", __DIR__)

defmodule Ipse.KnowledgeIndependenceTest do
  use ExUnit.Case, async: false

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-independence-artifacts-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(root) end)

    for {package, preset} <- [
          {"corpus", "state-lexical"},
          {"graph", "state-explicit"},
          {"research", "offline"}
        ] do
      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            "extensions/knowledge/build.exs",
            "--sdk",
            Application.app_dir(:ipse, "ebin"),
            "--output",
            Path.join(root, package),
            "--package",
            package,
            "--preset",
            preset
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output
    end

    %{artifacts: root}
  end

  for {kind, scope} <- [
        {"working", "session"},
        {"persistent", "project"},
        {"persistent", "operator"}
      ],
      package <- ~w(corpus graph research) do
    @tag selection: {kind, scope, package}
    test "#{scope} memory and #{package} remain independent through real Sessions", ctx do
      report = IpseKnowledgeExample.Proof.independence(ctx.artifacts, ctx.selection)
      assert report["checks"] == 2
      assert report["catalog_bound_refused"] and report["cleanup"] == "confirmed"
      assert report["model_requests"] == 0 and report["payloads_traced"] == false
      assert report["host_loaded_domain_modules"] == false
      [row] = report["cases"]
      assert {row["memory"], row["scope"], row["package"]} == ctx.selection

      assert row["note_isolation"] and row["forget_isolation"]
      assert row["state_files"] == if(row["package"] == "research", do: 1, else: 2)

      for phase <- ~w(disabled_calls idle_calls resume_calls) do
        assert Enum.all?(Map.values(row[phase]), &(&1 == 0))
      end

      assert row["operation_calls"]["extension_worker_starts"] > 0
      assert row["operation_calls"]["state_operations"] > 0
    end
  end
end
