Code.require_file("../dev/evaluation/session.exs", __DIR__)

defmodule Ipse.KnowledgeQueryCompletenessTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Evaluation.Session, as: EvaluationSession
  alias Ipse.{Session, Usage}
  alias Ipse.Extensions.{State, EmbeddingCall}

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Lexical completeness control attempted inference")
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-query-completeness-" <> Usage.id())
    File.mkdir!(root)

    artifacts =
      Map.new(
        [
          {"corpus", "corpus", "state-lexical"},
          {"graph", "graph", "state-explicit"},
          {"dense", "corpus", "state-dense"}
        ],
        fn {name, package, preset} ->
          artifact = Path.join(root, name)

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
                package,
                "--preset",
                preset
              ],
              stderr_to_stdout: true
            )

          assert status == 0, output
          {name, artifact}
        end
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, artifacts: artifacts}
  end

  test "public lexical queries distinguish intentional exclusions from an unpublished source",
       ctx do
    {run, policy} = open(ctx, :lexical)

    try do
      assert put(run, policy, source("current"))["status"] == "ok"
      current = query(run, policy, "Release")
      assert put(run, policy, source("forgotten"))["status"] == "ok"

      coverage =
        source_call(run, policy, "inspect", %{"source_id" => "fixture:forgotten"})["coverage"]

      assert source_call(run, policy, "forget", %{
               "source_id" => "fixture:forgotten",
               "expected_revision" => coverage["revision"]
             })["status"] == "ok"

      forgotten = query(run, policy, "Release")
      assert put(run, policy, Map.put(source("expired"), "expires_at_ms", 20))["status"] == "ok"
      expired = query(run, policy, "Release")
      assert put(run, policy, Map.put(source("future"), "observed_at_ms", 21))["status"] == "ok"
      future = query(run, policy, "Release")
      absent = query(run, policy, "absent mineral")

      pending =
        source("pending")
        |> Map.delete("text")
        |> Map.merge(%{
          "byte_count" => 28,
          "content_sha256" => Ipse.JSON.sha256("Release requires quiescence.")
        })

      assert source_call(run, policy, "open", pending)["status"] == "draft"
      incomplete = query(run, policy, "Release")
      incomplete_empty = query(run, policy, "absent mineral")

      observed =
        Map.new(
          [
            {"current", current},
            {"forgotten", forgotten},
            {"expired", expired},
            {"future", future},
            {"absent", absent},
            {"incomplete", incomplete},
            {"incomplete_empty", incomplete_empty}
          ],
          fn {name, result} -> {name, result["status"]} end
        )

      assert observed == %{
               "current" => "ok",
               "forgotten" => "ok",
               "expired" => "ok",
               "future" => "ok",
               "absent" => "abstain",
               "incomplete" => "partial",
               "incomplete_empty" => "partial"
             }

      for result <- [current, forgotten, expired, future, incomplete] do
        assert Enum.map(result["evidence"], & &1["citation"]["source_id"]) == ["fixture:current"]
        assert result["coverage"]["revalidated"]
      end

      assert Enum.any?(forgotten["gaps"], &(&1["code"] == "suppressed"))
      assert Enum.any?(expired["gaps"], &(&1["code"] == "stale_source"))
      assert Enum.any?(incomplete_empty["gaps"], &(&1["code"] == "incomplete_source"))
      assert incomplete_empty["evidence"] == []
      assert incomplete["coverage"]["complete"] == false
      assert future["coverage"]["complete"] == true
      assert length(future["coverage"]["exclusions"]) == 3
      assert Session.info(run.pid).accounting["request_count"] == 0
      assert {:ok, %{"cleanup" => "confirmed"}} = EvaluationSession.close(run)
    after
      if Process.alive?(run.pid), do: EvaluationSession.close(run)
    end
  end

  test "public Corpus graph fusion retains a truncated traversal", ctx do
    {run, policy} = open(ctx, :graph)
    text = "Release requires quiescence. Quiescence uses locks."
    input = Map.put(source("current"), "text", text)

    try do
      assert put(run, policy, input)["status"] == "ok"

      [chunk] =
        source_call(run, policy, "inspect", %{"source_id" => input["source_id"]})["coverage"][
          "chunks"
        ]

      attrs =
        input
        |> Map.delete("expected_revision")
        |> Map.merge(%{
          "partition" => "manual",
          "origin" => %{
            "kind" => "provided",
            "store_profile" => "notes",
            "partition_or_scope" => "manual",
            "receipt" => nil,
            "historical" => false
          }
        })

      author = ~S'''
      alias IpseKnowledge.Evidence, as: E
      {:ok, source} = E.source(JSON.decode!(hd(System.argv())))
      {:ok, [chunk]} = E.chunks(source)
      {:ok, citation} = E.citation(source, chunk, 0, byte_size(source["text"]))
      expires = System.system_time(:millisecond) + 86_400_000
      facts = for {subject, predicate, object} <- [{"Release", "requires", "quiescence"}, {"quiescence", "uses", "locks"}] do
        {:ok, fact} = E.fact(%{"subject" => subject, "predicate" => predicate, "object" => object, "polarity" => "positive", "inferred" => false, "valid_from_ms" => nil, "valid_to_ms" => expires, "extraction" => %{"kind" => "explicit", "profile" => nil, "version" => 1}, "citations" => [citation]})
        fact
      end
      IO.puts(JSON.encode!(facts))
      '''

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          ["-r", "extensions/knowledge/src/evidence.ex", "-e", author, "--", JSON.encode!(attrs)],
          stderr_to_stdout: true
        )

      assert status == 0, output
      facts = JSON.decode!(output)

      assert invoke(
               run,
               policy,
               "extract",
               %{
                 "store" => "notes",
                 "extraction" => "asserted",
                 "source_id" => input["source_id"],
                 "generation" => 1,
                 "max_edges" => 2,
                 "chunks" => [chunk["chunk_id"]],
                 "facts" => facts
               },
               "graph"
             )["status"] == "ok"

      result = query(run, policy, "Release", "bounded")
      assert result["status"] == "partial"
      assert result["evidence"] != []
      assert result["coverage"]["complete"] == false
      assert result["coverage"]["components"]["graph"]["complete"] == false

      depth_bounded = query(run, policy, "Release", "depth_bounded")
      assert depth_bounded["status"] == "partial"
      assert depth_bounded["coverage"]["components"]["graph"]["complete"] == false
      assert depth_bounded["coverage"]["complete"] == false
      assert depth_bounded["evidence"] != []

      graph_args = %{
        "store" => "notes",
        "entity" => "Release",
        "depth" => 2,
        "max_nodes" => 16,
        "max_edges" => 1,
        "top_k" => 10,
        "as_of_ms" => 20
      }

      direct_bounded = invoke(run, policy, "query", graph_args, "graph")

      for depth <- [0, 1] do
        direct =
          invoke(
            run,
            policy,
            "query",
            %{graph_args | "depth" => depth, "max_edges" => 16},
            "graph"
          )

        assert direct["status"] == "partial"
        refute direct["coverage"]["complete"]
        assert direct["coverage"]["edges"] == depth
      end

      assert put(run, policy, source("forgotten"))["status"] == "ok"

      revision =
        source_call(run, policy, "inspect", %{"source_id" => "fixture:forgotten"})["coverage"][
          "revision"
        ]

      assert source_call(run, policy, "forget", %{
               "source_id" => "fixture:forgotten",
               "expected_revision" => revision
             })["status"] == "ok"

      direct_eligible = invoke(run, policy, "query", %{graph_args | "max_edges" => 16}, "graph")

      direct_expired =
        invoke(
          run,
          policy,
          "query",
          %{graph_args | "max_edges" => 16, "as_of_ms" => hd(facts)["valid_to_ms"]},
          "graph"
        )

      assert direct_expired["status"] == "abstain"
      assert direct_expired["coverage"]["complete"]
      assert direct_expired["evidence"] == []

      assert Enum.count(
               direct_expired["coverage"]["exclusions"],
               &(&1["code"] == "excluded_fact")
             ) == 2

      pending =
        source("pending")
        |> Map.delete("text")
        |> Map.merge(%{
          "byte_count" => 28,
          "content_sha256" => Ipse.JSON.sha256("Release requires quiescence.")
        })

      assert source_call(run, policy, "open", pending)["status"] == "draft"

      direct_incomplete =
        invoke(
          run,
          policy,
          "query",
          %{graph_args | "entity" => "absent", "max_edges" => 16},
          "graph"
        )

      assert %{
               bounded: direct_bounded["status"],
               eligible: direct_eligible["status"],
               incomplete: direct_incomplete["status"]
             } == %{bounded: "partial", eligible: "ok", incomplete: "partial"}

      assert direct_bounded["coverage"]["complete"] == false
      assert direct_eligible["coverage"]["complete"] == true
      assert direct_incomplete["coverage"]["complete"] == false
      assert direct_incomplete["evidence"] == []
      assert Session.info(run.pid).accounting["request_count"] == 0
      assert {:ok, %{"cleanup" => "confirmed"}} = EvaluationSession.close(run)
    after
      if Process.alive?(run.pid), do: EvaluationSession.close(run)
    end
  end

  test "an explicit lexical fallback for missing vectors remains partial", ctx do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    parent = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 10_000)

        try do
          {:ok, {:http_request, :POST, {:abs_path, "/api/embed"}, _}} =
            :gen_tcp.recv(socket, 0, 5000)

          length = headers(socket, 0)
          true = length in 1..4096
          :ok = :inet.setopts(socket, packet: :raw)
          {:ok, bytes} = :gen_tcp.recv(socket, length, 5000)
          send(parent, {:query_encoding, JSON.decode!(bytes)})

          body =
            JSON.encode!(%{
              "model" => "fixture-query-encoder",
              "embeddings" => [[1.0, 0.0]],
              "prompt_eval_count" => 3
            })

          :ok =
            :gen_tcp.send(socket, [
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
              body
            ])
        after
          :gen_tcp.close(socket)
        end
      end)

    {run, policy} = open(ctx, :hybrid, "http://127.0.0.1:#{port}")

    try do
      assert put(run, policy, source("current"))["status"] == "ok"
      result = query(run, policy, "Release", "fallback")
      assert result["status"] == "partial"
      assert result["coverage"]["complete"] == false
      assert Enum.any?(result["gaps"], &(&1["code"] == "missing_embedding" and &1["count"] == 1))
      assert Enum.map(result["evidence"], & &1["citation"]["source_id"]) == ["fixture:current"]
      assert Session.info(run.pid).accounting["request_count"] == 1
      assert_receive {:query_encoding, %{"input" => ["Release"]}}, 1000
      assert :ok = Task.await(server, 5000)
      assert {:ok, %{"cleanup" => "confirmed"}} = EvaluationSession.close(run)
    after
      if Process.alive?(run.pid), do: EvaluationSession.close(run)
      :gen_tcp.close(listener)
      Task.shutdown(server, :brutal_kill)
    end
  end

  defp headers(socket, length) do
    case :gen_tcp.recv(socket, 0, 5000) do
      {:ok, :http_eoh} ->
        length

      {:ok, {:http_header, _, name, _, value}} ->
        headers(
          socket,
          if(String.downcase(to_string(name)) == "content-length",
            do: String.to_integer(value),
            else: length
          )
        )
    end
  end

  defp open(ctx, mode, origin \\ nil) do
    options = JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))

    options =
      if mode == :graph,
        do:
          put_in(options, ["retrieval", "bounded"], %{
            "kind" => "graph",
            "version" => 1,
            "lexical" => "words",
            "depth" => 2,
            "max_nodes" => 16,
            "max_edges" => 1
          })
          |> put_in(["retrieval", "depth_bounded"], %{
            "kind" => "graph",
            "version" => 1,
            "lexical" => "words",
            "depth" => 1,
            "max_nodes" => 16,
            "max_edges" => 16
          }),
        else: options

    selections =
      if mode == :graph,
        do: [
          {"corpus", options},
          {"graph", JSON.decode!(File.read!("extensions/knowledge/options/graph-explicit.json"))}
        ],
        else: [{"corpus", options}]

    selections =
      if mode == :hybrid do
        [
          {"corpus",
           options
           |> Map.put("embedding", %{
             "native" => %{"kind" => "embedding", "profile" => "query_vectors"}
           })
           |> put_in(["retrieval", "fallback"], %{
             "kind" => "hybrid",
             "version" => 1,
             "lexical" => "words",
             "embedding" => "native",
             "graph" => nil,
             "rrf_k" => 60,
             "missing_embedding" => "lexical_with_gap"
           })}
        ]
      else
        selections
      end

    artifacts =
      for {{instance, options}, order} <- Enum.with_index(selections) do
        path = ctx.artifacts[if(mode == :hybrid, do: "dense", else: instance)]
        bytes = File.read!(Path.join(path, "extension.json"))
        digest = Ipse.JSON.sha256(bytes)
        manifest = JSON.decode!(bytes)

        %{
          instance: instance,
          path: path,
          digest: digest,
          options: options,
          order: order,
          trust: %{
            "artifact" => digest,
            "capabilities" => manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false,
            "state_bindings" => [
              %{"version" => 1, "instance" => instance, "id" => "scope", "scopes" => ["project"]}
            ]
          }
        }
      end

    bindings = %{
      "ingest" => %{"instance" => "corpus", "id" => "source"},
      "query" => %{"instance" => "corpus", "id" => "query"}
    }

    bindings =
      if mode == :graph,
        do: Map.put(bindings, "extract", %{"instance" => "graph", "id" => "extract"}),
        else: bindings

    spec = %{
      root: ctx.root,
      project: "synthetic",
      variant: Atom.to_string(mode),
      artifacts: artifacts,
      runtime: %{
        provider: :demo,
        model: "unused",
        provider_module: NoModel,
        compact: false,
        budget: %{"version" => 1, "max_requests" => 1},
        embedding_profiles:
          if(mode == :hybrid,
            do: %{
              "query_vectors" => %{
                "operation" => "embedding",
                "provider" => "ollama",
                "model" => "fixture-query-encoder",
                "credential" => "none",
                "base_url" => origin,
                "dimensions" => 2,
                "dimension_mode" => "native",
                "timeout_ms" => 5000
              }
            },
            else: %{}
          )
      },
      bindings: bindings,
      required_verbs: Map.keys(bindings),
      approval_validator: fn _ -> :deny end,
      timeout_ms: 20_000
    }

    {:ok, run} = EvaluationSession.open(spec)
    {:ok, cwd} = Ipse.WorkspaceContext.canonical_path(Path.join(run.directory, "workspace"))

    namespace =
      Ipse.JSON.digest([
        %{
          "scope" => "project",
          "project" => Ipse.JSON.sha256(cwd),
          "session" => nil,
          "version" => 2,
          "binding" => "scope"
        }
      ])

    runtime =
      Map.put(
        spec.runtime,
        :extensions,
        Enum.map(artifacts, &%{identity: %{"capabilities" => &1.trust["capabilities"]}})
      )

    {run,
     %{
       artifacts: Map.new(artifacts, &{&1.instance, &1.digest}),
       namespace: namespace,
       runtime: runtime
     }}
  end

  defp source(name),
    do: %{
      "source_id" => "fixture:" <> name,
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Release policy",
      "text" => "Release requires quiescence.",
      "uri" => "local:" <> name,
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

  defp put(run, policy, source), do: source_call(run, policy, "put", source)

  defp source_call(run, policy, action, args),
    do: invoke(run, policy, "source", %{"store" => "notes", "action" => action, "args" => args})

  defp query(run, policy, text, retrieval \\ "words"),
    do:
      invoke(run, policy, "query", %{
        "store" => "notes",
        "retrieval" => retrieval,
        "rerank" => nil,
        "query" => text,
        "top_k" => 10,
        "as_of_ms" => 20
      })

  defp invoke(run, policy, command, args, instance \\ "corpus") do
    assert :ok =
             Session.invoke_export(
               run.pid,
               :command,
               "ext__" <> instance <> "__" <> command,
               args
             )

    wait(run, policy, System.monotonic_time(:millisecond) + 20_000)
  end

  defp wait(run, policy, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:ipse, pid, {:approval, ref, "extension:state.put", proposed}} when pid == run.pid ->
        assert proposed["artifact_sha256"] == policy.artifacts[proposed["extension"]]
        assert proposed["namespace"] == policy.namespace
        assert :ok = State.validate(proposed["request"])
        assert proposed["request"]["scope"] == "project"
        assert :ok = Session.approve(pid, ref, true)
        wait(run, policy, deadline)

      {:ipse, pid, {:approval, ref, "extension:embedding.create", proposed}}
      when pid == run.pid ->
        assert proposed["artifact_sha256"] == policy.artifacts["corpus"]
        assert proposed["namespace"] == run.session_id
        assert proposed["request"]["inputs"] == ["Release"]
        assert proposed["request"]["profile"] == "query_vectors"
        assert {:ok, binding} = EmbeddingCall.binding(policy.runtime, proposed["request"])
        assert proposed["effect_binding"] == binding
        assert :ok = Session.approve(pid, ref, true)
        wait(run, policy, deadline)

      {:ipse, pid, {:done, :ok}} when pid == run.pid ->
        assert {:ok, value, _proof} =
                 EvaluationSession.complete_result(pid, Session.info(pid).extension_result)

        value

      {:ipse, pid, _} when pid == run.pid ->
        wait(run, policy, deadline)
    after
      remaining -> flunk("Public completeness control did not finish")
    end
  end
end
