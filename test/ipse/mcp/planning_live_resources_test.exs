defmodule Ipse.MCP.PlanningLiveResourcesTest do
  use ExUnit.Case, async: false

  @moduletag skip:
               if(:os.type() == {:unix, :linux}, do: false, else: "Linux PTY and /proc control")

  @tag :planning_live_resources
  @tag timeout: 120_000
  test "native transitions refuse live MCP carryover and owner loss stops actual resources without replay" do
    root = Path.join(System.tmp_dir!(), "ipse-planning-live-mcp-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/planning_live_mcp_pty.rs",
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

    for mode <- ~w(entry_release exit_kill) do
      workspace = Path.join(root, mode)
      File.mkdir!(workspace)
      File.chmod!(workspace, 0o700)

      {output, status} =
        System.cmd(
          driver,
          [mode, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++ [Path.expand("test/support/planning_live_mcp.exs"), mode, workspace],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "PLANNING_LIVE_MCP_PASSED"
      assert output =~ "LIVE_MCP_TERMINAL_RESTORED"

      assert output =~
               if(mode == "entry_release",
                 do: "Planning entry requires an idle native terminal.",
                 else: "Planning exit requires an idle native terminal."
               )
    end
  end
end
