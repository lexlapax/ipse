Code.require_file("../../../dev/verification/knowledge_recovery.exs", __DIR__)

defmodule Ipse.KnowledgeRecoveryProofTest do
  use ExUnit.Case, async: false

  test "Graph alone recovers denied extraction with exact approved abort and no model dispatch" do
    root = Path.join(System.tmp_dir!(), "ipse-graph-recovery-artifact-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          root,
          "--package",
          "graph",
          "--preset",
          "state-model"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    assert %{
             "checks" => 8,
             "cleanup" => "confirmed",
             "model_requests" => 0,
             "denied_model_dispatches" => 0,
             "host_loaded_domain_modules" => false,
             "graph_only" => true,
             "exact_abort" => true,
             "stale_abort_zero_writes" => true,
             "explicit_new_draft" => true
           } = IpseKnowledgeExample.RecoveryProof.run(root)
  end
end
