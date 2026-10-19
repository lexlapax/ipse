Code.require_file("evaluation_session.exs", __DIR__)

Code.require_file("../../test/support/knowledge_mcp_fixture.exs", __DIR__)

defmodule IpseKnowledgeExample.ResearchProof do
  @moduledoc false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Config, Registry, Store}
  alias IpseKnowledge.Test.CASFixture, as: Fixture
  @query "quiescence"
  @uri "fixture:release"

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Research transport proof called a model")
  end

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-research-proof-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    {:ok, backend} = Fixture.start_backend("notes")
    Process.put(:knowledge_research_sessions, [])
    text = "Release requires quiescence.\n" <> String.duplicate("Unrelated rehearsal.\n", 340)

    try do
      :ok =
        Fixture.configure_web_backend(backend, %{
          "searches" => %{
            @query => [
              %{
                "source_id" => "manual:release",
                "uri" => @uri,
                "title" => "Release manual",
                "snippet" => "Release requires quiescence."
              }
            ],
            "no matches" => []
          },
          "pages" => %{
            @uri => %{
              "text" => text,
              "observed_uri" => "fixture:captured-release",
              "media_type" => "text/plain",
              "observed_at_ms" => 1
            }
          }
        })

      config = config(artifact, root, backend, "normal")
      pid = start(config, root)
      {:ok, value} = invoke(pid, arguments())
      "ok" = value["status"]
      true = value["coverage"]["source_count"] == 1
      false = value["coverage"]["native_ledger"]
      [candidate] = value["evidence"]
      citation = candidate["citation"]
      "manual:release" = citation["source_id"]
      true = citation["content_sha256"] == sha(text)

      true =
        binary_part(text, citation["start_byte"], citation["end_byte"] - citation["start_byte"]) ==
          citation["quote"]

      "fetch" = citation["origin"]["kind"]
      receipt = citation["origin"]["receipt"]
      @uri = receipt["requested_uri"]
      "fixture:captured-release" = receipt["observed_uri"]
      true = receipt["body_sha256"] == sha(text)
      true = receipt["descriptor"]["operation_id"] =~ ~r/\A[0-9a-f]{32}\z/
      [search, fetch] = web_calls(backend)
      true = search["tool"] == "search" and fetch["tool"] == "fetch"
      true = action_count(events(pid, root), "effect.result.read") >= 3
      true = Session.info(pid).accounting["request_count"] == 0

      for {at, expected} <- [{0, "abstain"}, {1, "ok"}] do
        {:ok, fixed} = invoke(pid, Map.put(arguments(), "as_of_ms", at))
        true = fixed["status"] == expected
        true = fixed["coverage"]["as_of_ms"] == at
      end

      before = web_calls(backend)
      {:ok, %{"status" => "refused", "evidence" => []}} = invoke(pid, arguments(), :deny)
      true = web_calls(backend) == before

      {:ok, %{"status" => "refused", "evidence" => []}} = invoke(pid, arguments(), :deny_fetch)
      true = length(web_calls(backend)) == length(before) + 1
      "search" = List.last(web_calls(backend))["tool"]
      :ok = Session.close_confirmed(pid)

      for mode <-
            ~w(search_partial search_forged_hit search_refused fetch_partial fetch_changed_body fetch_forged_hash fetch_wrong_uri) do
        rejected = start(config(artifact, root, backend, mode), root)
        {:ok, %{"status" => "refused", "evidence" => []}} = invoke(rejected, arguments())
        true = Session.info(rejected).accounting["request_count"] == 0
        :ok = Session.close_confirmed(rejected)
      end

      future = start(config(artifact, root, backend, "fetch_future"), root)
      {:ok, %{"status" => "abstain", "evidence" => []}} = invoke(future, arguments())
      :ok = Session.close_confirmed(future)

      current = start(config(artifact, root, backend, "fetch_current"), root)
      {:ok, current_value} = invoke(current, arguments())
      "ok" = current_value["status"]
      [current_candidate] = current_value["evidence"]

      true =
        current_candidate["citation"]["observed_at_ms"] <= current_value["coverage"]["as_of_ms"]

      :ok = Session.close_confirmed(current)

      empty = start(config, root)
      before = web_calls(backend)
      {:ok, %{"status" => "abstain", "evidence" => []}} = invoke(empty, arguments("no matches"))
      true = length(web_calls(backend)) == length(before) + 1
      "search" = List.last(web_calls(backend))["tool"]
      :ok = Session.close_confirmed(empty)

      for mode <- ~w(disconnect_after_search disconnect_after_fetch) do
        unknown_config = config(artifact, root, backend, mode)
        unknown = start(unknown_config, root)
        {:error, _} = invoke(unknown, arguments())
        unknown_events = events(unknown, root)

        true =
          Enum.any?(
            unknown_events,
            &(&1["type"] == "extension_action_result" and &1["outcome"]["status"] == "unknown")
          )

        id = Session.info(unknown).id
        :ok = Session.close_confirmed(unknown)
        before = web_calls(backend)
        resumed = start(unknown_config, root, id)
        :idle = Session.info(resumed).phase
        true = web_calls(backend) == before
        true = action_count(events(resumed, root)) == action_count(unknown_events)
        :ok = Session.close_confirmed(resumed)
      end

      for module <- [
            IpseKnowledge.Research,
            IpseKnowledge.Evidence,
            IpseKnowledge.Profiles,
            IpseKnowledge.Adapters
          ],
          do: false = :code.is_loaded(module)

      %{
        "checks" => 17,
        "fixed_as_of" => true,
        "native_fetch_citations" => true,
        "paged_body" => true,
        "denied_dispatches" => 0,
        "unknown_replayed" => false,
        "model_requests" => 0,
        "host_loaded_domain_modules" => false
      }
    after
      for pid <- Process.get(:knowledge_research_sessions, []),
          Process.alive?(pid),
          do: :ok = Session.close_confirmed(pid)

      :ok = Fixture.stop_backend(backend)
      File.rm_rf!(root)
    end
  end

  defp config(artifact, root, backend, mode) do
    home = Path.join(root, "home")
    {:ok, imported} = Store.import(artifact, Path.join(home, "extensions/artifacts"))
    manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))

    options = %{
      "version" => 1,
      "stores" => %{},
      "search" => %{
        "web" => %{"kind" => "mcp", "binding" => "search_web", "contract" => "search-v1"}
      },
      "fetch" => %{
        "web" => %{"kind" => "mcp", "binding" => "fetch_web", "contract" => "fetch-v1"}
      },
      "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
      "embedding" => %{},
      "rerank" => %{},
      "extraction" => %{}
    }

    source = %{
      scope: "operator",
      path: Path.join(root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => "research",
            "artifact" => imported.digest,
            "enabled" => true,
            "options" => options,
            "order" => 0,
            "lifetime" => "persistent"
          }
        ],
        "extension_trust" => [
          %{
            "artifact" => imported.digest,
            "capabilities" => manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false,
            "mcp_bindings" => [
              %{
                "instance" => "research",
                "alias" => "search_web",
                "tool" => "mcp__knowledge_cas__search"
              },
              %{
                "instance" => "research",
                "alias" => "fetch_web",
                "tool" => "mcp__knowledge_cas__fetch"
              }
            ]
          }
        ]
      }
    }

    {:ok, selections} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selections, home)
    path = Path.join(root, "mcp-" <> mode <> ".json")

    File.write!(
      path,
      Jason.encode!(%{"servers" => [Fixture.web_stdio_config("notes", mode, backend.port)]})
    )

    {:ok, [server]} = Ipse.MCP.Config.load(path)

    %{
      provider: :demo,
      model: "unused",
      provider_module: NoModel,
      home: home,
      operator_home: nil,
      compact: false,
      approval: :ask,
      extensions: entries,
      mcp_servers: [server]
    }
  end

  defp start(config, root, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config,
         cwd: root,
         state_dir: Path.join(root, "sessions"),
         id: id,
         owner: self(),
         subscriber: self()}
      )

    Process.put(:knowledge_research_sessions, [pid | Process.get(:knowledge_research_sessions)])
    pid
  end

  defp invoke(pid, args, decision \\ :approve) do
    :ok = Session.invoke_export(pid, :command, "ext__research__investigate", args)
    status = wait(pid, args, decision, System.monotonic_time(:millisecond) + 60_000)

    if status == :ok do
      {:ok, value, _proof} =
        IpseKnowledgeExample.EvaluationSession.complete_result(
          pid,
          Session.info(pid).extension_result
        )

      {status, value}
    else
      {status, nil}
    end
  end

  defp wait(pid, args, decision, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:ipse, ^pid, {:approval, ref, "extension:mcp.call", proposed}} ->
        request = proposed["request"]
        binding = request["binding"]
        true = binding in ~w(search_web fetch_web)

        {tool, expected} =
          if binding == "search_web",
            do:
              {"search",
               %{
                 "version" => 1,
                 "contract" => "search-v1",
                 "query" => args["query"],
                 "limit" => args["limits"]["max_sources"]
               }},
            else: {"fetch", %{"version" => 1, "contract" => "fetch-v1", "uri" => @uri}}

        true = request["arguments"] == expected
        true = proposed["effect_binding"]["manifest"]["tool_id"] == "mcp__knowledge_cas__" <> tool
        approve = decision != :deny and not (decision == :deny_fetch and tool == "fetch")
        :ok = Session.approve(pid, ref, approve)
        wait(pid, args, decision, deadline)

      {:ipse, ^pid, {:approval, _, name, _}} ->
        raise("Unselected Research approval: " <> name)

      {:ipse, ^pid, {:done, status}} ->
        status

      {:ipse, ^pid, _} ->
        wait(pid, args, decision, deadline)
    after
      remaining -> raise("Research transport proof deadline")
    end
  end

  defp arguments(query \\ @query),
    do: %{
      "search" => "web",
      "fetch" => "web",
      "retrieval" => "words",
      "rerank" => nil,
      "query" => query,
      "limits" => %{"max_sources" => 1, "max_body_bytes" => 16_384, "timeout_ms" => 30_000},
      "sources" => []
    }

  defp web_calls(backend), do: Fixture.backend_state(backend).web_calls
  defp sha(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)
  defp action_count(events), do: Enum.count(events, &(&1["type"] == "extension_action_intent"))

  defp action_count(events, op),
    do:
      Enum.count(events, &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == op))

  defp events(pid, root) do
    {:ok, events} = Journal.load(Path.join(root, "sessions"), Session.info(pid).id)
    {:ok, _} = Session.restore_context(events)
    events
  end
end
