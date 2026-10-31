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

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    expression = """
    {:ok, _} = Application.ensure_all_started(:ipse)
    [proof, artifact] = System.argv()
    Code.require_file(proof)
    IO.puts(Jason.encode!(IpseKnowledgeExample.RecoveryProof.run(artifact)))
    """

    {proof_output, proof_status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++
          [
            "-e",
            expression,
            Path.expand("../../../dev/verification/knowledge_recovery.exs", __DIR__),
            root
          ],
        stderr_to_stdout: true
      )

    assert proof_status == 0, proof_output
    report = proof_output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()

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
           } = report
  end
end
