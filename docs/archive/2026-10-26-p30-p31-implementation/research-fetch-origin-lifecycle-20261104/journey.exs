defmodule Ipse.Test.ResearchOriginJourney do
  import ExUnit.Assertions
  alias Ipse.{Session, Journal, JSON}
  alias Ipse.Extension.{Artifact, Config, Registry, State}
  alias Ipse.Development.Fixtures.Knowledge, as: F

  defmodule NoModel do
    def complete(_, _, _, _), do: raise("origin journey attempted inference")
  end

  def main(root, research_path, corpus_path, options_path) do
    Process.put(:origin_deadline, System.monotonic_time(:millisecond) + 120_000)
    Process.put(:origin_sessions, [])
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    for path <- [home, cwd], do: File.mkdir!(path)
    File.chmod!(home, 0o700)
    System.put_env("HOME", home)
    System.put_env("IPSE_HOME", home)
    {:ok, _} = Application.ensure_all_started(:ipse)
    assert :sys.get_state(Ipse.Session.Input).entries == %{}
    refute Code.ensure_loaded?(IpseKnowledge.Research)
    refute Code.ensure_loaded?(IpseKnowledge.Corpus)

    artifacts =
      for {name, path} <- [{"research", research_path}, {"corpus", corpus_path}], into: %{} do
        assert {:ok, artifact} = Artifact.import(path, Path.join(home, "extensions/artifacts"))
        {name, artifact}
      end

    options = File.read!(options_path) |> Jason.decode!()
    corpus_options = Map.put(options, "fetch", %{})

    source = %{
      scope: "operator",
      path: Path.join(home, "fixture.json"),
      data: %{
        "extensions" =>
          for {name, artifact} <- artifacts do
            %{
              "instance" => name,
              "artifact" => artifact.digest,
              "enabled" => true,
              "options" => if(name == "research", do: options, else: corpus_options),
              "order" => 0,
              "lifetime" => "session"
            }
          end,
        "extension_trust" =>
          for {name, artifact} <- artifacts do
            %{
              "artifact" => artifact.digest,
              "capabilities" => artifact.manifest["capabilities"],
              "allow_project" => false,
              "allow_children" => false,
              "state_bindings" => [
                %{
                  "version" => 1,
                  "instance" => name,
                  "id" => "research-shared",
                  "scopes" => ["project"]
                }
              ],
              "mcp_bindings" =>
                if(name == "research",
                  do: [
                    %{
                      "instance" => name,
                      "alias" => "fetch-web",
                      "tool" => "mcp__knowledge_cas__fetch"
                    }
                  ],
                  else: []
                )
            }
          end
      }
    }

    {:ok, selected} = Config.resolve([source], [])
    {:ok, entries} = Registry.prepare(selected, home)
    {:ok, backend} = F.start_backend("research-notes")
    configure(backend, "Résumé 雪: Ada owns release after audit.", 10)
    config_path = Path.join(root, "mcp.json")

    File.write!(
      config_path,
      Jason.encode!(%{
        "servers" => [F.web_stdio_config("research-notes", "normal", backend.port)]
      }),
      [:exclusive]
    )

    {:ok, [server]} = Ipse.MCP.Config.load(config_path)

    config = %{
      provider: :demo,
      model: "unused",
      provider_module: NoModel,
      home: home,
      operator_home: nil,
      extensions: entries,
      mcp_servers: [server],
      approval: :ask,
      approval_origin: :interactive,
      headless: false,
      compact: false
    }

    session_options = [
      config: config,
      cwd: cwd,
      state_dir: Path.join(home, "sessions"),
      owner: self(),
      subscriber: self()
    ]

    state_root = Path.join(home, "extension-state-v1")

    try do
      first = start(session_options)
      first_id = Session.info(first).id
      identity = Enum.find(entries, &(&1.identity["instance"] == "research")).identity
      {:ok, namespace} = State.namespace(identity, "project", cwd, first_id)
      a = "Résumé 雪: Ada owns release after audit."
      b = "Résumé 雪: Babbage owns release after audit."
      c = "Résumé 雪: Charles owns release after audit."

      args = %{
        "store" => "notes",
        "fetch" => "web",
        "uri" => "fixture:release",
        "title" => "Release",
        "quote" => "Ada owns release after audit.",
        "timeout_ms" => 3000
      }

      {stored_a, count} = command(first, "ext__research__fetch_retain", args)
      assert stored_a["status"] == "ok" and count.mcp == 1 and count.state > 0
      assert stored_a["coverage"]["derivation"]["version"] === 2
      a_id = stored_a["coverage"]["source_id"]

      query = %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "release",
        "top_k" => 3,
        "as_of_ms" => 30
      }

      {old_query, %{mcp: 0, state: 0, selector_denied: 0}} =
        command(first, "ext__corpus__query", query)

      assert [old_evidence] = old_query["evidence"]
      assert old_evidence["citation"]["quote"] == a
      before = snapshot(state_root, namespace)

      a_row =
        Enum.find(
          before["records"],
          &(get_in(&1, ["value", "source_id"]) == a_id and get_in(&1, ["value", "kind"]) == "root")
        )

      assert a_row["value"]["format"] === 2
      configure(backend, b, 20)

      {partial, count} =
        command(
          first,
          "ext__research__fetch_retain",
          %{args | "quote" => "Babbage owns release after audit."},
          :deny_selector
        )

      assert count.mcp == 1 and count.selector_denied == 1 and count.state > 1
      assert partial["status"] == "refused"
      assert partial["coverage"]["body_publication"] == "known"
      b_id = partial["coverage"]["source_id"]
      assert b_id == "research.provided:" <> JSON.sha256(b)
      after_partial = snapshot(state_root, namespace)
      assert Enum.find(after_partial["records"], &(&1["key"] == a_row["key"])) === a_row
      assert :ok = Session.close_confirmed(first)
      first_events = events(session_options, first_id)
      idle(session_options, first_id, first_events)
      assert snapshot(state_root, namespace) === after_partial

      fresh = start(session_options)
      fresh_id = Session.info(fresh).id
      {inspected, _} = source(fresh, "inspect", %{"source_id" => b_id})
      assert inspected["coverage"]["fetch_version"]["status"] == "historical"

      {exported, _} =
        source(fresh, "export", %{"source_id" => b_id, "cursor" => nil, "limit" => 2})

      assert exported["coverage"]["text"] == b and exported["coverage"]["next"] == nil
      assert exported["coverage"]["source"]["origin"]["receipt"]["selection_base_revision"] == 1

      select = %{
        "store" => "notes",
        "fetch" => "web",
        "uri" => args["uri"],
        "source_id" => b_id,
        "source_revision" => inspected["coverage"]["revision"],
        "expected_selection_revision" => inspected["coverage"]["fetch_version"]["revision"]
      }

      b_row =
        Enum.find(
          after_partial["records"],
          &(get_in(&1, ["value", "source_id"]) == b_id and get_in(&1, ["value", "kind"]) == "root")
        )

      {recovered, %{mcp: 0, state: 1, selector_denied: 0}} =
        command(fresh, "ext__research__select_retained", select)

      assert recovered["status"] == "ok" and
               recovered["coverage"]["selection_status"] == "selected"

      assert recovered["coverage"]["fresh_fetch"] == false and
               recovered["coverage"]["body_republished"] == false

      recovered_snapshot = snapshot(state_root, namespace)

      changes =
        Enum.reject(recovered_snapshot["records"], fn row -> row in after_partial["records"] end)

      assert [%{"value" => %{"kind" => "fetch_origin"}}] = changes
      assert Enum.find(recovered_snapshot["records"], &(&1["key"] == b_row["key"])) === b_row
      {new_query, _} = command(fresh, "ext__corpus__query", query)
      assert [new_evidence] = new_query["evidence"]
      assert new_evidence["citation"]["quote"] == b

      assert new_evidence["citation"]["origin"]["receipt"] ===
               exported["coverage"]["source"]["origin"]["receipt"]

      {current_b, _} = source(fresh, "inspect", %{"source_id" => b_id})

      {observed, %{mcp: 0, state: 0, selector_denied: 0}} =
        command(fresh, "ext__research__select_retained", %{
          select
          | "expected_selection_revision" => current_b["coverage"]["fetch_version"]["revision"]
        })

      assert observed["coverage"]["selection_status"] == "already_selected"
      assert snapshot(state_root, namespace) === recovered_snapshot
      configure(backend, c, 5)

      {stored_c, count} =
        command(fresh, "ext__research__fetch_retain", %{
          args
          | "quote" => "Charles owns release after audit."
        })

      assert stored_c["status"] == "ok" and count.mcp == 1
      {historical_b, _} = source(fresh, "inspect", %{"source_id" => b_id})
      assert historical_b["coverage"]["fetch_version"]["status"] == "historical"
      frozen = snapshot(state_root, namespace)

      {conflict, %{mcp: 0, state: 0, selector_denied: 0}} =
        command(fresh, "ext__research__select_retained", %{
          select
          | "expected_selection_revision" => historical_b["coverage"]["fetch_version"]["revision"]
        })

      assert conflict["status"] == "refused" and snapshot(state_root, namespace) === frozen
      {last_query, _} = command(fresh, "ext__corpus__query", query)
      assert [last] = last_query["evidence"]
      assert last["citation"]["quote"] == c
      assert Enum.find(frozen["records"], &(&1["key"] == a_row["key"])) === a_row
      assert Enum.find(frozen["records"], &(&1["key"] == b_row["key"])) === b_row
      assert :ok = Session.close_confirmed(fresh)
      fresh_events = events(session_options, fresh_id)
      idle(session_options, fresh_id, fresh_events)
      assert snapshot(state_root, namespace) === frozen
      assert :ok = F.stop_backend(backend)
      assert :sys.get_state(Ipse.Session.Input).entries == %{}
      refute Code.ensure_loaded?(IpseKnowledge.Research)
      refute Code.ensure_loaded?(IpseKnowledge.Corpus)

      %{
        status: "passed",
        partial_known_body: true,
        recovery_selector_only: true,
        already_selected_no_effect: true,
        newer_revision_refused: true,
        upstream_clock_skew: true,
        historical_citations_immutable: true,
        paired_workers: true,
        strict_saved_idle_no_replay: true,
        provider_requests: 0,
        tty_reads: 0,
        native_note_authority: false
      }
    after
      for pid <- Process.get(:origin_sessions, []),
          Process.alive?(pid),
          do: Session.close_confirmed(pid)

      if Process.alive?(backend.pid), do: F.stop_backend(backend)
    end
  end

  defp start(options) do
    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, options})
    Process.put(:origin_sessions, [pid | Process.get(:origin_sessions, [])])
    pid
  end

  defp configure(backend, text, observed) do
    assert :ok =
             F.configure_web_backend(backend, %{
               "searches" => %{},
               "pages" => %{
                 "fixture:release" => %{
                   "text" => text,
                   "observed_uri" => "fixture:observed-release",
                   "media_type" => "text/plain",
                   "observed_at_ms" => observed
                 }
               }
             })
  end

  defp source(pid, action, args),
    do:
      command(pid, "ext__corpus__source", %{
        "store" => "notes",
        "action" => action,
        "args" => args
      })

  defp command(pid, name, args, decision \\ :allow) do
    assert :ok = Session.invoke_export(pid, :command, name, args)
    deadline = min(System.monotonic_time(:millisecond) + 20_000, Process.get(:origin_deadline))
    await(pid, args, decision, %{mcp: 0, state: 0, selector_denied: 0}, deadline)
  end

  defp await(pid, args, decision, counts, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:mcp.call", proposed}} ->
        req = proposed["request"]

        assert req["binding"] == "fetch-web" and
                 req["arguments"] == %{
                   "version" => 1,
                   "contract" => "fetch-v1",
                   "uri" => args["uri"]
                 }

        assert proposed["effect_binding"]["manifest"]["tool_id"] == "mcp__knowledge_cas__fetch"
        assert :ok = Session.approve(pid, ref, true)
        await(pid, args, decision, %{counts | mcp: counts.mcp + 1}, deadline)

      {:ipse, ^pid, {:approval, ref, "extension:state.put", proposed}} ->
        req = proposed["request"]
        assert :ok = State.validate(req)
        assert req["scope"] == "project"
        deny = decision == :deny_selector and get_in(req, ["value", "kind"]) == "fetch_origin"
        assert :ok = Session.approve(pid, ref, not deny)

        await(
          pid,
          args,
          decision,
          %{
            counts
            | state: counts.state + 1,
              selector_denied: counts.selector_denied + if(deny, do: 1, else: 0)
          },
          deadline
        )

      {:ipse, ^pid, {:approval, _, _, _}} ->
        flunk("unexpected approval")

      {:ipse, ^pid, {:done, :ok}} ->
        assert %{"value" => value} = Session.info(pid).extension_result
        {value, counts}

      {:ipse, ^pid, {:done, _}} ->
        flunk("origin command failed")

      _ ->
        await(pid, args, decision, counts, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) ->
        flunk("bounded origin command did not settle")
    end
  end

  defp events(options, id) do
    assert {:ok, rows} = Journal.load(options[:state_dir], id)
    assert {:ok, _} = Session.Saved.restore(rows, id)

    refute Enum.any?(
             rows,
             &(&1["type"] in ~w(request_intent request_admitted inference_dispatch_intent))
           )

    rows
  end

  defp idle(options, id, before) do
    kinds =
      ~w(input_received extension_invocation_intent extension_action_intent worker_input_intent inference_dispatch_intent mcp_action_intent)

    pid = start(Keyword.put(options, :id, id))

    assert Session.info(pid).phase == :idle
    assert :ok = Session.close_confirmed(pid)
    after_rows = events(options, id)

    assert Enum.filter(before, &(&1["type"] in kinds)) ===
             Enum.filter(after_rows, &(&1["type"] in kinds))
  end

  defp snapshot(root, namespace), do: snapshot(root, namespace, nil, nil, [], 0)

  defp snapshot(root, namespace, cursor, generation, rows, count) do
    assert count < 32

    assert {:ok, page} =
             State.execute(
               root,
               namespace,
               %{
                 "op" => "state.scan",
                 "scope" => "project",
                 "after" => cursor,
                 "generation" => generation,
                 "limit" => 16
               },
               Ipse.Usage.id()
             )

    assert generation == nil or page["generation"] == generation
    next = page["next"]

    if next == nil,
      do: %{"generation" => page["generation"], "records" => rows ++ page["records"]},
      else:
        snapshot(root, namespace, next, page["generation"], rows ++ page["records"], count + 1)
  end
end

