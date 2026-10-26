defmodule Ipse.Runner.OperatorTest do
  use ExUnit.Case, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-operator-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "display bytes and deadlines refuse before opening an operator channel" do
    for prompt <- ["", <<255>>, "\e[2Jhidden", "\u202Ehidden", String.duplicate("x", 8193)] do
      assert {:error, :operator_input_unavailable} = Ipse.Runner.operator_input(prompt, 1_000)
    end

    for timeout <- [0, 999, 600_001, 1000.0, nil] do
      assert {:error, :operator_input_unavailable} =
               Ipse.Runner.operator_input("fixture> ", timeout)
    end
  end

  test "redirected streams never return a verified observation or print the card", c do
    {output, 0} = child(c.root, [], [])
    assert String.trim(output) == "{:error, :operator_input_unavailable}"
    refute output =~ "operator fixture card"
  end

  test "an environment-selected executable cannot forge terminal observations", c do
    forged = forgery(c.root)
    {output, 0} = child(c.root, [], [{"IPSE_RUNNER_PATH", forged}])
    assert String.trim(output) == "{:error, :operator_input_unavailable}"
    refute output =~ "forged operator input"
  end

  test "substituting packaged helper bytes refuses against the compiled identity", c do
    forged = forgery(c.root)
    app = Path.join(c.root, "ipse")
    File.mkdir!(app)
    File.cp_r!(Application.app_dir(:ipse, "ebin"), Path.join(app, "ebin"))
    File.mkdir!(Path.join(app, "priv"))
    File.cp!(forged, Path.join(app, "priv/ipse-runner"))
    stat = File.stat!(Path.join(app, "priv/ipse-runner"))
    assert stat.type == :regular and stat.links == 1
    assert Bitwise.band(stat.mode, 0o111) != 0 and Bitwise.band(stat.mode, 0o022) == 0

    {output, 0} =
      child(c.root, ["-pa", Path.join(app, "ebin")], [
        {"IPSE_EXPECT_PRIV_DIR", Path.join(app, "priv")}
      ])

    assert String.trim(output) == "{:error, :operator_input_unavailable}"
    refute output =~ "forged operator input"
  end

  defp forgery(root) do
    path = Path.join(root, "forged-helper")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/operator_forgery.rs",
                 "-o",
                 path
               ],
               stderr_to_stdout: true
             )

    path
  end

  defp child(root, extra_paths, env) do
    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    code = ~S'''
    {:ok, _} = Application.ensure_all_started(:ipse)
    if expected = System.get_env("IPSE_EXPECT_PRIV_DIR") do
      actual = :code.priv_dir(:ipse) |> List.to_string() |> Path.expand()
      unless actual == expected, do: raise("isolated application selection failed")
    end
    IO.inspect(Ipse.Runner.operator_input("operator fixture card> ", 1000))
    '''

    System.cmd(
      System.find_executable("elixir"),
      ["--erl", "+S 2:2"] ++ paths ++ extra_paths ++ ["-e", code],
      cd: root,
      env: env,
      stderr_to_stdout: true
    )
  end
end
