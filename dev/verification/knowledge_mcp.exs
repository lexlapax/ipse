Code.require_file("../evaluation/session.exs", __DIR__)

defmodule IpseKnowledgeExample.MCPProof do
  @moduledoc false
  alias Ipse.{Session, Journal}
  alias Ipse.Extension.{Config, Registry, Artifact}
  alias Ipse.Development.Fixtures.Knowledge, as: Fixture

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("Knowledge MCP proof called a model")
  end

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-knowledge-mcp-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    IO.puts(:stderr, "KNOWLEDGE_MCP_RETAINED_ROOT=" <> root)
    {:ok, backend} = Fixture.start_backend("notes")
    Process.put(:knowledge_mcp_sessions, [])
    Process.put(:knowledge_mcp_confirmed, MapSet.new())

    outcome =
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
            raise(
              "Selected query refused: " <> inspect(Map.take(answer, ~w(status gaps coverage)))
            )

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
        other_hash = Ipse.JSON.sha256("manual:other")

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
        :ok = close!(pid)

        for mode <-
              ~w(query_wrong_partition query_partial query_forged_hash query_stale_generation) do
          rejected = start(config(artifact, root, backend, mode), root)
          {:ok, %{"status" => "refused", "evidence" => []}} = invoke(rejected, "query", query())
          true = Session.info(rejected).accounting["request_count"] == 0
          :ok = close!(rejected)
        end

        empty = start(config(artifact, root, backend, "query_empty"), root)
        empty_before = Fixture.backend_state(backend)
        before_empty_events = events(empty, root)

        {:ok,
         %{
           "status" => "abstain",
           "evidence" => [],
           "claims" => [
             %{
               "label" => "open",
               "evidence_indexes" => [],
               "uncertainty" => "semantic_support_unassessed"
             }
           ]
         } = empty_answer} =
          invoke(empty, "query", query())

        empty_delta = Enum.drop(events(empty, root), length(before_empty_events))

        empty_calls =
          for e <- empty_delta,
              e["type"] == "extension_action_intent",
              e["request"]["op"] == "mcp.call",
              do: e["request"]

        [query_call, probe] = empty_calls
        "search" = query_call["binding"]
        "query-v1" = query_call["arguments"]["contract"]
        "notes" = query_call["arguments"]["partition"]
        "quiescence" = query_call["arguments"]["query"]
        5 = query_call["arguments"]["top_k"]
        10 = query_call["arguments"]["as_of_ms"]
        "storage" = probe["binding"]
        "ipse-cas-v3" = probe["arguments"]["contract"]
        "notes" = probe["arguments"]["partition"]
        "get_many" = probe["arguments"]["action"]

        probe_key =
          Ipse.JSON.sha256(
            IO.iodata_to_binary(
              JSON.encode!(["ipse-knowledge", 1, "namespace-generation-probe", ["notes"]])
            )
          )

        [^probe_key] = probe["arguments"]["args"]["keys"]
        ["keys"] = Map.keys(probe["arguments"]["args"])

        empty_reads =
          Enum.count(
            empty_delta,
            &(&1["type"] == "extension_action_intent" and
                &1["request"]["op"] == "effect.result.read")
          )

        2 = empty_reads

        empty_page_results =
          for e <- empty_delta,
              e["type"] == "extension_action_result" and
                e["request"]["op"] == "effect.result.read",
              do: e["outcome"]

        2 = length(empty_page_results)

        true =
          Enum.all?(
            empty_page_results,
            &(&1["status"] == "ok" and &1["value"]["complete"] === true)
          )

        2 = empty_answer["coverage"]["final_validation"]["effects_used"]
        ^empty_reads = empty_answer["coverage"]["final_validation"]["reads_used"]
        true = empty_answer["coverage"]["revalidated"]
        false = empty_answer["coverage"]["store"]["namespace_complete"]
        true = empty_answer["coverage"]["store"]["generation"] == empty_before.generation
        empty_after = Fixture.backend_state(backend)

        true =
          empty_after.records === empty_before.records and
            empty_after.generation === empty_before.generation

        :ok = close!(empty)

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
        :ok = close!(unknown)
        after_seen = seen(backend)
        resumed = start(unknown_config, root, id)
        :idle = Session.info(resumed).phase
        true = seen(backend) == after_seen
        true = action_count(events(resumed, root)) == action_count(unknown_events)
        :ok = close!(resumed)

        for module <- [
              IpseKnowledge.Corpus,
              IpseKnowledge.Evidence,
              IpseKnowledge.Store,
              IpseKnowledge.Profiles,
              IpseKnowledge.Adapters
            ],
            do: false = :code.is_loaded(module)

        {:ok,
         %{
           "checks" => 9,
           "selected_only" => true,
           "denied_dispatches" => 0,
           "unknown_replayed" => false,
           "model_requests" => 0,
           "host_loaded_domain_modules" => false
         }}
      rescue
        error -> {:failed, :error, error, __STACKTRACE__}
      catch
        kind, reason -> {:failed, kind, reason, __STACKTRACE__}
      end

    finish_outcome(outcome, root, cleanup(backend))
  end

  defp finish_outcome(outcome, root, cleanup) do
    receipt = %{
      "version" => 1,
      "retained_root" => root,
      "sessions_confirmed" => cleanup.sessions_confirmed,
      "sessions_unconfirmed" => cleanup.sessions_unconfirmed,
      "backend_process_stopped" => cleanup.backend_process_stopped,
      "proof_completed" => match?({:ok, _}, outcome)
    }

    written =
      File.write(Path.join(root, "cleanup.json"), JSON.encode!(receipt), [:exclusive, :sync])

    cleanup_ok =
      cleanup.sessions_unconfirmed == 0 and cleanup.backend_process_stopped and written == :ok

    case outcome do
      {:ok, report} when cleanup_ok ->
        Map.merge(report, %{
          "retained_root" => root,
          "cleanup" => "confirmed",
          "cleanup_scope" => "session_ack_and_backend_process_exit_only"
        })

      {:ok, _} ->
        raise "Knowledge MCP proof cleanup unconfirmed; retained root: " <> root

      {:failed, kind, reason, stack} ->
        if not cleanup_ok, do: IO.puts(:stderr, "KNOWLEDGE_MCP_CLEANUP_UNCONFIRMED")
        :erlang.raise(kind, reason, stack)
    end
  end

  defp close!(pid) do
    :ok = Session.close_confirmed(pid)
    Process.put(:knowledge_mcp_confirmed, MapSet.put(Process.get(:knowledge_mcp_confirmed), pid))
    :ok
  end

  defp cleanup(backend) do
    confirmed = Process.get(:knowledge_mcp_confirmed, MapSet.new())
    sessions = Process.get(:knowledge_mcp_sessions, []) |> Enum.uniq()

    {closed, unconfirmed} =
      Enum.reduce(sessions, {0, 0}, fn pid, {closed, unconfirmed} ->
        cond do
          MapSet.member?(confirmed, pid) ->
            {closed + 1, unconfirmed}

          Process.alive?(pid) and safe_close(pid) ->
            {closed + 1, unconfirmed}

          true ->
            {closed, unconfirmed + 1}
        end
      end)

    %{
      sessions_confirmed: closed,
      sessions_unconfirmed: unconfirmed,
      backend_process_stopped: safe_stop_backend(backend)
    }
  end

  defp safe_close(pid) do
    Session.close_confirmed(pid) === :ok
  catch
    _, _ -> false
  end

  defp safe_stop_backend(backend) do
    Fixture.stop_backend(backend) === :ok
  catch
    _, _ -> false
  end

  defp config(artifact, root, backend, mode) do
    home = Path.join(root, "home")
    {:ok, imported} = Artifact.import(artifact, Path.join(home, "extensions/artifacts"))
    manifest = Jason.decode!(File.read!(Path.join(artifact, "extension.json")))

    options = %{
      "version" => 1,
      "stores" => %{
        "remote" => %{
          "kind" => "mcp_cas",
          "binding" => "storage",
          "partition" => "notes",
          "contract" => "ipse-cas-v3"
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
        Ipse.Development.Evaluation.Session.complete_result(
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

  defp seen(backend), do: MapSet.size(Fixture.backend_state(backend).seen)
  defp action_count(events), do: Enum.count(events, &(&1["type"] == "extension_action_intent"))

  defp events(pid, root) do
    {:ok, events} = Journal.load(Path.join(root, "sessions"), Session.info(pid).id)
    {:ok, _} = Session.restore_context(events)
    events
  end
end
