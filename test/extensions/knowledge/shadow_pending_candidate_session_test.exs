defmodule IpseKnowledge.ShadowPendingCandidateSessionTest do
  use ExUnit.Case, async: false

  for {name, scenario} <- [
        {"approved", "save_managed_approval_root_shadow"},
        {"deferred candidate", "save_managed_approval_defer_candidate"},
        {"mixed literal and pending sources", "save_managed_approval_mixed_v4_v7"},
        {"low confidence", "save_managed_approval_low_confidence"},
        {"unknown decision remains charged and is not replayed", "save_managed_approval_unknown"},
        {"source withdrawn before decision", "save_managed_approval_input_source_lost"},
        {"source withdrawn before output release", "save_managed_approval_output_source_lost"},
        {"denied", "save_managed_approval_deny"},
        {"revoked grant", "save_managed_approval_revoked_grant"},
        {"expired while preflight is blocked", "save_managed_approval_root_shadow_expiry"},
        {"expired while result admission is blocked",
         "save_managed_approval_root_shadow_release_expiry"}
      ] do
    @tag timeout: 120_000
    @tag shadow_case: name
    test "actual bundled shadow Session is #{name}" do
      root = Path.join(System.tmp_dir!(), "ipse-shadow-session-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)

      on_exit(fn ->
        unless System.get_env("IPSE_KEEP_SHADOW_FIXTURES") == "1", do: File.rm_rf!(root)
      end)

      driver = Path.join(root, "pty")

      assert {"", 0} =
               System.cmd(
                 "rustc",
                 [
                   "--edition=2021",
                   "-D",
                   "warnings",
                   "test/support/operator_pty.rs",
                   "-o",
                   driver
                 ],
                 stderr_to_stdout: true
               )

      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      {output, status} =
        System.cmd(
          driver,
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            [
              Path.expand("../../support/shadow_pending_candidate_cli.exs", __DIR__),
              root,
              unquote(scenario)
            ],
          stderr_to_stdout: true
        )

      assert status == 0, "Synthetic fixture root: #{root}\n" <> output
      assert output =~ "SHADOW_EXPERIMENT_SESSION_PASSED"
    end
  end
end
