Code.require_file("../examples/knowledge/evaluation_plan.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationMeasuredTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.{EvaluationMeasuredExecution, EvaluationRunner}
  alias Ipse.Extensions.Manifest

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-measured-boundary-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "native receipt acceptance requires the declared completion policy and original timeout" do
    receipt = %{
      "version" => 2,
      "metric" => "linux_memcg_charged_peak_bytes_v1",
      "completion_policy" => "bounded_natural_drain_v1",
      "population_drain_limit_ms" => 2000,
      "population_drain_ms" => 215,
      "natural_drain_us" => 215_123,
      "elapsed_us" => 500_000,
      "population_exit" => "natural",
      "complete" => true,
      "cleanup_confirmed" => true,
      "born_in_scope" => true,
      "exit_code" => 0,
      "reason" => "completed",
      "peak_bytes" => 1234
    }

    assert EvaluationMeasuredExecution.native_receipt?(receipt, 1000)

    for {key, value} <- [
          {"version", 1},
          {"version", 3},
          {"completion_policy", "other"},
          {"population_drain_limit_ms", 3000},
          {"population_exit", "forced"},
          {"elapsed_us", 1_000_000},
          {"elapsed_us", -1},
          {"elapsed_us", 499_999.0},
          {"natural_drain_us", nil},
          {"natural_drain_us", -1},
          {"natural_drain_us", 500_001},
          {"natural_drain_us", 2_000_000},
          {"population_drain_ms", 214},
          {"complete", false},
          {"cleanup_confirmed", false},
          {"exit_code", 7},
          {"reason", "timeout"}
        ] do
      refute EvaluationMeasuredExecution.native_receipt?(Map.put(receipt, key, value), 1000),
             inspect({key, value})
    end

    for key <-
          ~w(version completion_policy population_drain_limit_ms population_exit elapsed_us natural_drain_us population_drain_ms) do
      refute EvaluationMeasuredExecution.native_receipt?(Map.delete(receipt, key), 1000), key
    end

    assert EvaluationMeasuredExecution.native_receipt?(
             Map.merge(receipt, %{"natural_drain_us" => 0, "population_drain_ms" => 0}),
             1000
           )

    boundary =
      Map.merge(receipt, %{
        "elapsed_us" => 3_000_000,
        "natural_drain_us" => 1_999_999,
        "population_drain_ms" => 1999
      })

    assert EvaluationMeasuredExecution.native_receipt?(boundary, 4000)

    refute EvaluationMeasuredExecution.native_receipt?(
             Map.merge(boundary, %{"natural_drain_us" => 2_000_000, "population_drain_ms" => 2000}),
             4000
           )

    refute EvaluationMeasuredExecution.native_receipt?(receipt, 500)
    refute EvaluationMeasuredExecution.native_receipt?(receipt, nil)
  end

  test "measured invocation rejects unbound options before effects", %{root: root} do
    assert {:error, %{"code" => "option_shape"}} = EvaluationMeasuredExecution.run([])

    assert {:error, %{"code" => "option_shape"}} =
             EvaluationMeasuredExecution.run(
               freeze: Path.join(root, "missing"),
               freeze_sha256: String.duplicate("a", 64),
               output: root
             )

    assert File.ls!(root) == []

    assert {:error, %{"code" => "freeze_identity"}} =
             EvaluationMeasuredExecution.audit(Path.join(root, "missing"), "bad")

    assert File.ls!(root) == []
  end

  test "environment names alone cannot enter a claimed stage", %{root: root} do
    expected =
      if :os.type() == {:unix, :linux}, do: "authority_descriptor", else: "unsupported_platform"

    assert {:error, %{"code" => ^expected}} =
             EvaluationMeasuredExecution.enter(Path.join(root, "must-not-open"))

    assert File.ls!(root) == []
  end

  test "the selected ERTS command restores paths before loading scripts and encodes caller strings" do
    launch = %{
      "executable" => "/runtime/erts/bin/erl",
      "root" => "/runtime",
      "boot" => "/runtime/bin/no_dot_erlang",
      "code_paths" => ["/first/ebin", "/second/ebin"]
    }

    marker = "untrusted \"quote\"; System.halt(99)"

    {executable, arguments} =
      EvaluationMeasuredExecution.command(
        launch,
        ["/selected/script.exs"],
        "IO.puts(hd(System.argv()))",
        [marker]
      )

    assert executable == launch["executable"]

    assert [
             "+S",
             "2:2",
             "+A",
             "1",
             "-noshell",
             "-mode",
             "interactive",
             "-boot",
             "/runtime/bin/no_dot_erlang",
             "-boot_var",
             "RELEASE_LIB",
             "/runtime/lib",
             "-eval",
             expression
           ] = arguments

    refute expression =~ marker
    assert expression =~ "true=(code:get_path()=:=P)"

    [_, paths] =
      Regex.run(~r/P=binary_to_term\(base64:decode\("([A-Za-z0-9+\/=]+)"\)/, expression)

    assert :erlang.binary_to_term(Base.decode64!(paths), [:safe]) == [
             ~c"/first/ebin",
             ~c"/second/ebin"
           ]

    [_, code] = Regex.run(~r/eval_string\(base64:decode\("([A-Za-z0-9+\/=]+)"\)/, expression)
    decoded = Base.decode64!(code)
    assert {:ok, _} = Code.string_to_quoted(decoded)
    assert decoded =~ "Code.require_file(\"/selected/script.exs\")"
  end

  test "read-only domain audit detects changed and extra artifacts", %{root: root} do
    path = Path.join(root, "journal.jsonl")
    File.write!(path, "first\n")

    report = %{
      "files" => [
        %{"path" => "journal.jsonl", "bytes" => 6, "sha256" => Manifest.sha256("first\n")}
      ]
    }

    assert :ok = EvaluationRunner.audit_cell(root, report)
    File.write!(path, "other\n")

    assert catch_throw(EvaluationRunner.audit_cell(root, report)) ==
             {:evaluation_runner, :domain_files_changed}

    File.write!(path, "first\n")
    File.write!(Path.join(root, "extra"), "")

    assert catch_throw(EvaluationRunner.audit_cell(root, report)) ==
             {:evaluation_runner, :domain_files_changed}
  end

  test "merged evidence must equal every closed cell stream in schedule order", %{root: root} do
    cells = Enum.map(~w(first second), &Path.join(root, &1))
    output = Path.join(root, "merged")
    for directory <- cells ++ [output], do: File.mkdir!(directory)

    names =
      ~w(predictions.jsonl execution.jsonl usage.jsonl request-resources.jsonl resources.jsonl timings.jsonl)

    for name <- names do
      File.write!(Path.join(hd(cells), name), "first #{name}\n")
      File.write!(Path.join(List.last(cells), name), "second #{name}\n")
      File.write!(Path.join(output, name), "first #{name}\nsecond #{name}\n")
    end

    expected = Map.new(names, &{&1, File.read!(Path.join(output, &1))})
    assert EvaluationRunner.audit_merged_files(cells, output) == expected

    for name <- names do
      path = Path.join(output, name)
      original = File.read!(path)
      changed = String.replace(original, "first", "other")
      File.write!(path, changed)

      code =
        if name == "predictions.jsonl",
          do: :first_predictions_changed,
          else: :merged_stream_changed

      assert catch_throw(EvaluationRunner.audit_merged_files(cells, output)) ==
               {:evaluation_runner, code}

      assert File.read!(path) == changed
      assert File.read!(Path.join(hd(cells), name)) == "first #{name}\n"
      File.write!(path, original)
    end

    path = Path.join(output, "request-resources.jsonl")
    original = File.read!(path)
    File.write!(path, "")

    assert catch_throw(EvaluationRunner.audit_merged_files(cells, output)) ==
             {:evaluation_runner, :merged_stream_changed}

    assert File.read!(path) == ""
    File.write!(path, original)

    assert catch_throw(EvaluationRunner.audit_merged_files(Enum.reverse(cells), output)) ==
             {:evaluation_runner, :first_predictions_changed}

    assert EvaluationRunner.audit_merged_files(cells, output) == expected
  end

  test "the current selected ERTS actually boots with exact paths and literal arguments" do
    {:ok, launch} = IpseKnowledgeExample.EvaluationFreeze.runtime_launch()
    supplied = ["untrusted \"quote\"; System.halt(99)", "雪\nsecond line"]

    {executable, arguments} =
      EvaluationMeasuredExecution.command(
        launch,
        [],
        "IO.puts(JSON.encode!(%{argv: System.argv(), paths: Enum.map(:code.get_path(), &to_string/1)}))",
        supplied
      )

    {bytes, status} =
      System.cmd(executable, arguments,
        env: [{"ERL_CRASH_DUMP", "/dev/null"}],
        stderr_to_stdout: true
      )

    assert status == 0, bytes

    assert JSON.decode!(String.trim(bytes)) == %{
             "argv" => supplied,
             "paths" => launch["code_paths"]
           }
  end

  test "sealing refuses duplicate first rows before replacing any output", %{root: root} do
    input = Path.join(root, "cell")
    output = Path.join(root, "merged")
    File.mkdir!(input)
    File.mkdir!(output)
    row = %{"variant" => "lexical", "query_id" => "q", "project" => "alpha"}
    bytes = JSON.encode!(row) <> "\n"
    File.write!(Path.join(input, "predictions.jsonl"), bytes <> bytes)
    plan = %{"data" => %{"expected_queries" => 1}, "variants" => [%{"id" => "lexical"}]}

    assert catch_throw(
             EvaluationRunner.seal_predictions(
               plan,
               [%{"query_id" => "q", "project" => "alpha"}],
               [input],
               output,
               nil
             )
           ) == {:evaluation_runner, :prediction_grid}

    assert File.ls!(output) == []
    assert File.read!(Path.join(input, "predictions.jsonl")) == bytes <> bytes
  end
end
