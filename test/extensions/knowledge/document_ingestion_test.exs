defmodule Ipse.KnowledgeDocumentIngestionTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  defp isolated(body) do
    files =
      ~w(profiles evidence adapters store store/state store/mcp_cas store/collection store/collection/index store/collection/projection store/collection/generation store/collection/directory store/collection/selected store/collection/job store/collection/reduction store/collection/finalization store/collection/paged store/collection/producer store/collection/producer_progress documents documents/zip documents/docx documents/parser_stage documents/pdf corpus)

    {source_args, compile_prefix} =
      case System.get_env("IPSE_DOCUMENT_TEST_ARTIFACT") do
        nil ->
          sources = Enum.map(files, &Path.join(@root, "extensions/knowledge/src/#{&1}.ex"))

          script =
            "case Kernel.ParallelCompiler.compile(" <>
              inspect(sources) <>
              ", return_diagnostics: true) do " <>
              "{:ok, _, []} -> :ok; " <>
              "{:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok; " <>
              "other -> raise inspect(other) end\n"

          {[], script}

        artifact ->
          {["-pa", Path.join(Path.expand(artifact), "ebin")], ""}
      end

    library_root =
      Ipse.Extension
      |> :code.which()
      |> List.to_string()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()

    paths = Path.wildcard(Path.join(library_root, "*/ebin"))
    args = Enum.flat_map(paths, &["-pa", &1]) ++ source_args

    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.{Corpus, Documents, Evidence, Store}
    alias Ipse.Development.Fixtures.Knowledge, as: F
    if artifact = System.get_env("IPSE_DOCUMENT_TEST_ARTIFACT") do
      for module <- [Corpus, Documents, Evidence, Store] do
        Code.ensure_loaded!(module)
        assert Path.dirname(to_string(:code.which(module))) == Path.join(Path.expand(artifact), "ebin")
      end
    end
    defmodule DocDriver do
      def call(state, db, id, args), do: drive(Corpus.handle("invoke.command", %{"id" => id, "arguments" => args}, state), db)
      def drive({:ok, %{"kind" => "host_call", "request" => request}, state}, db) do
        {outcome, db} = F.host(db, request)
        drive(Corpus.handle("host.actions", %{"outcome" => outcome}, state), db)
      end
      def drive({:ok, %{"kind" => "result", "value" => value}, state}, db), do: {value, state, db}
      def drive(other, _), do: raise("unexpected document continuation #{inspect(other, limit: 5)}")
      def store({:call, request, continuation}, db) do
        {outcome, db} = F.host(db, request)
        store(Store.resume(continuation, outcome), db)
      end
      def store(result, db), do: {result, db}
    end
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    make = fn body ->
      rel = "http://schemas.openxmlformats.org/package/2006/relationships"
      prefix = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
      root = "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"#{prefix}officeDocument\" Target=\"word/document.xml\"/></Relationships>"
      types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"
      {:ok, {_, bytes}} = :zip.create(~c"source.docx", [{~c"_rels/.rels", root}, {~c"[Content_Types].xml", types},
        {~c"word/document.xml", "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}], [:memory])
      bytes
    end
    paragraph = fn text -> "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" end
    state_profile = %{"kind" => "state", "scope" => "project", "partition" => "notes"}
    options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{"version" => 1, "stores" => %{"notes" => state_profile},
        "retrieval" => %{"lexical" => %{"kind" => "bm25", "version" => 1}}})
    {:ok, state} = Corpus.init(options)
    document_args = fn bytes, extra -> Map.merge(%{"source_id" => "provided:word", "generation" => 1,
      "expected_revision" => 0, "title" => "Explicit Word payload", "filename" => "source.docx",
      "bytes_base64" => Base.encode64(bytes), "uri" => "provided:source.docx", "observed_at_ms" => 10,
      "event_at_ms" => nil, "expires_at_ms" => nil}, extra) end
    source_command = fn state, db, action, args -> DocDriver.call(state, db, "source", %{"store" => "notes", "action" => action, "args" => args}) end
    query = fn state, db, text -> DocDriver.call(state, db, "query", %{"store" => "notes", "retrieval" => "lexical", "rerank" => nil,
      "query" => text, "top_k" => 3, "as_of_ms" => 20}) end
    '''

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        args ++
          [
            "-e",
            compile_prefix <>
              "false = Code.ensure_loaded?(Ipse.Development.Fixtures.Knowledge)\n" <>
              "Code.require_file(" <>
              inspect(Path.join(@root, "dev/fixtures/knowledge.exs")) <>
              ")\n" <> bootstrap <> body
          ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
  end

  test "isolated document fixtures ignore unrelated parent code paths" do
    root = Path.join(System.tmp_dir!(), "ipse-doc-polluted-path-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    source = Path.join(root, "polluted.ex")
    File.write!(source, "defmodule Ipse.Development.Fixtures.Knowledge do\nend\n")

    {output, status} =
      System.cmd(System.find_executable("elixirc"), ["-o", root, source], stderr_to_stdout: true)

    assert status == 0, output
    true = Code.prepend_path(root)

    on_exit(fn ->
      Code.delete_path(root)
      File.rm_rf!(root)
    end)

    isolated("assert :ok == :ok\n")
  end

  test "explicit Word payload becomes a stored revision and exact paragraph/table citations" do
    isolated(~S'''
    body = paragraph.("Résumé 好: keep authority explicit.") <>
      "<w:tbl><w:tr><w:tc>" <> paragraph.("Orion deployment is Tuesday.") <> "</w:tc></w:tr></w:tbl>"
    bytes = make.(body)
    descriptor = Enum.find(Corpus.describe()["exports"]["commands"], &(&1["id"] == "source"))
    assert :ok = Ipse.Extension.Catalog.validate_call(descriptor,
      %{"store" => "notes", "action" => "put_document", "args" => document_args.(bytes, %{})})
    {stored, state, db} = source_command.(state, F.new(), "put_document", document_args.(bytes, %{}))
    assert stored["status"] == "ok", inspect(stored)
    {result, state, db} = query.(state, db, "Orion deployment")
    assert result["status"] == "ok", inspect(result)
    [hit] = result["evidence"]
    citation = hit["citation"]
    assert citation["version"] == 2
    assert citation["quote"] == "Orion deployment is Tuesday."
    assert citation["document"]["original_sha256"] == Evidence.sha256(bytes)
    assert citation["document"]["extraction_version"] == Documents.version("docx")
    assert citation["document"]["locator"] == %{"kind" => "table_cell", "part" => "word/document.xml",
      "paragraph" => 2, "table" => 1, "row" => 1, "cell" => 1}
    assert citation["document"]["start_byte"] == 0
    assert citation["generation"] == 1
    {{:done, {:ok, snapshot}}, db} = DocDriver.store(Store.start("notes", state_profile, :snapshot, %{}), db)
    [original] = snapshot["sources"]
    assert Evidence.valid_span?(original, citation)
    assert Evidence.valid_spans?(original, [citation, citation])
    refute Evidence.valid_spans?(original, [citation, put_in(citation, ["document", "locator", "cell"], 2)])
    refute Evidence.valid_span?(original, Map.put(citation, "version", 1) |> Map.delete("document"))
    refute Evidence.valid_span?(original, put_in(citation, ["document", "locator", "cell"], 2))
    refute Evidence.valid_span?(original, put_in(citation, ["document", "original_sha256"], Evidence.sha256("other")))
    {:ok, chunks} = Evidence.chunks(original)
    assert Enum.map(chunks, & &1["text"]) == ["Résumé 好: keep authority explicit.", "Orion deployment is Tuesday."]
    [first, second] = chunks
    assert {:error, :invalid_span} = Evidence.citation(original, first, first["start_byte"], second["end_byte"])
    {inspected, state, db} = source_command.(state, db, "inspect", %{"source_id" => "provided:word"})
    revision = inspected["coverage"]["revision"]
    changed = make.(paragraph.("Orion deployment is Friday."))
    {updated, state, db} = source_command.(state, db, "put_document", document_args.(changed, %{"generation" => 2, "expected_revision" => revision}))
    assert updated["status"] == "ok", inspect(updated)
    {new_result, state, db} = query.(state, db, "Orion deployment")
    [new_hit] = new_result["evidence"]
    assert new_hit["citation"]["generation"] == 2
    assert new_hit["citation"]["document"]["original_sha256"] == Evidence.sha256(changed)
    {{:done, {:ok, snapshot}}, db} = DocDriver.store(Store.start("notes", state_profile, :snapshot, %{}), db)
    [current] = snapshot["sources"]
    refute Evidence.valid_span?(current, citation)
    assert Evidence.valid_span?(current, new_hit["citation"])
    {inspected, state, db} = source_command.(state, db, "inspect", %{"source_id" => "provided:word"})
    {forgotten, state, db} = source_command.(state, db, "forget", %{"source_id" => "provided:word", "expected_revision" => inspected["coverage"]["revision"]})
    assert forgotten["status"] == "ok"
    {empty, _, _} = query.(state, db, "Orion deployment")
    assert empty["evidence"] == []
    ''')
  end

  test "partial Word coverage survives storage/query and forged receipts never enter ordinary put" do
    isolated(~S'''
    bytes = make.(paragraph.("Aurora evidence") <> "<w:p><w:r><w:sym w:char=\"F0FC\"/></w:r></w:p>")
    {stored, state, db} = source_command.(state, F.new(), "put_document", document_args.(bytes, %{}))
    assert stored["status"] == "ok", inspect(stored)
    {result, state, db} = query.(state, db, "Aurora")
    assert result["status"] == "partial", inspect(result)
    refute result["coverage"]["complete"]
    [hit] = result["evidence"]
    assert hit["citation"]["document"]["status"] == "partial"
    assert Enum.any?(result["gaps"], &(&1["code"] == "partial_document" and &1["warnings"] != []))
    before = db
    forged = document_args.(bytes, %{}) |> Map.drop(~w(filename bytes_base64))
      |> Map.put("text", "forged") |> Map.put("document", hit["citation"]["origin"]["receipt"])
    {refused, _, unchanged} = source_command.(state, db, "put", forged)
    assert refused["status"] == "refused"
    assert unchanged == before
    for bad <- ["not base64", Base.encode64("not a Word package")] do
      {refused, _, unchanged} = source_command.(state, db, "put_document", document_args.(bytes, %{"bytes_base64" => bad}))
      assert refused["status"] == "refused" and unchanged == before
    end
    {:ok, extracted} = Documents.extract(bytes, "source.docx")
    {:ok, payload} = Documents.source_payload(extracted)
    assert Evidence.valid_document?(payload["document"], payload["text"])
    refute Evidence.valid_document?(put_in(payload["document"], ["segments", Access.at(0), "end_byte"], 1), payload["text"])
    refute Evidence.valid_document?(Map.put(payload["document"], "status", "complete"), payload["text"])
    assert {:error, :document_source_limit} = Documents.source_payload(Map.put(extracted, "segments", List.duplicate(hd(extracted["segments"]), 33)))
    ''')
  end

  test "selected CAS source reads retain the document receipt and final revision token" do
    isolated(~S'''
    bytes = make.(paragraph.("Lyra authority remains explicit."))
    {:ok, extracted} = Documents.extract(bytes, "source.docx")
    {:ok, payload} = Documents.source_payload(extracted)
    attrs = document_args.(bytes, %{}) |> Map.drop(~w(filename bytes_base64)) |> Map.merge(payload)
    remote = %{"kind" => "mcp_cas", "binding" => "storage", "partition" => "notes", "contract" => "ipse-cas-v3"}
    {{:done, {:ok, _}}, db} = DocDriver.store(Store.start("notes", remote, :put, attrs), F.new())
    {{:done, {:ok, snapshot}}, db} = DocDriver.store(Store.start("notes", remote, :snapshot, %{}), db)
    [source] = snapshot["sources"]
    {:ok, [chunk]} = Evidence.chunks(source)
    ref = source |> Map.take(~w(source_id source_key generation content_sha256))
      |> Map.merge(%{"chunk_id" => chunk["chunk_id"], "score" => 2.0})
    args = %{"refs" => [ref], "store_generation" => db.generation, "effects_used" => 1,
      "reads_used" => 2, "as_of_ms" => 20}
    {{:done, {:ok, selected}}, db} = DocDriver.store(Store.start("notes", remote, :snapshot_selected, args), db)
    assert selected["sources"] == [source]
    {:ok, citation} = Evidence.citation(hd(selected["sources"]), chunk, chunk["start_byte"], chunk["end_byte"])
    assert citation["document"]["original_sha256"] == Evidence.sha256(bytes)
    assert Evidence.valid_span?(source, citation)
    {{:done, {:ok, checked}}, _} = DocDriver.store(Store.start("notes", remote, :revalidate,
      %{"tokens" => selected["tokens"]}), db)
    assert checked["valid"]
    ''')
  end

  @tag :staged_document
  test "larger typed Word sources use staged CAS and refuse ordinary append substitution" do
    isolated(~S'''
    bytes = make.(paragraph.(String.duplicate("Large provenance text ", 550) <> " Atlas staged evidence."))
    {:ok, extracted} = Documents.extract(bytes, "source.docx")
    {:ok, payload} = Documents.source_payload(extracted, 65_536)
    assert byte_size(payload["text"]) > 8192
    remote = %{"kind" => "mcp_cas", "binding" => "storage", "partition" => "notes", "contract" => "ipse-cas-v3"}
    attrs = document_args.(bytes, %{}) |> Map.drop(~w(filename bytes_base64))
      |> Map.merge(%{"document" => payload["document"], "document_text" => payload["text"],
        "byte_count" => byte_size(payload["text"]), "content_sha256" => Evidence.sha256(payload["text"])})
    {{:done, {:ok, draft}}, db} = DocDriver.store(Store.start("notes", remote, :open, attrs), F.new())
    {{:done, {:ok, snapshot}}, db} = DocDriver.store(Store.start("notes", remote, :snapshot, %{}), db)
    assert snapshot["sources"] == []
    append = Map.merge(draft["continuation"], %{"source_id" => attrs["source_id"], "text" => "forged"})
    {{:done, {:error, _, _}}, unchanged} = DocDriver.store(Store.start("notes", remote, :append, append), db)
    assert unchanged.records == db.records and unchanged.generation == db.generation
    {draft, db} = Enum.reduce(Enum.chunk_every(String.to_charlist(payload["text"]), 3000), {draft, db}, fn chars, {draft, db} ->
      text = List.to_string(chars)
      append = Map.merge(draft["continuation"], %{"source_id" => attrs["source_id"], "text" => text,
        "document" => payload["document"], "document_text" => payload["text"]})
      {{:done, {:ok, next}}, db} = DocDriver.store(Store.start("notes", remote, :append, append), db)
      {next, db}
    end)
    publish = Map.merge(Map.drop(draft["continuation"], ["offset"]), %{"source_id" => attrs["source_id"],
      "document" => payload["document"], "document_text" => payload["text"]})
    {{:done, {:ok, _}}, db} = DocDriver.store(Store.start("notes", remote, :publish, publish), db)
    {{:done, {:ok, snapshot}}, _} = DocDriver.store(Store.start("notes", remote, :snapshot, %{}), db)
    [source] = snapshot["sources"]
    assert source["text"] == payload["text"]
    {:ok, chunks} = Evidence.chunks(source)
    last = List.last(chunks)
    {:ok, citation} = Evidence.citation(source, last, max(last["start_byte"], last["end_byte"] - 128), last["end_byte"])
    assert citation["quote"] =~ "Atlas staged evidence."
    assert citation["document"]["original_sha256"] == Evidence.sha256(bytes)
    assert Evidence.valid_span?(source, citation)
    ''')
  end

  @tag :locator_manifest
  test "selected CAS hydrates the complete paged locator manifest before producing an exact citation" do
    isolated(~S'''
    bytes = make.(Enum.map_join(1..24, fn n -> paragraph.("Atlas paragraph #{n} preserves exact evidence.") end))
    {:ok, extracted} = Documents.extract(bytes, "source.docx")
    {:ok, payload} = Documents.source_payload(extracted, 65_536)
    assert byte_size(IO.iodata_to_binary(JSON.encode!(payload["document"]))) > 2048
    remote = %{"kind" => "mcp_cas", "binding" => "storage", "partition" => "notes", "contract" => "ipse-cas-v3"}
    attrs = document_args.(bytes, %{}) |> Map.drop(~w(filename bytes_base64))
      |> Map.merge(%{"document" => payload["document"], "document_text" => payload["text"],
        "byte_count" => byte_size(payload["text"]), "content_sha256" => Evidence.sha256(payload["text"])})
    {{:done, {:ok, draft}}, db} = DocDriver.store(Store.start("notes", remote, :open, attrs), F.new())
    {_, db} = Enum.reduce_while(1..40, {draft, db}, fn _, {draft, db} ->
      offset = draft["continuation"]["offset"]
      text = payload["text"]
      args = Map.merge(draft["continuation"], %{"source_id" => attrs["source_id"],
        "document" => payload["document"], "document_text" => text})
      {operation, args} = if offset == byte_size(text),
        do: {:publish, Map.delete(args, "offset")},
        else: {:append, Map.put(args, "text", binary_part(text, offset, min(1024, byte_size(text) - offset)))}
      {{:done, {:ok, next}}, db} = DocDriver.store(Store.start("notes", remote, operation, args), db)
      if operation == :publish, do: {:halt, {next, db}}, else: {:cont, {next, db}}
    end)
    {{:done, {:ok, snapshot}}, db} = DocDriver.store(Store.start("notes", remote, :snapshot, %{}), db)
    [source] = snapshot["sources"]
    assert source["version"] == 2 and source["document"] == payload["document"]
    assert source["origin"]["receipt"]["version"] == 4
    {:ok, chunks} = Evidence.chunks(source)
    last = List.last(chunks)
    ref = source |> Map.take(~w(source_id source_key generation content_sha256))
      |> Map.merge(%{"chunk_id" => last["chunk_id"], "score" => 2.0})
    {{:done, {:ok, selected}}, _} = DocDriver.store(Store.start("notes", remote, :snapshot_selected,
      %{"refs" => [ref], "store_generation" => db.generation, "effects_used" => 1,
        "reads_used" => 2, "as_of_ms" => 20}), db)
    assert selected["sources"] == [source]
    {:ok, citation} = Evidence.citation(hd(selected["sources"]), last, last["start_byte"], last["end_byte"])
    assert citation["quote"] == "Atlas paragraph 24 preserves exact evidence."
    assert citation["document"]["locator"]["paragraph"] == 24
    assert Evidence.valid_span?(source, citation)
    refute Evidence.valid_source?(Map.delete(source, "document"))
    refute Evidence.valid_source?(put_in(source, ["document", "segments"], Enum.reverse(source["document"]["segments"])))
    envelope = %{"version" => 1, "complete" => true, "kind" => "source", "source" => Map.delete(source, "text"),
      "text" => source["text"], "byte_count" => byte_size(source["text"]), "cursor" => 0, "next" => nil}
    {{:done, {:error, :incomplete_import, _}}, unchanged} = DocDriver.store(Store.start("notes", remote, :import,
      %{"expected_revision" => 0, "export" => envelope}), db)
    assert unchanged.records == db.records and unchanged.generation == db.generation
    ''')
  end
end
