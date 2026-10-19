Code.require_file("../examples/knowledge/evaluation_plan.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationRunnerTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.EvaluationRunner, as: Runner

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
          "examples/model-calls/build.exs",
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

  for scenario <- [:current, :suppressed] do
    @tag scenario: scenario
    test "all seven variants preserve #{scenario} source selection and canonical model accounting",
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
        "sha256" => Ipse.Extensions.Manifest.sha256(text),
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
          "sha256" => Ipse.Extensions.Manifest.sha256("PRIVATE_FORGOTTEN requires silence."),
          "byte_length" => byte_size("PRIVATE_FORGOTTEN requires silence.")
      }

      expired = %{
        doc
        | "document_id" => "d3",
          "source_id" => "fixture:expired",
          "title" => "Expired",
          "state" => "expired",
          "text" => "PRIVATE_EXPIRED requires silence.",
          "sha256" => Ipse.Extensions.Manifest.sha256("PRIVATE_EXPIRED requires silence."),
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
              "query" => text,
              "expected_answer" => "NEVER_PROVIDER_INPUT"
            }
          )
      }

      plan = matrix_plan(ctx, origin)

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
        assert :ok = Runner.validate(plan)
        output = Path.join(root, "results")

        assert {:ok, report} =
                 Runner.run(:verify,
                   plan: Path.join(root, "plan.json"),
                   corpus: Path.join(root, "corpus.json"),
                   queries: Path.join(root, "queries.json"),
                   output: output
                 )

        assert report["execution_complete"], inspect(report)
        assert report["rows"] == 14
        preflight = JSON.decode!(File.read!(Path.join(output, "preflight.json")))
        assert preflight["status"] == "ok"
        assert preflight["inventory"]["status"] == "ok"

        assert Enum.map(preflight["variants"], & &1["variant"]) ==
                 Enum.map(plan["variants"], & &1["id"])

        initialized = Enum.flat_map(preflight["variants"], & &1["value"]["initialization"])
        assert length(initialized) == 16
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

        for kind <- ~w(embedding extraction rerank answer),
            do: assert(Enum.any?(requests, &(&1["fixture_operation"] == kind)), kind)

        usage = jsonl(Path.join(output, "usage.jsonl"))
        assert Enum.count(usage, &Map.has_key?(&1, "budget")) == 7

        assert Enum.sum(for row <- usage, row["budget"], do: row["budget"]["request_count"]) ==
                 length(requests)

        events = jsonl(Path.join(output, "execution.jsonl"))
        assert Enum.count(events, &(&1["phase"] == "close" and &1["status"] == "ok")) == 7

        if scenario == :suppressed,
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

    {:ok, declared} = IpseKnowledgeExample.EvaluationPlan.build(spec)
    declared
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
        ["POST", target, _] = String.split(line, " ")

        headers =
          Map.new(fields, fn field ->
            [key, value] = String.split(field, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        length = String.to_integer(headers["content-length"])

        if byte_size(rest) < length do
          {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
          http_request(socket, bytes <> more)
        else
          {target, JSON.decode!(binary_part(rest, 0, length))}
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        http_request(socket, bytes <> more)
    end
  end

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
                 "chunk_id" => chunk["chunk_id"],
                 "start_byte" => chunk["start_byte"],
                 "end_byte" => chunk["end_byte"]
               }
             ]
           }}

        is_integer(input["required_count"]) ->
          {"rerank", %{"order" => Enum.map(input["candidates"], & &1["id"])}}

        input["candidates"] == [] or input["query"] == "absent mineral" ->
          {"answer", %{"classification" => "abstain", "answer" => "No evidence.", "claims" => []}}

        true ->
          {"answer",
           %{
             "classification" => "answer",
             "answer" => "Release requires quiescence.",
             "claims" => [
               %{
                 "text" => "Release requires quiescence.",
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
              ~w(ingest inspect forget query),
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
          "sha256" => Ipse.Extensions.Manifest.sha256(text),
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
            "sha256" => Ipse.Extensions.Manifest.sha256(File.read!(paths[name]))
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
        Ipse.Extensions.Manifest.sha256(manifest_bytes)
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
             IpseKnowledgeExample.EvaluationFreeze.create(
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
    assert {:error, :heldout_matrix} = Runner.validate(declared)

    assert {:error, %{"code" => "labels_forbidden"}} =
             Runner.run(:predict, labels: "must-not-open")

    assert {:error, %{"code" => "option_shape"}} = Runner.run(:verify, unknown: "must-not-open")
  end

  test "usage export preserves canonical requests beyond the sixteen-request UI snapshot", ctx do
    {server, origin, tag} = model_fixture()
    {paths, root} = cli_inputs(ctx, false)
    matrix = matrix_plan(ctx, origin)
    declared = %{matrix | "variants" => [hd(matrix["variants"])]}
    declared = put_in(declared, ["data", "expected_queries"], 17)

    queries =
      for index <- 1..17,
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

      assert report["rows"] == 17
      requests = drain(tag, [])
      assert length(requests) == 17
      assert Enum.all?(requests, &(&1["fixture_operation"] == "answer"))
      usage = jsonl(Path.join(output, "usage.jsonl"))
      [saved] = Enum.filter(usage, &Map.has_key?(&1, "budget"))
      assert saved["budget"]["request_count"] == 17

      {:ok, events} =
        Ipse.Journal.load(
          Path.join([output, "alpha", "lexical", "sessions"]),
          saved["session_id"]
        )

      {:ok, ledger} = Ipse.Usage.restore(events, saved["session_id"])
      assert Ipse.Usage.snapshot(ledger)["shown_request_count"] == 16
      records = Enum.filter(usage, &Map.has_key?(&1, "request_id"))
      assert length(records) == 17
      assert Enum.map(records, & &1["request_id"]) == Ipse.Usage.order(ledger)
      assert Enum.all?(records, &Ipse.Usage.valid_request_record?/1)

      assert Enum.all?(
               records,
               &(&1["selected_profile"] == "p27_answer" and &1["outcome"] == "completed")
             )

      resource_records = jsonl(Path.join(output, "request-resources.jsonl"))
      assert length(resource_records) == 17
      assert Enum.map(resource_records, & &1["query_id"]) == Enum.map(queries, & &1["query_id"])

      assert Enum.all?(
               resource_records,
               &(&1["attribution"] == "confirmed" and &1["budget_admitted"] and
                   &1["dispatch_intent"] and &1["budget_settled"])
             )

      resources = JSON.decode!(File.read!(Path.join(output, "resource-summary.json")))
      assert resources["complete"]
      [variant] = resources["variants"]
      assert variant["queries"]["observed"] == 17
      assert variant["queries"]["missing"] == 0
      assert variant["accounting_verified"]
      assert variant["requests"]["attempted"] == 17
      [answer] = variant["requests"]["groups"]
      assert answer["role"] == "answer" and answer["count"] == 17
      assert answer["latency_ms"]["observed"] == 17
      assert resources["storage_reachability_complete"]
      prepared = Enum.find(variant["storage_snapshots"], &(&1["phase"] == "after_preparation"))
      assert prepared["inventory"]["status"] == "verified"
      assert prepared["inventory"]["inventory"]["selected_pages"]["records"] > 0
      assert prepared["inventory"]["state_file_bytes"] > 0
      query_storage = Enum.filter(variant["storage_snapshots"], &(&1["phase"] == "after_query"))
      assert length(query_storage) == 17
      assert Enum.map(query_storage, & &1["query_id"]) == Enum.map(queries, & &1["query_id"])
      assert Enum.all?(query_storage, &(&1["inventory"] == prepared["inventory"]))
      assert length(Path.wildcard(Path.join(output, "storage-inventory-*.json"))) == 1
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

  test "CLI status agrees with retained failed rows and refuses unsupported phases", ctx do
    for failed <- [false, true] do
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

    {summary, status} = cli(["--phase", "unsupported"])
    assert status == 1
    assert summary == %{"status" => "failed", "reason" => %{"code" => "invalid_options"}}

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
      assert :ok = Runner.validate(declared)
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

  test "CLI freezes copied selections and enforces frozen execution and hash-before-label phases",
       ctx do
    {paths, root} = cli_inputs(ctx, false)
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

    members =
      for name <- ~w(corpus queries),
          do: %{
            "path" => name <> ".json",
            "sha256" => Ipse.Extensions.Manifest.sha256(File.read!(paths[name]))
          }

    bytes = JSON.encode!(%{"files" => members})
    manifest = Path.join(root, "manifest.json")
    File.write!(manifest, bytes)

    declared =
      put_in(plan(ctx), ["data", "manifest_sha256"], Ipse.Extensions.Manifest.sha256(bytes))

    File.write!(paths["plan"], JSON.encode!(declared))

    {sealed, 0} =
      cli(
        ["--phase", "freeze", "--plan", paths["plan"], "--output", Path.join(root, "seal")],
        repository
      )

    assert sealed["status"] == "ok"
    frozen = ["--freeze", sealed["result"]["path"], "--freeze-sha256", sealed["result"]["sha256"]]
    output = Path.join(root, "frozen-results")

    {summary, 0} =
      cli(
        ["--phase", "verify-frozen"] ++
          frozen ++ ["--data-manifest", manifest, "--output", output]
      )

    assert summary["result"]["rows"] == 2
    assert summary["result"]["failed_rows"] == 0
    assert summary["result"]["execution_complete"]

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
            Path.join(output, "predictions.jsonl"),
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
      "sha256" => Ipse.Extensions.Manifest.sha256(text),
      "byte_length" => byte_size(text),
      "media_type" => "text/plain"
    }

    docs = if failed, do: [doc, %{doc | "document_id" => "d2", "version" => 2}], else: [doc]

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

  defp cli(arguments, cwd \\ File.cwd!()) do
    paths = Path.wildcard(Path.join([Path.dirname(Application.app_dir(:ipse)), "*", "ebin"]))
    code_paths = Enum.flat_map(paths, &["-pa", &1])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        code_paths ++ [Path.expand("scripts/evaluate-knowledge.exs") | arguments],
        stderr_to_stdout: true,
        cd: cwd
      )

    {output |> String.split("\n", trim: true) |> List.last() |> JSON.decode!(), status}
  end

  test "variant declarations reject hidden fallback, mismatched stores and unselected model routes",
       ctx do
    declared = matrix_plan(ctx, "http://127.0.0.1:19999")
    assert :ok = Runner.validate(declared)

    changed = fn id, update ->
      Map.update!(declared, "variants", fn variants ->
        Enum.map(variants, fn variant ->
          if variant["id"] == id, do: update.(variant), else: variant
        end)
      end)
    end

    assert {:error, :variant_algorithm} =
             Runner.validate(changed.("lexical", &Map.put(&1, "prepare", "embedding")))

    assert {:error, :hidden_fallback} =
             Runner.validate(
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
             Runner.validate(
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
             Runner.validate(
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
             Runner.validate(
               put_in(declared, ["profiles", "p27_answer", "base_url"], "http://127.0.0.1:11434")
             )
  end
end
