defmodule Ipse.Config.ActivationSessionTest do
  use ExUnit.Case, async: false
  @tag timeout: 120_000
  test "actual protected activation uses private packaged bytes and exact fresh/resume selections" do
    root = Path.join(System.tmp_dir!(), "ipse-activation-runtime-" <> Ipse.Usage.id())
    app = Path.join(root, "ipse")
    File.mkdir_p!(app)
    on_exit(fn -> File.rm_rf!(root) end)
    File.cp_r!(Application.app_dir(:ipse, "ebin"), Path.join(app, "ebin"))
    {:ok, priv} = Ipse.Workspace.canonical_path(Application.app_dir(:ipse, "priv"))
    File.cp_r!(priv, Path.join(app, "priv"))
    # Only the child sees this private application directory. Primary priv and
    # helper bytes remain untouched throughout these packaged-catalog fixtures.
    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.filter(&String.ends_with?(&1, "/ebin"))
      |> Enum.reject(&(&1 == Application.app_dir(:ipse, "ebin")))

    args =
      ["--erl", "+S 2:2"] ++
        Enum.flat_map(paths, &["-pa", &1]) ++
        ["-pa", Path.join(app, "ebin"), "test/support/activation_overlay_vm.exs", root]

    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "activation overlay child controls complete"
  end
end
