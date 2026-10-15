defmodule Ipse.Session do
  @moduledoc "One supervised owner per coding conversation. I/O runs in monitored tasks."
  use GenServer
  alias Ipse.{Journal, Skills, Tools}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}, restart: :temporary}

  def prompt(pid, text), do: GenServer.call(pid, {:prompt, text})
  def approve(pid, ref, allowed), do: GenServer.call(pid, {:approve, ref, allowed})
  def cancel(pid), do: GenServer.call(pid, :cancel, 10_000)
  def info(pid), do: GenServer.call(pid, :info)

  @impl true
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    cwd = Path.expand(Keyword.fetch!(opts, :cwd))
    dir = Keyword.fetch!(opts, :state_dir) |> Path.expand()
    id = Keyword.get(opts, :id)

    with true <- File.dir?(cwd),
         {:ok, id, _events} <- open(dir, id, cwd, config),
         {:ok, _} <- Registry.register(Ipse.Registry, {dir, id}, nil),
         {:ok, lock} <- acquire_lock(Path.join(dir, id <> ".lock"), 10),
         :ok <- Journal.repair_tail(dir, id),
         {:ok, events} <- Journal.load(dir, id) do
      state = %{
        id: id,
        dir: dir,
        cwd: cwd,
        config: config,
        subscriber: Keyword.fetch!(opts, :subscriber),
        skills: Skills.discover(cwd),
        messages: restore(events),
        task: nil,
        job_ref: nil,
        phase: :idle,
        calls: [],
        approval: nil,
        steps: 0,
        lock: lock,
        usage: %{},
        final: ""
      }

      {:ok, state}
    else
      false -> {:stop, :workspace_not_found}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:info, _from, s),
    do: {:reply, Map.take(s, [:id, :cwd, :phase, :usage, :final]), s}

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
    {:reply, :ok, model(%{s | steps: 0, final: ""})}
  end

  def handle_call({:prompt, _}, _from, s), do: {:reply, {:error, :empty_prompt}, s}

  def handle_call({:approve, ref, allowed}, _from, %{approval: {ref, call, args}} = s) do
    s = %{s | approval: nil}

    if allowed,
      do: {:reply, :ok, launch_tool(s, call, args)},
      else: {:reply, :ok, tool_result(s, call, "Denied by user. Do not evade this denial.")}
  end

  def handle_call({:approve, _, _}, _from, s), do: {:reply, {:error, :no_pending_approval}, s}

  def handle_call(:cancel, _from, s) do
    if s.task, do: Task.shutdown(s.task, :brutal_kill)

    s =
      settle_calls(
        s,
        "Cancelled. If execution had started, its effects may have occurred. Inspect the workspace before retrying."
      )

    record(s, %{"type" => "cancelled"})
    notify(s, {:done, :cancelled})
    {:reply, :ok, %{s | phase: :idle, task: nil, approval: nil, job_ref: nil}}
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
      {:model, {:ok, assistant, usage}} ->
        s = append_message(s, assistant)
        calls = Map.get(assistant, "tool_calls", []) || []
        s = %{s | usage: usage, calls: calls, final: assistant["content"] || ""}
        notify(s, {:usage, usage})
        if calls == [], do: {:noreply, finish(s, :ok)}, else: {:noreply, next_tool(s)}

      {:model, {:error, error}} ->
        {:noreply, fail(s, error)}

      {:tool, {_, text}} when is_binary(text) ->
        {:noreply, tool_result(s, hd(s.calls), text)}

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

  defp model(s) do
    max = Map.get(s.config, :max_steps, 30)

    if s.steps >= max do
      fail(s, "Reached the #{max}-step limit. Send another message to continue.")
    else
      messages = [
        %{"role" => "system", "content" => Ipse.Context.system(s.cwd, s.skills)} | s.messages
      ]

      if byte_size(Jason.encode!(messages)) > Map.get(s.config, :context_bytes, 400_000) do
        fail(
          s,
          "Conversation reached the prototype context limit. Start a new session with a concise summary."
        )
      else
        owner = self()
        job_ref = make_ref()

        provider =
          Map.get(
            s.config,
            :provider_module,
            if(s.config.provider == :demo, do: Ipse.Provider.Demo, else: Ipse.Provider)
          )

        task =
          owned_task(fn ->
            config =
              if s.config.provider == :chatgpt do
                case Ipse.Auth.token(s.config.auth_dir) do
                  {:ok, token} -> {:ok, Map.put(s.config, :api_key, token)}
                  error -> error
                end
              else
                key =
                  case s.config.provider do
                    :openai -> System.get_env("OPENAI_API_KEY")
                    :anthropic -> System.get_env("ANTHROPIC_API_KEY")
                    _ -> nil
                  end

                {:ok, Map.put_new(s.config, :api_key, key)}
              end

            with {:ok, config} <- config do
              provider.complete(config, messages, definitions(), fn event ->
                send(owner, {:progress, job_ref, event})
              end)
            end
          end)

        notify(s, {:status, "Thinking"})
        %{s | task: task, phase: :model, steps: s.steps + 1, job_ref: job_ref}
      end
    end
  end

  defp next_tool(%{calls: []} = s), do: model(s)

  defp next_tool(s) do
    call = hd(s.calls)
    name = get_in(call, ["function", "name"])

    with args when is_binary(args) <- get_in(call, ["function", "arguments"]),
         {:ok, args} when is_map(args) <- Jason.decode(args) do
      mode = Map.get(s.config, :approval, :ask)

      cond do
        Tools.mutating?(name) and mode == :deny ->
          tool_result(s, call, "Denied: this run is read-only. Ask the user to enable execution.")

        Tools.mutating?(name) and mode == :ask ->
          ref = make_ref()
          notify(s, {:approval, ref, name, args})
          %{s | phase: :approval, approval: {ref, call, args}}

        true ->
          launch_tool(s, call, args)
      end
    else
      _ -> tool_result(s, call, "Invalid tool arguments: expected a JSON object.")
    end
  end

  defp launch_tool(s, call, args) do
    name = get_in(call, ["function", "name"])
    record(s, %{"type" => "tool_started", "call_id" => call["id"], "name" => name})
    notify(s, {:tool, name, args})
    owner = self()
    job_ref = make_ref()

    context = %{
      cwd: s.cwd,
      skills: s.skills,
      emit: fn event -> send(owner, {:progress, job_ref, event}) end
    }

    task =
      owned_task(fn ->
        if name == "load_skill",
          do: Skills.load(s.skills, args["name"] || ""),
          else: Tools.execute(name, args, context)
      end)

    %{s | phase: :tool, task: task, job_ref: job_ref}
  end

  defp tool_result(s, call, text) do
    s = append_message(s, %{"role" => "tool", "tool_call_id" => call["id"], "content" => text})
    notify(s, {:tool_result, get_in(call, ["function", "name"]), text})
    next_tool(%{s | calls: tl(s.calls)})
  end

  defp settle_calls(s, text) do
    Enum.reduce(s.calls, s, fn call, state ->
      append_message(state, %{"role" => "tool", "tool_call_id" => call["id"], "content" => text})
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
    %{s | phase: :idle, task: nil, approval: nil, job_ref: nil}
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
             "model" => config.model
           }),
         do: {:ok, id, []}
  end

  defp open(dir, id, cwd, config) do
    with {:ok, [%{"metadata" => meta} | _] = events} <- Journal.load(dir, id),
         true <-
           meta["cwd"] == cwd and meta["provider"] == to_string(config.provider) and
             meta["model"] == config.model do
      {:ok, id, events}
    else
      false -> {:error, :resume_configuration_mismatch}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_session}
    end
  end

  defp restore(events) do
    messages = for %{"type" => "message", "message" => message} <- events, do: message
    restore_messages(messages)
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
            "Outcome unknown: session interrupted before a result was recorded. Inspect the workspace before retrying."
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

  defp definitions do
    Tools.definitions() ++
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
