defmodule IpseKnowledgeExample.CompleteResultProof do
  @moduledoc false
  alias Ipse.{Journal, Session}
  alias Ipse.Extensions.{Config, Invocation, Registry, ResultReader, Store}

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Complete-result proof unexpectedly called a model")
  end

  def run(artifacts) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    unloaded!()
    root = Path.join(System.tmp_dir!(), "ipse-knowledge-complete-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put(:complete_result_sessions, [])

    try do
      configs = Map.new(~w(corpus graph research), &{&1, prepare(artifacts, &1, root)})
      research = start(configs["research"], root, "research")
      quote = "Lock " <> String.duplicate("x", 1019)
      sources = Enum.map(1..10, &raw("s#{&1}", quote))
      full = invoke(research, "research", "investigate", investigation(sources))
      true = byte_size(full.bytes) > 12_000
      true = full.value["status"] == "ok" and length(full.value["evidence"]) == 10
      expected = Map.new(sources, &{&1["source_id"], &1})
      Enum.each(full.value["evidence"], &citation!(&1["citation"], expected))
      true = Enum.all?(full.value["evidence"], &(&1["citation"]["quote"] == quote))

      true =
        full.value["claims"] == [
          %{
            "label" => "open",
            "evidence_indexes" => Enum.to_list(0..9),
            "uncertainty" => "semantic_support_unassessed"
          }
        ]

      escaped_quote = "Lock " <> String.duplicate(<<1>>, 1019)

      escaped_sources = [
        raw("escaped", escaped_quote)
        | Enum.map(1..9, &raw("short#{&1}", "Lock " <> String.duplicate("z", 80)))
      ]

      escaped = invoke(research, "research", "investigate", investigation(escaped_sources))
      true = byte_size(escaped.bytes) > 12_000

      citation =
        Enum.find(escaped.value["evidence"], &(&1["citation"]["source_id"] == "escaped"))[
          "citation"
        ]

      ^escaped_quote = citation["quote"]
      encoded_citation = Jason.encode!(citation)
      true = byte_size(encoded_citation) > 4096
      {position, size} = :binary.match(escaped.bytes, encoded_citation)
      true = div(position, 4096) != div(position + size - 1, 4096)

      Enum.each(
        escaped.value["evidence"],
        &citation!(
          &1["citation"],
          Map.new(escaped_sources, fn source -> {source["source_id"], source} end)
        )
      )

      research_id = Session.info(research).id
      research_path = journal_path(root, "research", research_id)
      research_sha = sha(File.read!(research_path))
      :ok = Session.close_confirmed(research)
      resumed = start(configs["research"], root, "research", research_id)
      {:ok, historical} = Session.materialize_result(resumed, full.delivery)
      true = historical.bytes == full.bytes and historical.value == full.value

      {:ok, offline} =
        ResultReader.saved(
          state_dir(root, "research"),
          research_id,
          escaped.delivery["output_id"]
        )

      true = offline.bytes == escaped.bytes and offline.value == escaped.value
      :ok = Session.close_confirmed(resumed)
      ^research_sha = sha(File.read!(research_path))

      corpus = start(configs["corpus"], root, "corpus")

      Enum.each(sources, fn source ->
        result =
          invoke(
            corpus,
            "corpus",
            "source",
            source_command("put", Map.put(source, "expected_revision", 0))
          )

        "ok" = result.value["status"]
      end)

      corpus_result =
        invoke(corpus, "corpus", "query", %{
          "store" => "notes",
          "retrieval" => "words",
          "rerank" => nil,
          "query" => "lock",
          "top_k" => 10,
          "as_of_ms" => 20
        })

      true =
        byte_size(corpus_result.bytes) > 12_000 and length(corpus_result.value["evidence"]) == 10

      true = corpus_result.value["coverage"]["revalidated"]
      Enum.each(corpus_result.value["evidence"], &citation!(&1["citation"], expected))
      :ok = Session.close_confirmed(corpus)

      graph = start(configs["graph"], root, "graph")

      graph_sources =
        Enum.map(1..8, fn n ->
          raw("graph#{n}", "Release " <> String.duplicate(Integer.to_string(n), 1016))
        end)

      facts =
        Enum.map(Enum.with_index(graph_sources), fn {source, index} ->
          "ok" =
            invoke(
              graph,
              "graph",
              "source",
              source_command("put", Map.put(source, "expected_revision", 0))
            ).value["status"]

          inspected =
            invoke(
              graph,
              "graph",
              "source",
              source_command("inspect", %{"source_id" => source["source_id"]})
            )

          [chunk] = inspected.value["coverage"]["chunks"]
          fact = fact(source, chunk["chunk_id"], 0, "step" <> Integer.to_string(index))

          extraction =
            invoke(graph, "graph", "extract", %{
              "store" => "notes",
              "extraction" => "asserted",
              "source_id" => source["source_id"],
              "generation" => 1,
              "max_edges" => 1,
              "chunks" => [chunk["chunk_id"]],
              "facts" => [fact]
            })

          unless extraction.value["status"] == "ok",
            do:
              raise(
                "Graph extraction refused: " <>
                  inspect(Map.take(extraction.value, ~w(status gaps coverage)))
              )

          fact
        end)

      graph_result =
        invoke(graph, "graph", "query", %{
          "store" => "notes",
          "entity" => "Release",
          "depth" => 1,
          "max_nodes" => 16,
          "max_edges" => 8,
          "top_k" => 1,
          "as_of_ms" => 20
        })

      true = byte_size(graph_result.bytes) > 12_000
      1 = length(graph_result.value["evidence"])
      8 = length(graph_result.value["claims"])
      actual_basis = Map.new(graph_result.value["claims"], &{&1["fact_id"], &1["basis"]})
      true = actual_basis == Map.new(facts, &{&1["fact_id"], &1["citations"]})
      visible = hd(graph_result.value["evidence"])["citation"]
      true = Enum.any?(Map.values(actual_basis), &(&1 != [visible]))

      graph_expected = Map.new(graph_sources, &{&1["source_id"], &1})
      Enum.each(List.flatten(Map.values(actual_basis)), &citation!(&1, graph_expected))

      positive_text = "Pair requires lock."
      negative_text = "Pair does not require lock."
      pair = raw("pair", positive_text <> " " <> negative_text)

      "ok" =
        invoke(
          graph,
          "graph",
          "source",
          source_command("put", Map.put(pair, "expected_revision", 0))
        ).value["status"]

      [pair_chunk] =
        invoke(graph, "graph", "source", source_command("inspect", %{"source_id" => "pair"})).value[
          "coverage"
        ]["chunks"]

      pair_facts = [
        fact(pair, pair_chunk["chunk_id"], 0, "lock",
          subject: "Pair",
          length: byte_size(positive_text)
        ),
        fact(pair, pair_chunk["chunk_id"], byte_size(positive_text) + 1, "lock",
          subject: "Pair",
          length: byte_size(negative_text),
          polarity: "negative"
        )
      ]

      "ok" =
        invoke(graph, "graph", "extract", %{
          "store" => "notes",
          "extraction" => "asserted",
          "source_id" => "pair",
          "generation" => 1,
          "max_edges" => 2,
          "chunks" => [pair_chunk["chunk_id"]],
          "facts" => pair_facts
        }).value["status"]

      conflict =
        invoke(graph, "graph", "query", %{
          "store" => "notes",
          "entity" => "Pair",
          "depth" => 1,
          "max_nodes" => 8,
          "max_edges" => 8,
          "top_k" => 1,
          "as_of_ms" => 20
        })

      conflict!(conflict.value, pair_facts, pair, conflict.value["coverage"])

      paths = %{
        "kind" => "graph",
        "version" => 1,
        "lexical" => "words",
        "depth" => 1,
        "max_nodes" => 8,
        "max_edges" => 8
      }

      shared = prepare(artifacts, "corpus", root, home: configs["graph"].home, retrieval: paths)
      corpus_graph = start(shared, root, "graph")

      same_conflict =
        invoke(corpus_graph, "corpus", "query", %{
          "store" => "notes",
          "retrieval" => "paths",
          "rerank" => nil,
          "query" => "Pair",
          "top_k" => 1,
          "as_of_ms" => 20
        })

      conflict!(
        same_conflict.value,
        pair_facts,
        pair,
        same_conflict.value["coverage"]["components"]["graph"]
      )

      :ok = Session.close_confirmed(corpus_graph)
      :ok = Session.close_confirmed(graph)
      unloaded!()

      %{
        "checks" => 5,
        "research_bytes" => byte_size(full.bytes),
        "research_evidence" => 10,
        "escaped_citation_bytes" => byte_size(encoded_citation),
        "citation_crosses_fragment" => true,
        "corpus_bytes" => byte_size(corpus_result.bytes),
        "corpus_evidence" => 10,
        "graph_bytes" => byte_size(graph_result.bytes),
        "graph_evidence" => 1,
        "graph_claims" => 8,
        "unranked_claim_bases_preserved" => true,
        "opposing_assertions_preserved" => true,
        "corpus_graph_conflict" => true,
        "complete_hashes_verified" => true,
        "historical_reads_exact" => true,
        "resume_inert" => true,
        "journal_unchanged" => true,
        "model_requests" => 0,
        "host_loaded_domain_modules" => false,
        "cleanup" => "confirmed"
      }
    after
      for pid <- Process.get(:complete_result_sessions),
          Process.alive?(pid),
          do: :ok = Session.close_confirmed(pid)

      File.rm_rf!(root)
    end
  end

  defp prepare(artifacts, package, root, overrides \\ []) do
    home = Keyword.get(overrides, :home, Path.join(root, "home-" <> package))

    {:ok, imported} =
      Store.import(Path.join(artifacts, package), Path.join(home, "extensions/artifacts"))

    2 = imported.manifest["sdk"]
    true = "invoke.result.pages" in imported.manifest["capabilities"]

    option_file =
      %{
        "corpus" => "corpus-lexical",
        "graph" => "graph-explicit",
        "research" => "research-offline"
      }[package]

    options =
      Jason.decode!(
        File.read!(
          Path.expand("../../extensions/knowledge/options/" <> option_file <> ".json", __DIR__)
        )
      )

    options =
      if overrides[:retrieval],
        do: put_in(options, ["retrieval", "paths"], overrides[:retrieval]),
        else: options

    trust = %{
      "artifact" => imported.digest,
      "capabilities" => imported.manifest["capabilities"],
      "allow_project" => false,
      "allow_children" => false
    }

    trust =
      if package == "research",
        do: trust,
        else:
          Map.put(trust, "state_bindings", [
            %{
              "version" => 1,
              "instance" => package,
              "id" => "complete-proof",
              "scopes" => ["project"]
            }
          ])

    source = %{
      scope: "operator",
      path: Path.join(root, package <> ".json"),
      data: %{
        "extensions" => [
          %{
            "instance" => package,
            "artifact" => imported.digest,
            "enabled" => true,
            "options" => options,
            "order" => 0,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [trust]
      }
    }

    {:ok, selected} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selected, home)

    %{
      provider: :demo,
      model: "unused",
      provider_module: NoModel,
      home: home,
      operator_home: nil,
      approval: :ask,
      compact: false,
      extensions: entries
    }
  end

  defp start(config, root, package, id \\ nil) do
    cwd = Path.join(root, "workspace-" <> package)
    File.mkdir_p!(cwd)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config,
         cwd: cwd,
         state_dir: state_dir(root, package),
         id: id,
         subscriber: self(),
         owner: self()}
      )

    Process.put(:complete_result_sessions, [pid | Process.get(:complete_result_sessions)])
    Process.put({:complete_state_dir, pid}, state_dir(root, package))
    pid
  end

  defp invoke(pid, package, command, arguments) do
    :ok = Session.invoke_export(pid, :command, "ext__" <> package <> "__" <> command, arguments)
    wait(pid, System.monotonic_time(:millisecond) + 60_000)
    info = Session.info(pid)
    0 = info.accounting["request_count"]
    result = info.extension_result

    materialized =
      case result do
        %{"delivery" => delivery} ->
          {:ok, value} = Session.materialize_result(pid, delivery)

          true =
            byte_size(value.bytes) == delivery["byte_count"] and
              sha(value.bytes) == delivery["sha256"]

          Map.put(value, :delivery, delivery)

        %{"value" => value} ->
          %{value: value, bytes: Jason.encode!(value), delivery: nil}
      end

    {:ok, events} = Journal.load(state_dir_from_info(pid), info.id)
    :ok = Invocation.validate_events(events)
    materialized
  end

  defp state_dir_from_info(pid), do: Process.get({:complete_state_dir, pid})

  defp wait(pid, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}} ->
        true = is_map(proposed["request"])
        :ok = Session.approve(pid, ref, true)
        wait(pid, deadline)

      {:ipse, ^pid, {:done, :ok}} ->
        :ok

      {:ipse, ^pid, {:done, other}} ->
        raise "Complete-result invocation failed: #{inspect(other)}"

      {:ipse, ^pid, _} ->
        wait(pid, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        raise "Complete-result proof deadline exceeded"
    end
  end

  defp raw(id, text),
    do: %{
      "source_id" => id,
      "generation" => 1,
      "title" => "Locks",
      "text" => text,
      "uri" => "local:" <> id,
      "observed_at_ms" => 1,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

  defp source_command(action, args), do: %{"store" => "notes", "action" => action, "args" => args}

  defp investigation(sources),
    do: %{
      "search" => "given",
      "fetch" => "given",
      "retrieval" => "words",
      "rerank" => nil,
      "query" => "lock",
      "as_of_ms" => 20,
      "limits" => %{"max_sources" => 10, "max_body_bytes" => 16_384, "timeout_ms" => 5000},
      "sources" => sources
    }

  defp state_dir(root, package), do: Path.join(root, "sessions-" <> package)
  defp journal_path(root, package, id), do: Path.join(state_dir(root, package), id <> ".jsonl")
  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp citation!(citation, sources) do
    source = Map.fetch!(sources, citation["source_id"])

    quote =
      binary_part(
        source["text"],
        citation["start_byte"],
        citation["end_byte"] - citation["start_byte"]
      )

    true =
      quote == citation["quote"] and sha(quote) == citation["quote_sha256"] and
        sha(source["text"]) == citation["content_sha256"] and citation["generation"] == 1

    true = citation["origin"]["kind"] == "provided" and not citation["origin"]["historical"]
  end

  defp fact(raw, chunk_id, first, object, options \\ []) do
    length = Keyword.get(options, :length, 1024)
    subject = Keyword.get(options, :subject, "Release")
    polarity = Keyword.get(options, :polarity, "positive")
    quote = binary_part(raw["text"], first, length)

    citation =
      Map.take(raw, ~w(source_id generation uri observed_at_ms event_at_ms))
      |> Map.merge(%{
        "version" => 1,
        "source_key" => sha(raw["source_id"]),
        "content_sha256" => sha(raw["text"]),
        "chunk_id" => chunk_id,
        "start_byte" => first,
        "end_byte" => first + length,
        "quote" => quote,
        "quote_sha256" => sha(quote),
        "origin" => %{
          "kind" => "provided",
          "store_profile" => "notes",
          "partition_or_scope" => "manual",
          "receipt" => nil,
          "historical" => false
        }
      })

    identity =
      Enum.map(
        ~w(source_key generation content_sha256 chunk_id start_byte end_byte quote_sha256),
        &citation[&1]
      )

    id =
      sha(
        JSON.encode!([
          "ipse-knowledge",
          1,
          "fact",
          [
            subject,
            "requires",
            object,
            polarity,
            false,
            nil,
            nil,
            "explicit",
            nil,
            1,
            [identity]
          ]
        ])
      )

    %{
      "version" => 1,
      "fact_id" => id,
      "subject" => subject,
      "predicate" => "requires",
      "object" => object,
      "polarity" => polarity,
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => nil,
      "extraction" => %{"kind" => "explicit", "profile" => nil, "version" => 1},
      "citations" => [citation]
    }
  end

  defp conflict!(value, facts, source, coverage) do
    1 = length(value["evidence"])

    true =
      coverage["edges"] == 1 and coverage["context_facts"] == 2 and
        coverage["counterassertions"] == 1

    claims = Enum.filter(value["claims"], &Map.has_key?(&1, "fact_id"))
    true = Enum.sort(Enum.map(claims, & &1["polarity"])) == ~w(negative positive)
    true = Enum.all?(claims, &(&1["label"] == "conflict"))

    true =
      Map.new(claims, &{&1["fact_id"], &1["basis"]}) ==
        Map.new(facts, &{&1["fact_id"], &1["citations"]})

    Enum.each(claims, fn claim ->
      Enum.each(claim["basis"], &citation!(&1, %{source["source_id"] => source}))
    end)
  end

  defp unloaded!,
    do:
      Enum.each(
        [
          IpseKnowledge.Corpus,
          IpseKnowledge.Graph,
          IpseKnowledge.Research,
          IpseKnowledge.Evidence,
          IpseKnowledge.Store
        ],
        &(false = :code.is_loaded(&1))
      )
end
