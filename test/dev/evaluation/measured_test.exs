Code.require_file("../../../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../../../dev/verification/runtime.exs", __DIR__)
Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)
Code.require_file("../../../dev/evaluation/runner.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationMeasuredTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Evaluation.MeasuredExecution
  alias Ipse.Development.Evaluation.Runner

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

    assert MeasuredExecution.native_receipt?(receipt, 1000)

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
      refute MeasuredExecution.native_receipt?(Map.put(receipt, key, value), 1000),
             inspect({key, value})
    end

    for key <-
          ~w(version completion_policy population_drain_limit_ms population_exit elapsed_us natural_drain_us population_drain_ms) do
      refute MeasuredExecution.native_receipt?(Map.delete(receipt, key), 1000), key
    end

    assert MeasuredExecution.native_receipt?(
             Map.merge(receipt, %{"natural_drain_us" => 0, "population_drain_ms" => 0}),
             1000
           )

    boundary =
      Map.merge(receipt, %{
        "elapsed_us" => 3_000_000,
        "natural_drain_us" => 1_999_999,
        "population_drain_ms" => 1999
      })

    assert MeasuredExecution.native_receipt?(boundary, 4000)

    refute MeasuredExecution.native_receipt?(
             Map.merge(boundary, %{"natural_drain_us" => 2_000_000, "population_drain_ms" => 2000}),
             4000
           )

    refute MeasuredExecution.native_receipt?(receipt, 500)
    refute MeasuredExecution.native_receipt?(receipt, nil)
  end

  test "measured invocation rejects unbound options before effects", %{root: root} do
    assert {:error, %{"code" => "option_shape"}} = MeasuredExecution.run([])

    assert {:error, %{"code" => "option_shape"}} =
             MeasuredExecution.run(
               freeze: Path.join(root, "missing"),
               freeze_sha256: String.duplicate("a", 64),
               output: root
             )

    assert File.ls!(root) == []

    assert {:error, %{"code" => "freeze_identity"}} =
             MeasuredExecution.audit(Path.join(root, "missing"), "bad")

    assert File.ls!(root) == []
  end

  test "environment names alone cannot enter a claimed stage", %{root: root} do
    expected =
      if :os.type() == {:unix, :linux}, do: "authority_descriptor", else: "unsupported_platform"

    assert {:error, %{"code" => ^expected}} =
             MeasuredExecution.enter(Path.join(root, "must-not-open"))

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
      MeasuredExecution.command(
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

  test "legacy source execution cannot replace a captured precompiled evaluator" do
    assert :code.which(MeasuredExecution) == []
    {:ok, launch} = Ipse.Development.Evaluation.Freeze.runtime_launch()

    verified = %{
      "manifest" => %{"version" => 2, "runtime" => %{"launch" => launch, "files" => []}}
    }

    assert {:source, ^launch} = MeasuredExecution.execution_context!(verified)

    frozen_beam = %{
      "path" => "/captured/Elixir.Ipse.Development.Evaluation.MeasuredExecution.beam"
    }

    changed = put_in(verified, ["manifest", "runtime", "files"], [frozen_beam])

    assert catch_throw(MeasuredExecution.execution_context!(changed)) ==
             {:measured_execution, :precompiled_module}
  end

  test "stage admission budgets the complete resolved native measurement command", %{root: root} do
    directory = Path.join(root, String.duplicate("long-target-", 12))
    File.mkdir!(directory)
    File.write!(Path.join(directory, "ipse-runner"), "fixture")
    File.ln_s!(directory, Path.join(root, "short"))
    helper = Path.join(root, "short/ipse-runner")
    {:ok, resolved} = Ipse.Workspace.canonical_path(helper)
    assert byte_size(resolved) > byte_size(helper)

    stage = %{
      token: String.duplicate("a", 32),
      timeout: 180_000,
      output: "/private/measurement/雪/metric-cell-013",
      argv: ["/selected/erts/bin/erl", "-eval", ""]
    }

    wrapper = [resolved, "--measure-stage", "cell", stage.token, "180000", stage.output, "--"]
    bytes = Enum.sum(Enum.map(wrapper ++ stage.argv, &byte_size/1))
    exact = %{stage | argv: List.replace_at(stage.argv, 2, String.duplicate(" ", 65_536 - bytes))}
    assert :ok = MeasuredExecution.validate_stage_launch!(helper, exact)

    oversized = %{exact | argv: List.update_at(exact.argv, 2, &(&1 <> " "))}
    assert Enum.sum(Enum.map(oversized.argv, &byte_size/1)) < 65_536

    assert catch_throw(MeasuredExecution.validate_stage_launch!(helper, oversized)) ==
             {:measured_execution, :stage_argument_limit}
  end

  test "read-only domain audit detects changed and extra artifacts", %{root: root} do
    path = Path.join(root, "journal.jsonl")
    File.write!(path, "first\n")

    report = %{
      "files" => [
        %{"path" => "journal.jsonl", "bytes" => 6, "sha256" => Ipse.JSON.sha256("first\n")}
      ]
    }

    assert :ok = Runner.audit_cell(root, report)
    File.write!(path, "other\n")

    assert catch_throw(Runner.audit_cell(root, report)) ==
             {:evaluation_runner, :domain_files_changed}

    File.write!(path, "first\n")
    File.write!(Path.join(root, "extra"), "")

    assert catch_throw(Runner.audit_cell(root, report)) ==
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

    bytes = Map.new(names, &{&1, File.read!(Path.join(output, &1))})

    expected =
      {Map.new(bytes, fn {name, value} -> {name, Ipse.JSON.sha256(value)} end),
       Map.delete(bytes, "execution.jsonl")}

    audited_cells = closed_streams(cells, names)
    assert Runner.audit_merged_files(audited_cells, output) == expected

    for name <- names do
      path = Path.join(output, name)
      original = File.read!(path)
      changed = String.replace(original, "first", "other")
      File.write!(path, changed)

      code =
        if name == "predictions.jsonl",
          do: :first_predictions_changed,
          else: :merged_stream_changed

      assert catch_throw(Runner.audit_merged_files(audited_cells, output)) ==
               {:evaluation_runner, code}

      assert File.read!(path) == changed
      assert File.read!(Path.join(hd(cells), name)) == "first #{name}\n"

      File.write!(Path.join(hd(cells), name), "other #{name}\n")

      assert catch_throw(Runner.audit_merged_files(audited_cells, output)) ==
               {:evaluation_runner, code}

      File.write!(Path.join(hd(cells), name), "first #{name}\n")
      File.write!(path, original)
    end

    path = Path.join(output, "request-resources.jsonl")
    original = File.read!(path)
    File.write!(path, "")

    assert catch_throw(Runner.audit_merged_files(audited_cells, output)) ==
             {:evaluation_runner, :merged_stream_changed}

    assert File.read!(path) == ""
    File.write!(path, original)

    assert catch_throw(Runner.audit_merged_files(Enum.reverse(audited_cells), output)) ==
             {:evaluation_runner, :first_predictions_changed}

    assert Runner.audit_merged_files(audited_cells, output) == expected
  end

  test "raw execution audit accepts the bounded concatenation above 64 MiB", %{root: root} do
    cells = Enum.map(~w(first second), &Path.join(root, &1))
    output = Path.join(root, "merged")

    names =
      ~w(predictions.jsonl execution.jsonl usage.jsonl request-resources.jsonl resources.jsonl timings.jsonl)

    for directory <- cells ++ [output] do
      File.mkdir!(directory)
      for name <- names, do: File.write!(Path.join(directory, name), "")
    end

    chunk = :binary.copy("x", 1_048_576)

    for {directory, count, tail} <- [
          {hd(cells), 32, ""},
          {List.last(cells), 32, "x"},
          {output, 64, "x"}
        ] do
      File.open!(Path.join(directory, "execution.jsonl"), [:write, :binary], fn io ->
        for _ <- 1..count, do: IO.binwrite(io, chunk)
        IO.binwrite(io, tail)
      end)
    end

    execution = Path.join(output, "execution.jsonl")
    assert File.stat!(execution).size == 67_108_865

    digest =
      execution
      |> File.stream!(65_536)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    audited_cells = closed_streams(cells, names)
    {identities, parsed} = Runner.audit_merged_files(audited_cells, output)
    assert identities["execution.jsonl"] == digest
    refute Map.has_key?(parsed, "execution.jsonl")
    assert Enum.all?(parsed, fn {_, bytes} -> bytes == "" end)

    File.open!(execution, [:read, :write, :binary], fn io ->
      :ok = :file.pwrite(io, 67_108_864, "y")
    end)

    assert catch_throw(Runner.audit_merged_files(audited_cells, output)) ==
             {:evaluation_runner, :merged_stream_changed}

    assert File.stat!(execution).size == 67_108_865
  end

  test "merged comparison retains parsed-stream and individual cell limits", %{root: root} do
    cell = Path.join(root, "cell")
    output = Path.join(root, "merged")

    names =
      ~w(predictions.jsonl execution.jsonl usage.jsonl request-resources.jsonl resources.jsonl timings.jsonl)

    for directory <- [cell, output] do
      File.mkdir!(directory)
      for name <- names, do: File.write!(Path.join(directory, name), "")
    end

    [closed] = closed_streams([cell], names)

    for {name, bytes} <- [{"execution.jsonl", 67_108_865}, {"usage.jsonl", 33_554_433}] do
      oversized = %{
        closed
        | files:
            Enum.map(closed.files, fn file ->
              if file["path"] == name, do: Map.put(file, "bytes", bytes), else: file
            end)
      }

      assert catch_throw(Runner.audit_merged_files([oversized], output)) ==
               {:evaluation_runner, :file_limit}
    end
  end

  defp closed_streams(paths, names) do
    Enum.map(paths, fn path ->
      files =
        Enum.map(names, fn name ->
          file = Path.join(path, name)

          digest =
            file
            |> File.stream!(65_536)
            |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
            |> :crypto.hash_final()
            |> Base.encode16(case: :lower)

          %{"path" => name, "bytes" => File.stat!(file).size, "sha256" => digest}
        end)

      %{path: path, files: files}
    end)
  end

  test "the current selected ERTS actually boots with exact paths and literal arguments" do
    {:ok, launch} = Ipse.Development.Evaluation.Freeze.runtime_launch()
    supplied = ["untrusted \"quote\"; System.halt(99)", "雪\nsecond line"]

    {executable, arguments} =
      MeasuredExecution.command(
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
             Runner.seal_predictions(
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
