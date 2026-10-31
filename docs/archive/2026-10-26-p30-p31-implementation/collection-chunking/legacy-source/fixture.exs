defmodule IpseTest.CollectionAdapter do
  @behaviour Ipse.Extension
  alias IpseKnowledge.{Documents, Evidence}
  alias IpseKnowledge.Store.Collection

  @caps ~w(invoke.command invoke.result.pages host.actions host.actions.mixed host.collection.store)
  @exports %{
    "version" => 1,
    "tools" => [],
    "services" => [],
    "commands" =>
      for(
        id <- ~w(put query inspect lexical index namespace),
        do: %{
          "id" => id,
          "description" => "Synthetic packed source fixture",
          "arguments_schema" => %{"type" => "object"},
          "result_schema" => %{"type" => "object"}
        }
      )
  }
  def describe, do: %{"sdk" => 2, "capabilities" => @caps, "exports" => @exports}
  def init(options), do: {:ok, options}

  def handle("invoke.command", payload, state) do
    args = payload["arguments"]
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
    state = Map.merge(state, %{mode: payload["id"], args: args})

    case payload["id"] do
      "put" ->
        source =
          if args["tiny"] == true,
            do: tiny(args["source_id"], args["generation"] || 1, args),
            else:
              source(
                args["generation"] || 1,
                args["many"] == true,
                if(args["large_blocks"], do: 6500, else: 1600)
              )

        drive(
          Collection.start(profile, :put, %{
            "source" => source,
            "expected_revision" => args["expected_revision"] || 0,
            "continuation" => args["continuation"]
          }),
          state
        )

      "query" ->
        drive(
          Collection.start(profile, :selected, %{
            "source_ids" => args["source_ids"] || ["fixture:word"],
            "as_of_ms" => 20
          }),
          state
        )

      "lexical" ->
        drive(
          Collection.start(profile, :lexical, %{
            "source_ids" => args["source_ids"] || ["fixture:word"],
            "as_of_ms" => 20
          }),
          state
        )

      "index" ->
        drive(
          Collection.start(profile, :lexical_build, %{
            "action" => args["action"] || "begin",
            "continuation" => args["continuation"]
          }),
          state
        )

      "namespace" ->
        drive(
          Collection.start(profile, :lexical_query, %{
            "query" => args["query"] || "Nocturne",
            "top_k" => args["top_k"] || 1,
            "as_of_ms" => args["as_of_ms"] || 20
          }),
          state
        )

      "inspect" ->
        {:ok,
         %{
           "api_version" => 1,
           "kind" => "host_call",
           "request" => %{
             "op" => "collection.store",
             "scope" => "project",
             "request" => %{"op" => "snapshot"}
           }
         }, Map.put(state, :inspect_step, :snapshot)}
    end
  end

  def handle(
        "host.actions",
        %{"outcome" => %{"status" => "ok", "value" => value}},
        %{mode: "inspect", inspect_step: :snapshot} = state
      ) do
    request =
      Map.merge(state.args["ref"], %{
        "op" => "stage.inspect",
        "generation" => value["result"]["generation"]
      })

    {:ok,
     %{
       "api_version" => 1,
       "kind" => "host_call",
       "request" => %{"op" => "collection.store", "scope" => "project", "request" => request}
     }, %{state | inspect_step: :done}}
  end

  def handle("host.actions", %{"outcome" => outcome}, %{mode: "inspect"} = state),
    do: finish(outcome, state)

  def handle("host.actions", %{"outcome" => outcome}, state),
    do: drive(Collection.resume(state.continuation, outcome), state)

  defp drive({:call, request, continuation}, state),
    do:
      {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request},
       Map.put(state, :continuation, continuation)}

  defp drive({:done, {:continue, value}}, state), do: finish(value, state)

  defp drive({:done, {:ok, snapshot}}, %{mode: "query"} = state) do
    {:ok, rank} =
      Evidence.rank_lexical(snapshot["sources"], state.args["query"] || "Nocturne", 1, 20)

    rank = Evidence.query_scope(rank, snapshot["sources"], [], 20)

    coverage = rank["coverage"] |> Map.delete("complete") |> Map.merge(snapshot["coverage"])

    value =
      rank
      |> Map.put("scope", "explicit_selected_sources")
      |> Map.put("coverage", coverage)
      |> Map.put("catalog_generation", snapshot["catalog_generation"])

    finish(value, state)
  end

  defp drive({:done, {:ok, snapshot}}, %{mode: "lexical"} = state) do
    runs =
      Enum.map(snapshot["runs"], fn entry ->
        run = entry["run"]

        summary =
          run
          |> Map.delete("terms")
          |> Map.put("term_count", length(run["terms"]))
          |> Map.put(
            "sample",
            Enum.filter(run["terms"], &(hd(&1) in ~w(approval evidence index)))
          )

        Map.put(entry, "run", summary)
      end)

    finish(Map.put(snapshot, "runs", runs), state)
  end

  defp drive({:done, {:ok, value}}, state), do: finish(value, state)

  defp drive({:done, {:error, code, _}}, state),
    do: finish(%{"status" => "refused", "code" => Atom.to_string(code)}, state)

  defp drive({:stop, :unknown_effect}, state), do: finish(%{"status" => "unknown"}, state)

  defp finish(value, state) do
    {:ok, reply} = Ipse.Extension.ResultPublication.prepare(value)
    {:ok, reply, state}
  end

  def source(generation, many, entries \\ 1600) do
    phrase =
      if generation == 1,
        do: "Nocturne migration needs review.",
        else: "Nocturne migration needs approval."

    paragraph = fn text -> "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>" end

    body =
      if many do
        Enum.map_join(1..24, fn n ->
          paragraph.(if(n == 24, do: phrase, else: "Paragraph #{n} has exact résumé context."))
        end) <> "<w:p><w:r><w:sym w:char=\"F0FC\"/></w:r></w:p>"
      else
        paragraph.(Enum.map_join(1..entries, " ", &"entry#{&1}") <> " " <> phrase)
      end

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
        ]
        |> Enum.map(fn {name, bytes} ->
          fixed = {{2000, 1, 1}, {0, 0, 0}}

          info =
            File.Stat.to_record(%File.Stat{
              size: byte_size(bytes),
              type: :regular,
              access: :read_write,
              atime: fixed,
              mtime: fixed,
              ctime: fixed,
              mode: 0o100644,
              links: 1,
              major_device: 0,
              minor_device: 0,
              inode: 0,
              uid: 0,
              gid: 0
            })

          {name, bytes, info}
        end),
        [:memory]
      )

    {:ok, extraction} = Documents.extract(bytes, "source.docx")
    {:ok, payload} = Documents.source_payload(extraction, 65_536)
    receipt = Evidence.document_storage_receipt!(payload["document"])

    attrs = %{
      "source_id" => "fixture:word",
      "partition" => "notes",
      "generation" => generation,
      "title" => "Synthetic Word source",
      "text" => payload["text"],
      "uri" => "provided:source.docx",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "documents",
        "partition_or_scope" => "notes",
        "receipt" => receipt,
        "historical" => false
      }
    }

    attrs =
      if receipt["version"] == 4, do: Map.put(attrs, "document", payload["document"]), else: attrs

    {:ok, source} = Evidence.source(attrs)
    source
  end

  defp tiny(id, generation, args) do
    {:ok, source} =
      Evidence.source(%{
        "source_id" => id,
        "partition" => "notes",
        "generation" => generation,
        "title" => "Catalog source",
        "text" => args["text"] || "Index evidence for #{id}.",
        "uri" => "provided:" <> id,
        "observed_at_ms" => args["observed_at_ms"] || 10,
        "event_at_ms" => nil,
        "expires_at_ms" => args["expires_at_ms"],
        "origin" => %{
          "kind" => "provided",
          "store_profile" => "documents",
          "partition_or_scope" => "notes",
          "receipt" => nil,
          "historical" => args["historical"] || false
        }
      })

    source
  end
end
