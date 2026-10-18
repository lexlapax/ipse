defmodule Ipse.CIPolicyTest do
  use ExUnit.Case, async: true

  test "CI pin policy accepts immutable and local actions and rejects mutable selectors" do
    path = Path.join(System.tmp_dir!(), "ipse-ci-policy-#{Ipse.Usage.id()}.yml")
    on_exit(fn -> File.rm(path) end)
    executable = System.find_executable("elixir")
    script = Path.expand("../scripts/check-ci-policy.exs", __DIR__)

    for selector <- ["actions/checkout@v4", "dtolnay/rust-toolchain@stable"] do
      File.write!(path, "steps:\n  - uses: #{selector}\n")
      assert {_, 1} = System.cmd(executable, [script, path], stderr_to_stdout: true)
    end

    File.write!(
      path,
      "steps:\n  - uses: actions/checkout@#{String.duplicate("a", 40)}\n  - uses: ./local\n"
    )

    assert {_, 0} = System.cmd(executable, [script, path], stderr_to_stdout: true)
  end
end
