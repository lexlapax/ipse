ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)

defmodule DocumentSetupJourney do
  import ExUnit.Assertions

  def document do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"source.docx",
        [
          {~c"_rels/.rels",
           "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"},
          {~c"[Content_Types].xml",
           "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body><w:p><w:r><w:t>Nebula setup retains exact résumé evidence.</w:t></w:r></w:p></w:body></w:document>"}
        ],
        [:memory]
      )

    bytes
  end

  def numbered_document do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"
    office = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    content = "application/vnd.openxmlformats-officedocument.wordprocessingml"

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"numbered.docx",
        [
          {~c"_rels/.rels",
           "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"#{office}officeDocument\" Target=\"word/document.xml\"/></Relationships>"},
          {~c"[Content_Types].xml",
           "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"#{content}.document.main+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"#{content}.numbering+xml\"/></Types>"},
          {~c"word/_rels/document.xml.rels",
           "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"numbers\" Type=\"#{office}numbering\" Target=\"numbering.xml\"/></Relationships>"},
          {~c"word/numbering.xml",
           "<w:numbering xmlns:w=\"#{word}\"><w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"3\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/></w:lvl></w:abstractNum><w:num w:numId=\"7\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>"},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>" <>
             Enum.map_join(1..40, fn n ->
               text =
                 case n do
                   1 -> "First café item"
                   2 -> "amberneedle exact evidence"
                   3 -> "Plain middle"
                   4 -> "Table numbered"
                   _ -> "Filler #{n}"
                 end

               props =
                 if n in [1, 2, 4],
                   do:
                     "<w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"7\"/></w:numPr></w:pPr>",
                   else: ""

               paragraph = "<w:p>#{props}<w:r><w:t>#{text}</w:t></w:r></w:p>"

               if n == 4,
                 do: "<w:tbl><w:tr><w:tc>#{paragraph}</w:tc></w:tr></w:tbl>",
                 else: paragraph
             end) <> "</w:body></w:document>"}
        ],
        [:memory]
      )

    bytes
  end

  def invoke(pid, id, arguments, digest) do
    assert :ok = Ipse.Session.invoke_export(pid, :command, "ext__documents__" <> id, arguments)
    wait(pid, digest, System.monotonic_time(:millisecond) + 20_000)
  end

  def finish(pid, value, digest) do
    Enum.reduce_while(1..40, value, fn _, value ->
      if value["status"] == "draft" do
        next = value["continuation"]
        {:cont, invoke(pid, next["id"], next["arguments"], digest)}
      else
        {:halt, value}
      end
    end)
  end

  defp wait(pid, digest, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, label, proposed}} ->
        assert label in ["extension:state.put", "extension:collection.store"]
        assert proposed["artifact_sha256"] == digest
        assert :ok = Ipse.Session.approve(pid, ref, true)
        wait(pid, digest, deadline)

      {:ipse, ^pid, {:done, :ok}} ->
        assert %{"value" => value} = Ipse.Session.info(pid).extension_result
        value

      {:ipse, ^pid, {:error, reason}} ->
        flunk(inspect(reason))

      {:ipse, ^pid, _} ->
        wait(pid, digest, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("document setup command timed out")
    end
  end
end

for key <-
      ~w(IPSE_HOME IPSE_CONFIG IPSE_PROFILE) ++
        Enum.map(
          Map.keys(Ipse.Config.settings_schema()["properties"]),
          &("IPSE_" <> String.upcase(&1))
        ),
    do: System.delete_env(key)

[root, scenario] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "workspace")
File.mkdir_p!(cwd)
File.mkdir!(home)
File.chmod!(home, 0o700)
path = Path.join(home, "config.json")
System.put_env("IPSE_HOME", home)

original =
  Jason.encode!(%{
    "version" => 1,
    "settings" => %{"provider" => "demo", "model" => "scripted"},
    "profiles" => %{"kept" => %{"provider" => "demo", "model" => "scripted"}},
    "roles" => %{"main" => "kept"}
  })

File.write!(path, original)
File.chmod!(path, 0o600)

if scenario == "race" do
  spawn(fn ->
    wait = fn wait ->
      if File.exists?(Path.join(root, "native-review-ready")) do
        File.write!(path, original <> "\n")
        File.write!(Path.join(root, "consent-raced"), "ready")
      else
        Process.sleep(10)
        wait.(wait)
      end
    end

    wait.(wait)
  end)
end

profile = if scenario == "collection", do: "collection", else: "state"

argv =
  ["documents", "setup", "--cwd", cwd, "--profile", profile, "--write"] ++
    if(profile == "collection", do: ["--scope", "folder"], else: [])

result = Ipse.CLI.run(argv)

