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
  options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
    |> Map.put("version", 1)
    |> put_in(["stores", "notes"], %{"kind" => "state", "scope" => "project", "partition" => "notes"})
    |> put_in(["retrieval", "dense"], %{"kind" => "dense", "version" => 1, "embedding" => "local",
      "query_prefix" => "Instruct: Retrieve passages.\nQuery:"})
    |> put_in(["embedding", "local"], %{"kind" => "embedding", "profile" => "host"})
  {:ok, corpus} = IpseKnowledge.Corpus.init(options)
  args = %{"store" => "notes", "retrieval" => "dense", "rerank" => nil, "query" => "snow 雪", "top_k" => 1, "as_of_ms" => 1}
  wrapped = Map.put(args, "query", "Instruct: Retrieve passages.\nQuery:snow 雪")
  assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
    IpseKnowledge.Corpus.handle("invoke.command", %{"id" => "query", "arguments" => wrapped}, corpus)
  assert {:ok, %{"request" => %{"op" => "state.scan"}}, corpus} =
    IpseKnowledge.Corpus.handle("invoke.command", %{"id" => "query", "arguments" => args}, corpus)
  expected = "Instruct: Retrieve passages.\nQuery:snow 雪"
  assert {:ok, %{"request" => %{"op" => "embedding.create", "inputs" => [^expected]}}, corpus} =
    IpseKnowledge.Corpus.handle("host.actions", %{"outcome" => %{"status" => "ok",
      "value" => %{"generation" => 0, "records" => [], "next" => nil}}}, corpus)
  assert corpus.ctx.args["query"] == "snow 雪"
  text = "snow 雪"
  receipt = %{"kind" => "document_extraction", "version" => 2, "format" => "docx",
    "original_sha256" => Evidence.sha256("synthetic original"), "original_bytes" => 18,
    "extraction_version" => "ipse-documents-v14", "status" => "complete", "warnings" => [],
    "segments" => [%{"start_byte" => 0, "end_byte" => byte_size(text), "text_sha256" => Evidence.sha256(text),
      "locator" => %{"kind" => "paragraph", "part" => "word/document.xml", "paragraph" => 1}}],
    "acquisition" => %{"kind" => "workspace.read", "path" => "source.docx", "operation_id" => String.duplicate("2",32)}}
  {:ok, source} = Evidence.source(%{"source_id" => "workspace:source", "partition" => "notes",
    "generation" => 1, "title" => "Fixture", "text" => text, "uri" => "workspace:source.docx",
    "observed_at_ms" => 0, "event_at_ms" => nil, "expires_at_ms" => nil,
    "origin" => %{"kind" => "provided", "store_profile" => "notes", "partition_or_scope" => "notes",
      "receipt" => Evidence.document_storage_receipt!(receipt), "historical" => false}})
  assert Evidence.valid_source?(source)
  {:ok, initial} = IpseKnowledge.Corpus.init(options)
  state = %{initial | phase: :index_embed, pending: :adapter, cont: reading,
    ctx: %{args: %{"store" => "notes"}, store_profile: options["stores"]["notes"],
      opened: %{"source" => source, "draft" => %{}}}}
  assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused", "gaps" =>
    [%{"code" => "document_current_check_unavailable"}]}}, _} =
    IpseKnowledge.Corpus.handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => page}}, state)
  {:ok, [chunk]} = Evidence.chunks(source)
  stored = Map.put(vector, "chunk_id", chunk["chunk_id"])
  state = %{initial | phase: :query_embed, pending: :adapter, cont: reading,
    ctx: %{args: %{"query" => text, "top_k" => 1, "rerank" => "judge"}, as_of_ms: 1,
      retrieval: %{"kind" => "dense"}, snapshot: %{"sources" => [source],
        "projections" => %{source["source_key"] => %{"vectors" => [stored], "facts" => []}}}}}
  assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused", "gaps" =>
    [%{"code" => "document_current_check_unavailable"}]}}, _} =
    IpseKnowledge.Corpus.handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => page}}, state)
  IO.puts("CORPUS_ARTIFACT_INPUT_BINDING_OK")
  """

  @collection_probe ~S"""
  import ExUnit.Assertions
  options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
    |> Map.put("version", 1)
    |> put_in(["stores", "notes"], %{"kind" => "collection", "scope" => "project", "partition" => "notes"})
    |> put_in(["retrieval", "dense"], %{"kind" => "dense", "version" => 1, "embedding" => "local",
      "query_prefix" => "Instruct: Retrieve passages.\nQuery:"})
    |> put_in(["embedding", "local"], %{"kind" => "embedding", "profile" => "host"})
  {:ok, corpus} = IpseKnowledge.Corpus.init(options)
  args = %{"store" => "notes", "retrieval" => "dense", "query" => "snow 雪", "top_k" => 1,
    "as_of_ms" => 1, "source_ids" => ["source"],
    "vector_selection" => %{"selection_sha256" => String.duplicate("a", 64), "profile" => "host",
      "model" => "fixture", "dimensions" => 1024, "encoding" => "float32le"},
    "fact_selection" => %{"kind" => "explicit", "profile" => nil, "version" => 1}}
  wrapped = Map.put(args, "query", "Instruct: Retrieve passages.\nQuery:snow 雪")
  assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
    IpseKnowledge.Corpus.handle("invoke.command", %{"id" => "query_selected", "arguments" => wrapped}, corpus)
  assert {:ok, %{"kind" => "host_call", "request" => %{"op" => "collection.store"}}, _} =
    IpseKnowledge.Corpus.handle("invoke.command", %{"id" => "query_selected", "arguments" => args}, corpus)
  IO.puts("CORPUS_COLLECTION_PREFIX_OK")
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

    collection = Path.join(root, "collection-artifact")

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
          collection,
          "--package",
          "corpus",
          "--preset",
          "collection-dense"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    {output, status} =
      System.cmd(
        elixir,
        paths ++ ["-pa", sdk, "-pa", Path.join(collection, "ebin"), "-e", @collection_probe],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "CORPUS_COLLECTION_PREFIX_OK"
  end
end
