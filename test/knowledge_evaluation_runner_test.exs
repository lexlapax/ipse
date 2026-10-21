Code.require_file("../dev/verification/cli.exs", __DIR__)
Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)
Code.require_file("../dev/evaluation/runner.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationRunnerTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Evaluation.Runner, as: Runner
  alias Ipse.Development.Evaluation.Contract, as: Contract

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-runner-" <> Ipse.Usage.id())
    artifact = Path.join(root, "corpus")
    File.mkdir!(root)

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
          "corpus",
          "--preset",
          "state-lexical"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    on_exit(fn -> File.rm_rf!(root) end)

    artifacts =
      Map.new(
        [
          {"dense", "corpus", "state-dense"},
          {"semantic", "corpus", "state-semantic"},
          {"explicit", "graph", "state-explicit"},
          {"model", "graph", "state-model"},
          {"research", "research", "mcp"}
        ],
        fn {name, package, preset} ->
          path = Path.join(root, name)

          {output, status} =
            System.cmd(
              System.find_executable("elixir"),
              [
                "extensions/knowledge/build.exs",
                "--sdk",
                Application.app_dir(:ipse, "ebin"),
                "--output",
                path,
                "--package",
                package,
                "--preset",
                preset
              ],
              stderr_to_stdout: true
            )

          assert status == 0, output
          {name, path}
        end
      )

    answer = Path.join(root, "answer")

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "scripts/build-artifact.exs",
          "model-calls",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          answer
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    %{
      root: root,
      artifact: artifact,
      artifacts: Map.merge(artifacts, %{"lexical" => artifact, "answer" => answer})
    }
  end

  for {scenario, selected, initialized, model_kinds} <-
        [
          {:current, "all seven variants", 16, ~w(embedding extraction rerank answer)},
          {:suppressed, "lexical", 2, ~w(answer)},
          {:suppressed, "graph_explicit", 3, ~w(answer)},
          {:suppressed, "graph_model", 3, ~w(extraction answer)},
          {:suppressed, "dense", 2, ~w(embedding answer)},
          {:suppressed, "hybrid", 2, ~w(embedding answer)},
          {:suppressed, "rerank", 2, ~w(embedding rerank answer)},
          {:suppressed, "research", 2, ~w(answer)}
        ] do
    @tag scenario: scenario,
         selected_variant: selected,
         initialized: initialized,
         model_kinds: model_kinds
    test "#{selected} preserves #{scenario} source selection and canonical model accounting",
         ctx do
      scenario = ctx.scenario
      {server, origin, tag} = model_fixture()
      root = Path.join(ctx.root, Ipse.Usage.id())
      File.mkdir!(root)
      text = "Release requires quiescence."

      doc = %{
        "document_id" => "d1",
        "project" => "alpha",
        "source_id" => "fixture:release",
        "generation" => 1,
        "version" => 1,
        "title" => "Release",
        "text" => text,
        "created_at" => "2026-01-01T00:00:00Z",
        "observed_at" => "2026-03-01T00:00:00Z",
        "state" => "current",
        "sha256" => Ipse.JSON.sha256(text),
        "byte_length" => byte_size(text),
        "media_type" => "text/plain"
      }

      removed = %{
        doc
        | "document_id" => "d2",
          "source_id" => "fixture:forgotten",
          "title" => "Forgotten",
          "state" => "forgotten",
          "text" => "PRIVATE_FORGOTTEN requires silence.",
          "sha256" => Ipse.JSON.sha256("PRIVATE_FORGOTTEN requires silence."),
          "byte_length" => byte_size("PRIVATE_FORGOTTEN requires silence.")
      }

      expired = %{
        doc
        | "document_id" => "d3",
          "source_id" => "fixture:expired",
          "title" => "Expired",
          "state" => "expired",
          "text" => "PRIVATE_EXPIRED requires silence.",
          "sha256" => Ipse.JSON.sha256("PRIVATE_EXPIRED requires silence."),
          "byte_length" => byte_size("PRIVATE_EXPIRED requires silence.")
      }

      query = %{
        "schema_version" => 1,
        "queries" =>
          for(
            {id, text} <- [{"Q1", "Release"}, {"Q2", "absent mineral"}],
            do: %{
              "query_id" => id,
              "project" => "alpha",
              "split" => "fixture",
              "query" =>
                if(scenario == :suppressed and ctx.selected_variant == "rerank" and id == "Q1",
                  do: "quiescence",
                  else: text
                ),
              "expected_answer" => "NEVER_PROVIDER_INPUT"
            }
          )
      }

      plan =
        matrix_plan(ctx, origin)
        |> Map.update!("variants", fn variants ->
          if scenario == :current,
            do: variants,
            else: Enum.filter(variants, &(&1["id"] == ctx.selected_variant))
        end)

      variant_count = if scenario == :current, do: 7, else: 1

      for {name, value} <- [
            {"plan", plan},
            {"corpus",
             %{
               "schema_version" => 1,
               "documents" => if(scenario == :current, do: [doc], else: [doc, removed, expired])
             }},
            {"queries", query}
          ],
          do: File.write!(Path.join(root, name <> ".json"), JSON.encode!(value))

      try do
        assert :ok = Contract.validate(plan)
        output = Path.join(root, "results")

        assert {:ok, report} =
                 Runner.run(:verify,
                   plan: Path.join(root, "plan.json"),
                   corpus: Path.join(root, "corpus.json"),
                   queries: Path.join(root, "queries.json"),
                   output: output
                 )

        assert report["execution_complete"], inspect(report)
        assert report["rows"] == 2 * variant_count
        snapshots = jsonl(Path.join(output, "resources.jsonl"))

        for variant <- plan["variants"] do
          records = Enum.filter(snapshots, &(&1["variant"] == variant["id"]))
          forgotten = Enum.find(records, &(&1["phase"] == "after_forget"))["inventory"]
          collected = Enum.find(records, &(&1["phase"] == "after_collection"))["inventory"]

          if variant["prepare"] == "research" do
            assert forgotten["status"] == "not_applicable" and collected == forgotten
          else
            before = forgotten["inventory"]
            after_collection = collected["inventory"]
            assert before["selected_pages"]["records"] == 0
            assert before["draft_pages"]["records"] == 0
            assert Enum.all?(before["roots"], &(&1["state"] == "suppressed"))
            assert after_collection["orphan_pages"]["records"] == 0
            assert before["namespace_slots"] == after_collection["namespace_slots"]

            assert after_collection["namespace_tombstones"]["records"] ==
                     before["namespace_tombstones"]["records"] + before["orphan_pages"]["records"]
          end

          projections = Enum.filter(records, &(&1["phase"] == "after_projection"))

          if variant["prepare"] in ~w(embedding explicit extract) do
            assert length(projections) == 1

            assert Enum.all?(
                     projections,
                     &(&1["source_id"] == doc["source_id"] and &1["generation"] == 1 and
                         is_binary(&1["chunk_id"]))
                   )
          else
            assert projections == []
          end
        end

        if scenario == :current or ctx.selected_variant == "research" do
          gateway_calls = JSON.decode!(File.read!(Path.join(output, "gateway-calls.json")))
          gateway_summary = JSON.decode!(File.read!(Path.join(output, "gateway-summary.json")))

          assert gateway_summary == %{
                   "call_limit" => 22,
                   "recorded_calls" => length(gateway_calls),
                   "rejected_over_limit" => 0,
                   "request_count" => length(gateway_calls)
                 }
        else
          refute File.exists?(Path.join(output, "gateway-calls.json"))
          refute File.exists?(Path.join(output, "gateway-summary.json"))
        end

        preflight = JSON.decode!(File.read!(Path.join(output, "preflight.json")))
        assert preflight["status"] == "ok"
        assert preflight["inventory"]["status"] == "ok"

        assert Enum.map(preflight["variants"], & &1["variant"]) ==
                 Enum.map(plan["variants"], & &1["id"])

        assert Enum.map(preflight["variants"], & &1["value"]["inference_step_limit"]) ==
                 Enum.map(plan["variants"], &(&1["budget"]["max_requests"] + 1))

        initialized = Enum.flat_map(preflight["variants"], & &1["value"]["initialization"])
        assert length(initialized) == ctx.initialized
        assert Enum.all?(initialized, &(&1["initialized"] and &1["cleanup"] == "confirmed"))
        assert Enum.all?(initialized, &(&1["options_validated"] in [true, nil]))
        assert Path.wildcard(Path.join(output, "preflight/**/extension-state-v1/**")) == []
        rows = jsonl(Path.join(output, "predictions.jsonl"))
        events = jsonl(Path.join(output, "execution.jsonl"))
        diagnostics = Enum.map(events, &Map.take(&1, ~w(phase verb status value class frames)))

        assert Enum.all?(
                 rows,
                 &(&1["status"] == "ok")
               ),
               inspect(diagnostics, limit: :infinity)

        if scenario == :suppressed and ctx.selected_variant == "rerank" do
          ranked = Enum.find(events, &(&1["verb"] == "query" and &1["query_id"] == "Q1"))
          candidates = ranked["value"]["evidence"]
          assert length(candidates) == 1

          assert length(Enum.uniq_by(candidates, & &1["citation"]["chunk_id"])) ==
                   length(candidates)
        end

        assert Enum.all?(
                 Enum.filter(rows, &(&1["query_id"] == "Q1")),
                 &(&1["evidence"] != [] and &1["response_kind"] == "answer" and
                     &1["context_evidence"] != [])
               )

        assert Enum.all?(
                 Enum.filter(rows, &(&1["query_id"] == "Q2")),
                 &(&1["response_kind"] == "abstention")
               )

        requests = drain(tag, [])
        refute requests == []
        encoded = JSON.encode!(requests)

        for secret <- ~w(PRIVATE_FORGOTTEN PRIVATE_EXPIRED NEVER_PROVIDER_INPUT),
            do: refute(encoded =~ secret)

        for kind <- ctx.model_kinds,
            do: assert(Enum.any?(requests, &(&1["fixture_operation"] == kind)), kind)

        usage = jsonl(Path.join(output, "usage.jsonl"))
        assert Enum.count(usage, &Map.has_key?(&1, "budget")) == variant_count

        assert Enum.sum(for row <- usage, row["budget"], do: row["budget"]["request_count"]) ==
                 length(requests)

        events = jsonl(Path.join(output, "execution.jsonl"))

        assert Enum.count(events, &(&1["phase"] == "close" and &1["status"] == "ok")) ==
                 variant_count

        if scenario == :suppressed and ctx.selected_variant != "research",
          do:
            assert(
              Enum.any?(
                events,
                &(&1["phase"] == "projection_skipped" and &1["source_id"] == "fixture:forgotten")
              )
            )

        assert Enum.all?(events, fn event ->
                 not is_list(event["approvals"]) or
                   Enum.all?(event["approvals"], &(&1["decision"] != "deny"))
               end)

        assert :code.is_loaded(IpseKnowledge.Corpus) == false
      after
        stop_model_fixture(server)
      end
    end
  end

  @tag timeout: 120_000, source_evaluation: true
  test "Research approves four fetches and distinguishes reused typed versions with identical replacement bytes",
       ctx do
    for execution <- [:direct, :public_cli, :public_borrowed, :public_frozen] do
      {server, origin, tag} = model_fixture()
      root = Path.join(ctx.root, Ipse.Usage.id())
      File.mkdir!(root)
      text = "Release requires quiescence."

      docs =
        for n <- 1..4, generation <- 1..2 do
          %{
            "document_id" => "d#{n}",
            "project" => "alpha",
            "source_id" => "s#{n}",
            "generation" => generation,
            "version" => if(rem(n, 2) == 0 and generation == 2, do: "1", else: 1),
            "title" => "Release",
            "text" => text,
            "created_at" => "2026-01-01T00:00:00Z",
            "observed_at" => "2026-03-01T00:00:00Z",
            "state" => "current",
            "sha256" => Ipse.JSON.sha256(text),
            "byte_length" => byte_size(text),
            "media_type" => "text/plain"
          }
        end

      plan =
        matrix_plan(ctx, origin)
        |> Map.put("answer", false)
        |> Map.update!("variants", fn variants ->
          [research] = Enum.filter(variants, &(&1["id"] == "research"))

          research =
            research
            |> Map.update!("bindings", &Map.delete(&1, "answer"))
            |> Map.update!(
              "artifacts",
              &Enum.reject(&1, fn entry -> entry["instance"] == "answer" end)
            )
            |> put_in(["query_options", "limits", "max_sources"], 4)

          [research]
        end)
        |> put_in(["data", "expected_queries"], 1)

      queries = %{
        "schema_version" => 1,
        "queries" => [
          %{
            "query_id" => "Q1",
            "project" => "alpha",
            "split" => "fixture",
            "query" => "Release",
            "expected_answer" => "NEVER_PROVIDER_INPUT"
          }
        ]
      }

      for {name, value} <- [
            {"plan", plan},
            {"corpus", %{"schema_version" => 1, "documents" => docs}},
            {"queries", queries}
          ] do
        File.write!(Path.join(root, name <> ".json"), JSON.encode!(value))
      end

      output = Path.join(root, "results")

      try do
        assert :ok = Contract.validate(plan)

        options = [
          plan: Path.join(root, "plan.json"),
          corpus: Path.join(root, "corpus.json"),
          queries: Path.join(root, "queries.json"),
          output: output
        ]

        report =
          case execution do
            :direct ->
              assert {:ok, report} = Runner.run(:verify, options)
              report

            mode when mode in [:public_cli, :public_borrowed] ->
              temporary = Path.join(root, "tmp")
              File.mkdir!(temporary)
              env = [{"TMPDIR", temporary}]

              borrowed =
                if mode == :public_borrowed do
                  directory = Path.join(root, "shared-fixture")
                  File.mkdir!(directory)

                  for module <- [
                        Ipse.Development.Fixtures.Knowledge,
                        Ipse.Development.Fixtures.Knowledge.Backend
                      ] do
                    File.cp!(
                      to_string(:code.which(module)),
                      Path.join(directory, Atom.to_string(module) <> ".beam")
                    )
                  end

                  File.cp!(
                    Application.app_dir(:ipse, "ebin/Elixir.Ipse.JSON.beam"),
                    Path.join(directory, "Elixir.Ipse.JSON.beam")
                  )

                  directory
                end

              argv =
                ["--phase", "verify"] ++
                  Enum.flat_map(options, fn {key, value} ->
                    ["--" <> Atom.to_string(key), value]
                  end)

              assert {%{"status" => "ok", "result" => report}, 0} =
                       cli(argv, File.cwd!(), env, borrowed)

              assert Path.wildcard(Path.join(temporary, "ipse-verification-*")) == []

              failed =
                options
                |> Keyword.put(:corpus, Path.join(root, "missing"))
                |> Keyword.put(:output, Path.join(root, "failed-results"))

              failed_argv =
                ["--phase", "verify"] ++
                  Enum.flat_map(failed, fn {key, value} ->
                    ["--" <> Atom.to_string(key), value]
                  end)

              assert {%{"status" => "failed"}, 1} = cli(failed_argv, File.cwd!(), env, borrowed)
              assert Path.wildcard(Path.join(temporary, "ipse-verification-*")) == []
              if borrowed, do: assert(length(File.ls!(borrowed)) == 3)
              report

            :public_frozen ->
              repository = fixture_repository!(root)

              members =
                for name <- ~w(corpus queries),
                    do: %{
                      "path" => name <> ".json",
                      "sha256" => Ipse.JSON.sha256(File.read!(Path.join(root, name <> ".json")))
                    }

              manifest = Path.join(root, "manifest.json")
              bytes = JSON.encode!(%{"files" => members})
              File.write!(manifest, bytes)

              File.write!(
                options[:plan],
                JSON.encode!(put_in(plan, ["data", "manifest_sha256"], Ipse.JSON.sha256(bytes)))
              )

              seal_output = Path.join(root, "seal")

              assert {%{"status" => "ok", "result" => seal}, 0} =
                       cli(
                         ["--phase", "freeze", "--plan", options[:plan], "--output", seal_output],
                         repository
                       )

              captured = JSON.decode!(File.read!(seal["path"]))
              assert captured["version"] == 1
              refute Map.has_key?(captured["runtime"], "launch")

              pair =
                for file <- captured["runtime"]["files"],
                    String.starts_with?(
                      Path.basename(file["path"]),
                      "Elixir.Ipse.Development.Fixtures.Knowledge"
                    ),
                    do: file

              assert length(pair) == 2

              assert Enum.all?(
                       pair,
                       &(Path.dirname(&1["path"]) == seal_output <> ".runtime/runtime/harness")
                     )

              assert {%{"status" => "ok", "result" => report}, 0} =
                       cli(
                         [
                           "--phase",
                           "verify-frozen",
                           "--freeze",
                           seal["path"],
                           "--freeze-sha256",
                           seal["sha256"],
                           "--data-manifest",
                           manifest,
                           "--output",
                           output
                         ],
                         repository
                       )

              for file <- pair do
                assert byte_size(File.read!(file["path"])) == file["bytes"]
                assert Ipse.JSON.sha256(File.read!(file["path"])) == file["sha256"]
              end

              historical = Path.join(root, "historical")
              File.mkdir!(historical)

              old =
                frozen_api_inputs(
                  options[:plan],
                  historical,
                  manifest,
                  repository,
                  :source_only,
                  false
                )

              assert old["prediction"]["error"]["code"] == "research_fixture_missing"
              refute File.exists?(Path.join(historical, "frozen-results"))

              refused = [
                "--phase",
                "verify-frozen",
                "--freeze",
                seal["path"],
                "--freeze-sha256",
                seal["sha256"],
                "--data-manifest",
                "must-not-open",
                "--output",
                Path.join(root, "refused")
              ]

              first = hd(pair)["path"]
              original = File.read!(first)
              File.write!(first, original <> "changed")

              assert {%{"reason" => %{"code" => "frozen_runtime_refused"}}, 1} =
                       cli(refused, repository)

              File.write!(first, original)
              File.rm!(List.last(pair)["path"])

              assert {%{"reason" => %{"code" => "frozen_runtime_refused"}}, 1} =
                       cli(refused, repository)

              refute File.exists?(Path.join(root, "refused"))

              report
          end

        events = jsonl(Path.join(output, "execution.jsonl"))
        calls = JSON.decode!(File.read!(Path.join(output, "gateway-calls.json")))

        assert report["failed_rows"] == 0,
               inspect(%{
                 failed_rows: report["failed_rows"],
                 approval_refusals: Enum.count(events, &(&1["phase"] == "approval_refused")),
                 gateway_calls: length(calls)
               })

        assert report["execution_complete"]
        [row] = jsonl(Path.join(output, "predictions.jsonl"))
        assert row["status"] == "ok" and length(row["evidence"]) == 4

        assert Enum.sort(Enum.map(row["evidence"], & &1["source"]["source_id"])) ==
                 ~w(s1 s2 s3 s4)

        assert Enum.all?(row["evidence"], fn span ->
                 expected_version = if span["source"]["source_id"] in ~w(s2 s4), do: "1", else: 1

                 span["source"]["generation"] == 2 and
                   span["source"]["version"] === expected_version and
                   span["source"]["sha256"] == Ipse.JSON.sha256(text) and
                   span["quote"] == text
               end)

        receipt = Enum.find(events, &(&1["verb"] == "research" and is_map(&1["value"])))

        assert Enum.all?(receipt["value"]["evidence"], fn candidate ->
                 candidate["citation"]["generation"] == 1 and
                   String.starts_with?(candidate["citation"]["uri"], "dataset:alpha:")
               end)

        assert receipt["value"]["evidence"]
               |> Enum.map(& &1["citation"]["uri"])
               |> Enum.uniq()
               |> length() == 4

        assert Enum.count(calls, &(&1["tool"] == "fetch")) == 4

        assert JSON.decode!(File.read!(Path.join(output, "gateway-summary.json"))) ==
                 %{
                   "call_limit" => 5,
                   "recorded_calls" => 5,
                   "rejected_over_limit" => 0,
                   "request_count" => 5
                 }

        assert drain(tag, []) == []
        assert :code.is_loaded(IpseKnowledge.Research) == false
      after
        stop_model_fixture(server)
      end
    end
  end

  defp matrix_plan(ctx, origin) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, search_port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)

    profiles =
      Map.new(~w(p27_extract p27_rerank p27_answer), fn name ->
        {name,
         %{
           "provider" => "ollama",
           "model" => "fixture-text",
           "credential" => "none",
           "base_url" => origin,
           "max_output_tokens" => 4096,
           "reasoning_effort" => "none",
           "timeout_ms" => 120_000
         }}
      end)

    spec =
      plan(ctx)
      |> Map.drop(~w(answer variants))
      |> Map.merge(%{
        "artifacts" => ctx.artifacts,
        "profiles" => profiles,
        "embedding_profiles" => %{
          "p27_embedding" => %{
            "operation" => "embedding",
            "provider" => "ollama",
            "model" => "fixture-embedding",
            "credential" => "none",
            "base_url" => origin,
            "dimensions" => 2,
            "dimension_mode" => "native",
            "timeout_ms" => 120_000
          }
        },
        "search_port" => search_port,
        "budgets" =>
          Map.new(
            ~w(lexical graph_explicit graph_model dense hybrid rerank research),
            &{&1, %{"version" => 1, "max_requests" => 20}}
          )
      })

    {:ok, declared} = Ipse.Development.Evaluation.Contract.build(spec)
    declared
  end

  test "tuning inventories its declared private origin before opening input files", ctx do
    {server, origin, tag} = model_fixture()
    root = Path.join(ctx.root, Ipse.Usage.id())
    File.mkdir!(root)

    declared =
      plan(ctx)
      |> Map.put("mode", "tuning")
      |> put_in(["data", "split"], "tuning")
      |> Map.put("profiles", %{
        "p27_answer" => %{
          "provider" => "ollama",
          "model" => "qwen3.5:9b",
          "credential" => "none",
          "base_url" => origin,
          "max_output_tokens" => 4096,
          "reasoning_effort" => "none",
          "timeout_ms" => 120_000
        }
      })
      |> Map.put("models", %{"qwen3.5:9b" => String.duplicate("a", 64)})

    plan_path = Path.join(root, "plan.json")
    File.write!(plan_path, JSON.encode!(declared))
    output = Path.join(root, "result")

    try do
      assert {:error, %{"code" => "preflight_failed"}} =
               Runner.run(:tune,
                 plan: plan_path,
                 corpus: Path.join(root, "absent-corpus.json"),
                 queries: Path.join(root, "absent-queries.json"),
                 output: output
               )

      assert drain(tag, []) == [%{"fixture_operation" => "inventory"}]
      preflight = JSON.decode!(File.read!(Path.join(output, "preflight.json")))
      assert preflight["inventory"]["status"] == "failed"
      assert preflight["model_requests"] == 0
    after
      stop_model_fixture(server)
    end
  end

  defp model_fixture do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    tag = make_ref()
    {pid, monitor} = spawn_monitor(fn -> model_loop(listener, owner, tag) end)
    {%{pid: pid, monitor: monitor, listener: listener}, "http://127.0.0.1:#{port}", tag}
  end

  defp stop_model_fixture(server) do
    :gen_tcp.close(server.listener)
    Process.exit(server.pid, :kill)

    receive do
      {:DOWN, ref, :process, _, _} when ref == server.monitor -> :ok
    after
      5000 -> flunk("model fixture cleanup unconfirmed")
    end
  end

  defp model_loop(listener, owner, tag) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        try do
          {target, body} = http_request(socket, "")
          {kind, response} = fixture_response(target, body)
          send(owner, {tag, Map.put(body, "fixture_operation", kind)})
          bytes = JSON.encode!(response) <> "\n"

          :gen_tcp.send(socket, [
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(bytes)}\r\nconnection: close\r\n\r\n",
            bytes
          ])
        after
          :gen_tcp.close(socket)
        end

        model_loop(listener, owner, tag)

      {:error, :closed} ->
        :ok
    end
  end

  defp http_request(socket, bytes) do
    true = byte_size(bytes) <= 65_536

    case :binary.split(bytes, "\r\n\r\n") do
      [header, rest] ->
        [line | fields] = String.split(header, "\r\n")
        [_method, target, _] = String.split(line, " ")

        headers =
          Map.new(fields, fn field ->
            [key, value] = String.split(field, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        length = String.to_integer(Map.get(headers, "content-length", "0"))

        if byte_size(rest) < length do
          {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
          http_request(socket, bytes <> more)
        else
          {target, if(length == 0, do: %{}, else: JSON.decode!(binary_part(rest, 0, length)))}
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        http_request(socket, bytes <> more)
    end
  end

  defp fixture_response("/api/tags", _body), do: {"inventory", %{"models" => []}}

  defp fixture_response("/api/embed", body) do
    vectors =
      Enum.map(body["input"], fn input ->
        if String.contains?(String.downcase(input), "release"), do: [1.0, 0.0], else: [0.0, 1.0]
      end)

    {"embedding",
     %{"model" => "fixture-embedding", "embeddings" => vectors, "prompt_eval_count" => 3}}
  end

  defp fixture_response("/api/chat", body) do
    input =
      body["messages"]
      |> List.last()
      |> Map.fetch!("content")
      |> String.split("\n", parts: 2)
      |> List.last()
      |> JSON.decode!()
      |> Map.fetch!("input")
      |> JSON.decode!()

    {kind, answer} =
      cond do
        is_list(input["chunks"]) ->
          [chunk] = input["chunks"]

          {"extraction",
           %{
             "facts" => [
               %{
                 "subject" => "Release",
                 "predicate" => "requires",
                 "object" => "quiescence",
                 "polarity" => "positive",
                 "chunk" => chunk["id"],
                 "quote" => chunk["text"]
               }
             ]
           }}

        is_integer(input["required_count"]) ->
          {"rerank", %{"order" => Enum.map(input["candidates"], & &1["id"])}}

        input["candidates"] == [] or input["query"] == "absent mineral" ->
          {"answer", %{"classification" => "abstain", "claims" => []}}

        input["query"] == "Release invalid shape fixture" ->
          {"answer", %{"classification" => "open", "answer" => nil, "claims" => []}}

        true ->
          {"answer",
           %{
             "classification" => "answer",
             "claims" => [
               %{
                 "text" => "Release requires quiescence.",
                 "citations" => [hd(input["candidates"])["id"]]
               },
               %{
                 "text" => "Quiescence is required for release.",
                 "citations" => [hd(input["candidates"])["id"]]
               }
             ]
           }}
      end

    {kind,
     %{
       "model" => "fixture-text",
       "message" => %{"role" => "assistant", "content" => JSON.encode!(answer)},
       "done" => true,
       "done_reason" => "stop",
       "prompt_eval_count" => 8,
       "eval_count" => 8
     }}
  end

  defp drain(tag, requests) do
    receive do
      {^tag, request} -> drain(tag, [request | requests])
    after
      0 -> Enum.reverse(requests)
    end
  end

  defp jsonl(path),
    do: File.read!(path) |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp plan(ctx) do
    options = JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))

    %{
      "version" => 1,
      "mode" => "fixture",
      "data" => %{
        "corpus" => "corpus.json",
        "queries" => "queries.json",
        "split" => "fixture",
        "expected_queries" => 2,
        "manifest_sha256" => String.duplicate("a", 64)
      },
      "as_of_ms" => 1_800_000_000_000,
      "artifacts" => %{"lexical" => ctx.artifact},
      "profiles" => %{},
      "embedding_profiles" => %{},
      "models" => %{},
      "answer" => false,
      "interval_ms" => 10,
      "search_port" => nil,
      "blind_seed" => String.duplicate("b", 64),
      "storage_policy" => "forget_all_then_collect_v1",
      "variants" => [
        %{
          "id" => "lexical",
          "prepare" => "none",
          "artifacts" => [
            %{
              "alias" => "lexical",
              "instance" => "corpus",
              "options" => options,
              "state_binding" => "evaluation"
            }
          ],
          "bindings" =>
            Map.new(
              ~w(ingest inspect forget collect query),
              &{&1,
               %{"instance" => "corpus", "id" => if(&1 == "query", do: "query", else: "source")}}
            ),
          "prepare_options" => %{"store" => "notes"},
          "query_options" => %{
            "store" => "notes",
            "retrieval" => "words",
            "rerank" => nil,
            "top_k" => 10
          },
          "budget" => %{"version" => 1, "max_requests" => 2}
        }
      ]
    }
  end

  test "public lexical comparison preserves first rows and excludes query label values", ctx do
    root = Path.join(ctx.root, Ipse.Usage.id())
    File.mkdir!(root)
    text = "Release requires quiescence."

    corpus = %{
      "schema_version" => 1,
      "documents" => [
        %{
          "document_id" => "d1",
          "project" => "alpha",
          "source_id" => "fixture:release",
          "generation" => 1,
          "version" => 1,
          "title" => "Release",
          "text" => text,
          "created_at" => "2026-01-01T00:00:00Z",
          "observed_at" => "2026-03-01T00:00:00Z",
          "state" => "current",
          "sha256" => Ipse.JSON.sha256(text),
          "byte_length" => byte_size(text),
          "media_type" => "text/plain"
        }
      ]
    }

    queries = %{
      "schema_version" => 1,
      "queries" =>
        for {id, query} <- [{"Q1", "quiescence"}, {"Q2", "absent mineral"}] do
          %{
            "query_id" => id,
            "query" => query,
            "project" => "alpha",
            "split" => "fixture",
            "expected_class" => "secret-class",
            "expected_answer" => "NEVER_PROVIDER_INPUT",
            "relevance" => "NEVER_PROVIDER_INPUT"
          }
        end
    }

    paths =
      Map.new([{"plan", plan(ctx)}, {"corpus", corpus}, {"queries", queries}], fn {name, value} ->
        path = Path.join(root, name <> ".json")
        File.write!(path, JSON.encode!(value))
        {name, path}
      end)

    output = Path.join(root, "result")

    assert {:ok, report} =
             Runner.run(:verify,
               plan: paths["plan"],
               corpus: paths["corpus"],
               queries: paths["queries"],
               output: output
             )

    assert report["rows"] == 2
    assert report["failed_rows"] == 0
    assert report["heldout_quality_complete"] == false

    rows =
      File.read!(Path.join(output, "predictions.jsonl"))
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert Enum.map(rows, & &1["query_id"]) == ["Q1", "Q2"]

    assert Enum.all?(
             rows,
             &(&1["attempt"] == 1 and &1["status"] == "ok" and
                 &1["response_kind"] == "retrieval_only")
           )

    assert hd(rows)["evidence"] != []
    assert List.last(rows)["evidence"] == []

    usage =
      File.read!(Path.join(output, "usage.jsonl"))
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert length(usage) == 1
    assert hd(usage)["budget"]["request_count"] == 0

    for path <- Path.wildcard(Path.join(output, "**/*.json*")) do
      refute File.read!(path) =~ "NEVER_PROVIDER_INPUT", path
    end

    memory = JSON.decode!(File.read!(Path.join(output, "memory-summary.json")))
    assert memory["samples"] > 0
    assert memory["sampled_beam_max_bytes"] > 0
    assert memory["start"]["at_monotonic_ms"] <= memory["end"]["at_monotonic_ms"]

    manifest = %{
      "files" =>
        for(
          name <- ~w(corpus queries),
          do: %{
            "path" => name <> ".json",
            "sha256" => Ipse.JSON.sha256(File.read!(paths[name]))
          }
        )
    }

    manifest_bytes = JSON.encode!(manifest)
    manifest_path = Path.join(root, "dataset-manifest.json")
    File.write!(manifest_path, manifest_bytes)

    declared =
      put_in(
        plan(ctx),
        ["data", "manifest_sha256"],
        Ipse.JSON.sha256(manifest_bytes)
      )

    repository = Path.join(root, "identity-fixture")
    File.mkdir!(repository)
    File.write!(Path.join(repository, "README.md"), "Synthetic identity fixture.\n")

    for arguments <- [
          ["init", "-q"],
          ["add", "README.md"],
          [
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "Synthetic fixture"
          ]
        ] do
      {message, status} =
        System.cmd("git", ["-C", repository | arguments], stderr_to_stdout: true)

      assert status == 0, message
    end

    assert {:ok, seal} =
             Ipse.Development.Evaluation.Freeze.create(
               repository,
               JSON.encode!(declared),
               declared["artifacts"],
               Path.join(root, "seal")
             )

    frozen_output = Path.join(root, "frozen-results")

    assert {:ok, frozen} =
             Runner.run(:verify_frozen,
               freeze: seal["path"],
               freeze_sha256: seal["sha256"],
               data_manifest: manifest_path,
               output: frozen_output
             )

    assert frozen["execution_complete"]
    assert frozen["rows"] == 2
    assert frozen["failed_rows"] == 0
    assert frozen["freeze_sha256"] == seal["sha256"]
    assert frozen["data_manifest_sha256"] == declared["data"]["manifest_sha256"]

    assert {:error, %{"code" => "prediction_hash_mismatch"}} =
             Runner.run(:score,
               freeze: seal["path"],
               freeze_sha256: seal["sha256"],
               data_manifest: "must-not-open",
               predictions: Path.join(frozen_output, "predictions.jsonl"),
               prediction_sha256: String.duplicate("0", 64),
               labels: "must-not-open",
               reviews: "must-not-open",
               output: Path.join(root, "scored")
             )

    assert {:error, %{"code" => "execution_mode"}} =
             Runner.run(:predict,
               freeze: seal["path"],
               freeze_sha256: seal["sha256"],
               data_manifest: "must-not-open",
               output: Path.join(root, "heldout-forbidden")
             )

    assert {:error, %{"code" => "output_exists"}} =
             Runner.run(:verify,
               plan: paths["plan"],
               corpus: paths["corpus"],
               queries: paths["queries"],
               output: output
             )
  end

  test "heldout declarations cannot omit variants, actual profiles or answer generation", ctx do
    declared = %{plan(ctx) | "mode" => "heldout", "answer" => true}
    assert {:error, :heldout_matrix} = Contract.validate(declared)

    assert {:error, %{"code" => "labels_forbidden"}} =
             Runner.run(:predict, labels: "must-not-open")

    assert {:error, %{"code" => "option_shape"}} = Runner.run(:verify, unknown: "must-not-open")
  end

  test "usage export crosses the thirty-request default and the sixteen-request UI snapshot",
       ctx do
    {server, origin, tag} = model_fixture()
    {paths, root} = cli_inputs(ctx, false)
    matrix = matrix_plan(ctx, origin)
    variant = hd(matrix["variants"]) |> put_in(["budget", "max_requests"], 31)
    declared = %{matrix | "variants" => [variant]}
    declared = put_in(declared, ["data", "expected_queries"], 31)

    queries =
      for index <- 1..31,
          do: %{
            "query_id" => "Q#{index}",
            "project" => "alpha",
            "split" => "fixture",
            "query" => "Release"
          }

    File.write!(paths["plan"], JSON.encode!(declared))
    File.write!(paths["queries"], JSON.encode!(%{"schema_version" => 1, "queries" => queries}))
    output = Path.join(root, "results")

    try do
      assert {:ok, report} =
               Runner.run(:verify,
                 plan: paths["plan"],
                 corpus: paths["corpus"],
                 queries: paths["queries"],
                 output: output
               )

      assert report["execution_complete"] and report["failed_rows"] == 0,
             inspect(
               {report["errors"],
                Enum.map(jsonl(Path.join(output, "resources.jsonl")), fn row ->
                  {row["phase"], get_in(row, ["inventory", "status"])}
                end)}
             )

      assert report["rows"] == 31
      requests = drain(tag, [])
      assert length(requests) == 31
      assert Enum.all?(requests, &(&1["fixture_operation"] == "answer"))
      usage = jsonl(Path.join(output, "usage.jsonl"))
      [saved] = Enum.filter(usage, &Map.has_key?(&1, "budget"))
      assert saved["budget"]["request_count"] == 31

      {:ok, events} =
        Ipse.Journal.load(
          Path.join([output, "alpha", "lexical", "sessions"]),
          saved["session_id"]
        )

      {:ok, ledger} = Ipse.Usage.restore(events, saved["session_id"])
      assert Ipse.Usage.snapshot(ledger)["shown_request_count"] == 16
      records = Enum.filter(usage, &Map.has_key?(&1, "request_id"))
      assert length(records) == 31
      assert Enum.map(records, & &1["request_id"]) == Ipse.Usage.order(ledger)
      assert Enum.all?(records, &Ipse.Usage.valid_request_record?/1)

      assert Enum.all?(
               records,
               &(&1["selected_profile"] == "p27_answer" and &1["outcome"] == "completed")
             )

      resource_records = jsonl(Path.join(output, "request-resources.jsonl"))
      assert length(resource_records) == 31
      assert Enum.map(resource_records, & &1["query_id"]) == Enum.map(queries, & &1["query_id"])

      assert Enum.all?(
               resource_records,
               &(&1["attribution"] == "confirmed" and &1["budget_admitted"] and
                   &1["dispatch_intent"] and &1["budget_settled"])
             )

      resources = JSON.decode!(File.read!(Path.join(output, "resource-summary.json")))
      assert resources["complete"]
      [variant] = resources["variants"]
      assert variant["queries"]["observed"] == 31
      assert variant["queries"]["missing"] == 0
      assert variant["accounting_verified"]
      assert variant["requests"]["attempted"] == 31
      [answer] = variant["requests"]["groups"]
      assert answer["role"] == "answer" and answer["count"] == 31
      assert answer["latency_ms"]["observed"] == 31
      assert resources["storage_reachability_complete"]
      prepared = Enum.find(variant["storage_snapshots"], &(&1["phase"] == "after_preparation"))
      assert prepared["inventory"]["status"] == "verified"
      assert prepared["inventory"]["inventory"]["selected_pages"]["records"] > 0
      assert prepared["inventory"]["state_file_bytes"] > 0
      query_storage = Enum.filter(variant["storage_snapshots"], &(&1["phase"] == "after_query"))
      assert length(query_storage) == 31
      assert Enum.map(query_storage, & &1["query_id"]) == Enum.map(queries, & &1["query_id"])
      assert Enum.all?(query_storage, &(&1["inventory"] == prepared["inventory"]))
      forgotten = Enum.find(variant["storage_snapshots"], &(&1["phase"] == "after_forget"))
      collected = Enum.find(variant["storage_snapshots"], &(&1["phase"] == "after_collection"))
      assert forgotten["inventory"]["inventory"]["selected_pages"]["records"] == 0
      assert collected["inventory"]["inventory"]["namespace_tombstones"]["records"] > 0
      assert length(Path.wildcard(Path.join(output, "storage-inventory-*.json"))) == 3
      overview = JSON.decode!(File.read!(Path.join(output, "execution-overview.json")))
      assert overview["elapsed_through_finalization_us"] > 0
      assert overview["output_storage"]["source_authoring"]["bytes"] > 0
      assert overview["output_storage"]["preflight"]["bytes"] > 0
      assert overview["output_storage"]["store"]["bytes"] > 0
      refute overview["resource_evaluation_complete"]
    after
      stop_model_fixture(server)
    end
  end

  @tag :answer_contract
  test "derived claims reach saved pairs and an invalid first answer is retained without retry",
       ctx do
    {server, origin, tag} = model_fixture()
    {paths, root} = cli_inputs(ctx, false)
    matrix = matrix_plan(ctx, origin)
    File.write!(paths["plan"], JSON.encode!(%{matrix | "variants" => [hd(matrix["variants"])]}))

    queries = JSON.decode!(File.read!(paths["queries"]))
    queries = put_in(queries, ["queries", Access.at(1), "query"], "Release invalid shape fixture")
    File.write!(paths["queries"], JSON.encode!(queries))
    output = Path.join(root, "results")

    try do
      assert {:ok, report} =
               Runner.run(:verify,
                 plan: paths["plan"],
                 corpus: paths["corpus"],
                 queries: paths["queries"],
                 output: output
               )

      assert report["execution_complete"] and report["rows"] == 2 and report["failed_rows"] == 1
      assert length(drain(tag, [])) == 2
      [good, failed] = jsonl(Path.join(output, "predictions.jsonl"))
      assert good["status"] == "ok" and good["attempt"] == 1
      assert good["predicted_class"] == "answer" and good["response_kind"] == "answer"

      assert good["claims"] == [
               %{"claim_id" => "c1", "text" => "Release requires quiescence."},
               %{"claim_id" => "c2", "text" => "Quiescence is required for release."}
             ]

      assert good["answer"] == Enum.map_join(good["claims"], "\n", & &1["text"])

      assert good["citations"] == [
               %{"citation_id" => "pair1-1", "claim_id" => "c1", "span_id" => "a-e1"},
               %{"citation_id" => "pair2-1", "claim_id" => "c2", "span_id" => "a-e1"}
             ]

      assert [ranked] = good["evidence"]
      assert [cited] = good["context_evidence"]
      assert cited == Map.put(ranked, "span_id", "a-e1")
      assert failed["status"] == "failed" and failed["attempt"] == 1
      assert failed["answer"] == nil and failed["claims"] == [] and failed["citations"] == []
      assert failed["context_evidence"] == [] and failed["evidence"] != []
      [budget] = Enum.filter(jsonl(Path.join(output, "usage.jsonl")), &Map.has_key?(&1, "budget"))
      assert budget["budget"]["request_count"] == 2
    after
      stop_model_fixture(server)
    end
  end

  test "an empty corpus keeps lifecycle absence explicit without creating stored data", ctx do
    {paths, root} = cli_inputs(ctx, false)
    File.write!(paths["corpus"], JSON.encode!(%{"schema_version" => 1, "documents" => []}))
    output = Path.join(root, "empty-results")

    assert {:ok, report} =
             Runner.run(:verify,
               plan: paths["plan"],
               corpus: paths["corpus"],
               queries: paths["queries"],
               output: output
             )

    assert report["execution_complete"] and report["rows"] == 2 and report["failed_rows"] == 0
    snapshots = jsonl(Path.join(output, "resources.jsonl"))
    assert Enum.all?(snapshots, &(&1["inventory"]["status"] == "absent"))
    assert Enum.count(snapshots, &(&1["phase"] in ~w(after_forget after_collection))) == 2
    resources = JSON.decode!(File.read!(Path.join(output, "resource-summary.json")))
    assert resources["storage_reachability_complete"]
    assert jsonl(Path.join(output, "request-resources.jsonl")) == []
  end

  test "resource reporting separates a budget refusal from dispatch and retains both queries",
       ctx do
    {server, origin, tag} = model_fixture()
    {paths, root} = cli_inputs(ctx, false)
    matrix = matrix_plan(ctx, origin)
    variant = hd(matrix["variants"]) |> put_in(["budget", "max_requests"], 1)
    File.write!(paths["plan"], JSON.encode!(%{matrix | "variants" => [variant]}))
    output = Path.join(root, "results")

    try do
      assert {:ok, report} =
               Runner.run(:verify,
                 plan: paths["plan"],
                 corpus: paths["corpus"],
                 queries: paths["queries"],
                 output: output
               )

      assert report["rows"] == 2 and report["failed_rows"] == 1
      assert length(drain(tag, [])) == 1
      rows = jsonl(Path.join(output, "predictions.jsonl"))
      [failed] = Enum.filter(rows, &(&1["status"] == "failed"))
      assert failed["response_kind"] == "answer"
      assert failed["answer"] == nil and failed["claims"] == [] and failed["citations"] == []

      [resource] =
        JSON.decode!(File.read!(Path.join(output, "resource-summary.json")))["variants"]

      assert resource["accounting_verified"]
      assert resource["queries"]["observed"] == 2
      assert resource["queries"]["statuses"] == %{"ok" => 1, "failed" => 1}
      assert resource["requests"]["attempted"] == 2
      assert resource["requests"]["budget_admitted"] == 1
      assert resource["requests"]["budget_refused"] == 1
      assert resource["requests"]["dispatch_intents"] == 1
      assert length(jsonl(Path.join(output, "predictions.jsonl"))) == 2
    after
      stop_model_fixture(server)
    end
  end

  for failed <- [false, true] do
    @tag failed_rows: failed
    test "CLI status agrees with retained #{if failed, do: "failed", else: "successful"} rows",
         ctx do
      failed = ctx.failed_rows
      {paths, root} = cli_inputs(ctx, failed)
      output = Path.join(root, "results")

      {summary, exit_status} =
        cli([
          "--phase",
          "verify",
          "--plan",
          paths["plan"],
          "--corpus",
          paths["corpus"],
          "--queries",
          paths["queries"],
          "--output",
          output
        ])

      assert exit_status == if(failed, do: 1, else: 0), inspect(summary)
      assert summary["status"] == if(failed, do: "failed", else: "ok")
      assert summary["result"]["failed_rows"] == if(failed, do: 2, else: 0)
      assert summary["result"]["execution_complete"]
      rows = jsonl(Path.join(output, "predictions.jsonl"))
      assert length(rows) == 2
      assert Enum.all?(rows, &(&1["attempt"] == 1))
      assert Enum.all?(rows, &(&1["status"] == if(failed, do: "partial", else: "ok")))
    end
  end

  test "CLI refuses unsupported phases" do
    {summary, status} = cli(["--phase", "unsupported"])
    assert status == 1
    assert summary == %{"status" => "failed", "reason" => %{"code" => "invalid_options"}}
  end

  test "CLI forbids label input during prediction" do
    {summary, status} = cli(["--phase", "predict", "--labels", "must-not-open"])
    assert status == 1
    assert summary["reason"]["code"] == "labels_forbidden"
  end

  test "all catalogs and initialized options pass preflight before any dataset opens", ctx do
    matrix = matrix_plan(ctx, "http://127.0.0.1:19999")

    invalid_binding =
      update_in(matrix, ["variants"], fn variants ->
        Enum.map(variants, fn variant ->
          if variant["id"] == "research",
            do: put_in(variant, ["bindings", "research", "id"], "query"),
            else: variant
        end)
      end)

    invalid_options =
      update_in(
        plan(ctx),
        ["variants", Access.at(0), "artifacts", Access.at(0), "options", "retrieval"],
        fn profiles ->
          Map.put(profiles, "unused", %{"kind" => "unknown", "version" => 1})
        end
      )

    for {name, declared, variant} <- [
          {"binding", invalid_binding, "research"},
          {"options", invalid_options, "lexical"}
        ] do
      root = Path.join(ctx.root, "preflight-" <> name)
      File.mkdir!(root)
      path = Path.join(root, "plan.json")
      File.write!(path, JSON.encode!(declared))
      assert :ok = Contract.validate(declared)
      output = Path.join(root, "result")

      outcome =
        Runner.run(:verify,
          plan: path,
          corpus: "must-not-open",
          queries: "must-not-open",
          output: output
        )

      assert {:error, %{"code" => "preflight_failed"}} = outcome

      report = JSON.decode!(File.read!(Path.join(output, "preflight.json")))
      assert report["status"] == "failed"
      assert List.last(report["variants"])["variant"] == variant
      assert report["inventory"] == nil

      if name == "options" do
        [receipt] = hd(report["variants"])["value"]["initialization"]
        assert receipt["initialized"]
        refute receipt["options_validated"]
        assert receipt["cleanup"] == "confirmed"
      end

      refute File.exists?(Path.join(output, "predictions.jsonl"))
      refute File.exists?(Path.join(output, "inventory-before.json"))
      assert Path.wildcard(Path.join(output, "**/extension-state-v1/**")) == []
    end
  end

  test "CLI freezes copied selections and verifies complete execution", ctx do
    {_paths, root, manifest, _sealed, frozen} = cli_frozen_inputs(ctx, :cli)
    output = Path.join(root, "frozen-results")

    {summary, 0} =
      cli(
        ["--phase", "verify-frozen"] ++
          frozen ++ ["--data-manifest", manifest, "--output", output]
      )

    assert summary["result"]["rows"] == 2
    assert summary["result"]["failed_rows"] == 0
    assert summary["result"]["execution_complete"]
    assert File.regular?(Path.join(output, "predictions.jsonl"))
  end

  @tag timeout: 120_000
  test "CLI creates a bound private review and refuses stale verdicts before labels", ctx do
    {paths, root, manifest, sealed, frozen} = cli_frozen_inputs(ctx, :predictions)
    output = Path.join(root, "frozen-results")
    prediction = sealed["prediction"]
    assert prediction["execution_complete"] and prediction["failed_rows"] == 0

    packet_path = Path.join(root, "blind-review")
    prediction_path = Path.join(output, "predictions.jsonl")
    prediction_hash = prediction["prediction_sha256"]

    review_args =
      ["--phase", "review"] ++
        frozen ++
        [
          "--data-manifest",
          manifest,
          "--predictions",
          prediction_path,
          "--prediction-sha256",
          prediction_hash,
          "--output",
          packet_path
        ]

    {packet, 0} = cli(review_args)
    assert packet["result"]["rows"] == 2 and packet["result"]["reference_integrity_complete"]
    manifest_bytes = File.read!(Path.join(packet_path, "manifest.json"))
    assert packet["result"]["packet_sha256"] == Ipse.JSON.sha256(manifest_bytes)
    assert JSON.decode!(manifest_bytes)["execution_freeze_sha256"] == sealed["result"]["sha256"]

    assert Enum.all?(
             jsonl(Path.join(packet_path, "cases.jsonl")),
             &(not Map.has_key?(&1, "variant"))
           )

    assert Bitwise.band(File.stat!(packet_path).mode, 0o777) == 0o700

    assert Enum.all?(
             Path.wildcard(Path.join(packet_path, "*")),
             &(Bitwise.band(File.stat!(&1).mode, 0o777) == 0o600)
           )

    review_path = Path.join(root, "unmeasured-reviews.json")

    File.write!(
      review_path,
      File.read!(Path.join(packet_path, "reviews-template.json")) <>
        String.duplicate(" ", 1024 * 1024)
    )

    {unmeasured, 1} =
      cli(
        ["--phase", "score"] ++
          frozen ++
          [
            "--data-manifest",
            manifest,
            "--predictions",
            prediction_path,
            "--prediction-sha256",
            prediction_hash,
            "--labels",
            paths["queries"],
            "--reviews",
            review_path,
            "--output",
            Path.join(root, "unmeasured-scores")
          ]
      )

    assert unmeasured["status"] == "failed" and
             unmeasured["result"]["quality_gates_passed"] == false

    assert unmeasured["result"]["gates"]["support"]["status"] == "unmeasured"
    assert File.regular?(Path.join(root, "unmeasured-scores/scores.json"))

    template = File.read!(Path.join(packet_path, "reviews-template.json")) |> JSON.decode!()
    assert template["version"] == 2

    assert template["review_binding_sha256"] ==
             JSON.decode!(manifest_bytes)["review_binding_sha256"]

    for {name, changed, code} <- [
          {"wrong-binding", Map.put(template, "review_binding_sha256", String.duplicate("0", 64)),
           "review_binding_mismatch"},
          {"unbound", Map.delete(template, "review_binding_sha256"), "invalid_reviews"},
          {"legacy", Map.put(template, "version", 1), "invalid_reviews"}
        ] do
      changed_path = Path.join(root, name <> ".json")
      File.write!(changed_path, JSON.encode!(changed))
      refused_output = Path.join(root, name)
      unopened_labels = Path.join(root, "must-not-open-labels.json")

      {refused, 1} =
        cli(
          ["--phase", "score"] ++
            frozen ++
            [
              "--data-manifest",
              manifest,
              "--predictions",
              prediction_path,
              "--prediction-sha256",
              prediction_hash,
              "--labels",
              unopened_labels,
              "--reviews",
              changed_path,
              "--output",
              refused_output
            ]
        )

      assert refused["reason"]["code"] == code
      refute File.exists?(refused_output)
      refute File.exists?(unopened_labels)
    end
  end

  test "CLI refuses an existing review output without replacing its manifest", ctx do
    {_paths, root, manifest, sealed, frozen} = cli_frozen_inputs(ctx, :predictions)
    packet_path = Path.join(root, "existing-review")
    File.mkdir!(packet_path)
    manifest_bytes = JSON.encode!(%{"retained" => "original review output"})
    File.write!(Path.join(packet_path, "manifest.json"), manifest_bytes)

    {rejected, 1} =
      cli(
        ["--phase", "review"] ++
          frozen ++
          [
            "--data-manifest",
            manifest,
            "--predictions",
            Path.join(root, "frozen-results/predictions.jsonl"),
            "--prediction-sha256",
            sealed["prediction"]["prediction_sha256"],
            "--output",
            packet_path
          ]
      )

    assert rejected["reason"]["code"] == "output_exists"
    assert File.read!(Path.join(packet_path, "manifest.json")) == manifest_bytes
  end

  @tag timeout: 120_000
  test "CLI refuses mode changes and verifies prediction hashes before labels or review inputs",
       ctx do
    {paths, root, _manifest, _sealed, frozen} = cli_frozen_inputs(ctx)
    prediction_path = Path.join(root, "unparsed-predictions.jsonl")
    File.write!(prediction_path, String.duplicate("x", 16 * 1024 * 1024 + 1))

    {rejected, 1} =
      cli(
        ["--phase", "review"] ++
          frozen ++
          [
            "--data-manifest",
            "must-not-open",
            "--predictions",
            prediction_path,
            "--prediction-sha256",
            String.duplicate("0", 64),
            "--output",
            Path.join(root, "bad-review")
          ]
      )

    assert rejected["reason"]["code"] == "prediction_hash_mismatch"

    {rejected, 1} =
      cli(
        ["--phase", "predict"] ++
          frozen ++ ["--data-manifest", "must-not-open", "--output", Path.join(root, "forbidden")]
      )

    assert rejected["reason"]["code"] == "execution_mode"

    {rejected, 1} =
      cli(
        ["--phase", "score"] ++
          frozen ++
          [
            "--data-manifest",
            "must-not-open",
            "--predictions",
            prediction_path,
            "--prediction-sha256",
            String.duplicate("0", 64),
            "--labels",
            "must-not-open",
            "--reviews",
            "must-not-open",
            "--output",
            Path.join(root, "scores")
          ]
      )

    assert rejected["reason"]["code"] == "prediction_hash_mismatch"

    {rejected, 1} =
      cli([
        "--phase",
        "tune",
        "--plan",
        paths["plan"],
        "--corpus",
        "must-not-open",
        "--queries",
        "must-not-open",
        "--output",
        Path.join(root, "tuning")
      ])

    assert rejected["reason"]["code"] == "execution_mode"
  end

  defp cli_frozen_inputs(ctx, prepare \\ :seal) do
    {paths, root} = cli_inputs(ctx, false)
    label_input = JSON.decode!(File.read!(paths["queries"]))

    label_input =
      Map.update!(label_input, "queries", fn rows ->
        Enum.map(rows, fn row ->
          row
          |> Map.put("expected_class", if(row["query_id"] == "Q1", do: "open", else: "abstain"))
          |> Map.put(
            "expected_answer",
            if(row["query_id"] == "Q1", do: "Release requires quiescence.")
          )
          |> Map.put("relevance", [])
        end)
      end)

    File.write!(paths["queries"], JSON.encode!(label_input))
    repository = fixture_repository!(root)

    members =
      for name <- ~w(corpus queries),
          do: %{
            "path" => name <> ".json",
            "sha256" => Ipse.JSON.sha256(File.read!(paths[name]))
          }

    bytes = JSON.encode!(%{"files" => members})
    manifest = Path.join(root, "manifest.json")
    File.write!(manifest, bytes)

    declared =
      put_in(plan(ctx), ["data", "manifest_sha256"], Ipse.JSON.sha256(bytes))

    File.write!(paths["plan"], JSON.encode!(declared))

    sealed =
      case prepare do
        :cli ->
          {sealed, 0} =
            cli(
              ["--phase", "freeze", "--plan", paths["plan"], "--output", Path.join(root, "seal")],
              repository
            )

          sealed

        mode when mode in [:seal, :predictions] ->
          frozen_api_inputs(paths["plan"], root, manifest, repository, mode)
      end

    assert sealed["status"] == "ok"
    frozen = ["--freeze", sealed["result"]["path"], "--freeze-sha256", sealed["result"]["sha256"]]
    {paths, root, manifest, sealed, frozen}
  end

  defp frozen_api_inputs(plan, root, manifest, repository, mode, include_fixture \\ true) do
    code = """
    [source, plan, seal_output, manifest, output, mode] = System.argv()
    Code.require_file(source)
    alias Ipse.Development.Evaluation.Runner, as: Runner
    {:ok, sealed} = Runner.run(:freeze, plan: plan, output: seal_output)
    prediction =
      case mode do
        "predictions" ->
          {:ok, prediction} = Runner.run(:verify_frozen,
            freeze: sealed["path"], freeze_sha256: sealed["sha256"],
            data_manifest: manifest, output: output)
          prediction
        "source_only" ->
          Code.require_file(Path.expand("../../dev/fixtures/knowledge.exs", Path.dirname(source)))
          true = Code.ensure_loaded?(Ipse.Development.Fixtures.Knowledge)
          [] = :code.which(Ipse.Development.Fixtures.Knowledge)
          {:error, error} = Runner.run(:verify_frozen,
            freeze: sealed["path"], freeze_sha256: sealed["sha256"],
            data_manifest: "must-not-open", output: output)
          %{"error" => error}
        _ -> nil
      end
    IO.puts(JSON.encode!(%{"status" => "ok", "result" => sealed, "prediction" => prediction}))
    """

    started = System.monotonic_time(:millisecond)
    phase_timing("freeze_fixture", "started", nil)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        cli_code_paths(include_fixture) ++
          [
            "-e",
            code,
            "--",
            Path.expand("dev/evaluation/runner.exs"),
            plan,
            Path.join(root, "seal"),
            manifest,
            Path.join(root, "frozen-results"),
            Atom.to_string(mode)
          ],
        stderr_to_stdout: true,
        cd: repository
      )

    phase_timing("freeze_fixture", "finished", System.monotonic_time(:millisecond) - started)
    assert status == 0, output
    output |> String.split("\n", trim: true) |> List.last() |> JSON.decode!()
  end

  defp cli_inputs(ctx, failed) do
    root = Path.join(ctx.root, "cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    text = "Release requires quiescence."

    doc = %{
      "document_id" => "d1",
      "project" => "alpha",
      "source_id" => "fixture:release",
      "generation" => 1,
      "version" => 1,
      "title" => "Release",
      "text" => text,
      "created_at" => "2026-01-01T00:00:00Z",
      "observed_at" => "2026-03-01T00:00:00Z",
      "state" => "current",
      "sha256" => Ipse.JSON.sha256(text),
      "byte_length" => byte_size(text),
      "media_type" => "text/plain"
    }

    docs =
      if failed,
        do: [
          Map.put(doc, "state", "forgotten"),
          %{doc | "document_id" => "d2", "generation" => 2, "version" => 2}
        ],
        else: [doc]

    queries =
      for {id, query} <- [{"Q1", "Release"}, {"Q2", "absent mineral"}],
          do: %{"query_id" => id, "project" => "alpha", "split" => "fixture", "query" => query}

    paths =
      Map.new(
        [
          {"plan", plan(ctx)},
          {"corpus", %{"schema_version" => 1, "documents" => docs}},
          {"queries", %{"schema_version" => 1, "queries" => queries}}
        ],
        fn {name, value} ->
          path = Path.join(root, name <> ".json")
          File.write!(path, JSON.encode!(value))
          {name, path}
        end
      )

    {paths, root}
  end

  defp fixture_repository!(root) do
    repository = Path.join(root, "repository")
    File.mkdir!(repository)
    File.write!(Path.join(repository, "README.md"), "Synthetic CLI identity fixture.\n")

    for args <- [
          ["init", "-q"],
          ["add", "README.md"],
          [
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "Synthetic fixture"
          ]
        ] do
      {message, status} = System.cmd("git", ["-C", repository | args], stderr_to_stdout: true)
      assert status == 0, message
    end

    repository
  end

  defp cli(arguments, cwd \\ File.cwd!(), env \\ [], fixture \\ nil) do
    phase =
      case arguments do
        ["--phase", phase | _] when phase in ~w(freeze predict review score tune verify-frozen) ->
          phase

        _ ->
          "other"
      end

    started = System.monotonic_time(:millisecond)
    phase_timing(phase, "started", nil)

    try do
      entry = Path.expand("scripts/evaluate-knowledge.exs")

      preloaded = if fixture, do: "true", else: "false"

      program =
        "#{preloaded} = Code.ensure_loaded?(Ipse.Development.Fixtures.Knowledge); Code.require_file(#{inspect(entry)}); false = :code.is_loaded(IpseKnowledge.Research)"

      paths = cli_code_paths(false) ++ if(fixture, do: ["-pa", fixture], else: [])

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          paths ++ ["-e", program, "--" | arguments],
          stderr_to_stdout: true,
          cd: cwd,
          env: env
        )

      {output |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(), status}
    after
      phase_timing(phase, "finished", System.monotonic_time(:millisecond) - started)
    end
  end

  defp phase_timing(phase, event, elapsed) do
    if System.get_env("IPSE_TEST_STDIO_PROBE") == "1" do
      IO.puts(
        :stderr,
        JSON.encode!(%{synthetic_evaluation_cli_phase: phase, event: event, elapsed_ms: elapsed})
      )
    end
  end

  defp cli_code_paths(include_fixture) do
    paths = Path.wildcard(Path.join([Path.dirname(Application.app_dir(:ipse)), "*", "ebin"]))
    fixture = :code.which(Ipse.Development.Fixtures.Knowledge) |> to_string() |> Path.dirname()
    paths = if include_fixture, do: [fixture | paths], else: paths
    Enum.flat_map(paths, &["-pa", &1])
  end

  test "variant declarations reject hidden fallback, mismatched stores and unselected model routes",
       ctx do
    declared = matrix_plan(ctx, "http://127.0.0.1:19999")
    assert :ok = Contract.validate(declared)

    changed = fn id, update ->
      Map.update!(declared, "variants", fn variants ->
        Enum.map(variants, fn variant ->
          if variant["id"] == id, do: update.(variant), else: variant
        end)
      end)
    end

    for limits <- [
          %{"max_sources" => 11, "max_body_bytes" => 1024, "timeout_ms" => 1000},
          %{"max_sources" => 1.0, "max_body_bytes" => 1024, "timeout_ms" => 1000},
          %{"max_sources" => 1, "max_body_bytes" => 49_153, "timeout_ms" => 1000},
          %{"max_sources" => 1, "max_body_bytes" => 1024, "timeout_ms" => 999},
          %{"max_sources" => 1, "max_body_bytes" => 1024, "timeout_ms" => 1000, "renew" => true}
        ] do
      assert {:error, :research_limits} =
               Contract.validate(
                 changed.("research", fn variant ->
                   put_in(variant, ["query_options", "limits"], limits)
                 end)
               )
    end

    assert {:error, :variant_algorithm} =
             Contract.validate(changed.("lexical", &Map.put(&1, "prepare", "embedding")))

    assert {:error, :hidden_fallback} =
             Contract.validate(
               changed.("hybrid", fn variant ->
                 Map.update!(variant, "artifacts", fn [corpus | rest] ->
                   [
                     put_in(
                       corpus,
                       ["options", "retrieval", "combined", "missing_embedding"],
                       "lexical_with_gap"
                     )
                     | rest
                   ]
                 end)
               end)
             )

    assert {:error, :graph_store_sharing} =
             Contract.validate(
               changed.("graph_model", fn variant ->
                 Map.update!(
                   variant,
                   "artifacts",
                   &Enum.map(&1, fn entry ->
                     if entry["instance"] == "graph",
                       do: Map.put(entry, "state_binding", "foreign"),
                       else: entry
                   end)
                 )
               end)
             )

    assert {:error, :profile_reference} =
             Contract.validate(
               changed.("rerank", fn variant ->
                 Map.update!(variant, "artifacts", fn [corpus | rest] ->
                   [
                     put_in(corpus, ["options", "rerank", "chosen", "profile"], "unselected")
                     | rest
                   ]
                 end)
               end)
             )

    assert {:error, :fixture_model_origin} =
             Contract.validate(
               put_in(declared, ["profiles", "p27_answer", "base_url"], "http://127.0.0.1:11434")
             )
  end
end
