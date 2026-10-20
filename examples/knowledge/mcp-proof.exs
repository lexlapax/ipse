Code.require_file("evaluation_session.exs", __DIR__)

Code.require_file("../../test/support/knowledge_mcp_fixture.exs", __DIR__)

defmodule IpseKnowledgeExample.MCPProof do
  @moduledoc false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Config, Registry, Store}
  alias IpseKnowledge.Test.CASFixture, as: Fixture

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Knowledge MCP proof called a model")
  end

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-knowledge-mcp-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    {:ok, backend} = Fixture.start_backend("notes")
    Process.put(:knowledge_mcp_sessions, [])

    try do
      normal = config(artifact, root, backend, "normal")
      pid = start(normal, root)

      {:ok, %{"status" => "ok"}} =
        invoke(pid, "source", put("manual:release", "Release requires quiescence."))

      {:ok, %{"status" => "ok"}} =
        invoke(pid, "source", put("manual:other", "A separate rehearsal record."))

      before_query = events(pid, root)
      {:ok, answer} = invoke(pid, "query", query())

      unless answer["status"] == "ok",
        do:
          raise("Selected query refused: " <> inspect(Map.take(answer, ~w(status gaps coverage))))

      [candidate] = answer["evidence"]
      "mcp_query" = candidate["method"]
      "manual:release" = candidate["citation"]["source_id"]
      true = answer["coverage"]["revalidated"]
      "server_asserted" = answer["coverage"]["score_provenance"]
      delta = Enum.drop(events(pid, root), length(before_query))

      calls =
        for e <- delta,
            e["type"] == "extension_action_intent",
            e["request"]["op"] == "mcp.call",
            do: e["request"]

      [selected | reads] = calls
      "query-v1" = selected["arguments"]["contract"]
      true = reads != [] and Enum.all?(reads, &(&1["arguments"]["action"] == "get_many"))
      true = length(calls) == answer["coverage"]["final_validation"]["effects_used"]
      true = length(calls) <= 16
      other_hash = sha("manual:other")

      foreign_keys =
        for {key, row} <- Fixture.backend_state(backend).records,
            is_map(row["value"]) and row["value"]["source_key"] == other_hash,
            do: key

      true = foreign_keys != []

      true =
        Enum.all?(reads, fn request ->
          Enum.all?(request["arguments"]["args"]["keys"], &(&1 not in foreign_keys))
        end)

      seen = seen(backend)
      {:ok, %{"status" => "refused"}} = invoke(pid, "query", query(), false)
      true = seen(backend) == seen
      :ok = Session.close(pid)

      for mode <- ~w(query_wrong_partition query_partial query_forged_hash query_stale_generation) do
        rejected = start(config(artifact, root, backend, mode), root)
        {:ok, %{"status" => "refused", "evidence" => []}} = invoke(rejected, "query", query())
        true = Session.info(rejected).accounting["request_count"] == 0
        :ok = Session.close(rejected)
      end

      empty = start(config(artifact, root, backend, "query_empty"), root)
      {:ok, %{"status" => "abstain", "evidence" => []}} = invoke(empty, "query", query())

      empty_calls =
        for e <- events(empty, root),
            e["type"] == "extension_action_intent",
            e["request"]["op"] == "mcp.call",
            do: e

      true = length(empty_calls) == 1
      :ok = Session.close(empty)

      unknown_config = config(artifact, root, backend, "disconnect_after_query")
      unknown = start(unknown_config, root)
      prior_seen = seen(backend)
      {:error, _} = invoke(unknown, "query", query())
      true = seen(backend) == prior_seen + 1
      unknown_events = events(unknown, root)

      true =
        Enum.any?(
          unknown_events,
          &(&1["type"] == "extension_action_result" and &1["outcome"]["status"] == "unknown")
        )

      id = Session.info(unknown).id
      :ok = Session.close(unknown)
      after_seen = seen(backend)
      resumed = start(unknown_config, root, id)
      :idle = Session.info(resumed).phase
      true = seen(backend) == after_seen
      true = action_count(events(resumed, root)) == action_count(unknown_events)
      :ok = Session.close(resumed)

      for module <- [
            IpseKnowledge.Corpus,
            IpseKnowledge.Evidence,
            IpseKnowledge.Store,
            IpseKnowledge.Profiles,
            IpseKnowledge.Adapters
          ],
          do: false = :code.is_loaded(module)

      %{
        "checks" => 9,
        "selected_only" => true,
        "denied_dispatches" => 0,
        "unknown_replayed" => false,
        "model_requests" => 0,
        "host_loaded_domain_modules" => false
      }
    after
      for pid <- Process.get(:knowledge_mcp_sessions, []),
          Process.alive?(pid),
          do: :ok = Session.close(pid)

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
      "stores" => %{
        "remote" => %{
          "kind" => "mcp_cas",
          "binding" => "storage",
          "partition" => "notes",
          "contract" => "ipse-cas-v2"
        }
      },
      "retrieval" => %{
        "remote" => %{
          "kind" => "mcp_query",
          "binding" => "search",
          "partition" => "notes",
          "contract" => "query-v1"
        }
      },
      "search" => %{},
      "fetch" => %{},
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
            "instance" => "corpus",
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
                "instance" => "corpus",
                "alias" => "storage",
                "tool" => "mcp__knowledge_cas__cas"
              },
              %{
                "instance" => "corpus",
                "alias" => "search",
                "tool" => "mcp__knowledge_cas__query"
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
      Jason.encode!(%{"servers" => [Fixture.stdio_config("notes", mode, backend.port)]})
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

    Process.put(:knowledge_mcp_sessions, [pid | Process.get(:knowledge_mcp_sessions)])
    pid
  end

  defp invoke(pid, command, args, approve \\ true) do
    :ok = Session.invoke_export(pid, :command, "ext__corpus__" <> command, args)
    status = wait(pid, approve, System.monotonic_time(:millisecond) + 60_000)

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

  defp wait(pid, approve, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:ipse, ^pid, {:approval, ref, "extension:mcp.call", proposed}} ->
        request = proposed["request"]
        true = request["binding"] in ~w(storage search)
        "notes" = request["arguments"]["partition"]
        expected = if request["binding"] == "storage", do: "cas", else: "query"

        true =
          proposed["effect_binding"]["manifest"]["tool_id"] == "mcp__knowledge_cas__" <> expected

        :ok = Session.approve(pid, ref, approve)
        wait(pid, approve, deadline)

      {:ipse, ^pid, {:done, status}} ->
        status

      {:ipse, ^pid, _} ->
        wait(pid, approve, deadline)
    after
      remaining -> raise "Knowledge MCP proof deadline"
    end
  end

  defp put(id, text),
    do: %{
      "store" => "remote",
      "action" => "put",
      "args" => %{
        "source_id" => id,
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Manual",
        "text" => text,
        "uri" => "fixture:" <> id,
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }
    }

  defp query,
    do: %{
      "store" => "remote",
      "retrieval" => "remote",
      "rerank" => nil,
      "query" => "quiescence",
      "top_k" => 5,
      "as_of_ms" => 10
    }

  defp sha(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)
  defp seen(backend), do: MapSet.size(Fixture.backend_state(backend).seen)
  defp action_count(events), do: Enum.count(events, &(&1["type"] == "extension_action_intent"))

  defp events(pid, root) do
    {:ok, events} = Journal.load(Path.join(root, "sessions"), Session.info(pid).id)
    {:ok, _} = Session.restore_context(events)
    events
  end
end
