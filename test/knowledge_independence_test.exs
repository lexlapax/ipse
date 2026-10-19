Code.require_file("../examples/knowledge/proof.exs", __DIR__)

defmodule Ipse.KnowledgeIndependenceTest do
  use ExUnit.Case, async: false

  test "knowledge packages and all memory scopes remain independent through real Sessions" do
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

    report = IpseKnowledgeExample.Proof.independence(root)
    assert report["checks"] == 10 and length(report["cases"]) == 9
    assert report["catalog_bound_refused"] and report["cleanup"] == "confirmed"
    assert report["model_requests"] == 0 and report["payloads_traced"] == false
    assert report["host_loaded_domain_modules"] == false

    assert Enum.all?(report["cases"], fn row ->
             row["note_isolation"] and row["forget_isolation"] and
               row["state_files"] == if(row["package"] == "research", do: 1, else: 2) and
               Enum.all?(~w(disabled_calls idle_calls resume_calls), fn phase ->
                 Enum.all?(Map.values(row[phase]), &(&1 == 0))
               end) and row["operation_calls"]["extension_worker_starts"] > 0 and
               row["operation_calls"]["state_operations"] > 0
           end)
  end
end
