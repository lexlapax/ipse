defmodule Ipse.KnowledgeDocumentAcquisitionSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, JSON}
  alias Ipse.Extension.{Artifact, Config, Registry, State}
  import Ipse.Test.ResumeAssertions

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("document acquisition attempted inference")
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-document-acquisition-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    artifacts =
      for preset <- ~w(state-documents state-lexical collection-documents), into: %{} do
        if preset == "collection-documents" and System.get_env("IPSE_TEST_WORD_SHIPPED") == "1" do
          {:ok, bundles} = Ipse.Extension.Bundles.inventory()
          %{path: path} = Enum.find(bundles, &(&1.id == "corpus-collection-documents"))
          {preset, path}
        else
          path = Path.join(root, preset)

          assert {output, 0} =
                   System.cmd(
                     System.find_executable("elixir"),
                     [
                       "extensions/knowledge/build.exs",
                       "--sdk",
                       Application.app_dir(:ipse, "ebin"),
                       "--output",
                       path,
                       "--package",
                       "corpus",
                       "--preset",
                       preset
                     ],
                     stderr_to_stdout: true
                   )

          refute output =~ "warning:"
          {preset, path}
        end
      end

    if System.get_env("IPSE_TEST_WORD_KEEP") != "1", do: on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, artifacts: artifacts}
  end

  defp open(c, preset \\ "state-documents") do
    {cwd, home} =
      if preset == "collection-documents" do
        native = System.get_env("IPSE_DOCUMENT_NATIVE_TMPDIR") || System.tmp_dir!()
        base = Path.join(native, "ipse-public-collection-" <> Ipse.Usage.id())
        File.mkdir!(base)
        if System.get_env("IPSE_TEST_WORD_KEEP") != "1", do: on_exit(fn -> File.rm_rf!(base) end)
        {Path.join(base, "workspace"), Path.join(base, "home")}
      else
        cwd = Path.join(c.root, Ipse.Usage.id())
        {cwd, Path.join(cwd, "home")}
      end

    File.mkdir_p!(cwd)
    File.mkdir_p!(home)
    File.chmod!(home, 0o700)

    {:ok, artifact} =
      Artifact.import(c.artifacts[preset], Path.join(home, "extensions/artifacts"))

    options_file =
      if preset == "collection-documents",
        do: "corpus-collection.json",
        else: "corpus-lexical.json"

    options = Jason.decode!(File.read!("extensions/knowledge/options/" <> options_file))

    source = %{
      scope: "operator",
      path: Path.join(home, "fixture.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "corpus",
            "artifact" => artifact.digest,
            "enabled" => true,
            "options" => options,
            "order" => 0,
            "lifetime" => "session"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => artifact.digest,
            "capabilities" => artifact.manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false,
            "state_bindings" => [
              %{
                "version" => 1,
                "instance" => "corpus",
                "id" => "knowledge",
                "scopes" => ["project"]
              }
            ]
          }
        ]
      }
    }

    source =
      if preset == "collection-documents" do
        update_in(source.data["extension_trust"], fn [trust] ->
          [
            trust
            |> Map.delete("state_bindings")
            |> Map.put("collection_bindings", [
              %{
                "version" => 1,
                "instance" => "corpus",
                "id" => "documents",
                "scope" => "project",
                "profile" => "document_graph_v1"
              }
            ])
          ]
        end)
      else
        source
      end

    {:ok, selected} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selected, home)

    if preset == "collection-documents",
      do: assert({:ok, _} = Ipse.Extension.ProjectIdentity.admit(home, cwd, :folder))

    config = %{
      provider: :demo,
      model: "synthetic",
      provider_module: NoModel,
      home: home,
      extensions: entries,
      approval: :ask,
      approval_origin: :interactive,
      headless: false,
      compact: false
    }

    opts = [config: config, cwd: cwd, state_dir: Path.join(home, "sessions"), subscriber: self()]
    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    %{pid: pid, cwd: cwd, dir: opts[:state_dir], opts: opts, artifact: artifact}
  end

  defp document(text, options \\ []) do
    document_body("<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>", options)
  end

  defp document_body(body, options) do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"source.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ],
        [:memory] ++ options
      )

    bytes
  end

  defp many_locations do
    paragraph = fn text -> "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" end

    paragraphs =
      Enum.map_join(
        1..20,
        &paragraph.(
          "Paragraph #{&1} carries ordinary document context and exact Unicode résumé evidence."
        )
      )

    table =
      "<w:tbl>" <>
        Enum.map_join(1..2, fn row ->
          "<w:tr>" <>
            Enum.map_join(1..2, fn cell ->
              "<w:tc>" <>
                paragraph.(
                  if row == 2 and cell == 2,
                    do: "Nebula table evidence stays exactly located.",
                    else: "Table row #{row} cell #{cell} context."
                ) <> "</w:tc>"
            end) <> "</w:tr>"
        end) <> "</w:tbl>"

    document_body(paragraphs <> table <> "<w:p><w:r><w:sym w:char=\"F0FC\"/></w:r></w:p>", [
      {:compress, []}
    ])
  end

  defp larger_document do
    text =
      Enum.map_join(1..700, " ", &"entry#{&1} résumé") <> " Vega staging preserves every byte."

    {document(text, [{:compress, []}]), text}
  end

  defp numbered_document do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"
    prefix = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"#{prefix}officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    links =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"numbers\" Type=\"#{prefix}numbering\" Target=\"numbering.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/></Types>"

    numbering =
      "<w:numbering xmlns:w=\"#{word}\"><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"3\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/></w:lvl></w:abstractNum><w:num w:numId=\"7\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>"

    body =
      Enum.map_join(1..40, fn n ->
        text = "Numbered source #{n}" <> if(n == 40, do: " amberneedle", else: "")

        "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"7\"/></w:numPr></w:pPr><w:r><w:t>#{text}</w:t></w:r></w:p>"
      end)

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"numbered.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/_rels/document.xml.rels", links},
          {~c"word/numbering.xml", numbering},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ],
        [:memory, {:compress, []}]
      )

    bytes
  end

  defp continue(run, %{"id" => id, "arguments" => arguments}), do: invoke(run, id, arguments)

  defp query(run, words) do
    invoke(run, "query", %{
      "store" => "notes",
      "retrieval" => "words",
      "rerank" => nil,
      "query" => words,
      "top_k" => 1,
      "as_of_ms" => 20
    })
  end

  defp assert_retained_workspace_source(run, path, original, words) do
    replacement = File.read!(path)
    result = query(run, words)
    assert result["status"] == "refused"
    assert result["evidence"] == [] and result["claims"] == []
    assert result["gaps"] == [%{"code" => "document_source_changed_or_unavailable"}]

    try do
      File.write!(path, original)
      assert query(run, words)["evidence"] != []
    after
      File.write!(path, replacement)
    end
  end

  defp finish_staging(run, opened) do
    Enum.reduce_while(1..40, opened, fn _, current ->
      next = continue(run, current["continuation"])

      case next["status"] do
        "draft" -> {:cont, next}
        "ok" -> {:halt, next}
        _ -> flunk("metadata staging refused: #{inspect({next, acquisition_trace(run)})}")
      end
    end)
  end

  defp stored_state(run) do
    [path] = Path.wildcard(Path.join(run.opts[:config][:home], "extension-state-v1/*/state.json"))

    {Path.dirname(Path.dirname(path)), Path.basename(Path.dirname(path)),
     Jason.decode!(File.read!(path))}
  end

  defp change_record(run, key, value) do
    {root, namespace, state} = stored_state(run)
    row = state["records"][key]

    request = %{
      "op" => if(value, do: "state.put", else: "state.delete"),
      "scope" => "project",
      "key" => key,
      "expected_revision" => if(row, do: row["revision"], else: 0)
    }

    request = if value, do: Map.put(request, "value", value), else: request
    assert {:ok, _} = State.execute(root, namespace, request, Ipse.Usage.id())
  end

  defp restore_fixture_state(run, state) do
    {root, namespace, _} = stored_state(run)

    File.write!(Path.join([root, namespace, "state.json"]), Jason.encode!(state), [:binary, :sync])
  end

  defp ordered(map) when is_map(map),
    do: ["map", Enum.map(Enum.sort(map), fn {key, value} -> [key, ordered(value)] end)]

  defp ordered(list) when is_list(list), do: ["list", Enum.map(list, &ordered/1)]
  defp ordered(value), do: value

  defp changed_page(value, body) do
    sha = JSON.digest(["ipse-knowledge", 1, "page-body", [value["page_kind"], ordered(body)]])
    value = Map.merge(value, %{"body" => body, "body_sha256" => sha})

    key =
      JSON.digest([
        "ipse-knowledge",
        1,
        "page",
        Enum.map(
          ~w(partition source_key generation draft_id page_kind ordinal body_sha256),
          &value[&1]
        )
      ])

    {key, value,
     %{
       "key" => key,
       "sha256" => JSON.digest(["ipse-knowledge", 1, "page-record", [ordered(value)]])
     }}
  end

  defp args do
    %{
      "store" => "notes",
      "action" => "read_document",
      "args" => %{
        "source_id" => "workspace:source",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Workspace Word source",
        "path" => "source.docx",
        "expected_sha256" => nil,
        "uri" => "workspace:source.docx",
        "observed_at_ms" => 10,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }
    }
  end

  defp invoke(c, id, arguments) do
    assert :ok = Session.invoke_export(c.pid, :command, "ext__corpus__" <> id, arguments)
    wait(c, System.monotonic_time(:millisecond) + 20_000)
  end

  defp wait(c, deadline) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:state.put", proposed}} when pid == c.pid ->
        assert proposed["artifact_sha256"] == c.artifact.digest
        assert proposed["request"]["scope"] == "project"
        assert :ok = State.validate(proposed["request"])
        assert :ok = Session.approve(pid, ref, true)
        wait(c, deadline)

      {:ipse, pid, {:approval, ref, "extension:collection.store", proposed}} when pid == c.pid ->
        assert proposed["artifact_sha256"] == c.artifact.digest
        assert :ok = Ipse.Extension.CollectionStore.validate(proposed["request"])
        assert :ok = Session.approve(pid, ref, true)
        wait(c, deadline)

      {:ipse, pid, {:done, :ok}} when pid == c.pid ->
        assert %{"value" => value} = Session.info(pid).extension_result
        value

      {:ipse, pid, {:done, status}} when pid == c.pid ->
        flunk("document command failed: #{inspect(status)}")

      {:ipse, pid, {:error, reason}} when pid == c.pid ->
        if c[:expected_host_refusal] do
          assert_receive {:ipse, ^pid, {:done, :error}}, 5000
          {:host_refused, reason}
        else
          {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

          actions =
            for event <- events,
                event["type"] in ~w(extension_action_intent extension_action_result),
                do:
                  {event["type"], get_in(event, ["request", "op"]),
                   get_in(event, ["request", "name"]), event["approval"],
                   get_in(event, ["outcome", "status"]),
                   get_in(event, ["outcome", "value", "reason"])}

          flunk(
            "document command error: #{inspect(reason)} #{inspect(Enum.take(actions, -6), limit: :infinity)}"
          )
        end

      {:ipse, pid, _} when pid == c.pid ->
        wait(c, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("document command timed out")
    end
  end

  defp await_staged_collection(run, result) do
    Enum.reduce_while(1..40, result, fn _, current ->
      assert current["status"] == "draft", inspect(current)

      if match?(
           [_ | _],
           get_in(current, ["continuation", "arguments", "args", "collection_state", "stages"])
         ) do
        {:halt, current}
      else
        {:cont, continue(run, current["continuation"])}
      end
    end)
    |> then(fn current ->
      assert match?(
               [_ | _],
               get_in(current, ["continuation", "arguments", "args", "collection_state", "stages"])
             ),
             inspect(current)

      current
    end)
  end

  @tag :workspace_current_query
  test "opt-in workspace acquisition journals exact reads before writes and returns a bound citation",
       c do
    run = open(c)
    bytes = document("Vega migration requires an audit.")
    File.write!(Path.join(run.cwd, "source.docx"), bytes)
    assert invoke(run, "source", args())["status"] == "ok"

    result =
      invoke(run, "query", %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "Vega migration",
        "top_k" => 1,
        "as_of_ms" => 20
      })

    assert result["status"] == "ok", inspect(result)
    [hit] = result["evidence"]
    citation = hit["citation"]
    assert citation["quote"] == "Vega migration requires an audit."
    assert citation["document"]["original_sha256"] == JSON.sha256(bytes)
    assert citation["origin"]["receipt"]["version"] == 3
    metadata = Jason.decode!(citation["origin"]["receipt"]["document"])
    assert metadata["version"] == 2
    acquisition = metadata["acquisition"]
    assert acquisition["path"] == "source.docx"
    id = Session.info(run.pid).id
    assert {:ok, events} = Journal.load(run.dir, id)

    reads =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "name"]) == "read")
      )

    assert length(reads) == 3
    [first, second, current] = reads
    assert first["approval"] == "not_required"
    assert second["request"]["arguments"]["expected_sha256"] == JSON.sha256(bytes)
    assert second["operation_id"] == acquisition["operation_id"]
    assert current["request"]["arguments"]["expected_sha256"] == JSON.sha256(bytes)
    assert current["request"]["arguments"]["max_bytes"] == 1
    assert [%{"operation_id" => current_id}] = result["coverage"]["workspace_file_checks"]
    assert current_id == current["operation_id"]
    assert result["coverage"]["workspace_invocation_effects"] == 1

    query_reads =
      Enum.count(events, fn event ->
        event["type"] == "extension_action_result" and
          event["parent_invocation_id"] == current["parent_invocation_id"] and
          get_in(event, ["request", "op"]) in ~w(state.get state.list state.scan)
      end)

    assert query_reads > 0
    assert result["coverage"]["workspace_invocation_reads"] == query_reads

    read_positions =
      Enum.with_index(events)
      |> Enum.filter(fn {event, _} -> event in [first, second] end)
      |> Enum.map(&elem(&1, 1))

    write_position =
      Enum.find_index(
        events,
        &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "state.put")
      )

    assert Enum.max(read_positions) < write_position
    assert Enum.find_index(events, &(&1 === current)) > write_position
    refute Enum.any?(events, &(&1["type"] == "request_admitted"))
    assert {:ok, _} = Session.Saved.restore(events, id)
    assert :ok = Session.close_confirmed(run.pid)
    assert {:ok, _before} = Journal.load(run.dir, id)
    journal = Path.join(run.dir, id <> ".jsonl")
    before_bytes = File.read!(journal)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(run.opts, :id, id)}
             )

    assert_idle_resume_journal(journal, before_bytes, id)
    assert :ok = Session.close_confirmed(resumed)
  end

  for preset <- ~w(state-documents collection-documents) do
    @tag :workspace_current_query
    @tag current_query_preset: preset
    test "#{preset} withholds changed, renamed, deleted and redirected workspace documents", c do
      run = open(c, c.current_query_preset)
      original = document("Vega migration requires an audit.")
      path = Path.join(run.cwd, "source.docx")
      moved = Path.join(run.cwd, "moved.docx")
      File.write!(path, original)
      saved = invoke(run, "source", args())

      saved =
        Enum.reduce_while(1..40, saved, fn _, result ->
          if result["status"] == "draft",
            do: {:cont, continue(run, result["continuation"])},
            else: {:halt, result}
        end)

      assert saved["status"] == "ok"

      query_current = fn selected ->
        if c.current_query_preset == "collection-documents" do
          invoke(selected, "query_selected", %{
            "store" => "notes",
            "retrieval" => "words",
            "query" => "Vega migration",
            "top_k" => 1,
            "as_of_ms" => 20,
            "source_ids" => ["workspace:source"]
          })
        else
          query(selected, "Vega migration")
        end
      end

      assert query_current.(run)["status"] == "ok"

      for change <- [:replace, :rename, :delete, :redirect] do
        case change do
          :replace ->
            File.write!(path, document("Vega migration no longer uses this source."))

          :rename ->
            File.rename!(path, moved)

          :delete ->
            File.rm!(path)

          :redirect ->
            File.rename!(path, moved)
            File.ln_s!("moved.docx", path)
        end

        if change == :redirect do
          assert {:host_refused, message} =
                   query_current.(Map.put(run, :expected_host_refusal, true))

          assert message =~ "unknown after refusal"
          assert {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)
          parent = Enum.find(Enum.reverse(events), &(&1["type"] == "extension_invocation_intent"))

          calls =
            Enum.filter(
              events,
              &(&1["type"] == "extension_action_intent" and
                  &1["invocation_id"] == parent["invocation_id"])
            )

          refute Enum.any?(calls, &(get_in(&1, ["request", "name"]) == "read"))

          refute Enum.any?(
                   events,
                   &(&1["type"] == "extension_invocation_result" and
                       &1["invocation_id"] == parent["invocation_id"])
                 )
        else
          result = query_current.(run)
          assert result["status"] == "refused", inspect({change, result})
          assert result["evidence"] == [] and result["claims"] == []
          assert result["gaps"] == [%{"code" => "document_source_changed_or_unavailable"}]
        end

        case change do
          :rename ->
            File.rename!(moved, path)

          :redirect ->
            File.rm!(path)
            File.rename!(moved, path)

          _ ->
            File.write!(path, original)
        end
      end

      restored = query_current.(run)
      assert restored["status"] == "ok"

      assert hd(restored["evidence"])["citation"]["document"]["original_sha256"] ==
               JSON.sha256(original)

      id = Session.info(run.pid).id
      assert :ok = Session.close_confirmed(run.pid)
      assert {:ok, events} = Journal.load(run.dir, id)
      assert {:ok, _} = Session.Saved.restore(events, id)
      refute Enum.any?(events, &(&1["type"] == "request_admitted"))

      File.rm!(path)

      assert {:ok, resumed} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session, Keyword.put(run.opts, :id, id)}
               )

      assert query_current.(%{run | pid: resumed})["status"] == "refused"
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  @tag :workspace_current_query
  test "a source revision changed during the workspace check withholds the query", c do
    run = open(c)
    File.write!(Path.join(run.cwd, "source.docx"), document("Vega migration requires an audit."))
    assert invoke(run, "source", args())["status"] == "ok"
    {_, _, state} = stored_state(run)
    root = Enum.find(Map.values(state["records"]), &(get_in(&1, ["value", "kind"]) == "root"))

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_begin, _, %{"name" => "read", "arguments" => %{"max_bytes" => 1}}}}},
      _ ->
        change_record(run, root["key"], root["value"])
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(run.pid, {callback, 0})
    result = query(run, "Vega migration")
    assert result["status"] == "conflict"
    assert result["evidence"] == [] and result["claims"] == []
    assert result["gaps"] == [%{"code" => "snapshot_changed"}]
    assert query(run, "Vega migration")["status"] == "ok"
    assert {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)
    assert {:ok, _} = Session.Saved.restore(events, Session.info(run.pid).id)
    refute Enum.any?(events, &(&1["type"] == "request_admitted"))
  end

  @tag :public_many_block_document
  @tag skip:
         if(is_nil(System.get_env("IPSE_PUBLIC_WORD_FIXTURE")),
           do: "requires frozen public Word fixture",
           else: false
         )
  test "the original public many-cell Word file acquires and returns source-exact citations", c do
    bytes = File.read!(System.fetch_env!("IPSE_PUBLIC_WORD_FIXTURE"))

    assert JSON.sha256(bytes) ==
             "e9efad0ad358200a8e1e0fe4c072d2496177c3698e7e4a3da406141ddfb40c2d"

    run = open(c)
    source_path = Path.join(run.cwd, "source.docx")
    File.write!(source_path, bytes)

    expression = """
    {:ok, d} = IpseKnowledge.Documents.extract(File.read!(#{inspect(source_path)}), "source.docx")
    {:ok, p} = IpseKnowledge.Documents.source_payload(d, 65536)
    largest = Enum.max_by(d["segments"], &byte_size(&1["text"]))
    {query, _} = IpseKnowledge.Evidence.utf8_prefix(largest["text"], 256)
    IO.puts(JSON.encode!(%{"query" => query, "text" => p["text"], "blocks" => length(d["segments"])}))
    """

    {output, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["-pa", Path.join(c.artifacts["state-documents"], "ebin"), "-e", expression],
        stderr_to_stdout: true
      )

    expected = Jason.decode!(output)
    assert expected["blocks"] == 329
    opened = invoke(run, "source", args())
    assert opened["status"] == "draft"
    assert finish_staging(run, opened)["status"] == "ok"
    result = query(run, expected["query"])
    assert result["status"] == "partial"
    [hit] = result["evidence"]
    citation = hit["citation"]
    assert citation["document"]["original_sha256"] == JSON.sha256(bytes)
    assert citation["document"]["extraction_version"] == "ipse-documents-v16"

    assert citation["quote"] ==
             binary_part(
               expected["text"],
               citation["start_byte"],
               citation["end_byte"] - citation["start_byte"]
             )

    assert Enum.any?(result["gaps"], &(&1["code"] == "partial_document"))
    id = Session.info(run.pid).id
    assert {:ok, events} = Journal.load(run.dir, id)
    refute Enum.any?(events, &(&1["type"] == "request_admitted"))
    assert {:ok, _} = Session.Saved.restore(events, id)
    assert :ok = Session.close_confirmed(run.pid)
  end

  for preset <- ~w(state-documents collection-documents) do
    @tag :many_paragraph_document
    @tag packing_preset: preset
    test "many short blocks acquire through bounded stages and retain original citation positions (#{preset})",
         c do
      run = open(c, c.packing_preset)

      texts =
        for i <- 1..329, do: "Line #{i} café 好" <> if(i == 329, do: " orbitalneedle", else: "")

      paragraph = fn text -> "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" end
      body = Enum.take(texts, 17) |> Enum.map_join(paragraph)

      body =
        body <>
          "<w:tbl>" <>
          (texts
           |> Enum.drop(17)
           |> Enum.map_join(fn text -> "<w:tr><w:tc>" <> paragraph.(text) <> "</w:tc></w:tr>" end)) <>
          "</w:tbl>"

      bytes = document_body(body, [{:compress, []}])
      File.write!(Path.join(run.cwd, "source.docx"), bytes)
      opened = invoke(run, "source", args())
      assert opened["status"] == "draft", inspect(opened)
      id = Session.info(run.pid).id
      {:ok, before_change} = Journal.load(run.dir, id)
      File.write!(Path.join(run.cwd, "source.docx"), document("changed during grouped staging"))
      assert continue(run, opened["continuation"])["status"] == "refused"
      {:ok, after_change} = Journal.load(run.dir, id)

      refute Enum.any?(Enum.drop(after_change, length(before_change)), fn event ->
               event["type"] == "extension_action_intent" and
                 get_in(event, ["request", "op"]) in ~w(state.put state.delete collection.store)
             end)

      File.write!(Path.join(run.cwd, "source.docx"), bytes)
      final = finish_staging(run, opened)
      assert final["status"] == "ok", inspect(final)

      query_blocks = fn selected ->
        if c.packing_preset == "collection-documents" do
          invoke(selected, "query_selected", %{
            "store" => "notes",
            "retrieval" => "words",
            "query" => "orbitalneedle",
            "top_k" => 1,
            "as_of_ms" => 20,
            "source_ids" => ["workspace:source"]
          })
        else
          query(selected, "orbitalneedle")
        end
      end

      result = query_blocks.(run)
      assert result["status"] == "ok", inspect(result)
      [hit] = result["evidence"]
      citation = hit["citation"]
      assert citation["quote"] =~ "orbitalneedle"
      assert citation["document"]["original_sha256"] == JSON.sha256(bytes)
      assert citation["document"]["extraction_version"] == "ipse-documents-v16"

      if citation["document"]["version"] == 2 do
        assert Enum.any?(citation["document"]["spans"], fn
                 [329, _, _, _, _, 1, 312, 1, nil] -> true
                 _ -> false
               end)
      else
        assert citation["document"]["locator"]["paragraph"] == 329
        assert citation["document"]["locator"]["table"] == 1
        assert citation["document"]["locator"]["row"] == 312
        assert citation["document"]["locator"]["cell"] == 1
      end

      assert {:ok, events} = Journal.load(run.dir, id)
      refute Enum.any?(events, &(&1["type"] == "request_admitted"))
      assert {:ok, _} = Session.Saved.restore(events, id)
      assert :ok = Session.close_confirmed(run.pid)

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(run.opts, :id, id)})

      assert query_blocks.(%{run | pid: resumed})["evidence"] == result["evidence"]
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  for preset <- ~w(state-documents collection-documents) do
    @tag :docx_numbering_session
    @tag numbering_preset: preset
    test "numbered Word source retains its source-bound locator after resume (#{preset})", c do
      run = open(c, c.numbering_preset)
      bytes = numbered_document()
      path = Path.join(run.cwd, "source.docx")
      File.write!(path, bytes)
      opened = invoke(run, "source", args())
      stored = if opened["status"] == "draft", do: finish_staging(run, opened), else: opened
      assert stored["status"] == "ok", inspect(stored)

      find = fn selected ->
        if c.numbering_preset == "collection-documents" do
          invoke(selected, "query_selected", %{
            "store" => "notes",
            "retrieval" => "words",
            "query" => "amberneedle",
            "top_k" => 1,
            "as_of_ms" => 20,
            "source_ids" => ["workspace:source"]
          })
        else
          query(selected, "amberneedle")
        end
      end

      result = find.(run)
      assert result["status"] == "partial", inspect(result)
      assert Enum.any?(result["gaps"], &(&1["code"] == "partial_document"))
      [hit] = result["evidence"]
      citation = hit["citation"]
      assert citation["quote"] =~ "amberneedle"
      refute citation["quote"] =~ "42."
      doc = citation["document"]
      assert doc["original_sha256"] == JSON.sha256(bytes)
      assert doc["extraction_version"] == "ipse-documents-v16"

      if doc["version"] == 2 do
        assert Enum.any?(doc["spans"], fn
                 [40, _, _, _, _, nil, nil, nil, %{"ordinal" => 42, "label" => "42."}] -> true
                 _ -> false
               end)
      else
        assert doc["locator"]["paragraph"] == 40
        assert doc["locator"]["numbering"]["ordinal"] == 42
        assert doc["locator"]["numbering"]["label"] == "42."
      end

      File.write!(path, document("replacement"))
      changed = find.(run)
      assert changed["status"] == "refused"
      assert changed["evidence"] == []
      assert Enum.any?(changed["gaps"], &(&1["code"] == "document_source_changed_or_unavailable"))
      File.write!(path, bytes)
      id = Session.info(run.pid).id
      assert {:ok, events} = Journal.load(run.dir, id)
      refute Enum.any?(events, &(&1["type"] == "request_admitted"))
      assert {:ok, _} = Session.Saved.restore(events, id)
      assert :ok = Session.close_confirmed(run.pid)

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(run.opts, :id, id)})

      assert find.(%{run | pid: resumed})["evidence"] == result["evidence"]
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  for preset <- ~w(state-documents collection-documents) do
    @tag :docx_annotation_session
    @tag annotation_preset: preset
    test "linked Word annotations retain complete coverage and cited locations (#{preset})", c do
      run = open(c, c.annotation_preset)
      word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      relations = "http://schemas.openxmlformats.org/package/2006/relationships"
      prefix = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

      annotations = [
        {"footnotes", "footnote", "7", "footnoteneedle α"},
        {"endnotes", "endnote", "8", "endnoteneedle β"},
        {"comments", "comment", "9", "commentneedle γ"}
      ]

      body =
        "<w:p><w:r><w:t>café </w:t></w:r><w:commentRangeStart w:id=\"9\"/>" <>
          "<w:r><w:t>chosen</w:t></w:r><w:commentRangeEnd w:id=\"9\"/>" <>
          "<w:r><w:footnoteReference w:id=\"7\"/><w:endnoteReference w:id=\"8\"/>" <>
          "<w:commentReference w:id=\"9\"/></w:r></w:p>"

      {:ok, entries} = :zip.extract(document_body(body, []), [:memory])

      entries =
        Enum.map(entries, fn
          {~c"[Content_Types].xml", types} ->
            additions =
              Enum.map_join(annotations, fn {part, _, _, _} ->
                "<Override PartName=\"/word/#{part}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.#{part}+xml\"/>"
              end)

            {~c"[Content_Types].xml", String.replace(types, "</Types>", additions <> "</Types>")}

          entry ->
            entry
        end)

      links =
        Enum.map_join(annotations, fn {part, _, _, _} ->
          "<Relationship Id=\"#{part}\" Type=\"#{prefix}#{part}\" Target=\"#{part}.xml\"/>"
        end)

      parts =
        Enum.map(annotations, fn {part, item, id, text} ->
          {String.to_charlist("word/#{part}.xml"),
           "<w:#{part} xmlns:w=\"#{word}\"><w:#{item} w:id=\"#{id}\"><w:p><w:r><w:t>#{text}</w:t></w:r></w:p></w:#{item}></w:#{part}>"}
        end)

      {:ok, {_, bytes}} =
        :zip.create(
          ~c"annotations.docx",
          entries ++
            [
              {~c"word/_rels/document.xml.rels",
               "<Relationships xmlns=\"#{relations}\">#{links}</Relationships>"}
            ] ++ parts,
          [:memory]
        )

      File.write!(Path.join(run.cwd, "source.docx"), bytes)
      opened = invoke(run, "source", args())
      stored = if opened["status"] == "draft", do: finish_staging(run, opened), else: opened
      assert stored["status"] == "ok", inspect(stored)

      query_annotation = fn selected, text ->
        if c.annotation_preset == "collection-documents" do
          invoke(selected, "query_selected", %{
            "store" => "notes",
            "retrieval" => "words",
            "query" => text,
            "top_k" => 1,
            "as_of_ms" => 20,
            "source_ids" => ["workspace:source"]
          })
        else
          query(selected, text)
        end
      end

      evidence =
        for {part, _, annotation_id, text} <- annotations do
          result = query_annotation.(run, text)
          assert result["status"] == "ok", inspect(result)
          [hit] = result["evidence"]
          citation = hit["citation"]
          assert citation["quote"] == text
          assert citation["document"]["status"] == "complete"
          assert citation["document"]["extraction_version"] == "ipse-documents-v16"
          assert citation["document"]["original_sha256"] == JSON.sha256(bytes)
          locator = citation["document"]["locator"]
          assert locator["part"] == "word/#{part}.xml"
          assert locator["annotation_id"] == annotation_id

          assert locator["reference_site"] == %{
                   "kind" => "paragraph",
                   "part" => "word/document.xml",
                   "paragraph" => 1,
                   "byte_offset" => 12
                 }

          if part == "comments" do
            assert locator["reference_range"] == %{
                     "kind" => "paragraph",
                     "part" => "word/document.xml",
                     "paragraph" => 1,
                     "start_byte" => 6,
                     "end_byte" => 12
                   }
          else
            refute Map.has_key?(locator, "reference_range")
          end

          result["evidence"]
        end

      id = Session.info(run.pid).id
      assert {:ok, events} = Journal.load(run.dir, id)
      refute Enum.any?(events, &(&1["type"] == "request_admitted"))
      assert {:ok, _} = Session.Saved.restore(events, id)
      assert :ok = Session.close_confirmed(run.pid)

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(run.opts, :id, id)})

      for {{_, _, _, text}, expected} <- Enum.zip(annotations, evidence) do
        assert query_annotation.(%{run | pid: resumed}, text)["evidence"] == expected
      end

      assert :ok = Session.close_confirmed(resumed)
    end
  end

  for effects? <- [false, true] do
    @tag :docx_table_style_session
    @tag docx_effects: effects?
    test "workspace acquisition preserves a named table style through its versioned citation (effects #{effects?})",
         c do
      effects? = c.docx_effects
      run = open(c)
      word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      relations = "http://schemas.openxmlformats.org/package/2006/relationships"
      prefix = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
      text = "Vega café migration requires an audit."

      styles =
        "<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"table\" w:styleId=\"grid\"/></w:styles>"

      effects_type =
        if effects?,
          do:
            "<Override PartName=\"/word/stylesWithEffects.xml\" ContentType=\"application/vnd.ms-word.stylesWithEffects+xml\"/>",
          else: ""

      effects_link =
        if effects?,
          do:
            "<Relationship Id=\"effects\" Type=\"http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects\" Target=\"stylesWithEffects.xml\"/>",
          else: ""

      effects_part = if effects?, do: [{~c"word/stylesWithEffects.xml", styles}], else: []

      body =
        "<w:tbl><w:tblPr><w:tblStyle w:val=\"grid\"/></w:tblPr><w:tr><w:tc><w:p><w:r><w:t>" <>
          text <> "</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"

      {:ok, entries} = :zip.extract(document_body(body, []), [:memory])

      entries =
        Enum.map(entries, fn
          {~c"[Content_Types].xml", types} ->
            {~c"[Content_Types].xml",
             String.replace(
               types,
               "</Types>",
               "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>" <>
                 effects_type <> "</Types>"
             )}

          entry ->
            entry
        end)

      {:ok, {_, bytes}} =
        :zip.create(
          ~c"styled.docx",
          entries ++
            [
              {~c"word/_rels/document.xml.rels",
               "<Relationships xmlns=\"#{relations}\"><Relationship Id=\"style\" Type=\"#{prefix}styles\" Target=\"styles.xml\"/>" <>
                 effects_link <> "</Relationships>"},
              {~c"word/styles.xml", styles}
            ] ++ effects_part,
          [:memory]
        )

      File.write!(Path.join(run.cwd, "source.docx"), bytes)
      assert invoke(run, "source", args())["status"] == "ok"
      result = query(run, "Vega café")
      assert result["status"] == "ok", inspect(result)
      [hit] = result["evidence"]
      citation = hit["citation"]
      assert citation["quote"] == text
      assert citation["document"]["original_sha256"] == JSON.sha256(bytes)
      assert citation["document"]["extraction_version"] == "ipse-documents-v16"

      assert citation["document"]["locator"] == %{
               "kind" => "table_cell",
               "part" => "word/document.xml",
               "paragraph" => 1,
               "table" => 1,
               "row" => 1,
               "cell" => 1
             }

      id = Session.info(run.pid).id
      assert {:ok, events} = Journal.load(run.dir, id)
      refute Enum.any?(events, &(&1["type"] == "request_admitted"))
      assert {:ok, _} = Session.Saved.restore(events, id)
      assert :ok = Session.close_confirmed(run.pid)
    end
  end

  test "legacy lexical preset never acquires files or silently receives tools capability", c do
    run = open(c, "state-lexical")
    refute "host.tools" in run.artifact.manifest["capabilities"]
    File.write!(Path.join(run.cwd, "source.docx"), document("not acquired"))
    assert invoke(run, "source", args())["status"] == "refused"
    assert {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)
    refute Enum.any?(events, &(&1["type"] == "extension_action_intent"))
  end

  test "paged Word acquisition stages complete larger text and selects it only at final publication",
       c do
    run = open(c)
    path = Path.join(run.cwd, "source.docx")
    legacy = document("Legacy selection remains current.")
    File.write!(path, legacy)
    assert invoke(run, "source", args())["status"] == "ok"

    inspected =
      invoke(run, "source", %{
        "store" => "notes",
        "action" => "inspect",
        "args" => %{"source_id" => "workspace:source"}
      })

    {bytes, text} = larger_document()
    assert byte_size(bytes) > 4096 and byte_size(text) > 8192
    File.write!(path, bytes)

    command =
      args()
      |> put_in(["args", "generation"], 2)
      |> put_in(["args", "expected_revision"], inspected["coverage"]["revision"])
      |> put_in(["args", "expected_sha256"], JSON.sha256(bytes))

    opened = invoke(run, "source", command)
    assert opened["status"] == "draft", inspect({opened, acquisition_trace(run)})
    first = opened["continuation"]
    assert_retained_workspace_source(run, path, legacy, "Legacy")
    File.write!(path, document("changed between stages"))
    assert continue(run, first)["status"] == "refused"
    assert_retained_workspace_source(run, path, legacy, "Legacy")
    File.write!(path, bytes)

    finished =
      Enum.reduce_while(1..20, opened, fn _, result ->
        next = continue(run, result["continuation"])

        case next["status"] do
          "draft" ->
            assert_retained_workspace_source(run, path, legacy, "Legacy")
            {:cont, next}

          "ok" ->
            {:halt, next}

          _ ->
            flunk("staged Word continuation refused: #{inspect(next)}")
        end
      end)

    assert finished["status"] == "ok"
    result = query(run, "Vega staging")
    assert result["status"] == "ok", inspect(result)
    [hit] = result["evidence"]
    citation = hit["citation"]
    assert citation["quote"] =~ "Vega staging preserves every byte."
    assert citation["generation"] == 2
    assert citation["document"]["original_sha256"] == JSON.sha256(bytes)
    assert citation["document"]["locator"]["paragraph"] == 1

    assert binary_part(
             text,
             citation["start_byte"],
             citation["end_byte"] - citation["start_byte"]
           ) == citation["quote"]

    assert query(run, "Legacy")["evidence"] == []
    assert continue(run, first)["status"] == "refused"
    {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)

    reads =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "name"]) == "read")
      )

    assert Enum.any?(reads, &(get_in(&1, ["request", "arguments", "byte_offset"]) == 4096))

    for event <- reads do
      value = event["outcome"]["value"]

      if event["outcome"]["status"] == "ok" do
        assert byte_size(value["text"]) <= 8192
        assert :ok = Ipse.Extension.validate(value)
      end
    end

    assert {:ok, _} = Session.Saved.restore(events, Session.info(run.pid).id)
  end

  test "changing a larger Word file between pages refuses before draft writes", c do
    run = open(c)
    {bytes, _} = larger_document()
    path = Path.join(run.cwd, "source.docx")
    File.write!(path, bytes)

    callback = fn
      count,
      {:in,
       {:"$gen_call", _,
        {:extension_action_begin, _, %{"name" => "read", "arguments" => arguments}}}},
      _ ->
        if arguments["byte_offset"] == 4096, do: File.write!(path, document("changed"))
        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(run.pid, {callback, 0})
    assert invoke(run, "source", args())["status"] == "refused"
    {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)
    refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == "state.put"))
  end

  @tag :locator_manifest
  test "paged typed locator manifests hydrate across actual host results and reject corruption",
       c do
    run = open(c)
    path = Path.join(run.cwd, "source.docx")
    legacy = document("Legacy metadata selection remains current.")
    File.write!(path, legacy)
    assert invoke(run, "source", args())["status"] == "ok"

    old =
      invoke(run, "source", %{
        "store" => "notes",
        "action" => "inspect",
        "args" => %{"source_id" => "workspace:source"}
      })

    bytes = many_locations()
    File.write!(path, bytes)

    command =
      args()
      |> put_in(["args", "generation"], 2)
      |> put_in(["args", "expected_revision"], old["coverage"]["revision"])
      |> put_in(["args", "expected_sha256"], JSON.sha256(bytes))

    opened = invoke(run, "source", command)
    assert opened["status"] == "draft", inspect({opened, acquisition_trace(run)})
    assert opened["continuation"]["arguments"]["args"]["metadata_offset"] == 0
    first = continue(run, opened["continuation"])
    assert first["status"] == "draft", inspect(first)
    assert first["continuation"]["arguments"]["args"]["offset"] == 0
    assert first["continuation"]["arguments"]["args"]["metadata_offset"] > 0
    assert_retained_workspace_source(run, path, legacy, "Legacy metadata")
    tampered = put_in(first, ["continuation", "arguments", "args", "metadata_offset"], 0)
    assert continue(run, tampered["continuation"])["status"] == "refused"
    wrong_text_offset = put_in(first, ["continuation", "arguments", "args", "offset"], 1)
    assert continue(run, wrong_text_offset["continuation"])["status"] == "refused"
    assert finish_staging(run, first)["status"] == "ok"
    result = query(run, "Nebula table")
    assert result["status"] == "partial", inspect(result)
    refute result["coverage"]["complete"]
    [hit] = result["evidence"]
    citation = hit["citation"]
    assert citation["quote"] == "Nebula table evidence stays exactly located."

    assert citation["document"]["locator"] == %{
             "kind" => "table_cell",
             "part" => "word/document.xml",
             "paragraph" => 24,
             "table" => 1,
             "row" => 2,
             "cell" => 2
           }

    assert citation["document"]["start_byte"] == 0
    descriptor = citation["origin"]["receipt"]
    assert descriptor["version"] == 4 and descriptor["manifest_bytes"] > 2048
    assert descriptor["segment_count"] == 24 and descriptor["warning_count"] > 0
    assert Enum.any?(result["gaps"], &(&1["code"] == "partial_document" and &1["warnings"] != []))
    refute Map.has_key?(descriptor, "segments")
    {_, _, state} = stored_state(run)
    records = Map.values(state["records"])

    progress =
      Enum.filter(records, &(get_in(&1, ["value", "page_kind"]) == "document"))
      |> Enum.sort_by(&get_in(&1, ["value", "ordinal"]))

    contents = Enum.filter(records, &(get_in(&1, ["value", "page_kind"]) == "document_content"))
    assert length(progress) > 2 and length(contents) > 2
    root = Enum.find(records, &(get_in(&1, ["value", "kind"]) == "root"))
    page = hd(contents)
    change_record(run, page["key"], nil)
    missing = query(run, "Nebula table")
    assert missing["status"] == "refused"
    assert Enum.any?(missing["gaps"], &(&1["code"] == "source_corrupt"))
    restore_fixture_state(run, state)
    assert query(run, "Nebula table")["evidence"] != []

    change_record(
      run,
      page["key"],
      put_in(page["value"], ["body", "text"], "forged locator metadata")
    )

    assert query(run, "Nebula table")["status"] == "refused"
    restore_fixture_state(run, state)
    [a, b | rest] = Enum.map(progress, &get_in(&1, ["value", "body", "pieces"]))
    pieces = [b, a | rest]

    head =
      Enum.zip(progress, pieces)
      |> Enum.reduce(nil, fn {row, pieces}, previous ->
        body = row["value"]["body"] |> Map.put("previous", previous) |> Map.put("pieces", pieces)
        {key, value, ref} = changed_page(row["value"], body)
        change_record(run, key, value)
        ref
      end)

    changed_root = put_in(root["value"], ["origin", "receipt", "manifest_ref"], head)
    change_record(run, root["key"], changed_root)
    reordered = query(run, "Nebula table")
    assert reordered["status"] == "refused"
    assert Enum.any?(reordered["gaps"], &(&1["code"] == "source_corrupt"))
    restore_fixture_state(run, state)

    hidden_warning =
      root["value"]
      |> put_in(["origin", "receipt", "status"], "complete")
      |> put_in(["origin", "receipt", "warning_count"], 0)

    change_record(run, root["key"], hidden_warning)
    assert query(run, "Nebula table")["status"] == "refused"
    restore_fixture_state(run, state)
    assert query(run, "Nebula table")["status"] == "partial"
    {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)

    for event <- events,
        event["type"] == "extension_action_result",
        event["outcome"]["status"] == "ok" do
      assert :ok = Ipse.Extension.validate(event["outcome"]["value"])
    end

    assert {:ok, _} = Session.Saved.restore(events, Session.info(run.pid).id)
  end

  @tag :public_collection_document
  @tag :public_collection_refusal
  @tag :namespace_public
  test "public Collection preset authenticates paused Word storage and returns typed selected citation",
       c do
    run = open(c, "collection-documents")
    paragraph = fn text -> "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" end

    body =
      Enum.map_join(1..32, fn n ->
        paragraph.(
          "Paragraph #{n}: " <>
            String.duplicate("context ", 220) <>
            if(n == 32, do: "Altair collection keeps every locator.", else: "stable evidence.")
        )
      end) <> "<w:p><w:r><w:sym w:char=\"F0FC\"/></w:r></w:p>"

    bytes = document_body(body, [])
    assert byte_size(bytes) in 1..32_768
    File.write!(Path.join(run.cwd, "source.docx"), bytes)
    opened = run |> invoke("source", args()) |> then(&await_staged_collection(run, &1))
    checkpoint = opened["continuation"]["arguments"]["args"]["collection_state"]
    assert checkpoint["version"] == 3
    assert [_ | _] = checkpoint["stages"]
    assert opened["continuation"]["arguments"]["args"]["expected_sha256"] == JSON.sha256(bytes)
    original = opened["continuation"]["arguments"]["args"]["opening_acquisition"]

    {:ok, before_refusal} = Journal.load(run.dir, Session.info(run.pid).id)

    forged =
      update_in(
        opened["continuation"],
        ["arguments", "args", "collection_state", "stages"],
        fn [stage | rest] -> [Map.put(stage, "epoch", String.duplicate("0", 32)) | rest] end
      )

    assert continue(run, forged)["status"] == "refused"

    changed = document("The workspace document changed after a known storage prefix.")
    File.write!(Path.join(run.cwd, "source.docx"), changed)
    assert continue(run, opened["continuation"])["status"] == "refused"
    File.write!(Path.join(run.cwd, "source.docx"), bytes)

    forged_origin =
      put_in(
        opened["continuation"],
        ["arguments", "args", "opening_acquisition", "operation_id"],
        String.duplicate("0", 32)
      )

    assert continue(run, forged_origin)["status"] == "refused"
    {:ok, after_refusal} = Journal.load(run.dir, Session.info(run.pid).id)

    new_events = Enum.drop(after_refusal, length(before_refusal))

    refute Enum.any?(new_events, fn event ->
             event["type"] == "extension_action_intent" and
               Ipse.Extension.CollectionStore.mutating?(event["request"])
           end)

    finished =
      Enum.reduce_while(1..40, opened, fn _, result ->
        case result["status"] do
          "draft" -> {:cont, continue(run, result["continuation"])}
          _ -> {:halt, result}
        end
      end)

    assert finished["status"] == "ok", inspect(finished)

    result =
      invoke(run, "query_selected", %{
        "store" => "notes",
        "retrieval" => "words",
        "query" => "Altair collection",
        "top_k" => 1,
        "as_of_ms" => 20,
        "source_ids" => ["workspace:source"]
      })

    assert result["status"] == "partial", inspect(result)
    [hit] = result["evidence"]
    assert hit["citation"]["document"]["locator"]["paragraph"] == 32
    assert hit["citation"]["document"]["original_sha256"] == JSON.sha256(bytes)
    assert hit["citation"]["origin"]["receipt"]["acquisition"] == original
    assert Enum.any?(result["gaps"], &(&1["code"] == "partial_document"))
    refute result["coverage"]["namespace_complete"]
    assert query(run, "Altair")["status"] == "refused"

    indexing =
      invoke(run, "lexical_index", %{
        "store" => "notes",
        "action" => "begin",
        "continuation" => nil
      })

    indexed =
      Enum.reduce_while(1..80, indexing, fn _, current ->
        if current["status"] == "draft",
          do: {:cont, continue(run, current["continuation"])},
          else: {:halt, current}
      end)

    assert indexed["status"] == "ok", inspect(indexed)
    namespace = query(run, "Altair collection")
    assert namespace["status"] == "partial", inspect(namespace)
    assert namespace["coverage"]["namespace_complete"]
    assert namespace["coverage"]["index_generation"] == 1
    assert hd(namespace["evidence"])["citation"]["document"]["locator"]["paragraph"] == 32
    assert hd(namespace["evidence"])["citation"]["origin"]["receipt"]["acquisition"] == original
    {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)
    actions = Enum.filter(events, &(&1["type"] == "extension_action_result"))

    for {_id, group} <- Enum.group_by(actions, & &1["parent_invocation_id"]) do
      others =
        Enum.count(group, fn e ->
          get_in(e, ["request", "op"]) == "tool.call" or
            Ipse.Extension.CollectionStore.mutating?(e["request"])
        end)

      assert others <= 16
    end

    assert Enum.any?(actions, &(get_in(&1, ["request", "request", "op"]) == "stage.inspect"))
    assert Enum.all?(actions, &Ipse.Extension.Actions.valid_result?/1)
    assert {:ok, _} = Session.Saved.restore(events, Session.info(run.pid).id)
  end

  @tag :public_collection_document
  test "public Collection provided source continues without extra authority and old presets keep grants",
       c do
    run = open(c, "collection-documents")

    input = %{
      "source_id" => "provided:plain",
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Provided source",
      "text" => "Lyra source stays explicit.",
      "uri" => "provided:plain",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

    opened = invoke(run, "source", %{"store" => "notes", "action" => "put", "args" => input})

    finished =
      Enum.reduce_while(1..20, opened, fn _, result ->
        if result["status"] == "draft",
          do: {:cont, continue(run, result["continuation"])},
          else: {:halt, result}
      end)

    assert finished["status"] == "ok", inspect(finished)

    result =
      invoke(run, "query_selected", %{
        "store" => "notes",
        "retrieval" => "words",
        "query" => "Lyra",
        "top_k" => 1,
        "as_of_ms" => 20,
        "source_ids" => ["provided:plain"]
      })

    assert result["status"] == "ok"
    assert hd(result["evidence"])["citation"]["quote"] == input["text"]
    old = Jason.decode!(File.read!(Path.join(c.artifacts["state-documents"], "extension.json")))
    refute "host.collection.store" in old["capabilities"]
    refute Enum.any?(old["exports"]["commands"], &(&1["id"] == "query_selected"))
  end

  @tag :public_collection_grant
  test "generated collection preset requires its explicit operator binding and preserves old grants",
       c do
    modules = [IpseKnowledge.Profiles, IpseKnowledge.BuildSpec]
    loaded_before = Enum.map(modules, &:code.is_loaded/1)

    expression = """
    [manifest] = System.argv()
    options = JSON.decode!(File.read!("extensions/knowledge/options/corpus-collection.json"))
    bytes = File.read!(manifest)
    args = [bytes, "corpus", "collection-documents", "corpus", options, nil, %{}]
    config = apply(IpseKnowledge.BuildSpec, :operator, args)
    refused = try do
      apply(IpseKnowledge.BuildSpec, :operator, List.replace_at(args, 5, "knowledge"))
      false
    rescue
      ArgumentError -> true
    end
    IO.puts(JSON.encode!(%{"config" => config, "state_binding_refused" => refused}))
    """

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "--erl",
          "+S 2:2",
          "-r",
          "extensions/knowledge/src/profiles.ex",
          "-r",
          "extensions/knowledge/spec.exs",
          "-e",
          expression,
          Path.join(c.artifacts["collection-documents"], "extension.json")
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert %{"config" => config, "state_binding_refused" => true} = Jason.decode!(output)
    assert Enum.map(modules, &:code.is_loaded/1) == loaded_before

    [trust] = config["extension_trust"]

    assert trust["collection_bindings"] == [
             %{
               "version" => 1,
               "instance" => "corpus",
               "id" => "documents",
               "scope" => "project",
               "profile" => "document_graph_v1"
             }
           ]

    assert trust["state_bindings"] == []
    assert "host.collection.store" in trust["capabilities"]
    assert "host.tools" in trust["capabilities"]
    refute "host.inference" in trust["capabilities"]

    for preset <- ~w(state-documents state-lexical) do
      manifest = Jason.decode!(File.read!(Path.join(c.artifacts[preset], "extension.json")))
      refute "host.collection.store" in manifest["capabilities"]
    end
  end

  @tag :collection_chunking_public
  test "public Collection Word uses explicit paragraph-local recipe2 through namespace citations",
       c do
    run = open(c, "collection-documents")

    body =
      Enum.map_join(1..10, fn n ->
        head =
          if n == 10, do: "Altair capacity evidence.", else: "Paragraph #{n} stable evidence."

        remaining = 2097 - byte_size(head) - 1

        text =
          head <>
            " " <>
            String.duplicate("context ", div(remaining, 8)) <>
            String.duplicate("z", rem(remaining, 8))

        "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>"
      end)

    bytes = document_body(body, [{:compress, []}])
    assert byte_size(bytes) > 4096 and byte_size(bytes) <= 32768
    File.write!(Path.join(run.cwd, "source.docx"), bytes)
    opened = invoke(run, "source", args())

    stored =
      Enum.reduce_while(1..40, opened, fn _, current ->
        if current["status"] == "draft",
          do: {:cont, continue(run, current["continuation"])},
          else: {:halt, current}
      end)

    assert stored["status"] == "ok", inspect(stored)

    opened =
      invoke(run, "lexical_index", %{
        "store" => "notes",
        "action" => "begin",
        "continuation" => nil
      })

    indexed =
      Enum.reduce_while(1..40, opened, fn _, current ->
        if current["status"] == "draft",
          do: {:cont, continue(run, current["continuation"])},
          else: {:halt, current}
      end)

    assert indexed["status"] == "ok", inspect(indexed)
    result = query(run, "Altair capacity")
    assert result["status"] == "ok", inspect(result)
    assert result["coverage"]["indexed_chunks"] == 10
    [hit] = result["evidence"]
    assert hit["citation"]["version"] == 3
    assert hit["citation"]["chunking"] == %{"version" => 2, "max_bytes" => 4096}
    assert hit["citation"]["document"]["locator"]["paragraph"] == 10
    assert hit["citation"]["document"]["original_sha256"] == JSON.sha256(bytes)
  end

  @tag :public_collection_unknown
  test "public Collection continuation owner loss retains an unknown fused write without replay",
       c do
    run = open(c, "collection-documents")
    {bytes, _} = larger_document()
    File.write!(Path.join(run.cwd, "source.docx"), bytes)
    opened = invoke(run, "source", args())
    assert opened["status"] == "draft"
    id = Session.info(run.pid).id
    guard = :sys.get_state(run.pid).lock_guard
    guard_ref = Process.monitor(guard)
    owner = self()

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{
           "request" => %{"op" => "collection.store", "request" => %{"op" => "value.write_parts"}}
         }}}},
      _ ->
        send(owner, :public_collection_append_before_commit)
        receive do: (:release_public_collection_append -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(run.pid, {callback, 0})

    assert :ok =
             Session.invoke_export(
               run.pid,
               :command,
               "ext__corpus__source",
               opened["continuation"]["arguments"]
             )

    approve_until_collection_append(run)
    monitor = Process.monitor(run.pid)
    Process.exit(run.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    assert {:ok, before} = Journal.load(run.dir, id)
    [last | _] = Enum.reverse(before)
    assert last["type"] == "extension_action_intent"
    assert get_in(last, ["request", "request", "op"]) == "value.write_parts"
    retained = retained_files(run.opts[:config][:home])
    journal = Path.join(run.dir, id <> ".jsonl")
    before_bytes = File.read!(journal)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(run.opts, :id, id)}
             )

    assert_idle_resume_journal(journal, before_bytes, id)
    assert :ok = Session.close_confirmed(resumed)

    assert_retained_after_close(run, id, retained, journal)
  end

  defp approve_until_collection_append(run) do
    receive do
      :public_collection_append_before_commit ->
        :ok

      {:ipse, pid, {:approval, ref, "extension:collection.store", _}} when pid == run.pid ->
        assert :ok = Session.approve(pid, ref, true)
        approve_until_collection_append(run)

      {:ipse, pid, {:done, :ok}} when pid == run.pid ->
        assert %{"value" => result} = Session.info(pid).extension_result
        assert result["status"] == "draft", inspect(result)

        assert :ok =
                 Session.invoke_export(
                   pid,
                   :command,
                   "ext__corpus__source",
                   result["continuation"]["arguments"]
                 )

        approve_until_collection_append(run)

      {:ipse, pid, {:done, status}} when pid == run.pid ->
        flunk("continuation ended before fused write: #{inspect(status)}")

      {:ipse, pid, _} when pid == run.pid ->
        approve_until_collection_append(run)
    after
      10_000 -> flunk("continuation did not reach a Collection append")
    end
  end

  @tag :queued_document_expiry
  test "State refuses a document stage held in approval beyond its stored deadline", c do
    run = open(c)
    {bytes, _} = larger_document()
    File.write!(Path.join(run.cwd, "source.docx"), bytes)
    opened = invoke(run, "source", args())
    assert opened["status"] == "draft"
    {_, _, state} = stored_state(run)

    {key, row} =
      Enum.find(state["records"], fn {_, row} -> get_in(row, ["value", "kind"]) == "root" end)

    expiry = System.system_time(:millisecond) + 2000

    assert {:ok, _} =
             change_record(run, key, put_in(row["value"], ["draft", "expires_at_ms"], expiry))

    {_, _, before} = stored_state(run)

    next =
      put_in(
        opened["continuation"],
        ["arguments", "args", "expected_revision"],
        before["records"][key]["revision"]
      )

    assert :ok =
             Session.invoke_export(run.pid, :command, "ext__corpus__source", next["arguments"])

    receive do
      {:ipse, pid, {:approval, ref, "extension:state.put", proposed}} when pid == run.pid ->
        assert proposed["request"]["write_before_ms"] == expiry
        Process.sleep(max(expiry - System.system_time(:millisecond), 0) + 5)
        assert :ok = Session.approve(pid, ref, true)
    after
      5000 -> flunk("conditioned stage did not reach approval")
    end

    result = wait(run, System.monotonic_time(:millisecond) + 10_000)
    assert result["status"] == "refused"
    {_, _, after_refusal} = stored_state(run)
    assert after_refusal === before
    id = Session.info(run.pid).id
    {:ok, events} = Journal.load(run.dir, id)

    [failed] =
      Enum.filter(events, &(get_in(&1, ["outcome", "value", "code"]) == "write_deadline_elapsed"))

    assert get_in(failed, ["outcome", "status"]) == "failed"
    assert get_in(failed, ["outcome", "value", "checked_at_ms"]) >= expiry
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "owner loss after a staged append leaves its effect unknown and resume does not replay",
       c do
    for bytes <- [elem(larger_document(), 0), many_locations()] do
      run = open(c)
      File.write!(Path.join(run.cwd, "source.docx"), bytes)
      opened = invoke(run, "source", args())
      assert opened["status"] == "draft", inspect({opened, acquisition_trace(run)})
      id = Session.info(run.pid).id
      guard = :sys.get_state(run.pid).lock_guard
      guard_ref = Process.monitor(guard)
      owner = self()

      callback = fn
        0,
        {:in,
         {:"$gen_call", _, {:extension_action_commit, _, %{"request" => %{"op" => "state.put"}}}}},
        _ ->
          send(owner, :append_before_commit)
          receive do: (:release_staged_append_test -> :ok)
          1

        count, _, _ ->
          count
      end

      assert :ok = :sys.install(run.pid, {callback, 0})
      next = opened["continuation"]

      assert :ok =
               Session.invoke_export(run.pid, :command, "ext__corpus__source", next["arguments"])

      approve_until_append(run)
      monitor = Process.monitor(run.pid)
      Process.exit(run.pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
      assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
      assert {:ok, before} = Journal.load(run.dir, id)
      writes = Enum.filter(before, &(get_in(&1, ["request", "op"]) == "state.put"))
      assert List.last(writes)["type"] == "extension_action_intent"
      retained = retained_files(run.opts[:config][:home])
      journal = Path.join(run.dir, id <> ".jsonl")
      before_bytes = File.read!(journal)

      assert {:ok, resumed} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session, Keyword.put(run.opts, :id, id)}
               )

      assert_idle_resume_journal(journal, before_bytes, id)
      assert :ok = Session.close_confirmed(resumed)

      assert_retained_after_close(run, id, retained, journal)
    end
  end

  defp assert_retained_after_close(run, id, retained, journal) do
    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Session.Saved.inspect_saved(run.dir, id)

    assert {:ok, closed_events} = Journal.load(run.dir, id)

    assert %{"type" => "session_release_intent", "operation_id" => operation} =
             List.last(closed_events)

    release = Path.join(run.dir, ".release-" <> id <> "-" <> operation)
    refute Map.has_key?(retained, release)
    after_close = retained_files(run.opts[:config][:home])
    assert Map.has_key?(after_close, release)
    assert Map.drop(after_close, [journal, release]) == Map.delete(retained, journal)
  end

  defp retained_files(home) do
    Path.wildcard(Path.join(home, "**/*"), match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(&{&1, JSON.sha256(File.read!(&1))})
  end

  defp acquisition_trace(run) do
    {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)

    for event <- events,
        event["type"] == "extension_action_result",
        do:
          {get_in(event, ["request", "op"]),
           get_in(event, ["request", "arguments", "byte_offset"]),
           get_in(event, ["outcome", "status"]), get_in(event, ["outcome", "value", "reason"])}
  end

  defp approve_until_append(run) do
    receive do
      {:ipse, pid, {:approval, ref, "extension:state.put", proposed}} when pid == run.pid ->
        assert :ok = State.validate(proposed["request"])
        assert :ok = Session.approve(pid, ref, true)
        approve_until_append(run)

      :append_before_commit ->
        :ok

      {:ipse, pid, _} when pid == run.pid ->
        approve_until_append(run)
    after
      15_000 -> flunk("staged append did not reach its actual write")
    end
  end

  test "a changed file at the final acquisition refuses before any source write", c do
    run = open(c)
    File.write!(Path.join(run.cwd, "source.docx"), document("original content"))
    path = Path.join(run.cwd, "source.docx")
    changed = document("changed content")

    callback = fn
      count,
      {:in,
       {:"$gen_call", _, {:extension_action_begin, _, %{"op" => "tool.call", "name" => "read"}}}},
      _ ->
        if count == 1, do: File.write!(path, changed)
        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(run.pid, {callback, 0})
    assert invoke(run, "source", args())["status"] == "refused"
    assert {:ok, events} = Journal.load(run.dir, Session.info(run.pid).id)

    refute Enum.any?(
             events,
             &(&1["type"] == "extension_action_intent" and
                 get_in(&1, ["request", "op"]) == "state.put")
           )

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_action_result" and
                 get_in(&1, ["outcome", "status"]) == "failed")
           )
  end

  test "owner loss after actual binary read leaves an unknown prefix and resume performs no read or write",
       c do
    run = open(c)
    File.write!(Path.join(run.cwd, "source.docx"), document("interrupted source"))
    id = Session.info(run.pid).id
    guard = :sys.get_state(run.pid).lock_guard
    guard_ref = Process.monitor(guard)
    owner = self()

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{"request" => %{"op" => "tool.call", "name" => "read"}} = event}}},
      _ ->
        send(owner, {:acquired_before_commit, event})
        receive do: (:release_acquisition_test -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(run.pid, {callback, 0})
    assert :ok = Session.invoke_export(run.pid, :command, "ext__corpus__source", args())
    assert_receive {:acquired_before_commit, event}, 10_000
    assert event["outcome"]["status"] == "ok"
    monitor = Process.monitor(run.pid)
    Process.exit(run.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    assert {:ok, before} = Journal.load(run.dir, id)

    assert Enum.count(
             before,
             &(get_in(&1, ["request", "name"]) == "read" and
                 &1["type"] == "extension_action_intent")
           ) == 1

    refute Enum.any?(before, &(&1["type"] == "extension_action_result"))
    journal = Path.join(run.dir, id <> ".jsonl")
    before_bytes = File.read!(journal)
    File.write!(Path.join(run.cwd, "source.docx"), document("changed after owner loss"))

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(run.opts, :id, id)}
             )

    assert_idle_resume_journal(journal, before_bytes, id)
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag :workspace_word_guard_diagnostic
  @tag timeout: 180_000
  test "diagnostic fresh small guarded Word publication", c do
    run = open(c, "collection-documents")
    bytes = document("Orion synthetic diagnostic source.")
    assert byte_size(bytes) < 32_768
    File.write!(Path.join(run.cwd, "source.docx"), bytes)
    opened = invoke(run, "source", args())

    finished =
      Enum.reduce_while(1..40, opened, fn _, current ->
        if current["status"] == "draft",
          do: {:cont, continue(run, current["continuation"])},
          else: {:halt, current}
      end)

    assert finished["status"] == "ok", inspect(finished)
    assert File.read!(Path.join(run.cwd, "source.docx")) == bytes
  end

  @tag :workspace_word_large
  @tag timeout: 300_000
  test "large workspace Word survives staged publication and rechecks the original on citation",
       c do
    run = open(c, "collection-documents")

    text =
      "Orion launch is grounded in this original. " <> String.duplicate("stable detail ", 2800)

    bytes = document(text, [{:compress, []}])
    assert byte_size(bytes) > 32_768 and byte_size(bytes) <= 1_048_576
    path = Path.join(run.cwd, "source.docx")
    File.write!(path, bytes)

    opened = run |> invoke("source", args()) |> then(&await_staged_collection(run, &1))
    opening = get_in(opened, ["continuation", "arguments", "args", "opening_acquisition"])
    assert %{"kind" => "workspace.read", "path" => "source.docx", "operation_id" => _} = opening

    File.write!(path, document("A different synthetic original."))
    assert continue(run, opened["continuation"])["status"] == "refused"
    File.write!(path, bytes)

    finished =
      Enum.reduce_while(1..40, opened, fn _, current ->
        if current["status"] == "draft",
          do: {:cont, continue(run, current["continuation"])},
          else: {:halt, current}
      end)

    assert finished["status"] == "ok", inspect(finished)

    query_args = %{
      "store" => "notes",
      "retrieval" => "words",
      "query" => "Orion launch",
      "top_k" => 1,
      "as_of_ms" => 20,
      "source_ids" => ["workspace:source"]
    }

    result = invoke(run, "query_selected", query_args)
    assert result["status"] in ~w(ok partial), inspect(result)

    assert Enum.any?(result["evidence"], fn hit ->
             get_in(hit, ["citation", "document", "original_sha256"]) == JSON.sha256(bytes) and
               get_in(hit, ["citation", "document", "locator", "paragraph"]) == 1
           end)

    held = path <> ".held"
    File.rename!(path, held)

    try do
      missing = invoke(run, "query_selected", query_args)
      assert missing["status"] == "refused", inspect(missing)
    after
      if File.exists?(held) and not File.exists?(path), do: File.rename!(held, path)
    end

    restored = invoke(run, "query_selected", query_args)
    assert restored["status"] in ~w(ok partial), inspect(restored)
    assert File.read!(path) == bytes

    id = Session.info(run.pid).id
    {:ok, events} = Journal.load(run.dir, id)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_result" and
               get_in(event, ["request", "arguments", "snapshot"]) == "page" and
               get_in(event, ["outcome", "status"]) == "ok"
           end)

    assert Enum.any?(events, fn event ->
             event["type"] == "extension_action_intent" and
               get_in(event, ["request", "workspace_guard", "opening_operation_id"]) ==
                 opening["operation_id"]
           end)

    assert {:ok, _} = Session.Saved.restore(events, id)
    assert :ok = Session.close_confirmed(run.pid)
    journal = Path.join(run.dir, id <> ".jsonl")
    before = File.read!(journal)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(run.opts, :id, id)}
             )

    assert_idle_resume_journal(journal, before, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(path) == bytes
  end

  @tag :workspace_word_large_unknown
  @tag timeout: 180_000
  test "owner loss before a large Word page result stays unknown and is not replayed", c do
    run = open(c, "collection-documents")
    bytes = document("Orion " <> String.duplicate("source ", 5000), [{:compress, []}])
    assert byte_size(bytes) > 32_768
    path = Path.join(run.cwd, "source.docx")
    File.write!(path, bytes)
    id = Session.info(run.pid).id
    lock = :sys.get_state(run.pid).lock_guard
    lock_ref = Process.monitor(lock)
    owner = self()

    callback = fn
      0,
      {:in,
       {:"$gen_call", _,
        {:extension_action_commit, _,
         %{"request" => %{"op" => "tool.call", "arguments" => %{"snapshot" => "page"}}} = event}}},
      _ ->
        send(owner, {:large_word_page_before_commit, event})
        receive do: (:release_large_word_page -> :ok)
        1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(run.pid, {callback, 0})
    assert :ok = Session.invoke_export(run.pid, :command, "ext__corpus__source", args())
    assert_receive {:large_word_page_before_commit, event}, 30_000
    assert get_in(event, ["outcome", "status"]) == "ok"
    monitor = Process.monitor(run.pid)
    Process.exit(run.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}, 5000
    assert_receive {:DOWN, ^lock_ref, :process, ^lock, _}, 5000
    {:ok, events} = Journal.load(run.dir, id)
    assert List.last(events)["type"] == "extension_action_intent"
    assert get_in(List.last(events), ["request", "arguments", "snapshot"]) == "page"
    journal = Path.join(run.dir, id <> ".jsonl")
    before = File.read!(journal)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(run.opts, :id, id)}
             )

    assert_idle_resume_journal(journal, before, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(path) == bytes
  end
end
