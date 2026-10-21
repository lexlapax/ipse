Code.require_file("../examples/knowledge/evaluation_model_service.exs", __DIR__)
Code.require_file("../dev/verification/cli.exs", __DIR__)
Ipse.Development.Verification.Runtime.load_fixture!(:model_service)

defmodule Ipse.KnowledgeMeasuredModelFixtureTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.EvaluationModelService
  alias Ipse.Development.Fixtures.ModelService, as: Fixture
  alias Ipse.Development.Fixtures.ModelService.Daemon

  if :os.type() == {:unix, :linux} do
    test "a terminal service exit waits for helper cleanup without sending cancellation" do
      root = Path.join(System.tmp_dir!(), "ipse-measured-exit-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)

      config = Fixture.configuration(root, launch(), "http://127.0.0.1:#{port}", :exit_on_answer)
      owner = self()
      Code.ensure_loaded!(Ipse.Runner)

      tracer = spawn(fn -> observe_service_close(owner, nil) end)
      trace = :trace.session_create(:ipse_model_service_terminal, tracer, [])

      try do
        assert :trace.function(trace, {EvaluationModelService, :close_daemon, 1}, true, [:local]) ==
                 1

        assert :trace.function(trace, {Ipse.Runner, :close_stdio, 2}, true, [:local]) == 1
        :trace.process(trace, self(), true, [:call])
        output = Path.join(root, "service")

        result =
          EvaluationModelService.run(config, output, fn ->
            input = JSON.encode!(%{"query" => "absent mineral", "candidates" => []})
            content = "Synthetic exit control\n" <> JSON.encode!(%{"input" => input})

            body =
              JSON.encode!(%{
                "model" => "fixture-text:latest",
                "messages" => [%{"role" => "user", "content" => content}]
              })

            {:ok, connection} =
              :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)

            :ok =
              :gen_tcp.send(connection, [
                "POST /api/chat HTTP/1.1\r\nhost: 127.0.0.1\r\ncontent-type: application/json\r\ncontent-length: ",
                Integer.to_string(byte_size(body)),
                "\r\nconnection: close\r\n\r\n",
                body
              ])

            _ = :gen_tcp.recv(connection, 0, 5_000)
            :gen_tcp.close(connection)

            receive do
              :unexpected -> :unexpected
            after
              30_000 -> :unexpected_return
            end
          end)

        assert_receive {:service_close_mode, :completed}, 1_000
        assert result.work == {:interrupted, :service_exited}
        assert result.receipt["code"] == "service_exited"
        assert result.receipt["status"] == "failed"
        assert result.receipt["native_cleanup"] == "confirmed"
        assert result.receipt["staging_cleanup"] == "confirmed"
        assert JSON.decode!(File.read!(Path.join(output, "receipt.json"))) == result.receipt

        answers =
          Path.join(output, "home/fixture-requests.jsonl")
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.map(&JSON.decode!/1)
          |> Enum.filter(&(&1["operation"] == "answer"))

        assert length(answers) == 1
      after
        :trace.session_destroy(trace)
        Process.exit(tracer, :kill)
      end
    end

    defp observe_service_close(owner, selected) do
      receive do
        {:trace, ^owner, :call, {EvaluationModelService, :close_daemon, [state]}} ->
          observe_service_close(owner, state.port)

        {:trace, ^owner, :call, {Ipse.Runner, :close_stdio, [port, mode]}}
        when port == selected ->
          send(owner, {:service_close_mode, mode})
          observe_service_close(owner, selected)

        _ ->
          observe_service_close(owner, selected)
      end
    end

    test "generated ERTS wrapper starts successive owned fixtures on the sealed origin" do
      root = Path.join(System.tmp_dir!(), "ipse-measured-wrapper-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)

      config =
        Fixture.configuration(root, launch(), "http://127.0.0.1:#{port}")

      for index <- 1..2 do
        result =
          EvaluationModelService.run(config, Path.join(root, "service-#{index}"), fn -> :ready end)

        details = Map.take(result.receipt, ~w(code status work_status native_cleanup))
        assert result.work == {:returned, :ready}, inspect(details)
        assert result.receipt["status"] == "ok", inspect(details)
        assert result.receipt["native_cleanup"] == "confirmed"
        assert result.receipt["metadata_requests"] > 0
        assert is_integer(result.receipt["listener"]["pid"])
      end
    end
  end

  test "builder declares both synthetic model closures and an exact ERTS exec wrapper" do
    root = Path.join(System.tmp_dir!(), "ipse-measured-fixture-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(root) end)
    launch = launch()
    config = Fixture.configuration(root, launch, "http://127.0.0.1:47631")
    assert EvaluationModelService.validate(config) == :ok

    assert Enum.sort(Map.keys(config["models"])) ==
             ~w(fixture-embedding:latest fixture-text:latest)

    for {name, digest} <- config["models"] do
      bytes = File.read!(Path.join(config["cache_source"], config["manifests"][name]))
      assert Ipse.JSON.sha256(bytes) == digest
      manifest = JSON.decode!(bytes)

      for descriptor <- [manifest["config"] | manifest["layers"]] do
        "sha256:" <> hash = descriptor["digest"]
        blob = File.read!(Path.join(config["cache_source"], "blobs/sha256-" <> hash))
        assert byte_size(blob) == descriptor["size"]
        assert Ipse.JSON.sha256(blob) == hash
      end
    end

    [wrapper | _] = config["runtime"]["files"]
    source = File.read!(wrapper["source"])
    assert String.contains?(source, "exec '")
    assert String.contains?(source, launch["executable"])
    assert String.contains?(source, "code:set_path(Paths)")
    assert String.contains?(source, "$ipse_fixture_runtime/lib/ollama")
    refute String.contains?(source, "mix run")
    refute String.contains?(source, "require_file")
    assert Enum.count(config["runtime"]["files"], &(Path.extname(&1["path"]) == ".beam")) == 1

    assert_raise File.Error, fn ->
      Fixture.configuration(root, launch, config["origin"])
    end
  end

  test "scripted protocol preserves embedding extraction rerank answer and abstention" do
    models = %{
      "fixture-text:latest" => String.duplicate("a", 64),
      "fixture-embedding:latest" => String.duplicate("b", 64)
    }

    assert {"tags", %{"models" => tags}} =
             Daemon.response("GET", "/api/tags", %{}, models)

    assert Enum.sort(Enum.map(tags, & &1["name"])) == Enum.sort(Map.keys(models))

    assert {"resident", %{"models" => []}} =
             Daemon.response("GET", "/api/ps", %{}, models)

    assert {"show", %{"capabilities" => ["embedding"]}} =
             Daemon.response(
               "POST",
               "/api/show",
               %{"model" => "fixture-embedding:latest"},
               models
             )

    assert {"embedding", %{"embeddings" => vectors, "prompt_eval_count" => 3}} =
             Daemon.response(
               "POST",
               "/api/embed",
               %{"model" => "fixture-embedding:latest", "input" => ["Release", "mineral"]},
               models
             )

    assert vectors == [[1.0, 0.0], [0.0, 1.0]]

    {"extraction", result} =
      chat(%{"chunks" => [%{"id" => "c1", "text" => "Release requires quiescence."}]}, models)

    assert %{
             "facts" => [
               %{
                 "chunk" => "c1",
                 "predicate" => "requires",
                 "polarity" => "positive",
                 "quote" => "Release requires quiescence."
               }
             ]
           } =
             answer(result)

    {"rerank", result} =
      chat(%{"required_count" => 2, "candidates" => [%{"id" => "b"}, %{"id" => "a"}]}, models)

    assert answer(result) == %{"order" => ["b", "a"]}
    {"answer", result} = chat(%{"query" => "release", "candidates" => [%{"id" => "e1"}]}, models)

    assert answer(result) == %{
             "classification" => "answer",
             "claims" => [%{"text" => "Release requires quiescence.", "citations" => ["e1"]}]
           }

    assert result["eval_count"] == 8 and result["prompt_eval_count"] == 8

    {"answer", result} =
      chat(%{"query" => "absent mineral", "candidates" => [%{"id" => "e1"}]}, models)

    assert answer(result) == %{"classification" => "abstain", "claims" => []}
  end

  test "unselected model names and malformed request shapes never produce scripted inference" do
    models = %{"fixture-text:latest" => String.duplicate("a", 64)}

    assert_raise MatchError, fn ->
      Daemon.response("POST", "/api/show", %{"model" => "unknown"}, models)
    end

    assert_raise FunctionClauseError, fn ->
      Daemon.response(
        "POST",
        "/api/chat",
        %{"model" => "unknown", "messages" => []},
        models
      )
    end

    assert_raise MatchError, fn -> chat(%{"required_count" => 2, "candidates" => []}, models) end
  end

  defp chat(input, models) do
    content = "Synthetic input\n" <> JSON.encode!(%{"input" => JSON.encode!(input)})

    Daemon.response(
      "POST",
      "/api/chat",
      %{"model" => "fixture-text:latest", "messages" => [%{"content" => content}]},
      models
    )
  end

  defp answer(result), do: JSON.decode!(result["message"]["content"])

  defp launch do
    root = to_string(:code.root_dir())

    executable =
      Path.join([root, "erts-" <> to_string(:erlang.system_info(:version)), "bin", "erl"])

    boot =
      case :init.get_argument(:boot) do
        {:ok, [[path]]} ->
          candidate = Path.join(Path.dirname(List.to_string(path)), "start_clean")

          if File.regular?(candidate <> ".boot"),
            do: candidate,
            else: Path.join(root, "bin/no_dot_erlang")

        _ ->
          Path.join(root, "bin/no_dot_erlang")
      end

    files =
      for path <- [executable, boot <> ".boot"] do
        {:ok, path} = Ipse.WorkspaceContext.canonical_path(path)

        %{
          "path" => path,
          "bytes" => File.stat!(path).size,
          "sha256" => Ipse.JSON.sha256(File.read!(path))
        }
      end

    %{
      "executable" => hd(files)["path"],
      "boot" => String.replace_suffix(List.last(files)["path"], ".boot", ""),
      "root" => root,
      "code_paths" => Enum.map(:code.get_path(), &Path.expand(to_string(&1))),
      "files" => files
    }
  end
end
