Code.require_file("../../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../../dev/verification/runtime.exs", __DIR__)

defmodule Ipse.Development.KnowledgeMCPRetentionTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Verification.{Runtime, Scenarios}

  test "knowledge MCP retains compatibility with default and explicit output selection" do
    for {mode, option} <- [{"source", "--sdk"}, {"installed", "--archive"}] do
      {"knowledge-mcp", old} =
        Scenarios.parse!([mode, "knowledge-mcp", option, "origin", "--input", "artifact"])

      refute Keyword.has_key?(old, :output)

      {"knowledge-mcp", explicit} =
        Scenarios.parse!([
          mode,
          "knowledge-mcp",
          option,
          "origin",
          "--input",
          "artifact",
          "--output",
          "evidence"
        ])

      assert explicit[:output] == "evidence"
    end

    assert Scenarios.fetch!("knowledge-mcp").retained === true
    refute Map.has_key?(Scenarios.fetch!("knowledge-research"), :retained)

    assert catch_error(
             Scenarios.parse!(
               ~w(source knowledge-mcp --sdk sdk --input artifact --output one --output two)
             )
           )

    assert catch_error(
             Scenarios.parse!(
               ~w(source knowledge-research --sdk sdk --input artifact --output evidence)
             )
           )
  end

  test "knowledge MCP result requires a retained path and scoped confirmed cleanup" do
    report = %{
      "checks" => 9,
      "model_requests" => 0,
      "host_loaded_domain_modules" => false,
      "cleanup" => "confirmed",
      "cleanup_scope" => "session_ack_and_backend_process_exit_only",
      "retained_root" => "/private/proof"
    }

    assert :ok = Scenarios.validate!(Scenarios.fetch!("knowledge-mcp"), report, "default")

    for bad <- [
          Map.delete(report, "retained_root"),
          Map.put(report, "cleanup", "unknown"),
          Map.put(report, "cleanup_scope", "all_descendants")
        ] do
      assert catch_error(Scenarios.validate!(Scenarios.fetch!("knowledge-mcp"), bad, "default"))
    end

    assert :ok =
             Scenarios.validate!(
               Scenarios.fetch!("knowledge-research"),
               %{"checks" => 17, "model_requests" => 0, "host_loaded_domain_modules" => false},
               "default"
             )
  end

  test "default retained runtime reports its private root and keeps callback failure data" do
    spec =
      Scenarios.fetch!("memory") |> Map.put(:name, "knowledge-mcp") |> Map.put(:retained, true)

    observer = self()

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, "synthetic callback failure", fn ->
          Runtime.with_runtime(spec, options(), fn runtime ->
            send(observer, {:retained_output, Path.dirname(runtime.root)})

            File.write!(Path.join(runtime.tmp, "synthetic-unknown.jsonl"), "fixture only\n", [
              :exclusive
            ])

            raise "synthetic callback failure"
          end)
        end
      end)

    assert_receive {:retained_output, output}
    on_exit(fn -> File.rm_rf!(output) end)
    assert stderr =~ "KNOWLEDGE_MCP_RETAINED_OUTPUT=" <> output
    assert Bitwise.band(File.stat!(output).mode, 0o077) == 0

    assert File.read!(Path.join(output, "runtime/tmp/synthetic-unknown.jsonl")) ==
             "fixture only\n"

    failure =
      output |> Path.join("runtime/verification-failure.json") |> File.read!() |> JSON.decode!()

    assert failure["callback_failed"] === true
    assert failure["inventories_unchanged"] === true
  end

  test "explicit output survives success, refuses reuse and cannot overlap the input" do
    parent = Path.join(System.tmp_dir!(), "ipse-mcp-retention-test-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)

    spec =
      Scenarios.fetch!("memory") |> Map.put(:name, "knowledge-mcp") |> Map.put(:retained, true)

    output = Path.join(parent, "evidence")

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        runtime = Runtime.with_runtime(spec, Keyword.put(options(), :output, output), & &1)
        assert runtime.root == Path.join(output, "runtime")
        assert File.dir?(runtime.tmp)
      end)

    assert stderr =~ "KNOWLEDGE_MCP_RETAINED_OUTPUT=" <> output
    assert Bitwise.band(File.stat!(output).mode, 0o077) == 0
    before = Runtime.inventory(output)

    assert_raise File.Error, fn ->
      Runtime.with_runtime(spec, Keyword.put(options(), :output, output), fn _ ->
        flunk("existing output reopened")
      end)
    end

    assert Runtime.inventory(output) == before
    input = Path.join(parent, "input")
    File.mkdir!(input)

    assert catch_error(
             Runtime.with_runtime(
               spec,
               [
                 sdk: Application.app_dir(:ipse, "ebin"),
                 input: input,
                 output: Path.join(input, "nested")
               ],
               fn _ -> flunk("overlap admitted") end
             )
           )
  end

  defp options do
    [
      sdk: Application.app_dir(:ipse, "ebin"),
      input: Path.expand("../../examples/memory-corpus.json", __DIR__)
    ]
  end
end
