#!/usr/bin/env elixir

defmodule Ipse.PackageVerifier do
  @utility_names ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head)
  @job_timeout_note "Run this verifier under a bounded CI job timeout; System.cmd/3 has no per-process timeout option."

  def main([archive_arg]) do
    archive = Path.expand(archive_arg)
    unless File.regular?(archive), do: raise("archive is not a regular file: #{archive}")
    tar = System.find_executable("tar") || raise("tar is required to extract the package")

    id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    root = Path.join(System.tmp_dir!(), "ipse-package-check-#{id}")
    File.mkdir_p!(root)

    try do
      verify!(archive, root, tar)
    after
      File.rm_rf!(root)
    end
  end

  def main(_) do
    raise "usage: elixir scripts/verify-package.exs /path/to/ipse-*.tar.gz"
  end

  defp verify!(archive, root, tar) do
    release = Path.join(root, "release")
    home = Path.join(root, "home")
    ipse_home = Path.join(home, ".ipse")
    temp = Path.join(root, "tmp")
    utility_path = Path.join(root, "utility-path")
    default_workspace = Path.join(root, "caller cwd with spaces")
    override_caller = Path.join(root, "different caller cwd")
    override_workspace = Path.join(root, "explicit workspace with spaces")

    Enum.each(
      [release, home, temp, utility_path, default_workspace, override_caller, override_workspace],
      &File.mkdir_p!/1
    )

    [] = File.ls!(home)
    File.mkdir_p!(ipse_home)
    [] = File.ls!(ipse_home)
    File.chmod!(home, 0o700)
    File.chmod!(ipse_home, 0o700)

    {_output, 0} = System.cmd(tar, ["-xzf", archive, "-C", release], stderr_to_stdout: true)
    utility_path = make_utility_path!(utility_path)

    for name <- ["erl", "elixir", "mix", "rustc"] do
      if File.exists?(Path.join(utility_path, name)),
        do: raise("toolchain executable unexpectedly present in utility PATH: #{name}")
    end

    env = isolated_env(utility_path, home, ipse_home, temp)
    wrapper = Path.join(release, "ipse")
    otp_launcher = Path.join(release, "bin/ipse")
    require_executable!(wrapper)
    require_executable!(otp_launcher)

    run!(wrapper, ["--help"], release, env, "bundled CLI help")

    # The first run exercises default cwd from a directory outside the release.
    run!(
      wrapper,
      ["run", "--provider", "demo", "--yes", "Create and read the deterministic demo file"],
      default_workspace,
      env,
      "demo using default cwd"
    )

    assert_demo_file!(default_workspace)

    # Invoke from another arbitrary directory and require --cwd to select the
    # actual workspace rather than the caller directory or release directory.
    run!(
      wrapper,
      [
        "run",
        "--provider",
        "demo",
        "--yes",
        "--cwd",
        override_workspace,
        "Create and read the deterministic demo file"
      ],
      override_caller,
      env,
      "demo using --cwd"
    )

    assert_demo_file!(override_workspace)
    refute_demo_file!(override_caller)
    refute_demo_file!(release)

    eval = "Code.require_file(\"verify-release.exs\")"
    output = run!(otp_launcher, ["eval", eval], release, env, "bundled runtime/helper checks")

    unless String.contains?(
             output,
             "Bundled runtime/helper, timeout cleanup, owner-death cleanup, and locks passed."
           ) do
      raise "release helper verification did not print its completion marker: #{inspect(output)}"
    end

    unless String.contains?(
             output,
             "Bundled local MCP SDK round trip passed without a development toolchain."
           ) do
      raise "release MCP verification did not print its completion marker"
    end

    IO.puts(
      "PASS: extracted package help, demo from isolated fresh HOME/IPSE_HOME, default cwd, explicit --cwd, bundled MCP round trip, and OTP/helper checks."
    )

    IO.puts("Verified default workspace: #{default_workspace}")
    IO.puts("Verified --cwd workspace: #{override_workspace}")

    IO.puts(
      "Execution used a utility-only PATH; no Elixir, Erlang, Mix, or Rust toolchain executables were available to the release."
    )

    IO.puts(@job_timeout_note)
  end

  defp make_utility_path!(directory) do
    Enum.each(@utility_names, fn name ->
      executable =
        System.find_executable(name) || raise("required host utility unavailable: #{name}")

      :ok = File.ln_s(executable, Path.join(directory, name))
    end)

    directory
  end

  defp isolated_env(path, home, ipse_home, temp) do
    allowed_names = ["PATH", "HOME", "IPSE_HOME", "TMPDIR", "LANG", "LC_ALL"]

    cleared =
      System.get_env()
      |> Map.keys()
      |> Enum.reject(&(&1 in allowed_names))
      |> Enum.map(&{&1, nil})

    allowed = [
      {"PATH", path},
      {"HOME", home},
      {"IPSE_HOME", ipse_home},
      {"TMPDIR", temp},
      {"LANG", "C"},
      {"LC_ALL", "C"}
    ]

    cleared ++ allowed
  end

  defp run!(executable, args, cwd, env, label) do
    {output, status} =
      System.cmd(executable, args,
        cd: cwd,
        env: env,
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "#{label} failed with exit #{status}: #{String.trim(output)}"
    end

    output
  end

  defp assert_demo_file!(workspace) do
    expected = "Hello from Ipse!\n"
    path = Path.join(workspace, "ipse-demo.txt")
    actual = File.read!(path)
    unless actual == expected, do: raise("unexpected demo file at #{path}: #{inspect(actual)}")
  end

  defp refute_demo_file!(workspace) do
    path = Path.join(workspace, "ipse-demo.txt")
    if File.exists?(path), do: raise("unexpected demo file in non-selected workspace: #{path}")
  end

  defp require_executable!(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 -> :ok
      _ -> raise("required release launcher missing or not executable: #{path}")
    end
  end
end

Ipse.PackageVerifier.main(System.argv())
