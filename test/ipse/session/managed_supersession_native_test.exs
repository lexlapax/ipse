defmodule Ipse.Session.ManagedSupersessionNativeTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 120_000

  test "native correction and temporal successor publish together and keep the old note noncurrent" do
    root = Path.join(System.tmp_dir!(), "ipse-native-supersession-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    helper = Path.join(root, "pty-driver")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", helper],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    modes =
      System.get_env(
        "IPSE_SUPERSESSION_TEST_MODES",
        "ordinary temporal deadline split history_expiry pin_history"
      )
      |> String.split()

    assert modes != [] and
             Enum.all?(
               modes,
               &(&1 in ~w(ordinary temporal deadline split history_expiry pin_history binding-only))
             )

    for mode <- modes do
      directory = Path.join(root, mode)
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)

      graph = Ipse.Runner |> :code.which() |> List.to_string() |> Path.dirname() |> Path.expand()
      genuine = mode in ~w(ordinary temporal deadline pin_history history_expiry split)
      scenario = if mode == "deadline", do: "terminal_deadline", else: mode

      script =
        if genuine,
          do: "test/support/managed_supersession_session.exs",
          else: "test/support/managed_literal_supersession.exs"

      {output, status} =
        System.cmd(
          helper,
          [
            if(genuine, do: "--assertion", else: "--review"),
            System.find_executable("elixir"),
            "--erl",
            "+S 2:2"
          ] ++
            paths ++
            ["-pa", graph] ++
            [Path.expand(script), directory, scenario],
          stderr_to_stdout: true,
          env: [{"HOME", directory}, {"IPSE_HOME", directory <> "/ipse"}, {"TMPDIR", directory}]
        )

      assert status == 0, output

      if mode == "split",
        do:
          Enum.each(String.split(output, "\n"), fn line ->
            if String.contains?(line, [
                 "SUPERCESSION_READ_UNITS=",
                 "SUPERSESSION_RECEIPT_BYTES=",
                 "SUPERSESSION_CHARGED_BYTES="
               ]),
               do: IO.puts(String.trim(line))
          end)

      marker =
        case mode do
          "deadline" -> "MANAGED_SUPERSESSION_TERMINAL_DEADLINE_PASSED"
          "pin_history" -> "NATIVE_PINNED_HISTORY_SESSION_PASSED"
          _ -> "NATIVE_SUPERSESSION_PASSED:" <> mode
        end

      assert output =~ marker
    end
  end
end
