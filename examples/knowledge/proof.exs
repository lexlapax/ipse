defmodule IpseKnowledgeExample.Proof do
  @moduledoc false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Config, Registry, Store}
  @text "Release requires quiescence. Quiescence requires worker exit."
  @at 1_700_000_020_000

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Explicit knowledge proof called the conversation model")
  end

  def run(artifacts) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    unloaded!()
    root = Path.join(System.tmp_dir!(), "ipse-knowledge-proof-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put(:knowledge_proof_sessions, [])

    try do
      corpus = prepare(artifacts, "corpus", root)
      graph = prepare(artifacts, "graph", root)
      research = prepare(artifacts, "research", root)

      for package <- ~w(corpus graph research) do
        disabled = prepare(artifacts, package, root, false)
        [] = disabled.extensions
        control = start(disabled, root, "disabled-" <> package)
        %{"version" => 1, "entries" => []} = Session.exports(control)
        true = Session.info(control).accounting["request_count"] == 0

        [] =
          Enum.filter(
            events(control, root, "disabled-" <> package),
            &(&1["type"] == "extension_action_intent")
          )

        :ok = Session.close_confirmed(control)
      end

      for {config, package} <- [{corpus, "corpus"}, {graph, "graph"}, {research, "research"}] do
        control = start(config, root, "catalog-" <> package)
        catalog = Session.exports(control)
        true = catalog["entries"] != []
        true = Enum.all?(catalog["entries"], &(&1["instance"] == package))
        true = Session.info(control).accounting["request_count"] == 0

        [] =
          Enum.filter(
            events(control, root, "catalog-" <> package),
            &(&1["type"] == "extension_action_intent")
          )

        :ok = Session.close_confirmed(control)
      end

      for config <- [corpus, graph, research] do
        false =
          Enum.any?(config.extensions, fn entry ->
            Enum.any?(
              ~w(host.embedding host.model host.mcp),
              &(&1 in entry.identity["capabilities"])
            )
          end)
      end

      cp = start(corpus, root, "corpus")

      "ok" =
        invoke(cp, "corpus", "source", source("put", source_args("manual:release")))["status"]

      query = %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "quiescence",
        "top_k" => 5,
        "as_of_ms" => @at
      }

      found = invoke(cp, "corpus", "query", query)
      "ok" = found["status"]
      [candidate] = found["evidence"]
      citation!(candidate["citation"], "manual:release", @text)
      true = found["coverage"]["revalidated"]

      current =
        invoke(cp, "corpus", "source", source("inspect", %{"source_id" => "manual:release"}))

      revision = current["coverage"]["revision"]
      true = is_integer(revision) and revision > 0

      "ok" =
        invoke(
          cp,
          "corpus",
          "source",
          source("forget", %{"source_id" => "manual:release", "expected_revision" => revision})
        )["status"]

      "abstain" = invoke(cp, "corpus", "query", query)["status"]

      "ok" =
        invoke(cp, "corpus", "source", source("put", source_args("manual:eligible")))["status"]

      for {name, extra} <- [
            {"expired", %{"expires_at_ms" => @at}},
            {"future", %{"observed_at_ms" => @at + 1}}
          ] do
        "ok" =
          invoke(
            cp,
            "corpus",
            "source",
            source("put", Map.merge(source_args("manual:" <> name), extra))
          )["status"]
      end

      eligible = invoke(cp, "corpus", "query", query)
      "ok" = eligible["status"]
      true = eligible["coverage"]["complete"] and length(eligible["coverage"]["exclusions"]) == 3
      [eligible_candidate] = eligible["evidence"]
      citation!(eligible_candidate["citation"], "manual:eligible", @text)

      missing =
        source_args("manual:pending")
        |> Map.delete("text")
        |> Map.merge(%{"content_sha256" => sha(@text), "byte_count" => byte_size(@text)})

      "draft" = invoke(cp, "corpus", "source", source("open", missing))["status"]
      partial = invoke(cp, "corpus", "query", query)
      "partial" = partial["status"]
      false = partial["coverage"]["complete"]
      partial_empty = invoke(cp, "corpus", "query", Map.put(query, "query", "absent mineral"))
      "partial" = partial_empty["status"]
      [] = partial_empty["evidence"]
      true = Enum.any?(partial_empty["gaps"], &(&1["code"] == "incomplete_source"))
      before = events(cp, root, "corpus")
      id = Session.info(cp).id
      :ok = Session.close(cp)
      resumed = start(corpus, root, "corpus", id)
      after_resume = events(resumed, root, "corpus")
      true = action_count(before) == action_count(after_resume)
      true = Session.info(resumed).accounting["request_count"] == 0
      :ok = Session.close(resumed)

      gp = start(graph, root, "graph")
      raw = source_args("manual:graph")
      "ok" = invoke(gp, "graph", "source", source("put", raw))["status"]

      inspected =
        invoke(gp, "graph", "source", source("inspect", %{"source_id" => "manual:graph"}))

      [chunk] = inspected["coverage"]["chunks"]
      fact = explicit_fact(raw, chunk["chunk_id"])

      "ok" =
        invoke(gp, "graph", "extract", %{
          "store" => "notes",
          "extraction" => "asserted",
          "source_id" => raw["source_id"],
          "generation" => 1,
          "max_edges" => 1,
          "chunks" => [chunk["chunk_id"]],
          "facts" => [fact]
        })["status"]

      path =
        invoke(gp, "graph", "query", %{
          "store" => "notes",
          "entity" => "Release",
          "depth" => 2,
          "max_nodes" => 8,
          "max_edges" => 8,
          "top_k" => 5,
          "as_of_ms" => @at
        })

      "ok" = path["status"]
      true = length(path["evidence"]) == 1 and path["coverage"]["revalidated"]
      citation!(hd(path["evidence"])["citation"], raw["source_id"], @text)
      true = Session.info(gp).accounting["request_count"] == 0
      events(gp, root, "graph")
      :ok = Session.close(gp)

      shared_home = Path.join(root, "home-bounded")

      bounded_profile = %{
        "kind" => "graph",
        "version" => 1,
        "lexical" => "words",
        "depth" => 2,
        "max_nodes" => 8,
        "max_edges" => 1
      }

      bounded_corpus =
        prepare(artifacts, "corpus", root, true, home: shared_home, retrieval: bounded_profile)

      bounded_graph = prepare(artifacts, "graph", root, true, home: shared_home)

      bounded_config = %{
        bounded_corpus
        | extensions: bounded_corpus.extensions ++ bounded_graph.extensions
      }

      bp = start(bounded_config, root, "bounded")
      raw = source_args("manual:bounded")
      "ok" = invoke(bp, "corpus", "source", source("put", raw))["status"]

      [bounded_chunk] =
        invoke(bp, "corpus", "source", source("inspect", %{"source_id" => raw["source_id"]}))[
          "coverage"
        ]["chunks"]

      fact_expiry = System.system_time(:millisecond) + 86_400_000

      facts = [
        explicit_fact(
          raw,
          bounded_chunk["chunk_id"],
          "Release",
          "quiescence",
          0,
          byte_size("Release requires quiescence."),
          fact_expiry
        ),
        explicit_fact(
          raw,
          bounded_chunk["chunk_id"],
          "Quiescence",
          "worker exit",
          byte_size("Release requires quiescence. "),
          byte_size(@text),
          fact_expiry
        )
      ]

      "ok" =
        invoke(bp, "graph", "extract", %{
          "store" => "notes",
          "extraction" => "asserted",
          "source_id" => raw["source_id"],
          "generation" => 1,
          "max_edges" => 2,
          "chunks" => [bounded_chunk["chunk_id"]],
          "facts" => facts
        })["status"]

      bounded =
        invoke(bp, "corpus", "query", %{query | "retrieval" => "bounded", "query" => "Release"})

      "partial" = bounded["status"]
      false = bounded["coverage"]["complete"]
      false = bounded["coverage"]["components"]["graph"]["complete"]
      true = bounded["evidence"] != [] and bounded["coverage"]["revalidated"]

      direct_args = %{
        "store" => "notes",
        "entity" => "Release",
        "depth" => 2,
        "max_nodes" => 8,
        "max_edges" => 1,
        "top_k" => 5,
        "as_of_ms" => @at
      }

      direct_bounded = invoke(bp, "graph", "query", direct_args)
      "partial" = direct_bounded["status"]
      false = direct_bounded["coverage"]["complete"]

      "ok" =
        invoke(bp, "corpus", "source", source("put", source_args("manual:graph-forgotten")))[
          "status"
        ]

      forgotten =
        invoke(
          bp,
          "corpus",
          "source",
          source("inspect", %{"source_id" => "manual:graph-forgotten"})
        )["coverage"]

      "ok" =
        invoke(
          bp,
          "corpus",
          "source",
          source("forget", %{
            "source_id" => "manual:graph-forgotten",
            "expected_revision" => forgotten["revision"]
          })
        )["status"]

      direct_current = invoke(bp, "graph", "query", %{direct_args | "max_edges" => 8})
      "ok" = direct_current["status"]
      true = direct_current["coverage"]["complete"]
      true = Enum.any?(direct_current["coverage"]["exclusions"], &(&1["code"] == "suppressed"))

      direct_expired =
        invoke(bp, "graph", "query", %{direct_args | "max_edges" => 8, "as_of_ms" => fact_expiry})

      "abstain" = direct_expired["status"]
      [] = direct_expired["evidence"]
      true = direct_expired["coverage"]["complete"]
      2 = Enum.count(direct_expired["coverage"]["exclusions"], &(&1["code"] == "excluded_fact"))

      graph_pending =
        source_args("manual:graph-pending")
        |> Map.delete("text")
        |> Map.merge(%{"content_sha256" => sha(@text), "byte_count" => byte_size(@text)})

      "draft" = invoke(bp, "corpus", "source", source("open", graph_pending))["status"]

      direct_empty =
        invoke(bp, "graph", "query", %{direct_args | "entity" => "absent", "max_edges" => 8})

      "partial" = direct_empty["status"]
      [] = direct_empty["evidence"]
      false = direct_empty["coverage"]["complete"]
      true = Session.info(bp).accounting["request_count"] == 0
      :ok = Session.close_confirmed(bp)

      rp = start(research, root, "research")
      supplied = Map.delete(source_args("provided:release"), "expected_revision")

      answer =
        invoke(rp, "research", "investigate", %{
          "search" => "given",
          "fetch" => "given",
          "retrieval" => "words",
          "rerank" => nil,
          "query" => "quiescence",
          "limits" => %{"max_sources" => 1, "max_body_bytes" => 1024, "timeout_ms" => 5000},
          "sources" => [supplied]
        })

      "ok" = answer["status"]
      true = length(answer["evidence"]) == 1
      citation!(hd(answer["evidence"])["citation"], supplied["source_id"], @text)
      false = answer["coverage"]["native_ledger"]
      true = Session.info(rp).accounting["request_count"] == 0
      [] = Enum.filter(events(rp, root, "research"), &(&1["type"] == "extension_action_intent"))
      :ok = Session.close(rp)
      unloaded!()

      %{
        "checks" => 16,
        "disabled_catalogs_empty" => true,
        "independent_catalogs" => true,
        "corpus" => "lexical/current/forget/recovery",
        "graph" => "explicit/current",
        "research" => "provided-only",
        "policy_exclusions_retained" => true,
        "incomplete_empty_is_partial" => true,
        "fused_graph_bound_is_partial" => true,
        "direct_graph_scope_matches" => true,
        "expired_facts_excluded" => true,
        "model_requests" => 0,
        "host_loaded_domain_modules" => false
      }
    after
      for pid <- Process.get(:knowledge_proof_sessions, []),
          Process.alive?(pid),
          do: :ok = Session.close(pid)

      File.rm_rf!(root)
    end
  end

  defp prepare(artifacts, package, root, enabled \\ true, overrides \\ []) do
    artifact = Path.join(artifacts, package)
    home = Keyword.get(overrides, :home, Path.join(root, "home-" <> package))
    {:ok, imported} = Store.import(artifact, Path.join(home, "extensions/artifacts"))
    manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))
    "ipse-knowledge/" <> ^package = manifest["id"]
    options_path = Path.expand("../../extensions/knowledge/options/", __DIR__)

    file =
      case package do
        "corpus" -> "corpus-lexical.json"
        "graph" -> "graph-explicit.json"
        "research" -> "research-offline.json"
      end

    options = Jason.decode!(File.read!(Path.join(options_path, file)))

    options =
      if overrides[:retrieval],
        do: put_in(options, ["retrieval", "bounded"], overrides[:retrieval]),
        else: options

    trust = %{
      "artifact" => imported.digest,
      "capabilities" => manifest["capabilities"],
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
              "id" => "knowledge-proof",
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
            "enabled" => enabled,
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
      extensions: entries,
      compact: false
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
         state_dir: Path.join(root, "sessions-" <> package),
         id: id,
         subscriber: self(),
         owner: self()}
      )

    Process.put(:knowledge_proof_sessions, [pid | Process.get(:knowledge_proof_sessions)])
    pid
  end

  defp invoke(pid, package, command, arguments) do
    :ok = Session.invoke_export(pid, :command, "ext__" <> package <> "__" <> command, arguments)
    wait(pid, System.monotonic_time(:millisecond) + 30_000)
    Session.info(pid).extension_result["value"]
  end

  defp wait(pid, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:ipse, ^pid, {:approval, ref, name, proposed}} ->
        true = name in ~w(extension:state.put extension:state.delete)
        true = is_map(proposed["request"])
        :ok = Session.approve(pid, ref, true)
        wait(pid, deadline)

      {:ipse, ^pid, {:done, :ok}} ->
        :ok

      {:ipse, ^pid, {:done, other}} ->
        raise "Knowledge command failed: #{inspect(other)}"

      {:ipse, ^pid, _} ->
        wait(pid, deadline)
    after
      remaining -> raise "Knowledge command exceeded proof deadline"
    end
  end

  defp source(action, args), do: %{"store" => "notes", "action" => action, "args" => args}

  defp source_args(id),
    do: %{
      "source_id" => id,
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Release",
      "text" => @text,
      "uri" => "fixture:release",
      "observed_at_ms" => @at - 1000,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

  defp sha(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp domain_id(tag, parts),
    do: sha(IO.iodata_to_binary(JSON.encode!(["ipse-knowledge", 1, tag, parts])))

  defp explicit_fact(
         raw,
         chunk_id,
         subject \\ "Release",
         object \\ "quiescence",
         first \\ 0,
         last \\ byte_size("Release requires quiescence."),
         valid_to \\ nil
       ) do
    quote = binary_part(raw["text"], first, last - first)

    citation =
      Map.take(raw, ~w(source_id generation uri observed_at_ms event_at_ms))
      |> Map.merge(%{
        "version" => 1,
        "source_key" => sha(raw["source_id"]),
        "content_sha256" => sha(raw["text"]),
        "chunk_id" => chunk_id,
        "start_byte" => first,
        "end_byte" => last,
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

    %{
      "version" => 1,
      "fact_id" =>
        domain_id("fact", [
          subject,
          "requires",
          object,
          "positive",
          false,
          nil,
          valid_to,
          "explicit",
          nil,
          1,
          [identity]
        ]),
      "subject" => subject,
      "predicate" => "requires",
      "object" => object,
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => valid_to,
      "extraction" => %{"kind" => "explicit", "profile" => nil, "version" => 1},
      "citations" => [citation]
    }
  end

  defp citation!(citation, source_id, text) do
    ^source_id = citation["source_id"]
    true = citation["generation"] == 1 and citation["content_sha256"] == sha(text)

    quote =
      binary_part(text, citation["start_byte"], citation["end_byte"] - citation["start_byte"])

    ^quote = citation["quote"]
    true = String.valid?(quote) and citation["quote_sha256"] == sha(quote)
    :ok
  end

  defp events(pid, root, package) do
    {:ok, events} = Journal.load(Path.join(root, "sessions-" <> package), Session.info(pid).id)
    {:ok, _} = Session.restore_context(events)
    events
  end

  defp action_count(events), do: Enum.count(events, &(&1["type"] == "extension_action_intent"))

  defp unloaded! do
    for module <- [
          IpseKnowledge.Corpus,
          IpseKnowledge.Graph,
          IpseKnowledge.Research,
          IpseKnowledge.Adapters,
          IpseKnowledge.Evidence,
          IpseKnowledge.Profiles,
          IpseKnowledge.Store,
          IpseKnowledge.Store.State,
          IpseKnowledge.Store.MCPCAS
        ],
        do: false = :code.is_loaded(module)
  end
end
