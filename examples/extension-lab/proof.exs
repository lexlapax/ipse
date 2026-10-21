Code.require_file("spec.exs", __DIR__)

defmodule IpseLab.Proof do
  @moduledoc false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Store, Config, Registry}
  @core_reference __DIR__ |> Path.join("FROZEN_CORE") |> File.read!() |> String.trim()

  def run_installed(artifacts) do
    root = Path.join(System.tmp_dir!(), "ipse-lab-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)

    try do
      release = to_string(:code.root_dir())
      wrapper = Path.join(release, "ipse")

      for name <- ~w(memory lookup),
          do: cli!(wrapper, ["extension", "import", Path.join(artifacts, name)], release)

      operator = Path.join(root, "operator.json")
      File.write!(operator, :json.encode(IpseLab.Spec.operator(artifacts)))
      File.chmod!(operator, 0o600)

      fixture = %{
        "version" => 1,
        "cases" => [
          %{
            "id" => "temporary-tool",
            "kind" => "tool",
            "name" => "ext__memory__remember",
            "arguments" => %{"text" => "entity: Temporary"},
            "expect" => %{"status" => "ok", "requests" => 2, "context_contains" => "supervisors"}
          },
          %{
            "id" => "project-export",
            "kind" => "command",
            "name" => "ext__memory__export",
            "arguments" => %{},
            "expect" => %{"status" => "ok", "requests" => 0}
          }
        ]
      }

      fixture_path = Path.join(root, "scenarios.json")
      File.write!(fixture_path, :json.encode(fixture))

      output =
        cli!(
          wrapper,
          [
            "extension",
            "check",
            "--config",
            operator,
            "--fixture",
            fixture_path,
            "--extension",
            "memory",
            "--extension",
            "lookup",
            "--no-project-config",
            "--yes"
          ],
          release
        )

      lines = String.split(output, "\n")
      start = Enum.find_index(lines, &(&1 == "{")) || raise("CLI conformance report missing")
      cli = lines |> Enum.drop(start) |> Enum.join("\n") |> :json.decode()
      true = cli["passed"] and cli["safe_to_continue"] and cli["case_count"] == 2
      Map.put(run(artifacts), "temporary_cli_selection", true)
    after
      File.rm_rf!(root)
    end
  end

  defp cli!(command, arguments, cwd) do
    case System.cmd(command, arguments, cd: cwd, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, code} -> raise("Extension lab CLI exited #{code}: " <> output)
    end
  end

  defmodule Model do
    def complete(config, messages, _tools, emit) do
      send(config.lab_owner, {:lab_model, config.lab_tag, messages})
      emit.({:reason, "Synthetic hidden reasoning"})

      if config[:lab_usage],
        do:
          Enum.each(
            1..3,
            &emit.({:provider_usage, %{"input_tokens" => 1, "output_tokens" => &1}})
          )

      assistant =
        if is_binary(config[:lab_tool]) and not Enum.any?(messages, &(&1["role"] == "tool")) do
          %{
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              %{
                "id" => "lab-tool",
                "type" => "function",
                "function" => %{
                  "name" => config.lab_tool,
                  "arguments" => ~s({"text":"entity: ToolCreated"})
                }
              }
            ]
          }
        else
          %{
            "role" => "assistant",
            "content" => "Synthetic answer",
            "provider_data" => %{"native" => "opaque-native-fixture"}
          }
        end

      if assistant["content"] != "", do: emit.({:text, assistant["content"]})

      {:ok, assistant,
       if(config[:lab_usage], do: %{"input_tokens" => 1, "output_tokens" => 3}, else: %{})}
    end
  end

  def run(artifacts) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    kernel = kernel_digest()
    root = Path.join(System.tmp_dir!(), "ipse-extension-lab-#{nonce()}")
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    Process.put(:lab_sessions, [])
    Process.put(:lab_checks, [])

    try do
      home = Path.join(root, "home")
      cwd = Path.join(root, "workspace")
      File.mkdir_p!(cwd)

      installed =
        for name <- ~w(memory memory-v2 lookup metadata observer tool_observer text_observer),
            into: %{} do
          {:ok, artifact} =
            Store.import(Path.join(artifacts, name), Path.join(home, "extensions/artifacts"))

          {name, artifact}
        end

      c = %{
        root: root,
        home: home,
        cwd: cwd,
        dir: Path.join(root, "sessions"),
        installed: installed
      }

      disabled = config(c, enabled: false)
      {inactive, tag} = start(c, disabled)
      prompt(inactive, "entity: Disabled")
      _ = model(tag)

      checked(
        "disabled_no_domain_actions",
        not Enum.any?(events(c, inactive), &String.starts_with?(&1["type"], "extension_"))
      )

      :ok = Session.close(inactive)

      cfg = config(c)
      {pid, tag} = start(c, cfg)

      stats_exports =
        Session.exports(pid)["entries"] |> Enum.filter(&(&1["name"] == "ext__memory__stats"))

      checked(
        "stats_is_operator_command_only",
        Enum.map(stats_exports, & &1["stage"]) == ["invoke.command"]
      )

      stats(
        c,
        pid,
        %{"sources" => 0, "entities" => 0, "links" => 0, "revision" => 0, "deleted" => true},
        "missing"
      )

      original = "entity: Ada; link: Ada -> OTP"
      prompt(pid, original)
      first_messages = model(tag)

      checked(
        "effective_input_distinct",
        String.contains?(List.last(first_messages)["content"], "Effective-only annotation")
      )

      checked(
        "capture_does_not_change_admitted_request",
        not String.contains?(hd(first_messages)["content"], "Known entities: Ada") and
          not String.contains?(Enum.at(first_messages, 1)["content"], "Known entities: Ada")
      )

      first = command(pid, "export", %{})["value"]
      graph = first["value"]

      stats(
        c,
        pid,
        %{
          "sources" => 1,
          "entities" => 2,
          "links" => 1,
          "revision" => first["revision"],
          "deleted" => false
        },
        "populated"
      )

      checked(
        "graph_extraction",
        graph["entities"] == ["Ada", "OTP"] and length(graph["links"]) == 1
      )

      checked(
        "original_source_provenance",
        Enum.all?(
          graph["sources"],
          &(&1["view"] == "prompt.original" and &1["source"]["event_id"] == &1["id"] and
              &1["package_version"] == "0.1.0")
        )
      )

      prompt(pid, original)
      second_messages = model(tag)

      checked(
        "awaited_recall",
        Enum.at(second_messages, 1)["role"] == "user" and
          String.contains?(Enum.at(second_messages, 1)["content"], "Known entities: Ada, OTP") and
          not String.contains?(hd(second_messages)["content"], "Known entities: Ada, OTP")
      )

      second = command(pid, "export", %{})["value"]

      checked(
        "identical_prompts_are_distinct_sources",
        length(second["value"]["sources"]) == 2 and
          length(Enum.uniq_by(second["value"]["sources"], & &1["id"])) == 2
      )

      catchup(pid)
      repeated = command(pid, "export", %{})["value"]
      checked("catchup_deduplicates_without_write", repeated == second)
      recall = command(pid, "recall", %{"text" => "Ada"})

      checked(
        "explicit_recall_and_service",
        recall["status"] == "recalled" and recall["value"]["memory_items"] == 1
      )

      :ok =
        Session.invoke_export(pid, :command, "ext__memory__workflow", %{"path" => "lab-note.txt"})

      {:question, question} = drive(pid, :pause)
      id = Session.info(pid).id
      before = File.read!(Path.join(c.dir, id <> ".jsonl"))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)

      receive do
        {:DOWN, ^ref, :process, ^pid, :killed} -> :ok
      after
        2_000 -> raise "Lab owner did not stop"
      end

      {resumed, _} = start(c, cfg, id)
      {:question, ^question} = drive(resumed, :pause)
      checked("question_resume_is_inert", File.read!(Path.join(c.dir, id <> ".jsonl")) == before)
      :ok = Session.answer(resumed, question, %{"choice" => "second"})
      :ok = drive(resumed, :deny)
      denied = Session.info(resumed).extension_result["value"]

      checked(
        "question_is_not_write_approval",
        denied["status"] == "denied" and not File.exists?(Path.join(c.cwd, "lab-note.txt"))
      )

      :ok =
        Session.invoke_export(resumed, :command, "ext__memory__workflow", %{
          "path" => "lab-note.txt"
        })

      {:question, next_question} = drive(resumed, :pause)
      :ok = Session.answer(resumed, next_question, %{"choice" => "first"})
      :ok = drive(resumed, :allow)

      checked(
        "approved_workflow",
        File.read!(Path.join(c.cwd, "lab-note.txt")) == "Operator selected first\n"
      )

      checked(
        "workflow_needs_no_model_request",
        Session.info(resumed).accounting["request_count"] == 2
      )

      %{"status" => "forgotten"} = command(resumed, "forget", %{"entity" => "Ada"})
      forgotten = command(resumed, "export", %{})["value"]
      catchup(resumed)

      checked(
        "catchup_does_not_revive_forgotten_sources",
        command(resumed, "export", %{})["value"] == forgotten and
          forgotten["value"]["sources"] == []
      )

      %{"status" => "stored"} = command(resumed, "remember", %{"text" => "entity: Grace"})
      state = command(resumed, "export", %{})["value"]
      :ok = Session.close(resumed)
      {shared, _} = start(c, cfg)
      checked("project_state_crosses_sessions", command(shared, "export", %{})["value"] == state)
      session_cfg = config(c, scope: "session")
      {scoped, _} = start(c, session_cfg)
      %{"status" => "stored"} = command(scoped, "remember", %{"text" => "entity: SessionOnly"})
      :ok = Session.close(scoped)
      {other_scoped, _} = start(c, session_cfg)
      checked("session_scope_isolated", command(other_scoped, "export", %{})["value"]["deleted"])
      :ok = Session.close(other_scoped)

      versions_cfg = config(c, versions: true)
      {versions, _} = start(c, versions_cfg)

      %{"status" => "stored"} =
        command(versions, "remember", %{"text" => "entity: NewVersion"}, "memory_v2")

      checked(
        "concurrent_versions_keep_namespaces",
        command(versions, "export", %{}, "memory")["value"] == state and
          command(versions, "export", %{}, "memory_v2")["value"]["value"]["entities"] == [
            "NewVersion"
          ]
      )

      :ok = Session.close(versions)
      %{"status" => "forgotten"} = command(shared, "forget", %{"entity" => "all"})
      %{"status" => "blocked"} = command(shared, "remember", %{"text" => "entity: Ada"})

      checked(
        "delete_tombstone_blocks_automatic_revival",
        command(shared, "export", %{})["value"]["deleted"]
      )

      deleted = command(shared, "export", %{})["value"]

      stats(
        c,
        shared,
        %{
          "sources" => 0,
          "entities" => 0,
          "links" => 0,
          "revision" => deleted["revision"],
          "deleted" => true
        },
        "deleted"
      )

      checked("stats_preserves_tombstone", command(shared, "export", %{})["value"] == deleted)

      id = Session.info(shared).id
      :ok = Session.close(shared)
      {:ok, _} = Ipse.Diagnostics.saved(c.dir, id)
      checked("saved_receipts_validate", true)
      stress(c)

      checked(
        "domain_modules_never_loaded_in_host",
        Enum.all?(
          [
            IpseLab.Memory,
            IpseLab.Lookup,
            IpseLab.Metadata,
            IpseLab.Observer,
            IpseLab.ToolObserver,
            IpseLab.TextObserver
          ],
          &(:code.is_loaded(&1) == false)
        )
      )

      checked("kernel_bytes_unchanged", kernel_digest() == kernel)

      %{
        "version" => 1,
        "core_reference" => @core_reference,
        "kernel_digest" => kernel,
        "fixture_provider" => "synthetic",
        "safe_to_continue" => false,
        "expected_terminal_cleanup" => "unconfirmed",
        "checks" => Map.new(Process.get(:lab_checks)),
        "artifacts" => Map.new(installed, fn {name, artifact} -> {name, artifact.digest} end)
      }
    after
      Enum.each(Process.get(:lab_sessions, []), fn pid ->
        if Process.alive?(pid), do: Session.close(pid)
      end)

      File.rm_rf!(root)
    end
  end

  defp config(c, options \\ []) do
    memory = c.installed["memory"]
    lookup = c.installed["lookup"]
    metadata = c.installed["metadata"]
    observer = c.installed["observer"]
    tool_observer = c.installed["tool_observer"]
    text_observer = c.installed["text_observer"]
    memory_id = options[:instance] || "memory"
    enabled = Keyword.get(options, :enabled, true)

    instances = [
      instance(
        memory_id,
        memory.digest,
        %{
          "scope" => options[:scope] || "project",
          "capture" => true,
          "recall" => true,
          "bad_recall" => options[:bad_recall] == true
        },
        enabled
      ),
      instance(
        "lookup",
        lookup.digest,
        %{
          "text" => "Synthetic corpus: supervisors own dependent processes.",
          "uri" => "fixture:supervision",
          "fail" => options[:fail_lookup] == true
        },
        enabled
      ),
      instance("metadata", metadata.digest, %{}, enabled),
      instance(
        "annotation",
        "builtin:prompt-annotation:1",
        %{"text" => "Effective-only annotation"},
        enabled
      ),
      instance("observer", observer.digest, %{"hang" => true}, options[:observer] == true),
      instance("tool_observer", tool_observer.digest, %{}, options[:watch_tools] == true),
      instance("text_observer", text_observer.digest, %{}, options[:watch_text] == true)
    ]

    trust = [
      trust(memory, [
        %{
          "caller" => memory_id,
          "alias" => "lookup",
          "target" => "lookup",
          "artifact" => lookup.digest,
          "service" => "query"
        }
      ]),
      trust(lookup),
      trust(metadata),
      trust(observer),
      trust(tool_observer),
      trust(text_observer),
      %{
        "artifact" => "builtin:prompt-annotation:1",
        "capabilities" => ["transform.prompt"],
        "allow_project" => false,
        "allow_children" => false
      }
    ]

    {instances, trust} =
      if options[:versions] do
        v2 = c.installed["memory-v2"]

        {instances ++
           [
             instance(
               "memory_v2",
               v2.digest,
               %{
                 "scope" => "project",
                 "capture" => false,
                 "recall" => false,
                 "bad_recall" => false
               },
               true
             )
           ],
         trust ++
           [
             trust(v2, [
               %{
                 "caller" => "memory_v2",
                 "alias" => "lookup",
                 "target" => "lookup",
                 "artifact" => lookup.digest,
                 "service" => "query"
               }
             ])
           ]}
      else
        {instances, trust}
      end

    data = %{"version" => 1, "extensions" => instances, "extension_trust" => trust}
    path = Path.join(c.root, "operator.json")
    File.write!(path, :json.encode(data))
    File.chmod!(path, 0o600)
    {:ok, catalog} = Config.resolve([%{scope: "operator", path: path, data: data}], [])
    {:ok, entries} = Registry.prepare(catalog, c.home)

    %{
      provider: :demo,
      model: "extension-lab-fixture",
      provider_module: Model,
      home: c.home,
      approval: :ask,
      compact: false,
      context_bytes: 65_536,
      operator_questions: true,
      extensions: entries,
      lab_owner: self(),
      lab_tag: nonce()
    }
  end

  defp stress(c) do
    race_cfg = config(c, instance: "race")
    {delayed, _} = start(c, race_cfg)
    :ok = Session.prompt(delayed, "entity: Delayed")
    ref = approval(delayed)
    {forgetter, _} = start(c, race_cfg)
    %{"status" => "forgotten"} = command(forgetter, "forget", %{"entity" => "all"}, "race")
    :ok = Session.approve(delayed, ref, true)
    :ok = drive(delayed, :allow)

    checked(
      "delayed_write_conflicts_after_forget",
      Enum.any?(
        events(c, delayed),
        &match?(
          %{"type" => "extension_action_result", "outcome" => %{"status" => "conflict"}},
          &1
        )
      ) and command(forgetter, "export", %{}, "race")["value"]["deleted"]
    )

    :ok = Session.close(delayed)
    :ok = Session.close(forgetter)

    abrupt_cfg = config(c, instance: "abrupt")
    {abrupt, _} = start(c, abrupt_cfg)
    :ok = Session.prompt(abrupt, "entity: Interrupted")
    _ = approval(abrupt)
    id = Session.info(abrupt).id
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)
    ref = Process.monitor(abrupt)
    Process.exit(abrupt, :kill)

    receive do
      {:DOWN, ^ref, :process, ^abrupt, :killed} -> :ok
    after
      2_000 -> raise "Lab abrupt owner did not stop"
    end

    {resumed, _} = start(c, abrupt_cfg, id)

    checked(
      "interrupted_capture_idle_resume_no_replay",
      Session.info(resumed).phase == :idle and File.read!(path) == before
    )

    checked(
      "unapproved_capture_has_no_write",
      command(resumed, "export", %{}, "abrupt")["value"]["deleted"]
    )

    :ok = Session.close(resumed)

    {tools, _} =
      start(
        c,
        config(c, instance: "tools", watch_tools: true)
        |> Map.put(:lab_tool, "ext__tools__remember")
      )

    prompt(tools, "Exercise the explicit memory tool")

    eventually(fn ->
      Enum.count(events(c, tools), &(&1["type"] == "extension_feed_delivery_result")) == 4
    end)

    checked("installed_private_tool_views_acknowledged", true)

    checked(
      "model_selected_extension_tool",
      command(tools, "export", %{}, "tools")["value"]["value"]["entities"] == ["ToolCreated"] and
        Session.info(tools).accounting["request_count"] == 2
    )

    :ok = Session.close(tools)

    {text, _} = start(c, config(c, enabled: false, watch_text: true))
    prompt(text, "Exercise installed v2 visible text")

    eventually(fn ->
      case Map.values(:sys.get_state(text).extension_text) do
        [%{pid: consumer, closed: false}] ->
          try do
            state = :sys.get_state(consumer)
            state.frames == 3 and state.bytes == byte_size("Synthetic answer")
          catch
            :exit, _ -> false
          end

        _ ->
          false
      end
    end)

    checked("installed_v2_text_acknowledged", true)
    :ok = Session.close(text)

    {failed, _} = start(c, config(c, instance: "failure", bad_recall: true))
    :ok = Session.prompt(failed, "required recall must fail")
    :error = drive(failed, :allow)

    checked(
      "required_recall_failure_prevents_inference",
      Session.info(failed).accounting["request_count"] == 0
    )

    :ok = Session.close(failed)

    observer_cfg =
      config(c, enabled: false, observer: true)
      |> Map.put(:provider, :ollama)
      |> Map.put(:lab_usage, true)

    {observed, _} = start(c, observer_cfg)
    prompt(observed, "Synthetic usage burst")
    eventually(fn -> Enum.any?(events(c, observed), &(&1["type"] == "extension_feed_closed")) end)
    [closed] = Enum.filter(events(c, observed), &(&1["type"] == "extension_feed_closed"))

    if closed["reason"] != "capacity",
      do:
        raise(
          "Unexpected synthetic queue closure: " <>
            inspect(Map.take(closed, ~w(reason admitted acknowledged cleanup_confirmed)))
        )

    checked(
      "queue_saturation_is_visible",
      closed["reason"] == "capacity" and closed["acknowledged"] == 0 and
        closed["gap_source"] != nil
    )

    id = Session.info(observed).id
    :ok = Session.close(observed)
    before = File.read!(Path.join(c.dir, id <> ".jsonl"))
    {idle, _} = start(c, observer_cfg, id)

    checked(
      "feed_resume_does_not_reenroll",
      Session.diagnostics(idle)["extension_feeds"]["feeds"] == [] and
        File.read!(Path.join(c.dir, id <> ".jsonl")) == before
    )

    :ok = Session.close(idle)

    {crashed, _} = start(c, config(c, instance: "crash", fail_lookup: true))
    :ok = Session.prompt(crashed, "crashed required service must not infer or retry")
    :error = drive(crashed, :allow)

    checked(
      "service_crash_prevents_inference",
      Session.info(crashed).accounting["request_count"] == 0
    )

    checked(
      "terminal_crash_cleanup_is_not_promoted",
      Session.close(crashed) == {:error, :cleanup_unconfirmed}
    )
  end

  defp approval(pid) do
    receive do
      {:ipse, ^pid, {:approval, ref, "extension:state.put", _}} -> ref
      {:ipse, ^pid, {:done, _}} -> raise "Lab expected a separate storage approval"
      {:ipse, ^pid, _} -> approval(pid)
    after
      15_000 -> raise "Lab storage approval missing"
    end
  end

  defp eventually(fun, attempts \\ 1000)
  defp eventually(fun, 0), do: checked("bounded asynchronous completion", fun.())

  defp eventually(fun, attempts) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, attempts - 1)
        )
  end

  defp instance(id, artifact, options, enabled),
    do: %{
      "instance" => id,
      "artifact" => artifact,
      "enabled" => enabled,
      "options" => options,
      "order" => 0,
      "lifetime" => "persistent"
    }

  defp trust(artifact, routes \\ []) do
    base = %{
      "artifact" => artifact.digest,
      "capabilities" => artifact.manifest["capabilities"],
      "allow_project" => false,
      "allow_children" => false
    }

    if routes == [], do: base, else: Map.put(base, "service_bindings", routes)
  end

  defp start(c, cfg, id \\ nil, attempts \\ 100) do
    case DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Session, config: cfg, cwd: c.cwd, state_dir: c.dir, id: id, subscriber: self()}
         ) do
      {:ok, pid} ->
        Process.put(:lab_sessions, [pid | Process.get(:lab_sessions)])
        {pid, cfg.lab_tag}

      {:error, :session_locked} when attempts > 0 ->
        Process.sleep(10)
        start(c, cfg, id, attempts - 1)

      error ->
        raise "Extension lab session admission failed: #{inspect(error)}"
    end
  end

  defp prompt(pid, text) do
    :ok = Session.prompt(pid, text)
    :ok = drive(pid, :allow)
  end

  defp command(pid, command, arguments, instance \\ "memory") do
    :ok = Session.invoke_export(pid, :command, "ext__#{instance}__#{command}", arguments)
    :ok = drive(pid, :allow)
    Session.info(pid).extension_result["value"]
  end

  defp stats(c, pid, expected, stage) do
    before = events(c, pid)
    count = Session.info(pid).accounting["request_count"]
    result = command(pid, "stats", %{})
    added = events(c, pid) |> Enum.drop(length(before))

    actions =
      for %{"type" => "extension_action_intent", "request" => request} <- added, do: request["op"]

    checked("stats_" <> stage, result == %{"status" => "ok", "value" => expected})

    checked(
      "stats_" <> stage <> "_read_only",
      actions == ["state.get"] and Session.info(pid).accounting["request_count"] == count
    )
  end

  defp drive(pid, policy) do
    receive do
      {:ipse, ^pid, {:approval, ref, _, _}} ->
        :ok = Session.approve(pid, ref, policy == :allow)
        drive(pid, policy)

      {:ipse, ^pid, {:question, id, _}} when policy == :pause ->
        {:question, id}

      {:ipse, ^pid, {:done, :ok}} ->
        :ok

      {:ipse, ^pid, {:done, :error}} ->
        :error

      {:ipse, ^pid, _} ->
        drive(pid, policy)
    after
      15_000 -> raise "Extension lab operation timed out"
    end
  end

  defp model(tag) do
    receive do
      {:lab_model, ^tag, messages} -> messages
    after
      1_000 -> raise "Extension lab model observation missing"
    end
  end

  defp catchup(pid, cursor \\ 0, snapshot \\ nil, remaining \\ 8) do
    result = command(pid, "catchup", %{"cursor" => cursor, "snapshot" => snapshot, "pages" => 8})
    next = result["value"]["next"]

    if next != nil and remaining > 0,
      do: catchup(pid, next, result["value"]["snapshot"], remaining - 1),
      else:
        checked(
          "bounded_history_range_finished",
          next == nil and result["value"]["coverage"] == "recorded_views_only"
        )
  end

  defp events(c, pid) do
    {:ok, rows} = Journal.load(c.dir, Session.info(pid).id)
    rows
  end

  defp checked(label, value) do
    unless value == true, do: raise("Extension lab assertion failed: " <> label)
    Process.put(:lab_checks, [{label, true} | Process.get(:lab_checks)])
    :ok
  end

  defp kernel_digest do
    entries =
      for module <- Application.spec(:ipse, :modules) do
        {^module, beam, _} = :code.get_object_code(module)
        {Atom.to_string(module), :crypto.hash(:sha256, beam)}
      end

    :crypto.hash(:sha256, :erlang.term_to_binary(Enum.sort(entries)))
    |> Base.encode16(case: :lower)
  end

  defp nonce, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
