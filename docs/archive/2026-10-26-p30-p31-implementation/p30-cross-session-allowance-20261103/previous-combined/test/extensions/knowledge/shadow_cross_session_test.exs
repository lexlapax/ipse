defmodule IpseKnowledge.ShadowCrossSessionTest do
  use ExUnit.Case, async: false

  for {name, scenario} <- [
        {"shared limit", "save_managed_approval_cross_session"},
        {"unknown liability", "save_managed_approval_cross_session_unknown"}
      ] do
    @tag timeout: 180_000
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
              Path.expand(
                if(unquote(scenario) == "save_managed_approval_cross_session_unknown",
                  do: "../../support/shadow_cross_unknown_cli.exs",
                  else: "../../support/shadow_cross_session_cli.exs"
                ),
                __DIR__
              ),
              root,
              unquote(scenario)
            ],
          stderr_to_stdout: true
        )

      assert status == 0, "Synthetic fixture root: #{root}\n" <> output
      assert output =~ "SHADOW_CROSS_SESSION_PASSED"
    end
  end
end
