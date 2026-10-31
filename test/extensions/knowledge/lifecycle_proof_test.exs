Code.require_file("../../../dev/verification/knowledge_lifecycle.exs", __DIR__)

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

  test "fresh Sessions preserve embedding identity across endpoint changes and explicit reindex" do
    root = Path.join(System.tmp_dir!(), "ipse-selection-artifact-" <> Ipse.Usage.id())
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
          "corpus",
          "--preset",
          "state-dense"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    selection = IpseKnowledgeExample.LifecycleProof.selection(root)
    assert selection["checks"] == 10
    assert selection["fixture_provider_requests"] == 10
    assert selection["changed_endpoint_refused"] and selection["explicit_reindex_succeeded"]
    assert selection["explicit_fallback_partial"] and selection["timeout_only_reused"]

    assert selection["changed_reported_model_reindexed"] and
             selection["reported_model_change_preserved_selection"]

    assert selection["idle_resume_replays"] == 0 and selection["cleanup"] == "confirmed"
  end

  test "a current Session treats an older mismatched input as missing and can reindex" do
    root = Path.join(System.tmp_dir!(), "ipse-historical-embedding-" <> Ipse.Usage.id())
    old_source = Path.join(root, "source/extensions/knowledge")
    File.mkdir_p!(Path.dirname(old_source))
    File.cp_r!("extensions/knowledge", old_source)
    File.cp!("LICENSE", Path.join(root, "source/LICENSE"))
    on_exit(fn -> File.rm_rf!(root) end)

    replace_once = fn path, from, to ->
      bytes = File.read!(path)
      assert length(:binary.matches(bytes, from)) == 1
      File.write!(path, String.replace(bytes, from, to, global: false))
    end

    adapter = Path.join(old_source, "src/adapters.ex")
    store = Path.join(old_source, "src/store.ex")
    corpus = Path.join(old_source, "src/corpus.ex")

    replace_once.(
      adapter,
      "         {:ok, expected_input} <- Ipse.Extension.canonical_digest([input[\"text\"]]),\n" <>
        "         true <- page[\"input_sha256\"] === expected_input,\n",
      ""
    )

    replace_once.(
      adapter,
      "\"input_sha256\" => page[\"input_sha256\"]",
      "\"input_sha256\" => Evidence.sha256(\"synthetic historical mismatch\")"
    )

    replace_once.(
      store,
      "Enum.any?(chunks, &Evidence.vector_input_matches_chunk?(vector, &1))",
      "Enum.any?(chunks, &(&1[\"chunk_id\"] == vector[\"chunk_id\"]))"
    )

    replace_once.(
      corpus,
      " and\n                Evidence.vector_input_matches_chunk?(v, chunk)",
      ""
    )

    sdk = Application.app_dir(:ipse, "ebin")
    old_artifact = Path.join(root, "old-artifact")
    current_artifact = Path.join(root, "current-artifact")

    for {builder, artifact} <- [
          {Path.join(old_source, "build.exs"), old_artifact},
          {"extensions/knowledge/build.exs", current_artifact}
        ] do
      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            builder,
            "--sdk",
            sdk,
            "--output",
            artifact,
            "--package",
            "corpus",
            "--preset",
            "state-dense"
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output
    end

    assert %{"fixture_provider_requests" => 6, "cleanup" => "confirmed"} =
             IpseKnowledgeExample.LifecycleProof.historical_input(old_artifact, current_artifact)
  end
end
