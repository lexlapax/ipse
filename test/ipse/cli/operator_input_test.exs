defmodule Ipse.CLIOperatorInputTest do
  use ExUnit.Case, async: false

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
