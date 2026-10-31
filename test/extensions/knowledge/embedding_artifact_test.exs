defmodule IpseKnowledge.EmbeddingArtifactTest do
  use ExUnit.Case, async: false

  @probe ~S"""
  import ExUnit.Assertions
  alias IpseKnowledge.{Adapters, Evidence}
  refute Code.ensure_loaded?(Ipse.Session)
  refute Code.ensure_loaded?(Ipse.Extension.Context)
  item = %{"id" => "item", "version" => "1", "text" => "synthetic", "priority" => 1,
    "source" => %{"kind" => "assertion", "uri" => nil}}
  assert Ipse.Extension.context_rendered_bytes([item], "knowledge") > byte_size(item["text"])
  refute Code.ensure_loaded?(Ipse.Extension.Context)
  refute Code.ensure_loaded?(Ipse.Session.Reference)
  resolved = %{"options" => %{"embedding" => %{"local" => %{"kind" => "embedding", "profile" => "host"}}}}
  input = %{"chunk_id" => Evidence.sha256("chunk"), "text" => "snow 雪"}
  assert {:call, _, pending} = Adapters.start(resolved, :embed, %{"profile" => "local", "inputs" => [input]})
  bytes = <<1.0::little-float-size(32)>>
  descriptor = %{"version" => 2, "kind" => "embedding.f32le", "encoding" => "float32le.base64",
    "operation_id" => String.duplicate("1", 32), "source_sha256" => Evidence.sha256("source"),
    "vector_count" => 1, "dimensions" => 1}
  result = %{"version" => 2, "selection_sha256" => Evidence.sha256("selection"), "result" => descriptor,
    "profile" => "host", "reported_model" => "synthetic", "usage" => %{}}
  assert {:call, _, reading} = Adapters.resume(pending, %{"status" => "ok", "value" => result})
  {:ok, input_hash} = Ipse.Extension.canonical_digest([input["text"]])
  page = Map.merge(Map.take(descriptor, ~w(version kind encoding dimensions source_sha256 operation_id)),
    %{"vector_index" => 0, "offset" => 0, "complete" => true, "next" => nil,
      "input_sha256" => input_hash, "vector_sha256" => Evidence.sha256(bytes), "values" => Base.encode64(bytes)})
  assert {:done, {:ok, %{"vectors" => [vector]}}} = Adapters.resume(reading, %{"status" => "ok", "value" => page})
  assert Evidence.vector_input_matches_chunk?(vector, input)
  refute Evidence.vector_input_matches_chunk?(Map.put(vector, "input_sha256", Evidence.sha256("other")), input)
  wrong = Map.put(page, "input_sha256", Evidence.sha256("other"))
  assert {:done, {:error, :invalid_embedding_result, %{}}} = Adapters.resume(reading, %{"status" => "ok", "value" => wrong})
  IO.puts("CORPUS_ARTIFACT_INPUT_BINDING_OK")
  """

  test "built corpus artifact checks input binding with the minimal public SDK" do
    root = Path.join(System.tmp_dir!(), "ipse-embedding-artifact-" <> Ipse.Usage.id())
    sdk = Path.join(root, "lib/ipse/ebin")
    File.mkdir_p!(sdk)
    on_exit(fn -> File.rm_rf!(root) end)

    dependencies =
      for dep <- ~w(jason jsonschex ex_json_pointer)a do
        target = Path.join([root, "lib", Atom.to_string(dep), "ebin"])
        File.mkdir_p!(Path.dirname(target))
        File.cp_r!(Application.app_dir(dep, "ebin"), target)
        target
      end

    paths = Enum.flat_map(dependencies, &["-pa", &1])
    elixir = System.find_executable("elixir")

    compile =
      "case Kernel.ParallelCompiler.compile_to_path(~w(lib/ipse/json.ex lib/ipse/decision.ex lib/ipse/extension.ex), #{inspect(sdk)}, return_diagnostics: true) do {:ok,_,%{compile_warnings: [], runtime_warnings: []}} -> :ok; {:ok,_,[]} -> :ok; bad -> raise inspect(bad) end"

    assert {_, 0} = System.cmd(elixir, paths ++ ["-e", compile], stderr_to_stdout: true)
    artifact = Path.join(root, "artifact")
    builder_support = Path.join(root, "builder-support")
    File.mkdir_p!(builder_support)

    for module <- [Ipse.Extension.Catalog, Ipse.Extension.History] do
      beam = Atom.to_string(module) <> ".beam"
      File.cp!(Application.app_dir(:ipse, "ebin/" <> beam), Path.join(builder_support, beam))
    end

    {output, status} =
      System.cmd(
        elixir,
        [
          "-pa",
          builder_support,
          "extensions/knowledge/build.exs",
          "--sdk",
          sdk,
          "--output",
          artifact,
          "--package",
          "corpus",
          "--preset",
          "state-dense"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    {output, status} =
      System.cmd(elixir, paths ++ ["-pa", sdk, "-pa", Path.join(artifact, "ebin"), "-e", @probe],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "CORPUS_ARTIFACT_INPUT_BINDING_OK"
  end
end
