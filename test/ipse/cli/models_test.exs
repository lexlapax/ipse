Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.CLI.ModelsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  test "explicit inspection does not read or alter the selected conversation configuration" do
    root = Path.join(System.tmp_dir!(), "ipse-model-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    home = Path.join(root, "unused-home")
    path = Path.join(root, "private-config.json")
    original = "malformed synthetic-private-configuration"
    File.write!(path, original)
    previous = Map.new(~w(IPSE_HOME IPSE_CONFIG), &{&1, System.get_env(&1)})
    System.put_env("IPSE_HOME", home)
    System.put_env("IPSE_CONFIG", path)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      File.rm_rf!(root)
    end)

    model = "fixture:fixed"

    row = %{
      "name" => model,
      "model" => model,
      "digest" => String.duplicate("a", 64),
      "size" => 4096
    }

    version = %{"version" => "0.40.13"}
    tags = %{"models" => [row]}

    show = %{
      "details" => %{},
      "model_info" => %{"general.architecture" => "fixture"},
      "capabilities" => ["embedding"]
    }

    {base, server} =
      Ipse.Test.ProviderFixture.sequence(
        Enum.map([version, tags, show, %{"models" => []}, tags, version], &Jason.encode!/1)
      )

    output =
      capture_io(fn ->
        assert Ipse.CLI.run([
                 "model",
                 "inspect",
                 "--provider",
                 "ollama",
                 "--model",
                 model,
                 "--base-url",
                 base,
                 "--json"
               ]) == 0
      end)

    assert Jason.decode!(output)["effective_context"] == "unverified_not_loaded"
    refute output =~ original
    assert File.read!(path) == original
    refute File.exists?(home)
    assert length(Task.await(server)) == 6
  end

  test "inspection requires explicit local selection and rejects unrelated flags" do
    for args <- [
          [],
          ["--provider", "demo"],
          ["--provider", "ollama", "--yes"],
          ["--provider", "ollama", "--model", "fixture", "--base-url", "https://example.com"]
        ] do
      output =
        capture_io(:stderr, fn -> assert Ipse.CLI.run(["model", "inspect" | args]) == 1 end)

      assert output =~ "inspection refused"
    end
  end

  test "JSON refusal contains only a fixed error code" do
    private = "synthetic-private-value"

    output =
      capture_io(:stderr, fn ->
        assert Ipse.CLI.run([
                 "model",
                 "inspect",
                 "--provider",
                 "ollama",
                 "--model",
                 private,
                 "--base-url",
                 "http://127.0.0.1:1?token=" <> private,
                 "--json"
               ]) == 1
      end)

    assert Jason.decode!(output) == %{"version" => 1, "error" => "invalid_ollama_inspection"}
    refute output =~ private
  end
end
