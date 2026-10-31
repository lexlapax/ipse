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

    paths = Enum.reverse(:code.get_path()) |> Enum.flat_map(&["-pa", List.to_string(&1)])

    modes =
      System.get_env(
        "IPSE_SUPERSESSION_TEST_MODES",
        "ordinary temporal deadline split history_expiry pin_history"
      )
      |> String.split()

    assert Enum.all?(
             modes,
             &(&1 in ~w(ordinary temporal deadline split history_expiry pin_history binding-only))
           )

    for mode <- modes do
      directory = Path.join(root, mode)
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)

      graph = Ipse.Runner |> :code.which() |> List.to_string() |> Path.dirname() |> Path.expand()

      {output, status} =
        System.cmd(
          helper,
          ["--review", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths ++
            ["-pa", graph] ++
            ["test/support/managed_literal_supersession.exs", directory, mode],
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
        if mode == "deadline",
          do: "NATIVE_SUPERSESSION_DEADLINE_PASSED",
          else: "NATIVE_SUPERSESSION_PASSED:" <> mode

      assert output =~ marker
    end
  end
end
