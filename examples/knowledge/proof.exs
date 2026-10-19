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
        "checks" => 11,
        "disabled_catalogs_empty" => true,
        "independent_catalogs" => true,
        "corpus" => "lexical/current/forget/recovery",
        "graph" => "explicit/current",
        "research" => "provided-only",
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

  defp prepare(artifacts, package, root, enabled \\ true) do
    artifact = Path.join(artifacts, package)
    home = Path.join(root, "home-" <> package)
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

  defp explicit_fact(raw, chunk_id) do
    quote = "Release requires quiescence."

    citation =
      Map.take(raw, ~w(source_id generation uri observed_at_ms event_at_ms))
      |> Map.merge(%{
        "version" => 1,
        "source_key" => sha(raw["source_id"]),
        "content_sha256" => sha(raw["text"]),
        "chunk_id" => chunk_id,
        "start_byte" => 0,
        "end_byte" => byte_size(quote),
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
          "Release",
          "requires",
          "quiescence",
          "positive",
          false,
          nil,
          nil,
          "explicit",
          nil,
          1,
          [identity]
        ]),
      "subject" => "Release",
      "predicate" => "requires",
      "object" => "quiescence",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => nil,
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
