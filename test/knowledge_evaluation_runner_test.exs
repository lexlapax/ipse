Code.require_file("../examples/knowledge/evaluation_runner.exs", __DIR__)

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
        rows = jsonl(Path.join(output, "predictions.jsonl"))
        events = jsonl(Path.join(output, "execution.jsonl"))
        diagnostics = Enum.map(events, &Map.take(&1, ~w(phase verb status value class frames)))

        assert Enum.all?(
                 rows,
                 &(&1["status"] in if(scenario == :current, do: ~w(ok), else: ~w(ok partial)))
               ),
               inspect(diagnostics, limit: :infinity)

        assert Enum.all?(
                 Enum.filter(rows, &(&1["query_id"] == "Q1")),
                 &(&1["evidence"] != [] and
                     (&1["status"] == "partial" or
                        (&1["response_kind"] == "answer" and &1["context_evidence"] != [])))
               )

        assert Enum.all?(
                 Enum.filter(rows, &(&1["query_id"] == "Q2")),
                 &(&1["status"] == "partial" or &1["response_kind"] == "abstention")
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
    base = plan(ctx)
    lexical = hd(base["variants"])
    common = hd(lexical["artifacts"])["options"]

    vector =
      Map.merge(common, %{
        "embedding" => %{"native" => %{"kind" => "embedding", "profile" => "p27_embedding"}},
        "retrieval" =>
          Map.merge(common["retrieval"], %{
            "dense" => %{"kind" => "dense", "version" => 1, "embedding" => "native"},
            "combined" => %{
              "kind" => "hybrid",
              "version" => 1,
              "lexical" => "words",
              "embedding" => "native",
              "graph" => nil,
              "rrf_k" => 60,
              "missing_embedding" => "refuse"
            }
          })
      })

    answer = %{
      "alias" => "answer",
      "instance" => "answer",
      "options" => %{},
      "state_binding" => nil
    }

    variants =
      for id <- ~w(lexical graph_explicit graph_model dense hybrid rerank research) do
        {prepare, artifact, options, prepare_options, query_options, bindings, extra} =
          case id do
            "lexical" ->
              {"none", "lexical", common, lexical["prepare_options"], lexical["query_options"],
               lexical["bindings"], []}

            graph when graph in ~w(graph_explicit graph_model) ->
              kind = if graph == "graph_explicit", do: "explicit", else: "model"

              extraction =
                if kind == "explicit",
                  do: %{"kind" => "explicit", "version" => 1},
                  else: %{"kind" => "model_complete", "profile" => "p27_extract", "version" => 1}

              graph_options =
                JSON.decode!(File.read!("extensions/knowledge/options/graph-explicit.json"))
                |> Map.put("extraction", %{"chosen" => extraction})

              corpus_options =
                put_in(common, ["retrieval", "graph"], %{
                  "kind" => "graph",
                  "version" => 1,
                  "lexical" => "words",
                  "depth" => 2,
                  "max_nodes" => 16,
                  "max_edges" => 16
                })

              bindings =
                Map.put(lexical["bindings"], "extract", %{
                  "instance" => "graph",
                  "id" => "extract"
                })

              {if(kind == "explicit", do: "explicit", else: "extract"), "lexical", corpus_options,
               %{"store" => "notes", "extraction" => "chosen"},
               %{lexical["query_options"] | "retrieval" => "graph"}, bindings,
               [
                 %{
                   "alias" => kind,
                   "instance" => "graph",
                   "options" => graph_options,
                   "state_binding" => "evaluation"
                 }
               ]}

            dense when dense in ~w(dense hybrid rerank) ->
              opts =
                if dense == "rerank",
                  do:
                    Map.put(vector, "rerank", %{
                      "chosen" => %{
                        "kind" => "model_complete",
                        "profile" => "p27_rerank",
                        "max_candidates" => 16,
                        "quote_bytes" => 128
                      }
                    }),
                  else: vector

              query = %{
                lexical["query_options"]
                | "retrieval" => if(dense == "dense", do: "dense", else: "combined"),
                  "rerank" => if(dense == "rerank", do: "chosen")
              }

              {"embedding", if(dense == "rerank", do: "semantic", else: "dense"), opts,
               %{"store" => "notes", "embedding" => "native"}, query,
               Map.put(lexical["bindings"], "index", %{"instance" => "corpus", "id" => "index"}),
               []}

            "research" ->
              opts = %{
                common
                | "stores" => %{},
                  "search" => %{
                    "web" => %{
                      "kind" => "mcp",
                      "binding" => "search_web",
                      "contract" => "search-v1"
                    }
                  },
                  "fetch" => %{
                    "web" => %{
                      "kind" => "mcp",
                      "binding" => "fetch_web",
                      "contract" => "fetch-v1"
                    }
                  }
              }

              {"research", "research", opts, %{},
               %{
                 "search" => "web",
                 "fetch" => "web",
                 "retrieval" => "words",
                 "rerank" => nil,
                 "limits" => %{
                   "max_sources" => 3,
                   "max_body_bytes" => 49_152,
                   "timeout_ms" => 30_000
                 },
                 "sources" => []
               }, %{"research" => %{"instance" => "research", "id" => "investigate"}}, []}
          end

        instance = if id == "research", do: "research", else: "corpus"

        %{
          lexical
          | "id" => id,
            "prepare" => prepare,
            "artifacts" =>
              [
                %{
                  "alias" => artifact,
                  "instance" => instance,
                  "options" => options,
                  "state_binding" => if(id != "research", do: "evaluation")
                }
              ] ++ extra ++ [answer],
            "prepare_options" => prepare_options,
            "query_options" => query_options,
            "bindings" =>
              Map.put(bindings, "answer", %{"instance" => "answer", "id" => "complete"}),
            "budget" => %{"version" => 1, "max_requests" => 20}
        }
      end

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, search_port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)

    profiles =
      Map.new(
        ~w(p27_extract p27_rerank p27_answer),
        &{&1,
         %{
           "provider" => "ollama",
           "model" => "fixture-text",
           "credential" => "none",
           "base_url" => origin,
           "max_output_tokens" => 4096,
           "reasoning_effort" => "none",
           "timeout_ms" => 120_000
         }}
      )

    %{
      base
      | "artifacts" => ctx.artifacts,
        "variants" => variants,
        "answer" => true,
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
        "search_port" => search_port
    }
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
