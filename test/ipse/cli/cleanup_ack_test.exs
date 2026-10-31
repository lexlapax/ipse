defmodule Ipse.CLICleanupAckTest do
  use ExUnit.Case, async: false

  @moduletag skip:
               if(:os.type() == {:unix, :linux}, do: false, else: "Linux release-claim fixture")

  @tag :cli_cleanup_ack
  test "public CLI confirms clean EOF and refuses success after its Session already died" do
    for scenario <- ~w(clean already_dead), do: scenario(scenario)
  end

  @tag :cli_cleanup_ack
  @tag skip: System.get_env("IPSE_CLI_CLOSE_HOOK_GRAPH") == nil
  test "public CLI refuses success when Session dies after native unlock before acknowledgment" do
    scenario("lost_reply", System.fetch_env!("IPSE_CLI_CLOSE_HOOK_GRAPH"))
  end

  defp scenario(scenario, graph \\ nil) do
    root = Path.join(System.tmp_dir!(), "ipse-cli-cleanup-#{scenario}-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.map(fn path ->
        if graph && File.exists?(Path.join(path, "Elixir.Ipse.Session.beam")),
          do: Path.expand(Path.join(graph, "ipse/ebin")),
          else: path
      end)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++
          paths ++ [Path.expand("test/support/cli_cleanup_ack.exs"), scenario, root],
        stderr_to_stdout: true,
        env: [
          {"IPSE_CONFIG", Path.join(root, "unselected-ambient-config.json")},
          {"IPSE_PROFILE", "unselected-ambient-profile"},
          {"IPSE_SANDBOX", "unsupported-ambient-sandbox"}
        ]
      )

    assert status == 0, output
    assert output =~ "CLI_CLEANUP_ACK_PASSED"
    IO.puts(String.trim(output))
  end
end
