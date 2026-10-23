defmodule Ipse.NativeHelperBoundaryTest do
  use ExUnit.Case, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-helper-boundary-#{Ipse.Usage.id()}")
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(cwd)
    previous = System.get_env("IPSE_RUNNER_PATH")

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(root)
    end)

    %{root: root, cwd: cwd}
  end

  test "native shell and stdio refuse a workspace helper before executing it", ctx do
    helper = Path.join(ctx.cwd, "supervisor")
    marker = Path.join(ctx.root, "must-not-run")
    File.write!(helper, "#!/bin/sh\nprintf executed > '#{marker}'\n")
    File.chmod!(helper, 0o700)
    System.put_env("IPSE_RUNNER_PATH", helper)

    assert {:error, reason} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                config: %{provider: :demo, model: "fixture", sandbox: :native},
                cwd: ctx.cwd,
                state_dir: Path.join(ctx.root, "sessions")}
             )

    assert reason =~ "overlaps the active helper or application"
    refute File.exists?(marker)

    result = Ipse.Runner.run("true", ctx.cwd, sandbox: :native)
    refute File.exists?(marker)
    assert {:error, reason} = result
    assert reason =~ "overlaps the active helper or application"

    assert {:error, reason} =
             Ipse.Runner.open_stdio("/bin/cat", [], ctx.cwd, %{}, 1_000, sandbox: :native)

    assert reason =~ "overlaps the active helper or application"
    refute File.exists?(marker)
  end

  test "native resolution rejects helper aliases and the active application", ctx do
    helper = Path.join(ctx.root, "supervisor")
    File.cp!(Path.join(:code.priv_dir(:ipse), "ipse-runner"), helper)
    File.chmod!(helper, 0o700)
    System.put_env("IPSE_RUNNER_PATH", helper)
    assert {:ok, _} = Ipse.Tools.Sandbox.resolve(:native, ctx.cwd)

    File.ln!(helper, Path.join(ctx.cwd, "alias"))
    assert {:error, reason} = Ipse.Tools.Sandbox.resolve(:native, ctx.cwd)
    assert reason =~ "single-link"
    File.rm!(Path.join(ctx.cwd, "alias"))

    app = Application.app_dir(:ipse)
    assert {:error, reason} = Ipse.Tools.Sandbox.resolve(:native, app)
    assert reason =~ "overlaps the active helper or application"
  end
end
