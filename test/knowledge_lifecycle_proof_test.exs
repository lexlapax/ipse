Code.require_file("../examples/knowledge/lifecycle-proof.exs", __DIR__)

defmodule Ipse.KnowledgeLifecycleProofTest do
  use ExUnit.Case, async: false

  for {kind, preset} <- [{"graph", "state-model"}, {"corpus", "state-dense"}] do
    @tag package: kind, preset: preset
    test "#{kind} uses public provider IO for forget races, interruption, quota and failed responses",
         ctx do
      root = Path.join(System.tmp_dir!(), "ipse-lifecycle-artifact-" <> Ipse.Usage.id())
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
            ctx.package,
            "--preset",
            ctx.preset
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output
      report = IpseKnowledgeExample.LifecycleProof.run(root, ctx.package)
      assert report["checks"] == 7
      assert report["fixture_provider_requests"] == 7
      assert report["actual_model_inference"] == false
      assert report["host_loaded_domain_modules"] == false
      assert report["fixture_cleanup"] == "confirmed"
      assert report["session_cleanup_unconfirmed_cases"] == ["owner_loss"]
      assert Enum.all?(report["cases"], &(&1["idle_resume_replays"] == 0))
    end
  end
end
