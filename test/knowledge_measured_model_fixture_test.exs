Code.require_file("../examples/knowledge/evaluation_model_service.exs", __DIR__)
Code.require_file("support/measured_model_fixture.exs", __DIR__)
Code.require_file("support/measured_model_daemon.exs", __DIR__)

defmodule Ipse.KnowledgeMeasuredModelFixtureTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.Manifest
  alias IpseKnowledgeExample.EvaluationModelService

  if :os.type() == {:unix, :linux} do
    test "generated ERTS wrapper starts successive owned fixtures on the sealed origin" do
      root = Path.join(System.tmp_dir!(), "ipse-measured-wrapper-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)

      config =
        MeasuredModelFixture.configuration(root, launch(), "http://127.0.0.1:#{port}")

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
    config = MeasuredModelFixture.configuration(root, launch, "http://127.0.0.1:47631")
    assert EvaluationModelService.validate(config) == :ok

    assert Enum.sort(Map.keys(config["models"])) ==
             ~w(fixture-embedding:latest fixture-text:latest)

    for {name, digest} <- config["models"] do
      bytes = File.read!(Path.join(config["cache_source"], config["manifests"][name]))
      assert Manifest.sha256(bytes) == digest
      manifest = JSON.decode!(bytes)

      for descriptor <- [manifest["config"] | manifest["layers"]] do
        "sha256:" <> hash = descriptor["digest"]
        blob = File.read!(Path.join(config["cache_source"], "blobs/sha256-" <> hash))
        assert byte_size(blob) == descriptor["size"]
        assert Manifest.sha256(blob) == hash
      end
    end

    [wrapper | _] = config["runtime"]["files"]
    source = File.read!(wrapper["source"])
    assert String.contains?(source, "exec '")
    assert String.contains?(source, launch["executable"])
    assert String.contains?(source, "code:set_path(Paths)")
    assert String.contains?(source, "$ipse_fixture_runtime/lib/ollama/measured_model_daemon.exs")
    refute String.contains?(source, "mix run")

    assert_raise File.Error, fn ->
      MeasuredModelFixture.configuration(root, launch, config["origin"])
    end
  end

  test "scripted protocol preserves embedding extraction rerank answer and abstention" do
    models = %{
      "fixture-text:latest" => String.duplicate("a", 64),
      "fixture-embedding:latest" => String.duplicate("b", 64)
    }

    assert {"tags", %{"models" => tags}} =
             MeasuredModelDaemon.response("GET", "/api/tags", %{}, models)

    assert Enum.sort(Enum.map(tags, & &1["name"])) == Enum.sort(Map.keys(models))

    assert {"resident", %{"models" => []}} =
             MeasuredModelDaemon.response("GET", "/api/ps", %{}, models)

    assert {"show", %{"capabilities" => ["embedding"]}} =
             MeasuredModelDaemon.response(
               "POST",
               "/api/show",
               %{"model" => "fixture-embedding:latest"},
               models
             )

    assert {"embedding", %{"embeddings" => vectors, "prompt_eval_count" => 3}} =
             MeasuredModelDaemon.response(
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
      MeasuredModelDaemon.response("POST", "/api/show", %{"model" => "unknown"}, models)
    end

    assert_raise FunctionClauseError, fn ->
      MeasuredModelDaemon.response(
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

    MeasuredModelDaemon.response(
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
          "sha256" => Manifest.sha256(File.read!(path))
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
