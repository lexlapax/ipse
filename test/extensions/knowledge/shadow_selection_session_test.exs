defmodule IpseKnowledge.ShadowSelectionSessionTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage

  for {name, scenario} <- [
        {"approved over-budget selection", "save_managed_approval_selection"},
        {"denied", "save_managed_approval_deny"},
        {"fitting set without a decision call", "save_managed_approval_selection_fits"},
        {"source withdrawn before decision", "save_managed_approval_input_source_lost"},
        {"unknown decision remains charged and is not replayed", "save_managed_approval_unknown"}
      ] do
    @tag timeout: 120_000
    @tag shadow_case: name
    test "actual bundled selection Session is #{name}" do
      root = Path.join(System.tmp_dir!(), "ipse-selection-session-" <> Ipse.Usage.id())
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
              Path.expand("../../support/selection_shadow_cli.exs", __DIR__),
              root,
              unquote(scenario)
            ],
          stderr_to_stdout: true
        )

      assert status == 0, "Synthetic fixture root: #{root}\n" <> output
      assert output =~ "SELECTION_SHADOW_SESSION_PASSED"
    end
  end
end
