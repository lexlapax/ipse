defmodule Ipse.CLIOperatorInputTest do
  use ExUnit.Case, async: false

  @tag planning_crash: true
  test "native planning entry and exit recover correctly after Session death around receipts" do
    root = Path.join(System.tmp_dir!(), "ipse-planning-native-crash-" <> Ipse.Usage.id())
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
                 "test/support/operator_cli_pty.rs",
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

    for boundary <-
          ~w(entry_before entry_after exit_before exit_after mcp_entry_epoch mcp_exit_epoch) do
      workspace = Path.join(root, boundary)
      File.mkdir!(workspace)
      File.chmod!(workspace, 0o700)

      mode =
        if boundary in ~w(exit_before exit_after mcp_exit_epoch),
          do: "--planning-crash-exit",
          else: "--planning-crash"

      {output, status} =
        System.cmd(
          driver,
          [mode, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++ [Path.expand("test/support/planning_crash_pty.exs"), boundary, workspace],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "SYNTHETIC_PLANNING_CRASH_#{String.upcase(boundary)}_PASSED"

      if boundary in ~w(entry_before entry_after mcp_entry_epoch),
        do: refute(output =~ "Planning mode entered."),
        else: refute(output =~ "Local planning mode exited.")
    end
  end

  test "native terminal witnesses exits after local and startup planning selections" do
    root = Path.join(System.tmp_dir!(), "ipse-planning-entry-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
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

    for {mode, extra} <- [{"--planning-entry", []}, {"--planning-startup", ["startup"]}] do
      workspace = Path.join(root, String.trim_leading(mode, "--"))
      File.mkdir!(workspace)
      File.chmod!(workspace, 0o700)

      {output, status} =
        System.cmd(
          driver,
          [mode, System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++ [Path.expand("test/support/planning_cli_pty.exs")] ++ extra ++ [workspace],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "SYNTHETIC_PLANNING_ENTRY_PASSED"
    end
  end

  test "native question EOF preserves already staged prompts and their verified source bytes" do
    root = Path.join(System.tmp_dir!(), "ipse-operator-eof-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
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
        ["--queued-eof", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("test/support/operator_eof.exs"), root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "OPERATOR_QUEUED_EOF_CHECKS_PASSED"
  end

  test "actual CLI native reader binds exact prompts and fresh question answers without granting effects" do
    root = Path.join(System.tmp_dir!(), "ipse-operator-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
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
        [System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/operator_cli.exs"), root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "OPERATOR_CLI_CHECKS_PASSED"
  end

  test "native queued tickets and active reads survive only their exact client and live host ownership" do
    root = Path.join(System.tmp_dir!(), "ipse-operator-channel-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
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
        ["--channel", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("test/support/operator_channel.exs"), root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "OPERATOR_CHANNEL_CHECKS_PASSED"
  end

  test "abrupt CLI VM death leaves independent native terminal restoration" do
    root = Path.join(System.tmp_dir!(), "ipse-operator-owner-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "pty")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_cli_pty.rs",
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
        ["--kill-owner", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [Path.expand("test/support/operator_cli.exs"), root],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "OPERATOR_OWNER_DEATH_RESTORED"
  end

  test "native CLI fixture exit readiness covers both prompt display orders" do
    root = Path.join(System.tmp_dir!(), "ipse-operator-cli-readiness-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    driver = Path.join(root, "readiness-tests")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "--test",
                 "test/support/operator_cli_pty.rs",
                 "-o",
                 driver
               ],
               stderr_to_stdout: true
             )

    {output, status} = System.cmd(driver, [], stderr_to_stdout: true)
    assert status == 0, output
  end
end
