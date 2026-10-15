defmodule Ipse.Session do
  @moduledoc "One supervised owner per coding conversation. I/O runs in monitored tasks."
  use GenServer
  alias Ipse.{Journal, Skills, Tools, WorkspaceContext}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}, restart: :temporary}

  def prompt(pid, text), do: GenServer.call(pid, {:prompt, text})
  def approve(pid, ref, allowed), do: GenServer.call(pid, {:approve, ref, allowed})
  def cancel(pid), do: GenServer.call(pid, :cancel, 10_000)
  def refresh_context(pid), do: GenServer.call(pid, :refresh_context)
  def info(pid), do: GenServer.call(pid, :info)

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    requested_cwd = Keyword.fetch!(opts, :cwd)
    home = Map.get(config, :home) || System.get_env("IPSE_HOME") || Path.expand("~/.ipse")
    dir = Keyword.fetch!(opts, :state_dir) |> Path.expand()
    id = Keyword.get(opts, :id)

    with {:ok, cwd} <- WorkspaceContext.canonical_path(requested_cwd),
         true <- File.dir?(cwd),
         {:ok, id, _events} <- open(dir, id, cwd, config),
         {:ok, _} <- Registry.register(Ipse.Registry, {dir, id}, nil),
         {:ok, lock} <- acquire_lock(Path.join(dir, id <> ".lock"), 10),
         :ok <- Journal.repair_tail(dir, id),
         {:ok, events} <- Journal.load(dir, id),
         {:ok, messages} <- restore(events),
         {:ok, context_snapshot, context_is_new} <- workspace_snapshot(events, cwd, home) do
      state = %{
        id: id,
        dir: dir,
        cwd: cwd,
        config: config,
        context_home: Path.expand(home),
        context_snapshot: context_snapshot,
        context_drift: WorkspaceContext.drift(context_snapshot),
        reported_model: nil,
        historical_model: historical_model(events),
        subscriber: Keyword.fetch!(opts, :subscriber),
        skills: Skills.discover(cwd, Path.join(Path.expand(home), "skills")),
        messages: messages,
        compaction: nil,
        tool_decision: "not_decided",
        task: nil,
        job_ref: nil,
        phase: :idle,
        calls: [],
        approval: nil,
        steps: 0,
        lock: lock,
        usage: %{},
        final: "",
        mcp_tools: [],
        mcp_ready: false,
        mcp_resources: %{}
      }

      if context_is_new,
        do: {:ok, persist_context(state, context_snapshot, true)},
        else: {:ok, state}
    else
      false -> {:stop, :workspace_not_found}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:mcp_register, ref, resource}, _from, %{job_ref: ref} = s) when ref != nil do
    monitor = Process.monitor(resource)
    {:reply, :ok, %{s | mcp_resources: Map.put(s.mcp_resources, resource, monitor)}}
  end

  def handle_call({:mcp_register, _, _}, _from, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(:info, _from, s) do
    info =
      Map.take(s, [:id, :cwd, :phase, :usage, :final])
      |> Map.put(:runtime, runtime(s))
      |> Map.put(:context, context_manifest(s))
      |> Map.put(:sandbox, Ipse.Sandbox.info(Map.get(s.config, :sandbox, :off)))
      |> Map.put(:mcp, Enum.map(Map.get(s.config, :mcp_servers, []), &Ipse.MCP.Config.manifest/1))

    {:reply, info, s}
  end

  def handle_call(:refresh_context, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call(:refresh_context, _from, s) do
    task =
      owned_task(fn ->
        with {:ok, snapshot} <- WorkspaceContext.snapshot(s.cwd, s.context_home) do
          {:ok, snapshot, WorkspaceContext.drift(snapshot)}
        end
      end)

    notify(s, {:status, :refreshing_context})
    {:reply, :ok, %{s | task: task, phase: :context_refresh, job_ref: nil}}
  end

  def handle_call({:prompt, _}, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call({:prompt, text}, _from, s) when is_binary(text) and byte_size(text) > 0 do
    text =
      Enum.reduce(Skills.explicit(text, s.skills), text, fn name, acc ->
        case Skills.load(s.skills, name) do
          {:ok, body} ->
            notify(s, {:skill, name})
            acc <> "\n\n" <> body

          _ ->
            acc
        end
      end)

    s = append_message(s, %{"role" => "user", "content" => text})
    {:reply, :ok, model(%{s | steps: 0, final: "", mcp_ready: false})}
  end

  def handle_call({:prompt, _}, _from, s), do: {:reply, {:error, :empty_prompt}, s}

  def handle_call({:approve, ref, allowed}, _from, %{approval: {ref, call, args}} = s) do
    s = %{s | approval: nil}

    if allowed,
      do: {:reply, :ok, launch_tool(s, call, args, "approved")},
      else:
        {:reply, :ok,
         tool_result(s, call, "Denied by user. Do not evade this denial.", "denied", "denied")}
  end

  def handle_call({:approve, _, _}, _from, s), do: {:reply, {:error, :no_pending_approval}, s}

  def handle_call(:cancel, _from, s) do
    cleanup =
      s.mcp_resources
      |> Map.keys()
      |> Enum.filter(&Process.alive?/1)
      |> Enum.map(&Ipse.MCP.Transport.close/1)

    if s.task, do: Task.shutdown(s.task, :brutal_kill)

    s =
      settle_calls(
        s,
        "Cancelled. If execution had started, its effects may have occurred. Inspect the workspace before retrying."
      )

    record(s, %{"type" => "cancelled"})

    next =
      %{
        s
        | phase: :idle,
          task: nil,
          approval: nil,
          job_ref: nil,
          compaction: nil,
          tool_decision: "not_decided",
          mcp_resources: %{}
      }

    if Enum.any?(cleanup, &(&1 != :ok)) do
      notify(
        s,
        {:error, "MCP cleanup could not be confirmed. Inspect running processes before retrying."}
      )

      notify(s, {:done, :error})
      {:stop, :normal, {:error, :cleanup_unconfirmed}, next}
    else
      notify(s, {:done, :cancelled})
      {:reply, :ok, next}
    end
  end

  @impl true
  def handle_info({:progress, ref, event}, %{job_ref: ref} = s) when ref != nil do
    if s.phase != :idle, do: notify(s, event)
    {:noreply, s}
  end

  def handle_info({ref, result}, %{task: %{ref: ref}} = s) do
    Process.demonitor(ref, [:flush])
    phase = s.phase
    s = %{s | task: nil}

    case {phase, result} do
      {:mcp_discovery, {:ok, tools}} ->
        record(s, %{"type" => "mcp_catalog", "version" => 1, "tools" => Ipse.MCP.manifests(tools)})

        {:noreply, model(%{s | mcp_tools: tools, mcp_ready: true})}

      {:mcp_discovery, {:error, error}} ->
        {:noreply, fail(s, error)}

      {:tool, {:unknown, error}} ->
        {:noreply, fail(s, error)}

      {:context_preflight, {:ok, snapshot, drift}} ->
        if snapshot == s.context_snapshot do
          {:noreply, dispatch_pending_tool(%{s | context_drift: drift})}
        else
          s = persist_context(%{s | context_drift: drift}, snapshot)

          s =
            settle_calls(
              s,
              "Not executed: new scoped workspace context was loaded. Review it before retrying this action."
            )

          {:noreply, model(s)}
        end

      {:context_preflight, {:error, reason}} ->
        s =
          settle_calls(
            s,
            "Not executed: scoped context could not be loaded (#{inspect(reason)}). Review workspace guidance before retrying."
          )

        {:noreply, model(s)}

      {:context_refresh, {:ok, snapshot, drift}} ->
        s = persist_context(%{s | context_drift: drift}, snapshot)
        manifest = context_manifest(s)
        notify(s, {:context_refreshed, manifest})
        notify(s, {:done, :ok})
        {:noreply, %{s | phase: :idle, job_ref: nil}}

      {:context_refresh, {:error, reason}} ->
        notify(s, {:error, "Workspace context refresh failed: #{inspect(reason)}"})
        notify(s, {:done, {:error, reason}})
        {:noreply, %{s | phase: :idle, job_ref: nil}}

      {:compaction, {:ok, assistant, usage}} ->
        {:noreply, complete_compaction(s, assistant, usage)}

      {:compaction, {:error, _error}} ->
        {:noreply, compaction_failed(s)}

      {:model, {:ok, assistant, usage}} ->
        s = append_message(s, assistant)
        calls = Map.get(assistant, "tool_calls", []) || []

        s = %{
          s
          | usage: usage,
            calls: calls,
            final: assistant["content"] || "",
            reported_model: reported_model(assistant)
        }

        notify(s, {:usage, usage})
        if calls == [], do: {:noreply, finish(s, :ok)}, else: {:noreply, next_tool(s)}

      {:model, {:error, error}} ->
        {:noreply, fail(s, error)}

      {:tool, {status, text}} when is_binary(text) ->
        outcome = if status == :error, do: "error", else: "result_recorded"
        {:noreply, tool_result(s, hd(s.calls), text, outcome, s.tool_decision)}

      _ ->
        {:noreply, fail(s, "Unexpected worker result")}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %{ref: ref}} = s) do
    {:noreply,
     fail(
       %{s | task: nil},
       "Worker stopped unexpectedly; any started tool may have taken effect."
     )}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, s) do
    resources =
      if s.mcp_resources[pid] == ref, do: Map.delete(s.mcp_resources, pid), else: s.mcp_resources

    {:noreply, %{s | mcp_resources: resources}}
  end

  def handle_info({port, {:exit_status, _}}, %{lock: port} = s) do
    # Stop without appending: journal ownership is no longer guaranteed.
    notify(s, {:error, "Session lock helper exited; stopping to protect the journal."})
    notify(s, {:done, :error})
    {:stop, :normal, s}
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def terminate(_reason, s) do
    if s.task, do: Task.shutdown(s.task, :brutal_kill)
    Ipse.Runner.unlock(s.lock)
    :ok
  end

  @impl true
  def format_status(_reason, [_dictionary, state]) do
    [data: [{~c"State", Map.take(state, [:id, :phase])}]]
  end

  defp system_message(s) do
    %{
      "role" => "system",
      "content" =>
        Ipse.Context.system(
          s.cwd,
          s.skills,
          runtime(s),
          s.context_snapshot,
          Map.get(s.config, :sandbox, :off)
        )
    }
  end

  defp workspace_snapshot(events, cwd, home) do
    case Enum.find(Enum.reverse(events), &(&1["type"] == "workspace_context_snapshot")) do
      nil ->
        case WorkspaceContext.snapshot(cwd, home) do
          {:ok, snapshot} -> {:ok, snapshot, true}
          {:error, reason} -> {:error, {:workspace_context_unavailable, reason}}
        end

      %{"version" => 1, "snapshot" => snapshot} ->
        if WorkspaceContext.valid?(snapshot) and snapshot["cwd"] == cwd,
          do: {:ok, snapshot, false},
          else: {:error, :invalid_workspace_context_snapshot}

      _ ->
        {:error, :invalid_workspace_context_snapshot}
    end
  end

  defp persist_context(s, snapshot, force \\ false) do
    if force or snapshot != s.context_snapshot do
      record(s, %{
        "type" => "workspace_context_snapshot",
        "version" => 1,
        "snapshot" => snapshot
      })
    end

    %{s | context_snapshot: snapshot}
  end

  defp context_manifest(s) do
    manifest = WorkspaceContext.manifest(s.context_snapshot)
    diagnostics = Enum.uniq(manifest["diagnostics"] ++ s.context_drift)
    %{manifest | "diagnostics" => diagnostics}
  end

  defp model(s) do
    servers = Map.get(s.config, :mcp_servers, [])

    cond do
      servers != [] and not s.mcp_ready ->
        resource = %{owner: self(), job_ref: make_ref()}
        task = owned_task(fn -> Ipse.MCP.discover(servers, s.cwd, resource) end)
        notify(s, {:status, :discovering_mcp})
        %{s | task: task, phase: :mcp_discovery, job_ref: resource.job_ref}

      s.steps >= Map.get(s.config, :max_steps, 30) ->
        fail(
          s,
          "Reached the #{Map.get(s.config, :max_steps, 30)}-step limit. Send another message to continue."
        )

      true ->
        system = system_message(s)

        case Ipse.Compaction.prepare(s.messages, s.config, system) do
          :skip ->
            launch_model(s, [system | s.messages])

          {:ok, plan} ->
            task =
              owned_task(fn -> request(s.config, plan.summary_messages, [], fn _ -> :ok end) end)

            notify(s, {:status, :compacting})

            %{
              s
              | task: task,
                phase: :compaction,
                compaction: plan,
                steps: s.steps + 1,
                job_ref: nil
            }

          {:error, _reason} ->
            compaction_failed(s)
        end
    end
  end

  defp launch_model(s, messages) do
    owner = self()
    job_ref = make_ref()

    task =
      owned_task(fn ->
        request(
          s.config,
          messages,
          definitions(s.config) ++ Ipse.MCP.definitions(s.mcp_tools),
          fn event ->
            send(owner, {:progress, job_ref, event})
          end
        )
      end)

    notify(s, {:status, "Thinking"})
    %{s | task: task, phase: :model, steps: s.steps + 1, job_ref: job_ref}
  end

  defp request(config, messages, tools, emit) do
    provider =
      Map.get(
        config,
        :provider_module,
        if(config.provider == :demo, do: Ipse.Provider.Demo, else: Ipse.Provider)
      )

    credentials =
      if config.provider == :chatgpt do
        case Ipse.Auth.token(config.auth_dir) do
          {:ok, token} -> {:ok, Map.put(config, :api_key, token)}
          error -> error
        end
      else
        key =
          case config.provider do
            :openai -> System.get_env("OPENAI_API_KEY")
            :anthropic -> System.get_env("ANTHROPIC_API_KEY")
            _ -> nil
          end

        {:ok, Map.put_new(config, :api_key, key)}
      end

    with {:ok, config} <- credentials, do: provider.complete(config, messages, tools, emit)
  end

  defp complete_compaction(s, assistant, usage) do
    case Ipse.Compaction.finish(s.compaction, assistant, system_message(s), s.config) do
      {:ok, messages, checkpoint, stats} ->
        record(s, %{
          "type" => "context_compacted",
          "version" => 1,
          "covered_messages" => length(s.compaction.prefix),
          "prefix_sha256" => Ipse.Compaction.digest(s.compaction.prefix),
          "checkpoint" => checkpoint,
          "before_bytes" => stats.before_bytes,
          "after_bytes" => stats.after_bytes
        })

        notify(s, {:compacted, stats.before_bytes, stats.after_bytes})
        notify(s, {:usage, usage})

        model(%{
          s
          | messages: messages,
            compaction: nil,
            usage: usage,
            reported_model: reported_model(assistant)
        })

      {:error, _reason} ->
        compaction_failed(s)
    end
  end

  defp compaction_failed(s) do
    fail(
      s,
      "Context compaction could not safely fit this conversation. Original history is retained. " <>
        "Review the journal and start a new session with the necessary context; no tools were replayed."
    )
  end

  defp next_tool(%{calls: []} = s), do: model(s)

  defp next_tool(s) do
    call = hd(s.calls)
    name = get_in(call, ["function", "name"])

    with args when is_binary(args) <- get_in(call, ["function", "arguments"]),
         {:ok, args} when is_map(args) <- Jason.decode(args) do
      if name in ["read", "write", "edit"] do
        task =
          owned_task(fn ->
            with {:ok, snapshot, _added} <-
                   WorkspaceContext.nested(s.context_snapshot, args["path"]) do
              {:ok, snapshot, WorkspaceContext.drift(snapshot)}
            end
          end)

        notify(s, {:status, :checking_workspace_context})
        %{s | phase: :context_preflight, task: task, job_ref: nil}
      else
        dispatch_tool(s, call, args)
      end
    else
      _ ->
        tool_result(
          s,
          call,
          "Invalid tool arguments: expected a JSON object.",
          "invalid_arguments",
          "not_decided"
        )
    end
  end

  defp dispatch_pending_tool(s) do
    case s.calls do
      [call | _] ->
        with args when is_binary(args) <- get_in(call, ["function", "arguments"]),
             {:ok, args} when is_map(args) <- Jason.decode(args) do
          dispatch_tool(s, call, args)
        else
          _ ->
            tool_result(
              s,
              call,
              "Invalid tool arguments: expected a JSON object.",
              "invalid_arguments",
              "not_decided"
            )
        end

      [] ->
        model(s)
    end
  end

  defp dispatch_tool(s, call, args) do
    name = get_in(call, ["function", "name"])
    mode = Map.get(s.config, :approval, :ask)
    external = Ipse.MCP.external?(name)

    validation =
      if external, do: Ipse.MCP.validate_call(Ipse.MCP.tool(s.mcp_tools, name), args), else: :ok

    requires_approval = Tools.mutating?(name) or external

    cond do
      validation != :ok ->
        {:error, reason} = validation
        tool_result(s, call, reason, "invalid_arguments", "not_decided")

      requires_approval and mode == :deny ->
        tool_result(
          s,
          call,
          "Denied: this run is read-only. Ask the user to enable execution.",
          "denied",
          "policy_denied"
        )

      requires_approval and mode == :ask ->
        ref = make_ref()
        notify(s, {:approval, ref, name, args})
        %{s | phase: :approval, approval: {ref, call, args}}

      true ->
        decision = if requires_approval, do: "session_allow", else: "not_required"
        launch_tool(s, call, args, decision)
    end
  end

  defp launch_tool(s, call, args, decision) do
    name = get_in(call, ["function", "name"])
    external = Ipse.MCP.tool(s.mcp_tools, name)

    record(s, %{
      "type" => "tool_started",
      "call_id" => call["id"],
      "name" => name,
      "approval" => decision,
      "arguments" => if(external, do: args),
      "mcp" => if(external, do: Ipse.MCP.Client.manifest(external)),
      "sandbox_requested" => to_string(Map.get(s.config, :sandbox, :off))
    })

    notify(s, {:tool, name, args})
    owner = self()
    job_ref = make_ref()

    context = %{
      cwd: s.cwd,
      skills: s.skills,
      sandbox: Map.get(s.config, :sandbox, :off),
      emit: fn event -> send(owner, {:progress, job_ref, event}) end
    }

    task =
      owned_task(fn ->
        cond do
          external ->
            Ipse.MCP.Client.call(external, args, s.cwd, %{owner: owner, job_ref: job_ref})

          name == "load_skill" ->
            Skills.load(s.skills, args["name"] || "")

          true ->
            Tools.execute(name, args, context)
        end
      end)

    %{s | phase: :tool, task: task, job_ref: job_ref, tool_decision: decision}
  end

  defp tool_result(s, call, text, status, approval) do
    s =
      append_message(s, %{
        "role" => "tool",
        "tool_call_id" => call["id"],
        "content" => text,
        "ipse_tool_outcome" => %{"status" => status, "approval" => approval}
      })

    notify(s, {:tool_result, get_in(call, ["function", "name"]), text})
    next_tool(%{s | calls: tl(s.calls), tool_decision: "not_decided"})
  end

  defp settle_calls(s, text) do
    s.calls
    |> Enum.with_index()
    |> Enum.reduce(s, fn {call, index}, state ->
      started = index == 0 and s.phase == :tool
      approval = if started, do: s.tool_decision, else: "not_decided"
      status = if started, do: "unknown", else: "not_started"
      outcome = if started, do: text, else: "Not executed: work stopped before this call started."

      append_message(state, %{
        "role" => "tool",
        "tool_call_id" => call["id"],
        "content" => outcome,
        "ipse_tool_outcome" => %{"status" => status, "approval" => approval}
      })
    end)
    |> Map.put(:calls, [])
  end

  defp fail(s, error) do
    notify(s, {:error, error})

    s
    |> settle_calls("Outcome unknown after interruption. Inspect before retrying.")
    |> finish(:error)
  end

  defp finish(s, status) do
    record(s, %{"type" => "turn_finished", "status" => to_string(status)})
    notify(s, {:done, status})

    %{
      s
      | phase: :idle,
        task: nil,
        approval: nil,
        job_ref: nil,
        compaction: nil,
        tool_decision: "not_decided"
    }
  end

  defp append_message(s, message) do
    record(s, %{"type" => "message", "message" => message})
    %{s | messages: s.messages ++ [message]}
  end

  defp record(s, event) do
    case Journal.append(s.dir, s.id, event) do
      :ok -> :ok
      {:error, reason} -> raise "Journal write failed: #{inspect(reason)}"
    end
  end

  defp notify(s, event), do: send(s.subscriber, {:ipse, self(), event})

  defp open(dir, nil, cwd, config) do
    with {:ok, id} <-
           Journal.create(dir, %{
             "cwd" => cwd,
             "provider" => to_string(config.provider),
             "model" => config.model,
             "sandbox" => to_string(Map.get(config, :sandbox, :off)),
             "mcp_servers" => Ipse.MCP.fingerprints(config)
           }),
         do: {:ok, id, []}
  end

  defp open(dir, id, cwd, config) do
    with {:ok, [%{"metadata" => meta} | _] = events} <- Journal.load(dir, id),
         {:ok, old_cwd} <- WorkspaceContext.canonical_path(meta["cwd"]),
         true <-
           old_cwd == cwd and meta["provider"] == to_string(config.provider) and
             meta["model"] == config.model and
             Map.get(meta, "sandbox", "off") == to_string(Map.get(config, :sandbox, :off)) and
             Map.get(meta, "mcp_servers", []) == Ipse.MCP.fingerprints(config) do
      {:ok, id, events}
    else
      false -> {:error, :resume_configuration_mismatch}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_session}
    end
  end

  defp runtime(s),
    do: Ipse.RuntimeInfo.snapshot(s.config, s.reported_model, s.historical_model)

  defp reported_model(%{"provider_data" => data}) when is_map(data),
    do: Ipse.RuntimeInfo.model_name(data["reported_model"])

  defp reported_model(_), do: nil

  defp historical_model(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "message", "message" => %{"role" => "assistant"} = message} ->
        {:found, reported_model(message)}

      _ ->
        nil
    end)
    |> case do
      {:found, model} -> model
      nil -> nil
    end
  end

  defp restore(events) do
    Enum.reduce_while(events, {:ok, []}, fn
      %{"type" => "message", "message" => message}, {:ok, messages} ->
        {:cont, {:ok, messages ++ [message]}}

      %{"type" => "context_compacted"} = event, {:ok, messages} ->
        messages = restore_messages(messages)
        count = event["covered_messages"]

        if event["version"] == 1 and is_integer(count) and count > 0 and
             count <= length(messages) and
             Ipse.Compaction.valid_checkpoint?(event["checkpoint"]) and
             Ipse.Compaction.digest(Enum.take(messages, count)) == event["prefix_sha256"] do
          {:cont, {:ok, [event["checkpoint"] | Enum.drop(messages, count)]}}
        else
          {:halt, {:error, :invalid_compaction_checkpoint}}
        end

      _, acc ->
        {:cont, acc}
    end)
    |> case do
      {:ok, messages} -> {:ok, restore_messages(messages)}
      error -> error
    end
  end

  defp restore_messages([]), do: []

  defp restore_messages([%{"role" => "assistant", "tool_calls" => calls} = message | rest])
       when is_list(calls) do
    {results, tail} = Enum.split_while(rest, &(&1["role"] == "tool"))
    by_id = Map.new(results, &{&1["tool_call_id"], &1})

    ordered =
      Enum.map(calls, fn call ->
        Map.get(by_id, call["id"], %{
          "role" => "tool",
          "tool_call_id" => call["id"],
          "content" =>
            "Outcome unknown: session interrupted before a result was recorded. Inspect the workspace before retrying.",
          "ipse_tool_outcome" => %{"status" => "unknown", "approval" => "historical_unknown"}
        })
      end)

    [message | ordered] ++ restore_messages(tail)
  end

  defp restore_messages([message | rest]), do: [message | restore_messages(rest)]

  defp owned_task(fun) do
    owner = self()

    Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
      worker = self()

      spawn(fn ->
        owner_ref = Process.monitor(owner)
        worker_ref = Process.monitor(worker)

        receive do
          {:DOWN, ^owner_ref, :process, _, _} -> Process.exit(worker, :kill)
          {:DOWN, ^worker_ref, :process, _, _} -> :ok
        end
      end)

      try do
        fun.()
      rescue
        _ -> {:error, "Worker failed. Inspect the workspace before retrying any action."}
      catch
        _, _ -> {:error, "Worker interrupted. Inspect the workspace before retrying any action."}
      end
    end)
  end

  defp acquire_lock(path, retries) do
    case Ipse.Runner.lock(path) do
      {:ok, port} ->
        {:ok, port}

      {:error, _} when retries > 0 ->
        Process.sleep(20)
        acquire_lock(path, retries - 1)

      error ->
        error
    end
  end

  defp definitions(config) do
    Tools.definitions(Map.get(config, :sandbox, :off)) ++
      [
        %{
          "type" => "function",
          "function" => %{
            "name" => "load_skill",
            "description" =>
              "Load a skill's full instructions by name. This grants no permissions.",
            "parameters" => %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}},
              "required" => ["name"]
            }
          }
        }
      ]
  end
end
