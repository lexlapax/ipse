defmodule Ipse.Session do
  alias Ipse.Session.Turn

  @moduledoc "One supervised owner per agent conversation. I/O runs in monitored tasks."

  use GenServer

  alias Ipse.Journal
  alias Ipse.Workspace
  alias Ipse.Tools
  alias Ipse.Tools.Questions

  alias Ipse.Journal.Writer

  alias Ipse.Session.Saved

  alias Ipse.Session.Invocation, as: CurrentInvocation

  alias Ipse.Extension.{
    Projection,
    Catalog,
    Invocation,
    ModelCall,
    EmbeddingCall,
    DecisionCall,
    Subscriptions,
    Feeds,
    FeedChannel,
    ResultSource
  }

  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)

    cond do
      not Ipse.Extension.Registry.valid_entries?(config) ->
        {:error, :invalid_extension_configuration}

      Ipse.Observability.runtime(config) != :ok ->
        {:error, :invalid_observability_policy}

      Map.get(config, :extensions, []) == [] ->
        GenServer.start_link(__MODULE__, opts)

      true ->
        task = owned_task(fn -> Ipse.Extension.Registry.revalidate(config) end)

        result = Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill)
        Ipse.Session.Resources.close_task(task.pid)

        case result do
          {:ok, :ok} -> GenServer.start_link(__MODULE__, opts)
          _ -> {:error, :extension_admission_refused}
        end
    end
  end

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}, restart: :temporary}

  def prompt(pid, text), do: GenServer.call(pid, {:prompt, text})
  @doc "Submit exact observed text with a volatile, single-use input witness."
  def prompt(pid, text, witness), do: GenServer.call(pid, {:prompt, text, witness})

  @doc "Observe one native terminal input for the current idle Session generation."
  def observe_input(pid, display, timeout \\ 120_000) do
    with true <- is_integer(timeout) and timeout in 1000..600_000,
         {:ok, lease} <- GenServer.call(pid, {:observe_input, display, timeout}) do
      Ipse.Session.Input.await(lease, timeout)
    else
      false -> {:error, :operator_input_unavailable}
      error -> error
    end
  catch
    :exit, _ -> {:error, :operator_input_unavailable}
  end

  def approve(pid, ref, allowed), do: GenServer.call(pid, {:approve, ref, allowed})
  def permissions(pid), do: GenServer.call(pid, :permissions)
  def clear_permissions(pid), do: GenServer.call(pid, :clear_permissions)
  def answer(pid, id, answers), do: GenServer.call(pid, {:answer, id, answers})
  @doc false
  def open_input_channel(pid, reader), do: GenServer.call(pid, {:open_input_channel, reader})
  @doc false
  def observe_channel(pid, channel, request, timeout \\ 120_000) do
    with {:ok, lease} <- GenServer.call(pid, {:observe_channel, channel, request, timeout}) do
      Ipse.Session.Input.await(lease, timeout)
    end
  end

  @doc false
  def cancel_input_read(pid, channel), do: GenServer.call(pid, {:cancel_input_read, channel})
  @doc false
  def stage_input(pid, channel, text, witness),
    do: GenServer.call(pid, {:stage_input, channel, text, witness})

  @doc false
  def discard_input(pid, channel, witness),
    do: GenServer.call(pid, {:discard_input, channel, witness})

  @doc false
  def render_question(pid, channel, item),
    do: GenServer.call(pid, {:render_question, channel, item})

  @doc false
  def answer_observed(pid, channel, render, text, witness),
    do: GenServer.call(pid, {:answer_observed, channel, render, text, witness})

  @doc false
  def question_eof(pid, channel), do: GenServer.call(pid, {:question_eof, channel}, 10_000)

  @doc "Read only this subscribed client's admitted source window; tokens grant no authority."
  def sources(pid, operation, request),
    do: GenServer.call(pid, {:session_sources, operation, request})

  @doc false
  def source_snapshot(s) do
    case Writer.source_query(s.journal_writer, :snapshot) do
      {:ok, snapshot} -> snapshot
      _ -> %{"version" => 1, "available" => false}
    end
  end

  def cancel(pid), do: GenServer.call(pid, :cancel, 10_000)
  def materialize_result(pid, delivery), do: ResultSource.materialize_session(pid, delivery)
  def read_saved_result(pid, request), do: ResultSource.read_session(pid, request)

  def close(pid), do: close(pid, false)

  @doc "Require the owned session's actual cleanup acknowledgment as well as process exit."

  def close_confirmed(pid), do: close(pid, true)

  defp close(pid, require_ack) do
    monitor = Process.monitor(pid)
    drain_observations(pid, System.monotonic_time(:millisecond) + 500)

    result =
      try do
        GenServer.call(pid, :close, 5_000)
      catch
        :exit, _ ->
          if require_ack or Process.alive?(pid), do: {:error, :cleanup_unconfirmed}, else: :ok
      end

    result =
      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> result
      after
        1_000 -> {:error, :cleanup_unconfirmed}
      end

    Process.demonitor(monitor, [:flush])
    result
  end

  defp drain_observations(pid, deadline) do
    try do
      %{idle: idle, capture: capture} = GenServer.call(pid, :observation_drain_state, 500)

      if idle and capture["mode"] != "off" and
           Enum.any?(
             capture["sinks"],
             &(&1["closed"] == false and
                 (not &1["ready"] or &1["pending"] > 0))
           ) and
           System.monotonic_time(:millisecond) < deadline do
        Process.sleep(10)
        drain_observations(pid, deadline)
      end
    catch
      :exit, _ -> :ok
    end
  end

  def refresh_context(pid), do: GenServer.call(pid, :refresh_context)
  def info(pid), do: GenServer.call(pid, :info)

  defp input_binding(s),
    do: %{session_id: s.id, cwd: s.cwd, generation: s.input_generation}

  defp operator_binding(s, purpose, render),
    do: %{
      session_id: s.id,
      cwd: s.cwd,
      generation: s.operator_channel.generation,
      channel_id: s.operator_channel.id,
      purpose: purpose,
      render_id: render
    }

  defp operator_request(s, %{"kind" => "question", "render_id" => id} = request)
       when map_size(request) == 2 do
    case s.operator_render do
      %{"render_id" => ^id, "display" => display} -> {:ok, display, "question", id}
      _ -> :error
    end
  end

  defp operator_request(_s, %{"kind" => "prompt"} = request) when map_size(request) == 1,
    do: {:ok, "you> ", "prompt", nil}

  defp operator_request(_s, %{"kind" => "control", "display" => display} = request)
       when map_size(request) == 2 and is_binary(display) do
    {:ok, display, "control", nil}
  end

  defp operator_request(_, _), do: :error

  def diagnostics(pid), do: GenServer.call(pid, :diagnostics)
  def stop_observability(pid), do: GenServer.call(pid, :stop_observability)
  def stop_feeds(pid), do: GenServer.call(pid, :stop_feeds, :infinity)
  def subscribe_text(pid), do: GenServer.call(pid, :subscribe_text)
  def subscribe_text(pid, version), do: GenServer.call(pid, {:subscribe_text, version})
  def unsubscribe_text(pid, handle), do: GenServer.call(pid, {:unsubscribe_text, handle})

  def subscribe_text(pid, version, opts) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) in [[], [:required]] and
         is_boolean(Keyword.get(opts, :required, false)),
       do: GenServer.call(pid, {:subscribe_text, version, Keyword.get(opts, :required, false)}),
       else: {:error, :invalid_text_policy}
  end

  def exports(pid), do: GenServer.call(pid, :exports)

  def invoke_export(pid, kind, name, arguments),
    do: GenServer.call(pid, {:invoke_export, kind, name, arguments})

  @impl true

  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    requested_cwd = Keyword.fetch!(opts, :cwd)
    home = Map.get(config, :home) || System.get_env("IPSE_HOME") || Path.expand("~/.ipse")
    dir = Keyword.fetch!(opts, :state_dir) |> Path.expand()
    id = Keyword.get(opts, :id)
    owner_ref = if is_pid(opts[:owner]), do: Process.monitor(opts[:owner])

    with {:ok, handoff} <- handoff_option(opts),
         :ok <- extension_configuration(config),
         :ok <- Ipse.Observability.runtime(config),
         :ok <- Ipse.Usage.configuration(config),
         :ok <- ModelCall.configuration(config),
         :ok <- Ipse.Config.Profiles.embedding_configuration(config),
         :ok <- Ipse.Config.Decisions.configuration(config),
         :ok <- Ipse.Provider.validate_output_limit(config),
         :ok <- Ipse.Provider.Registry.validate_request(config),
         :ok <- provider_configuration(config),
         :ok <- Ipse.Usage.Budget.validate_configuration(config),
         {:ok, _journal_limits} <- Ipse.Journal.normalize_limits(config[:journal]),
         {:ok, cwd} <- Workspace.canonical_path(requested_cwd),
         true <- File.dir?(cwd),
         {:ok, _sandbox} <- Ipse.Tools.Sandbox.resolve(Map.get(config, :sandbox, :off), cwd),
         {:ok, id, _events, config} <- open(dir, id, cwd, config),
         {:ok, _} <- Registry.register(Ipse.Registry, {dir, id}, nil),
         {:ok, lock} <- acquire_lock(Path.join(dir, id <> ".lock"), 10),
         {:ok, locked_events} <- Journal.load(dir, id, config[:journal]),
         {:ok, config} <- Ipse.Usage.BudgetStore.attach(config, dir, id, opts[:id] == nil),
         {:ok, _} <- restore_context(locked_events),
         :ok <- Ipse.Observability.validate_events(locked_events, id),
         :ok <- Ipse.Extension.TextResources.validate_events(locked_events, id),
         :ok <- Subscriptions.validate_sources(dir, id, locked_events),
         {:ok, _validated_prefix} <- Saved.restore(locked_events, id),
         :ok <- Ipse.Session.SourceWindow.validate_sources(dir, id, locked_events),
         :ok <- Ipse.Usage.Budget.validate_sources(config, id, locked_events),
         :ok <- Journal.repair_tail(dir, id, config[:journal]),
         {:ok, events} <- Journal.load(dir, id, config[:journal]),
         {:ok, saved} <- Saved.restore(events, id),
         {:ok, source_window} <-
           Ipse.Session.SourceWindow.attach_effective_source(saved.source_window, dir, id),
         %{
           accounting: accounting,
           extension_state: extension_state,
           result_sources: result_sources,
           messages: messages,
           question: question
         } = saved,
         :ok <- question_available(question, config),
         {:ok, event_question} <- Invocation.restore_event_question(question, dir, id, events),
         {:ok, event_question} <-
           Subscriptions.restore_question(question, event_question, dir, id, events),
         {:ok, context_snapshot, context_is_new} <-
           workspace_snapshot(events, cwd, home, opts[:context_snapshot]),
         discovered =
           Workspace.discover_skills(
             cwd,
             Path.join(Path.expand(home), "skills"),
             skill_discovery_options(config)
           ),
         {:ok, skills, skills_saved} <- Workspace.restore_skills(events, discovered),
         {:ok, source_runtime} <- Ipse.Session.RuntimeLifecycle.restore(events, id),
         {:ok, source_tools} <- Ipse.Session.ToolLifecycle.restore(events, id),
         {:ok, writer} <- Writer.start(dir, id, self(), config[:journal]) do
      :ok = Writer.install_source_window(writer, source_window)
      :ok = Ipse.Session.Lock.track(writer, :writer)

      state = %{
        id: id,
        dir: dir,
        journal_writer: writer,
        journal_writer_ref: Process.monitor(writer),
        cwd: cwd,
        config: config,
        context_home: Path.expand(home),
        context_snapshot: context_snapshot,
        context_drift: Workspace.drift(context_snapshot),
        reported_model: nil,
        historical_model: saved.historical_model,
        subscriber: Keyword.fetch!(opts, :subscriber),
        skills: skills,
        skills_saved: skills_saved,
        skill_drift:
          if(skills == discovered,
            do: [],
            else: ["Skill catalog changed; use /context refresh to adopt current discovery."]
          ),
        messages: messages,
        extension_contributions: extension_state.contributions,
        compaction: nil,
        tool_decision:
          if(question && question[:kind] == :extension,
            do: question.parent["approval"],
            else: "not_decided"
          ),
        task: nil,
        prompt_from: nil,
        input_generation: Ipse.Usage.id(),
        operator_channel: nil,
        operator_render: nil,
        operator_answers: %{},
        operator_pieces: [],
        reference: saved.reference,
        task_cleanup_failed: false,
        job_ref: nil,
        phase: if(question, do: :question, else: :idle),
        calls: if(question && question.call, do: [question.call], else: []),
        question: question,
        approval: nil,
        permissions: Ipse.Session.Permissions.new(config),
        steps: if(question, do: question.steps, else: 0),
        tool_budget: Tools.restore_call_budget(messages),
        lock: lock,
        lock_guard: Ipse.Session.Lock.current(),
        lock_guard_ref: Process.monitor(Ipse.Session.Lock.current()),
        usage: %{},
        accounting: accounting,
        usage_reads: extension_state.usage_reads,
        child_usage: extension_state.child_usage,
        active_request: nil,
        extension_model: nil,
        last_request_id: saved.last_request_id,
        turn_id:
          if(question && question[:kind] == :extension,
            do: question.parent["payload"]["turn_id"],
            else: saved.turn_id || Ipse.Usage.id()
          ),
        text_stream: nil,
        text_stream_monitor: nil,
        text_stream_policy_ref: nil,
        text_required: false,
        extension_text: %{},
        extension_text_count: Ipse.Extension.TextResources.count(events),
        extension_text_turn: nil,
        extension_text_cleanup_failed: false,
        event_received: if(event_question, do: event_question.received),
        event_committed: if(event_question, do: event_question.effective),
        event_answer: if(event_question, do: event_question.answer),
        event_turn: if(event_question, do: event_question.turn),
        event_intent: if(event_question, do: event_question.intent),
        event_schedule: if(event_question, do: event_question.schedule, else: "before_request"),
        event_after_started: event_question != nil and event_question.schedule == "after_turn",
        event_count: Enum.count(events, &(&1["type"] == "extension_event_intent")),
        event_cleanup_failed: false,
        final:
          if(event_question && event_question.schedule == "after_turn",
            do: Saved.event_final(events, messages),
            else: Projection.presentation(events)
          ),
        extension_intent: nil,
        extension_result_sources: result_sources,
        extension_output: nil,
        extension_output_clock: nil,
        invocation: CurrentInvocation.restore(question, extension_state.effect_sources),
        extension_tool_context: nil,
        extension_mcp_context: nil,
        extension_result: Invocation.latest_display(events),
        extension_catalog: extension_catalog(config),
        extension_invocations: Invocation.count(events),
        mcp_tools: [],
        mcp_ready: false,
        mcp_resources: %{},
        delegation_resources: %{},
        delegation_workers: MapSet.new(),
        delegation_queue: [],
        delegation_effect: nil,
        delegation_claims: %{},
        delegations: 0,
        owner_ref: owner_ref,
        request_started_at: nil,
        observation: nil,
        lifecycle: nil,
        tool_lifecycle: nil,
        source_runtime_summary: Map.take(source_runtime, [:epoch, :count, :closed, :stopped]),
        source_tool_summary: Map.take(source_tools, [:count, :stopped]),
        source_resumed: opts[:id] != nil,
        feeds: Feeds.new(events, id)
      }

      state =
        %{
          state
          | reference:
              Ipse.Session.Reference.seed(
                state.reference,
                Ipse.Session.Context.admission_header(state),
                Ipse.Session.Context.admission_publishers(state)
              )
        }

      state =
        if handoff do
          record(state, handoff)
          %{state | messages: state.messages ++ [handoff["message"]]}
        else
          state
        end

      capture =
        Ipse.Observability.prepare(
          self(),
          config,
          id,
          &record(state, &1),
          Enum.count(events, &(&1["type"] == "diagnostic_sink_intent"))
        )

      state = %{state | observation: capture}
      state = if context_is_new, do: persist_context(state, context_snapshot, true), else: state
      state = if opts[:id] == nil, do: persist_skills(state, skills), else: state

      state =
        lifecycle_records(
          state,
          Ipse.Session.RuntimeLifecycle.open(config, capture.policy, events, id, opts[:id] != nil)
        )

      state =
        Turn.tool_records(
          state,
          Ipse.Session.ToolLifecycle.open(
            Map.put(config, :source_layout, nil),
            events,
            id,
            state.lifecycle,
            dir,
            question
          )
        )

      state =
        if question,
          do:
            question_wait(
              state,
              question,
              Ipse.Session.RuntimeLifecycle.question_source(events, question),
              saved.turn_id
            ),
          else: state

      if config[:semantic_admission]["status"] not in ["off", "active"] do
        notify(
          state,
          {:status,
           "Knowledge inactive: saved permission was not admitted (" <>
             config[:semantic_admission]["status"] <> ")."}
        )
      end

      if question, do: {:ok, state, {:continue, :question}}, else: {:ok, state}
    else
      false -> {:stop, :workspace_not_found}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp handoff_option(opts) do
    cond do
      not Keyword.has_key?(opts, :handoff) -> {:ok, nil}
      opts[:id] != nil -> {:error, :handoff_requires_fresh_session}
      true -> Ipse.Session.Saved.prepare_handoff(opts[:handoff])
    end
  end

  defp extension_configuration(config),
    do:
      if(Ipse.Extension.Registry.valid_entries?(config),
        do: :ok,
        else: {:error, :invalid_extension_configuration}
      )

  # Explicit application homes are commonly isolation fixtures. Shared discovery
  # requires a separate opt-in in that case; the CLI supplies the operator home.
  defp skill_discovery_options(config) do
    isolated_home? = Map.get(config, :home) || System.get_env("IPSE_HOME")
    default = if isolated_home?, do: nil, else: Workspace.operator_home()

    [operator_home: Map.get(config, :operator_home, default)] ++
      if(Map.has_key?(config, :shared_root), do: [shared_root: config.shared_root], else: [])
  end

  @impl true

  def handle_continue(:question, s) do
    notify(s, {:question, s.question.id, s.question.arguments})
    {:noreply, s}
  end

  @impl true

  def handle_call(
        {:extension_begin, ref, instance, stage},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_intent: nil, phase: phase} = s
      )
      when ref != nil and phase in [:extension_prompt, :extension_presentation] do
    expected =
      if phase == :extension_prompt, do: "transform.prompt", else: "transform.presentation"

    entry = Enum.find(Map.get(s.config, :extensions, []), &(&1.identity["instance"] == instance))
    input = if phase == :extension_prompt, do: List.last(s.messages)["content"], else: s.final

    if stage == expected and entry != nil and stage in entry.identity["capabilities"] and
         Ipse.Extension.Registry.live?(entry.identity) do
      intent = Projection.intent(entry.identity, stage, input, s.messages)
      record(s, intent)
      {:reply, {:ok, intent, input}, %{s | extension_intent: intent}}
    else
      {:reply, {:error, :extension_admission_refused}, s}
    end
  end

  def handle_call({:extension_begin, _, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_commit, ref, event},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_intent: intent, phase: phase} = s
      )
      when ref != nil and intent != nil and phase in [:extension_prompt, :extension_presentation] do
    with {:ok, expected} <- Projection.build(intent, event["input"], event["result"]),
         true <- expected == event,
         true <- phase != :extension_presentation or event["input"] == s.final,
         true <- Ipse.Extension.Registry.live?(intent["identity"]),
         {:ok, messages} <- Projection.apply(s.messages, event) do
      record(s, event)
      final = if phase == :extension_presentation, do: event["output"], else: s.final
      {:reply, :ok, %{s | messages: messages, final: final, extension_intent: nil}}
    else
      _ -> {:reply, {:error, :invalid_extension_projection}, s}
    end
  end

  def handle_call({:extension_commit, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_event_begin, ref, instance, subscription},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_events, event_intent: nil} = s
      )
      when ref != nil do
    with entry when is_map(entry) <-
           Enum.find(s.config.extensions, &(&1.identity["instance"] == instance)),
         declaration when is_map(declaration) <-
           Enum.find(entry.subscriptions, &(&1["id"] == subscription)),
         true <- s.event_count < 10_000 and Ipse.Extension.Registry.live?(entry.identity),
         true <- Invocation.event_schedule(declaration) == s.event_schedule,
         fact =
           (case declaration["event"] do
              "prompt.received" -> s.event_received
              "prompt.effective_committed" -> s.event_committed
              "answer.committed" -> s.event_answer
            end),
         true <- fact != nil,
         {intent, payload} =
           Subscriptions.intent(entry.identity, declaration, fact.source, fact.record, s.turn_id) do
      record(s, intent)
      s = %{s | event_intent: intent, event_count: s.event_count + 1}

      if declaration["mode"] == "job" do
        facts = %{
          received: s.event_received,
          effective: s.event_committed,
          answer: s.event_answer
        }

        case Invocation.prepare_event(s.config, entry, intent, payload, facts, s.id, s.turn_id) do
          {:ok, parent} when s.extension_invocations < 10_000 ->
            record(s, parent)

            {:reply, {:job, intent, entry, parent},
             %{
               s
               | invocation: %CurrentInvocation{parent: parent},
                 extension_invocations: s.extension_invocations + 1,
                 extension_mcp_context: nil
             }}

          _ ->
            {:reply, {:ok, intent, entry, nil}, s}
        end
      else
        {:reply, {:ok, intent, entry, payload}, s}
      end
    else
      _ -> {:reply, {:error, :event_admission_refused}, s}
    end
  end

  def handle_call(
        {:extension_event_commit, ref, result},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_events, event_intent: intent} = s
      )
      when ref != nil and intent != nil do
    if Subscriptions.valid_result?(result, intent) and
         result["outcome"] not in ~w(completed failed) and
         (result["outcome"] != "not_started" or is_nil(s.invocation.parent)) and
         (result["outcome"] != "acknowledged" or
            Ipse.Extension.Registry.live?(intent["identity"])) do
      record(s, result)

      if result["outcome"] != "acknowledged" and not intent["declaration"]["required"],
        do:
          notify(
            s,
            {:status,
             "Optional event subscriber did not acknowledge; inspect its saved delivery receipt."}
          )

      {:reply, :ok,
       %{
         s
         | event_intent: nil,
           event_cleanup_failed: s.event_cleanup_failed or not result["cleanup_confirmed"]
       }}
    else
      {:reply, {:error, :event_result_refused}, s}
    end
  end

  def handle_call({:extension_event_begin, _, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}
  def handle_call({:extension_event_commit, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_event_job_commit, ref, result},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_events, event_intent: delivery} =
          s
      )
      when ref != nil and delivery != nil do
    case CurrentInvocation.commit_event_job(s, result) do
      {:ok, next, outcome} -> {:reply, {:ok, outcome}, next}
      _ -> {:reply, {:error, :event_job_result_refused}, s}
    end
  end

  def handle_call({:extension_event_job_commit, _, _}, _, s),
    do: {:reply, {:error, :cancelled}, s}

  def handle_call({:mcp_register, ref, resource}, _from, %{job_ref: ref} = s) when ref != nil do
    monitor = Process.monitor(resource)
    {:reply, :ok, %{s | mcp_resources: Map.put(s.mcp_resources, resource, monitor)}}
  end

  def handle_call({:mcp_register, _, _}, _from, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:delegation_register, ref, child, id, origin_call},
        {worker, _},
        %{job_ref: ref, task: %{pid: coordinator}, phase: phase} = s
      )
      when ref != nil and phase in [:tool, :delegated_approval] do
    call = hd(s.calls)

    expected =
      if call["function"]["name"] == "delegate_parallel",
        do: [call["id"] <> "/0", call["id"] <> "/1"],
        else: [call["id"]]

    if (worker == coordinator or MapSet.member?(s.delegation_workers, worker)) and
         origin_call in expected do
      :ok = Ipse.Session.Lock.track_session(child)

      event = %{
        "type" => "delegation_started",
        "child_id" => id,
        "call_id" => call["id"],
        "origin_call_id" => origin_call
      }

      source =
        record_source(s, event)

      monitor = Process.monitor(child)
      notify(s, {:subagent, id, :started})

      {:reply, :ok,
       %{
         s
         | child_usage: Ipse.Extension.ChildUsage.apply_parent(s.child_usage, event),
           delegation_resources:
             Map.put(s.delegation_resources, child, %{
               monitor: monitor,
               id: id,
               worker: worker,
               source: source,
               turn: s.turn_id,
               request: s.last_request_id,
               job_ref: ref,
               started: System.monotonic_time(:millisecond),
               down: false,
               finished: false
             })
       }}
    else
      {:reply, {:error, :cancelled}, s}
    end
  end

  def handle_call(
        {:delegation_worker, ref, worker},
        {coordinator, _},
        %{job_ref: ref, task: %{pid: coordinator}} = s
      )
      when ref != nil do
    if MapSet.size(s.delegation_workers) < 2,
      do: {:reply, :ok, %{s | delegation_workers: MapSet.put(s.delegation_workers, worker)}},
      else: {:reply, {:error, :worker_limit}, s}
  end

  def handle_call(
        {:delegation_children, ref},
        {coordinator, _},
        %{job_ref: ref, task: %{pid: coordinator}} = s
      )
      when ref != nil,
      do: {:reply, Map.keys(s.delegation_resources), s}

  def handle_call({:delegation_worker, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}
  def handle_call({:delegation_children, _}, _, s), do: {:reply, [], s}

  def handle_call({:delegation_register, _, _, _, _}, _from, s),
    do: {:reply, {:error, :cancelled}, s}

  def handle_call({:delegation_finished, ref, child, status, reason, cleanup}, {worker, _}, s) do
    case s.delegation_resources[child] do
      %{worker: ^worker, job_ref: ^ref, finished: false} = resource when ref == s.job_ref ->
        event = Ipse.Tools.Delegation.child_finished(resource, status, reason, cleanup)

        if s.task != nil and Ipse.Tools.Delegation.valid_child_record?(event) do
          s = record_child_outcome(s, event)
          Process.demonitor(resource.monitor, [:flush])
          {:reply, :ok, next_delegated_approval(retire_child(s, child))}
        else
          {:reply, {:error, :cancelled}, s}
        end

      _ ->
        {:reply, {:error, :cancelled}, s}
    end
  end

  def handle_call(:info, _from, s) do
    info =
      Map.take(s, [:id, :cwd, :phase, :usage, :final])
      |> Map.put(:runtime, runtime(s))
      |> Map.put(
        :context,
        Ipse.Session.Context.manifest(
          s.context_snapshot,
          s.context_drift,
          s.skill_drift,
          s.skills
        )
      )
      |> Map.put(:sandbox, Ipse.Tools.Sandbox.info(Map.get(s.config, :sandbox, :off)))
      |> Map.put(:mcp, Enum.map(Map.get(s.config, :mcp_servers, []), &Ipse.MCP.Config.manifest/1))
      |> Map.put(:subagents, Ipse.Tools.Delegation.enabled?(s.config))
      |> Map.put(:configuration, Map.get(s.config, :configuration))
      |> Map.put(:extensions, Ipse.Extension.Registry.manifests(s.config))
      |> Map.put(:accounting, Ipse.Usage.snapshot(s.accounting))
      |> Map.put(:extension_result, s.extension_result)
      |> Map.put(:question, if(s.question, do: Map.take(s.question, [:id, :arguments])))

    {:reply, info, s}
  end

  def handle_call(:subscribe_text, from, s), do: handle_call({:subscribe_text, 1}, from, s)

  def handle_call({:subscribe_text, version}, from, s),
    do: handle_call({:subscribe_text, version, false}, from, s)

  def handle_call({:subscribe_text, version, required}, {consumer, _}, %{phase: :idle} = s)
      when version in [1, 2] and is_boolean(required) do
    s = Turn.ensure_text_stream(s)
    result = Turn.subscribe_text_stream(s.text_stream, consumer, version, required)

    next =
      if match?({:ok, _}, result), do: %{s | text_required: s.text_required or required}, else: s

    {:reply, result, next}
  end

  def handle_call({:subscribe_text, version, _}, _, s) when version not in [1, 2],
    do: {:reply, {:error, :unsupported_text_version}, s}

  def handle_call({:subscribe_text, _, _}, _, s), do: {:reply, {:error, :busy}, s}

  def handle_call(
        {:unsubscribe_text, %{server: stream, subscription_id: id} = handle},
        _,
        %{phase: :idle, text_stream: stream} = s
      )
      when is_pid(stream) and is_binary(id) do
    if Process.alive?(stream) do
      result =
        try do
          Ipse.Session.TextStream.unsubscribe(handle)
        catch
          :exit, _ -> {:error, :text_stream_unavailable}
        end

      {:reply, result, s}
    else
      if s.text_stream_monitor, do: Process.demonitor(s.text_stream_monitor, [:flush])
      {:reply, :ok, %{s | text_stream: nil, text_stream_monitor: nil, text_required: false}}
    end
  end

  def handle_call({:unsubscribe_text, _}, _, s),
    do: {:reply, {:error, :text_unsubscribe_refused}, s}

  def handle_call(
        {:extension_text_begin, ref, identity},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    duplicate =
      Enum.any?(s.extension_text, fn {_, resource} ->
        resource.intent["identity"]["instance"] == identity["instance"]
      end)

    if identity in Ipse.Extension.Registry.manifests(s.config) and
         "stream.text" in identity["capabilities"] and
         Ipse.Extension.Registry.live?(identity) and not duplicate and
         s.extension_text_count < 10_000 and map_size(s.extension_text) < 4 do
      intent = Ipse.Extension.TextResources.intent(identity, s.id, s.turn_id)
      record(s, intent)

      resource = %{
        intent: intent,
        pid: nil,
        worker: nil,
        monitor: nil,
        subscription_id: nil,
        ready: false,
        closed: false
      }

      {:reply, {:ok, intent},
       %{
         s
         | extension_text: Map.put(s.extension_text, intent["resource_id"], resource),
           extension_text_count: s.extension_text_count + 1
       }}
    else
      {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call(
        {:extension_text_register, ref, intent, consumer},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    with %{intent: ^intent, pid: nil} = resource <- s.extension_text[intent["resource_id"]],
         true <- is_pid(consumer) and Process.alive?(consumer),
         s = Turn.ensure_text_stream(s),
         {:ok, handle} <-
           Turn.subscribe_text_stream(
             s.text_stream,
             consumer,
             Ipse.Extension.TextResources.frame_version(intent["identity"]),
             intent["identity"]["text_required"] == true
           ) do
      resource = %{
        resource
        | pid: consumer,
          monitor: Process.monitor(consumer),
          subscription_id: handle.subscription_id
      }

      s = %{s | text_required: s.text_required or intent["identity"]["text_required"] == true}

      {:reply, {:ok, handle},
       %{s | extension_text: Map.put(s.extension_text, intent["resource_id"], resource)}}
    else
      _ -> {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call({:extension_text_worker, id, worker}, {consumer, _}, s) do
    case s.extension_text[id] do
      %{pid: ^consumer, worker: nil} = resource when is_pid(worker) ->
        if Process.alive?(consumer) and Process.alive?(worker) do
          {:reply, :ok,
           %{s | extension_text: Map.put(s.extension_text, id, %{resource | worker: worker})}}
        else
          {:reply, {:error, :extension_text_refused}, s}
        end

      _ ->
        {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call(
        {:extension_text_ready, ref, intent, consumer},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    with %{intent: ^intent, pid: ^consumer, ready: false, closed: false} = resource <-
           s.extension_text[intent["resource_id"]],
         true <- Process.alive?(consumer) and Process.alive?(resource.worker),
         true <-
           Ipse.Session.TextStream.enrolled?(s.text_stream, resource.subscription_id, consumer),
         true <- Ipse.Extension.Registry.live?(intent["identity"]) do
      record(s, Ipse.Extension.TextResources.ready(intent))

      {:reply, :ok,
       %{
         s
         | extension_text:
             Map.put(s.extension_text, intent["resource_id"], %{resource | ready: true})
       }}
    else
      _ -> {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call({:extension_text_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call(
        {:extension_text_abort, ref, intent},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    case s.extension_text[intent["resource_id"]] do
      %{intent: ^intent, pid: nil} ->
        record(s, Ipse.Extension.TextResources.closed(intent, "startup_failed", nil, nil, true))
        {:reply, :ok, %{s | extension_text: Map.delete(s.extension_text, intent["resource_id"])}}

      _ ->
        {:reply, :ok, s}
    end
  end

  def handle_call({:extension_text_abort, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call({:extension_text_register, _, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call({:extension_text_ready, _, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call(:exports, _, s), do: {:reply, s.extension_catalog, s}

  def handle_call({:invoke_export, kind, name, arguments}, _, %{phase: :idle} = s)
      when kind in [:command, :service] do
    CurrentInvocation.invoke_export(s, kind, name, arguments)
  end

  def handle_call({:invoke_export, _, _, _}, _, s),
    do: {:reply, {:error, :extension_unavailable_or_busy}, s}

  def handle_call(
        {:extension_invoke_begin, ref, stage, name, arguments},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{parent: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.begin(s, ref, stage, name, arguments, phase)
  end

  def handle_call({:extension_invoke_begin, _, _, _, _}, _, s),
    do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_output_begin, ref, offer},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_output: nil, phase: phase} = s
      )
      when ref != nil and phase in [:tool, :extension_command] do
    CurrentInvocation.open_output(s, offer)
  end

  def handle_call(
        {:extension_output_chunk, ref, output_id, reply},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_output: %{id: output_id} = active} = s
      )
      when ref != nil do
    CurrentInvocation.push_output(s, output_id, reply, active)
  end

  def handle_call(
        {:extension_output_seal, ref, %ResultSource.Sealed{} = proof},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_output: active} = s
      )
      when ref != nil and active != nil do
    CurrentInvocation.seal_output(s, proof, active)
  end

  def handle_call({:extension_output_begin, _, _}, _, s),
    do: {:reply, {:error, :output_admission_refused}, s}

  def handle_call({:extension_output_chunk, _, _, _}, _, s),
    do: {:reply, {:error, :output_fragment_refused}, s}

  def handle_call({:extension_output_seal, _, _}, _, s),
    do: {:reply, {:error, :output_seal_refused}, s}

  def handle_call({:saved_result_materialize, delivery}, _, s),
    do: {:reply, ResultSource.readable_source(s.extension_result_sources, delivery), s}

  def handle_call({:saved_result_read, request}, _, s),
    do: {:reply, CurrentInvocation.readable_output(s, request, false), s}

  def handle_call(
        {:saved_result_model_read, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :tool} = s
      )
      when ref != nil do
    CurrentInvocation.read_model_output(s, request)
  end

  def handle_call({:saved_result_model_read, _, _}, _, s),
    do: {:reply, {:error, :saved_result_read_refused}, s}

  def handle_call(
        {:extension_tool_context, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.tool_context(s, request)
  end

  def handle_call({:extension_tool_context, _, _}, _, s),
    do: {:reply, {:error, :extension_tool_context_refused}, s}

  def handle_call(
        {:extension_tool_context_commit, ref, request, old_hash, snapshot, drift},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.commit_tool_context(s, ref, request, old_hash, snapshot, drift)
  end

  def handle_call({:extension_tool_context_commit, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_tool_context_refused}, s}

  def handle_call(
        {:extension_mcp_prepare, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.prepare_mcp(s, ref, request)
  end

  def handle_call({:extension_mcp_prepare, _, _}, _, s),
    do: {:reply, {:error, :extension_mcp_refused}, s}

  def handle_call(
        {:extension_mcp_bound, ref, request, descriptor, binding},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.bind_mcp(s, ref, request, descriptor, binding)
  end

  def handle_call({:extension_mcp_bound, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_mcp_refused}, s}

  def handle_call(
        {:extension_action_begin, ref, request},
        from = {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.begin_action(s, request, from, phase)
  end

  def handle_call({:extension_action_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_action_refused}, s}

  def handle_call(
        {:extension_collection_sources, ref, intent},
        {caller, _},
        %{job_ref: ref, task: %{pid: worker}, invocation: %{action: %{intent: intent}}} = s
      )
      when ref != nil do
    reply =
      with true <- Ipse.Extension.CollectionCall.operation?(intent["request"]),
           true <- not s.invocation.interrupted,
           true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
           true <- Ipse.Session.Resources.authorized_effect?(worker, caller),
           {:ok, window} <- Writer.source_query(s.journal_writer, :snapshot),
           {:ok, context} <-
             Ipse.Extension.SemanticAdmission.context(s.config, s.id, window["generation"]) do
        proofs =
          Enum.map(Map.get(intent["request"], "proofs", []), fn request ->
            Writer.source_query(s.journal_writer, {:proof, request})
          end)

        if Enum.all?(proofs, &match?({:ok, _}, &1)),
          do: {:ok, context, Enum.map(proofs, fn {:ok, proof} -> proof end)},
          else: {:error, :collection_source_refused}
      else
        _ -> {:error, :collection_source_refused}
      end

    {:reply, reply, s}
  end

  def handle_call(
        {:inference_dispatch_intent, ref, phase, admission, expected, facts},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil do
    Ipse.Session.InferenceDispatch.commit(s, caller, phase, admission, expected, facts)
  end

  def handle_call({:inference_dispatch_intent, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :inference_dispatch_refused}, s}

  def handle_call(
        {:inference_service_status, ref, {event, _} = status},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}} = s
      )
      when ref != nil and event in [:inference_service_status, :inference_service_timing] do
    notify(s, status)
    {:reply, :ok, s}
  end

  def handle_call({:inference_service_status, _, _}, _, s),
    do: {:reply, {:error, :inference_dispatch_refused}, s}

  def handle_call({:extension_collection_sources, _, _}, _, s),
    do: {:reply, {:error, :collection_source_refused}, s}

  def handle_call(
        {:extension_effect_source, ref, intent, kind, data},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          phase: phase
        } =
          s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.bind_effect_source(s, intent, kind, data)
  end

  def handle_call({:extension_effect_source, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_effect_source_refused}, s}

  def handle_call(
        {message, ref, intent},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: nil,
          phase: phase
        } = s
      )
      when message in [
             :extension_model_begin,
             :extension_embedding_begin,
             :extension_decision_begin
           ] and ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.begin_inference(s, message, intent)
  end

  def handle_call({:extension_model_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_model_refused}, s}

  def handle_call({:extension_embedding_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_embedding_refused}, s}

  def handle_call({:extension_decision_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_decision_refused}, s}

  def handle_call(
        {message, ref, id, usage},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          extension_model: %{admission: %{"request_id" => id} = admission}
        } = s
      )
      when message in [
             :extension_model_usage,
             :extension_embedding_usage,
             :extension_decision_usage
           ] and ref != nil do
    CurrentInvocation.observe_inference(s, message, id, usage, admission)
  end

  def handle_call({:extension_model_usage, _, _, _}, _, s),
    do: {:reply, {:error, :extension_model_refused}, s}

  def handle_call({:extension_embedding_usage, _, _, _}, _, s),
    do: {:reply, {:error, :extension_embedding_refused}, s}

  def handle_call({:extension_decision_usage, _, _, _}, _, s),
    do: {:reply, {:error, :extension_decision_refused}, s}

  def handle_call(
        {:extension_model_finish, ref, intent, result, capture, reason},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: %{admission: admission}
        } = s
      )
      when ref != nil do
    CurrentInvocation.finish_model(s, intent, result, capture, reason, admission)
  end

  def handle_call({:extension_model_finish, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_model_refused}, s}

  def handle_call(
        {:extension_embedding_finish, ref, intent, result, capture, reason},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: %{admission: admission, started: started}
        } = s
      )
      when ref != nil do
    CurrentInvocation.finish_embedding(s, intent, result, capture, reason, admission, started)
  end

  def handle_call({:extension_embedding_finish, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_embedding_refused}, s}

  def handle_call(
        {:extension_decision_finish, ref, intent, result, capture, reason},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: %{admission: admission, started: started}
        } = s
      )
      when ref != nil do
    CurrentInvocation.finish_decision(s, intent, result, capture, reason, admission, started)
  end

  def handle_call({:extension_decision_finish, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_decision_refused}, s}

  def handle_call(
        {:extension_action_commit, ref, event},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          phase: phase
        } =
          s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.commit_action(s, event, intent)
  end

  def handle_call({:extension_action_commit, _, _}, _, s),
    do: {:reply, {:error, :extension_action_refused}, s}

  def handle_call(:permissions, _from, s),
    do: {:reply, Ipse.Session.Permissions.snapshot(s), s}

  def handle_call(:clear_permissions, _from, s) do
    record(s, %{"type" => "approval_grants_cleared"})
    {:reply, :ok, %{s | permissions: %{edits: false, commands: []}}}
  end

  def handle_call(:diagnostics, _from, s) do
    {:reply,
     %{
       "version" => 1,
       "phase" => Atom.to_string(s.phase),
       "observability" => Ipse.Observability.snapshot(s.observation),
       "extension_feeds" => Feeds.snapshot(s.feeds),
       "tool_events" => Ipse.Session.ToolLifecycle.snapshot(s.tool_lifecycle),
       "steps" => s.steps,
       "max_steps" => Map.get(s.config, :max_steps, 30),
       "approval_waiting" => not is_nil(s.approval),
       "question_waiting" => not is_nil(s.question),
       "active_worker" => not is_nil(s.task),
       "accounting" => Ipse.Usage.snapshot(s.accounting),
       "context" =>
         Ipse.Session.Context.measure(s.messages, s.config, Ipse.Session.Context.header(s)),
       "extension_context" => Ipse.Extension.Context.summary(s.extension_contributions),
       "extension_events" => %{
         "admitted_deliveries" => s.event_count,
         "delivery_pending" => s.event_intent != nil,
         "unconfirmed_cleanup" => s.event_cleanup_failed
       },
       "extension_text" => %{
         "active_consumers" =>
           Enum.count(s.extension_text, fn {_, resource} ->
             resource.ready and not resource.closed
           end),
         "unconfirmed_cleanup" => s.extension_text_cleanup_failed
       }
     }, s}
  end

  def handle_call(:stop_observability, _from, s) do
    capture = Ipse.Observability.stop(s.observation)
    {:reply, :ok, %{s | observation: capture}}
  end

  def handle_call(:stop_feeds, _from, s) do
    {cleanup, feeds} = Feeds.close(s.feeds, "stopped", &record(s, &1))
    result = if Enum.all?(cleanup, &(&1 == :ok)), do: :ok, else: {:error, :cleanup_unconfirmed}
    {:reply, result, %{s | feeds: feeds}}
  end

  def handle_call({:feed_worker, id, worker}, {caller, _}, s) when is_pid(worker) do
    case s.feeds.resources[id] do
      %{pid: ^caller, worker: nil, closed: false} = resource ->
        if FeedChannel.active?(resource),
          do: {:reply, :ok, put_in(s, [:feeds, :resources, id], %{resource | worker: worker})},
          else: {:reply, {:error, :feed_stopped}, s}

      _ ->
        {:reply, {:error, :feed_refused}, s}
    end
  end

  def handle_call(:observation_drain_state, _from, s),
    do:
      {:reply, %{idle: s.phase == :idle, capture: Ipse.Observability.snapshot(s.observation)}, s}

  def handle_call({:observer_worker, id, worker}, {caller, _}, s) when is_pid(worker) do
    case s.observation.resources[id] do
      %{pid: ^caller, worker: nil, closed: false} = resource ->
        if s.observation.policy["mode"] != "off" do
          {:reply, :ok, put_in(s, [:observation, :resources, id], %{resource | worker: worker})}
        else
          {:reply, {:error, :observation_revoked}, s}
        end

      _ ->
        {:reply, {:error, :observation_refused}, s}
    end
  end

  def handle_call(:refresh_context, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call(:refresh_context, _from, s) do
    s = enroll_feeds(s)

    task =
      owned_task(fn ->
        with {:ok, snapshot} <- Workspace.snapshot(s.cwd, s.context_home) do
          discovered =
            Workspace.discover_skills(
              s.cwd,
              Path.join(s.context_home, "skills"),
              skill_discovery_options(s.config)
            )

          with {:ok, skills, _} <- Workspace.restore_skills([], discovered),
               do: {:ok, snapshot, Workspace.drift(snapshot), skills}
        end
      end)

    notify(s, {:status, :refreshing_context})
    {:reply, :ok, %{s | task: task, phase: :context_refresh, job_ref: nil}}
  end

  def handle_call({:open_input_channel, reader}, {client, _}, %{subscriber: client} = s)
      when is_pid(reader) and node(reader) == node() do
    if Process.alive?(reader) do
      :ok = Ipse.Session.Input.invalidate()

      if s.operator_channel do
        Process.demonitor(s.operator_channel.client_monitor, [:flush])
        Process.demonitor(s.operator_channel.reader_monitor, [:flush])
      end

      channel = %{
        id: Ipse.Usage.id(),
        generation: Ipse.Usage.id(),
        client: client,
        reader: reader,
        client_monitor: Process.monitor(client),
        reader_monitor: Process.monitor(reader)
      }

      {:reply, {:ok, channel.id},
       %{
         s
         | operator_channel: channel,
           operator_render: nil,
           operator_answers: %{},
           operator_pieces: []
       }}
    else
      {:reply, {:error, :operator_input_unavailable}, s}
    end
  end

  def handle_call({:open_input_channel, _}, _, s),
    do: {:reply, {:error, :operator_input_unavailable}, s}

  def handle_call(
        {:observe_channel, channel, request, timeout},
        {reader, _},
        %{operator_channel: %{id: channel, reader: reader}} = s
      ) do
    case operator_request(s, request) do
      {:ok, display, purpose, render} ->
        {:ok, scope} = Ipse.Session.Resources.start(self())
        :ok = Ipse.Session.Lock.track(scope, :scope)

        result =
          Ipse.Session.Input.start(
            operator_binding(s, purpose, render),
            display,
            timeout,
            reader,
            scope
          )

        if not match?({:ok, _}, result), do: Ipse.Session.Resources.stop_async(scope)
        {:reply, result, s}

      _ ->
        {:reply, {:error, :operator_input_unavailable}, s}
    end
  end

  def handle_call({:observe_channel, _, _, _}, _, s),
    do: {:reply, {:error, :operator_input_unavailable}, s}

  def handle_call(
        {:cancel_input_read, channel},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    {:reply, Ipse.Session.Input.cancel_read(), s}
  end

  def handle_call({:cancel_input_read, _}, _, s),
    do: {:reply, {:error, :operator_input_unavailable}, s}

  def handle_call(
        {:stage_input, channel, text, witness},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    {:reply, Ipse.Session.Input.stage(witness, text, operator_binding(s, "prompt", nil)), s}
  end

  def handle_call({:stage_input, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call(
        {:discard_input, channel, witness},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    {:reply, Ipse.Session.Input.discard(witness), s}
  end

  def handle_call({:discard_input, _, _}, _, s), do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call(
        {:render_question, channel, item},
        {client, _},
        %{
          operator_channel: %{id: channel, client: client},
          phase: :question,
          question: %{id: _} = question
        } = s
      )
      when not is_map_key(question, :kind) do
    expected = Enum.at(question.arguments["questions"], length(s.operator_pieces))

    with true <- expected != nil and expected["id"] == item,
         {:ok, render} <- Ipse.Session.OperatorAnswer.render(question, item, channel) do
      :ok = Ipse.Session.Input.cancel_read()
      {:reply, {:ok, render}, %{s | operator_render: render}}
    else
      _ -> {:reply, {:error, :no_pending_question}, s}
    end
  end

  def handle_call(
        {:render_question, channel, _},
        {client, _},
        %{
          operator_channel: %{id: channel, client: client},
          question: %{kind: :extension},
          phase: :question
        } = s
      ),
      do: {:reply, {:error, :extension_question}, s}

  def handle_call({:render_question, _, _}, _, s), do: {:reply, {:error, :no_pending_question}, s}

  def handle_call(
        {:answer_observed, channel, render_id, text, witness},
        {client, _},
        %{
          operator_channel: %{id: channel, client: client},
          phase: :question,
          question: question,
          operator_render: %{"render_id" => render_id} = render
        } = s
      ) do
    with {:ok, observation} <-
           Ipse.Session.Input.consume(witness, text, operator_binding(s, "question", render_id)),
         {:ok, answer, piece} <-
           Ipse.Session.OperatorAnswer.parse(question, render, text, observation) do
      answers = Map.put(s.operator_answers, render["item_id"], answer)
      pieces = s.operator_pieces ++ [piece]
      next = %{s | operator_render: nil, operator_answers: answers, operator_pieces: pieces}

      if length(pieces) == length(question.arguments["questions"]) do
        Ipse.Session.Turn.answer(next, question.id, answers, question, %{
          client_id: channel,
          pieces: pieces
        })
      else
        {:reply, {:ok, :more}, next}
      end
    else
      _ -> {:reply, {:error, :invalid_operator_answer_origin}, s}
    end
  end

  def handle_call({:answer_observed, _, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_operator_answer_origin}, s}

  def handle_call({:observe_input, display, timeout}, {client, _}, %{phase: :idle} = s) do
    {:ok, scope} = Ipse.Session.Resources.start(self())
    :ok = Ipse.Session.Lock.track(scope, :scope)
    result = Ipse.Session.Input.start(input_binding(s), display, timeout, client, scope)
    if not match?({:ok, _}, result), do: Ipse.Session.Resources.stop_async(scope)
    {:reply, result, s}
  end

  def handle_call({:observe_input, _, _}, _from, s), do: {:reply, {:error, :busy}, s}

  def handle_call({:prompt, _, _}, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call({:prompt, text, witness}, from, s)
      when is_binary(text) and byte_size(text) > 0 do
    observed =
      case s.operator_channel do
        %{client: client} when elem(from, 0) == client ->
          case Ipse.Session.Input.submit(witness, text, operator_binding(s, "prompt", nil)) do
            {:ok, _} = result -> result
            _ -> Ipse.Session.Input.consume(witness, text, input_binding(s))
          end

        _ ->
          Ipse.Session.Input.consume(witness, text, input_binding(s))
      end

    case observed do
      {:ok, observation} ->
        Turn.prompt(%{s | input_generation: Ipse.Usage.id()}, text, from, observation)

      error ->
        {:reply, error, s}
    end
  end

  def handle_call({:prompt, _, _}, _from, s), do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call({:prompt, _}, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call({:prompt, text}, from, s) when is_binary(text) and byte_size(text) > 0 do
    :ok = Ipse.Session.Input.invalidate()
    Turn.prompt(%{s | input_generation: Ipse.Usage.id()}, text, from)
  end

  def handle_call({:prompt, _}, _from, s), do: {:reply, {:error, :empty_prompt}, s}

  def handle_call({:approve, _, choice}, _from, %{approval: approval} = s)
      when choice in [:session_edits, :session_command] and
             (not is_tuple(approval) or tuple_size(approval) != 3),
      do: {:reply, {:error, :grant_unavailable}, s}

  def handle_call(
        {:approve, ref, allowed},
        _from,
        %{approval: {:delegated, ref, worker, child, child_ref, name, args}, task: %{}} =
          s
      ) do
    case s.delegation_resources[child] do
      %{id: id, worker: ^worker, down: false, finished: false} ->
        s = finish_wait(s, if(allowed == true, do: "approved", else: "denied"))

        record(s, %{
          "type" => "delegation_approval",
          "child_id" => id,
          "name" => name,
          "arguments" => args,
          "decision" => if(allowed == true, do: "approved", else: "denied")
        })

        send(worker, {:delegated_decision, child, child_ref, allowed == true})
        s = if allowed == true, do: claim_delegated_effect(s, child, name, args), else: s
        {:reply, :ok, next_delegated_approval(%{s | approval: nil, phase: :tool})}

      _ ->
        {:reply, {:error, :no_pending_approval}, s}
    end
  end

  def handle_call(
        {:approve, ref, allowed},
        _from,
        %{
          approval: {:extension, ref, caller, phase},
          invocation: %{action: action},
          phase: :extension_approval
        } = s
      ) do
    CurrentInvocation.approve(s, allowed, caller, phase, action)
  end

  def handle_call({:approve, ref, allowed}, _from, %{approval: {ref, call, args}} = s) do
    Turn.approve(s, allowed, call, args)
  end

  def handle_call({:approve, _, _}, _from, s), do: {:reply, {:error, :no_pending_approval}, s}

  def handle_call(
        {:answer, id, answers},
        _from,
        %{question: %{kind: :extension, id: id} = question, phase: :question} = s
      ) do
    CurrentInvocation.answer(s, answers, question)
  end

  def handle_call(
        {:answer, id, answers},
        _from,
        %{question: %{id: id} = question, phase: :question} = s
      ) do
    Turn.answer(s, id, answers, question)
  end

  def handle_call({:answer, _, _}, _from, s), do: {:reply, {:error, :no_pending_question}, s}

  def handle_call(
        {:question_eof, channel},
        {client, _},
        %{operator_channel: %{id: channel, client: client}, phase: :question, question: question} =
          s
      )
      when is_map(question) do
    cancel_work(s, true)
  end

  def handle_call({:question_eof, _}, _, s), do: {:reply, {:error, :no_pending_question}, s}

  def handle_call({:session_sources, operation, request}, {client, _}, %{subscriber: client} = s) do
    {:reply, source_query(s, operation, request), s}
  end

  def handle_call({:session_sources, _, _}, _, s),
    do: {:reply, {:error, :source_index_refused}, s}

  def handle_call(
        {:model_sources, ref, operation, request},
        {worker, _},
        %{task: %{pid: worker}, job_ref: ref, phase: :tool} = s
      ) do
    call = List.first(s.calls)

    if Ipse.Session.SourceWindow.enabled?(s.config) and
         get_in(call, ["function", "name"]) == Ipse.Extension.SourceRead.tool_name(operation) and
         Ipse.JSON.decode_unique(get_in(call, ["function", "arguments"])) == {:ok, request},
       do: {:reply, source_query(s, operation, request), s},
       else: {:reply, {:error, :source_index_refused}, s}
  end

  def handle_call({:model_sources, _, _, _}, _, s),
    do: {:reply, {:error, :source_index_refused}, s}

  def handle_call(:cancel, _from, s), do: cancel_work(s, false)

  def handle_call(:close, _from, s) do
    {cleanup, next} = stop_work(s, s.phase != :idle, "cancelled", "session_close")
    observer_cleanup = Ipse.Observability.close(s.observation, &record(s, &1))
    cleanup = cleanup ++ observer_cleanup
    result = if Enum.all?(cleanup, &(&1 == :ok)), do: :ok, else: {:error, :cleanup_unconfirmed}
    {:stop, :normal, result, close_epoch(next, "close", result == :ok)}
  end

  defp cancel_work(s, keep_queued) do
    {cleanup, next} = stop_work(s, true, "cancelled", "cancelled", keep_queued)

    if Enum.any?(cleanup, &(&1 != :ok)) do
      notify(
        s,
        {:error,
         "Owned work cleanup could not be confirmed. Inspect running processes before retrying."}
      )

      notify(s, {:done, :error})

      {:stop, :normal, {:error, :cleanup_unconfirmed},
       close_epoch(next, "cleanup_failure", false)}
    else
      notify(s, {:done, :cancelled})
      {:reply, :ok, next}
    end
  end

  defp source_query(s, operation, request) do
    if is_map(request) and
         Ipse.Extension.SourceRead.validate(Map.put(request, "op", operation)) == :ok,
       do: Writer.source_query(s.journal_writer, {operation, request}),
       else: {:error, :source_index_refused}
  end

  defp stop_work(
         s,
         record_cancel,
         wait_outcome,
         feed_reason \\ "cancelled",
         keep_queued \\ false
       ) do
    :ok =
      if keep_queued, do: Ipse.Session.Input.cancel_read(), else: Ipse.Session.Input.invalidate()

    s = %{s | operator_render: nil, operator_answers: %{}, operator_pieces: []}
    s = CurrentInvocation.release_output(s)
    s = finish_wait(s, wait_outcome)
    s = if s.task, do: measure_request(s, :cancelled), else: s
    s = Turn.close_question(s)
    child_cleanup = Enum.map(Map.keys(s.delegation_resources), &close/1)
    child_reason = if feed_reason == "consumer_down", do: "owner_down", else: "cancelled"
    s = settle_children(s, child_reason)

    Enum.each(s.delegation_resources, fn {_, child} ->
      Process.demonitor(child.monitor, [:flush])
    end)

    cleanup =
      s.mcp_resources
      |> Map.keys()
      |> Enum.filter(&Process.alive?/1)
      |> Enum.map(&Ipse.MCP.StdioTransport.close/1)

    task_cleanup =
      if s.task, do: [Ipse.Session.Resources.close_task(s.task.pid)], else: []

    if s.task, do: Task.shutdown(s.task, :brutal_kill)

    if s.prompt_from, do: GenServer.reply(s.prompt_from, {:error, :cancelled})

    text_cleanup =
      Enum.map(s.extension_text, fn {_, resource} ->
        result =
          cond do
            resource.closed ->
              if is_pid(resource.pid) and Process.alive?(resource.pid),
                do: Process.exit(resource.pid, :kill)

              :ok

            is_pid(resource.pid) ->
              Ipse.Extension.TextConsumer.close(resource)

            true ->
              :ok
          end

        if result == :ok and is_binary(resource.subscription_id) do
          try do
            Ipse.Session.TextStream.unsubscribe(%{
              server: s.text_stream,
              subscription_id: resource.subscription_id
            })
          catch
            :exit, _ -> :ok
          end
        end

        if not resource.closed,
          do:
            record(
              s,
              Ipse.Extension.TextResources.closed(
                resource.intent,
                "cancelled",
                nil,
                nil,
                result == :ok
              )
            )

        result
      end)

    s =
      Turn.settle_calls(
        s,
        "Cancelled. If execution had started, its effects may have occurred. Inspect the workspace before retrying."
      )

    if record_cancel, do: record(s, %{"type" => "cancelled"})

    next =
      %{
        s
        | phase: :idle,
          prompt_from: nil,
          input_generation: Ipse.Usage.id(),
          task: nil,
          approval: nil,
          job_ref: nil,
          compaction: nil,
          extension_intent: nil,
          invocation: %CurrentInvocation{},
          extension_mcp_context: nil,
          event_intent: nil,
          event_received: nil,
          event_committed: nil,
          event_answer: nil,
          event_turn: nil,
          event_schedule: "before_request",
          event_after_started: false,
          extension_text: %{},
          extension_text_turn: nil,
          tool_decision: "not_decided",
          mcp_resources: %{},
          delegation_resources: %{},
          delegation_workers: MapSet.new(),
          delegation_queue: [],
          delegation_effect: nil,
          delegation_claims: %{}
      }

    text_cleanup =
      if s.extension_text_cleanup_failed or s.event_cleanup_failed or s.task_cleanup_failed,
        do: [{:error, :cleanup_unconfirmed} | text_cleanup],
        else: text_cleanup

    {feed_cleanup, feeds} = Feeds.close(s.feeds, feed_reason, &record(s, &1))

    {child_cleanup ++ cleanup ++ task_cleanup ++ text_cleanup ++ feed_cleanup,
     %{next | feeds: feeds}}
  end

  @impl true

  def handle_info(
        {:extension_output_deadline, ref},
        %{job_ref: ref, extension_output_clock: clock} = s
      )
      when ref != nil and clock != nil do
    {cleanup, next} = stop_work(s, true, "interrupted")

    notify(
      s,
      {:error, "Complete-result deadline exceeded. Inspect prior actions before retrying."}
    )

    notify(s, {:done, :error})

    if Enum.all?(cleanup, &(&1 == :ok)),
      do: {:noreply, next},
      else: {:stop, :normal, close_epoch(next, "cleanup_failure", false)}
  end

  def handle_info({:extension_output_deadline, _}, s), do: {:noreply, s}

  def handle_info(
        {:delegated_approval, ref, worker, child, child_ref, name, args},
        %{job_ref: ref, task: %{}, phase: phase} = s
      )
      when ref != nil and phase in [:tool, :delegated_approval] do
    case s.delegation_resources[child] do
      %{worker: ^worker, down: false, finished: false} when length(s.delegation_queue) < 2 ->
        item = {worker, child, child_ref, name, args}
        {:noreply, next_delegated_approval(%{s | delegation_queue: s.delegation_queue ++ [item]})}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:delegated_progress, ref, child, event}, %{job_ref: ref} = s)
      when ref != nil do
    case {s.delegation_resources[child], event} do
      {%{id: id}, {:tool, name, args}} ->
        notify(s, {:tool, "child #{id}/#{name}", args})

      {%{id: id}, {:status, status}} ->
        notify(s, {:subagent, id, status})

      {%{id: id}, {:tool_result, name, text}} ->
        notify(s, {:tool_result, "child #{id}/#{name}", text})

      _ ->
        :ok
    end

    s =
      if match?({:tool_result, _, _}, event) and s.delegation_effect == child,
        do: %{s | delegation_effect: nil},
        else: s

    {:noreply, next_delegated_approval(s)}
  end

  def handle_info(
        {:progress, ref, {:provider_usage, usage}},
        %{job_ref: ref, active_request: request} = s
      )
      when ref != nil and request != nil do
    entry = s.accounting.requests[request["request_id"]]
    event = Ipse.Usage.observation(request, usage, entry.sequence + 1)

    if entry.sequence < 64 and event["usage"] != entry.observation do
      {:noreply, account(s, event)}
    else
      {:noreply, s}
    end
  end

  def handle_info({:progress, ref, {:provider_usage, _}}, %{job_ref: ref} = s),
    do: {:noreply, s}

  def handle_info({:progress, ref, event}, %{job_ref: ref} = s) when ref != nil do
    if s.phase != :idle, do: notify(s, event)
    {:noreply, s}
  end

  def handle_info({ref, result}, %{task: %{ref: ref}} = s) do
    cleanup = Ipse.Session.Resources.close_task(s.task.pid)
    result = if cleanup == :ok, do: result, else: :task_cleanup_unconfirmed
    s = measure_request(s, result)
    Process.demonitor(ref, [:flush])
    phase = if s.phase == :delegated_approval, do: :tool, else: s.phase
    s = %{s | task: nil}

    case {phase, result} do
      {_, :task_cleanup_unconfirmed} ->
        {_, next} =
          stop_work(%{s | task_cleanup_failed: true}, true, "interrupted", "cleanup_failure")

        notify(
          s,
          {:error, "Task-owned OS cleanup could not be confirmed. Inspect before retrying."}
        )

        notify(s, {:done, :error})
        {:stop, :normal, close_epoch(next, "cleanup_failure", false)}

      {:semantic_outer, {:extension_command_outer, request, result}} ->
        CurrentInvocation.command_outer(s, request, result)

      {:semantic_outer, result} ->
        Turn.semantic_outer_completed(s, result)

      {invocation_phase, {:extension_question, action}}
      when invocation_phase in [:tool, :extension_command, :extension_service, :extension_events] ->
        CurrentInvocation.suspend_for_question(s, invocation_phase, action)

      {:extension_events, {:extension_invocation_result, event}} ->
        CurrentInvocation.complete_event_job(s, event)

      {invocation_phase, {:extension_saved_result, delivery}}
      when invocation_phase in [:tool, :extension_command] ->
        CurrentInvocation.publish_saved_result(s, delivery)

      {invocation_phase, {:extension_invocation_result, event}}
      when invocation_phase in [:tool, :extension_command, :extension_service, :extension_events] ->
        CurrentInvocation.publish_inline_result(s, event)

      {:extension_events, {:unknown, error}} ->
        if s.event_intent, do: record(s, Subscriptions.result(s.event_intent, "unknown", false))
        {:noreply, Turn.fail(%{s | event_intent: nil, event_cleanup_failed: true}, error)}

      {invocation_phase, {:unknown, error}}
      when invocation_phase in [:extension_command, :extension_service] ->
        {:noreply, Turn.fail(s, error)}

      {:extension_prompt, :ok} ->
        {:noreply, Turn.model(%{s | extension_intent: nil})}

      {:extension_events, :ok} ->
        {:noreply,
         if(s.event_schedule == "after_turn", do: Turn.finish(s, :ok), else: Turn.model(s))}

      {:extension_events, {:error, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:extension_text_start, :ok} ->
        {:noreply, Turn.model(s)}

      {:extension_text_start, {:error, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:extension_presentation, :ok} ->
        notify(s, {:presentation, s.final})
        {:noreply, Turn.finish(s, :ok)}

      {extension_phase, {:error, error}}
      when extension_phase in [:extension_prompt, :extension_presentation] ->
        {:noreply, Turn.fail(s, error)}

      {:mcp_discovery, {:ok, tools}} ->
        Turn.mcp_discovered(s, tools)

      {:mcp_discovery, {:error, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:tool, {:unknown, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:context_preflight, {:ok, snapshot, drift}} ->
        Turn.context_checked(s, snapshot, drift)

      {:prompt_preflight, prepared} ->
        Turn.prompt_prepared(s, prepared)

      {:context_preflight, {:error, reason}} ->
        Turn.context_check_failed(s, reason)

      {:context_refresh, {:ok, snapshot, drift, skills}} ->
        Turn.context_refreshed(s, snapshot, drift, skills)

      {:context_refresh, {:error, reason}} ->
        Turn.context_refresh_failed(s, reason)

      {:compaction, {:ok, assistant, usage}} ->
        {:noreply, Turn.complete_compaction(s, assistant, usage)}

      {:compaction, {:error, _error}} ->
        {:noreply,
         Turn.compaction_failed(s, "The selected provider's summary request failed.", "summary")}

      {:model, {:ok, assistant, usage}} ->
        Turn.model_completed(s, assistant, usage)

      {:model, {:error, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:tool, {:research_record, event, text}} ->
        record(s, event)
        {:noreply, Turn.tool_result(s, hd(s.calls), text, "result_recorded", s.tool_decision)}

      {:tool, {status, text}} when is_binary(text) ->
        Turn.tool_completed(s, status, text)

      _ ->
        {:noreply, Turn.fail(s, "Unexpected worker result")}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{owner_ref: ref, question: question} = s
      )
      when ref != nil and question != nil do
    {_cleanup, next} =
      stop_work(%{s | question: nil, calls: []}, false, "interrupted", "consumer_down")

    {:stop, :normal, close_epoch(next, "owner_down", false)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = s) when ref != nil do
    {_cleanup, next} = stop_work(s, true, "interrupted", "consumer_down")
    {:stop, :normal, close_epoch(next, "owner_down", false)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{journal_writer_ref: ref} = s),
    do: {:stop, :journal_unavailable, s}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{lock_guard_ref: ref} = s) do
    notify(s, {:error, "Session lock owner stopped. Inspect before resuming."})
    notify(s, {:done, :error})
    {:stop, :normal, s}
  end

  def handle_info({:owned_task_cleanup_failed, worker}, %{task: %{pid: worker}} = s) do
    {_, next} =
      stop_work(%{s | task_cleanup_failed: true}, true, "interrupted", "cleanup_failure")

    notify(
      s,
      {:error,
       "Task-owned OS cleanup could not be confirmed. Inspect running processes before retrying."}
    )

    notify(s, {:done, :error})
    {:stop, :normal, close_epoch(next, "cleanup_failure", false)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %{ref: ref}} = s) do
    s = measure_request(s, :worker_down)

    {_, next} =
      stop_work(%{s | task_cleanup_failed: true}, true, "interrupted", "cleanup_failure")

    notify(s, {:error, "Worker stopped unexpectedly; effects and OS cleanup are unconfirmed."})
    notify(s, {:done, :error})
    {:stop, :normal, close_epoch(next, "cleanup_failure", false)}
  end

  def handle_info({:extension_text_closed, consumer, id, reason, frames, bytes, cleanup}, s) do
    case s.extension_text[id] do
      %{pid: ^consumer, closed: false} = resource ->
        event =
          Ipse.Extension.TextResources.closed(resource.intent, reason, frames, bytes, cleanup)

        if Ipse.Extension.TextResources.valid_closed?(event, resource.intent) do
          record(s, event)

          notify(
            s,
            {:status,
             "Extension text consumer closed incomplete; original provider history is retained."}
          )

          {:noreply,
           %{
             s
             | extension_text: Map.put(s.extension_text, id, %{resource | closed: true}),
               extension_text_cleanup_failed: s.extension_text_cleanup_failed or not cleanup
           }}
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:feed_ready, pid, id}, s) do
    case s.feeds.resources[id] do
      %{pid: ^pid, ready: false, closed: false} = r ->
        if FeedChannel.active?(r) do
          record(s, Feeds.ready(r.intent))
          FeedChannel.admit(r)
          {:noreply, put_in(s, [:feeds, :resources, id], %{r | ready: true})}
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:feed_ack, pid, id, sequence}, s) do
    case s.feeds.resources[id] do
      %{pid: ^pid, ready: true, closed: false} = r ->
        if FeedChannel.active?(r) and sequence == r.ack + 1 and
             Ipse.Extension.Registry.live?(r.intent["identity"]) do
          case :ets.take(r.pending, sequence) do
            [{^sequence, intent}] ->
              record(s, Feeds.result(intent))
              :atomics.add(r.counters, 4, 1)
              send(pid, {:ack_committed, sequence})
              {:noreply, put_in(s, [:feeds, :resources, id], %{r | ack: sequence})}

            _ ->
              {:noreply, s}
          end
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:feed_closed, pid, id, cleanup}, s) when is_boolean(cleanup) do
    case s.feeds.resources[id] do
      %{pid: ^pid, closed: false} = r ->
        {:noreply, record_feed_close(s, id, r, cleanup)}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _}, %{operator_channel: channel} = s)
      when is_map(channel) and (ref == channel.client_monitor or ref == channel.reader_monitor) do
    :ok = Ipse.Session.Input.invalidate()
    Process.demonitor(channel.client_monitor, [:flush])
    Process.demonitor(channel.reader_monitor, [:flush])

    {:noreply,
     %{
       s
       | operator_channel: nil,
         operator_render: nil,
         operator_answers: %{},
         operator_pieces: []
     }}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, s) do
    s =
      Enum.reduce(s.feeds.resources, s, fn {id, r}, state ->
        if r.monitor == ref and r.pid == pid and not r.closed,
          do: record_feed_close(state, id, r, false),
          else: state
      end)

    observation =
      Enum.reduce(s.observation.resources, s.observation, fn {id, resource}, capture ->
        if resource.monitor == ref and resource.pid == pid and not resource.closed do
          Ipse.Observability.Channel.revoke(resource)
          record(s, Ipse.Observability.receipt(resource.intent, "closed", false))

          notify(
            s,
            {:status, "Diagnostic sink exited; inspect /diagnostics for unconfirmed cleanup."}
          )

          put_in(capture, [:resources, id], %{resource | closed: true, cleanup: false})
        else
          capture
        end
      end)

    s = %{s | observation: observation}

    unconfirmed_text =
      Enum.any?(s.extension_text, fn {_, resource} ->
        resource.monitor == ref and resource.pid == pid and not resource.closed
      end)

    extension_text =
      Enum.reduce(s.extension_text, s.extension_text, fn {id, resource}, resources ->
        if resource.monitor == ref and resource.pid == pid do
          if not resource.closed,
            do: record(s, Ipse.Extension.TextResources.closed(resource.intent, "consumer_down"))

          Map.delete(resources, id)
        else
          resources
        end
      end)

    s = %{
      s
      | extension_text: extension_text,
        extension_text_cleanup_failed: s.extension_text_cleanup_failed or unconfirmed_text
    }

    s =
      if ref == s.text_stream_monitor,
        do: %{
          s
          | text_stream: if(s.text_required, do: s.text_stream, else: nil),
            text_stream_monitor: nil
        },
        else: s

    resources =
      if s.mcp_resources[pid] == ref, do: Map.delete(s.mcp_resources, pid), else: s.mcp_resources

    {children, child_down, child_usage} =
      case s.delegation_resources[pid] do
        %{monitor: ^ref} = child ->
          if not child.finished and s.task != nil and s.job_ref == child.job_ref and
               Process.alive?(child.worker) do
            {Map.put(s.delegation_resources, pid, %{child | down: true}), true, s.child_usage}
          else
            next =
              if child.finished,
                do: s,
                else:
                  record_child_outcome(
                    s,
                    Ipse.Tools.Delegation.child_finished(child, "unknown", "worker_failed", false)
                  )

            {Map.delete(s.delegation_resources, pid), true, next.child_usage}
          end

        _ ->
          {s.delegation_resources, false, s.child_usage}
      end

    s = %{s | mcp_resources: resources, delegation_resources: children, child_usage: child_usage}

    s =
      case s.approval do
        {:delegated, _, _, ^pid, _, _, _} when child_down ->
          finish_wait(%{s | approval: nil, phase: :tool}, "interrupted")

        _ ->
          s
      end

    s = if s.delegation_effect == pid, do: %{s | delegation_effect: nil}, else: s
    {:noreply, next_delegated_approval(s)}
  end

  def handle_info({port, {:exit_status, _}}, %{lock: port} = s) do
    # Stop without appending: journal ownership is no longer guaranteed.
    notify(s, {:error, "Session lock helper exited; stopping to protect the journal."})
    notify(s, {:done, :error})
    {:stop, :normal, s}
  end

  def handle_info({:observer_ready, pid, id}, s) do
    case s.observation.resources[id] do
      %{pid: ^pid, ready: false, closed: false} = resource ->
        if s.observation.policy["mode"] != "off" do
          record(s, Ipse.Observability.receipt(resource.intent, "ready"))
          resource = %{resource | ready: true}
          Ipse.Observability.Channel.admit(resource)
          {:noreply, put_in(s, [:observation, :resources, id], resource)}
        else
          Ipse.Observability.Channel.stop(resource)
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info(
        {:text_policy, stream, ref, required},
        %{text_stream: stream, text_stream_policy_ref: ref} = s
      )
      when is_boolean(required),
      do: {:noreply, %{s | text_required: required}}

  def handle_info({:observer_closed, pid, id, cleanup}, s) when is_boolean(cleanup) do
    case s.observation.resources[id] do
      %{pid: ^pid, closed: false} = resource ->
        record(s, Ipse.Observability.receipt(resource.intent, "closed", cleanup))

        notify(
          s,
          {:status,
           "Diagnostic sink stopped; inspect /diagnostics for bounded delivery counters."}
        )

        {:noreply,
         put_in(s, [:observation, :resources, id], %{resource | closed: true, cleanup: cleanup})}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true

  def terminate(_reason, s) do
    if s.task, do: Ipse.Session.Resources.close_task(s.task.pid)
    if s.task, do: Task.shutdown(s.task, :brutal_kill)

    Enum.each(s.extension_text, fn {_, resource} ->
      if is_pid(resource.pid) and Process.alive?(resource.pid),
        do: Process.exit(resource.pid, :kill)
    end)

    Enum.each(s.observation.resources, fn {_, resource} ->
      Ipse.Observability.Channel.revoke(resource)
      if Process.alive?(resource.pid), do: Process.exit(resource.pid, :kill)
    end)

    Enum.each(s.feeds.resources, fn {_, resource} ->
      FeedChannel.stop(resource, "consumer_down")
      if Process.alive?(resource.pid), do: Process.exit(resource.pid, :kill)
    end)

    # A timed-out append may still be queued or inside IO. Stop its sole writer
    # before releasing the session lock; never retry an unconfirmed record.
    Process.unlink(s.journal_writer)
    writer_ref = Process.monitor(s.journal_writer)
    Process.exit(s.journal_writer, :kill)

    receive do
      {:DOWN, ^writer_ref, :process, _, _} -> :ok
    end

    if Process.alive?(s.lock_guard), do: Ipse.Session.Lock.release(s.lock_guard)

    :ok
  end

  @impl true

  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:id, :phase])}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp workspace_snapshot(events, cwd, home, supplied) do
    case Enum.find(Enum.reverse(events), &(&1["type"] == "workspace_context_snapshot")) do
      nil when supplied != nil ->
        if Workspace.valid?(supplied) and supplied["cwd"] == cwd,
          do: {:ok, supplied, true},
          else: {:error, :invalid_workspace_context_snapshot}

      nil ->
        case Workspace.snapshot(cwd, home) do
          {:ok, snapshot} -> {:ok, snapshot, true}
          {:error, reason} -> {:error, {:workspace_context_unavailable, reason}}
        end

      %{"version" => 1, "snapshot" => snapshot} ->
        if Workspace.valid?(snapshot) and snapshot["cwd"] == cwd,
          do: {:ok, snapshot, false},
          else: {:error, :invalid_workspace_context_snapshot}

      _ ->
        {:error, :invalid_workspace_context_snapshot}
    end
  end

  @doc false
  def persist_context(s, snapshot, force \\ false) do
    if force or snapshot != s.context_snapshot do
      record(s, %{
        "type" => "workspace_context_snapshot",
        "version" => 1,
        "snapshot" => snapshot
      })
    end

    %{s | context_snapshot: snapshot}
  end

  @doc false
  def persist_skills(s, skills) do
    if not s.skills_saved or s.skills != skills do
      record(s, Workspace.skill_checkpoint(skills))
      %{s | skills: skills, skills_saved: true}
    else
      s
    end
  end

  defp inference_approval?(name, args),
    do:
      ModelCall.delegated_approval?(name, args) or EmbeddingCall.delegated_approval?(name, args) or
        DecisionCall.delegated_approval?(name, args)

  defp next_delegated_approval(%{approval: approval} = s) when approval != nil, do: s
  defp next_delegated_approval(%{delegation_queue: []} = s), do: s

  defp next_delegated_approval(s) do
    index =
      Enum.find_index(s.delegation_queue, fn {_, _, _, name, args} ->
        s.delegation_effect == nil or inference_approval?(name, args)
      end)

    if index == nil do
      s
    else
      {item, rest} = List.pop_at(s.delegation_queue, index)
      dispatch_delegated_approval(%{s | delegation_queue: rest}, item)
    end
  end

  defp dispatch_delegated_approval(s, {worker, child, ref, name, args}) do
    case s.delegation_resources[child] do
      %{id: id, worker: ^worker, down: false, finished: false} ->
        mode = Map.get(s.config, :approval, :ask)
        conflict = delegated_conflict?(s, child, name, args)

        cond do
          Ipse.Tools.Delegation.validate_approval(args) != :ok or conflict or mode == :deny ->
            record(s, %{
              "type" => "delegation_approval",
              "child_id" => id,
              "name" => name,
              "arguments" => args,
              "decision" => if(conflict, do: "conflict_denied", else: "policy_denied")
            })

            send(worker, {:delegated_decision, child, ref, false})
            next_delegated_approval(s)

          mode == :ask ->
            approval = make_ref()

            s =
              begin_wait(s, "delegated_tool", %{
                "turn_id" => s.turn_id,
                "request_id" => s.last_request_id,
                "child_id" => id
              })

            notify(s, {:approval, approval, "child #{id}/#{name}", args})

            %{
              s
              | phase: :delegated_approval,
                approval: {:delegated, approval, worker, child, ref, name, args}
            }

          true ->
            record(s, %{
              "type" => "delegation_approval",
              "child_id" => id,
              "name" => name,
              "arguments" => args,
              "decision" => "session_allow"
            })

            send(worker, {:delegated_decision, child, ref, true})
            claim_delegated_effect(s, child, name, args)
        end

      _ ->
        next_delegated_approval(s)
    end
  end

  defp delegated_target(s, name, args) when name in ["write", "edit"] do
    if is_binary(args["path"]),
      do: Tools.path_key(Path.expand(args["path"], s.cwd)) || "*",
      else: "*"
  end

  defp delegated_target(_, _, _), do: "*"

  defp retire_child(s, child) do
    s = %{s | delegation_resources: Map.delete(s.delegation_resources, child)}

    s =
      case s.approval do
        {:delegated, _, _, ^child, _, _, _} ->
          finish_wait(%{s | approval: nil, phase: :tool}, "interrupted")

        _ ->
          s
      end

    if s.delegation_effect == child, do: %{s | delegation_effect: nil}, else: s
  end

  @doc false
  def settle_children(s, reason) do
    Enum.reduce(s.delegation_resources, s, fn {pid, child}, state ->
      state =
        if child.finished,
          do: state,
          else:
            record_child_outcome(
              state,
              Ipse.Tools.Delegation.child_finished(child, "unknown", reason, false)
            )

      if child.down do
        Process.demonitor(child.monitor, [:flush])
        retire_child(state, pid)
      else
        put_in(state, [:delegation_resources, pid], %{child | finished: true})
      end
    end)
  end

  defp record_child_outcome(s, event) do
    record(s, event)
    %{s | child_usage: Ipse.Extension.ChildUsage.apply_parent(s.child_usage, event)}
  end

  defp delegated_conflict?(s, child, name, args) do
    target = delegated_target(s, name, args)

    not inference_approval?(name, args) and
      Enum.any?(s.delegation_claims, fn {claimed, owner} ->
        owner != child and (target == "*" or claimed == "*" or target == claimed)
      end)
  end

  defp claim_delegated_effect(s, child, name, args) do
    if inference_approval?(name, args) do
      s
    else
      %{
        s
        | delegation_effect: child,
          delegation_claims: Map.put(s.delegation_claims, delegated_target(s, name, args), child)
      }
    end
  end

  @doc false
  def optional_source(s, event) do
    case Writer.append_observed(s.journal_writer, event) do
      {:ok, source} ->
        offer_record(s, source, event)
        source

      {:error, reason} ->
        journal_failed(s, reason)
    end
  end

  @doc false
  def record(s, event) do
    result =
      if event["type"] not in ~w(input_received reference_admitted reference_refresh reference_epoch reference_envelope) and
           ((s.observation != nil and s.observation.policy["mode"] != "off") or
              Feeds.active?(s.feeds)),
         do: Writer.append_observed(s.journal_writer, event),
         else: Writer.append(s.journal_writer, event)

    case result do
      :ok -> :ok
      {:ok, source} -> offer_record(s, source, event)
      {:error, reason} -> journal_failed(s, reason)
    end
  end

  @doc false
  def record_source(s, event) do
    case Writer.append_with_source(s.journal_writer, event) do
      {:ok, source} ->
        offer_record(s, source, event)
        source

      {:error, reason} ->
        journal_failed(s, reason)
    end
  end

  @doc false
  def journal_failed(s, :journal_limit_reached) do
    notify(
      s,
      {:error,
       "Journal resource limit reached. History was preserved; inspect it and use an explicit fresh-session handoff before continuing."}
    )

    exit(:journal_limit_reached)
  end

  @doc false
  def journal_failed(_s, _reason), do: exit(:journal_unavailable)

  @doc false
  def notify(s, event), do: send(s.subscriber, {:ipse, self(), event})

  @doc false
  def offer_record(s, source, event) do
    if s.observation, do: Ipse.Observability.offer(s.observation, source, event)

    Feeds.offer(s.feeds, source, event, fn intent ->
      case Writer.append(s.journal_writer, intent) do
        :ok -> :ok
        {:error, reason} -> journal_failed(s, reason)
      end
    end)
  end

  @doc false
  def enroll_feeds(s) do
    feeds = Feeds.enroll(s.feeds, s.config, self(), &record_source(s, &1))

    if s.tool_lifecycle != nil and not Ipse.Session.ToolLifecycle.recording?(s.tool_lifecycle) do
      Enum.each(feeds.resources, fn {_, resource} ->
        if resource.intent["declaration"]["event"] in ~w(tool.intent_committed tool.outcome_recorded tool.recording_stopped),
          do: FeedChannel.stop(resource, "source_unavailable")
      end)
    end

    if feeds.refused > s.feeds.refused,
      do:
        notify(
          s,
          {:status, "Event feed lease capacity refused enrollment; inspect /diagnostics."}
        )

    %{s | feeds: feeds}
  end

  defp record_feed_close(s, id, r, cleanup) do
    FeedChannel.stop(r, "consumer_down")
    record(s, Feeds.closed(r, cleanup))
    :ets.delete_all_objects(r.pending)

    notify(
      s,
      {:status, "Event feed closed; inspect /diagnostics for incomplete coverage and cleanup."}
    )

    put_in(s, [:feeds, :resources, id], %{r | closed: true, cleanup: cleanup})
  end

  @doc false
  def admit_request(s, config, kind) do
    event = Ipse.Usage.admission(s.id, config, kind, s.turn_id)
    s = account(s, event)

    %{
      s
      | active_request: event,
        last_request_id: event["request_id"],
        child_usage: Ipse.Extension.ChildUsage.apply_parent(s.child_usage, event)
    }
  end

  @doc false
  def account(s, event) do
    {:ok, accounting} = Ipse.Usage.apply_event(s.accounting, event)
    record(s, event)
    %{s | accounting: accounting}
  end

  @doc false
  def record_extension_action(s, event) do
    if Ipse.Extension.Actions.inference?(event["request"]) do
      account(s, event)
    else
      record(s, event)

      contributions =
        Ipse.Extension.Context.admit_replacement(
          s.extension_contributions,
          if(s.invocation.parent, do: s.invocation.parent["identity"]),
          event,
          if(s.reference, do: Ipse.Session.Reference.layout())
        )

      %{s | extension_contributions: contributions}
    end
  end

  @doc false
  def measure_request(%{extension_model: %{admission: admission, started: started}} = s, result) do
    observed = s.accounting.requests[admission["request_id"]].observation

    event =
      Ipse.Usage.completion(
        admission,
        result,
        max(System.monotonic_time(:millisecond) - started, 0),
        observed
      )

    s = account(s, event)
    %{s | extension_model: nil}
  end

  @doc false
  def measure_request(
        %{phase: phase, request_started_at: started, active_request: admission} = s,
        result
      )
      when phase in [:model, :compaction] and is_integer(started) and admission != nil do
    outcome =
      cond do
        result == :cancelled -> "cancelled"
        match?({:ok, _, _}, result) -> "completed"
        true -> "failed"
      end

    record(s, %{
      "type" => "request_measured",
      "kind" => Atom.to_string(phase),
      "outcome" => outcome,
      "duration_ms" => max(System.monotonic_time(:millisecond) - started, 0)
    })

    observed = s.accounting.requests[admission["request_id"]].observation

    event =
      Ipse.Usage.completion(
        admission,
        result,
        max(System.monotonic_time(:millisecond) - started, 0),
        observed
      )

    s = account(s, event)
    if phase == :model, do: Turn.finish_text(s.text_stream, admission["request_id"], outcome)
    %{s | active_request: nil, request_started_at: nil}
  end

  @doc false
  def measure_request(s, _), do: s

  defp usage_version(config) do
    cond do
      Ipse.Config.Decisions.enabled?(config) -> 3
      Ipse.Config.Profiles.embeddings_enabled?(config) -> 2
      true -> 1
    end
  end

  defp open(dir, nil, cwd, config) do
    config = Ipse.MCP.fingerprint_version(config, 2)
    config = Map.put(config, :source_layout, Ipse.Session.SourceWindow.layout())

    with {:ok, mode} <- Ipse.Extension.Mode.capture(config),
         config = apply_execution_mode(config, mode),
         selected_id = Ipse.Usage.id(),
         {:ok, semantic_admission} <-
           Ipse.Extension.SemanticAdmission.fresh(config, cwd, selected_id),
         config = Map.put(config, :semantic_admission, semantic_admission),
         {:ok, id} <-
           Journal.create_with_id(
             dir,
             selected_id,
             %{
               "cwd" => cwd,
               "reference_layout" => Ipse.Session.Reference.layout(),
               "source_layout" => Ipse.Session.SourceWindow.layout(),
               "execution_mode" => mode,
               "semantic_admission" => semantic_admission,
               "usage_version" => usage_version(config),
               "embedding_profiles" => Ipse.Config.Profiles.embedding_snapshot(config),
               "decision_profiles" => Ipse.Config.Decisions.snapshot(config),
               "max_output_tokens" => config[:max_output_tokens],
               "model_profiles" => ModelCall.snapshot(config),
               "budget" => config[:budget],
               "budget_root" => config[:budget_root],
               "provider" => to_string(config.provider),
               "provider_destination" => provider_destination(config),
               "model" => config.model,
               "sandbox" => to_string(Map.get(config, :sandbox, :off)),
               "mcp_servers" => Ipse.MCP.fingerprints(config),
               "mcp_fingerprint_version" => 2,
               "subagents" => Ipse.Tools.Delegation.enabled?(config),
               "subagent_concurrency" => Map.get(config, :subagent_concurrency, 1),
               "delegation_origin" => config[:delegation_origin],
               "configuration" => Map.get(config, :configuration),
               "execution" => Map.get(config, :execution),
               "extensions" => Ipse.Extension.Registry.manifests(config),
               "extension_catalog" => extension_catalog(config),
               "extension_subscriptions" => Subscriptions.snapshot(config)
             },
             config[:journal]
           ),
         do: {:ok, id, [], config}
  end

  defp open(dir, id, cwd, config) do
    with {:ok, [%{"metadata" => meta} | _] = events} <- Journal.load(dir, id, config[:journal]),
         :ok <- Ipse.Journal.writable_events(events),
         {:ok, version} <- Ipse.MCP.Config.journal_fingerprint_version(meta),
         config = Ipse.MCP.fingerprint_version(config, version),
         true <- meta["source_layout"] in [nil, Ipse.Session.SourceWindow.layout()],
         config = Map.put(config, :source_layout, meta["source_layout"]),
         {:ok, saved_mode} <- Saved.execution_mode(events),
         {:ok, mode} <- resume_execution_mode(saved_mode, config),
         config = apply_execution_mode(config, mode),
         {:ok, saved_admission} <- Saved.semantic_admission(events, id),
         {:ok, semantic_admission} <-
           Ipse.Extension.SemanticAdmission.resume(config, cwd, id, saved_admission),
         config = Map.put(config, :semantic_admission, semantic_admission),
         {:ok, old_cwd} <- Workspace.canonical_path(meta["cwd"]),
         true <-
           old_cwd == cwd and meta["provider"] == to_string(config.provider) and
             matching_destination?(meta, config, events) and
             meta["model"] == config.model and
             meta["max_output_tokens"] === config[:max_output_tokens] and
             meta["model_profiles"] === ModelCall.snapshot(config) and
             meta["embedding_profiles"] === Ipse.Config.Profiles.embedding_snapshot(config) and
             meta["decision_profiles"] === Ipse.Config.Decisions.snapshot(config) and
             meta["budget"] === config[:budget] and meta["budget_root"] === config[:budget_root] and
             Map.get(meta, "sandbox", "off") == to_string(Map.get(config, :sandbox, :off)) and
             Map.get(meta, "mcp_servers", []) == Ipse.MCP.fingerprints(config) and
             Map.get(meta, "subagents", false) == Ipse.Tools.Delegation.enabled?(config) and
             Map.get(meta, "subagent_concurrency", 1) == Map.get(config, :subagent_concurrency, 1) and
             meta["delegation_origin"] == config[:delegation_origin] and
             compatible_configuration?(meta["configuration"], config[:configuration]) and
             meta["execution"] == json_execution(config[:execution]) and
             Map.get(meta, "extensions", []) == Ipse.Extension.Registry.manifests(config),
         true <-
           Map.get(meta, "extension_catalog", %{"version" => 1, "entries" => []}) ==
             extension_catalog(config),
         true <-
           Map.get(meta, "extension_subscriptions", %{"version" => 1, "entries" => []}) ==
             Subscriptions.snapshot(config),
         :ok <- Ipse.Session.Saved.validate_handoff_events(events),
         {:ok, _} <- Ipse.Usage.restore(events, id),
         {:ok, _messages} <- restore_context(events) do
      {:ok, id, events, config}
    else
      false -> {:error, :resume_configuration_mismatch}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_session}
    end
  end

  defp resume_execution_mode(nil, config), do: Ipse.Extension.Mode.capture(config)
  defp resume_execution_mode(saved, config), do: Ipse.Extension.Mode.inherit(saved, config)

  defp apply_execution_mode(config, mode) do
    Map.merge(config, %{
      approval: String.to_existing_atom(mode["approval"]),
      approval_origin: mode["approval_origin"],
      headless: mode["headless"],
      execution_mode: mode["ceiling"],
      enclosing_mode: mode["enclosing_ceiling"],
      knowledge_ceiling: mode["knowledge"]
    })
  end

  defp extension_catalog(config) do
    {:ok, catalog} = Catalog.snapshot(config)
    catalog
  end

  defp provider_configuration(%{provider: :demo}), do: :ok

  defp provider_configuration(config) do
    case Ipse.Provider.destination(config) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_provider_endpoint}
    end
  end

  defp provider_destination(%{provider: :demo}), do: nil

  defp provider_destination(config) do
    {:ok, destination} = Ipse.Provider.destination(config)
    destination
  end

  defp matching_destination?(metadata, config, events) do
    if Map.has_key?(metadata, "provider_destination") do
      metadata["provider_destination"] === provider_destination(config)
    else
      expected =
        if is_binary(config[:base_url]), do: Ipse.JSON.sha256(config.base_url)

      requests =
        Enum.filter(
          events,
          &(&1["type"] == "request_admitted" and &1["kind"] in ~w(model compaction))
        )

      if requests == [],
        do:
          is_nil(expected) or
            (metadata["execution"] == json_execution(config[:execution]) and
               config[:execution] != nil),
        else: Enum.all?(requests, &(&1["endpoint_sha256"] === expected))
    end
  end

  defp compatible_configuration?(nil, nil), do: true
  defp compatible_configuration?(nil, %{"sources" => []}), do: true
  defp compatible_configuration?(nil, %{sources: []}), do: true

  defp compatible_configuration?(old, current) when is_map(old) and is_map(current) do
    old["fingerprint"] == (current[:fingerprint] || current["fingerprint"])
  end

  defp compatible_configuration?(_, _), do: false

  defp json_execution(nil), do: nil
  defp json_execution(execution), do: execution |> Jason.encode!() |> Jason.decode!()

  defp runtime(s),
    do: Ipse.Session.Context.runtime_snapshot(s.config, s.reported_model, s.historical_model)

  @doc "Validate saved effective context without starting inference, tools or a session."

  defdelegate restore_context(events), to: Ipse.Session.Saved, as: :context

  defp lifecycle_records(s, {context, records}) do
    Enum.each(records, &record(s, &1))
    %{s | lifecycle: context}
  end

  @doc false
  def ensure_source_window(s) do
    if Ipse.Session.SourceWindow.enabled?(s.config) do
      case Writer.ensure_source_window(s.journal_writer) do
        :ok -> :ok
        {:error, reason} -> journal_failed(s, reason)
      end
    end

    s
  end

  @doc false
  def ensure_source_tracking(s) do
    if Ipse.Session.SourceWindow.enabled?(s.config) do
      s = ensure_source_window(s)

      s =
        if s.lifecycle == nil,
          do:
            lifecycle_records(
              s,
              Ipse.Session.RuntimeLifecycle.open_source(
                s.source_runtime_summary,
                s.id,
                s.source_resumed
              )
            ),
          else: s

      if s.tool_lifecycle == nil,
        do:
          Turn.tool_records(
            s,
            Ipse.Session.ToolLifecycle.open_source(s.source_tool_summary, s.id, s.lifecycle)
          ),
        else: s
    else
      s
    end
  end

  @doc false
  def begin_wait(s, domain, links),
    do: lifecycle_records(s, Ipse.Session.RuntimeLifecycle.begin_wait(s.lifecycle, domain, links))

  @doc false
  def finish_wait(s, outcome),
    do: lifecycle_records(s, Ipse.Session.RuntimeLifecycle.finish_wait(s.lifecycle, outcome))

  defp close_epoch(s, reason, cleanup),
    do: lifecycle_records(s, Ipse.Session.RuntimeLifecycle.close(s.lifecycle, reason, cleanup))

  @doc false
  def record_wait_subject(s, event) do
    if match?(%{active: true}, s.lifecycle) or Feeds.active?(s.feeds) do
      case Writer.append_with_source(s.journal_writer, event) do
        {:ok, source} -> source
        {:error, reason} -> journal_failed(s, reason)
      end
    else
      record(s, event)
      nil
    end
  end

  @doc false
  def question_wait(s, question, source, turn \\ :current)

  @doc false
  def question_wait(s, %{kind: :extension} = question, source, _turn),
    do:
      begin_wait(s, "extension_question", %{
        "turn_id" => question.parent["payload"]["turn_id"],
        "parent_invocation_id" => question.parent["invocation_id"],
        "operation_id" => question.action["operation_id"],
        "subject_source" => source
      })

  @doc false
  def question_wait(s, _question, source, turn),
    do:
      begin_wait(s, "native_question", %{
        "turn_id" => if(turn == :current, do: s.turn_id, else: turn),
        "request_id" => s.last_request_id,
        "subject_source" => source
      })

  defp question_available(nil, _), do: :ok

  defp question_available(_, config),
    do: if(Questions.enabled?(config), do: :ok, else: {:error, :operator_input_unavailable})

  @doc false
  def checkpoint_event_question(s, question) do
    if s.event_committed != nil and s.event_intent == nil do
      record(
        s,
        Subscriptions.question_sources(
          s.turn_id,
          question.id,
          s.event_received.source,
          s.event_committed.source
        )
      )
    end
  end

  @doc false
  def owned_task(fun, failure_status \\ :error) do
    owner = self()
    {:ok, scope} = Ipse.Session.Resources.start(owner)
    :ok = Ipse.Session.Lock.track(scope, :scope)

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        Ipse.Session.Resources.await_ready(scope, owner)
        Ipse.Session.Resources.bind(scope)

        result =
          try do
            fun.()
          rescue
            _ ->
              {failure_status, "Worker failed. Inspect the workspace before retrying any action."}
          catch
            _, _ ->
              {failure_status,
               "Worker interrupted. Inspect the workspace before retrying any action."}
          end

        if Ipse.Session.Resources.finish(scope) != :ok,
          do: send(owner, {:owned_task_cleanup_failed, self()})

        result
      end)

    :ok = Ipse.Session.Lock.track(task.pid, :worker)
    :ok = Ipse.Session.Resources.attach(scope, task.pid)
    send(task.pid, {:cleanup_scope_ready, scope})
    task
  end

  defp acquire_lock(path, retries) do
    case Ipse.Session.Lock.acquire(path) do
      {:ok, port} ->
        {:ok, port}

      {:error, _} when retries > 0 ->
        Process.sleep(20)
        acquire_lock(path, retries - 1)

      error ->
        error
    end
  end
end
