Code.require_file("../evaluation/session.exs", __DIR__)

defmodule IpseKnowledgeExample.LifecycleProof do
  @moduledoc "Barrier-controlled public domain operations, using only synthetic provider responses."
  alias Ipse.Session
  alias Ipse.Journal
  alias Ipse.Usage.Budget
  alias Ipse.Usage
  alias Ipse.Extension.{Catalog, Config, Registry, Artifact, State, ModelCall, EmbeddingCall}
  @source "proof:projection-lifecycle"
  @text "Release requires quiescence."

  defmodule NoMain do
    def complete(_, _, _, _), do: raise("Lifecycle fixture attempted main inference")
  end

  def run(artifact, kind) when kind in ~w(graph corpus) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-domain-lifecycle-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    try do
      cases =
        for mode <- [:forget, :cancel, :owner_loss, :timeout, :quota, :malformed, :unavailable] do
          directory = Path.join(root, Atom.to_string(mode))
          File.mkdir!(directory)
          exercise(artifact, kind, mode, directory)
        end

      for module <- [
            IpseKnowledge.Corpus,
            IpseKnowledge.Graph,
            IpseKnowledge.Store,
            IpseKnowledge.Adapters
          ],
          do: false = :code.is_loaded(module)

      %{
        "checks" => length(cases),
        "package" => kind,
        "cases" => cases,
        "actual_model_inference" => false,
        "fixture_provider_requests" => Enum.sum(Enum.map(cases, & &1["provider_requests"])),
        "host_loaded_domain_modules" => false,
        "fixture_cleanup" => "confirmed",
        "session_cleanup_unconfirmed_cases" => ["owner_loss"]
      }
    after
      File.rm_rf!(root)
    end
  end

  defp exercise(artifact, kind, mode, root) do
    http = http_start(mode)
    Process.put(:lifecycle_owned_sessions, [])

    try do
      config =
        configuration(
          artifact,
          kind,
          root,
          http.base,
          if(mode == :timeout, do: 1000, else: 15_000)
        )

      if mode in [:quota, :malformed, :unavailable] do
        sequential(config, kind, mode, root, http)
      else
        interrupted(config, kind, mode, root, http)
      end
    after
      for pid <- Process.delete(:lifecycle_owned_sessions) || [],
          Process.alive?(pid),
          do: :ok = Session.close_confirmed(pid)

      :ok = http_stop(http)
    end
  end

  def selection(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    root = Path.join(System.tmp_dir!(), "ipse-embedding-selection-" <> Usage.id())
    File.mkdir!(root)
    Process.put(:lifecycle_owned_sessions, [])
    a = http_start(:selection_a)
    b = http_start(:selection_b)

    try do
      config_a = configuration(artifact, "corpus", root, a.base, 15_000, true)
      first = start(config_a, "corpus", root)
      chunk = prepare(first)
      %{"status" => "ok"} = invoke(first, "index", projection_args("corpus", chunk))
      assert_request("corpus", dispatched(a).body)
      %{"status" => "ok"} = selection_query(first, "dense")
      ["Release"] = dispatched(a).body["input"]
      hash_a = selection_receipts(first, 2)
      :ok = Session.close_confirmed(first.pid)

      config_b = configuration(artifact, "corpus", root, b.base, 15_000, true)
      second = start(config_b, "corpus", root)
      %{"status" => "refused", "evidence" => []} = selection_query(second, "dense")
      ["Release"] = dispatched(b).body["input"]

      %{"status" => "partial", "gaps" => gaps, "evidence" => [_]} =
        selection_query(second, "fallback")

      true = Enum.any?(gaps, &(&1["code"] == "missing_embedding"))
      ["Release"] = dispatched(b).body["input"]
      %{"status" => "ok"} = invoke(second, "index", projection_args("corpus", chunk))
      assert_request("corpus", dispatched(b).body)
      %{"status" => "ok"} = selection_query(second, "dense")
      ["Release"] = dispatched(b).body["input"]
      hash_b = selection_receipts(second, 4)
      true = hash_a != hash_b
      :ok = Session.close_confirmed(second.pid)

      timeout_config =
        put_in(config_b, [:embedding_profiles, "fixture_embed", "timeout_ms"], 10_000)

      third = start(timeout_config, "corpus", root)
      %{"status" => "ok"} = selection_query(third, "dense")
      ["Release"] = dispatched(b).body["input"]
      ^hash_b = selection_receipts(third, 1)
      :ok = Session.close_confirmed(third.pid)

      restored = start(config_b, "corpus", root, second.id)
      ^hash_b = selection_receipts(restored, 4)
      :idle = Session.info(restored.pid).phase
      :ok = Session.close_confirmed(restored.pid)

      :atomics.put(b.model_revision, 1, 2)
      fourth = start(config_b, "corpus", root)
      %{"status" => "refused", "evidence" => []} = selection_query(fourth, "dense")
      ["Release"] = dispatched(b).body["input"]
      %{"status" => "ok"} = invoke(fourth, "index", projection_args("corpus", chunk))
      assert_request("corpus", dispatched(b).body)
      %{"status" => "ok"} = selection_query(fourth, "dense")
      ["Release"] = dispatched(b).body["input"]
      ^hash_b = selection_receipts(fourth, 3)
      :ok = Session.close_confirmed(fourth.pid)
      no_dispatch(a)
      no_dispatch(b)
      false = :code.is_loaded(IpseKnowledge.Corpus)
      false = :code.is_loaded(IpseKnowledge.Store)

      %{
        "checks" => 10,
        "fixture_provider_requests" => 10,
        "actual_model_inference" => false,
        "changed_endpoint_refused" => true,
        "explicit_fallback_partial" => true,
        "explicit_reindex_succeeded" => true,
        "timeout_only_reused" => true,
        "changed_reported_model_reindexed" => true,
        "reported_model_change_preserved_selection" => true,
        "idle_resume_replays" => 0,
        "host_loaded_domain_modules" => false,
        "cleanup" => "confirmed"
      }
    after
      for pid <- Process.delete(:lifecycle_owned_sessions) || [],
          Process.alive?(pid),
          do: :ok = Session.close_confirmed(pid)

      :ok = http_stop(a)
      :ok = http_stop(b)
      File.rm_rf!(root)
    end
  end

  defp selection_query(session, retrieval),
    do:
      invoke(session, "query", %{
        "store" => "notes",
        "retrieval" => retrieval,
        "rerank" => nil,
        "query" => "Release",
        "top_k" => 10,
        "as_of_ms" => 10
      })

  defp selection_receipts(session, count) do
    {:ok, events} = Journal.load(session.state_dir, session.id)
    :ok = Ipse.Extension.Actions.validate_events(events)
    {:ok, _} = Session.restore_context(events)
    {:ok, ledger} = Usage.restore(events, session.id)
    ^count = Usage.snapshot(ledger)["request_count"]

    results =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            &1["request"]["op"] == "embedding.create")
      )

    ^count = length(results)

    hashes =
      Enum.map(results, fn event ->
        "ok" = event["outcome"]["status"]
        2 = event["request"]["version"]
        2 = event["outcome"]["value"]["version"]
        {:ok, hash} = EmbeddingCall.selection_sha256(Ipse.Extension.Actions.result_intent(event))
        ^hash = event["outcome"]["value"]["selection_sha256"]
        hash
      end)

    [hash] = Enum.uniq(hashes)
    hash
  end

  defp sequential(config, kind, mode, root, http) do
    session = start(config, kind, root)

    try do
      chunk = prepare(session)
      result = invoke(session, projection(kind), projection_args(kind, chunk))
      expected = if mode == :quota, do: "ok", else: "refused"
      true = result["status"] == expected
      request = dispatched(http)
      assert_request(kind, request.body)
      coverage = inspect_source(session)
      true = coverage["projections"] != [] == (mode == :quota)

      if mode == :quota do
        %{"status" => "refused"} = invoke(session, projection(kind), projection_args(kind, chunk))
        {:ok, saved} = Budget.saved(session.state_dir, session.id)
        1 = saved["request_count"]
        true = saved["refused_count"] >= 1
        true = inspect_source(session)["projections"] == coverage["projections"]
      end

      index_abort = kind == "corpus" and mode in [:malformed, :unavailable]

      if index_abort do
        true = is_map(coverage["draft"])

        aborted =
          invoke(session, "index", Map.put(projection_args(kind, chunk), "action", "abort"))

        "ok" = aborted["status"]
        1 = aborted["coverage"]["generation"]
        true = aborted["coverage"]["revision"] == coverage["revision"] + 1
        nil = inspect_source(session)["draft"]
        no_dispatch(http)
      end

      {:ok, events} = Journal.load(session.state_dir, session.id)
      {:ok, ledger} = Usage.restore(events, session.id)
      requests = Usage.snapshot(ledger)["requests"]
      true = requests != []
      if mode == :quota, do: true = Enum.any?(requests, &(&1["outcome"] == "completed"))
      :ok = Session.close_confirmed(session.pid)

      verify_idle_resume(
        session,
        config,
        kind,
        root,
        http,
        if(mode == :quota, do: :present, else: :empty)
      )

      no_dispatch(http)

      %{
        "case" => Atom.to_string(mode),
        "provider_requests" => 1,
        "idle_resume_replays" => 0,
        "session_cleanup" => "confirmed",
        "canonical_requests" => length(requests),
        "index_abort_confirmed" => index_abort
      }
    after
      if Process.alive?(session.pid), do: :ok = Session.close_confirmed(session.pid)
    end
  end

  defp interrupted(config, kind, mode, root, http) do
    controller = self()

    task =
      Task.async(fn ->
        Process.put(:lifecycle_owned_sessions, [])
        session = start(config, kind, root)

        try do
          chunk = prepare(session)
          send(controller, {:lifecycle_prepared, self(), session})
          result = invoke(session, projection(kind), projection_args(kind, chunk))
          if Process.alive?(session.pid), do: :ok = Session.close_confirmed(session.pid)
          {session, result}
        after
          if Process.alive?(session.pid), do: :ok = Session.close_confirmed(session.pid)
        end
      end)

    try do
      session =
        receive do
          {:lifecycle_prepared, pid, session} when pid == task.pid -> session
        after
          15_000 -> raise("Lifecycle preparation barrier missing")
        end

      request = dispatched(http)
      assert_request(kind, request.body)

      case mode do
        :forget ->
          other = start(config, kind, root)

          try do
            coverage = inspect_source(other)
            true = is_map(coverage["draft"])

            %{"status" => "ok"} =
              invoke(
                other,
                "source",
                source_args("forget", %{
                  "source_id" => @source,
                  "expected_revision" => coverage["revision"]
                })
              )

            send(request.handler, {:respond, http.tag})
            {_, result} = Task.await(task, 20_000)
            true = result["status"] in ~w(refused conflict)
            "suppressed" = inspect_source(other)["state"]
            no_evidence(other, kind)
            :ok = Session.close_confirmed(other.pid)
          after
            if Process.alive?(other.pid), do: :ok = Session.close_confirmed(other.pid)
          end

        :cancel ->
          :ok = Session.cancel(session.pid)
          {_, %{"fixture_outcome" => "cancelled"}} = Task.await(task, 20_000)
          closed(http, request.handler)
          uncertainty(session, kind)

        :owner_loss ->
          guard = Ipse.Session.Lock.for_owner(session.pid)
          guard_monitor = Process.monitor(guard)
          Process.exit(session.pid, :kill)
          {_, %{"fixture_outcome" => "owner_down"}} = Task.await(task, 20_000)

          receive do
            {:DOWN, ^guard_monitor, :process, ^guard, _} -> :ok
          after
            10_000 -> raise("Session lock cleanup unconfirmed")
          end

          closed(http, request.handler)
          uncertainty(session, kind)

        :timeout ->
          {_, %{"status" => "refused"}} = Task.await(task, 20_000)
          closed(http, request.handler)
          uncertainty(session, kind)
      end

      verify_idle_resume(
        session,
        config,
        kind,
        root,
        http,
        if(mode == :forget, do: :suppressed, else: :empty)
      )

      no_dispatch(http)

      report = %{
        "case" => Atom.to_string(mode),
        "provider_requests" => 1,
        "idle_resume_replays" => 0,
        "session_cleanup" =>
          if(mode == :owner_loss, do: "unconfirmed_owner_loss", else: "confirmed")
      }

      if mode == :forget,
        do: Map.put(report, "source_resurrected", false),
        else: Map.put(report, "unsettled_inference", true)
    after
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp uncertainty(session, kind) do
    {:ok, events} = Journal.load(session.state_dir, session.id)
    {:ok, _} = Session.restore_context(events)
    false = Enum.any?(events, &(&1["type"] == "extension_effect_result"))
    {:ok, saved} = Budget.saved(session.state_dir, session.id)
    1 = saved["request_count"]
    true = saved["unsettled_count"] >= 1 or saved["partial_count"] >= 1
    booked = Map.new(saved["dimensions"], &{&1["unit"], &1["booked"]})
    true = booked["input_tokens"] >= 4096

    if kind == "corpus",
      do: 0 = booked["output_tokens"],
      else: true = booked["output_tokens"] >= 4096
  end

  defp verify_idle_resume(session, config, kind, root, http, expected) do
    {:ok, before} = Journal.load(session.state_dir, session.id)
    resumed = start(config, kind, root, session.id)

    try do
      :idle = Session.info(resumed.pid).phase
      {:ok, after_events} = Journal.load(session.state_dir, session.id)
      before_intents = Enum.filter(before, &(&1["type"] == "extension_action_intent"))

      true =
        before_intents == Enum.filter(after_events, &(&1["type"] == "extension_action_intent"))

      no_dispatch(http)
      coverage = inspect_source(resumed)

      case expected do
        :suppressed ->
          "suppressed" = coverage["state"]
          no_evidence(resumed, kind)

        :empty ->
          [] = coverage["projections"]

        :present ->
          true = coverage["projections"] != []
      end

      :ok = Session.close_confirmed(resumed.pid)
    after
      if Process.alive?(resumed.pid), do: :ok = Session.close_confirmed(resumed.pid)
    end
  end

  defp start(config, kind, root, id \\ nil) do
    cwd = Path.join(root, "workspace")
    File.mkdir_p!(cwd)
    {:ok, cwd} = Ipse.Workspace.canonical_path(cwd)
    state_dir = Path.join(root, "sessions")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: cwd, state_dir: state_dir, id: id, owner: self(), subscriber: self()}
      )

    Process.put(:lifecycle_owned_sessions, [pid | Process.get(:lifecycle_owned_sessions, [])])
    true = Enum.all?(Session.exports(pid)["entries"], &(&1["instance"] == kind))

    %{
      pid: pid,
      id: Session.info(pid).id,
      cwd: cwd,
      state_dir: state_dir,
      config: config,
      kind: kind
    }
  end

  defp configuration(artifact, kind, root, origin, timeout, selection \\ false) do
    home = Path.join(root, "home")
    {:ok, imported} = Artifact.import(artifact, Path.join(home, "extensions/artifacts"))
    manifest = JSON.decode!(File.read!(Path.join(artifact, "extension.json")))

    options = %{
      "version" => 1,
      "stores" => %{
        "notes" => %{"kind" => "state", "scope" => "project", "partition" => "lifecycle"}
      },
      "search" => %{},
      "fetch" => %{},
      "embedding" => %{},
      "extraction" => %{},
      "rerank" => %{},
      "retrieval" => %{}
    }

    options =
      if kind == "graph" do
        Map.put(options, "extraction", %{
          "assisted" => %{
            "kind" => "model_complete",
            "profile" => "fixture_extract",
            "version" => 1,
            "output_contract" => "json_schema_v2"
          }
        })
      else
        Map.merge(options, %{
          "embedding" => %{"native" => %{"kind" => "embedding", "profile" => "fixture_embed"}},
          "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}}
        })
      end

    options =
      if selection do
        options
        |> put_in(["retrieval", "dense"], %{
          "kind" => "dense",
          "version" => 1,
          "embedding" => "native"
        })
        |> put_in(["retrieval", "fallback"], %{
          "kind" => "hybrid",
          "version" => 1,
          "lexical" => "words",
          "embedding" => "native",
          "graph" => nil,
          "rrf_k" => 60,
          "missing_embedding" => "lexical_with_gap"
        })
      else
        options
      end

    trust = %{
      "artifact" => imported.digest,
      "capabilities" => manifest["capabilities"],
      "allow_project" => false,
      "allow_children" => false,
      "state_bindings" => [
        %{"version" => 1, "instance" => kind, "id" => "lifecycle", "scopes" => ["project"]}
      ]
    }

    source = %{
      scope: "operator",
      path: Path.join(root, "operator.json"),
      data: %{
        "extensions" => [
          %{
            "instance" => kind,
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

    config = %{
      provider: :ollama,
      model: "no-main",
      provider_module: NoMain,
      compact: false,
      home: home,
      operator_home: Path.join(root, "operator-home"),
      extensions: entries,
      approval: :ask,
      budget: %{
        "version" => 1,
        "max_requests" => if(selection, do: 4, else: 1),
        "max_input_tokens" => 8192,
        "reserve_input_tokens" => 4096,
        "max_output_tokens" => 8192,
        "reserve_output_tokens" => 4096
      },
      profiles: %{
        "fixture_extract" => %{
          "provider" => "ollama",
          "model" => "fixture-text",
          "credential" => "none",
          "base_url" => origin,
          "max_output_tokens" => 4096,
          "reasoning_effort" => "none",
          "timeout_ms" => timeout
        }
      },
      embedding_profiles: %{
        "fixture_embed" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture-embedding",
          "credential" => "none",
          "base_url" => origin,
          "dimensions" => 2,
          "dimension_mode" => "native",
          "timeout_ms" => timeout
        }
      }
    }

    {:ok, _} = Catalog.snapshot(config)
    config
  end

  defp prepare(session) do
    %{"status" => "ok"} =
      invoke(
        session,
        "source",
        source_args("put", %{
          "source_id" => @source,
          "generation" => 1,
          "expected_revision" => 0,
          "title" => "Release policy",
          "text" => @text,
          "uri" => "local:lifecycle",
          "observed_at_ms" => 1,
          "event_at_ms" => nil,
          "expires_at_ms" => nil
        })
      )

    [chunk] = inspect_source(session)["chunks"]
    chunk
  end

  defp inspect_source(session),
    do: invoke(session, "source", source_args("inspect", %{"source_id" => @source}))["coverage"]

  defp source_args(action, args), do: %{"store" => "notes", "action" => action, "args" => args}
  defp projection("graph"), do: "extract"
  defp projection("corpus"), do: "index"

  defp projection_args("graph", chunk),
    do: %{
      "store" => "notes",
      "extraction" => "assisted",
      "source_id" => @source,
      "generation" => 1,
      "max_edges" => 1,
      "chunks" => [chunk["chunk_id"]],
      "facts" => []
    }

  defp projection_args("corpus", chunk),
    do: %{
      "store" => "notes",
      "embedding" => "native",
      "source_id" => @source,
      "generation" => 1,
      "action" => "next",
      "chunks" => [chunk["chunk_id"]]
    }

  defp no_evidence(session, kind) do
    args =
      if kind == "graph",
        do: %{
          "store" => "notes",
          "entity" => "Release",
          "depth" => 1,
          "max_nodes" => 16,
          "max_edges" => 16,
          "top_k" => 10,
          "as_of_ms" => 10
        },
        else: %{
          "store" => "notes",
          "retrieval" => "words",
          "rerank" => nil,
          "query" => "Release",
          "top_k" => 10,
          "as_of_ms" => 10
        }

    %{"status" => "abstain", "evidence" => []} = invoke(session, "query", args)
  end

  defp invoke(session, command, args) do
    monitor = Process.monitor(session.pid)

    try do
      :ok =
        Session.invoke_export(
          session.pid,
          :command,
          "ext__" <> session.kind <> "__" <> command,
          args
        )

      await(session, monitor, command, args, System.monotonic_time(:millisecond) + 20_000)
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp await(session, monitor, command, args, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:ipse, pid, {:approval, ref, name, proposed}} when pid == session.pid ->
        :ok = approve(session, command, args, name, proposed)
        :ok = Session.approve(pid, ref, true)
        await(session, monitor, command, args, deadline)

      {:ipse, pid, {:done, :ok}} when pid == session.pid ->
        {:ok, value, _proof} =
          Ipse.Development.Evaluation.Session.complete_result(
            pid,
            Session.info(pid).extension_result
          )

        value

      {:ipse, pid, {:done, :cancelled}} when pid == session.pid ->
        %{"fixture_outcome" => "cancelled"}

      {:DOWN, ^monitor, :process, _, :killed} ->
        %{"fixture_outcome" => "owner_down"}

      {:ipse, pid, _} when pid == session.pid ->
        await(session, monitor, command, args, deadline)
    after
      remaining -> raise("Domain fixture invocation did not finish")
    end
  end

  defp approve(session, command, _args, name, proposed) do
    [entry] = session.config.extensions

    true =
      proposed["extension"] == session.kind and
        proposed["artifact_sha256"] == entry.identity["artifact_sha256"]

    request = proposed["request"]

    case name do
      "extension:state.put" ->
        true = command in ~w(source index extract)
        :ok = State.validate(request)
        "project" = request["scope"]
        {:ok, namespace} = State.namespace(entry.identity, "project", session.cwd, session.id)
        true = proposed["namespace"] == namespace

        true =
          request["value"]["partition"] == "lifecycle" and
            request["value"]["source_key"] == Ipse.JSON.sha256(@source)

      "extension:model.complete" ->
        "extract" = command
        "fixture_extract" = request["profile"]
        true = ModelCall.delegated_approval?(name, proposed)
        {:ok, selected, execution} = ModelCall.prepare(session.config, request)
        {:ok, destination} = Ipse.Provider.destination(selected)

        true =
          proposed["execution"] == execution and proposed["destination"] == destination and
            proposed["namespace"] == session.id

        %{"max_facts" => 1, "chunks" => [%{"text" => @text}]} = JSON.decode!(request["input"])

      "extension:embedding.create" ->
        true = command in ~w(index query)
        "fixture_embed" = request["profile"]
        true = request["inputs"] == if(command == "index", do: [@text], else: ["Release"])
        2 = request["version"]
        {:ok, binding} = EmbeddingCall.binding(session.config, request)
        true = proposed["effect_binding"] == binding and proposed["namespace"] == session.id

      _ ->
        raise("Unselected lifecycle effect")
    end

    :ok
  end

  defp http_start(mode) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    tag = make_ref()
    revision = if mode == :selection_b, do: :atomics.new(1, [])
    if revision, do: :atomics.put(revision, 1, 1)
    mode = if revision, do: {mode, revision}, else: mode

    {pid, monitor} =
      spawn_monitor(fn -> http_loop(listener, owner, Process.monitor(owner), tag, mode) end)

    %{
      pid: pid,
      monitor: monitor,
      listener: listener,
      tag: tag,
      base: "http://127.0.0.1:#{port}",
      model_revision: revision
    }
  end

  defp http_loop(listener, owner, owner_monitor, tag, mode) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        try do
          {target, body} = read_http(socket, "")
          send(owner, {:lifecycle_dispatched, tag, self(), body})
          :ok = :inet.setopts(socket, active: :once)

          respond =
            if mode in [:forget, :cancel, :owner_loss, :timeout] do
              receive do
                {:respond, ^tag} ->
                  true

                {:tcp_closed, ^socket} ->
                  send(owner, {:lifecycle_http_closed, tag, self()})
                  false

                {:DOWN, ^owner_monitor, :process, _, _} ->
                  false
              after
                25_000 -> raise("Lifecycle HTTP response barrier missing")
              end
            else
              true
            end

          if respond do
            response = response(target, body, mode)
            status = if mode == :unavailable, do: 503, else: 200

            :gen_tcp.send(socket, [
              "HTTP/1.1 #{status} Fixture\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n",
              response
            ])
          end
        after
          :gen_tcp.close(socket)
        end

        http_loop(listener, owner, owner_monitor, tag, mode)

      {:error, :closed} ->
        :ok
    end
  end

  defp response("/api/embed", _body, mode) do
    vectors =
      case mode do
        :malformed -> [[1.0]]
        {:selection_b, _} -> [[0.0, 1.0]]
        _ -> [[1.0, 0.0]]
      end

    model =
      case mode do
        {:selection_b, revision} ->
          if :atomics.get(revision, 1) == 2,
            do: "fixture-embedding-resolved-v2",
            else: "fixture-embedding"

        _ ->
          "fixture-embedding"
      end

    JSON.encode!(%{
      "model" => model,
      "embeddings" => vectors,
      "prompt_eval_count" => 8
    })
  end

  defp response("/api/chat", body, mode) do
    input = task_input(body)
    [chunk] = input["chunks"]

    facts = [
      %{
        "subject" => "Release",
        "predicate" => "requires",
        "object" => "quiescence",
        "polarity" => "positive",
        "chunk" => chunk["id"],
        "quote" => chunk["text"]
      }
    ]

    text = if mode == :malformed, do: "not a fact object", else: JSON.encode!(%{"facts" => facts})

    JSON.encode!(%{
      "model" => "fixture-text",
      "message" => %{"role" => "assistant", "content" => text},
      "done" => true,
      "done_reason" => "stop",
      "prompt_eval_count" => 8,
      "eval_count" => 8
    }) <> "\n"
  end

  defp task_input(body),
    do:
      body["messages"]
      |> List.last()
      |> Map.fetch!("content")
      |> String.split("\n", parts: 2)
      |> List.last()
      |> JSON.decode!()
      |> Map.fetch!("input")
      |> JSON.decode!()

  defp assert_request("graph", body) do
    %{"max_facts" => 1, "chunks" => [%{"text" => @text}]} = task_input(body)
    "object" = body["format"]["type"]
    ["facts"] = body["format"]["required"]
    1 = body["format"]["properties"]["facts"]["maxItems"]
  end

  defp assert_request("corpus", body), do: [@text] = body["input"]

  defp read_http(socket, bytes) do
    true = byte_size(bytes) <= 65_536

    case :binary.split(bytes, "\r\n\r\n") do
      [header, body] ->
        [line | fields] = String.split(header, "\r\n")
        ["POST", target, _] = String.split(line, " ")

        headers =
          Map.new(fields, fn field ->
            [key, value] = String.split(field, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        count = String.to_integer(headers["content-length"])

        if byte_size(body) >= count do
          {target, JSON.decode!(binary_part(body, 0, count))}
        else
          {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
          read_http(socket, bytes <> more)
        end

      _ ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
        read_http(socket, bytes <> more)
    end
  end

  defp dispatched(http) do
    receive do
      {:lifecycle_dispatched, tag, handler, body} when tag == http.tag ->
        %{handler: handler, body: body}
    after
      15_000 -> raise("Provider dispatch barrier missing")
    end
  end

  defp closed(http, handler) do
    receive do
      {:lifecycle_http_closed, tag, ^handler} when tag == http.tag -> :ok
    after
      5000 -> raise("Provider socket cleanup unconfirmed")
    end
  end

  defp no_dispatch(http) do
    receive do
      {:lifecycle_dispatched, tag, _, _} when tag == http.tag ->
        raise("Unexpected provider dispatch")
    after
      0 -> :ok
    end
  end

  defp http_stop(http) do
    :gen_tcp.close(http.listener)
    Process.exit(http.pid, :shutdown)

    receive do
      {:DOWN, ref, :process, _, reason} when ref == http.monitor ->
        if reason in [:normal, :shutdown], do: :ok, else: {:error, :fixture_failed}
    after
      5000 -> {:error, :fixture_cleanup_unconfirmed}
    end
  end
end
