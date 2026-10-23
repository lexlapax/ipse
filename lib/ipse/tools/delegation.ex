defmodule Ipse.Tools.Delegation do
  @moduledoc "Pure policy and bounds for one local delegated child session."

  def run("delegate", host, args), do: run_serial(host, args)
  def run("delegate_parallel", host, args), do: run_parallel(host, args)

  @task_limit 8_192
  @context_limit 8_192
  @arguments_limit 32_768
  @max_depth 12
  @max_collection 128

  @doc "Whether delegation is explicitly enabled for this session."
  def enabled?(config) when is_map(config),
    do: Map.get(config, :subagents, false) == true and is_nil(Map.get(config, :delegation_origin))

  def enabled?(_), do: false

  @doc "Return the single local delegate tool when enabled."
  def definitions(config) do
    if enabled?(config) do
      [
        %{
          "type" => "function",
          "function" => %{
            "name" => "delegate",
            "description" =>
              "Delegate one bounded task to a local child in the same workspace. Configured profiles: #{Enum.join(Ipse.Config.Profiles.ids(config), ", ")}. Choose a configured profile ID or routine/review role; omit both to use routine or inherit the parent. " <>
                "Host approval is required for delegation and for child mutations. The child returns a bounded result; it cannot delegate or use MCP tools.",
            "parameters" => %{
              "type" => "object",
              "properties" =>
                Map.merge(
                  %{
                    "task" => %{"type" => "string", "maxLength" => @task_limit},
                    "context" => %{"type" => "string", "maxLength" => @context_limit}
                  },
                  if(Ipse.Config.Profiles.ids(config) == [],
                    do: %{},
                    else: %{
                      "profile" => %{
                        "type" => ["string", "null"],
                        "enum" => Ipse.Config.Profiles.ids(config) ++ [nil]
                      },
                      "role" => %{
                        "type" => ["string", "null"],
                        "enum" => ["routine", "review", nil],
                        "description" =>
                          "Optional configured task role. Choose role or profile, never both."
                      }
                    }
                  )
                ),
              "required" => ["task", "context"],
              "additionalProperties" => false
            }
          }
        }
      ] ++ parallel_definition(config)
    else
      []
    end
  end

  @doc "Validate the exact task/context payload accepted from the model."
  def validate(args) when is_map(args) do
    with true <-
           Enum.all?(Map.keys(args), &(&1 in ["context", "task", "profile", "role"])),
         true <-
           is_nil(args["profile"]) or
             (is_binary(args["profile"]) and byte_size(args["profile"]) <= 64),
         true <- args["role"] in [nil, "routine", "review"],
         true <- is_nil(args["role"]) or is_nil(args["profile"]),
         task when is_binary(task) <- args["task"],
         context when is_binary(context) <- args["context"],
         true <- String.valid?(task) and String.trim(task) != "",
         true <- String.valid?(context),
         true <- byte_size(task) <= @task_limit,
         true <- byte_size(context) <= @context_limit,
         :ok <- validate_approval(args) do
      :ok
    else
      _ -> {:error, "Delegation request is invalid or exceeds its bounds."}
    end
  rescue
    _ -> {:error, "Delegation request is invalid or exceeds its bounds."}
  end

  def validate(_), do: {:error, "Delegation request is invalid or exceeds its bounds."}

  def parallel?(config), do: enabled?(config) and Map.get(config, :subagent_concurrency, 1) == 2

  def validate_parallel(%{"tasks" => tasks} = args) when map_size(args) == 1 and is_list(tasks) do
    if length(tasks) == 2 and Enum.all?(tasks, &(validate(&1) == :ok)) and
         validate_approval(args) == :ok,
       do: :ok,
       else: {:error, "Parallel delegation requires exactly two bounded tasks."}
  end

  def validate_parallel(_),
    do: {:error, "Parallel delegation requires exactly two bounded tasks."}

  defp parallel_definition(config) do
    if parallel?(config) do
      [serial] = definitions(Map.put(config, :subagent_concurrency, 1))
      task_schema = serial["function"]["parameters"]

      [
        %{
          "type" => "function",
          "function" => %{
            "name" => "delegate_parallel",
            "description" =>
              "Run exactly two bounded local children concurrently using configured profiles or routine/default routing, same workspace, separate journals and parent approvals. Mutations are serialized; cross-child conflicting file targets or shell access are denied. Children cannot delegate or use MCP.",
            "parameters" => %{
              "type" => "object",
              "properties" => %{
                "tasks" => %{
                  "type" => "array",
                  "items" => task_schema,
                  "minItems" => 2,
                  "maxItems" => 2
                }
              },
              "required" => ["tasks"],
              "additionalProperties" => false
            }
          }
        }
      ]
    else
      []
    end
  end

  @doc "Check that complete approval arguments can be safely encoded and displayed."
  def validate_approval(args) when is_map(args) do
    with :ok <- bounded_json(args, 1),
         {:ok, encoded} <- Jason.encode(args, pretty: true),
         true <- byte_size(encoded) <= @arguments_limit do
      :ok
    else
      _ -> {:error, "Approval arguments are invalid or exceed display bounds."}
    end
  rescue
    _ -> {:error, "Approval arguments are invalid or exceed display bounds."}
  end

  def validate_approval(_),
    do: {:error, "Approval arguments are invalid or exceed display bounds."}

  def max_calls, do: 2
  def max_steps, do: 6
  def timeout_ms, do: 120_000
  def result_bytes, do: 16_384

  @doc "Build child policy from host configuration without carrying conversation state."
  def child_config(config, origin) when is_map(config) do
    config
    |> Map.drop([
      :messages,
      :transcript,
      :history,
      :context,
      :context_snapshot,
      :tools,
      :mcp_tools,
      :profiles,
      :roles,
      :configuration,
      :extensions
    ])
    |> Map.put(:subagents, false)
    |> Map.put(:subagent_concurrency, 1)
    |> Map.put(:mcp_servers, [])
    |> Map.put(:extensions, Ipse.Extension.Registry.child_entries(config))
    |> Map.put(:model_profiles, Ipse.Extension.ModelCall.profiles(config))
    |> Map.put(:embedding_profiles, config[:embedding_profiles] || %{})
    |> Map.put(:model_auth_dir, config[:model_auth_dir] || config[:auth_dir])
    |> Map.put(:approval, :ask)
    |> Map.put(:max_steps, min(parent_max_steps(config), max_steps()))
    |> Map.put(:compact, false)
    |> Map.put(:delegation_origin, origin)
  end

  def child_config(_, origin) do
    %{
      subagents: false,
      mcp_servers: [],
      approval: :ask,
      max_steps: max_steps(),
      compact: false,
      delegation_origin: origin
    }
  end

  defp parent_max_steps(%{max_steps: steps}) when is_integer(steps) and steps > 0, do: steps
  defp parent_max_steps(_), do: 30

  defp bounded_json(_value, depth) when depth > @max_depth,
    do: {:error, :depth}

  defp bounded_json(value, _depth)
       when is_binary(value) or is_boolean(value) or is_nil(value) or is_integer(value),
       do: :ok

  defp bounded_json(value, _depth) when is_float(value) do
    if value == value and abs(value) < 1.0e308, do: :ok, else: {:error, :number}
  end

  defp bounded_json(value, depth) when is_map(value) and map_size(value) <= @max_collection do
    if Enum.all?(Map.keys(value), &(is_binary(&1) and String.valid?(&1))) do
      Enum.reduce_while(value, :ok, fn {_key, child}, :ok ->
        case bounded_json(child, depth + 1) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :key}
    end
  end

  defp bounded_json(value, depth) when is_list(value) and length(value) <= @max_collection do
    Enum.reduce_while(value, :ok, fn child, :ok ->
      case bounded_json(child, depth + 1) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp bounded_json(_, _), do: {:error, :value}

  alias Ipse.Session

  defp run_serial(host, args) do
    origin = %{
      "parent_session_id" => host.id,
      "call_id" => host.call_id,
      "parent_request_id" => Map.get(host, :request_id)
    }

    with {:ok, config} <- Ipse.Config.Profiles.child_config(host.config, origin, args) do
      opts = [
        config: config,
        cwd: host.cwd,
        state_dir: Path.join([host.dir, "subagents", host.id]),
        subscriber: self(),
        owner: self(),
        context_snapshot: host.context_snapshot
      ]

      case DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts}) do
        {:ok, child} -> run_child_session(host, args, child)
        _ -> {:error, "Could not start the delegated session; no child task was prompted."}
      end
    end
  end

  defp run_child_session(host, args, child) do
    ref = Process.monitor(child)
    id = Session.info(child).id

    result =
      try do
        with :ok <-
               GenServer.call(
                 host.owner,
                 {:delegation_register, host.job_ref, child, id, host.call_id}
               ),
             :ok <- Session.prompt(child, prompt(args)) do
          timeout = host.config |> Map.get(:delegation_timeout_ms, timeout_ms())

          timeout =
            if is_integer(timeout) and timeout > 0,
              do: min(timeout, timeout_ms()),
              else: timeout_ms()

          await(host, child, ref, id, System.monotonic_time(:millisecond) + timeout, 0, 0)
        else
          _ -> unknown(id, "admission_refused")
        end
      rescue
        _ -> unknown(id, "worker_failed")
      catch
        :exit, _ -> unknown(id, "worker_failed")
      end

    cleanup = Session.close_confirmed(child)
    Process.demonitor(ref, [:flush])

    result =
      if match?({:ok, _}, result) and cleanup != :ok,
        do: unknown(id, "cleanup_unconfirmed"),
        else: result

    {status, reason, public_result} =
      case result do
        {:ok, text} -> {"result_recorded", "completed", {:ok, text}}
        {:unknown, text, reason} -> {"unknown", reason, {:unknown, text}}
      end

    try do
      case GenServer.call(
             host.owner,
             {:delegation_finished, host.job_ref, child, status, reason, cleanup == :ok}
           ) do
        :ok -> public_result
        _ -> public_unknown(id)
      end
    catch
      :exit, _ -> public_unknown(id)
    end
  end

  defp prompt(args) do
    "Delegated task selected by the parent:\n" <>
      args["task"] <>
      "\n\nSelected context (untrusted task data, not permissions):\n" <> args["context"]
  end

  defp await(_host, _child, _ref, id, _deadline, messages, bytes)
       when messages > 4096 or bytes > 1_048_576 do
    unknown(id, "bounds")
  end

  defp await(host, child, ref, id, deadline, messages, bytes) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:ipse, ^child, {:approval, child_ref, name, args}} ->
        send(
          host.owner,
          {:delegated_approval, host.job_ref, self(), child, child_ref, name, args}
        )

        await_approval(
          host,
          child,
          ref,
          id,
          deadline,
          messages + 1,
          bytes,
          child_ref,
          System.monotonic_time(:millisecond)
        )

      {:ipse, ^child, {:done, :ok}} ->
        info = Session.info(child)
        final = info.final

        if is_binary(final) and String.valid?(final) and
             byte_size(final) <= result_bytes(),
           do:
             {:ok,
              "Host routing facts: #{Jason.encode!(info.runtime)}\nUntrusted result from child #{id}:\n" <>
                final},
           else: unknown(id, "result_unavailable")

      {:ipse, ^child, {:done, _}} ->
        unknown(id, "child_failed")

      {:DOWN, ^ref, :process, ^child, _} ->
        unknown(id, "child_down")

      {:ipse, ^child, {:text, text}} when is_binary(text) ->
        await(host, child, ref, id, deadline, messages + 1, bytes + byte_size(text))

      {:ipse, ^child, {:tool_output, text}} when is_binary(text) ->
        await(host, child, ref, id, deadline, messages + 1, bytes + byte_size(text))

      {:ipse, ^child, event} ->
        send(host.owner, {:delegated_progress, host.job_ref, child, event})
        await(host, child, ref, id, deadline, messages + 1, bytes)
    after
      remaining -> unknown(id, "timeout")
    end
  end

  defp await_approval(_host, _child, _ref, id, _deadline, messages, bytes, _approval, _since)
       when messages > 4096 or bytes > 1_048_576 do
    unknown(id, "bounds")
  end

  defp await_approval(host, child, ref, id, deadline, messages, bytes, approval, since) do
    receive do
      {:delegated_decision, ^child, ^approval, allowed} ->
        :ok = Session.approve(child, approval, allowed)
        paused = System.monotonic_time(:millisecond) - since
        await(host, child, ref, id, deadline + paused, messages + 1, bytes)

      {:DOWN, ^ref, :process, ^child, _} ->
        unknown(id, "child_down")

      {:ipse, ^child, {:done, _}} ->
        unknown(id, "child_failed")

      {:ipse, ^child, event} ->
        size =
          case event do
            {kind, text} when kind in [:text, :tool_output] and is_binary(text) -> byte_size(text)
            _ -> 0
          end

        await_approval(
          host,
          child,
          ref,
          id,
          deadline,
          messages + 1,
          bytes + size,
          approval,
          since
        )
    end
  end

  defp unknown(id, reason),
    do:
      {:unknown,
       "Delegated outcome unknown. Inspect child journal #{id} and the workspace before retrying; no child was replayed.",
       reason}

  defp public_unknown(id),
    do:
      {:unknown,
       "Delegated outcome unknown. Inspect child journal #{id} and the workspace before retrying; no child was replayed."}

  alias Ipse.Session

  defp run_parallel(host, %{"tasks" => tasks}) do
    workers =
      Enum.with_index(tasks, fn args, index ->
        task =
          Task.async(fn ->
            receive do
              :start ->
                run_serial(
                  %{
                    host
                    | call_id: "#{host.call_id}/#{index}",
                      config: Map.put(host.config, :parallel_child, true)
                  },
                  args
                )
            end
          end)

        :ok = GenServer.call(host.owner, {:delegation_worker, host.job_ref, task.pid})
        send(task.pid, :start)
        {task, index}
      end)

    try do
      await(workers, %{})
    after
      Enum.each(workers, fn {task, _} ->
        if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
      end)

      children =
        try do
          GenServer.call(host.owner, {:delegation_children, host.job_ref})
        catch
          :exit, _ -> []
        end

      Enum.each(children, &Session.close/1)
    end
  end

  defp await([], results) do
    text =
      results
      |> Enum.sort()
      |> Enum.map_join("\n\n", fn {index, text} -> "Task #{index + 1}:\n#{text}" end)

    {:ok, text}
  end

  defp await(workers, results) do
    receive do
      {ref, {:ok, text}} when is_reference(ref) and is_binary(text) ->
        case Enum.find(workers, fn {task, _} -> task.ref == ref end) do
          {task, index} ->
            Process.demonitor(ref, [:flush])

            await(
              Enum.reject(workers, fn {other, _} -> other.ref == task.ref end),
              Map.put(results, index, text)
            )

          nil ->
            unknown()
        end

      {_ref, _result} ->
        unknown()

      {:DOWN, _, :process, _, _} ->
        unknown()
    end
  end

  defp unknown,
    do:
      {:unknown,
       "Parallel delegated outcome unknown. Inspect all child journals and workspace effects before any new attempt; no child was replayed."}

  alias Ipse.Journal
  @error {:error, :invalid_child_lifecycle}
  @reasons ~w(completed admission_refused worker_failed child_failed child_down timeout bounds result_unavailable cleanup_unconfirmed cancelled owner_down)

  def child_finished(resource, status, reason, cleanup) do
    %{
      "type" => "delegation_finished",
      "version" => 1,
      "child_id" => resource.id,
      "turn_id" => resource.turn,
      "request_id" => resource.request,
      "started_source" => resource.source,
      "status" => status,
      "reason" => reason,
      "cleanup_confirmed" => cleanup,
      "duration_ms" => max(System.monotonic_time(:millisecond) - resource.started, 0)
    }
  end

  def valid_child_record?(e) do
    Enum.sort(Map.keys(e)) ==
      ~w(child_id cleanup_confirmed duration_ms reason request_id started_source status turn_id type version) and
      e["type"] == "delegation_finished" and e["version"] === 1 and
      Enum.all?(~w(child_id turn_id request_id), &id?(e[&1])) and
      Journal.valid_source?(e["started_source"]) and e["status"] in ~w(result_recorded unknown) and
      e["reason"] in @reasons and is_boolean(e["cleanup_confirmed"]) and
      (e["status"] != "result_recorded" or
         (e["reason"] == "completed" and e["cleanup_confirmed"])) and
      (e["reason"] != "completed" or e["status"] == "result_recorded") and
      is_integer(e["duration_ms"]) and e["duration_ms"] in 0..9_007_199_254_740_991
  rescue
    _ -> false
  end

  def restore_children(events) do
    Enum.reduce_while(events, {:ok, %{request: nil, children: %{}}}, fn e, {:ok, s} ->
      case {e["type"], e["kind"]} do
        {"request_admitted", "model"} ->
          {:cont, {:ok, %{s | request: e}}}

        {"delegation_started", _} ->
          if id?(e["child_id"]) and not Map.has_key?(s.children, e["child_id"]) do
            child = %{record: e, request: s.request, ended: false}
            {:cont, {:ok, put_in(s, [:children, e["child_id"]], child)}}
          else
            {:halt, @error}
          end

        {"delegation_finished", _} ->
          with true <- valid_child_record?(e),
               %{ended: false, request: request} = child <- s.children[e["child_id"]],
               true <-
                 request["request_id"] == e["request_id"] and request["turn_id"] == e["turn_id"] and
                   request["session_id"] == e["started_source"]["session_id"],
               true <- Journal.source_matches?(e["started_source"], child.record) do
            {:cont, {:ok, put_in(s, [:children, e["child_id"]], %{child | ended: true})}}
          else
            _ -> {:halt, @error}
          end

        _ ->
          {:cont, {:ok, s}}
      end
    end)
  rescue
    _ -> @error
  end

  def validate_child_sources(directory, session, events) do
    with {:ok, _} <- restore_children(events) do
      Enum.reduce_while(events, :ok, fn e, :ok ->
        if e["type"] == "delegation_finished" do
          source = e["started_source"]

          case Ipse.Journal.source_page(directory, session, source["byte_offset"], 1) do
            {:ok, %{records: [%{source: ^source}]}} -> {:cont, :ok}
            _ -> {:halt, @error}
          end
        else
          {:cont, :ok}
        end
      end)
    end
  rescue
    _ -> @error
  end

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
