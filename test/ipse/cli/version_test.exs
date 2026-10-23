defmodule Ipse.CLI.VersionTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  test "version commands and help share the application version" do
    version = Application.spec(:ipse, :vsn) |> to_string()
    assert capture_io(fn -> assert Ipse.CLI.run(["--version"]) == 0 end) == version <> "\n"
    assert capture_io(fn -> assert Ipse.CLI.run(["version"]) == 0 end) == "Ipse #{version}\n"
    assert capture_io(fn -> assert Ipse.CLI.run(["--help"]) == 0 end) =~ "Ipse #{version} —"

    info =
      capture_io(fn -> assert Ipse.CLI.run(["version", "--json"]) == 0 end) |> Jason.decode!()

    assert Enum.sort(Map.keys(info)) == ~w(arch commit elixir os otp_release version)
    assert info["version"] == version
    assert info["elixir"] == System.version()
    assert info["otp_release"] == to_string(:erlang.system_info(:otp_release))
    assert info["os"] in ~w(linux darwin)
    assert is_binary(info["arch"]) and info["arch"] != ""
    assert is_nil(info["commit"]) or Regex.match?(~r/\A[0-9a-f]{40,64}\z/, info["commit"])
  end

  test "runtime environment cannot replace compiled commit identity" do
    original = System.get_env("IPSE_BUILD_COMMIT")
    info = Ipse.build_info()

    try do
      System.put_env("IPSE_BUILD_COMMIT", String.duplicate("f", 40))
      assert Ipse.build_info() == info
    after
      if original,
        do: System.put_env("IPSE_BUILD_COMMIT", original),
        else: System.delete_env("IPSE_BUILD_COMMIT")
    end
  end
end