if scenario in ~w(pipe cancel stale race) do
  assert result == 1
  assert File.read!(path) == original <> if(scenario == "race", do: "\n", else: "")
  refute File.exists?(Path.join(home, "extensions"))
  refute File.exists?(Ipse.Extension.SemanticAdmission.control_root(home))
  assert File.exists?(path <> ".lock") == (scenario == "race")
  assert Path.wildcard(path <> ".bak-*") == []
  IO.puts("DOCUMENT_SETUP_REFUSAL_PASSED")
else
  assert result == 0
  refute File.exists?(Ipse.Extension.SemanticAdmission.control_root(home))
  saved = Jason.decode!(File.read!(path))
  assert saved["settings"] == Jason.decode!(original)["settings"]
  assert saved["profiles"] == Jason.decode!(original)["profiles"]
  assert saved["roles"] == Jason.decode!(original)["roles"]
  [instance] = saved["extensions"]
  [trust] = saved["extension_trust"]
  assert instance["enabled"]
  refute trust["allow_children"]
  refute trust["allow_project"]
  refute "host.model" in trust["capabilities"]
  refute "host.embedding" in trust["capabilities"]
  assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
  [backup] = Path.wildcard(path <> ".bak-*")
  assert File.read!(backup) == original
  File.rm!(backup)

  {:ok, effective} = Ipse.Config.resolve(cwd, home, [project_config: false], %{})

  client = %{
    workspace: cwd,
    home: home,
    auth_dir: Path.join(home, "auth"),
    operator_home: root,
    mcp_config: nil,
    base_url: nil,
    operator_questions: false,
    accept_edits: false,
    approval: :ask,
    approval_origin: :interactive,
    headless: false
  }

  {:ok, config} = Ipse.Config.runtime(effective, client)

  session_opts = [
    config: config,
    cwd: cwd,
    state_dir: Path.join(home, "sessions"),
    subscriber: self()
  ]

  {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, session_opts})
  bytes = DocumentSetupJourney.document()
  File.write!(Path.join(cwd, "source.docx"), bytes)

  acquired =
    DocumentSetupJourney.invoke(
      pid,
      "source",
      %{
        "store" => "notes",
        "action" => "read_document",
        "args" => %{
          "source_id" => "workspace:source",
          "generation" => 1,
          "expected_revision" => 0,
          "title" => "Setup Word source",
          "path" => "source.docx",
          "expected_sha256" => Ipse.JSON.sha256(bytes),
          "uri" => "workspace:source.docx",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => nil
        }
      },
      instance["artifact"]
    )

  acquired =
    Enum.reduce_while(1..40, acquired, fn _, value ->
      if value["status"] == "draft" do
        next = value["continuation"]

        {:cont,
         DocumentSetupJourney.invoke(pid, next["id"], next["arguments"], instance["artifact"])}
      else
        {:halt, value}
      end
    end)

  assert acquired["status"] == "ok", inspect(acquired)

  if profile == "collection" do
    index =
      DocumentSetupJourney.invoke(
        pid,
        "lexical_index",
        %{
          "store" => "notes",
          "action" => "begin",
          "continuation" => nil
        },
        instance["artifact"]
      )

    index = DocumentSetupJourney.finish(pid, index, instance["artifact"])
    assert index["status"] == "ok", inspect(index)
  end

  query = %{
    "store" => "notes",
    "retrieval" => "words",
    "rerank" => nil,
    "query" => "Nebula résumé",
    "top_k" => 1,
    "as_of_ms" => 20
  }

  result = DocumentSetupJourney.invoke(pid, "query", query, instance["artifact"])
  assert result["status"] == "ok", inspect(result)
  [hit] = result["evidence"]
  assert hit["citation"]["quote"] =~ "exact résumé evidence"
  assert hit["citation"]["document"]["original_sha256"] == Ipse.JSON.sha256(bytes)
  session_id = Ipse.Session.info(pid).id
  {:ok, events} = Ipse.Journal.load(session_opts[:state_dir], session_id)
  refute Enum.any?(events, &(&1["type"] == "request_admitted"))
  assert {:ok, _} = Ipse.Session.Saved.restore(events, session_id)
  :ok = Ipse.Session.close_confirmed(pid)

  {:ok, resumed} =
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Ipse.Session, Keyword.put(session_opts, :id, session_id)}
    )

  assert DocumentSetupJourney.invoke(resumed, "query", query, instance["artifact"])["evidence"] ==
           result["evidence"]

  numbered = DocumentSetupJourney.numbered_document()
  numbered_path = Path.join(cwd, "numbered.docx")
  File.write!(numbered_path, numbered)
  identity = fn stat -> Map.take(stat, [:major_device, :minor_device, :inode, :uid, :size]) end
  original_identity = identity.(File.stat!(numbered_path))

  numbered_source = %{
    "store" => "notes",
    "action" => "read_document",
    "args" => %{
      "source_id" => "workspace:numbered",
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Numbered Word source",
      "path" => "numbered.docx",
      "expected_sha256" => Ipse.JSON.sha256(numbered),
      "uri" => "workspace:numbered.docx",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }
  }

  stored = DocumentSetupJourney.invoke(resumed, "source", numbered_source, instance["artifact"])
  stored = DocumentSetupJourney.finish(resumed, stored, instance["artifact"])
  assert stored["status"] == "ok", inspect(stored)

  numbered_query = %{
    "store" => "notes",
    "retrieval" => "words",
    "query" => "amberneedle",
    "top_k" => 1,
    "as_of_ms" => 20
  }

  find_numbered = fn session ->
    {command, args} =
      if profile == "collection" do
        {"query_selected", Map.put(numbered_query, "source_ids", ["workspace:numbered"])}
      else
        {"query", Map.put(numbered_query, "rerank", nil)}
      end

    DocumentSetupJourney.invoke(session, command, args, instance["artifact"])
  end

  numbered_result = find_numbered.(resumed)
  assert numbered_result["status"] == "partial", inspect(numbered_result)
  assert Enum.any?(numbered_result["gaps"], &(&1["code"] == "partial_document"))
  [numbered_hit] = numbered_result["evidence"]
  citation = numbered_hit["citation"]
  assert citation["quote"] =~ "amberneedle exact evidence"
  refute citation["quote"] =~ "4."
  doc = citation["document"]
  assert doc["original_sha256"] == Ipse.JSON.sha256(numbered)
  assert doc["extraction_version"] == "ipse-documents-v17"

  assert doc["version"] == 2, "the installed journey did not return a packed multi-block citation"

  assert doc["span_fields"] ==
           ~w(paragraph start_byte end_byte quote_start_byte quote_end_byte table row cell numbering)

  expected = ["First café item", "amberneedle exact evidence", "Plain middle", "Table numbered"]
  assert String.starts_with?(citation["quote"], Enum.join(expected, "\n"))
  [first, second, plain, table | _] = doc["spans"]

  Enum.zip([first, second, plain, table], expected)
  |> Enum.reduce(0, fn {row, text}, offset ->
    assert length(row) == 9
    assert Enum.slice(row, 1, 4) == [0, byte_size(text), offset, offset + byte_size(text)]
    offset + byte_size(text) + 1
  end)

  assert [1, _, _, _, _, nil, nil, nil, %{"ordinal" => 3, "label" => "3."}] = first
  assert [2, _, _, _, _, nil, nil, nil, %{"ordinal" => 4, "label" => "4."}] = second
  assert [3, _, _, _, _, nil, nil, nil, nil] = plain
  assert [4, _, _, _, _, 1, 1, 1, %{"ordinal" => 5, "label" => "5."}] = table

  File.write!(numbered_path, DocumentSetupJourney.document())
  changed = find_numbered.(resumed)
  assert changed["status"] == "refused"
  assert changed["evidence"] == []
  assert Enum.any?(changed["gaps"], &(&1["code"] == "document_source_changed_or_unavailable"))
  File.write!(numbered_path, numbered)

  # Retain the same original inode while the saved document becomes unavailable.
  held_path = Path.join(cwd, "numbered-held.docx")
  refute File.exists?(held_path)
  assert identity.(File.stat!(numbered_path)) == original_identity
  assert File.read!(numbered_path) == numbered
  assert :ok = File.rename(numbered_path, held_path)
  refute File.exists?(numbered_path)
  assert identity.(File.stat!(held_path)) == original_identity
  assert File.read!(held_path) == numbered

  unavailable = fn session ->
    missing = find_numbered.(session)
    assert missing["status"] == "refused", inspect(missing)
    assert missing["evidence"] == []
    assert missing["claims"] == []
    assert Enum.any?(missing["gaps"], &(&1["code"] == "document_source_changed_or_unavailable"))
  end

  unavailable.(resumed)
  :ok = Ipse.Session.close_confirmed(resumed)
  {:ok, before_reopen} = Ipse.Journal.load(session_opts[:state_dir], session_id)

  # Reopening alone must not run a saved acquisition or any other new action.
  effect_intents = fn events ->
    Enum.filter(
      events,
      &(&1["type"] in ~w(extension_invocation_intent extension_action_intent request_admitted))
    )
  end

  acquisitions = fn events ->
    Enum.filter(events, fn event ->
      event["type"] == "extension_invocation_intent" and
        get_in(event, ["payload", "arguments", "action"]) == "read_document" and
        get_in(event, ["payload", "arguments", "args", "source_id"]) == "workspace:numbered"
    end)
  end

  before_acquisitions = acquisitions.(before_reopen)
  assert length(before_acquisitions) == 1

  {:ok, resumed_numbered} =
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Ipse.Session, Keyword.put(session_opts, :id, session_id)}
    )

  assert Ipse.Session.info(resumed_numbered).phase == :idle
  {:ok, after_reopen} = Ipse.Journal.load(session_opts[:state_dir], session_id)
  assert effect_intents.(after_reopen) == effect_intents.(before_reopen)
  unavailable.(resumed_numbered)

  # Return the exact held original, then require the full prior citation.
  assert :ok = File.rename(held_path, numbered_path)
  assert identity.(File.stat!(numbered_path)) == original_identity
  assert File.read!(numbered_path) == numbered
  recovered = find_numbered.(resumed_numbered)
  assert recovered["status"] == numbered_result["status"]
  assert recovered["evidence"] == numbered_result["evidence"]
  {:ok, after_recovery} = Ipse.Journal.load(session_opts[:state_dir], session_id)
  assert acquisitions.(after_recovery) == before_acquisitions
  refute Enum.any?(after_recovery, &(&1["type"] == "request_admitted"))
  :ok = Ipse.Session.close_confirmed(resumed_numbered)

  # Inspect the same imported package after the live Session journey has closed.
  artifact_ebin = Path.join([home, "extensions", "artifacts", instance["artifact"], "ebin"])
  Code.prepend_path(artifact_ebin)
  documents = IpseKnowledge.Documents
  evidence = IpseKnowledge.Evidence
  Code.ensure_loaded!(documents)
  Code.ensure_loaded!(evidence)
  assert Path.dirname(to_string(:code.which(documents))) == artifact_ebin
  assert Path.dirname(to_string(:code.which(evidence))) == artifact_ebin
  assert {:ok, extracted} = apply(documents, :extract, [numbered, "numbered.docx"])
  assert length(extracted["segments"]) == 40
  assert {:ok, payload} = apply(documents, :source_payload, [extracted, 65_536])
  assert length(payload["document"]["segments"]) < 40
  assert apply(evidence, :valid_document?, [payload["document"], payload["text"]])
  receipt = apply(evidence, :document_storage_receipt!, [payload["document"]])

  attrs = %{
    "source_id" => "provided:packed-numbered",
    "partition" => "notes",
    "generation" => 1,
    "title" => "Packed numbered control",
    "text" => payload["text"],
    "uri" => "provided:numbered.docx",
    "observed_at_ms" => 10,
    "event_at_ms" => nil,
    "expires_at_ms" => nil,
    "origin" => %{
      "kind" => "provided",
      "store_profile" => "notes",
      "partition_or_scope" => "notes",
      "receipt" => receipt,
      "historical" => false
    }
  }

  attrs =
    if receipt["version"] == 4, do: Map.put(attrs, "document", payload["document"]), else: attrs

  assert {:ok, source} = apply(evidence, :source, [attrs])
  assert {:ok, [chunk | _]} = apply(evidence, :chunks, [source])
  quote = Enum.join(expected, "\n")
  assert {:ok, crossing} = apply(evidence, :citation, [source, chunk, 0, byte_size(quote)])
  assert crossing["quote"] == quote and crossing["document"]["version"] == 2
  assert apply(evidence, :valid_span?, [source, crossing])
  forged = put_in(crossing, ["document", "spans", Access.at(1), Access.at(8), "label"], "5.")
  refute apply(evidence, :valid_span?, [source, forged])

  assert Ipse.CLI.run(["documents", "disable", "--cwd", cwd, "--write"]) == 0
  disabled = Jason.decode!(File.read!(path))
  assert [Map.put(instance, "enabled", false)] == disabled["extensions"]
  assert disabled["extension_trust"] == [trust]
  assert disabled["settings"] == saved["settings"]
  refute File.exists?(Ipse.Extension.SemanticAdmission.control_root(home))
  assert File.read!(Path.join(cwd, "source.docx")) == bytes
  {:ok, disabled_effective} = Ipse.Config.resolve(cwd, home, [project_config: false], %{})
  {:ok, disabled_config} = Ipse.Config.runtime(disabled_effective, client)
  assert disabled_config.extensions == []

  assert {:error, _} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session,
              session_opts
              |> Keyword.put(:id, session_id)
              |> Keyword.put(:config, disabled_config)}
           )

  IO.puts("DOCUMENT_SETUP_JOURNEY_PASSED")
end
