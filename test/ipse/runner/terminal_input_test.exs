defmodule Ipse.Runner.TerminalInputTest do
  use ExUnit.Case, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-terminal-input-" <> Ipse.Usage.id())
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

    %{root: root, driver: driver}
  end

  test "a claimed terminal leaves every typed line for the inheriting child", c do
    output = run(c, "claim")

    for n <- 1..3 do
      assert output =~ "TERMINAL_CHILD_#{n}=synthetic café 日本語 #{n}"
    end
  end

  test "an unclaimed eager VM reader takes lines meant for the inheriting child", c do
    output = run(c, "unclaimed")

    if eager_reader_absent?(c) do
      # Runtimes that read standard input only on request have nothing to pause.
      assert output =~ "TERMINAL_CHILD_1=synthetic café 日本語 1"
    else
      for n <- 1..3, do: assert(output =~ "TERMINAL_CHILD_#{n}=none")
    end
  end

  test "nonterminal standard input keeps ordinary VM reads" do
    {output, 0} =
      System.cmd(
        "sh",
        [
          "-c",
          ~S(printf 'piped line\n' | "$@"),
          "sh",
          System.find_executable("elixir")
          | code_paths() ++
              [
                "-e",
                ~S"""
                {:ok, _} = Application.ensure_all_started(:ipse)
                :ok = Ipse.Runner.TerminalInput.claim()
                IO.write("READ=" <> IO.gets(""))
                """
              ]
        ],
        stderr_to_stdout: true
      )

    assert output =~ "READ=piped line"
  end

  defp run(c, mode) do
    script = Path.expand("test/support/terminal_input_claim.exs")

    {output, status} =
      System.cmd(
        c.driver,
        [System.find_executable("elixir")] ++ code_paths() ++ [script, c.root, mode],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "TERMINAL_INPUT_CLAIM_DONE", output
    output
  end

  # The test VM itself does not run on a terminal, so ask a PTY child whether
  # its runtime registers the eager reader.
  defp eager_reader_absent?(c) do
    {output, _} =
      System.cmd(
        c.driver,
        [
          System.find_executable("elixir"),
          "-e",
          ~S|IO.puts("EAGER=#{Process.whereis(:user_drv_reader) != nil}")|
        ],
        stderr_to_stdout: true
      )

    output =~ "EAGER=false"
  end

  defp code_paths do
    :code.get_path()
    |> Enum.map(&List.to_string/1)
    |> Enum.reject(&(&1 == "."))
    |> Enum.map(&Path.expand/1)
    |> Enum.reverse()
    |> Enum.flat_map(&["-pa", &1])
  end
end
