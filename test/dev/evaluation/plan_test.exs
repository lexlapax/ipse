Code.require_file("../../../dev/verification/scenarios.exs", __DIR__)
Code.require_file("../../../dev/verification/runtime.exs", __DIR__)
Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)
Code.require_file("../../../dev/evaluation/runner.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationContractTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Evaluation.Contract
  alias Ipse.Development.Evaluation.Runner
  @variants ~w(lexical graph_explicit graph_model dense hybrid rerank research)

  defp spec do
    JSON.decode!(File.read!("dev/evaluation/benchmark-spec.json"))
    |> Map.put("blind_seed", String.duplicate("b", 64))
  end

  test "a fresh declaration VM loads no execution or fixture implementation" do
    root = Path.join(System.tmp_dir!(), "ipse-declaration-purity-" <> Ipse.Usage.id())
    contract = Path.expand("dev/evaluation/contract.exs")

    declared =
      spec()
      |> Map.update!("artifacts", &Map.new(&1, fn {id, _} -> {id, Path.join(root, id)} end))
      |> put_in(["data", "corpus"], "absent/corpus.json")
      |> put_in(["data", "queries"], "absent/queries.json")

    expression = """
    before = Code.required_files()
    Code.require_file(#{inspect(contract)})
    {:ok, plan} = Ipse.Development.Evaluation.Contract.build(#{inspect(declared)})
    :ok = Ipse.Development.Evaluation.Contract.validate(plan)
    [#{inspect(contract)}] = Code.required_files() -- before
    for module <- [Ipse.Development.Evaluation.Runner,
      Ipse.Development.Evaluation.Freeze, Ipse.Development.Evaluation.Session,
      Ipse.Development.Evaluation.ModelService, Ipse.Development.Evaluation.Score,
      Ipse.Development.Fixtures.Knowledge] do
      false = :code.is_loaded(module)
    end
    IO.puts("pure declaration passed")
    """

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    assert {"pure declaration passed\n", 0} =
             System.cmd(
               System.find_executable("elixir"),
               ["--erl", "+S 2:2 +A 1"] ++ paths ++ ["-e", expression],
               stderr_to_stdout: true
             )

    refute File.exists?(root)
  end

  defp sealed_spec do
    origin = "http://127.0.0.1:47635"

    spec()
    |> Map.put("version", 2)
    |> Map.put("model_origin", origin)
    |> Map.update!(
      "data",
      &Map.merge(&1, %{
        "contract" => "sealed_answers_v1",
        "queries" => "queries.json",
        "manifest_sha256" => String.duplicate("c", 64)
      })
    )
    |> Map.update!(
      "profiles",
      &Map.new(&1, fn {id, p} -> {id, Map.put(p, "base_url", origin)} end)
    )
    |> Map.update!(
      "embedding_profiles",
      &Map.new(&1, fn {id, p} -> {id, Map.put(p, "base_url", origin)} end)
    )
  end

  test "long-answer policy freezes only the answer override, reasoning and reservations" do
    contracts = %{
      "outputs" => %{
        "answer" => "json_schema_v3",
        "extract" => "json_schema_v2",
        "rerank" => "json_schema_v2"
      },
      "selection" => "per_strategy_eligibility_v1"
    }

    declared =
      sealed_spec()
      |> Map.put("version", 3)
      |> Map.put("contracts", contracts)
      |> update_in(["profiles", "p27_answer"], fn p ->
        p
        |> Map.delete("reasoning_effort")
        |> Map.put("max_output_tokens", 8192)
        |> Map.put("model_call_timeout_ms", 480_000)
      end)
      |> Map.update!(
        "budgets",
        &Map.new(&1, fn {id, b} -> {id, Map.put(b, "reserve_output_tokens", 8192)} end)
      )

    assert {:ok, plan} = Contract.build(declared)
    assert :ok = Contract.validate_shape(plan, :execution)
    assert Contract.long_answers?(plan)
    assert Contract.answer_timeout_ms(plan) == 480_000
    assert Contract.session_timeout_ms(plan) == 540_000
    assert plan["profiles"]["p27_extract"]["reasoning_effort"] == "none"
    assert plan["profiles"]["p27_rerank"]["max_output_tokens"] == 4096

    for bad <- [
          update_in(
            declared,
            ["profiles", "p27_answer"],
            &Map.delete(&1, "model_call_timeout_ms")
          ),
          put_in(declared, ["profiles", "p27_answer", "model_call_timeout_ms"], 120_000),
          put_in(declared, ["profiles", "p27_extract", "model_call_timeout_ms"], 480_000),
          put_in(declared, ["profiles", "p27_answer", "reasoning_effort"], "none"),
          put_in(declared, ["profiles", "p27_answer", "max_output_tokens"], 4096),
          put_in(declared, ["budgets", "lexical", "reserve_output_tokens"], 4096),
          put_in(declared, ["contracts", "outputs", "extract"], "json_schema_v3"),
          put_in(declared, ["contracts", "outputs", "answer"], "json_schema_v2")
        ],
        do: assert({:error, _} = Contract.build(bad))

    assert {:ok, old} = Contract.build(sealed_spec())
    refute Contract.long_answers?(old)
    assert Contract.answer_timeout_ms(old) == 120_000
    assert Contract.session_timeout_ms(old) == 180_000
  end

  test "new generation requires every structured task and its individual qualification policy" do
    contracts = %{
      "outputs" => %{
        "answer" => "json_schema_v2",
        "extract" => "json_schema_v2",
        "rerank" => "json_schema_v2"
      },
      "selection" => "per_strategy_eligibility_v1"
    }

    declared = sealed_spec() |> Map.put("version", 3) |> Map.put("contracts", contracts)
    assert {:ok, plan} = Contract.build(declared)
    assert plan["contracts"] == contracts
    assert :ok = Contract.validate(plan)
    assert :ok = Contract.validate_shape(plan, :execution)

    profiles =
      for variant <- plan["variants"],
          entry <- variant["artifacts"],
          family <- ~w(extraction rerank),
          p <- Map.values(entry["options"][family] || %{}),
          p["kind"] == "model_complete",
          do: p

    assert length(profiles) == 2
    assert Enum.all?(profiles, &(&1["output_contract"] == "json_schema_v2"))

    for changed <- [
          Map.delete(declared, "contracts"),
          Map.put(declared, "version", 2),
          put_in(declared, ["contracts", "selection"], "complete_frozen_grid"),
          put_in(declared, ["contracts", "outputs", "answer"], "text_v1"),
          put_in(declared, ["contracts", "outputs", "extract"], "text_v1"),
          put_in(declared, ["contracts", "outputs", "rerank"], "text_v1")
        ] do
      assert {:error, _} = Contract.build(changed)
    end

    changed =
      update_in(plan, ["variants"], fn variants ->
        Enum.map(variants, fn v ->
          if v["id"] == "graph_model" do
            update_in(v, ["artifacts"], fn entries ->
              Enum.map(entries, fn e ->
                if e["instance"] == "graph",
                  do:
                    update_in(
                      e,
                      ["options", "extraction", "chosen"],
                      &Map.delete(&1, "output_contract")
                    ),
                  else: e
              end)
            end)
          else
            v
          end
        end)
      end)

    assert {:error, :output_contract} = Contract.validate(changed)

    root = Path.join(System.tmp_dir!(), "ipse-structured-entry-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "plan.json")
    File.write!(path, JSON.encode!(plan))

    for phase <- [:freeze, :verify, :tune] do
      output = Path.join(root, Atom.to_string(phase))
      options = [plan: path, output: output]

      options =
        if phase == :freeze,
          do: options,
          else:
            options ++
              [
                corpus: Path.join(root, "absent-corpus"),
                queries: Path.join(root, "absent-queries")
              ]

      assert {:error, %{"code" => "measured_entry_required"}} =
               Runner.run(phase, options)

      refute File.exists?(output)
    end
  end

  defp trace_files(fun) do
    functions = [
      {File, :read!, 1},
      {File, :open, 3},
      {File, :lstat!, 1},
      {File, :stat!, 1},
      {File, :exists?, 1}
    ]

    for mfa <- functions, do: :erlang.trace_pattern(mfa, true, [:local])
    owner = self()

    worker =
      spawn(fn ->
        receive do
          :go ->
            outcome =
              try do
                {:ok, fun.()}
              catch
                kind, reason -> {:raised, kind, reason, __STACKTRACE__}
              end

            send(owner, {:outcome, self(), outcome})
            receive do: (:stop -> :ok)
        end
      end)

    try do
      :erlang.trace(worker, true, [:call, {:tracer, self()}])
      send(worker, :go)
      assert_receive {:outcome, ^worker, outcome}, 15_000
      ref = :erlang.trace_delivered(worker)
      assert_receive {:trace_delivered, ^worker, ^ref}, 1_000
      calls = drain_calls(worker, [])

      case outcome do
        {:ok, result} -> {result, calls}
        {:raised, kind, reason, stack} -> :erlang.raise(kind, reason, stack)
      end
    after
      send(worker, :stop)
      for mfa <- functions, do: :erlang.trace_pattern(mfa, false, [:local])
    end
  end

  defp drain_calls(pid, calls) do
    receive do
      {:trace, ^pid, :call, {File, function, [path | _]}} ->
        drain_calls(pid, [{function, path} | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end

  test "new sealed workload uses the v2 builder without relaxing heldout model or grid policies" do
    declared = sealed_spec()
    assert {:ok, plan} = Contract.build(declared)
    assert :ok = Contract.validate(plan)
    assert plan["data"] == declared["data"]

    fixture_spec =
      declared |> Map.put("mode", "fixture") |> Map.put("as_of_ms", 1_800_000_000_000)

    assert {:error, :fixture_models} = Contract.build(fixture_spec)

    fixture =
      fixture_spec
      |> Map.put("models", %{
        "fixture-text:latest" => String.duplicate("a", 64),
        "fixture-embedding:latest" => String.duplicate("b", 64)
      })
      |> Map.update!(
        "profiles",
        &Map.new(&1, fn {id, profile} ->
          {id, Map.put(profile, "model", "fixture-text:latest")}
        end)
      )
      |> Map.update!(
        "embedding_profiles",
        &Map.new(&1, fn {id, profile} ->
          {id, Map.put(profile, "model", "fixture-embedding:latest")}
        end)
      )

    assert {:ok, _} = Contract.build(fixture)
    assert {:error, _} = Contract.build(Map.put(fixture, "mode", "heldout"))

    assert {:error, :heldout_manifest} =
             Contract.build(update_in(declared, ["data"], &Map.delete(&1, "contract")))

    for changed <- [
          Map.delete(declared, "model_origin"),
          Map.put(declared, "extra", true),
          declared |> Map.put("version", 1) |> Map.delete("model_origin"),
          Map.put(declared, "mode", "fixture"),
          put_in(declared, ["data", "split"], "tuning"),
          put_in(declared, ["data", "labels"], "must-not-open"),
          put_in(declared, ["data", "expected_queries"], 49),
          put_in(declared, ["models", "qwen3.5:9b"], String.duplicate("0", 64)),
          put_in(declared, ["profiles", "p27_answer", "max_output_tokens"], 2048)
        ] do
      assert {:error, _} = Contract.build(changed)
    end
  end

  test "sealed preparation reads only committed corpus and questions, and refuses extra descriptors" do
    root = Path.join(System.tmp_dir!(), "ipse-sealed-inputs-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    corpus = JSON.encode!(%{"schema_version" => 1, "documents" => []})

    questions =
      for n <- 1..50,
          do: %{
            "query_id" => "q#{n}",
            "project" => if(n <= 25, do: "alpha", else: "beta"),
            "query" => "Synthetic question #{n}?"
          }

    queries =
      JSON.encode!(%{
        "contract" => "sealed_answers_v1",
        "split" => "heldout",
        "queries" => questions
      })

    File.write!(Path.join(root, "corpus.json"), corpus)
    File.write!(Path.join(root, "queries.json"), queries)
    answers = Path.join(root, "must-not-open-answers.json")

    manifest = %{
      "contract" => "sealed_answers_v1",
      "as_of_ms" => 1_800_000_000_000,
      "inputs" => %{
        "corpus" => %{
          "path" => "corpus.json",
          "sha256" => Ipse.JSON.sha256(corpus)
        },
        "queries" => %{
          "path" => "queries.json",
          "sha256" => Ipse.JSON.sha256(queries)
        }
      },
      "answers_sha256" => String.duplicate("a", 64)
    }

    path = Path.join(root, "manifest.json")

    write_plan = fn value ->
      bytes = JSON.encode!(value)
      File.write!(path, bytes)

      declared =
        put_in(sealed_spec(), ["data", "manifest_sha256"], Ipse.JSON.sha256(bytes))

      {:ok, plan} = Contract.build(declared)
      plan
    end

    plan = write_plan.(manifest)
    output = Path.join(root, "prepared")
    File.mkdir!(output)

    {{:ok, prepared}, calls} =
      trace_files(fn -> Runner.prepare_inputs(plan, path, output) end)

    assert prepared["queries"] == questions
    assert length(prepared["schedule"]["cells"]) == 14
    assert {:lstat!, path} in calls
    refute Enum.any?(calls, fn {_function, file} -> file == answers end)
    refute File.exists?(answers)
    refute JSON.encode!(prepared) =~ "commitment_nonce"

    File.write!(answers, "synthetic answer access sentinel")

    {_, positive} =
      trace_files(fn ->
        File.lstat!(answers)
        File.read!(answers)
      end)

    assert {:lstat!, answers} in positive and {:read!, answers} in positive
    present = Path.join(root, "prepared-with-sentinel")
    File.mkdir!(present)

    {{:ok, again}, calls} =
      trace_files(fn -> Runner.prepare_inputs(plan, path, present) end)

    assert again == prepared
    refute Enum.any?(calls, fn {_function, file} -> file == answers end)

    changed =
      put_in(manifest, ["inputs", "answers"], %{
        "path" => answers,
        "sha256" => String.duplicate("a", 64)
      })

    assert {:error, %{"code" => "data_manifest_members"}} =
             Runner.prepare_inputs(
               write_plan.(changed),
               path,
               Path.join(root, "never-created")
             )

    assert {:error, %{"code" => "data_manifest_shape"}} =
             Runner.prepare_inputs(
               write_plan.(
                 Map.put(manifest, "answers", %{
                   "path" => answers,
                   "sha256" => String.duplicate("a", 64)
                 })
               ),
               path,
               Path.join(root, "never-created")
             )

    plan = write_plan.(manifest)
    File.write!(Path.join(root, "queries.json"), queries <> " ")

    assert {:error, %{"code" => "data_member_hash"}} =
             Runner.prepare_inputs(plan, path, Path.join(root, "never-created"))

    refute File.exists?(Path.join(root, "never-created"))

    legacy =
      JSON.encode!(%{
        "schema_version" => 1,
        "queries" =>
          Enum.map(
            questions,
            &Map.merge(&1, %{
              "split" => "heldout",
              "expected_answer" => "PRIVATE_LEGACY_LABEL",
              "expected_class" => "answer",
              "relevance" => []
            })
          )
      })

    File.write!(Path.join(root, "queries.json"), legacy)

    legacy_manifest =
      put_in(manifest, ["inputs", "queries", "sha256"], Ipse.JSON.sha256(legacy))

    legacy_plan = write_plan.(legacy_manifest)
    legacy_output = Path.join(root, "legacy-shaped")
    File.mkdir!(legacy_output)

    {refused, calls} =
      trace_files(fn -> Runner.prepare_inputs(legacy_plan, path, legacy_output) end)

    assert {:error, %{"code" => "data_query_contract"}} = refused
    refute Enum.any?(calls, fn {_function, file} -> file == answers end)
    assert File.ls!(legacy_output) == []
  end

  test "author CLI validates fifty detached rows and emits only private manifest metadata" do
    root = Path.join(System.tmp_dir!(), "ipse-dataset-author-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    corpus = Path.join(root, "corpus.json")
    queries = Path.join(root, "queries.json")
    answers = Path.join(root, "custody.json")
    output = Path.join(root, "manifest.json")
    File.write!(corpus, JSON.encode!(%{"schema_version" => 1, "documents" => []}))

    rows =
      for n <- 1..50,
          do: %{
            "query_id" => "q#{n}",
            "project" => if(n <= 25, do: "alpha", else: "beta"),
            "query" => "Synthetic question #{n}?"
          }

    File.write!(
      queries,
      JSON.encode!(%{"contract" => "sealed_answers_v1", "split" => "heldout", "queries" => rows})
    )

    labels =
      Enum.map(rows, fn row ->
        row
        |> Map.delete("query")
        |> Map.merge(%{
          "expected_class" => "open",
          "expected_refusal" => false,
          "expected_answer" => "PRIVATE_ANSWER_SENTINEL",
          "relevance" => []
        })
      end)

    File.write!(
      answers,
      JSON.encode!(%{
        "contract" => "sealed_answers_v1",
        "split" => "heldout",
        "commitment_nonce" => String.duplicate("f", 64),
        "answers" => labels
      })
    )

    code =
      Path.wildcard(Path.join([Path.dirname(Application.app_dir(:ipse)), "*", "ebin"]))
      |> Enum.flat_map(&["-pa", &1])

    args =
      code ++
        [
          Path.expand("dev/prepare-knowledge-dataset.exs"),
          "--corpus",
          corpus,
          "--queries",
          queries,
          "--answers",
          answers,
          "--as-of-ms",
          "1800000000000",
          "--output",
          output
        ]

    {bytes, 0} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    report = JSON.decode!(String.trim(bytes))
    assert report["status"] == "ok"
    assert report["result"]["query_count"] == 50 and report["result"]["project_count"] == 2
    refute bytes =~ "PRIVATE_ANSWER_SENTINEL"
    refute bytes =~ String.duplicate("f", 64)
    assert Bitwise.band(File.stat!(output).mode, 0o777) == 0o600
    manifest = File.read!(output)

    assert JSON.decode!(manifest)["answers_sha256"] ==
             Ipse.JSON.sha256(File.read!(answers))

    {failed, 1} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert JSON.decode!(String.trim(failed))["code"] == "invalid_dataset_or_output"
    assert File.read!(output) == manifest
    File.rm!(output)
    File.write!(answers, "{}")
    {failed, 1} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert JSON.decode!(String.trim(failed))["code"] == "invalid_dataset_or_output"
    refute File.exists?(output)
  end

  test "tuning derives one explicit local origin from all selected profiles" do
    origin = "http://127.0.0.1:47635"

    declared =
      spec()
      |> Map.put("mode", "tuning")
      |> Map.put("as_of_ms", 1_800_000_000_000)
      |> Map.update!(
        "profiles",
        &Map.new(&1, fn {id, p} -> {id, Map.put(p, "base_url", origin)} end)
      )
      |> Map.update!(
        "embedding_profiles",
        &Map.new(&1, fn {id, p} -> {id, Map.put(p, "base_url", origin)} end)
      )

    assert {:ok, plan} = Contract.build(declared)
    assert :ok = Contract.validate(plan)
    refute Map.has_key?(plan, "model_origin")

    for changed <- [
          put_in(declared, ["profiles", "p27_answer", "base_url"], "http://127.0.0.1:47636"),
          Map.put(declared, "search_port", 47635),
          Map.put(declared, "mode", "heldout")
        ] do
      assert {:error, :model_origin} = Contract.build(changed)
    end

    for bad <- [
          "http://127.0.0.1:0",
          "http://127.0.0.1:047635",
          "https://example.com",
          "http://127.0.0.1:47635/path",
          "http://user@127.0.0.1:47635"
        ] do
      changed =
        declared
        |> Map.update!(
          "profiles",
          &Map.new(&1, fn {id, p} -> {id, Map.put(p, "base_url", bad)} end)
        )
        |> Map.update!(
          "embedding_profiles",
          &Map.new(&1, fn {id, p} -> {id, Map.put(p, "base_url", bad)} end)
        )

      assert {:error, :model_origin} = Contract.build(changed)
    end
  end

  test "the complete declaration is valid without opening dataset members or artifacts" do
    declared = spec()
    assert {:ok, plan} = Contract.build(declared)
    assert :ok = Contract.validate(plan)
    assert plan["answer"] and Enum.map(plan["variants"], & &1["id"]) == @variants
    assert plan["data"] == declared["data"] and plan["models"] == declared["models"]
    assert Enum.all?(plan["variants"], &(&1["budget"] == declared["budgets"][&1["id"]]))
    assert Enum.all?(plan["variants"], &Map.has_key?(&1["bindings"], "answer"))
    assert plan["storage_policy"] == "forget_all_then_collect_v1"
    assert Enum.all?(Enum.drop(plan["variants"], -1), &Map.has_key?(&1["bindings"], "collect"))
    research = List.last(plan["variants"])
    assert research["query_options"]["limits"]["max_sources"] == 10
    assert :code.is_loaded(IpseKnowledge.Corpus) == false

    for mutated <- [
          Map.put(declared, "labels", "PRIVATE_LABELS"),
          Map.delete(declared, "budgets"),
          Map.delete(declared, "storage_policy"),
          Map.put(declared, "storage_policy", "unreviewed_cleanup"),
          update_in(declared, ["artifacts"], &Map.delete(&1, "answer")),
          put_in(declared, ["profiles", "p27_answer", "credential"], "unreviewed")
        ] do
      assert {:error, _} = Contract.build(mutated)
    end
  end

  test "CLI normalizes declared paths and creates one private plan without reading inputs" do
    root = Path.join(System.tmp_dir!(), "ipse-plan-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    input = Path.join(root, "spec.json")
    declared = spec() |> Map.put("blind_seed", nil)
    File.write!(input, JSON.encode!(declared))
    paths = Path.wildcard(Path.join([Path.dirname(Application.app_dir(:ipse)), "*", "ebin"]))
    code = Enum.flat_map(paths, &["-pa", &1])
    script = Path.expand("dev/prepare-knowledge-evaluation.exs")

    for name <- ~w(first second) do
      output = Path.join(root, name <> ".json")

      {message, status} =
        System.cmd(
          System.find_executable("elixir"),
          code ++ [script, "--spec", input, "--output", output, "--new-blind-seed"],
          stderr_to_stdout: true
        )

      assert status == 0, message
      result = JSON.decode!(String.trim(message))
      assert result["status"] == "ok" and result["result"]["variants"] == 7
      assert result["result"]["sha256"] == Ipse.JSON.sha256(File.read!(output))
      plan = JSON.decode!(File.read!(output))
      refute message =~ plan["blind_seed"]
      assert :ok = Contract.validate(plan)
      assert plan["artifacts"]["lexical"] == Path.join(root, "artifacts/lexical")
      assert Bitwise.band(File.stat!(output).mode, 0o777) == 0o600
    end

    first = File.read!(Path.join(root, "first.json"))
    second = File.read!(Path.join(root, "second.json"))
    refute JSON.decode!(first)["blind_seed"] == JSON.decode!(second)["blind_seed"]

    {message, status} =
      System.cmd(
        System.find_executable("elixir"),
        code ++
          [script, "--spec", input, "--output", Path.join(root, "first.json"), "--new-blind-seed"],
        stderr_to_stdout: true
      )

    assert status == 1 and JSON.decode!(String.trim(message))["status"] == "failed"
    assert File.read!(Path.join(root, "first.json")) == first
    refute File.exists?(Path.join(root, "artifacts"))
    refute File.exists?(Path.join(root, "corpus.json"))
    refute File.exists?(Path.join(root, "heldout.json"))
  end

  test "baseline budgets cover every project distribution of fifty answer requests" do
    declared = spec()

    for id <- ~w(lexical graph_explicit research), projects <- 1..50 do
      budget = declared["budgets"][id]
      largest_project = 51 - projects
      assert div(budget["max_requests"], projects) >= largest_project

      assert div(budget["max_input_tokens"], projects) >=
               largest_project * budget["reserve_input_tokens"]

      assert div(budget["max_output_tokens"], projects) >=
               largest_project * budget["reserve_output_tokens"]
    end
  end

  test "public Session and driver return all ten offline Research citations" do
    root = Path.join(System.tmp_dir!(), "ipse-research-capacity-" <> Ipse.Usage.id())
    artifact = Path.join(root, "artifact")
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          artifact,
          "--package",
          "research",
          "--preset",
          "offline"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    bytes = File.read!(Path.join(artifact, "extension.json"))
    manifest = JSON.decode!(bytes)
    digest = Ipse.JSON.sha256(bytes)
    options = JSON.decode!(File.read!("extensions/knowledge/options/research-offline.json"))

    selection = %{
      root: root,
      project: "synthetic",
      variant: "research",
      artifacts: [
        %{
          instance: "research",
          path: artifact,
          digest: digest,
          options: options,
          order: 0,
          trust: %{
            "artifact" => digest,
            "capabilities" => manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false
          }
        }
      ],
      runtime: %{
        provider: :demo,
        model: "unused",
        compact: false,
        budget: %{"version" => 1, "max_requests" => 1}
      },
      bindings: %{"research" => %{"instance" => "research", "id" => "investigate"}},
      required_verbs: ["research"],
      timeout_ms: 30_000,
      approval_validator: fn _ -> flunk("offline Research proposed a host action") end
    }

    alias Ipse.Development.Evaluation.Session
    assert {:ok, run} = Session.open(selection)

    try do
      sources =
        Enum.map(1..10, fn n ->
          %{
            "source_id" => "s#{n}",
            "generation" => 1,
            "title" => "Locks",
            "text" => "Lock files preserve inode identity.",
            "uri" => "local:s#{n}",
            "observed_at_ms" => 1,
            "event_at_ms" => nil,
            "expires_at_ms" => nil
          }
        end)

      args = %{
        "search" => "given",
        "fetch" => "given",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "lock files",
        "as_of_ms" => 20,
        "limits" => %{"max_sources" => 10, "max_body_bytes" => 1024, "timeout_ms" => 5000},
        "sources" => sources
      }

      assert {:ok, receipt, next} = Session.invoke(run, "research", args)
      result = receipt["value"]
      assert result["status"] == "ok" and length(result["evidence"]) == 10
      assert hd(result["claims"])["evidence_indexes"] == Enum.to_list(0..9)
      assert {:ok, snapshot} = Session.snapshot(next)
      assert snapshot["accounting"]["request_count"] == 0
      assert length(next.receipts) == 1
      assert is_binary(hd(next.receipts)["result_sha256"])
      assert :code.is_loaded(IpseKnowledge.Research) == false
    after
      assert {:ok, %{"cleanup" => "confirmed"}} = Session.close(run)
    end
  end
end
